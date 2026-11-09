"""Remove Block cases whose reference fails the PEC self-check; log them in raw.

Usage, from the repository root, with a full-dataset self-check summary:
    python new_agent/prune_block_dataset.py --summary new_agent/runs/PEC_selfcheck_<stamp>/summary.csv

nl2sva_block.csv keeps only rows whose reference passed (preflight_status PASS);
non-PROVEN rows (the immediate assertion) are removed too. Kept rows are
renumbered per design (<design>_0, _1, ...), so task_id stays contiguous and
case numbers (row positions) shift up. nl2sva_block_raw.csv keeps every row and
gains three columns linking it to the curated file:
    block_status     KEPT, the self-check failure status, EXCLUDED_<jg_status>,
                     or empty when the target never entered nl2sva_block.csv
    block_task_id    the new nl2sva_block.csv task_id of a kept row
    block_detail     the old block task_id and the self-check error, if any
Rows are matched to raw by (design_name, assertion label), which is unique.
Run once, on the unpruned CSV that the summary was produced from.

With --case-ids, only those case numbers are removed (each must have failed
in the summary); every other row, including non-PROVEN rows, is kept.
"""

import argparse
import csv
from collections import Counter, defaultdict
import io
from pathlib import Path
import re


REPO_ROOT = Path(__file__).resolve().parents[1]
BLOCK = Path("Data/nl2sva_block.csv")
RAW = Path("Data/nl2sva_block_raw.csv")
NEW_COLUMNS = ("block_status", "block_task_id", "block_detail")


def read(path):
    text = path.read_bytes().decode("utf-8-sig")  # Keep \r\n; read_text would translate it.
    terminator = "\r\n" if "\r\n" in text else "\n"
    reader = csv.DictReader(io.StringIO(text, newline=""))
    return list(reader.fieldnames), list(reader), terminator


def write(path, fields, rows, terminator):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=fields, lineterminator=terminator)
    writer.writeheader()
    writer.writerows(rows)
    path.write_text(stream.getvalue(), encoding="utf-8", newline="")


def label(source):
    match = re.match(r"\s*([A-Za-z_]\w*)\s*:", source)
    if not match:
        raise ValueError(f"Reference has no assertion label: {source[:80]!r}")
    return match.group(1)


def prune(repo, summary_path, *, case_ids=None, dry_run=False):
    block_path, raw_path = repo / BLOCK, repo / RAW
    block_fields, block_rows, block_end = read(block_path)
    raw_fields, raw_rows, raw_end = read(raw_path)
    if any(name in raw_fields for name in NEW_COLUMNS):
        raise ValueError("nl2sva_block_raw.csv already has block_* columns; it was pruned before.")
    with Path(summary_path).open(encoding="utf-8-sig", newline="") as stream:
        summary = {int(row["case_number"]): row for row in csv.DictReader(stream)
                   if row.get("dataset", "nl2sva_block") == "nl2sva_block"}

    selected = set(case_ids or ())
    unknown = sorted(selected - set(range(1, len(block_rows) + 1)))
    if unknown:
        raise ValueError(f"Case IDs {unknown} are not rows of nl2sva_block.csv.")
    kept, removed = [], []
    for number, row in enumerate(block_rows, start=1):
        if selected and number not in selected:
            kept.append(row)
            continue
        if row["jg_status"].strip() != "PROVEN":
            removed.append((row, "EXCLUDED_" + row["jg_status"].strip(), ""))
            continue
        result = summary.get(number)
        if result is None:
            raise ValueError(f"Case {number} ({row['task_id']}) is missing from the summary; "
                             "run the self-check on the whole Block dataset.")
        if (result["design_name"], result["task_id"]) != (row["design_name"], row["task_id"]):
            raise ValueError(f"Case {number} is {row['task_id']} in the CSV but {result['task_id']} "
                             "in the summary; the CSV changed after the self-check.")
        if result["preflight_status"] == "PASS":
            if selected:
                raise ValueError(f"Case {number} ({row['task_id']}) passed the self-check; refusing to remove it.")
            kept.append(row)
        else:
            removed.append((row, result["preflight_status"], result.get("error") or ""))

    raw_index = {(row["design_name"], label(row["ref_solution"])): row for row in raw_rows}
    if len(raw_index) != len(raw_rows):
        raise ValueError("Raw (design, label) pairs are not unique.")
    for row in raw_rows:
        row.update(dict.fromkeys(NEW_COLUMNS, ""))

    def raw_row(row):
        key = (row["design_name"], label(row["ref_solution"]))
        if key not in raw_index:
            raise ValueError(f"No raw row for {key}.")
        return raw_index[key]

    counters = defaultdict(int)
    for row in kept:
        new_id = f"{row['design_name']}_{counters[row['design_name']]}"
        counters[row["design_name"]] += 1
        raw_row(row).update(block_status="KEPT", block_task_id=new_id,
                            block_detail=f"previous block task_id {row['task_id']}")
        row["task_id"] = new_id
    for row, status, error in removed:
        detail = f"previous block task_id {row['task_id']}"
        raw_row(row).update(block_status=status,
                            block_detail=detail + (f"; {' '.join(error.split())}" if error else ""))

    if not dry_run:
        write(block_path, block_fields, kept, block_end)
        write(raw_path, raw_fields + list(NEW_COLUMNS), raw_rows, raw_end)
    statuses = Counter(status for _, status, _ in removed)
    print(f"{'Would keep' if dry_run else 'Kept'} {len(kept)} of {len(block_rows)} Block rows; "
          f"removed {len(removed)}: {dict(statuses)}")
    for row, status, _ in removed:
        print(f"  removed {row['task_id']:40s} {status}")
    return kept, removed


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--summary", type=Path, required=True, help="Self-check summary.csv for all Block cases.")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--case-ids", type=int, nargs="+",
                        help="Remove only these failed case numbers instead of every non-PASS case.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    prune(args.repo_root.resolve(), args.summary, case_ids=args.case_ids, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
