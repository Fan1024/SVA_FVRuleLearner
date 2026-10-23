# lists/diag_verilog_ethernet_fcs_roundtrip.tcl -- the diag environment for
# verilog_ethernet_fcs_roundtrip.
#
# v5 sources this file and then calls
# `setup_diag_verilog_ethernet_fcs_roundtrip` at global scope (v5/cex.tcl,
# v5/check.tcl), and does `task -set diag_verilog_ethernet_fcs_roundtrip`
# straight after. So this proc's one hard obligation is to leave a Jasper task
# by that exact name in existence.
#
# This diag declares NO assumptions of its own, and that is the whole
# environment, not a missing step. The upstream task states its environment in
# `ft/tb.sv` itself: `A_RESET_IDLE` (nothing is driven during reset),
# `A_INPUT_GOOD` (the source never marks a beat bad), `A_INPUT_STICKY` (a
# stalled source holds valid, data, last and user) and
# `A_FRAME_AT_MOST_16_BYTES` (which BOUNDS the state space -- it is what keeps
# a frame inside the 64-entry reference ring, not a protocol nicety). All four
# elaborate with the package and are the four the census below counts.
# Restating them here would double them.

set ::diag_expected_assumes {A_RESET_IDLE A_INPUT_GOOD A_INPUT_STICKY \
                             A_FRAME_AT_MOST_16_BYTES}

proc setup_diag_verilog_ethernet_fcs_roundtrip {{base_task FPV} \
        {diag_task diag_verilog_ethernet_fcs_roundtrip}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Census for the log. Every assumption in this environment comes from the
    # package, so this counts all of them rather than a `diag_*` subset.
    set assumptions [get_property_list -include {type assume}]
    puts "diagnostic_task=$diag_task"
    puts "diagnostic_assumption_count=[llength $assumptions]"
    foreach p $assumptions {
        puts "ASSUME $p"
    }

    # The protected target. `cex.tcl` resolves targets for itself out of its
    # own label index and does not read what this returns, so this is a census
    # for the log -- report the count, and fail only on the one answer that is
    # certainly wrong.
    set targets [get_property_list \
        -include {type assert name {.*T_FCS_ROUNDTRIP.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No T_FCS_ROUNDTRIP target resolved in task '$diag_task'"
    }
    return $targets
}

puts {Loaded diag_verilog_ethernet_fcs_roundtrip.tcl. Boot runs: setup_diag_verilog_ethernet_fcs_roundtrip}
