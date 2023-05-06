; Read from disk drive (significant portions lifted from boot ROM)

include 'serial.asm'

driveno: equ	0x01		; Drive to read from (01, 02, 04, 08)
maxtries: equ	128		; Track read attempts per call

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
	ld de, 0x0490
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
	ld e, 0x98
	ld (de),a
	ld e, 0x90
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
	exx			; Put fdc/drive into motion
	ld c, driveno
	exx
	startmotors
	call init_floppy

	stopmotors		; Reset our timeout
	ld a, 0xf0
	call sleep
	startmotors
	ld a, 0xf0
	call sleep

nexttrack:
	ld a, (tracks)		; decrement our tracks remaining
	dec a
	ld (tracks), a
	jr z, alldone		; 0 tracks left, we out
	xor a
	exx			; try to get side 0
	ld b, maxtries
	or c
	exx
	out (0x81), a				
 	call fetch_track
	or a
	jr nz, fail				
	ld (bufferp), de	; advance buffer

	call gottrack		; bump progress bar

	ld a, 0x40		; try to get side 1
	exx
	ld b, maxtries
	or c
	exx
	out (0x81),a		
	call fetch_track
	or a
	jr nz, fail				
	ld (bufferp), de	; so advance buffer
	stopmotors		; stop motor command and sleep
	ld a, 0xf0 
	call sleep
	
	call gottrack		; bump progress bar again

	ld de, (bufferp)
	ld a, 0xc8		; buffer full?
	xor d
	call z, writebuf	; yup, write buffer
	
	startmotors		; start motor command and sleep for a bit
	ld a, 0xf0		; before selecting drive
	call sleep
	ld a, 0xa0		; step one track inward
	call floppy_step	; and hop back to side 0

	jr nexttrack

; Write buffer out to serial port.
writebuf:
	; in a, (0x83)
	ld hl, 0
	ld c, siobase
wbloop:
	siowrite_wait
	ld a, (hl)
	outi
	dec de
	ld a, d
	or e
	jr nz, wbloop
	ld (bufferp), de
	ret

alldone:
	;call writebuf		; flush buffer
	siowrite 0xab		; succeeded prompt
	siowrite_wait
	ld a, 0xff
	call clear
	jp 0xff00
fail:				; if we failed, prompt with failure number
	siowritea
	siowrite_wait
	ld a, (tracks)
	siowritea
	ld a, d
	siowritea
	ld a, e
	siowritea
	ld a, 0xff
	call clear 
	jp 0xff00

; Fetch entire track (one side) into (buffer).
fetch_track:
	exx			; first fail if retries exceeded
	dec b
	exx
	ld a, 0xf2
	ret z

	in a,(082h)		; clear read flag 
	ld de, (bufferp)	; set buffer to beginning of track
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

	ld a,0x0a		; grab 10 sectors
	ld b,0			; bytes to grab/2 from first sector

next_sector:
	ex af,af'
l81a8h:
	in a,(0e0h)		; wait til sector pulse low (should be now)
	and 040h
	jr nz,l81a8h
l81aeh:				; wait til sector pulse high
	in a,(0e0h)
	and 040h 
	jr z,l81aeh
	ld a,064h		; wait 100 times (~150us p3-36)
l81b6h:
	dec a	 
	jr nz,l81b6h
	ld a,015h		; clear acquire mode 
	out (0f8h),a
	out (082h),a		; set read data flag
	ld a,018h		; wait
l81c1h:				
	dec a
	jr nz,l81c1h
	ld a,01dh		; set acquire mode 
	out (0f8h),a
	ld a,b	
	ld bc,0x64e0 		; hang out til disk serial bit goes high
l81cch:
	db 0xed, 0x70		; undocumented: in (c), flags set only
	jp m,get_preamble 
	djnz l81cch 
	jp fetch_track		; aw, it never did
get_preamble:
	ld b,a			; restore b
	in a,(081h)	 	; did we get a valid sync byte?
	cp 0xfb		 
	jp nz,fetch_track 	; nope
	in a,(080h)		; load sector ID and never speak of it again
	ld c,000h 		; null CRC

fetchdata:
	in a,(080h)		; grab byte
	ld (de),a		
	xor c			
	rlca			
	ld c,a			 
	inc de			
	in a,(080h)		; grab another byte
	ld (de),a		
	xor c			 
	rlca			 
	ld c,a			 
	inc de			 
	djnz fetchdata		 

	in a,(080h)		; grab CRC byte and see if we made it 
	xor c	 
	in a,(082h)		; exit read mode
	jp nz,fetch_track

	ex af,af'		
	dec a			; if we need another sector, go git it 
	jr nz,next_sector	
	xor a
	ret			; otherwise peace


; Select drive, start motors, initialize FDC, and find track 0.
; C' should be 1 for drive 1, 2 for drive 2.
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
	exx 
	or c 
	exx
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
	ld a, 0xf8		; map in video memory
	out (0xa0),a
	inc a
	out (0xa1),a
	ld a, (bufferbar)	; increment location
	inc a
	ld (bufferbar),a
	ld d, a
	ld e, 0x92
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

	ret

bufferbar:	db 4
bufferp: dw 0x0000		; Buffer pointer
tracks: db 36			; Physical track counter
	dw 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
stacktop: