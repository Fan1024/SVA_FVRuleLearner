# Explicit reset-mode control for this task package.
#
# LOAD-BEARING: v5/cex.tcl and v5/check.tcl source this file unconditionally,
# and cex.tcl's ENTER_FRA_KEEP calls `rm_all_registers` and `_rm_apply_reset`
# out of it. The reset expression here must agree with the one
# `lists/tc_elab.tcl` elaborates under, because ENTER_FRA_KEEP re-applies
# reset through `_rm_apply_reset` AFTER installing the `stopat -reset` cut.
#
# Reset stopats are global reset-abstraction state in Jasper. Do not rely on
# task names to distinguish concrete-reset qualification from FRA screening.

# Nyuzi's reset is ACTIVE HIGH and asynchronous (`always_ff @(posedge clk,
# posedge reset)`), which is the one line of this file that is not
# task-agnostic. It must agree with `reset -expression` in tc_elab.tcl.
set ::rm_reset_expr {reset == 1'b1}
set ::rm_reset_max_iterations 100

proc rm_all_registers {} {
    return [get_design_info -list register -silent]
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

proc _rm_apply_reset {} {
    reset -expression $::rm_reset_expr -max_iterations $::rm_reset_max_iterations
}

proc rm_enter_normal {} {
    stopat -reset -clear
    _rm_apply_reset
    rm_require_normal
    puts "RESET_MODE normal"
    return [rm_status]
}

proc rm_enter_fra_all {} {
    set regs [rm_all_registers]
    if {[llength $regs] == 0} {
        error "No registers found; elaborate the design before entering FRA reset mode"
    }

    stopat -reset -clear
    stopat -reset $regs
    _rm_apply_reset
    rm_require_fra_all
    puts "RESET_MODE fra_all"
    return $regs
}

proc rm_require_normal {} {
    set stopat_count [rm_reset_stopat_count]
    if {$stopat_count != 0} {
        error "Refusing concrete-reset operation: reset_stopat_count=$stopat_count"
    }
    return 1
}

proc rm_require_fra_all {} {
    set stopat_count [rm_reset_stopat_count]
    set register_count [rm_full_register_count]
    if {$register_count == 0} {
        error "No registers found; elaborate the design before requiring FRA reset mode"
    }
    if {$stopat_count != $register_count} {
        error "Refusing FRA operation: reset_stopat_count=$stopat_count full_register_count=$register_count"
    }
    return 1
}

puts {Loaded reset_modes.tcl. Use rm_enter_normal, rm_enter_fra_all, rm_require_normal, rm_require_fra_all.}
