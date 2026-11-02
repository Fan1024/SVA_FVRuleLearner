"""Edit these settings to choose the data, model, budget, and saved evidence."""

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

# One model for every LLM call in the experiment:
#   Training: assertion generator + rule generator (includes diagnosis).
#   Inference: assertion generator + selector.
MODEL = "gpt-5.6-terra"

# Enabled model IDs and API keys:
#   gpt-5.6-terra                         -> OPENAI_API_KEY
#   kimi-k3.1-pro / kimi-k3.1-pro-highspeed -> MOONSHOT_API_KEY
#   deepseek-v4-pro / deepseek-flash       -> DEEPSEEK_API_KEY
#   claude-sonnet-5-5 / claude-opus-5-5    -> ANTHROPIC_API_KEY
# Claude uses the native Messages API; install: pip install --upgrade "anthropic>=1.0"
# Optional ANTHROPIC_WORKSPACE_ID selects a workspace for unscoped Claude keys.

# MODEL_REASONING_EFFORT accepts the following values (no silent remapping):
#   gpt-5.6-terra: None, "none", "low", "medium", "high", "xhigh", "max"
#       API keyword: reasoning={"effort": value}; provider default: "medium".
#   kimi-k3.1-pro / kimi-k3.1-pro-highspeed: None, "low", "high", "max"
#       API keyword: reasoning_effort=value; provider default: "max".
#   deepseek-v4-pro / deepseek-flash: None, "low", "high", "max"
#       API keyword: reasoning_effort=value, plus thinking={"type":"enabled"}
#       in extra_body when effort is explicit; provider default: "high".
#   claude-sonnet-5-5 / claude-opus-5-5: None, "low", "medium", "high", "xhigh", "max"
#       API keyword: output_config={"effort": value}; defaults: Sonnet "high", Opus "medium".
# None omits the effort field. The string "none" is only enabled for Terra.
# "high" is supported across the listed models, but does not mean equal compute.
MODEL_REASONING_EFFORT = None

# MODEL_MAX_OUTPUT_TOKENS is a positive integer within the provider's limit:
#   OpenAI -> max_output_tokens; Kimi -> max_completion_tokens;
#   DeepSeek -> max_tokens; native Claude -> max_tokens.
# None omits the limit for OpenAI/Kimi/DeepSeek. Claude REQUIRES an explicit value.
# 32768 is a common comparison cap, including thinking and final-answer tokens.
MODEL_MAX_OUTPUT_TOKENS = None

# Network timeout for each model request. SDK automatic retries are disabled.
# Streaming calls may take longer while the provider continues sending events.
MODEL_REQUEST_TIMEOUT_SECONDS = 600

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
# Formal round logs persist, including failures and Ctrl+C. Successful tool
# work directories are cleaned separately.
SAVE_DEBUG_TRACES = True

# Expand TB signal names and bind known integral parameters in native PEC inputs.
# A server-verified pec_interface_probe.json also enables typed signal entries.
# "legacy" keeps the native name-only inputs for baseline comparisons.
PEC_CONTEXT_MODE = "expanded_names"
PEC_CONTEXT_MODULE = None

# Pyslang establishes SVA grouping. Unsupported translations use original source.
ASSERTION_TREE_PARSER = "pyslang"







