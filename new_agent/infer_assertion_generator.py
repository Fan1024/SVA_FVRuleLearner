"""Requirement-based inference using selected existing training guidance."""
import json
from new_agent.generation_context import SYSTEM_PROMPT, outcome, output_instruction

PROMPT_VERSION='selected_whole_assertion_guidance_v8'
REVISION_PROCEDURE=''


def build_generation_prompt(requirement, testbench=None, *, examples=None,
                            previous_assertion=None, previous_round=None,
                            selector_guidance=None, previous_evaluation=None,
                            assertion_template=None):
    if not isinstance(requirement,str) or not requirement.strip():
        raise ValueError('A nonempty requirement is required.')
    sections=['Question: Create a SVA assertion that checks:\n'+requirement]
    pairs=[{key: entry[key] for key in ('requirement','solved_assertion')} for entry in examples or []]
    if pairs:
        sections.append('SVA EXAMPLES\n'+json.dumps(pairs,ensure_ascii=False,indent=2))
    if previous_assertion is not None:
        if type(previous_round) is not int or previous_round<1:
            raise ValueError('A previous assertion requires its positive round.')
        sections.append('PREVIOUS ASSERTION\n'+previous_assertion)
        sections.append('PREVIOUS OUTCOME\n'+outcome(previous_evaluation))
        if selector_guidance is not None:
            from new_agent.infer_rule_selector import generator_view
            sections.append('SELECTED TRAINING GUIDANCE\n'+json.dumps(
                generator_view(selector_guidance,previous_assertion,previous_round),ensure_ascii=False,indent=2))
    elif selector_guidance is not None:
        raise ValueError('Selected guidance requires a previous assertion.')
    sections.append(output_instruction())
    return '\n\n'.join(sections)
