"""Training assertion generation: all prior assertions, only latest guidance."""
import json

from new_agent.correction_locations import feedback_json
from new_agent.training_prompt_context import (
    EQUIVALENT, NO_VERDICT, NOT_EQUIVALENT, TESTBENCH_GUIDANCE, GUIDANCE_STATUS,
)


SYSTEM_PROMPT = """You generate one complete SystemVerilog assertion for the
current natural-language requirement using the complete supplied testbench.
Your objective is the required behavior, not matching a particular spelling.

JasperGold checks functional equivalence against a golden/reference assertion.
That reference is not supplied to you. A history entry marked not equivalent
means a completed comparison failed full equivalence; a no-verdict entry does
not establish a functional mismatch. Use the requirement and testbench to reason
about the behavior rather than guessing the golden assertion's text.

During revision, review every earlier generated assertion and its recorded
outcome. History records attempted assertions, not cumulative correction rules.
Use it to recognize repetitions and unsupported reversals. Revisit an earlier
form only for a specific behavioral or syntax reason; novelty alone does not
justify a change.

Only the latest correction guidance supplies proposed edits. Each Location
identifies an occurrence in the indicated latest assertion using its structural
path and exact expression. Identical text elsewhere is a different occurrence.
Use that location, not an imagined node ID or a replacement tree. Keep supported
edits local and independent. Defer unrelated ancestor edits; include a coordinated
change when necessary to express a supported correction with valid syntax.

Before returning, check trigger, response, guards, timing, relevant history,
reductions, predicate polarity and required X/Z handling. Preserve all behavior
required by this task. If no change is justified, do not make a cosmetic rewrite
merely to produce a different assertion.

Return only one complete assertion in the requested SystemVerilog code format.
Do not output a reasoning report, node IDs, a patch, a module or error messages.
""" + "\n" + TESTBENCH_GUIDANCE + "\n" + GUIDANCE_STATUS


def build_generation_prompt(requirement, testbench, *, assertion_history=None,
                            diagnosis_response=None, diagnosis_round=None,
                            assertion_template="asrt: assert property (@(posedge clk) BODY);"):
    """Accept only training-generation inputs; no reference, scores or tool logs.

    History must already be reduced by training_prompt_context.assertion_history.
    Re-project it here so extra record metadata cannot leak into the prompt.
    """
    if not isinstance(requirement, str) or not requirement.strip():
        raise ValueError("A nonempty requirement is required.")
    if not isinstance(testbench, str) or not testbench.strip():
        raise ValueError("A nonempty complete testbench or module context is required.")
    history = []
    seen = set()
    for entry in assertion_history or []:
        number, source = entry.get("round"), entry.get("generated_assertion")
        if type(number) is not int or number < 1 or number in seen:
            raise ValueError("History rounds must be unique positive integers.")
        if not isinstance(source, str) or not source.strip():
            raise ValueError("History assertions must be nonempty source text.")
        seen.add(number)
        # Unknown/free-form feedback is deliberately not forwarded.
        outcome = entry.get("evaluation")
        if not isinstance(outcome, str) or outcome not in {NOT_EQUIVALENT, EQUIVALENT, NO_VERDICT}:
            outcome = NO_VERDICT
        history.append({"round": number, "generated_assertion": source, "evaluation": outcome})
    history.sort(key=lambda entry: entry["round"])
    sections = ["CURRENT REQUIREMENT\n" + requirement,
                "COMPLETE TESTBENCH OR MODULE CONTEXT\n" + testbench]
    if history:
        sections.append("PREVIOUS GENERATED ASSERTIONS\n" + json.dumps(history, indent=2, ensure_ascii=False))
    elif diagnosis_response is not None:
        raise ValueError("Correction guidance requires an earlier generated assertion.")
    if diagnosis_response is not None:
        latest = history[-1]
        if type(diagnosis_round) is not int or diagnosis_round != latest["round"]:
            raise ValueError("Latest corrections must identify the latest assertion's round.")
        located = feedback_json(diagnosis_response, assertion=latest["generated_assertion"])
        sections.append(
            f"LATEST CORRECTION GUIDANCE — FOR ROUND {diagnosis_round}\n" + located
            + "\nThese are proposed local corrections to that assertion, not instructions "
            "to apply earlier rounds' rules. Validate each premise and preserve unrelated "
            "required behavior. Use the path and expression together to locate the occurrence."
        )
    elif history:
        sections.append(
            "LATEST CORRECTION GUIDANCE\nNo correction guidance was produced for the latest "
            "assertion. Review the task and earlier attempts; do not invent a diagnosis "
            "or treat the absence of guidance as acceptance."
        )
    if "CLOCK_SIGNAL" in assertion_template:
        clock_instruction = (
            "Replace EDGE and CLOCK_SIGNAL with the required edge and actual declared clock. "
            "Include reset disabling only when required by the task."
        )
    else:
        clock_instruction = (
            "Use the clock and any reset-disable clause shown in this statement format. "
            "Replace BODY with the required property."
        )
    sections.append(
        "OUTPUT FORMAT\n" + assertion_template + "\n" + clock_instruction
        + "\nPut any label before assert property. Preserve parentheses and valid property "
        "operator grammar. Return exactly one complete assertion enclosed in "
        "```systemverilog and ```. Output no other text."
    )
    return "\n\n".join(sections)
