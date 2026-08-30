#!/usr/bin/env bash
# Fix JasperGold 25.x TCL-echo false positives in FVRuleLearner.
#
# Usage:
#   bash fix_fvrulelearner_jasper_parser.sh REPO [GOLDEN_REPORT]
#
# GOLDEN_REPORT is the jasper_output.txt produced by the golden-vs-golden
# self-check.  Passing it is strongly recommended.

set -Eeuo pipefail

REPO_INPUT="${1:-/raid/spring2026/fwu44/research/SVA_FVRuleLearner}"
REPORT_INPUT="${2:-}"

[[ -d "${REPO_INPUT}" ]] || {
    echo "ERROR: repository not found: ${REPO_INPUT}" >&2
    exit 2
}

REPO="$(cd -- "${REPO_INPUT}" && pwd)"
cd "${REPO}"

EVALUATION="FVEval/fv_eval/evaluation.py"
EXECUTION="FVEval/fv_eval/fv_tool_execution.py"

for path in "${EVALUATION}" "${EXECUTION}"; do
    [[ -f "${path}" ]] || {
        echo "ERROR: required file missing: ${REPO}/${path}" >&2
        exit 2
    }
done

STAMP="$(date -u +%Y%m%dT%H%M%SZ)_$$"
BACKUP_DIR="${REPO}/patch_backups/jasper_parser_fix_${STAMP}"
mkdir -p "${BACKUP_DIR}/FVEval/fv_eval"

cp -p "${EVALUATION}" "${BACKUP_DIR}/${EVALUATION}"
cp -p "${EXECUTION}" "${BACKUP_DIR}/${EXECUTION}"
git diff --binary -- "${EVALUATION}" "${EXECUTION}" \
    > "${BACKUP_DIR}/before.patch"

echo "Backup: ${BACKUP_DIR}"

python3 - "${REPO}" "${REPORT_INPUT}" <<'PY'
from __future__ import annotations

import ast
import os
from pathlib import Path
import re
import sys
import tempfile

repo = Path(sys.argv[1])
report_arg = sys.argv[2]
evaluation_path = repo / "FVEval/fv_eval/evaluation.py"
execution_path = repo / "FVEval/fv_eval/fv_tool_execution.py"


def atomic_write(path: Path, content: str) -> None:
    mode = path.stat().st_mode
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
        os.chmod(temp_name, mode)
        os.replace(temp_name, path)
    except BaseException:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def replace_exact(text: str, old: str, new: str, expected: int, label: str) -> str:
    count = text.count(old)
    if count != expected:
        raise RuntimeError(
            f"Cannot safely patch {label}: expected {expected} exact block(s), "
            f"found {count}. No source files were written."
        )
    return text.replace(old, new)


evaluation = evaluation_path.read_text(encoding="utf-8")
execution = execution_path.read_text(encoding="utf-8")

eval_helper_marker = "FVR_JASPER_ECHO_FIX: ignore echoed TCL comments"
eval_import_anchor = (
    "from FVEval.fv_eval.data import LMResult, TextSimilarityEvaluationResult, "
    "JGEvaluationResult\n"
)
eval_helper = '''

# FVR_JASPER_ECHO_FIX: ignore echoed TCL comments.  JasperGold 25.x echoes
# lines such as "% # 1. Syntax error in the testbench" from the TCL file.
# That documentation text is not a compiler diagnostic.
def _has_real_jasper_syntax_error(jasper_out_str: str) -> bool:
    for line in jasper_out_str.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#") or re.match(r"^%\\s*#", stripped):
            continue
        if re.search(
            r"\\bERROR\\s+\\((?:VERI-[^)]+|ENL\\d+)\\)",
            line,
            flags=re.IGNORECASE,
        ):
            return True
        if re.search(
            r"\\bsyntax error\\b|ignored due to previous errors",
            line,
            flags=re.IGNORECASE,
        ):
            return True
    return False
'''

if eval_helper_marker not in evaluation:
    evaluation = replace_exact(
        evaluation,
        eval_import_anchor,
        eval_import_anchor + eval_helper,
        1,
        "evaluation helper insertion",
    )

simple_parser = '''        # check for syntax error
        syntax_error_match = re.findall(r"syntax error", jasper_out_str)
        if syntax_error_match:
'''
simple_replacement = '''        # Ignore documentation comments echoed from the TCL script.
        if _has_real_jasper_syntax_error(jasper_out_str):
'''
simple_parser_count = evaluation.count(simple_parser)
if simple_parser_count not in {0, 1, 2}:
    raise RuntimeError(
        f"Unexpected number of simple Jasper parser blocks: {simple_parser_count}"
    )
