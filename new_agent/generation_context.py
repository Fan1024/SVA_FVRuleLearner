"""Model-visible generation outcomes without evaluation-policy or oracle text."""
def outcome(value):
    if not isinstance(value, str):
        return 'The previous attempt did not obtain a completed evaluation.'
    text = value.lower()
    if value in {'SYNTAX_ERROR','FORMAT_ERROR','INPUT_ERROR'} or 'could not compile' in text:
        return 'The previous attempt could not be compiled as a valid assertion.'
    if value in {'IMPLIES','NO_EQUIVALENCE'} or 'not functionally equivalent' in text:
        return 'The previous assertion did not pass evaluation.'
    if value == 'FULL_EQUIVALENCE' or 'reported functional equivalence' in text:
        return 'The previous assertion passed evaluation.'
    return 'The previous attempt did not obtain a completed evaluation.'


SYSTEM_PROMPT = '''Generate a SystemVerilog assertion for the natural-language requirement. Choose
the sequential or combinational form that fits the requested behavior.

Use supplied examples to understand assertion structure. When revising, use the
previous assertion, evaluation outcome and relevant correction guidance. Apply or
adapt suggestions according to the current requirement. Interpret each location
within the assertion to which its guidance belongs. Do not copy unrelated source
conditions or add obligations unsupported by the task.
'''

def output_instruction():
    return 'Enclose the complete SVA statement in ```systemverilog and ```. Output no other text.'
