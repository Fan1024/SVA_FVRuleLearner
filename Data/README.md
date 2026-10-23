# Formal-verification task packages (open-source designs)

33 self-contained formal tasks. Every design here comes from a public
open-source project; the proprietary tasks in the same collection are not
included.

## What a package contains

    rtl/ or src/   the design, copied from upstream
    sva/           target assertions (task-authored)
    ft/            the formal top (task-authored)
    lists/         Jasper setup: tc_elab.tcl, diag_*.tcl, reset_modes.tcl
    PROVENANCE.md  what came from upstream, what was written here, and the cut
    taskdef.json   top, targets, elaboration entry points (where present)

In general the RTL is byte-identical to upstream and everything else --
the formal top, the environment, the oracle, the assertions -- was written
for the task. Each `PROVENANCE.md` states this precisely for its own
package, including which files differ from upstream and why.

## Upstream projects

    corundum_dma_path                    Corundum NIC (github.com/corundum/corundum)
    corundum_dma_path_oraclefree         "
    corundum_tx_rx_datapath              "
    cva6_frontend_issue_commit           OpenHW Group CVA6 + PULP common_cells
    l15_l2_mshr_onehot                   OpenPiton L1.5 + L2
    l15_l2_mshr_onehot_oraclefree        "
    nvdla_bdma_data_order                NVDLA (public nvdlav1 release)
    nvdla_cdp_syncfifo_order             "
    nvdla_conv_pipeline                  "
    nvdla_mcif_order                     "
    nvdla_rubik_merge_transpose          "
    nyuzi_l2_ring_coherence              NyuziProcessor (jbush001/NyuziProcessor)
    nyuzi_l2_ring_coherence_oraclefree   "
    openpiton_pmesh_order                OpenPiton P-Mesh
    openpiton_pmesh_waitcycle            "
    openpiton_two_tile_coherence         "
    opentitan_spi_device_fifo            OpenTitan
    opentitan_tlul_socket_order          "
    pulp_stream_xbar_order               PULP platform
    serv_rvfi_insn_addi                  SERV + riscv-formal, via github.com/gipsyh/cill-exp
    serv_rvfi_insn_bge                   "
    serv_rvfi_insn_jal                   "
    serv_rvfi_insn_lbu                   "
    serv_rvfi_insn_ori                   "
    serv_rvfi_insn_sll                   "
    serv_rvfi_insn_sw                    "
    serv_rvfi_pc_bwd                     "
    verilog_axis_arb_mux_order           alexforencich/verilog-axis
    verilog_axis_width_roundtrip         "
    verilog_ethernet_fcs_roundtrip       alexforencich/verilog-ethernet
    verilog_ethernet_mac_datapath        "
    wb2axip_axi3_reorder                 ZipCPU wb2axip
    wb2axip_axi3_reorder_oraclefree      "

LICENCES ARE UPSTREAM'S. This directory does not restate them and does not
ship licence files. Check the upstream project for the terms that apply to
the RTL in each package; several `PROVENANCE.md` files record the exact
upstream commit the RTL was taken at.

## An `_oraclefree` variant

Where a package has an `_oraclefree` twin, the twin states the same
targets without a reference model to compare against.

## Redaction

`PROVENANCE.md` and the comments in `lists/*.tcl` were written for an
internal audience and have been redacted here: absolute paths into
internal trees, and cross-references to internal (non-open-source) task
packages, now read as "an internal tree", "an internal reference task" and
similar. Only comments and documentation were touched. No RTL, assertion,
formal top, or Jasper setting was changed, so every package elaborates and
proves exactly as it does internally.
