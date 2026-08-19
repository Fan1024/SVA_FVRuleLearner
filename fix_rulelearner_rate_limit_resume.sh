#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
FVRuleLearner OpenAI 429/retry/resume hotfix

Usage:
  bash fix_fvrulelearner_rate_limit_resume.sh diagnose RUN_DIR
  bash fix_fvrulelearner_rate_limit_resume.sh apply REPO_ROOT
  bash fix_fvrulelearner_rate_limit_resume.sh resume REPO_ROOT RUN_DIR [MAX_TOKENS]

Recommended sequence:
  bash fix_fvrulelearner_rate_limit_resume.sh diagnose \
    /raid/spring2026/fwu44/research/SVA_FVRuleLearner/src/logs/gpt4o_reproduction/full_train_20260819T103315Z_3359991

  bash fix_fvrulelearner_rate_limit_resume.sh apply \
    /raid/spring2026/fwu44/research/SVA_FVRuleLearner

  bash fix_fvrulelearner_rate_limit_resume.sh resume \
    /raid/spring2026/fwu44/research/SVA_FVRuleLearner \
    /raid/spring2026/fwu44/research/SVA_FVRuleLearner/src/logs/gpt4o_reproduction/full_train_20260819T103315Z_3359991 \
    4096

The resume command counts completed JSONL traces automatically, preserves old
suggestions/Q-trees, archives exception.txt, and continues in the same run dir.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

abspath_dir() {
    local path="$1"
    [[ -d "${path}" ]] || die "not a directory: ${path}"
    (cd -- "${path}" && pwd)
}

diagnose() {
    local run_dir
    run_dir="$(abspath_dir "$1")"
    echo "Run directory: ${run_dir}"
    if [[ -s "${run_dir}/training_traces.jsonl" ]]; then
        python3 - "${run_dir}/training_traces.jsonl" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
traces = []
for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
    if not line.strip():
        continue
    try:
        traces.append(json.loads(line))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON at {path}:{line_no}: {exc}")
print(f"Completed training cases: {len(traces)}")
if traces:
    last = traces[-1]
    print(
        "Last completed case: "
        f"design={last.get('design_name', '')}, task={last.get('task_id', '')}, "
        f"iterations={last.get('iterations', '')}, fixed={last.get('fixed', '')}"
    )
PY
    else
        echo "Completed training cases: 0 (training_traces.jsonl missing or empty)"
    fi

    echo
    echo "Relevant 429/rate-limit lines (the error code determines the remedy):"
    local found=0
    local file
    for file in "${run_dir}/exception.txt" "${run_dir}/console.log"; do
        [[ -f "${file}" ]] || continue
        if grep -nEi -B 3 -A 5 \
            'error code: 429|RateLimitError|rate[_ -]?limit|insufficient_quota|credit_balance_exhausted|spend_limit|usage_limit|tokens per min|requests per min|Requested|Retry-After' \
            "${file}" | tail -n 120; then
            found=1
        fi
    done
    (( found == 1 )) || echo "No matching lines found; inspect ${run_dir}/exception.txt manually."

    echo
    echo "Interpretation:"
    echo "  credit_balance_exhausted / *_spend_limit_* / *_usage_limit_*: account action is required; retries cannot fix it."
    echo "  rate_limit_exceeded / tokens-per-minute / requests-per-minute: transient; pace requests and resume."
}

apply_hotfix() {
    local repo_root backup_root stamp
    repo_root="$(abspath_dir "$1")"
    [[ -f "${repo_root}/src/utils_agent.py" ]] || die "not an FVRuleLearner checkout: ${repo_root}"
    [[ -f "${repo_root}/src/saver.py" ]] || die "missing src/saver.py"
    [[ -f "${repo_root}/FVEval/fv_eval/benchmark_launcher.py" ]] || die "missing benchmark_launcher.py"
    [[ -f "${repo_root}/scripts/run_gpt4o_reproduction.sh" ]] || die "missing reproduction runner"

    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    backup_root="${repo_root}/.fvr_rate_limit_backup_${stamp}_$$"
    mkdir -p "${backup_root}/src" "${backup_root}/FVEval/fv_eval" "${backup_root}/scripts"
    cp -p "${repo_root}/src/utils_agent.py" "${backup_root}/src/"
    cp -p "${repo_root}/src/config.py" "${backup_root}/src/"
    cp -p "${repo_root}/src/saver.py" "${backup_root}/src/"
    cp -p "${repo_root}/FVEval/fv_eval/benchmark_launcher.py" "${backup_root}/FVEval/fv_eval/"
    cp -p "${repo_root}/scripts/run_gpt4o_reproduction.sh" "${backup_root}/scripts/"
    echo "Backup: ${backup_root}"

    python3 - "${repo_root}" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])

