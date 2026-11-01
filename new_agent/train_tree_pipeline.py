"""Training-only tree/rule loop; the original pipeline remains the inference path.

Native evaluation, acceptance and round budgets retain the existing checker.
Training prompts use complete assertion history, latest-only located guidance,
and behavior-first diagnosis with coarse outcomes only.
"""
from copy import deepcopy
from contextlib import contextmanager
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from openai import OpenAI
from new_agent import config, formal_check, model_io, run_io
from new_agent import tree_archive
from new_agent.revision_context import reconsider_repeat, evaluate_once, last_transition, retain_checker_failure
from new_agent.typed_pec import ContextPreparationError
from new_agent.correction_locations import feedback_json
from new_agent.pipeline import (
    _failed_round, _remember_round_error, retained_rules, update_rule_registry,
)


@contextmanager
def _save_round_trace(directory, record, round_number):
    """Lazy indented JSON, atomically updated after each round/interruption."""
    from new_agent.train_tree_rule_generator import compact_tree
    try:
        yield
    finally:
        evidence = next((item for item in reversed(record["round_evidence"])
                         if item["round"] == round_number), {})
        tree_archive.finish_round(directory, record, round_number, evidence)
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
            "evaluation": ({key: value for key, value in evaluation.items()
                            if key != "pec_context_preparation"} if evaluation else None),
            "pec_input_preparation": evidence.get("pec_input_preparation"),
            "pec_context_preparation": (evaluation or {}).get("pec_context_preparation"),
            "diagnosis_from_round": evidence.get("diagnosis_from_round"),
            "guidance_payload": evidence.get("guidance_payload"),
            "generation_prompts": evidence.get('generation_prompts'),
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
        path = root / f"case_{inputs['case_number']:04d}.json"
        document = record.setdefault("_rule_trace_document", {
            "case": {key: inputs[key] for key in ("case_number", "design_name", "task_id")},
            "reference_assertion": inputs.get("reference_assertion"),
            "rounds": [],
        })
        document["rounds"].append(entry)
        if trees and "reference" in trees and "reference_tree" not in document:
            document["reference_tree"] = compact_tree(trees["reference"], include_source=False)
        # Keep early rounds in memory until a trace is needed. Initial successes
        # create neither a file nor a rules directory. Once created, save all rounds.
        if path.exists() or raw is not None or output is not None or trees is not None or failures:
            root.mkdir(parents=True, exist_ok=True)
            run_io._atomic_write(path, json.dumps(document, ensure_ascii=False, indent=2) + "\n")
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
    from new_agent.training_prompt_context import (
        PROMPT_VERSION, assertion_history, statement_template,
    )
    inputs = record["inputs"]
    policy = formal_check.get_evaluation_policy(inputs.get("dataset", config.DATASET))
    dataset = inputs.get("dataset", config.DATASET)
    template = statement_template(dataset)
    record["settings"].update(
        training_prompt_version=PROMPT_VERSION,
        training_assertion_history="all_previous_assertions_coarse_results",
        training_feedback="latest_located_corrections_only",
        training_rule_feedback="coarse_reference_equivalence_only",
        training_rule_schema="behavior_review_diagnoses_corrections_v4",
    )
    registry = {}
    previous_assertion = None
    client = None
    latest_diagnosis_response = None
    latest_diagnosis_round = None

    for round_number in range(1, config.MAX_ROUNDS + 1):
        with _save_round_trace(directory, record, round_number):
            run_io.start_usage_round(record, round_number)
            # A failed call before extraction must never associate old text with new scores.
            record['training_feedback_round'] = latest_diagnosis_round
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
                        "assertion_history": assertion_history(
                            record["round_evidence"], before_round=round_number),
                        "diagnosis_response": latest_diagnosis_response,
                        "diagnosis_round": latest_diagnosis_round,
                        "assertion_template": template,
                    }
                    user_prompt = assertion_generator.build_generation_prompt(**generation_inputs)
                    evidence['guidance_payload'] = latest_diagnosis_response
                    run_io.save_debug_event(directory, record, 'guidance_context',
                                            source_round=latest_diagnosis_round,
                                            payload=latest_diagnosis_response)
                    if previous_assertion is not None:
                        if latest_diagnosis_response is not None:
                            print(f"Round {round_number}: forwarding complete diagnosis from round "
                                  f"{latest_diagnosis_round} to assertion generator "
                                  f"({len(latest_diagnosis_response)} characters).", flush=True)
                        else:
                            print(f"Round {round_number}: no diagnosis response from the preceding round; "
                                  "no rule feedback is available.", flush=True)
                    # Assertion history is cumulative; correction guidance is latest-round only.
                    latest_diagnosis_response = latest_diagnosis_round = None
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
                    response_text, generated_assertion = reconsider_repeat(
                        directory=directory, record=record, attempt=attempt,
                        assertion=generated_assertion, response_text=response_text,
                        user_prompt=user_prompt, instructions=assertion_generator.SYSTEM_PROMPT,
                        client=client, model=config.ASSERTION_MODEL)
                    attempt['generation']['raw_response'] = response_text
                    evidence['generation_prompts'] = deepcopy(attempt['prompts'])
                    attempt["generation"]["assertion"] = generated_assertion
                    record["round_evidence"][-1]["generated_assertion"] = generated_assertion
                    previous_assertion = generated_assertion
                    stage = "formal_check"
                    run_io.update_run(directory, record, stage=stage)
                    with run_io.measure_stage(record, "tool"):
                        formal_result = evaluate_once(record, round_number,
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
                    if isinstance(error, ContextPreparationError):
                        status = 'PEC_CONTEXT_ERROR' 
                    formal_result = _failed_round(
                        check_dir, round_number, status, f"{stage}: {type(error).__name__}: {error}", policy,
                    )

                # Persistent diagnostics disabled: the surrounding temporary-directory
                # context owns every native tool file, including failures/interruption.
                # Comment out this block when restoring persistent formal diagnostics.
                retain_checker_failure(directory, record, round_number, formal_result)
                formal_result["log_path"] = formal_result["input_path"] = None
                formal_result["cleanup"] = {
                    "retained": False,
                    "reason": "Temporary native work removed; small checker-failure diagnostics retained when tracing is enabled.",
                }
                formal_check.apply_acceptance_policy(formal_result)
                run_io.record_formal_result(directory, record, attempt, formal_result)
                # Inspection trees are built only after native evaluation returns.
                # Attempt this for every extracted assertion, even SYN/PEC failures.
                # A tree/archive failure must never replace an obtained tool verdict.
                inspection_trees = None
                if generated_assertion is not None:
                    stage = "tree_recording"
                    try:
                        with run_io.measure_stage(record, "diagnosis") as capture_tree_usage:
                            inspection_trees = tree_archive.record_generated(
                                directory, record, round_number, generated_assertion)
                            capture_tree_usage({"input_tokens": 0, "output_tokens": 0})
                    except Exception as error:
                        _remember_round_error(directory, record, round_number, stage, error)
                if formal_result.get("pec_input_preparation") is not None:
                    record["round_evidence"][-1]["pec_input_preparation"] = formal_result["pec_input_preparation"]
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

                if status in {'PEC_COMPILE_ERROR', 'PEC_CONTEXT_ERROR'}:
                    run_io.update_run(
                        directory, record, status='BLOCKED_PEC_CONTEXT', passed=False,
                        stage='finished', stop_reason='pec_context_error',
                        diagnosis_skipped_reason='PEC declarations/context failed; no semantic verdict. '
                                                 'Retain the candidate and repair the checker context.')
                    return 1

                # Next-round feedback comes only from whitelisted history outcomes.
                # Native logs, metrics and evaluation-policy text stay in experiment records.
                if round_number == config.MAX_ROUNDS:
                    run_io.update_run(directory, record, diagnosis_skipped_reason="Round budget exhausted.")
                    continue
                if inspection_trees is None:
                    run_io.update_run(directory, record,
                                      diagnosis_skipped_reason="Tree archive unavailable after evaluation.")
                    continue
                if status not in {"IMPLIES", "NO_EQUIVALENCE"}:
                    run_io.update_run(
                        directory, record,
                        diagnosis_skipped_reason="No completed semantic comparison; retry without semantic rule learning.",
                    )
                    continue

                stage = "tree_construction"
                try:
                    run_io.update_run(directory, record, stage=stage)
                    with run_io.measure_stage(record, "diagnosis") as capture_tree_usage:
                        trees = inspection_trees
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
                        evaluation_status=status,
                        previous_transition=last_transition(record['round_evidence'], generated_assertion, status),
                    )
                    record["round_evidence"][-1]["rule_prompt"] = rule_prompt
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
                    # Raw model output stays in the trace. Only located correction
                    # text is forwarded; source/reference IDs and trees stay local.
                    latest_diagnosis_response = latest_diagnosis_round = None
                    stage = "response_format"
                    run_io.update_run(directory, record, stage=stage)
                    diagnosis = rule_generator.parse_response(rule_response, trees)
                    evidence["tree_rule_diagnosis"] = deepcopy(diagnosis)
                    latest_diagnosis_response = feedback_json(diagnosis, tree=trees['generated'])
                    latest_diagnosis_round = round_number
                    run_io.save_debug_event(directory, record, 'correction_locations',
                                            corrections=diagnosis['corrections'])
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
                    reason = ("Diagnosis, location and rule feedback goes to the next round."
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


