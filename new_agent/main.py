"""Prepare training cases, then generate/check/revise each case independently."""

from copy import deepcopy
from math import isfinite
from pathlib import Path
from time import perf_counter

from openai import OpenAI

import assertion_generator
import config
import dataset_loader
import formal_check
import rule_generator
import run_io
from diagnosis_formatter import format_diagnosis
from jev_assertion_diagnosis import diagnose_assertion_mismatches


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
        }


def retained_rules(registry: dict) -> list[dict]:
    """Copy retained rules so later updates cannot change an earlier snapshot."""
    return deepcopy([registry[key] for key in sorted(registry)])


def validate_config() -> None:
    """Check active settings once, before creating a run or making API calls."""
    if not isinstance(config.DATASET, str) or not config.DATASET.strip():
        raise ValueError("DATASET must be a nonempty dataset name.")
    if config.DATASET not in {"nl2sva_human", "nl2sva_machine"}:
        raise ValueError("DATASET must be 'nl2sva_human' or 'nl2sva_machine'.")
    if type(config.MAX_ROUNDS) is not int or config.MAX_ROUNDS < 1:
        raise ValueError("MAX_ROUNDS must be a positive integer.")
    for name in ("ASSERTION_MODEL", "RULE_MODEL"):
        value = getattr(config, name)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{name} must be a nonempty model name.")
    timeout = config.JASPER_TIMEOUT_SECONDS
    if type(timeout) not in (int, float) or not isfinite(timeout) or timeout <= 0:
        raise ValueError("JASPER_TIMEOUT_SECONDS must be a finite positive number.")
    confidence = config.CONFIDENCE_THRESHOLD
    if (
        type(confidence) not in (int, float)
        or not isfinite(confidence)
        or not 0 <= confidence <= 1
    ):
        raise ValueError("CONFIDENCE_THRESHOLD must be a number between 0 and 1.")
    if type(config.SAVE_DEBUG_TRACES) is not bool:
        raise ValueError("SAVE_DEBUG_TRACES must be True or False.")


