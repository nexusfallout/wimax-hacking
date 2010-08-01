global CPU_MAX_ADDRESS
set CUP_MAX_ADDRESS 0xffffffff
global address_buffer
set address_buffer 0xb4000000
global address_code
set address_code 0xA0000000
source [find bitsbytes.tcl]
source [find memory.tcl]
source include/tools.tcl

# This does something with... Hrm, I don't remember.  Ugh, TCL is...
# Not my favorite.
proc parse_bytes {line} {
    set bytes "0x"
    foreach word $line {
	set nibbles [split $word {}]
	set b 1
	foreach nibble $nibbles {
	    append bytes $nibble
	    set b [expr ! $b]
	    if ($b) {
	       append bytes " 0x"
	    }
	}
    }
    return [string range $bytes 0 end-3]
}

# It is probably faster to write to RAM and then use copy_to_flash for
# anything large.  But for writing a few bytes direct to flash, this
# will do the trick.  Example:
# > buffer_write_line {B0000000: 00908040 00988040 00601A40 FEFF1B24 24D05B03 40001B3C 25D05B03 00609A40}
proc buffer_write_line {line} {
    set address "0x[string range [lindex $line 0] 0 end-1]"
    set sector [format "0x%08x" [extract_bitfield $address 31 17]]
    set base [format "0x%08x" [extract_bitfield $address 31 27]]
    set bytes [parse_bytes [lrange $line 1 8]]
    set length [llength $bytes]
    memwrite8 [expr $base + 0xAAA] 0xAA
    memwrite8 [expr $base + 0x555] 0x55
    memwrite8 $sector 0x25
    memwrite8 $sector [expr $length-1]
    set offset 0
    foreach byte $bytes {
	memwrite8 [expr $address + $offset] $byte
	incr offset
    }
    memwrite8 $sector 0x29
    puts "Wrote $address"
    return
}

# Not sure why this would be needed, it was in the specs and seemed
# like something that could come in handy during early development.
proc write_buffer_abort_reset {address} {
    set base [format "0x%08x" [extract_bitfield $address 31 27]]
    memwrite8 [expr $base + 0xAAA] 0xAA
    memwrite8 [expr $base + 0x555] 0x55
    memwrite8 [expr $base + 0xAAA] 0xF0
}

# Need to erase a sector of flash?  Here ya go.  Example:
# > erase_sector 0xB0020000
proc erase_sector {address} {
    set sector [format "0x%08x" [extract_bitfield $address 31 17]]
    set base [format "0x%08x" [extract_bitfield $address 31 27]]
    set sectend [format "0x%08x" [expr $sector + [create_mask 16 0]]]
    memwrite8 [expr $base + 0xAAA] 0xAA
    memwrite8 [expr $base + 0x555] 0x55
    memwrite8 [expr $base + 0xAAA] 0x80
    memwrite8 [expr $base + 0xAAA] 0xAA
    memwrite8 [expr $base + 0x555] 0x55
    memwrite8 $sector 0x30
    puts -nonewline "Erasing $sector-$sectend"
    while {[memread8 $sectend] != 0xFF} {
	puts -nonewline {.}
	sleep 10
    }
    puts "  Done."
}

# Find a place where we can cleanly set pc.  The core may be in the
# middle of a multi step operation.  This steps as many as 5 times to
# finish any existing operations and pc is in the code we want to run.
proc first_step {start} {
    for {set i 0} {$i < 5} {incr i} {
	reg pc $start
	set pc [step_parse]
	if {$pc == [expr $start+4]} break
    }
    if {$pc != [expr $start+4]} {
	puts "Failed to set PC"
	return -1
    }
    return $pc
}

# Poke small code chunk into a useful address space and verify.
proc poke_code {address code name} {
    set length [expr [llength $code] / 2]
    ocd_array2mem code 32 $address $length
    sleep 5
    ocd_mem2array verify_code 32 $address $length
    if {[arraysmatch $code $verify_code] != 1} {
	puts "Failed to write $name"

	puts "verify: $verify_code\ncode:   $code"
	mdw $address $length

	return -1
    }
    #mdw $address $length
    return $length
}

