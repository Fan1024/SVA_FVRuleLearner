"""Inference-only tree diagnosis and retrieval-rule selection loop.

PEC/BLEU evaluation, acceptance, retries and round budgets use the existing
checker and policies. Only the inference diagnosis/rule stages are replaced.
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
    _failed_round, _remember_round_error, retained_rules, update_rule_registry,
)


@contextmanager
def _save_inference_trace(directory, record, round_number):
    """Readable lazy per-case JSON; no target reference in diagnosis evidence."""
    from new_agent.infer_tree_rule_generator import compact_tree
    try:
        yield
    finally:
        evidence = next((row for row in reversed(record["round_evidence"])
                         if row["round"] == round_number), {})
        tree_archive.finish_round(directory, record, round_number, evidence)
        entry = {key: evidence.get(key) for key in
                 ("round", "generated_assertion", "evaluation", "diagnosis_from_round")}
        tree = evidence.get("generated_tree")
        if tree is not None:
            entry["generated_tree"] = compact_tree(tree, include_source=False)
        output, raw = evidence.get("inference_diagnosis"), evidence.get("inference_raw_response")
        if output is not None:
            entry["diagnosis"] = output
        elif raw is not None:
            entry["diagnosis_raw"] = raw
        else:
            entry["diagnosis_skipped"] = (
                "candidate_accepted" if (evidence.get("evaluation") or {}).get("accepted")
                else record.get("diagnosis_skipped_reason", "not_run"))
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
    from new_agent import infer_tree_rule_generator as rule_generator
    from new_agent.infer_rule_masking import prepare_candidates
    inputs = record["inputs"]
    policy = formal_check.get_evaluation_policy(inputs.get("dataset", config.DATASET))
    comparison_scope = policy["scope"]
    registry = {}
    example_cases = None
    candidates = None
    previous_assertion = None
    revision_feedback = None
    client = None
    latest_diagnosis_response = None
    latest_generated_tree = None
    latest_diagnosis_round = None

    for round_number in range(1, config.MAX_ROUNDS + 1):
        with _save_inference_trace(directory, record, round_number):
            run_io.start_usage_round(record, round_number)
            # Record the feedback source before start_attempt writes its debug event.
            record["inference_feedback_round"] = latest_diagnosis_round
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
                        "previous_assertion": previous_assertion, "examples": example_cases,
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
                    stage = 'tree_recording'
                    with run_io.measure_stage(record, 'diagnosis') as capture_tree_usage:
                        inspection_trees = tree_archive.record_generated(
                            directory, record, round_number, generated_assertion)
                        capture_tree_usage({'input_tokens': 0, 'output_tokens': 0})
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
                if status in {"FORMAT_ERROR", "INPUT_ERROR", "SYNTAX_ERROR"}:
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
                        "with requirement-based tree diagnosis and rule selection.", flush=True,
                    )
                stage = "tree_construction"
                try:
                    if candidates is None:
                        stage = "retrieval"
                        retrieved = retriever.retrieve(inputs["requirement"])
                        candidates = prepare_candidates(retrieved, getattr(retriever, "masking_contexts", {}))
                        record['retrieved_rule_bank'] = rule_generator.compact_rule_bank(candidates)
                        run_io.update_run(directory, record, retrieved_cases=[
                            {"case_number": case["case_number"], "similarity": case["similarity"]}
                            for case in retrieved])
                        run_io.save_debug_event(directory, record, 'retrieval',
                                                rule_bank=record['retrieved_rule_bank'])
                        print("Retrieved rule case IDs:", [c["case_number"] for c in candidates], flush=True)
                        for case in candidates:
                            print(f"  Training case {case['case_number']}: "
                                  f"{len(case['revision_trace'])} revision rounds; "
                                  f"{case['trace_status']}", flush=True)
                    stage = "tree_construction"
                    run_io.update_run(directory, record, stage=stage)
                    with run_io.measure_stage(record, "diagnosis") as capture_tree_usage:
                        tree = inspection_trees['generated']
                        capture_tree_usage({"input_tokens": 0, "output_tokens": 0})
                    record["round_evidence"][-1]["generated_tree"] = tree
                    if "parse_error" in tree:
                        print(f"Round {round_number}: unsupported tree syntax; using explicit source anchor: "
                              f"{tree['parse_error']}", flush=True)
                    stage = "rule_generation"
                    stage = 'rule_generation'
                    print(f"Round {round_number}: one LLM call for bottom-up diagnosis, rule selection "
                          "and adaptation.", flush=True)
                    run_io.update_run(directory, record, stage=stage)
                    rule_prompt = rule_generator.build_rule_prompt(
                        inputs['requirement'], inputs['testbench'], tree, candidates,
                        comparison_scope=comparison_scope, rule_bank=record['retrieved_rule_bank'])
                    run_io.save_debug_event(directory, record, "rule_request")
                    with run_io.measure_stage(record, "rule") as capture_usage:
                        rule_response = model_io.request_text(
                            client=client, model=config.RULE_MODEL,
                            instructions=rule_generator.SYSTEM_PROMPT, user_prompt=rule_prompt,
                            json_output=True, usage_callback=capture_usage,
                        )
                    evidence = record["round_evidence"][-1]
                    evidence["inference_raw_response"] = rule_response
                    run_io.save_debug_event(directory, record, "rule_response", raw_response=rule_response)
                    # Pass the FULL unmodified model response, independent of parsing/export.
                    latest_diagnosis_response = rule_response
                    latest_generated_tree = rule_generator.compact_tree(tree, include_source=False)
                    latest_diagnosis_round = round_number
                    stage = "response_format"
                    run_io.update_run(directory, record, stage=stage)
                    diagnosis = rule_generator.parse_response(rule_response, tree,
                        [{'rules': [{'id': rule_id} for rule_id in
                                    rule_generator.bank_rule_ids(record['retrieved_rule_bank'])]}])
                    evidence["inference_diagnosis"] = deepcopy(diagnosis)
                    latest_diagnosis_response = json.dumps(diagnosis, ensure_ascii=False)
                    selected = {rule_id for item in diagnosis["corrections"] for rule_id in item["source_rule_ids"]}
                    task_derived = sum(not item['source_rule_ids'] for item in diagnosis['corrections'])
                    print(f"Round {round_number}: {len(diagnosis['corrections'])} independent corrections; "
                          f"{len(selected)} retrieved training rules selected; "
                          f"{task_derived} task-derived corrections.", flush=True)
                    new_rules = rule_generator.export_rules(diagnosis, round_number)
                    replacement = deepcopy(registry)
                    update_rule_registry(replacement, new_rules, round_number)
                    registry = replacement
                    run_io.update_run(directory, record, diagnosis=diagnosis,
                                      diagnosis_model=config.RULE_MODEL,
                                      rule_registry=retained_rules(registry))
                    run_io.save_diagnosis_model(record, config.RULE_MODEL)
                    if not diagnosis['corrections']:
                        print(f"Round {round_number}: no actionable guidance; stopping this case "
                              "without accepting the assertion.", flush=True)
                        run_io.update_run(directory, record, status='COMPLETED', passed=False,
                                          stage='finished', stop_reason='no_guidance')
                        return 0
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
