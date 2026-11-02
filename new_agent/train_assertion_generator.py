"""Requirement-based generation with the latest training correction guidance."""
import json
from new_agent.correction_locations import feedback_json
from new_agent.generation_context import SYSTEM_PROMPT, outcome, output_instruction


def build_generation_prompt(requirement, testbench=None, *, assertion_history=None,
                            diagnosis_response=None, diagnosis_round=None,
                            assertion_template=None):
    # Retain call compatibility; testbench and assertion_template are not serialized.
    if not isinstance(requirement,str) or not requirement.strip():
        raise ValueError('A nonempty requirement is required.')
    history = sorted(assertion_history or [], key=lambda entry: entry['round'])
    sections=['Question: Create a SVA assertion that checks:\n'+requirement]
    if history:
        latest=history[-1]
        sections.append('PREVIOUS ASSERTION\n'+latest['generated_assertion'])
        sections.append('PREVIOUS OUTCOME\n'+outcome(latest.get('evaluation')))
        if diagnosis_response is not None:
            if diagnosis_round != latest['round']:
                raise ValueError('Training guidance must belong to the latest assertion round.')
            sections.append('CORRECTION GUIDANCE\n'+feedback_json(
                diagnosis_response,assertion=latest['generated_assertion']))
    elif diagnosis_response is not None:
        raise ValueError('Correction guidance requires a previous assertion.')
    sections.append(output_instruction())
    return '\n\n'.join(sections)
