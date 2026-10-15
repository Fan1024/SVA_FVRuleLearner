"""Edit these settings to choose the data, models, budget, and saved evidence."""

from pathlib import Path


# CSV filename without its extension. Also used as the experiment label.
DATASET = "nl2sva_human"
DATASET_PATH = (
    Path(__file__).resolve().parent.parent
    / "FVEval"
    / "data_nl2sva"
    / "data"
    / f"{DATASET}.csv"
)

# 1-based parsed examples: [] = all, [1] = first, [1, 5, 20] = selected examples.
# These numbers are not physical CSV line numbers or source task_id values.
CASE_IDS = [1]

# Models for the two generation components. Jev uses its service default.
ASSERTION_MODEL = "gpt-5.6-terra"
RULE_MODEL = "gpt-5.6-terra"

# Total assertion attempts per case: 2 = initial generation + at most one revision.
MAX_ROUNDS = 2

# Maximum duration of each Jasper invocation, in seconds.
JASPER_TIMEOUT_SECONDS = 300

# Minimum diagnosis confidence for statements sent to the rule generator.
CONFIDENCE_THRESHOLD = 0.4

# Every invocation creates a separate experiment directory here.
RUNS_DIR = Path(__file__).resolve().parent / "runs"

# True saves detailed round evidence. False saves only final case records,
# final scores/rules, and the latest formal input/log; no round history or raw
# model responses are saved. Temporary tool work is removed when ownership permits.
SAVE_DEBUG_TRACES = False
