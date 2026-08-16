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
;   - a filled box covers the read-modify-write path on partial bytes
;   - a line running off the right edge proves off-screen pixels are DISCARDED
;     rather than wrapping to the next row (the failure this catches is a
;     one-line bug in the RTL that a purely on-screen drawing would miss)
;   - SETPAL recolours pen 3 before it is used

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

;=== SETPAL: pen 3 := yellow (R=15 G=15 B=0) ===============================
; SETPAL reuses the coordinate registers as R,G,B and recolours the pen named
; by GCOL, so the pen must be selected BEFORE the command is issued.
        LDA  #3
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

;=== border: BOX (0,0)-(239,135) in pen 1 ==================================
        LDA  #1
        STA  GCOL
        LDA  #0
        STA  GX0
        LDA  #0
        STA  GY0
        LDA  #239
        STA  GX1
        LDA  #135
        STA  GY1
        LDA  #3                         ; BOX (outline)
        JSR  GWAIT
        STA  GCMD

;=== diagonal 1: LINE (0,0)-(239,135) in pen 2 =============================
        LDA  #2
        STA  GCOL
        LDA  #0
        STA  GX0
        LDA  #0
        STA  GY0
        LDA  #239
        STA  GX1
        LDA  #135
        STA  GY1
        LDA  #2                         ; LINE
        JSR  GWAIT
        STA  GCMD

;=== diagonal 2: LINE (239,0)-(0,135) -- the other sign of sx ==============
        LDA  #239
        STA  GX0
        LDA  #0
        STA  GY0
        LDA  #0
        STA  GX1
        LDA  #135
        STA  GY1
        LDA  #2                         ; LINE
        JSR  GWAIT
        STA  GCMD

;=== BOXFILL (90,50)-(150,86) in pen 3 (the yellow set above) ==============
        LDA  #3
        STA  GCOL
        LDA  #90
        STA  GX0
        LDA  #50
        STA  GY0
        LDA  #150
        STA  GX1
        LDA  #86
        STA  GY1
        LDA  #4                         ; BOXFILL
        JSR  GWAIT
        STA  GCMD

;=== BOX (80,100)-(140,124) in pen 2 -- an OUTLINE, so it must stay hollow ==
; Placed in the wedge between the two diagonals (at y=100..124 they sit at
; x~177..219 and x~62..21), so nothing else can colour its interior. Without
; this the only BOX on screen is the full-screen border, whose interior is
; covered by other drawing -- so BOX silently filling would go unnoticed.
; GCOL is sticky across commands and BOXFILL left it at 3, so re-select pen 2.
        LDA  #2
        STA  GCOL
        LDA  #80
        STA  GX0
        LDA  #100
        STA  GY0
        LDA  #140
        STA  GX1
        LDA  #124
        STA  GY1
        LDA  #3                         ; BOX (outline)
        JSR  GWAIT
        STA  GCMD

;=== clipping: LINE (200,120)-(255,120), x>239 must be DROPPED =============
; 255 is reachable because a coordinate register holds far more than the screen
; is wide (they are 16-bit pairs). Pixels 240..255
; are discarded one at a time; nothing wraps onto row 121.
        LDA  #1
        STA  GCOL
        LDA  #200
        STA  GX0
        LDA  #120
        STA  GY0
        LDA  #255
        STA  GX1
        LDA  #120
        STA  GY1
        LDA  #2                         ; LINE
        JSR  GWAIT
        STA  GCMD

;=== PLOT a single pixel at (10,10) in pen 2 ===============================
        LDA  #2
        STA  GCOL
        LDA  #10
        STA  GX0
        LDA  #10
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
GWAIT:  LDA  GSTAT
        LDB  #$80
        AND
        JNZ  GWAIT
        RTS
