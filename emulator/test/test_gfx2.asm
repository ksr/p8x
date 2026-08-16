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

; CIRCLE centred at (120,68) radius 40, pen 2 -- an OUTLINE, so its centre
; must stay background.
        LDA  #2
        STA  GCOL
        LDA  #120
        STA  GX0
        LDA  #68
        STA  GY0
        LDA  #40
        STA  GPARM                      ; radius
        LDA  #$07                       ; CIRCLE
        JSR  GWAIT
        STA  GCMD

;=== 16-bit coordinates, case 1: x = 356 is OFF-SCREEN =====================
; Write the low byte first, THEN the high byte: 100 + (1<<8) = 356. Nothing may
; appear at (100,60) -- if the high byte were ignored, that is exactly where the
; pixel would land, so this fails loudly rather than silently.
        LDA  #100
        STA  GX0
        LDA  #1
        STA  GX0H
        LDA  #60
        STA  GY0
        LDA  #$01                       ; PLOT
        JSR  GWAIT
        STA  GCMD

;=== 16-bit coordinates, case 2: a LOW write CLEARS the high byte ==========
; GX0H is still 1 from above. Writing GX0 must zero it, putting this pixel at
; x=100 and not x=356. This is the rule that keeps 8-bit software safe from a
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
GWAIT:  LDA  GSTAT
        LDB  #$80
        AND
        JNZ  GWAIT
        RTS
