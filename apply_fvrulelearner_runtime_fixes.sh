#!/usr/bin/env bash
# One-shot, idempotent patch for the FVRuleLearner GPT-4o reproduction flow.
#
# Usage (run from the SVA_FVRuleLearner repository root):
#   bash /path/to/apply_fvrulelearner_runtime_fixes.sh
#
# Or pass the repository root explicitly:
#   bash /path/to/apply_fvrulelearner_runtime_fixes.sh \
#     /raid/spring2026/fwu44/research/SVA_FVRuleLearner

set -Eeuo pipefail

REPO_ROOT="${1:-$PWD}"
REPO_ROOT="$(cd -- "${REPO_ROOT}" && pwd)"

EVALUATION_FILE="${REPO_ROOT}/FVEval/fv_eval/evaluation.py"
JG_EXECUTION_FILE="${REPO_ROOT}/FVEval/fv_eval/fv_tool_execution.py"
RUNNER_FILE="${REPO_ROOT}/scripts/run_gpt4o_reproduction.sh"

for required_file in \
    "${EVALUATION_FILE}" \
    "${JG_EXECUTION_FILE}" \
    "${RUNNER_FILE}"
do
    if [[ ! -f "${required_file}" ]]; then
        echo "ERROR: required file not found: ${required_file}" >&2
        echo "Run this script from the SVA_FVRuleLearner repository root." >&2
        exit 2
    fi
done

BACKUP_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "${REPO_ROOT}/patch_backups"
BACKUP_DIR="$(mktemp -d \
    "${REPO_ROOT}/patch_backups/fvrulelearner_runtime_fix_${BACKUP_STAMP}_XXXXXX")"
mkdir -p "${BACKUP_DIR}/FVEval/fv_eval" "${BACKUP_DIR}/scripts"

cp -p "${EVALUATION_FILE}" \
    "${BACKUP_DIR}/FVEval/fv_eval/evaluation.py"
cp -p "${JG_EXECUTION_FILE}" \
    "${BACKUP_DIR}/FVEval/fv_eval/fv_tool_execution.py"
cp -p "${RUNNER_FILE}" \
    "${BACKUP_DIR}/scripts/run_gpt4o_reproduction.sh"

python3 - "${REPO_ROOT}" <<'PY'
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile


repo = Path(sys.argv[1]).resolve()
evaluation_path = repo / "FVEval/fv_eval/evaluation.py"
jg_path = repo / "FVEval/fv_eval/fv_tool_execution.py"
runner_path = repo / "scripts/run_gpt4o_reproduction.sh"

paths = [evaluation_path, jg_path, runner_path]
original = {path: path.read_text(encoding="utf-8") for path in paths}
updated = dict(original)
changes: list[str] = []


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"Cannot safely apply {description}: expected exactly one matching "
            f"code block, found {count}. No source files were changed."
        )
    changes.append(description)
    return text.replace(old, new, 1)


# -------------------------------------------------------------------------
# 1. NL2SVA-Machine PEC must declare tb_reset when the generated assertion
#    introduces `disable iff (tb_reset)`.
# -------------------------------------------------------------------------
evaluation = updated[evaluation_path]
signal_marker = "FVR_FIX: include valid reset used only by generated assertion"
if signal_marker not in evaluation:
    old_signal_block = '''                    signal_list = re.findall(r"\\bsig_\\w+", lm_result.ref_solution)
                    signal_list = list(set(signal_list))
                    signal_list_text = ",".join(signal_list)
'''
    new_signal_block = '''                    signal_list = set(re.findall(r"\\bsig_\\w+", lm_result.ref_solution))

                    # FVR_FIX: include valid reset used only by generated assertion.
                    # NL2SVA-Machine testbenches declare tb_reset, while GPT may
                    # introduce `disable iff (tb_reset)` even when the reference
                    # property does not mention reset.
                    combined_assertion_text = (
                        f"{lm_assertion_text} {ref_assertion_text}"
                    )
                    if re.search(r"\\btb_reset\\b", combined_assertion_text):
                        signal_list.add("tb_reset")

                    signal_list_text = ",".join(sorted(signal_list))
'''
    evaluation = replace_once(
        evaluation,
        old_signal_block,
        new_signal_block,
        "NL2SVA-Machine tb_reset signal-list fix",
    )


