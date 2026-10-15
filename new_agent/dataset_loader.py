"""Read, select, and split NL2SVA examples without running experiments.

Run this file directly to preview the training selection from config.py.
Use --inference to preview held-out cases from a saved training experiment.
The loader uses only the Python standard library and imports no model/tool code.
"""

import csv
from math import isfinite
from pathlib import Path
from random import Random


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
    """Load numbered examples without splitting; None or [] reads all examples.

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


def split_cases(
    cases: list[dict], *, train_fraction: float, split_seed: int,
) -> tuple[list[dict], list[dict]]:
    """Randomly partition whole examples; preserve original IDs and file order.

    The training count is rounded down. Every remaining example belongs to
    inference. A local random generator leaves global random state unchanged.
    """
    if (
        type(train_fraction) not in (int, float)
        or not isfinite(train_fraction)
        or not 0 < train_fraction < 1
    ):
        raise ValueError("TRAIN_FRACTION must be a finite number strictly between 0 and 1.")
    if type(split_seed) is not int or split_seed < 0:
        raise ValueError("SPLIT_SEED must be a nonnegative integer.")
    if len(cases) < 2:
        raise ValueError("A train/inference split requires at least two examples.")

    training_count = int(len(cases) * train_fraction)
    if not 1 <= training_count < len(cases):
        raise ValueError(
            f"TRAIN_FRACTION={train_fraction} gives {training_count} training examples "
            f"out of {len(cases)}. Choose a fraction that leaves both parts nonempty."
        )

    positions = list(range(len(cases)))
    Random(split_seed).shuffle(positions)
    training_positions = set(positions[:training_count])
    training = [case for index, case in enumerate(cases) if index in training_positions]
    inference = [case for index, case in enumerate(cases) if index not in training_positions]
    return training, inference


def load_training_cases(
    dataset_path: str | Path, case_ids: list[int] | None = None, *,
    train_fraction: float, split_seed: int,
) -> tuple[list[dict], dict | None]:
    """Prepare training inputs and optional split metadata for the experiment.

    Explicit IDs bypass splitting. An empty selection splits the full CSV and
    returns only training inputs; inference IDs are reserved in the metadata.
    """
    cases = load_cases(dataset_path, case_ids)
    if case_ids:
        return cases, None

    training, inference = split_cases(
        cases, train_fraction=train_fraction, split_seed=split_seed,
    )
    split = {
        "train_fraction": train_fraction,
        "seed": split_seed,
        "training_case_ids": [case["case_number"] for case in training],
        "inference_case_ids": [case["case_number"] for case in inference],
    }
    return training, split


def load_inference_cases(dataset_path: str | Path, training_metadata: dict) -> list[dict]:
    """Load saved held-out IDs after select_training_run checks the dataset hash.

    Validate complete, disjoint membership against the current parsed examples.
    Failed or unfinished training cases never move into the inference group.
    """
    cases = read_dataset(dataset_path)
    split = training_metadata["settings"]["dataset_split"]
    training_ids = split.get("training_case_ids")
    inference_ids = split.get("inference_case_ids")
    for name, numbers in (
        ("training_case_ids", training_ids),
        ("inference_case_ids", inference_ids),
    ):
        if (
            not isinstance(numbers, list) or not numbers
            or any(type(number) is not int for number in numbers)
            or len(numbers) != len(set(numbers))
        ):
            raise ValueError(f"Saved {name} must be a nonempty list of unique integer IDs.")
    training_set, inference_set = set(training_ids), set(inference_ids)
    if training_set & inference_set:
        raise ValueError("Saved training and inference case IDs overlap.")
    if training_set | inference_set != {case["case_number"] for case in cases}:
        raise ValueError("The saved split must cover the current dataset exactly.")
    selected_cases = training_metadata.get("selected_cases", [])
    if (
        not isinstance(selected_cases, list)
        or any(not isinstance(case, dict) for case in selected_cases)
    ):
        raise ValueError("Training metadata has an invalid selected_cases list.")
    if [case.get("case_number") for case in selected_cases] != training_ids:
        raise ValueError("The recorded training selection does not match the saved split.")
    case_map = {case["case_number"]: case for case in cases}
    return [case_map[number] for number in inference_ids]


def main(argv=None) -> None:
    """Preview training inputs or a saved inference selection; make no model calls."""
    import argparse
    import config

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inference", action="store_true", help="Preview the saved inference cases.")
    args = parser.parse_args(argv)
    if args.inference:
        import run_io

        directory, metadata = run_io.select_training_run(
            dataset=config.DATASET, dataset_path=resolve_dataset_path(config.DATASET_PATH),
            runs_root=config.RUNS_DIR, training_run_dir=config.TRAINING_RUN_DIR,
        )
        cases = load_inference_cases(config.DATASET_PATH, metadata)
        split = None
        print(f"Training source: {directory}")
        print(f"Saved inference case IDs: {[case['case_number'] for case in cases]}")
    else:
        cases, split = load_training_cases(
            config.DATASET_PATH, config.CASE_IDS,
            train_fraction=config.TRAIN_FRACTION, split_seed=config.SPLIT_SEED,
        )
    print(f"Dataset: {cases[0]['dataset_path']}")
    if split is not None:
        print(f"Random split: training fraction {split['train_fraction']}; seed {split['seed']}")
        print(f"Training case IDs ({len(cases)}): {split['training_case_ids']}")
        print(
            f"Reserved inference case IDs ({len(split['inference_case_ids'])}): "
            f"{split['inference_case_ids']}"
        )
    elif not args.inference:
        print("Explicit case selection: random splitting is not applied.")
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