# Run some code until it is done (code should end in an infinite loop).
proc run_code {address length increment timeout} {
    set pc [first_step $address]
    if {$pc == -1} {return -1}
    set endpoint [expr $address + 4 * [expr $length - 2]]
    puts [format "Debug: all ready to step through until pc>0x%08x." $endpoint]
    set usec 5
    sleep $usec
    while {$pc >= $address && $pc < $endpoint} {
	set usec [expr $usec + $increment]
	resume
	sleep $increment
	set pc [halt_parse]
	if {$usec > $timeout} {
	    puts [format "Timed out after %.3f seconds at address $pc" [expr $usec / 1000.0]]
	    return -1
	}
    }
    puts [format "Finished running code in %.3f seconds" [expr $usec / 1000.0]]
    return $pc
}

# This is the code that does the actual work of comparing specified
# address space against a provided word.  Most useful for verifying
# that RAM is empty (0x00000000) or that flash is empty (0xFFFFFFFF).
proc verify_worker {address expect bytes} {
    global address_code
    set verify_erase_code [arrayify [concat \
	0x00822820 0x8CA10000 0x10260002 0x00000000 0x24E70001 0x24420004 0x1443FFF9 0x00000000 0x1000FFFF 0x00000000 \
    ]]
    #a0 = <from address>
    #a2 = <expect>	(0xFFFFFFFF)
    #a3 = <errors>	(0)
    #v0 = <skip>	(0)
    #v1 = <bytes>	(0x20000)
    #					/-op-\/rs-\/rt-\/----offset----\
    # SPECIAL ADD a0, v0, a1		00000000100000100010100000100000	00822820
    # LW a1, at, 0			10001100101000010000000000000000	8CA10000
    # BEQ at, a2, 2			00010000001001100000000000000010	10260002
    # NOP				0					00000000
    # ADDIU a3, a3, 1			00100100111001110000000000000001	24E70001
    # ADDIU v0, v0, 4			00100100010000100000000000000100	24420004
    # BNE v0, v1, -7			00010100010000111111111111111001	1443FFF9
    # NOP				0					00000000
    # BEQ zero, zero, -1		00010000000000001111111111111111	1000FFFF
    # NOP				0					00000000

    set code_length [poke_code $address_code $verify_erase_code "verify erase code"]
    if {$code_length == -1} {return 0}

    reg a0 [expr $address + ((4 - $address % 4) % 4)]
    reg a2 $expect
    reg a3 0
    reg v0 0
    reg v1 [expr $bytes + ((4 - $bytes % 4) % 4)]

    set pc [run_code $address_code $code_length 100 10000]
    if {$pc == -1} {return 0}

    set start [format "0x%08x" [get_reg a0]]
    set end [format "0x%08x" [expr [get_reg a1] + 3]]
    set errors [format "%i" [get_reg a3]]
    if {$errors > 0} {
	puts "Address range $start-$end has $errors non-empty word/s."
	return 0
    }
    puts "Address range $start-$end is verified empty."
    return 1
}

# Confirm that a sector of flash is blank/erased
proc verify_erase {address {bytes 0x20000}} {
    return [verify_worker $address 0xFFFFFFFF $bytes]
}

# Confirm that a sector of RAM is blank/empty
proc verify_blank {address {bytes 0x20000}} {
    return [verify_worker $address 0x00000000 $bytes]
}

