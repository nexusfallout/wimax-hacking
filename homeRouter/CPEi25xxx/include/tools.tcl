# WARNING these formats change.  No effort is made to recover from failures.
proc get_reg {REG} {
    string range [lindex [split [ocd_reg $REG] " "] 2] 0 end-1
}

# WARNING these formats change.  No effort is made to recover from failures.
proc halt_parse {} {
    string range [lindex [split [ocd_halt] " "] 11] 0 end-1
}

# WARNING these formats change.  No effort is made to recover from failures.
proc step_parse {} {
    string range [lindex [split [ocd_step] " "] 11] 0 end-1
}

# Step the given number of times
proc step_count {count} {
    global pc
    for {set i 0} {$i < $count} {incr i} {
	set pc [step_parse]
    }
    return $pc
}

# Step for the given amount of time in milliseconds
proc step_time {time} {
    resume
    sleep $time
    return [halt_parse]
}

# Turn a list of words into a TCL array which looks like a list of
# words with arry indexes interjected between words.
proc arrayify {LIST} {
    set i 0
    foreach item $LIST {
	set ret($i) $item
	incr i
    }
    return $ret
}

# Compare two arrays and confirm that they match.
proc arraysmatch {A B} {
    puts "comparing:\nA: $A\nB: $B"
    if {[llength $A] != [llength $B]} {
	puts "array lengths do not match"
	return 0
    }
    for {set i 0} {$i < [expr [llength $A] / 2]} {incr i} {
	if {$A($i) != $B($i)} {
	    puts "ab($i) not the same: $A($i) != $B($i)"
	    return 0
	}
    }
    puts "good match"
    return 1
}

# Reboot the device and let it run for the specified ms before halting.
proc partial_boot {{time 14488}} {
    # This default is high precision right here, folks.  But it seems
    # to come in just after "Decrypt successful" on the console, and
    # before the watchdog is started or networking is up.
    puts [format "Waiting %0.3f seconds for partial boot" [expr $time / 1000.0]]
    reset init
    return [step_time $time]
}

# An old name for partial_boot.  Probably not used any more.
proc rehalt {{time 14488}} {
    return [partial_boot $time]
}

# Ninja Attack
proc save_registers {} {
    global savereg
    for {set i 1} {$i<=37} {incr i} {
	set savereg($i) [get_reg $i]
    }
}

# Ninja Vanish
proc restore_registers {} {
    global savereg
    for {set i 1} {$i<=37} {incr i} {
	reg $i $savereg($i)
    }
    step
}
