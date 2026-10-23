"""Save case records, usage, and experiment summaries.

Experiment decisions belong in main.py and pipeline.py. This module manages records and files.
Case records contain only final outcomes. Round evidence is optional and separate.
"""

import csv
import hashlib
import io
import json
import re
import traceback
from copy import deepcopy
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from time import perf_counter


RUN_TIMEZONE = timezone.utc
SCORE_FIELDS = ("syntax", "pec", "relax_pec", "bleu", "rouge", "exact_match")
CSV_FIELDS = (
    "case_number", "design_name", "task_id",
    "rounds_used", "last_evaluated_round",
    "pipeline_status", "formal_status", "syntax", "pec", "relax_pec", "bleu",
    "rouge", "exact_match", "passed", "stop_reason",
    "generated_assertion", "reference_assertion",
)

MODEL_STAGES = ("assertion", "diagnosis", "rule")
USAGE_METRIC_FIELDS = tuple(
    f"{stage}_{name}"
    for stage in MODEL_STAGES
    for name in ("input_tokens", "output_tokens", "total_tokens", "seconds")
) + (
    "tool_seconds", "input_tokens", "output_tokens", "total_tokens",
    "other_seconds", "total_seconds",
)
USAGE_FIELDS = ("case_id", "round") + USAGE_METRIC_FIELDS + ("passed",)


# Tokens and wall time. These records contain no model names or formal scores.

def _sum_usage(values) -> int | float | None:
    """Missing usage makes the sum unknown; skipped stages contribute zero."""
    values = list(values)
    return None if any(value is None for value in values) else sum(values)


def finish_usage_round(record: dict) -> None:
    """Close the active round once, including any failed or interrupted stage."""
    rounds = record.get("usage_rounds", [])
    if rounds and rounds[-1]["total_seconds"] is None:
        rounds[-1]["total_seconds"] = perf_counter() - rounds[-1]["started_counter"]


def start_usage_round(record: dict, round_number: int) -> None:
    """Start before prompt preparation; close the previous round if necessary."""
    finish_usage_round(record)
    record.setdefault("usage_rounds", []).append({
        "round": round_number,
        "started_counter": perf_counter(),
        "total_seconds": None,
        "passed": False,
        "stages": {
            stage: {"input_tokens": 0, "output_tokens": 0, "seconds": 0.0}
            for stage in (*MODEL_STAGES, "tool")
        },
    })


@contextmanager
def measure_stage(record: dict, stage: str):
    """Time a stage, capturing provider usage before response validation."""
    metric = record["usage_rounds"][-1]["stages"][stage]
    if stage in MODEL_STAGES:
        # Invoked but unreported is unknown, rather than a free/skipped call.
        metric["input_tokens"] = metric["output_tokens"] = None
    received = False

    def capture_usage(usage) -> None:
        nonlocal received
        for field in ("input_tokens", "output_tokens"):
            value = usage.get(field) if isinstance(usage, dict) else getattr(usage, field, None)
            if type(value) is not int or value < 0:
                value = None
            metric[field] = _sum_usage((metric[field], value)) if received else value
        received = True

    started = perf_counter()
    try:
        yield capture_usage
    finally:
        metric["seconds"] += perf_counter() - started


def _usage_metrics(rounds: list[dict], elapsed_seconds: float) -> dict:
    """Produce the same numeric columns for one round or a whole case."""
    row = {}
    for stage in MODEL_STAGES:
        for field in ("input_tokens", "output_tokens"):
            row[f"{stage}_{field}"] = _sum_usage(r["stages"][stage][field] for r in rounds)
        row[f"{stage}_total_tokens"] = _sum_usage(
            (row[f"{stage}_input_tokens"], row[f"{stage}_output_tokens"])
        )
        row[f"{stage}_seconds"] = sum(r["stages"][stage]["seconds"] for r in rounds)
    row["tool_seconds"] = sum(r["stages"]["tool"]["seconds"] for r in rounds)
    for field in ("input_tokens", "output_tokens", "total_tokens"):
        row[field] = _sum_usage(row[f"{stage}_{field}"] for stage in MODEL_STAGES)
    stage_seconds = sum(row[f"{stage}_seconds"] for stage in (*MODEL_STAGES, "tool"))
    row["other_seconds"] = max(0.0, elapsed_seconds - stage_seconds)
    row["total_seconds"] = elapsed_seconds
    return row


