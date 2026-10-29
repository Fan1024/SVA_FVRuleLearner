"""Training-only tree/rule loop; the original pipeline remains the inference path.

PEC/BLEU evaluation, acceptance, retries and round budgets use the existing
checker and policies. Only the training diagnosis/rule stages are replaced.
"""
from copy import deepcopy
from contextlib import contextmanager
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from openai import OpenAI
from new_agent import config, formal_check, model_io, run_io
from new_agent.pipeline import (
    _failed_round, _remember_round_error, retained_rules, update_rule_registry,
)


@contextmanager
def _save_round_trace(directory, record, round_number):
    """Lazy per-case JSONL: case/reference once, diagnosis once per round."""
    from new_agent.train_tree_rule_generator import compact_tree
    try:
        yield
    finally:
        evidence = next((item for item in reversed(record["round_evidence"])
                         if item["round"] == round_number), {})
        failures = [item for item in record.get("round_failures", [])
                    if item["round"] == round_number]
        output = evidence.get("tree_rule_diagnosis")
        raw = evidence.get("tree_rule_raw_response")
        trees = evidence.get("assertion_trees")
        evaluation = evidence.get("evaluation")
        error_type, error, _ = sys.exc_info()
        entry = {
            "round": round_number,
            "assertion": evidence.get("generated_assertion"),
            "evaluation": evaluation,
            "diagnosis_from_round": evidence.get("diagnosis_from_round"),
        }
        if trees and "generated" in trees:
            entry["generated_tree"] = compact_tree(trees["generated"], include_source=False)
        if output is not None:
            # Store the response once as readable JSON, not raw + parsed + extracted copies.
            entry["diagnosis"] = output
        elif raw is not None:
            entry["diagnosis_raw"] = raw
        else:
            entry["diagnosis_skipped"] = (
                "candidate_accepted" if evaluation and evaluation.get("accepted") else
                "round_budget_exhausted" if round_number == config.MAX_ROUNDS else
                record.get("diagnosis_skipped_reason", "not_run"))
        if failures:
            entry["errors"] = failures
        if error_type is not None:
            entry["interruption"] = {"type": error_type.__name__, "message": str(error)}
        inputs = record["inputs"]
        root = Path(record.get("summary_directory", directory)) / "rules"
        path = root / f"case_{inputs['case_number']:04d}.jsonl"
        pending = record.setdefault("_pending_rule_trace", [])
        pending.append(entry)
        if path.exists() or raw is not None or output is not None or trees is not None or failures:
            root.mkdir(parents=True, exist_ok=True)
            if not record.get("_rule_trace_initialized"):
                first = pending[0]
                first["case"] = {key: inputs[key] for key in ("case_number", "design_name", "task_id")}
                first["reference_assertion"] = inputs.get("reference_assertion")
                record["_rule_trace_initialized"] = True
            if trees and "reference" in trees and not record.get("_reference_tree_saved"):
                pending[-1]["reference_tree"] = compact_tree(trees["reference"], include_source=False)
                record["_reference_tree_saved"] = True
            with path.open("a", encoding="utf-8") as stream:
                for row in pending:
                    stream.write(json.dumps(row, ensure_ascii=False) + "\n")
                stream.flush()
            pending.clear()
            record["rule_trace_file"] = f"rules/{path.name}"