# -------------------------------------------------------------------------
# 2. Treat Jasper syntax/elaboration diagnostics as candidate failures rather
#    than accidentally reporting syntax=1/functionality=0.
#    Patch only the calculate_jg_metric method inside NL2SVAMachineEvaluator.
# -------------------------------------------------------------------------
metric_marker = "FVR_FIX: recognize Jasper syntax and elaboration failures"
if metric_marker not in evaluation:
    class_anchor = "class NL2SVAMachineEvaluator(Evaluator):"
    class_pos = evaluation.find(class_anchor)
    if class_pos < 0:
        raise RuntimeError(
            "Cannot find NL2SVAMachineEvaluator. No source files were changed."
        )
    prefix = evaluation[:class_pos]
    machine_section = evaluation[class_pos:]
    old_metric_block = '''        # check for syntax error
        syntax_error_match = re.findall(r"syntax error", jasper_out_str)
        if syntax_error_match:
'''
    new_metric_block = '''        # FVR_FIX: recognize Jasper syntax and elaboration failures.
        syntax_error_match = re.search(
            r"syntax error"
            r"|\\[ERROR \\(VERI-"
            r"|ERROR \\(ENL\\d+\\)"
            r"|ignored due to previous errors",
            jasper_out_str,
            flags=re.IGNORECASE,
        )
        if syntax_error_match:
'''
    machine_section = replace_once(
        machine_section,
        old_metric_block,
        new_metric_block,
        "NL2SVA-Machine Jasper error classification fix",
    )
    evaluation = prefix + machine_section

updated[evaluation_path] = evaluation


# -------------------------------------------------------------------------
# 3. A hard property may legitimately time out. Preserve a UID and report it
#    as a per-case functionality failure so one case cannot kill 240 cases.
#    A completed JG process with syntax/elaboration diagnostics is also a
#    candidate failure. License/tool failures remain fatal.
# -------------------------------------------------------------------------
jg_text = updated[jg_path]
timeout_marker = "FVR_FIX: keep a single Jasper timeout local to its case"
if timeout_marker not in jg_text:
    old_timeout_block = '''    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"JasperGold timed out after {timeout_seconds} seconds "
            f"for task {task_id}"
        ) from exc
'''
    new_timeout_block = '''    except subprocess.TimeoutExpired:
        # FVR_FIX: keep a single Jasper timeout local to its case.  The UID is
        # required by evaluation.py when it converts tool output into metrics.
        timeout_output = (
            f"TASK_ID {task_id}\\n"
            f"JASPER_TIMEOUT: exceeded {timeout_seconds} seconds"
        )
        print(f"WARNING: {timeout_output.replace(chr(10), ' | ')}")
        return timeout_output
'''
    jg_text = replace_once(
        jg_text,
        old_timeout_block,
        new_timeout_block,
        "per-case Jasper timeout handling",
    )

return_marker = "FVR_FIX: separate candidate errors from infrastructure errors"
if return_marker not in jg_text:
    function_anchor = "def launch_jg_custom_equiv_check("
    next_function_anchor = "\ndef launch_jg_with_queue_custom_equiv_check("
    start = jg_text.find(function_anchor)
    end = jg_text.find(next_function_anchor, start)
    if start < 0 or end < 0:
        raise RuntimeError(
            "Cannot isolate launch_jg_custom_equiv_check. "
            "No source files were changed."
        )

    prefix = jg_text[:start]
    function_text = jg_text[start:end]
    suffix = jg_text[end:]

    nonzero_start = function_text.find("    if result.returncode != 0:")
    if nonzero_start < 0:
        raise RuntimeError(
            "Cannot find Jasper nonzero-return block. No source files were changed."
        )
    nonzero_end = function_text.find("\n\n", nonzero_start)
    if nonzero_end < 0:
        raise RuntimeError(
            "Cannot delimit Jasper nonzero-return block. No source files were changed."
        )

    old_nonzero_block = function_text[nonzero_start:nonzero_end]
    new_nonzero_block = '''    if result.returncode != 0:
        # FVR_FIX: separate candidate errors from infrastructure errors.
        # Syntax/elaboration errors are expected feedback for FVRuleLearner;
        # license failures and unexpected tool failures are still fatal.
        output_lower = jasper_output.lower()
        infrastructure_markers = (
            "failed to checkout license",
            "license checkout failed",
            "failed to contact license server",
            "license server machine is down",
            "no license available",
            "flexnet licensing error",
            "license manager daemon",
            "lmc-",
        )
        candidate_error_markers = (
            "syntax error",
            "[error (veri-",
            "error (enl",
            "ignored due to previous errors",
        )

        if any(marker in output_lower for marker in infrastructure_markers):
            raise RuntimeError(
                f"JasperGold infrastructure failure for task {task_id}; "
                f"return code={result.returncode}\\n{jasper_output}"
            )
        if not any(marker in output_lower for marker in candidate_error_markers):
            raise RuntimeError(
                f"Unexpected JasperGold failure for task {task_id}; "
                f"return code={result.returncode}\\n{jasper_output}"
            )

        print(
            f"WARNING: JasperGold candidate evaluation failed for task "
            f"{task_id}; recording syntax/functionality failure and continuing."
        )'''
    function_text = (
        function_text[:nonzero_start]
        + new_nonzero_block
        + function_text[nonzero_end:]
    )
    jg_text = prefix + function_text + suffix
    changes.append("Jasper candidate-vs-infrastructure failure policy")