def save_usage(summary_dir, record: dict, elapsed_seconds: float) -> None:
    """Write contiguous case blocks, labeling only the first row of each case."""
    path = Path(summary_dir) / "token_time.csv"
    cases = {}
    if path.exists():
        with path.open(encoding="utf-8", newline="") as source:
            reader = csv.DictReader(source)
            if reader.fieldnames != list(USAGE_FIELDS):
                raise ValueError(f"Unexpected usage CSV header: {path.name}")
            case_id = None
            for row in reader:
                if row["case_id"]:
                    case_id = row["case_id"]
                    cases[case_id] = []
                if case_id is None:
                    raise ValueError("The first usage row must identify its case.")
                cases[case_id].append(row)

    rounds = record.get("usage_rounds", [])
    rows = [
        {"case_id": "", "round": r["round"],
         **_usage_metrics([r], r["total_seconds"]), "passed": r["passed"]}
        for r in rounds
    ]
    rows.append({
        "case_id": "", "round": "case_total",
        **_usage_metrics(rounds, elapsed_seconds), "passed": record["passed"],
    })
    inputs = record["inputs"]
    # Task names repeat across designs; the selection ID identifies the case.
    selection_id = inputs.get("case_number", "")
    design_name = inputs.get("design_name", "")
    case_label = f"{design_name}/{record['case_id']}" if design_name else str(record["case_id"])
    if selection_id != "":
        case_label = f"{selection_id}: {case_label}"
    rows[0]["case_id"] = case_label
    cases[case_label] = rows

    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=USAGE_FIELDS)
    writer.writeheader()
    for case_rows in cases.values():
        for row in case_rows:
            writer.writerow({
                key: round(value, 6) if isinstance(value, float) else value
                for key, value in row.items()
            })
    _atomic_write(path, buffer.getvalue())


def _experiment_usage(directory: Path, elapsed_seconds: float) -> dict:
    """Accumulate case-total rows without counting round rows again."""
    with (directory / "token_time.csv").open(encoding="utf-8", newline="") as source:
        cases = [row for row in csv.DictReader(source) if row["round"] == "case_total"]
    totals = {}
    for field in USAGE_METRIC_FIELDS:
        convert = int if field.endswith("tokens") else float
        totals[field] = _sum_usage(
            None if row[field] == "" else convert(row[field]) for row in cases
        )
    totals["case_seconds"] = totals.pop("total_seconds")
    totals["experiment_seconds"] = elapsed_seconds
    stage_seconds = sum(totals[f"{stage}_seconds"] for stage in (*MODEL_STAGES, "tool"))
    totals["other_seconds"] = max(0.0, elapsed_seconds - stage_seconds)
    return totals


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
    requires_source = phase == "infer"
    if requires_source != (source_training_run is not None):
        raise ValueError("Inference requires a source training run; training does not accept one.")
    directory_label = re.sub(r"[^A-Za-z0-9_-]+", "_", dataset).strip("_") or "dataset"
    directory = create_run(directory_label, runs_root=runs_root, phase=phase)
    metadata = {
        "output_format_version": 4,
        "phase": phase,
        "mode": settings.get("mode", "inference" if phase == "infer" else "train"),
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
    """Check whether an experiment can supply its selection and learning evidence."""
    metadata = json.loads((directory / "run_metadata.json").read_text(encoding="utf-8"))
    if not isinstance(metadata, dict):
        raise ValueError("run_metadata.json must contain an object.")
    if metadata.get("phase") != "train" or metadata.get("status") != "COMPLETED":
        raise ValueError("The source must be a COMPLETED training experiment.")
    if metadata.get("dataset") != dataset or metadata.get("dataset_sha256") != dataset_sha256:
        raise ValueError("The training dataset name or CSV contents do not match the current dataset.")
    selected = metadata.get("selected_cases")
    if not isinstance(selected, list) or not selected or any(not isinstance(c, dict) for c in selected):
        raise ValueError("The training experiment has no valid selected_cases list.")
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
    incompatible, and older-format experiments without selection metadata.
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
            f"No completed training experiment matches {dataset!r} "
            f"and the current CSV in {root}. Complete a training run first, "
            "or set TRAINING_RUN_DIR to a compatible experiment."
        )
    return max(candidates, key=lambda item: (
        datetime.fromisoformat(item[1]["finished_at"]), item[0].name,
    ))


