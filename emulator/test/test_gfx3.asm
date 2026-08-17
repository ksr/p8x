; test_gfx3.asm -- ELLIPSE / ELLIPSEFILL against the golden model.
;
; The ellipse is the one primitive whose two implementations could plausibly
; disagree by a pixel: it has two regions, a decision variable scaled by 4 to
; keep the classic rx^2/4 term exact, and an initialiser at the region boundary
; that reaches ~35 bits. A rounding or width difference shows up here and
; nowhere else.
;
; Radii chosen so both regions do real work in both shapes: wide (rx>ry) puts
; most of the curve in region 1, tall (ry>rx) in region 2.

        .include "../../generators/memmap.inc"

        .org $0000
        LPL3 #$00
        LPH3 #$3F

        LDA  #0                         ; CLS to background
        STA  GCOL
        LDA  #5
        JSR  GWAIT
        STA  GCMD

        LDA  #1                         ; wide outline ellipse
        STA  GCOL
        LDA  #100
        STA  GX0
        LDA  #50
        STA  GY0
        LDA  #80
        STA  GPARM
        LDA  #30
        STA  GPARM2
        LDA  #$0A
        JSR  GWAIT
        STA  GCMD

        LDA  #2                         ; tall FILLED ellipse
        STA  GCOL
        LDA  #180
        STA  GX0
        LDA  #95
        STA  GY0
        LDA  #25
        STA  GPARM
        LDA  #38
        STA  GPARM2
        LDA  #$0B
        JSR  GWAIT
        STA  GCMD

        LDA  #3                         ; a near-circle, to catch region skew
        STA  GCOL
        LDA  #40
        STA  GX0
        LDA  #100
        STA  GY0
        LDA  #20
        STA  GPARM
        LDA  #19
        STA  GPARM2
        LDA  #$0A
        JSR  GWAIT
        STA  GCMD

        HLT

;=== waiting for the engine ================================================
; MUST preserve A: it is called between loading the command byte and storing it.
GWSAV   = $3020
GWAIT:  STA  GWSAV
gw_lp:  LDA  GSTAT
        LDB  #$80
        AND
        JNZ  gw_lp
        LDA  GWSAV
        RTS
