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
    requirements,examples,diagnoses,cases={},{},{},[]
    req_ids,example_ids,diag_ids={},{},{}
    for candidate in candidates:
        case=safe_candidate(candidate); number=case['case_number']
        requirement=case['requirement']
        if requirement not in req_ids:
            req_ids[requirement]=f'Q{len(requirements)+1}'
            requirements[req_ids[requirement]]=requirement
        req_id=req_ids[requirement]
        rules=[]; seen={}
        def add_diag(value,example_id=None):
            item=diagnosis_view(value)
            if not item.get('category'): return None
            key=(number,item.get('category'),item.get('statement',''))
            if key not in diag_ids:
                diag_id=f'D{len(diagnoses)+1}'; diag_ids[key]=diag_id
                diagnoses[diag_id]={k:v for k,v in item.items() if k in ('category','statement','requirement_quote')}
                diagnoses[diag_id].update(requirement_id=req_id,example_ids=[])
            item=diagnoses[diag_ids[key]]
            if example_id and example_id not in item['example_ids']: item['example_ids'].append(example_id)
            return diag_ids[key]
        def add_rule(value,example_id=None):
            key=(value['rule'].strip(),value.get('location'))
            # Enrich an older index entry that lacked the trace's source location.
            if key not in seen and key[1] and (key[0],None) in seen:
                old=seen.pop((key[0],None))
                old['location']=key[1]
                seen[key]=old
            elif key not in seen and not key[1]:
                match=next((item for (text,location),item in seen.items() if text==key[0]),None)
                if match is not None:
                    key=(key[0],match.get('location'))
            if key not in seen:
                seen[key]={'id':value['id'],'rule':value['rule'],'location':value.get('location'),
                           'diagnosis_ids':[],'requirement_id':req_id}
                rules.append(seen[key])
            rule=seen[key]
            if example_id: rule['example_id']=example_id
            for item in value.get('diagnoses',[]):
                diag_id=add_diag(item,example_id)
                if diag_id and diag_id not in rule['diagnosis_ids']: rule['diagnosis_ids'].append(diag_id)
            return rule
        for item in case['diagnoses']: add_diag(item)
        for item in case['rules']: add_rule(item)
        rounds=case['revision_trace']
        for entry in rounds:
            following=next((r for r in rounds if r['diagnosis_from_round']==entry['round']),None)
            before=entry.get('assertion'); after=following.get('assertion') if following else None
            example_id=None
            if isinstance(before,str):
                key=(number,before,after if isinstance(after,str) else None)
                if key not in example_ids:
                    example_ids[key]=f'E{len(examples)+1}'
                    examples[example_ids[key]]={'before':before,'after':key[2]}
                example_id=example_ids[key]
            for item in entry['diagnoses']: add_diag(item,example_id)
            for item in entry['corrections']: add_rule(item,example_id)
        cases.append({'case_number':number,'requirement_id':req_id,'rules':rules})
    return {'requirements':requirements,'examples':examples,'diagnoses':diagnoses,'cases':cases}


def bank_rule_ids(bank):
    return {item['id'] for case in bank['cases'] for item in case['rules']}


def _rule_map(bank):
    return {item['id']:item for case in bank['cases'] for item in case['rules']}


def build_selector_prompt(requirement,testbench,tree,rule_bank,*,evaluation_status,previous_transition=None):
    # No testbench, raw tool output, policy, source score or target diagnosis.
    from new_agent.infer_rule_selector_prompts import TASK_INSTRUCTIONS
    bank={'requirements':dict(rule_bank['requirements']),
          'examples':{key:{field:item.get(field) for field in ('before','after')}
                      for key,item in rule_bank['examples'].items()},
          'diagnoses':{key:{field:deepcopy(item[field]) for field in
                           ('category','statement','requirement_quote','requirement_id','example_ids') if field in item}
                       for key,item in rule_bank.get('diagnoses',{}).items()},
          'cases':[{key:deepcopy(case[key]) for key in ('case_number','requirement_id','rules')}
                   for case in rule_bank['cases']]}
    data={'requirement':requirement,'generated_assertion':tree['source_assertion'],
          'training_guidance':bank,'selection_limits':limits(),
          'previous_outcome':outcome(evaluation_status)}
    return TASK_INSTRUCTIONS+'\nINPUT DATA\n'+json.dumps(data,ensure_ascii=False,indent=2)


def parse_response(raw,tree,rule_bank):
    data=json.loads(raw) if isinstance(raw,str) else raw
    if not isinstance(data,dict) or set(data)!={'ranked_diagnoses','ranked_rules'}:
        raise ValueError('Expected ranked_diagnoses and ranked_rules only.')
    result={}
    for field,id_field,allowed,limit in (
            ('ranked_diagnoses','diagnosis_id',set(rule_bank.get('diagnoses',{})),limits()['diagnoses']),
            ('ranked_rules','rule_id',bank_rule_ids(rule_bank),limits()['rules'])):
        values=data[field]
        if not isinstance(values,list) or len(values)>limit:
            raise ValueError('Selection exceeds its configured limit or is not an array.')
        selected=set(); rows=[]
        for rank,item in enumerate(values,1):
            if not isinstance(item,dict) or set(item)!={id_field,'rank','reason'}:
                raise ValueError('Select existing IDs and give only rank and applicability reason.')
            key=item[id_field]
            if not isinstance(key,str) or key not in allowed or key in selected or item['rank']!=rank:
                raise ValueError('Selected IDs must exist, be unique and have consecutive ranks.')
            if not isinstance(item['reason'],str) or not item['reason'].strip():
                raise ValueError('Selection needs a short applicability reason.')
            selected.add(key); rows.append(dict(item))
        result[field]=rows
    return result


def make_generator_guidance(selection,rule_bank,tree,*,source_round):
    selection=parse_response(selection,tree,rule_bank); rules=_rule_map(rule_bank)
    guidance={'for_round':source_round,
              'assertion_sha256':hashlib.sha256(tree['source_assertion'].encode()).hexdigest(),
              'ranked_diagnoses':[],'ranked_rules':[]}
    def context(item):
        result={}
        req_id=item.get('requirement_id')
        if req_id in rule_bank['requirements']: result['source_requirement']=rule_bank['requirements'][req_id]
        example_ids=item.get('example_ids',[]) or ([item['example_id']] if item.get('example_id') else [])
        if example_ids:
            example=rule_bank['examples'].get(example_ids[-1])
            if example: result['source_example']=deepcopy(example)
        return result
    for selected in selection['ranked_diagnoses']:
        item=rule_bank['diagnoses'][selected['diagnosis_id']]
        guidance['ranked_diagnoses'].append({**selected,**diagnosis_view(item),**context(item)})
    for selected in selection['ranked_rules']:
        item=rules[selected['rule_id']]
        guidance['ranked_rules'].append({**selected,'rule':item['rule'],
            'source_location':item.get('location'),**context(item)})
    return guidance


def generator_view(guidance,assertion,source_round):
    if guidance.get('for_round')!=source_round or guidance.get('assertion_sha256')!=hashlib.sha256(assertion.encode()).hexdigest():
        raise ValueError('Selected guidance belongs to another assertion or round.')
    return deepcopy({key:guidance.get(key,[]) for key in ('ranked_diagnoses','ranked_rules')})


from new_agent.infer_rule_selector_prompts import SYSTEM_PROMPT
