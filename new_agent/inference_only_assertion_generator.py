"""Fixed-example assertion generation and revision from current-case diagnosis."""
import json
from new_agent.diagnosis_context import DIAGNOSIS_CATEGORIES
from new_agent.inference_only_diagnosis import generator_view
from new_agent.training_prompt_context import (
    EQUIVALENT, NO_VERDICT, NOT_EQUIVALENT, SYNTAX_FAILURE, TESTBENCH_GUIDANCE,
)

SYSTEM_PROMPT = """Generate one complete SystemVerilog assertion for the current requirement
using its supplied testbench. Establish required scope, activation, response,
timing and context. The three fixed examples illustrate separate tasks; their
identifiers, obligations and helper meanings do not transfer automatically.

During revision, actively interpret the requirement and diagnose the previous
assertion before using the supplied current-case diagnosis. Compare its actual
behavior with each required part. Trace supported high-level mismatches to the
clause, signal use, guard, timing or relationship causing them. Category examples:
""" + '\n'.join('- ' + category for category in DIAGNOSIS_CATEGORIES) + """

Read the diagnosis's requirement parts, linked TB sections and expected behavior.
Assess its category/location/issue/rule entries against the complete task and
source. Use, adapt or reject the suggested corrections according to their
behavioral premises. Locations identify occurrences, not exclusive edit boundaries.
You may make coordinated changes or identify an issue the diagnosis missed.
Empty corrections still require your independent review. Reconsider ineffective
prior guidance instead of repeating a failed candidate or making cosmetic edits.

Do not guess a hidden reference. A missing verdict does not establish a semantic
defect. Follow the supplied clock/reset convention and valid SVA grammar. Review
the resulting assertion against all requirement parts and their interactions.
Return only one complete assertion in a systemverilog code block; no separate
diagnosis report.

""" + TESTBENCH_GUIDANCE


def build_generation_prompt(requirement, testbench, *, examples,
                            previous_assertion=None, previous_round=None,
                            diagnosis_guidance=None, previous_evaluation=None,
                            assertion_template='assert property (@(posedge clk) BODY);'):
    if not isinstance(requirement, str) or not requirement.strip() or not isinstance(testbench, str) or not testbench.strip():
        raise ValueError('A nonempty requirement and TB/module context are required.')
    if len(examples) != 3:
        raise ValueError('Exactly three fixed examples are required.')
    pairs = [{key: example[key] for key in ('requirement', 'testbench', 'solved_assertion')}
             for example in examples]
    sections = ['CURRENT REQUIREMENT\n' + requirement,
                'COMPLETE TESTBENCH OR MODULE CONTEXT\n' + testbench,
                'THREE FIXED ILLUSTRATIVE EXAMPLES\n' + json.dumps(pairs, ensure_ascii=False, indent=2)]
    if previous_assertion is not None:
        if not isinstance(previous_assertion, str) or not previous_assertion.strip() or type(previous_round) is not int or previous_round < 1:
            raise ValueError('Previous assertion requires its positive round.')
        sections.append(f'LATEST GENERATED ASSERTION — ROUND {previous_round}\n' + previous_assertion)
        if previous_evaluation in {EQUIVALENT, NO_VERDICT, NOT_EQUIVALENT, SYNTAX_FAILURE}:
            sections.append('PREVIOUS EVALUATION\n' + previous_evaluation)
        if diagnosis_guidance is not None:
            sections.append('LATEST REQUIREMENT INTERPRETATION AND LOCATED CORRECTIONS\n' + json.dumps(
                generator_view(diagnosis_guidance, previous_assertion, previous_round), ensure_ascii=False, indent=2))
        else:
            sections.append('LATEST DIAGNOSIS\nUnavailable; independently review the task and previous assertion.')
    elif diagnosis_guidance is not None or previous_round is not None:
        raise ValueError('Diagnosis guidance requires a previous assertion and round.')
    sections.append('OUTPUT FORMAT\n' + assertion_template + '\nReplace BODY; follow the shown clock/reset convention. '
                    'For EDGE/CLOCK_SIGNAL use the required edge and actual declared clock. '
                    'Return exactly one complete assertion in ```systemverilog and ```; no other text.')
    return '\n\n'.join(sections)
