# lists/diag_opentitan_spi_device_fifo.tcl -- the diag environment for
# opentitan_spi_device_fifo.
#
# v5 sources this file and then calls `setup_diag_opentitan_spi_device_fifo` at
# global scope (v5/cex.tcl, v5/check.tcl), and does
# `task -set diag_opentitan_spi_device_fifo` straight after. So this proc's one
# hard obligation is to leave a Jasper task by that exact name in existence.
# `setup_opentitan_spi_device_fifo` is defined below as an alias for callers
# that spell the proc without the `diag_` prefix.
#
# THE DIAG DECLARES NO ASSUMPTION, AND NEITHER DOES THE PACKAGE. That is a
# decision, not an omission, and it is the reason the formal top ties the CSR
# side off with CONSTANTS rather than constraining a symbolic register
# interface: a constant is part of the design under proof and shows up in the
# design map, where an assumption is a promise the round has to keep track of.
#
# THE ONE ENVIRONMENT ASSUMPTION IS NOT WRITTEN AS AN `assume`, IT IS WRITTEN
# INTO THE FORMAL TOP: the SPI clock and the bus clock are THE SAME CLOCK.
# `lists/tc_elab.tcl` declares `clock clk_i` and nothing else, and
# `ft/opentitan_spi_device_fifo_ft.sv` drives `clk_spi_in`, `clk_spi_out` and
# `clk_sys` from it. PROVENANCE.md, "The clock assumption", records what that
# changes about what every target means. It is recorded here too because a
# constrained clock ratio must not be silent.
#
# The free inputs -- `csb_i`, `sd_i[3:0]`, `cmdfifo_rready_i`,
# `addrfifo_rready_i`, the five software SRAM port signals and the two
# FLASH_STATUS write signals -- are left entirely unconstrained. The SPI host
# may drive any bit pattern, may assert and de-assert CSb at any time, and the
# software port may read or write any SRAM address with any data. Every target
# in `sva/targets_opentitan_spi_device_fifo.sv` is written to be true under
# that, which is why the fairness, bounded-response and deadlock obligations
# are bounded counters over LOCAL progress and not over the whole subsystem.
#
# The census below counts the elaborated assumptions and names them. It should
# print 0 for this package; if a round prints more, a worker's file brought an
# assumption with it and the round log is where that has to be visible.

set ::diag_expected_assumes {}

proc setup_diag_opentitan_spi_device_fifo {{base_task FPV} {diag_task diag_opentitan_spi_device_fifo}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Every elaborated assumption, not only the `diag_*`-prefixed ones: this
    # package ships none, so a filter would print 0 for the wrong reason.
    set assumptions [get_property_list -include {type assume}]
    puts "diagnostic_task=$diag_task"
    puts "diagnostic_assumption_count=[llength $assumptions]"
    foreach p $assumptions {
        puts "ASSUME $p"
    }

    # The protected target. `cex.tcl` resolves targets for itself out of its own
    # label index and does not read what this returns, so this is a census for
    # the log -- report the count, and fail only on the one answer that is
    # certainly wrong.
    set targets [get_property_list \
        -include {type assert name {.*T_DATA_CMDFIFO_POP_EQ_PUSH.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No T_DATA_CMDFIFO_POP_EQ_PUSH target resolved in task '$diag_task'"
    }

    # A second census, for the phase-1 screen: how many of the 50 candidates
    # elaborated, and how many covers came with them.
    set candidates [get_property_list -include {type assert name {.*\.T_[A-Z0-9_]+$}} -regexp]
    set covers     [get_property_list -include {type cover  name {.*\.C_[A-Z0-9_]+$}} -regexp]
    puts "candidate_target_count=[llength $candidates]"
    puts "candidate_cover_count=[llength $covers]"

    return $targets
}

# Alias, for a caller that spells the proc without the `diag_` prefix. Both
# names run the same body and leave the same Jasper task in existence.
proc setup_opentitan_spi_device_fifo {{base_task FPV} {diag_task diag_opentitan_spi_device_fifo}} {
    return [setup_diag_opentitan_spi_device_fifo $base_task $diag_task]
}

puts {Loaded diag_opentitan_spi_device_fifo.tcl. Boot runs: setup_diag_opentitan_spi_device_fifo}
