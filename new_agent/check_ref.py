"""Run with: python check_ref.py. No LLM calls or experiment-file changes."""

import csv
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess

import formal_check


# Edit only these two settings. Numbers are 1-based CSV data rows.
DATASET = "nl2sva_human"
CASE_IDS = [47]  # [] checks every row.


def original_inputs(row):
    """Reproduce FVRuleLearner's expression and signal-list preparation."""
    reference = row["ref_solution"].strip().replace("\n", "")
    split_at = "tb_reset)" if DATASET == "nl2sva_human" else "clk)"
    body = reference.split(split_at)[-1].strip().split(");")[0].strip()
    if DATASET == "nl2sva_human":
        signals = re.findall(r"'([^'\s]+)'", row["prompt"])
        parameters = re.findall(
            r"\b(parameter|localparam)\s+(int\s+|real\s+|bit\s+|\[[^]]+\]\s*)?(\w+)",
            row["testbench"],
        )
        signals.extend(match[2] for match in parameters)
    else:
        signals = sorted(set(re.findall(r"\bsig_\w+", reference)))
        if re.search(r"\btb_reset\b", body):
            signals.append("tb_reset")
    return body, ",".join(signals)


def run_original(repo, row, folder):
    """Use original input preparation with the installed, unchanged Tcl/PEC."""
    body, signals = original_inputs(row)
    task_id = re.sub(r"[^A-Za-z0-9_-]+", "_", row["task_id"])
    (folder / f"{DATASET}_{task_id}.sva").write_text(row["testbench"], encoding="utf-8")
    project = folder / "jg" / task_id
    project.parent.mkdir()
    command = [
        "jg", "-fpv", "-batch", "-tcl",
        str(repo / "FVEval" / "tool_scripts" / f"run_jg_{DATASET}.tcl"),
        "-define", "LM_ASSERT_TEXT", body,
        "-define", "REF_ASSERT_TEXT", body,
        "-define", "SIGNAL_LIST", signals,
        "-define", "EXP_ID", DATASET,
        "-define", "TASK_ID", task_id,
        "-define", "SV_DIR", str(folder),
        "-proj", str(project), "-allow_unsupported_OS",
    ]
    (folder / "command.json").write_text(json.dumps(command, indent=2), encoding="utf-8")
    try:
        completed = subprocess.run(command, cwd=repo / "FVEval",
                                   capture_output=True, text=True, timeout=300)
        output = "\n".join(s for s in (completed.stdout, completed.stderr) if s)
        result = formal_check._parse_formal_result(output, completed.returncode)
    except subprocess.TimeoutExpired as error:
        def decode(value):
            return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")
        output = decode(error.stdout) + "\n" + decode(error.stderr) + "\nTimed out after 300 seconds."
        result = {"status": "TIMEOUT"}
    except OSError as error:
        output, result = str(error), {"status": "TOOL_ERROR"}
    (folder / "jasper.log").write_text(output, encoding="utf-8")
    result.update(comparison_inputs={"candidate_expression": body,
                  "reference_expression": body, "signal_list": signals})
    return result


def run_wrapper(repo, row, folder, candidate=None):
    """Pass the same complete reference as both generated and reference SVA."""
    return formal_check.evaluate_assertion(
        generated_assertion=row["ref_solution"] if candidate is None else candidate,
        reference_assertion=row["ref_solution"],
        testbench=row["testbench"], requirement=row["prompt"],
        run_dir=folder, fveval_dir=repo / "FVEval",
        task_id=row["task_id"], dataset=DATASET,
    )


