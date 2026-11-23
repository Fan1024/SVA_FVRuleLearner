"""Shared rule-registry and failed-round helpers for the three active pipelines."""

from copy import deepcopy
from pathlib import Path
from new_agent import run_io


def update_rule_registry(registry: dict, new_rules: dict, round_number: int) -> None:
    """Replace exact groups; retain different groups, including overlaps."""
    keys = [tuple(sorted(set(entry["group"]))) for entry in new_rules.values()]
    if len(keys) != len(set(keys)):
        raise ValueError("Rule output contains duplicate canonical groups.")

    for key, entry in zip(keys, new_rules.values()):
        earlier = registry.get(key)
        registry[key] = {
            "group": list(key),
            "rule": entry["rule"].strip(),
            "first_learned_round": (
                earlier["first_learned_round"] if earlier else round_number
            ),
            "updated_round": round_number,
            **({'location': entry['location']} if entry.get('location') else {}),
            **({'diagnoses': deepcopy(entry['diagnoses'])} if 'diagnoses' in entry else {}),
        }


def retained_rules(registry: dict) -> list[dict]:
    """Copy retained rules so later updates cannot change an earlier snapshot."""
    return deepcopy([registry[key] for key in sorted(registry)])


def _failed_round(directory, round_number, status, message, policy):
    """Represent an unsuccessful attempt without inventing formal scores."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    log_path = directory / "jasper.log"
    log_path.write_text(message + "\n", encoding="utf-8")
    return {
        "status": status,
        "syntax": None,
        "pec": None,
        "relax_pec": None,
        "bleu": None, "rouge": None, "exact_match": None,
        "comparison_scope": policy["scope"], "returncode": None,
        "source_task_id": "", "tool_task_id": f"round_{round_number:04d}",
        "run_dir": str(directory), "work_dir": str(directory / "_work"),
        "log_path": str(log_path), "input_path": str(directory / "formal_input.sva"),
        "tool_output": message, "feedback": message,
    }


def _remember_round_error(directory, record, number, stage, error):
    failures = record.setdefault("round_failures", [])
    failures.append({
        "round": number, "stage": stage,
        "type": type(error).__name__, "message": str(error),
    })
    run_io.update_run(directory, record, round_failures=failures)
    message = str(error).splitlines()
    message = message[0][:180] if message else ""
    print(f"Round {number} | {stage}: {type(error).__name__}: {message}", flush=True)
