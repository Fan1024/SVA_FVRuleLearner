# lists/diag_verilog_ethernet_mac_datapath.tcl -- the diag environment for
# verilog_ethernet_mac_datapath.
#
# v5 sources this file and then calls
# `setup_diag_verilog_ethernet_mac_datapath` at global scope (v5/cex.tcl,
# v5/check.tcl), and does `task -set diag_verilog_ethernet_mac_datapath`
# straight after. So this proc's one hard obligation is to leave a Jasper task
# by that exact name in existence.
#
# THIS DIAG DECLARES NO ASSUMPTIONS, and that is the whole environment, not a
# missing step. Everything a `constraint` would normally say is BUILT instead,
# in `ft/verilog_ethernet_mac_datapath_ft.sv`, as ordinary synthesisable logic:
#
#   * `veth_frame_src` offers ONE well-formed Ethernet frame at a time and
#     holds every byte stable until the link takes it, so no AXI-Stream
#     source-stability assumption is needed;
#   * the receive link is an upstream `axis_gmii_tx` instance, so the preamble,
#     the SFD and the CRC-32 FCS the receiver checks are computed by real
#     transmit logic. No assumption says "the incoming frame has a good FCS" --
#     it has one because something built it;
#   * both gmii byte-clock enables come from `veth_bounded_stall`, which cannot
#     hold a link off for more than three consecutive cycles. That is what
#     gives the fairness, bounded-response and deadlock candidates a real
#     bound rather than an assumed one;
#   * `eth_demux.enable` is tied high and `eth_demux.drop` tied low, so the one
#     mid-chain place that could discard a frame is wired shut rather than
#     assumed quiet.
#
# The consequence for a reader of a result: this task's numbers are NOT
# obtained under a constrained environment. They are obtained under a built
# one, and the built one is in the reset cut's scope -- see
# `taskdef.json:design_keep`, which keeps that environment out of the cut for
# exactly this reason.

set ::diag_expected_assumes {}

proc setup_diag_verilog_ethernet_mac_datapath {{base_task FPV} \
        {diag_task diag_verilog_ethernet_mac_datapath}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Census for the log. This package declares no assumption of its own, so a
    # non-zero count here means something else in the session added one.
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
        -include {type assert name {.*veth_mac_targets\.T_.*}} -regexp]
    puts "candidate_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No T_* candidate target resolved in task '$diag_task'"
    }

    set covers [get_property_list \
        -include {type cover name {.*veth_mac_targets\.C_.*}} -regexp]
    puts "candidate_cover_count=[llength $covers]"

    return $targets
}

# The harness calls `setup_${diag}` (v5/cex.tcl:1107), and `diag` is
# taskdef.json's `diag_verilog_ethernet_mac_datapath`, so
# `setup_diag_verilog_ethernet_mac_datapath` above is the name that is
# actually invoked. This alias exists only so that the shorter spelling
# `setup_<task>` also works if a driver ever uses it; it adds no behaviour.
proc setup_verilog_ethernet_mac_datapath {args} {
    return [setup_diag_verilog_ethernet_mac_datapath {*}$args]
}

puts {Loaded diag_verilog_ethernet_mac_datapath.tcl. Boot runs: setup_diag_verilog_ethernet_mac_datapath}
