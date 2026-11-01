"""Select existing rules and independently localize issues; never generate rules."""
import hashlib
import json
import re

from new_agent.correction_locations import location_for
from new_agent.diagnosis_context import diagnosis_view
from new_agent.training_prompt_context import evaluation_feedback
from new_agent.infer_rule_selector_prompts import SYSTEM_PROMPT, TASK_INSTRUCTIONS

MAX_SELECTED_RULES = 5


def compact_tree(tree, *, include_source=True):
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
        result["context"] = {key: {"root": compact(value["root"])}
                             for key, value in tree["context"].items()}
    if "parse_error" in tree:
        result["parse_error"] = "Tree unavailable; use the supplied opaque source anchor."
    return result


def safe_candidate(case):
    """Only training requirement/rules/generated revisions; no refs or scores."""
    result = {"case_number": case["case_number"], "requirement": case["requirement"],
              "rules": [{key: rule[key] for key in ("id", "rule", "location", "diagnoses") if key in rule}
                        for rule in case["rules"]], "revision_trace": []}
    for entry in case.get("revision_trace", []):
        result["revision_trace"].append({
            "round": entry["round"], "assertion": entry.get("assertion"),
            "diagnosis_from_round": entry.get("diagnosis_from_round"),
            "corrections": [{key: correction[key] for key in ("id", "rule", "location", "diagnoses") if key in correction}
                            for correction in entry.get("corrections", [])],
        })
    return result


def compact_rule_bank(candidates):
    """One source requirement/text per occurrence; no scores or full histories."""
    requirements, requirement_ids, cases = {}, {}, []
    examples, example_ids = {}, {}
    diagnoses, diagnosis_ids = {}, {}
    for candidate in candidates:
        case = safe_candidate(candidate)
        requirement = case['requirement']
        if requirement not in requirement_ids:
            key = f'Q{len(requirements) + 1}'
            requirement_ids[requirement] = key
            requirements[key] = requirement
        rules, seen = [], {}

        def add_rule(rule):
            text_key = re.sub(r'\s+', ' ', rule['rule']).strip()
            location = rule.get('location') or None
            matches = seen.setdefault(text_key, [])
            item = next((r for r in matches if r.get('location') == location), None)
            # An old index may lack the location available in its linked trace.
            if item is None and location:
                item = next((r for r in matches if not r.get('location')), None)
            if item is None and not location and matches:
                item = matches[0]
            if item is None:
                item = {'id': rule['id'], 'rule': rule['rule'], 'location': location}
                matches.append(item)
                rules.append(item)
            elif location:
                item['location'] = location
            for diagnosis in rule.get('diagnoses', []):
                value = {key: text for key, text in diagnosis_view(diagnosis).items()
                         if key in {'category', 'statement'}}
                if not value:
                    continue
                key = (case['case_number'], value.get('category'), value.get('statement'))
                if key not in diagnosis_ids:
                    diagnosis_id = f'D{len(diagnoses) + 1}'
                    diagnosis_ids[key] = diagnosis_id
                    diagnoses[diagnosis_id] = value
                linked = item.setdefault('diagnosis_ids', [])
                if diagnosis_ids[key] not in linked:
                    linked.append(diagnosis_ids[key])
            return item

        for rule in case['rules']:
            add_rule(rule)
        rounds = case['revision_trace']
        for entry in rounds:
            following = next((r for r in rounds if r['diagnosis_from_round'] == entry['round']), None)
            for correction in entry['corrections']:
                item = add_rule(correction)
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
    return {'requirements': requirements, 'examples': examples, 'diagnoses': diagnoses, 'cases': cases}


def bank_rule_ids(bank):
    return {rule['id'] for case in bank['cases'] for rule in case['rules']}


def build_selector_prompt(requirement, testbench, tree, rule_bank, *, evaluation_status):
    """No reference argument, raw result, policy, metrics, logs or template."""
    # Re-project cached data rather than trusting arbitrary bank metadata.
    bank = {
        "requirements": dict(rule_bank["requirements"]),
        "diagnoses": {key: {field: item[field] for field in ('category', 'statement') if field in item}
                      for key, item in rule_bank.get("diagnoses", {}).items()},
        "examples": {key: {field: example.get(field) for field in ("before", "after")}
                     for key, example in rule_bank["examples"].items()},
        "cases": [{"case_number": case["case_number"], "requirement_id": case["requirement_id"],
                   "rules": [{key: rule[key] for key in ("id", "rule", "location", "example_id", "diagnosis_ids") if key in rule}
                             for rule in case["rules"]]} for case in rule_bank["cases"]],
    }
    data = {"requirement": requirement, "testbench": testbench,
            "generated_tree": compact_tree(tree), "retrieved_training_guidance": bank,
            "evaluation_feedback": evaluation_feedback(evaluation_status)}
    return TASK_INSTRUCTIONS + "\nINPUT DATA\n" + json.dumps(data, ensure_ascii=False, indent=2)


