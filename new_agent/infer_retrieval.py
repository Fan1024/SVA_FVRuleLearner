"""Separate example and rule indexes for one selected training run."""

import csv
import hashlib
import json
from pathlib import Path


def _accepted_csv_assertions(directory, allowed_ids):
    """Read final generated source, never the reference column, from a TRAIN run."""
    path = Path(directory) / "evaluation.csv"
    if not path.is_file():
        return {}
    result, seen = {}, set()
    with path.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            try:
                number = int(row["case_number"])
            except (KeyError, TypeError, ValueError) as error:
                raise ValueError("Invalid training evaluation case ID.") from error
            if number not in allowed_ids or number in seen:
                raise ValueError("Training evaluation contains an excluded or duplicate case ID.")
            seen.add(number)
            result[number] = None
            source = row.get("generated_assertion")
            if row.get("passed", "").strip().lower() == "true" and isinstance(source, str) and source.strip():
                result[number] = source
    return result


def _legacy_generated_assertion(directory, number, case):
    """Legacy generated-source fallback; an absent source never falls back to gold."""
    source = case.get("generated_assertion")
    if isinstance(source, str) and source.strip():
        return source
    from new_agent.infer_training_traces import load_case_trace
    rounds, _ = load_case_trace(directory, number, {
        "trace_file": case.get("trace_file"), "round_evidence": case.get("round_evidence", [])})
    for entry in reversed(rounds):
        source = entry.get("assertion")
        evaluation = entry.get("evaluation") or {}
        accepted = evaluation.get("accepted") is True or evaluation.get("status") == "FULL_EQUIVALENCE"
        if accepted and isinstance(source, str) and source.strip():
            return source
    return None