def finish_experiment(experiment_dir, exit_code: int, *, elapsed_seconds=None) -> int:
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
    if elapsed_seconds is not None:
        metadata["experiment_seconds"] = elapsed_seconds
        if (directory / "token_time.csv").is_file():
            metadata["usage_totals"] = _experiment_usage(directory, elapsed_seconds)
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
        "round_evidence": [],
        "usage_rounds": [],
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
    saved["round_failures"] = record.get("round_failures", [])
    saved["round_metrics"] = record.get("round_metrics", [])
    saved["phase"] = record["settings"].get("phase", "train")
    saved["mode"] = record["settings"].get("mode", "inference" if saved["phase"] == "infer" else "train")
    saved["retrieved_cases"] = record.get("retrieved_cases", [])
    saved["retrieved_examples"] = record.get("retrieved_examples", [])
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
            "status", "comparison_scope", "backend", "native_source", "native_metrics",
            "raw_scores", "accepted", "acceptance_reason",
            "native_similarity", "native_timing", "similarity_error", "evaluation_error",
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


# Readable debug evidence. Prompts, paths, and internal objects are not serialized.

def _debug_diagnosis_text(diagnosis: dict, statements: dict | None) -> str:
    """Show every answer and whether it survived the actual formatter."""
    lines = [f"{'Question':<44} {'Answer':<16} {'Noul':>5} {'Confidence':>10} Selection"]
    for name, result in diagnosis.get("answers", {}).items():
        answer = result["answer"]
        if isinstance(answer, bool):
            answer = "yes" if answer else "no"
        else:
            answer = str(answer)
        raw = diagnosis.get("raw_answers", {}).get(name, {})
        if statements is None:
            selected = "not formatted"
        else:
            selected = "kept" if name in statements else "excluded"
        lines.append(
            f"{name:<44} {answer:<16} {str(raw.get('noul', '-')):>5} "
            f"{str(result.get('confidence', '-')):>10} {selected}"
        )
    if len(lines) == 1:
        return "No diagnosis answers returned."
    return "\n".join(lines)


