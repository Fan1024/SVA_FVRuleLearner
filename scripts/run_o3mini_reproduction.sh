#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

MODEL="${FVRULELEARNER_MODEL:-o3-mini}"
TASK="${FVRULELEARNER_TASK:-nl2sva_machine}"
SEED="${FVRULELEARNER_SEED:-100}"
NUM_ITER="${FVRULELEARNER_NUM_ITER:-25}"
MAX_TOKENS="${FVRULELEARNER_MAX_TOKENS:-20000}"
REASONING_EFFORT="${FVRULELEARNER_REASONING_EFFORT:-}"
JG_TIMEOUT="${FVRULELEARNER_JG_TIMEOUT_SECONDS:-300}"
NPARALLEL="${FVRULELEARNER_NPARALLEL:-1}"
RUN_ROOT="${FVRULELEARNER_RUN_ROOT:-${REPO_ROOT}/src/logs/o3mini_reproduction}"

usage() {
    sed -n '/^# Usage:/,/^#   FVRULELEARNER_RUN_ROOT/p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# Usage:
#   export OPENAI_API_KEY='your-key'
#   export PATH='/path/to/jasper/bin':"$PATH"
#   export LM_LICENSE_FILE='your-license-setting'
#   export CDS_LIC_FILE='your-license-setting'
#
#   bash scripts/run_o3mini_reproduction.sh preflight
#   bash scripts/run_o3mini_reproduction.sh smoke
#   bash scripts/run_o3mini_reproduction.sh pilot
#   bash scripts/run_o3mini_reproduction.sh train
#   bash scripts/run_o3mini_reproduction.sh infer /absolute/path/to/train
#   bash scripts/run_o3mini_reproduction.sh analyze-train /absolute/path/to/train
#   bash scripts/run_o3mini_reproduction.sh analyze-infer /absolute/path/to/inference
#   bash scripts/run_o3mini_reproduction.sh full --yes
#
# Phases:
#   preflight      Check source patches, Python packages, API access, and JasperGold setup.
#   smoke          Run one training case with at most two fixing iterations.
#   pilot          Run about five machine-training cases with the full 25-iteration budget.
#   train          Run the full 80% training split (240 cases for nl2sva_machine).
#   infer DIR      Run the full 20% test split using the rules learned in DIR.
#   analyze-train  Generate training_summary.json and training_fixing_curve.csv.
#   analyze-infer  Generate eval/reproduction_summary.json and strict failure CSV.
#   full --yes     Run preflight, full training, training analysis, inference, and final analysis.
#
# Optional overrides:
#   FVRULELEARNER_TASK, FVRULELEARNER_MODEL, FVRULELEARNER_SEED,
#   FVRULELEARNER_NUM_ITER, FVRULELEARNER_MAX_TOKENS,
#   FVRULELEARNER_REASONING_EFFORT (empty|low|medium|high),
#   FVRULELEARNER_JG_TIMEOUT_SECONDS, FVRULELEARNER_NPARALLEL,
#   FVRULELEARNER_RUN_ROOT, FVRULELEARNER_SKIP_API_PROBE=1.

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

write_manifest() {
    local run_dir="$1"
    local phase="$2"
    mkdir -p "${run_dir}"
    git diff --binary > "${run_dir}/source.patch"
    cp scripts/prepare_gpt4o_reproduction.py "${run_dir}/"
    cp scripts/analyze_gpt4o_results.py "${run_dir}/"
    cp scripts/run_o3mini_reproduction.sh "${run_dir}/"
    python3 - "${run_dir}" "${phase}" <<'PY'
import json
import hashlib
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

run_dir = Path(sys.argv[1])
phase = sys.argv[2]
repo_root = Path.cwd()

def git(*args):
    return subprocess.run(
        ["git", *args], check=True, text=True, capture_output=True
    ).stdout.strip()

task = os.environ["FVRULELEARNER_TASK"]
dataset_by_task = {
    "nl2sva_machine": repo_root / "FVEval/data_nl2sva/data/nl2sva_machine.csv",
    "nl2sva_human": repo_root / "FVEval/data_nl2sva/data/nl2sva_human.csv",
    "nl2sva_opencore": repo_root / "FVEval/data_1k/module_sva_nl_manual_editing.csv",
}
dataset_path = dataset_by_task[task]

manifest = {
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "phase": phase,
    "git_commit": git("rev-parse", "HEAD"),
    "git_status": git("status", "--short").splitlines(),
    "task": task,
    "dataset_path": str(dataset_path),
    "dataset_sha256": hashlib.sha256(dataset_path.read_bytes()).hexdigest(),
    "model": os.environ["FVRULELEARNER_MODEL"],
    "reasoning_effort": os.environ.get(
        "FVRULELEARNER_REASONING_EFFORT", ""
    ) or "api_default",
    "chat_token_parameter": "max_completion_tokens",
    "temperature_sent_to_api": False,
    "seed": int(os.environ["FVRULELEARNER_SEED"]),
    "num_iter": int(os.environ["FVRULELEARNER_NUM_ITER"]),
    "max_tokens": int(os.environ["FVRULELEARNER_MAX_TOKENS"]),
    "jg_timeout_seconds": int(os.environ["FVRULELEARNER_JG_TIMEOUT_SECONDS"]),
    "nparallel": int(os.environ["FVRULELEARNER_NPARALLEL"]),
}
(run_dir / "run_manifest.json").write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY
}

export FVRULELEARNER_MODEL="${MODEL}"
export FVRULELEARNER_TASK="${TASK}"
export FVRULELEARNER_SEED="${SEED}"
export FVRULELEARNER_NUM_ITER="${NUM_ITER}"
export FVRULELEARNER_MAX_TOKENS="${MAX_TOKENS}"
export FVRULELEARNER_REASONING_EFFORT="${REASONING_EFFORT}"
export FVRULELEARNER_JG_TIMEOUT_SECONDS="${JG_TIMEOUT}"
export FVRULELEARNER_NPARALLEL="${NPARALLEL}"

case "${FVRULELEARNER_MODEL}" in
    o3-mini|o3-mini-*) ;;
    *) echo "ERROR: o3-mini runner refuses model: ${FVRULELEARNER_MODEL}" >&2; exit 2 ;;
