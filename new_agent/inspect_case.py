import csv

from agent import DATASET_PATH, SYSTEM_PROMPT


with DATASET_PATH.open(newline="", encoding="utf-8") as csv_file:
    row = next(csv.DictReader(csv_file), None)

if row is None:
    raise ValueError(f"No cases found in {DATASET_PATH}")

# Keep this expression identical to the user_text construction in agent.py.
user_text = (
    f"Testbench:\n{row['testbench']}\n\n"
    f"Question: Create an SVA assertion that checks: {row['prompt']}"
)

print("DATASET FILE:", DATASET_PATH.resolve())
print("ROW INDEX: 0 (the first data row)")
print("DESIGN NAME:", row["design_name"])
print("TASK ID:", row["task_id"])
print("IS counter_0:", row["design_name"] == "counter" and row["task_id"] == "counter_0")
print("PROMPT AS STORED IN CSV:", repr(row["prompt"]))
print("\n=== SYSTEM MESSAGE SENT TO MODEL ===")
print(SYSTEM_PROMPT)
print("\n=== USER MESSAGE SENT TO MODEL (testbench and question verbatim) ===")
print(user_text)
print("\n=== REFERENCE SOLUTION IN CSV (NOT SENT TO MODEL) ===")
print(row["ref_solution"])
