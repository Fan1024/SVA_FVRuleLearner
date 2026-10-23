# lists/diag_cva6_frontend_issue_commit.tcl -- the diag environment for this task.
#
# v5 requires one: cex.tcl and check.tcl source `lists/<diag>.tcl`, call
# `setup_<diag>` at global scope, and then `task -set <diag>`. `<diag>` is the
# `diag` field of `taskdef.json`, which is `diag_cva6_frontend_issue_commit`,
# so the proc below MUST be named `setup_diag_cva6_frontend_issue_commit` --
# a proc named anything else is silently never called and the package runs
# with no diag at all.
#
# THIS DIAG INSTALLS NO ASSUMPTIONS, and that is a fact about the package
# rather than an omission. The whole environment is built into `ft/` as
# synthesisable models -- the instruction cache, the data cache and the CVXIF
# coprocessor that accepts nothing -- so there is nothing left for Tcl to
# constrain. `sva/targets_cva6_frontend_issue_commit.sv` and
# `sva/covers_cva6_frontend_issue_commit.sv` declare no assumption either.
# The census below prints the assumption list so the console log records that
# it is empty, and `check_assumptions -show` in tc_elab.tcl says the same
# thing from the other side.
#
# It therefore needs no `safe_assume`; `lists/vendor/iterdev_utils.tcl` is
# shipped only because `cex.tcl` / `check.tcl` source it when present.

set ::diag_expected_assumes {}

proc setup_diag_cva6_frontend_issue_commit {{base_task FPV} {diag_task diag_cva6_frontend_issue_commit}} {
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
    # log records how many of the 50 authored candidates actually elaborated.
    #
    # The pattern is anchored on `u_targets.` on purpose: CVA6 ships its own
    # `assert property` statements and they are still in the property list.
    # None of them can match `.*\.u_targets\.T_...`.
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

puts {Loaded diag_cva6_frontend_issue_commit.tcl. Boot runs: setup_diag_cva6_frontend_issue_commit}
