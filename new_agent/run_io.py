"""Save case records, readable reports, and experiment summaries.

Experiment decisions belong in main.py. This module manages records and files.
Only the latest full attempt is kept; earlier rounds retain compact scores.
"""

import csv
import io
import json
import re
import traceback
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


RUN_TIMEZONE = ZoneInfo("America/New_York")
SCORE_FIELDS = ("syntax", "pec", "relax_pec", "bleu", "reset_mismatch")
CSV_FIELDS = (
    "dataset", "design_name", "task_id", "rounds_used", "last_evaluated_round",
    "pipeline_status", "formal_status", "syntax", "pec", "relax_pec", "bleu",
    "reset_mismatch", "passed", "stop_reason",
    "generated_assertion", "reference_assertion",
)


# Case records and checkpoints.

def local_now() -> str:
    """Return a readable timestamp in the configured local timezone."""
    return datetime.now(RUN_TIMEZONE).strftime("%Y-%m-%d %H:%M:%S")


def create_run(case_id: str, runs_root=None) -> Path:
    """Create one timestamped case directory, with no round subdirectories."""
    if not re.fullmatch(r"[A-Za-z0-9_-]+", case_id):
        raise ValueError("case_id must contain only letters, digits, _ or -.")
    root = (
        Path(runs_root).expanduser().resolve()
        if runs_root is not None
        else Path(__file__).resolve().parent / "runs"
    )
    root.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(RUN_TIMEZONE).strftime("%Y%m%d_%H%M%S_%f")
    directory = root / f"{timestamp}_{case_id}"
    directory.mkdir()
    return directory


def create_record(case_id: str, model, inputs: dict, prompts: dict, settings: dict) -> dict:
    """Create the record shared by the workflow and standalone formal checker."""
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
        "rounds_used": 0,
        "last_evaluated_round": None,
        "round_metrics": [],
        "passed": False,
        "stop_reason": None,
        "rule_registry": [],
        "rules_used": [],
        "pending_attempt": None,
        "diagnosis_skipped_reason": None,
        "error": None,
        "summary_error": None,
    }


def _atomic_write(path: Path, text: str) -> None:
    """Write a complete temporary file, then replace the destination."""
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def save_run(run_dir, record: dict) -> None:
    """Save JSON and report; keep the full tool output in jasper.log."""
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
    """Replace the supplied top-level fields and save a checkpoint."""
    record.update(changes)
    save_run(run_dir, record)


def start_attempt(
    run_dir, record: dict, round_number: int, *,
    system_prompt: str, user_prompt: str, rules: list[dict],
) -> dict:
    """Keep a new request separate from the last evaluated assertion and scores."""
    attempt = {
        "round": round_number,
        "prompts": {"system": system_prompt, "user": user_prompt},
        "generation": {"raw_response": None, "assertion": None},
        "rules_used": deepcopy(rules),
    }
    update_run(
        run_dir, record, stage="generation",
        rounds_used=round_number, pending_attempt=attempt,
    )
    return attempt


def record_formal_result(run_dir, record: dict, attempt: dict, formal: dict) -> None:
    """Publish matching assertion/verdict fields and append compact round scores."""
    metric = {"round": attempt["round"], "status": formal["status"]}
    for name in SCORE_FIELDS:
        metric[name] = formal.get(name)  # Unavailable scores remain None.
    update_run(
        run_dir, record,
        generation=deepcopy(attempt["generation"]),
        prompts=deepcopy(attempt["prompts"]),
        rules_used=deepcopy(attempt["rules_used"]),
        formal=formal,
        last_evaluated_round=attempt["round"],
        round_metrics=record["round_metrics"] + [metric],
        pending_attempt=None,
        diagnosis=None, statements={}, diagnosis_skipped_reason=None,
    )


# Formal-tool artifacts and cleanup.

def prepare_formal_check(run_dir) -> None:
    """Remove previous input/log so an unsupported new input cannot inherit them."""
    for name in ("formal_input.sva", "jasper.log"):
        (Path(run_dir) / name).unlink(missing_ok=True)


def cleanup_formal_work(run_dir, record: dict, cleanup_work, *, keep_work=False):
    """Use the checker's owned cleanup once and record unexpected exceptions."""
    formal = record["formal"]
    if formal is None or cleanup_work is None:
        return None
    if "cleanup" in formal:
        return formal["cleanup"]
    try:
        result = cleanup_work(formal, keep_work=keep_work)
    except Exception as error:
        result = {
            "retained": True,
            "reason": f"Cleanup error: {type(error).__name__}: {error}",
        }
    formal["cleanup"] = result
    save_run(run_dir, record)
    return result


