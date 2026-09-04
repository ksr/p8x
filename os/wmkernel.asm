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
;                              chrome and title from the RESIDENT records
;   WMBASE+9  .byte 'W','M'    presence signature (the launcher checks it
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

; ---- jump table: MUST be first so the entries land at WMBASE+0/3/6 ----------
        JMP  wk_init
        JMP  wk_open
        JMP  wk_repaint
ksig:   .byte $57, $4D                  ; 'W','M'

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
ktlen:  .fill 1
recs:   .fill 96                        ; 4 windows x 24 bytes
