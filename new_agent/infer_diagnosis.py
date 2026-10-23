"""Assess and filter retrieved training rules for the current inference assertion."""

from typesafe_sdk import Noul, TypeSafeClient


def diagnose_inference_assertion(requirement, generated_assertion, design_context="", *,
    retrieved_cases, comparison_scope="", confidence_threshold=0.4,
    client=None, usage_callback=None,
):
    """Ask one question per retrieved rule and retain confident yes answers."""
    active_questions = {}
    candidates = {}
    background = (
        "Assess each retrieved training rule against the CURRENT requirement, "
        "generated assertion and design_context. No current-case reference or "
        "PEC feedback is provided. Historical references belong only to training cases. "
        "Judge the rule's transferable behavioral principle, not an exact match "
        "to its original edit. Map signals by role and adapt related operators "
        "when they express the same correction, preserving required polarity. "
        "For example, a four-state equality principle may also guide four-state "
        "inequality when the current requirement needs inequality and X/Z handling. "
        "Answer yes when that principle addresses a current issue and supports "
        "a correction consistent with the current requirement and design context. "
        "Check timing, widths, parameters, reset and X/Z applicability conditions. "
        "Shared operators or topic similarity alone are insufficient. Answer no "
        "for unrelated, already-resolved, conflicting or out-of-scope guidance. "
        "Do not select label changes or excluded clock/reset wrapper changes as "
        "semantic corrections. Do not override explicit current-case timing merely "
        "because a historical benchmark reference used different timing. "
        "Use a Noul value near 0.5 when applicability cannot be determined. "
        "Inspect the testbench or module interface to clarify signal meanings, widths, "
        "parameters and relationships. If the requirement omits information needed to "
        "express its intended behavior, consider additional declared signals supported "
        "by that context. Do not add signals or conditions merely because they are "
        "available, and do not invent undeclared signals."
    )
    for case in retrieved_cases:
        for number, (rule_id, rule) in enumerate(case["rules"].items(), 1):
            question_id = f"case_{case['case_number']:04d}_rule_{number:04d}"
            source_round = case.get("rule_rounds", {}).get(rule_id)
            group = case.get("rule_groups", {}).get(rule_id, [])
            source = None
            applications = []
            for evidence in case.get("round_evidence", []):
                if source_round is not None and evidence["round"] == source_round:
                    source = evidence
                used = evidence.get("rules_used", [])
                if source_round is not None and any(
                    item.get("updated_round") == source_round
                    and item.get("rule") == rule
                    and set(item.get("group", [])) == set(group)
                    for item in used
                ):
                    applications.append({
                        "round": evidence["round"],
                        "generated_assertion": evidence.get("generated_assertion"),
                        "evaluation": evidence.get("evaluation"),
                        "other_rules_supplied": len(used) - 1,
                    })
            candidate = {
                "question_id": question_id,
                "source_case_number": case["case_number"],
                "source_rule_id": rule_id,
                "source_requirement": case["requirement"],
                "historical_reference_assertion": case.get("reference_assertion"),
                "group": group, "rule": rule, "generated_round": source_round,
                "source_assertion": source.get("generated_assertion") if source else None,
                "source_evaluation": source.get("evaluation") if source else None,
                "applications": applications,
            }
            candidates[question_id] = candidate
            active_questions[question_id] = Noul(instructions={
                "retrieved_rule": candidate,
                "question": (
                    "Does this rule provide a useful behavioral correction principle "
                    "for an issue in the current assertion, after adapting signal roles "
                    "and related operators while preserving the current requirement's "
                    "meaning, design constraints and comparison_scope?"
                ),
            })
    request_state = {
        "background": background,
        "comparison_scope": comparison_scope,
        "requirement": requirement,
        "generated_assertion": generated_assertion,
        "design_context": design_context,
    }
    if not active_questions:
        return {"answers": {}, "raw_answers": {}, "model": None,
                "state": request_state, "questions": {}, "candidates": candidates, "selected_rules": []}
    if client is None:
        with TypeSafeClient() as owned_client:
            response = owned_client.system_one(state=request_state, questions=active_questions)
    else:
        response = client.system_one(state=request_state, questions=active_questions)
    if usage_callback is not None:
        usage_callback(getattr(response, "usage", None))
    if set(response.answers) != set(active_questions):
        raise RuntimeError("Jev response question names do not match the request")
    answers = {}
    raw_answers = {}
    selected_rules = []
    for question_id in active_questions:
        raw = response.answers[question_id].model_dump(mode="json")
        raw_answers[question_id] = raw
        if raw["type"] != "noul":
            raise RuntimeError(f"Expected a Noul answer for {question_id}")
        answers[question_id] = {
            "answer": raw["noul"] > 0.5,
            "confidence": round(abs(2 * raw["noul"] - 1), 12),
        }
        if answers[question_id]["answer"] and answers[question_id]["confidence"] >= confidence_threshold:
            selected_rules.append({
                **candidates[question_id],
                "applicability_confidence": answers[question_id]["confidence"],
            })
    return {
        "answers": answers,
        "raw_answers": raw_answers,
        "model": response.model,
        "state": request_state,
        "candidates": candidates,
        "selected_rules": selected_rules,
        "questions": {key: value.model_dump(mode="json", exclude_none=True)
                      for key, value in active_questions.items()},
    }

