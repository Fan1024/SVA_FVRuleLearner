"""Training-only tree/rule loop with concise requirement-based corrections.

Native evaluation, acceptance and round budgets retain the existing checker.
Training prompts use the latest assertion, latest interpretation/categories/rules,
and a short repetition notice. Complete history remains in saved round evidence.
"""
from copy import deepcopy
from contextlib import contextmanager
from new_agent.runtime_support import formal_round_directory
from new_agent.model_gateway import ModelGateway
from new_agent.model_output_schemas import TRAINING_RULES
from new_agent import config, formal_check, model_io, run_io
from new_agent import tree_archive
from new_agent.revision_context import reconsider_repeat, evaluate_once, last_transition, retain_checker_failure
from new_agent.correction_locations import feedback_json
from new_agent.tool_feedback import POLICY_VERSION as TOOL_FEEDBACK_POLICY
from new_agent.pipeline import (
    _failed_round, _remember_round_error, retained_rules, update_rule_registry,
)


@contextmanager
def _save_round_trace(directory, record, round_number):
    """Attach outcomes to inspection trees; case outputs use the shared trace."""
    try:
        yield
    finally:
        evidence = next((row for row in reversed(record["round_evidence"])
                         if row["round"] == round_number), {})
        tree_archive.finish_round(directory, record, round_number, evidence)


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
        PROMPT_VERSION, assertion_history,
    )
    inputs = record["inputs"]
    policy = formal_check.get_evaluation_policy(inputs.get("dataset", config.DATASET))
    dataset = inputs.get("dataset", config.DATASET)
    record["settings"].update(
        training_prompt_version=PROMPT_VERSION,
        training_assertion_history="latest_assertion_compact_tool_feedback_repetition_notice",
        training_feedback="latest_high_level_diagnoses_located_rules",
        training_rule_feedback=TOOL_FEEDBACK_POLICY,
        training_rule_schema="whole_assertion_diagnoses_v8",
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
            with formal_round_directory(directory, round_number, record) as check_dir:
                generated_assertion = None
                stage = "generation"
                try:
                    stage = "generation"
                    generation_inputs = {
                        "requirement": inputs["requirement"],
                        "testbench": inputs["testbench"],
                        "assertion_template": inputs.get("assertion_template") or policy["assertion_template"],
                        "assertion_history": assertion_history(
                            record["round_evidence"], before_round=round_number),
                        "diagnosis_response": latest_diagnosis_response,
                        "diagnosis_round": latest_diagnosis_round,
                    }
                    user_prompt = assertion_generator.build_generation_prompt(**generation_inputs)
                    evidence['guidance_payload'] = latest_diagnosis_response
                    run_io.save_debug_event(directory, record, 'guidance_context',
                                            source_round=latest_diagnosis_round,
                                            payload=latest_diagnosis_response)
                    # Assertion history is cumulative; correction guidance is latest-round only.
                    latest_diagnosis_response = latest_diagnosis_round = None
                    attempt["prompts"]["user"] = user_prompt
                    run_io.update_run(directory, record, stage=stage)
                    if client is None:
                        client = ModelGateway()
                    with run_io.measure_stage(record, "assertion") as capture_usage:
                        response_text = model_io.request_text(
                            client=client, model=config.MODEL,
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
                        client=client, model=config.MODEL)
                    attempt['generation']['raw_response'] = response_text
                    evidence['generation_prompts'] = deepcopy(attempt['prompts'])
                    attempt["generation"]["assertion"] = generated_assertion
                    record["round_evidence"][-1]["generated_assertion"] = generated_assertion
                    previous_assertion = generated_assertion
                    stage = "formal_check"
                    run_io.update_run(directory, record, stage=stage,
                                      generation=deepcopy(attempt["generation"]), formal=None)
                    with run_io.measure_stage(record, "tool"):
                        formal_result = evaluate_once(record, round_number,
                            generated_assertion=generated_assertion,
                            reference_assertion=inputs["reference_assertion"],
                            testbench=inputs["testbench"], requirement=inputs["requirement"],
                            run_dir=check_dir, timeout_seconds=config.JASPER_TIMEOUT_SECONDS,
                            task_id=inputs["task_id"], dataset=inputs.get("dataset", config.DATASET),
                            model_name=config.MODEL,
                        )
                except Exception as error:
                    _remember_round_error(directory, record, round_number, stage, error)
                    status = {"generation": "GENERATION_ERROR", "extraction": "FORMAT_ERROR"}.get(stage, "TOOL_ERROR")
                    formal_result = _failed_round(
                        check_dir, round_number, status, f"{stage}: {type(error).__name__}: {error}", policy,
                    )

                # Keep one failure log; the round owns and discards temporary tool files.
                retain_checker_failure(directory, record, round_number, formal_result)
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
                run_io.print_round_summary(round_number, config.MAX_ROUNDS, formal_result)
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

                # Forward compact statuses and extracted candidate errors only.
                # Full logs, metrics and evaluation-policy text stay in experiment records.
                if round_number == config.MAX_ROUNDS:
                    run_io.update_run(directory, record, diagnosis_skipped_reason="Round budget exhausted.")
                    continue
                if generated_assertion is None:
                    run_io.update_run(directory, record,
                                      diagnosis_skipped_reason="No candidate source was extracted for review.")
                    continue
                if inspection_trees is None:
                    # Archive/parser failures must not disable source-based diagnosis.
                    inspection_trees = {
                        'generated': tree_archive.build(generated_assertion, 'G'),
                        'reference': tree_archive.build(inputs['reference_assertion'], 'R'),
                    }
                evidence['diagnosis_basis'] = ('completed_comparison' if status in
                    {'IMPLIES', 'NO_EQUIVALENCE'} else 'source_review_no_equivalence_verdict')

                stage = "tree_construction"
                try:
                    run_io.update_run(directory, record, stage=stage)
                    with run_io.measure_stage(record, "diagnosis") as capture_tree_usage:
                        trees = inspection_trees
                        capture_tree_usage({"input_tokens": 0, "output_tokens": 0})
                    record["round_evidence"][-1]["assertion_trees"] = trees
                    stage = "rule_generation"
                    run_io.update_run(directory, record, stage=stage)
                    rule_prompt = rule_generator.build_rule_prompt(
                        requirement=inputs["requirement"],
                        testbench=inputs["testbench"],
                        generated_assertion=generated_assertion,
                        reference_assertion=inputs["reference_assertion"], trees=trees,
                        evaluation_status=formal_result['tool_feedback'],
                        previous_transition=last_transition(record['round_evidence'], generated_assertion, status),
                    )
                    record["round_evidence"][-1]["rule_prompt"] = rule_prompt
                    run_io.save_debug_event(directory, record, "rule_request")
                    with run_io.measure_stage(record, "rule") as capture_usage:
                        rule_response = model_io.request_text(
                            client=client, model=config.MODEL,
                            instructions=rule_generator.SYSTEM_PROMPT, user_prompt=rule_prompt,
                            json_output=True, usage_callback=capture_usage,
                            output_schema=TRAINING_RULES,
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
                    for item in rule_generator.export_diagnoses(diagnosis,round_number):
                        if item not in record.setdefault('diagnosis_registry',[]):
                            record['diagnosis_registry'].append(item)
                    latest_diagnosis_response = feedback_json(diagnosis, tree=trees['generated'])
                    latest_diagnosis_round = round_number
                    run_io.save_debug_event(directory, record, 'correction_locations',
                                            corrections=diagnosis['corrections'])
                    new_rules = rule_generator.export_rules(diagnosis, round_number)
                    replacement = deepcopy(registry)
                    update_rule_registry(replacement, new_rules, round_number)
                    registry = replacement
                    run_io.update_run(directory, record, diagnosis=diagnosis,
                                      diagnosis_model=config.MODEL,
                                      rule_registry=retained_rules(registry))
                    run_io.save_diagnosis_model(record, config.MODEL)
                except Exception as error:
                    _remember_round_error(directory, record, round_number, stage, error)
                    reason = ("Diagnosis, location and rule feedback goes to the next round."
                              if latest_diagnosis_round == round_number else f"{stage} failed; continuing next round.")
                    run_io.update_run(directory, record, diagnosis_skipped_reason=reason)
                continue

    # No earlier pass is possible here. Keep the latest attempt and its scores.
    last = record["formal"]
    resolved = last["status"] in {"IMPLIES", "NO_EQUIVALENCE", "SYNTAX_ERROR", "FORMAT_ERROR", "PEC_COMPILE_ERROR"} or (
        last["status"] == "INPUT_ERROR" and last.get("error_origin") in {"candidate", "candidate_format"}
    )
    run_io.update_run(
        directory, record, status="COMPLETED" if resolved else "CHECKER_UNRESOLVED",
        passed=False, stage="finished", stop_reason="max_rounds",
    )
    return 0 if resolved else 1







