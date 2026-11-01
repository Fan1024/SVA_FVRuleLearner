"""Inference generation: diagnose the latest assertion before optional guidance."""
import json

from new_agent.training_prompt_context import TESTBENCH_GUIDANCE


PROMPT_VERSION = "inference_independent_behavior_review_v2"

SYSTEM_PROMPT = """Generate one complete SystemVerilog assertion for the current
requirement using the complete supplied testbench or module context.
Express the requested behavior. Use functional meaning to choose the assertion;
literal similarity to a training example is not an objective. The current
target's reference assertion is not supplied; do not guess its contents.

Use the requirement to establish which events, states and intervals are checked.
Use the testbench to interpret the relevant signals and omitted details. The
presence of other behavior in the testbench does not make it an obligation of
this assertion. In particular, distinguish an initial operation from subsequent
operations and a selected scenario from the complete design policy.

During revision, independently diagnose the previous generated assertion's
overall behavior before deciding on edits. Follow the revision procedure in
the request. This review is required; adopting any supplied rule is optional.
The previous assertion's presence does not establish a functional defect or
explain why an earlier evaluation did not accept it.

Treat all supplied guidance as fallible context for your own assessment:
- Accepted generated training examples illustrate solutions to other tasks.
- Ranked rules describe potentially useful correction principles. Rank is
  relative relevance, not authority or an instruction to apply the rule.
- source_diagnoses describe suspected issues in TRAINING assertions. They do
  not establish that the current assertion has the same issue.
- Selector locations and their expected/observed behavior describe suspected
  issues in the CURRENT previous assertion. They are suggestions, not facts,
  required edit sites, an exhaustive defect list or boundaries on your review.

No rule is assigned to a target location. Learn from the behavioral principles
when useful. You may use, adapt or disregard any suggestion, or derive a correction
directly from the requirement and testbench without using a supplied rule.
Do not reproduce an example's exact expression or edit pattern merely because
it was supplied. Preserve the current task's signal roles, guards and timing;
never emit source-training placeholders or blindly copy source-specific names.

For a reported current occurrence, its structural path and expression identify
what the selector examined. Identical text elsewhere is a different occurrence.
You may instead revise a containing expression or another location when your
behavioral diagnosis supports it. Source-training locations, when described
inside guidance, are examples from their source assertion, not target addresses.

Empty or missing rules/locations do not imply acceptance or require preservation.
Do not invent a defect or cosmetic rewrite just to produce different text.
Preserve behavior required by the task and make only supported corrections.

Carry out this review as part of generating the assertion. Return only one
complete assertion in a systemverilog code block. Do not output a separate
diagnosis report, reasoning transcript, module, tree, node IDs or patch.
""" + "\n" + TESTBENCH_GUIDANCE


REVISION_PROCEDURE = """REVISION PROCEDURE — INDEPENDENT BEHAVIOR REVIEW
1. Establish the required obligation and its scope from the current requirement
   and testbench: which events/states it covers, its activation conditions,
   expected response and timing, and any relevant initial/history condition.
2. Assess the latest assertion as a whole: what it requires, permits or exempts,
   and when. Identify supported high-level discrepancies before choosing local
   edits. Consider scope mismatch, missing or additional obligations, unjustified
   exemptions, timing/history, polarity, boundaries and ineffective checks.
   Also inspect the original source for structural syntax defects.
3. Then consider the optional selector observations, retrieved rules and source
   diagnoses, and training examples. Compare their premises with your own
   assessment. A useful principle may be adapted; neither its exact rule wording,
   source expression nor suggested target location must be followed. An irrelevant
   suggestion may be disregarded. No supplied rule needs to be used.
4. Generate the complete assertion from the supported diagnosis. A high-level
   issue may require a different guard, a containing subtree or a coordinated
   rewrite rather than an edit at a reported location. Check that the result
   expresses the requested obligation without adding unrelated requirements,
   and that its grouping and property operators form valid SystemVerilog.

This procedure guides generation; do not print its analysis. Return only the
complete assertion in the requested code block.
"""


def build_generation_prompt(requirement, testbench, *, examples=None,
                            previous_assertion=None, previous_round=None,
                            selector_guidance=None,
                            assertion_template="assert property (@(posedge clk) BODY);"):
    """Same inputs/output contract; revision review precedes optional guidance."""
    if not isinstance(requirement, str) or not requirement.strip():
        raise ValueError("A nonempty requirement is required.")
    if not isinstance(testbench, str) or not testbench.strip():
        raise ValueError("A nonempty complete testbench/module context is required.")
    sections = ["CURRENT REQUIREMENT\n" + requirement,
                "COMPLETE TESTBENCH OR MODULE CONTEXT\n" + testbench]
    pairs = []
    for example in examples or []:
        task, source = example.get("requirement"), example.get("solved_assertion")
        if not isinstance(task, str) or not task.strip() or not isinstance(source, str) or not source.strip():
            raise ValueError("Examples require a requirement and accepted generated solved_assertion.")
        # Deliberately no fallback to reference_assertion and no metadata dump.
        pairs.append({"requirement": task, "solved_assertion": source})
    if previous_assertion is not None:
        if not isinstance(previous_assertion, str) or not previous_assertion.strip():
            raise ValueError("Previous assertion must be nonempty source text.")
        if type(previous_round) is not int or previous_round < 1:
            raise ValueError("Previous assertion requires its positive source round.")
        sections.append(f"LATEST GENERATED ASSERTION — ROUND {previous_round}\n" + previous_assertion)
        sections.append(REVISION_PROCEDURE)
        from new_agent.infer_rule_selector import generator_view
        if selector_guidance is not None:
            view = generator_view(selector_guidance, previous_assertion, previous_round)
            sections.append(
                "OPTIONAL SELECTOR CONTEXT — INDEPENDENT RULES AND ISSUE OBSERVATIONS\n"
                + json.dumps(view, ensure_ascii=False, indent=2))
        else:
            sections.append(
                "OPTIONAL SELECTOR CONTEXT\nUnavailable. Independently review the whole "
                "behavior using the requirement, testbench and latest assertion; follow the same revision procedure.")
        sections.append(
            "Empty or missing locations do not instruct you to preserve the assertion. "
            "Diagnose the whole obligation independently. Use guidance only when its "
            "behavioral premise helps with this task; reported locations do not limit your edits."
        )
    elif selector_guidance is not None or previous_round is not None:
        raise ValueError("Selector guidance requires its current source assertion and round.")
    if pairs:
        sections.append("OPTIONAL ACCEPTED GENERATED TRAINING EXAMPLES\n"
                        + json.dumps(pairs, ensure_ascii=False, indent=2))
    output = "OUTPUT FORMAT\n" + assertion_template
    if "CLOCK_SIGNAL" in assertion_template:
        output += "\nReplace EDGE/CLOCK_SIGNAL with the required edge and actual declared clock; use reset disabling only if required."
    else:
        output += "\nKeep the shown clock/reset statement convention and replace BODY with the required property."
    output += "\nReturn exactly one complete assertion enclosed in ```systemverilog and ```. Output no other text."
    sections.append(output)
    return "\n\n".join(sections)
