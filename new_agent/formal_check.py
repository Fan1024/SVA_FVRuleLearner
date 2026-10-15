"""Check one selected NL2SVA-Human case.

Reuses FVEval/tool_scripts/run_jg_nl2sva_human.tcl and pec/pec.tcle.
Preserves syntax/strict/relaxed score categories for recognized tool results.
Human PEC compares property bodies; clock/reset wrappers are not compared.
This starter supports one assert property (@(posedge clk) ...) statement and
an optional disable iff with one reset signal. Unsupported input is reported,
rather than assigned a formal syntax-failure score.
"""

import re
import shutil
import subprocess
import tempfile
from pathlib import Path


CHECKER_NAME = "nl2sva_human"

COMPARISON_SCOPE = (
    "Original NL2SVA-Human PEC: property bodies only; "
    "clock/reset wrappers are removed before PEC. "
    "The complete assertions are compiled first. "
    "Reset mismatch is reported separately."
)


def _assertion_parts(text: str) -> tuple[str, str, str]:
    """Return the unlabeled assertion, property body, and reset signal."""
    # Comments must not hide extra statements or look like property delimiters.
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.DOTALL)
    assertion = re.sub(r"^\s*[A-Za-z_]\w*\s*:\s*", "", text.strip())
    match = re.fullmatch(
        r"assert\s+property\s*\(\s*@\s*\(\s*posedge\s+clk\s*\)\s*"
        r"(?:disable\s+iff\s*\(\s*(?P<reset>[A-Za-z_]\w*)\s*\)\s*)?"
        r"(?P<body>.*?)\s*\)\s*;\s*",
        assertion,
        flags=re.DOTALL,
    )
    if not match or not match.group("body").strip():
        raise ValueError(
            "This starter expects one assert property (@(posedge clk) "
            "[disable iff (RESET_SIGNAL)] BODY); statement."
        )
    body = match.group("body").strip()
    if ";" in body:
        raise ValueError("Expected exactly one assertion; extra statements are unsupported.")
    if re.match(r"disable\s+iff\b", body):
        raise ValueError("Only disable iff (RESET_SIGNAL) with one signal is supported.")
    return assertion, body, match.group("reset") or ""


def _prepare_formal_input(
    generated_assertion: str,
    reference_assertion: str,
    testbench: str,
    requirement: str,
    destination: Path,
) -> dict:
    """Package full assertions; extract bodies and signal names for PEC."""
    candidate, candidate_body, candidate_reset = _assertion_parts(
        generated_assertion
    )
    reference, reference_body, reference_reset = _assertion_parts(
        reference_assertion
    )
    before_end, end, after_end = testbench.rpartition("endmodule")
    if not end or after_end.strip() or re.search(r"\bendmodule\b", before_end):
        raise ValueError("This starter expects a testbench with one module.")

    destination.write_text(
        before_end
        + "\n\nreference: " + reference
        + "\n\nasrt: " + candidate
        + "\nendmodule\n",
        encoding="utf-8",
    )

    # Start with the quoted signals and parameters used by the original flow.
    signals = set(re.findall(r"'([^'\s]+)'", requirement))
    declarations = re.findall(
        r"\b(input|output|inout|wire|reg|logic|parameter|localparam)\s+"
        r"(?:(?:signed|unsigned|int|integer|real|bit|logic)\s+)*"
        r"(?:\[[^]]+\]\s*)?([A-Za-z_]\w*)",
        testbench,
    )
    used_names = set(
        re.findall(r"\b[A-Za-z_]\w*\b", candidate_body + " " + reference_body)
    )
    for kind, name in declarations:
        if kind in {"parameter", "localparam"} or name in used_names:
            signals.add(name)

    return {
        "candidate_body": candidate_body,
        "reference_body": reference_body,
        "signal_list": ",".join(sorted(signals)),
        "generated_reset": candidate_reset,
        "reference_reset": reference_reset,
        "reset_mismatch": candidate_reset != reference_reset,
    }


