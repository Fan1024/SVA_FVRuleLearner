"""Evaluate saved NL2SVA samples with the repository's JasperGold PEC Tcl.

Run: python evaluate.py
Reads EVAL_RUN_DIR from new_agent/config.py, with optional --run-dir override.
Does not call the language model or import the repository's src/config.py.
"""

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

import config


REPO_ROOT = Path(__file__).resolve().parent.parent
FVEVAL = REPO_ROOT / "FVEval"

FIELDS = (
    "design_name",
    "task_id",
    "trial",
    "status",
    "syntax",
    "functionality",
    "func_relaxed",
    "reset_mismatch",
    "model_reset",
    "reference_reset",
    "response_path",
    "generated_assertion",
    "reference_assertion",
)


def extract_code(raw):
    """Require one complete <CODE> block; preserve the raw response on disk."""
    match = re.fullmatch(r"\s*<CODE>\s*(.*?)\s*</CODE>\s*", raw, re.I | re.S)
    if match is None or re.search(r"</?CODE>", match.group(1), re.I):
        raise ValueError(
            "Expected exactly one <CODE>...</CODE> block, "
            "with no surrounding text"
        )
    return match.group(1).strip()


def assertion_parts(text):
    """Return assertion, sampled property body, and disable condition."""
    text = re.sub(r"^\s*[A-Za-z_]\w*\s*:\s*", "", text.strip())

    match = re.fullmatch(
        r"assert\s+property\s*\(\s*@\s*\(\s*posedge\s+clk\s*\)\s*"
        r"(?:disable\s+iff\s*\(\s*(?P<reset>[A-Za-z_]\w*)\s*\)\s*)?"
        r"(?P<body>.*?)\s*\)\s*;\s*",
        text,
        re.I | re.S,
    )

    if not match or not match.group("body").strip():
        raise ValueError(
            "Expected one assert property "
            "(@(posedge clk) [disable iff (...)] BODY);"
        )

    return text, match.group("body").strip(), match.group("reset") or ""


def package_testbench(row, candidate, destination):
    before_end, end, after_end = row["testbench"].rpartition("endmodule")

    if not end or after_end.strip():
        raise ValueError("Expected the CSV testbench to end with endmodule")

    reference, _, _ = assertion_parts(row["ref_solution"])

    destination.write_text(
        before_end
        + "\nreference: "
        + reference
        + "\n\nasrt: "
        + candidate
        + "\nendmodule\n",
        encoding="utf-8",
    )


def signal_list(row, dataset, candidate_body, reference_body):
    if dataset == "nl2sva_machine":
        signals = set(re.findall(r"\bsig_\w+", row["ref_solution"]))

        if re.search(r"\btb_reset\b", candidate_body + " " + reference_body):
            signals.add("tb_reset")

        return ",".join(sorted(signals))

    signals = re.findall(r"'([^'\s]+)'", row["prompt"])

    params = re.findall(
        r"\b(parameter|localparam)\s+"
        r"(int\s+|real\s+|bit\s+|\[[^]]+\]\s*)?(\w+)",
        row["testbench"],
    )

    signals.extend(match[2] for match in params)

    return ",".join(signals)


def real_syntax_error(output):
    """Use the fork's distinction between Tcl comments and Jasper diagnostics."""
    for line in output.splitlines():
        stripped = line.lstrip()

        if stripped.startswith("#") or re.match(r"^%\s*#", stripped):
            continue

        if re.search(r"\bERROR\s+\((?:VERI-[^)]+|ENL\d+)\)", line, re.I):
            return True

        if re.search(
            r"\bsyntax error\b|ignored due to previous errors",
            line,
            re.I,
        ):
            return True

    return False


def score(output, returncode):
    """Match the repository's PEC syntax/strict/relaxed score categories."""
    if real_syntax_error(output):
        return "SYNTAX_ERROR", 0.0, 0.0, 0.0

    if returncode != 0 or not re.search(r"\bTASK_ID\b", output):
        return "TOOL_ERROR", "", "", ""

    if "Full equivalence" in output:
        return "FULL_EQUIVALENCE", 1.0, 1.0, 1.0

    if "implies" in output:
        return "IMPLIES", 1.0, 0.0, 1.0

    if "No equivalence between" in output or "conflict with each other" in output:
        return "NO_EQUIVALENCE", 1.0, 0.0, 0.0

    return "INCONCLUSIVE", "", "", ""


