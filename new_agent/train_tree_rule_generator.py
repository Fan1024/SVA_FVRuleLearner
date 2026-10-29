"""Training-only tree payloads, strict response checks and legacy export adaptation."""

from copy import deepcopy
import json
import re

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
                generated_assertion=generated_assertion,
                reference_assertion=reference_assertion, trees=trees,
                comparison_scope=comparison_scope, formal_feedback=formal_feedback)
    return TASK_INSTRUCTIONS + "\nINPUT DATA\n" + json.dumps(data, ensure_ascii=False, indent=2)


def _nodes(tree):
    roots = [tree["root"]]
    roots.extend(x["root"] for x in tree.get("context", {}).values())
    nodes, components = {}, {}
    def walk(n, component):
        nodes[n["id"]] = n
        components[n["id"]] = component
        for child in n["children"]:
            walk(child, component)
    for index, root in enumerate(roots):
        walk(root, index)
    return nodes, components


def _fields(obj, expected, label):
    if not isinstance(obj, dict) or set(obj) != set(expected):
        raise ValueError(f"{label} must contain exactly {sorted(expected)}")


def _content(content, label):
    _fields(content, {"kind", "value", "attributes"}, label)
    if any(not isinstance(content[k], str) or not content[k].strip() for k in ("kind", "value")):
        raise ValueError(f"{label} needs nonempty kind/value strings")
    if not isinstance(content["attributes"], dict):
        raise ValueError(f"{label}.attributes must be an object")
    allowed = {"signal", "parameter", "literal", "unparsed_assertion", "function_call",
               "unary_operator", "binary_operator", "conditional_operator", "sequence_delay",
               "sequence_repetition", "temporal_operator", "select", "replication", "concatenation"}
    if content["kind"] not in allowed:
        raise ValueError(f"Unknown node kind in {label}")
    if content["kind"] == "unary_operator" and content["value"] not in assertion_tree.UNARY:
        raise ValueError("Unknown unary operator")
    if content["kind"] == "binary_operator" and content["value"] not in assertion_tree.BINDING:
        raise ValueError("Unknown binary operator")


def _ids(ids, label):
    if not isinstance(ids, list) or any(not isinstance(x, str) or not x for x in ids):
        raise ValueError(f"{label} must be an array of IDs")
    if len(ids) != len(set(ids)):
        raise ValueError(f"{label} contains duplicate IDs")


def _diagnosis(entry, known_ids):
    _fields(entry["diagnosis"], {"difference", "why_it_matters"}, "diagnosis")
    for text in [*entry["diagnosis"].values(), entry["rule"]]:
        if not isinstance(text, str) or not text.strip():
            raise ValueError("Diagnosis and rule text must be nonempty strings")
    pattern = r"(?<![\w])(?:" + "|".join(re.escape(x) for x in known_ids) + r")(?![\w])"
    if known_ids and re.search(pattern, entry["rule"]):
        raise ValueError("Rule text must not contain node IDs")