def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        print(f"Already patched: {path} ({marker})")
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one patch anchor in {path}, found {count}: {old[:80]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"Patched: {path}")

utils = root / "src/utils_agent.py"
replace_once(
    utils,
    "from openai import APITimeoutError, APIError, APIConnectionError, InternalServerError\n",
    "from openai import (\n"
    "    APITimeoutError, APIError, APIConnectionError, InternalServerError,\n"
    "    RateLimitError as OpenAIRateLimitError,\n"
    ")\n"
    "# FVR_RATE_LIMIT_FIX: distinguish transient throttling from quota/billing 429s.\n",
    "FVR_RATE_LIMIT_FIX",
)

text = utils.read_text(encoding="utf-8")
old_client = "client = OpenAI(api_key=api_key, timeout=timeout)"
new_client = (
    "client = OpenAI(\n"
    "        api_key=api_key,\n"
    "        timeout=timeout,\n"
    "        # The official SDK honors Retry-After for eligible 429 responses.\n"
    "        max_retries=int(os.environ.get(\"FVRULELEARNER_OPENAI_MAX_RETRIES\", \"3\")),\n"
    "    )"
)
if new_client not in text:
    if text.count(old_client) != 1:
        raise SystemExit(f"Expected one OpenAI client anchor in {utils}, found {text.count(old_client)}")
    text = text.replace(old_client, new_client, 1)

old_retry = "    stop=stop_after_attempt(10),\n)\ndef llm_inference"
new_retry = (
    "    # Avoid multiplying SDK retries by another ten-attempt Tenacity loop.\n"
    "    stop=stop_after_attempt(1),\n"
    "    reraise=True,\n"
    ")\n"
    "def llm_inference"
)
if new_retry not in text:
    if text.count(old_retry) != 1:
        raise SystemExit(f"Expected one Tenacity anchor in {utils}, found {text.count(old_retry)}")
    text = text.replace(old_retry, new_retry, 1)

start_anchor = "        # Implement retry logic for the direct OpenAI gateway\n"
end_anchor = "        raise RuntimeError(\"Failed to get a response after all retries using the configured direct LLM gateway.\")\n"
start = text.find(start_anchor)
end = text.find(end_anchor, start)
if start == -1 or end == -1:
    if "FVR_DIRECT_RETRY_FIX" not in text:
        raise SystemExit(f"Could not locate direct retry block in {utils}")
else:
    end += len(end_anchor)
    new_block = '''        # FVR_DIRECT_RETRY_FIX: bounded application retries with quota fail-fast.
        permanent_429_codes = {
            "credit_balance_exhausted",
            "organization_spend_limit_exceeded",
            "project_spend_limit_exceeded",
            "organization_usage_limit_exceeded",
        }

        def error_code(exc):
            body = getattr(exc, "body", None)
            if isinstance(body, dict):
                nested = body.get("error")
                if isinstance(nested, dict) and nested.get("code"):
                    return str(nested["code"])
                if body.get("code"):
                    return str(body["code"])
            return ""

        for attempt in range(max(int(retries), 1)):
            try:
                return llm_inference(
                    system_prompt,
                    message,
                    temperature=temperature,
                    model=effective_model,
                )
            except OpenAIRateLimitError as exc:
                code = error_code(exc)
                text_lower = str(exc).lower()
                permanent = (
                    code in permanent_429_codes
                    or "insufficient_quota" in text_lower
                    or "exceeded your current quota" in text_lower
                )
                if permanent:
                    raise RuntimeError(
                        "Non-retryable OpenAI quota/billing error"
                        f" ({code or 'insufficient_quota'}). Add credits or raise the "
                        "project/organization limit before resuming."
                    ) from exc
                if attempt + 1 >= max(int(retries), 1):
                    raise
                wait_time = min(60.0, (2.0 ** attempt) + random.random())
                print(
                    f"@@@{FLAGS.llm_model}: temporary OpenAI rate limit; "
                    f"application retry {attempt + 1}/{retries} in {wait_time:.1f}s"
                )
                time.sleep(wait_time)
            except (
                APITimeoutError,
                APIError,
                APIConnectionError,
                httpx.TimeoutException,
                httpx.ReadTimeout,
                InternalServerError,
            ) as exc:
                if attempt + 1 >= max(int(retries), 1):
                    raise
                wait_time = min(60.0, (2.0 ** attempt) + random.random())
                print(
                    f"@@@{FLAGS.llm_model}: transient API error {type(exc).__name__}; "
                    f"application retry {attempt + 1}/{retries} in {wait_time:.1f}s"
                )
                time.sleep(wait_time)

        raise RuntimeError("Failed to get a response after bounded API retries.")
'''
    text = text[:start] + new_block + text[end:]