# Final summaries: one entry per dataset/design/task within an experiment.

def _summary_row(record: dict) -> dict:
    """Build the final CSV row without confusing pending output with old scores."""
    inputs = record["inputs"]
    formal = record["formal"] or {}
    row = {
        "dataset": inputs.get("dataset", "nl2sva_human"),
        "design_name": inputs.get("design_name", ""),
        "task_id": record["case_id"],
        "rounds_used": record["rounds_used"],
        "last_evaluated_round": record["last_evaluated_round"],
        "pipeline_status": record["status"],
        "formal_status": formal.get("status"),
        "passed": record["passed"],
        "stop_reason": record["stop_reason"],
        "generated_assertion": record["generation"]["assertion"],
        "reference_assertion": inputs["reference_assertion"],
    }
    for name in SCORE_FIELDS:
        row[name] = formal.get(name)
    return row


def save_summaries(summary_dir, record: dict) -> None:
    """Update CSV and JSONL from one shared collection of case summaries.

    For the fixed example, summary_dir is its run directory. A later dataset
    runner can supply one shared experiment directory for sequential cases.
    Re-saving the same dataset/design/task replaces its entry.
    """
    directory = Path(summary_dir)
    directory.mkdir(parents=True, exist_ok=True)
    trace_path = directory / "training_traces.jsonl"

    cases = {}
    if trace_path.exists():
        for line in trace_path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                trace = json.loads(line)
                key = (trace["dataset"], trace["design_name"], trace["task_id"])
                cases[key] = trace

    trace = _summary_row(record)
    trace["round_metrics"] = deepcopy(record["round_metrics"])
    key = (trace["dataset"], trace["design_name"], trace["task_id"])
    cases[key] = trace
    traces = list(cases.values())

    text = "".join(json.dumps(item, ensure_ascii=False) + "\n" for item in traces)
    _atomic_write(trace_path, text)

    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=CSV_FIELDS, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(traces)  # None becomes a blank CSV cell, not a zero score.
    _atomic_write(directory / "evaluation.csv", buffer.getvalue())


# Execution, failures, and finalization.

def run_experiment(
    workflow, *, case_id: str, model, inputs: dict, prompts: dict, settings: dict,
    cleanup_work=None, summary_dir=None,
) -> int:
    """Run one case and finalize its reports/summaries after success or failure.

    Exit codes: 0 for normal completion, 1 for unresolved/errors, 130 for Ctrl+C.
    Normal completion does not necessarily mean the assertion passed.
    """
    directory = create_run(case_id)
    record = create_record(case_id, model, inputs, prompts, settings)
    save_run(directory, record)
    exit_code = 0

    try:
        exit_code = workflow(directory, record)
    except Exception as error:
        stage = record["stage"]
        record.update(
            status="ERROR", passed=False,
            stop_reason={
                "generation": "generation_error",
                "extraction": "format_error",
                "formal_check": "checker_error",
                "cleanup": "cleanup_error",
                "diagnosis": "diagnosis_error",
                "formatting": "formatting_error",
                "rule_generation": "rule_output_error",
                "rule_validation": "rule_output_error",
                "rule_update": "rule_output_error",
            }.get(stage, "pipeline_error"),
            error={
                "stage": stage,
                "type": type(error).__name__,
                "message": str(error),
                "traceback": traceback.format_exc(),
            },
        )
        exit_code = 1
    except KeyboardInterrupt:
        record.update(
            status="INTERRUPTED", passed=False, stop_reason="interrupted",
            error={
                "stage": record["stage"], "type": "KeyboardInterrupt",
                "message": "Execution interrupted by the user.",
            },
        )
        exit_code = 130
    finally:
        record["finished_at"] = local_now()
        cleanup_formal_work(
            directory, record, cleanup_work,
            keep_work=settings.get("keep_work", False),
        )
        save_run(directory, record)
        try:
            save_summaries(directory if summary_dir is None else summary_dir, record)
        except Exception as error:
            record["summary_error"] = f"{type(error).__name__}: {error}"
            save_run(directory, record)
            if exit_code == 0:
                exit_code = 1
        print_summary(directory, record)

    return exit_code


# Human-readable views of the same record.

