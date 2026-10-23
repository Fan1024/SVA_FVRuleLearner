# lists/diag_tlul_socket_order.tcl — the diag environment for
# opentitan_tlul_socket_order.
#
# v5 sources this file and then calls `setup_diag_tlul_socket_order` at global
# scope (v5/cex.tcl, v5/check.tcl), and does `task -set diag_tlul_socket_order`
# straight after. So this proc's one hard obligation is to leave a Jasper task
# by that exact name in existence.
#
# The diag DECLARES NO ASSUMPTION OF ITS OWN, and that is a decision rather than
# an omission. This task's two environment assumptions are written in the
# package itself -- `testbench.A_RESET_IDLE` (no request asserted while reset is
# held) and `testbench.A_REQUEST_STICKY` (a stalled host request holds its
# device, source, address and data until it is accepted) -- so they are already
# in the elaborated set before this file is sourced, and repeating them here
# would be a second, competing statement of the environment. The census below
# counts the elaborated assumptions and names them, which is what a reader of
# the round log needs.

set ::diag_expected_assumes {testbench.A_RESET_IDLE testbench.A_REQUEST_STICKY}

proc setup_diag_tlul_socket_order {{base_task FPV} {diag_task diag_tlul_socket_order}} {
    if {$diag_task ni [task -list -silent]} {
        task -set $base_task
        task -create $diag_task -copy_all -set
        puts "Created diag task '$diag_task' (copied all from '$base_task')"
    } else {
        task -set $diag_task
        puts "Using existing diag task '$diag_task'"
    }

    task -set $diag_task

    # Every elaborated assumption, not only the `diag_*`-prefixed ones the
    # reference package looks for: here the environment ships WITH the package,
    # so a filter on `diag_*` would print 0 and read as "unconstrained", which
    # is the wrong thing to tell someone reading the log.
    set assumptions [get_property_list -include {type assume}]
    puts "diagnostic_task=$diag_task"
    puts "diagnostic_assumption_count=[llength $assumptions]"
    foreach p $assumptions {
        puts "ASSUME $p"
    }

    # The protected target. `cex.tcl` resolves targets for itself out of its
    # own label index and does not read what this returns, so this is a census
    # for the log -- report the count, and fail only on the one answer that is
    # certainly wrong.
    set targets [get_property_list \
        -include {type assert name {.*T_TLUL_SOCKET_RESPONSE_ORDER.*}} -regexp]
    puts "protected_target_count=[llength $targets]"
    foreach p $targets {
        puts "TARGET $p"
    }
    if {[llength $targets] == 0} {
        error "No T_TLUL_SOCKET_RESPONSE_ORDER target resolved in task '$diag_task'"
    }
    return $targets
}

puts {Loaded diag_tlul_socket_order.tcl. Boot runs: setup_diag_tlul_socket_order}
