"""Standalone analysis: how does the diagnosis/rule knowledge bank grow with N?

Reads ONE completed training run (read-only) and writes results under
    <RUN_DIR>/cluster_eval/      (a rerun replaces the previous results)
It never modifies the run's own files, so the run can still be selected as an
inference source by main.py.

Method
  1. Extract every diagnosis and rule from learned_rules.jsonl (all rounds).
  2. Mask signal names per case (reuses new_agent/infer_rule_masking.py) so
     clusters group by error type, not by design vocabulary.
  3. Embed the masked text and cluster the FULL training pool ONCE
     (agglomerative, cosine distance, average linkage, cut at each threshold).
     Clusters are therefore fixed and comparable across subset sizes.
  4. For each subset seed, shuffle the pool once and take nested prefixes
     (first 25, first 50, ...). Measure how much of the fixed clusters each
     subset covers.

Run from anywhere:  python new_agent/cluster_eval.py   (or python cluster_eval.py)
"""

# =============================================================================
# Settings (edit here)
# =============================================================================

# Training run directory; relative paths are resolved from this file's folder.
RUN_DIR = "runs/Train_20261110_034100_935433Z_nl2sva_block"

# Nested subset sizes. The full pool size is always added as the final point.
SUBSET_SIZES = [25, 50, 100, 200, 400, 600]

# Subset seeds (independent of the experiment's SPLIT_SEED). Offline, so cheap.
SUBSET_SEEDS = list(range(10))

# Cosine-distance cut-offs (distance = 1 - cosine similarity). Several are
# reported so conclusions can be checked for robustness to this choice.
DISTANCE_THRESHOLDS = [0.3, 0.4, 0.5]
LINKAGE = "average"

# "sentence_transformers" (same family as inference retrieval) or "tfidf"
# (no model download; lexical only, for quick checks).
EMBEDDING_BACKEND = "sentence_transformers"
EMBEDDING_MODEL = "all-MiniLM-L6-v2"

# Mask signal/parameter names before embedding (strongly recommended).
MASK_SIGNALS = True
# True turns <request_signal_2> into <request_signal> so placeholders from
# different cases look alike.
DROP_PLACEHOLDER_INDEX = True

# Item types to analyse.
ITEM_TYPES = ["diagnosis", "rule"]

# Safety limit on unique texts per item type for O(n^2) clustering memory.
MAX_CLUSTER_ITEMS = 20000

# Pairs per threshold written for manual "same issue?" labelling.
THRESHOLD_CHECK_PAIRS = 40

# =============================================================================

import csv
import hashlib
import json
import random
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

SUGGESTED_CATEGORIES = (
    'Scope mismatch', 'Missing required behavior', 'Additional obligation',
    'Unjustified exemption', 'Overly broad activation',
    'Incorrect response relationship', 'Timing mismatch',
    'Incorrect context interpretation', 'Polarity or quantification mismatch',
    'Domain or boundary mismatch', 'Invalid assertion structure',
)
_CATEGORY_LOOKUP = {c.casefold(): c for c in SUGGESTED_CATEGORIES}


def normalize_category(value):
    text = (value or "").strip()
    key = re.sub(r"\s+", " ", text.replace("_", " ")).casefold()
    return _CATEGORY_LOOKUP.get(key, text or "(none)")


def log(message):
    print(message, flush=True)


# -----------------------------------------------------------------------------
# 1. Load the run
# -----------------------------------------------------------------------------

def resolve_run_dir():
    path = Path(RUN_DIR).expanduser()
    if not path.is_absolute():
        path = (HERE / path).resolve()
    if not (path / "run_metadata.json").is_file():
        raise SystemExit(f"Not a run directory (no run_metadata.json): {path}")
    if not (path / "learned_rules.jsonl").is_file():
        raise SystemExit(f"No learned_rules.jsonl in {path}")
    return path


def load_run(run_dir):
    metadata = json.loads((run_dir / "run_metadata.json").read_text(encoding="utf-8"))
    if metadata.get("phase") != "train":
        raise SystemExit("RUN_DIR must be a training run.")
    if metadata.get("status") != "COMPLETED":
        log(f"WARNING: run status is {metadata.get('status')!r}, not COMPLETED; "
            "analysing the cases it recorded.")
    pool = [c["case_number"] for c in metadata["selected_cases"]]
    entries = {}
    for line in (run_dir / "learned_rules.jsonl").read_text(encoding="utf-8").splitlines():
        if line.strip():
            entry = json.loads(line)
            entries[entry["case_number"]] = entry
    scores = {}
    if (run_dir / "evaluation.csv").is_file():
        with (run_dir / "evaluation.csv").open(encoding="utf-8", newline="") as file:
            for row in csv.DictReader(file):
                scores[int(row["case_number"])] = row
    return metadata, pool, entries, scores