def read_run(run_dir):
    manifest = json.loads(
        (run_dir / "manifest.json").read_text(encoding="utf-8")
    )

    dataset = manifest["dataset"]

    if dataset not in {"nl2sva_human", "nl2sva_machine"}:
        raise ValueError(f"Unsupported dataset: {dataset}")

    dataset_path = Path(manifest["dataset_path"])

    if hashlib.sha256(dataset_path.read_bytes()).hexdigest() != manifest[
        "dataset_sha256"
    ]:
        raise ValueError(
            "Dataset changed since generation; "
            "refusing to match assertions to rows"
        )

    with dataset_path.open(newline="", encoding="utf-8") as file:
        rows = list(csv.DictReader(file))

    return manifest, dataset, rows


def refresh_assertion_text(record, row, run_dir, case_name, trial):
    """Add candidate and reference SVA text for visual comparison."""
    response_path = run_dir / case_name / f"trial_{trial:02d}.txt"

    record["response_path"] = str(response_path.relative_to(run_dir))
    record["reference_assertion"] = row["ref_solution"].strip()

    if not response_path.is_file():
        record["generated_assertion"] = ""
        return

    raw_response = response_path.read_text(encoding="utf-8")

    try:
        # Normal case: store the generated SVA without <CODE> tags.
        record["generated_assertion"] = extract_code(raw_response)
    except ValueError:
        # For FORMAT_ERROR, retain the malformed model output for inspection.
        record["generated_assertion"] = raw_response.strip()


def record_key_from_csv(raw_record, row_numbers_by_identity):
    """
    Load both:
    - old evaluation.csv files containing row_number, and
    - new compact evaluation.csv files without row_number.
    """
    trial = int(raw_record["trial"])

    old_row_number = raw_record.get("row_number", "")
    if old_row_number:
        return int(old_row_number), trial

    identity = (
        raw_record.get("design_name", ""),
        raw_record.get("task_id", ""),
    )

    if identity not in row_numbers_by_identity:
        raise ValueError(f"Cannot identify saved result row: {identity}")

    return row_numbers_by_identity[identity], trial


def evaluate_trial(run_dir, manifest, dataset, row_number, row, trial, timeout):
    task_id = row["task_id"]

    if not re.fullmatch(r"[A-Za-z0-9_-]+", task_id):
        raise ValueError(f"Unsafe task_id: {task_id}")

    case_name = manifest.get("case_dirs", {}).get(str(row_number), task_id)

    if not re.fullmatch(r"[A-Za-z0-9_-]+", case_name):
        raise ValueError(f"Unsafe case directory: {case_name}")

    response_path = run_dir / case_name / f"trial_{trial:02d}.txt"

    record = dict.fromkeys(FIELDS, "")
    record.update(
        design_name=row["design_name"],
        task_id=task_id,
        trial=trial,
    )

    refresh_assertion_text(record, row, run_dir, case_name, trial)

    if not response_path.is_file():
        record.update(status="MISSING_RESPONSE")
        return record

    try:
        candidate, candidate_body, candidate_reset = assertion_parts(
            extract_code(response_path.read_text(encoding="utf-8"))
        )

        _, reference_body, reference_reset = assertion_parts(
            row["ref_solution"]
        )

    except ValueError:
        record.update(
            status="FORMAT_ERROR",
            syntax=0.0,
            functionality=0.0,
            func_relaxed=0.0,
        )
        return record

    record.update(
        model_reset=candidate_reset,
        reference_reset=reference_reset,
        reset_mismatch=int(candidate_reset != reference_reset),
    )

    # The repository's Machine PEC includes disable iff in the compared body.
    if dataset == "nl2sva_machine":
        if candidate_reset:
            candidate_body = (
                f"disable iff ({candidate_reset}) {candidate_body}"
            )

        if reference_reset:
            reference_body = (
                f"disable iff ({reference_reset}) {reference_body}"
            )

    trial_name = f"trial_{trial:02d}"
    work_dir = run_dir / ".work" / case_name / trial_name
    work_dir.mkdir(parents=True, exist_ok=True)

    tool_task_id = f"{row['design_name']}_{task_id}_trial_{trial - 1}"

    if not re.fullmatch(r"[A-Za-z0-9_-]+", tool_task_id):
        raise ValueError(f"Unsafe tool task ID: {tool_task_id}")

    sv_file = work_dir / f"{dataset}_{tool_task_id}.sva"
    package_testbench(row, candidate, sv_file)

    tcl = FVEVAL / "tool_scripts" / f"run_jg_{dataset}.tcl"

    project = work_dir / "jg" / f"{dataset}_{tool_task_id}"
    project.parent.mkdir(exist_ok=True)

    command = [
        "jg",
        "-fpv",
        "-batch",
        "-tcl",
        str(tcl),
        "-define",
        "LM_ASSERT_TEXT",
        candidate_body,
        "-define",
        "REF_ASSERT_TEXT",
        reference_body,
        "-define",
        "SIGNAL_LIST",
        signal_list(row, dataset, candidate_body, reference_body),
        "-define",
        "EXP_ID",
        dataset,
        "-define",
        "TASK_ID",
        tool_task_id,
        "-define",
        "SV_DIR",
        str(work_dir),
        "-proj",
        str(project),
        "-allow_unsupported_OS",
    ]

    log_path = run_dir / case_name / trial_name / "jasper.log"
    log_path.parent.mkdir(exist_ok=True)

    try:
        result = subprocess.run(
            command,
            cwd=FVEVAL,
            capture_output=True,
            text=True,
            timeout=timeout,
        )

        output = "\n".join(
            item for item in (result.stdout, result.stderr) if item
        )

        status, syntax, functionality, relaxed = score(
            output,
            result.returncode,
        )

    except subprocess.TimeoutExpired as exc:
        output = f"JASPER_TIMEOUT: exceeded {timeout} seconds\n"

        for part in (exc.stdout, exc.stderr):
            if part:
                output += (
                    part.decode(errors="replace")
                    if isinstance(part, bytes)
                    else part
                )

        status, syntax, functionality, relaxed = "TIMEOUT", "", "", ""

    except OSError as exc:
        output = f"JASPER_TOOL_ERROR: {exc}\n"
        status, syntax, functionality, relaxed = "TOOL_ERROR", "", "", ""

    log_path.write_text(output, encoding="utf-8")

    record.update(
        status=status,
        syntax=syntax,
        functionality=functionality,
        func_relaxed=relaxed,
    )

    if status in {
        "SYNTAX_ERROR",
        "FULL_EQUIVALENCE",
        "IMPLIES",
        "NO_EQUIVALENCE",
    }:
        shutil.rmtree(work_dir)

    return record


