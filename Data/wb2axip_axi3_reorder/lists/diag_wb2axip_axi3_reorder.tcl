# lists/diag_wb2axip_axi3_reorder.tcl -- the diag environment for
# wb2axip_axi3_reorder.
#
# v5 sources this file and then calls `setup_diag_wb2axip_axi3_reorder` at
# global scope (v5/cex.tcl, v5/check.tcl), and does
# `task -set diag_wb2axip_axi3_reorder` straight after. So this proc's one hard
# obligation is to leave a Jasper task by that exact name in existence.
#
# This diag declares NO assumptions of its own, and that is the whole
# environment, not a missing step. The upstream task states its environment in
# `ft/tb.sv` itself: `A_RESET_AW_IDLE` and `A_RESET_W_IDLE` (nothing is driven
# during reset), `A_AW_STICKY` and `A_W_STICKY` (a stalled AXI3 channel holds
# its payload), and `A_FIXED_PACKET_LAST`, which BOUNDS the state space -- it
# forces every write packet to be exactly four beats per ID, which is what
# keeps a packet inside the 32-entry per-ID reference queue. All five elaborate
# with the package and are the five the census below counts. Restating them
# here would double them.

set ::diag_expected_assumes {A_RESET_AW_IDLE A_RESET_W_IDLE A_AW_STICKY \
                             A_W_STICKY A_FIXED_PACKET_LAST}

proc setup_diag_wb2axip_axi3_reorder {{base_task FPV} \
        {diag_task diag_wb2axip_axi3_reorder}} {
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

    # The protected target. Lowercase, unlike the other four packages in this
    # group -- the upstream task names it `o_axi3_reorder_e2e`, and the name is
    # taken as shipped rather than normalised.
    #
    # `cex.tcl` resolves targets for itself out of its own label index and does
    # not read what this returns, so this is a census for the log -- report the
    # count, and fail only on the one answer that is certainly wrong.
    set targets [get_property_list \
        -include {type assert name {.*o_axi3_reorder_e2e.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No o_axi3_reorder_e2e target resolved in task '$diag_task'"
    }
    return $targets
}

puts {Loaded diag_wb2axip_axi3_reorder.tcl. Boot runs: setup_diag_wb2axip_axi3_reorder}
