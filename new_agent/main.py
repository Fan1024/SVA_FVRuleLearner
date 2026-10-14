"""Run one counter case: generate, check, learn rules, and revise."""

from copy import deepcopy

from openai import OpenAI

import assertion_generator
import counter_example as example
import formal_check
import rule_generator
import run_io
from diagnosis_formatter import format_diagnosis, format_reset_mismatch
from jev_assertion_diagnosis import diagnose_assertion_mismatches


MODEL = "gpt-5.6-terra"
CASE_ID = "counter_0"
MAX_ROUNDS = 2  # Initial attempt plus one guided revision.
TIMEOUT_SECONDS = 300
CONFIDENCE_THRESHOLD = 0.4
KEEP_WORK = False


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


def run_pipeline(directory, record: dict) -> int:
    """Keep experiment decisions here; delegate record/file handling to run_io."""
    if type(MAX_ROUNDS) is not int or MAX_ROUNDS < 1:
        raise ValueError("MAX_ROUNDS must be a positive integer.")
    if KEEP_WORK and MAX_ROUNDS > 1:
        raise ValueError("Use KEEP_WORK=False when reusing _work across rounds.")

    client = OpenAI()
    inputs = record["inputs"]
    registry = {}
    previous_assertion = None

    for round_number in range(1, MAX_ROUNDS + 1):
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
            client=client, model=MODEL, user_prompt=user_prompt,
        )
        attempt["generation"]["raw_response"] = response_text
        run_io.update_run(directory, record, stage="extraction")
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
            timeout_seconds=TIMEOUT_SECONDS,
        )
        run_io.record_formal_result(directory, record, attempt, formal_result)
        run_io.update_run(directory, record, stage="cleanup")
        cleanup = run_io.cleanup_formal_work(
            directory, record, formal_check.cleanup_work, keep_work=KEEP_WORK,
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

        if formal_result["pec"] == 1.0 and formal_result["reset_mismatch"] is False:
            run_io.update_run(
                directory, record, status="PASSED", stage="finished",
                passed=True, stop_reason="passed",
                diagnosis_skipped_reason="Strict body PEC passed and reset names match.",
            )
            return 0

        if round_number == MAX_ROUNDS:
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
        run_io.update_run(directory, record, stage="formatting", diagnosis=diagnosis)
        statements = format_diagnosis(
            diagnosis["answers"], confidence_threshold=CONFIDENCE_THRESHOLD,
        )
        statements.update(format_reset_mismatch(formal_result))
        run_io.update_run(directory, record, statements=statements)
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
        new_rules = rule_generator.generate_rules(
            client=client, model=MODEL, user_prompt=rule_prompt,
        )
        run_io.update_run(directory, record, stage="rule_validation")
        rule_generator.check_rule_groups(new_rules, statements)
        if not new_rules:
            return stop_pipeline(directory, record, "no_guidance")

        run_io.update_run(directory, record, stage="rule_update")
        update_rule_registry(registry, new_rules, round_number)
        run_io.update_run(directory, record, rule_registry=retained_rules(registry))
        previous_assertion = generated_assertion

    raise RuntimeError("The round loop ended without a terminal outcome.")


def main() -> int:
    """Supply the fixed case and let run_io manage execution and summaries."""
    return run_io.run_experiment(
        workflow=run_pipeline,
        cleanup_work=formal_check.cleanup_work,
        case_id=CASE_ID,
        model=MODEL,
        inputs={
            "dataset": "nl2sva_human",
            "design_name": "counter",
            "requirement": example.REQUIREMENT,
            "testbench": example.TESTBENCH,
            "reference_assertion": example.REFERENCE_ASSERTION,
        },
        prompts={},
        settings={
            "max_rounds": MAX_ROUNDS,
            "timeout_seconds": TIMEOUT_SECONDS,
            "confidence_threshold": CONFIDENCE_THRESHOLD,
            "keep_work": KEEP_WORK,
        },
    )


if __name__ == "__main__":
    raise SystemExit(main())

