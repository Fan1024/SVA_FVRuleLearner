"""Generate the configured cases, then evaluate that run with JasperGold."""

import argparse
import subprocess
import sys
from pathlib import Path

from agent import main as generate_assertions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--resume-run-dir",
        type=Path,
        help="Retry missing model responses in an existing run",
    )
    args = parser.parse_args()

    run_dir = generate_assertions(run_dir=args.resume_run_dir)
    evaluator = Path(__file__).resolve().with_name("evaluate.py")

    print(f"Generation complete. Evaluating: {run_dir}", flush=True)
    subprocess.run(
        [sys.executable, str(evaluator), "--run-dir", str(run_dir)],
        check=True,
    )
    return run_dir


if __name__ == "__main__":
    main()