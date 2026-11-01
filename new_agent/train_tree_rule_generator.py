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
                      testbench, *, trees, evaluation_status, previous_transition=None):
    """Whitelist task data plus one fixed coarse result; never include logs/scores."""
    for side, source in (("generated", generated_assertion), ("reference", reference_assertion)):
        if trees[side].get("source_assertion") != source:
            raise ValueError(f"The {side} tree does not belong to the current source assertion.")
    data = dict(requirement=requirement, testbench=testbench,
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
    result = json.loads(response_text)
    if not isinstance(result, dict) or not isinstance(result.get("corrections"), list):
        raise ValueError("Expected a JSON object with a corrections array")
    generated, reference = _nodes(trees["generated"]), _nodes(trees["reference"])
    if 'requirement_interpretation' in result:
        if not isinstance(result['requirement_interpretation'], dict):
            raise ValueError('requirement_interpretation must be an object')
        result['requirement_interpretation'] = interpretation_view(result['requirement_interpretation'])
    for entry in result["corrections"]:
        if not isinstance(entry, dict):
            raise ValueError("Each correction must be an object")
        node_id = entry.get("generated_node_id")
        if not isinstance(node_id, str) or node_id not in generated:
            raise ValueError("Correction has an unknown generated_node_id")
        ids = entry.get("reference_node_ids", [])
        if not isinstance(ids, list) or any(not isinstance(x, str) or x not in reference for x in ids):
            raise ValueError("reference_node_ids must contain existing reference IDs")
        if 'diagnosis' in entry:
            entry['diagnosis'] = category_label(entry['diagnosis'])
        elif 'requirement_interpretation' in result:
            raise ValueError('Each new-schema correction needs a diagnosis category')
        for key in ("rule",):
            if not isinstance(entry.get(key), str) or not entry[key].strip():
                raise ValueError(f"Correction needs nonempty {key} text")
        entry['location'] = location_for(trees['generated'], node_id)
    return result


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



