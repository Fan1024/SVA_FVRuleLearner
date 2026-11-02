"""Fixed-example generation-only baseline, without an extra diagnosis component."""
from new_agent.infer_assertion_generator import SYSTEM_PROMPT, build_generation_prompt as _build


def build_generation_prompt(requirement,testbench=None,*,examples,previous_assertion=None,
                            previous_round=None,diagnosis_guidance=None,previous_evaluation=None,
                            assertion_template=None):
    if len(examples)!=3:
        raise ValueError('Exactly three fixed examples are required.')
    return _build(requirement,testbench,examples=examples,previous_assertion=previous_assertion,
                  previous_round=previous_round,previous_evaluation=previous_evaluation)
