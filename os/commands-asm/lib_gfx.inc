; lib_gfx.inc — the display device's address book for hand-asm /BIN commands.
; A twin declares `;#use gfx` and mkasm.sh appends this file; on-target the
; assembler splices /lib/gfx.inc. Pure equates (no bytes), the asm twin of
; os/commands/lib_gfx.c's //#defines — one home per address on each side.
;
; The register rules (fpga/rtl/gfx.v): coordinates are 16-bit pairs, LOW
; write clears the high byte, highs sit 9 above their lows; the pen is
; GCOL low / GCOLH high with the same rule; wait for GSTAT bit 7 (busy)
; clear before writing GCMD — a command issued mid-draw ABORTS the running
; one. Coordinates are UNSIGNED at the device (no sign extension). Probe
; GID0/GID1 for "PG" before anything else: an absent display floats to $FF.

GX0    = $FF20   ; x0 low  (high at GX0H)
GY0    = $FF21   ; y0 low
GX1    = $FF22   ; x1 low
GY1    = $FF23   ; y1 low
GCOL   = $FF24   ; pen low byte — write CLEARS the high byte
GCMD   = $FF25   ; command strobe (GC_* below)
GSTAT  = $FF26   ; bit7 = busy, bit0 = error (unknown command)
GDATA  = $FF27   ; POINT result stream: low byte then high (and IDENT)
GPARM  = $FF28   ; circle radius / ellipse x-radius
GX0H   = $FF29   ; x0 high
GY0H   = $FF2A   ; y0 high
GX1H   = $FF2B   ; x1 high
GY1H   = $FF2C   ; y1 high
GCOLH  = $FF2D   ; pen high byte (write side of GID0)
GID0   = $FF2D   ; reads 'P' ($50) when a display is fitted
GID1   = $FF2E   ; reads 'G' ($47)
GPARM2 = $FF2F   ; ellipse y-radius

GC_PIXW = 1      ; plot (GX0,GY0) in the pen colour
GC_LINE = 2      ; line (GX0,GY0)-(GX1,GY1), both endpoints drawn
;GC_BOX = 3      ; RETIRED (stage-10 diet): draw four GC_LINEs
GC_BOXF = 4      ; ... filled
;GC_CLS = 5      ; RETIRED: BOXFILL 0,0-479,271 is the same pixels
;GC_CIRC= 7      ; RETIRED: the ellipse with rx=ry is the circle now
;GC_CIRCF=8      ;   (GC_ELL/GC_ELLF with GPARM2 = GPARM)
GC_PIXR = 9      ; read the colour at (GX0,GY0) -> GDATA low, high
GC_ELL  = $0A    ; ellipse outline, radii GPARM (x) / GPARM2 (y)
GC_ELLF = $0B    ; ... filled
GC_TEST = $F0    ; device self-test pattern
GC_RST  = $F1    ; reset: clear to black, pen white
GC_IDENT= $F2    ; IDENT: GDATA then streams the 14-byte geometry record
