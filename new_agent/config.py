"""Edit these settings to choose the data, models, budget, and saved evidence."""

from pathlib import Path

# "train": learn rules on selected training cases.
# "inference": exclude source training cases and retrieve learned rules.
# "inference_only": three fixed examples; no retrieval or separate diagnosis.
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

# Used only by MODE = "inference_only". [] runs the entire dataset without a
# train/test split or training-run dependency; [1, 32] selects specific cases.
INFERENCE_ONLY_CASE_IDS = []

# Used only when TRAIN_CASE_IDS = []. The remainder is reserved for inference.
# Training count = int(total cases * TRAIN_FRACTION); both parts must be nonempty.
TRAIN_FRACTION = 0.8

# Keep this seed and the CSV unchanged to reproduce the same split.
SPLIT_SEED = 100

# Models for assertion generation, training diagnosis and inference selection.
ASSERTION_MODEL = "gpt-5.6-terra"
RULE_MODEL = "gpt-5.6-terra"
# RULE_MODEL runs training diagnosis/rules and inference selection.

# Official API routing is inferred from these unchanged model-ID settings.
# Enabled alternatives: "kimi-k3.1-pro", "kimi-k3.1-pro-highspeed",
# "deepseek-v4-pro", "deepseek-flash". Claude is excluded because its
# compatibility endpoint rejects the required JSON-object output mode.
# Keys: OPENAI_API_KEY, MOONSHOT_API_KEY, DEEPSEEK_API_KEY, as applicable.
# None preserves provider defaults (and the existing OpenAI request).
# For a controlled comparison, set both options explicitly for every model;
# "high" and 32768 are accepted by all enabled comparison routes.
MODEL_REASONING_EFFORT = None
MODEL_MAX_OUTPUT_TOKENS = None

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
# Independently rank existing training diagnoses and correction rules.
TOP_K_DIAGNOSES = 5
TOP_K_RULES = 5
EMBEDDING_MODEL = "all-MiniLM-L6-v2"

# True additionally writes readable debug_trace.txt files.
# Final scores and learned-rule evidence are saved regardless of this setting.
# Formal-tool work and native logs remain temporary.
SAVE_DEBUG_TRACES = True

# Expand TB signal names and bind known integral parameters in native PEC inputs.
# A server-verified pec_interface_probe.json also enables typed signal entries.
# "legacy" keeps the native name-only inputs for baseline comparisons.
PEC_CONTEXT_MODE = "expanded_names"
PEC_CONTEXT_MODULE = None

# Pyslang establishes SVA grouping. Unsupported translations use original source.
ASSERTION_TREE_PARSER = "pyslang"






