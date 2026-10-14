"""Run the fixed counter example: generate, check, and diagnose."""

from openai import OpenAI

import assertion_generator
import counter_example as example
import formal_check
import run_io
from diagnosis_formatter import format_diagnosis
from jev_assertion_diagnosis import diagnose_assertion_mismatches


MODEL = "gpt-5.6-terra"
CASE_ID = "counter_0"
TIMEOUT_SECONDS = 300
CONFIDENCE_THRESHOLD = 0.4
KEEP_WORK = False


def run_pipeline(directory, record: dict) -> int:
    """Keep the experiment steps visible; run_io handles saving and failures."""
    # 1. Generate one assertion. Preserve the response even if extraction fails.
    run_io.update_run(directory, record, stage="generation")
    response_text = assertion_generator.generate_assertion(
        client=OpenAI(), model=MODEL, user_prompt=record["prompts"]["user"],
    )
    run_io.update_run(
        directory, record,
        generation={"raw_response": response_text, "assertion": None},
    )
    generated_assertion = assertion_generator.extract_assertion(response_text)
    run_io.update_run(
        directory, record, stage="formal_check",
        generation={"raw_response": response_text, "assertion": generated_assertion},
    )

    # 2. Run the existing formal checker, using the same inputs and scores.
    formal_result = formal_check.evaluate_assertion(
        generated_assertion=generated_assertion,
        reference_assertion=example.REFERENCE_ASSERTION,
        testbench=example.TESTBENCH,
        requirement=example.REQUIREMENT,
        run_dir=directory,
        timeout_seconds=TIMEOUT_SECONDS,
    )
    run_io.update_run(directory, record, formal=formal_result)

    # 3. Decide whether diagnosis is useful.
    if formal_result["status"] in {
        "INPUT_ERROR", "TOOL_ERROR", "TIMEOUT", "INCONCLUSIVE",
    }:
        run_io.update_run(
            directory, record, status="CHECKER_UNRESOLVED",
            diagnosis_skipped_reason="Diagnosis skipped: resolve the checker result first.",
        )
        return 1

    if formal_result["pec"] == 1.0 and formal_result["reset_mismatch"] is False:
        run_io.update_run(
            directory, record, status="PASSED",
            diagnosis_skipped_reason=(
                "Strict body PEC passed and reset names match; diagnosis skipped."
            ),
        )
        return 0

    # 4. Diagnose the mismatch, then format the answers.
    run_io.update_run(directory, record, stage="diagnosis")
    diagnosis = diagnose_assertion_mismatches(
        requirement=example.REQUIREMENT,
        generated_assertion=generated_assertion,
        reference_assertion=example.REFERENCE_ASSERTION,
        design_context=example.TESTBENCH,
        formal_feedback=formal_result["feedback"],
    )
    run_io.update_run(directory, record, stage="formatting", diagnosis=diagnosis)
    statements = format_diagnosis(
        diagnosis["answers"], confidence_threshold=CONFIDENCE_THRESHOLD,
    )
    run_io.update_run(directory, record, status="COMPLETED", statements=statements)
    return 0


def main() -> int:
    """Prepare this example and let run_io manage its execution record."""
    user_prompt = assertion_generator.build_generation_prompt(
        requirement=example.REQUIREMENT, testbench=example.TESTBENCH,
    )
    return run_io.run_experiment(
        workflow=run_pipeline,
        cleanup_work=formal_check.cleanup_work,
        case_id=CASE_ID,
        model=MODEL,
        inputs={
            "requirement": example.REQUIREMENT,
            "testbench": example.TESTBENCH,
            "reference_assertion": example.REFERENCE_ASSERTION,
        },
        prompts={"system": assertion_generator.SYSTEM_PROMPT, "user": user_prompt},
        settings={
            "timeout_seconds": TIMEOUT_SECONDS,
            "confidence_threshold": CONFIDENCE_THRESHOLD,
            "keep_work": KEEP_WORK,
        },
    )


if __name__ == "__main__":
    raise SystemExit(main())
