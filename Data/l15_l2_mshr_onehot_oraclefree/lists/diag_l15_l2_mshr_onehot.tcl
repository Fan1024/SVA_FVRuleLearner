# lists/diag_l15_l2_mshr_onehot.tcl -- the diag environment for this task.
#
# v5 requires one: cex.tcl and check.tcl source `lists/<diag>.tcl`, call
# `setup_<diag>` at global scope, and then `task -set <diag>`. So the proc's
# job is to leave a Jasper task named exactly `diag_l15_l2_mshr_onehot`
# behind, and it is the last chance to fail loudly if the target did not
# elaborate.
#
# UNLIKE the internal reference task diags, this one installs NO assumptions. the internal reference task
# needs them because its cell is a symmetric fabric and the diag pins the
# observed source/destination pair. Here the environment is not a symmetry
# reduction and is not steerable from Tcl: it is the two bounded core
# sources, the NOC2 demultiplexer and the memory responder built into
# `ft/openpiton_l15l2_deadlock_ft.sv`, plus the two fairness assumptions the
# checker declares. There is nothing left for a diag to constrain, so it does
# not pretend to. It therefore needs no `safe_assume` and no
# `lists/vendor/iterdev_utils.tcl`.

set ::diag_expected_assumes {}

proc setup_diag_l15_l2_mshr_onehot {{base_task FPV} {diag_task diag_l15_l2_mshr_onehot}} {
    if {$diag_task in [task -list -silent]} {
        # A fresh project per run is the contract; a pre-existing task means
        # project or session reuse, and the assumption set in it is not one we
        # can vouch for.
        error "diag task '$diag_task' already exists -- refusing to reuse a\
               pre-existing task (stale project/session?); use a fresh run dir"
    }
    task -set $base_task
    task -create $diag_task -copy_all -set

    puts "diagnostic_task=$diag_task"
    puts "diagnostic_assumption_count=0"

    # The environment assumptions are the checker's, not the diag's. Report
    # them so the console log records what was in force.
    foreach p [get_property_list -include {type assume disabled 0}] {
        puts "ASSUME $p"
    }

    set targets [get_property_list \
        -include {type assert name {.*\.u_checker\.T_L2_MSHR_ONEHOT$}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] != 1} {
        error "Expected exactly 1 u_checker.T_L2_MSHR_ONEHOT target, got\
               [llength $targets]. The checker did not elaborate as expected."
    }
    return $targets
}

puts {Loaded diag_l15_l2_mshr_onehot.tcl. Boot runs: setup_diag_l15_l2_mshr_onehot}