# This just coppys from one address range to another.
proc copy_to_ram {from_addr to_addr bytes} {
    global address_code

    set cache_code [arrayify [concat \
	0x00822820 0x00C23820 0x8CA10000 0xACE10000 0x24420004 0x1443FFFA 0x00000000 0x1000FFFF 0x00000000 \
    ]]
    #a0 = <from address>
    #a2 = <to address>
    #v0 = <skip>	(0)
    #v1 = <bytes>	(0x20000)
    #				/-op-\/rs-\/rt-\/----offset----\
    # SPECIAL ADD a0, v0, a1	00000000100000100010100000100000	00822820
    # SPECIAL ADD a2, v0, a3	00000000110000100011100000100000	00C23820
    # LW a1, at, 0		10001100101000010000000000000000	8CA10000
    # SW a3, at, 0		10101100111000010000000000000000	ACE10000
    # ADDIU v0, v0, 4		00100100010000100000000000000100	24420004
    # BNE v0, v1, -6		00010100010000111111111111111010	1443FFFA
    # NOP			0					00000000
    # BEQ zero, zero, -1	00010000000000001111111111111111	1000FFFF
    # NOP			0					00000000

    set code_length [poke_code $address_code $cache_code "copy to ram code"]
    if {$code_length == -1} return

    # set up registers
    reg a0 $from_addr
    reg a2 $to_addr
    reg v0 0
    reg v1 [expr $bytes + ((4 - $bytes % 4) % 4)]

    # make sure the flash is awake
    memread8 $from_addr

    # run the code until it is done
    set pc [run_code $address_code $code_length 10 1000]
    if {$pc == -1} return

    puts "Finished copy to ram."
}

# Welcome to expirement land.  This doesn't actually work.  It doesn't
# monitor UART status, thus only 16 bytes or so get written reliably.
proc copy_to_serial {from_addr bytes} {
    global address_code

    set cache_code [arrayify [concat \
	0x00822820 0x80A10000 0xA0C10000 0x24420001 0x1443FFFB 0x00000000 0x1000FFFF 0x00000000
    ]]
    #a0 = <from address>
    #a2 = <to address>
    #v0 = <skip>	(0)
    #v1 = <bytes>	(0x20000)
    #				/-op-\/rs-\/rt-\/----offset----\
    # SPECIAL ADD a0, v0, a1	00000000100000100010100000100000	00822820
    # LB a1, at, 0		10000000101000010000000000000000	80A10000
    # SB a2, at, 0		10100000110000010000000000000000	A0C10000
    # ADDIU v0, v0, 1		00100100010000100000000000000001	24420001
    # BNE v0, v1, -5		00010100010000111111111111111011	1443FFFB
    # NOP			0					00000000
    # BEQ zero, zero, -1	00010000000000001111111111111111	1000FFFF
    # NOP			0					00000000

    set code_length [poke_code $address_code $cache_code "copy to serial code"]
    if {$code_length == -1} return

    # set up registers
    reg a0 $from_addr
    reg a2 0xA8610E00
    reg v0 0
    reg v1 $bytes

    # make sure the flash is awake
    memread8 $from_addr

    # run the code until it is done
    set pc [run_code $address_code $code_length 10 1000]
    if {$pc == -1} return

    memwrite8 0xA8610E00 0x0d
    memwrite8 0xA8610E00 0x0a

    puts "Finished copy to serial."
}

# Want to write a bunch of zeros to something?  Look no further.
proc zero_ram {start bytes} {
    global address_code

    set zero_code [arrayify {0xA0810000 0x24840001 0x1485FFFD 0x00000000 0x1000FFFF 0x00000000}]
    #a0 = <start address>
    #a1 = <end address +1>
    #at = <data>	(0)
    #				/-op-\/rs-\/rt-\/----offset----\
    # SB a0, at, 0		10100000100000010000000000000000	A0810000
    # ADDIU a0, a0, 1		00100100100001000000000000000001	24840001
    # BNE a0, a1, -3		00010100100001011111111111111101	1485FFFD
    # NOP			0					00000000
    # BEQ zero, zero, -1	00010000000000001111111111111111	1000FFFF
    # NOP			0					00000000

    set code_length [poke_code $address_code $zero_code "zero ram code"]
    if {$code_length == -1} return

    # set up registers
    reg a0 $start
    reg a1 [expr $start + $bytes]
    reg at 0

    # run the code until it is done
    set pc [run_code $address_code $code_length 10 1000]
    if {$pc == -1} return

    puts "Finished zeroing ram."
}

