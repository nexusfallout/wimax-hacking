global CPU_MAX_ADDRESS
set CPU_MAX_ADDRESS 0xFFFFFFFF
source include/wflash.tcl

set address_code 0xA0000000
set address_bootloader 0xB0000000
set address_bootloader_config 0xB0020000
set address_sneaky_flash 0xB0C00000
set address_buffer 0xB4000000
set address_sneaky_ram 0xB5F01000
set address_sneaky_ram_alt 0xB6AFF000
set offset_list {0x1185C 0x11848 0x1161C}
set expect_CONSOLE_STATE [arrayify {0x534E4F43 0x5F454C4F 0x54415453 0x6F6C0045 0x64656B63 0xFFFFFF00 0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF}]
set set_CONSOLE_STATE [arrayify {0x534E4F43 0x5F454C4F 0x54415453 0x6E750045 0x6B636F6C 0x42006465 0x43544F4F 0x6D004746 0x223A663A 0x47414D49 0x22425F45 0xFFFFFF00}]

# reset with functional RAM
reset init

# Search for the bootloader default config blob and alter CONSOLE_STATE
set offset_fixed 0
foreach offset $offset_list {
    set address_CONSOLE_STATE [expr $address_bootloader + $offset]
    mem2array verify_CONSOLE_STATE 32 $address_CONSOLE_STATE [expr [llength $expect_CONSOLE_STATE] / 2]
    if {[arraysmatch $expect_CONSOLE_STATE $verify_CONSOLE_STATE] == 1} {
	puts "### Found CONSOLE_STATE.  Changing to unlocked..."
	copy_to_ram $address_bootloader $address_buffer 0x20000

	# alter the buffer
	array2mem set_CONSOLE_STATE 32 [expr $address_buffer + $offset] [expr [llength $set_CONSOLE_STATE] / 2]
	mdb [expr $address_buffer + $offset] [expr [llength $set_CONSOLE_STATE] / 2 * 4]

	copy_to_flash $address_buffer $address_bootloader 0x20000
	set offset_fixed 1
	break
    } else {
	if {[arraysmatch $set_CONSOLE_STATE $verify_CONSOLE_STATE] == 1} {
	    puts "### Found CONSOLE_STATE and it is already unlocked."
	    set offset_fixed 1
	    break
	} else {
	    puts "### Failed to locate CONSOLE_STATE at $offset."
	}
    }
}
if {$offset_fixed != 1} {
    puts "### Tried all known offsets.  Please dump your bootloader, search for"
    puts "### the offset to CONSOLE_STATE=locked, and add that to offset_list."
    return
}

# Try to find a spot to stash the bootloader config temporarily
if {[verify_erase $address_sneaky_flash] != 1} {
    set address_sneaky_flash [expr $address_sneaky_flash + 0x20000]
    if {[verify_erase $address_sneaky_flash] != 1} {
	puts "### Darn, couldn't find a good spot to hide the bootloader config."
	return
    }
}

puts "### Copying bootloader config."
copy_to_ram $address_bootloader_config $address_buffer 0x20000
copy_to_flash $address_buffer $address_sneaky_flash 0x20000
puts "### Erasing orriginal bootloader config."
erase_sector $address_bootloader_config
puts "### Prepping RAM."
zero_ram $address_sneaky_ram 0x2000
zero_ram $address_sneaky_ram_alt 0x2000
puts "###"
puts "### Booting device to rebuild the temporary bootloader config."
puts "###"
puts "### This will take a few seconds."
puts "###"
partial_boot 13000
puts "### Halting mid boot to switch back to orriginal config."
save_registers
mem2array save_code 32 $address_code 30
if {[verify_blank $address_sneaky_ram 0x1800] != 1} {
    set address_sneaky_ram $address_sneaky_ram_alt
    if {[verify_blank $address_sneaky_ram 0x1800] != 1} {
	puts "### Darn, couldn't find a good spot in RAM for shuffling bootloader back."
	return
    }
}
puts "### Shuffling bootloader config from secret stash to orriginal location."
copy_to_ram $address_sneaky_flash $address_sneaky_ram 0x1800
copy_to_flash $address_sneaky_ram $address_bootloader_config 0x1800
puts "### Cleaning up from bootloader config shuffle."
erase_sector $address_sneaky_flash
zero_ram $address_sneaky_ram 0x1800
puts "### Cleaning up registers and stuff."
array2mem save_code 32 $address_code 30
restore_registers
puts "### Resuming boot like nothing happened.  (Ninja Vanish)"
resume
puts "All done over here, go poke at the serial interface."
puts "You should have a shell in a few moments."
puts "Hit enter when instructed, then do the following 4 commands:"
puts "mkdir /pstore/dbg_tools/"
puts "touch /pstore/dbg_tools/bd_open2"
puts {echo -e "unsetpermenv CONSOLE_STATE" >/proc/ticfg/env}
puts {echo -e "setpermenv CONSOLE_STATE unlocked" >/proc/ticfg/env}
puts "At this point, networking and other services will be down.  `reboot` to play with the fully functional system."
shutdown