class RuleRetriever:
    """Share one embedding model; rank training examples and rule cases separately."""

    def __init__(self, training_run_dir, *, training_case_ids, training_cases,
                 top_k: int, model_name: str):
        self.directory = Path(training_run_dir).resolve()
        self.top_k = top_k
        # Only source requirements/declarations assist masking; no references
        # are copied into retrieval objects or inference model payloads.
        source_cases = {case["case_number"]: case for case in training_cases}
        if len(source_cases) != len(training_cases) or set(source_cases) != set(training_case_ids):
            raise ValueError("Training source pool must match the selected training case IDs.")
        self.masking_contexts = {number: {
            "requirement": case.get("requirement", ""), "testbench": case.get("testbench", "")}
            for number, case in source_cases.items()}
        self.examples = []
        self.missing_generated_example_case_ids = []
        accepted_rows = _accepted_csv_assertions(self.directory, set(training_case_ids))
        path = self.directory / "learned_rules.jsonl"
        data = path.read_bytes()
        self.sha256 = hashlib.sha256(data).hexdigest()
        self.cases = []
        self.excluded_unpassed_case_ids = []
        self._trace_sources = {}
        self._trace_cache = {}
        seen = set()
        for line_number, line in enumerate(data.decode("utf-8-sig").splitlines(), 1):
            if not line.strip():
                continue
            case = json.loads(line)
            if not isinstance(case, dict):
                raise ValueError(f"Rule bank line {line_number} must be an object.")
            number = case.get("case_number")
            if type(number) is not int or number not in training_case_ids or number in seen:
                raise ValueError(f"Invalid or duplicate rule-bank case ID at line {line_number}.")
            seen.add(number)
            if case.get('passed') is not True:
                self.excluded_unpassed_case_ids.append(number)
                continue
            example_source = accepted_rows.get(number)
            if number not in accepted_rows:
                example_source = _legacy_generated_assertion(self.directory, number, case)
            example_requirement = source_cases[number].get("requirement")
            if (isinstance(example_source, str) and example_source.strip()
                    and isinstance(example_requirement, str) and example_requirement.strip()):
                self.examples.append({"case_number": number, "requirement": example_requirement,
                                      "solved_assertion": example_source})
            else:
                self.missing_generated_example_case_ids.append(number)
            requirement = case.get("requirement")
            rules = case.get("rules")
            if not isinstance(requirement, str) or not requirement.strip() or not isinstance(rules, dict):
                continue
            rules = {key: value.strip() for key, value in rules.items()
                     if isinstance(value, str) and value.strip()}
            if not rules:
                continue
            self._trace_sources[number] = {
                'trace_file': case.get('trace_file'),
                'round_evidence': case.get('round_evidence', []),
            }
            groups = case.get("rule_groups", {})
            if not isinstance(groups, dict):
                raise ValueError(f"Invalid rule_groups for case {number}.")
            locations = case.get('rule_locations', {})
            if not isinstance(locations, dict):
                locations = {}
            # Only selected TRAINING generated revisions can enter selector
            # evidence. The selector's allowlist removes scores and diagnostics.
            round_evidence = []
            for evidence in case.get("round_evidence", []):
                evaluation = evidence.get("evaluation")
                round_evidence.append({
                    "round": evidence["round"],
                    "generated_assertion": evidence.get("generated_assertion"),
                    "evaluation": None if evaluation is None else {
                        key: evaluation.get(key) for key in (
                            "status", "syntax", "pec", "relax_pec", "bleu", "rouge",
                            "exact_match", "accepted", "acceptance_reason",
                        )
                    },
                    "rules_used": [{key: rule.get(key) for key in (
                        "group", "rule", "updated_round",
                    )} for rule in evidence.get("rules_used", [])],
                    "rules_generated": {
                        rule_id: {"group": rule["group"], "rule": rule["rule"]}
                        for rule_id, rule in evidence.get("rules_generated", {}).items()
                    },
                })
            self.cases.append({
                "case_number": number, "design_name": case.get("design_name"),
                "task_id": case.get("task_id"), "requirement": requirement.strip(),
                "passed": case.get("passed"), "rules": rules,
                "rule_groups": {key: groups.get(key, []) for key in rules},
                "rule_locations": {key: locations[key] for key in rules
                                   if isinstance(locations.get(key), str) and locations[key].strip()},
                "rule_rounds": {key: case.get("rule_rounds", {}).get(key) for key in rules},
                "round_evidence": round_evidence,
            })
        self.examples.sort(key=lambda case: case["case_number"])
        if not self.examples and not self.cases:
            self.model = self._cosine_similarity = None
            self.example_embeddings = self.embeddings = []
            return
        # Training mode does not import or load the embedding dependency.
        from sentence_transformers import SentenceTransformer
        from sklearn.metrics.pairwise import cosine_similarity
        self._cosine_similarity = cosine_similarity
        self.model = SentenceTransformer(model_name, device="cpu")
        embeddings = self.model.encode(
            [c["requirement"] for c in self.examples] + [c["requirement"] for c in self.cases]
        )
        self.example_embeddings = embeddings[:len(self.examples)]
        self.embeddings = embeddings[len(self.examples):]

    def retrieve(self, requirement: str) -> list[dict]:
        """Rank eligible cases before selecting up to top_k; keep ties deterministic."""
        if not self.cases:
            return []
        query = self.model.encode([requirement])
        scores = self._cosine_similarity(query, self.embeddings)[0]
        order = sorted(range(len(scores)), key=lambda i: (-float(scores[i]), self.cases[i]["case_number"]))
        from new_agent.infer_training_traces import load_case_trace
        selected = []
        for i in order[:self.top_k]:
            case = self.cases[i]
            number = case['case_number']
            if number not in self._trace_cache:
                self._trace_cache[number] = load_case_trace(
                    self.directory, number, self._trace_sources[number])
            trace, status = self._trace_cache[number]
            selected.append({**case, 'similarity': float(scores[i]),
                             'revision_trace': trace, 'trace_status': status})
        return selected

    def retrieve_examples(self, requirement: str) -> list[dict]:
        """Return up to three accepted generated pairs; never substitute a golden assertion."""
        if not self.examples:
            return []
        query = self.model.encode([requirement])
        scores = self._cosine_similarity(query, self.example_embeddings)[0]
        order = sorted(range(len(scores)), key=lambda i: (-float(scores[i]), self.examples[i]["case_number"]))
        return [{**self.examples[i], "similarity": float(scores[i])} for i in order[:3]]
