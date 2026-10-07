import csv
import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from openai import OpenAI

import config

SYSTEM_PROMPT = (
    "You write SystemVerilog assertions (SVA) from natural-language requirements. "
    "Use the provided testbench to identify the relevant signals, clock, and reset. "
    "Generate exactly one assertion that checks the requested behavior. "
    "Return only the assertion enclosed in <CODE> and </CODE>. "
    "Do not include Markdown, explanations, or other text."
)


def select_cases(rows):
    """Select 1-based CSV data rows in file order; [] selects them all."""
    numbers = config.CASE_NUMBER
    if not isinstance(numbers, list) or any(
        type(n) is not int or n < 1 or n > len(rows) for n in numbers
    ):
        raise ValueError(
            f"CASE_NUMBER must be a list of integers from 1 to {len(rows)}"
        )
    if len(numbers) != len(set(numbers)):
        raise ValueError("CASE_NUMBER contains duplicate row numbers")

    selected = set(numbers) if numbers else set(range(1, len(rows) + 1))
    return [
        (number, row)
        for number, row in enumerate(rows, 1)
        if number in selected
    ]


def main(run_dir=None):
    if config.DATASET not in {"nl2sva_human", "nl2sva_machine"}:
        raise ValueError(
            "DATASET must be 'nl2sva_human' or 'nl2sva_machine'"
        )
    if type(config.NUM_SAMPLES) is not int or config.NUM_SAMPLES < 1:
        raise ValueError("NUM_SAMPLES must be a positive integer")

    dataset_path = Path(config.DATA_DIR) / f"{config.DATASET}.csv"
    with dataset_path.open(newline="", encoding="utf-8") as csv_file:
        rows = list(csv.DictReader(csv_file))
    if not rows:
        raise ValueError(f"No cases found in {dataset_path}")

    cases = select_cases(rows)

    # Give cases distinct directories even if task IDs repeat.
    task_ids = [row["task_id"] for _, row in cases]
    counts = Counter(task_ids)
    case_dirs = {}
    used_dirs = set()

    for number, row in cases:
        task_id = row["task_id"]
        case_name = (
            task_id
            if counts[task_id] == 1
            else f"{row['design_name']}_{task_id}"
        )
        if case_name in used_dirs:
            case_name = f"row_{number:04d}_{case_name}"
        if not re.fullmatch(r"[A-Za-z0-9_-]+", case_name):
            raise ValueError(
                f"A selected case cannot be used as a directory name: "
                f"{case_name}"
            )
        used_dirs.add(case_name)
        case_dirs[str(number)] = case_name

    model_dir = re.sub(r"[^A-Za-z0-9._-]+", "_", config.MODEL)
    if model_dir in {"", ".", ".."}:
        raise ValueError("MODEL cannot be used as a directory name")

    manifest = {
        "dataset": config.DATASET,
        "dataset_path": str(dataset_path.resolve()),
        "dataset_sha256": hashlib.sha256(
            dataset_path.read_bytes()
        ).hexdigest(),
        "model": config.MODEL,
        "case_number": [number for number, _ in cases],
        "case_dirs": case_dirs,
        "num_samples": config.NUM_SAMPLES,
        "system_prompt": SYSTEM_PROMPT,
        "user_message_template": (
            "Testbench:\n{testbench}\n\n"
            "Question: Create an SVA assertion that checks: {prompt}"
        ),
    }

    if run_dir is None:
        run_id = datetime.now(timezone.utc).strftime(
            "%Y%m%dT%H%M%S%fZ"
        )
        run_dir = (
            Path(config.LOG_ROOT)
            / config.DATASET
            / config.EXPERIMENT
            / model_dir
            / run_id
        )
        run_dir.mkdir(parents=True, exist_ok=False)
        manifest["created_utc"] = run_id
        (run_dir / "manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n",
            encoding="utf-8",
        )
    else:
        run_dir = Path(run_dir).expanduser().resolve()
        existing = json.loads(
            (run_dir / "manifest.json").read_text(encoding="utf-8")
        )
        if any(
            existing.get(key) != value
            for key, value in manifest.items()
        ):
            raise ValueError(
                "Run manifest differs from config.py or the dataset; "
                "cannot resume safely"
            )

    client = OpenAI()
    print(f"Dataset: {dataset_path}")
    print(f"Saving responses to: {run_dir}")

    for number, row in cases:
        user_text = (
            f"Testbench:\n{row['testbench']}\n\n"
            f"Question: Create an SVA assertion that checks: "
            f"{row['prompt']}"
        )
        case_dir = run_dir / case_dirs[str(number)]

        for trial in range(1, config.NUM_SAMPLES + 1):
            output_path = case_dir / f"trial_{trial:02d}.txt"
            if output_path.is_file() and output_path.stat().st_size > 0:
                print(f"Already saved: {output_path}", flush=True)
                continue

            # Each trial starts with fresh messages.
            state = {
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_text},
                ]
            }

            print(
                f"Row {number}: {row['design_name']} / "
                f"{row['task_id']}, trial "
                f"{trial}/{config.NUM_SAMPLES}",
                flush=True,
            )

            response = client.responses.create(
                model=config.MODEL,
                input=state["messages"],
            )
            if not response.output_text:
                raise RuntimeError(
                    f"Empty response for row {number}, trial {trial}"
                )

            state["messages"].append(
                {"role": "assistant", "content": response.output_text}
            )
            case_dir.mkdir(parents=True, exist_ok=True)
            output_path.write_text(
                response.output_text,
                encoding="utf-8",
            )
            print(f"Saved: {output_path}", flush=True)

    return run_dir


if __name__ == "__main__":
    main()