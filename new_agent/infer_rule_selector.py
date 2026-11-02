"""Independent selection of existing training explanations and correction rules."""
from copy import deepcopy
import hashlib
import json
from new_agent import config
from new_agent.diagnosis_context import diagnosis_view
from new_agent.generation_context import outcome

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


def safe_candidate(case):
    """Project only source requirement, diagnoses, rules and generated revisions."""
    return {'case_number':case['case_number'],'requirement':case['requirement'],
            'diagnoses':[diagnosis_view(item) for item in case.get('diagnoses',[])],
            'rules':[{key:deepcopy(item[key]) for key in ('id','rule','location','diagnoses') if key in item}
                     for item in case.get('rules',[])],
            'revision_trace':[
                {'round':entry['round'],'assertion':entry.get('assertion'),
                 'diagnosis_from_round':entry.get('diagnosis_from_round'),
                 'diagnoses':[diagnosis_view(item) for item in entry.get('diagnoses',[])],
                 'corrections':[{key:deepcopy(item[key]) for key in ('id','rule','location','diagnoses') if key in item}
                                for item in entry.get('corrections',[])]}
                for entry in case.get('revision_trace',[])]}


def compact_rule_bank(candidates):
    requirements, examples, diagnoses, cases = {}, {}, [], []
    req_ids, example_ids, diagnosis_entries = {}, {}, {}
    for candidate in candidates:
        case = safe_candidate(candidate)
        number, requirement = case['case_number'], case['requirement']
        if requirement not in req_ids:
            req_ids[requirement] = f'Q{len(requirements)+1}'
            requirements[req_ids[requirement]] = requirement
        req_id = req_ids[requirement]
        rules, seen = [], {}

        def add_diagnosis(value, example_id=None):
            item = diagnosis_view(value)
            if not item.get('category'):
                return
            key = (item['category'], item.get('statement', ''))
            if key not in diagnosis_entries:
                diagnosis_entries[key] = {'category': key[0], 'statement': key[1],
                                           'source_contexts': []}
                diagnoses.append(diagnosis_entries[key])
            contexts = diagnosis_entries[key]['source_contexts']
            context = next((entry for entry in contexts if entry['requirement_id'] == req_id), None)
            if context is None:
                context = {'requirement_id': req_id, 'example_ids': []}
                contexts.append(context)
            if example_id and example_id not in context['example_ids']:
                context['example_ids'].append(example_id)

        def add_rule(value, example_id=None):
            key = (value['rule'].strip(), value.get('location'))
            if key not in seen and key[1] and (key[0], None) in seen:
                entry = seen.pop((key[0], None))
                entry['location'] = key[1]
                seen[key] = entry
            elif key not in seen and not key[1]:
                entry = next((item for (text, loc), item in seen.items() if text == key[0]), None)
                if entry is not None:
                    key = (key[0], entry.get('location'))
            if key not in seen:
                seen[key] = {'id': value['id'], 'rule': value['rule'],
                             'location': value.get('location'), 'requirement_id': req_id}
                rules.append(seen[key])
            if example_id:
                seen[key]['example_id'] = example_id
            # Older source banks attached diagnoses to rules. Read them as
            # independent source observations; do not recreate those associations.
            for item in value.get('diagnoses', []):
                add_diagnosis(item, example_id)

        for item in case['diagnoses']:
            add_diagnosis(item)
        for item in case['rules']:
            add_rule(item)
        rounds = case['revision_trace']
        for entry in rounds:
            following = next((row for row in rounds if row['diagnosis_from_round'] == entry['round']), None)
            before, after = entry.get('assertion'), following.get('assertion') if following else None
            example_id = None
            if isinstance(before, str):
                key = (number, before, after if isinstance(after, str) else None)
                if key not in example_ids:
                    example_ids[key] = f'E{len(examples)+1}'
                    examples[example_ids[key]] = {'before': before, 'after': key[2]}
                example_id = example_ids[key]
            for item in entry['diagnoses']:
                add_diagnosis(item, example_id)
            for item in entry['corrections']:
                add_rule(item, example_id)
        cases.append({'case_number': number, 'requirement_id': req_id, 'rules': rules})
    return {'requirements': requirements, 'examples': examples, 'diagnoses': diagnoses, 'cases': cases}


def bank_rule_ids(bank):
    return {item['id'] for case in bank['cases'] for item in case['rules']}


def _rule_map(bank):
    return {item['id']:item for case in bank['cases'] for item in case['rules']}


