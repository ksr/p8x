; test_gfx2.asm -- the graphics card's identify / diagnostic / geometry commands.
;
; test_gfx.asm covers the drawing primitives. This one covers everything a
; *card* needs that an on-die device does not: proving it is there, saying what
; it is, and drawing something without any software behind it.
;
;   IDENT   -> a 14-byte record streamed back through GDATA, carrying the
;              geometry so software can ask instead of assume
;   GID0/1  -> two fixed bytes, "PG". A single magic byte would be useless:
;              an absent card floats the bus to $FF, and $FF is a legal value
;              for most things. Two fixed bytes at two addresses are not.
;   CIRCLE  -> the midpoint-circle primitive
;   the 16-bit coordinate rule -- writing a LOW byte clears its HIGH byte
;
; The IDENT record and signature are echoed to the ACIA so the test can assert
; on them from stdout; the drawing is checked in the rendered image.

        .include "../../generators/memmap.inc"

CNT     = $3000                         ; loop counter (RAM scratch)

        .org $0000

        LPL3 #$00                       ; P3 = SP = $3F00
        LPH3 #$3F

;=== IDENT: issue, then stream 14 bytes out of GDATA to the console ========
        LDA  #$F2                       ; IDENT
        JSR  GWAIT
        STA  GCMD
        LDA  #14
        STA  CNT
id_lp:  LDA  GDATA
        STA  ACIAD                      ; echo the record byte
        LDA  CNT
        LDB  #1
        SUB
        STA  CNT
        LDA  CNT                        ; reload so Z reflects the counter
        JNZ  id_lp

;=== presence signature: GID0 GID1 -> "PG" =================================
        LDA  GID0
        STA  ACIAD
        LDA  GID1
        STA  ACIAD

;=== RESET, then draw with the extended commands ===========================
        LDA  #$F1                       ; RESET (clears screen, default palette)
        JSR  GWAIT
        STA  GCMD

; CIRCLE centred at (240,136) radius 80, pen $E0 -- an OUTLINE, so its centre
; must stay background. Centred on the screen, so the four axis points sit at
; (160,136) (320,136) (240,56) (240,216).
        LDA  #$E0
        STA  GCOL
        LDA  #240
        STA  GX0                        ; clears GX0H
        LDA  #136
        STA  GY0
        LDA  #80
        STA  GPARM                      ; radius
        LDA  #$07                       ; CIRCLE
        JSR  GWAIT
        STA  GCMD

;=== 16-bit coordinates, case 1: x = 612 is OFF-SCREEN =====================
; Write the low byte first, THEN the high byte: 100 + (2<<8) = 612, which is
; past the 480-wide screen. Nothing may appear at (100,60) -- if the high byte
; were ignored, that is exactly where the pixel would land, so this fails
; loudly rather than silently. (A high byte of 1 would give 356, which USED to
; be off-screen at 240 wide and is now well inside it: the case had quietly
; stopped testing anything.)
        LDA  #100
        STA  GX0
        LDA  #2
        STA  GX0H
        LDA  #60
        STA  GY0
        LDA  #$01                       ; PLOT
        JSR  GWAIT
        STA  GCMD

;=== 16-bit coordinates, case 2: a LOW write CLEARS the high byte ==========
; GX0H is still 2 from above. Writing GX0 must zero it, putting this pixel at
; x=100 and not x=612. This is the rule that keeps 8-bit software safe from a
; stale high byte someone else left behind.
        LDA  #100
        STA  GX0                        ; ... clears GX0H
        LDA  #70
        STA  GY0
        LDA  #$01                       ; PLOT
        JSR  GWAIT
        STA  GCMD

        HLT

;=== waiting for the engine ================================================
; The DEVICE draws in real time -- a full-screen fill is tens of thousands of
; pixels -- and a command issued while another is running ABORTS it. The
; emulator draws instantaneously and always reports not-busy, so this costs
; nothing there; on the RTL it is the difference between a picture and a few
; scattered pixels. GWAIT is called before every command so ONE payload is
; correct on both, which is what makes the framebuffer diff meaningful.
;
; It MUST preserve A. It is called between loading the command byte and storing
; it to GCMD, so a GWAIT that clobbers A stores the status register instead --
; which is 0, a NOP. Every command in this file silently became a no-op and the
; whole payload drew nothing.
GWSAV   = $3020
GWAIT:  STA  GWSAV
gw_lp:  LDA  GSTAT
        LDB  #$80
        AND
        JNZ  gw_lp
        LDA  GWSAV
        RTS
