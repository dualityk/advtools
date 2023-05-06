; Advantage serial bootloader.  

; Stage 1 typed into monitor.  Sets up serial port, listens for a fixed
; number of bytes (stage 2, sent by PC) and falls off the end into whatever
; it's loaded in.  No error checking, no nothin'.

; After the first stage is typed in to the Advantage and run, the second
; stage is sent over the serial connection.  The second stage is interactive
; with the host computer and much more talented.

; Adv sends a prompt byte to host (indeterminate on boot, just something)

; Host sends a command as follows:
; Address: 2 bytes, Size: 1 byte, Command: 1 byte
; For command 0, host then sends (size) bytes of data
; Adv returns a 1 byte value

; command 0: retrieve (size) bytes, startincg at (address), return 'r'
; command 1: verify (size) bytes, starting at (address), return checksum
; command 2: send (size) bytes, starting at (address), return 'k'
; command 3: null (size) bytes, starting at (address), return 'n'
; command 4: jump to (address), return 'J'
; command 6: receive compressed stream starting at (address), return 'c'
; command 7: read from port at LSB of address, return byte
; command 8: write (size) to port at LSB of address, return 'w'

; Invalid command returns to prompt with '?'.  You can sometimes wrap around
; to the prompt if it's stuck by sending an invalid command until a '?' is
; received.

; ian 2017

; right now target is at c01b, size is c017

include 'serial.asm'

target:	equ	0xff29		; String destination (end of stage 1)
size:	equ	139		; String size (0=256)

	; Main memory starts at c000 on boot.
	org 0xff00

; First stage bootloader starts here

	; reset serial port
	ld a, 0x80		; attn
	out (sioctl), a
	out (sioctl), a
 	ld a, 0x40		; software reset
	out (sioctl), a

	; set baud register
	ld a, siorate
	out (siobps), a

	; set mode 8,n,1, 16x clock, asynchronous
	ld a, 0x4e
	out (sioctl), a
	
	; send control byte: RTS, DTR, enable rx/tx, clear error
	ld a, 0x37
	out (sioctl), a

loopy:
	; set up size/destination, clear input reg
	ld b, size
	ld c, siobase
	ld hl, target
	in a, (siobase)

	; wait for character ready
dygttisy:
	sioread_wait
	ini
	jr nz, dygttisy

; ------

; Second stage bootloader starts here

	; send prompt/ack byte (whatever's in D)
prompt:
	siowrite_wait
	ld a, d
	out (siobase), a
	ld d, 'r'

	; fetch low address byte
	sioread
	ld l, a

	; fetch high address byte
	sioread
	ld h, a	
	
	; fetch size
	sioread
	ld b, a

	; fetch command
	sioread

	; what is innnn the box?
	; is it data?
	cp 0
	jr z, dygttisy
	; do you want some data?
	dec a
	jr z, senddata
	; do you want a checksum?
	dec a
	jr z, checksum
	; is it -nothing, absolutely nothing-?
	dec a
	jr z, nullblock
	; are we outta here?
	dec a
	jr z, boot
	; compressed data in?
	dec a
	jr z, uncompress
	; port input?
	dec a
	jr z, portin
	; port output?
	dec a
	jr z, portout
	; if none of those, say whaaaat and return to prompt
	ld d, '?'
	jr prompt

	; Checksum
checksum:
	xor a
	ckloop:
	add a, (hl)
	inc hl
	djnz ckloop
	ld d, a
	jr prompt
		
	; Reversing the flow
senddata:
	siowrite_wait
	outi
	jr nz, senddata
	ld d, 'k'
	jr prompt
	
	; Null memory block
nullblock:
	ld (hl), 0
	inc hl
	djnz nullblock
	ld d, 'n'
	jr prompt

	; tell host we're leaving and git!  (But make sure our J sent)
boot:
	siowrite 'J'
	siowrite_wait
	jp (hl)

uncompress:
	magic_receive	; macro from serial.asm
	ld d, 'c'
	jp prompt
	
	; fetch from a port and return it as acknowledgement
portin:
	ld c, l
	in a, (c)
	ld c, siobase
	ld d, a
	jp prompt

	; send to a port
portout:
	ld c, l
	ld a, b
	out (c), a
	ld c, siobase
	ld d, 'o'
	jp prompt
