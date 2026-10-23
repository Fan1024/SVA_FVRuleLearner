"""One generate/evaluate/revise loop; stage-specific prompts stay in train/infer modules."""

from copy import deepcopy
from pathlib import Path
from tempfile import TemporaryDirectory
from openai import OpenAI
from new_agent import config, formal_check, model_io, run_io


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
        "bleu": None, "rouge": None, "exact_match": None,
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


def run_pipeline(directory, record: dict, *, retriever=None) -> int:
    """Stop on PEC/BLEU success or exhaustion of the configured attempt budget.

    Ordinary generation, extraction, checker, diagnosis and rule-output errors
    are round outcomes. KeyboardInterrupt/SystemExit are deliberately not caught.
    File-system failures can still prevent reliable recording and must propagate.
    """
    inference = record["settings"].get("phase", "train") == "infer"
    if inference:
        from new_agent import infer_assertion_generator as assertion_generator
        from new_agent import infer_rule_generator as rule_generator
        from new_agent.infer_diagnosis import diagnose_inference_assertion as diagnose
        if retriever is None:
            raise ValueError("Retrieval-backed inference requires the resolved training-rule retriever.")
    else:
        from new_agent import train_assertion_generator as assertion_generator
        from new_agent import train_rule_generator as rule_generator
        from new_agent.train_diagnosis import diagnose_assertion_mismatches as diagnose
        from new_agent.train_diagnosis_formatter import format_diagnosis
    retrieved_cases = None
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
                user_prompt = assertion_generator.build_generation_prompt(
                    requirement=inputs["requirement"], testbench=inputs["testbench"],
                    previous_assertion=previous_assertion, rules=selected_rules,
                    case_history=record["round_evidence"][:-1],
                    comparison_scope=comparison_scope, revision_feedback=revision_feedback,
                    assertion_template=policy.get("assertion_template", "asrt: assert property (@(posedge clk) BODY);"),
                )
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
            if not inference and status == "INPUT_ERROR" and formal_result.get("error_origin") == "candidate":
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
                    f"with {'requirement-based' if inference else 'reference-based'} diagnosis and rule generation.", flush=True,
                )
            stage = "diagnosis"
            try:
                if inference and retrieved_cases is None:
                    stage = "retrieval"
                    run_io.update_run(directory, record, stage=stage)
                    retrieved_cases = retriever.retrieve(inputs["requirement"])
                    evidence = [{"case_number": c["case_number"], "design_name": c.get("design_name"),
                                 "task_id": c.get("task_id"), "similarity": c["similarity"]}
                                for c in retrieved_cases]
                    run_io.update_run(directory, record, retrieved_cases=evidence)
                    run_io.save_debug_event(directory, record, "retrieval", cases=retrieved_cases)
                    print("Retrieved case IDs:", [c["case_number"] for c in retrieved_cases], flush=True)
                stage = "diagnosis"
                print(f"Round {round_number}: running Jev "
                      f"{'rule applicability' if inference else 'diagnosis'}.", flush=True)
                run_io.update_run(directory, record, stage=stage)
                with run_io.measure_stage(record, "diagnosis") as capture_usage:
                    diagnosis_inputs = {
                        "requirement": inputs["requirement"],
                        "generated_assertion": generated_assertion,
                        "design_context": inputs["testbench"],
                        "comparison_scope": comparison_scope,
                        "usage_callback": capture_usage,
                    }
                    if inference:
                        diagnosis_inputs.update(retrieved_cases=retrieved_cases,
                                                confidence_threshold=config.CONFIDENCE_THRESHOLD)
                    else:
                        diagnosis_inputs.update(
                            reference_assertion=inputs["reference_assertion"],
                            formal_feedback=formal_result["feedback"],
                        )
                    diagnosis = diagnose(**diagnosis_inputs)
                run_io.update_run(directory, record, stage=stage, diagnosis=diagnosis,
                                  diagnosis_model=diagnosis.get("model"))
                run_io.save_diagnosis_model(record, diagnosis.get("model"))
                if inference:
                    selected = diagnosis["selected_rules"]
                    selected_ids = {rule["question_id"] for rule in selected}
                    record["round_evidence"][-1]["retrieved_rule_selection"] = {
                        question_id: {
                            "source_case_number": candidate["source_case_number"],
                            "source_rule_id": candidate["source_rule_id"],
                            **diagnosis["answers"][question_id],
                            "selected": question_id in selected_ids,
                        } for question_id, candidate in diagnosis["candidates"].items()
                    }
                    run_io.save_debug_event(directory, record, "diagnosis", diagnosis=diagnosis, selected_rules=selected)
                    run_io.save_debug_event(directory, record, "rule_selection", selected_rules=selected)
                    print(f"Round {round_number}: Jev selected {len(selected)}/"
                          f"{len(diagnosis['answers'])} retrieved rules.", flush=True)
                else:
                    stage = "formatting"
                    run_io.update_run(directory, record, stage=stage)
                    statements = None
                    try:
                        statements = format_diagnosis(diagnosis["answers"], confidence_threshold=config.CONFIDENCE_THRESHOLD)
                    finally:
                        run_io.save_debug_event(directory, record, "diagnosis", diagnosis=diagnosis, statements=statements)
                    run_io.update_run(directory, record, statements=statements)
                    run_io.save_debug_event(directory, record, "statements", statements=statements)
                stage = "rule_generation"
                print(f"Round {round_number}: running rule generation.", flush=True)
                run_io.update_run(directory, record, stage=stage)
                rule_inputs = {
                    "requirement": inputs["requirement"],
                    "generated_assertion": generated_assertion,
                    "testbench": inputs["testbench"],
                    "comparison_scope": comparison_scope,
                }
                if inference:
                    rule_inputs["selected_rules"] = selected
                    rule_inputs["case_history"] = record["round_evidence"]
                else:
                    rule_inputs.update(statements=statements,
                                       reference_assertion=inputs["reference_assertion"],
                                       formal_feedback=formal_result["feedback"])
                stage = "rule_generation"
                run_io.update_run(directory, record, stage=stage)
                rule_prompt = rule_generator.build_rule_prompt(**rule_inputs)
                rule_attempt = {"round": round_number, "model": config.RULE_MODEL,
                                "raw_response": None, "rules": None}
                run_io.update_run(directory, record, last_rule_generation=rule_attempt)
                run_io.save_debug_event(directory, record, "rule_request")
                with run_io.measure_stage(record, "rule") as capture_usage:
                    rule_response = model_io.request_text(
                        client=client, model=config.RULE_MODEL, instructions=rule_generator.SYSTEM_PROMPT,
                        user_prompt=rule_prompt, json_output=True,
                        usage_callback=capture_usage,
                    )
                rule_attempt["raw_response"] = rule_response
                run_io.save_debug_event(directory, record, "rule_response", raw_response=rule_response)
                stage = "rule_validation"
                run_io.update_run(directory, record, stage=stage)
                new_rules = model_io.parse_rules(rule_response)
                rule_attempt["rules"] = new_rules
                # Commit only a completely validated update; never leave a partial registry.
                replacement = deepcopy(registry)
                update_rule_registry(replacement, new_rules, round_number)
                registry = replacement
                record["round_evidence"][-1]["rules_generated"] = deepcopy(new_rules)
                run_io.update_run(directory, record, rule_registry=retained_rules(registry))
                if new_rules:
                    run_io.save_debug_event(directory, record, "rule_update", rule_registry=record["rule_registry"])
            except Exception as error:
                _remember_round_error(directory, record, round_number, stage, error)
                run_io.update_run(directory, record, diagnosis_skipped_reason=f"{stage} failed; continuing next round.")

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


