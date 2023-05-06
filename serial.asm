
sioslot: equ	1		; SIO card in slot 1
siorate: equ	127		; 19200 bps

siobase: equ	(6-sioslot)*16
sioctl:	equ 	siobase+1
siobps:	equ	siobase+8

; Blocking write.
siowrite: macro data
	siowrite_wait
	ld a, data
	out (siobase), a
endm

; Write A.
siowritea: macro
	ld b, a
	siowrite_wait
	ld a, b
	out (siobase), a
endm

; Blocking read.
sioread: macro
	sioread_wait
	in a, (siobase)
endm

; Block until a character is waiting.
sioread_wait: macro
.wait:	in a, (sioctl)
	and 2
	jr z, .wait
endm

; Block until ready to send character.
siowrite_wait: macro
.wait:	in a, (sioctl)
	and 1
	jr z, .wait
endm

; Receive magic RLE stream.  HL points to beginning of buffer.
magic_receive: macro
.loopy:	sioread_wait	; grab control byte
	in a, (siobase)
	ld b, a

	and 0x80	; is it compressed data?
	jr z, .uncompressed

	ld a, b		; is it end of line?
	and 0x7f
	jr z, .done

	res 7, b	; drop high bit and add 1 to get count
	inc b
	sioread_wait 	; grab data byte
	in a, (siobase)
.compressed:	ld (hl), a ; blast to screen
	inc hl
	djnz .compressed
	jr .loopy
		
.uncompressed:	or b		; is it a fill character?
	jr z, .loopy
.uncompnext: sioread_wait
	in a, (siobase)
	ld (hl), a
	inc hl
	djnz .uncompnext
	jr .loopy
.done:  nop
endm

;	in a, (0x83)	; beep!
;	jr top		; wait for next frame
