"""Build reference-free guidance requests from diagnosis and retrieved rules."""

import json

SYSTEM_PROMPT = """You generate reusable natural-language guidance for revising a
SystemVerilog assertion during inference. Your evidence is the requirement,
design context, current generated assertion, diagnosis statements, and rules
retrieved from historical training cases. No reference assertion is provided.
Do not invent a hidden reference or assume the current assertion is incorrect.

Diagnosis statements and retrieved rules are hypotheses, not verified facts.
Check their applicability using the current requirement, assertion and context.
Presence observations do not by themselves require an edit. Global edit-count
statements are estimates, not equivalence proofs. A high requirement-similarity
score does not establish that a historical correction applies to this case.
Even a passed historical case does not prove each of its rules caused success.

Select, adapt or combine the relevant retrieved rules. Ignore unrelated,
unsupported or conflicting guidance. You may identify a supported issue beyond
the diagnosis statements. Preserve behavior that already meets the requirement.
Account for sampling, delays, vacuity, signal widths, X/Z behavior, reset aliases
and disable iff semantics where the supplied inputs establish them. Do not
recommend a reset change solely because two equivalent aliases differ in text.

Group corrections about the same behavioral issue and edit location. Keep
independent corrections in separate groups, even if they share an operator
category. Resolve competing edits instead of returning contradictory commands.
For each group, write one concise editing principle saying what should change,
where, and under what behavioral condition. Use Replace, Remove, Insert or Modify
when an edit is supported. Describe signals by their roles rather than copying
historical signal names, parameters, literal expressions or complete assertions.

Choose descriptive lowercase snake_case group labels. Reuse a retrieved label
only when its meaning applies. Include diagnosis question IDs in the group when
their statements actually support the guidance; they are not mandatory labels.
Do not attach unsupported statements merely to obtain a matching label.

Return a nonempty JSON object with consecutive keys rule_1, rule_2, and so on.
Each entry must contain exactly these two fields:
- group: a nonempty list of descriptive labels and/or supporting question IDs.
- rule: one nonempty natural-language guidance string.
Return one rule per distinct group. Do not output an assertion or additional
assessment fields. If no specific edit is established, return an actionable
re-analysis instruction that states the uncertainty, checks the relevant
requirement/context, and preserves already-supported behavior. Do not invent
a specific defect to satisfy the nonempty-output requirement.
"""


def build_rule_prompt(
    requirement: str, generated_assertion: str, statements: dict,
    retrieved_cases: list[dict], testbench: str, *, comparison_scope: str,
) -> str:
    """Whitelist historical evidence; accept neither reference nor raw PEC output."""
    historical_cases = []
    for case in retrieved_cases:
        # Explicit fields prevent extra saved fields from entering the prompt.
        historical_cases.append({
            "case_number": case["case_number"],
            "design_name": case.get("design_name"),
            "task_id": case.get("task_id"),
            "requirement": case["requirement"],
            "similarity": case.get("similarity"),
            "passed": case.get("passed"),
            "rules": [
                {
                    "source_rule_id": rule_id,
                    "group": case.get("rule_groups", {}).get(rule_id, []),
                    "rule": text,
                }
                for rule_id, text in case["rules"].items()
                if isinstance(text, str) and text.strip()
            ],
        })
    inputs = {
        "requirement": requirement,
        "generated_assertion": generated_assertion,
        "design_context": testbench,
        "diagnosis_statements": statements,
        "retrieved_cases": historical_cases,
        "comparison_scope": comparison_scope,
    }
    return ("Generate grouped guidance for the next assertion attempt. Return a JSON object.\n"
            + json.dumps(inputs, indent=2, ensure_ascii=False))