if simple_parser_count:
    # Upstream NVlabs uses the simple block for both Human and Machine.  The
    # current reproduction fork has an expanded Machine block, leaving one
    # simple Human block.
    evaluation = replace_exact(
        evaluation,
        simple_parser,
        simple_replacement,
        simple_parser_count,
        "human/upstream-machine Jasper parser",
    )

opencore_parser = '''        # check for syntax error
        syntax_error_match = re.findall(r"syntax error", jasper_out_str)
        
        # 1126
        # check for assumption conflict errors (EAS001, ERS055)
        # assumption_conflict = re.search(r"ERROR \\((EAS001|ERS055)\\)", jasper_out_str)
        
        if syntax_error_match: # or assumption_conflict:
'''
opencore_replacement = '''        # Ignore documentation comments echoed from the TCL script.
        if _has_real_jasper_syntax_error(jasper_out_str):
'''
if opencore_parser in evaluation:
    evaluation = replace_exact(
        evaluation,
        opencore_parser,
        opencore_replacement,
        1,
        "OpenCore Jasper parser",
    )

machine_parser = '''        # FVR_FIX: recognize Jasper syntax and elaboration failures.
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
machine_replacement = '''        # Ignore documentation comments echoed from the TCL script while
        # retaining real VERI/ENL/syntax diagnostics.
        if _has_real_jasper_syntax_error(jasper_out_str):
'''
if machine_parser in evaluation:
    evaluation = replace_exact(
        evaluation,
        machine_parser,
        machine_replacement,
        1,
        "machine Jasper parser",
    )

if evaluation.count("if _has_real_jasper_syntax_error(jasper_out_str):") < 3:
    raise RuntimeError("Not all concrete Jasper metric parsers use the safe helper")

exec_helper_marker = "FVR_JASPER_ECHO_FIX: return only real diagnostic lines"
exec_anchor = "print = saver.log_info\n"
exec_helper = '''

# FVR_JASPER_ECHO_FIX: return only real diagnostic lines.  Do not classify
# echoed comments from run_jg_*.tcl as candidate syntax failures.
def _real_jasper_diagnostic_lines(jasper_out_str: str) -> list[str]:
    diagnostics = []
    for line in jasper_out_str.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#") or re.match(r"^%\\s*#", stripped):
            continue
        if re.search(
            r"\\bERROR\\s+\\((?:VERI-[^)]+|ENL\\d+)\\)"
            r"|\\bsyntax error\\b"
            r"|ignored due to previous errors",
            line,
            flags=re.IGNORECASE,
        ):
            diagnostics.append(line)
    return diagnostics
'''

old_candidate_block = '''        candidate_error_markers = (
            "syntax error",
            "[error (veri-",
            "error (enl",
            "ignored due to previous errors",
        )

        if any(marker in output_lower for marker in infrastructure_markers):
'''
new_candidate_block = '''        candidate_diagnostics = _real_jasper_diagnostic_lines(jasper_output)

        if any(marker in output_lower for marker in infrastructure_markers):
'''
has_nonzero_classifier = (
    old_candidate_block in execution
    or "candidate_diagnostics = _real_jasper_diagnostic_lines(jasper_output)" in execution
)
if has_nonzero_classifier and exec_helper_marker not in execution:
    execution = replace_exact(
        execution,
        exec_anchor,
        exec_anchor + exec_helper,
        1,
        "Jasper execution helper insertion",
    )

if old_candidate_block in execution:
    execution = replace_exact(
        execution,
        old_candidate_block,
        new_candidate_block,
        1,
        "candidate diagnostic extraction",
    )

old_candidate_condition = '''        if not any(marker in output_lower for marker in candidate_error_markers):
            raise RuntimeError(
                f"Unexpected JasperGold failure for task {task_id}; "
                f"return code={result.returncode}\\n{jasper_output}"
            )

        print(
            f"WARNING: JasperGold candidate evaluation failed for task "
            f"{task_id}; recording syntax/functionality failure and continuing."
        )
'''
new_candidate_condition = '''        if not candidate_diagnostics:
            raise RuntimeError(
                f"Unexpected JasperGold failure for task {task_id}; "
                f"return code={result.returncode}\\n{jasper_output}"
            )

        print(
            f"WARNING: JasperGold candidate evaluation failed for task "
            f"{task_id}; recording syntax/functionality failure and continuing.\\n"
            + "\\n".join(candidate_diagnostics[:20])
        )