esac

case "${FVRULELEARNER_REASONING_EFFORT}" in
    ""|low|medium|high) ;;
    *) echo "ERROR: invalid reasoning effort: ${FVRULELEARNER_REASONING_EFFORT}" >&2; exit 2 ;;
esac

preflight() {
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
from openai import OpenAI

model = os.environ["FVRULELEARNER_MODEL"]
if not (model == "o3-mini" or model.startswith("o3-mini-")):
    raise SystemExit(f"ERROR: o3-mini runner received model={model!r}")

effort = os.environ.get("FVRULELEARNER_REASONING_EFFORT", "").strip().lower()
if effort not in {"", "low", "medium", "high"}:
    raise SystemExit(
        "ERROR: FVRULELEARNER_REASONING_EFFORT must be empty, low, medium, or high"
    )

kwargs = {
    "model": model,
    "messages": [{"role": "user", "content": "Reply exactly with OK."}],
    "max_completion_tokens": 4096,
}
if effort:
    kwargs["reasoning_effort"] = effort

response = OpenAI(
    api_key=os.environ["OPENAI_API_KEY"], timeout=120, max_retries=0
).chat.completions.create(**kwargs)
content = response.choices[0].message.content or ""
if "OK" not in content.upper():
    raise SystemExit(f"ERROR: unexpected o3-mini probe response: {content!r}")

usage = response.usage
print("o3-mini paid API probe: OK")
print("requested_model:", model)
print("returned_model:", response.model)
print("reasoning_effort:", effort or "api_default")
print("prompt_tokens:", getattr(usage, "prompt_tokens", None))
print("completion_tokens:", getattr(usage, "completion_tokens", None))
PY
    else
        echo "OpenAI paid completion probe: skipped"
    fi

    echo "JasperGold executable: $(command -v jg)"
    echo "Preflight complete. No API key value was printed or saved."
}

