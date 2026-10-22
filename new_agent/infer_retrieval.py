"""A frozen training-rule bank ranked by natural-language requirement similarity."""

import hashlib
import json
from pathlib import Path


class RuleRetriever:
    """Read one resolved run once; encode its eligible requirements once on CPU."""

    def __init__(self, training_run_dir, *, training_case_ids, top_k: int, model_name: str):
        self.directory = Path(training_run_dir).resolve()
        self.top_k = top_k
        path = self.directory / "learned_rules.jsonl"
        data = path.read_bytes()
        self.sha256 = hashlib.sha256(data).hexdigest()
        self.cases = []
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
            groups = case.get("rule_groups", {})
            if not isinstance(groups, dict):
                raise ValueError(f"Invalid rule_groups for case {number}.")
            # Only these fields can later enter inference prompts. References,
            # saved assertions, formal logs, and arbitrary JSON fields are excluded.
            self.cases.append({
                "case_number": number, "design_name": case.get("design_name"),
                "task_id": case.get("task_id"), "requirement": requirement.strip(),
                "passed": case.get("passed"), "rules": rules,
                "rule_groups": {key: groups.get(key, []) for key in rules},
            })
        if not self.cases:
            raise ValueError(f"No cases with nonempty requirements and rules in {path}.")
        # Training mode does not import or load the embedding dependency.
        from sentence_transformers import SentenceTransformer
        from sklearn.metrics.pairwise import cosine_similarity
        self._cosine_similarity = cosine_similarity
        self.model = SentenceTransformer(model_name, device="cpu")
        self.embeddings = self.model.encode([c["requirement"] for c in self.cases])

    def retrieve(self, requirement: str) -> list[dict]:
        """Rank eligible cases before selecting up to top_k; keep ties deterministic."""
        query = self.model.encode([requirement])
        scores = self._cosine_similarity(query, self.embeddings)[0]
        order = sorted(range(len(scores)), key=lambda i: (-float(scores[i]), self.cases[i]["case_number"]))
        return [{**self.cases[i], "similarity": float(scores[i])}
                for i in order[:self.top_k]]
