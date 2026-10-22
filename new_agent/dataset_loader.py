"""Read, select, and split NL2SVA examples without running experiments.

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


def load_inference_cases(
    dataset_path: str | Path, training_metadata: dict, case_ids: list[int] | None = None,
) -> list[dict]:
    """Use the selected run's saved split, or exclude its entire explicit selection.

    Exclusion includes cases that passed immediately and cases without rules.
    Inference never derives the training population from the filtered rule bank.
    select_training_run verifies CSV identity before this function is called.
    """
    cases = load_cases(dataset_path, case_ids)
    all_cases = cases if not case_ids else read_dataset(dataset_path)
    case_map = {case["case_number"]: case for case in all_cases}
    selected = training_metadata.get("selected_cases")
    if not isinstance(selected, list) or not selected or any(not isinstance(c, dict) for c in selected):
        raise ValueError("Training metadata needs a nonempty selected_cases list.")
    training_ids = [case.get("case_number") for case in selected]
    if (any(type(number) is not int or number not in case_map for number in training_ids)
            or len(training_ids) != len(set(training_ids))):
        raise ValueError("Training selected_cases contains invalid or duplicate case IDs.")
    for saved in selected:
        current = case_map[saved["case_number"]]
        if any(saved.get(key) != current[key] for key in ("design_name", "task_id")):
            raise ValueError("Training case identities do not match the current CSV.")
    training_set = set(training_ids)
    split = training_metadata.get("settings", {}).get("dataset_split")
    if split is None:
        inference_ids = [n for n in case_map if n not in training_set]
    else:
        if not isinstance(split, dict) or split.get("training_case_ids") != training_ids:
            raise ValueError("The recorded training selection does not match the saved split.")
        inference_ids = split.get("inference_case_ids")
        if (not isinstance(inference_ids, list) or
            any(type(n) is not int for n in inference_ids) or
            len(inference_ids) != len(set(inference_ids))):
            raise ValueError("Saved inference IDs must be unique integers.")
        if training_set & set(inference_ids) or training_set | set(inference_ids) != set(case_map):
            raise ValueError("The saved split must be disjoint and cover the current CSV exactly.")
    if not inference_ids:
        raise ValueError("The selected training run leaves no held-out inference cases.")
    if case_ids:
        invalid = [n for n in case_ids if n not in set(inference_ids)]
        if invalid:
            raise ValueError(f"INFER_CASE_IDS includes training cases: {invalid}.")
        return cases
    return [case_map[n] for n in inference_ids]
