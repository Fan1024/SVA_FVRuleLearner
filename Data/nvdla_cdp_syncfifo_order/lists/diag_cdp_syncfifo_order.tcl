# lists/diag_cdp_syncfifo_order.tcl -- the diag environment for
# nvdla_cdp_syncfifo_order.
#
# v5 sources this file and then calls `setup_diag_cdp_syncfifo_order` at global
# scope (v5/cex.tcl, v5/check.tcl), and does `task -set diag_cdp_syncfifo_order`
# straight after. So this proc's one hard obligation is to leave a Jasper task
# by that exact name in existence.
#
# This environment has NO assumptions AT ALL -- not in the diag and not in the
# package. The upstream task's `DERIVATION.json` states an empty
# `base_assumptions` list and the checker declares none: the CVT and SUM input
# valids and payloads are free, and the three output readies are free. The task
# is stated against that unconstrained environment, so both censuses below
# print 0 and those are the correct numbers, not a missing step.

set ::diag_expected_assumes {}

proc setup_diag_cdp_syncfifo_order {{base_task FPV} {diag_task diag_cdp_syncfifo_order}} {
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

    # The package's own environment. Zero for this task, and reported anyway so
    # that a reader of the round log sees the number rather than its absence.
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
        -include {type assert name {.*u_checker\.T_SYNCFIFO_DATA_ORDER.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No u_checker T_SYNCFIFO_DATA_ORDER target resolved in task '$diag_task'"
    }
    return $targets
}

puts {Loaded diag_cdp_syncfifo_order.tcl. Boot runs: setup_diag_cdp_syncfifo_order}
