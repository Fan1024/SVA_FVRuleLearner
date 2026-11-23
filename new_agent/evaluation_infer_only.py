#!/usr/bin/env python3
"""Score the whole dataset and training-compatible held-out inference_only subset.

Usage:
  python evaluation_infer_only.py /path/to/InferenceOnly_run --seed 100
  python evaluation_infer_only.py /path/to/InferenceOnly_run --seed 100 \
      --training-run /path/to/Train_run

Python standard library only. No LLM requests, Jasper launches, or config edits.
Reads run_metadata.json, evaluation.csv, and optional cases/*/result.json.
The default split exactly reproduces dataset_loader.split_cases: shuffle CSV-
ordered eligible cases with random.Random(seed), hold out the first
int(N * round(1 - train_fraction, 12)) shuffled positions, restore CSV order.
The full eligible universe comes from the inference_only run's selected_cases,
not from its possibly incomplete evaluation.csv. Explicit CASE_IDS are rejected.

--training-run uses the saved training selection's exact complement instead of
guessing a split; dataset hashes and saved case identities must match. For an
ordinary seeded training run, the seed, fraction and held-out IDs are also checked.
Metric values follow the pipeline's reported pec/relax_pec score policy (including
any acceptance-policy overrides); this is not a fresh native PEC recheck.
All attempts, including generation/API failures, count toward the round budget.
Missing rows stay in the denominator. Incomplete round histories produce bounds,
not invented exact rates. Writes one file in the input run evaluation/ directory:
infer_only_evaluation.csv. Four rows cover whole_dataset and test_subset at
pass@1 and pass@5, with strict and relaxed PEC in separate columns. Other budgets
can be requested with --budgets. Reruns replace only this derived report; original
experiment files are never modified. The evaluation/ output subdirectory is created if needed.
"""

import argparse
import csv
import hashlib
import json
import math
import random
import sys
from pathlib import Path


def read_json(path):
    with path.open(encoding="utf-8-sig") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def positive_int(value, label):
    if isinstance(value, bool):
        raise ValueError(f"Invalid {label}: {value!r}")
    number = int(value)
    if str(number) != str(value) or number < 1:
        raise ValueError(f"Invalid {label}: {value!r}")
    return number


def identities(cases, label):
    if not isinstance(cases, list) or not cases:
        raise ValueError(f"{label}: selected_cases must be a nonempty list.")
    result = {}
    for case in cases:
        number = positive_int(case.get("case_number"), "case_number")
        if number in result:
            raise ValueError(f"{label}: duplicate case {number}.")
        if not case.get("design_name") or not case.get("task_id"):
            raise ValueError(f"{label}: case {number} has no design/task identity.")
        result[number] = case
    return result


def same_identity(a, b):
    return all(a.get(key) == b.get(key) for key in ("design_name", "task_id"))


def split_ids(universe, seed, train_fraction):
    """Same operations and float rounding as new_agent.dataset_loader."""
    ordered = sorted(universe)
    count = int(len(ordered) * round(1 - train_fraction, 12))
    if not 1 <= count < len(ordered):
        raise ValueError("The requested fraction leaves an empty training/test split.")
    positions = list(range(len(ordered)))
    random.Random(seed).shuffle(positions)
    chosen = set(positions[:count])
    return [number for index, number in enumerate(ordered) if index in chosen]


def select_subset(metadata, args):
    settings = metadata.get("settings") or {}
    if metadata.get("phase", settings.get("phase")) != "inference_only":
        raise ValueError("The input directory must be an inference_only experiment.")
    # These fields establish that selected_cases is the full eligible universe.
    requested = settings.get("requested_case_ids")
    selection = settings.get("inference_case_selection")
    if requested or (requested is None and selection != "explicit_ids_or_entire_dataset_no_split"):
        raise ValueError("Cannot establish a full-dataset run: explicit/unknown CASE_IDS. "
                         "Use an inference_only run saved with CASE_IDS=[].")
    universe = identities(metadata.get("selected_cases"), "Inference-only metadata")
    predicted = split_ids(universe, args.seed, args.train_fraction)
    source = "reconstructed_fvrulelearner_test_first_shuffle"
    if args.training_run:
        train = read_json(args.training_run / "run_metadata.json")
        if train.get("phase") != "train":
            raise ValueError("--training-run must identify a training experiment.")
        if not metadata.get("dataset_sha256") or not train.get("dataset_sha256"):
            raise ValueError("Both runs must record dataset_sha256 for exact verification.")
        if (train.get("dataset") != metadata.get("dataset") or
                train["dataset_sha256"] != metadata["dataset_sha256"]):
            raise ValueError("Training and baseline dataset name/CSV hash differ.")
        training = identities(train.get("selected_cases"), "Training metadata")
        for number, saved in training.items():
            current = universe.get(number)
            if current is None or not same_identity(saved, current):
                raise ValueError(f"Training identity mismatch at case {number}.")
            if saved.get("testbench_sha256") != current.get("testbench_sha256"):
                raise ValueError(f"Training/baseline testbench hash differs at case {number}.")
        selected = sorted(set(universe) - set(training))
        if not selected:
            raise ValueError("Training selected every case; there is no test subset.")
        saved_split = (train.get("settings") or {}).get("dataset_split")
        if saved_split:
            if saved_split.get("method") != "fvrulelearner_test_first_shuffle":
                raise ValueError("Training used a different split algorithm.")
            if (saved_split.get("seed") != args.seed or not math.isclose(
                    float(saved_split["train_fraction"]), args.train_fraction, abs_tol=1e-12)):
                raise ValueError("Seed/train fraction disagree with the training run.")
            if selected != predicted or set(saved_split["inference_case_ids"]) != set(selected):
                raise ValueError("Reconstructed split disagrees with saved training IDs.")
            source = "verified_against_saved_training_split"
        else:
            source = "saved_training_selection_complement_explicit_ids"
            print("NOTE: Training used explicit IDs; using their exact complement. "
                  "The seed does not define that selection.", file=sys.stderr)
    else:
        selected = predicted
    return universe, selected, source