def parse_response(response_text, trees):
    """Check JSON/IDs/combined graph, not semantic correctness of an LLM proposal."""
    def unique_object(pairs):
        obj = {}
        for key, value in pairs:
            if key in obj:
                raise ValueError(f"Duplicate JSON key: {key}")
            obj[key] = value
        return obj
    result = json.loads(response_text, object_pairs_hook=unique_object)
    _fields(result, {"node_rules", "formatting_rules"}, "response")
    if any(not isinstance(result[k], list) for k in result):
        raise ValueError("Both response fields must be arrays")
    original, components = _nodes(trees["generated"])
    reference, _ = _nodes(trees["reference"])
    graph = {k: list(n["child_ids"]) for k, n in original.items()}
    content = {k: {x: deepcopy(n.get(x, {})) for x in ("kind", "value", "attributes")}
               for k, n in original.items()}
    inserted = [e.get("node", {}).get("id") for e in result["node_rules"]
                if isinstance(e, dict) and e.get("operation") == "insert"
                and isinstance(e.get("node"), dict)]
    if any(not isinstance(x, str) or not re.fullmatch(r"NEW_[1-9][0-9]*", x) for x in inserted):
        raise ValueError("Inserted IDs must be NEW_1, NEW_2, ...")
    if len(set(inserted)) != len(inserted):
        raise ValueError("Inserted IDs must be unique")
    known = set(original) | set(reference) | set(inserted)
    deleted, targeted, updates, insertions = set(), set(), {}, []
    common = {"operation", "node", "reference_node_ids", "diagnosis", "rule"}
    extras = {"modify": {"new_content"},
              "insert": {"parent_id", "child_index", "replaces_child_id", "child_ids"},
              "remove": {"connections_after"}, "move": {"connections_after"}}
    for e in result["node_rules"]:
        if not isinstance(e, dict) or e.get("operation") not in extras:
            raise ValueError("Unknown correction operation")
        op = e["operation"]
        _fields(e, common | extras[op], "node correction")
        _fields(e["node"], {"id", "kind", "value", "attributes"}, "node")
        node_id = e["node"]["id"]
        if not isinstance(node_id, str) or node_id in targeted:
            raise ValueError("Each target node must have exactly one correction")
        targeted.add(node_id)
        item_content = {k: e["node"][k] for k in ("kind", "value", "attributes")}
        _content(item_content, "node")
        _ids(e["reference_node_ids"], "reference_node_ids")
        if not set(e["reference_node_ids"]) <= reference.keys():
            raise ValueError("Unknown reference node ID")
        _diagnosis(e, known)
        if op != "insert":
            if node_id not in original or item_content != content[node_id]:
                raise ValueError("Existing target content must match the original tree")
            if content[node_id]["kind"] == "unparsed_assertion" and op != "modify":
                raise ValueError("Opaque source anchors support modify only")
        if op == "modify":
            _content(e["new_content"], "new_content")
            if item_content["kind"] == "unparsed_assertion" and e["new_content"]["kind"] != "unparsed_assertion":
                raise ValueError("Do not invent parsed structure inside an opaque source anchor")
            content[node_id] = deepcopy(e["new_content"])
        elif op == "insert":
            if node_id in original:
                raise ValueError("An inserted node cannot reuse an existing ID")
            _ids(e["child_ids"], "child_ids")
            graph[node_id] = list(e["child_ids"])
            content[node_id] = deepcopy(item_content)
            insertions.append(e)
        else:
            if op == "remove":
                deleted.add(node_id)
            if not isinstance(e["connections_after"], list):
                raise ValueError("connections_after must be an array")
            for change in e["connections_after"]:
                _fields(change, {"node_id", "child_ids"}, "connection update")
                _ids(change["child_ids"], "child_ids")
                parent = change["node_id"]
                if not isinstance(parent, str) or parent in updates:
                    raise ValueError("Record each changed child list once")
                updates[parent] = list(change["child_ids"])
    # Explicit child lists describe the final graph, not sequential mutations.
    for node_id, children in updates.items():
        if node_id not in graph or node_id in deleted:
            raise ValueError("Connection update names a missing/deleted parent")
        graph[node_id] = children
    # A new parent's child_ids already describes its final children. For an
    # existing parent, apply sibling insertions in ascending final positions.
    for e in sorted(insertions, key=lambda x: (str(x["parent_id"]),
                    x["child_index"] if type(x["child_index"]) is int else -1)):
        parent, index, replaced = e["parent_id"], e["child_index"], e["replaces_child_id"]
        if parent is None:
            if index is not None or replaced is not None:
                raise ValueError("New-root location fields must all be null")
            continue
        if not isinstance(parent, str) or parent not in graph or parent in deleted:
            raise ValueError("Unknown insertion parent")
        if type(index) is not int or index < 0:
            raise ValueError("child_index must be a nonnegative integer")
        children = graph[parent]
        if parent in inserted or parent in updates:
            if index >= len(children) or children[index] != e["node"]["id"]:
                raise ValueError("Insertion location conflicts with the parent's final child list")
            if parent in inserted and replaced is not None:
                raise ValueError("An inserted parent has no original child to replace")
            continue
        if replaced is not None:
            if not isinstance(replaced, str) or replaced not in children:
                raise ValueError("Insertion replacement is not a child of its parent")
            children.remove(replaced)
        if index > len(children):
            raise ValueError("Insertion position exceeds the child list")
        children.insert(index, e["node"]["id"])
    for node_id in deleted:
        del graph[node_id]
        del content[node_id]
    indegree = {k: 0 for k in graph}
    for children in graph.values():
        for child in children:
            if child not in graph:
                raise ValueError("Connection names a missing/deleted child")
            indegree[child] += 1
    if any(n > 1 for n in indegree.values()):
        raise ValueError("Proposed tree gives a node multiple parents")
    roots = [k for k, degree in indegree.items() if degree == 0]
    if len(roots) != len(set(components.values())):
        raise ValueError("Proposed graph changes the number of body/context roots")
    seen = set()
    def visit(k, component_members):
        if k in seen:
            raise ValueError("Cycle or multiply visited node")
        seen.add(k)
        if k in components:
            component_members.add(components[k])
        for child in graph[k]:
            visit(child, component_members)
    memberships = []
    for root in roots:
        members = set()
        visit(root, members)
        if len(members) != 1:
            raise ValueError("Do not merge or invent body/context components")
        memberships.extend(members)
    if len(seen) != len(graph) or len(set(memberships)) != len(memberships):
        raise ValueError("Cycle, disconnection or split body/context component")
    fixed = {"signal": 0, "parameter": 0, "literal": 0, "unparsed_assertion": 0,
             "unary_operator": 1, "binary_operator": 2, "conditional_operator": 3,
             "sequence_repetition": 1, "temporal_operator": 1, "replication": 2}
    for node_id, children in graph.items():
        kind = content[node_id]["kind"]
        expected = fixed.get(kind)
        if kind == "sequence_delay":
            expected = 1 if content[node_id]["attributes"].get("prefix") else 2
        if expected is not None and len(children) != expected:
            raise ValueError(f"Invalid operand count for {node_id}: {kind}")
        if kind == "select" and len(children) not in (2, 3):
            raise ValueError("Invalid selection operand count")
        if kind == "concatenation" and not children:
            raise ValueError("Empty concatenation")
    for entry in result["formatting_rules"]:
        _fields(entry, {"diagnosis", "rule"}, "formatting correction")
        _diagnosis(entry, known)
    return result


def export_rules(response, round_number):
    """Preserve inference's group/rule contract; details are exported separately.

    IDs are snapshot-local. Round-scoped groups avoid merging unrelated nodes
    solely because their preorder IDs happen to match in successive rounds.
    """
    entries = [("node", e) for e in response["node_rules"]]
    entries += [("formatting", e) for e in response["formatting_rules"]]
    return {f"rule_{i}": {
        "group": ["tree_" + kind, f"round_{round_number:04d}", f"correction_{i:04d}"],
        "rule": entry["rule"].strip(),
    } for i, (kind, entry) in enumerate(entries, 1)}
