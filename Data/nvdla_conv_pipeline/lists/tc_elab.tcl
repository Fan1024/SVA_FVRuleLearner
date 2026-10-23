# -*- mode: tcl -*-
# nvdla_conv_pipeline elaboration recipe.
#
# Sourced by v5 (`cex.tcl`, `check.tcl`, `elab.tcl`) with the PACKAGE ROOT as
# cwd, so every path here is package-relative.  It must leave the session
# elaborated, clocked, reset and sitting in a base task the diag can copy.
#
# Shape taken from `tasks/nvdla_mcif_order/lists/tc_elab.tcl`, which is the
# recipe the other generated-NVDLA packages in this repo already run.  This is
# a much larger elaboration -- five blocks, 983 instances, 314k lines of
# generated RTL and 512 KiB of CBUF SRAM -- so the elaborate time limit is
# raised and the compilation profile is reported, but nothing else differs.

clear -all
configure -default
set_message -default -all

# Elaboration diagnostics that must not pass silently.  Deliberately short:
# promoting the usual lint family to error on generated code we did not write
# buys rejected elaborations, not information.
set_message -error VERI-2314
set_message -error VERI-1141
set_message -disable VERI-1523

set_elab_time_limit 10800s
compilation -profile -enable

# One `-sv12` analyze over the whole list, which is what lets
# `lists/tc_elab.files` stay the one appendable list the round adds each
# worker's file to.
analyze -sv12 -f lists/tc_elab.files

compilation -profile -report -sort_by time -limit 10
compilation -profile -report -sort_by mem -limit 10

# `AFRA_ELAB_EXTRA` carries extra elaborate switches for one run and is empty
# otherwise.  The payload exports it unconditionally, so a recipe that does not
# read it drops the run's switches silently.
set _elab_extra ""
if {[info exists ::env(AFRA_ELAB_EXTRA)]} { set _elab_extra $::env(AFRA_ELAB_EXTRA) }
puts "ELAB_EXTRA: '$_elab_extra'"

# No `-create_related_covers`: related covers would attach precondition and
# witness covers to every helper an agent writes, which changes what the cover
# phase counts without changing what any target means.
elaborate -top nvdla_conv_pipeline_ft -disable_auto_bbox {*}$_elab_extra

analyze -clear

set_clock_reference_mode auto
clock nvdla_core_clk
set_cumulative_reset on
reset -expression {nvdla_core_rstn == 1'b0} -max_iterations 100

# Reported, not fatal.  The five blocks close on their own port names with no
# multiply driven net -- checked before the package was built -- so a nonzero
# count here is news and belongs in the round log next to everything else.
set _multiple_driven [get_design_info -list multiple_driven -silent]
puts "MULTIPLE_DRIVEN count=[llength $_multiple_driven] list=$_multiple_driven"

# The base task the diag copies from.
task -create FPV -copy_all -set
task -set FPV -update_gui

# ProofGrid defaults.  `CONFIG_GRID` in the v5 driver runs after this file and
# overrides max_jobs/per_engine/per_session; what survives from the profile is
# everything it does not set.
set _fvbuddy_pg_job_prefix [expr {[info exists ::env(FVBUDDY_MANUAL_JOB_PREFIX)] ? $::env(FVBUDDY_MANUAL_JOB_PREFIX) : {fvbuddy_manual_}}]
source [file join [file dirname [file normalize [info script]]] proofgrid_profiles.tcl]
pg_profile_medium $_fvbuddy_pg_job_prefix
unset _fvbuddy_pg_job_prefix

check_assumptions -show
