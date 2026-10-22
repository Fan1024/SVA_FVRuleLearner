"""Build training requests for reusable assertion-correction rules."""

import json
from new_agent.formal_check import COMPARISON_SCOPE


SYSTEM_PROMPT = """Generate reusable assertion-correction rules during training.

The current assertion has not passed evaluation. You receive the requirement,
testbench, generated assertion, reference assertion, diagnosis and formal feedback.
Use the reference behavior as the benchmark target, including when the prose
requirement conflicts with it. The next assertion generator receives your rules
but no reference assertion, so explain the correction without copying its code.
Connect the required behavior, the generated assertion's issue, and its correction
so the rule can later be selected for another case with the same kind of issue.
"""


TASK_INSTRUCTIONS = """TASK
1. Compare the generated assertion with the reference within comparison_scope.
   Analyze their behavior using the requirement, testbench and formal feedback.
   Use relevant diagnosis statements, discard incorrect ones, and investigate
   differences beyond the diagnosis when needed.
2. Connect three elements in every rule: the required behavior that makes the
   rule applicable; what the generated assertion does differently and why that
   matters; and the concrete edit that restores the required behavior.
   Use this pattern: "When [behavior is required], [the generated construct]
   instead [incorrect behavior]; Replace/Remove/Insert/Modify [construct at its
   location] to [correction], so [the required behavior is obtained]."
   Name the actual behavioral difference, not just an operator category.
   If the requirement conflicts with the reference, state that conflict rather
   than attributing the reference's behavior to the requirement.
   Do not return rules such as "keep the assertion unchanged", "retain the
   current assertion", "Modify no assertion construct yet", or "re-analyze
   before editing". Do not defer a correction until the requirement is clarified.
3. Group corrections addressing the same issue and edit location. Keep independent
   issues separate and resolve conflicting proposals. Use descriptive lowercase
   snake_case group labels and supporting diagnosis question IDs where relevant.
4. Write reusable natural-language rules. Describe signals and parameters by their
   roles. Operator names are allowed; complete assertions, copied property bodies
   and instructions to copy the reference are not.
5. Respect the dataset's comparison_scope, actual widths and parameter values.
   Excluded wrappers and equivalent reset aliases do not require correction.
   Do not change assertion semantics solely to repair PEC compilation problems.

OUTPUT
Return only a JSON object with consecutive keys rule_1, rule_2, and so on.
Each entry must contain exactly:
- group: a nonempty list of labels and/or supporting diagnosis question IDs.
- rule: one concise natural-language rule connecting required behavior, issue
  and concrete correction, including the condition under which it applies.
Return at least one rule and one rule per group. No assertions or extra fields.
"""


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
        + "\nINPUT DATA\n" + json.dumps(inputs, indent=2, ensure_ascii=False)
    )


