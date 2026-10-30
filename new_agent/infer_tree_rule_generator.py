"""Reference-free inference; checker feedback is limited to a coarse status."""
import json
import re
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


def compact_rule_bank(candidates):
    """One source requirement/text per occurrence; no scores or full histories."""
    requirements, requirement_ids, cases = {}, {}, []
    examples, example_ids = {}, {}
    for candidate in candidates:
        case = safe_candidate(candidate)
        requirement = case['requirement']
        if requirement not in requirement_ids:
            key = f'Q{len(requirements) + 1}'
            requirement_ids[requirement] = key
            requirements[key] = requirement
        rules, seen = [], {}
        for rule in case['rules']:
            key = re.sub(r'\s+', ' ', rule['rule']).strip()
            if key not in seen:
                item = {'id': rule['id'], 'rule': rule['rule']}
                seen[key] = item
                rules.append(item)
        rounds = case['revision_trace']
        for entry in rounds:
            following = next((r for r in rounds if r['diagnosis_from_round'] == entry['round']), None)
            for correction in entry['corrections']:
                key = re.sub(r'\s+', ' ', correction['rule']).strip()
                if key not in seen:
                    item = {'id': correction['id'], 'rule': correction['rule']}
                    seen[key] = item
                    rules.append(item)
                item = seen[key]
                before = entry.get('assertion')
                after = following.get('assertion') if following else None
                if not isinstance(before, str):
                    continue
                example = {'before': before, 'after': after if isinstance(after, str) else None}
                old = item.get('example')
                if old is None or (old['before'] == old['after'] and before != after):
                    item['example'] = example
        for item in rules:
            example = item.pop('example', None)
            if example is not None:
                key = (case['case_number'], example['before'], example['after'])
                if key not in example_ids:
                    example_id = f'E{len(examples) + 1}'
                    example_ids[key] = example_id
                    examples[example_id] = example
                item['example_id'] = example_ids[key]
        cases.append({'case_number': case['case_number'],
                      'requirement_id': requirement_ids[requirement], 'rules': rules})
    return {'requirements': requirements, 'examples': examples, 'cases': cases}


def bank_rule_ids(bank):
    return {rule['id'] for case in bank['cases'] for rule in case['rules']}


def build_rule_prompt(requirement, testbench, tree, candidates, *, comparison_scope,
                      rule_bank=None, checker_status=None):
    bank = compact_rule_bank(candidates) if rule_bank is None else rule_bank
    data = {
        'requirement': requirement, 'testbench': testbench,
        'generated_tree': compact_tree(tree), 'retrieved_rule_bank': bank,
        'comparison_scope': comparison_scope,
    }
    if checker_status is not None:
        if not isinstance(checker_status, str) or checker_status not in {
                'IMPLIES', 'NO_EQUIVALENCE', 'PEC_COMPILE_ERROR'}:
            raise ValueError('Expected a supported coarse checker status, not tool output')
        data['checker_status'] = checker_status
    return TASK_INSTRUCTIONS + '\nINPUT DATA\n' + json.dumps(data, ensure_ascii=False, indent=2)


def parse_response(raw, tree, candidates):
    """Validate corrections and exclude trace-only decisions from feedback."""
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
    # Keep the agreed correction format; source text and extra metadata stay
    # in the bank rather than being repeated as next-round feedback.
    fields = ('generated_node_id', 'source_rule_ids', 'difference', 'why_it_matters', 'rule')
    return {'corrections': [{key: item[key] for key in fields} for item in data['corrections']]}


def parse_rule_evaluations(raw, candidates, diagnosis):
    """Check complete per-rule decisions separately from actionable corrections."""
    data = json.loads(raw)
    evaluations = data.get('rule_evaluations')
    if not isinstance(evaluations, list):
        raise ValueError('Expected a rule_evaluations array with one decision per supplied rule')
    sources = candidate_rule_ids(candidates)
    selected = {rule_id for item in diagnosis['corrections']
                for rule_id in item['source_rule_ids']}
    seen, result = set(), []
    for item in evaluations:
        if not isinstance(item, dict):
            raise ValueError('Each rule evaluation must be an object')
        rule_id = item.get('rule_id')
        if not isinstance(rule_id, str) or rule_id not in sources or rule_id in seen:
            raise ValueError('Unknown or duplicate rule evaluation ID')
        if type(item.get('selected')) is not bool or item['selected'] != (rule_id in selected):
            raise ValueError(f'Rule evaluation selection disagrees with corrections: {rule_id}')
        reason = item.get('reason')
        if not isinstance(reason, str) or not reason.strip():
            raise ValueError(f'Rule evaluation requires a nonempty reason: {rule_id}')
        seen.add(rule_id)
        result.append({'rule_id': rule_id, 'selected': item['selected'], 'reason': reason.strip()})
    if seen != sources:
        raise ValueError('Missing rule evaluations: ' + ', '.join(sorted(sources - seen)))
    return result


def export_rules(data, round_number):
    return {f'rule_{i}': {'group': ['inference_tree_correction', f'round_{round_number:04d}',
                                  f'correction_{i:04d}'], 'rule': item['rule'].strip()}
            for i, item in enumerate(data['corrections'], 1)}
