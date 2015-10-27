## WebUI Tricks ##
  * Engineering Menu: move your mouse over the device image, then hold ctrl+shift+e and click
  * Software Menu: move your mouse over the device image, then hold ctrl+alt+h
  * LFI: `http://192.168.15.1/cgi-bin/sysconf.cgi?page=../../[afile]&action=request&sid=[valid_sid]&timestamp=[valid_timestamp]`

## Remote Command Execution ##
  1. load up TamperData, Charles, or some other tampering proxy
  1. log into the device and change the Basic->Device Name to FOO
  1. in your tampering proxy, change FOO to `<!--#exec cmd="<your command>" -->`
  1. using the LFI above, get /etc/hosts
  1. your command will be run, and you should see your results

## Software Unlock (enable telnet) ##
  1. Using the above Remote Command execution trick, run the command: ` fw_setenv factory 1 `
  1. reboot, and you can telnet right in.
  1. this disabled most the startup scripts, so you need to set your own IP - try 192.168.15.2

## Filesystem ##
  * /mnt/jffs2/conf/app/lighttpd.conf
  * /mnt/jffs2/conf/app/ipkg.conf
  * /bin/ipkg\_verify.sh
  * /etc/conf/app/pubkey
  * mtd5 & mtd6 are squashfs, but wierd.  use unsquashfs from http://deb.grml.org/pool/main/s/squashfs-lzma/

## Missing busybox functions ##
just download http://www.busybox.net/downloads/binaries/1.16.0/busybox-armv4l to the modem, then use it.  It is a pre-built busybox binary that contains all the normal functions.

## Teardown Instructions ##
_thanks to Panic_

To disassemble:
  * Remove two T6 screws located under the round black feet on the bottom.
  * Remove the colored piece from the right side of the case. On the clear modem this piece is black and has neither the logo on it nor the lights on it. To remove, use a credit card to pop it off. Begin along the vented portion at the top, move slowly along the edges starting from here, releasing the clips as you go. There are a three clips located in the center of this panel so some pulling will be required once the edges release to remove it. Note that you do not need to remove the left side panel to disassemble the modem -- in fact it appears that a few of the posts have been fused to help hold it in place.
  * Remove the three T8 screws from under the panel removed in the previous step.
  * Split the two halves of the modem using a credit card. This seemed to work best by beginning near the ports at the back and working outward from there. The clips are pretty heavy and require some force to release. There are two built into the bottom plastic. There are two minor clips near ports and two major clips on this side at the top. There are 3 major clips at the top. Two major clips on the front top curve. Three major clips on the front. Most of these should be identifiable in the FCC photos.


Note that you need to be careful of the antenna and its cables when
working on the top edge of the modem. The antenna uses an extremely
thin PCB and I could see ham handed disassembly breaking it. The main
PCB is attached to the case using a single T8 screw located at the
bottom rear of the case (near the power jack). This screw is not
externally accessible and will require splitting the case to get to.
The board is roughly 5.5" square.