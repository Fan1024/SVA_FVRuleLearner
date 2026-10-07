"""Run the repository's NL2SVA-Human JasperGold checker on counter_0."""

import csv
import re
import sys
from datetime import datetime
from pathlib import Path

HERE = Path.cwd()  # Run from the fork's new_agent directory.
ROOT = HERE.parent
sys.path[:0] = [str(ROOT / "src"), str(ROOT)]

from FVEval.fv_eval import fv_tool_execution
from FVEval.fv_eval.evaluation import NL2SVAHumanEvaluator

dataset = ROOT / "FVEval/data_nl2sva/data/nl2sva_human.csv"
with dataset.open(newline="", encoding="utf-8") as f:
    row = next(csv.DictReader(f))
assert row["task_id"] == "counter_0"

source = (HERE / "log/counter_0.sva").read_text(encoding="utf-8")
tb, end, trailing = source.rpartition("endmodule")
if not end or trailing.strip():
    raise ValueError("Expected counter_0.sva to end with endmodule")
found = re.findall(r"(?:\b\w+\s*:\s*)?assert\s+property\s*\(.*?\)\s*;", tb, re.S)
if len(found) != 1:
    raise ValueError("Expected exactly one generated assertion in counter_0.sva")
candidate = found[0].strip()
reference = row["ref_solution"].strip()

property_pattern = re.compile(
    r"(?:\w+\s*:\s*)?assert\s+property\s*\(\s*"
    r"@\s*\(\s*posedge\s+clk\s*\)\s*disable\s+iff\s*"
    r"\(\s*(\w+)\s*\)\s*(.*)\s*\)\s*;",
    re.S,
)
def parts(assertion):
    match = property_pattern.fullmatch(assertion)
    if not match:
        raise ValueError("Expected assert property (@(posedge clk) disable iff (SIGNAL) BODY);")
    return match.group(1), match.group(2).strip()

candidate_reset, candidate_body = parts(candidate)
reference_reset, reference_body = parts(reference)

run_dir = HERE / "log" / ("judge_counter_0_" + datetime.now().strftime("%Y%m%d_%H%M%S%f"))
run_dir.mkdir(parents=True)
exp_id, task_id = "nl2sva_human", "counter_counter_0_trial_0"
packaged = run_dir / f"{exp_id}_{task_id}.sva"
packaged.write_text(
    tb + "\n" + reference.replace("asrt:", "reference:", 1) + "\nendmodule\n",
    encoding="utf-8",
)

# Original signal selection: quoted question signals and testbench parameters.
signals = re.findall(r"'([^'\s]+)'", row["prompt"])
signals += [m[2] for m in re.findall(
    r"\b(parameter|localparam)\s+(int\s+|real\s+|bit\s+|\[[^]]+\]\s*)?(\w+)",
    tb,
)]
# This particular generated candidate uses a signal omitted by the question.
if "net_incr_d1" in candidate_body and "net_incr_d1" not in signals:
    signals.append("net_incr_d1")
    print("Added net_incr_d1 to the PEC signal list; the original question omits it.")

output = fv_tool_execution.launch_jg_custom_equiv_check(
    tcl_file_path=str(ROOT / "FVEval/tool_scripts/run_jg_nl2sva_human.tcl"),
    sv_dir=str(run_dir), experiment_id=exp_id, task_id=task_id,
    lm_assertion_text=candidate_body, ref_assertion_text=reference_body,
    signal_list_text=",".join(signals),
)
log = run_dir / "jasper.log"
log.write_text(output or "", encoding="utf-8")
print("Packaged SVA:", packaged)
print("Jasper output:", log)
if not output or "TASK_ID" not in output or "TIMEOUT" in output:
    raise RuntimeError("No reliable Jasper verdict; inspect jasper.log")
print("Repository PEC scores:", NL2SVAHumanEvaluator.calculate_jg_metric(None, output))
if candidate_reset != reference_reset:
    print("Different disable iff conditions:", candidate_reset, "versus", reference_reset)
    print("PEC compares the extracted bodies; this is not full-assertion equivalence.")
