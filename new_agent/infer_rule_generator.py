"""Build guidance without the current target's reference; training examples are allowed."""

import json

SYSTEM_PROMPT = """Generate correction rules for the next SystemVerilog assertion attempt.

BACKGROUND
The current assertion has not passed evaluation. You receive its requirement,
design context, diagnosis statements, and retrieved training cases.
Retrieved rules were learned for their own cases; decide which apply here.
Historical references belong to those training cases. The current case's
reference assertion is not provided.

TASK
1. Analyze the current requirement, design context, assertion and diagnosis.
2. Review each retrieved case's requirement, reference, generated assertions,
   rules and evaluation results to understand the original correction.
   A rule generated in round r analyzes that round's assertion; rules_used
   identifies later assertions generated with that rule.
3. Select only relevant rules. Do not apply every retrieved rule. Ignore
   unrelated or conflicting corrections. If none applies, derive corrections
   directly from the current requirement, context and diagnosis.
4. Generate concrete editing instructions using Replace, Remove, Insert or
   Modify. State what changes, where, and why it matches the requirement.
   Do not return "Modify no assertion construct yet", "keep the assertion
   unchanged", or instructions that only request further analysis.
5. Group corrections addressing the same issue; keep independent issues separate.
   Use descriptive lowercase snake_case labels and supporting diagnosis question
   IDs where relevant. Describe signals by their roles instead of copying
   historical names, constants or complete assertions.
6. Respect comparison_scope, actual parameter values and the single-assertion
   interface. Do not recommend surrounding generate loops or helper declarations.

OUTPUT
Return only a nonempty JSON object with consecutive keys rule_1, rule_2, etc.
Each entry must contain exactly:
- group: a nonempty list of labels and/or supporting diagnosis question IDs.
- rule: one concise natural-language editing instruction.
Return one rule per group. Do not output an assertion or extra fields.
"""


def build_rule_prompt(
    requirement: str, generated_assertion: str, statements: dict,
    retrieved_cases: list[dict], testbench: str, *, comparison_scope: str,
) -> str:
    """Whitelist training evidence; accept no target reference or raw PEC output."""
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
            "historical_reference_assertion": case.get("reference_assertion"),
            "round_evidence": case.get("round_evidence", []),
            "rules": [
                {
                    "source_rule_id": rule_id,
                    "generated_round": case.get("rule_rounds", {}).get(rule_id),
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
    task = "Generate grouped guidance for the next assertion attempt. Return a JSON object.\n"
    if not historical_cases:
        task += ("No historical training cases or rules are provided. Derive guidance only "
                 "from the current requirement, testbench, candidate and diagnosis statements.\n")
    return task + json.dumps(inputs, indent=2, ensure_ascii=False)
