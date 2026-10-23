# lists/diag_two_tile_coherence.tcl -- the diag environment for this task.
#
# v5 requires one: cex.tcl and check.tcl source `lists/<diag>.tcl`, call
# `setup_<diag>` at global scope, and then `task -set <diag>`. So the proc's
# job is to leave a Jasper task named exactly `diag_two_tile_coherence`
# behind, and it is the last chance to fail loudly if the target did not
# elaborate.
#
# Like tasks/l15_l2_mshr_onehot and unlike the internal reference task diags, this one
# installs NO assumptions. The environment is not a symmetry reduction and is
# not steerable from Tcl: it is the four bounded core sources, the 2x1 mesh and
# the off-chip memory responder built into
# `ft/openpiton_two_tile_coherence_ft.sv`, plus the three fairness assumptions
# the checker declares over free inputs (cpx_ack[0], cpx_ack[1], mem_send).
# There is nothing left for a diag to constrain, so it does not pretend to. It
# therefore needs no `safe_assume` and no `lists/vendor/iterdev_utils.tcl`.
#
# The two-tile configuration is NOT a diag choice either. It is
# `config_system_tile_count = 2` on both L1.5s, coreid_x = the tile index, and
# the two-tile rendering of flat_id_to_xy / xy_to_flat_id in
# rtl/openpiton -- all of them in the sources, where a reader can see them.

set ::diag_expected_assumes {}

proc setup_diag_two_tile_coherence {{base_task FPV} {diag_task diag_two_tile_coherence}} {
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
        -include {type assert name {.*\.u_checker\.T_COHERENCE_NO_TWO_WRITERS$}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] != 1} {
        error "Expected exactly 1 u_checker.T_COHERENCE_NO_TWO_WRITERS target,\
               got [llength $targets]. The checker did not elaborate as expected."
    }

    # The two-agent structure is what makes this task different from
    # l15_l2_mshr_onehot; if only one L1.5 or one L2 elaborated, every
    # coherence target below is vacuous and nothing else would say so.
    set l15s [get_design_info -instance openpiton_two_tile_coherence_ft \
                  -list instance -silent]
    puts "two_tile_check top_children=[llength $l15s]"

    return $targets
}

puts {Loaded diag_two_tile_coherence.tcl. Boot runs: setup_diag_two_tile_coherence}
