#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# Scientific settings (stage, task, model, and debug) are intentionally read
# from src/config.py.  Environment variables below control numeric/runtime
# settings and output placement only.
SEED="${FVRULELEARNER_SEED:-100}"
NUM_ITER="${FVRULELEARNER_NUM_ITER:-25}"
MAX_TOKENS="${FVRULELEARNER_MAX_TOKENS:-16384}"
JG_TIMEOUT="${FVRULELEARNER_JG_TIMEOUT_SECONDS:-60}"
NPARALLEL="${FVRULELEARNER_NPARALLEL:-1}"
PILOT_CASES="${FVRULELEARNER_PILOT_CASES:-5}"
RUN_ROOT="${FVRULELEARNER_RUN_ROOT:-${REPO_ROOT}/src/logs/gpt4o_reproduction}"

usage() {
    sed -n '/^# Usage:/,/^# End usage/p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# Usage:
#   Edit src/config.py before each phase.  This runner requires:
#
#   smoke: global_task='train', debug=True,  task=<dataset>, llm_model=<GPT-4o>
#   pilot: global_task='train', debug=False, task=<dataset>, llm_model=<GPT-4o>
#   train: global_task='train', debug=False, task=<dataset>, llm_model=<GPT-4o>
#   infer: global_task='inference', debug=False, task=<dataset>, llm_model=<GPT-4o>
#
#   export OPENAI_API_KEY='your-key'
#   export PATH='/path/to/jasper/bin':"$PATH"
#   export LM_LICENSE_FILE='your-license-setting'
#   export CDS_LIC_FILE='your-license-setting'
#   export FVRULELEARNER_RUN_ROOT='/absolute/path/to/result/root'
#
#   bash scripts/run_gpt4o_reproduction.sh preflight
#   bash scripts/run_gpt4o_reproduction.sh smoke
#   bash scripts/run_gpt4o_reproduction.sh pilot
#   bash scripts/run_gpt4o_reproduction.sh train
#   bash scripts/run_gpt4o_reproduction.sh infer /absolute/path/to/train
#   bash scripts/run_gpt4o_reproduction.sh analyze-train /absolute/path/to/train
#   bash scripts/run_gpt4o_reproduction.sh analyze-infer /absolute/path/to/inference
#
# Optional runtime/path overrides:
#   FVRULELEARNER_SEED, FVRULELEARNER_NUM_ITER,
#   FVRULELEARNER_MAX_TOKENS, FVRULELEARNER_JG_TIMEOUT_SECONDS,
#   FVRULELEARNER_NPARALLEL, FVRULELEARNER_PILOT_CASES,
#   FVRULELEARNER_RUN_ROOT, FVRULELEARNER_SKIP_API_PROBE=1.
#
# FVRULELEARNER_MODEL, FVRULELEARNER_TASK, FVRULELEARNER_STAGE, and
# FVRULELEARNER_DEBUG do not select scientific settings in this runner.
# Edit src/config.py instead.  The runner validates and records the effective
# FLAGS imported from that file.
# End usage

require_nonempty_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "ERROR: ${name} is not set." >&2
        return 1
    fi
}

new_run_dir() {
    local label="$1"
    local stamp
    stamp="$(date -u +%Y%m%dT%H%M%SZ)_$$"
    printf '%s/%s_%s' "${RUN_ROOT}" "${label}" "${stamp}"
}