def load_testbenches(metadata):
    """Testbench text per case for masking; empty dict if unavailable."""
    try:
        from new_agent import dataset_loader
        path = metadata.get("dataset_path")
        actual = hashlib.sha256(Path(path).read_bytes()).hexdigest()
        if actual != metadata.get("dataset_sha256"):
            log("WARNING: dataset CSV changed since training; testbench masking may differ.")
        return {c["case_number"]: c.get("testbench", "") for c in dataset_loader.read_dataset(path)}
    except Exception as error:  # masking still works from assertions/requirements
        log(f"WARNING: could not load testbenches ({error}); masking uses assertions only.")
        return {}


# -----------------------------------------------------------------------------
# 2. Extract items
# -----------------------------------------------------------------------------

def extract_items(pool, entries):
    """One row per diagnosis/rule occurrence, keeping duplicates across rounds."""
    items = []
    for case_number in pool:
        entry = entries.get(case_number)
        if entry is None:
            continue
        design = entry.get("design_name", "")
        rounds = [r for r in entry.get("round_evidence") or [] if isinstance(r, dict)]
        seen_diag, seen_rule = set(), set()
        if rounds:
            for evidence in rounds:
                block = evidence.get("tree_rule_diagnosis") or {}
                number = evidence.get("round")
                categories = sorted({normalize_category(d.get("category"))
                                     for d in block.get("diagnoses") or [] if isinstance(d, dict)})
                for d in block.get("diagnoses") or []:
                    if not isinstance(d, dict) or not (d.get("statement") or "").strip():
                        continue
                    category = normalize_category(d.get("category"))
                    key = (category, d["statement"].strip())
                    items.append(dict(type="diagnosis", case_number=case_number, design=design,
                                      round=number, category=category, categories=[category],
                                      text=d["statement"].strip(), location="",
                                      repeat_in_case=key in seen_diag))
                    seen_diag.add(key)
                for c in block.get("corrections") or []:
                    if not isinstance(c, dict) or not (c.get("rule") or "").strip():
                        continue
                    text = c["rule"].strip()
                    items.append(dict(type="rule", case_number=case_number, design=design,
                                      round=number, category="", categories=categories,
                                      text=text, location=(c.get("location") or "").strip(),
                                      repeat_in_case=text in seen_rule))
                    seen_rule.add(text)
        else:  # fall back to the case-level registries
            for d in entry.get("diagnoses") or []:
                if isinstance(d, dict) and (d.get("statement") or "").strip():
                    category = normalize_category(d.get("category"))
                    items.append(dict(type="diagnosis", case_number=case_number, design=design,
                                      round=None, category=category, categories=[category],
                                      text=d["statement"].strip(), location="",
                                      repeat_in_case=False))
            for rule_id, text in (entry.get("rules") or {}).items():
                if isinstance(text, str) and text.strip():
                    items.append(dict(type="rule", case_number=case_number, design=design,
                                      round=(entry.get("rule_rounds") or {}).get(rule_id),
                                      category="", categories=[], text=text.strip(),
                                      location=(entry.get("rule_locations") or {}).get(rule_id, ""),
                                      repeat_in_case=False))
    return items


# -----------------------------------------------------------------------------
# 3. Mask
# -----------------------------------------------------------------------------

_PLACEHOLDER = re.compile(r"<([a-z_]+?)_\d+>")


