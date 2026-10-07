from pathlib import Path


NEW_AGENT_DIR = Path(__file__).resolve().parent
REPO_ROOT = NEW_AGENT_DIR.parent

# Choose "nl2sva_human" or "nl2sva_machine".
DATASET = "nl2sva_machine"
DATA_DIR = REPO_ROOT / "FVEval" / "data_nl2sva" / "data"

MODEL = "gpt-5.6-terra"
CASE_NUMBER = []  # CSV data rows, starting at 1; [] selects every row.
NUM_SAMPLES = 5   # Five independent requests for each selected case.

LOG_ROOT = NEW_AGENT_DIR / "log"
EXPERIMENT = "baseline"



EVAL_RUN_DIR = (
    LOG_ROOT / "nl2sva_human" / "baseline" / "gpt-5.6-terra"
    / "20260925T064015448750Z"
)


op_sel_method = "Jev"