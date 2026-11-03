"""Inference with existing-rule ranking and independent issue locations.

Native extraction/checking/scoring and the installed tree implementation stay
unchanged. The active selector never generates or rewrites rules.
"""
from copy import deepcopy
from contextlib import contextmanager
from new_agent.runtime_support import formal_round_directory
from new_agent.model_gateway import ModelGateway
from new_agent.model_output_schemas import INFERENCE_SELECTION
from new_agent import config, formal_check, model_io, run_io
from new_agent import tree_archive
from new_agent.revision_context import reconsider_repeat, evaluate_once, last_transition, retain_checker_failure
from new_agent.tool_feedback import feedback_for_round
from new_agent.pipeline import (
    _failed_round, _remember_round_error,
)


@contextmanager
def _save_inference_trace(directory, record, round_number):
    """Attach outcomes to inspection trees; case outputs use the shared trace."""
    try:
        yield
    finally:
        evidence = next((row for row in reversed(record["round_evidence"])
                         if row["round"] == round_number), {})
        tree_archive.finish_round(directory, record, round_number, evidence)


def run_inference_pipeline(directory, record: dict, *, retriever=None) -> int:
    """Stop on PEC/BLEU success or exhaustion of the configured attempt budget.

    Ordinary generation, extraction, checker, diagnosis and rule-output errors
    are round outcomes. KeyboardInterrupt/SystemExit are deliberately not caught.
    File-system failures can still prevent reliable recording and must propagate.
    """
    if record["settings"].get("phase") != "infer":
        raise ValueError("The inference tree pipeline requires phase=infer.")
    if retriever is None:
        raise ValueError("Inference requires the selected training-run retriever.")
    from new_agent import infer_assertion_generator as assertion_generator
    from new_agent import infer_rule_selector as selector
    from new_agent.infer_rule_masking import prepare_candidates
    inputs = record["inputs"]
    policy = formal_check.get_evaluation_policy(inputs.get("dataset", config.DATASET))
    record["settings"].update(
        inference_workflow="existing_diagnosis_and_rule_selection",
        inference_rule_stages="select_existing_diagnoses_and_corrections",
        inference_feedback="selected_masked_training_repairs",
        inference_rule_context="masked_all_round_guidance_locations_and_generated_before_after",
        inference_example_source="accepted_generated_training_assertions",
        inference_retrieval="once_per_target_case",
        inference_max_selected_rules=selector.limits()["rules"],
        inference_max_selected_diagnoses=selector.limits()["diagnoses"],
    )
    example_cases = None
    candidates = None
    previous_assertion = None
    client = None
    latest_selector_guidance = None
    latest_selector_round = None
    previous_round = None

    for round_number in range(1, config.MAX_ROUNDS + 1):
        with _save_inference_trace(directory, record, round_number):
            run_io.start_usage_round(record, round_number)
            # Record the feedback source before start_attempt writes its debug event.
            record["inference_feedback_round"] = latest_selector_round
            # A failed call before extraction must never associate old text with new scores.
            attempt = run_io.start_attempt(
                directory, record, round_number,
                system_prompt=assertion_generator.SYSTEM_PROMPT,
                user_prompt="", rules=[],
            )
            evidence = record["round_evidence"][-1]
            evidence.pop("rules_used", None)
            evidence.pop("rules_generated", None)
            evidence["diagnosis_from_round"] = latest_selector_round
            with formal_round_directory(directory, round_number, record) as check_dir:
                generated_assertion = None
                stage = "generation"
                try:
                    if example_cases is None:
                        stage = "example_retrieval"
                        example_cases = retriever.retrieve_examples(inputs["requirement"])
                        run_io.update_run(directory, record, retrieved_examples=[
                            {"case_number": case["case_number"], "similarity": case["similarity"]}
                            for case in example_cases])
                        run_io.save_debug_event(directory, record, "example_retrieval", examples=example_cases)
                    if candidates is None:
                        stage = "initial_retrieval"
                        run_io.update_run(directory, record, stage=stage)
                        retrieved = retriever.retrieve(inputs["requirement"])
                        candidates = prepare_candidates(retrieved, getattr(retriever, "masking_contexts", {}))
                        record["retrieved_rule_bank"] = selector.compact_rule_bank(candidates)
                        run_io.update_run(directory, record, retrieved_cases=[
                            {"case_number": case["case_number"], "similarity": case["similarity"]}
                            for case in retrieved])
                        run_io.save_debug_event(directory, record, "retrieval",
                            rule_bank=record["retrieved_rule_bank"],
                            case_pool=getattr(retriever, 'last_retrieval_audit', None))
                        stage = "initial_rule_selection"
                        run_io.update_run(directory, record, stage=stage)
                        if client is None:
                            client = ModelGateway()
                        prompt = selector.build_selector_prompt(
                            inputs["requirement"], inputs["testbench"], None,
                            record["retrieved_rule_bank"])
                        run_io.save_debug_event(directory, record, "selector_request", initial=True)
                        with run_io.measure_stage(record, "rule") as capture_usage:
                            response = model_io.request_text(
                                client=client, model=config.MODEL,
                                instructions=selector.SYSTEM_PROMPT, user_prompt=prompt,
                                json_output=True, usage_callback=capture_usage,
                                output_schema=INFERENCE_SELECTION)
                        evidence["initial_selector_raw_response"] = response
                        run_io.save_debug_event(directory, record, "selector_response", raw_response=response)
                        stage = "initial_selector_response_format"
                        selection = selector.parse_response(response, None, record["retrieved_rule_bank"])
                        evidence["initial_inference_selection"] = deepcopy(selection)
                        selected_diagnoses = {(item['category'], item['statement'])
                                              for item in selection['selected_diagnoses']}
                        selected_rules = {item['rule_id'] for item in selection['selected_rules']}
                        run_io.save_debug_event(directory, record, 'selector_unselected',
                            initial=True, round=round_number,
                            diagnoses=[item for item in record['retrieved_rule_bank']['diagnoses']
                                       if (item['category'], item['statement']) not in selected_diagnoses],
                            rules=[item for item in record['retrieved_rule_bank']['rules']
                                   if item['id'] not in selected_rules])
                        latest_selector_guidance = selector.make_generator_guidance(
                            selection, record["retrieved_rule_bank"], None, source_round=None)
                        run_io.update_run(directory, record, diagnosis=selection,
                                          diagnosis_model=config.MODEL)
                        run_io.save_diagnosis_model(record, config.MODEL)
                    stage = "generation"
                    run_io.save_debug_event(directory, record, "assertion_generation")
                    generation_inputs = {
                        "requirement": inputs["requirement"],
                        "testbench": inputs["testbench"],
                        "assertion_template": policy["assertion_template"],
                        "examples": example_cases, "previous_assertion": previous_assertion,
                        "previous_round": previous_round, "selector_guidance": latest_selector_guidance,
                        "previous_evaluation": feedback_for_round(record['round_evidence'], previous_round),
                    }
                    user_prompt = assertion_generator.build_generation_prompt(**generation_inputs)
                    evidence['guidance_payload'] = deepcopy(latest_selector_guidance)
                    run_io.save_debug_event(directory, record, 'guidance_context',
                                            source_round=latest_selector_round,
                                            payload=latest_selector_guidance)
                    # Retain current guidance if generation/extraction fails.
                    # Selected masked training repairs guide generation and revision.
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
                    previous_round = round_number
                    latest_selector_guidance = latest_selector_round = None
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
                    if stage.startswith("initial_"):
                        run_io.save_debug_event(directory, record, 'selector_error',
                            stage=stage, reason=f'{type(error).__name__}: {error}')
                        run_io.update_run(directory, record,
                            status='BLOCKED_SELECTION', passed=False, stage='finished',
                            stop_reason='selection_unavailable',
                            diagnosis_skipped_reason='Initial guidance could not be retrieved or selected.')
                        return 1
                    status = {"generation": "GENERATION_ERROR", "extraction": "FORMAT_ERROR"}.get(stage, "TOOL_ERROR")
                    formal_result = _failed_round(
                        check_dir, round_number, status, f"{stage}: {type(error).__name__}: {error}", policy,
                    )

                # Keep one failure log; the round owns and discards temporary tool files.
                retain_checker_failure(directory, record, round_number, formal_result)
                formal_check.apply_acceptance_policy(formal_result)
                run_io.record_formal_result(directory, record, attempt, formal_result)
                # Build inspection trees after native SYN/PEC evaluation, even on failure.
                # Tree/archive errors must never replace an obtained tool verdict.
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

                # No detailed checker feedback is sent to assertion generation.
                if round_number == config.MAX_ROUNDS:
                    run_io.update_run(directory, record, diagnosis_skipped_reason="Round budget exhausted.")
                    continue
                if generated_assertion is None:
                    run_io.update_run(directory, record,
                                      diagnosis_skipped_reason="No candidate source was extracted for review.")
                    continue
                if inspection_trees is None:
                    inspection_trees = {'generated': tree_archive.build(generated_assertion, 'G')}

                stage = "rule_selection"
                try:
                    tree = inspection_trees["generated"]
                    evidence = record["round_evidence"][-1]
                    evidence["generated_tree"] = tree
                    stage = "rule_selection"
                    run_io.update_run(directory, record, stage=stage)
                    prompt = selector.build_selector_prompt(
                        inputs["requirement"], inputs["testbench"], tree,
                        record["retrieved_rule_bank"], evaluation_status=formal_result['tool_feedback'],
                        previous_transition=last_transition(record['round_evidence'], generated_assertion, status))
                    evidence["selector_checker_status"] = status
                    run_io.save_debug_event(directory, record, "selector_request")
                    # Reuse the existing 'rule' usage column for selector cost only.
                    # Select the configured counts or every entry in a smaller pool.
                    with run_io.measure_stage(record, "rule") as capture_usage:
                        response = model_io.request_text(
                            client=client, model=config.MODEL,
                            instructions=selector.SYSTEM_PROMPT, user_prompt=prompt,
                            json_output=True, usage_callback=capture_usage,
                            output_schema=INFERENCE_SELECTION)
                    evidence["selector_raw_response"] = response
                    run_io.save_debug_event(directory, record, "selector_response", raw_response=response)
                    stage = "selector_response_format"
                    selection = selector.parse_response(response, tree, record["retrieved_rule_bank"])
                    evidence["inference_selection"] = deepcopy(selection)
                    selected_diagnoses = {(item['category'], item['statement'])
                                          for item in selection['selected_diagnoses']}
                    selected_rules = {item['rule_id'] for item in selection['selected_rules']}
                    run_io.save_debug_event(directory, record, 'selector_unselected',
                        round=round_number,
                        diagnoses=[item for item in record['retrieved_rule_bank']['diagnoses']
                                   if (item['category'], item['statement']) not in selected_diagnoses],
                        rules=[item for item in record['retrieved_rule_bank']['rules']
                               if item['id'] not in selected_rules])
                    latest_selector_guidance = selector.make_generator_guidance(
                        selection, record["retrieved_rule_bank"], tree, source_round=round_number)
                    latest_selector_round = round_number
                    evidence["selector_guidance"] = deepcopy(latest_selector_guidance)
                    run_io.update_run(directory, record, diagnosis=selection,
                                      diagnosis_model=config.MODEL)
                    run_io.save_diagnosis_model(record, config.MODEL)
                except Exception as error:
                    latest_selector_guidance = latest_selector_round = None
                    _remember_round_error(directory, record, round_number, stage, error)
                    run_io.save_debug_event(directory, record, 'selector_error',
                        stage=stage, reason=f'{type(error).__name__}: {error}')
                    run_io.update_run(directory, record,
                        status='BLOCKED_SELECTION', passed=False, stage='finished',
                        stop_reason='selection_unavailable',
                        diagnosis_skipped_reason='The selector response could not be obtained or parsed.')
                    return 1
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








