#!/usr/bin/env python3
"""Analyze FVRuleLearner training traces and inference evaluation outputs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd


def load_csvs(paths: list[Path], label: str) -> pd.DataFrame:
    if not paths:
        raise FileNotFoundError(f"No {label} CSV files were found")
    return pd.concat([pd.read_csv(path) for path in paths], ignore_index=True)


def analyze_training(run_dir: Path) -> None:
    trace_path = run_dir / "training_traces.jsonl"
    if not trace_path.is_file():
        raise FileNotFoundError(f"Missing training trace file: {trace_path}")

    traces = [
        json.loads(line)
        for line in trace_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if not traces:
        raise ValueError(f"No training traces found in {trace_path}")

    initial_failures = [
        trace
        for trace in traces
        if trace.get("functionality") and trace["functionality"][0] < 1.0
    ]
    max_iteration = max(
        max(len(trace.get("functionality", [])) - 1, 0) for trace in traces
    )

    curve_rows = []
    for iteration in range(max_iteration + 1):
        fixed_count = 0
        for trace in initial_failures:
            values = trace["functionality"]
            observed = values[: min(iteration + 1, len(values))]
            if observed and max(observed) >= 1.0:
                fixed_count += 1
        denominator = len(initial_failures)
        curve_rows.append(
            {
                "iteration": iteration,
                "fixed_cases": fixed_count,
                "initially_incorrect_cases": denominator,
                "all_training_cases": len(traces),
                "fixing_ratio_over_initial_failures": (
                    fixed_count / denominator if denominator else 0.0
                ),
                "fixing_ratio_over_all_cases": fixed_count / len(traces),
            }
        )

    curve = pd.DataFrame(curve_rows)
    curve_path = run_dir / "training_fixing_curve.csv"
    curve.to_csv(curve_path, index=False)

    summary = {
        "training_cases": len(traces),
        "initially_correct_cases": len(traces) - len(initial_failures),
        "initially_incorrect_cases": len(initial_failures),
        "fixed_initial_failures": sum(bool(t.get("fixed")) for t in initial_failures),
        "final_fixing_ratio_over_initial_failures": float(
            curve.iloc[-1]["fixing_ratio_over_initial_failures"]
        ),
        "final_fixing_ratio_over_all_cases": float(
            curve.iloc[-1]["fixing_ratio_over_all_cases"]
        ),
        "max_recorded_iteration": int(max_iteration),
    }
    summary_path = run_dir / "training_summary.json"
    summary_path.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print("Training summary")
    for key, value in summary.items():
        print(f"  {key}: {value}")
    print(f"  curve: {curve_path}")
    print(f"  summary: {summary_path}")


def analyze_inference(run_dir: Path) -> None:
    eval_dir = run_dir / "eval"
    if not eval_dir.is_dir():
        raise FileNotFoundError(f"Missing inference eval directory: {eval_dir}")

    jg = load_csvs(sorted(eval_dir.glob("*_jg.csv")), "JasperGold")
    sim = load_csvs(sorted(eval_dir.glob("*_sim.csv")), "similarity")

    summary = {
        "evaluated_cases": int(len(jg)),
        "bleu": float(sim["bleu"].mean()),
        "rouge": float(sim["rouge"].mean()),
        "exact_match": float(sim["exact_match"].mean()),
        "syntax": float(jg["syntax"].mean()),
        "functionality": float(jg["functionality"].mean()),
        "relaxed_functionality": float(jg["func_relaxed"].mean()),
        "syntax_pass_count": int(jg["syntax"].sum()),
        "functionality_pass_count": int(jg["functionality"].sum()),
        "relaxed_functionality_pass_count": int(jg["func_relaxed"].sum()),
    }
    summary_path = eval_dir / "reproduction_summary.json"
    summary_path.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    raw_paths = sorted(run_dir.glob("*.csv"))
    if raw_paths:
        raw = load_csvs(raw_paths, "raw generation")
        keys = ["experiment_id", "task_id", "model_name"]
        if all(key in raw.columns and key in jg.columns for key in keys):
            joined = raw.merge(jg, on=keys, how="inner")
            failures = joined[joined["functionality"] < 1.0].copy()
            failure_path = eval_dir / "strict_functionality_failures.csv"
            failures.to_csv(failure_path, index=False)
            summary["strict_failure_file"] = str(failure_path)

    summary_path.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print("Inference summary")
    for key, value in summary.items():
        print(f"  {key}: {value}")
    print(f"  summary: {summary_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--train-dir", type=Path)
    group.add_argument("--inference-dir", type=Path)
    args = parser.parse_args()

    if args.train_dir:
        analyze_training(args.train_dir.expanduser().resolve())
    else:
        analyze_inference(args.inference_dir.expanduser().resolve())


if __name__ == "__main__":
    main()
