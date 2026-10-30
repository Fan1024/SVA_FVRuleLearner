"""Inference payloads never accept a target reference or raw checker feedback."""
import json
from new_agent import assertion_tree
from new_agent.infer_tree_rule_prompts import SYSTEM_PROMPT, TASK_INSTRUCTIONS
from new_agent.infer_training_traces import EVALUATION_FIELDS


def compact_tree(tree, *, include_source=True):
    """One recursive representation; no repeated parent/child IDs or expressions."""
    def compact(node):
        result = {key: node[key] for key in ("id", "kind", "value")}
        for key in ("attributes", "operand_role"):
            if node.get(key):
                result[key] = node[key]
        result["children"] = [compact(child) for child in node.get("children", [])]
        return result
    result = {"root": compact(tree["root"])}
    if include_source:
        result["source_assertion"] = tree["source_assertion"]
    if tree.get("context"):
        result["context"] = {name: {"root": compact(value["root"])}
                             for name, value in tree["context"].items()}
    if "parse_error" in tree:
        result["parse_error"] = tree["parse_error"]
    return result


def build_tree(generated_assertion):
    try:
        return assertion_tree.build_tree(generated_assertion, 'G')
    except assertion_tree.ParseError as error:
        return {'source_assertion': generated_assertion, 'parse_error': str(error),
                'context': {}, 'root': {'id': 'G_unparsed', 'kind': 'unparsed_assertion',
                'value': generated_assertion, 'children': []}}


def candidate_rule_ids(candidates):
    return {r['id'] for case in candidates for r in case['rules']} | {
        correction['id'] for case in candidates
        for entry in case.get('revision_trace', [])
        for correction in entry.get('corrections', [])}


def safe_candidate(case):
    """Explicit allowlist including revision evidence, never raw saved records."""
    result = {'case_number': case['case_number'], 'requirement': case['requirement'],
              'rules': [{'id': r['id'], 'rule': r['rule']} for r in case['rules']],
              'trace_status': case.get('trace_status', 'unavailable_missing_trace'),
              'revision_trace': []}
    for entry in case.get('revision_trace', []):
        result['revision_trace'].append({
            'round': entry['round'], 'assertion': entry.get('assertion'),
            'diagnosis_from_round': entry.get('diagnosis_from_round'),
            'evaluation': {key: value for key, value in entry.get('evaluation', {}).items()
                           if key in EVALUATION_FIELDS},
            'corrections': [{key: correction[key]
                             for key in ('id', 'difference', 'why_it_matters', 'rule')
                             if key in correction}
                            for correction in entry.get('corrections', [])],
        })
    return result


def build_rule_prompt(requirement, testbench, tree, candidates, *, comparison_scope):
    safe = [safe_candidate(c) for c in candidates]
    return TASK_INSTRUCTIONS + '\nINPUT DATA\n' + json.dumps({
        'requirement': requirement, 'testbench': testbench,
        'generated_tree': compact_tree(tree), 'retrieved_cases': safe,
        'comparison_scope': comparison_scope,
    }, ensure_ascii=False, indent=2)


def parse_response(raw, tree, candidates):
    """Basic JSON/ID checks for indexing; the full response still becomes feedback."""
    data = json.loads(raw)
    if not isinstance(data, dict) or not isinstance(data.get('corrections'), list):
        raise ValueError('Expected a JSON object with a corrections array')
    ids = set()
    def walk(node):
        ids.add(node['id'])
        for child in node.get('children', []):walk(child)
    walk(tree['root'])
    for context in tree.get('context', {}).values():walk(context['root'])
    sources = candidate_rule_ids(candidates)
    for item in data['corrections']:
        if not isinstance(item, dict) or item.get('generated_node_id') not in ids:
            raise ValueError('Unknown generated node ID')
        selected = item.get('source_rule_ids')
        if not isinstance(selected, list) or any(not isinstance(x, str) or x not in sources for x in selected):
            raise ValueError('Unknown source rule ID')
        for field in ('difference', 'why_it_matters', 'rule'):
            if not isinstance(item.get(field), str) or not item[field].strip():
                raise ValueError(f'Correction requires nonempty {field}')
    return data


def export_rules(data, round_number):
    return {f'rule_{i}': {'group': ['inference_tree_correction', f'round_{round_number:04d}',
                                  f'correction_{i:04d}'], 'rule': item['rule'].strip()}
            for i, item in enumerate(data['corrections'], 1)}