def _parse_formal_result(output: str, returncode: int) -> dict:
    """Apply the original score categories to recognized completed results."""
    # Tcl comments can mention errors without reporting a real error.
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

    syntax_error = re.search(
        r"\bERROR\s+\((?:VERI-[^)]+|ENL\d+)\)"
        r"|\bsyntax error\b|ignored due to previous errors",
        text,
        flags=re.IGNORECASE,
    )
    if syntax_error:
        return {
            "status": "SYNTAX_ERROR",
            "syntax": 0.0, "pec": 0.0, "relax_pec": 0.0,
        }

    if returncode != 0 or not re.search(r"\bTASK_ID\b", text):
        return {"status": "TOOL_ERROR"}
    if "Full equivalence" in text:
        return {
            "status": "FULL_EQUIVALENCE",
            "syntax": 1.0, "pec": 1.0, "relax_pec": 1.0,
        }
    if re.search(r"\bimplies\b", text):
        return {
            "status": "IMPLIES",
            "syntax": 1.0, "pec": 0.0, "relax_pec": 1.0,
        }
    if "No equivalence between" in text or "conflict with each other" in text:
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
            r"TIMEOUT|license|not found|expects|Missing",
            line,
            flags=re.IGNORECASE,
        )
    ]
    details = "\n".join(useful_lines) or output[-4000:]
    result["feedback"] = (
        f"Formal status: {result['status']}\n"
        f"Syntax: {result['syntax']}; strict PEC: {result['pec']}; "
        f"relaxed PEC: {result['relax_pec']}\n"
        f"Generated reset: {result['generated_reset'] or '(none)'}\n"
        f"Reference reset: {result['reference_reset'] or '(none)'}\n"
        f"Reset mismatch: {result['reset_mismatch']}\n"
        f"Comparison scope: {COMPARISON_SCOPE}\n"
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
) -> dict:
    """Evaluate one assertion and return scores, feedback, and log paths."""
    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive.")
    if not isinstance(task_id, str) or not task_id.strip():
        raise ValueError("task_id must be a nonempty string.")
    source_task_id = task_id
    task_id = re.sub(r"[^A-Za-z0-9_-]+", "_", task_id).strip("_") or "case"

    # Keep the permanent input/log outside the disposable tool directory.
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
        "comparison_scope": COMPARISON_SCOPE,
        "run_dir": str(directory),
        "work_dir": str(work),
        "log_path": str(directory / "jasper.log"),
        "input_path": str(sv_file),
        "returncode": None,
        "source_task_id": source_task_id,
        "tool_task_id": task_id,
    }

    experiment_id = CHECKER_NAME
    try:
        prepared = _prepare_formal_input(
            generated_assertion, reference_assertion,
            testbench, requirement, sv_file,
        )
    except ValueError as error:
        return _finish_result(result, str(error))
    for key in ("generated_reset", "reference_reset", "reset_mismatch"):
        result[key] = prepared[key]
    result["comparison_inputs"] = {
        key: prepared[key]
        for key in ("candidate_body", "reference_body", "signal_list")
    }
    tool_sv_file = work / f"{experiment_id}_{task_id}.sva"
    shutil.copyfile(sv_file, tool_sv_file)

    # Locate FVEval whether this file is in new_agent/ or new_agent/src/.
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
            result, "FVEval not found. Place this file inside your repository "
            "or supply fveval_dir explicitly."
        )

    tcl_file = fveval / "tool_scripts" / "run_jg_nl2sva_human.tcl"
    pec_file = fveval / "tool_scripts" / "pec" / "pec.tcle"
    for required_file in (tcl_file, pec_file):
        if not required_file.is_file():
            result["status"] = "TOOL_ERROR"
            return _finish_result(result, f"Missing required file: {required_file}")

    project = work / "jg" / task_id
    project.parent.mkdir()
    command = [
        str(jg_executable), "-fpv", "-batch", "-tcl", str(tcl_file),
        "-define", "LM_ASSERT_TEXT", prepared["candidate_body"],
        "-define", "REF_ASSERT_TEXT", prepared["reference_body"],
        "-define", "SIGNAL_LIST", prepared["signal_list"],
        "-define", "EXP_ID", experiment_id,
        "-define", "TASK_ID", task_id,
        "-define", "SV_DIR", str(work),
        "-proj", str(project),
        "-allow_unsupported_OS",
    ]
    result["command"] = command
    result["working_directory"] = str(fveval)
    try:
        completed = subprocess.run(
            command, cwd=fveval, capture_output=True,
            text=True, timeout=timeout_seconds,
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

    output = "\n".join(
        part for part in (completed.stdout, completed.stderr) if part
    )
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

