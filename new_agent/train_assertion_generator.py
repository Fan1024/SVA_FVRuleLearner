import json

from new_agent.formal_check import COMPARISON_SCOPE
from new_agent.correction_locations import feedback_json


SYSTEM_PROMPT = """You write SystemVerilog assertions from natural-language requirements.
Use the requirement and testbench or module interface as the specification.
Inspect signal definitions, widths, parameters and relationships. If the
requirement omits essential information, consider additional declared signals
supported by that context. Add signals or conditions only when they help express
the intended behavior; do not invent undeclared signals.

Before returning the assertion, check:
- Signals have the intended roles, data sources and time snapshots, with valid
  indices, widths and parameters.
- All required scenarios are covered. Where applicable, distinguish first/later
  operations, empty/nonempty states and simultaneous transactions. Preserve a
  required branch when correcting another part.
- Guards, implication timing and reductions express when the check applies,
  same-cycle/next-cycle behavior and any-bit/all-bit conditions.
- The complete predicate has the intended polarity: require valid behavior or
  reject a violation. Do not introduce an unintended negation. Choose explicit
  truth comparisons and X/Z handling only with the required meaning and scope.
Follow the supplied dataset-specific assertion template and comparison scope.
When revising, use the complete latest diagnosis response as local correction
guidance. Do not invent additional edits to ancestors deferred to a later round.
Node IDs are location labels only; never include them in the assertion.
"""


def build_generation_prompt(
    requirement: str,
    testbench: str,
    previous_assertion: str | None = None,
    *,
    comparison_scope: str = COMPARISON_SCOPE,
    revision_feedback: str | None = None,
    assertion_template: str = "asrt: assert property (@(posedge clk) BODY);",
    diagnosis_response: str | None = None,
    previous_tree: dict | None = None,
) -> str:
    """Build a fresh initial or revision prompt; never accept a reference."""
    revision = ""
    if previous_assertion is not None:
        if not previous_assertion.strip():
            raise ValueError("A revision requires a nonempty previous assertion.")
        revision = "\nPREVIOUS ASSERTION\n" + previous_assertion + "\n"
        if diagnosis_response is not None:
            diagnosis_response = feedback_json(
                diagnosis_response, assertion=previous_assertion, tree=previous_tree)
            revision += (
                "\nLATEST DIAGNOSIS RESPONSE\n" + diagnosis_response
                + "\nEND LATEST DIAGNOSIS RESPONSE\n"
                "Use each correction's Location to identify the exact expression occurrence in "
                "the previous assertion, then apply its condition-and-action Rule. "
                "The location includes the expression and its position to distinguish repeated "
                "operators or identical subexpressions. Use difference and explanation as context. "
                "These are local edits to the previous assertion. Preserve other branches, "
                "signals and timing unless a selected coordinated correction requires changing them. "
                "Do not independently correct deferred ancestors in this round. "
                "Return a complete assertion, not a patch or tree.\n"
            )
        else:
            revision += (
                "\nNo diagnosis response was produced in the preceding round. "
                "Review the requirement, testbench and any checker feedback.\n"
            )
    elif diagnosis_response is not None:
        raise ValueError("Diagnosis feedback requires a previous assertion.")

    scope_guidance = (
        "\nEVALUATION SCOPE\n" + comparison_scope
        + "\nChoose clock and reset conditions from the task and testbench.\n"
        if comparison_scope else ""
    )
    retry_guidance = ("\nPREVIOUS ATTEMPT FEEDBACK\n" + revision_feedback + "\n") if revision_feedback else ""
    context_name = "module interface" if "CLOCK_SIGNAL" in assertion_template else "testbench"
    label_guidance = (
        "Put the label shown in the template before assert property, not after it."
        if ":" in assertion_template.split("assert property", 1)[0] else
        "Start with assert property; do not add an assertion label."
    )
    return f"""Here is the {context_name} to perform your translation:

{testbench}

Question: Create a SVA assertion checks {requirement}
{scope_guidance}{revision}{retry_guidance}
Generate exactly one assertion using this statement structure:
{assertion_template}
If the testbench/task requires reset disabling, put disable iff (RESET) after
the clock event, inside the same outer parentheses.
{label_guidance}
Close the outer property parentheses before the final semicolon.
Do not add code to output an error message string.
Enclose your SVA code with ```systemverilog and ```.
Only output the code snippet and do NOT output anything else.

Answer:"""


