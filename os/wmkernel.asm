; wmkernel.asm -- the resident P8X window-manager kernel (skeleton, v1).
;
; Assembled at WMBASE ($D800) and loaded there ONCE by the launcher
; (`desk`); resident thereafter, surviving apps that come and go in the
; TPA below it (proven by wm_reside_test). The jump table at the base is
; bios()-callable at fixed addresses, exactly like the BIOS table at
; $0100 or the OS syscalls at $2000:
;
;   WMBASE+0  wk_init          clear the window list
;   WMBASE+3  wk_open   P1 ->  a 22-byte record [x,y,w,h (LE pairs),
;                              list, tlen, title(12)]; copied resident
;   WMBASE+6  wk_repaint       FLOOD the desktop + draw every window's
;                              chrome, title and CONTENT from the records
;   WMBASE+9  wk_run           the resident event loop (keyboard; mouse next)
;   WMBASE+12 .byte 'W','M'    presence signature (the launcher checks it
;                              to skip reloading a resident kernel)
;
; Draws chrome + stroke-font title + CONTENT: each window's content is a
; card-resident command list (its `list` field), replayed with CLRUN into
; the content rect -- so the picture lives on the CARD and redraws even
; when the program that recorded it is gone. wk_repaint must NOT RESETF
; (RESETF clears the card lists); it sets the text camera directly.
; All coordinates are window space, y UP (the GL default).

GLDATA = $FF50
GLSTAT = $FF51

        .org $D800                       ; WMBASE (match --base)

; ---- jump table: MUST be first so the entries land at WMBASE+0/3/6/9 --------
        JMP  wk_init                    ; +0
        JMP  wk_open                    ; +3
        JMP  wk_repaint                 ; +6
        JMP  wk_run                     ; +9  the resident event loop
ksig:   .byte $57, $4D                  ; +12 'W','M'

; ==== helpers ================================================================
; kput: send one GL byte (A), honouring FIFO backpressure.
kput:   STA  kt2
kp_w:   LDA  GLSTAT
        LDB  #$80
        AND
        JNZ  kp_w
        LDA  kt2
        STA  GLDATA
        RTS

; ksw: send the 16-bit value in kw, little-endian.
ksw:    LDA  kw
        JSR  kput
        LDA  kw+1
        JSR  kput
        RTS

; k16add: kw = ka + kb (16-bit, unsigned).
k16add: LDA  ka
        LDB  kb
        ADD
        STA  kw
        LDA  #0
        JNC  k16a_h
        LDA  #1
k16a_h: STA  kt
        LDA  ka+1
        LDB  kb+1
        ADD
        LDB  kt
        ADD
        STA  kw+1
        RTS

; k16sub: kw = ka - kb (16-bit). SUB sets C=1 when there was NO borrow.
k16sub: LDA  ka
        LDB  kb
        SUB
        STA  kw
        LDA  #0
        JC   k16s_h
        LDA  #1
k16s_h: STA  kt
        LDA  ka+1
        LDB  kb+1
        SUB
        LDB  kt
        SUB
        STA  kw+1
        RTS

; kseta/ksetb: ka/kb := the 16-bit value at the address in P0-relative
; source is inconvenient; instead the callers load ka/kb directly. Small
; movers keep the draw code readable:
;   ka := kx    (etc.)  are open-coded where needed.

; kp1: P1 = recs + (A)  where A = a byte offset (<= 96, no page cross issue
; handled via carry). Preserves nothing but P1.
kp1:    STA  kt
        LDA  #<recs
        LDB  kt
        ADD
        TAP1L
        LDA  #>recs
        JNC  kp1_r
        LDB  #1
        ADD
kp1_r:  TAP1H
        RTS

; koff: A = 24 * ki  (record stride; ki is 0..3, so the product is < 256).
koff:   LDA  ki
        SHL
        SHL
        SHL                             ; 8*ki
        STA  kt3
        SHL                             ; 16*ki
        LDB  kt3
        ADD                             ; 24*ki
        RTS

; ==== wk_init ================================================================
wk_init:LDA  #0
        STA  wcnt
        RTS

