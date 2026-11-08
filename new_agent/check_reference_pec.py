"""Run reference self-checks for all four NL2SVA datasets using native Jasper PEC.

Place this file in new_agent/ and run from the repository root:
    python new_agent/check_reference_pec.py

Human and Machine read inline testbenches. OpenCore reads module interfaces
and calls native PEC once. Block reads clean context paths
from the CSV and uses the Machine backend. Relative paths start at the repo
root. Original Block sources, missing templates, and immediate assertions
are reported as skipped.
"""

import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import shutil
import sys
import traceback


DATASET_PATHS = {
    "nl2sva_human": "FVEval/data_nl2sva/data/nl2sva_human.csv",
    "nl2sva_machine": "FVEval/data_nl2sva/data/nl2sva_machine.csv",
    "nl2sva_opencore": "FVEval/data_1k/module_sva_nl_manual_editing.csv",
    "nl2sva_block": "Data/nl2sva_block.csv",
}

SUMMARY_FIELDS = (
    "dataset", "native_backend", "case_number", "design_name", "task_id", "testbench",
    "preflight_status", "formal_status", "syntax", "syntax_check", "native_pec",
    "native_relax_pec", "bleu", "pec_context_mode", "typed_profile", "interface_note",
    "native_self_check_passed", "self_check_passed", "error", "evidence_dir",
    "unavailable_parameters", "compound_sampled_calls", "context_source",
)


def native_backend(dataset):
    return "nl2sva_machine" if dataset == "nl2sva_block" else dataset


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def context_path_for(repo, case, override):
    return (repo / (override or Path(case["testbench"])).expanduser()).resolve()


def assertion_head(source):
    from new_agent.pec_input_adapter import _tokens

    tokens = _tokens(source)
    start = 2 if len(tokens) > 2 and tokens[1].text == ":" else 0
    return [token.text for token in tokens[start:start + 2]]


def check_case(dataset, case, context_path, directory, timeout):
    from new_agent import formal_check, model_io

    directory.mkdir()
    reference = case["reference_assertion"]
    response = "```systemverilog\n" + reference + "\n```"
    (directory / "model_response.txt").write_text(response + "\n", encoding="utf-8")

    phase = "INPUT_ERROR"
    try:
        context = case["testbench"] if context_path is None else context_path.read_text(encoding="utf-8-sig")
        phase = "FORMAT_ERROR"
        candidate = model_io.extract_assertion(response)
        if candidate != reference:
            raise ValueError("The model-output extractor changed the reference text.")
        phase = "UNSUPPORTED_ASSERTION"
        if assertion_head(candidate) != ["assert", "property"]:
            raise ValueError("This check requires a concurrent 'assert property' statement.")
        phase = "CHECK_ERROR"
        result = formal_check.evaluate_assertion(
            generated_assertion=candidate,
            reference_assertion=reference,
            testbench=context,
            requirement=case["requirement"],
            run_dir=directory,
            timeout_seconds=timeout,
            task_id=case["design_name"] + "/" + case["task_id"],
            dataset=native_backend(dataset),
            model_name="reference_self_check",
        )
    except Exception as error:
        (directory / "preflight_error.log").write_text(traceback.format_exc(), encoding="utf-8")
        result = {"status": phase, "evaluation_error": f"{type(error).__name__}: {error}"}

    summary = summarize_case(dataset, case, context_path, result, directory)
    write_json(directory / "preflight.json", summary)
    if summary["self_check_passed"]:
        formal_check.cleanup_work(result)
    return summary


def summarize_case(dataset, case, context_path, result, directory=None):
    native = {} if result["status"] == "TB_COMPILE_ERROR" else result.get("native_metrics", {})
    interface = result.get("pec_context_preparation", {})
    reference_input = result.get("pec_input_preparation", {}).get("reference", {})
    typed_profile = interface.get("typed_interface_profile")
    native_pass = (
        result["status"] == "FULL_EQUIVALENCE"
        and result.get("syntax") == 1.0
        and native.get("functionality") == 1.0
    )
    if native_pass:
        context_requires_types = dataset == "nl2sva_block" or (
            dataset == "nl2sva_opencore" and interface.get("mode") == "expanded_names")
        preflight_status = "UNVERIFIED_INTERFACE" if context_requires_types and not typed_profile else "PASS"
    else:
        preflight_status = result.get("skip_status") or (
            "NATIVE_SCORE_MISMATCH" if result["status"] == "FULL_EQUIVALENCE" else result["status"]
        )
    return {
        "dataset": dataset,
        "native_backend": native_backend(dataset),
        "case_number": case["case_number"],
        "design_name": case["design_name"],
        "task_id": case["task_id"],
        "testbench": str(context_path) if context_path is not None else (
            "CSV:module_interface" if dataset == "nl2sva_opencore" else "CSV:testbench"
        ),
        "preflight_status": preflight_status,
        "formal_status": result["status"],
        "syntax": result.get("syntax"),
        "syntax_check": "native_pec" if dataset == "nl2sva_opencore" else "testbench_elaboration",
        "native_pec": native.get("functionality"),
        "native_relax_pec": native.get("func_relaxed"),
        "bleu": result.get("bleu"),
        "pec_context_mode": interface.get("mode"),
        "typed_profile": typed_profile,
        "interface_note": interface.get("typed_interface_note"),
        "native_self_check_passed": native_pass,
        "self_check_passed": preflight_status == "PASS",
        "error": result.get("evaluation_error"),
        "evidence_dir": str(directory) if directory is not None else None,
        "unavailable_parameters": json.dumps(interface["unavailable_parameters"])
        if interface.get("unavailable_parameters") else None,
        "compound_sampled_calls": json.dumps(reference_input["compound_sampled_calls"])
        if reference_input.get("compound_sampled_calls") else None,
        "context_source": interface.get("context_source"),
    }


