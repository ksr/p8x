; osload.asm -- install a P8X/OS image onto the card, over the serial console.
;
; Writing a raw disk image from a host needs root (dd to /dev/rdiskN), which is
; not always available. The board does not need it: its own CFWRITE works, so it
; can install its own OS. This is poked into RAM through the monitor's E command
; and started with `G 3000`.
;
; Protocol, host -> board, no handshaking beyond the per-sector ack:
;   1 byte   N, the number of 512-byte sectors to write (the image's OSCNT)
;   N*512    the OS image, written to LBA 1..N
; The board answers '.' after each sector and 'K' when it has patched OSCNT into
; the boot block. At 115200 the wire is far slower than the card, so no flow
; control is needed -- each byte is consumed as it arrives.
;
; Leaves the boot block's other fields alone: only OSCNT (byte 3) is touched, so
; a card formatted by the monitor's F stays valid.

CONIN   = $0100                 ; wait for a key -> A
CONOUT  = $0103                 ; A -> serial
CFREAD  = $010C                 ; sector LBA -> (P1); P1 += 512
CFWRITE = $010F                 ; SBUF -> sector LBA

LBA0    = $6047                 ; 24-bit LBA, little-endian
LBA1    = $6048
LBA2    = $6049
SBUF    = $6100                 ; 512-byte sector buffer

NSEC    = $3300                 ; sectors left to write
NTOT    = $3301                 ; total, for the OSCNT patch
CNT     = $3302                 ; inner byte counter
OUTER   = $3303                 ; 2 x 256 = 512

        .org $3000

        JSR  CONIN              ; N
        STA  NSEC
        STA  NTOT

        LDA  #$01               ; first OS sector is LBA 1
        STA  LBA0
        LDA  #$00
        STA  LBA1
        STA  LBA2

SECLP:  LDP1 #SBUF              ; fill the sector buffer with 512 bytes
        LDA  #$02
        STA  OUTER
OUTLP:  LDA  #$00
        STA  CNT
BYTLP:  JSR  CONIN
        STA  (P1)+
        LDA  CNT
        INC
        STA  CNT
        JNZ  BYTLP              ; 256 bytes per pass
        LDA  OUTER
        DEC
        STA  OUTER
        JNZ  OUTLP

        JSR  CFWRITE            ; SBUF -> LBA
        LDA  #$2E               ; '.' ack
        JSR  CONOUT

        LDA  LBA0               ; next sector
        INC
        STA  LBA0
        LDA  NSEC
        DEC
        STA  NSEC
        JNZ  SECLP

        LDA  #$00               ; patch OSCNT into the boot block at LBA 0
        STA  LBA0
        STA  LBA1
        STA  LBA2
        LDP1 #SBUF
        JSR  CFREAD             ; boot block -> SBUF (advances P1, not LBA)
        LDA  NTOT
        STA  SBUF+3             ; OSCNT
        LDA  #$00
        STA  LBA0
        JSR  CFWRITE

        LDA  #$4B               ; 'K' -- done
        JSR  CONOUT
        RTS                     ; back to the monitor prompt