def run_training_pipeline(directory, record: dict, *, retriever=None) -> int:
    """Stop on PEC/BLEU success or exhaustion of the configured attempt budget.

    Ordinary generation, extraction, checker, diagnosis and rule-output errors
    are round outcomes. KeyboardInterrupt/SystemExit are deliberately not caught.
    File-system failures can still prevent reliable recording and must propagate.
    """
    if record["settings"].get("phase", "train") != "train":
        raise ValueError("The tree pipeline is training-only.")
    if retriever is not None:
        raise ValueError("Training does not accept an inference retriever.")
    from new_agent import train_assertion_generator as assertion_generator
    from new_agent import train_tree_rule_generator as rule_generator
    inputs = record["inputs"]
    policy = formal_check.get_evaluation_policy(inputs.get("dataset", config.DATASET))
    comparison_scope = policy["scope"]
    registry = {}
    previous_assertion = None
    revision_feedback = None
    client = None
    latest_diagnosis_response = None
    latest_generated_tree = None
    latest_diagnosis_round = None

    for round_number in range(1, config.MAX_ROUNDS + 1):
        with _save_round_trace(directory, record, round_number):
            run_io.start_usage_round(record, round_number)
            # A failed call before extraction must never associate old text with new scores.
            attempt = run_io.start_attempt(
                directory, record, round_number,
                system_prompt=assertion_generator.SYSTEM_PROMPT,
                user_prompt="", rules=[],
            )
            evidence = record["round_evidence"][-1]
            evidence.pop("rules_used", None)
            evidence.pop("rules_generated", None)
            evidence["diagnosis_from_round"] = latest_diagnosis_round
            # Persistent formal diagnostics disabled. To restore later, import
            # nullcontext from contextlib, restore check_dir below, and replace
            # TemporaryDirectory with nullcontext(str(check_dir)). Also restore
            # persistent paths/cleanup at the marked block below.
            # check_dir = Path(directory) / "formal_rounds" / f"round_{round_number:04d}"
            # check_dir.mkdir(parents=True, exist_ok=False)
            with TemporaryDirectory(prefix="fv_formal_round_", ignore_cleanup_errors=True) as temporary_check_dir:
                check_dir = Path(temporary_check_dir)
                generated_assertion = None
                stage = "generation"
                try:
                    stage = "generation"
                    generation_inputs = {
                        "requirement": inputs["requirement"], "testbench": inputs["testbench"],
                        "previous_assertion": previous_assertion,
                        "diagnosis_response": latest_diagnosis_response,
                        "previous_tree": latest_generated_tree,
                        "comparison_scope": comparison_scope, "revision_feedback": revision_feedback,
                        "assertion_template": policy.get("assertion_template", "asrt: assert property (@(posedge clk) BODY);"),
                    }
                    user_prompt = assertion_generator.build_generation_prompt(**generation_inputs)
                    if previous_assertion is not None:
                        if latest_diagnosis_response is not None:
                            print(f"Round {round_number}: forwarding complete diagnosis from round "
                                  f"{latest_diagnosis_round} to assertion generator "
                                  f"({len(latest_diagnosis_response)} characters).", flush=True)
                        else:
                            print(f"Round {round_number}: no diagnosis response from the preceding round; "
                                  "no rule feedback is available.", flush=True)
                    # Consume only the immediately preceding round's response; no history/readback.
                    latest_diagnosis_response = latest_generated_tree = latest_diagnosis_round = None
                    attempt["prompts"]["user"] = user_prompt
                    run_io.update_run(directory, record, stage=stage)
                    if client is None:
                        client = OpenAI()
                    with run_io.measure_stage(record, "assertion") as capture_usage:
                        response_text = model_io.request_text(
                            client=client, model=config.ASSERTION_MODEL,
                            instructions=assertion_generator.SYSTEM_PROMPT, user_prompt=user_prompt,
                            usage_callback=capture_usage,
                        )
                    attempt["generation"]["raw_response"] = response_text
                    run_io.save_debug_event(directory, record, "assertion_response", raw_response=response_text)
                    stage = "extraction"
                    run_io.update_run(directory, record, stage=stage)
                    generated_assertion = model_io.extract_assertion(response_text)
                    attempt["generation"]["assertion"] = generated_assertion
                    record["round_evidence"][-1]["generated_assertion"] = generated_assertion
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
                            model_name=config.ASSERTION_MODEL,
                        )
                except Exception as error:
                    _remember_round_error(directory, record, round_number, stage, error)
                    status = {"generation": "GENERATION_ERROR", "extraction": "FORMAT_ERROR"}.get(stage, "TOOL_ERROR")
                    formal_result = _failed_round(
                        check_dir, round_number, status, f"{stage}: {type(error).__name__}: {error}", policy,
                    )

                # Persistent diagnostics disabled: the surrounding temporary-directory
                # context owns every native tool file, including failures/interruption.
                # Comment out this block when restoring persistent formal diagnostics.
                formal_result["log_path"] = formal_result["input_path"] = None
                formal_result["cleanup"] = {
                    "retained": False,
                    "reason": "Formal files are temporary and removed when this round exits.",
                }
                formal_check.apply_acceptance_policy(formal_result)
                run_io.record_formal_result(directory, record, attempt, formal_result)
                run_io.update_run(directory, record, stage="cleanup")
                run_io.cleanup_formal_work(directory, record, formal_check.cleanup_work)
                status = formal_result["status"]
                pec_pass = formal_result["acceptance_reason"] == "pec"
                passed = formal_result["accepted"]
                print(f"Round {round_number}/{config.MAX_ROUNDS}: {status} | "
                      f"PEC={formal_result.get('pec')} | BLEU={formal_result.get('bleu')}", flush=True)
                if passed:
                    run_io.update_run(
                        directory, record, status="PASSED", passed=True, stage="finished",
                        stop_reason="passed" if pec_pass else "bleu_match",
                        diagnosis_skipped_reason=(
                            "The supplied PEC checker reported full equivalence."
                            if pec_pass else
                            "BLEU is 1.0; accepted under FVRuleLearner's PEC-or-BLEU policy. "
                            "Reported PEC and relaxed PEC are 1.0; raw scores remain in raw_scores/native_metrics."
                        ),
                    )
                    return 0

                # Feedback for generation never includes the reference or PEC's expressions.
                if status == "INPUT_ERROR" and formal_result.get("error_origin") == "candidate":
                    revision_feedback = formal_result["tool_output"]
                elif status in {"FORMAT_ERROR", "INPUT_ERROR", "SYNTAX_ERROR"}:
                    revision_feedback = (
                        "The previous candidate could not be accepted as a complete SVA assertion. "
                        f"Use {policy.get('assertion_template', 'asrt: assert property (@(posedge clk) [optional disable iff (...)] BODY);')} "
                        "with the label before assert and the whole property inside parentheses. "
                        "Enclose the statement in one systemverilog code block."
                    )
                elif status == "PEC_COMPILE_ERROR":
                    # Diagnosis can refine the assertion without a PEC verdict.
                    revision_feedback = None
                elif status in {"TOOL_ERROR", "TIMEOUT", "INCONCLUSIVE", "GENERATION_ERROR"}:
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
                if status not in {"IMPLIES", "NO_EQUIVALENCE", "PEC_COMPILE_ERROR"}:
                    run_io.update_run(
                        directory, record,
                        diagnosis_skipped_reason="No completed semantic comparison; retry without semantic rule learning.",
                    )
                    continue

                if status == "PEC_COMPILE_ERROR":
                    print(
                        f"Round {round_number}: PEC verdict unavailable; continuing "
                        "with reference-based tree diagnosis and rule generation.", flush=True,
                    )
                stage = "tree_construction"
                try:
                    run_io.update_run(directory, record, stage=stage)
                    with run_io.measure_stage(record, "diagnosis") as capture_tree_usage:
                        trees = rule_generator.build_trees(inputs["reference_assertion"], generated_assertion)
                        capture_tree_usage({"input_tokens": 0, "output_tokens": 0})
                    record["round_evidence"][-1]["assertion_trees"] = trees
                    for side in ("generated", "reference"):
                        if "parse_error" in trees[side]:
                            print(f"Round {round_number}: {side} tree unsupported; "
                                  f"using explicit source anchor: {trees[side]['parse_error']}", flush=True)
                    stage = "rule_generation"
                    print(f"Round {round_number}: running LLM tree diagnosis and rule generation.", flush=True)
                    run_io.update_run(directory, record, stage=stage)
                    rule_prompt = rule_generator.build_rule_prompt(
                        requirement=inputs["requirement"], testbench=inputs["testbench"],
                        generated_assertion=generated_assertion,
                        reference_assertion=inputs["reference_assertion"], trees=trees,
                        comparison_scope=comparison_scope, formal_feedback=formal_result["feedback"],
                    )
                    run_io.save_debug_event(directory, record, "rule_request")
                    with run_io.measure_stage(record, "rule") as capture_usage:
                        rule_response = model_io.request_text(
                            client=client, model=config.RULE_MODEL,
                            instructions=rule_generator.SYSTEM_PROMPT, user_prompt=rule_prompt,
                            json_output=True, usage_callback=capture_usage,
                        )
                    evidence = record["round_evidence"][-1]
                    evidence["tree_rule_raw_response"] = rule_response
                    run_io.save_debug_event(directory, record, "rule_response", raw_response=rule_response)
                    # Pass the FULL unmodified model response, independent of parsing/export.
                    latest_diagnosis_response = rule_response
                    latest_generated_tree = rule_generator.compact_tree(trees["generated"], include_source=False)
                    latest_diagnosis_round = round_number
                    stage = "response_format"
                    run_io.update_run(directory, record, stage=stage)
                    diagnosis = rule_generator.parse_response(rule_response, trees)
                    evidence["tree_rule_diagnosis"] = deepcopy(diagnosis)
                    new_rules = rule_generator.export_rules(diagnosis, round_number)
                    replacement = deepcopy(registry)
                    update_rule_registry(replacement, new_rules, round_number)
                    registry = replacement
                    run_io.update_run(directory, record, diagnosis=diagnosis,
                                      diagnosis_model=config.RULE_MODEL,
                                      rule_registry=retained_rules(registry))
                    run_io.save_diagnosis_model(record, config.RULE_MODEL)
                except Exception as error:
                    _remember_round_error(directory, record, round_number, stage, error)
                    reason = ("Response format check failed; full response still goes to the next round."
                              if latest_diagnosis_round == round_number else f"{stage} failed; continuing next round.")
                    run_io.update_run(directory, record, diagnosis_skipped_reason=reason)
                continue

    # No earlier pass is possible here. Keep the latest attempt and its scores.
    last = record["formal"]
    resolved = last["status"] in {"IMPLIES", "NO_EQUIVALENCE", "SYNTAX_ERROR", "FORMAT_ERROR", "PEC_COMPILE_ERROR"} or (
        last["status"] == "INPUT_ERROR" and last.get("error_origin") == "candidate"
    )
    run_io.update_run(
        directory, record, status="COMPLETED" if resolved else "CHECKER_UNRESOLVED",
        passed=False, stage="finished", stop_reason="max_rounds",
    )
    return 0 if resolved else 1
