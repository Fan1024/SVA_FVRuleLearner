"""Select masked diagnoses and corrections from all recorded training rounds."""
from copy import deepcopy
import json
from new_agent import config
from new_agent.diagnosis_context import diagnosis_view
from new_agent.generation_context import model_testbench
from new_agent.tool_feedback import compact_tool_feedback

MAX_SELECTED_RULES=5  # Compatibility name; configured limits are read per request.


def limits():
    return {'diagnoses':getattr(config,'TOP_K_DIAGNOSES',5),
            'rules':getattr(config,'TOP_K_RULES',5)}


def compact_tree(tree, *, include_source=True):
    def walk(node):
        result={key:node[key] for key in ('id','kind','value')}
        for key in ('attributes','operand_role'):
            if node.get(key): result[key]=node[key]
        result['children']=[walk(child) for child in node.get('children',[])]
        return result
    result={'root':walk(tree['root'])}
    if include_source: result['source_assertion']=tree['source_assertion']
    if tree.get('context'):
        result['context']={key:{'root':walk(value['root'])} for key,value in tree['context'].items()}
    if tree.get('parse_error'): result['parse_error']='Tree unavailable; use the source assertion.'
    return result


def compact_rule_bank(candidates):
    """Keep every round's guidance, locations and recorded revision examples."""
    diagnoses, rules, examples = [], [], []
    seen_diagnoses, seen_rules = set(), {}

    def add_diagnosis(value):
        item = diagnosis_view(value)
        category = item.get('category', '').strip()
        statement = item.get('statement', '').strip()
        key = (category, statement)
        if category and statement and key not in seen_diagnoses:
            seen_diagnoses.add(key)
            diagnoses.append({'category': category, 'statement': statement})

    def add_rule(value):
        text = value.get('rule', '').strip()
        location = value.get('location', '').strip()
        if not text:
            return None
        key = (text, location, value.get('before_assertion'), value.get('after_assertion'))
        if key not in seen_rules:
            seen_rules[key] = value['id']
            rules.append({'id': value['id'], 'rule': text, 'location': location})
        for item in value.get('diagnoses', []):
            add_diagnosis(item)
        return seen_rules[key]

    for case in candidates:
        trace = case.get('revision_trace', [])
        for item in case.get('diagnoses', []):
            add_diagnosis(item)
        for before in trace:
            for item in before.get('diagnoses', []):
                add_diagnosis(item)
            after = next((entry for entry in trace if entry.get('assertion')
                          and entry.get('diagnosis_from_round') == before['round']), {})
            status = (after.get('evaluation') or {}).get('status') or 'UNAVAILABLE'
            rule_ids = []
            for correction in before.get('corrections', []):
                rule_id = add_rule({**correction,
                    'before_assertion': before.get('assertion'),
                    'after_assertion': after.get('assertion')})
                if rule_id and rule_id not in rule_ids:
                    rule_ids.append(rule_id)
            if rule_ids and before.get('assertion'):
                example = next((entry for entry in examples
                    if entry['before_assertion'] == before['assertion']
                    and entry['after_assertion'] == after.get('assertion')
                    and entry['after_status'] == status), None)
                if example is None:
                    example = {'rule_ids': [], 'before_assertion': before['assertion'],
                               'after_assertion': after.get('assertion'), 'after_status': status}
                    examples.append(example)
                example['rule_ids'].extend(rule_id for rule_id in rule_ids
                                           if rule_id not in example['rule_ids'])
        if not any(entry.get('corrections') for entry in trace):
            for rule in case.get('rules', []):
                add_rule(rule)
    return {'diagnoses': diagnoses, 'rules': rules, 'correction_examples': examples}


def bank_rule_ids(bank):
    return {item['id'] for item in bank['rules']}


def _rule_map(bank):
    return {item['id']:item for item in bank['rules']}


def required_counts(rule_bank):
    """Select the configured count, using the entire pool when it is smaller."""
    available = {'diagnoses': len({_diagnosis_key(item) for item in rule_bank.get('diagnoses', [])}),
                 'rules': len(bank_rule_ids(rule_bank))}
    return {name: min(limits()[name], count) for name, count in available.items()}


def build_selector_prompt(requirement, testbench, tree, rule_bank, *, evaluation_status=None, previous_transition=None):
    from new_agent.infer_rule_selector_prompts import TASK_INSTRUCTIONS
    if not isinstance(testbench, str) or not testbench.strip():
        raise ValueError('A nonempty target testbench or module context is required.')
    counts = required_counts(rule_bank)
    bank = {
        'diagnoses': [{'position': position, **diagnosis_view(item)}
                      for position, item in enumerate(rule_bank['diagnoses'], 1)],
        'rules': [{key: item[key] for key in ('id', 'rule', 'location')}
                  for item in rule_bank['rules']],
        'correction_examples': [{key: item[key] for key in
            ('rule_ids', 'before_assertion', 'after_assertion', 'after_status')}
            for item in rule_bank['correction_examples']],
    }
    data = {'requirement': requirement, 'testbench': model_testbench(testbench), 'guidance_pool': bank}
    if tree is not None:
        data['generated_assertion'] = tree['source_assertion']
    if evaluation_status is not None:
        data['tool_feedback'] = compact_tool_feedback(evaluation_status)
    if previous_transition is not None:
        previous_guidance = previous_transition.get('previous_guidance') or {}
        data['previous_revision'] = {
            'before_assertion': previous_transition.get('before_assertion'),
            'after_assertion': previous_transition.get('after_assertion'),
            'previous_selection': {
                'selected_diagnoses': [diagnosis_view(item)
                    for item in previous_guidance.get('selected_diagnoses', [])],
                'selected_rules': [{'rule_id': item['rule_id']}
                    for item in previous_guidance.get('selected_rules', [])],
            },
            'outcome': previous_transition.get('outcome'),
        }
    instructions = TASK_INSTRUCTIONS.replace('{diagnosis_count}', str(counts['diagnoses']))
    instructions = instructions.replace('{rule_count}', str(counts['rules']))
    return instructions + '\nINPUT DATA\n' + json.dumps(data, ensure_ascii=False, indent=2)


