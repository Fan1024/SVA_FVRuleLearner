"""Evaluate assertions with FVRuleLearner's supplied FVEval/PEC checker.

Both complete assertions are compiled in the testbench first. The original
PEC helper then compares Human property bodies or Machine expressions after
the clock event. This module prepares inputs and parses the helper's verdict;
it does not implement an alternative equivalence proof.
"""

import re
import shutil
import subprocess
import tempfile
from pathlib import Path


COMPARISON_SCOPE = (
    "Use FVRuleLearner's supplied PEC checker and the dataset's comparison scope. "
    "Complete assertions must compile in the testbench. Only recommend changes "
    "that correct syntax or behavior within the supplied scope; harmless "
    "formatting differences do not require correction."
)


def get_evaluation_policy(dataset: str) -> dict:
    """Match the expression scope used by the original dataset evaluators."""
    if dataset == "nl2sva_human":
        scope = (
            "Human PEC compares property bodies only. Clock events and disable iff "
            "wrappers are excluded from equivalence comparison, but the complete "
            "assertions must compile. Do not recommend wrapper edits solely to "
            "resolve a PEC mismatch. Reset-related conditions inside the body "
            "remain in scope."
        )
    elif dataset == "nl2sva_machine":
        scope = (
            "Machine PEC compares the property expression after the clock event, "
            "including any disable iff condition. Clock events are excluded from "
            "equivalence comparison, but the complete assertions must compile. "
            "Do not recommend clock edits solely to resolve a PEC mismatch. "
            "Do not invent reset conditions when the task does not require them."
        )
    else:
        raise ValueError("DATASET must be 'nl2sva_human' or 'nl2sva_machine'.")
    return {
        "scope": scope,
        "include_reset": dataset == "nl2sva_machine",
        "tcl_file": f"run_jg_{dataset}.tcl",
    }


def _without_comments(text: str) -> str:
    """Remove comments while preserving strings and character positions."""
    return re.sub(
        r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
        lambda match: match[0] if match[0].startswith('"') else " " * len(match[0]),
        text,
        flags=re.DOTALL,
    )


def _parenthesized(text: str) -> tuple[str, str]:
    """Read one balanced (...) group, returning its content and remaining text."""
    text = text.lstrip()
    if not text.startswith("("):
        raise ValueError("Expected a parenthesized expression.")
    depth = 0
    in_string = False
    escaped = False
    for index, character in enumerate(text):
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return text[1:index].strip(), text[index + 1:].strip()
    raise ValueError("Unbalanced parentheses in the assertion.")


def _assertion_parts(text: str) -> tuple[str, str, str, str]:
    """Return the assertion, expression after clock, body, and reset text.

    Balanced parentheses allow reset expressions such as !reset_ or a || b.
    The complete assertion is preserved for compilation.
    """
    assertion = re.sub(
        r"^\s*[A-Za-z_]\w*\s*:\s*", "", _without_comments(text).strip(),
    )
    header = re.match(r"assert\s+property\b", assertion)
    if header is None:
        raise ValueError("Expected exactly one assert property (...) statement.")
    specification, trailing = _parenthesized(assertion[header.end():])
    if not specification or trailing != ";":
        raise ValueError("Expected exactly one assert property (...) statement.")

    expression = specification
    if expression.startswith("@"):
        _, expression = _parenthesized(expression[1:])
    body = expression
    disable = re.match(r"disable\s+iff\b", expression)
    reset = ""
    if disable:
        reset, body = _parenthesized(expression[disable.end():])
        if not reset or not body:
            raise ValueError("Expected a disable iff condition followed by a property body.")
    if not body:
        raise ValueError("Expected a nonempty property body.")
    return assertion, expression, body, reset


def _prepare_formal_input(
    generated_assertion: str,
    reference_assertion: str,
    testbench: str,
    requirement: str,
    destination: Path,
    *,
    dataset: str,
) -> dict:
    """Compile full assertions and select the original PEC expressions/signals."""
    policy = get_evaluation_policy(dataset)
    try:
        candidate, candidate_expression, candidate_body, candidate_reset = (
            _assertion_parts(generated_assertion)
        )
    except ValueError as error:
        raise ValueError(f"Generated assertion: {error}") from error
    try:
        reference, reference_expression, reference_body, reference_reset = (
            _assertion_parts(reference_assertion)
        )
    except ValueError as error:
        raise ValueError(f"Reference assertion: {error}") from error

    if not policy["include_reset"]:
        candidate_expression = candidate_body
        reference_expression = reference_body

    # Follow the original evaluators' signal-list construction.
    if dataset == "nl2sva_human":
        signals = set(re.findall(r"'([^'\s]+)'", requirement))
        parameters = re.findall(
            r"\b(parameter|localparam)\s+(int\s+|real\s+|bit\s+|\[[^]]+\]\s*)?(\w+)",
            testbench,
        )
        signals.update(match[2] for match in parameters)
    else:
        signals = set(re.findall(r"\bsig_\w+", reference_assertion))

    clean_testbench = _without_comments(testbench)
    modules = re.findall(r"\bmodule\s+([A-Za-z_]\w*)\b", clean_testbench)
    endings = list(re.finditer(r"\bendmodule\b", clean_testbench))
    if len(modules) != 1 or len(endings) != 1 or clean_testbench[endings[0].end():].strip():
        raise ValueError("Expected a testbench with one module ending in endmodule.")
    insertion = endings[0].start()
    destination.write_text(
        testbench[:insertion]
        + "\nreference: " + reference
        + "\nasrt: " + candidate + "\n"
        + testbench[insertion:],
        encoding="utf-8",
    )
    return {
        "candidate_expression": candidate_expression,
        "reference_expression": reference_expression,
        "signal_list": ",".join(sorted(signals)),
        "generated_reset": candidate_reset,
        "reference_reset": reference_reset,
        # Textual information only. Equivalent aliases can differ here.
        "reset_mismatch": candidate_reset != reference_reset,
    }


