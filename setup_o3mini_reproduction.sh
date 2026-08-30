#!/usr/bin/env bash
# Prepare an already GPT-4o-patched FVRuleLearner checkout for public-API
# o3-mini reproduction, without changing the GPT-4o runner.
#
# Usage:
#   bash setup_o3mini_reproduction.sh /absolute/path/to/SVA_FVRuleLearner

set -Eeuo pipefail

REPO_INPUT="${1:-$PWD}"
[[ -d "${REPO_INPUT}" ]] || {
    echo "ERROR: repository directory not found: ${REPO_INPUT}" >&2
    exit 2
}
REPO="$(cd -- "${REPO_INPUT}" && pwd)"
cd "${REPO}"

for required in \
    src/config.py \
    src/utils_agent.py \
    FVEval/fv_eval/benchmark_launcher.py \
    scripts/run_gpt4o_reproduction.sh \
    scripts/prepare_gpt4o_reproduction.py \
    scripts/analyze_gpt4o_results.py
do
    [[ -f "${required}" ]] || {
        echo "ERROR: required file missing: ${REPO}/${required}" >&2
        exit 2
    }
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "ERROR: ${REPO} is not a Git working tree." >&2
    exit 2
}

STAMP="$(date -u +%Y%m%dT%H%M%SZ)_$$"
BACKUP_DIR="${REPO}/patch_backups/o3mini_setup_${STAMP}"
mkdir -p "${BACKUP_DIR}/files/src" "${BACKUP_DIR}/files/FVEval/fv_eval" "${BACKUP_DIR}/files/scripts"

git status --short > "${BACKUP_DIR}/git_status_before.txt"
git diff --binary > "${BACKUP_DIR}/worktree_before.patch"
git diff --cached --binary > "${BACKUP_DIR}/index_before.patch"

cp -p src/config.py "${BACKUP_DIR}/files/src/config.py"
cp -p src/utils_agent.py "${BACKUP_DIR}/files/src/utils_agent.py"
cp -p FVEval/fv_eval/benchmark_launcher.py \
    "${BACKUP_DIR}/files/FVEval/fv_eval/benchmark_launcher.py"
cp -p scripts/run_gpt4o_reproduction.sh \
    "${BACKUP_DIR}/files/scripts/run_gpt4o_reproduction.sh"

python3 - "${REPO}" <<'PY_SETUP_O3'
from __future__ import annotations

import os
from pathlib import Path
import tempfile
import sys

repo = Path(sys.argv[1])
changed: list[str] = []


