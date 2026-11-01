"""Training generation: latest candidate and latest interpreted corrections."""
import json
from new_agent.correction_locations import feedback_json
from new_agent.training_prompt_context import (
    EQUIVALENT, NO_VERDICT, NOT_EQUIVALENT, SYNTAX_FAILURE,
)

SYSTEM_PROMPT = """Generate one complete SystemVerilog assertion for the current requirement
using the supplied testbench. Establish the obligation's scope, activation,
response, timing and relevant context. Use actual declarations/helper updates;
do not infer extra obligations from unrelated TB logic.

During revision, compare the previous assertion with that obligation. Assess the
latest requirement interpretation, short diagnosis categories, and located
correction principles. Apply or adapt useful guidance to repair the actual
behavioral issue; a containing expression or coordinated rewrite is allowed.
A category identifies the KIND of mismatch; the interpretation and rule provide
the construction details. Guidance is fallible. Empty guidance does not replace
your own assessment or instruct you to repeat a previously unsuccessful attempt.

A source location identifies an occurrence, not an exclusive edit boundary.
Do not infer a semantic defect from an unavailable PEC verdict. Resolve any
requirement/reference conflict using the requirement/TB, not by guessing hidden
reference text. Follow the supplied clock/reset format and valid SVA grammar.
Return only one complete assertion in a systemverilog code block.
"""


def build_generation_prompt(requirement, testbench, *, assertion_history=None,
                            diagnosis_response=None, diagnosis_round=None,
                            assertion_template="asrt: assert property (@(posedge clk) BODY);"):
    if not isinstance(requirement, str) or not requirement.strip():
        raise ValueError('A nonempty requirement is required.')
    if not isinstance(testbench, str) or not testbench.strip():
        raise ValueError('A complete testbench or module context is required.')
    history = []
    seen = set()
    for entry in assertion_history or []:
        number, source = entry.get('round'), entry.get('generated_assertion')
        if type(number) is not int or number < 1 or number in seen:
            raise ValueError('History rounds must be unique positive integers.')
        if not isinstance(source, str) or not source.strip():
            raise ValueError('History assertions must be nonempty.')
        seen.add(number)
        outcome = entry.get('evaluation')
        if not isinstance(outcome, str) or outcome not in {EQUIVALENT, NO_VERDICT, NOT_EQUIVALENT, SYNTAX_FAILURE}:
            outcome = NO_VERDICT
        history.append({'round': number, 'generated_assertion': source, 'evaluation': outcome})
    history.sort(key=lambda item: item['round'])
    sections = ['CURRENT REQUIREMENT\n' + requirement, 'COMPLETE TESTBENCH OR MODULE CONTEXT\n' + testbench]
    if history:
        latest = history[-1]
        sections.append('LATEST GENERATED ASSERTION AND OUTCOME\n' + json.dumps(latest, ensure_ascii=False, indent=2))
        # Full history stays in records; only a short repetition notice enters the request.
        from new_agent.revision_context import candidate_key
        repeated = [item['round'] for item in history[:-1]
                    if candidate_key(item['generated_assertion']) == candidate_key(latest['generated_assertion'])]
        if repeated:
            sections.append('REPETITION NOTICE\nThe latest candidate also occurred in round(s) ' + str(repeated)
                            + '. Reconsider the unresolved requirement component before revising.')
    if diagnosis_response is not None:
        if not history or diagnosis_round != history[-1]['round']:
            raise ValueError('Latest guidance must belong to the latest assertion round.')
        located = feedback_json(diagnosis_response, assertion=history[-1]['generated_assertion'])
        sections.append(f'LATEST INTERPRETATION AND CORRECTIONS — ROUND {diagnosis_round}\n' + located)
    elif history:
        sections.append('LATEST GUIDANCE\nUnavailable; independently reassess the requirement and previous assertion.')
    sections.append('OUTPUT FORMAT\n' + assertion_template + '\nReplace BODY; follow the shown clock/reset convention. '
                    'For EDGE/CLOCK_SIGNAL placeholders use the required edge and actual declared clock. '
                    'Return exactly one complete assertion in ```systemverilog and ```; no other text.')
    return '\n\n'.join(sections)
