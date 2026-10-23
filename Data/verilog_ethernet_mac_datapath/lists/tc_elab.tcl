# -*- mode: tcl -*-
# verilog_ethernet_mac_datapath elaboration recipe.
#
# Sourced by v5 (`cex.tcl`, `check.tcl`, `elab.tcl`) with the PACKAGE ROOT as
# cwd, so every path here is package-relative. It must leave the session
# elaborated, clocked, reset and sitting in a base task the diag can copy.
#
# There is no upstream `tcl/setup.tcl` to derive this from: verilog-ethernet
# ships cocotb testbenches, not a Jasper flow. It follows the shape of the
# other ports in `tasks/` -- one `analyze -sv12 -f` over the one appendable
# list, one `elaborate -disable_auto_bbox`, `set_cumulative_reset`, a base FPV
# task -- and adds nothing task-specific beyond the reset expression and the
# clock name, which are the formal top's `rst` (ACTIVE HIGH) and `clk`.

clear -all
configure -default
set_message -default -all

# Elaboration diagnostics that must not pass silently. Kept short: the RTL is
# upstream verilog-ethernet and promoting the usual lint family to error on
# code we did not write buys rejected elaborations, not information.
set_message -error VERI-2314
set_message -error VERI-1141
set_message -disable VERI-1523

set_elab_time_limit 3600s
compilation -profile -enable

# ONE `analyze -sv12` over ONE list. The list carries the eighteen upstream
# Verilog-2001 files, the formal top and the candidate targets, and the round
# appends one `../submission/<worker>.sv` line per worker to the end of it.
#
# The upstream files are Verilog 2001 and the authored files are SystemVerilog;
# `-sv12` reads both. Checked before collapsing them into one call: none of the
# eighteen upstream files declares an identifier that SystemVerilog 2012
# reserves, and each opens with its own ``resetall`` / ``default_nettype none``
# pair so a single-unit compile cannot carry a directive across a file edge.
analyze -sv12 -f lists/tc_elab.files

compilation -profile -report -sort_by time -limit 5
compilation -profile -report -sort_by mem -limit 5

# `AFRA_ELAB_EXTRA` carries extra elaborate switches for one run and is empty
# otherwise. The payload exports it unconditionally, so a recipe that does not
# read it drops the run's switches silently.
set _elab_extra ""
if {[info exists ::env(AFRA_ELAB_EXTRA)]} { set _elab_extra $::env(AFRA_ELAB_EXTRA) }
puts "ELAB_EXTRA: '$_elab_extra'"

# No `-create_related_covers`: they would attach precondition/witness covers to
# every helper an agent writes, changing what the cover phase counts without
# changing what the target means.
elaborate -top verilog_ethernet_mac_datapath_ft -disable_auto_bbox {*}$_elab_extra

analyze -clear

set_clock_reference_mode auto
clock clk
set_cumulative_reset on
# ACTIVE HIGH. verilog-ethernet spells its synchronous reset `rst` and asserts
# it high; the formal top passes the same net to the logic domain and through
# the two upstream `sync_reset` instances to the two gmii domains.
reset -expression {rst == 1'b1} -max_iterations 100

# Reported, not fatal. An abort here kills the round before any verdict, and
# the number in the log answers the same question.
set _multiple_driven [get_design_info -list multiple_driven -silent]
puts "MULTIPLE_DRIVEN count=[llength $_multiple_driven] list=$_multiple_driven"

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
