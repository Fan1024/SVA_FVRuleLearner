"""Edit these settings to choose the data, models, budget, and saved evidence."""

from pathlib import Path

# "train" or "inference"; launch both with python main.py.
MODE = "train"


# Supported CSV stems: "nl2sva_human" or "nl2sva_machine".
# Each dataset uses its native FVRuleLearner evaluator and comparison scope.
DATASET = "nl2sva_human"
DATASET_PATH = (
    Path(__file__).resolve().parent.parent
    / "FVEval"
    / "data_nl2sva"
    / "data"
    / f"{DATASET}.csv"
)

# [] = split the full dataset and train only on the training portion.
# [1] or [1, 5, 20] = run exactly these examples, bypassing the random split.
# These numbers are not physical CSV line numbers or source task_id values.
# Start with the FIFO example from the failing trace. Change this selection
# after confirming diagnosis/rule output, or use [] for the training split.
TRAIN_CASE_IDS = [69]

# Used only when TRAIN_CASE_IDS = []. The remainder is reserved for inference.
# Training count = int(total cases * TRAIN_FRACTION); both parts must be nonempty.
TRAIN_FRACTION = 0.8

# Keep this seed and the CSV unchanged to reproduce the same split.
SPLIT_SEED = 42

# Models for the two generation components. Jev uses its service default.
ASSERTION_MODEL = "gpt-5.6-terra"
RULE_MODEL = "gpt-5.6-terra"

# Total assertion attempts: 10 = initial generation + at most nine revisions.
MAX_ROUNDS = 10

# Requested Jasper timeout for native launchers that expose a timeout setting.
# An unmodified launcher's fixed limit (e.g. 60 s) remains authoritative.
JASPER_TIMEOUT_SECONDS = 300

# Minimum diagnosis confidence for statements sent to the rule generator.
CONFIDENCE_THRESHOLD = 0.2

# Every invocation creates a separate experiment directory here.
RUNS_DIR = Path(__file__).resolve().parent / "runs"

# None selects the most recently completed compatible Train run.
# An absolute path or a directory name relative to RUNS_DIR selects one run.
# This SAME run determines the excluded training cases and the retrieval bank.
TRAINING_RUN_DIR = None

# [] = every held-out case. Nonempty IDs must be outside the selected training run.
INFER_CASE_IDS = []

# Retrieve up to this many cases WITH rules, ranked by requirement similarity.
TOP_K_CASES = 5
EMBEDDING_MODEL = "all-MiniLM-L6-v2"

# True saves detailed round evidence. False saves only final case records,
# final scores/rules, and the latest formal input/log; no round history or raw
# model responses are saved. Temporary tool work is removed when ownership permits.
SAVE_DEBUG_TRACES = True