def main():
    if DATASET not in {"nl2sva_human", "nl2sva_machine"}:
        raise ValueError("DATASET must be nl2sva_human or nl2sva_machine.")
    here = Path(__file__).resolve().parent
    repo = here.parent
    dataset_path = repo / "FVEval" / "data_nl2sva" / "data" / f"{DATASET}.csv"
    with dataset_path.open(newline="", encoding="utf-8-sig") as file:
        rows = list(csv.DictReader(file))
    selected = list(dict.fromkeys(CASE_IDS)) if CASE_IDS else list(range(1, len(rows) + 1))
    if any(type(number) is not int or not 1 <= number <= len(rows) for number in selected):
        raise ValueError(f"CASE_IDS must contain numbers from 1 to {len(rows)}.")
    output = here / "check_ref_results" / datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    output.mkdir(parents=True, exist_ok=False)
    print("Dataset:", dataset_path)
    print("Results:", output, flush=True)
    results = []
    lines = []
    for number in selected:
        row = rows[number - 1]
        title = f"Case {number}: {row['design_name']} / {row['task_id']}"
        print("\n" + title, flush=True)
        lines.append(title)
        pair = []
        for label, check in (("original_inputs", run_original), ("current_wrapper", run_wrapper)):
            folder = output / f"case_{number:04d}" / label
            folder.mkdir(parents=True)
            try:
                result = check(repo, row, folder)
            except Exception as error:
                result = {"status": "CHECK_ERROR", "error": f"{type(error).__name__}: {error}"}
                (folder / "jasper.log").write_text(result["error"], encoding="utf-8")
            log = folder / "jasper.log"
            raw = log.read_text(errors="replace") if log.exists() else ""
            if re.search(r"[/\\]pec\.sve(?:\(|:)", raw) and re.search(r"VERI-\d+", raw):
                result["reported_status"] = result["status"]
                result["status"] = "PEC_COMPILE_ERROR"
            result.update(case_id=number, design_name=row["design_name"],
                          task_id=row["task_id"], backend=label)
            result["pec_files"] = [str(p) for p in folder.rglob("pec.sve")]
            (folder / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
            pair.append(result)
            results.append(result)
            line = f"  {label}: {result['status']}"
            print(line, flush=True)
            lines.append(line)
        if all("comparison_inputs" in result for result in pair):
            a, b = [result["comparison_inputs"] for result in pair]
            same = (a["candidate_expression"] == b["candidate_expression"]
                    and a["reference_expression"] == b["reference_expression"]
                    and set(a["signal_list"].split(",")) == set(b["signal_list"].split(",")))
            adapted = pair[1].get("input_adapter")
            line = f"  Same comparison expressions and signal-name set: {same}"
            if adapted:
                line += " (expected: the wrapper now expands vector inputs into scalar bits)"
            print(line)
            lines.append(line)
    # A vector negative control checks that adaptation does not simply accept
    # everything. Both properties compile, but differ for known in-range values.
    control = {
        "task_id": "vector_negative_control", "design_name": "vector_control",
        "prompt": "Use signals 'v' and 'idx'.",
        "testbench": "module control; input clk; input tb_reset; input [5:0] v; input [2:0] idx; endmodule",
        "ref_solution": "asrt: assert property (@(posedge clk) disable iff (tb_reset) v[idx]);",
    }
    negative = "asrt: assert property (@(posedge clk) disable iff (tb_reset) !v[idx]);"
    folder = output / "vector_negative_control"
    folder.mkdir()
    try:
        result = formal_check.evaluate_assertion(
            generated_assertion=negative, reference_assertion=control["ref_solution"],
            testbench=control["testbench"], requirement=control["prompt"],
            run_dir=folder, fveval_dir=repo / "FVEval",
            task_id=control["task_id"], dataset="nl2sva_human",
        )
    except Exception as error:
        result = {"status": "CHECK_ERROR", "error": f"{type(error).__name__}: {error}"}
    result["backend"] = "negative_control"
    results.append(result)
    (folder / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    line = f"  vector_negative_control: {result['status']} (expected: NO_EQUIVALENCE)"
    print("\n" + line, flush=True)
    lines.append(line)
    (output / "summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (output / "summary.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print("\nExpected: current_wrapper self-checks FULL_EQUIVALENCE; negative control NO_EQUIVALENCE.")
    print("The original_inputs baseline may reproduce the old PEC_COMPILE_ERROR.")
    print("Logs and generated PEC files are retained in:", output)
    failed_self_check = any(result["status"] != "FULL_EQUIVALENCE"
                            for result in results if result["backend"] == "current_wrapper")
    return int(failed_self_check or results[-1]["status"] != "NO_EQUIVALENCE")


if __name__ == "__main__":
    raise SystemExit(main())