def build_selector_prompt(requirement, testbench, tree, rule_bank, *, evaluation_status, previous_transition=None):
    from new_agent.infer_rule_selector_prompts import TASK_INSTRUCTIONS
    bank = {'requirements': dict(rule_bank['requirements']),
            'examples': {key: {field: item.get(field) for field in ('before', 'after')}
                         for key, item in rule_bank['examples'].items()},
            'diagnoses': [{**diagnosis_view(item), 'source_contexts': deepcopy(item.get('source_contexts', []))}
                          for item in rule_bank.get('diagnoses', [])],
            'cases': [{key: deepcopy(case[key]) for key in ('case_number', 'requirement_id', 'rules')}
                      for case in rule_bank['cases']]}
    data = {'requirement': requirement, 'generated_assertion': tree['source_assertion'],
            'training_guidance': bank, 'selection_limits': limits(),
            'previous_outcome': outcome(evaluation_status)}
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
    diagnoses = data['ranked_diagnoses']
    if not isinstance(diagnoses, list) or len(diagnoses) > limits()['diagnoses']:
        raise ValueError('Diagnosis selection exceeds its limit or is not an array.')
    available = {_diagnosis_key(item) for item in rule_bank.get('diagnoses', [])}
    selected, ranked_diagnoses = set(), []
    for rank, item in enumerate(diagnoses, 1):
        if not isinstance(item, dict) or set(item) != {'category', 'statement', 'rank', 'reason'}:
            raise ValueError('Diagnoses use category and statement, with rank and reason; no IDs.')
        key = _diagnosis_key(item)
        if key not in available or key in selected or item['rank'] != rank:
            raise ValueError('Select existing, distinct diagnoses in consecutive rank order.')
        if not isinstance(item['reason'], str) or not item['reason'].strip():
            raise ValueError('Selection needs a short applicability reason.')
        selected.add(key)
        ranked_diagnoses.append({'category': key[0], 'statement': key[1],
                                  'rank': rank, 'reason': item['reason'].strip()})
    rules = data['ranked_rules']
    if not isinstance(rules, list) or len(rules) > limits()['rules']:
        raise ValueError('Rule selection exceeds its limit or is not an array.')
    selected, ranked_rules, available = set(), [], bank_rule_ids(rule_bank)
    for rank, item in enumerate(rules, 1):
        if not isinstance(item, dict) or set(item) != {'rule_id', 'rank', 'reason'}:
            raise ValueError('Select existing rule IDs with rank and reason.')
        key = item['rule_id']
        if not isinstance(key, str) or key not in available or key in selected or item['rank'] != rank:
            raise ValueError('Selected rule IDs must exist and be distinct in consecutive rank order.')
        if not isinstance(item['reason'], str) or not item['reason'].strip():
            raise ValueError('Selection needs a short applicability reason.')
        selected.add(key)
        ranked_rules.append(dict(item))
    return {'ranked_diagnoses': ranked_diagnoses, 'ranked_rules': ranked_rules}


def make_generator_guidance(selection, rule_bank, tree, *, source_round):
    selection = parse_response(selection, tree, rule_bank)
    rules = _rule_map(rule_bank)
    diagnoses = {_diagnosis_key(item): item for item in rule_bank.get('diagnoses', [])}
    guidance = {'for_round': source_round,
                'assertion_sha256': hashlib.sha256(tree['source_assertion'].encode()).hexdigest(),
                'ranked_diagnoses': [], 'ranked_rules': []}

    def context(item):
        result = {}
        contexts = item.get('source_contexts', [])
        if contexts:
            item = next((entry for entry in contexts if entry.get('example_ids')), contexts[0])
        req_id = item.get('requirement_id')
        if req_id in rule_bank['requirements']:
            result['source_requirement'] = rule_bank['requirements'][req_id]
        example_ids = item.get('example_ids', []) or ([item['example_id']] if item.get('example_id') else [])
        if example_ids:
            example = rule_bank['examples'].get(example_ids[-1])
            if example:
                result['source_example'] = deepcopy(example)
        return result

    for selected in selection['ranked_diagnoses']:
        item = diagnoses[_diagnosis_key(selected)]
        guidance['ranked_diagnoses'].append({**selected, **context(item)})
    for selected in selection['ranked_rules']:
        item = rules[selected['rule_id']]
        guidance['ranked_rules'].append({**selected, 'rule': item['rule'],
                                         'source_location': item.get('location'), **context(item)})
    return guidance


def generator_view(guidance,assertion,source_round):
    if guidance.get('for_round')!=source_round or guidance.get('assertion_sha256')!=hashlib.sha256(assertion.encode()).hexdigest():
        raise ValueError('Selected guidance belongs to another assertion or round.')
    return deepcopy({key:guidance.get(key,[]) for key in ('ranked_diagnoses','ranked_rules')})


from new_agent.infer_rule_selector_prompts import SYSTEM_PROMPT