'''
if old_candidate_condition in execution:
    execution = replace_exact(
        execution,
        old_candidate_condition,
        new_candidate_condition,
        1,
        "nonzero Jasper failure classification",
    )

if has_nonzero_classifier and "candidate_error_markers" in execution:
    raise RuntimeError("Legacy raw substring candidate-error classifier remains")
if (
    has_nonzero_classifier
    and "candidate_diagnostics = _real_jasper_diagnostic_lines(jasper_output)" not in execution
):
    raise RuntimeError("Safe nonzero-return classifier was not installed")

# Validate both complete modules before writing either one.
compile(evaluation, str(evaluation_path), "exec")
compile(execution, str(execution_path), "exec")

# Execute the actual helper function AST in isolation for deterministic tests.
tree = ast.parse(evaluation, filename=str(evaluation_path))
helper_node = next(
    node
    for node in tree.body
    if isinstance(node, ast.FunctionDef)
    and node.name == "_has_real_jasper_syntax_error"
)
namespace = {"re": re}
exec(compile(ast.Module(body=[helper_node], type_ignores=[]), str(evaluation_path), "exec"), namespace)
has_error = namespace["_has_real_jasper_syntax_error"]

successful_echo = """% # 1. Syntax error in the testbench
[INFO (VERI-1018)] compiling module 'dummy'
Full equivalence between
"""
real_veri_error = "[ERROR (VERI-1234)] syntax error near token"
real_enl_error = "[ERROR (ENL034)] design elaboration failed"

assert has_error(successful_echo) is False
assert has_error(real_veri_error) is True
assert has_error(real_enl_error) is True

# Exercise every concrete metric method without importing the repository's
# optional runtime dependencies.  The standard human/machine paths must also
# recognize the successful result as functionally correct; OpenCore uses a
# different multi-property counting rule, so only its syntax verdict is shared.
concrete_metric_methods = []
for class_node in (node for node in tree.body if isinstance(node, ast.ClassDef)):
    for method_node in class_node.body:
        if (
            isinstance(method_node, ast.FunctionDef)
            and method_node.name in {"calculate_jg_metric", "calculate_jg_metric_opencore"}
            and any(isinstance(node, ast.Return) for node in ast.walk(method_node))
        ):
            concrete_metric_methods.append((class_node.name, method_node))

if len(concrete_metric_methods) != 3:
    raise RuntimeError(
        f"Expected 3 concrete Jasper metric methods, found {len(concrete_metric_methods)}"
    )

for class_name, method_node in concrete_metric_methods:
    method_namespace = {"re": re, "_has_real_jasper_syntax_error": has_error}
    exec(
        compile(
            ast.Module(body=[method_node], type_ignores=[]),
            str(evaluation_path),
            "exec",
        ),
        method_namespace,
    )
    metric = method_namespace[method_node.name](object(), successful_echo)
    assert metric["syntax"] == 1.0, (class_name, method_node.name, metric)
    if method_node.name == "calculate_jg_metric":
        assert metric["functionality"] == 1.0, (class_name, method_node.name, metric)

if report_arg:
    report_path = Path(report_arg).expanduser().resolve()
    if not report_path.is_file():
        raise RuntimeError(f"Golden report not found: {report_path}")
    report_text = report_path.read_text(encoding="utf-8", errors="replace")
    if "Full equivalence" not in report_text:
        raise RuntimeError("Golden report lacks 'Full equivalence'")
    if has_error(report_text):
        raise RuntimeError("Golden report contains a real Jasper diagnostic")
    for class_name, method_node in concrete_metric_methods:
        method_namespace = {"re": re, "_has_real_jasper_syntax_error": has_error}
        exec(
            compile(
                ast.Module(body=[method_node], type_ignores=[]),
                str(evaluation_path),
                "exec",
            ),
            method_namespace,
        )
        metric = method_namespace[method_node.name](object(), report_text)
        assert metric["syntax"] == 1.0, (class_name, method_node.name, metric)
        if method_node.name == "calculate_jg_metric":
            assert metric["functionality"] == 1.0, (class_name, method_node.name, metric)
    print(f"Golden report parser check: PASS ({report_path})")

atomic_write(evaluation_path, evaluation)
atomic_write(execution_path, execution)

print("Patched:")
print(f"  {evaluation_path.relative_to(repo)}")
print(f"  {execution_path.relative_to(repo)}")
print("Synthetic parser tests: PASS")
PY

python3 -m py_compile "${EVALUATION}" "${EXECUTION}"

grep -n \
    'FVR_JASPER_ECHO_FIX\|_has_real_jasper_syntax_error\|_real_jasper_diagnostic_lines' \
    "${EVALUATION}" "${EXECUTION}"

git diff --check -- "${EVALUATION}" "${EXECUTION}"
git diff -- "${EVALUATION}" "${EXECUTION}" \
    > "${BACKUP_DIR}/after.patch"

echo
echo "Jasper parser fix applied successfully."
echo "Backup: ${BACKUP_DIR}"
echo "Next: rerun the golden parser check, then a one-case smoke test."