def _parse_formal_result(output: str, returncode: int) -> dict:
    """Map the supplied PEC helper's explicit verdict to the existing scores."""
    lines = [
        line for line in output.splitlines()
        if not line.lstrip().startswith("#")
        and not re.match(r"^\s*%\s*#", line)
    ]
    text = "\n".join(lines)
    lower = text.lower()
    infrastructure_markers = (
        "failed to checkout license", "license checkout failed",
        "failed to contact license server", "license server machine is down",
        "no license available", "flexnet licensing error",
        "license manager daemon", "lmc-",
    )
    if any(marker in lower for marker in infrastructure_markers):
        return {"status": "TOOL_ERROR"}
    if re.search(
        r"\bERROR\s+\((?:VERI-[^)]+|ENL\d+)\)"
        r"|\bsyntax error\b|ignored due to previous errors",
        text, flags=re.IGNORECASE,
    ):
        return {
            "status": "SYNTAX_ERROR",
            "syntax": 0.0, "pec": 0.0, "relax_pec": 0.0,
        }
    if returncode != 0:
        return {"status": "TOOL_ERROR"}

    if re.search(r"^\s*Full equivalence between\b", text, re.MULTILINE):
        return {
            "status": "FULL_EQUIVALENCE",
            "syntax": 1.0, "pec": 1.0, "relax_pec": 1.0,
        }
    if re.search(r"^\s*implies\s*$", text, re.MULTILINE):
        return {"status": "IMPLIES", "syntax": 1.0, "pec": 0.0, "relax_pec": 1.0}
    if re.search(
        r"^\s*(?:No equivalence between\b|conflict with each other\b)",
        text, re.MULTILINE,
    ):
        return {
            "status": "NO_EQUIVALENCE",
            "syntax": 1.0, "pec": 0.0, "relax_pec": 0.0,
        }
    return {"status": "INCONCLUSIVE"}


def _finish_result(result: dict, output: str) -> dict:
    """Keep the full log, but send a concise report to the diagnosis model."""
    result["tool_output"] = output
    Path(result["log_path"]).write_text(output, encoding="utf-8")
    useful_lines = [
        line for line in output.splitlines()
        if not line.lstrip().startswith("#")
        and not re.match(r"^\s*%\s*#", line)
        and re.search(
            r"ERROR|syntax error|equivalence|implies|conflict|"
            r"TIMEOUT|license|not found|Expected|Missing",
            line, flags=re.IGNORECASE,
        )
    ]
    details = "\n".join(useful_lines) or output[-4000:]
    result["feedback"] = (
        f"Formal status: {result['status']}\n"
        f"Syntax: {result['syntax']}; strict PEC: {result['pec']}; "
        f"relaxed PEC: {result['relax_pec']}\n"
        f"Generated reset: {result['generated_reset'] or '(none)'}\n"
        f"Reference reset: {result['reference_reset'] or '(none)'}\n"
        f"Reset text differs: {result['reset_mismatch']} (informational only)\n"
        f"Comparison scope: {result['comparison_scope']}\n"
        f"Tool details:\n{details[:6000]}"
    )
    return result


