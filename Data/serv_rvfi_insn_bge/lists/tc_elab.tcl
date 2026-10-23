# -*- mode: tcl -*-
# Elaboration recipe for tasks/serv_rvfi_insn_bge.
#
# Sourced by v5/cex.tcl, v5/check.tcl and v5/elab.tcl, each of which does
# `cd $task_root` first, so every path here is package-relative. It must leave
# the session elaborated, clocked, reset and sitting in a base task the diag
# can copy.
#
# AUTHORED, not derived from a vendor script. The source package
# (an earlier internal task package) has no `tcl/` at all: it
# ships `engine/ric3.toml`, a config for the rIC3 model checker with a
# yosys-slang front end. What that file decides -- the file list, the include
# files, `top = testbench`, `reset = "reset"` -- is carried over here and in
# lists/tc_elab.files; everything else below is this harness's own convention,
# taken from tasks/openpiton_pmesh_order/lists/tc_elab.tcl.

clear -all
configure -default
set_message -default -all

# Deprecation and version drift: a setting silently absent is a configuration
# difference nobody can see afterwards, so report the refusal and carry on.
proc _try {args} {
    if {[catch {uplevel 1 $args} _e]} {
        puts "DEPRECATED/UNAVAILABLE on this Jasper, skipped: [lindex $args 0]"
        puts "    $_e"
    }
}

# Elaboration diagnostics that must not pass silently. Short on purpose: SERV
# and riscv-formal are upstream code we did not write, and promoting the usual
# lint family to error buys rejected elaborations, not information.
set_message -error VERI-2314
set_message -error VERI-1141
set_message -disable VERI-1523
set_message -limit_beta_warning_message
set_message -limit_initial_release_warning

set_elab_time_limit 3600s
compilation -profile -enable

# ONE `analyze` over ONE list, because v5/round.py appends each worker's helper
# file to exactly that list and taskdefs.slang_args reads the same list to build
# the design map. A second list would silently drop one or the other.
#
# -sv12 for the whole list, SERV's Verilog-2001 RTL included. The list opens
# with the riscv-formal header `ft/defines.sv`; see lists/tc_elab.files for why
# the order is load-bearing.
analyze -sv12 -f lists/tc_elab.files

compilation -profile -report -sort_by time -limit 5
compilation -profile -report -sort_by mem -limit 5

# `AFRA_ELAB_EXTRA` carries extra elaborate switches for one run and is empty
# otherwise. The payload exports it unconditionally, so a recipe that does not
# read it drops the run's switches silently.
set _elab_extra ""
if {[info exists ::env(AFRA_ELAB_EXTRA)]} { set _elab_extra $::env(AFRA_ELAB_EXTRA) }
puts "ELAB_EXTRA: '$_elab_extra'"

# -disable_auto_bbox: a module this package fails to carry must stop the load
# loudly, not become an unconstrained black box that makes every proof
# meaningless.
#
# No `-create_related_covers`: the source task has none and this package keeps
# it that way. Related covers would attach a precondition/witness cover to
# every helper an agent writes, changing what the cover phase counts without
# changing what the target means.
elaborate -top testbench -disable_auto_bbox {*}$_elab_extra

analyze -clear

# `clock` and `reset` are the SIGNAL names here, not just the command names --
# ft/tb.sv declares `input check, input clock, reset` and ft/wrapper.sv wires
# `reset` straight to SERV's active-high `i_rst`. That is what
# engine/ric3.toml records as `reset = "reset"`, and the source flow drives it
# as a concrete 1,0 sequence out of power-on.
set_clock_reference_mode auto
clock clock
set_cumulative_reset on
reset -expression {reset == 1'b1} -max_iterations 100

# Reported, not fatal. The value is seeing the number in the round log next to
# everything else; an abort here kills the round before any verdict.
set _multiple_driven [get_design_info -list multiple_driven -silent]
puts "MULTIPLE_DRIVEN count=[llength $_multiple_driven] list=$_multiple_driven"

puts "ELABORATION_CENSUS assertions=[llength [get_property_list -include {type assert disabled 0}]]\
 assumptions=[llength [get_property_list -include {type assume disabled 0}]]\
 covers=[llength [get_property_list -include {type cover disabled 0}]]"

# The base task the diag copies from.
task -create FPV -copy_all -set
task -set FPV -update_gui

# ProofGrid defaults. `CONFIG_GRID` in the v5 driver runs after this file and
# overrides max_jobs/per_engine/per_session; what survives from the profile is
# everything it does not set -- restarts, pending_time_limit, persistent
# timeout.
set _fvbuddy_pg_job_prefix [expr {[info exists ::env(FVBUDDY_MANUAL_JOB_PREFIX)] ? $::env(FVBUDDY_MANUAL_JOB_PREFIX) : {fvbuddy_manual_}}]
source [file join [file dirname [file normalize [info script]]] proofgrid_profiles.tcl]
pg_profile_medium $_fvbuddy_pg_job_prefix
unset _fvbuddy_pg_job_prefix

check_assumptions -show
