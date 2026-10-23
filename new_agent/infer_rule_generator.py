"""Build inference correction guidance from selected rules and compact case history."""

import json

SYSTEM_PROMPT = """Generate concrete correction rules for the next inference assertion.

BACKGROUND
You receive the current requirement, assertion, design context, Jev-selected
historical rules and compact case_history. Historical references belong only
to training examples; the current reference is not provided. Rejected and
low-confidence historical rules have been excluded. The latest history entry
is the current evaluated attempt, before its new rules are generated.

TASK
1. Analyze the requirement and testbench. Inspect signal definitions, widths,
   parameters and relationships. If the requirement omits essential information,
   consider additional declared signals supported by the context. Add signals
   or conditions only when they help express the intended behavior.
2. Check selected rules against this case. Map signals by role and adapt the
   underlying correction principle, including related operators with the required
   polarity. Discard inapplicable, already-resolved or conflicting guidance;
   you need not use every rule. Historical applications show attempts supplied
   with a rule, not proof that this rule alone fixed the source case. If no rule
   is usable, derive guidance from the current requirement and context.
3. Use case_history to identify repeated assertions, opposite edits and rules
   restating an already-present construct. When several attempts revisit the
   same issue without acceptance, explore a different behavioral cause rather
   than repeating or reversing the last edit. Revisit an earlier alternative
   only with a specific reason from the requirement or testbench; state that
   reason in the rule. Do not repeatedly toggle redundant parentheses.
4. Look beyond the previous diagnosis when the case is stuck:
   - Check signal roles: input versus tracker/model signal, current versus
     registered value, array index, bit range, width and parameter.
   - Check behavioral coverage: first versus later transactions, empty versus
     nonempty states, simultaneous operations and the correct data source.
     A historical rule may cover a different branch or miss a qualification.
   - Check structure: missing/extra guards or alternatives, trigger versus
     invariant, antecedent versus consequent, any-bit versus all-bit reduction,
     same-cycle versus next-cycle timing. Replace a mistaken structure when
     changing one operator cannot express the intended behavior.
   - Check truth/X/Z behavior: required true (=== 1'b1), forbidden definitely-true
     violation (!== 1'b1), negation and ordinary equality are not interchangeable.
     Add an explicit comparison only when the context supports that meaning.
5. PEC_COMPILE_ERROR provides no equivalence verdict. Do not treat it as evidence
   that the last semantic edit was wrong or that reversing it will help.
   Checker statuses are not counterexamples. Ground edits in current behavior;
   distinguish formatting normalization from semantic repair.
6. Each rule must connect applicability condition, current issue, concrete
   Replace/Remove/Insert/Modify action and intended effect. Combine compatible
   corrections, resolve conflicts and group by issue. Reuse meaningful historical
   labels or descriptive lowercase snake_case labels, not per-case Jev IDs.

CONSTRAINTS
Respect comparison_scope, timing, widths, parameters, reset and X/Z semantics.
Do not substitute historical timing for explicit current timing. Labels and
excluded clock/reset wrappers are not semantic fixes. Do not invent undeclared
signals, surrounding generate loops or helper declarations, copy historical
assertion bodies, or instruct copying a reference.
Prohibit "keep unchanged", "keep the assertion unchanged", "retain the current
assertion", "Modify no assertion construct yet" and clarification-only guidance.
Do not disguise an unchanged expression as a replacement rule. Every rule must
specify a concrete correction for the next attempt.

OUTPUT
Return only a nonempty JSON object with consecutive keys rule_1, rule_2, etc.
Each entry contains exactly group (a nonempty list of descriptive labels) and
rule (one concise natural-language correction). One rule per group. Do not
output an assertion or extra fields.
"""


def build_rule_prompt(
    requirement: str, generated_assertion: str,
    selected_rules: list[dict], testbench: str, *, comparison_scope: str,
    case_history: list[dict] | None = None,
) -> str:
    """Include compact case history, excluding current references, scores and tool text."""
    inputs = {
        "requirement": requirement,
        "generated_assertion": generated_assertion,
        "design_context": testbench,
        "selected_rules": [{key: rule.get(key) for key in (
            "question_id", "source_case_number", "source_rule_id", "source_requirement",
            "historical_reference_assertion", "group", "rule", "generated_round",
            "source_assertion", "source_evaluation", "applications", "applicability_confidence",
        )} for rule in selected_rules],
        "case_history": [{
            "round": entry.get("round"),
            "generated_assertion": entry.get("generated_assertion"),
            "checker_status": (entry.get("evaluation") or {}).get("status"),
            "rules_used": [{"group": rule.get("group"), "rule": rule.get("rule")}
                           for rule in entry.get("rules_used", [])],
            "rules_generated": [{"group": rule.get("group"), "rule": rule.get("rule")}
                                for rule in entry.get("rules_generated", {}).values()],
        } for entry in (case_history or []) if entry.get("generated_assertion")],
        "comparison_scope": comparison_scope,
    }
    task = "Generate grouped correction guidance for the next assertion attempt. Return a JSON object.\n"
    if not selected_rules:
        task += ("No historical rules were selected. Use the current requirement, "
                 "testbench and assertion to derive the next correction.\n")
    return task + json.dumps(inputs, indent=2, ensure_ascii=False)
