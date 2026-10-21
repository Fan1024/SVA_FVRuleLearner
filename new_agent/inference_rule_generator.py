"""Standalone inference diagnosis -> retrieval -> guidance; print results only."""

import json
import re

from openai import OpenAI

from inference_diagnosis_formatter import format_inference_diagnosis
from jev_inference_diagnosis import (
    requirement,
    generated_assertion,
    design_context,
    diagnose_inference_assertion,
)
from retrieve_similar_cases import TRAINING_RUN_DIR, TOP_K, retrieve_similar_cases


RULE_MODEL = "gpt-5.6-terra"
CONFIDENCE_THRESHOLD = 0.4

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


def generate_inference_rules(
    requirement,
    generated_assertion,
    statements,
    retrieved_cases,
    design_context="",
    *,
    model=RULE_MODEL,
    client=None,
):
    """Return groups/rules in training's format; accept no reference input."""
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
        "design_context": design_context,
        "diagnosis_statements": statements,
        "retrieved_cases": historical_cases,
    }
    print("\nINFERENCE RULE GENERATOR INPUT")
    print(json.dumps(inputs, indent=2, ensure_ascii=False))

    if client is None:
        client = OpenAI()
    response = client.responses.create(
        model=model,
        instructions=SYSTEM_PROMPT,
        input="Generate grouped guidance for the next assertion attempt.\n"
              + json.dumps(inputs, indent=2, ensure_ascii=False),
        text={"format": {"type": "json_object"}},
    )
    if response.status != "completed":
        raise RuntimeError(f"Inference rule generation did not complete: {response.status}")
    try:
        rules = json.loads(response.output_text)
    except ValueError as error:
        raise ValueError(f"Rule generation returned invalid JSON:\n{response.output_text}") from error
    if not isinstance(rules, dict) or not rules:
        raise ValueError("Expected at least one labeled inference guidance rule.")
    if set(rules) != {f"rule_{number}" for number in range(1, len(rules) + 1)}:
        raise ValueError("Use consecutive names: rule_1, rule_2, and so on.")
    seen_groups = set()
    for name, entry in rules.items():
        if not isinstance(entry, dict) or set(entry) != {"group", "rule"}:
            raise ValueError(f"{name} must contain only group and rule.")
        group = entry["group"]
        if (not isinstance(group, list) or not group
                or any(not isinstance(label, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", label)
                       for label in group)):
            raise ValueError(f"{name}.group needs nonempty lowercase snake_case labels.")
        if len(group) != len(set(group)):
            raise ValueError(f"{name}.group repeats a label.")
        key = tuple(sorted(group))
        if key in seen_groups:
            raise ValueError("Generate one guidance rule per distinct group.")
        seen_groups.add(key)
        if not isinstance(entry["rule"], str) or not entry["rule"].strip():
            raise ValueError(f"{name}.rule must be nonempty natural-language guidance.")
    return rules


if __name__ == "__main__":
    # Construct the OpenAI client first so a missing key fails before Jev runs.
    client = OpenAI()
    print("Running reference-free inference diagnosis...", flush=True)
    diagnosis = diagnose_inference_assertion(requirement, generated_assertion, design_context)
    print("\nDIAGNOSIS ANSWERS")
    print(json.dumps(diagnosis["answers"], indent=2))
    print("Diagnosis usage:", diagnosis["usage"])
    statements = format_inference_diagnosis(diagnosis["answers"], CONFIDENCE_THRESHOLD)

    print("\nRetrieving cases with rules from:", TRAINING_RUN_DIR, flush=True)
    retrieved_cases = retrieve_similar_cases(requirement, TRAINING_RUN_DIR, TOP_K)
    print("Retrieved case numbers:", [case["case_number"] for case in retrieved_cases])
    rules = generate_inference_rules(
        requirement, generated_assertion, statements, retrieved_cases,
        design_context, client=client,
    )
    print("\nINFERENCE GUIDANCE RULES")
    print(json.dumps(rules, indent=2, ensure_ascii=False))
