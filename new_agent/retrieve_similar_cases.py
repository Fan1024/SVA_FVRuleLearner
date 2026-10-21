"""Retrieve up to five rule-bearing cases by requirement cosine similarity."""

import json
from pathlib import Path

from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity


# Choose the training run manually here. Config integration comes later.
TRAINING_RUN_DIR = (
    Path(__file__).resolve().parent
    / "runs"
    / "Train_20261020_183618_421104Z_nl2sva_human"
)
TOP_K = 5

# Same fixed requirement as the standalone inference diagnosis example.
requirement = (
    "Whenever a is high at a rising edge of clk, b must be high two rising "
    "clock edges later. Disable this check while rst_n is low."
)


def retrieve_similar_cases(requirement, training_run_dir=TRAINING_RUN_DIR, top_k=TOP_K):
    """Return ranked case records, including their rules, groups and similarity."""
    cases = []
    with (Path(training_run_dir) / "learned_rules.jsonl").open(encoding="utf-8") as file:
        for line in file:
            if not line.strip():
                continue
            case = json.loads(line)
            rules = case.get("rules") or {}
            if not any(isinstance(rule, str) and rule.strip() for rule in rules.values()):
                continue
            if not case.get("requirement", "").strip():
                continue
            cases.append(case)

    if not cases:
        raise ValueError("No cases with nonempty rules and requirements found.")

    model = SentenceTransformer("all-MiniLM-L6-v2", device="cpu")
    texts = [requirement] + [case["requirement"] for case in cases]
    embeddings = model.encode(texts, show_progress_bar=False)
    scores = cosine_similarity(embeddings[:1], embeddings[1:])[0]

    ranked_indices = sorted(
        range(len(cases)), key=lambda index: float(scores[index]), reverse=True
    )
    return [
        {**cases[index], "similarity": float(scores[index])}
        for index in ranked_indices[:top_k]
    ]


if __name__ == "__main__":
    for case in retrieve_similar_cases(requirement):
        print(case["case_number"])