def result_columns(k):
    """Return trial columns followed by per-case pass@1/pass@k metrics."""
    columns = FIELDS + ("pass@1_strict", "pass@1_relaxed")

    if k != 1:
        columns += (f"pass@{k}_strict", f"pass@{k}_relaxed")

    return columns


def save_results(path, records, k):
    temp = path.with_suffix(".csv.tmp")

    with temp.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=result_columns(k),
        )
        writer.writeheader()
        writer.writerows(records)

    temp.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument(
        "--run-dir",
        type=Path,
        default=config.EVAL_RUN_DIR,
        help="Override EVAL_RUN_DIR in new_agent/config.py",
    )

    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Jasper timeout in seconds",
    )

    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Reevaluate completed trials too",
    )

    parser.add_argument(
        "--summary-only",
        action="store_true",
        help=(
            "Recompute pass@1/pass@k and rebuild textual comparison "
            "columns from an existing evaluation.csv; do not run Jasper"
        ),
    )

    args = parser.parse_args()

    if args.timeout < 1:
        parser.error("--timeout must be positive")

    if args.run_dir is None:
        parser.error("Set EVAL_RUN_DIR in config.py or pass --run-dir")

    run_dir = Path(args.run_dir).resolve()

    print(f"Evaluating run: {run_dir}")

    output_csv = run_dir / "evaluation.csv"

    if args.summary_only and not output_csv.is_file():
        parser.error(
            f"--summary-only requires an existing file: {output_csv}"
        )

    manifest, dataset, rows = read_run(run_dir)
    k = manifest["num_samples"]

    # Needed only to read a compact CSV after row_number is removed.
    row_numbers_by_identity = {}

    for number in manifest["case_number"]:
        row = rows[number - 1]
        identity = (row["design_name"], row["task_id"])

        if identity in row_numbers_by_identity:
            raise ValueError(
                "Cannot use compact evaluation.csv because "
                "design_name/task_id is not unique: "
                f"{identity}"
            )

        row_numbers_by_identity[identity] = number

    completed = {
        "SYNTAX_ERROR",
        "FULL_EQUIVALENCE",
        "IMPLIES",
        "NO_EQUIVALENCE",
        "FORMAT_ERROR",
    }

    records = {}

    # Read the old CSV. It may have the old redundant columns; they are
    # intentionally not copied into the rewritten file.
    if output_csv.exists() and not args.overwrite:
        with output_csv.open(newline="", encoding="utf-8") as file:
            for raw_record in csv.DictReader(file):
                key = record_key_from_csv(
                    raw_record,
                    row_numbers_by_identity,
                )

                records[key] = {
                    column: raw_record.get(column, "")
                    for column in result_columns(k)
                }

    for number in manifest["case_number"]:
        if type(number) is not int or not 1 <= number <= len(rows):
            raise ValueError(
                f"Invalid CSV row number in manifest: {number}"
            )

        row = rows[number - 1]

        case_name = manifest.get("case_dirs", {}).get(
            str(number),
            row["task_id"],
        )

        for trial in range(1, k + 1):
            key = (number, trial)

            if args.summary_only:
                if key not in records:
                    raise ValueError(
                        f"Missing result for {case_name} trial {trial}; "
                        "cannot summarize only"
                    )
                continue

            if key in records and records[key]["status"] in completed:
                print(
                    f"{case_name} trial {trial}: already evaluated",
                    flush=True,
                )
                continue

            record = evaluate_trial(
                run_dir,
                manifest,
                dataset,
                number,
                row,
                trial,
                args.timeout,
            )

            records[key] = record

            save_results(
                output_csv,
                [records[key] for key in sorted(records)],
                k,
            )

            print(
                f"{case_name} trial {trial}: {record['status']}",
                flush=True,
            )

    # Rebuild generated/reference columns even when evaluation.csv was created
    # by the previous evaluator version.
    for number in manifest["case_number"]:
        row = rows[number - 1]

        case_name = manifest.get("case_dirs", {}).get(
            str(number),
            row["task_id"],
        )

        for trial in range(1, k + 1):
            key = (number, trial)

            refresh_assertion_text(
                records[key],
                row,
                run_dir,
                case_name,
                trial,
            )

    print(f"Results: {output_csv}")

    total_1 = 0
    strict_1 = 0
    relaxed_1 = 0

    total_k = 0
    strict_k = 0
    relaxed_k = 0

    for number in manifest["case_number"]:
        trials = [
            records[(number, trial)]
            for trial in range(1, k + 1)
        ]

        case_name = manifest.get("case_dirs", {}).get(
            str(number),
            rows[number - 1]["task_id"],
        )

        for record in trials:
            record["design_name"] = rows[number - 1]["design_name"]

        # pass@1 uses only trial_01.
        first_trial = trials[0]

        if first_trial["functionality"] == "":
            for record in trials:
                record["pass@1_strict"] = ""
                record["pass@1_relaxed"] = ""

            print(
                f"{case_name}: trial 1 is incomplete; no pass@1 score"
            )

        else:
            case_strict_1 = int(
                float(first_trial["functionality"]) == 1.0
            )

            case_relaxed_1 = int(
                float(first_trial["func_relaxed"]) == 1.0
            )

            for record in trials:
                record["pass@1_strict"] = case_strict_1
                record["pass@1_relaxed"] = case_relaxed_1

            total_1 += 1
            strict_1 += case_strict_1
            relaxed_1 += case_relaxed_1

        # pass@k uses whether any of the k trials passes.
        if any(record["functionality"] == "" for record in trials):
            for record in trials:
                record[f"pass@{k}_strict"] = ""
                record[f"pass@{k}_relaxed"] = ""

            print(
                f"{case_name}: incomplete evaluation; no pass@{k} score"
            )

            continue

        case_strict_k = int(
            any(
                float(record["functionality"]) == 1.0
                for record in trials
            )
        )

        case_relaxed_k = int(
            any(
                float(record["func_relaxed"]) == 1.0
                for record in trials
            )
        )

        for record in trials:
            record[f"pass@{k}_strict"] = case_strict_k
            record[f"pass@{k}_relaxed"] = case_relaxed_k

        total_k += 1
        strict_k += case_strict_k
        relaxed_k += case_relaxed_k

    save_results(
        output_csv,
        [records[key] for key in sorted(records)],
        k,
    )

    if total_1:
        print(
            f"Pass@1 on {total_1} complete first trials: "
            f"strict {strict_1}/{total_1}, "
            f"relaxed {relaxed_1}/{total_1}"
        )

    if total_k:
        print(
            f"Pass@{k} on {total_k} complete cases: "
            f"strict {strict_k}/{total_k}, "
            f"relaxed {relaxed_k}/{total_k}"
        )


if __name__ == "__main__":
    main()