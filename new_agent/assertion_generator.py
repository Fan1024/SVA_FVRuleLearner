import re

from openai import OpenAI


SYSTEM_PROMPT = """You write SystemVerilog assertions from natural-language requirements.
Use the provided testbench as the context for your translation.
"""


def build_generation_prompt(requirement: str, testbench: str) -> str:
    """Combine the testbench, requirement, and output instructions."""
    return f"""Here is the testbench to perform your translation:

{testbench}

Question: Create a SVA assertion checks {requirement}

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

