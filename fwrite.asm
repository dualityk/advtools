; Write to disk drive (less significant portions lifted from boot ROM)

include 'serial.asm'

drive: equ	0x01		; Drive to write to (01, 02, 04, 08)

; Start drive motor command.
startmotors: macro	
	ld a, 0x1d
	out (0xf8),a
endm

stopmotors: macro
	ld a, 0x18
	out (0xf8),a
endm

; Stop 

org 0xe000			; stay out of the way of buffer
	ld sp, stacktop		; make a small call stack
	ld a,002h		; disable RAM parity interrupts
	out (060h),a

				;drawl progress bar
	ld de, 0x0480
	ld a, 7			; left side
	ld (de),a
	ld a, 4
	ld b, 7
lp1:	inc e
	ld (de),a
	djnz lp1
	inc e
	ld a, 7
	ld (de),a

	ld a, 0xff		; middle
	ld b, 70
lp2:	inc d
	ld e, 0x88
	ld (de),a
	ld e, 0x80
	ld (de),a
	djnz lp2	

	inc d			; right
	ld a, 0xe0
	ld (de),a
	ld a, 0x20
	ld b, 7
lp3:	inc e
	ld (de),a
	djnz lp3
	inc e
	ld a, 0xe0
	ld (de),a


	ld a, 1			; map in the other 48k memory
	out (0xa0),a
	inc a
	out (0xa1),a
	inc a
	out (0xa2),a
	ld a, drive		; initialize our drive control byte
	ld (controlbyte), a

				; Put fdc/drive into motion
	startmotors
	call init_floppy
	stopmotors
	ld de, 0xc800		; Initial buffer position (empty)

nexttrack:
	ld a, (track)		; increment current cylinder
	inc a
	ld (track), a
	sub 35
	jp z, alldone		; 0 tracks left, we out

	ld a, 0xc8		; end of buffer?
	xor d
	call z, fill_buffer	; yup, ask for more
	
	startmotors		; start motor command and sleep for a bit
	ld a, 0xf0		; before selecting drive
	call sleep

	; ld a, 0xf0
	; call sleep
	; ld a, 0xf0
	; call sleep

	ld a, (track)		; set up our second sync byte
	rla
	rla
	rla
	rla
	rla
	rla
	and 0xc0
	ld (sync2), a

	ld a, (track)		; set up our drive control byte
	ld b, 0			; default no precomp
	sub 14			; are we on cylinder 0-15?
	jr c, shipit
	ld b, 0x20		; no, then set precomp

shipit:	ld a, drive
	or b
	out (0x81), a

	ld (controlbyte), a

				; write side 0
	call write_track
	or a
	jp nz, fail				

	ld a, (track)
	rla
	rla
	rla
	rla
	rla
	rla
	and 0xc0
	or  0x10
	ld (sync2), a

	call gottrack		; bump progress bar

	;ld a, drive
	;out (0x81), a
	ld a, (controlbyte)	; Flip to side 1 and write
	or 0x40
	out (0x81),a
	ld (controlbyte), a		
	call write_track
	or a
	jr nz, fail				

	call gottrack		; bump progress bar

	startmotors
	ld a, 0xf0
	call sleep
	ld a, 0xa0		; step one track inward
	call floppy_step	; and hop back to side 0
	stopmotors		; stop motor command and sleep
	ld a, 0xf0 
	call sleep

	jp nexttrack

; Read next (compressed) five tracks from serial port.
fill_buffer:
	ld hl, 0		; reset HL
	siowrite (track)	; tracks plz
	magic_receive		; grab stream from PC
	ld de, 0		; reset DE
	; in a, (0x83)		; beep!
	ret

alldone:
	siowrite 0xab		; succeeded prompt
	siowrite_wait
	ld a, 0xff
	call clear
	jp 0xff00
fail:				; if we failed, prompt with failure number
	siowritea
	siowrite_wait
	ld a, (track)		; and track number
	siowritea
	ld a, d			; and buffer position
	siowritea	
	ld a, e
	siowritea
	ld a, 0xff
	call clear
	jp 0xff00

; Write entire track (one side) from buffer at DE.
write_track:
	ld b,020h		; see if we get a sector pulse
sectorwait:
	dec bc
	ld a,b
	or c
	ld a, 0xf3		; fail: no pulse or sector not found
	ret z
	in a,(0e0h)
	and 040h
	jr z,sectorwait
	ld b,020h		; see if we stop getting a sector pulse
sw2:
	dec bc	
	ld a,b	 
	or c	 
	ld a, 0xf4		; fail: always pulse (maybe no disk?)
	ret z
	in a,(0e0h) 		
	and 040h
	jr nz,sw2

	in a,(0d0h)		; wait for our sector number to come up
	and 0x0f
	cp 0x0f
	jr nz,sectorwait

	ld a, 10		; write 10 sectors