def mask_items(items, entries, testbenches):
    if not MASK_SIGNALS:
        for item in items:
            item["masked"] = item["text"]
        return "disabled"
    try:
        from new_agent.infer_rule_masking import CaseMasker, source_names
    except Exception as error:
        log(f"WARNING: repo masker unavailable ({error}); using a simple identifier masker.")
        CaseMasker = source_names = None

    by_case = defaultdict(list)
    for item in items:
        by_case[item["case_number"]].append(item)
    for case_number, case_items in by_case.items():
        entry = entries[case_number]
        if CaseMasker is not None:
            context = {
                "testbench": testbenches.get(case_number, ""),
                "reference_assertion": entry.get("reference_assertion", ""),
                "_source_assertions": [r.get("generated_assertion") for r in entry.get("round_evidence") or []
                                       if isinstance(r, dict) and r.get("generated_assertion")],
            }
            descriptions = {f"item_{i}": item["text"] for i, item in enumerate(case_items)}
            masker = CaseMasker(source_names(entry.get("requirement", ""), descriptions, context))
            for item in case_items:
                item["masked"] = masker.mask(item["text"])
        else:
            for item in case_items:
                item["masked"] = re.sub(r"`[^`]+`", "`<expr>`",
                                        re.sub(r"\b[A-Za-z]\w*_\w+\b", "<signal>", item["text"]))
        if DROP_PLACEHOLDER_INDEX:
            for item in case_items:
                item["masked"] = _PLACEHOLDER.sub(r"<\1>", item["masked"])
    return "repo_masker" if CaseMasker is not None else "simple_fallback"


# -----------------------------------------------------------------------------
# 4. Embed and cluster (full pool, once)
# -----------------------------------------------------------------------------

def embed(texts, cache_dir):
    key = hashlib.sha256(json.dumps([EMBEDDING_BACKEND, EMBEDDING_MODEL, texts]).encode()).hexdigest()[:16]
    cache = cache_dir / f"embeddings_{EMBEDDING_BACKEND}_{key}.npy"
    if cache.is_file():
        return np.load(cache)
    if EMBEDDING_BACKEND == "sentence_transformers":
        from sentence_transformers import SentenceTransformer
        model = SentenceTransformer(EMBEDDING_MODEL)
        vectors = model.encode(texts, batch_size=64, show_progress_bar=True,
                               normalize_embeddings=True, convert_to_numpy=True)
    elif EMBEDDING_BACKEND == "tfidf":
        from sklearn.feature_extraction.text import TfidfVectorizer
        vectors = TfidfVectorizer(ngram_range=(1, 2), min_df=1).fit_transform(texts).toarray()
    else:
        raise SystemExit(f"Unknown EMBEDDING_BACKEND {EMBEDDING_BACKEND!r}")
    vectors = np.asarray(vectors, dtype=np.float64)
    cache_dir.mkdir(parents=True, exist_ok=True)
    np.save(cache, vectors)
    return vectors


def cluster(vectors):
    """Return {threshold: labels} and the condensed distance matrix."""
    from scipy.cluster.hierarchy import fcluster, linkage
    from scipy.spatial.distance import pdist
    if len(vectors) == 1:
        return {t: np.array([1]) for t in DISTANCE_THRESHOLDS}, np.zeros(0)
    distances = pdist(vectors, metric="cosine")
    distances = np.nan_to_num(np.clip(distances, 0.0, 2.0), nan=1.0)
    tree = linkage(distances, method=LINKAGE)
    return {t: fcluster(tree, t=t, criterion="distance") for t in DISTANCE_THRESHOLDS}, distances


def condensed_index(i, j, n):
    if i > j:
        i, j = j, i
    return n * i - i * (i + 1) // 2 + (j - i - 1)


# -----------------------------------------------------------------------------
# 5. Subset metrics
# -----------------------------------------------------------------------------

def subset_metrics(item_mask, items_case, items_cluster, items_cats, items_repeat,
                   full_sizes, total_items, subset):
    selected = np.flatnonzero(item_mask)
    clusters = items_cluster[selected]
    counts = Counter(clusters.tolist())
    covered = set(counts)
    cats = Counter(c for i in selected for c in items_cats[i])
    clusters_per_cat = defaultdict(set)
    for i in selected:
        for c in items_cats[i]:
            clusters_per_cat[c].add(items_cluster[i])
    raw = len(selected)
    return {
        "cases": len(subset),
        "cases_with_items": len(set(items_case[selected].tolist())),
        "raw_items": raw,
        "bank_items": int((~items_repeat[selected]).sum()),
        "categories": len(cats),
        "clusters_covered": len(covered),
        "cluster_fraction": len(covered) / len(full_sizes) if full_sizes else 0.0,
        "weighted_coverage": (sum(full_sizes[c] for c in covered) / total_items) if total_items else 0.0,
        "singleton_rate": (sum(1 for v in counts.values() if v == 1) / raw) if raw else 0.0,
        "mean_clusters_per_category": (float(np.mean([len(v) for v in clusters_per_cat.values()]))
                                       if clusters_per_cat else 0.0),
    }


METRICS = ["raw_items", "bank_items", "categories", "clusters_covered", "cluster_fraction",
           "weighted_coverage", "singleton_rate", "mean_clusters_per_category",
           "new_clusters_per_100_cases"]