def _diagnosis_key(item):
    category, statement = item.get('category'), item.get('statement')
    if not isinstance(category, str) or not category.strip() or not isinstance(statement, str):
        raise ValueError('Select an existing diagnosis category and statement.')
    return category.strip(), statement.strip()


def parse_response(raw, tree, rule_bank):
    data = json.loads(raw) if isinstance(raw, str) else raw
    if not isinstance(data, dict) or set(data) != {'selected_diagnoses', 'selected_rules'}:
        raise ValueError('Expected selected_diagnoses and selected_rules only.')
    required = required_counts(rule_bank)
    diagnoses = data['selected_diagnoses']
    if not isinstance(diagnoses, list) or len(diagnoses) != required['diagnoses']:
        raise ValueError(f"Select {required['diagnoses']} existing diagnoses.")
    available = {_diagnosis_key(item) for item in rule_bank['diagnoses']}
    seen, selected_diagnoses = set(), []
    for item in diagnoses:
        if type(item) is int:
            if not 1 <= item <= len(rule_bank['diagnoses']):
                raise ValueError(f'Diagnosis pool position {item} is outside the supplied pool.')
            item = rule_bank['diagnoses'][item - 1]
        if not isinstance(item, dict) or set(item) != {'category', 'statement'}:
            raise ValueError('Select diagnoses using their integer pool positions.')
        key = _diagnosis_key(item)
        if key not in available:
            raise ValueError('Diagnosis text differs from the pool; select its integer position.')
        if key in seen:
            raise ValueError('Select distinct diagnosis pool positions.')
        seen.add(key)
        selected_diagnoses.append({'category': key[0], 'statement': key[1]})
    selected = data['selected_rules']
    if not isinstance(selected, list) or len(selected) != required['rules']:
        raise ValueError(f"Select {required['rules']} existing rules.")
    seen, selected_rules, available = set(), [], bank_rule_ids(rule_bank)
    for item in selected:
        if not isinstance(item, dict) or set(item) != {'rule_id'}:
            raise ValueError('A selected correction contains its existing rule_id.')
        key = item['rule_id']
        if not isinstance(key, str) or key not in available or key in seen:
            raise ValueError('Select distinct existing correction IDs.')
        seen.add(key)
        selected_rules.append({'rule_id': key})
    return {'selected_diagnoses': selected_diagnoses, 'selected_rules': selected_rules}


def make_generator_guidance(selection, rule_bank, tree, *, source_round):
    selection = parse_response(selection, tree, rule_bank)
    rules = _rule_map(rule_bank)
    selected_ids = {item['rule_id'] for item in selection['selected_rules']}
    return {'for_round': source_round,
            'selected_diagnoses': deepcopy(selection['selected_diagnoses']),
            'selected_rules': [{**item, 'rule': rules[item['rule_id']]['rule'],
                                'location': rules[item['rule_id']]['location']}
                               for item in selection['selected_rules']],
            'correction_examples': [{
                'rule_ids': [rule_id for rule_id in example['rule_ids'] if rule_id in selected_ids],
                'before_assertion': example['before_assertion'],
                'after_assertion': example['after_assertion'],
                'after_status': example['after_status'],
            } for example in rule_bank['correction_examples']
              if any(rule_id in selected_ids for rule_id in example['rule_ids'])]}


def generator_view(guidance, assertion, source_round):
    if guidance.get('for_round') != source_round:
        raise ValueError('Selected guidance belongs to another round.')
    result = {key: guidance.get(key, []) for key in
              ('selected_diagnoses', 'selected_rules', 'correction_examples')}
    if any(not isinstance(items, list) for items in result.values()):
        raise ValueError('Guidance uses diagnosis, rule and correction-example arrays.')
    return {
        'selected_diagnoses': [diagnosis_view(item) for item in result['selected_diagnoses']],
        'selected_rules': [{key: item[key] for key in ('rule_id', 'rule', 'location')}
                           for item in result['selected_rules']],
        'correction_examples': [{key: item[key] for key in
            ('rule_ids', 'before_assertion', 'after_assertion', 'after_status')}
            for item in result['correction_examples']],
    }


from new_agent.infer_rule_selector_prompts import SYSTEM_PROMPT

