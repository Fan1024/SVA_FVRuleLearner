# -*- mode: tcl -*-
# opentitan_tlul_socket_order elaboration recipe.
#
# Sourced by v5 (`cex.tcl`, `check.tcl`, `elab.tcl`) with the PACKAGE ROOT as
# cwd, so every path here is package-relative. It must leave the session
# elaborated, clocked, reset and sitting in a base task the diag can copy.
#
# Derived from the upstream task's `tcl/setup.tcl`. What that file did beyond
# elaboration -- a name census over the expected assertion/assumption/cover
# lists, a fail-closed target-resolution check, and the `helpers.sv` include
# path -- belonged to a single-shot evaluator with a frozen submission. v5
# stages one file per worker and re-elaborates every round, so those checks
# would reject a legal round. The census is not lost: `cex.tcl` runs its own
# `LABEL_INDEX`, `CHECK_FT_MODULES` and `CHECK_LABEL_COLLISIONS` after this.

clear -all
configure -default
set_message -default -all

# Elaboration diagnostics that must not pass silently. Kept deliberately short:
# most of this is real upstream OpenTitan RTL, and promoting the usual lint
# family to error on code we did not write buys rejected elaborations, not
# information.
set_message -error VERI-2314
set_message -error VERI-1141
set_message -disable VERI-1523

set_elab_time_limit 3600s
compilation -profile -enable

# One `-sv12` analyze over one appendable list. `+define+SYNTHESIS` and
# `+incdir+rtl` live in the list itself, not here, so `taskdefs.slang_args`
# sees the same switches the Jasper run does.
analyze -sv12 -f lists/tc_elab.files

compilation -profile -report -sort_by time -limit 5
compilation -profile -report -sort_by mem -limit 5

# `AFRA_ELAB_EXTRA` carries extra elaborate switches for one run and is empty
# otherwise. The payload exports it unconditionally, so a recipe that does not
# read it drops the run's switches silently.
set _elab_extra ""
if {[info exists ::env(AFRA_ELAB_EXTRA)]} { set _elab_extra $::env(AFRA_ELAB_EXTRA) }
puts "ELAB_EXTRA: '$_elab_extra'"

# No `-create_related_covers`: the upstream task elaborates without them and
# this package keeps that. Related covers would attach precondition/witness
# covers to every helper an agent writes, which changes what the cover phase
# counts without changing what the target means.
elaborate -top testbench -disable_auto_bbox {*}$_elab_extra

analyze -clear

set_clock_reference_mode auto
clock clock
set_cumulative_reset on
# ACTIVE HIGH. `testbench` takes `reset`, not `rst_ni`, and hands `!reset` to
# the socket. Copying the pmesh recipe's `reset_n == 1'b0` here would reset the
# design exactly when it is meant to be running.
reset -expression {reset == 1'b1} -max_iterations 100

# Reported, not fatal. The upstream setup errored out on any multiply driven
# net; here the value is seeing it in the round log next to everything else.
set _multiple_driven [get_design_info -list multiple_driven -silent]
puts "MULTIPLE_DRIVEN count=[llength $_multiple_driven] list=$_multiple_driven"

# The base task the diag copies from, matching the reference package's name.
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
