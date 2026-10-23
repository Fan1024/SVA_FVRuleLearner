"""Edit these settings to choose the data, models, budget, and saved evidence."""

from pathlib import Path

# "train": learn rules on selected training cases.
# "inference": exclude source training cases and retrieve learned rules.
# Launch every mode with python main.py.
MODE = "train"


# Supported datasets: nl2sva_human, nl2sva_machine, nl2sva_opencore.
DATASET = "nl2sva_machine"
REPO_ROOT = Path(__file__).resolve().parent.parent
DATASET_PATH = (
    REPO_ROOT / "FVEval" / "data_1k" / "module_sva_nl_manual_editing.csv"
    if DATASET == "nl2sva_opencore" else
    REPO_ROOT / "FVEval" / "data_nl2sva" / "data" / f"{DATASET}.csv"
)

# [] = split the full dataset and train only on the training portion.
# [1] or [1, 5, 20] = run exactly these examples, bypassing the random split.
# These numbers are not physical CSV line numbers or source task_id values.
TRAIN_CASE_IDS = []

# Used only when TRAIN_CASE_IDS = []. The remainder is reserved for inference.
# Training count = int(total cases * TRAIN_FRACTION); both parts must be nonempty.
TRAIN_FRACTION = 0.8

# Keep this seed and the CSV unchanged to reproduce the same split.
SPLIT_SEED = 100

# Models for the two generation components. Jev uses its service default.
ASSERTION_MODEL = "gpt-5.6-terra"
RULE_MODEL = "gpt-5.6-terra"

# Total assertion attempts: 10 = initial generation + at most nine revisions.
MAX_ROUNDS = 10

# Requested Jasper timeout for native launchers that expose a timeout setting.
# An unmodified launcher's fixed limit (e.g. 60 s) remains authoritative.
JASPER_TIMEOUT_SECONDS = 300

# Minimum confidence for training statements and inference rule applicability.
CONFIDENCE_THRESHOLD = 0.2

# Every invocation creates a separate experiment directory here.
RUNS_DIR = Path(__file__).resolve().parent / "runs"

# Used only by MODE = "inference". Ignored by train.
# None selects the most recently completed compatible Train run.
# An absolute path or a directory name relative to RUNS_DIR selects one run.
# This SAME run determines the excluded training cases and the retrieval bank.
TRAINING_RUN_DIR = None

# Inference always runs every dataset case outside the selected training run.
# Case IDs are determined automatically; there is no inference ID override.

# Retrieve up to this many cases WITH rules, ranked by requirement similarity.
TOP_K_CASES = 5
EMBEDDING_MODEL = "all-MiniLM-L6-v2"

# True additionally writes readable debug_trace.txt files.
# Final scores and learned-rule evidence are saved regardless of this setting.
# Formal-tool work and native logs remain temporary.
SAVE_DEBUG_TRACES = True


