# lists/diag_corundum_dma_path.tcl -- the diag environment for
# corundum_dma_path.
#
# v5 sources this file and then calls `setup_diag_corundum_dma_path` at global
# scope (v5/cex.tcl, v5/check.tcl), and does
# `task -set diag_corundum_dma_path` straight after. So this proc's one hard
# obligation is to leave a Jasper task by that exact name in existence.
#
# THIS DIAG DECLARES NO ASSUMPTIONS, and that is the whole environment, not a
# missing step. Everything a `constraint` would normally say is BUILT instead,
# in `ft/corundum_dma_path_ft.sv`, as ordinary synthesisable logic:
#
#   * the request generator holds one descriptor-fetch request at a time and
#     holds its payload stable until `desc_fetch` takes it, so no AXI-Stream
#     source-stability assumption is needed;
#   * `corundum_axil_qcfg` brings all four rings up over AXI-Lite before the
#     first request is offered (`all_configured` gates `desc_fetch.enable`),
#     so no assumption about queue configuration is needed;
#   * the same module is the only writer of a producer or consumer pointer, and
#     it bumps one by one only while its own credit account allows, so no
#     assumption keeps the driver from over-filling or over-draining a ring;
#   * `corundum_host_rd` and `corundum_host_wr` answer a DMA descriptor within
#     a bounded number of cycles (a free two-bit delay, 0..3), and the
#     descriptor sink cannot stall more than three cycles running, so the
#     fairness / bounded-response / deadlock targets have a real bound rather
#     than an assumed one.
#
# The consequence for a reader of a result: this task's numbers are NOT
# obtained under a constrained environment. They are obtained under a built
# one, and the built one is in the reset cut's scope -- see
# `taskdef.json:design_keep`, which keeps that environment out of the cut for
# exactly this reason.

set ::diag_expected_assumes {}

proc setup_diag_corundum_dma_path {{base_task FPV} \
        {diag_task diag_corundum_dma_path}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Census for the log. This package declares no assumption of its own, so a
    # non-zero count here means something else in the session added one.
    set assumptions [get_property_list -include {type assume}]
    puts "diagnostic_task=$diag_task"
    puts "diagnostic_assumption_count=[llength $assumptions]"
    foreach p $assumptions {
        puts "ASSUME $p"
    }

    # The protected targets. `cex.tcl` resolves targets for itself out of its
    # own label index and does not read what this returns, so this is a census
    # for the log -- report the count, and fail only on the one answer that is
    # certainly wrong.
    set targets [get_property_list \
        -include {type assert name {.*corundum_dma_targets\.T_.*}} -regexp]
    puts "candidate_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No T_* candidate target resolved in task '$diag_task'"
    }

    set covers [get_property_list \
        -include {type cover name {.*corundum_dma_targets\.C_.*}} -regexp]
    puts "candidate_cover_count=[llength $covers]"

    return $targets
}

puts {Loaded diag_corundum_dma_path.tcl. Boot runs: setup_diag_corundum_dma_path}
