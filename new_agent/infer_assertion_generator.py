"""Minimal inference generation with independent rule and location guidance."""
import json

from new_agent.training_prompt_context import TESTBENCH_GUIDANCE, GUIDANCE_STATUS


SYSTEM_PROMPT = """Generate one complete SystemVerilog assertion for the current
requirement using the complete supplied testbench or module context.
Focus on required behavior, not literal similarity to a training assertion.
The current target's reference assertion is never supplied to you.

Accepted generated training examples illustrate other tasks. Their signals,
guards, constants and timing are not requirements of this task. Interpret source
placeholders in selected training rules by behavioral role; never emit a training
placeholder or blindly copy source-specific signal names into the current assertion.

During revision, review the latest generated assertion. Two independent types
of guidance may be supplied: ranked existing rules and suspected issue locations.
No rule has been assigned to a location. Validate their premises against the task
and decide whether and how any rule can help. Rules may be adapted or rejected;
locations are diagnostic suggestions, not mandatory edits or a complete defect list.

An empty locations list, empty rule list, missing selector response or unavailable
tree does NOT mean preserve the assertion and does NOT imply it passed. Independently
review the whole assertion and make task-supported behavioral or syntax corrections
where needed, including outside reported locations. Do not invent changes just to
produce different text; preserve required behavior and avoid cosmetic rewrites.

For a reported occurrence, use its structural path and exact expression together.
Identical source text elsewhere is a different occurrence. Treat every location
as specific to the indicated assertion round; do not carry old locations forward.

Check trigger, response, guards, sampling, timing, reductions, relevant history,
polarity, widths and valid indices. Follow the requested statement format.
Return only one complete assertion in a systemverilog code block. No analysis
report, module, error-message action, tree, node IDs or patch.
""" + "\n" + TESTBENCH_GUIDANCE + "\n" + GUIDANCE_STATUS


def build_generation_prompt(requirement, testbench, *, examples=None,
                            previous_assertion=None, previous_round=None,
                            selector_guidance=None,
                            assertion_template="assert property (@(posedge clk) BODY);"):
    """Explicit allowlist: task, generated examples, latest source and guidance."""
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
    if pairs:
        sections.append("ACCEPTED GENERATED TRAINING EXAMPLES\n" + json.dumps(pairs, ensure_ascii=False, indent=2))
    if previous_assertion is not None:
        if not isinstance(previous_assertion, str) or not previous_assertion.strip():
            raise ValueError("Previous assertion must be nonempty source text.")
        if type(previous_round) is not int or previous_round < 1:
            raise ValueError("Previous assertion requires its positive source round.")
        sections.append(f"LATEST GENERATED ASSERTION — ROUND {previous_round}\n" + previous_assertion)
        from new_agent.infer_rule_selector import generator_view
        if selector_guidance is not None:
            view = generator_view(selector_guidance, previous_assertion, previous_round)
            sections.append("LATEST SELECTOR GUIDANCE — TWO INDEPENDENT LISTS\n" + json.dumps(view, ensure_ascii=False, indent=2))
        else:
            sections.append("SELECTOR GUIDANCE\nUnavailable. Independently review and revise the assertion from the task.")
        sections.append(
            "Empty or missing locations do not instruct you to preserve the assertion. "
            "Review the whole task; use only corrections justified by its required behavior or syntax."
        )
    elif selector_guidance is not None or previous_round is not None:
        raise ValueError("Selector guidance requires its current source assertion and round.")
    output = "OUTPUT FORMAT\n" + assertion_template
    if "CLOCK_SIGNAL" in assertion_template:
        output += "\nReplace EDGE/CLOCK_SIGNAL with the required edge and actual declared clock; use reset disabling only if required."
    else:
        output += "\nKeep the shown clock/reset statement convention and replace BODY with the required property."
    output += "\nReturn exactly one complete assertion enclosed in ```systemverilog and ```. Output no other text."
    sections.append(output)
    return "\n\n".join(sections)