next_sector:
	ex af,af'
	ld a, (controlbyte)
	ld b, a		
l81a8h:
	in a,(0e0h)		; wait til sector pulse low (should be now)
	and 040h
	jr nz,l81a8h
l81aeh:				; wait til sector pulse high
	in a,(0e0h)
	and 040h 
	jr z,l81aeh

	in a, (0xe0)		; is it write protected?
	and 0x10
	jr z, sendprecomp
	ld a, 0xf8		; yup, fail
	ret


monkeys:			; who the fuck knows
	in a, (0xe0)
	and 0
	ret z
	in a, (0x83)
	jr monkeys


sendprecomp:			; send our precomp/side selection
	ld a, (controlbyte)
	ld a, b
	out (0x81), a		; set precomp and side bits
	out (0x83), a		; set write flag (any data works)

	ld bc, 0x2200		; 34 bytes preamble, null c
writesync:	
	xor a			; write preamble
	out (0x80), a
	call monkeys
	djnz writesync
	
	ld a, 0xfb		; write first sync byte
	out (0x80), a
	
	ex (sp),hl		; monkey delay
	ex (sp),hl	

	ld a, (sync2)		; write second sync byte
	out (0x80), a

	;ld b,0			; write 512 bytes
	;ld c,0	 		; null CRC
writedata:
	ld a, (de)		; write a byte
	inc de
	out (080h),a				
	xor c			
	rlca			
	ld c,a			 			

	call monkeys		; monkey delay

	ld a, (de)		
	out (080h),a		; write another byte
	inc de
	xor c			 
	rlca			 
	ld c,a			 
	djnz writedata 

	ld a, c			; write CRC and done
	out (080h),a		
	xor c	 
	
	ld a, (sync2)		; Increment our sync byte for next sector
	inc a
	ld (sync2), a

	ex af,af'		
	dec a			; if we need another sector, go git it
	jr nz,next_sector	
	xor a			; otherwise peace
	ret


; Select drive, start motors, initialize FDC, and find track 0.

init_floppy:
	ld b,00ah		; 256 attempts to step
leave_track0:
	ld a,0a0h		; step inward
	call floppy_step	 
	in a,(0e0h)		; track 0?
	and 020h	
	jr z,seek_track0
	djnz leave_track0
	ld a, 0xf0		; fail: couldn't get off track 0
	ret
seek_track0:
	ld b,064h		; 100 attempts to step
st0loop:
	ld a,080h		; step outward
	call floppy_step
	in a,(0e0h)		; track 0?
	and 020h
	jr nz,reset_datasep
	djnz st0loop
	ld a, 0xf1		; fail: couldn't find track 0 again
	ret
reset_datasep:			; initialize data separator (p.3-34)
	ld b,004h		
rdsloop:
	out (082h),a
	ld a,07dh
	call sleep
	in a,(082h)
	ld a,07dh
	call sleep
	djnz rdsloop
	ret			

; Step and wait.  A should be 0x80 for outward, 0xa0 for inward.
floppy_step:
	ld c, drive
	or c
	out (081h),a 
	or 010h	
	out (081h),a
	xor 010h
	out (081h),a
	ld a,028h
sleep:				; sleep for 'a' whiles
	ld c,0fah 
sleepl:
	dec c 
	jr nz,sleepl 
	dec a	
	jr nz,sleep 
	ret

clear:				; clear screen and map in video
	ld a, 0xf8
	out (0xa0),a
	inc a
	out (0xa1),a

	ld de, 0x50ff
clloop:	ld a, 0
	ld (de),a
	dec de
	ld a, d
	or e
	jr nz, clloop

	ret


gottrack:			; bump progress bar
	push de
	ld a, 0xf8		; map in video memory
	out (0xa0),a
	inc a
	out (0xa1),a
	ld a, (bufferbar)	; increment location
	inc a
	ld (bufferbar),a
	ld d, a
	ld e, 0x82
	ld b, 2			; drawl checkerboard
gt2: 	ld a, 0xaa
	ld (de),a
	inc e
	ld a, 0x55
	ld (de),a
	inc e
	djnz gt2
	ld a, 0xaa
	ld (de),a

	ld a, 1			; map main memory back in
	out (0xa0),a
	inc a
	out (0xa1),a
	pop de
	ret

bufferbar:	db 4
track:  db 0xff			; Current cylinder
controlbyte:	db 0		; Drive control byte
sync2:  db 0			; Current sector ID mask
	dw 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
stacktop:
