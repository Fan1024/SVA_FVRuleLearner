"""Build rule-generation requests and validate the returned correction groups."""

import json

from openai import OpenAI


SYSTEM_PROMPT = """You analyze SystemVerilog assertion mismatches and generate
reusable natural-language correction rules. Diagnosis statements are hypotheses, not facts.
Use the requirement, testbench, and reference to assess and group them.
Return one JSON object containing only groups and their correction rules.
Work only on issues represented by the supplied statements.
The reference is analysis evidence. The later assertion-generation call will
receive the requirement, testbench, and your guidance, but no reference assertion.
Your rules must guide that call without copying the reference implementation.
"""


TASK_INSTRUCTIONS = """Group the supplied diagnosis statements into correction
issues. Generate exactly ONE rule for EACH group. There is no fixed rule count;
the number of rules is determined by the number of supported correction groups.

HOW TO GROUP STATEMENTS
- Check the statements against the requirement, generated assertion, reference,
  and testbench. Presence observations are evidence, not automatic edit commands.
- Exclude factually incorrect observations from the output groups. For example,
  a claim that a category occurs only in the reference is incorrect if the
  generated assertion also contains that category. Do not treat it as support.
- Group statements that concern the SAME behavioral issue and edit location.
  Related statements from different operator categories may belong together.
- Use the smallest coherent correction principle. Sharing the same assertion
  body or contributing to one large replacement is NOT enough to form a group.
  Ask whether the corrections need different semantic justifications or can be
  applied independently. If so, separate them. For example, changing the handling
  of X/Z in a comparison is usually independent of restructuring an implication
  into a Boolean violation check, even when both affect the same property body.
- Investigate: Are these competing corrections for the same occurrence, or are
  they corrections to different occurrences? Are they parts of one expression rewrite?
- When removal and replacement are competing proposals for the same occurrence,
  consider them together and choose the correction supported by the assertions.
- When edits are complementary parts of one rewrite, put them in one group.
  For example, implication removal and logical insertion may form one correction.
- Keep independent issues separate, even if their statements share a category.
  A supported issue described by only one statement can form a group by itself.
- Do not force every statement into a group. Omit unsupported or unresolved
  recommendations unless considering them helps resolve a supported correction.
  Do not create a group containing only observations with no supported edit.
- A statement ID may appear in more than one group if it supports distinct issues.

HOW TO GENERATE THE RULE FOR EACH GROUP
- Write one concise NATURAL-LANGUAGE instruction describing the correction
  principle for that group, including the behavioral condition under which it applies.
- Explicitly say WHAT construct changes to WHAT construct and WHERE in the
  property structure, using 'Replace', 'Remove', 'Insert', or 'Modify'.
  Operators such as |=>, |->, &&, ||, ==, and === may be named in short form.
- Describe signals and parameters by their semantic roles, such as the previous
  sampled value, upper bound, lower bound, trigger, response, and reset guard.
  Avoid copying this example\'s signal names, parameter names, or literal expressions.
- Do not provide a complete assertion, property body, before/after code pair,
  or instruction to replace the generated body with the reference body.
  Derive the reusable correction principle from that difference instead.
- Guidance example from a DIFFERENT task: 'When the response must be checked
  in the trigger\'s sampled cycle, replace non-overlapping implication (|=>)
  with overlapping implication (|->) between the trigger and response.'
  This demonstrates rule style only; do not assume this correction fits the input.
- If a group requires several coordinated edits, combine them into one rule.
- Resolve competing proposals rather than issuing incompatible commands.
- Avoid vague instructions such as 'fix the timing' or 'match the reference'.
- Work only on issues covered by the supplied statements. Do not add new issues,
  labels, keywords, assessment sections, or a complete rewritten assertion.

OUTPUT
Return only a JSON object with consecutive keys rule_1, rule_2, and so on.
Each entry must contain exactly TWO fields:
- group: a list of original statement IDs belonging to the correction group.
- rule: the reusable natural-language editing instruction for that group.
The layout below illustrates one entry, not a limit of one rule. Generate one
entry per supported group. Return {} if no supported correction can be formed.
"""


OUTPUT_LAYOUT = {
    "rule_1": {
        "group": ["original statement ID", "another related statement ID"],
        "rule": "When a behavioral condition applies, replace/remove/insert/modify the relevant construct as specified by this correction principle.",
    },
}


def build_rule_prompt(
    requirement: str,
    generated_assertion: str,
    reference_assertion: str,
    statements: dict,
    testbench: str,
) -> str:
    """Build the prompt from data; this function makes no API call."""
    inputs = {
        "requirement": requirement,
        "generated_assertion": generated_assertion,
        "reference_assertion": reference_assertion,
        "statements": statements,
        "testbench": testbench,
    }
    return (
        TASK_INSTRUCTIONS
        + "\nOUTPUT LAYOUT\n" + json.dumps(OUTPUT_LAYOUT, indent=2)
        + "\nINPUT DATA\n" + json.dumps(inputs, indent=2, ensure_ascii=False)
    )


def generate_rules(client: OpenAI, model: str, user_prompt: str) -> str:
    """Make one request and return text so the caller can save it before parsing."""
    response = client.responses.create(
        model=model,
        instructions=SYSTEM_PROMPT,
        input=user_prompt,
        text={"format": {"type": "json_object"}},
    )
    if response.status != "completed":
        raise RuntimeError(f"Rule generation did not complete: {response.status}")
    if not response.output_text.strip():
        raise RuntimeError("The model returned no rule-generation output.")

    return response.output_text


def parse_rules(response_text: str) -> dict:
    """Decode a saved response; JSON validity does not prove rule correctness."""
    result = json.loads(response_text)
    if not isinstance(result, dict):
        raise ValueError("Expected a JSON object for the rule-generation result.")
    return result


def check_rule_groups(result: dict, statements: dict) -> None:
    """Check the two-field format and source IDs; this does not prove rule correctness."""
    expected_names = {f"rule_{number}" for number in range(1, len(result) + 1)}
    if set(result) != expected_names:
        raise ValueError("Use consecutive names: rule_1, rule_2, and so on.")
    for name, entry in result.items():
        if not isinstance(entry, dict) or set(entry) != {"group", "rule"}:
            raise ValueError(f"{name} must contain only group and rule.")
        group = entry["group"]
        if (
            not isinstance(group, list) or not group
            or any(not isinstance(item, str) or item not in statements for item in group)
        ):
            raise ValueError(f"{name}.group must list original statement IDs.")
        if len(group) != len(set(group)):
            raise ValueError(f"{name}.group contains a repeated statement ID.")
        if not isinstance(entry["rule"], str) or not entry["rule"].strip():
            raise ValueError(f"{name}.rule must contain an editing instruction.")

