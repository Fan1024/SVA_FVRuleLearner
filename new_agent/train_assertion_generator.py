from new_agent.formal_check import COMPARISON_SCOPE


SYSTEM_PROMPT = """You write SystemVerilog assertions from natural-language requirements.
Use the provided testbench as the context for your translation.
"""


def build_generation_prompt(
    requirement: str,
    testbench: str,
    previous_assertion: str | None = None,
    rules: list[dict] | None = None,
    *,
    comparison_scope: str = COMPARISON_SCOPE,
    revision_feedback: str | None = None,
    assertion_template: str = "asrt: assert property (@(posedge clk) BODY);",
) -> str:
    """Build a fresh initial or revision prompt; never accept a reference."""
    revision = ""
    if previous_assertion is not None:
        if not previous_assertion.strip():
            raise ValueError("A revision requires a nonempty previous assertion.")
        guidance = []
        for number, entry in enumerate(rules or [], 1):
            rule = entry.get("rule")
            if not isinstance(rule, str) or not rule.strip():
                raise ValueError("Every selected rule must contain nonempty rule text.")
            guidance.append(f"{number}. {rule.strip()}")
        guidance_text = "\n".join(guidance) or (
            "No specific correction rule is available. Re-derive the assertion "
            "from the requirement and testbench, reviewing its clock, disable "
            "condition, trigger, response, signal relationships, and timing."
        )
        revision = (
            "\nRevise the previous assertion using the correction guidance below.\n"
            "Consider every supplied rule as guidance for this revision.\n"
            "Resolve its applicability using the requirement and testbench.\n"
            "If guidance is uncertain or calls for re-analysis, re-derive the behavior.\n"
            "Preserve correct behavior while correcting the identified issues.\n"
            "Always return one complete assertion, even when guidance is empty or uncertain.\n"
            "\nPREVIOUS ASSERTION\n" + previous_assertion
            + "\n\nCORRECTION GUIDANCE\n" + guidance_text + "\n"
        )
    elif rules:
        raise ValueError("Rules require a previous assertion for this experiment.")

    scope_guidance = (
        "\nEVALUATION SCOPE\n" + comparison_scope
        + "\nChoose clock and reset conditions from the task and testbench.\n"
        if comparison_scope else ""
    )
    retry_guidance = ("\nPREVIOUS ATTEMPT FEEDBACK\n" + revision_feedback + "\n") if revision_feedback else ""
    context_name = "module interface" if "CLOCK_SIGNAL" in assertion_template else "testbench"
    return f"""Here is the {context_name} to perform your translation:

{testbench}

Question: Create a SVA assertion checks {requirement}
{scope_guidance}{revision}{retry_guidance}
Generate exactly one assertion using this statement structure:
{assertion_template}
If the testbench/task requires reset disabling, put disable iff (RESET) after
the clock event, inside the same outer parentheses.
The label is asrt: BEFORE assert property. Do not write assert property asrt.
Close the outer property parentheses before the final semicolon.
Do not add code to output an error message string.
Enclose your SVA code with ```systemverilog and ```.
Only output the code snippet and do NOT output anything else.

Answer:"""


