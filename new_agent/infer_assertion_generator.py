import json

from new_agent.formal_check import COMPARISON_SCOPE


SYSTEM_PROMPT = """You write SystemVerilog assertions from natural-language requirements.
Use the requirement and testbench or module interface as the specification.
Inspect signal definitions, widths, parameters and relationships. If the
requirement omits essential information, consider additional declared signals
supported by that context. Add signals or conditions only when they help express
the intended behavior; do not invent undeclared signals.

Before returning the assertion, check:
- Signals have the intended roles, data sources and time snapshots, with valid
  indices, widths and parameters.
- All required scenarios are covered. Where applicable, distinguish first/later
  operations, empty/nonempty states and simultaneous transactions. Preserve a
  required branch when correcting another part.
- Guards, implication timing and reductions express when the check applies,
  same-cycle/next-cycle behavior and any-bit/all-bit conditions.
- The complete predicate has the intended polarity: require valid behavior or
  reject a violation. Do not introduce an unintended negation. Choose explicit
  truth comparisons and X/Z handling only with the required meaning and scope.
Training examples demonstrate translation patterns. Adapt them to the current
requirement and testbench, using current signal declarations and only the guards
and timing required here. Follow the current dataset's assertion template and
comparison scope.
"""


def build_generation_prompt(
    requirement: str,
    testbench: str,
    previous_assertion: str | None = None,
    rules: list[dict] | None = None,
    *,
    comparison_scope: str = COMPARISON_SCOPE,
    revision_feedback: str | None = None,
    assertion_template: str = "asrt: assert property (@(posedge clk) BODY);",
    case_history: list[dict] | None = None,
    examples: list[dict] | None = None,
    diagnosis_response: str | None = None,
    previous_tree: dict | None = None,
) -> str:
    """Build a fresh initial or revision prompt; never accept a reference."""
    revision = ""
    if previous_assertion is not None:
        if not previous_assertion.strip():
            raise ValueError("A revision requires a nonempty previous assertion.")
        if diagnosis_response is not None:
            revision = (
                "\nPREVIOUS ASSERTION\n" + previous_assertion
                + "\n\nLATEST DIAGNOSIS RESPONSE\n" + diagnosis_response
                + "\nEND LATEST DIAGNOSIS RESPONSE\n"
                "Apply only the corrections selected in the latest diagnosis response, "
                "using each correction's difference, explanation and target-specific rule. "
                "If corrections is empty, preserve the previous assertion. "
                "source_rule_ids record provenance; they are not instructions to fetch or "
                "apply additional retrieved training rules. Check corrections against the CURRENT "
                "requirement and testbench. Training examples illustrate translation patterns; "
                "do not introduce extra edits from their assertion bodies. Preserve unrelated "
                "branches, signals and timing, and defer ancestors excluded by the bottom-up "
                "diagnosis. The current requirement, testbench and generated tree are unmasked; "
                "use their actual declared signal names, never training placeholders or IDs. "
                "Return one complete assertion.\n"
            )
            if previous_tree is not None:
                revision += ("\nPREVIOUS GENERATED TREE\n"
                             + json.dumps(previous_tree, ensure_ascii=False) + "\n")
        else:
            guidance = []
            for number, entry in enumerate(rules or [], 1):
                rule = entry.get("rule")
                if not isinstance(rule, str) or not rule.strip():
                    raise ValueError("Every selected rule must contain nonempty rule text.")
                guidance.append(f"{number}. {rule.strip()}")
            guidance_text = "\n".join(guidance) or (
                "No specific correction rule is available. Re-derive the assertion "
                "from the requirement and testbench, reviewing its clock, disable "
                "condition, trigger, response, signal relationships, and timing."
            )
            revision = (
                "\nRevise the previous assertion using the latest correction guidance.\n"
                "Check the guidance against the requirement and testbench; preserve required behavior.\n"
                "If no specific correction is available, review the behavioral checks above.\n"
                "Always return one complete assertion.\n"
                "\nPREVIOUS ASSERTION\n" + previous_assertion
                + "\n\nCORRECTION GUIDANCE\n" + guidance_text + "\n"
            )
    elif rules or diagnosis_response is not None or previous_tree is not None or case_history:
        raise ValueError("Rule feedback, trees and history require a previous assertion.")

    history = [{
        "round": entry.get("round"),
        "generated_assertion": entry.get("generated_assertion"),
        "checker_status": (entry.get("evaluation") or {}).get("status"),
        "rules_used": [{"group": rule.get("group"), "rule": rule.get("rule")}
                       for rule in entry.get("rules_used", [])],
        "rules_generated": [{"group": rule.get("group"), "rule": rule.get("rule")}
                            for rule in entry.get("rules_generated", {}).values()],
    } for entry in (case_history or []) if entry.get("generated_assertion")]
    history_guidance = (
        "\nUse this case's earlier attempts to identify repeated assertions and opposite edits.\n"
        "Earlier rules record attempted corrections; they are not cumulative instructions.\n"
        "Use the latest correction guidance for the next edit. Preserve required scenarios,\n"
        "and revisit an earlier form only for a specific behavioral reason from the task.\n"
        "A previously untried expression alone does not justify a change. Distinguish\n"
        "semantic correction from equivalent rewriting. PEC_COMPILE_ERROR provides no\n"
        "equivalence verdict and does not prove that an earlier candidate was wrong.\n"
        "CASE HISTORY\n" + json.dumps(history, indent=2, ensure_ascii=False)
        + "\nEND CASE HISTORY\n"
    ) if history else ""

    example_guidance = (
        "\nSIMILAR TRAINING EXAMPLES\n"
        + json.dumps([{
            "requirement": example["requirement"],
            "reference_assertion": example["reference_assertion"],
        } for example in examples], indent=2, ensure_ascii=False)
        + "\nEND TRAINING EXAMPLES\n"
    ) if examples else ""

    scope_guidance = (
        "\nEVALUATION SCOPE\n" + comparison_scope
        + "\nChoose clock and reset conditions from the task and testbench.\n"
        if comparison_scope else ""
    )
    retry_guidance = ("\nPREVIOUS ATTEMPT FEEDBACK\n" + revision_feedback + "\n") if revision_feedback else ""
    context_name = "module interface" if "CLOCK_SIGNAL" in assertion_template else "testbench"
    label_guidance = (
        "Put the label shown in the template before assert property, not after it."
        if ":" in assertion_template.split("assert property", 1)[0] else
        "Start with assert property; do not add an assertion label."
    )
    return f"""Here is the {context_name} to perform your translation:

{testbench}

{example_guidance}
Question: Create a SVA assertion checks {requirement}
{scope_guidance}{revision}{history_guidance}{retry_guidance}
Generate exactly one assertion using this statement structure:
{assertion_template}
If the testbench/task requires reset disabling, put disable iff (RESET) after
the clock event, inside the same outer parentheses.
{label_guidance}
Close the outer property parentheses before the final semicolon.
Do not add code to output an error message string.
Enclose your SVA code with ```systemverilog and ```.
Only output the code snippet and do NOT output anything else.

Answer:"""


