#!/bin/bash

SERIAL="${1:-/dev/ttyUSB0}"

fail() { echo "$@"; exit 1; }
[ -c $SERIAL ] || fail "$SERIAL doesn't look like a device file."
[ -r $SERIAL ] || fail "You don't have read access to $SERIAL."
echo "Using serial device $SERIAL for console access."

screen -d -m -S ${SERIAL##*/} -fn $SERIAL 115200
# There should be some testing in here to verify that we actually have
# control of the serial device.  Maybe a log file of serial output that
# is checked for activity.

{
    sleep 1
    echo -e "set CPU_MAX_ADDRESS 0xFFFFFFFF\nscript unlock.tcl" | nc.traditional localhost 4444
} &
openocd 2>/dev/null
echo "Waiting for device to finish booting..."

cat <<EOF >/tmp/screen-exchange

mkdir /pstore/dbg_tools/
touch /pstore/dbg_tools/bd_open2
echo -e "unsetpermenv CONSOLE_STATE" >/proc/ticfg/env
echo -e "setpermenv CONSOLE_STATE unlocked" >/proc/ticfg/env
reboot
EOF

{
    sleep 5
    echo "Waiting for device to finish booting..."
    sleep 5
    echo "Waiting for device to finish booting..."
    sleep 5
    echo "Waiting for device to finish booting..."
    sleep 5
    echo "Enabling debug mode and setting CONSOLE_STATE unlocked in permenv."
    screen -X -S ${SERIAL##*/} readbuf
    screen -X -S ${SERIAL##*/} paste .
    screen -X -S ${SERIAL##*/} removebuf
    echo "All done.  Wait for second reboot and enjoy."
} &

exec screen -x ${SERIAL##*/}
