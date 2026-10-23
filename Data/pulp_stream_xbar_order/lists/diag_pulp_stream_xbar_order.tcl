# lists/diag_pulp_stream_xbar_order.tcl -- the diag environment for
# pulp_stream_xbar_order.
#
# v5 sources this file and then calls `setup_diag_pulp_stream_xbar_order` at
# global scope (v5/cex.tcl, v5/check.tcl), and does
# `task -set diag_pulp_stream_xbar_order` straight after. So this proc's one
# hard obligation is to leave a Jasper task by that exact name in existence.
#
# This diag declares NO assumptions of its own, and that is the whole
# environment, not a missing step. The upstream task states its environment in
# `ft/tb.sv` itself -- `A_RESET_IDLE` (no input drives during reset) and
# `A_IN0..3_STICKY` (a stalled input holds valid, data AND destination). Those
# are ordinary ready/valid source behaviour, they elaborate with the package,
# and they are the five the census below counts. Restating them here would
# double them.
#
# What is NOT an assumption and is easy to mistake for one: `ft/tb.sv` line 2
# defines `COMMON_CELLS_ASSERTS_OFF` before including the RTL, which compiles
# out the common-cells library's own `assert` macros. That is a compile-time
# fact stated in the source, not a constraint added here.

set ::diag_expected_assumes {A_RESET_IDLE A_IN0_STICKY A_IN1_STICKY \
                             A_IN2_STICKY A_IN3_STICKY}

proc setup_diag_pulp_stream_xbar_order {{base_task FPV} \
        {diag_task diag_pulp_stream_xbar_order}} {
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
        -include {type assert name {.*T_BUFFERED_XBAR_ORDER.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No T_BUFFERED_XBAR_ORDER target resolved in task '$diag_task'"
    }
    return $targets
}

puts {Loaded diag_pulp_stream_xbar_order.tcl. Boot runs: setup_diag_pulp_stream_xbar_order}