run_main() {
    local stage="$1"
    local run_dir="$2"
    local debug="$3"
    local num_groups="$4"
    local group_id="$5"
    local iterations="$6"
    local train_dir="${7:-}"

    export FVRULELEARNER_STAGE="${stage}"
    export FVRULELEARNER_DEBUG="${debug}"
    export FVRULELEARNER_NUM_GROUPS="${num_groups}"
    export FVRULELEARNER_GROUP_ID="${group_id}"
    export FVRULELEARNER_START_NUM=0
    export FVRULELEARNER_NUM_ITER="${iterations}"
    if [[ -n "${train_dir}" ]]; then
        export FVRULELEARNER_TRAIN_LOGDIR="${train_dir}"
    else
        unset FVRULELEARNER_TRAIN_LOGDIR || true
    fi

    write_manifest "${run_dir}" "${stage}"
    echo "Output directory: ${run_dir}"
    set -o pipefail
    python3 -u src/main.py --logdir "${run_dir}" 2>&1 | tee "${run_dir}/console.log"

    # FVR_FIX: reject incomplete train/inference phases.  src/main.py stores
    # top-level exceptions in exception.txt but may still exit with status 0.
    if [[ -s "${run_dir}/exception.txt" ]]; then
        echo "ERROR: ${stage} failed; see ${run_dir}/exception.txt" >&2
        return 1
    fi
    if [[ "${stage}" == "train" && ! -s "${run_dir}/training_traces.jsonl" ]]; then
        echo "ERROR: training finished without training_traces.jsonl." >&2
        return 1
    fi
    if [[ "${stage}" == "inference" ]] &&        ! compgen -G "${run_dir}/eval/*_jg.csv" >/dev/null; then
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
        preflight
        run_dir="$(new_run_dir smoke_train)"
        run_main train "${run_dir}" 1 1 0 2
        analyze_train "${run_dir}"
        ;;
    pilot)
        preflight
        run_dir="$(new_run_dir pilot_train)"
        run_main train "${run_dir}" 0 48 0 25
        analyze_train "${run_dir}"
        ;;
    train)
        preflight
        run_dir="$(new_run_dir full_train)"
        run_main train "${run_dir}" 0 1 0 "${NUM_ITER}"
        analyze_train "${run_dir}"
        echo "TRAIN_DIR=${run_dir}"
        ;;
    infer)
        train_dir="${2:-}"
        [[ -n "${train_dir}" ]] || { echo "ERROR: infer requires a training directory." >&2; usage 2; }
        [[ -d "${train_dir}" ]] || { echo "ERROR: not a directory: ${train_dir}" >&2; exit 2; }
        preflight
        run_dir="$(new_run_dir full_inference)"
        run_main inference "${run_dir}" 0 1 0 "${NUM_ITER}" "$(cd -- "${train_dir}" && pwd)"
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
        [[ "${2:-}" == "--yes" ]] || {
            echo "ERROR: full run can make many tens of thousands of paid API calls." >&2
            echo "Re-run as: bash scripts/run_o3mini_reproduction.sh full --yes" >&2
            exit 2
        }
        preflight
        full_root="$(new_run_dir complete)"
        train_dir="${full_root}/train"
        inference_dir="${full_root}/inference"
        run_main train "${train_dir}" 0 1 0 "${NUM_ITER}"
        analyze_train "${train_dir}"
        run_main inference "${inference_dir}" 0 1 0 "${NUM_ITER}" "${train_dir}"
        analyze_infer "${inference_dir}"
        echo "COMPLETE_RUN_DIR=${full_root}"
        echo "TRAIN_DIR=${train_dir}"
        echo "INFERENCE_DIR=${inference_dir}"
        ;;
    *)
        echo "ERROR: unknown phase: ${phase}" >&2
        usage 2
        ;;
esac