def _node_ids(tree):
    ids = set()
    def walk(node):
        ids.add(node["id"])
        for child in node.get("children", []):
            walk(child)
    walk(tree["root"])
    for context in tree.get("context", {}).values():
        walk(context["root"])
    return ids


def _text(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(label + " must be nonempty text.")
    return value.strip()


def parse_response(raw, tree, rule_bank):
    """Strictly forbid newly authored rules and rule/location assignments."""
    data = json.loads(raw) if isinstance(raw, str) else raw
    if not isinstance(data, dict) or set(data) != {"ranked_rules", "locations"}:
        raise ValueError("Expected only ranked_rules and locations.")
    if not isinstance(data["ranked_rules"], list) or not isinstance(data["locations"], list):
        raise ValueError("ranked_rules and locations must be arrays.")
    if len(data["ranked_rules"]) > MAX_SELECTED_RULES:
        raise ValueError("Select at most five existing rules.")
    allowed, selected = bank_rule_ids(rule_bank), set()
    ranked = []
    for rank, item in enumerate(data["ranked_rules"], 1):
        if not isinstance(item, dict) or set(item) != {"rule_id", "rank", "reason"}:
            raise ValueError("Ranked entries contain only rule_id, rank and reason; no target or rule text.")
        rule_id = item["rule_id"]
        if not isinstance(rule_id, str) or rule_id not in allowed or rule_id in selected:
            raise ValueError("Unknown or duplicate retrieved rule ID.")
        if type(item["rank"]) is not int or item["rank"] != rank:
            raise ValueError("Ranks must be consecutive integers starting at one.")
        selected.add(rule_id)
        ranked.append({"rule_id": rule_id, "rank": rank, "reason": _text(item["reason"], "reason")})
    ids, seen, locations = _node_ids(tree), set(), []
    fields = {"generated_node_id", "expected_behavior", "observed_behavior", "why_it_matters"}
    for item in data["locations"]:
        if not isinstance(item, dict) or set(item) != fields:
            raise ValueError("Locations contain diagnostic observations only; no rule assignment or action.")
        node_id = item["generated_node_id"]
        if not isinstance(node_id, str) or node_id not in ids or node_id in seen:
            raise ValueError("Unknown or duplicate current node ID.")
        seen.add(node_id)
        locations.append({key: _text(item[key], key) for key in
                          ("generated_node_id", "expected_behavior", "observed_behavior", "why_it_matters")})
    return {"ranked_rules": ranked, "locations": locations}


def make_generator_guidance(selection, rule_bank, tree, *, source_round):
    """Resolve immutable rule texts and independent locations in Python."""
    if type(source_round) is not int or source_round < 1:
        raise ValueError("A positive source round is required.")
    selection = parse_response(selection, tree, rule_bank)
    by_id = {rule["id"]: rule for case in rule_bank["cases"] for rule in case["rules"]}
    return {
        "for_round": source_round,
        "assertion_sha256": hashlib.sha256(tree["source_assertion"].encode("utf-8")).hexdigest(),
        "ranked_rules": [{"rank": entry["rank"], "rule": by_id[entry["rule_id"]]["rule"],
                          "reason": entry["reason"],
                          "source_diagnoses": [dict(rule_bank.get('diagnoses', {})[key])
                              for key in by_id[entry['rule_id']].get('diagnosis_ids', [])
                              if key in rule_bank.get('diagnoses', {})]}
                         for entry in selection["ranked_rules"]],
        "locations": [{"location": location_for(tree, entry["generated_node_id"]),
                       **{key: entry[key] for key in ("expected_behavior", "observed_behavior", "why_it_matters")}}
                      for entry in selection["locations"]],
    }


def generator_view(guidance, assertion, source_round):
    """Re-project model-visible fields and reject stale source locations."""
    if not isinstance(guidance, dict) or guidance.get("for_round") != source_round:
        raise ValueError("Selector guidance belongs to another assertion round.")
    digest = hashlib.sha256(assertion.encode("utf-8")).hexdigest()
    if guidance.get("assertion_sha256") != digest:
        raise ValueError("Selector guidance belongs to another source assertion.")
    ranked = []
    for rank, entry in enumerate(guidance.get("ranked_rules", []), 1):
        if rank > MAX_SELECTED_RULES or entry.get("rank") != rank:
            raise ValueError("Invalid ranked rule list.")
        ranked.append({"rank": rank, "rule": _text(entry.get("rule"), "rule"),
                       "reason": _text(entry.get("reason"), "reason"),
                       "source_diagnoses": [
                           {key: item[key] for key in ('category', 'statement') if isinstance(item.get(key), str)}
                           for item in entry.get('source_diagnoses', []) if isinstance(item, dict)]})
    locations = [{key: _text(entry.get(key), key) for key in
                  ("location", "expected_behavior", "observed_behavior", "why_it_matters")}
                 for entry in guidance.get("locations", [])]
    return {"ranked_rules": ranked, "locations": locations}



