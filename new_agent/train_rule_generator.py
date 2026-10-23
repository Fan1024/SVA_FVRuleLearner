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
Inspect the testbench or module interface to clarify signal meanings, widths,
parameters and relationships. If the requirement omits information needed to
express its intended behavior, consider additional declared signals supported
by that context. Do not add signals or conditions merely because they are
available, and do not invent undeclared signals.
"""


TASK_INSTRUCTIONS = """TASK
1. Compare the generated assertion with the reference within comparison_scope.
   Use the requirement, testbench and formal feedback to explain the behavioral
   difference. Use relevant diagnosis statements and discard incorrect ones.
2. Write each rule as a reusable conditional correction:
   "When [behavioral condition], [generated construct] causes [specific issue].
   Replace/Remove/Insert/Modify [construct at its location] to [concrete edit],
   so [required effect]."
   Connect requirement, issue and action; do not merely name an operator category.
   State applicability in terms observable from a new requirement and assertion,
   not "when the reference requires it". If prose conflicts with the reference,
   state that conflict and identify the benchmark-specific correction; do not
   generalize the conflict into a universal language-to-operator mapping.
3. Describe signals and parameters by behavioral role. Generalize related
   operators only when the same semantic principle applies: a four-state
   comparison correction can cover == to === or != to !==, preserving the
   required equality/inequality polarity. Retain essential timing, width,
   parameter, reset and X/Z conditions. Do not generalize a case-specific
   constant, signal name or edit into an unconditional instruction.
4. Group corrections addressing the same issue and edit location. Keep independent
   issues separate and resolve conflicting proposals. Use descriptive lowercase
   snake_case group labels and supporting diagnosis question IDs where relevant.
5. Respect comparison_scope and the single-assertion interface. Excluded labels,
   clock/reset wrappers and equivalent reset aliases are not semantic fixes.
   Do not change assertion semantics solely to repair PEC compilation problems.

PROHIBITED GUIDANCE
- Do not generate "keep unchanged", "keep the assertion unchanged",
  "retain the current assertion", or "Modify no assertion construct yet" rules.
- Do not return clarification-only guidance such as "re-analyze before editing"
  or "wait until the requirement is clarified".
- Every rule must specify a concrete assertion correction for the next attempt.
- Do not output complete assertions, copied property bodies or instructions
  to copy the reference.

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