def plan_cases(repo, dataset, cases, override):
    plan = []
    for case in cases:
        context_path = context_path_for(repo, case, override) if dataset == "nl2sva_block" else None
        skip = None
        if assertion_head(case["reference_assertion"]) == ["assert", "("]:
            skip = ("SKIPPED_IMMEDIATE_ASSERTION", "This PEC route handles concurrent assertions.")
        elif context_path is not None and context_path.parent.name in {"ft", "sva", "rtl", "lists"}:
            skip = ("SKIPPED_SOURCE_TEMPLATE", "Point the CSV testbench column to the shared clean context.")
        elif context_path is not None and not context_path.is_file():
            skip = ("SKIPPED_NO_TEMPLATE", f"Expected clean context at {context_path}")
        plan.append((case, context_path, skip))
    return plan


def initialize_backend(dataset, output, timeout):
    from new_agent import formal_check
    from new_agent.pec_context_adapter import context_mode

    mode = context_mode()
    if dataset == "nl2sva_block" and mode != "expanded_names":
        raise ValueError("Block needs FVRULE_PEC_CONTEXT_MODE=expanded_names.")
    if dataset != "nl2sva_opencore" or mode == "expanded_names":
        import pyslang

        if not hasattr(getattr(pyslang, "syntax", None), "SyntaxTree"):
            raise ImportError("The installed pyslang lacks pyslang.syntax.SyntaxTree.")
    if shutil.which("jg") is None:
        raise FileNotFoundError("The existing Jasper backend requires 'jg' on PATH.")
    formal_check.initialize_evaluator(output / "native_logs", native_backend(dataset), timeout)


