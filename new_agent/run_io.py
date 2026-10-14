"""Manage experiment records, file saving, and execution finalization.

This module does not generate assertions or interpret formal scores.
The workflow and the optional cleanup function are supplied by main.py.
"""

import json
import re
import traceback
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


RUN_TIMEZONE = ZoneInfo("America/New_York")  # Baltimore, including daylight saving.


def local_now() -> str:
    """Return a readable timestamp in Baltimore local time."""
    return datetime.now(RUN_TIMEZONE).strftime("%Y-%m-%d %H:%M:%S")


def create_run(case_id: str, runs_root=None) -> Path:
    """Create one timestamped folder for one pipeline execution."""
    if not re.fullmatch(r"[A-Za-z0-9_-]+", case_id):
        raise ValueError("case_id must contain only letters, digits, _ or -.")
    root = (
        Path(runs_root).expanduser().resolve()
        if runs_root is not None
        else Path(__file__).resolve().parent / "runs"
    )
    root.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(RUN_TIMEZONE).strftime("%Y%m%d_%H%M%S_%f")
    run_dir = root / f"{timestamp}_{case_id}"
    run_dir.mkdir()
    return run_dir


def create_record(
    case_id: str,
    model,
    inputs: dict,
    prompts: dict,
    settings: dict,
) -> dict:
    """Create the common record used by main.py and the standalone checker."""
    return {
        "case_id": case_id,
        "model": model,
        "started_at": local_now(),
        "finished_at": None,
        "status": "RUNNING",
        "stage": "initialization",
        "settings": settings,
        "inputs": inputs,
        "prompts": prompts,
        "generation": {"raw_response": None, "assertion": None},
        "formal": None,
        "diagnosis": None,
        "statements": {},
        "diagnosis_skipped_reason": None,
        "error": None,
    }


def _atomic_write(path: Path, text: str) -> None:
    """Replace a text file after its complete contents have been written."""
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def _readable_report(record: dict) -> str:
    """Build the report to open first when inspecting an experiment."""
    lines = [
        f"Case: {record['case_id']}",
        f"Model: {record['model'] or '(not used)'}",
        f"Pipeline status: {record['status']}",
        f"Stage: {record['stage']}",
        f"Started: {record['started_at']}",
        f"Finished: {record['finished_at'] or '(not finished)'}",
        "",
        "REQUIREMENT",
        record["inputs"]["requirement"],
        "",
        "GENERATED ASSERTION",
        record["generation"]["assertion"] or "(no extracted assertion)",
        "",
        "REFERENCE ASSERTION",
        record["inputs"]["reference_assertion"],
        "",
        "FORMAL RESULT",
    ]
    formal = record["formal"]
    if formal is None:
        lines.append("(not run)")
    else:
        for key in (
            "status", "syntax", "pec", "relax_pec",
            "generated_reset", "reference_reset", "reset_mismatch",
            "comparison_scope", "log_path", "input_path",
        ):
            value = formal.get(key)
            lines.append(f"{key}: {value if value is not None else '(unavailable)'}")
        cleanup = formal.get("cleanup")
        if cleanup:
            lines.append(f"Work directory retained: {cleanup['retained']}")
            lines.append(f"Cleanup note: {cleanup['reason']}")

    lines.extend(["", "FORMATTED DIAGNOSIS"])
    if record["diagnosis_skipped_reason"]:
        lines.append(record["diagnosis_skipped_reason"])
    elif record["statements"]:
        for name, statement in record["statements"].items():
            lines.append(f"{name}: {statement}")
    elif record["diagnosis"] is not None:
        lines.append("(no answers passed the formatting filters)")
    else:
        lines.append("(not run)")

    if record["error"]:
        error = record["error"]
        lines.extend([
            "", "PIPELINE ERROR",
            f"Stage: {error['stage']}",
            f"{error['type']}: {error['message']}",
            error.get("traceback", ""),
        ])
    lines.extend([
        "",
        "Open result.json for prompts, raw model output, and complete Jev answers.",
        "Open jasper.log for the captured tool output, if formal checking ran.",
    ])
    return "\n".join(lines) + "\n"


def save_run(run_dir, record: dict) -> None:
    """Save both views without duplicating the Jasper log inside JSON."""
    directory = Path(run_dir)
    saved = dict(record)
    if record["formal"] is not None:
        saved["formal"] = {
            key: value for key, value in record["formal"].items()
            if key != "tool_output"
        }
    _atomic_write(
        directory / "result.json",
        json.dumps(saved, indent=2, ensure_ascii=False) + "\n",
    )
    _atomic_write(directory / "report.txt", _readable_report(record))


def update_run(run_dir, record: dict, **changes) -> None:
    """Update top-level record fields and save a checkpoint.

    For example, update_run(directory, record, stage="formal_check").
    A supplied dictionary replaces that whole field; it is not merged deeply.
    """
    record.update(changes)
    save_run(run_dir, record)


def run_experiment(
    workflow,
    *,
    case_id: str,
    model,
    inputs: dict,
    prompts: dict,
    settings: dict,
    cleanup_work=None,
) -> int:
    """Run workflow(directory, record), save failures, and finalize the run.

    workflow returns the program exit code: 0 for normal completion, 1 for
    an unresolved checker. Unexpected exceptions return 1; Ctrl+C returns 130.
    cleanup_work is called only after the experiment evidence has been saved.
    """
    directory = create_run(case_id)
    record = create_record(case_id, model, inputs, prompts, settings)
    save_run(directory, record)
    exit_code = 0

    try:
        exit_code = workflow(directory, record)
    except Exception as error:
        record["status"] = "ERROR"
        record["error"] = {
            "stage": record["stage"],
            "type": type(error).__name__,
            "message": str(error),
            "traceback": traceback.format_exc(),
        }
        exit_code = 1
    except KeyboardInterrupt:
        record["status"] = "INTERRUPTED"
        record["error"] = {
            "stage": record["stage"],
            "type": "KeyboardInterrupt",
            "message": "Execution interrupted by the user.",
        }
        exit_code = 130
    finally:
        record["finished_at"] = local_now()
        # Preserve the evidence before deleting disposable formal-tool files.
        save_run(directory, record)
        if record["formal"] is not None and cleanup_work is not None:
            record["formal"]["cleanup"] = cleanup_work(
                record["formal"], keep_work=settings.get("keep_work", False),
            )
            save_run(directory, record)
        print_summary(directory, record)

    return exit_code


def print_summary(run_dir, record: dict) -> None:
    """Keep terminal output short; detailed information stays in the report."""
    print(f"Case: {record['case_id']} | Pipeline: {record['status']}")
    formal = record["formal"]
    if formal is not None:
        print(
            f"Formal: {formal['status']} | Syntax: {formal['syntax']} | "
            f"Strict: {formal['pec']} | Relaxed: {formal['relax_pec']}"
        )
        print(f"Reset mismatch: {formal['reset_mismatch']}")
    if record["error"]:
        error = record["error"]
        print(f"Error at {error['stage']}: {error['type']}: {error['message']}")
    print("Report:", Path(run_dir) / "report.txt")

