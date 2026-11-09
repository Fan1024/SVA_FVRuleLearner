"""NL2SVA-Block: dataset facts shared by the loader, prompts and formal check.

Block rows live in Data/nl2sva_block.csv. Unlike Human/Machine, the CSV
testbench column holds a repository-relative path to a clean context under
Data/<design>/tb/, not inline source. Each design has one clock/reset
convention; references sample on that clock and (except reset-observing
targets) use the matching disable iff condition.

Formal checking reuses the native NL2SVA-Machine backend: the leading clock
event is excluded from PEC and any disable iff clause stays in the formula.
Standard library only; no model or tool code is imported here.

Run python -m new_agent.block_dataset to audit the CSV against this module.
"""

import hashlib
from pathlib import Path
import re


DATASET = "nl2sva_block"
NATIVE_BACKEND = "nl2sva_machine"
REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CSV = REPO_ROOT / "Data" / "nl2sva_block.csv"
DATA_ROOT = REPO_ROOT / "Data"

# Only formally PROVEN concurrent targets are experiment cases. The one
# PROVEN_IMMEDIATE row is an immediate assertion the PEC route cannot compare.
INCLUDED_JG_STATUSES = frozenset({"PROVEN"})

# Generic template; per-design templates replace CLOCK_SIGNAL/RESET_CONDITION.
GENERIC_TEMPLATE = "asrt: assert property (@(posedge CLOCK_SIGNAL) disable iff (RESET_CONDITION) BODY);"
# PEC compares disable iff, and reset-observing targets have none.
RESET_NOTE = ("// Omit the disable iff clause only when the requirement itself describes "
              "behavior during reset or at reset release.")

# One clock/reset convention per design, taken from the clean TB ports and
# matching every reference wrapper in Data/nl2sva_block.csv.
DESIGN_CONVENTIONS = {
    "corundum_dma_path": ("clk", "rst"),
    "corundum_tx_rx_datapath": ("clk", "rst"),
    "cva6_frontend_issue_commit": ("clk_i", "!rst_ni"),
    "nvdla_bdma_data_order": ("clk", "!reset_n"),
    "nvdla_cdp_syncfifo_order": ("clk", "!reset_n"),
    "nvdla_conv_pipeline": ("clk", "!reset_n"),
    "nvdla_mcif_order": ("clk", "!reset_n"),
    "nvdla_rubik_merge_transpose": ("clk", "!reset_n"),
    "nyuzi_l2_ring_coherence": ("clk", "reset"),
    "openpiton_pmesh_order": ("clk", "!rst_ok"),
    "openpiton_pmesh_waitcycle": ("clk", "!rst_ok"),
    "openpiton_two_tile_coherence": ("clk", "!reset_n"),
    "opentitan_spi_device_fifo": ("clk_i", "!rst_ni"),
    "opentitan_tlul_socket_order": ("clk", "rst"),
    "pulp_stream_xbar_order": ("clk", "rst"),
    "serv_rvfi_insn_addi": ("clk", "rst"),
    "serv_rvfi_insn_bge": ("clk", "rst"),
    "serv_rvfi_insn_jal": ("clk", "rst"),
    "serv_rvfi_insn_lbu": ("clk", "rst"),
    "serv_rvfi_insn_ori": ("clk", "rst"),
    "serv_rvfi_insn_sll": ("clk", "rst"),
    "serv_rvfi_insn_sw": ("clk", "rst"),
    "serv_rvfi_pc_bwd": ("clk", "rst"),
    "verilog_axis_arb_mux_order": ("clock", "reset"),
    "verilog_axis_width_roundtrip": ("clock", "reset"),
    "verilog_ethernet_fcs_roundtrip": ("clock", "reset"),
    "verilog_ethernet_mac_datapath": ("clk", "rst"),
    "wb2axip_axi3_reorder": ("clock", "reset"),
}