def _debug_event_text(record: dict, event: str, data: dict) -> str:
    """Render only the outputs and decisions useful when inspecting a case."""
    if event == "assertion_request":
        number = record["pending_attempt"]["round"]
        groups = "; ".join(
            ", ".join(rule["group"]) for rule in data.get("rules_used", [])
        ) or "none"
        return (
            f"\nROUND {number}\n=======\nRule groups used: {groups}\n\n"
            "ASSERTION GENERATOR OUTPUT"
        )
    if event == "assertion_response":
        return data["raw_response"]
    if event == "formal_check":
        formal = data["formal_result"]
        lines = ["\nFORMAL RESULT", f"Status: {formal['status']}"]
        for label, key in (
            ("Syntax", "syntax"), ("Strict PEC", "pec"), ("Relaxed PEC", "relax_pec"),
            ("BLEU", "bleu"), ("ROUGE-L", "rouge"), ("Exact match", "exact_match"),
        ):
            value = formal.get(key)
            lines.append(f"{label}: {'unavailable' if value is None else value}")
        if formal["status"] not in {"FULL_EQUIVALENCE", "IMPLIES", "NO_EQUIVALENCE"}:
            feedback = formal.get("feedback", "")
            details = feedback.partition("Tool details:\n")[2] or feedback
            if details:
                lines.extend(["Details:", details])
        return "\n".join(lines)
    if event == "diagnosis":
        selection = data.get("statements")
        if "selected_rules" in data:
            selection = {rule["question_id"]: rule["rule"] for rule in data["selected_rules"]}
        return "\nDIAGNOSIS OUTPUT\n" + _debug_diagnosis_text(
            data["diagnosis"], selection,
        )
    if event == "rule_selection":
        return "\nJEV-SELECTED RETRIEVED RULES\n" + json.dumps(data["selected_rules"], indent=2, ensure_ascii=False)
    if event == "statements":
        lines = [f"{name}: {text}" for name, text in data["statements"].items()]
        return "\nSTATEMENTS SENT TO RULE GENERATOR\n" + (
            "\n".join(lines) if lines else
            "None. Rule generation may explore potential issues using the background."
        )
    if event == "example_retrieval":
        return "\nRETRIEVED TRAINING EXAMPLES\n" + json.dumps(data["examples"], indent=2, ensure_ascii=False)
    if event == "retrieval":
        return "\nRETRIEVED TRAINING CASES\n" + json.dumps(data["cases"], indent=2)
    if event == "rule_request":
        return "\nRULE GENERATOR OUTPUT"
    if event == "rule_response":
        raw = data["raw_response"]
        try:
            return json.dumps(json.loads(raw), indent=2, ensure_ascii=False)
        except ValueError:
            return raw  # Preserve malformed output before parsing reports the error.
    if event == "rule_update":
        return "\nDECISION\nContinue: candidate not accepted; guidance is available for the next round."
    if event == "case_finished":
        reason = data["stop_reason"]
        explanation = {
            "passed": "The supplied FVRuleLearner PEC checker reported full equivalence.",
            "bleu_match": "BLEU is 1.0; accepted under FVRuleLearner's PEC-or-BLEU policy. Reported PEC/relaxed PEC are 1.0; raw scores remain in the formal result.",
            "max_rounds": "Maximum assertion attempts reached.",
            "no_guidance": "Rule generator returned no rules.",
            "interrupted": "Execution was interrupted by the user.",
        }.get(reason, f"Processing ended with {reason}.")
        lines = ["\nDECISION", f"Stop: {explanation}"]
        error = data.get("error")
        if error:
            lines.extend(["\nEXCEPTION / INTERRUPTION"])
            for label, key in (("Stage", "stage"), ("Type", "type"), ("Message", "message")):
                lines.append(f"{label}: {error.get(key, '(unavailable)')}")
            if error.get("traceback"):
                lines.extend(["Traceback:", error["traceback"]])
        if reason == "cleanup_failed":
            lines.append(record["formal"]["cleanup"]["reason"])
        lines.extend([
            "\nFINAL RESULT", f"Pipeline: {data['status']}", f"Passed: {data['passed']}",
            f"Rounds used: {record['rounds_used']}", f"Stop reason: {reason}",
        ])
        return "\n".join(lines)
    return ""


