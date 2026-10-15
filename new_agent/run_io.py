"""Save case records, readable reports, and experiment summaries.

Experiment decisions belong in main.py. This module manages records and files.
Case records contain only final outcomes. Round evidence is optional and separate.
"""

import csv
import hashlib
import io
import json
import re
import traceback
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path


RUN_TIMEZONE = timezone.utc
SCORE_FIELDS = ("syntax", "pec", "relax_pec", "bleu", "reset_mismatch")
CSV_FIELDS = (
    "case_number", "design_name", "task_id",
    "rounds_used", "last_evaluated_round",
    "pipeline_status", "formal_status", "syntax", "pec", "relax_pec", "bleu",
    "reset_mismatch", "passed", "stop_reason",
    "generated_assertion", "reference_assertion",
)


# Case records and checkpoints.

def local_now() -> str:
    """Return an ISO timestamp with an explicit UTC offset."""
    return datetime.now(RUN_TIMEZONE).isoformat(timespec="seconds")


def create_run(case_id: str, runs_root=None, *, phase: str | None = None) -> Path:
    """Create a timestamped directory, optionally labeled Train or Infer."""
    if not re.fullmatch(r"[A-Za-z0-9_-]+", case_id):
        raise ValueError("case_id must contain only letters, digits, _ or -.")
    if phase not in (None, "train", "infer"):
        raise ValueError("phase must be 'train' or 'infer'.")
    root = (
        Path(runs_root).expanduser().resolve()
        if runs_root is not None
        else Path(__file__).resolve().parent / "runs"
    )
    root.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(RUN_TIMEZONE).strftime("%Y%m%d_%H%M%S_%fZ")
    prefix = f"{phase.title()}_" if phase else ""
    directory = root / f"{prefix}{timestamp}_{case_id}"
    directory.mkdir()
    return directory


def create_experiment(
    *, dataset: str, dataset_path, cases: list[dict], models: dict,
    settings: dict, runs_root=None, phase: str = "train", source_training_run=None,
) -> Path:
    """Create one batch directory and save its resolved inputs/selection once."""
    if phase not in ("train", "infer"):
        raise ValueError("phase must be 'train' or 'infer'.")
    if (phase == "infer") != (source_training_run is not None):
        raise ValueError("Only inference experiments require source_training_run.")
    directory_label = re.sub(r"[^A-Za-z0-9_-]+", "_", dataset).strip("_") or "dataset"
    directory = create_run(directory_label, runs_root=runs_root, phase=phase)
    metadata = {
        "output_format_version": 2,
        "phase": phase,
        "dataset": dataset,
        "dataset_path": str(dataset_path),
        "dataset_sha256": hashlib.sha256(Path(dataset_path).read_bytes()).hexdigest(),
        "models": models,
        "diagnosis_models": [],
        "settings": settings,
        "selected_cases": [
            {
                "case_number": case["case_number"],
                "design_name": case["design_name"],
                "task_id": case["task_id"],
                "directory": f"cases/case_{case['case_number']:04d}",
            }
            for case in cases
        ],
        "started_at": local_now(),
        "finished_at": None,
        "status": "RUNNING",
    }
    if source_training_run is not None:
        metadata["source_training_run"] = str(Path(source_training_run).expanduser().resolve())
    _atomic_write(
        directory / "run_metadata.json",
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n",
    )
    return directory


def _read_training_metadata(directory: Path, dataset: str, dataset_sha256: str) -> dict:
    """Check whether an experiment can supply a saved split and learning evidence."""
    metadata = json.loads((directory / "run_metadata.json").read_text(encoding="utf-8"))
    if not isinstance(metadata, dict):
        raise ValueError("run_metadata.json must contain an object.")
    if metadata.get("phase") != "train" or metadata.get("status") != "COMPLETED":
        raise ValueError("The source must be a COMPLETED training experiment.")
    if metadata.get("dataset") != dataset or metadata.get("dataset_sha256") != dataset_sha256:
        raise ValueError("The training dataset name or CSV contents do not match the current dataset.")
    settings = metadata.get("settings")
    split = settings.get("dataset_split") if isinstance(settings, dict) else None
    if (
        not isinstance(split, dict)
        or not split.get("training_case_ids")
        or not split.get("inference_case_ids")
    ):
        raise ValueError("The training experiment has no saved train/inference split.")
    finished_at = metadata.get("finished_at")
    if not isinstance(finished_at, str) or datetime.fromisoformat(finished_at).tzinfo is None:
        raise ValueError("The training experiment has no valid completion timestamp.")
    for name in ("evaluation.csv", "learned_rules.jsonl"):
        if not (directory / name).is_file():
            raise ValueError(f"The training experiment is missing {name}.")
    return metadata


