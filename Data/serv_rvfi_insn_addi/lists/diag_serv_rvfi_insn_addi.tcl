# lists/diag_serv_rvfi_insn_addi.tcl -- the diag environment for
# tasks/serv_rvfi_insn_addi.
#
# v5 sources this file and then calls `setup_diag_serv_rvfi_insn_addi` at
# global scope (v5/cex.tcl, v5/check.tcl), and does
# `task -set diag_serv_rvfi_insn_addi` straight after. So this proc's one hard
# obligation is to leave a Jasper task by that exact name in existence.
#
# This environment DECLARES no assumptions, but it is not an unconstrained one
# -- the package carries its own, and they are already elaborated by the time
# this runs:
#
#   ft/wrapper.sv   the two Wishbone handshake assumptions on each of the
#                   instruction and data buses: no `ack` under reset, and no
#                   `ack` without `cyc`. `ibus_rdt`/`ibus_ack`/`dbus_rdt`/
#                   `dbus_ack` are undriven `(* keep *) reg`s, i.e. free every
#                   cycle, so without these the core would be acked into
#                   nonsense.
#   ft/tb.sv        `assume (!(rvfi_order_loopback && check))`. riscv-formal
#                   was written for BOUNDED checking; `rvfi_order` is 64 bits
#                   and can wrap, and a wrapped order field breaks the checks.
#                   The CIll artifact added this assumption to make the
#                   unbounded proof sound, and its state register is the one
#                   entry in this task's `design_keep`.
#
# The diag adds nothing on top of those. The `diag_*` census below prints 0 and
# that is the correct number, not a missing step.

set ::diag_expected_assumes {}

proc setup_diag_serv_rvfi_insn_addi {{base_task FPV} {diag_task diag_serv_rvfi_insn_addi}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Same census shape the reference packages print. `diag_*` is empty here by
    # construction; the package's own assumptions are counted separately so the
    # log distinguishes "this environment is unconstrained" from "this diag
    # added nothing".
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
    puts "package_assumption_count=[llength [get_property_list -include {type assume disabled 0}]]"

    # The protected targets. `cex.tcl` resolves targets for itself out of its
    # own label index and does not read what this returns, so this is a census
    # for the log -- report the count, and fail only on the one answer that is
    # certainly wrong.
    #
    # NOTE these are IMMEDIATE assertions inside `always @(posedge clock)` in
    # sva/rvfi_insn_check.sv, not `assert property`. That is upstream
    # riscv-formal's form and the package keeps it; see PROVENANCE.md.
    set targets [get_property_list \
        -include {type assert name {.*checker_inst\.(o_rd_wdata_match|o_pc_wdata_match).*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No checker_inst o_rd_wdata_match / o_pc_wdata_match target resolved in task '$diag_task'"
    }
    return $targets
}

puts {Loaded diag_serv_rvfi_insn_addi.tcl. Boot runs: setup_diag_serv_rvfi_insn_addi}