; ==== wk_open : copy the 22-byte record at (P1) into slot wcnt ===============
wk_open:LDA  wcnt
        LDB  #4                         ; MAXWIN
        CMP
        JC   wko_ret                    ; wcnt >= 4 -> drop (C=1 means A>=B)
        ; P2 = recs + 24*wcnt  (dest); P1 already = the param block (src)
        LDA  wcnt
        SHL
        SHL
        SHL
        STA  kt3                        ; 8*wcnt
        SHL                             ; 16*wcnt
        LDB  kt3
        ADD                             ; 24*wcnt
        LDB  #<recs
        ADD
        TAP2L
        LDA  #>recs
        JNC  wko_h
        LDB  #1
        ADD
wko_h:  TAP2H
        LDA  #22                        ; copy the fixed record head+title
        STA  kt
wko_cp: LDA  (P1)+
        STA  (P2)+
        LDA  kt
        DEC
        STA  kt
        JNZ  wko_cp
        LDA  wcnt
        INC
        STA  wcnt
wko_ret:RTS

; ==== wk_repaint : desktop + every window, from the resident records ========
wk_repaint:
        ; NOTE: no RESETF here -- RESETF clears the card command lists
        ; (cldef[]), which would wipe every window's recorded content. The
        ; text camera is set directly instead.
        LDA  #$B0                       ; PROJCT 0 -> orthographic, so z=0
        JSR  kput                       ;   TEXT strokes are NOT near-clipped
        LDA  #0
        JSR  kput
        JSR  kput
        LDA  #$90                       ; MDIDEN: identity model matrix
        JSR  kput
        LDA  #$81                       ; TSIZE 256 (1x)
        JSR  kput
        LDA  #0
        JSR  kput
        LDA  #1
        JSR  kput
        JSR  k_ident                    ; identity window/viewport (full screen)
        LDA  #$07                       ; FLOOD the desktop grey
        JSR  kput
        LDA  #6
        JSR  kput
        LDA  #12
        JSR  kput
        LDA  #9
        JSR  kput
        LDA  #0
        STA  ki
wkr_lp: LDA  ki
        LDB  wcnt
        CMP
        JC   wkr_done                   ; ki >= wcnt -> done (C=1 means A>=B)
        JSR  wk_draw
        LDA  ki
        INC
        STA  ki
        JMP  wkr_lp
wkr_done:
        JSR  k_ident
        RTS

; ==== wk_run : the resident event loop (keyboard first) =====================
; Draws once, then reads the console. Arrow keys move the TOP window (the
; last opened, drawn on top); ^D returns to the caller. Mouse (xterm SGR)
; parsing + focus/drag/close/menu are the next slice. The loop is resident,
; so the app that called SYS_WMRUN is still in the TPA -- but a launched
; program will replace it while the loop persists (the launch-and-resume
; rung).
wk_run: LDA  #99                       ; no window grabbed yet
        STA  kdragw
        JSR  wk_repaint
wru_lp: JSR  $0100                      ; CONIN -> A (blocks for a key)
        LDB  #4                         ; ^D -> quit
        CMP
        JZ   wru_ret
        LDB  #$6C                       ; 'l' -> LAUNCH a WM-client program
        CMP
        JZ   wru_launch
        LDB  #27                        ; ESC -> an arrow sequence
        CMP
        JZ   wru_esc
        JMP  wru_lp

