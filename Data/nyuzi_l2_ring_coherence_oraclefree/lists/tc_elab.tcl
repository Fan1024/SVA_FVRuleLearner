# -*- mode: tcl -*-
# Elaboration recipe for tasks/nyuzi_l2_ring_coherence.
#
# Sourced by v5/cex.tcl, v5/check.tcl and v5/elab.tcl, each of which does
# `cd $task_root` first -- so every path here is relative to the package root.
# It opens with `clear -all`, which is what lets the drivers configure the
# proofgrid AFTER the load and have their settings win.
#
# Notes on the analyze step:
#   * one `analyze` call over `lists/tc_elab.files`, because v5/round.py
#     appends each worker's helper file to exactly that list and
#     taskdefs.slang_args reads the same list to build the design map. A
#     second list would mean the design map or the workers' files were
#     silently dropped.
#   * -sv12 for the whole list. Nyuzi is SystemVerilog throughout -- packed
#     structs, `enum`, `always_ff`, `interface` with modports -- and so are the
#     formal top and the checkers.
#   * the list carries the one `+incdir+rtl/nyuzi` this package needs. Every
#     RTL file opens with `include "defines.svh"`, and `defines.svh` includes
#     `config.svh` from the same directory.
#   * NO vendor define. With VENDOR_ALTERA / VENDOR_XILINX / MEMORY_COMPILER
#     all absent, `sram_1r1w`, `sram_2r1w` and `sync_fifo` take their
#     behavioural branch, which is the only branch this package ships a body
#     for. SIMULATION is absent too; it guards Nyuzi's own $display/$finish
#     debug checks and nothing the proof needs.

clear -all
configure -default
set_message -default -all

# Deprecation and version drift: a setting silently absent is a configuration
# difference nobody can see afterwards, so report the refusal and carry on
# rather than aborting the run after elaboration.
proc _try {args} {
    if {[catch {uplevel 1 $args} _e]} {
        puts "DEPRECATED/UNAVAILABLE on this Jasper, skipped: [lindex $args 0]"
        puts "    $_e"
    }
}

set_message -disable VERI-1523
set_message -disable INL206
set_message -disable IOBS001
set_message -disable WDIN005
set_message -limit_beta_warning_message
set_message -limit_initial_release_warning
_try set_message -warning EDEP260

# NOTHING is escalated to an error here. This cut leaves a lot of Nyuzi's own
# outputs unread -- the whole writeback-stage and control-register side of
# `dcache_data_stage` and `ifetch_data_stage`, the performance-event strobes,
# the I/O request port -- and turning that class of warning into an error would
# abort the load for a reason that says nothing about the task.

set_engine_mode auto
set_prove_orchestration on
set_proofgrid_manager on
set_save_compress_database on
set_log_timestamp_mode on
set_log_timestamp_format "(%m-%d %H:%M:%S) "
set_word_level_reduction on
set_proof_simplification on
set_prove_advanced_simplification on
set_prove_advanced_simplification_time_limit 30s
set_prove_report_period 300
set_prove_orchestration_undetermined_report true
set_analyze_bbox_parse_mode read_header
set_elab_time_limit 3600s

# ---------------------------------------------------------------- analyze
analyze -sv12 -f lists/tc_elab.files

# `AFRA_ELAB_EXTRA` carries extra switches for one run and is empty otherwise.
# The payload always exports it; without reading it here the export is a
# silent no-op.
set _elab_extra ""
if {[info exists ::env(AFRA_ELAB_EXTRA)]} { set _elab_extra $::env(AFRA_ELAB_EXTRA) }
puts "ELAB_EXTRA: '$_elab_extra'"

# -disable_auto_bbox: a module this package fails to carry must stop the load
# loudly, not become an unconstrained black box that makes every proof
# meaningless. The cache arrays in particular -- `sram_1r1w` / `sram_2r1w` --
# must be elaborated, because half the targets are about what is in them.
elaborate -top nyuzi_l2_ring_coherence_ft -disable_auto_bbox {*}$_elab_extra

set_clock_reference_mode auto
clock clk

# ACTIVE HIGH, asynchronous: every sequential block in Nyuzi is
# `always_ff @(posedge clk, posedge reset)`. `lists/reset_modes.tcl` carries
# the same expression and must not drift from this line.
set_cumulative_reset on
reset -expression {reset == 1'b1} -max_iterations 100

set _multiple_driven [get_design_info -list multiple_driven -silent]
if {[llength $_multiple_driven] != 0} {
    error "MULTI_DRIVEN: $_multiple_driven"
}

# The assertion count printed here is NOT the candidate-target count. Nyuzi's
# RTL carries ~139 of its own unlabelled immediate `assert(...)` statements
# inside `always_ff` blocks; they elaborate as properties and are counted here.
# The 49 labelled candidates are the `u_targets.T_*` set the diag censuses.
puts "ELABORATION_CENSUS assertions=[llength [get_property_list -include {type assert disabled 0}]]\
 assumptions=[llength [get_property_list -include {type assume disabled 0}]]\
 covers=[llength [get_property_list -include {type cover disabled 0}]]"

# The base task every diag starts from. `lists/diag_*.tcl` does
# `task -set $base_task` with base_task defaulting to FPV.
task -create FPV -copy_all -set
task -set FPV -update_gui

sanity_check -analyze simple_clk -verbose
sanity_check -analyze inactive_clk -verbose

# ------------------------------------------------------------- proofgrid
# Applied here, by the package. The drivers' own CONFIG_GRID runs after this
# load and overrides max_jobs and the per-engine limits; what this profile
# still decides is everything they do not set -- restarts, pending_time_limit,
# persistent_timeout, and local execution mode.
set _fvbuddy_pg_job_prefix [expr {[info exists ::env(FVBUDDY_MANUAL_JOB_PREFIX)] ? $::env(FVBUDDY_MANUAL_JOB_PREFIX) : {fvbuddy_manual_}}]
source [file join [file dirname [file normalize [info script]]] proofgrid_profiles.tcl]
pg_profile_medium $_fvbuddy_pg_job_prefix
unset _fvbuddy_pg_job_prefix
set_prove_cache_job_mode follow_proofgrid
set_prove_cache_max_jobs 0

check_assumptions -show
