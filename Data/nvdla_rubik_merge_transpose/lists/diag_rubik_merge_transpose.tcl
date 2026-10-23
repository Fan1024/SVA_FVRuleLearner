# lists/diag_rubik_merge_transpose.tcl -- the diag environment for
# nvdla_rubik_merge_transpose.
#
# v5 sources this file and then calls `setup_diag_rubik_merge_transpose` at
# global scope (v5/cex.tcl, v5/check.tcl), and does
# `task -set diag_rubik_merge_transpose` straight after. So this proc's one hard
# obligation is to leave a Jasper task by that exact name in existence.
#
# The diag ADDS NO ASSUMPTION. This task's environment is not empty -- it states
# one, `A_READY_RESERVATION` -- but that assumption is written in
# `sva/nvdla_rubik_merge_transpose_checker.sv` and is therefore already
# elaborated by `tc_elab.tcl`. The census below reports it;
# `diagnostic_assumption_count` is 0 and that is the correct number, not a
# missing step.

set ::diag_expected_assumes {}

proc setup_diag_rubik_merge_transpose {{base_task FPV} {diag_task diag_rubik_merge_transpose}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Same census shape the reference package prints, so an nvdla round log
    # reads like the internal reference task one. Empty here by construction: nothing in this
    # file declares an assumption.
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

    # The package's own environment, which came in with the checker. Reported
    # so a reader of the round log can see the constraint set the target is
    # stated against without opening the source.
    set package_assumes [get_property_list \
        -include {type assume name {.*u_checker\..*}} -regexp]
    puts "package_assumption_count=[llength $package_assumes]"
    foreach p $package_assumes {
        puts "PACKAGE_ASSUME $p"
    }

    # The protected target. `cex.tcl` resolves targets for itself out of its
    # own label index and does not read what this returns, so this is a census
    # for the log -- report the count, and fail only on the one answer that is
    # certainly wrong.
    set targets [get_property_list \
        -include {type assert name {.*u_checker\.T_RUBIK_MERGE_TRANSPOSE.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No u_checker T_RUBIK_MERGE_TRANSPOSE target resolved in task '$diag_task'"
    }
    return $targets
}

puts {Loaded diag_rubik_merge_transpose.tcl. Boot runs: setup_diag_rubik_merge_transpose}
