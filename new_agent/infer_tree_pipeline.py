"""Inference with existing-rule ranking and independent issue locations.

Native extraction/checking/scoring and the installed tree implementation stay
unchanged. The active selector never generates or rewrites rules.
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
from new_agent.pipeline import (
    _failed_round, _remember_round_error,
)


@contextmanager
def _save_inference_trace(directory, record, round_number):
    """Readable lazy per-case JSON; no target reference in diagnosis evidence."""
    from new_agent.infer_rule_selector import compact_tree
    try:
        yield
    finally:
        evidence = next((row for row in reversed(record["round_evidence"])
                         if row["round"] == round_number), {})
        tree_archive.finish_round(directory, record, round_number, evidence)
        entry = {key: evidence.get(key) for key in
                 ("round", "generated_assertion", "evaluation", "diagnosis_from_round",
                  "pec_input_preparation")}
        entry["pec_context_preparation"] = (evidence.get("evaluation") or {}).get("pec_context_preparation")
        if isinstance(entry.get("evaluation"), dict):
            entry["evaluation"] = {key: value for key, value in entry["evaluation"].items()
                                   if key != "pec_context_preparation"}
        tree = evidence.get("generated_tree")
        if tree is not None:
            entry["generated_tree"] = compact_tree(tree, include_source=False)
        output, raw = evidence.get("inference_selection"), evidence.get("selector_raw_response")
        if output is not None:
            entry["selector"] = output
        elif raw is not None:
            entry["selector_raw"] = raw
        else:
            entry["diagnosis_skipped"] = (
                "candidate_accepted" if (evidence.get("evaluation") or {}).get("accepted")
                else record.get("diagnosis_skipped_reason", "not_run"))
        for key in ('selector_checker_status', 'selector_guidance'):
            if key in evidence:
                entry[key] = deepcopy(evidence[key])
        errors = [row for row in record.get("round_failures", []) if row["round"] == round_number]
        if errors:
            entry["errors"] = errors
        exception_type, exception, _ = sys.exc_info()
        if exception_type is not None:
            entry["interruption"] = {"type": exception_type.__name__, "message": str(exception)}
        inputs = record["inputs"]
        document = record.setdefault("_inference_trace", {
            "case": {key: inputs[key] for key in ("case_number", "design_name", "task_id")},
            "rounds": [],
        })
        if 'retrieved_rule_bank' in record and 'retrieved_rule_bank' not in document:
            document['retrieved_rule_bank'] = record['retrieved_rule_bank']
        document["rounds"].append(entry)
        path = Path(directory) / "inference_trace.json"
        if path.exists() or tree is not None or raw is not None or errors:
            run_io._atomic_write(path, json.dumps(document, ensure_ascii=False, indent=2) + "\n")
            summary = Path(record.get("summary_directory", directory))
            try:
                record["inference_trace_file"] = str(path.relative_to(summary))
            except ValueError:
                record["inference_trace_file"] = str(path)


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
    from new_agent.training_prompt_context import statement_template
    from new_agent.infer_rule_masking import prepare_candidates
    inputs = record["inputs"]
    policy = formal_check.get_evaluation_policy(inputs.get("dataset", config.DATASET))
    template = statement_template(inputs.get("dataset", config.DATASET))
    record["settings"].update(
        inference_workflow="existing_rule_selector_independent_locations",
        inference_rule_stages="rank_existing_rules_and_locate_issues_only",
        inference_feedback="latest_ranked_rules_and_independent_locations",
        inference_example_source="accepted_generated_training_assertions",
        inference_retrieval="once_per_target_case",
        inference_max_selected_rules=selector.MAX_SELECTED_RULES,
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
                    if example_cases is None:
                        stage = "example_retrieval"
                        example_cases = retriever.retrieve_examples(inputs["requirement"])
                        run_io.update_run(directory, record, retrieved_examples=[
                            {"case_number": case["case_number"], "similarity": case["similarity"]}
                            for case in example_cases])
                        run_io.save_debug_event(directory, record, "example_retrieval", examples=example_cases)
                        print("Example case IDs:", [c["case_number"] for c in example_cases], flush=True)
                    stage = "generation"
                    generation_inputs = {
                        "requirement": inputs["requirement"], "testbench": inputs["testbench"],
                        "examples": example_cases, "previous_assertion": previous_assertion,
                        "previous_round": previous_round, "selector_guidance": latest_selector_guidance,
                        "assertion_template": template,
                    }
                    user_prompt = assertion_generator.build_generation_prompt(**generation_inputs)
                    # Only the latest selector response is used. No assertion history,
                    # old rules, native logs, scores or reference enters this prompt.
                    latest_selector_guidance = latest_selector_round = None
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
                    previous_round = round_number
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

                # No detailed checker feedback is sent to assertion generation.
                if round_number == config.MAX_ROUNDS:
                    run_io.update_run(directory, record, diagnosis_skipped_reason="Round budget exhausted.")
                    continue
                if inspection_trees is None:
                    run_io.update_run(directory, record,
                                      diagnosis_skipped_reason="Tree archive unavailable after evaluation.")
                    continue
                if status not in {"IMPLIES", "NO_EQUIVALENCE", "PEC_COMPILE_ERROR"}:
                    run_io.update_run(
                        directory, record,
                        diagnosis_skipped_reason="No eligible comparison outcome; retry assertion generation without selector guidance.",
                    )
                    continue

                if status == "PEC_COMPILE_ERROR":
                    print(
                        f"Round {round_number}: PEC verdict unavailable; continuing "
                        "with requirement-based rule ranking and independent issue localization.", flush=True,
                    )
                stage = "retrieval"
                try:
                    if candidates is None:
                        retrieved = retriever.retrieve(inputs["requirement"])
                        candidates = prepare_candidates(retrieved, getattr(retriever, "masking_contexts", {}))
                        record["retrieved_rule_bank"] = selector.compact_rule_bank(candidates)
                        run_io.update_run(directory, record, retrieved_cases=[
                            {"case_number": case["case_number"], "similarity": case["similarity"]}
                            for case in retrieved])
                        run_io.save_debug_event(directory, record, "retrieval",
                                                rule_bank=record["retrieved_rule_bank"])
                    tree = inspection_trees["generated"]
                    evidence = record["round_evidence"][-1]
                    evidence["generated_tree"] = tree
                    stage = "rule_selection"
                    run_io.update_run(directory, record, stage=stage)
                    prompt = selector.build_selector_prompt(
                        inputs["requirement"], inputs["testbench"], tree,
                        record["retrieved_rule_bank"], evaluation_status=status)
                    evidence["selector_checker_status"] = status
                    run_io.save_debug_event(directory, record, "selector_request")
                    # Reuse the existing 'rule' usage column for selector cost only.
                    # Empty outputs are valid; no forced-rule retry or generator fallback.
                    with run_io.measure_stage(record, "rule") as capture_usage:
                        response = model_io.request_text(
                            client=client, model=config.RULE_MODEL,
                            instructions=selector.SYSTEM_PROMPT, user_prompt=prompt,
                            json_output=True, usage_callback=capture_usage)
                    evidence["selector_raw_response"] = response
                    run_io.save_debug_event(directory, record, "selector_response", raw_response=response)
                    stage = "selector_response_format"
                    selection = selector.parse_response(response, tree, record["retrieved_rule_bank"])
                    evidence["inference_selection"] = deepcopy(selection)
                    latest_selector_guidance = selector.make_generator_guidance(
                        selection, record["retrieved_rule_bank"], tree, source_round=round_number)
                    latest_selector_round = round_number
                    evidence["selector_guidance"] = deepcopy(latest_selector_guidance)
                    run_io.update_run(directory, record, diagnosis=selection,
                                      diagnosis_model=config.RULE_MODEL)
                    run_io.save_diagnosis_model(record, config.RULE_MODEL)
                    print(f"Round {round_number}: {len(selection['ranked_rules'])} existing rules ranked; "
                          f"{len(selection['locations'])} independent issue locations.", flush=True)
                except Exception as error:
                    latest_selector_guidance = latest_selector_round = None
                    _remember_round_error(directory, record, round_number, stage, error)
                    run_io.update_run(directory, record,
                        diagnosis_skipped_reason="Selector unavailable; next attempt independently reviews the task.")
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

