"""Read an NL2SVA CSV and select numbered examples without running experiments.

Place this file in new_agent/. Run it directly to inspect the fixed test selection.
The loader uses only the Python standard library and imports no model/tool code.
"""

import csv
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
REQUIRED_COLUMNS = ("design_name", "task_id", "prompt", "ref_solution", "testbench")


def resolve_dataset_path(dataset_path: str | Path) -> Path:
    """Resolve ~, absolute paths, or paths relative to the repository root."""
    if not isinstance(dataset_path, (str, Path)) or not str(dataset_path).strip():
        raise ValueError("dataset_path must be a nonempty file path.")
    path = Path(dataset_path).expanduser()
    if not path.is_absolute():
        path = REPO_ROOT / path
    path = path.resolve()
    if not path.exists():
        raise FileNotFoundError(f"Dataset file does not exist: {path}")
    if not path.is_file():
        raise ValueError(f"Dataset path must point to a CSV file, not a directory: {path}")
    return path


def read_dataset(dataset_path: str | Path) -> list[dict]:
    """Validate a CSV and normalize its examples into pipeline input names.

    case_number is the 1-based parsed-example position, excluding the header.
    It is not a physical text-line number or a number extracted from task_id.
    Extra named CSV columns are allowed but are not used by this loader.
    """
    path = resolve_dataset_path(dataset_path)
    cases = []
    identities = set()

    # newline="" lets csv handle quoted multiline assertions and testbenches.
    # utf-8-sig also accepts a UTF-8 byte-order mark before the header.
    with path.open(encoding="utf-8-sig", newline="") as file:
        reader = csv.DictReader(file, strict=True)
        columns = reader.fieldnames
        if columns is None:
            raise ValueError(f"Dataset is empty: {path}")
        if len(columns) != len(set(columns)):
            raise ValueError("CSV header contains duplicate column names.")
        missing = [name for name in REQUIRED_COLUMNS if name not in columns]
        if missing:
            raise ValueError(f"CSV is missing required columns: {', '.join(missing)}")

        for number, row in enumerate(reader, start=1):
            if None in row:
                raise ValueError(f"Example {number} has more values than the CSV header.")
            empty = [name for name in REQUIRED_COLUMNS if not (row[name] or "").strip()]
            if empty:
                raise ValueError(
                    f"Example {number} has missing or empty fields: {', '.join(empty)}"
                )
            identity = (row["design_name"].strip(), row["task_id"].strip())
            if identity in identities:
                raise ValueError(f"Duplicate design/task identity at example {number}: {identity}")
            identities.add(identity)
            cases.append({
                "case_number": number,
                "dataset_path": str(path),
                "design_name": identity[0],
                "task_id": identity[1],
                "requirement": row["prompt"].strip(),
                "reference_assertion": row["ref_solution"].strip(),
                "testbench": row["testbench"].strip(),
            })

    if not cases:
        raise ValueError(f"Dataset contains a header but no examples: {path}")
    return cases


def load_cases(dataset_path: str | Path, case_ids: list[int] | None = None) -> list[dict]:
    """Load and select examples; None or [] selects all in file order.

    A nonempty selection preserves the requested order. Invalid selections
    raise before returning any cases, so the caller cannot start a partial run.
    The full CSV is validated, including examples outside the selection.
    """
    if case_ids is None:
        case_ids = []
    if not isinstance(case_ids, list) or any(type(number) is not int for number in case_ids):
        raise ValueError("case_ids must be a list of integers, such as [] or [1, 5, 20].")
    if any(number < 1 for number in case_ids):
        raise ValueError("Case IDs start at 1; zero and negative values are invalid.")
    if len(case_ids) != len(set(case_ids)):
        raise ValueError("case_ids contains duplicate case IDs.")

    cases = read_dataset(dataset_path)
    if not case_ids:
        return cases

    case_map = {case["case_number"]: case for case in cases}
    invalid = [number for number in case_ids if number not in case_map]
    if invalid:
        raise ValueError(
            f"Case IDs {invalid} do not exist. This dataset has {len(cases)} examples; "
            f"valid IDs are 1 through {len(cases)}."
        )
    return [case_map[number] for number in case_ids]


def main() -> None:
    """Standalone inspection only. Edit these two test values before running."""
    dataset_path = "FVEval/data_nl2sva/data/nl2sva_human.csv"
    case_ids = [1, 5, 20]

    cases = load_cases(dataset_path, case_ids)
    print(f"Dataset: {cases[0]['dataset_path']}")
    print(f"Selected {len(cases)} example(s).")
    for case in cases:
        print(
            f"Case {case['case_number']}: "
            f"{case['design_name']} / {case['task_id']}"
        )
        print(f"  Requirement: {case['requirement']}")
        print(
            f"  Reference: {len(case['reference_assertion'])} characters; "
            f"testbench: {len(case['testbench'])} characters"
        )
    print("Dataset inspection complete. No model or formal-tool calls were made.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, csv.Error, ValueError) as error:
        raise SystemExit(f"Dataset validation failed: {error}")