def run_dataset(repo, dataset, csv_path, output, args, timeout, writer, stream):
    from new_agent import dataset_loader

    cases = dataset_loader.load_cases(csv_path, args.case_ids)
    if args.testbench and len(cases) != 1:
        raise ValueError("--testbench requires exactly one selected case.")
    plan = plan_cases(repo, dataset, cases, args.testbench)

    runnable = sum(skip is None for _, _, skip in plan)
    print(f"{dataset} | cases={len(cases)} | ready={runnable}", flush=True)
    if runnable:
        initialize_backend(dataset, output, timeout)

    counts = Counter()
    for case, context_path, skip in plan:
        number = case["case_number"]
        if skip:
            status, detail = skip
            summary = summarize_case(dataset, case, context_path, {
                "status": None, "skip_status": status, "evaluation_error": detail,
            })
        else:
            summary = check_case(dataset, case, context_path, output / f"case_{number:04d}", timeout)
        writer.writerow(summary)
        stream.flush()
        counts[summary["preflight_status"]] += 1
        if not skip:
            print(
                f"{dataset} case {number} {case['task_id']} | {summary['preflight_status']} | "
                f"SYN={summary['syntax']} | native PEC={summary['native_pec']}", flush=True,
            )
            if summary["error"]:
                print(summary["error"], flush=True)

    return {
        "dataset": dataset,
        "cases": len(cases),
        "checked": runnable,
        "passed": counts["PASS"],
        "failed": runnable - counts["PASS"],
        "skipped": len(cases) - runnable,
        "error": "",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--dataset", choices=DATASET_PATHS, help="Default: all four datasets.")
    parser.add_argument("--csv", type=Path, help="Override the CSV for one selected dataset.")
    parser.add_argument("--opencore-csv", type=Path,
                        help="Override the OpenCore CSV, including when checking all four datasets.")
    parser.add_argument("--case-ids", nargs="+", type=int, help="One-based rows in one selected dataset.")
    parser.add_argument("--testbench", type=Path, help="Override the clean context for one Block case.")
    parser.add_argument("--timeout", type=float, help="Override the configured Jasper timeout in seconds.")
    parser.add_argument("--output-dir", type=Path, help="New directory for this run's evidence.")
    parser.add_argument("--repair-block-tb", action="store_true",
                        help="Make input net types explicit in the Block CSV testbench templates before checking.")
    args = parser.parse_args(argv)
    if (args.csv or args.case_ids) and not args.dataset:
        parser.error("--csv and --case-ids require --dataset.")
    if args.testbench and args.dataset != "nl2sva_block":
        parser.error("--testbench requires --dataset nl2sva_block.")
    if args.repair_block_tb and (args.dataset not in (None, "nl2sva_block") or args.testbench):
        parser.error("--repair-block-tb requires the Block dataset with its CSV testbench paths.")
    if args.opencore_csv and (args.csv or args.dataset not in (None, "nl2sva_opencore")):
        parser.error("--opencore-csv requires OpenCore or an all-dataset run and cannot be combined with --csv.")

    repo = args.repo_root.expanduser().resolve()
    if not (repo / "new_agent/formal_check.py").is_file():
        parser.error("Set --repo-root to the SVA_FVRuleLearner checkout or place this file in new_agent/.")
    sys.path.insert(0, str(repo))
    from new_agent import config, formal_check, model_io
    from new_agent.pec_context_adapter import context_mode, verified_interface_profile

    timeout = config.JASPER_TIMEOUT_SECONDS if args.timeout is None else args.timeout
    if not math.isfinite(timeout) or timeout <= 0:
        parser.error("--timeout must be finite and positive.")

    datasets = (args.dataset,) if args.dataset else tuple(DATASET_PATHS)
    csv_paths = {dataset: (repo / (args.csv or Path(DATASET_PATHS[dataset])).expanduser()).resolve()
                 for dataset in datasets}
    if args.opencore_csv:
        csv_paths["nl2sva_opencore"] = (repo / args.opencore_csv.expanduser()).resolve()
    block_repair = None
    if args.repair_block_tb:
        from new_agent.repair_block_testbenches import repair_block_testbenches

        block_repair = repair_block_testbenches(repo, csv_paths["nl2sva_block"])

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%fZ")
    output = (args.output_dir or config.RUNS_DIR / f"PEC_selfcheck_{stamp}").expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    profile, profile_note = verified_interface_profile()
    write_json(output / "run_metadata.json", {
        "datasets": {
            dataset: {
                "csv_path": str(csv_paths[dataset]),
                "native_backend": native_backend(dataset),
                "pec_context_mode": context_mode(),
            }
            for dataset in datasets
        },
        "case_ids": args.case_ids,
        "python": sys.executable,
        "extractor_file": str(Path(model_io.__file__).resolve()),
        "evaluator_file": str(Path(formal_check.__file__).resolve()),
        "timeout_seconds": timeout,
        "typed_profile": profile,
        "interface_note": profile_note,
        "block_testbench_repair": block_repair,
    })
    print(f"Evidence directory: {output}\nInterface: {profile_note}", flush=True)

    dataset_summaries = []
    previous_module = config.PEC_CONTEXT_MODULE
    try:
        config.PEC_CONTEXT_MODULE = None  # Resolve the context module separately for each case.
        with (output / "summary.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=SUMMARY_FIELDS)
            writer.writeheader()
            for dataset in datasets:
                directory = output / dataset
                directory.mkdir()
                try:
                    summary = run_dataset(repo, dataset, csv_paths[dataset], directory, args, timeout, writer, stream)
                except Exception as error:
                    (directory / "dataset_error.log").write_text(traceback.format_exc(), encoding="utf-8")
                    summary = dict.fromkeys(("cases", "checked", "passed", "failed", "skipped"))
                    summary.update(dataset=dataset, error=f"{type(error).__name__}: {error}")
                dataset_summaries.append(summary)
                if summary["error"]:
                    print(f"{dataset} | DATASET_ERROR | {summary['error']}", flush=True)
                else:
                    print(f"{dataset} | passed={summary['passed']} | failed={summary['failed']} | skipped={summary['skipped']}", flush=True)
    finally:
        config.PEC_CONTEXT_MODULE = previous_module
    with (output / "dataset_summary.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=("dataset", "cases", "checked", "passed", "failed", "skipped", "error"))
        writer.writeheader()
        writer.writerows(dataset_summaries)
    print(f"Summary: {output / 'dataset_summary.csv'}", flush=True)
    if any(row["error"] or row["failed"] for row in dataset_summaries):
        return 1
    return 0 if any(row["checked"] for row in dataset_summaries) else 2


if __name__ == "__main__":
    raise SystemExit(main())