# -----------------------------------------------------------------------------
# 6. Outputs
# -----------------------------------------------------------------------------

def write_csv(path, rows, fields=None):
    rows = list(rows)
    fields = fields or (list(rows[0]) if rows else [])
    with path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def plot_curves(summary, out_dir):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as error:
        log(f"Skipping plots ({error}).")
        return
    for item_type in ITEM_TYPES:
        shown = ["raw_items", "clusters_covered", "weighted_coverage",
                 "singleton_rate", "new_clusters_per_100_cases", "mean_clusters_per_category"]
        fig, axes = plt.subplots(2, 3, figsize=(15, 8))
        for ax, metric in zip(axes.flat, shown):
            for threshold in DISTANCE_THRESHOLDS:
                rows = sorted((r for r in summary if r["item_type"] == item_type
                               and r["threshold"] == threshold), key=lambda r: r["n"])
                if not rows:
                    continue
                x = [r["n"] for r in rows]
                mean = np.array([r[f"{metric}_mean"] for r in rows], dtype=float)
                std = np.array([r[f"{metric}_std"] for r in rows], dtype=float)
                ax.plot(x, mean, marker="o", label=f"d≤{threshold}")
                ax.fill_between(x, mean - std, mean + std, alpha=0.2)
            ax.set_title(metric)
            ax.set_xlabel("training cases (N)")
            ax.grid(alpha=0.3)
        axes.flat[0].legend()
        fig.suptitle(f"{item_type}: knowledge-bank growth (mean ± std over {len(SUBSET_SEEDS)} seeds)")
        fig.tight_layout()
        fig.savefig(out_dir / f"curves_{item_type}.png", dpi=150)
        plt.close(fig)


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main():
    run_dir = resolve_run_dir()
    # One result folder per training run; a rerun replaces the previous results
    # (old files are removed so stale thresholds do not linger). The embedding
    # cache in cluster_eval/cache/ is kept to make reruns fast.
    out_dir = out_root = run_dir / "cluster_eval"
    out_dir.mkdir(exist_ok=True)
    for old in out_dir.iterdir():
        if old.is_file():
            old.unlink()
    log(f"Run:    {run_dir}\nOutput: {out_dir}")

    metadata, pool, entries, scores = load_run(run_dir)
    missing = [c for c in pool if c not in entries]
    log(f"Training pool: {len(pool)} cases; {len(pool) - len(missing)} have learned_rules entries.")

    items = extract_items(pool, entries)
    masking = mask_items(items, entries, load_testbenches(metadata))
    log(f"Extracted {sum(i['type'] == 'diagnosis' for i in items)} diagnoses and "
        f"{sum(i['type'] == 'rule' for i in items)} rules (masking: {masking}).")

    sizes = sorted({n for n in SUBSET_SIZES if n < len(pool)} | {len(pool)})
    orders = {seed: random.Random(seed).sample(sorted(pool), len(pool)) for seed in SUBSET_SEEDS}

    # Per-case statistics
    per_case = Counter((i["case_number"], i["type"]) for i in items)
    case_rows = []
    for c in pool:
        e, s = entries.get(c, {}), scores.get(c, {})
        case_rows.append({
            "case_number": c, "design_name": e.get("design_name", s.get("design_name", "")),
            "in_learned_rules": c in entries, "passed": e.get("passed", s.get("passed")),
            "rounds_used": s.get("rounds_used", ""), "stop_reason": s.get("stop_reason", ""),
            "diagnoses": per_case[(c, "diagnosis")], "rules": per_case[(c, "rule")],
        })
    write_csv(out_dir / "case_stats.csv", case_rows)

    cat_counts, cat_cases = Counter(), defaultdict(set)
    for i in items:
        if i["type"] == "diagnosis":
            cat_counts[i["category"]] += 1
            cat_cases[i["category"]].add(i["case_number"])
    write_csv(out_dir / "category_counts.csv", [
        {"category": c, "count": n, "cases": len(cat_cases[c]), "suggested": c in SUGGESTED_CATEGORIES}
        for c, n in cat_counts.most_common()])

    raw_rows, report_lines = [], []
    full_cluster_counts = {}
    for item_type in ITEM_TYPES:
        typed = [i for i in items if i["type"] == item_type]
        if not typed:
            log(f"No {item_type} items; skipping.")
            continue
        unique = sorted({i["masked"] for i in typed})
        if len(unique) > MAX_CLUSTER_ITEMS:
            raise SystemExit(f"{len(unique)} unique {item_type} texts exceed MAX_CLUSTER_ITEMS.")
        log(f"[{item_type}] embedding {len(unique)} unique masked texts ...")
        vectors = embed(unique, out_root / "cache")
        log(f"[{item_type}] clustering ...")
        labels_by_t, distances = cluster(vectors)
        index_of = {text: k for k, text in enumerate(unique)}
        text_idx = np.array([index_of[i["masked"]] for i in typed])
        items_case = np.array([i["case_number"] for i in typed])
        items_cats = [i["categories"] for i in typed]
        items_repeat = np.array([i["repeat_in_case"] for i in typed])
        case_index = defaultdict(list)
        for k, i in enumerate(typed):
            case_index[i["case_number"]].append(k)

        for threshold, labels in labels_by_t.items():
            items_cluster = labels[text_idx]
            for k, i in enumerate(typed):
                i[f"cluster_d{threshold}"] = int(items_cluster[k])
            full_sizes = Counter(items_cluster.tolist())
            full_cluster_counts[(item_type, threshold)] = len(full_sizes)

            # Cluster descriptions on the full pool
            members = defaultdict(list)
            for k, cid in enumerate(items_cluster):
                members[int(cid)].append(k)
            cluster_rows = []
            for cid, ks in sorted(members.items(), key=lambda kv: -len(kv[1])):
                texts = sorted({text_idx[k] for k in ks})
                centroid = vectors[texts].mean(axis=0)
                norms = np.linalg.norm(vectors[texts], axis=1) * (np.linalg.norm(centroid) or 1)
                sims = (vectors[texts] @ centroid) / np.where(norms == 0, 1, norms)
                reps = [unique[texts[j]] for j in np.argsort(-sims)[:3]]
                cats = Counter(c for k in ks for c in typed[k]["categories"])
                cluster_rows.append({
                    "cluster_id": cid, "size": len(ks), "unique_texts": len(texts),
                    "cases": len({typed[k]["case_number"] for k in ks}),
                    "designs": len({typed[k]["design"] for k in ks}),
                    "top_categories": "; ".join(f"{c} ({n})" for c, n in cats.most_common(3)),
                    "example_1": reps[0], "example_2": reps[1] if len(reps) > 1 else "",
                    "example_3": reps[2] if len(reps) > 2 else "",
                })
            write_csv(out_dir / f"clusters_{item_type}_d{threshold}.csv", cluster_rows)
            singletons = sum(1 for v in full_sizes.values() if v == 1)
            report_lines.append(
                f"| {item_type} | {threshold} | {len(typed)} | {len(unique)} | {len(full_sizes)} | "
                f"{singletons} | {cluster_rows[0]['size']} |")

            # Nested subsets
            for seed, order in orders.items():
                previous = None
                for n in sizes:
                    subset = order[:n]
                    mask = np.zeros(len(typed), dtype=bool)
                    for c in subset:
                        mask[case_index.get(c, [])] = True
                    row = {"item_type": item_type, "threshold": threshold, "seed": seed, "n": n}
                    row.update(subset_metrics(mask, items_case, items_cluster, items_cats,
                                              items_repeat, full_sizes, len(typed), subset))
                    if previous is None:
                        row["new_clusters_per_100_cases"] = row["clusters_covered"] / n * 100
                    else:
                        row["new_clusters_per_100_cases"] = ((row["clusters_covered"] - previous["clusters_covered"])
                                                             / (n - previous["n"]) * 100)
                    raw_rows.append(row)
                    previous = row

        # Pairs near each threshold, for manual labelling
        if len(unique) > 2 and THRESHOLD_CHECK_PAIRS:
            rng = np.random.default_rng(0)
            pair_rows, n_u = [], len(unique)
            for threshold in DISTANCE_THRESHOLDS:
                near = np.flatnonzero(np.abs(distances - threshold) <= 0.03)
                for flat in rng.choice(near, size=min(THRESHOLD_CHECK_PAIRS, len(near)), replace=False):
                    i = int(np.searchsorted(np.cumsum(np.arange(n_u - 1, 0, -1)), flat, side="right"))
                    j = int(flat - condensed_index(i, i + 1, n_u) + i + 1)
                    pair_rows.append({"threshold": threshold, "distance": round(float(distances[flat]), 4),
                                      "text_a": unique[i], "text_b": unique[j], "same_issue (fill y/n)": ""})
            write_csv(out_dir / f"threshold_check_{item_type}.csv", pair_rows,
                      ["threshold", "distance", "text_a", "text_b", "same_issue (fill y/n)"])

    write_csv(out_dir / "items.csv", items,
              ["type", "case_number", "design", "round", "category", "categories", "repeat_in_case",
               "location", "text", "masked"] + [f"cluster_d{t}" for t in DISTANCE_THRESHOLDS])
    write_csv(out_dir / "curves_raw.csv", raw_rows)

    # Mean/std/min/max across seeds
    grouped = defaultdict(list)
    for row in raw_rows:
        grouped[(row["item_type"], row["threshold"], row["n"])].append(row)
    summary = []
    for (item_type, threshold, n), rows in sorted(grouped.items()):
        out = {"item_type": item_type, "threshold": threshold, "n": n, "seeds": len(rows)}
        for metric in METRICS:
            values = np.array([r[metric] for r in rows], dtype=float)
            out[f"{metric}_mean"] = round(float(values.mean()), 4)
            out[f"{metric}_std"] = round(float(values.std(ddof=1)) if len(values) > 1 else 0.0, 4)
            out[f"{metric}_min"] = round(float(values.min()), 4)
            out[f"{metric}_max"] = round(float(values.max()), 4)
        summary.append(out)
    write_csv(out_dir / "curves_summary.csv", summary)
    plot_curves(summary, out_dir)

    settings = {k: globals()[k] for k in (
        "RUN_DIR", "SUBSET_SIZES", "SUBSET_SEEDS", "DISTANCE_THRESHOLDS", "LINKAGE",
        "EMBEDDING_BACKEND", "EMBEDDING_MODEL", "MASK_SIGNALS", "DROP_PLACEHOLDER_INDEX",
        "ITEM_TYPES", "THRESHOLD_CHECK_PAIRS")}
    settings.update(resolved_run_dir=str(run_dir), masking=masking, pool_size=len(pool),
                    subset_sizes_used=sizes, cases_missing_learned_rules=missing,
                    learned_rules_sha256=hashlib.sha256((run_dir / "learned_rules.jsonl").read_bytes()).hexdigest(),
                    created_at=datetime.now().isoformat(timespec="seconds"))
    (out_dir / "config.json").write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")

    zero = sum(1 for r in case_rows if r["diagnoses"] == 0)
    off_list = sum(n for c, n in cat_counts.items() if c not in SUGGESTED_CATEGORIES)
    total_diag = sum(cat_counts.values())
    full_n = sizes[-1]
    lines = [
        f"# Cluster evaluation: {run_dir.name}", "",
        f"- Training pool: {len(pool)} cases ({len(missing)} missing from learned_rules.jsonl)",
        f"- Cases with no diagnoses (e.g. passed in round 1): {zero}",
        f"- Diagnoses: {total_diag}; off-list categories: {off_list} "
        f"({off_list / total_diag:.1%} of diagnoses)" if total_diag else "- Diagnoses: 0",
        f"- Masking: {masking}; embedding: {EMBEDDING_BACKEND}/{EMBEDDING_MODEL}; linkage: {LINKAGE}",
        f"- Subset sizes: {sizes}; seeds: {len(SUBSET_SEEDS)}", "",
        "## Full-pool clusters", "",
        "| type | distance ≤ | items | unique texts | clusters | singleton clusters | largest |",
        "|---|---|---|---|---|---|---|", *report_lines, "",
        "## Weighted coverage by N (mean ± std across seeds)", "",
        "| type | distance ≤ | " + " | ".join(f"N={n}" for n in sizes) + " |",
        "|---|---|" + "---|" * len(sizes),
    ]
    for item_type in ITEM_TYPES:
        for threshold in DISTANCE_THRESHOLDS:
            rows = {r["n"]: r for r in summary if r["item_type"] == item_type and r["threshold"] == threshold}
            if rows:
                lines.append(f"| {item_type} | {threshold} | " + " | ".join(
                    f"{rows[n]['weighted_coverage_mean']:.3f} ± {rows[n]['weighted_coverage_std']:.3f}"
                    for n in sizes) + " |")
    lines += ["", f"At N={full_n} coverage is 1.0 by construction (clusters are defined on the full pool).",
              "Check threshold_check_*.csv and clusters_*.csv by eye before trusting the curves."]
    (out_dir / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    log(f"Done. See {out_dir / 'report.md'}")


if __name__ == "__main__":
    main()