utils.write_text(text, encoding="utf-8")
print(f"Patched: {utils} (SDK retry + bounded application retry)")

config = root / "src/config.py"
replace_once(
    config,
    "    GPT_retries = 10\n",
    "    # FVR_API_RETRY_CONFIG: high-level retries after SDK retries.\n"
    "    GPT_retries = max(1, int(os.environ.get(\"FVRULELEARNER_GPT_RETRIES\", \"3\")))\n",
    "FVR_API_RETRY_CONFIG",
)

launcher = root / "FVEval/fv_eval/benchmark_launcher.py"
launcher_text = launcher.read_text(encoding="utf-8")
if "FVR_OUTER_RETRY_FIX" not in launcher_text:
    launcher_text = launcher_text.replace(
        "        max_retries: int = 40,\n",
        "        max_retries: int = 2,\n",
        1,
    ).replace(
        "        while num_retries <= 20:\n",
        "        # FVR_OUTER_RETRY_FIX: honor max_retries; do not print a retry then raise immediately.\n"
        "        while num_retries <= max_retries:\n",
        1,
    ).replace(
        "            # Sleep for the delay\n            time.sleep(delay)\n            # Increment the delay\n            delay *= 2 * (1 + 1 * random.random())\n",
        "            # Bound whole-case retries; request-level retries happen in utils_agent.py.\n"
        "            time.sleep(min(delay, 60.0))\n"
        "            delay = min(60.0, delay * 2 * (1 + random.random()))\n",
        1,
    ).replace(
        "            except Exception as e:\n                delay, error, num_retries = _handle_exception(delay, error, num_retries, e)\n\n            if error is not None:\n                raise error\n",
        "            except Exception as e:\n"
        "                if \"Non-retryable OpenAI quota/billing error\" in str(e):\n"
        "                    raise\n"
        "                delay, error, num_retries = _handle_exception(delay, error, num_retries, e)\n\n"
        "            if error is not None:\n"
        "                if num_retries > max_retries:\n"
        "                    raise error\n"
        "                continue\n",
        1,
    ).replace(
        "        max_retries: int = 20,\n",
        "        max_retries: int = 2,\n",
        1,
    )
    required = ["FVR_OUTER_RETRY_FIX", "continue\n        return None"]
    if not all(value in launcher_text for value in required):
        raise SystemExit(f"Failed to patch retry loop safely in {launcher}")
    launcher.write_text(launcher_text, encoding="utf-8")
    print(f"Patched: {launcher}")
else:
    print(f"Already patched: {launcher} (FVR_OUTER_RETRY_FIX)")

saver = root / "src/saver.py"
saver_text = saver.read_text(encoding="utf-8")
if "FVR_RESUME_STATE_FIX" not in saver_text:
    old = (
        "        self.learned_knowledge = []  # TODO --> KG\n"
        "        self.qtree_corrections = []  # Store qtrees that lead to corrections\n"
    )
    new = '''        self.learned_knowledge = []  # TODO --> KG
        self.qtree_corrections = []  # Store qtrees that lead to corrections

        # FVR_RESUME_STATE_FIX: preserve accumulated retrieval knowledge across a resumed process.
        if os.environ.get("FVRULELEARNER_RESUME", "0") == "1":
            suggestions_path = join(self.logdir, "suggestions.pkl")
            qtrees_path = join(self.logdir, "qtrees.pkl")
            if os.path.isfile(suggestions_path):
                with open(suggestions_path, "rb") as stream:
                    loaded = pickle.load(stream)
                if not isinstance(loaded, list):
                    raise TypeError(f"Expected a list in {suggestions_path}")
                self.learned_knowledge = loaded
                print(f"Resume: loaded {len(loaded)} saved suggestions")
            if os.path.isfile(qtrees_path):
                with open(qtrees_path, "rb") as stream:
                    loaded = pickle.load(stream)
                if not isinstance(loaded, list):
                    raise TypeError(f"Expected a list in {qtrees_path}")
                self.qtree_corrections = loaded
                print(f"Resume: loaded {len(loaded)} saved Q-trees")
'''
    if saver_text.count(old) != 1:
        raise SystemExit(f"Expected one resume-state anchor in {saver}, found {saver_text.count(old)}")
    saver.write_text(saver_text.replace(old, new, 1), encoding="utf-8")
    print(f"Patched: {saver}")
