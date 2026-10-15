"""Select dataset cases, then generate/check/revise each case independently."""

from copy import deepcopy
from math import isfinite
from pathlib import Path

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


def stop_pipeline(directory, record: dict, reason: str, *, unresolved=False) -> int:
    """Record why processing stopped; raw formal scores remain unchanged."""
    run_io.update_run(
        directory, record,
        status="CHECKER_UNRESOLVED" if unresolved else "COMPLETED",
        stage="finished", stop_reason=reason, passed=False,
    )
    return 1 if unresolved else 0


def validate_config() -> None:
    """Check active settings once, before creating a run or making API calls."""
    if not isinstance(config.DATASET, str) or not config.DATASET.strip():
        raise ValueError("DATASET must be a nonempty dataset name.")
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


def run_pipeline(directory, record: dict) -> int:
    """Run the existing round loop for ONE case. Each call has fresh rules."""
    client = OpenAI()
    inputs = record["inputs"]
    registry = {}
    previous_assertion = None

    for round_number in range(1, config.MAX_ROUNDS + 1):
        # 1. Build a fresh prompt and generate one assertion.
        selected_rules = retained_rules(registry)
        user_prompt = assertion_generator.build_generation_prompt(
            requirement=inputs["requirement"],
            testbench=inputs["testbench"],
            previous_assertion=previous_assertion,
            rules=selected_rules,
        )
        attempt = run_io.start_attempt(
            directory, record, round_number,
            system_prompt=assertion_generator.SYSTEM_PROMPT,
            user_prompt=user_prompt,
            rules=selected_rules,
        )
        response_text = assertion_generator.generate_assertion(
            client=client, model=config.ASSERTION_MODEL, user_prompt=user_prompt,
        )
        attempt["generation"]["raw_response"] = response_text
        run_io.update_run(directory, record, stage="extraction")
        run_io.save_debug_event(
            directory, record, "assertion_response", raw_response=response_text,
        )
        generated_assertion = assertion_generator.extract_assertion(response_text)
        attempt["generation"]["assertion"] = generated_assertion
        run_io.update_run(directory, record, stage="formal_check")

        # 2. Check the assertion, record its verdict, and clean temporary work.
        run_io.prepare_formal_check(directory)
        formal_result = formal_check.evaluate_assertion(
            generated_assertion=generated_assertion,
            reference_assertion=inputs["reference_assertion"],
            testbench=inputs["testbench"],
            requirement=inputs["requirement"],
            run_dir=directory,
            timeout_seconds=config.JASPER_TIMEOUT_SECONDS,
            task_id=inputs["task_id"],
        )
        run_io.record_formal_result(directory, record, attempt, formal_result)
        run_io.update_run(directory, record, stage="cleanup")
        cleanup = run_io.cleanup_formal_work(
            directory, record, formal_check.cleanup_work,
        )

        # 3. Decide whether another revision is possible and necessary.
        if formal_result["status"] in {
            "INPUT_ERROR", "TOOL_ERROR", "TIMEOUT", "INCONCLUSIVE",
        }:
            run_io.update_run(
                directory, record,
                diagnosis_skipped_reason="Resolve the checker result before diagnosis.",
            )
            return stop_pipeline(
                directory, record, formal_result["status"].lower(), unresolved=True,
            )

        if formal_result["pec"] == 1.0:
            run_io.update_run(
                directory, record, status="PASSED", stage="finished",
                passed=True, stop_reason="passed",
                diagnosis_skipped_reason="Strict body PEC passed; reset is informational.",
            )
            return 0

        if round_number == config.MAX_ROUNDS:
            run_io.update_run(
                directory, record,
                diagnosis_skipped_reason="Round budget exhausted; no further revision.",
            )
            return stop_pipeline(directory, record, "max_rounds")

        if cleanup["retained"]:
            return stop_pipeline(directory, record, "cleanup_failed", unresolved=True)

        # 4. Diagnose this failure and format current correction hypotheses.
        run_io.update_run(directory, record, stage="diagnosis")
        diagnosis = diagnose_assertion_mismatches(
            requirement=inputs["requirement"],
            generated_assertion=generated_assertion,
            reference_assertion=inputs["reference_assertion"],
            design_context=inputs["testbench"],
            formal_feedback=formal_result["feedback"],
        )
        run_io.update_run(
            directory, record, stage="formatting", diagnosis=diagnosis,
            diagnosis_model=diagnosis.get("model"),
        )
        run_io.save_debug_event(directory, record, "diagnosis", diagnosis=diagnosis)
        statements = format_diagnosis(
            diagnosis["answers"], confidence_threshold=config.CONFIDENCE_THRESHOLD,
        )
        run_io.update_run(directory, record, statements=statements)
        run_io.save_debug_event(directory, record, "statements", statements=statements)
        if not statements:
            return stop_pipeline(directory, record, "no_guidance")

        # 5. Learn rules from current statements; Python manages older rules.
        run_io.update_run(directory, record, stage="rule_generation")
        rule_prompt = rule_generator.build_rule_prompt(
            requirement=inputs["requirement"],
            generated_assertion=generated_assertion,
            reference_assertion=inputs["reference_assertion"],
            statements=statements,
            testbench=inputs["testbench"],
        )
        rule_attempt = {
            "round": round_number, "model": config.RULE_MODEL,
            "raw_response": None, "rules": None,
        }
        run_io.update_run(directory, record, last_rule_generation=rule_attempt)
        run_io.save_debug_event(
            directory, record, "rule_request", model=config.RULE_MODEL,
            system_prompt=rule_generator.SYSTEM_PROMPT, user_prompt=rule_prompt,
        )
        rule_response = rule_generator.generate_rules(
            client=client, model=config.RULE_MODEL, user_prompt=rule_prompt,
        )
        rule_attempt["raw_response"] = rule_response
        run_io.update_run(directory, record, stage="rule_validation")
        run_io.save_debug_event(directory, record, "rule_response", raw_response=rule_response)
        new_rules = rule_generator.parse_rules(rule_response)
        rule_attempt["rules"] = new_rules
        rule_generator.check_rule_groups(new_rules, statements)
        if not new_rules:
            return stop_pipeline(directory, record, "no_guidance")

        run_io.update_run(directory, record, stage="rule_update")
        update_rule_registry(registry, new_rules, round_number)
        run_io.update_run(directory, record, rule_registry=retained_rules(registry))
        run_io.save_debug_event(
            directory, record, "rule_update", rule_registry=record["rule_registry"],
        )
        previous_assertion = generated_assertion

    raise RuntimeError("The round loop ended without a terminal outcome.")


def main() -> int:
    """Load cases once; use the existing round workflow separately for each."""
    # 1. Validate the configuration, CSV, and complete selection before any API call.
    validate_config()
    cases = dataset_loader.load_cases(config.DATASET_PATH, config.CASE_IDS)
    dataset_path = Path(cases[0]["dataset_path"])
    models = {"assertion": config.ASSERTION_MODEL, "rule": config.RULE_MODEL}
    settings = {
        "dataset": config.DATASET,
        "dataset_path": str(dataset_path),
        "checker": formal_check.CHECKER_NAME,
        "case_ids": list(config.CASE_IDS),
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
    )
    print("Dataset:", dataset_path)
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
        exit_code = run_io.finish_experiment(experiment_dir, exit_code)

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