def select_training_run(
    *, dataset: str, dataset_path, runs_root, training_run_dir=None,
) -> tuple[Path, dict]:
    """Select an explicit source or the compatible run that finished most recently.

    Relative explicit paths are resolved from runs_root. Invalid explicit paths
    fail without falling back. Automatic selection ignores incomplete,
    incompatible, and older-format experiments without phase/split metadata.
    """
    root = Path(runs_root).expanduser().resolve()
    dataset_sha256 = hashlib.sha256(Path(dataset_path).read_bytes()).hexdigest()
    if training_run_dir is not None:
        directory = Path(training_run_dir).expanduser()
        directory = (directory if directory.is_absolute() else root / directory).resolve()
        try:
            return directory, _read_training_metadata(directory, dataset, dataset_sha256)
        except (OSError, ValueError) as error:
            raise ValueError(f"Cannot use training run {directory}: {error}") from error

    candidates = []
    directories = root.iterdir() if root.is_dir() else []
    for directory in directories:
        if not directory.is_dir():
            continue
        try:
            metadata = _read_training_metadata(directory, dataset, dataset_sha256)
        except (OSError, ValueError):
            continue
        candidates.append((directory, metadata))
    if not candidates:
        raise ValueError(
            f"No completed training experiment with a saved split matches {dataset!r} "
            f"and the current CSV in {root}. Train with CASE_IDS = [] first, "
            "or set TRAINING_RUN_DIR to a compatible experiment."
        )
    return max(candidates, key=lambda item: (
        datetime.fromisoformat(item[1]["finished_at"]), item[0].name,
    ))


def finish_experiment(experiment_dir, exit_code: int) -> int:
    """Finalize batch metadata; individual assertion acceptance stays in the CSV."""
    directory = Path(experiment_dir)
    metadata_path = directory / "run_metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    score_path = directory / "evaluation.csv"
    try:
        scores = _read_scores(score_path)
    except (OSError, ValueError) as error:
        scores = []
        metadata["summary_error"] = f"{type(error).__name__}: {error}"
        if exit_code == 0:
            exit_code = 1
    metadata.update(
        finished_at=local_now(),
        status=("INTERRUPTED" if exit_code == 130 else
                "COMPLETED_WITH_ERRORS" if exit_code else "COMPLETED"),
        cases_recorded=None if metadata.get("summary_error") else len(scores),
        cases_passed=None if metadata.get("summary_error") else sum(row["passed"] == "True" for row in scores),
        exit_code=exit_code,
    )
    _atomic_write(metadata_path, json.dumps(metadata, indent=2, ensure_ascii=False) + "\n")
    print("\nBatch:", metadata["status"])
    if metadata.get("summary_error"):
        print("Batch summary unavailable:", metadata["summary_error"])
    else:
        print(f"Cases recorded: {len(scores)} | Passed: {metadata['cases_passed']}")
    print("Evaluation:", directory / "evaluation.csv")
    print("Learning evidence:", directory / "learned_rules.jsonl")
    return exit_code


def create_record(case_id: str, models: dict, inputs: dict, prompts: dict, settings: dict) -> dict:
    """Create one case record for the workflow and its saved evidence."""
    return {
        "case_id": case_id,
        "models": dict(models),
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
        "diagnosis_model": None,
        "statements": {},
        "rounds_used": 0,
        "last_evaluated_round": None,
        "round_metrics": [],
        "passed": False,
        "stop_reason": None,
        "rule_registry": [],
        "rules_used": [],
        "last_rule_generation": None,
        "pending_attempt": None,
        "diagnosis_skipped_reason": None,
        "error": None,
        "summary_error": None,
        "trace_error": None,
    }


def _atomic_write(path: Path, text: str) -> None:
    """Write a complete temporary file, then replace the destination."""
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def final_record(record: dict) -> dict:
    """Select final case data; runtime prompts and round history stay in memory."""
    saved = {
        name: record[name] for name in (
            "case_id", "started_at", "finished_at", "status", "stage",
            "rounds_used", "last_evaluated_round", "passed", "stop_reason",
            "summary_error", "trace_error",
        )
    }
    saved["inputs"] = {
        name: record["inputs"][name]
        for name in ("case_number", "design_name", "requirement", "reference_assertion")
        if name in record["inputs"]
    }
    saved["generation"] = {"assertion": record["generation"]["assertion"]}
    formal = record["formal"]
    saved["formal"] = None if formal is None else {
        name: formal[name]
        for name in SCORE_FIELDS + (
            "status", "generated_reset", "reference_reset", "comparison_scope",
            "returncode", "source_task_id", "tool_task_id", "log_path", "input_path", "cleanup",
        )
        if name in formal
    }
    error = record["error"]
    saved["error"] = None if error is None else {
        name: error[name] for name in ("stage", "type", "message") if name in error
    }
    saved["summary_directory"] = record.get("summary_directory")
    return saved


