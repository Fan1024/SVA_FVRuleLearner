# -*- mode: tcl -*-
# opentitan_spi_device_fifo elaboration recipe.
#
# Sourced by v5 (`cex.tcl`, `check.tcl`, `elab.tcl`) with the PACKAGE ROOT as
# cwd, so every path here is package-relative. It must leave the session
# elaborated, clocked, reset and sitting in a base task the diag can copy.
#
# There is no upstream `tcl/setup.tcl` for this package -- it is not a port, it
# was assembled here -- so this file is derived from the recipe the three other
# OpenTitan packages in this tree use, with the switches this design needs.

clear -all
configure -default
set_message -default -all

# Elaboration diagnostics that must not pass silently. Kept deliberately short:
# all of `rtl/` is upstream lowRISC OpenTitan, and promoting the usual lint
# family to error on code we did not write buys rejected elaborations, not
# information.
set_message -error VERI-2314
set_message -error VERI-1141
set_message -disable VERI-1523

# The design closure here is 44 analyzed files: eight spi_device blocks, two
# asynchronous FIFO primitives, a dual-port SRAM wrapper and two arbiters.
set_elab_time_limit 7200s
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

# No `-create_related_covers`: they would attach precondition/witness covers to
# every helper an agent writes, which changes what the cover phase counts
# without changing what the target means.
elaborate -top opentitan_spi_device_fifo_ft -disable_auto_bbox {*}$_elab_extra

analyze -clear

# ONE CLOCK, AND THAT IS AN ASSUMPTION. spi_device is a two-clock design: SCK
# from the SPI host and the bus clock from the chip. The formal top drives BOTH
# from `clk_i`, i.e. a fixed 1:1 edge-aligned ratio. See PROVENANCE.md, "The
# clock assumption". The gray-coded pointers, both 2-flop synchronisers, the
# SRAM latency and the `stored` handshake are all still in the design; what is
# gone is the arbitrary phase and frequency relationship between the domains.
#
# `set_clock_reference_mode auto` is what lets the two DERIVED clocks in this
# design resolve against `clk_i`: `csb_q` clocks one flop in `spid_csb_sync`
# and one in `spid_status`, and the formal top registers CSb into the bus clock
# domain precisely so that those edges are `clk_i`-derived and not a second
# free-running primary clock.
set_clock_reference_mode auto
clock clk_i
set_cumulative_reset on

# ACTIVE LOW. This top keeps OpenTitan's own `rst_ni`.
reset -expression {rst_ni == 1'b0} -max_iterations 100

# Reported, not fatal. The value is seeing the number in the round log next to
# everything else; an abort here kills the round before any verdict.
set _multiple_driven [get_design_info -list multiple_driven -silent]
puts "MULTIPLE_DRIVEN count=[llength $_multiple_driven] list=$_multiple_driven"

# The base task the diag copies from, matching the other packages' name.
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
