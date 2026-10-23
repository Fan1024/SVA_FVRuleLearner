# lists/diag_pmesh_waitcycle.tcl — the diag environment for
# openpiton_pmesh_waitcycle.
#
# v5 sources this file and then calls `setup_diag_pmesh_waitcycle` at global
# scope (v5/cex.tcl, v5/check.tcl), and does `task -set diag_pmesh_waitcycle`
# straight after. So this proc's one hard obligation is to leave a Jasper task
# by that exact name in existence.
#
# The diag DECLARES NO ASSUMPTION OF ITS OWN, and that is a decision rather than
# an omission. This task carries exactly one environment assumption,
# `u_checker.A_FAIR_SINK`: the single congested destination buffer (tile 8's
# processor egress, the only endpoint that does not drain immediately) accepts
# at least once in every four-cycle window. It is in
# `sva/openpiton_pmesh_deadlock_checker.sv`, so it is in the elaborated set
# before this file is sourced, and repeating it here would be a second,
# competing statement of the environment. A round log that shows zero
# assumptions is a broken environment, not a strict one.
#
# The top module and both source files keep the name they had upstream
# (`openpiton_pmesh_deadlock_*`); the TASK is `openpiton_pmesh_waitcycle` and
# the target is T_WAIT_GRAPH_ACYCLIC.

set ::diag_expected_assumes {
    openpiton_pmesh_deadlock_ft.u_checker.A_FAIR_SINK
}

proc setup_diag_pmesh_waitcycle {{base_task FPV} {diag_task diag_pmesh_waitcycle}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Every elaborated assumption, not only the `diag_*`-prefixed ones the
    # reference package looks for: here the environment ships WITH the package,
    # so a filter on `diag_*` would print 0 and read as "unconstrained", which
    # is the wrong thing to tell someone reading the log.
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
        -include {type assert name {.*u_checker\.T_WAIT_GRAPH_ACYCLIC.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No u_checker T_WAIT_GRAPH_ACYCLIC target resolved in task '$diag_task'"
    }
    return $targets
}

puts {Loaded diag_pmesh_waitcycle.tcl. Boot runs: setup_diag_pmesh_waitcycle}