def save_run(run_dir, record: dict) -> None:
    """Write compact final records; tracing also permits overwritten checkpoints."""
    tracing = record["settings"].get("save_debug_traces", False)
    if not tracing and record["finished_at"] is None:
        return
    directory = Path(run_dir)
    saved = final_record(record)
    _atomic_write(
        directory / "result.json",
        json.dumps(saved, indent=2, ensure_ascii=False) + "\n",
    )
    _atomic_write(directory / "report.txt", _readable_report(saved))


def update_run(run_dir, record: dict, **changes) -> None:
    """Replace the supplied top-level fields and save a checkpoint."""
    record.update(changes)
    save_run(run_dir, record)


def save_diagnosis_model(record: dict, model: str | None) -> None:
    """Keep observed diagnosis model names once in experiment metadata."""
    if not model:
        return
    path = Path(record["summary_directory"]) / "run_metadata.json"
    metadata = json.loads(path.read_text(encoding="utf-8"))
    models = metadata.setdefault("diagnosis_models", [])
    if model not in models:
        models.append(model)
        _atomic_write(path, json.dumps(metadata, indent=2, ensure_ascii=False) + "\n")


def save_debug_event(run_dir, record: dict, event: str, **data) -> None:
    """Append one round event when detailed evidence is enabled.

    These records are saved evidence, not conversation history sent to models.
    """
    if not record["settings"].get("save_debug_traces", False):
        return
    pending = record["pending_attempt"]
    round_number = pending["round"] if pending else record["last_evaluated_round"]
    entry = {"round": round_number, "event": event, "time": local_now(), **data}
    with (Path(run_dir) / "debug_traces.jsonl").open("a", encoding="utf-8") as file:
        file.write(json.dumps(entry, ensure_ascii=False) + "\n")


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
    save_debug_event(
        run_dir, record, "assertion_request", model=record["models"]["assertion"],
        system_prompt=system_prompt, user_prompt=user_prompt, rules_used=rules,
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
    save_debug_event(run_dir, record, "formal_check", formal_result=formal)


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
        result = cleanup_work(
            formal, keep_work=keep_work,
            preserve_unresolved=record["settings"].get("save_debug_traces", False),
        )
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
        "case_number": inputs.get("case_number"),
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


def _read_scores(path: Path) -> list[dict]:
    """Read the final score table without overwriting an invalid existing file."""
    if not path.exists():
        return []
    with path.open(encoding="utf-8", newline="") as file:
        reader = csv.DictReader(file)
        if reader.fieldnames != list(CSV_FIELDS):
            raise ValueError("Evaluation CSV has an unexpected header.")
        rows = list(reader)
    if any(row.get("passed") not in {"True", "False"} for row in rows):
        raise ValueError("Evaluation CSV contains an invalid passed value.")
    return rows


def _update_case_collection(path: Path, entry: dict) -> list[dict]:
    """Save one JSONL entry per design/task within this experiment."""
    cases = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                previous = json.loads(line)
                key = (previous["design_name"], previous["task_id"])
                cases[key] = previous
    key = (entry["design_name"], entry["task_id"])
    cases[key] = entry
    entries = list(cases.values())
    text = "".join(json.dumps(item, ensure_ascii=False) + "\n" for item in entries)
    _atomic_write(path, text)
    return entries


def save_summaries(summary_dir, record: dict) -> None:
    """Save final scores and learned guidance, replacing repeated case entries.

    The batch runner supplies one shared experiment directory. Case records
    remain in their own folders; summaries contain one entry per source case.
    """
    directory = Path(summary_dir)
    directory.mkdir(parents=True, exist_ok=True)
    row = _summary_row(record)
    score_path = directory / "evaluation.csv"
    rows = {(old["design_name"], old["task_id"]): old
            for old in _read_scores(score_path)}
    rows[(row["design_name"], row["task_id"])] = row
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=CSV_FIELDS, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows.values())  # None becomes blank, not a zero score.
    _atomic_write(directory / "evaluation.csv", buffer.getvalue())

    if record["settings"].get("save_debug_traces", False):
        trace = {**row, "round_metrics": record["round_metrics"]}
        _update_case_collection(directory / "training_traces.jsonl", trace)

    # Guidance is exported separately from score traces. A passed case does not
    # establish that every individual rule caused the successful revision.
    rule_groups = {}
    rules = {}
    for number, entry in enumerate(record["rule_registry"], start=1):
        rule_id = f"rule_{number}"
        rule_groups[rule_id] = entry["group"]
        rules[rule_id] = entry["rule"]

    learning = {
        "case_number": row["case_number"], "design_name": row["design_name"],
        "task_id": row["task_id"],
        "requirement": record["inputs"]["requirement"],
        "passed": record["passed"],
        "rule_groups": rule_groups,
        "rules": rules,
    }
    _update_case_collection(directory / "learned_rules.jsonl", learning)