def _failed_round(directory, round_number, status, message, policy):
    """Represent an unsuccessful attempt without inventing formal scores."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    log_path = directory / "jasper.log"
    log_path.write_text(message + "\n", encoding="utf-8")
    candidate_error = status in {"FORMAT_ERROR", "INPUT_ERROR"}
    return {
        "status": status,
        "syntax": 0.0 if candidate_error else None,
        "pec": 0.0 if candidate_error else None,
        "relax_pec": 0.0 if candidate_error else None,
        "generated_reset": "", "reference_reset": "", "reset_mismatch": None,
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
    print(f"Round {number}: {stage}: {type(error).__name__}: {error}; continuing.", flush=True)


def run_pipeline(directory, record: dict) -> int:
    """Stop on strict PEC success or exhaustion of the configured attempt budget.

    Ordinary generation, extraction, checker, diagnosis and rule-output errors
    are round outcomes. KeyboardInterrupt/SystemExit are deliberately not caught.
    File-system failures can still prevent reliable recording and must propagate.
    """
    inputs = record["inputs"]
    policy = formal_check.get_evaluation_policy(inputs.get("dataset", config.DATASET))
    comparison_scope = policy["scope"]
    registry = {}
    previous_assertion = None
    revision_feedback = None
    client = None

    for round_number in range(1, config.MAX_ROUNDS + 1):
        run_io.start_usage_round(record, round_number)
        selected_rules = [r for r in retained_rules(registry)
                          if r["updated_round"] == round_number - 1]
        # A failed call before extraction must never associate old text with new scores.
        attempt = run_io.start_attempt(
            directory, record, round_number,
            system_prompt=assertion_generator.SYSTEM_PROMPT,
            user_prompt="", rules=selected_rules,
        )
        check_dir = Path(directory) / "formal_rounds" / f"round_{round_number:04d}"
        check_dir.mkdir(parents=True, exist_ok=False)
        generated_assertion = None
        stage = "generation"
        try:
            user_prompt = assertion_generator.build_generation_prompt(
                requirement=inputs["requirement"], testbench=inputs["testbench"],
                previous_assertion=previous_assertion, rules=selected_rules,
                comparison_scope=comparison_scope, revision_feedback=revision_feedback,
            )
            attempt["prompts"]["user"] = user_prompt
            run_io.update_run(directory, record, stage=stage)
            if client is None:
                client = OpenAI()
            with run_io.measure_stage(record, "assertion") as capture_usage:
                response_text = assertion_generator.generate_assertion(
                    client=client, model=config.ASSERTION_MODEL, user_prompt=user_prompt,
                    usage_callback=capture_usage,
                )
            attempt["generation"]["raw_response"] = response_text
            run_io.save_debug_event(directory, record, "assertion_response", raw_response=response_text)
            stage = "extraction"
            run_io.update_run(directory, record, stage=stage)
            generated_assertion = assertion_generator.extract_assertion(response_text)
            attempt["generation"]["assertion"] = generated_assertion
            previous_assertion = generated_assertion
            stage = "formal_check"
            run_io.update_run(directory, record, stage=stage)
            with run_io.measure_stage(record, "tool"):
                formal_result = formal_check.evaluate_assertion(
                    generated_assertion=generated_assertion,
                    reference_assertion=inputs["reference_assertion"],
                    testbench=inputs["testbench"], requirement=inputs["requirement"],
                    run_dir=check_dir, timeout_seconds=config.JASPER_TIMEOUT_SECONDS,
                    task_id=inputs["task_id"], dataset=inputs.get("dataset", config.DATASET),
                )
        except Exception as error:
            _remember_round_error(directory, record, round_number, stage, error)
            status = {"generation": "GENERATION_ERROR", "extraction": "FORMAT_ERROR"}.get(stage, "TOOL_ERROR")
            formal_result = _failed_round(
                check_dir, round_number, status, f"{stage}: {type(error).__name__}: {error}", policy,
            )

        run_io.record_formal_result(directory, record, attempt, formal_result)
        run_io.update_run(directory, record, stage="cleanup")
        run_io.cleanup_formal_work(directory, record, formal_check.cleanup_work)
        status = formal_result["status"]
        passed = formal_result.get("pec") == 1.0
        print(f"Round {round_number}/{config.MAX_ROUNDS}: {status}", flush=True)
        if passed:
            run_io.update_run(
                directory, record, status="PASSED", passed=True, stage="finished",
                stop_reason="passed",
                diagnosis_skipped_reason="The supplied PEC checker reported full equivalence.",
            )
            return 0

        # Feedback for generation never includes the reference or PEC's expressions.
        if status == "INPUT_ERROR" and formal_result.get("error_origin") == "candidate":
            revision_feedback = formal_result["tool_output"]
        elif status in {"FORMAT_ERROR", "INPUT_ERROR", "SYNTAX_ERROR"}:
            revision_feedback = (
                "The previous candidate could not be accepted as a complete SVA assertion. "
                "Use asrt: assert property (@(posedge clk) [optional disable iff (...)] BODY); "
                "with the label before assert and the whole property inside parentheses. "
                "Enclose the statement in one systemverilog code block."
            )
        elif status in {"PEC_COMPILE_ERROR", "TOOL_ERROR", "TIMEOUT", "INCONCLUSIVE", "GENERATION_ERROR"}:
            revision_feedback = (
                "The preceding attempt did not obtain an equivalence verdict. "
                "Re-derive a complete assertion from the requirement and testbench; "
                "preserve the declared signal types, widths and valid bit selections."
            )
        else:
            revision_feedback = None

        if round_number == config.MAX_ROUNDS:
            run_io.update_run(directory, record, diagnosis_skipped_reason="Round budget exhausted.")
            continue
        if status not in {"IMPLIES", "NO_EQUIVALENCE"}:
            run_io.update_run(
                directory, record,
                diagnosis_skipped_reason="No completed semantic comparison; retry without semantic rule learning.",
            )
            continue

        stage = "diagnosis"
        try:
            run_io.update_run(directory, record, stage=stage)
            with run_io.measure_stage(record, "diagnosis") as capture_usage:
                diagnosis = diagnose_assertion_mismatches(
                    requirement=inputs["requirement"], generated_assertion=generated_assertion,
                    reference_assertion=inputs["reference_assertion"],
                    design_context=inputs["testbench"], formal_feedback=formal_result["feedback"],
                    comparison_scope=comparison_scope, usage_callback=capture_usage,
                )
            stage = "formatting"
            run_io.update_run(directory, record, stage=stage, diagnosis=diagnosis,
                              diagnosis_model=diagnosis.get("model"))
            run_io.save_diagnosis_model(record, diagnosis.get("model"))
            statements = None
            try:
                statements = format_diagnosis(diagnosis["answers"], confidence_threshold=config.CONFIDENCE_THRESHOLD)
            finally:
                run_io.save_debug_event(directory, record, "diagnosis", diagnosis=diagnosis, statements=statements)
            run_io.update_run(directory, record, statements=statements)
            run_io.save_debug_event(directory, record, "statements", statements=statements)
            stage = "rule_generation"
            run_io.update_run(directory, record, stage=stage)
            rule_prompt = rule_generator.build_rule_prompt(
                requirement=inputs["requirement"], generated_assertion=generated_assertion,
                reference_assertion=inputs["reference_assertion"], statements=statements,
                testbench=inputs["testbench"], comparison_scope=comparison_scope,
                formal_feedback=formal_result["feedback"],
            )
            rule_attempt = {"round": round_number, "model": config.RULE_MODEL,
                            "raw_response": None, "rules": None}
            run_io.update_run(directory, record, last_rule_generation=rule_attempt)
            run_io.save_debug_event(directory, record, "rule_request")
            with run_io.measure_stage(record, "rule") as capture_usage:
                rule_response = rule_generator.generate_rules(
                    client=client, model=config.RULE_MODEL, user_prompt=rule_prompt,
                    usage_callback=capture_usage,
                )
            rule_attempt["raw_response"] = rule_response
            run_io.save_debug_event(directory, record, "rule_response", raw_response=rule_response)
            stage = "rule_validation"
            run_io.update_run(directory, record, stage=stage)
            new_rules = rule_generator.parse_rules(rule_response)
            rule_attempt["rules"] = new_rules
            rule_generator.check_rule_groups(new_rules, statements)
            # Commit only a completely validated update; never leave a partial registry.
            replacement = deepcopy(registry)
            update_rule_registry(replacement, new_rules, round_number)
            registry = replacement
            run_io.update_run(directory, record, rule_registry=retained_rules(registry))
            if new_rules:
                run_io.save_debug_event(directory, record, "rule_update", rule_registry=record["rule_registry"])
        except Exception as error:
            _remember_round_error(directory, record, round_number, stage, error)
            run_io.update_run(directory, record, diagnosis_skipped_reason=f"{stage} failed; continuing next round.")

    # No earlier pass is possible here. Keep the latest attempt and its scores.
    last = record["formal"]
    resolved = last["status"] in {"IMPLIES", "NO_EQUIVALENCE", "SYNTAX_ERROR", "FORMAT_ERROR"} or (
        last["status"] == "INPUT_ERROR" and last.get("error_origin") == "candidate"
    )
    run_io.update_run(
        directory, record, status="COMPLETED" if resolved else "CHECKER_UNRESOLVED",
        passed=False, stage="finished", stop_reason="max_rounds",
    )
    return 0 if resolved else 1



def main() -> int:
    """Load cases once; use the existing round workflow separately for each."""
    experiment_started = perf_counter()
    # 1. Validate the configuration, CSV, and complete selection before any API call.
    validate_config()
    policy = formal_check.get_evaluation_policy(config.DATASET)
    cases, dataset_split = dataset_loader.load_training_cases(
        config.DATASET_PATH, config.CASE_IDS,
        train_fraction=config.TRAIN_FRACTION, split_seed=config.SPLIT_SEED,
    )
    dataset_path = Path(cases[0]["dataset_path"])
    models = {"assertion": config.ASSERTION_MODEL, "rule": config.RULE_MODEL}
    settings = {
        "dataset": config.DATASET,
        "dataset_path": str(dataset_path),
        "checker": "fvrulelearner_pec",
        "comparison_scope": policy["scope"],
        "revision_rules": "previous_round_only",
        "round_policy": "pass_or_max_rounds",
        "case_ids": list(config.CASE_IDS),
        "dataset_split": dataset_split,
        "max_rounds": config.MAX_ROUNDS,
        "timeout_seconds": config.JASPER_TIMEOUT_SECONDS,
        "confidence_threshold": config.CONFIDENCE_THRESHOLD,
        "runs_dir": str(config.RUNS_DIR),
        "save_debug_traces": config.SAVE_DEBUG_TRACES,
    }

    # 2. Create one experiment containing shared summaries and separate case folders.
    experiment_dir = run_io.create_experiment(
        dataset=config.DATASET, dataset_path=dataset_path, cases=cases,
        models=models, settings=settings, runs_root=config.RUNS_DIR,
        phase="train",
    )
    print("Dataset:", dataset_path)
    print("Evaluation scope:", policy["scope"])
    if dataset_split is not None:
        print(
            f"Random split: {len(cases)} training | "
            f"{len(dataset_split['inference_case_ids'])} reserved for inference | "
            f"seed {dataset_split['seed']}"
        )
    else:
        print("Explicit case selection: random splitting is not applied.")
    print("Selected case IDs:", [case["case_number"] for case in cases])
    print("Experiment:", experiment_dir)

    # 3. Run each selected case with its own revision loop and rule registry.
    exit_code = 0
    try:
        for position, case in enumerate(cases, start=1):
            print(
                f"\nRunning {position}/{len(cases)}: case {case['case_number']} | "
                f"{case['design_name']} / {case['task_id']}"
            )
            case_exit = run_io.run_experiment(
                workflow=run_pipeline,
                cleanup_work=formal_check.cleanup_work,
                case_id=case["task_id"],
                case_dir=experiment_dir / "cases" / f"case_{case['case_number']:04d}",
                summary_dir=experiment_dir,
                models=models,
                inputs={**case, "dataset": config.DATASET},
                prompts={},
                settings=settings,
            )
            if case_exit == 130:
                exit_code = 130
                break
            if case_exit != 0:
                exit_code = 1  # Record the case error; continue to the next selected case.
    except KeyboardInterrupt:
        exit_code = 130
    except Exception:
        exit_code = 1
        raise
    finally:
        exit_code = run_io.finish_experiment(
            experiment_dir, exit_code,
            elapsed_seconds=perf_counter() - experiment_started,
        )

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())



