"""Separate example and rule indexes for one selected training run."""

import hashlib
import json
from pathlib import Path


class RuleRetriever:
    """Share one embedding model; rank training examples and rule cases separately."""

    def __init__(self, training_run_dir, *, training_case_ids, training_cases,
                 top_k: int, model_name: str):
        self.directory = Path(training_run_dir).resolve()
        self.top_k = top_k
        # Private training source context used only to discover names for masking.
        # These dictionaries are never serialized into inference model prompts.
        self.masking_contexts = {case["case_number"]: case for case in training_cases}
        # Examples come from the source run's complete selected training pool in
        # the verified CSV, independently of rule availability or generation success.
        self.examples = [{
            "case_number": case["case_number"],
            "requirement": case["requirement"],
            "reference_assertion": case["reference_assertion"],
        } for case in training_cases]
        if (not self.examples or len({c["case_number"] for c in self.examples}) != len(self.examples)
                or {c["case_number"] for c in self.examples} != set(training_case_ids)):
            raise ValueError("Example pool must contain exactly the selected training cases.")
        if any(not isinstance(case[key], str) or not case[key].strip()
               for case in self.examples for key in ("requirement", "reference_assertion")):
            raise ValueError("Every training example needs a requirement and reference assertion.")
        path = self.directory / "learned_rules.jsonl"
        data = path.read_bytes()
        self.sha256 = hashlib.sha256(data).hexdigest()
        self.cases = []
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
            # Only these fields can later enter inference prompts. References,
            # assertions and scores below belong only to selected TRAINING cases.
            # Tool logs, runtime prompts and arbitrary JSON fields stay excluded.
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
                "reference_assertion": case.get("reference_assertion"),
                "rule_rounds": {key: case.get("rule_rounds", {}).get(key) for key in rules},
                "round_evidence": round_evidence,
            })
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
        """Return up to three training pairs, regardless of their rules or pass status."""
        query = self.model.encode([requirement])
        scores = self._cosine_similarity(query, self.example_embeddings)[0]
        order = sorted(range(len(scores)), key=lambda i: (-float(scores[i]), self.examples[i]["case_number"]))
        return [{**self.examples[i], "similarity": float(scores[i])} for i in order[:3]]
