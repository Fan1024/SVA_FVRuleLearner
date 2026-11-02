"""Independent selection of existing training explanations and correction rules."""
from copy import deepcopy
import hashlib
import json
from new_agent import config
from new_agent.diagnosis_context import diagnosis_view
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
    """Keep only masked diagnosis text and rules, including learned trace entries."""
    diagnoses, rules, seen_diagnoses, seen_rules = [], [], set(), set()

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
        if text and text not in seen_rules:
            seen_rules.add(text)
            rules.append({'id': value['id'], 'rule': text})
        for item in value.get('diagnoses', []):
            add_diagnosis(item)

    for case in candidates:
        for item in case.get('diagnoses', []):
            add_diagnosis(item)
        for item in case.get('rules', []):
            add_rule(item)
        for entry in case.get('revision_trace', []):
            for item in entry.get('diagnoses', []):
                add_diagnosis(item)
            for item in entry.get('corrections', []):
                add_rule(item)
    return {'diagnoses': diagnoses, 'rules': rules}


def bank_rule_ids(bank):
    return {item['id'] for item in bank['rules']}


def _rule_map(bank):
    return {item['id']:item for item in bank['rules']}


def required_counts(rule_bank):
    """Both lists are required; count existing items without judging relevance."""
    available = {'diagnoses': len({_diagnosis_key(item) for item in rule_bank.get('diagnoses', [])}),
                 'rules': len(bank_rule_ids(rule_bank))}
    missing = [name for name, count in available.items() if count == 0]
    if missing:
        raise ValueError('Retrieved training guidance has no ' + ' or '.join(missing)
                         + '; both diagnoses and rules are required before a revision.')
    return {name: min(limits()[name], count) for name, count in available.items()}


def build_selector_prompt(requirement, testbench, tree, rule_bank, *, evaluation_status, previous_transition=None):
    from new_agent.infer_rule_selector_prompts import TASK_INSTRUCTIONS
    if not isinstance(testbench, str) or not testbench.strip():
        raise ValueError('A nonempty target testbench or module context is required.')
    bank = {
        'diagnoses': [diagnosis_view(item) for item in rule_bank['diagnoses']],
        'rules': [{key: item[key] for key in ('id', 'rule')} for item in rule_bank['rules']],
    }
    data = {'requirement': requirement, 'testbench': testbench,
            'generated_assertion': tree['source_assertion'],
            'tool_feedback': compact_tool_feedback(evaluation_status),
            'training_guidance': bank, 'selection_limits': limits(),
            'required_selection_counts': required_counts(rule_bank)}
    return TASK_INSTRUCTIONS + '\nINPUT DATA\n' + json.dumps(data, ensure_ascii=False, indent=2)


def _diagnosis_key(item):
    category, statement = item.get('category'), item.get('statement')
    if not isinstance(category, str) or not category.strip() or not isinstance(statement, str):
        raise ValueError('Select an existing diagnosis category and statement.')
    return category.strip(), statement.strip()


def parse_response(raw, tree, rule_bank):
    data = json.loads(raw) if isinstance(raw, str) else raw
    if not isinstance(data, dict) or set(data) != {'ranked_diagnoses', 'ranked_rules'}:
        raise ValueError('Expected ranked_diagnoses and ranked_rules only.')
    required = required_counts(rule_bank)
    diagnoses = data['ranked_diagnoses']
    if not isinstance(diagnoses, list) or len(diagnoses) != required['diagnoses']:
        raise ValueError(f"Select exactly {required['diagnoses']} existing diagnoses.")
    available = {_diagnosis_key(item) for item in rule_bank.get('diagnoses', [])}
    selected, ranked_diagnoses = set(), []
    for rank, item in enumerate(diagnoses, 1):
        if not isinstance(item, dict) or not {'category', 'statement', 'rank'} <= set(item):
            raise ValueError('Diagnoses use an existing category and statement, with rank; no IDs.')
        key = _diagnosis_key(item)
        if key not in available or key in selected or item['rank'] != rank:
            raise ValueError('Select existing, distinct diagnoses in consecutive rank order.')
        selected.add(key)
        ranked_diagnoses.append({'category': key[0], 'statement': key[1],
                                  'rank': rank})
    rules = data['ranked_rules']
    if not isinstance(rules, list) or len(rules) != required['rules']:
        raise ValueError(f"Select exactly {required['rules']} existing rules.")
    selected, ranked_rules, available = set(), [], bank_rule_ids(rule_bank)
    for rank, item in enumerate(rules, 1):
        if not isinstance(item, dict) or not {'rule_id', 'rank'} <= set(item):
            raise ValueError('Select existing rule IDs with rank.')
        key = item['rule_id']
        if not isinstance(key, str) or key not in available or key in selected or item['rank'] != rank:
            raise ValueError('Selected rule IDs must exist and be distinct in consecutive rank order.')
        selected.add(key)
        ranked_rules.append({'rule_id': key, 'rank': rank})
    return {'ranked_diagnoses': ranked_diagnoses, 'ranked_rules': ranked_rules}


def make_generator_guidance(selection, rule_bank, tree, *, source_round):
    selection = parse_response(selection, tree, rule_bank)
    rules = _rule_map(rule_bank)
    return {'for_round': source_round,
            'assertion_sha256': hashlib.sha256(tree['source_assertion'].encode()).hexdigest(),
            'ranked_diagnoses': deepcopy(selection['ranked_diagnoses']),
            'ranked_rules': [{**item, 'rule': rules[item['rule_id']]['rule']}
                             for item in selection['ranked_rules']]}


def generator_view(guidance,assertion,source_round):
    if guidance.get('for_round')!=source_round or guidance.get('assertion_sha256')!=hashlib.sha256(assertion.encode()).hexdigest():
        raise ValueError('Selected guidance belongs to another assertion or round.')
    result = {key:guidance.get(key,[]) for key in ('ranked_diagnoses','ranked_rules')}
    if any(not isinstance(items, list) or not items for items in result.values()):
        raise ValueError('Revision guidance must include both selected diagnoses and selected rules.')
    fields = {'ranked_diagnoses': ('category', 'statement', 'rank'),
              'ranked_rules': ('rule_id', 'rule', 'rank')}
    return {name: [{key: item[key] for key in fields[name]} for item in items]
            for name, items in result.items()}


from new_agent.infer_rule_selector_prompts import SYSTEM_PROMPT
