"""Separate example and rule indexes for one selected training run."""

import csv
import hashlib
import json
import re
from math import isclose
from pathlib import Path


RETRIEVAL_REQUIREMENT_POLICY = 'behavior_without_appended_signal_hint_v1'
_SIGNAL_HINT_SUFFIX = re.compile(
    r'(?:^|(?<=[.!?]))\s*Use\s+(?:the\s+)?signals?\b.*\Z',
    re.IGNORECASE | re.MULTILINE | re.DOTALL,
)


def requirement_for_retrieval(requirement: str) -> str:
    """Drop the appended signal hint for embedding and example deduplication."""
    match = _SIGNAL_HINT_SUFFIX.search(requirement)
    if match:
        behavior = requirement[:match.start()].strip()
        if behavior:
            return behavior
    return requirement


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
    """Index accepted examples and all recorded guidance from passed cases."""

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
        self.excluded_missing_guidance_case_ids = []
        self._trace_sources = {}
        self._trace_cache = {}
        seen = set()
        from new_agent.infer_training_traces import load_case_trace
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
            requirement = source_cases[number].get("requirement")
            if not isinstance(requirement, str) or not requirement.strip():
                self.excluded_missing_guidance_case_ids.append(number)
                continue
            source = {'trace_file': case.get('trace_file'),
                      'round_evidence': case.get('round_evidence', [])}
            trace, trace_status = load_case_trace(self.directory, number, source)
            corrections = [(entry['round'], correction) for entry in trace
                           for correction in entry.get('corrections', [])]
            rules = {f'round_{entry["round"]}:correction_{index}': correction['rule']
                     for entry in trace
                     for index, correction in enumerate(entry.get('corrections', []), 1)}
            # Legacy runs may retain their rules only in the flat case registry.
            if not rules:
                rules = {key: value for key, value in case.get('rules', {}).items()
                         if isinstance(value, str) and value.strip()}
            if not rules:
                self.excluded_missing_guidance_case_ids.append(number)
                continue
            keys = list(rules)
            diagnoses = [item for entry in trace for item in entry.get('diagnoses', [])]
            if not corrections:
                diagnoses = case.get('diagnoses', [])
            self._trace_sources[number] = source
            self._trace_cache[number] = (trace, trace_status)
            self.cases.append({
                "case_number": number, "design_name": case.get("design_name"),
                "task_id": case.get("task_id"), "requirement": requirement.strip(),
                "passed": True, "rules": rules, "diagnoses": diagnoses,
                "rule_groups": {},
                "rule_diagnoses": ({key: correction.get('diagnoses', [])
                                    for key, (_, correction) in zip(keys, corrections)}
                                   if corrections else case.get('rule_diagnoses', {})),
                "rule_locations": ({key: correction['location']
                                    for key, (_, correction) in zip(keys, corrections)
                                    if correction.get('location')}
                                   if corrections else case.get('rule_locations', {})),
                "rule_rounds": ({key: number for key, (number, _) in zip(keys, corrections)}
                                if corrections else case.get('rule_rounds', {})),
                "correction_rounds": sorted({number for number, _ in corrections}),
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
            [requirement_for_retrieval(c["requirement"]) for c in self.examples + self.cases]
        )
        self.example_embeddings = embeddings[:len(self.examples)]
        self.embeddings = embeddings[len(self.examples):]

    def retrieve(self, requirement: str) -> list[dict]:
        """Rank eligible cases before selecting up to top_k; keep ties deterministic."""
        self.last_retrieval_audit = {
            'source_training_run': str(self.directory),
            'source_rule_file': str(self.directory / 'learned_rules.jsonl'),
            'embedding_requirement': requirement_for_retrieval(requirement),
            'top_k_cases': self.top_k,
            'excluded_unpassed_case_ids': list(self.excluded_unpassed_case_ids),
            'excluded_missing_guidance_case_ids': list(self.excluded_missing_guidance_case_ids),
            'ranked_cases': [],
        }
        if not self.cases:
            return []
        query = self.model.encode([requirement_for_retrieval(requirement)])
        scores = self._cosine_similarity(query, self.embeddings)[0]
        order = sorted(range(len(scores)), key=lambda i: (-float(scores[i]), self.cases[i]["case_number"]))
        self.last_retrieval_audit['ranked_cases'] = [{
            'rank': rank, 'case_number': self.cases[i]['case_number'],
            'design_name': self.cases[i].get('design_name'),
            'task_id': self.cases[i].get('task_id'),
            'similarity': float(scores[i]),
            'selected_for_rule_pool': rank <= self.top_k,
            'correction_rounds': self.cases[i]['correction_rounds'],
            'embedding_requirement': requirement_for_retrieval(self.cases[i]['requirement']),
        } for rank, i in enumerate(order, 1)]
        selected = []
        for i in order[:self.top_k]:
            case = self.cases[i]
            number = case['case_number']
            trace, status = self._trace_cache[number]
            selected.append({**case, 'similarity': float(scores[i]),
                             'revision_trace': trace, 'trace_status': status})
        return selected

    def retrieve_examples(self, requirement: str) -> list[dict]:
        """Return up to three diverse accepted pairs from the full ranked pool.

        Keep one example per numerical similarity tie, behavioral requirement and
        generated-assertion token sequence. Never fill a short pool with repeats.
        """
        if not self.examples:
            return []
        query = self.model.encode([requirement_for_retrieval(requirement)])
        scores = self._cosine_similarity(query, self.example_embeddings)[0]
        order = sorted(range(len(scores)), key=lambda i: (-float(scores[i]), self.examples[i]["case_number"]))
        from new_agent.pec_input_adapter import _tokens
        selected, seen_requirements, seen_assertions, selected_scores = [], set(), set(), []
        for i in order:
            case = self.examples[i]
            score = float(scores[i])
            requirement_key = ' '.join(requirement_for_retrieval(case['requirement']).split())
            assertion_key = tuple(token.text for token in _tokens(case['solved_assertion']))
            if (requirement_key in seen_requirements or assertion_key in seen_assertions
                    or any(isclose(score, previous, rel_tol=0.0, abs_tol=1e-8)
                           for previous in selected_scores)):
                continue
            selected.append({**case, 'similarity': score})
            seen_requirements.add(requirement_key)
            seen_assertions.add(assertion_key)
            selected_scores.append(score)
            if len(selected) == 3:
                break
        return selected



