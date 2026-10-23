# lists/diag_nyuzi_l2_ring_coherence.tcl -- the diag environment for this task.
#
# v5 requires one: cex.tcl and check.tcl source `lists/<diag>.tcl`, call
# `setup_<diag>` at global scope, and then `task -set <diag>`. So the proc's
# job is to leave a Jasper task named exactly `diag_nyuzi_l2_ring_coherence`
# behind, and it is the last chance to fail loudly if the targets did not
# elaborate.
#
# THIS DIAG INSTALLS NO ASSUMPTIONS, and that is a fact about the package
# rather than an omission. Everything an assumption would normally do is built
# into `ft/` as synthesisable RTL:
#
#   * the two `nyuzi_l1_agent` instances close the L1 side over real Nyuzi
#     blocks, so the request stream is whatever the caches produce -- there is
#     no hand-written request generator to constrain;
#   * the pipeline-facing inputs (`of_*`, `cr_*`, `wb_*`, `ts_*`, `ocd_*`) are
#     left FREE on purpose. An arbitrary instruction stream is a stronger
#     environment for the L1/L2 protocol than a real decoder would be, and it
#     is what makes the miss queues and the store queue fill;
#   * `nyuzi_axi_mem` is the system-memory responder, and its ready/valid
#     throttles are unconstrained top-level inputs, so memory latency is
#     whatever the proof needs it to be.
#
# `sva/targets_*.sv` and `sva/covers_*.sv` declare no assumption either. The
# census below prints the assumption list so the console log records that it is
# empty, and `check_assumptions -show` in tc_elab.tcl says the same from the
# other side.
#
# It therefore needs no `safe_assume`; `lists/vendor/iterdev_utils.tcl` is
# shipped only because `cex.tcl` / `check.tcl` source it when present.

set ::diag_expected_assumes {}

proc setup_diag_nyuzi_l2_ring_coherence {{base_task FPV} {diag_task diag_nyuzi_l2_ring_coherence}} {
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

    foreach p [get_property_list -include {type assume disabled 0}] {
        puts "ASSUME $p"
    }

    # Every candidate target lives in the bound checker instance `u_targets`
    # and carries a `T_` label. Fail on zero, and report the count so a round
    # log records how many of the authored candidates actually elaborated.
    #
    # The filter matters here: Nyuzi's RTL carries ~139 of its OWN unlabelled
    # immediate `assert(...)` statements. They are properties in the census and
    # they are not candidates.
    set targets [get_property_list \
        -include {type assert name {.*\.u_targets\.T_[A-Z0-9_]+$}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No u_targets.T_* candidate targets resolved. The checker did\
               not elaborate as expected."
    }

    set covers [get_property_list \
        -include {type cover name {.*\.u_covers\.C_[A-Z0-9_]+$}} -regexp]
    puts "candidate_cover_count=[llength $covers]"

    return $targets
}

puts {Loaded diag_nyuzi_l2_ring_coherence.tcl. Boot runs: setup_diag_nyuzi_l2_ring_coherence}
