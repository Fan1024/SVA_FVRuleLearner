# lists/diag_nvdla_conv_pipeline.tcl -- the diag environment for
# nvdla_conv_pipeline.
#
# v5 sources this file and then calls `setup_diag_nvdla_conv_pipeline` at
# global scope (v5/cex.tcl, v5/check.tcl), and does
# `task -set diag_nvdla_conv_pipeline` straight after.  So this proc's one hard
# obligation is to leave a Jasper task by that exact name in existence.
#
# The diag ADDS NO ASSUMPTION.  This package states exactly ONE, `A_SYM_FROZEN`
# in `sva/nvdla_conv_pipeline_checker.sv`, which freezes the free formal-top
# inputs `env_sym_addr` / `env_sym_col` that name the CBUF half-line the
# data-integrity oracle watches.  It constrains an environment input and no
# design output.  It is already elaborated by `tc_elab.tcl`; the census below
# reports it, and `diagnostic_assumption_count` is 0 because nothing in THIS
# file declares one.
#
# Everything else the environment does is structural and lives in the formal
# top: four bounded memory responders, a bounded SDP sink, and free CSB
# stimulus (every one of the five generated regfiles ties its `req_prdy` to
# 1'b1, so there is no handshake left to constrain).

set ::diag_expected_assumes {}

proc setup_diag_nvdla_conv_pipeline {{base_task FPV} {diag_task diag_nvdla_conv_pipeline}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

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

    # The package's own environment, which came in with the checker.  Reported
    # so a reader of the round log sees the constraint set the targets are
    # stated against without opening the source.  Expect exactly one.
    set package_assumes [get_property_list \
        -include {type assume name {.*u_checker\..*}} -regexp]
    puts "package_assumption_count=[llength $package_assumes]"
    foreach p $package_assumes {
        puts "PACKAGE_ASSUME $p"
    }

    # The candidate targets.  `cex.tcl` resolves targets for itself out of its
    # own label index and does not read what this returns, so this is a census
    # for the log -- report the count, and fail only on the one answer that is
    # certainly wrong.
    set targets [get_property_list \
        -include {type assert name {.*u_checker\.T_.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No u_checker T_ target resolved in task '$diag_task'"
    }

    set covers [get_property_list \
        -include {type cover name {.*u_checker\.C_.*}} -regexp]
    puts "package_cover_count=[llength $covers]"

    return $targets
}

puts {Loaded diag_nvdla_conv_pipeline.tcl. Boot runs: setup_diag_nvdla_conv_pipeline}
