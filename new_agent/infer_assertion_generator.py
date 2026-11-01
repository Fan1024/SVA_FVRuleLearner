"""Inference generation with active high-level-to-specific revision diagnosis."""
import json
from new_agent.diagnosis_context import DIAGNOSIS_CATEGORIES
from new_agent.training_prompt_context import EQUIVALENT, NO_VERDICT, NOT_EQUIVALENT, SYNTAX_FAILURE

PROMPT_VERSION = 'inference_active_diagnosis_v5'
SYSTEM_PROMPT = """Generate one complete SystemVerilog assertion for the current requirement
using the supplied testbench. Establish scope, activation, response, timing and
relevant context from the task and actual declarations/helper updates. Do not
add obligations merely because other behavior exists in the TB.

When revising, actively diagnose the last-round assertion yourself, from high
level to specific, before consulting the selector's suggestions:
1. Interpret each relevant requirement component into a construction constraint:
   which scenarios are covered, when the check activates, what response is required,
   its timing, and what declared helpers/history mean in the TB.
2. Determine what the previous assertion actually requires and permits. Compare
   its complete behavior with those constraints. Identify supported high-level
   mismatches using these category examples; do not force a finding in every category:
""" + '\n'.join('- ' + category for category in DIAGNOSIS_CATEGORIES) + """
3. Trace each mismatch to the specific clause, activation guard, response
   relationship, temporal construct, operator, signal use or boundary causing it.
   Determine the concrete edit and its required behavioral effect. For example,
   an immediate-response requirement checked one cycle later has a Timing mismatch;
   if |=> introduces that delay, change that occurrence to |->. A scope mismatch
   may instead need a containing-expression rewrite, not a single-operator edit.
4. Then consider the selector's interpretation, current diagnoses/locations and
   ranked source rules as fallible examples. Compare their premises with your own
   findings. Learn from, adapt or disregard them; applying any retrieved rule is
   optional. You may identify unreported issues, revise outside suggested locations,
   or derive a correction directly from the requirement/TB when no example applies.
5. Implement the supported corrections and recheck the complete assertion against
   all relevant requirement components, including interactions between edits.

Source diagnoses/locations concern training assertions, not the current target.
No retrieved rule is assigned to a current location. The selector's assessment is
not authoritative or exhaustive. Empty guidance still requires active diagnosis.
An unavailable verdict is not evidence of a semantic mismatch; do not guess the
hidden reference. Follow the supplied clock/reset convention and valid SVA grammar.
Perform the review while constructing the revision; return only one complete
assertion in a systemverilog code block, without a separate diagnosis report.
"""
# Kept for callers importing this name; the procedure is stated once in SYSTEM_PROMPT.
REVISION_PROCEDURE = ''


def build_generation_prompt(requirement, testbench, *, examples=None,
                            previous_assertion=None, previous_round=None,
                            selector_guidance=None, previous_evaluation=None,
                            assertion_template='assert property (@(posedge clk) BODY);'):
    if not isinstance(requirement, str) or not requirement.strip():
        raise ValueError('A nonempty requirement is required.')
    if not isinstance(testbench, str) or not testbench.strip():
        raise ValueError('A complete testbench/module context is required.')
    sections = ['CURRENT REQUIREMENT\n' + requirement, 'COMPLETE TESTBENCH OR MODULE CONTEXT\n' + testbench]
    if previous_assertion is not None:
        if not isinstance(previous_assertion, str) or not previous_assertion.strip():
            raise ValueError('Previous assertion must be nonempty.')
        if type(previous_round) is not int or previous_round < 1:
            raise ValueError('Previous assertion requires its positive round.')
        sections.append(f'LATEST GENERATED ASSERTION — ROUND {previous_round}\n' + previous_assertion)
        if isinstance(previous_evaluation, str) and previous_evaluation in {EQUIVALENT, NO_VERDICT, NOT_EQUIVALENT, SYNTAX_FAILURE}:
            sections.append('PREVIOUS EVALUATION\n' + previous_evaluation)
        if selector_guidance is not None:
            from new_agent.infer_rule_selector import generator_view
            sections.append('OPTIONAL SELECTOR EXAMPLES AND SUGGESTIONS\n' + json.dumps(
                generator_view(selector_guidance, previous_assertion, previous_round), ensure_ascii=False, indent=2))
        else:
            sections.append('SELECTOR GUIDANCE\nUnavailable; independently reassess the task and previous assertion.')
    elif selector_guidance is not None or previous_round is not None:
        raise ValueError('Selector guidance requires a previous assertion and round.')
    pairs = []
    for example in examples or []:
        task, source = example.get('requirement'), example.get('solved_assertion')
        if not isinstance(task, str) or not task.strip() or not isinstance(source, str) or not source.strip():
            raise ValueError('Examples require requirement and accepted generated solved_assertion.')
        pairs.append({'requirement': task, 'solved_assertion': source})
    if pairs:
        sections.append('OPTIONAL ACCEPTED GENERATED TRAINING EXAMPLES\n' + json.dumps(pairs, ensure_ascii=False, indent=2))
    sections.append('OUTPUT FORMAT\n' + assertion_template + '\nReplace BODY; follow the shown clock/reset convention. '
                    'For EDGE/CLOCK_SIGNAL placeholders use the required edge and actual declared clock. '
                    'Return exactly one complete assertion in ```systemverilog and ```; no other text.')
    return '\n\n'.join(sections)
