"""No-reference diagnosis payloads and source locations; no retrieval or scoring."""
from copy import deepcopy
import hashlib
import json

from new_agent.correction_locations import location_for
from new_agent.diagnosis_context import category_label
from new_agent.inference_only_diagnosis_prompts import SYSTEM_PROMPT, TASK_INSTRUCTIONS
from new_agent.training_prompt_context import evaluation_feedback


def compact_tree(tree):
    def node_view(node):
        result = {key: node[key] for key in ('id', 'kind', 'value')}
        for key in ('attributes', 'operand_role'):
            if node.get(key):
                result[key] = node[key]
        result['children'] = [node_view(child) for child in node.get('children', [])]
        return result
    result = {'source_assertion': tree['source_assertion'], 'root': node_view(tree['root'])}
    if tree.get('context'):
        result['context'] = {key: {'root': node_view(item['root'])}
                             for key, item in tree['context'].items()}
    if tree.get('parse_error'):
        result['parse_error'] = 'Tree unavailable; use the opaque source anchor.'
    return result


def build_diagnosis_prompt(requirement, testbench, generated_assertion, *, tree,
                           evaluation_status, previous_transition=None):
    """No reference, raw result, log, metric or retrieval input can enter here."""
    if tree.get('source_assertion') != generated_assertion:
        raise ValueError('The generated tree belongs to another assertion.')
    data = {
        'requirement': requirement,
        'testbench_with_line_numbers': '\n'.join(
            f'{number}: {line}' for number, line in enumerate(testbench.splitlines(), 1)),
        'generated_tree': compact_tree(tree),
        'evaluation_feedback': evaluation_feedback(evaluation_status),
    }
    if previous_transition is not None:
        data['last_revision'] = previous_transition
    return TASK_INSTRUCTIONS + '\nINPUT DATA\n' + json.dumps(data, ensure_ascii=False, indent=2)


def _text(value, name):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(name + ' must be nonempty text.')
    return value.strip()


def parse_response(raw, tree, testbench):
    """Basic JSON/source-link checks only; no semantic diagnosis filtering."""
    data = json.loads(raw) if isinstance(raw, str) else raw
    if not isinstance(data, dict) or not isinstance(data.get('requirement_parts'), list) or not data['requirement_parts']:
        raise ValueError('Expected a nonempty requirement_parts array.')
    if not isinstance(data.get('corrections'), list):
        raise ValueError('Expected a corrections array.')
    lines = testbench.splitlines()
    parts, part_ids = [], set()
    for part in data['requirement_parts']:
        if not isinstance(part, dict):
            raise ValueError('Each requirement part must be an object.')
        part_id = _text(part.get('id'), 'part ID')
        if part_id in part_ids:
            raise ValueError('Requirement part IDs must be unique.')
        part_ids.add(part_id)
        sections = part.get('tb_sections')
        if not isinstance(sections, list):
            raise ValueError('tb_sections must be an array.')
        linked = []
        for section in sections:
            if not isinstance(section, dict):
                raise ValueError('Each TB section must be an object.')
            start, end = section.get('start_line'), section.get('end_line')
            if type(start) is not int or type(end) is not int or not 1 <= start <= end <= len(lines):
                raise ValueError('TB section lines must be within the supplied source.')
            linked.append({'start_line': start, 'end_line': end,
                           'source': '\n'.join(lines[start-1:end]),
                           'interpretation': _text(section.get('interpretation'), 'TB interpretation')})
        parts.append({'id': part_id,
                      'requirement_text': _text(part.get('requirement_text'), 'requirement_text'),
                      'tb_sections': linked,
                      'expected_behavior': _text(part.get('expected_behavior'), 'expected_behavior')})
    corrections = []
    for correction in data['corrections']:
        if not isinstance(correction, dict):
            raise ValueError('Each correction must be an object.')
        linked_ids = correction.get('requirement_part_ids')
        if not isinstance(linked_ids, list) or not linked_ids or any(
                not isinstance(key, str) or key not in part_ids for key in linked_ids):
            raise ValueError('Corrections must link to existing requirement parts.')
        node_id = _text(correction.get('generated_node_id'), 'generated_node_id')
        corrections.append({
            'diagnosis': category_label(correction.get('diagnosis')),
            'requirement_part_ids': list(dict.fromkeys(linked_ids)),
            'generated_node_id': node_id, 'location': location_for(tree, node_id),
            'issue': _text(correction.get('issue'), 'issue'),
            'rule': _text(correction.get('rule'), 'rule'),
        })
    return {'requirement_parts': parts, 'corrections': corrections}


def make_generator_guidance(diagnosis, assertion, *, source_round):
    """Keep explicit requirement/TB links, but replace node IDs with locations."""
    return {'for_round': source_round,
            'assertion_sha256': hashlib.sha256(assertion.encode('utf-8')).hexdigest(),
            'requirement_parts': deepcopy(diagnosis['requirement_parts']),
            'corrections': [{key: deepcopy(item[key]) for key in (
                'diagnosis', 'requirement_part_ids', 'location', 'issue', 'rule')}
                for item in diagnosis['corrections']]}


def generator_view(guidance, assertion, source_round):
    if guidance.get('for_round') != source_round or guidance.get('assertion_sha256') != hashlib.sha256(assertion.encode('utf-8')).hexdigest():
        raise ValueError('Diagnosis guidance belongs to another assertion/round.')
    return deepcopy({key: guidance[key] for key in ('requirement_parts', 'corrections')})