updated[jg_path] = jg_text


# -------------------------------------------------------------------------
# 4. src/main.py historically catches top-level exceptions and exits 0.
#    Make the shell runner inspect persisted exceptions and required outputs.
# -------------------------------------------------------------------------
runner = updated[runner_path]
runner_marker = "FVR_FIX: reject incomplete train/inference phases"
if runner_marker not in runner:
    run_main_start = runner.find("run_main() {")
    analyze_start = runner.find("\nanalyze_train()", run_main_start)
    if run_main_start < 0 or analyze_start < 0:
        raise RuntimeError(
            "Cannot isolate run_main in run_gpt4o_reproduction.sh. "
            "No source files were changed."
        )
    prefix = runner[:run_main_start]
    run_main = runner[run_main_start:analyze_start]
    suffix = runner[analyze_start:]
    close_pos = run_main.rfind("\n}")
    if close_pos < 0:
        raise RuntimeError(
            "Cannot find the end of run_main. No source files were changed."
        )

    guards = '''

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
    if [[ "${stage}" == "inference" ]] && \
       ! compgen -G "${run_dir}/eval/*_jg.csv" >/dev/null; then
        echo "ERROR: inference finished without JasperGold evaluation CSV files." >&2
        return 1
    fi
'''
    run_main = run_main[:close_pos] + guards + run_main[close_pos:]
    runner = prefix + run_main + suffix
    changes.append("runner phase-completeness guards")

updated[runner_path] = runner


# Validate every proposed edit before writing any source file.
compile(updated[evaluation_path], str(evaluation_path), "exec")
compile(updated[jg_path], str(jg_path), "exec")

bash_check = subprocess.run(
    ["bash", "-n"],
    input=updated[runner_path],
    text=True,
    capture_output=True,
)
if bash_check.returncode != 0:
    raise RuntimeError(
        "Patched runner failed bash syntax validation:\n"
        + bash_check.stderr
        + "\nNo source files were changed."
    )

# Small regression test for the exact task 4_77_0 failure mode.
import re

lm_assertion = (
    "disable iff (tb_reset) "
    "((sig_E ^ sig_I) ^ ((sig_E ^ sig_F) ^ sig_J)) == 0"
)
ref_assertion = "((sig_E ^ sig_I) ^ ((sig_E ^ sig_F) ^ sig_J))"
signals = set(re.findall(r"\bsig_\w+", ref_assertion))
if re.search(r"\btb_reset\b", f"{lm_assertion} {ref_assertion}"):
    signals.add("tb_reset")
assert "tb_reset" in signals
assert signals == {"sig_E", "sig_I", "sig_F", "sig_J", "tb_reset"}

# Commit the already-validated contents atomically, one file at a time.
for path in paths:
    if updated[path] == original[path]:
        continue
    mode = path.stat().st_mode
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.fvr_fix.",
        dir=path.parent,
        text=True,
    )
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(updated[path])
        os.chmod(temp_path, mode)
        os.replace(temp_path, path)
    finally:
        if temp_path.exists():
            temp_path.unlink()

if changes:
    print("Applied fixes:")
    for change in changes:
        print(f"  - {change}")
else:
    print("All fixes were already present; no source files changed.")
PY

python3 -m py_compile \
    "${EVALUATION_FILE}" \
    "${JG_EXECUTION_FILE}"
bash -n "${RUNNER_FILE}"

grep -q "FVR_FIX: include valid reset used only by generated assertion" \
    "${EVALUATION_FILE}"
grep -q "FVR_FIX: recognize Jasper syntax and elaboration failures" \
    "${EVALUATION_FILE}"
grep -q "FVR_FIX: separate candidate errors from infrastructure errors" \
    "${JG_EXECUTION_FILE}"
grep -q "FVR_FIX: keep a single Jasper timeout local to its case" \
    "${JG_EXECUTION_FILE}"
grep -q "FVR_FIX: reject incomplete train/inference phases" \
    "${RUNNER_FILE}"

echo
echo "Patch complete."
echo "Repository: ${REPO_ROOT}"
echo "Backup:     ${BACKUP_DIR}"
echo
echo "Next validation command:"
echo "  bash scripts/run_gpt4o_reproduction.sh pilot 0"
echo
echo "Restore command (only if needed):"
echo "  cp -p '${BACKUP_DIR}/FVEval/fv_eval/evaluation.py' '${EVALUATION_FILE}'"
echo "  cp -p '${BACKUP_DIR}/FVEval/fv_eval/fv_tool_execution.py' '${JG_EXECUTION_FILE}'"
echo "  cp -p '${BACKUP_DIR}/scripts/run_gpt4o_reproduction.sh' '${RUNNER_FILE}'"
