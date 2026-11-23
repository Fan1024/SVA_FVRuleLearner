"""Run strict reference self-checks for one selected NL2SVA dataset.

Place this file in new_agent/ and run from the repository root:
    python new_agent/check_reference_pec.py
    python new_agent/check_reference_pec.py --dataset nl2sva_block_hard.csv

Human and Machine read inline testbenches. OpenCore reads module interfaces
and calls native PEC once. Block reads clean context paths
from the CSV and uses the Machine backend. Relative paths start at the repo
root. Original Block sources, missing templates, and immediate assertions
are reported as skipped. Skips prevent an all-cases-passed result.

Edit DATASET below or pass --dataset. Filenames such as nl2sva_block_hard.csv
are accepted. Default checking includes every row of the selected dataset,
without a train/test split. --case-ids is diagnostic only: partial checks never
produce an all-cases-passed result. This checks reference against itself; it
does not prove equivalence of original and transformed references.
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


# EDIT THIS ONE SETTING. A dataset key or CSV filename is accepted.
DATASET = "nl2sva_block_hard.csv"

DATASET_PATHS = {
    "nl2sva_human": "FVEval/data_nl2sva/data/nl2sva_human.csv",
    "nl2sva_machine": "FVEval/data_nl2sva/data/nl2sva_machine.csv",
    "nl2sva_opencore": "FVEval/data_1k/module_sva_nl_manual_editing.csv",
    "nl2sva_block": "Data/nl2sva_block.csv",
    "nl2sva_block_hard": "Data/nl2sva_block_hard.csv",
}

SUMMARY_FIELDS = (
    "dataset", "native_backend", "case_number", "original_case_number", "design_name", "task_id", "testbench",
    "preflight_status", "formal_status", "syntax", "syntax_check", "native_pec",
    "native_relax_pec", "bleu", "pec_context_mode", "typed_profile", "interface_note",
    "native_self_check_passed", "self_check_passed", "error", "evidence_dir",
    "unavailable_parameters", "compound_sampled_calls", "context_source", "bound_parameters",
)



def dataset_key(value):
    """Accept an existing dataset key, its CSV filename, or explicit 'all'."""
    value = str(value).strip()
    if value == "all":
        return value
    key = Path(value.replace("\\", "/")).stem
    if key not in DATASET_PATHS:
        raise argparse.ArgumentTypeError("Unknown dataset: " + value)
    return key


def dataset_complete(summary):
    """Require coverage and strict native PASS for the complete selected CSV."""
    expected = summary.get("expected_cases")
    return bool(
        not summary.get("error")
        and isinstance(expected, int) and expected > 0
        and summary.get("cases") == expected
        and summary.get("checked") == expected
        and summary.get("passed") == expected
        and summary.get("failed") == 0
        and summary.get("skipped") == 0
    )


def gate_report(summaries):
    """A self-check certificate; deliberately not a transformation proof."""
    return {
        "check_kind": "reference_self_equivalence",
        "all_cases_passed": bool(summaries) and all(dataset_complete(s) for s in summaries),
        "expected_cases": sum(s.get("expected_cases") or 0 for s in summaries),
        "passed": sum(s.get("passed") or 0 for s in summaries),
        "datasets": summaries,
        "original_vs_hard_equivalence_checked": False,
        "scope": ("The hard reference is compared with itself through the native PEC route, "
                  "with full testbench syntax checking. A PASS validates this comparison path; "
                  "it does not establish raw-observation source bindings, original-versus-hard "
                  "equivalence, DUT proof, non-vacuity, or natural-language alignment."),
    }


def native_backend(dataset):
    from new_agent.formal_check import native_backend as backend
    return backend(dataset)


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def context_path_for(repo, case, override):
    # The loader has already read Block's CSV path into case["testbench"].
    return (repo / (override or Path(case["testbench_path"])).expanduser()).resolve()


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
        if context_path is None or str(context_path) == case.get("testbench_path"):
            context = case["testbench"]
        else:
            from new_agent.block_dataset import read_testbench
            context = read_testbench(context_path, case["task_id"])["testbench"]
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
            dataset=dataset,
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
        and result.get("raw_scores", {}).get("syntax", result.get("syntax")) == 1.0
        and native.get("functionality") == 1.0
    )
    if native_pass:
        context_requires_types = dataset in {"nl2sva_block", "nl2sva_block_hard"} or (
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
        "original_case_number": case.get("original_case_number"),
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
        "bound_parameters": json.dumps(interface["bound_parameters"])
        if interface.get("bound_parameters") else None,
    }


def plan_cases(repo, dataset, cases, override):
    plan = []
    for case in cases:
        context_path = context_path_for(repo, case, override) if dataset in {"nl2sva_block", "nl2sva_block_hard"} else None
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
    if dataset in {"nl2sva_block", "nl2sva_block_hard"} and mode != "expanded_names":
        raise ValueError("Block needs FVRULE_PEC_CONTEXT_MODE=expanded_names.")
    if dataset != "nl2sva_opencore" or mode == "expanded_names":
        import pyslang

        if not hasattr(getattr(pyslang, "syntax", None), "SyntaxTree"):
            raise ImportError("The installed pyslang lacks pyslang.syntax.SyntaxTree.")
    if shutil.which("jg") is None:
        raise FileNotFoundError("The existing Jasper backend requires 'jg' on PATH.")
    formal_check.initialize_evaluator(output / "native_logs", native_backend(dataset), timeout)



def original_case_numbers(csv_path):
    """Map stable design/task identities to original one-based CSV row numbers."""
    mapping = {}
    with Path(csv_path).open(encoding="utf-8-sig", newline="") as stream:
        for number, row in enumerate(csv.DictReader(stream), start=1):
            key = (row["design_name"].strip(), row["task_id"].strip())
            if key in mapping:
                raise ValueError("Duplicate original Block identity: " + repr(key))
            mapping[key] = number
    return mapping


def run_dataset(repo, dataset, csv_path, output, args, timeout, writer, stream):
    from new_agent import dataset_loader

    full_cases = dataset_loader.load_cases(csv_path)
    cases = dataset_loader.load_cases(csv_path, args.case_ids) if args.case_ids else full_cases
    expected_cases = len(full_cases)
    if dataset == "nl2sva_block_hard":
        # Every hard CSV row must be exercised; loader status filtering must not hide one.
        with Path(csv_path).open(encoding="utf-8-sig", newline="") as stream_in:
            expected_cases = sum(1 for _ in csv.DictReader(stream_in))
        # CSV identities already preserve the mapping; no sidecar JSON is needed.
        original_path = repo / "Data/nl2sva_block.csv"
        if original_path.is_file():
            mapping = original_case_numbers(original_path)
            for case in cases:
                identity = (case["design_name"], case["task_id"])
                if identity not in mapping:
                    raise ValueError("Hard case has no matching original Block identity: " + repr(identity))
                case["original_case_number"] = mapping[identity]
    if args.testbench and len(cases) != 1:
        raise ValueError("--testbench requires exactly one selected case.")
    plan = plan_cases(repo, dataset, cases, args.testbench)

    runnable = sum(skip is None for _, _, skip in plan)
    print(f"{dataset} | selected={len(cases)} | expected={expected_cases} | ready={runnable}", flush=True)
    if runnable:
        initialize_backend(dataset, output, timeout)

    counts = Counter()
    failed_cases = []
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
        if not summary["self_check_passed"]:
            failed_cases.append({key: summary.get(key) for key in (
                "case_number", "original_case_number", "design_name", "task_id",
                "preflight_status", "formal_status", "error", "evidence_dir")})
        if not skip:
            print(
                f"{dataset} case {number} {case['task_id']} | {summary['preflight_status']} | "
                f"SYN={summary['syntax']} | native PEC={summary['native_pec']}", flush=True,
            )
            if summary["error"]:
                print(summary["error"], flush=True)

    write_json(output / "failed_cases.json", failed_cases)
    summary = {
        "dataset": dataset,
        "expected_cases": expected_cases,
        "cases": len(cases),
        "checked": runnable,
        "passed": counts["PASS"],
        "failed": runnable - counts["PASS"],
        "skipped": len(cases) - runnable,
        "error": "",
    }
    summary["all_cases_passed"] = dataset_complete(summary)
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--dataset", type=dataset_key, choices=tuple(DATASET_PATHS) + ("all",),
                        default=DATASET, help="Dataset key or CSV filename; default: DATASET setting above.")
    parser.add_argument("--csv", type=Path, help="Override the CSV for one selected dataset.")
    parser.add_argument("--opencore-csv", type=Path,
                        help="Override the OpenCore CSV, including when checking all datasets.")
    parser.add_argument("--case-ids", nargs="+", type=int, help="One-based rows in one selected dataset.")
    parser.add_argument("--testbench", type=Path, help="Override the clean context for one Block case.")
    parser.add_argument("--timeout", type=float, help="Override the configured Jasper timeout in seconds.")
    parser.add_argument("--output-dir", type=Path, help="New directory for this run's evidence.")
    parser.add_argument("--repair-block-tb", action="store_true",
                        help="Make input net types explicit in the Block CSV testbench templates before checking.")
    args = parser.parse_args(argv)
    if (args.csv or args.case_ids) and args.dataset == "all":
        parser.error("--csv and --case-ids require --dataset.")
    if args.testbench and args.dataset not in {"nl2sva_block", "nl2sva_block_hard"}:
        parser.error("--testbench requires a Block or Block-hard dataset.")
    if args.repair_block_tb and (args.dataset not in ("all", "nl2sva_block", "nl2sva_block_hard") or args.testbench):
        parser.error("--repair-block-tb requires the Block dataset with its CSV testbench paths.")
    if args.opencore_csv and (args.csv or args.dataset not in ("all", "nl2sva_opencore")):
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

    datasets = tuple(DATASET_PATHS) if args.dataset == "all" else (args.dataset,)
    csv_paths = {dataset: (repo / (args.csv or Path(DATASET_PATHS[dataset])).expanduser()).resolve()
                 for dataset in datasets}
    if args.opencore_csv:
        csv_paths["nl2sva_opencore"] = (repo / args.opencore_csv.expanduser()).resolve()
    block_repair = None
    if args.repair_block_tb:
        from new_agent.repair_block_testbenches import repair_block_testbenches

        block_repair = repair_block_testbenches(repo, csv_paths["nl2sva_block" if args.dataset == "all" else args.dataset])

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
        "llm_testbench_comments_visible": getattr(config, "LLM_TESTBENCH_COMMENTS_VISIBLE", True),
        "pec_testbench_comments": "full source retained; LLM comment filtering is not applied",
        "check_kind": "reference_self_equivalence",
        "original_vs_hard_equivalence_checked": False,
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
                    summary = dict.fromkeys(("expected_cases", "cases", "checked", "passed", "failed", "skipped"))
                    summary.update(dataset=dataset, all_cases_passed=False, error=f"{type(error).__name__}: {error}")
                    try:
                        from new_agent import dataset_loader
                        expected = len(dataset_loader.load_cases(csv_paths[dataset]))
                        if dataset == "nl2sva_block_hard":
                            with csv_paths[dataset].open(encoding="utf-8-sig", newline="") as source_csv:
                                expected = sum(1 for _ in csv.DictReader(source_csv))
                        summary.update(expected_cases=expected, cases=expected, checked=0,
                                       passed=0, failed=0, skipped=0)
                    except Exception:
                        pass
                dataset_summaries.append(summary)
                if summary["error"]:
                    print(f"{dataset} | DATASET_ERROR | {summary['error']}", flush=True)
                else:
                    print(f"{dataset} | passed={summary['passed']} | failed={summary['failed']} | skipped={summary['skipped']}", flush=True)
    finally:
        config.PEC_CONTEXT_MODULE = previous_module
    with (output / "dataset_summary.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=("dataset", "expected_cases", "cases", "checked", "passed", "failed", "skipped", "all_cases_passed", "error"))
        writer.writeheader()
        writer.writerows(dataset_summaries)
    print(f"Summary: {output / 'dataset_summary.csv'}", flush=True)
    gate = gate_report(dataset_summaries)
    write_json(output / "all_cases_passed.json", gate)
    if gate["all_cases_passed"]:
        print(f"ALL_CASES_PASSED | {gate['passed']}/{gate['expected_cases']} | strict native reference self-check", flush=True)
        print("This is a harness self-check, not an original-versus-hard equivalence proof.", flush=True)
        return 0
    print(f"NOT_ALL_CASES_PASSED | {gate['passed']}/{gate['expected_cases']} | see summary.csv and failed_cases.json", flush=True)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

