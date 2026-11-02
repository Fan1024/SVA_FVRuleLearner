"""Compact tree payloads, basic response checks and inference index export."""

import json

from new_agent import assertion_tree
from new_agent.diagnosis_context import linked_diagnoses, category_label, interpretation_view
from new_agent.correction_locations import location_for
from new_agent.training_prompt_context import evaluation_feedback
from new_agent.train_tree_rule_prompts import SYSTEM_PROMPT, TASK_INSTRUCTIONS


def build_trees(reference_assertion, generated_assertion):
    """Unsupported syntax gets an explicit source anchor, never invented operators."""
    pair = {"schema_version": "training-raw-tree-1", "normalization": "none"}
    for side, source, prefix in (("reference", reference_assertion, "R"),
                                  ("generated", generated_assertion, "G")):
        try:
            pair[side] = assertion_tree.build_tree(source, prefix)
        except assertion_tree.ParseError as error:
            pair[side] = {
                "source_assertion": source, "parse_error": str(error), "context": {},
                "root": {"id": prefix + "_unparsed", "kind": "unparsed_assertion",
                         "value": source, "children": [], "child_ids": [],
                         "parent_id": None, "depth": 0},
            }
    return pair


def build_rule_prompt(requirement, generated_assertion, reference_assertion,
                      testbench=None, *, trees, evaluation_status, previous_transition=None):
    """Whitelist task data plus one fixed coarse result; never include logs/scores."""
    for side, source in (("generated", generated_assertion), ("reference", reference_assertion)):
        if trees[side].get("source_assertion") != source:
            raise ValueError(f"The {side} tree does not belong to the current source assertion.")
    data = dict(requirement=requirement,
                generated_tree=compact_tree(trees['generated']),
                reference_assertion=reference_assertion,
                evaluation_feedback=evaluation_feedback(evaluation_status))
    if previous_transition is not None:
        data['last_revision'] = previous_transition
    return TASK_INSTRUCTIONS + "\nINPUT DATA\n" + json.dumps(data, ensure_ascii=False, indent=2)


def _nodes(tree):
    """Collect original IDs without constructing or modifying a proposed graph."""
    found = {}
    def walk(node):
        found[node["id"]] = node
        for child in node.get("children", []):
            walk(child)
    walk(tree["root"])
    for context in tree.get("context", {}).values():
        walk(context["root"])
    return found


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
        # Raw parser diagnostics remain in the inspection archive. Model inputs
        # get only the availability marker, never a parser/tool log excerpt.
        result["parse_error"] = "Tree unavailable; use the source at its opaque anchor."
    return result


def parse_response(response_text, trees):
    """Read model output and resolve locations; no semantic diagnosis validation.

    Node IDs remain in inspection records; textual locations become generator
    feedback and can later be masked with the source examples for retrieval.
    """
    raw = json.loads(response_text)
    if not isinstance(raw,dict) or not isinstance(raw.get('corrections'),list):
        raise ValueError('Expected diagnoses and corrections arrays.')
    diagnoses=[]; ids=set()
    for entry in raw.get('diagnoses',[]):
        if not isinstance(entry,dict) or not isinstance(entry.get('id'),str) or entry['id'] in ids:
            raise ValueError('Diagnosis IDs must be unique strings.')
        if not isinstance(entry.get('statement'),str) or not entry['statement'].strip():
            raise ValueError('A high-level diagnosis needs an explanation.')
        ids.add(entry['id'])
        item={'id':entry['id'], 'category':category_label(entry.get('category')),
              'statement':entry['statement'].strip()}
        if isinstance(entry.get('requirement_quote'),str) and entry['requirement_quote'].strip():
            item['requirement_quote']=entry['requirement_quote'].strip()
        diagnoses.append(item)
    result={'diagnoses':diagnoses,'corrections':[]}
    for entry in raw['corrections']:
        if not isinstance(entry,dict) or not isinstance(entry.get('rule'),str) or not entry['rule'].strip():
            raise ValueError('Each correction needs a nonempty rule.')
        links=entry.get('diagnosis_ids',[])
        # Read legacy category-only corrections without preserving old interpretations.
        if not links and 'diagnosis' in entry:
            key=f'D{len(diagnoses)+1}'
            diagnoses.append({'id':key,'category':category_label(entry['diagnosis']),
                              'statement':entry.get('issue') or entry['rule'].strip()})
            ids.add(key); links=[key]
        if not isinstance(links,list) or not links or any(key not in ids for key in links):
            raise ValueError('Corrections must link to existing diagnosis IDs.')
        node_id=entry.get('generated_node_id')
        item={'diagnosis_ids':list(dict.fromkeys(links)), 'generated_node_id':node_id,
              'location':location_for(trees['generated'],node_id), 'rule':entry['rule'].strip()}
        result['corrections'].append(item)
    return result


def export_diagnoses(response,round_number):
    return [{**entry,'id':f"round_{round_number:04d}:"+entry['id'],'round':round_number}
            for entry in response.get('diagnoses',[])]


def export_rules(response, round_number):
    """Existing inference bank index only; never used as training feedback."""
    return {f"rule_{i}": {
        "group": ["tree_correction", f"round_{round_number:04d}", f"correction_{i:04d}"],
        "rule": entry["rule"].strip(),
        **({'diagnosis': entry['diagnosis']} if entry.get('diagnosis') else {}),
        **({'location': entry['location']} if entry.get('location') else {}),
        **({'diagnoses': linked_diagnoses(entry, response)}
           if any(key in entry for key in ('diagnosis', 'diagnosis_ids', 'diagnoses')) else {}),
    } for i, entry in enumerate(response["corrections"], 1)}




