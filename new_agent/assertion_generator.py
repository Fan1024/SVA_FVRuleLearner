import re

from openai import OpenAI


SYSTEM_PROMPT = """You write SystemVerilog assertions from natural-language requirements.
Use the provided testbench as the context for your translation.
"""


def build_generation_prompt(
    requirement: str,
    testbench: str,
    previous_assertion: str | None = None,
    rules: list[dict] | None = None,
) -> str:
    """Build a fresh initial or revision prompt; never accept a reference."""
    revision = ""
    if previous_assertion is not None:
        if not previous_assertion.strip() or not rules:
            raise ValueError("A revision requires a previous assertion and rules.")
        guidance = []
        for number, entry in enumerate(rules, 1):
            rule = entry.get("rule")
            if not isinstance(rule, str) or not rule.strip():
                raise ValueError("Every selected rule must contain nonempty rule text.")
            guidance.append(f"{number}. {rule.strip()}")
        revision = (
            "\nRevise the previous assertion using the correction guidance below.\n"
            "Apply each rule only when its behavioral condition fits the requirement.\n"
            "Preserve correct behavior while correcting the identified issues.\n"
            "\nPREVIOUS ASSERTION\n" + previous_assertion
            + "\n\nCORRECTION GUIDANCE\n" + "\n".join(guidance) + "\n"
        )
    elif rules:
        raise ValueError("Rules require a previous assertion for this experiment.")

    return f"""Here is the testbench to perform your translation:

{testbench}

Question: Create a SVA assertion checks {requirement}
{revision}
Generate exactly one assertion, labeled asrt.
Do not add code to output an error message string.
Enclose your SVA code with ```systemverilog and ```.
Only output the code snippet and do NOT output anything else.

Answer:"""


def generate_assertion(client: OpenAI, model: str, user_prompt: str) -> str:
    """Send one generation request and return the response text unchanged."""
    response = client.responses.create(
        model=model,
        instructions=SYSTEM_PROMPT,
        input=user_prompt,
    )

    if response.status != "completed":
        raise RuntimeError(f"Generation did not complete: {response.status}")

    if not response.output_text.strip():
        raise RuntimeError("The model returned no assertion text.")

    return response.output_text


def extract_assertion(response_text: str) -> str:
    """Extract the SVA from one systemverilog Markdown code block."""
    match = re.fullmatch(
        r"\s*```systemverilog\s*(.*?)\s*```\s*",
        response_text,
        flags=re.DOTALL,
    )
    if match is None:
        raise ValueError("Expected one systemverilog Markdown code block.")

    assertion = match.group(1).strip()
    if not assertion or "```" in assertion:
        raise ValueError("Expected one nonempty assertion code block.")

    return assertion


