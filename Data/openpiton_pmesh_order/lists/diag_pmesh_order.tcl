# lists/diag_pmesh_order.tcl — the diag environment for openpiton_pmesh_order.
#
# v5 sources this file and then calls `setup_diag_pmesh_order` at global scope
# (v5/cex.tcl, v5/check.tcl), and does `task -set diag_pmesh_order` straight
# after. So this proc's one hard obligation is to leave a Jasper task by that
# exact name in existence.
#
# This environment has NO assumptions. The upstream task declares an empty
# assumption set: the four source ports are free, their payloads are free, and
# the only thing gating an injection is the endpoint credit counter in the
# formal top. The task is stated against that unconstrained environment, so
# the diag adds nothing to it -- the census below prints 0 and that is the
# correct number, not a missing step.

set ::diag_expected_assumes {}

proc setup_diag_pmesh_order {{base_task FPV} {diag_task diag_pmesh_order}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Same census shape the reference package prints, so a pmesh round log
    # reads like the internal reference task one. Empty here by construction.
    set assumptions [list]
    foreach p [get_property_list -include {type assume}] {
        set nm [lindex [split $p ":"] end]
        if {[string match diag_* $nm]} { lappend assumptions $p }
    }
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
        -include {type assert name {.*u_checker\.T_ORDER.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No u_checker T_ORDER target resolved in task '$diag_task'"
    }
    return $targets
}

puts {Loaded diag_pmesh_order.tcl. Boot runs: setup_diag_pmesh_order}
