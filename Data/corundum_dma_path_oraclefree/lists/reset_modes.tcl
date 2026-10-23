# Reset-mode control for corundum_dma_path.
#
# v5 sources this file after the diag task is set and calls exactly two things
# out of it: `rm_all_registers` (to enumerate what the cut may take) and
# `_rm_apply_reset` (to re-apply reset after `stopat -reset`). Both are in
# `v5/cex.tcl:ENTER_FRA_KEEP`. Everything else here is reporting.
#
# Deliberately smaller than the internal reference task package's copy of this file. That one
# carries a manual-workspace API and a tailored keep-set for one FIFO inside
# one internal reference task instance; none of it is reachable from a v5 round, and a
# design-specific keep list in here would be a second place that decides the
# cut, competing with `taskdefs.DESIGN_KEEP`.

set ::rm_reset_expr {rst == 1'b1}
set ::rm_reset_max_iterations 100

proc rm_all_registers {} {
    return [get_design_info -list register -silent]
}

proc _rm_apply_reset {} {
    reset -expression $::rm_reset_expr -max_iterations $::rm_reset_max_iterations
}

proc rm_reset_stopats {} {
    return [stopat -reset -list]
}

proc rm_reset_stopat_count {} {
    return [llength [rm_reset_stopats]]
}

proc rm_full_register_count {} {
    return [llength [rm_all_registers]]
}

proc rm_status {} {
    set stopat_count [rm_reset_stopat_count]
    set register_count [rm_full_register_count]
    if {$stopat_count == 0} {
        set mode normal
    } elseif {$stopat_count == $register_count} {
        set mode fra_all
    } else {
        set mode fra_keep
    }
    puts "RESET_STATUS mode=$mode reset_stopat_count=$stopat_count full_register_count=$register_count"
    return [list $mode $stopat_count $register_count]
}

proc rm_enter_normal {} {
    stopat -reset -clear
    _rm_apply_reset
    if {[rm_reset_stopat_count] != 0} {
        error "Refusing concrete-reset operation: reset_stopat_count=[rm_reset_stopat_count]"
    }
    puts "RESET_MODE normal"
    return [rm_status]
}

puts {Loaded reset_modes.tcl. v5 uses rm_all_registers and _rm_apply_reset.}
