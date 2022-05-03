;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;       Written by DualityK
;
;       Reverse engineered from binary by Frank Palazzolo
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        .area   CODE1   (ABS)   ; ASXXXX directive, absolute addressing

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; SIO board IO addresses in slot 1
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DATA    .equ    0x50
CTRL    .equ    0x51
BAUD    .equ    0x58

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Bits on the USART CTRL register
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

TXREADY .equ    0x01
RXREADY .equ    0x02

;;;;;;;;;;;;;;;;;;;;;;;;;
; Common BAUD Rate values
;;;;;;;;;;;;;;;;;;;;;;;;;

UART_BAUDRATE_19200     .equ    0x7f
UART_BAUDRATE_9600      .equ    0x7e
UART_BAUDRATE_2400      .equ    0x78
UART_BAUDRATE_1200      .equ    0x70
UART_BAUDRATE_300       .equ    0x40

        .org    0xFF00

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Initialize the USART to Async mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

INIT:
        ld      a,0x80
        out     (CTRL),a
        out     (CTRL),a

        ld      a,0x40          ; reset
        out     (CTRL),a

        ld      a,UART_BAUDRATE_19200
        out     (BAUD),a

        ld      a,0x4E          ; MODE - 8-N-1, 16x async mode
        out     (CTRL),a

        ld      a,0x37          ; COMMAND - enable stuff
        out     (CTRL),a

        ld      b,0x8B          ; operand - number of bytes
        ld      c,DATA          ; init port to use
        ld      hl,MAIN         ; operand - block write location in HL
        in      a,(DATA)        ; clear receive register

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Command 0 - Write a block to memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

BLKWRITE:
        in      a,(CTRL)        ; wait for a serial char
        and     RXREADY
        jr      z,BLKWRITE
        ini
        jr      nz,BLKWRITE

;;;;;;;;;;;;;;;;;;;;;;;
; Main loop starts here
;;;;;;;;;;;;;;;;;;;;;;;

MAIN:                           
        in      a,(CTRL)        ; wait for transmit buf clear
        and     TXREADY
        jr      z,MAIN
        ld      a,d             ; send char in D register - probably an 'r'
        out     (DATA),a
        ld      d,0x72          ; init D to 'r'
$LOOP1:
        in      a,(CTRL)        ; wait for a serial char
        and     RXREADY
        jr      z,$LOOP1
        in      a,(DATA)        ; save in L
        ld      l,a
$LOOP2:
        in      a,(CTRL)        ; wait for a serial char
        and     RXREADY
        jr      z,$LOOP2
        in      a,(DATA)
        ld      h,a             ; save in H
$LOOP3:
        in      a,(CTRL)        ; wait for a serial char
        and     RXREADY
        jr      z,$LOOP3
        in      a,(DATA)
        ld      b,a             ; save in B
$LOOP4:
        in      a,(CTRL)        ; wait for a serial char - command byte
        and     RXREADY
        jr      z,$LOOP4
        in      a,(DATA)
        cp      0x00
        jr      z,BLKWRITE      ; jump to cmd 0
        dec     a
        jr      z,BLKREAD       ; jump to cmd 1
        dec     a
        jr      z,CHKSUM        ; jump to cmd 2
        dec     a
        jr      z,BLKNULL       ; jump to cmd 3
        dec     a
        jr      z,JUMP          ; jump to cmd 4
        dec     a
        jr      z,CBKWRITE      ; jump to cmd 5
        dec     a
        jr      z,IOREAD        ; jump to cmd 6
        dec     a
        jr      z,IOWRITE       ; jump to cmd 7

        ld      d,0x3F          ; unknown - return a '?'
        jr      MAIN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Command 2 - Checksum a block of memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CHKSUM:
        xor     a
$LOOP5:
        add     a,(hl)
        inc     hl
        djnz    $LOOP5
        ld      d,a             ; return checksum
        jr      MAIN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Command 1 - Read a block from memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

BLKREAD:
        in      a,(CTRL)
        and     TXREADY
        jr      z,BLKREAD
        outi
        jr      nz,BLKREAD
        ld      d,0x6B          ; return a 'k'
        jr      MAIN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Command 3 - Null out a memory block
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

BLKNULL:
        ld      (hl),0x00       
        inc     hl
        djnz    BLKNULL
        ld      d,0x6E          ; return a 'n'
        jr      MAIN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Command 4 - Jump to a location
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

JUMP:
        in      a,(CTRL)
        and     TXREADY
        jr      z,JUMP
        ld      a,0x4A          ; send a 'J'
        out     (DATA),a        
$LOOP6:
        in      a,(CTRL)        ; and wait for send complete
        and     TXREADY
        jr      z,$LOOP6
        jp      (hl)            ; then jump

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Command 5 - Write a compressed block to memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CBKWRITE:
        in      a,(CTRL)
        and     RXREADY
        jr      z,CBKWRITE
        in      a,(DATA)
        ld      b,a
        and     0x80
        jr      z,CHKZERO       ; upper bit zero?
        ld      a,b
        and     0x7F
        jr      z,CWEXIT        ; exit if it was 0x80 (end block)
        res     7,b             ; force bit 7 low
        inc     b               ; count += 1
$LOOP7:
        in      a,(CTRL)        ; read compressed data
        and     RXREADY
        jr      z,$LOOP7
        in      a,(DATA)
$LOOP8:
        ld      (hl),a
        inc     hl
        djnz    $LOOP8
        jr      CBKWRITE
;
CHKZERO:
        or      b
        jr      z,CBKWRITE
$LOOP9:
        in      a,(CTRL)        ; read uncompressed data
        and     RXREADY
        jr      z,$LOOP9
        in      a,(DATA)
        ld      (hl),a
        inc     hl
        djnz    $LOOP9
        jr      CBKWRITE
;
CWEXIT:
        nop
        ld      d,0x63          ; send a 'c'
        jp      MAIN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Command 6 - Read from a Port
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IOREAD:
        ld      c,l
        in      a,(c)
        ld      c,DATA
        ld      d,a             ; send result
        jp      MAIN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Command 7 - Write to a Port
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IOWRITE:
        ld      c,l
        ld      a,b
        out     (c),a
        ld      c,DATA
        ld      d,0x6F          ; send a 'o'
        jp      MAIN
