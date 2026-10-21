"""Build rule-generation requests and validate the returned correction groups."""

import json
import re

from openai import OpenAI

from new_agent.formal_check import COMPARISON_SCOPE


SYSTEM_PROMPT = """You analyze SystemVerilog assertion mismatches and generate
reusable natural-language correction rules. Diagnosis statements are hypotheses, not facts.
They are supporting evidence, not an exhaustive list of potential issues.
You may explore potential issues beyond the supplied statements using the requirement,
testbench, generated assertion, and reference as background. Check whether a proposed
correction is supported before turning it into a rule.
Return one JSON object containing only groups and their correction rules.
Follow the supplied dataset-specific comparison_scope. Human and Machine use
different native extraction policies; excluded clock/reset wrappers are not
evidence of a PEC mismatch. Do not assume the full assertion was compared.
Use testbench definitions to recognize equivalent reset expressions and aliases.
Do not recommend a reset change just because its text differs from the reference.
Preserve native disable iff behavior; it is not an antecedent guard.
The reference is analysis evidence. The later assertion-generation call will
receive the requirement, testbench, and your guidance, but no reference assertion.
Your rules must guide that call without copying the reference implementation.
This call follows an unaccepted evaluation. PEC compilation may have failed
without an equivalence verdict. Do not treat checker compilation errors as proof
of a candidate defect or propose assertion edits solely to repair the checker.
Use the requirement, testbench, and reference to assess any proposed correction.
Always return at least one labeled
rule. If the precise correction remains uncertain, give an actionable re-analysis
instruction instead of returning an empty object or inventing a specific cause.
"""


TASK_INSTRUCTIONS = """Identify potential correction issues using the supplied
background, formal feedback, and diagnosis statements. Generate exactly ONE rule
for EACH group and at least ONE rule overall. Do not return an empty object.

HOW TO GROUP STATEMENTS
- Check the statements against the requirement, generated assertion, reference,
  and testbench. Presence observations are evidence, not automatic edit commands.
- You may explore potential issues not identified by diagnosis. Empty or weak
  statements do not establish equivalence and do not prevent this exploration.
- Identify the correction groups yourself and choose their descriptive labels
  from your analysis. No group name or prefix is prescribed. Use lowercase
  snake_case labels: start with a letter, then use letters, digits, and underscores.
  Describe the behavioral issue rather than this case's signal names. Reuse a
  label when the same issue recurs. You may also include original statement IDs
  when they support the rule and make its diagnostic evidence traceable.
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
- Do not force every statement into a group or attach an observed label that
  does not support the rule. Exclude unsupported correction claims. If no
  specific edit is established, use the re-analysis rule described below.
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
- Different syntax can be behaviorally equivalent. Do not invent a specific
  correction to satisfy the nonempty-output requirement. Use formal feedback
  and the reference to investigate what remains unresolved.
- If no specific correction is established, return an actionable instruction
  to re-derive the assertion from the requirement and testbench and reconsider
  its clock, disable condition, trigger, response, signal relations, and timing.
  Choose a descriptive label yourself for the issue or uncertainty you actually
  identified. Explain the uncertainty in the rule; do not present a hypothesis
  as an observed fact. No generic fallback group name is prescribed.
- Keep the output limited to groups and rules, without assessment sections
  or a complete rewritten assertion.

OUTPUT
Return only a JSON object with consecutive keys rule_1, rule_2, and so on.
Each entry must contain exactly TWO fields:
- group: a list of descriptive labels you choose and/or supporting statement IDs.
- rule: the reusable natural-language editing instruction for that group.
The layout below illustrates one entry, not a limit of one rule. Return at least
one entry. You must identify and name its group from the supplied evidence.
The label in the output layout is a placeholder, not a prescribed group name.
Never return {}.
"""


OUTPUT_LAYOUT = {
    "rule_1": {
        "group": ["your_descriptive_issue_label"],
        "rule": "When a behavioral condition applies, replace/remove/insert/modify the relevant construct as specified by this correction principle.",
    },
}


def build_rule_prompt(
    requirement: str,
    generated_assertion: str,
    reference_assertion: str,
    statements: dict,
    testbench: str,
    *,
    comparison_scope: str = COMPARISON_SCOPE,
    formal_feedback: str = "",
) -> str:
    """Build the prompt from data; this function makes no API call."""
    inputs = {
        "requirement": requirement,
        "generated_assertion": generated_assertion,
        "reference_assertion": reference_assertion,
        "statements": statements,
        "testbench": testbench,
        "comparison_scope": comparison_scope,
        "formal_feedback": formal_feedback,
    }
    return (
        TASK_INSTRUCTIONS
        + "\nOUTPUT LAYOUT\n" + json.dumps(OUTPUT_LAYOUT, indent=2)
        + "\nINPUT DATA\n" + json.dumps(inputs, indent=2, ensure_ascii=False)
    )


def generate_rules(
    client: OpenAI, model: str, user_prompt: str, *, usage_callback=None,
) -> str:
    """Make one request and return text so the caller can save it before parsing."""
    response = client.responses.create(
        model=model,
        instructions=SYSTEM_PROMPT,
        input=user_prompt,
        text={"format": {"type": "json_object"}},
    )
    if usage_callback is not None:
        usage_callback(getattr(response, "usage", None))
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
    """Check output structure and label format, not a fixed list of group names."""
    if not result:
        raise ValueError("Rule generation returned no rules; expected at least one labeled rule.")
    expected_names = {f"rule_{number}" for number in range(1, len(result) + 1)}
    if set(result) != expected_names:
        raise ValueError("Use consecutive names: rule_1, rule_2, and so on.")
    for name, entry in result.items():
        if not isinstance(entry, dict) or set(entry) != {"group", "rule"}:
            raise ValueError(f"{name} must contain only group and rule.")
        group = entry["group"]
        if (
            not isinstance(group, list) or not group
            or any(
                not isinstance(item, str)
                or not re.fullmatch(r"[a-z][a-z0-9_]*", item)
                for item in group
            )
        ):
            raise ValueError(
                f"{name}.group must contain nonempty lowercase snake_case labels."
            )
        if len(group) != len(set(group)):
            raise ValueError(f"{name}.group contains a repeated label.")
        if not isinstance(entry["rule"], str) or not entry["rule"].strip():
            raise ValueError(f"{name}.rule must contain an editing instruction.")


