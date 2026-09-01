; lib_gfx.inc -- the GRAPHICS LANGUAGE port's address book for hand-asm
; /BIN commands. A twin declares `;#use gfx` and mkasm.sh appends this
; file; on-target the assembler splices /lib/gfx.inc. Pure equates, the
; asm twin of os/commands/lib_gfx.c's //#defines -- one home per address
; on each side. SINGLE-INTERFACE since 2026-09-01: the old $FF20 device
; register equates are gone with the device door; everything draws by
; streaming GL bytes at GLDATA (wait GLSTAT bit7 clear per byte) and
; reads answers from the RB FIFO (GLSTAT bit0, then GLRB, low byte
; first). Probe GLID for 'G' before anything else. man gl is the verb
; card; the coordinates are WINDOW space (y UP) -- a screen-space
; caller flips with 271-y under the identity window it establishes.

GLDATA = $FF50   ; write: push one GL command byte into the FIFO
GLSTAT = $FF51   ; bit7 FIFO full, bit6 walker busy, bit1 err, bit0 RB
GLRB   = $FF52   ; read: pop one read-back byte (PIXRD's reply)
GLERR  = $FF53   ; read: pop one error byte (0 = none)
GLID   = $FF54   ; reads 'G' ($47) when the GL engine is fitted
