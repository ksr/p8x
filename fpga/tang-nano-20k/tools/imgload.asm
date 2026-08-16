; imgload.asm -- write a whole disk image to the card over the serial console.
;
; osload.asm installs just the OS (LBA 1..N, N<256). This writes an arbitrary
; run of sectors from LBA 0, so a full P8XFS image -- OS, /bin, /lib, /src, the
; lot -- can be cloned onto a card by the board itself, with no root access on
; the host and no card reader.
;
; Poke to $3000 with the monitor's E command, start with `G 3000`.
;
; Protocol, host -> board:
;   2 bytes   sector count, little-endian (12377 for the 6 MB image)
;   N*512     the image from LBA 0
; The board answers '.' after every sector; the host MUST wait for it, because
; CFWRITE takes milliseconds and the ACIA holds only one byte. Inside a sector no
; pacing is needed: the receive loop is ~4 us per byte against 87 us on the wire.
;
; Nothing is patched afterwards -- the image carries its own boot block.

CONIN   = $0100
CONOUT  = $0103
CFWRITE = $010F

LBA0    = $6047                 ; 24-bit LBA, little-endian
LBA1    = $6048
LBA2    = $6049
SBUF    = $6100

NLO     = $3300                 ; sectors remaining, 16-bit
NHI     = $3301
CNT     = $3302
OUTER   = $3303
RETRY   = $3304                 ; CFWRITE attempts left for this sector

        .org $3000

        JSR  CONIN              ; sector count, little-endian
        STA  NLO
        JSR  CONIN
        STA  NHI

        LDA  #$00               ; start at LBA 0 -- the image includes its own
        STA  LBA0               ; boot block, so nothing needs patching after
        STA  LBA1
        STA  LBA2

SECLP:  LDP1 #SBUF              ; 512 bytes = 2 passes of 256
        LDA  #$02
        STA  OUTER
OUTLP:  LDA  #$00
        STA  CNT
BYTLP:  JSR  CONIN
        STA  (P1)+
        LDA  CNT
        INC
        STA  CNT
        JNZ  BYTLP
        LDA  OUTER
        DEC
        STA  OUTER
        JNZ  OUTLP

        ; A CFWRITE failure here is usually TRANSIENT: the firmware's busy-wait
        ; is bounded, and an SD card doing internal erase/housekeeping can hold
        ; BSY for far longer than a card that is merely idle. Under sustained
        ; sequential writes that happens often enough to kill a whole transfer,
        ; so retry the sector rather than give up. Rewriting the same LBA is
        ; harmless -- the data and the address are both unchanged.
        LDA  #8
        STA  RETRY
WRTRY:  JSR  CFWRITE            ; C=1 on error
        JNC  WROK
        LDA  RETRY
        DEC
        STA  RETRY
        JNZ  WRTRY
        JMP  WRERR              ; eight attempts failed: this one is real
WROK:

        LDA  LBA0               ; 24-bit LBA increment
        INC
        STA  LBA0
        JNZ  NOCY1
        LDA  LBA1
        INC
        STA  LBA1
        JNZ  NOCY1
        LDA  LBA2
        INC
        STA  LBA2
NOCY1:

        LDA  NLO                ; 16-bit count decrement
        JNZ  DECLO
        LDA  NHI                ; low byte is 0: borrow from the high byte
        JZ   FIN
        DEC
        STA  NHI
DECLO:  LDA  NLO
        DEC
        STA  NLO
        JNZ  NEXTS
        LDA  NHI
        JNZ  NEXTS

FIN:    LDA  #$2E               ; ack the final sector, then finish
        JSR  CONOUT
        LDA  #$4B               ; 'K'
        JSR  CONOUT
        RTS

; The ack is emitted HERE -- after CFWRITE and after ALL the bookkeeping -- so it
; means "ready for the next sector NOW", which is exactly how the host treats it.
;
; It used to fire immediately after CFWRITE, leaving ~30 instructions of LBA
; increment and counter work between the ack and the receive loop. The host sends
; the next 512 bytes the moment it sees the ack, the ACIA shim holds exactly ONE
; byte, and a byte landing in that window is lost. The board then waits forever
; for a sector one byte short, and the protocol has no framing to resync with --
; so the transfer stops dead. That is what it did twice, both times around 85%
; of a 3254-sector image.
NEXTS:  LDA  #$2E               ; '.'
        JSR  CONOUT
        JMP  SECLP

; A failed write stops the transfer. Acking unconditionally was the worst
; possible failure mode: run this without CFINIT and every CFWRITE errors, every
; error is reported as success, the run "completes" with K, and the card is
; untouched -- indistinguishable from success until you notice the files are
; still the old ones.
WRERR:  LDA  #$45               ; 'E'
        JSR  CONOUT
        RTS