def score(value):
    if value is None or value == "":
        return None
    number = float(value)
    if number not in (0.0, 1.0):
        raise ValueError(f"Expected binary metric, found {value!r}")
    return int(number)


def case_evidence(run, saved, row, warnings):
    number = saved["case_number"]
    evidence = {}
    complete_through = 0
    directory = saved.get("directory") or f"cases/case_{number:04d}"
    case_path = (run / directory).resolve()
    if not case_path.is_relative_to(run):
        raise ValueError(f"Case {number}: metadata directory escapes the run.")
    path = case_path / "result.json"
    if path.is_file():
        record = read_json(path)
        inputs = record.get("inputs") or {}
        # run_io.final_record keeps task_id in top-level case_id, not inputs.
        # Accept inputs.task_id as well for older/full-record exports, and
        # reject conflicting identities rather than silently ignoring them.
        if (positive_int(inputs.get("case_number"), "result case_number") != number
                or inputs.get("design_name") != saved["design_name"]):
            raise ValueError(f"Case {number}: result.json case number/design mismatch.")
        task_ids = [value for value in (record.get("case_id"), inputs.get("task_id"))
                    if value is not None]
        if not task_ids or any(str(value) != str(saved["task_id"]) for value in task_ids):
            raise ValueError(f"Case {number}: result.json task identity mismatch "
                             f"(expected {saved['task_id']!r}, found {task_ids!r}).")
        metrics = record.get("round_metrics")
        if isinstance(metrics, list) and metrics:
            for entry in metrics:
                r = positive_int(entry.get("round"), "round")
                if r in evidence:
                    raise ValueError(f"Case {number}: duplicate recorded round {r}.")
                evidence[r] = {key: score(entry.get(key)) for key in ("pec", "relax_pec")}
            last = positive_int(record.get("last_evaluated_round"), "last_evaluated_round")
            if sorted(evidence) == list(range(1, last + 1)):
                complete_through = last
            else:
                warnings.append(f"Case {number}: incomplete round_metrics; reporting bounds where needed.")
    if row:
        last = positive_int(row.get("last_evaluated_round"), "last_evaluated_round")
        last_scores = {key: score(row.get(key)) for key in ("pec", "relax_pec")}
        if evidence and (last != max(evidence) or evidence[last] != last_scores):
            raise ValueError(f"Case {number}: evaluation.csv and result.json disagree.")
        evidence.setdefault(last, last_scores)
        if last == 1:
            complete_through = max(complete_through, 1)
    return evidence, complete_through


