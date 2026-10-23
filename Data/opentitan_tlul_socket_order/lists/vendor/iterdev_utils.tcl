# Iterative FV development utilities (vendored for hermetic boot;
# verbatim semantics of the jasperIterDev safe_assume)
# Provides safe wrappers for destructive JG commands

proc safe_assume {args} {
    # Parse -task_name from args
    set idx [lsearch $args "-task_name"]
    if {$idx < 0} {
        error "safe_assume: -task_name is required.\nUsage: safe_assume -task_name <experiment_name> \{expression\}"
    }
    set task_name [lindex $args [expr {$idx + 1}]]
    set assume_args [lreplace $args $idx [expr {$idx + 1}]]

    if {[llength $assume_args] == 0} {
        error "safe_assume: no assume arguments provided after -task_name"
    }

    # Get current task for reference
    set original_task [task]

    # Create task if it doesn't exist, copying everything from current
    set existing [task -list -silent]
    if {$task_name ni $existing} {
        task -create $task_name -copy_all -set
        puts "Created new task '$task_name' (copied all from '$original_task')"
    } else {
        set current [task]
        if {$current ne $task_name} {
            task -set $task_name
        }
        puts "Using existing task '$task_name'"
    }

    # Run the assume in the new task
    set result [assume {*}$assume_args]
    puts "Assumption added in task '$task_name': $result"
    flush stdout
    return $result
}

puts "Loaded vendor/iterdev_utils.tcl (safe_assume available)."