; LAUNCH: SYS_EXEC a WM client into the TPA below us. SYS_EXEC replaces the
; TPA (this loop's original caller included) and never returns here -- but
; the kernel and its window records are RESIDENT at WMBASE, above the TPA,
; so they survive untouched. The launched program resumes the desktop by
; calling wk_run again (it is a WM client): a fresh event loop, redrawing
; the SAME resident records. That is launch-and-resume -- the windows
; persist across the launch for free, because nothing reloaded the WM.
wru_launch:
        LDA  #<kpath
        TAP1L
        LDA  #>kpath
        TAP1H
        JSR  $2024                      ; SYS_EXEC (does not return)
        JMP  wru_lp                      ; only reached if the exec failed
kpath:  .ascii "/bin/wapp.bin"
        .byte 0
wru_esc:JSR  $0100                      ; expect '['
        LDB  #$5B
        CMP
        JNZ  wru_lp
        JSR  $0100                      ; '<' (xterm SGR mouse) or A/B/C/D
        LDB  #$3C                       ; '<'
        CMP
        JZ   wru_mouse
        LDB  #$41                       ; 'A' up    -> y += 8
        CMP
        JZ   wru_up
        LDB  #$42                       ; 'B' down  -> y -= 8
        CMP
        JZ   wru_dn
        LDB  #$43                       ; 'C' right -> x += 8
        CMP
        JZ   wru_rt
        LDB  #$44                       ; 'D' left  -> x -= 8
        CMP
        JZ   wru_lf
        JMP  wru_lp
wru_up: LDA  #8
        STA  kdxy
        LDA  #0
        STA  kdxy+1
        LDA  #2                         ; field = y
        JMP  wru_mv
wru_dn: LDA  #$F8                       ; -8, two's complement
        STA  kdxy
        LDA  #$FF
        STA  kdxy+1
        LDA  #2
        JMP  wru_mv
wru_rt: LDA  #8
        STA  kdxy
        LDA  #0
        STA  kdxy+1
        LDA  #0                         ; field = x
        JMP  wru_mv
wru_lf: LDA  #$F8
        STA  kdxy
        LDA  #$FF
        STA  kdxy+1
        LDA  #0
wru_mv: JSR  k_movetop
        JSR  wk_repaint
        JMP  wru_lp
wru_ret:RTS

; ---- xterm SGR mouse: ESC [ < b ; x ; y (M press/drag | m release) --------
; b;x;y are decimal; x,y are 1-based terminal CELLS mapped to the panel via
; the MDU (80x24 assumed: px = (x-1)*6, py = 271-(y-1)*11). This slice moves
; the TOP window's bottom-left to the cursor on any M event -- a crude drag
; that proves the parse + map + MDU path; grab-relative drag + hit test come
; next.
wru_mouse:
        JSR  k_rdnum                    ; b (button) -> knum ; term ';'
        LDA  knum
        STA  mbtn                       ; keep the button byte (bit5 = drag)
        JSR  k_rdnum                    ; x -> knum ; term ';'
        JSR  k_dec1n                    ; ka = knum - 1
        LDA  #6
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k_mul                      ; kw = (x-1)*6
        LDA  kw
        STA  kmx
        LDA  kw+1
        STA  kmx+1
        JSR  k_rdnum                    ; y -> knum ; term M/m
        JSR  k_dec1n                    ; ka = knum - 1
        LDA  #11
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k_mul                      ; kw = (y-1)*11
        LDA  #15                        ; kmy = 271 - kw   (271 = $010F)
        STA  ka
        LDA  #1
        STA  ka+1
        LDA  kw
        STA  kb
        LDA  kw+1
        STA  kb+1
        JSR  k16sub
        LDA  kw
        STA  kmy
        LDA  kw+1
        STA  kmy+1
        ; ---- dispatch: release (m), or press/drag (M) -----------------------
        LDA  kterm
        LDB  #$6D                       ; 'm' -> release: end any drag
        CMP
        JZ   wru_mrel
        LDA  mbtn                       ; 'M' with bit5 set -> a drag motion
        LDB  #$20
        AND
        JZ   wru_mpress
        ; drag: move the grabbed window so the grab point stays under the
        ; cursor: origin = cursor - grab-offset
        LDA  kdragw
        LDB  #4
        CMP
        JC   wru_lp                     ; no window grabbed
        JSR  k_dragmove
        JSR  wk_repaint
        JMP  wru_lp
wru_mpress:
        JSR  k_intop                    ; is the cursor in the TOP window?
        JZ   wru_mnohit
        ; grab it: kdragw = top index, grab-offset = cursor - origin
        LDA  wcnt
        LDB  #1
        SUB
        STA  kdragw
        LDA  kmx                        ; kgx = kmx - kx  (kx/ky loaded by k_intop)
        STA  ka
        LDA  kmx+1
        STA  ka+1
        LDA  kx
        STA  kb
        LDA  kx+1
        STA  kb+1
        JSR  k16sub
        LDA  kw
        STA  kgx
        LDA  kw+1
        STA  kgx+1
        LDA  kmy                        ; kgy = kmy - ky
        STA  ka
        LDA  kmy+1
        STA  ka+1
        LDA  ky
        STA  kb
        LDA  ky+1
        STA  kb+1
        JSR  k16sub
        LDA  kw
        STA  kgy
        LDA  kw+1
        STA  kgy+1
        JMP  wru_lp
wru_mnohit:
        LDA  #99                        ; press missed: no drag target
        STA  kdragw
        JMP  wru_lp
wru_mrel:
        LDA  #99
        STA  kdragw
        JMP  wru_lp

; k_ge: A = 1 if ka >= kb (unsigned 16-bit), else 0.
k_ge:   LDA  ka+1
        LDB  kb+1
        CMP
        JZ   kge_lo
        LDA  #0
        JNC  kge_r
        LDA  #1
        JMP  kge_r
kge_lo: LDA  ka
        LDB  kb
        CMP
        LDA  #0
        JNC  kge_r
        LDA  #1
kge_r:  RTS

; k_intop: A = 1 (Z=0) if (kmx,kmy) is inside the TOP window, else 0. Loads
; the top window's rect into kx,ky,kcw,kch as a side effect.
k_intop:LDA  wcnt
        JZ   kit_no
        LDB  #1
        SUB
        STA  ki
        JSR  koff
        JSR  kp1
        LDA  (P1)+
        STA  kx
        LDA  (P1)+
        STA  kx+1
        LDA  (P1)+
        STA  ky
        LDA  (P1)+
        STA  ky+1
        LDA  (P1)+
        STA  kcw
        LDA  (P1)+
        STA  kcw+1
        LDA  (P1)+
        STA  kch
        LDA  (P1)+
        STA  kch+1
        ; kmx >= kx ?
        LDA  kmx
        STA  ka
        LDA  kmx+1
        STA  ka+1
        LDA  kx
        STA  kb
        LDA  kx+1
        STA  kb+1
        JSR  k_ge
        JZ   kit_no
        ; kmx < kx+kcw ?  (reject if kmx >= kx+kcw)
        LDA  kx
        STA  ka
        LDA  kx+1
        STA  ka+1
        LDA  kcw
        STA  kb
        LDA  kcw+1
        STA  kb+1
        JSR  k16add                     ; kw = kx+kcw
        LDA  kmx
        STA  ka
        LDA  kmx+1
        STA  ka+1
        LDA  kw
        STA  kb
        LDA  kw+1
        STA  kb+1
        JSR  k_ge
        JNZ  kit_no                     ; kmx >= kx+kcw -> outside
        ; kmy >= ky ?
        LDA  kmy
        STA  ka
        LDA  kmy+1
        STA  ka+1
        LDA  ky
        STA  kb
        LDA  ky+1
        STA  kb+1
        JSR  k_ge
        JZ   kit_no
        ; kmy < ky+kch ?
        LDA  ky
        STA  ka
        LDA  ky+1
        STA  ka+1
        LDA  kch
        STA  kb
        LDA  kch+1
        STA  kb+1
        JSR  k16add
        LDA  kmy
        STA  ka
        LDA  kmy+1
        STA  ka+1
        LDA  kw
        STA  kb
        LDA  kw+1
        STA  kb+1
        JSR  k_ge
        JNZ  kit_no                     ; kmy >= ky+kch -> outside
        LDA  #1                         ; inside
        RTS
kit_no: LDA  #0
        RTS

; k_dragmove: the grabbed window's origin := cursor - grab-offset.
k_dragmove:
        LDA  kmx                        ; x = kmx - kgx
        STA  ka
        LDA  kmx+1
        STA  ka+1
        LDA  kgx
        STA  kb
        LDA  kgx+1
        STA  kb+1
        JSR  k16sub
        LDA  kw
        STA  kmx2
        LDA  kw+1
        STA  kmx2+1
        LDA  kmy                        ; y = kmy - kgy
        STA  ka
        LDA  kmy+1
        STA  ka+1
        LDA  kgy
        STA  kb
        LDA  kgy+1
        STA  kb+1
        JSR  k16sub
        LDA  kw
        STA  kmy2
        LDA  kw+1
        STA  kmy2+1
        ; write (kmx2,kmy2) into the grabbed window's origin
        LDA  kdragw
        STA  ki
        JSR  koff
        JSR  kp1
        LDA  kmx2
        STA  (P1)+
        LDA  kmx2+1
        STA  (P1)+
        LDA  kmy2
        STA  (P1)+
        LDA  kmy2+1
        STA  (P1)
        RTS

; k_rdnum: read a decimal from the console into knum (16-bit); the first
; non-digit terminates and is left in kterm. Uses the MDU for the x10.
k_rdnum:LDA  #0
        STA  knum
        STA  knum+1
krn_lp: JSR  $0100
        STA  kterm
        LDB  #$30                       ; '0'
        CMP
        JNC  krn_ret                    ; < '0' -> terminator
        LDB  #$3A                       ; ':'
        CMP
        JC   krn_ret                    ; >= ':' (i.e. > '9') -> terminator
        LDB  #$30                       ; digit value
        SUB
        STA  kt                         ; kt = 0..9
        LDA  knum                       ; knum *= 10
        STA  ka
        LDA  knum+1
        STA  ka+1
        LDA  #10
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k_mul                      ; kw = knum*10
        LDA  kw                         ; knum = kw + digit
        STA  ka
        LDA  kw+1
        STA  ka+1
        LDA  kt
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k16add
        LDA  kw
        STA  knum
        LDA  kw+1
        STA  knum+1
        JMP  krn_lp
krn_ret:RTS

; k_mul: kw = ka * kb (16-bit * 16-bit -> 16-bit) via the MDU, divisor 1.
k_mul:  LDA  ka
        STA  $FF30                      ; MDA  (write clears MDAH)
        LDA  ka+1
        STA  $FF39                      ; MDAH
        LDA  kb
        STA  $FF31                      ; MDB
        LDA  kb+1
        STA  $FF3A                      ; MDBH
        LDA  #1
        STA  $FF32                      ; MDC = 1
        LDA  #0
        STA  $FF3B                      ; MDCH
        STA  $FF34                      ; MDGO
kml_w:  LDA  $FF35                      ; MDSTAT bit7 = busy
        LDB  #$80
        AND
        JNZ  kml_w
        LDA  $FF33                      ; MDQ
        STA  kw
        LDA  $FF3C                      ; MDQH
        STA  kw+1
        RTS

; k_dec1n: ka = knum - 1 (16-bit).
k_dec1n:LDA  knum
        LDB  #1
        SUB
        STA  ka
        LDA  knum+1
        JC   kd1_r
        LDB  #1
        SUB
kd1_r:  STA  ka+1
        RTS

; k_settop: the TOP window's origin (x,y) := (kmx, kmy).
k_settop:
        LDA  wcnt
        JZ   kst_ret
        LDB  #1
        SUB
        STA  ki
        JSR  koff                       ; A = 24*top
        JSR  kp1                        ; P1 = recs + 24*top (x field)
        LDA  kmx
        STA  (P1)+
        LDA  kmx+1
        STA  (P1)+
        LDA  kmy
        STA  (P1)+
        LDA  kmy+1
        STA  (P1)
kst_ret:RTS

; k_movetop: add the 16-bit signed delta in kdxy to the TOP window's field
; (A = 0 for x, 2 for y). The top window is the last opened (wcnt-1).
k_movetop:
        STA  kt                         ; field offset
        LDA  wcnt
        JZ   kmt_ret                    ; no windows
        LDB  #1
        SUB
        STA  ki                         ; top index
        JSR  koff                       ; A = 24*ki
        LDB  kt
        ADD                             ; + field offset
        JSR  kp1                        ; P1 = recs + 24*top + field
        LDA  (P1)                       ; read the 16-bit field -> ka
        STA  ka
        INP1
        LDA  (P1)
        STA  ka+1
        LDA  kdxy                       ; kb = delta
        STA  kb
        LDA  kdxy+1
        STA  kb+1
        JSR  k16add                     ; kw = field + delta
        LDA  kw+1                        ; P1 is at field+1 -> write high
        STA  (P1)
        DEP1
        LDA  kw                          ; write low
        STA  (P1)
kmt_ret:RTS

; ---- draw window ki : body (black fill), border (white), title (white) -----
wk_draw:JSR  koff                       ; A = 24*ki
        JSR  kp1                        ; P1 = recs + 24*ki
        LDA  (P1)+                      ; unpack x,y,w,h
        STA  kx
        LDA  (P1)+
        STA  kx+1
        LDA  (P1)+
        STA  ky
        LDA  (P1)+
        STA  ky+1
        LDA  (P1)+
        STA  kcw
        LDA  (P1)+
        STA  kcw+1
        LDA  (P1)+
        STA  kch
        LDA  (P1)+
        STA  kch+1
        LDA  (P1)+                      ; list id (unused in v1)
        STA  klist
        LDA  (P1)                       ; tlen
        STA  ktlen
        ; x1 = kx + kcw - 1 ; y1 = ky + kch - 1  -> kx1/ky1
        LDA  kx
        STA  ka
        LDA  kx+1
        STA  ka+1
        LDA  kcw
        STA  kb
        LDA  kcw+1
        STA  kb+1
        JSR  k16add                     ; kw = kx+kcw
        JSR  kw_dec1                    ; kw -= 1
        LDA  kw
        STA  kx1
        LDA  kw+1
        STA  kx1+1
        LDA  ky
        STA  ka
        LDA  ky+1
        STA  ka+1
        LDA  kch
        STA  kb
        LDA  kch+1
        STA  kb+1
        JSR  k16add
        JSR  kw_dec1
        LDA  kw
        STA  ky1
        LDA  kw+1
        STA  ky1+1
        ; body: PRMFIL 1, COLOR black, MOVE(kx,ky), RECT(kx1,ky1)
        LDA  #$E0
        JSR  kput
        LDA  #1
        JSR  kput
        JSR  kcol_blk
        JSR  kmove_xy                   ; MOVE(kx,ky)
        JSR  krect_11                   ; RECT(kx1,ky1)
        ; border: PRMFIL 0, COLOR white, MOVE(kx,ky), RECT(kx1,ky1)
        LDA  #$E0
        JSR  kput
        LDA  #0
        JSR  kput
        JSR  kcol_wht
        JSR  kmove_xy
        JSR  krect_11
        ; title: COLOR white, MOVE3(kx+5, ky+kch-11, 0), TEXT ktlen chars
        JSR  kcol_wht
        ; anchor x = kx + 5
        LDA  kx
        STA  ka
        LDA  kx+1
        STA  ka+1
        LDA  #5
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k16add
        LDA  kw
        STA  ktx
        LDA  kw+1
        STA  ktx+1
        ; anchor y = ky + kch - 11
        LDA  ky
        STA  ka
        LDA  ky+1
        STA  ka+1
        LDA  kch
        STA  kb
        LDA  kch+1
        STA  kb+1
        JSR  k16add                     ; ky+kch
        LDA  kw
        STA  ka
        LDA  kw+1
        STA  ka+1
        LDA  #11
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k16sub                     ; ky+kch-11
        LDA  kw
        STA  kty
        LDA  kw+1
        STA  kty+1
        ; MOVE3 ktx kty 0
        LDA  #$12
        JSR  kput
        LDA  ktx
        STA  kw
        LDA  ktx+1
        STA  kw+1
        JSR  ksw
        LDA  kty
        STA  kw
        LDA  kty+1
        STA  kw+1
        JSR  ksw
        LDA  #0
        STA  kw
        STA  kw+1
        JSR  ksw
        ; TEXT ktlen  then the title bytes
        LDA  #$80
        JSR  kput
        LDA  ktlen
        JSR  kput
        LDA  ktlen
        JZ   wkd_ret
        STA  kt
        JSR  koff                       ; title = recs + 24*ki + 10
        LDB  #10
        ADD
        JSR  kp1
wkd_tl: LDA  (P1)+
        JSR  kput
        LDA  kt
        DEC
        STA  kt
        JNZ  wkd_tl
        ; content: if klist != 0, map the content rect and CLRUN its card
        ; list -- the picture lives on the CARD, so it redraws even when
        ; the program that recorded it is long gone.
wkd_cnt:LDA  klist
        JZ   wkd_ret
        JSR  k_content                  ; WINDOW/VWPORT -> the content rect
        LDA  #$72                       ; CLRUN klist
        JSR  kput
        LDA  klist
        JSR  kput
        JSR  k_ident                    ; restore identity for the next window
wkd_ret:RTS

; k_content: set WINDOW (0..cw-1, 0..ch-1) + VWPORT (the content rect,
; inside the border and below the title bar) so a CLRUN replays into the
; window in LOCAL coords. cw=kcw-2, ch=kch-15 (the lib_wm mapping).
k_content:
        LDA  #$B3                       ; WINDOW 0 (kcw-3) 0 (kch-16)
        JSR  kput
        LDA  #0                         ; x1 = 0
        STA  kw
        STA  kw+1
        JSR  ksw
        LDA  kcw                        ; x2 = kcw - 3
        STA  ka
        LDA  kcw+1
        STA  ka+1
        LDA  #3
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k16sub
        JSR  ksw
        LDA  #0                         ; y1 = 0
        STA  kw
        STA  kw+1
        JSR  ksw
        LDA  kch                        ; y2 = kch - 16
        STA  ka
        LDA  kch+1
        STA  ka+1
        LDA  #16
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k16sub
        JSR  ksw
        LDA  #$B2                       ; VWPORT vx1 vx2 vy1 vy2
        JSR  kput
        LDA  kx                         ; vx1 = kx + 1
        STA  ka
        LDA  kx+1
        STA  ka+1
        LDA  #1
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k16add
        JSR  ksw
        LDA  kx                         ; vx2 = kx + kcw - 2
        STA  ka
        LDA  kx+1
        STA  ka+1
        LDA  kcw
        STA  kb
        LDA  kcw+1
        STA  kb+1
        JSR  k16add
        LDA  kw
        STA  ka
        LDA  kw+1
        STA  ka+1
        LDA  #2
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k16sub
        JSR  ksw
        LDA  #30                        ; vy1 = 286 - ky - kch   (286 = $011E)
        STA  ka
        LDA  #1
        STA  ka+1
        LDA  ky
        STA  kb
        LDA  ky+1
        STA  kb+1
        JSR  k16sub                     ; 286 - ky
        LDA  kw
        STA  ka
        LDA  kw+1
        STA  ka+1
        LDA  kch
        STA  kb
        LDA  kch+1
        STA  kb+1
        JSR  k16sub                     ; - kch
        JSR  ksw
        LDA  #14                        ; vy2 = 270 - ky   (270 = $010E)
        STA  ka
        LDA  #1
        STA  ka+1
        LDA  ky
        STA  kb
        LDA  ky+1
        STA  kb+1
        JSR  k16sub
        JSR  ksw
        RTS

; MOVE(kx,ky)
kmove_xy:
        LDA  #$10
        JSR  kput
        LDA  kx
        STA  kw
        LDA  kx+1
        STA  kw+1
        JSR  ksw
        LDA  ky
        STA  kw
        LDA  ky+1
        STA  kw+1
        JSR  ksw
        RTS
; RECT(kx1,ky1)
krect_11:
        LDA  #$34
        JSR  kput
        LDA  kx1
        STA  kw
        LDA  kx1+1
        STA  kw+1
        JSR  ksw
        LDA  ky1
        STA  kw
        LDA  ky1+1
        STA  kw+1
        JSR  ksw
        RTS

kcol_blk:
        LDA  #6
        JSR  kput
        LDA  #0
        JSR  kput
        JSR  kput
        JSR  kput
        RTS
kcol_wht:
        LDA  #6
        JSR  kput
        LDA  #31
        JSR  kput
        LDA  #63
        JSR  kput
        LDA  #31
        JSR  kput
        RTS

; kw_dec1: kw -= 1 (16-bit).
kw_dec1:LDA  kw
        LDB  #1
        SUB
        STA  kw
        JC   kwd_r                      ; C=1 -> no borrow
        LDA  kw+1
        LDB  #1
        SUB
        STA  kw+1
kwd_r:  RTS

; k_ident: identity WINDOW + VWPORT (full screen 0..479, 0..271).
k_ident:LDA  #<kid
        TAP1L
        LDA  #>kid
        TAP1H
        LDA  #18
        STA  kt
kid_lp: LDA  (P1)+
        JSR  kput
        LDA  kt
        DEC
        STA  kt
        JNZ  kid_lp
        RTS
kid:    .byte $B3, 0, 0, $DF, 1, 0, 0, $0F, 1
        .byte $B2, 0, 0, $DF, 1, 0, 0, $0F, 1

; ==== resident state =========================================================
wcnt:   .fill 1
ki:     .fill 1
kt:     .fill 1
kt2:    .fill 1
kt3:    .fill 1
ka:     .fill 2
kb:     .fill 2
kw:     .fill 2
kx:     .fill 2
ky:     .fill 2
kcw:    .fill 2
kch:    .fill 2
kx1:    .fill 2
ky1:    .fill 2
ktx:    .fill 2
kty:    .fill 2
klist:  .fill 1
kdxy:   .fill 2
knum:   .fill 2
kterm:  .fill 1
kmx:    .fill 2
kmy:    .fill 2
kmx2:   .fill 2
kmy2:   .fill 2
mbtn:   .fill 1
kdragw: .fill 1
kgx:    .fill 2
kgy:    .fill 2
ktlen:  .fill 1
recs:   .fill 96                        ; 4 windows x 24 bytes