# Same rule as repair_block_testbenches.py, applied in memory: under
# `default_nettype none, Jasper rejects "input logic" ports (VERI-1906).
_DEFAULT_NETTYPE_NONE = re.compile(r"(?m)^[ \t]*`default_nettype[ \t]+none\b")
_INPUT_LOGIC = re.compile(r"(?m)^([ \t]*input[ \t]+)(logic\b)")
_WRAPPER = re.compile(r"assert\s+property\s*\(\s*@\s*\(\s*posedge\s+(\w+)\s*\)\s*"
                      r"(?:disable\s+iff\s*\(\s*([^)]*?)\s*\))?")


def is_testbench_path(value: str) -> bool:
    """A Block CSV cell is one line naming a SystemVerilog source file."""
    value = value.strip()
    return "\n" not in value and value.endswith((".sv", ".v", ".svh"))


def resolve_testbench(value, repo_root=REPO_ROOT) -> Path:
    path = Path(value.strip()).expanduser()
    path = (path if path.is_absolute() else Path(repo_root) / path).resolve()
    if not path.is_file():
        raise FileNotFoundError(f"Block testbench does not exist: {path}")
    return path


def normalize_testbench(source: str) -> tuple[str, int]:
    """Make input net types explicit under `default_nettype none (idempotent)."""
    if not _DEFAULT_NETTYPE_NONE.search(source):
        return source, 0
    return _INPUT_LOGIC.subn(r"\1wire \2", source)


def read_testbench(path) -> dict:
    """Read one clean context; return model/checker text plus provenance."""
    path = Path(path)
    raw = path.read_text(encoding="utf-8-sig")
    text, changed = normalize_testbench(raw)
    if not text.strip():
        raise ValueError(f"Block testbench is empty: {path}")
    return {
        "testbench": text.strip(),
        "testbench_path": str(path),
        "testbench_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
        "testbench_explicit_input_nets": changed,
    }


def convention(design_name: str) -> tuple[str, str]:
    try:
        return DESIGN_CONVENTIONS[design_name]
    except KeyError:
        raise ValueError(
            f"No clock/reset convention for Block design {design_name!r}; "
            "add it to DESIGN_CONVENTIONS in new_agent/block_dataset.py.") from None


def assertion_template(design_name: str) -> str:
    clock, reset = convention(design_name)
    return (GENERIC_TEMPLATE.replace("CLOCK_SIGNAL", clock).replace("RESET_CONDITION", reset)
            + "\n" + RESET_NOTE)


def _declared(name: str, source: str) -> bool:
    return re.search(r"(?<![\w$])" + re.escape(name.lstrip("!")) + r"(?![\w$])", source) is not None


def audit(csv_path=DEFAULT_CSV) -> list[str]:
    """Report CSV rows whose files or wrappers disagree with this module."""
    import csv

    problems = []
    with Path(csv_path).open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    for number, row in enumerate(rows, start=1):
        design = row["design_name"].strip()
        if row.get("jg_status", "PROVEN").strip() not in INCLUDED_JG_STATUSES:
            continue
        try:
            clock, reset = convention(design)
            source = read_testbench(resolve_testbench(row["testbench"]))["testbench"]
        except (ValueError, OSError) as error:
            problems.append(f"row {number}: {error}")
            continue
        for name in (clock, reset):
            if not _declared(name, source):
                problems.append(f"row {number}: {design} TB does not declare {name.lstrip('!')}")
        match = _WRAPPER.search(row["ref_solution"])
        if not match or match.group(1) != clock:
            problems.append(f"row {number}: reference clock differs from {clock}")
        elif match.group(2) is not None and match.group(2).replace(" ", "") != reset:
            problems.append(f"row {number}: reference disable iff ({match.group(2)}) differs from ({reset})")
    return problems


if __name__ == "__main__":
    found = audit()
    print("\n".join(found) if found else f"{DEFAULT_CSV.name}: all Block rows match their conventions.")
    raise SystemExit(1 if found else 0)