else:
    print(f"Already patched: {saver} (FVR_RESUME_STATE_FIX)")

runner = root / "scripts/run_gpt4o_reproduction.sh"
runner_text = runner.read_text(encoding="utf-8")
if "FVR_RESUME_RUNNER_FIX" not in runner_text:
    runner_text = runner_text.replace(
        "#   bash scripts/run_gpt4o_reproduction.sh train\n",
        "#   bash scripts/run_gpt4o_reproduction.sh train\n"
        "#   bash scripts/run_gpt4o_reproduction.sh resume-train /absolute/path/to/interrupted/train [START_NUM]\n",
        1,
    )
    runner_text = runner_text.replace(
        "    local train_dir=\"${7:-}\"\n",
        "    local train_dir=\"${7:-}\"\n"
        "    local start_num=\"${8:-0}\"\n"
        "    local resume_mode=\"${9:-0}\"\n",
        1,
    )
    runner_text = runner_text.replace(
        "    export FVRULELEARNER_START_NUM=0\n",
        "    # FVR_RESUME_RUNNER_FIX: select only unfinished rows and preserve saved knowledge.\n"
        "    export FVRULELEARNER_START_NUM=\"${start_num}\"\n"
        "    export FVRULELEARNER_RESUME=\"${resume_mode}\"\n",
        1,
    )
    runner_text = runner_text.replace(
        "    write_manifest \"${run_dir}\" \"${stage}\"\n"
        "    echo \"Output directory: ${run_dir}\"\n"
        "    set -o pipefail\n"
        "    OPENAI_API_KEY=\"${OPENAI_API_KEY}\" \\\n"
        "        python3 -u src/main.py --logdir \"${run_dir}\" 2>&1 \\\n"
        "        | tee \"${run_dir}/console.log\"\n",
        "    if [[ \"${resume_mode}\" == \"1\" ]]; then\n"
        "        if [[ -s \"${run_dir}/exception.txt\" ]]; then\n"
        "            mv \"${run_dir}/exception.txt\" \\\n"
        "                \"${run_dir}/exception.before_resume.$(date -u +%Y%m%dT%H%M%SZ).txt\"\n"
        "        fi\n"
        "        echo \"Resuming at completed-case offset ${start_num}: ${run_dir}\"\n"
        "    else\n"
        "        write_manifest \"${run_dir}\" \"${stage}\"\n"
        "        echo \"Output directory: ${run_dir}\"\n"
        "    fi\n"
        "    set -o pipefail\n"
        "    if [[ \"${resume_mode}\" == \"1\" ]]; then\n"
        "        OPENAI_API_KEY=\"${OPENAI_API_KEY}\" \\\n"
        "            python3 -u src/main.py --logdir \"${run_dir}\" 2>&1 \\\n"
        "            | tee -a \"${run_dir}/console.log\"\n"
        "    else\n"
        "        OPENAI_API_KEY=\"${OPENAI_API_KEY}\" \\\n"
        "            python3 -u src/main.py --logdir \"${run_dir}\" 2>&1 \\\n"
        "            | tee \"${run_dir}/console.log\"\n"
        "    fi\n",
        1,
    )
    train_case = '''    train)
        preflight
        run_dir="$(new_run_dir full_train)"
        run_main train "${run_dir}" 0 1 0 "${NUM_ITER}"
        analyze_train "${run_dir}"
        echo "TRAIN_DIR=${run_dir}"
        ;;
'''
    resume_case = train_case + '''    resume-train)
        run_dir="${2:-}"
        [[ -n "${run_dir}" ]] || { echo "ERROR: resume-train requires a training directory." >&2; usage 2; }
        run_dir="$(cd -- "${run_dir}" && pwd)"
        [[ -s "${run_dir}/training_traces.jsonl" ]] || {
            echo "ERROR: missing or empty ${run_dir}/training_traces.jsonl" >&2
            exit 2
        }
        completed="$(python3 - "${run_dir}/training_traces.jsonl" <<'PYCOUNT'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
count = 0
for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
    if not line.strip():
        continue
    try:
        json.loads(line)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON at line {line_no}: {exc}")
    count += 1
print(count)
PYCOUNT
)"
        start_num="${3:-${completed}}"
        [[ "${start_num}" =~ ^[0-9]+$ ]] || { echo "ERROR: START_NUM must be nonnegative." >&2; exit 2; }
        if [[ "${start_num}" != "${completed}" ]]; then
            echo "WARNING: trace count is ${completed}, but explicit START_NUM is ${start_num}." >&2
        fi
        preflight
        run_main train "${run_dir}" 0 1 0 "${NUM_ITER}" "" "${start_num}" 1
        analyze_train "${run_dir}"
        echo "TRAIN_DIR=${run_dir}"
        ;;
'''
    if runner_text.count(train_case) != 1:
        raise SystemExit(f"Expected one train case anchor in {runner}, found {runner_text.count(train_case)}")
    runner_text = runner_text.replace(train_case, resume_case, 1)
    runner.write_text(runner_text, encoding="utf-8")
    print(f"Patched: {runner}")