def bounds(evidence, complete_through, metric, budget, args):
    if any(values[metric] == 1 for r, values in evidence.items() if r <= budget):
        return 1, 1
    if complete_through >= budget:
        return 0, 0
    # A known strict pass terminates baseline sampling, so all later budgets
    # are known once the complete prefix through that passing attempt exists.
    if any(r <= complete_through and values["pec"] == 1
           for r, values in evidence.items()):
        return 0, 0
    # Legacy final-only summaries can establish absence of an earlier strict
    # success ONLY under their pipeline's immediate-stop-on-strict-pass policy.
    if metric == "pec" and evidence and args.assume_stop_on_strict_pass:
        return 0, 0
    return 0, 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_directory", type=Path)
    parser.add_argument("--seed", type=int, default=100)
    parser.add_argument("--train-fraction", type=float, default=0.8)
    parser.add_argument("--training-run", type=Path,
                        help="Optional exact Train directory; checks saved split and dataset hashes.")
    parser.add_argument("--budgets", type=int, nargs="+", default=[1, 5])
    parser.add_argument("--assume-stop-on-strict-pass", action="store_true",
                        help="Allow exact strict rates from final-only legacy summaries. "
                             "Use only if the run stopped immediately on strict success.")
    args = parser.parse_args(argv)
    if args.seed < 0 or not math.isfinite(args.train_fraction) or not 0 < args.train_fraction < 1:
        parser.error("seed must be nonnegative; train fraction must be between 0 and 1.")
    if not args.budgets or min(args.budgets) < 1:
        parser.error("budgets must be positive integers.")
    args.budgets = sorted(set(args.budgets))
    run = args.run_directory.expanduser().resolve()
    if args.training_run:
        args.training_run = args.training_run.expanduser().resolve()
    metadata = read_json(run / "run_metadata.json")
    universe, selected, source = select_subset(metadata, args)
    evaluation_path = run / "evaluation.csv"
    with evaluation_path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields = reader.fieldnames
        required = {"case_number", "design_name", "task_id", "last_evaluated_round", "pec", "relax_pec"}
        if not fields or not required <= set(fields):
            raise ValueError("evaluation.csv is missing required columns.")
        rows = {}
        for row in reader:
            number = positive_int(row["case_number"], "case_number")
            if number in rows or number not in universe or not same_identity(row, universe[number]):
                raise ValueError(f"Duplicate, excluded, or mismatched evaluation case {number}.")
            rows[number] = row
    warnings = []
    missing = [number for number in sorted(universe) if number not in rows]
    if missing:
        warnings.append(f"Missing evaluation rows retained in denominator: {missing}")
    scopes = {"whole_dataset": sorted(universe), "test_subset": selected}
    evidence_by_case = {
        number: case_evidence(run, universe[number], rows.get(number), warnings)
        for number in sorted(universe)
    }
    summary = []
    for scope, numbers in scopes.items():
        n = len(numbers)
        for metric in ("pec", "relax_pec"):
            for budget in args.budgets:
                low = high = 0
                for number in numbers:
                    evidence, complete = evidence_by_case[number]
                    lower, upper = bounds(evidence, complete, metric, budget, args)
                    low += lower
                    high += upper
                exact = low == high
                display = (f"{low}/{n} ({100*low/n:.2f}%)" if exact else
                           f"{low}..{high}/{n} ({100*low/n:.2f}..{100*high/n:.2f}%; incomplete evidence)")
                summary.append({
                    "dataset": metadata.get("dataset", "unknown"),
                    "scope": scope, "metric": metric, "budget": f"pass@{budget}",
                    "result": display, "total_cases": n,
                    "passed_lower": low, "passed_upper": high,
                    "percent_lower": round(100 * low / n, 6),
                    "percent_upper": round(100 * high / n, 6), "exact": exact,
                    "missing_evaluation_rows": sum(number not in rows for number in numbers),
                    "seed": args.seed if scope == "test_subset" else "",
                    "train_fraction": args.train_fraction if scope == "test_subset" else "",
                    "selection_source": source if scope == "test_subset" else "all_eligible_cases",
                    "case_ids": " ".join(map(str, numbers)),
                    "dataset_sha256": metadata.get("dataset_sha256", ""),
                    "evaluation_sha256": hashlib.sha256(evaluation_path.read_bytes()).hexdigest(),
                    "metric_policy": "pipeline_reported_pec_and_relax_pec",
                    "assume_stop_on_strict_pass": args.assume_stop_on_strict_pass,
                })
    metric_columns = {"metric", "result", "passed_lower", "passed_upper",
                      "percent_lower", "percent_upper", "exact"}
    combined = []
    for scope in scopes:
        for budget in args.budgets:
            entries = {row["metric"]: row for row in summary
                       if row["scope"] == scope and row["budget"] == f"pass@{budget}"}
            row = {key: value for key, value in entries["pec"].items()
                   if key not in metric_columns}
            for metric, prefix in (("pec", "strict_pec"), ("relax_pec", "relaxed_pec")):
                for name in ("result", "passed_lower", "passed_upper", "percent_lower", "percent_upper", "exact"):
                    row[f"{prefix}_{name}"] = entries[metric][name]
            combined.append(row)
    out = run / "evaluation" / "infer_only_evaluation.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(combined[0]))
        writer.writeheader()
        writer.writerows(combined)
    print(f"Dataset: {metadata.get('dataset', 'unknown')} | "
          f"whole: {len(universe)} | test subset: {len(selected)} | seed: {args.seed}")
    print(f"Subset selection: {source}")
    print("\n| Scope | Metric | Strict PEC | Relaxed PEC |\n|---|---|---:|---:|")
    for scope in scopes:
        for budget in args.budgets:
            entries = {row["metric"]: row["result"] for row in summary
                       if row["scope"] == scope and row["budget"] == f"pass@{budget}"}
            print(f"| {scope} | pass@{budget} | {entries['pec']} | {entries['relax_pec']} |")
    if not args.training_run:
        print("\nSubset reconstructed from the baseline's full eligible case list. "
              "Use --training-run to verify the original split and dataset hash.")
    print("Scores use the pipeline's reported PEC policy; no formal checks were rerun.")
    for warning in warnings:
        print("WARNING: " + warning, file=sys.stderr)
    print(f"\nSaved: {out}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)

