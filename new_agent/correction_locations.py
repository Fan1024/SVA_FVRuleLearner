"""Resolve diagnosis IDs to textual occurrence locations; never edit an AST."""
import json
from new_agent.diagnosis_context import diagnosis_payload

from new_agent import assertion_tree


def _expression(node):
    text = node.get('expression')
    if isinstance(text, str) and text:
        return text
    if node.get('kind') == 'unparsed_assertion':
        return node.get('value', '')

    def restore(item):
        return assertion_tree.Node(
            item['kind'], item.get('value', ''), item.get('category', ''),
            [restore(child) for child in item.get('children', [])],
            item.get('attributes', {}))
    return assertion_tree.render(restore(node))


def _step(parent, child, index):
    role = child.get('operand_role', '')
    operation = parent.get('value', '')
    label = {
        'left': 'left operand', 'right': 'right operand',
        'antecedent': 'antecedent', 'consequent': 'consequent',
        'condition': 'condition', 'if_true': 'true branch', 'if_false': 'false branch',
        'operand': 'operand', 'base': 'selected expression',
        'before_delay': 'sequence before the delay', 'after_delay': 'sequence after the delay',
        'delayed_sequence': 'delayed sequence', 'repeat_count': 'replication count',
        'members': 'replicated members',
    }.get(role)
    if label is None and role.startswith(('argument_', 'member_', 'index_')):
        kind, number = role.rsplit('_', 1)
        if number.isdigit():
            label = f'{kind} {int(number) + 1}'
    if label is None:
        label = f'child {index + 1}'
    return f'{label} of `{operation}`'


def location_for(tree, node_id):
    """Identify an occurrence by its full role path and rendered expression.

    The path distinguishes even two identical subtrees. Expressions are location
    hints, not replacement code; the original assertion remains the edit source.
    """
    roots = [('property body', tree['root'])]
    for name, context in tree.get('context', {}).items():
        label = {'clock': 'clock event', 'disable_iff': 'disable iff condition'}.get(name, name)
        roots.append((label, context['root']))

    def find(node, path):
        if node.get('id') == node_id:
            return ' / '.join(path) + ': `' + _expression(node) + '`'
        for index, child in enumerate(node.get('children', [])):
            result = find(child, path + [_step(node, child, index)])
            if result is not None:
                return result
        return None

    for label, root in roots:
        result = find(root, [label])
        if result is not None:
            return result
    raise ValueError(f'Cannot resolve correction location: {node_id}')


def recover_location(assertion, node_id, tree=None):
    """Recover legacy source locations before dropping historical node metadata."""
    if not isinstance(node_id, str) or not isinstance(assertion, str):
        return None
    try:
        if not isinstance(tree, dict) or not isinstance(tree.get('root'), dict):
            try:
                tree = assertion_tree.build_tree(assertion, 'G')
            except assertion_tree.ParseError:
                tree = {'root': {'id': 'G_unparsed', 'kind': 'unparsed_assertion',
                                 'value': assertion, 'children': []}, 'context': {}}
        return location_for(tree, node_id)
    except (ValueError, KeyError, TypeError):
        return None


def feedback_json(diagnosis, *, assertion=None, tree=None):
    """Forward interpretation, category, textual location and correction action."""
    data = json.loads(diagnosis) if isinstance(diagnosis, str) else diagnosis
    if not isinstance(data, dict) or not isinstance(data.get('corrections'), list):
        raise ValueError('Expected a corrections array for located feedback')
    corrections = []
    for item in data['corrections']:
        if not isinstance(item, dict):
            raise ValueError('Expected a correction object')
        location = item.get('location')
        node_id = item.get('generated_node_id')
        if node_id is not None and tree is not None:
            location = location_for(tree, node_id)
        elif not isinstance(location, str) or not location.strip():
            location = recover_location(assertion, node_id)
        if not isinstance(location, str) or not location.strip():
            raise ValueError('Correction needs a resolvable textual location')
        rule = item.get('rule')
        if not isinstance(rule, str) or not rule.strip():
            raise ValueError('Correction needs a nonempty rule')
        correction = {'location': location}
        if isinstance(item.get('diagnosis'), str):
            correction['diagnosis'] = item['diagnosis']
        for field in ('difference', 'why_it_matters'):
            if isinstance(item.get(field), str) and item[field].strip():
                correction[field] = item[field].strip()
        if 'diagnosis_ids' in item:
            correction['diagnosis_ids'] = list(item['diagnosis_ids'])
        correction['rule'] = rule.strip()
        corrections.append(correction)
    return json.dumps({**diagnosis_payload(data), 'corrections': corrections}, ensure_ascii=False)


