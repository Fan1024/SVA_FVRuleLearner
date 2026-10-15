"""User-controlled settings for the current fixed-counter experiment."""

from pathlib import Path


# Models used by the two OpenAI components.
ASSERTION_MODEL = "gpt-5.6-terra"
RULE_MODEL = "gpt-5.6-terra"

# Experiment budget and diagnosis filtering.
MAX_ROUNDS = 2  # Total assertion attempts, including the initial attempt.
JASPER_TIMEOUT_SECONDS = 300
CONFIDENCE_THRESHOLD = 0.4

# Output files. Detailed traces preserve prompts, replies, diagnosis, and logs.
RUNS_DIR = Path(__file__).resolve().parent / "runs"
SAVE_DEBUG_TRACES = True