# If you have something in RAM that you want to write to flash, this is
# totally what you want.  Just don't try to copy directly from flash to
# flash.  That would probably bork.
proc copy_to_flash {from_addr to_addr bytes} {
    global address_code
    set base [format "0x%08x" [extract_bitfield $to_addr 31 27]]

    set write_code [arrayify [concat \
	0x3C13FFFE 0x00D39824 0x2415003F 0x00C23820 0x00F5B820 0xA2110AAA 0xA2120555 0xA2740000 \
	0xA2750000 0x00822820 0x00C23820 0x80A10000 0xA0E10000 0x24420001 0x14F7FFFA 0x00000000 \
	0xA2760000 0x00000000 0x00000000 0x80F90000 0x0039C826 0x0319C824 0x1319FFFA 0x00000000 \
	0x1443FFEA 0x00000000 0x1000FFFF 0x00000000 \
    ]]
    #a0 = <from address>
    #a2 = <to address>
    #v0 = <skip>	(0)
    #v1 = <bytes>	(0x20000)
    #s0 = <base>	(0xB0000000)
    #s1 = <unlock_cmd1>	(0xAA)
    #s2 = <unlock_cmd2>	(0x55)
    #s4 = <bwrite_cmd1>	(0x25)
    #s6 = <bwrite_cmd2>	(0x29)
    #t8 = <status_mask>	(0x80)
    #				/-op-\/rs-\/rt-\/----offset----\
    # LUI zero, s3, 0xFFFE	00111100000100111111111111111110	3C13FFFE
    # SPECIAL AND a2, s3, s3	00000000110100111001100000100100	00D39824
    # ADDIU zero, s5, 63	00100100000101010000000000111111	2415003F
    # SPECIAL ADD a2, v0, a3	00000000110000100011100000100000	00C23820
    # SPECIAL ADD a3, s5, s7	00000000111101011011100000100000	00F5B820
    # SB s0, s1, 0xAAA		10100010000100010000101010101010	A2110AAA
    # SB s0, s2, 0x555		10100010000100100000010101010101	A2120555
    # SB s3, s4, 0		10100010011101000000000000000000	A2740000
    # SB s3, s5, 0		10100010011101010000000000000000	A2750000
    # SPECIAL ADD a0, v0, a1	00000000100000100010100000100000	00822820
    # SPECIAL ADD a2, v0, a3	00000000110000100011100000100000	00C23820
    # LB a1, at, 0		10000000101000010000000000000000	80A10000
    # SB a3, at, 0		10100000111000010000000000000000	A0E10000
    # ADDIU v0, v0, 1		00100100010000100000000000000001	24420001
    # BNE a3, s7, -6		00010100111101111111111111111010	14F7FFFA
    # NOP			0					00000000
    # SB s3, s6, 0		10100010011101100000000000000000	A2760000
    # NOP			0					00000000
    # NOP			0					00000000
    # LB a3, t9, 0		10000000111110010000000000000000	80F90000
    # SPECIAL XOR at, t9, t9	00000000001110011100100000100110	0039C826
    # SPECIAL AND t8, t9, t9	00000011000110011100100000100100	0319C824
    # BEQ t8, t9, -6		00010011000110011111111111111010	1319FFFA
    # NOP			0					00000000
    # BNE v0, v1, -22		00010100010000111111111111101010	1443FFEA
    # NOP			0					00000000
    # BEQ zero, zero, -1	00010000000000001111111111111111	1000FFFF
    # NOP			0					00000000

    set code_length [poke_code $address_code $write_code "copy to flash code"]
    if {$code_length == -1} return

    # erase
    erase_sector $to_addr
    mdw $to_addr 16

    # set up registers
    reg a0 $from_addr
    reg a2 $to_addr
    reg v0 0
    reg v1 [expr $bytes + ((64 - $bytes % 64) % 64)]
    reg s0 $base
    reg s1 0xAA
    reg s2 0x55
    reg s4 0x25
    reg s6 0x29
    reg t8 0x80

    # run the code until it is done
    set pc [run_code $address_code $code_length 100 10000]
    if {$pc == -1} return

    puts "Finished copy to flash."
}