def atomic_write(path: Path, content: str) -> None:
    mode = path.stat().st_mode if path.exists() else 0o755
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
        os.chmod(tmp_name, mode)
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def guarded_replace(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        print(f"[skip] {label}")
        return
    if old not in text:
        raise RuntimeError(
            f"Cannot apply {label!r}: expected source block not found in {path}"
        )
    result = text.replace(old, new, 1)
    if path.suffix == ".py":
        compile(result, str(path), "exec")
    atomic_write(path, result)
    changed.append(str(path.relative_to(repo)))
    print(f"[done] {label}")


# The GPT-4o preparation capped every model at 16,384.  The historical
# FVRuleLearner o3-mini config used 20,000, and o3-mini supports a larger
# output budget.  Keep the GPT-4o cap while allowing a model-aware o-series
# limit selected through the same FVRULELEARNER_MAX_TOKENS variable.
config_path = repo / "src/config.py"
guarded_replace(
    config_path,
    '''    max_token = min(
        int(os.environ.get("FVRULELEARNER_MAX_TOKENS", "16384")),
        16384,
    )
''',
    '''    requested_max_tokens = int(
        os.environ.get("FVRULELEARNER_MAX_TOKENS", "16384")
    )
    if requested_max_tokens <= 0:
        raise ValueError("FVRULELEARNER_MAX_TOKENS must be positive")
    model_lower = llm_model.lower()
    model_output_cap = (
        100000
        if model_lower.startswith(("o1-", "o3-", "o4-"))
        else 16384
    )
    max_token = min(requested_max_tokens, model_output_cap)
''',
    "model-aware output-token cap",
)


# Chat Completions uses max_completion_tokens for o-series models.  Do not
# send temperature for o3-mini.  Leave reasoning effort unspecified by
# default, matching the public repository; allow an explicit controlled
# override when requested.
utils_path = repo / "src/utils_agent.py"
guarded_replace(
    utils_path,
    '''    create_kwargs = {
        "model": effective_model,
        "messages": messages,
        "max_tokens": min(getattr(FLAGS, "max_token", 16384), 16384),
    }
    if not is_o_series_model(effective_model):
        create_kwargs["temperature"] = effective_temperature

    response = client.chat.completions.create(**create_kwargs)
    return response.choices[0].message.content
''',
    '''    output_limit = int(getattr(FLAGS, "max_token", 16384))
    create_kwargs = {
        "model": effective_model,
        "messages": messages,
    }
    if is_o_series_model(effective_model):
        create_kwargs["max_completion_tokens"] = output_limit
        reasoning_effort = os.environ.get(
            "FVRULELEARNER_REASONING_EFFORT", ""
        ).strip().lower()
        if reasoning_effort:
            if reasoning_effort not in {"low", "medium", "high"}:
                raise ValueError(
                    "FVRULELEARNER_REASONING_EFFORT must be empty, "
                    "low, medium, or high for o3-mini"
                )
            create_kwargs["reasoning_effort"] = reasoning_effort
    else:
        create_kwargs["max_tokens"] = min(output_limit, 16384)
        create_kwargs["temperature"] = effective_temperature

    response = client.chat.completions.create(**create_kwargs)
    content = response.choices[0].message.content
    if not content:
        raise RuntimeError(
            "OpenAI returned no visible completion content; increase "
            "FVRULELEARNER_MAX_TOKENS or inspect the response usage."
        )
    return content
''',
    "o-series Chat Completions parameters",
)


# tiktoken 0.7 does not map the o3-mini alias automatically even though it
# provides the o200k_base encoding used by the public o-series models.  Use
# the encoding explicitly so prompt-token statistics are not silently counted
# with the GPT-3.5/cl100k fallback.  This counter is observational only; the
# API still performs its own authoritative billing-token accounting.
guarded_replace(
    utils_path,
    '''def get_tokenizer(llm_model):
    # Attempt to use the specific model for tokenization
    try:
        return tiktoken.encoding_for_model(llm_model)
    except Exception as e:
        print(f"Error loading tokenizer for {llm_model}: {e}. Falling back to 'gpt-3.5-turbo'.")
        try:
            return tiktoken.encoding_for_model("gpt-3.5-turbo")
        except Exception as fallback_e:
            print(f"Error loading fallback tokenizer: {fallback_e}")
            raise fallback_e
''',
    '''def get_tokenizer(llm_model):
    # tiktoken 0.7 does not know every o-series alias, but it includes the
    # o200k_base encoding used by o3-mini.
    if is_o_series_model(llm_model):
        return tiktoken.get_encoding("o200k_base")

    try:
        return tiktoken.encoding_for_model(llm_model)
    except KeyError as exc:
        print(
            f"Tokenizer mapping unavailable for {llm_model}: {exc}. "
            "Falling back to cl100k_base."
        )
        return tiktoken.get_encoding("cl100k_base")
''',
    "explicit o3-mini tokenizer encoding",
)


# Normalize the historical internal spelling to the public model IDs and
# support both the alias and the dated public snapshot spelling.
launcher_path = repo / "FVEval/fv_eval/benchmark_launcher.py"
guarded_replace(
    launcher_path,
    '''                if model_name == "o1-20241217":
                    full_model_name = "o1-20241217"
                elif model_name == "o3-mini-20250131":
                    full_model_name = "o3-mini-20250131"
''',
    '''                if model_name == "o1-20241217":
                    full_model_name = "o1-20241217"
                elif model_name == "o3-mini":
                    full_model_name = "o3-mini"
                elif model_name == "o3-mini-2025-01-31":
                    full_model_name = "o3-mini-2025-01-31"
                elif model_name == "o3-mini-20250131":
                    # Historical FVRuleLearner/PerfLab spelling.
                    full_model_name = "o3-mini-2025-01-31"
                else:
                    raise ValueError(f"Unknown o-series model: {model_name}")
''',
    "public o3-mini model routing",
)


gpt_runner_path = repo / "scripts/run_gpt4o_reproduction.sh"
o3_runner_path = repo / "scripts/run_o3mini_reproduction.sh"
runner = gpt_runner_path.read_text(encoding="utf-8")

runner = runner.replace(
    "run_gpt4o_reproduction.sh", "run_o3mini_reproduction.sh"
)
runner = runner.replace(
    'MODEL="${FVRULELEARNER_MODEL:-gpt-4o-2024-11-20}"',
    'MODEL="${FVRULELEARNER_MODEL:-o3-mini}"',
)
runner = runner.replace(
    'MAX_TOKENS="${FVRULELEARNER_MAX_TOKENS:-16384}"',
    'MAX_TOKENS="${FVRULELEARNER_MAX_TOKENS:-20000}"\n'
    'REASONING_EFFORT="${FVRULELEARNER_REASONING_EFFORT:-}"',
)
runner = runner.replace(
    'RUN_ROOT="${FVRULELEARNER_RUN_ROOT:-${REPO_ROOT}/src/logs/gpt4o_reproduction}"',
    'RUN_ROOT="${FVRULELEARNER_RUN_ROOT:-${REPO_ROOT}/src/logs/o3mini_reproduction}"',
)
runner = runner.replace(
    "#   FVRULELEARNER_NUM_ITER, FVRULELEARNER_MAX_TOKENS,\n",
    "#   FVRULELEARNER_NUM_ITER, FVRULELEARNER_MAX_TOKENS,\n"
    "#   FVRULELEARNER_REASONING_EFFORT (empty|low|medium|high),\n",
)
runner = runner.replace(
    '    "model": os.environ["FVRULELEARNER_MODEL"],\n',
    '    "model": os.environ["FVRULELEARNER_MODEL"],\n'
    '    "reasoning_effort": os.environ.get(\n'
    '        "FVRULELEARNER_REASONING_EFFORT", ""\n'
    '    ) or "api_default",\n'
    '    "chat_token_parameter": "max_completion_tokens",\n'
    '    "temperature_sent_to_api": False,\n',
)
runner = runner.replace(
    'export FVRULELEARNER_MAX_TOKENS="${MAX_TOKENS}"\n',
    'export FVRULELEARNER_MAX_TOKENS="${MAX_TOKENS}"\n'
    'export FVRULELEARNER_REASONING_EFFORT="${REASONING_EFFORT}"\n',
)

old_probe = '''    if [[ "${FVRULELEARNER_SKIP_API_PROBE:-0}" != "1" ]]; then
        python3 - <<'PY'
import os
from openai import OpenAI

model = os.environ["FVRULELEARNER_MODEL"]
OpenAI(api_key=os.environ["OPENAI_API_KEY"], timeout=60).models.retrieve(model)
print(f"OpenAI API access: OK ({model})")
PY
    else
        echo "OpenAI API access probe: skipped"
    fi
'''
new_probe = '''    if [[ "${FVRULELEARNER_SKIP_API_PROBE:-0}" != "1" ]]; then
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
'''
if old_probe not in runner:
    raise RuntimeError("Cannot create o3-mini runner: GPT-4o probe block not found")
runner = runner.replace(old_probe, new_probe, 1)

runner = runner.replace(
    'export FVRULELEARNER_NPARALLEL="${NPARALLEL}"\n\npreflight() {',
    'export FVRULELEARNER_NPARALLEL="${NPARALLEL}"\n\n'
    'case "${FVRULELEARNER_MODEL}" in\n'
    '    o3-mini|o3-mini-*) ;;\n'
    '    *) echo "ERROR: o3-mini runner refuses model: '
    '${FVRULELEARNER_MODEL}" >&2; exit 2 ;;\n'
    'esac\n\n'
    'case "${FVRULELEARNER_REASONING_EFFORT}" in\n'
    '    ""|low|medium|high) ;;\n'
    '    *) echo "ERROR: invalid reasoning effort: '
    '${FVRULELEARNER_REASONING_EFFORT}" >&2; exit 2 ;;\n'
    'esac\n\npreflight() {',
)

if "o3-mini" not in runner or "max_completion_tokens" not in runner:
    raise RuntimeError("Generated o3-mini runner failed content validation")

compile(config_path.read_text(encoding="utf-8"), str(config_path), "exec")
compile(utils_path.read_text(encoding="utf-8"), str(utils_path), "exec")
compile(launcher_path.read_text(encoding="utf-8"), str(launcher_path), "exec")
atomic_write(o3_runner_path, runner)
os.chmod(o3_runner_path, 0o755)
changed.append(str(o3_runner_path.relative_to(repo)))
print(f"[done] generated {o3_runner_path.relative_to(repo)}")
print("Changed files:")
for item in changed:
    print(f"  {item}")
PY_SETUP_O3

python3 -m py_compile \
    src/config.py \
    src/utils_agent.py \
    FVEval/fv_eval/benchmark_launcher.py
bash -n scripts/run_o3mini_reproduction.sh
python3 scripts/prepare_gpt4o_reproduction.py --check-only
git diff --check

python3 - <<'PY'
import ast
from pathlib import Path

path = Path("src/utils_agent.py")
tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
source = path.read_text(encoding="utf-8")
required = [
    'create_kwargs["max_completion_tokens"]',
    'FVRULELEARNER_REASONING_EFFORT',
    'create_kwargs["max_tokens"]',
    'tiktoken.get_encoding("o200k_base")',
]
missing = [item for item in required if item not in source]
if missing:
    raise SystemExit(f"ERROR: missing o3-mini API branches: {missing}")
print("o3-mini source validation: PASS")
PY

echo "Backup: ${BACKUP_DIR}"
echo "o3-mini setup complete."
echo "Next: bash scripts/run_o3mini_reproduction.sh preflight"
