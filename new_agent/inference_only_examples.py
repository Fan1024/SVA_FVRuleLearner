"""Three hand-written examples, fixed across targets; no dataset or retrieval IO."""
from new_agent.training_prompt_context import statement_template

VERSION = 'fixed_synthetic_three_v1'

# These are illustrative tasks, not selected training rows or target references.
# Edit these three definitions to change the examples used by inference_only.
FIXED_EXAMPLES = (
    {
        'id': 'same_cycle_response',
        'requirement': 'Whenever req is high, ack must be high in the same sampled cycle.',
        'ports': 'input clk, req, ack',
        'body': 'req |-> ack',
    },
    {
        'id': 'next_cycle_response',
        'requirement': 'Whenever start is high, done must be high at the next sampled cycle.',
        'ports': 'input clk, start, done',
        'body': 'start |=> done',
    },
    {
        'id': 'first_request_scope',
        'requirement': ('For the first sampled request after reset, require ack in that '
                        'same cycle. The supplied flag seen_request is cleared by reset and becomes one on the first request. '
                        'Later requests impose no ack obligation. Do not check during reset.'),
        'ports': 'input clk, tb_reset, req, ack',
        'declarations': ('logic seen_request;\n'
                         'always @(posedge clk)\n'
                         '  if (tb_reset) seen_request <= 1\'b0;\n'
                         '  else if (req) seen_request <= 1\'b1;'),
        'body': '(!tb_reset && !seen_request && req) |-> ack',
    },
)


def get_examples(dataset):
    """Use the same three tasks, with the existing dataset's statement format."""
    template = statement_template(dataset)
    # The example has a known clk. OpenCore targets still choose their own clock.
    template = template.replace('EDGE', 'posedge').replace('CLOCK_SIGNAL', 'clk')
    examples = []
    for item in FIXED_EXAMPLES:
        ports = item['ports']
        if dataset == 'nl2sva_human' and 'tb_reset' not in ports:
            ports += ', tb_reset'
        requirement = item['requirement'] + ' Sample on the rising edge of clk.'
        if dataset == 'nl2sva_human':
            requirement += ' Disable the property while tb_reset is asserted.'
        examples.append({
            'id': item['id'], 'requirement': requirement,
            'testbench': 'module example_tb(' + ports + ');\n'
                         + item.get('declarations', '') + '\nendmodule',
            'solved_assertion': template.replace('BODY', item['body']),
        })
    if len(examples) != 3:
        raise ValueError('inference_only requires exactly three fixed examples.')
    return examples