def evaluate_assertion(
    generated_assertion: str,
    reference_assertion: str,
    testbench: str,
    requirement: str,
    run_dir=None,
    timeout_seconds: float = 300,
    fveval_dir=None,
    jg_executable: str = "jg",
    task_id: str = "case",
    dataset: str = "nl2sva_human",
) -> dict:
    """Invoke the original FVEval Tcl driver and its supplied PEC helper."""
    policy = get_evaluation_policy(dataset)
    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive.")
    if not isinstance(task_id, str) or not task_id.strip():
        raise ValueError("task_id must be a nonempty string.")
    source_task_id = task_id
    task_id = re.sub(r"[^A-Za-z0-9_-]+", "_", task_id).strip("_") or "case"
    if run_dir is None:
        root = Path(__file__).resolve().parent / "runs"
        root.mkdir(parents=True, exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix=f"{task_id}_", dir=root))
    else:
        directory = Path(run_dir).expanduser().resolve()
        directory.mkdir(parents=True, exist_ok=True)
    work = directory / "_work"
    work.mkdir()
    (work / "checker_owned.marker").write_text(str(directory), encoding="utf-8")
    sv_file = directory / "formal_input.sva"
    result = {
        "status": "INPUT_ERROR",
        "syntax": None, "pec": None, "relax_pec": None,
        "generated_reset": "", "reference_reset": "",
        "reset_mismatch": None,
        "comparison_scope": policy["scope"],
        "run_dir": str(directory),
        "work_dir": str(work),
        "log_path": str(directory / "jasper.log"),
        "input_path": str(sv_file),
        "returncode": None,
        "source_task_id": source_task_id,
        "tool_task_id": task_id,
    }
    try:
        prepared = _prepare_formal_input(
            generated_assertion, reference_assertion, testbench, requirement, sv_file,
            dataset=dataset,
        )
    except ValueError as error:
        return _finish_result(result, str(error))
    for key in ("generated_reset", "reference_reset", "reset_mismatch"):
        result[key] = prepared[key]

    result["comparison_inputs"] = {
        name: prepared[name]
        for name in ("candidate_expression", "reference_expression", "signal_list")
    }
    # FVEval's scripts resolve pec/pec.tcle relative to this working directory.
    if fveval_dir is None:
        fveval = next(
            (parent / "FVEval" for parent in Path(__file__).resolve().parents
             if (parent / "FVEval").is_dir()),
            None,
        )
    else:
        fveval = Path(fveval_dir).expanduser().resolve()
    if fveval is None:
        result["status"] = "TOOL_ERROR"
        return _finish_result(
            result,
            "FVEval not found. Keep new_agent inside the repository or supply fveval_dir.",
        )
    tcl_file = fveval / "tool_scripts" / policy["tcl_file"]
    for required in (tcl_file, fveval / "tool_scripts" / "pec" / "pec.tcle"):
        if not required.is_file():
            result["status"] = "TOOL_ERROR"
            return _finish_result(result, f"Missing required file: {required}")

    shutil.copyfile(sv_file, work / f"{dataset}_{task_id}.sva")
    project = work / "jg" / task_id
    project.parent.mkdir()
    command = [
        str(jg_executable), "-fpv", "-batch", "-tcl", str(tcl_file),
        "-define", "LM_ASSERT_TEXT", prepared["candidate_expression"],
        "-define", "REF_ASSERT_TEXT", prepared["reference_expression"],
        "-define", "SIGNAL_LIST", prepared["signal_list"],
        "-define", "EXP_ID", dataset,
        "-define", "TASK_ID", task_id,
        "-define", "SV_DIR", str(work),
        "-proj", str(project), "-allow_unsupported_OS",
    ]
    result["command"] = command
    result["working_directory"] = str(fveval)
    try:
        completed = subprocess.run(
            command, cwd=fveval, capture_output=True, text=True, timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as error:
        result["status"] = "TIMEOUT"
        partial = []
        for part in (error.stdout, error.stderr):
            if isinstance(part, bytes):
                part = part.decode(errors="replace")
            if part:
                partial.append(part)
        output = "\n".join(partial)
        output += f"\nJASPER_TIMEOUT: exceeded {timeout_seconds} seconds"
        return _finish_result(result, output)
    except OSError as error:
        result["status"] = "TOOL_ERROR"
        return _finish_result(result, str(error))

    output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
    result["returncode"] = completed.returncode
    result.update(_parse_formal_result(output, completed.returncode))
    return _finish_result(result, output)


def cleanup_work(
    result: dict, keep_work: bool = False, *, preserve_unresolved: bool = True,
) -> dict:
    """Delete owned work; optionally retain unresolved checks for debugging."""
    work = Path(result["work_dir"])
    if not work.exists() and not work.is_symlink():
        return {"retained": False, "reason": "No work directory remains."}
    if keep_work:
        return {"retained": True, "reason": "KEEP_WORK is enabled."}
    if preserve_unresolved and result["status"] not in {
        "FULL_EQUIVALENCE", "IMPLIES", "NO_EQUIVALENCE", "SYNTAX_ERROR",
    }:
        return {
            "retained": True,
            "reason": "Retained for an unresolved tool or input result.",
        }

    directory = Path(result["run_dir"]).resolve()
    try:
        marker = work / "checker_owned.marker"
        if (
            work.is_symlink()
            or work.name != "_work"
            or work.resolve().parent != directory
            or not marker.is_file()
            or marker.read_text(encoding="utf-8") != str(directory)
        ):
            return {
                "retained": True,
                "reason": "Ownership check failed; no files were deleted.",
            }
        shutil.rmtree(work)
    except OSError as error:
        return {"retained": True, "reason": f"Cleanup failed: {error}"}
    return {"retained": False, "reason": "Owned work files removed."}