else:
    print(f"Already patched: {runner} (FVR_RESUME_RUNNER_FIX)")
PY

    python3 -m py_compile \
        "${repo_root}/src/utils_agent.py" \
        "${repo_root}/src/config.py" \
        "${repo_root}/src/saver.py" \
        "${repo_root}/FVEval/fv_eval/benchmark_launcher.py"
    bash -n "${repo_root}/scripts/run_gpt4o_reproduction.sh"
    grep -nE 'FVR_(RATE_LIMIT|DIRECT_RETRY|API_RETRY|OUTER_RETRY|RESUME_STATE|RESUME_RUNNER)_FIX' \
        "${repo_root}/src/utils_agent.py" \
        "${repo_root}/src/config.py" \
        "${repo_root}/src/saver.py" \
        "${repo_root}/FVEval/fv_eval/benchmark_launcher.py" \
        "${repo_root}/scripts/run_gpt4o_reproduction.sh"
    echo "Hotfix applied and syntax checks passed."
}

resume_run() {
    local repo_root run_dir max_tokens completed
    repo_root="$(abspath_dir "$1")"
    run_dir="$(abspath_dir "$2")"
    max_tokens="${3:-4096}"
    [[ "${max_tokens}" =~ ^[1-9][0-9]*$ ]] || die "MAX_TOKENS must be a positive integer"
    grep -q 'FVR_RESUME_RUNNER_FIX' "${repo_root}/scripts/run_gpt4o_reproduction.sh" || \
        die "hotfix is not applied; run the apply command first"
    [[ -s "${run_dir}/training_traces.jsonl" ]] || die "missing training_traces.jsonl in ${run_dir}"
    completed="$(grep -cve '^[[:space:]]*$' "${run_dir}/training_traces.jsonl")"
    echo "Continuing after ${completed} completed cases with max output tokens=${max_tokens}."
    echo "If diagnose showed a quota/billing code, fix the account limit first; retries cannot solve it."
    cd -- "${repo_root}"
    FVRULELEARNER_MAX_TOKENS="${max_tokens}" \
    FVRULELEARNER_OPENAI_MAX_RETRIES="3" \
    FVRULELEARNER_GPT_RETRIES="3" \
        bash scripts/run_gpt4o_reproduction.sh resume-train "${run_dir}" "${completed}"
}

command="${1:-help}"
case "${command}" in
    diagnose)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        diagnose "$2"
        ;;
    apply)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        apply_hotfix "$2"
        ;;
    resume)
        [[ $# -ge 3 && $# -le 4 ]] || { usage; exit 2; }
        resume_run "$2" "$3" "${4:-4096}"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        usage
        die "unknown command: ${command}"
        ;;
esac
