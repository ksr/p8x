; test_gfx.asm -- exercises the $FF20 graphics display model.
;
; Drives every command the device implements (CLS, SETPAL, BOX, BOXFILL, LINE,
; PLOT) straight through the I/O ports, which is exactly what BASIC's LINE /
; COLOR / BOX statements will emit once they exist. Written longhand rather than
; with helper subroutines so each port write is visible: this file doubles as
; the worked example of the register protocol.
;
;   ./p8xemu -l 200000 -G test/gfx.bin          # render to the terminal
;   ./p8xemu -l 200000 -g out.ppm test/gfx.bin  # ... or to an image
;
; It is a PAYLOAD, not a self-checking test: gfx_test.sh decides pass/fail by
; comparing the rendered output against the expected drawing. When the RTL
; engine exists this same ROM becomes the co-sim payload, and the two models'
; framebuffers must match pixel for pixel.
;
; The drawing is chosen to pin down the awkward cases, not to look pretty:
;   - a full-screen box outline puts pixels on all four extreme edges
;   - two diagonals crossing exercise Bresenham with both signs of sx and sy
;   - a filled box overpaints them, proving last-writer-wins
;   - a line running off the right edge proves off-screen pixels are DISCARDED
;     rather than wrapping to the next row (the failure this catches is a
;     one-line bug in the RTL that a purely on-screen drawing would miss)
;   - SETPAL recolours a pen before it is used
;
; The geometry is the old 240x136 drawing with every coordinate DOUBLED, since
; the panel went to exactly 2x in both axes. That is deliberate: the relative
; layout was reasoned about carefully (see the hollow BOX below, which has to
; sit where nothing else can colour its interior) and doubling preserves every
; one of those properties instead of re-deriving them.
;
; The PENS are not the old 0-3. At 8 bpp a pen is a whole byte, and pens 1/2/3
; exercise only its bottom two bits -- exactly where an engine that still
; thought in 2 bpp would look correct. So the payload draws in $E0, $1C, $03
; and $FF: the 3-3-2 primaries, which are both unmistakable in a failure message
; and proof that all eight bits reach the framebuffer.
;
; Coordinates past 255 need the high byte, and it is written AFTER the low one
; because a low write CLEARS its high byte (the rule test_gfx2.asm pins down).

        .include "../../generators/memmap.inc"

        .org $0000

        LPL3 #$00                       ; P3 = SP = $3F00 (unused, but set)
        LPH3 #$3F

;=== CLS to pen 0 ==========================================================
        LDA  #0
        STA  GCOL
        LDA  #5                         ; CLS
        JSR  GWAIT
        STA  GCMD

;=== SETPAL: pen $FF := yellow (R=15 G=15 B=0) =============================
; SETPAL reuses the coordinate registers as R,G,B and recolours the pen named
; by GCOL, so the pen must be selected BEFORE the command is issued.
; $FF is white in the default 3-3-2 ramp, so recolouring it to yellow is a
; visible change rather than one that could pass by accident.
        LDA  #$FF
        STA  GCOL
        LDA  #15
        STA  GX0                        ; red
        LDA  #15
        STA  GY0                        ; green
        LDA  #0
        STA  GX1                        ; blue
        LDA  #6                         ; SETPAL
        JSR  GWAIT
        STA  GCMD

;=== border: BOX (0,0)-(479,271) in pen $E0 (red) ==========================
; The whole point of this one is the four EXTREME edges, so it has to reach the
; real corners: 479 = $01DF and 271 = $010F both need their high byte.
        LDA  #$E0
        STA  GCOL
        LDA  #0
        STA  GX0
        LDA  #0
        STA  GY0
        LDA  #$DF
        STA  GX1
        LDA  #1
        STA  GX1H                       ; ... = 479
        LDA  #$0F
        STA  GY1
        LDA  #1
        STA  GY1H                       ; ... = 271
        LDA  #3                         ; BOX (outline)
        JSR  GWAIT
        STA  GCMD

;=== diagonal 1: LINE (0,0)-(479,271) in pen $1C (green) ===================
        LDA  #$1C
        STA  GCOL
        LDA  #0
        STA  GX0                        ; clears GX0H
        LDA  #0
        STA  GY0                        ; clears GY0H
        LDA  #$DF
        STA  GX1
        LDA  #1
        STA  GX1H                       ; ... = 479
        LDA  #$0F
        STA  GY1
        LDA  #1
        STA  GY1H                       ; ... = 271
        LDA  #2                         ; LINE
        JSR  GWAIT
        STA  GCMD

;=== diagonal 2: LINE (479,0)-(0,271) -- the other sign of sx ==============
        LDA  #$DF
        STA  GX0
        LDA  #1
        STA  GX0H                       ; ... = 479
        LDA  #0
        STA  GY0
        LDA  #0
        STA  GX1                        ; clears GX1H, so this really is 0
        LDA  #$0F
        STA  GY1
        LDA  #1
        STA  GY1H                       ; ... = 271
        LDA  #2                         ; LINE
        JSR  GWAIT
        STA  GCMD

;=== BOXFILL (180,100)-(300,172) in pen $FF (the yellow set above) =========
; Drawn AFTER the diagonals and covering the screen centre, so its interior
; also proves last-writer-wins over them.
        LDA  #$FF
        STA  GCOL
        LDA  #180
        STA  GX0
        LDA  #100
        STA  GY0
        LDA  #$2C
        STA  GX1
        LDA  #1
        STA  GX1H                       ; ... = 300
        LDA  #172
        STA  GY1
        LDA  #4                         ; BOXFILL
        JSR  GWAIT
        STA  GCMD

;=== BOX (160,200)-(280,248) in pen $1C -- an OUTLINE, so it must stay hollow
; Placed in the wedge between the two diagonals (at y=200..248 they sit at
; x~353..438 and x~126..41), so nothing else can colour its interior. Without
; this the only BOX on screen is the full-screen border, whose interior is
; covered by other drawing -- so BOX silently filling would go unnoticed.
; GCOL is sticky across commands and BOXFILL left it at $FF, so re-select.
        LDA  #$1C
        STA  GCOL
        LDA  #160
        STA  GX0
        LDA  #200
        STA  GY0
        LDA  #$18
        STA  GX1
        LDA  #1
        STA  GX1H                       ; ... = 280
        LDA  #248
        STA  GY1
        LDA  #3                         ; BOX (outline)
        JSR  GWAIT
        STA  GCMD

;=== clipping: LINE (400,240)-(510,240), x>479 must be DROPPED =============
; 510 is reachable because a coordinate register is a 16-bit pair and holds far
; more than the screen is wide. Pixels 480..510 are discarded one at a time;
; nothing wraps onto row 241.
        LDA  #$03
        STA  GCOL
        LDA  #$90
        STA  GX0
        LDA  #1
        STA  GX0H                       ; ... = 400
        LDA  #240
        STA  GY0
        LDA  #$FE
        STA  GX1
        LDA  #1
        STA  GX1H                       ; ... = 510, past the right edge
        LDA  #240
        STA  GY1
        LDA  #2                         ; LINE
        JSR  GWAIT
        STA  GCMD

;=== PLOT a single pixel at (20,20) in pen $03 =============================
        LDA  #$03
        STA  GCOL
        LDA  #20
        STA  GX0                        ; clears GX0H
        LDA  #20
        STA  GY0
        LDA  #1                         ; PLOT
        JSR  GWAIT
        STA  GCMD

        HLT                             ; stop; the emulator dumps on exit

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
