# -*- mode: tcl -*-
# Elaboration recipe for tasks/cva6_frontend_issue_commit.
#
# Sourced by v5/cex.tcl, v5/check.tcl and v5/elab.tcl, each of which does
# `cd $task_root` first -- so every path here is relative to the package root.
# It opens with `clear -all`, which is what lets the drivers configure the
# proofgrid AFTER the load and have their settings win.
#
# Two notes on the analyze step:
#   * one `analyze` call over `lists/tc_elab.files`, because v5/round.py
#     appends each worker's helper file to exactly that list and
#     taskdefs.slang_args reads the same list to build the design map. A
#     second list would mean the design map or the workers' files were
#     silently dropped.
#   * -sv12 for the whole list. Every source here is SystemVerilog to begin
#     with: CVA6, the pulp-platform common_cells, and this package's formal
#     top, its two memory models, its covers and its targets.
#
# The list carries its own `+incdir+` lines for `rtl/cva6/include` (which is
# where `rvfi_types.svh` and `cvxif_types.svh` live -- `ft/cva6_pipe_fv_pkg.sv`
# and `ft/cva6_frontend_issue_commit_ft.sv` both include them) and for
# `rtl/common_cells/include`, from which `cc_lzc` and `cc_shift_register_gated`
# include `assertions.svh` and `registers.svh`.

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

# NOTHING is escalated to an error here. This cut leaves several CVA6 outputs
# unread -- the RVFI probes, the performance-counter strobes, the accelerator
# ports, the CVXIF request record -- and turning that class of warning into an
# error would abort the load for a reason that says nothing about the task.

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
# meaningless. This package was checked against the local Slang WITHOUT
# `--ignore-unknown-modules` for exactly the same reason -- that flag hid two
# missing common_cells (`cc_shift_register_gated`, `unread`) until it was
# taken away.
elaborate -top cva6_frontend_issue_commit_ft -disable_auto_bbox {*}$_elab_extra

set_clock_reference_mode auto
clock clk_i
set_cumulative_reset on
reset -expression {rst_ni == 1'b0} -max_iterations 100

set _multiple_driven [get_design_info -list multiple_driven -silent]
if {[llength $_multiple_driven] != 0} {
    error "MULTI_DRIVEN: $_multiple_driven"
}

# The census below will NOT equal 50 targets + 41 covers. CVA6 ships its own
# assertions and they are left where upstream put them: 45 concurrent and 32
# immediate `assert` statements inside `pragma translate_off` regions in
# `scoreboard`, `issue_read_operands`, `instr_queue`, `load_unit`,
# `store_buffer`, `csr_regfile`, `cva6_fifo_v3`, `pmp_entry`, `pmp_data_if`
# and `config_pkg`. NONE of them is an `assume` and none is a `cover`, so
# nothing upstream constrains a proof here -- see PROVENANCE.md, which lists
# them. Whether Jasper skips a `pragma translate_off` region is a property of
# the tool, so print the count rather than predict it.
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
# still decides is everything they do not set -- restarts,
# pending_time_limit, persistent_timeout, and local execution mode.
set _fvbuddy_pg_job_prefix [expr {[info exists ::env(FVBUDDY_MANUAL_JOB_PREFIX)] ? $::env(FVBUDDY_MANUAL_JOB_PREFIX) : {fvbuddy_manual_}}]
source [file join [file dirname [file normalize [info script]]] proofgrid_profiles.tcl]
pg_profile_medium $_fvbuddy_pg_job_prefix
unset _fvbuddy_pg_job_prefix
set_prove_cache_job_mode follow_proofgrid
set_prove_cache_max_jobs 0

check_assumptions -show