validate_effective_config() {
    local expected_stage="${1:-}"
    local expected_debug="${2:-any}"

    python3 - "${expected_stage}" "${expected_debug}" <<'PY'
import sys
from pathlib import Path

repo_root = Path.cwd()
sys.path.insert(0, str(repo_root / "src"))

from config import FLAGS

expected_stage = sys.argv[1].strip()
expected_debug_text = sys.argv[2].strip().lower()

stage = str(FLAGS.global_task).strip().lower()
task = str(FLAGS.task).strip().lower()
model = str(FLAGS.llm_model).strip()
debug = bool(FLAGS.debug)
dataset_path = Path(FLAGS.dataset_path).resolve()

errors = []

if stage not in {"train", "inference", "eval"}:
    errors.append(f"unsupported config stage: {stage!r}")

if task not in {"nl2sva_machine", "nl2sva_human", "nl2sva_opencore"}:
    errors.append(f"unsupported config task: {task!r}")

model_lower = model.lower()
if not (model_lower == "gpt-4o" or model_lower.startswith("gpt-4o-")):
    errors.append(
        "GPT-4o runner requires config llm_model='gpt-4o' or "
        f"'gpt-4o-...'; got {model!r}"
    )

if expected_stage and stage != expected_stage:
    errors.append(
        f"runner action requires global_task={expected_stage!r}, "
        f"but config has {stage!r}"
    )

if expected_debug_text != "any":
    wanted_debug = expected_debug_text in {"1", "true", "yes", "on"}
    if debug != wanted_debug:
        errors.append(
            f"runner action requires debug={wanted_debug}, "
            f"but config has {debug}"
        )

if not dataset_path.is_file():
    errors.append(f"dataset does not exist: {dataset_path}")

print("Effective configuration from src/config.py")
print(f"  global_task       : {stage}")
print(f"  task              : {task}")
print(f"  llm_model         : {model}")
print(f"  debug             : {debug}")
print(f"  dataset_path      : {dataset_path}")
print(f"  random_seed       : {getattr(FLAGS, 'random_seed', None)}")
print(f"  num_iter          : {getattr(FLAGS, 'num_iter', None)}")
print(f"  max_token         : {getattr(FLAGS, 'max_token', None)}")
print(f"  num_group         : {getattr(FLAGS, 'num_group', None)}")
print(f"  group_id          : {getattr(FLAGS, 'group_id', None)}")
print(f"  random_sample_size: {getattr(FLAGS, 'random_sample_size', None)}")

if errors:
    print("\nCONFIGURATION ERRORS:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(2)

print("Effective configuration validation: PASSED")
PY
}

pilot_group_plan() {
    python3 - "${PILOT_CASES}" <<'PY'
import csv
import math
import sys
from pathlib import Path

repo_root = Path.cwd()
sys.path.insert(0, str(repo_root / "src"))

from config import FLAGS

target_cases = int(sys.argv[1])
if target_cases <= 0:
    raise SystemExit("FVRULELEARNER_PILOT_CASES must be positive")

dataset_path = Path(FLAGS.dataset_path)
with dataset_path.open(newline="", encoding="utf-8") as dataset_file:
    total_samples = sum(1 for _ in csv.DictReader(dataset_file))

test_size = int(total_samples * FLAGS.split_ratios["test"])
nominal_train_size = int(total_samples * FLAGS.split_ratios["train"])

# Match benchmark_launcher.py exactly, including its +1 upper bound and
# Python's end-of-list clipping.
train_indices = list(range(total_samples))[
    test_size : test_size + nominal_train_size + 1
]
train_cases = len(train_indices)

num_groups = max(1, math.ceil(train_cases / target_cases))
group_size = train_cases // num_groups
remainder = train_cases % num_groups
selected_cases = group_size + (1 if remainder > 0 else 0)

print(num_groups, train_cases, selected_cases)
PY
}

write_manifest() {
    local run_dir="$1"
    local expected_phase="$2"

    mkdir -p "${run_dir}"
    git diff --binary > "${run_dir}/source.patch"
    cp scripts/prepare_gpt4o_reproduction.py "${run_dir}/"
    cp scripts/analyze_gpt4o_results.py "${run_dir}/"
    cp "${BASH_SOURCE[0]}" "${run_dir}/"

    python3 - "${run_dir}" "${expected_phase}" <<'PY'
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

run_dir = Path(sys.argv[1]).resolve()
expected_phase = sys.argv[2].strip().lower()
repo_root = Path.cwd()
sys.path.insert(0, str(repo_root / "src"))

from config import FLAGS


def git(*args):
    return subprocess.run(
        ["git", *args], check=True, text=True, capture_output=True
    ).stdout.strip()


def optional_flag(name, default=None):
    return getattr(FLAGS, name, default)


def json_safe(value):
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [json_safe(item) for item in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return repr(value)


phase = str(FLAGS.global_task).strip().lower()
task = str(FLAGS.task).strip().lower()
model = str(FLAGS.llm_model).strip()
debug = bool(FLAGS.debug)
dataset_path = Path(FLAGS.dataset_path).resolve()
config_path = repo_root / "src" / "config.py"

if phase != expected_phase:
    raise SystemExit(
        f"ERROR: runner phase is {expected_phase!r}, but effective "
        f"config global_task is {phase!r}"
    )

model_lower = model.lower()
if not (model_lower == "gpt-4o" or model_lower.startswith("gpt-4o-")):
    raise SystemExit(
        f"ERROR: GPT-4o runner cannot use effective model {model!r}"
    )

effective_config = {
    "global_task": phase,
    "task": task,
    "llm_model": model,
    "debug": debug,
    "dataset_path": str(dataset_path),
    "dataset_sha256": hashlib.sha256(dataset_path.read_bytes()).hexdigest(),
    "random_seed": optional_flag("random_seed"),
    "num_iter": optional_flag("num_iter"),
    "requested_max_tokens": optional_flag("requested_max_tokens"),
    "max_token": optional_flag("max_token"),
    "nparallel": optional_flag("nparallel"),
    "jg_timeout_seconds": optional_flag("jg_timeout_seconds"),
    "num_group": optional_flag("num_group"),
    "group_id": optional_flag("group_id"),
    "start_num": optional_flag("start_num"),
    "random_sample_size": optional_flag("random_sample_size"),
    "split_ratios": optional_flag("split_ratios"),
    "use_RAG": optional_flag("use_RAG"),
    "use_JG": optional_flag("use_JG"),
    "RAG_content": optional_flag("RAG_content"),
    "Suggestions_top_k": optional_flag("Suggestions_top_k"),
    "filter_functionality": optional_flag("filter_functionality"),
    "load_suggestions_path": optional_flag("load_suggestions_path"),
    "retrieval_on_ranking": optional_flag("retrieval_on_ranking"),
    "qtree_similarity_top_k": optional_flag("qtree_similarity_top_k"),
    "qtree_ranking_mode": optional_flag("qtree_ranking_mode"),
    "rule_source": optional_flag("rule_source"),
    "deduplication": optional_flag("deduplication"),
    "operator_explanation": optional_flag("operator_explanation"),
}

manifest = {
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "output_directory": str(run_dir),
    "phase": phase,
    "task": task,
    "model": model,
    "debug": debug,
    "dataset_path": str(dataset_path),
    "dataset_sha256": effective_config["dataset_sha256"],
    "seed": effective_config["random_seed"],
    "num_iter": effective_config["num_iter"],
    "max_tokens": effective_config["max_token"],
    "jg_timeout_seconds": effective_config["jg_timeout_seconds"],
    "nparallel": effective_config["nparallel"],
    "git_commit": git("rev-parse", "HEAD"),
    "git_status": git("status", "--short").splitlines(),
    "config_sha256": hashlib.sha256(config_path.read_bytes()).hexdigest(),
    "source_patch": str(run_dir / "source.patch"),
    "effective_config": json_safe(effective_config),
    "reproduction_profile": "nvidia_logic_jasper25_openai_compatible",
    "logic_reference": {
        "repository": "NVlabs/FVRuleLearner",
        "commit": "0da2228dc573ff832f4d9b777d5efaf7e7171d23",
    },
    "compatibility_scope": [
        "TCL documentation-comment sanitization for JasperGold 25.x",
        "current OpenAI model/API parameter compatibility",
        "infrastructure failure detection",
        "structured manifests and training traces",
    ],
}

(run_dir / "run_manifest.json").write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY
}

export FVRULELEARNER_SEED="${SEED}"
export FVRULELEARNER_NUM_ITER="${NUM_ITER}"
export FVRULELEARNER_MAX_TOKENS="${MAX_TOKENS}"
export FVRULELEARNER_JG_TIMEOUT_SECONDS="${JG_TIMEOUT}"
export FVRULELEARNER_NPARALLEL="${NPARALLEL}"

preflight() {
    local expected_stage="${1:-}"
    local expected_debug="${2:-any}"

    validate_effective_config "${expected_stage}" "${expected_debug}"
    require_nonempty_env OPENAI_API_KEY
    command -v python3 >/dev/null || { echo "ERROR: python3 not found." >&2; return 1; }
    command -v jg >/dev/null || { echo "ERROR: JasperGold executable 'jg' is not on PATH." >&2; return 1; }

    python3 scripts/prepare_gpt4o_reproduction.py --check-only
    python3 -m pip check
    python3 - <<'PY'
import importlib

required = [
    "anthropic", "evaluate", "git", "klepto", "langchain", "openai",
    "pandas", "rouge_score", "sentence_transformers", "sklearn", "torch",
    "transformers",
]
for name in required:
    importlib.import_module(name)
print("Required Python imports: OK")
PY

    if [[ "${FVRULELEARNER_SKIP_API_PROBE:-0}" != "1" ]]; then
        python3 - <<'PY'
import os
import sys
from pathlib import Path

from openai import OpenAI

repo_root = Path.cwd()
sys.path.insert(0, str(repo_root / "src"))
from config import FLAGS

model = str(FLAGS.llm_model)
OpenAI(api_key=os.environ["OPENAI_API_KEY"], timeout=60).models.retrieve(model)
print(f"OpenAI API access: OK ({model})")
PY
    else
        echo "OpenAI API access probe: skipped"
    fi

    echo "JasperGold executable: $(command -v jg)"
    echo "Preflight complete. No API key value was printed or saved."
}

run_main() {
    local stage="$1"
    local run_dir="$2"
    local expected_debug="$3"
    local num_groups="$4"
    local group_id="$5"
    local iterations="$6"
    local train_dir="${7:-}"

    export FVRULELEARNER_NUM_GROUPS="${num_groups}"
    export FVRULELEARNER_GROUP_ID="${group_id}"
    export FVRULELEARNER_START_NUM=0
    export FVRULELEARNER_NUM_ITER="${iterations}"

    if [[ -n "${train_dir}" ]]; then
        export FVRULELEARNER_TRAIN_LOGDIR="${train_dir}"
    else
        unset FVRULELEARNER_TRAIN_LOGDIR || true
    fi

    validate_effective_config "${stage}" "${expected_debug}"
    write_manifest "${run_dir}" "${stage}"

    echo "Output directory: ${run_dir}"
    set -o pipefail
    python3 -u src/main.py --logdir "${run_dir}" 2>&1 | tee "${run_dir}/console.log"

    # src/main.py stores top-level exceptions in exception.txt but may still
    # exit successfully, so validate required artifacts explicitly.
    if [[ -s "${run_dir}/exception.txt" ]]; then
        echo "ERROR: ${stage} failed; see ${run_dir}/exception.txt" >&2
        return 1
    fi
    if [[ "${stage}" == "train" && ! -s "${run_dir}/training_traces.jsonl" ]]; then
        echo "ERROR: training finished without training_traces.jsonl." >&2
        return 1
    fi
    if [[ "${stage}" == "inference" ]] && \
       ! compgen -G "${run_dir}/eval/*_jg.csv" >/dev/null; then
        echo "ERROR: inference finished without JasperGold evaluation CSV files." >&2
        return 1
    fi
}

analyze_train() {
    local train_dir="$1"
    python3 scripts/analyze_gpt4o_results.py --train-dir "${train_dir}"
}

analyze_infer() {
    local inference_dir="$1"
    python3 scripts/analyze_gpt4o_results.py --inference-dir "${inference_dir}"
}

phase="${1:-help}"
case "${phase}" in
    help|-h|--help)
        usage 0
        ;;
    preflight)
        preflight
        ;;
    smoke)
        preflight train true
        run_dir="$(new_run_dir smoke_train)"
        run_main train "${run_dir}" true 1 0 2
        analyze_train "${run_dir}"
        echo "SMOKE_DIR=${run_dir}"
        ;;
    pilot)
        preflight train false
        read -r pilot_num_groups train_case_count selected_case_count \
            < <(pilot_group_plan)
        echo "Pilot plan: dataset training cases=${train_case_count}, target=${PILOT_CASES}, selected=${selected_case_count}, num_groups=${pilot_num_groups}, group_id=0"
        run_dir="$(new_run_dir pilot_train)"
        run_main train "${run_dir}" false "${pilot_num_groups}" 0 "${NUM_ITER}"
        analyze_train "${run_dir}"
        echo "PILOT_DIR=${run_dir}"
        ;;
    train)
        preflight train false
        run_dir="$(new_run_dir full_train)"
        run_main train "${run_dir}" false 1 0 "${NUM_ITER}"
        analyze_train "${run_dir}"
        echo "TRAIN_DIR=${run_dir}"
        ;;
    infer)
        train_dir="${2:-}"
        [[ -n "${train_dir}" ]] || { echo "ERROR: infer requires a training directory." >&2; usage 2; }
        [[ -d "${train_dir}" ]] || { echo "ERROR: not a directory: ${train_dir}" >&2; exit 2; }
        preflight inference false
        run_dir="$(new_run_dir full_inference)"
        run_main inference "${run_dir}" false 1 0 "${NUM_ITER}" "$(cd -- "${train_dir}" && pwd)"
        analyze_infer "${run_dir}"
        echo "INFERENCE_DIR=${run_dir}"
        ;;
    analyze-train)
        [[ -n "${2:-}" ]] || { echo "ERROR: analyze-train requires a directory." >&2; usage 2; }
        analyze_train "$2"
        ;;
    analyze-infer)
        [[ -n "${2:-}" ]] || { echo "ERROR: analyze-infer requires a directory." >&2; usage 2; }
        analyze_infer "$2"
        ;;
    full)
        echo "ERROR: full is intentionally disabled for config-controlled stages." >&2
        echo "Run train, edit config.py to global_task='inference', then run infer TRAIN_DIR." >&2
        exit 2
        ;;
    *)
        echo "ERROR: unknown phase: ${phase}" >&2
        usage 2
        ;;
esac
