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


SYSTEM_PROMPT = '''Create a SystemVerilog assertion that checks the behavior described in the
natural-language requirement. Choose the sequential or combinational form that
fits the requested behavior. Use any supplied examples to understand assertion
structure and any supplied guidance to revise the previous assertion. Apply or
adapt useful suggestions according to the current requirement; source examples
can have different signal roles, conditions and timing. A source location
identifies an occurrence in its example, not an edit boundary in the current task.
Do not add unrelated obligations or copy source-specific conditions blindly.
Return only one complete assertion in a systemverilog code block.
'''


def output_instruction():
    return 'Enclose the complete SVA statement in ```systemverilog and ```. Output no other text.'
