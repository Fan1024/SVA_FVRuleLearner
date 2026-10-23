# lists/diag_corundum_tx_rx_datapath.tcl -- the diag environment for
# corundum_tx_rx_datapath.
#
# v5 sources this file and then calls `setup_diag_corundum_tx_rx_datapath` at
# global scope (v5/cex.tcl, v5/check.tcl), and does
# `task -set diag_corundum_tx_rx_datapath` straight after. So this proc's one
# hard obligation is to leave a Jasper task by that exact name in existence,
# and its name must be `setup_` + the `diag` key in taskdef.json.
#
# THIS DIAG DECLARES NO ASSUMPTIONS, and that is the whole environment, not a
# missing step. Everything a `constraint` would normally say is BUILT instead,
# in `ft/corundum_tx_rx_datapath_ft.sv`, as ordinary synthesisable logic:
#
#   * `mqnic_tx_req_gen` holds one transmit request at a time with a stable
#     payload until `tx_engine` takes it, so no AXI-Stream source-stability
#     assumption is needed;
#   * three `mqnic_axil_qcfg` instances bring the two descriptor ring pairs and
#     the completion ring pair up over AXI-Lite, and `mqnic_rss_cfg` writes the
#     receive indirection table, before the first transmit request is offered
#     (`all_configured` gates the generator, `desc_fetch.enable` and
#     `cpl_write.enable`), so no assumption about queue configuration is needed;
#   * the same drivers are the only writers of a producer or consumer pointer
#     and each bumps one by one only while its own credit account allows, so no
#     assumption keeps them from over-filling or over-draining a ring;
#   * all four host-memory responders answer within a bounded number of cycles
#     (a free two-bit delay, 0..3) and each `mqnic_mac_loopback` cannot stall
#     its link for more than three consecutive cycles, so the fairness,
#     bounded-response and deadlock candidates have a real bound rather than an
#     assumed one. This is load-bearing: with an unbounded link stall every one
#     of them is false.
#
# UPSTREAM ASSERTION CENSUS. Corundum's RTL is Verilog 2001 and carries no SVA
# at all -- the elaborated AST holds zero concurrent assert / assume / cover /
# restrict nodes before this package's own targets file is added. So the count
# printed below should equal exactly this package's targets plus its covers,
# and any other number means something in the session added a property.
#
# The consequence for a reader of a result: this task's numbers are NOT
# obtained under a constrained environment. They are obtained under a built
# one, and the built one is in the reset cut's scope -- see
# `taskdef.json:design_keep`, which keeps that environment out of the cut for
# exactly this reason.

set ::diag_expected_assumes {}

proc setup_diag_corundum_tx_rx_datapath {{base_task FPV} \
        {diag_task diag_corundum_tx_rx_datapath}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Census for the log. This package declares no assumption of its own and
    # upstream Corundum declares none either, so a non-zero count here means
    # something else in the session added one.
    set assumptions [get_property_list -include {type assume}]
    puts "diagnostic_task=$diag_task"
    puts "diagnostic_assumption_count=[llength $assumptions]"
    foreach p $assumptions {
        puts "ASSUME $p"
    }

    # The protected targets. `cex.tcl` resolves targets for itself out of its
    # own label index and does not read what this returns, so this is a census
    # for the log -- report the count, and fail only on the one answer that is
    # certainly wrong.
    set targets [get_property_list \
        -include {type assert name {.*corundum_txrx_targets\.T_.*}} -regexp]
    puts "candidate_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No T_* candidate target resolved in task '$diag_task'"
    }

    set covers [get_property_list \
        -include {type cover name {.*corundum_txrx_targets\.C_.*}} -regexp]
    puts "candidate_cover_count=[llength $covers]"

    return $targets
}

puts {Loaded diag_corundum_tx_rx_datapath.tcl. Boot runs: setup_diag_corundum_tx_rx_datapath}