# Execution, failures, and finalization.

def run_experiment(
    workflow, *, case_id: str, models: dict, inputs: dict, prompts: dict, settings: dict,
    cleanup_work=None, summary_dir=None, runs_root=None, case_dir=None,
) -> int:
    """Run one case and finalize its reports/summaries after success or failure.

    Exit codes: 0 for normal completion, 1 for unresolved/errors, 130 for Ctrl+C.
    Normal completion does not necessarily mean the assertion passed.
    """
    if case_dir is None:
        directory = create_run(case_id, runs_root=runs_root)
    else:
        directory = Path(case_dir)
        directory.mkdir(parents=True, exist_ok=False)
    record = create_record(case_id, models, inputs, prompts, settings)
    record["summary_directory"] = str(
        Path(directory if summary_dir is None else summary_dir).resolve()
    )
    save_run(directory, record)
    if case_dir is None:  # Standalone calls still get their own metadata file.
        metadata = {
            "case_id": case_id, "dataset": inputs.get("dataset", "nl2sva_human"),
            "design_name": inputs.get("design_name", ""),
            "models": models, "settings": settings, "started_at": record["started_at"],
        }
        _atomic_write(
            directory / "run_metadata.json",
            json.dumps(metadata, indent=2, ensure_ascii=False) + "\n",
        )
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
            save_debug_event(
                directory, record, "case_finished", status=record["status"],
                passed=record["passed"], stop_reason=record["stop_reason"],
                error=record["error"],
            )
        except Exception as error:
            record["trace_error"] = f"{type(error).__name__}: {error}"
            save_run(directory, record)
            if exit_code == 0:
                exit_code = 1
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
    """Present only the final checked assertion, scores, outcome, and errors."""
    inputs = record["inputs"]
    lines = [
        f"Case: {record['case_id']}",
        f"Selection ID: {inputs.get('case_number', '(standalone)')}",
        f"Design: {inputs.get('design_name', '(unspecified)')}",
        f"Pipeline status: {record['status']}",
        f"Stage: {record['stage']}",
        f"Passed: {record['passed']}",
        f"Stop reason: {record['stop_reason'] or '(not stopped)'}",
        f"Rounds used: {record['rounds_used']}",
        f"Last evaluated round: {record['last_evaluated_round'] or '(none)'}",
        f"Started: {record['started_at']}",
        f"Finished: {record['finished_at'] or '(not finished)'}",
        "", "REQUIREMENT", inputs["requirement"],
        "", "LAST EVALUATED ASSERTION",
        record["generation"]["assertion"] or "(no evaluated assertion)",
        "", "REFERENCE ASSERTION", inputs["reference_assertion"],
        "", "FINAL FORMAL RESULT",
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

    if record["error"]:
        error = record["error"]
        lines.extend([
            "", "PIPELINE ERROR", f"Stage: {error['stage']}",
            f"{error['type']}: {error['message']}",
        ])
    if record["trace_error"]:
        lines.extend(["", "TRACE SAVE ERROR", record["trace_error"]])
    if record["summary_error"]:
        lines.extend(["", "SUMMARY SAVE ERROR", record["summary_error"]])
    if record.get("summary_directory"):
        lines.extend([
            "", f"Experiment directory: {record['summary_directory']}",
            "Open run_metadata.json for shared dataset, model, and configuration details.",
            "Open learned_rules.jsonl for retained guidance and case outcomes.",
        ])
    lines.append("This report contains no round history or raw model responses.")
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
    if record["trace_error"]:
        print("Trace save error:", record["trace_error"])
    if record["summary_error"]:
        print("Summary save error:", record["summary_error"])
    print("Report:", Path(run_dir) / "report.txt")