def _readable_report(record: dict) -> str:
    """Format the record; this function makes no experiment decisions."""
    lines = [
        f"Case: {record['case_id']}",
        f"Model: {record['model'] or '(not used)'}",
        f"Pipeline status: {record['status']}",
        f"Stage: {record['stage']}",
        f"Passed: {record['passed']}",
        f"Stop reason: {record['stop_reason'] or '(not stopped)'}",
        f"Rounds used: {record['rounds_used']}",
        f"Last evaluated round: {record['last_evaluated_round'] or '(none)'}",
        f"Started: {record['started_at']}",
        f"Finished: {record['finished_at'] or '(not finished)'}",
        "", "REQUIREMENT", record["inputs"]["requirement"],
        "", "GENERATED ASSERTION",
        record["generation"]["assertion"] or "(no evaluated assertion)",
        "", "REFERENCE ASSERTION", record["inputs"]["reference_assertion"],
        "", "FORMAL RESULT",
    ]
    formal = record["formal"]
    if formal is None:
        lines.append("(not run)")
    else:
        for name in (
            "status", "syntax", "pec", "relax_pec", "generated_reset",
            "reference_reset", "reset_mismatch", "comparison_scope",
            "log_path", "input_path",
        ):
            value = formal.get(name)
            lines.append(f"{name}: {value if value is not None else '(unavailable)'}")
        if formal.get("cleanup"):
            lines.append(f"Work directory retained: {formal['cleanup']['retained']}")
            lines.append(f"Cleanup note: {formal['cleanup']['reason']}")

    lines.extend(["", "ROUND SCORES"])
    for metric in record["round_metrics"]:
        scores = "; ".join(
            f"{name}={metric[name] if metric[name] is not None else '(unavailable)'}"
            for name in SCORE_FIELDS
        )
        lines.append(f"Round {metric['round']}: {metric['status']} | {scores}")
    if not record["round_metrics"]:
        lines.append("(no round verdicts recorded)")

    for title, entries in (
        ("RULES USED FOR THE LAST EVALUATED ASSERTION", record["rules_used"]),
        ("RETAINED RULE REGISTRY", record["rule_registry"]),
    ):
        lines.extend(["", title])
        if not entries:
            lines.append("(none)")
        for entry in entries:
            lines.extend([
                f"Group: {', '.join(entry['group'])}",
                entry["rule"],
                f"First learned: round {entry['first_learned_round']}; "
                f"updated: round {entry['updated_round']}",
            ])

    lines.extend(["", "FORMATTED DIAGNOSIS FOR THE LAST EVALUATED ASSERTION"])
    if record["diagnosis_skipped_reason"]:
        lines.append(record["diagnosis_skipped_reason"])
    elif record["statements"]:
        lines.extend(f"{name}: {text}" for name, text in record["statements"].items())
    else:
        lines.append("(none retained for this assertion)")

    pending = record["pending_attempt"]
    if pending is not None:
        lines.extend([
            "", "PENDING ATTEMPT WITHOUT A RETURNED CHECKER RESULT",
            f"Round: {pending['round']}",
            "Its output is separate from the evaluated assertion and scores above.",
            pending["generation"]["assertion"]
            or pending["generation"]["raw_response"] or "(no response)",
        ])
    if record["error"]:
        error = record["error"]
        lines.extend([
            "", "PIPELINE ERROR", f"Stage: {error['stage']}",
            f"{error['type']}: {error['message']}", error.get("traceback", ""),
        ])
    if record["summary_error"]:
        lines.extend(["", "SUMMARY SAVE ERROR", record["summary_error"]])
    lines.extend([
        "", "Open result.json for the latest prompts, model output, and Jev answers.",
        "Open jasper.log for captured tool output, if a check returned a log.",
    ])
    return "\n".join(lines) + "\n"


def print_summary(run_dir, record: dict) -> None:
    """Print the outcome and report path; detailed records stay in files."""
    print(f"Case: {record['case_id']} | Pipeline: {record['status']}")
    print(
        f"Rounds: {record['rounds_used']} | Passed: {record['passed']} | "
        f"Stop reason: {record['stop_reason'] or '(not stopped)'}"
    )
    formal = record["formal"]
    if formal is not None:
        print(
            f"Formal: {formal['status']} | Syntax: {formal['syntax']} | "
            f"Strict: {formal['pec']} | Relaxed: {formal['relax_pec']}"
        )
        print(f"Reset mismatch: {formal['reset_mismatch']}")
        cleanup = formal.get("cleanup")
        if cleanup and cleanup["retained"]:
            print("Work retained:", cleanup["reason"])
    if record["error"]:
        error = record["error"]
        print(f"Error at {error['stage']}: {error['type']}: {error['message']}")
    if record["summary_error"]:
        print("Summary save error:", record["summary_error"])
    print("Report:", Path(run_dir) / "report.txt")


