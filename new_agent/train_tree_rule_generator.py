"""Compact tree payloads, basic response checks and inference index export."""

import json

from new_agent import assertion_tree
from new_agent.formal_check import COMPARISON_SCOPE
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
                      testbench, *, trees, comparison_scope=COMPARISON_SCOPE,
                      formal_feedback=""):
    data = dict(requirement=requirement, testbench=testbench,
                trees={side: compact_tree(trees[side]) for side in ("generated", "reference")},
                comparison_scope=comparison_scope, formal_feedback=formal_feedback)
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
        result["parse_error"] = tree["parse_error"]
    return result


def parse_response(response_text, trees):
    """Basic JSON/field/ID checks only. This does not validate graph edits or SVA.

    The pipeline forwards the complete raw response even if these checks fail;
    checks control structured storage/retrieval export, not generation feedback.
    """
    result = json.loads(response_text)
    if not isinstance(result, dict) or not isinstance(result.get("corrections"), list):
        raise ValueError("Expected a JSON object with a corrections array")
    generated, reference = _nodes(trees["generated"]), _nodes(trees["reference"])
    for entry in result["corrections"]:
        if not isinstance(entry, dict):
            raise ValueError("Each correction must be an object")
        node_id = entry.get("generated_node_id")
        if not isinstance(node_id, str) or node_id not in generated:
            raise ValueError("Correction has an unknown generated_node_id")
        ids = entry.get("reference_node_ids")
        if not isinstance(ids, list) or any(not isinstance(x, str) or x not in reference for x in ids):
            raise ValueError("reference_node_ids must contain existing reference IDs")
        for key in ("difference", "why_it_matters", "rule"):
            if not isinstance(entry.get(key), str) or not entry[key].strip():
                raise ValueError(f"Correction needs nonempty {key} text")
    return result


def export_rules(response, round_number):
    """Existing inference bank index only; never used as training feedback."""
    return {f"rule_{i}": {
        "group": ["tree_correction", f"round_{round_number:04d}", f"correction_{i:04d}"],
        "rule": entry["rule"].strip(),
    } for i, entry in enumerate(response["corrections"], 1)}
