# Run OpenCore PEC once with the existing FVEval checker.
# The native launcher derives its working directory from the driver location.
cd [file normalize [file join [file dirname [info script]] .. FVEval]]
clear -all
include tool_scripts/pec/pec.tcle
set signal_list [split $SIGNAL_LIST ","]
puts [prop_eq_checker $LM_ASSERT_TEXT $REF_ASSERT_TEXT "" "" $signal_list]