def save_debug_event(run_dir, record: dict, event: str, **data) -> None:
    """Append readable outputs as they arrive, including output preceding errors."""
    if not record["settings"].get("save_debug_traces", False):
        return
    text = _debug_event_text(record, event, data)
    if not text:
        return
    path = Path(run_dir) / "debug_trace.txt"
    first_write = not path.exists()
    with path.open("a", encoding="utf-8", newline="\n") as file:
        if first_write:
            inputs = record["inputs"]
            checker = record["settings"].get("checker")
            if checker:
                file.write(f"EVALUATION POLICY\n{checker}\n\n")
            file.write(
                f"REQUIREMENT\n{inputs.get('requirement', '')}\n\n"
                f"REFERENCE ASSERTION\n{inputs.get('reference_assertion', '')}\n\n"
            )
        file.write(text.rstrip() + "\n")


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
    # Structured learning evidence is retained even when readable tracing is off.
    record["round_evidence"].append({
        "round": round_number, "generated_assertion": None, "evaluation": None,
        "rules_used": deepcopy(rules), "rules_generated": {},
    })
    update_run(
        run_dir, record, stage="generation",
        rounds_used=round_number, pending_attempt=attempt,
    )
    save_debug_event(
        run_dir, record, "assertion_request", rules_used=rules,
    )
    return attempt


def record_formal_result(run_dir, record: dict, attempt: dict, formal: dict) -> None:
    """Publish matching assertion/verdict fields and append compact round scores."""
    # Native similarity and policy-adjusted formal scores are supplied by the
    # evaluation layer. Never recompute or overwrite them here.
    metric = {"round": attempt["round"], "status": formal["status"]}
    for name in SCORE_FIELDS:
        metric[name] = formal.get(name)  # Unavailable scores remain None.
    record["round_evidence"][-1]["evaluation"] = {
        **metric,
        "raw_scores": deepcopy(formal.get("raw_scores", {})),
        "accepted": formal.get("accepted", False),
        "acceptance_reason": formal.get("acceptance_reason"),
    }
    if record.get("usage_rounds"):
        record["usage_rounds"][-1]["passed"] = (
            formal.get("pec") == 1.0 or formal.get("bleu") == 1.0
        )
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

    # Guidance is exported separately from score traces. A passed case does not
    # establish that every individual rule caused the successful revision.
    rule_groups = {}
    rules = {}
    rule_rounds = {}
    for number, entry in enumerate(record["rule_registry"], start=1):
        rule_id = f"rule_{number}"
        rule_groups[rule_id] = entry["group"]
        rules[rule_id] = entry["rule"]
        rule_rounds[rule_id] = entry["updated_round"]

    learning = {
        "case_number": row["case_number"], "design_name": row["design_name"],
        "task_id": row["task_id"],
        "requirement": record["inputs"]["requirement"],
        "reference_assertion": record["inputs"]["reference_assertion"],
        "passed": record["passed"],
        "rule_groups": rule_groups,
        "rules": rules,
        "rule_rounds": rule_rounds,
        "round_evidence": record["round_evidence"],
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
    # BLEU loads lazily during scoring; metric errors must not stop fixing.
    case_started = perf_counter()
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
        finish_usage_round(record)
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
        try:
            save_usage(
                directory if summary_dir is None else summary_dir,
                record, perf_counter() - case_started,
            )
        except Exception as error:
            record["summary_error"] = f"Usage save failed: {type(error).__name__}: {error}"
            save_run(directory, record)
            if exit_code == 0:
                exit_code = 1
        print_summary(directory, record)

    return exit_code


# Terminal summary.

def print_summary(run_dir, record: dict) -> None:
    """Print the outcome and result path; terminal output is not saved."""
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
        print(f"Native BLEU: {formal.get('bleu')} | ROUGE-L: {formal.get('rouge')} | "
              f"Exact match: {formal.get('exact_match')}")
        cleanup = formal.get("cleanup")
        if cleanup and cleanup["retained"]:
            print("Work retained:", cleanup["reason"])
    if record["error"]:
        error = record["error"]
        print(f"Error at {error['stage']}: {error['type']}: {error['message']}")
    if record["trace_error"]:
        print("Trace save error:", record["trace_error"])
    if record.get("round_failures"):
        print(f"Round-stage errors: {len(record['round_failures'])}; see result.json round_failures.")
    if record["summary_error"]:
        print("Summary save error:", record["summary_error"])
    print("Result:", Path(run_dir) / "result.json")



