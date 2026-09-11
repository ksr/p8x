; wmkernel_body.asm -- the resident P8X window-manager kernel (routines + data).
; .included by os/p8xos.asm at the END of the OS image, and reached through the
; OS syscall table right after SYS_EXEC:
;   $2027 SYS_WKINIT   $202A SYS_WKOPEN   $202D SYS_WKREPAINT
;   $2030 SYS_WKRUN    $2033 SYS_WKSAVE   $2036 SYS_WKLOAD
;   $2039 SYS_WKPATH   $203C SYS_WKEVENT  $203F SYS_WKCLOSE
;   $2042 SYS_WKARG    $2045 SYS_WKGET    $2048 SYS_WKTOP
;   $204B SYS_WKRAISE
; So it is resident from boot and needs no loading. No .org and no equates here
; -- GLDATA/GLSTAT come from memmap.inc via the OS. All code is label-relative.
; (A standalone .org'd harness once loaded this as a blob at $D800, then $5600;
; both retired -- $5600 sat inside the shell's command-history ring.)
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

; k_off16: kw = ka + A  (A a small 0..255 offset; ka preserved). Tail-calls
; k16add, whose RTS returns to OUR caller.
k_off16:STA  kb
        LDA  #0
        STA  kb+1
        JMP  k16add

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

; ==== wk_save / wk_load : per-window STATE, held RESIDENT across launches ====
; Each window owns a 4-byte state blob (wstate[]) that outlives the app --
; so a program can save where it was, and when it (or the next app) is
; launched into that window it resumes from there. This is the switcher's
; core: state survives switching, because the kernel holding it is resident.
;   wk_save: P1 = a 4-byte blob, A = window index -> copy into wstate[win]
;   wk_load: P1 = a 4-byte dest, A = window index -> copy wstate[win] out
wk_save:STA  ki                         ; window index
        LDA  ki                         ; P2 = wstate + 4*index
        SHL
        SHL
        STA  kt
        LDA  #<wstate
        LDB  kt
        ADD
        TAP2L
        LDA  #>wstate
        JNC  ws_h
        LDB  #1
        ADD
ws_h:   TAP2H
        LDA  #4
        STA  kt
ws_cp:  LDA  (P1)+
        STA  (P2)+
        LDA  kt
        DEC
        STA  kt
        JNZ  ws_cp
        RTS
wk_load:STA  ki
        LDA  ki
        SHL
        SHL
        STA  kt
        LDA  #<wstate
        LDB  kt
        ADD
        TAP2L
        LDA  #>wstate
        JNC  wl_h
        LDB  #1
        ADD
wl_h:   TAP2H
        LDA  #4
        STA  kt
wl_cp:  LDA  (P2)+
        STA  (P1)+
        LDA  kt
        DEC
        STA  kt
        JNZ  wl_cp
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
; so the app that called SYS_WKRUN is still in the TPA -- but a launched
; program will replace it while the loop persists (the launch-and-resume
; rung).
wk_run: LDA  #99                       ; no window grabbed yet
        STA  kdragw
        JSR  wk_repaint
wkrun_lp:JSR wk_event                  ; one event: C=quit, A=0 handled, A=1 key,
        JC   wkr_end                   ;   A=2 bar click (key/col in kev_arg)
        LDB  #1                        ; the built-in loop owns just the 'l' key
        CMP
        JNZ  wkrun_lp                  ; A=0 (handled) or A=2 (bar): ignore
        LDA  kev_arg                   ; A=1: a key -> is it 'l' = LAUNCH?
        LDB  #$6C
        CMP
        JZ   wru_launch
        JMP  wkrun_lp                  ; any other key: ignore (wk_run has no
                                       ;   client; wdesk uses wk_event)
wkr_end:RTS

; ==== wk_event : ONE step of the resident loop (SYS_WKEVENT, $203C) =========
; Reads a console event and handles everything the KERNEL owns -- TAB focus,
; arrow move, mouse press/drag/release (raise, drag, close) -- then RETURNS to
; the client, so the client owns the outer loop and its own UI (a menu bar,
; FILES, TERM...). Return: carry SET = quit (^D); else A = 0 when the kernel
; handled the event, or the key byte for a key the kernel does NOT own (the
; client decides). This is the split that keeps the kernel a small resident
; core while the rich desktop lives in the client's 37 KB TPA.
wk_event:
        JSR  $0100                      ; CONIN -> A (blocks for a key)
        LDB  #4                         ; ^D -> quit
        CMP
        JZ   wev_quit
        LDB  #9                         ; TAB -> cycle focus
        CMP
        JZ   wru_tab
        LDB  #27                        ; ESC -> arrow / mouse sequence
        CMP
        JZ   wru_esc
        STA  kev_arg                    ; an unowned key -> event 1, key in kev_arg
        CLC
        LDA  #1
        RTS
wev_quit:SEC                            ; carry set = quit
        RTS
wev_h1: CLC                             ; kernel handled it: A=0, C=0, Z=1
        LDA  #0
        RTS

; LAUNCH: SYS_EXEC a WM client into the TPA. SYS_EXEC replaces the TPA (this
; loop's original caller included) and never returns here -- but the kernel
; and its window records are RESIDENT inside the OS image, below the TPA,
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
        JMP  wkrun_lp                    ; only reached if the exec failed
; ==== wk_path : set the 'l'-key launch target (SYS_WKPATH, $2039) ==========
; P1 -> NUL-terminated "path [args]" (up to 23 chars), copied into kpath. The
; default "/bin/wapp.bin" is the WM tests' client; wdesk sets
; "/bin/paint.bin -w", and paint (launched with -w) resumes the desktop via
; SYS_WKRUN when it quits -- launch-and-resume from a real program.
wk_path:LDP2 #kpath
        LDA  #23
        STA  kt
wkp_cp: LDA  (P1)+
        STA  (P2)+
        JZ   wkp_ret                    ; copied the NUL (Z is the LDA's)
        LDA  kt
        DEC
        STA  kt
        JNZ  wkp_cp
        LDA  #0                         ; hit the cap: force a terminator
        STA  (P2)+
wkp_ret:RTS
; ==== wk_close : pop the top (focused) window (SYS_WKCLOSE, $203F) ==========
; The client's menu/keyboard "close" -- the mouse close box does the same pop
; inline. Records above it don't exist (top is the last), so this is a decrement.
wk_close:LDA  wcnt
        JZ   wkc_ret
        DEC
        STA  wcnt
wkc_ret:RTS
; ==== wk_arg : the data byte for the last SYS_WKEVENT (SYS_WKARG, $2042) ====
; After SYS_WKEVENT returns event 1 (a key) or event 2 (a menu-bar click), the
; client reads the payload here: the key byte, or the cursor COLUMN of the
; click. One byte keeps the SYS_WKEVENT return itself a clean event code.
wk_arg: CLC                             ; a clean byte: bios() must not see a
        LDA  kev_arg                    ;   stray carry as bit 256 in the result
        RTS
; ==== wk_get : copy window A's 22-byte record to (P1) (SYS_WKGET, $2045) ====
; Lets a client read a window's rect so it can draw its OWN dynamic content
; inside it (a directory listing, a terminal): the kernel owns the chrome and
; z-order, the client fills the body. A = window index, P1 = dest buffer.
wk_get: STA  ki
        JSR  koff                       ; A = 24*ki
        JSR  kp2                        ; P2 = recs + 24*ki (source)
        LDA  #22
        STA  kt
wkg_cp: LDA  (P2)+
        STA  (P1)+
        LDA  kt
        DEC
        STA  kt
        JNZ  wkg_cp
        RTS
; ==== wk_top : A = the top (focused) window index, 99 if none (SYS_WKTOP) ====
wk_top: LDA  wcnt
        JZ   wkt_no
        LDB  #1
        SUB
        CLC                             ; clean byte return
        RTS
wkt_no: LDA  #99
        CLC
        RTS

; ==== wk_raise : SYS_WKRAISE ($204B) -- raise window (A) to the top (focus it) =
; z-order is the kernel's job, so a "focus window N" primitive belongs here (the
; client picks WHICH window by title, then asks the kernel to raise that index).
; k_raise already exists for TAB/mouse; this just exposes it. Client repaints.
wk_raise:JSR  k_raise                    ; A = window index -> reorder to top slot
        CLC                             ; clean return (no stray carry for bios)
        RTS

; ==== wk_sink : SYS_WKSINK ($204E) -- route stdout into a window ==============
; A = window index -> ARM: record command output as TEXT into that window's card
; list (which the kernel already CLRUNs on repaint, so it persists), and set
; OUTCH's REDIRF=3 so every SYS_PUTC lands there. A = 255 -> DISARM (CLEND the
; list, REDIRF back to console). This is the mode-3 half of the OUTCH->window
; sink (docs/p8x-wm-design.md); the client arms it, runs a text command, disarms.
; Text flows because GL TEXT auto-advances the pen -- one "TEXT 1 char" per byte,
; a MOVE3 only on newline. No wrap/scroll yet: long lines / overflow just clip.
wk_sink: LDB  #255
        CMP
        JZ   wks_off
        STA  ki                         ; arm: ki = window index
        JSR  koff                       ; A = 24*ki
        LDB  #6
        ADD                             ; A = 24*ki + 6  (offset of h)
        JSR  kp1                        ; P1 = &record.h
        LDA  (P1)+                      ; h lo -> ka
        STA  ka
        LDA  (P1)+                      ; h hi -> ka+1
        STA  ka+1
        LDA  (P1)                       ; list id (offset 8)
        STA  sinklst
        LDW kb,#29                    ; homeY = h - 29 (top line, y-up local)
        JSR  k16sub                     ; kw = h - 29
        MOVW sinky,kw
        LDA  #112                       ; CLBEG sinklst  (fresh recording)
        JSR  kput
        LDA  sinklst
        JSR  kput
        LDA  #6                         ; COLOR white
        JSR  kput
        LDA  #31
        JSR  kput
        LDA  #63
        JSR  kput
        LDA  #31
        JSR  kput
        JSR  sink_home                  ; MOVE3 to the first line
        LDA  #3                         ; arm OUTCH mode 3
        STA  REDIRF
        RTS
wks_off:LDA  #113                       ; CLEND -> close the list
        JSR  kput
        LDA  #0
        STA  REDIRF
        RTS

; sink_home: record MOVE3 4, sinky, 0 -- move the text pen to the line start.
sink_home:
        LDA  #18                        ; MOVE3
        JSR  kput
        LDW kw,#4                     ; x = 4 (left margin)
        JSR  ksw
        MOVW kw,sinky                 ; y = sinky
        JSR  ksw
        LDA  #0                         ; z = 0
        STA  kw
        STA  kw+1
        JSR  ksw
        RTS

; OUTWIN: OUTCH's REDIRF=3 sink (char in RCH). Printable -> TEXT 1 char (the pen
; auto-advances); LF -> drop a line + home; CR -> home. Records into the open
; card list. RTS to OUTCH's caller.
OUTWIN: LDA  RCH
        LDB  #10                        ; LF
        CMP
        JZ   ow_lf
        LDB  #13                        ; CR
        CMP
        JZ   ow_cr
        LDA  RCH                        ; printable 32..126 ?
        LDB  #32
        CMP
        JNC  ow_ret                     ; < 32 -> ignore
        LDB  #127
        CMP
        JC   ow_ret                     ; >= 127 -> ignore
        LDA  #128                       ; TEXT 1 <char>
        JSR  kput
        LDA  #1
        JSR  kput
        LDA  RCH
        JSR  kput
ow_ret: RTS
ow_lf:  MOVW ka,sinky                 ; sinky -= 13
        LDW kb,#13
        JSR  k16sub
        MOVW sinky,kw
        JSR  sink_home
        RTS
ow_cr:  JSR  sink_home
        RTS

kpath:  .ascii "/bin/wapp.bin"          ; 13 + NUL + 10 pad = a 24-byte buffer
        .byte 0
        .fill 10
wru_esc:JSR  $0100                      ; expect '['
        LDB  #$5B
        CMP
        JNZ  wev_h1
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
        JMP  wev_h1
wru_up: LDW kdxy,#8
        LDA  #2                         ; field = y
        JMP  wru_mv
wru_dn: LDW kdxy,#65528               ; -8, two's complement
        LDA  #2
        JMP  wru_mv
wru_rt: LDW kdxy,#8
        LDA  #0                         ; field = x
        JMP  wru_mv
wru_lf: LDW kdxy,#65528
        LDA  #0
wru_mv: JSR  k_movetop
        JSR  wk_repaint
        JMP  wev_h1
; TAB: cycle focus -- raise the BOTTOM window (index 0) to the top, exactly
; what desk's TAB does. Focus IS the top record; it draws with a white title
; bar, the rest grey. Needs two windows to mean anything.
wru_tab:LDA  wcnt
        LDB  #2
        CMP
        JC   wrt_go                     ; C=1 -> wcnt >= 2
        JMP  wev_h1
wrt_go: LDA  #0
        JSR  k_raise
        JSR  wk_repaint
        JMP  wev_h1

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
        LDA  knum                       ; save the x CELL (menu-bar click column)
        STA  kcellx
        JSR  k_dec1n                    ; ka = knum - 1
        LDW kb,#6
        JSR  k_mul                      ; kw = (x-1)*6
        MOVW kmx,kw
        JSR  k_rdnum                    ; y -> knum ; term M/m
        LDA  knum                       ; save the y CELL (menu-bar test)
        STA  kcelly
        JSR  k_dec1n                    ; ka = knum - 1
        LDW kb,#11
        JSR  k_mul                      ; kw = (y-1)*11
        LDW ka,#271                   ; kmy = 271 - kw   (271 = $010F)
        MOVW kb,kw
        JSR  k16sub
        MOVW kmy,kw
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
        JC   wev_h1                     ; no window grabbed
        JSR  k_dragmove
        JSR  wk_repaint
        JMP  wev_h1
wru_mpress:
        ; a PRESS in the menu bar (top rows, cell y <= 2)? Hand it to the
        ; client as a bar CLICK, cursor column in kev_arg -- the client owns
        ; the menu; the kernel owns only the windows below.
        LDA  kcelly
        LDB  #3
        CMP
        JC   wmp_win                    ; C=1 -> cell y >= 3: a window press
        LDA  kcellx
        STA  kev_arg
        LDA  #99                        ; a bar press is not a window drag
        STA  kdragw
        CLC
        LDA  #2                         ; event 2 = menu-bar click (SYS_WKARG=col)
        RTS
wmp_win:JSR  k_hit                      ; which window is under the cursor?
        JZ   wru_mnohit
        LDA  ki
        JSR  k_raise                    ; focus it: its record moves to the top
        ; the CLOSE BOX? in the title bar (kmy >= ky+kch-14) and within
        ; kx+3..kx+11 -- desk's box. k_inwin left the rect in kx,ky,kcw,kch.
        MOVW ka,ky                    ; kw = ky + kch - 14  (the bar's bottom)
        MOVW kb,kch
        JSR  k16add
        MOVW ka,kw
        LDW kb,#14
        JSR  k16sub
        MOVW ka,kmy                   ; kmy >= bar bottom ?
        MOVW kb,kw
        JSR  k_ge
        JZ   wru_grab                   ; a body press: just grab
        MOVW ka,kx                    ; kmx2 = kx+3, kmy2 = kx+11 (as temps)
        LDA  #3
        JSR  k_off16
        MOVW kmx2,kw
        LDA  #11
        JSR  k_off16                    ; ka is still kx
        MOVW kmy2,kw
        MOVW ka,kmx                   ; kmx >= kx+3 ?
        MOVW kb,kmx2
        JSR  k_ge
        JZ   wru_grab                   ; left of the box
        MOVW ka,kmy2                  ; kx+11 >= kmx ?
        MOVW kb,kmx
        JSR  k_ge
        JZ   wru_grab                   ; right of the box
        ; CLOSE: the window is the top record now, so closing it = pop
        LDA  wcnt
        DEC
        STA  wcnt
        LDA  #99
        STA  kdragw
        JSR  wk_repaint
        JMP  wev_h1
wru_grab:
        JSR  wk_repaint                 ; the raise changed the z-order
        ; grab it: kdragw = top index, grab-offset = cursor - origin
        LDA  wcnt
        LDB  #1
        SUB
        STA  kdragw
        MOVW ka,kmx                   ; kgx = kmx - kx  (kx/ky loaded by k_intop)
        MOVW kb,kx
        JSR  k16sub
        MOVW kgx,kw
        MOVW ka,kmy                   ; kgy = kmy - ky
        MOVW kb,ky
        JSR  k16sub
        MOVW kgy,kw
        JMP  wev_h1
wru_mnohit:
        LDA  #99                        ; press missed: no drag target
        STA  kdragw
        JMP  wev_h1
wru_mrel:
        LDA  #99
        STA  kdragw
        JMP  wev_h1

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

; k_hit: the topmost window containing (kmx,kmy): A=1 (Z=0) with ki = its
; index and its rect in kx,ky,kcw,kch; A=0 if none. Scans top-down like
; lib_wm's wm_hit, so a press on a LOWER window finds that window (which the
; press handler then raises = focuses).
k_hit:  LDA  wcnt
        JZ   kit_no
        LDB  #1
        SUB
        STA  ki                         ; start at the top
kh_lp:  JSR  k_inwin
        JNZ  kh_yes
        LDA  ki
        JZ   kit_no                     ; index 0 missed too: nothing hit
        DEC
        STA  ki
        JMP  kh_lp
kh_yes: LDA  #1
        RTS
; k_inwin: A = 1 (Z=0) if (kmx,kmy) is inside window ki, else 0. Loads its
; rect into kx,ky,kcw,kch as a side effect.
k_inwin:JSR  koff
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
        MOVW ka,kmx
        MOVW kb,kx
        JSR  k_ge
        JZ   kit_no
        ; kmx < kx+kcw ?  (reject if kmx >= kx+kcw)
        MOVW ka,kx
        MOVW kb,kcw
        JSR  k16add                     ; kw = kx+kcw
        MOVW ka,kmx
        MOVW kb,kw
        JSR  k_ge
        JNZ  kit_no                     ; kmx >= kx+kcw -> outside
        ; kmy >= ky ?
        MOVW ka,kmy
        MOVW kb,ky
        JSR  k_ge
        JZ   kit_no
        ; kmy < ky+kch ?
        MOVW ka,ky
        MOVW kb,kch
        JSR  k16add
        MOVW ka,kmy
        MOVW kb,kw
        JSR  k_ge
        JNZ  kit_no                     ; kmy >= ky+kch -> outside
        LDA  #1                         ; inside
        RTS
kit_no: LDA  #0
        RTS

; k_dragmove: the grabbed window's origin := cursor - grab-offset.
k_dragmove:
        MOVW ka,kmx                   ; x = kmx - kgx
        MOVW kb,kgx
        JSR  k16sub
        MOVW kmx2,kw
        MOVW ka,kmy                   ; y = kmy - kgy
        MOVW kb,kgy
        JSR  k16sub
        MOVW kmy2,kw
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
        MOVW ka,knum                  ; knum *= 10
        LDW kb,#10
        JSR  k_mul                      ; kw = knum*10
        MOVW ka,kw                    ; knum = kw + digit
        LDA  kt
        STA  kb
        LDA  #0
        STA  kb+1
        JSR  k16add
        MOVW knum,kw
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
        MOVW kb,kdxy                  ; kb = delta
        JSR  k16add                     ; kw = field + delta
        LDA  kw+1                        ; P1 is at field+1 -> write high
        STA  (P1)
        DEP1
        LDA  kw                          ; write low
        STA  (P1)
kmt_ret:RTS

; kp2: P2 = recs + (A)  -- the P2 twin of kp1.
kp2:    STA  kt
        LDA  #<recs
        LDB  kt
        ADD
        TAP2L
        LDA  #>recs
        JNC  kp2_r
        LDB  #1
        ADD
kp2_r:  TAP2H
        RTS

; k_raise: A = window index -> move its 24-byte record to the TOP slot
; (wcnt-1), sliding the records above it down one. The record order IS the
; z-order and the top record IS the focus, so this is raise + focus in one:
; TAB calls it with 0 (bottom to top), a mouse press with the hit window.
k_raise:STA  kri
        LDA  wcnt
        LDB  #1
        SUB
        LDB  kri
        CMP
        JZ   krs_ret                    ; already on top
        LDA  kri                        ; save rec[kri] -> ktmp
        STA  ki
        JSR  koff
        JSR  kp1                        ; P1 = rec[kri]
        LDP2 #ktmp
        LDA  #24
        STA  kt
krs_sv: LDA  (P1)+
        STA  (P2)+
        LDA  kt
        DEC
        STA  kt
        JNZ  krs_sv
        ; slide rec[kri+1..top] down one slot: (top-kri)*24 bytes, forward,
        ; from P1 (now = rec[kri+1]) to P2 = rec[kri]
        LDA  kri
        STA  ki
        JSR  koff
        JSR  kp2                        ; P2 = rec[kri]
        LDA  wcnt
        LDB  #1
        SUB
        LDB  kri
        SUB                             ; n = top - kri  (1..3)
        SHL
        SHL
        SHL                             ; 8n
        STA  kt3
        SHL                             ; 16n
        LDB  kt3
        ADD                             ; 24n bytes
        STA  kt
krs_sh: LDA  (P1)+
        STA  (P2)+
        LDA  kt
        DEC
        STA  kt
        JNZ  krs_sh
        LDP1 #ktmp                      ; ktmp -> rec[top] (P2 is there now)
        LDA  #24
        STA  kt
krs_rs: LDA  (P1)+
        STA  (P2)+
        LDA  kt
        DEC
        STA  kt
        JNZ  krs_rs
krs_ret:RTS

; ---- draw window ki : body (black fill), title bar, border (white), title ----
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
        MOVW ka,kx
        MOVW kb,kcw
        JSR  k16add                     ; kw = kx+kcw
        JSR  kw_dec1                    ; kw -= 1
        MOVW kx1,kw
        MOVW ka,ky
        MOVW kb,kch
        JSR  k16add
        JSR  kw_dec1
        MOVW ky1,kw
        ; body: PRMFIL 1, COLOR black, MOVE(kx,ky), RECT(kx1,ky1)
        LDA  #$E0
        JSR  kput
        LDA  #1
        JSR  kput
        JSR  kcol_blk
        JSR  kmove_xy                   ; MOVE(kx,ky)
        JSR  krect_11                   ; RECT(kx1,ky1)
        ; title bar: the top 14 rows, WHITE for the focused (top) window and
        ; GREY for the rest -- desk's look (lib_wm wm_chrome). Still PRMFIL 1.
        MOVW ka,ky                    ; kty = ky + kch - 14  (the bar's bottom)
        MOVW kb,kch
        JSR  k16add
        MOVW ka,kw
        LDW kb,#14
        JSR  k16sub
        MOVW kty,kw
        LDA  ki                         ; focused <=> ki == wcnt-1
        INC
        LDB  wcnt
        CMP
        JZ   wkd_fw
        LDA  #6                         ; COLOR grey (16,32,16 = 33808)
        JSR  kput
        LDA  #16
        JSR  kput
        LDA  #32
        JSR  kput
        LDA  #16
        JSR  kput
        JMP  wkd_bar
wkd_fw: JSR  kcol_wht
wkd_bar:LDA  #$10                       ; MOVE(kx, kty)
        JSR  kput
        MOVW kw,kx
        JSR  ksw
        MOVW kw,kty
        JSR  ksw
        JSR  krect_11                   ; RECT(kx1,ky1): the bar
        ; close box: a black 9x9 on the bar at (kx+3,kty+2)..(kx+11,kty+10)
        ; -- desk's (wmx+3, wmy+wmh-12)..(wmx+11, wmy+wmh-4). PRMFIL still 1.
        JSR  kcol_blk
        LDA  #$10                       ; MOVE(kx+3, kty+2)
        JSR  kput
        MOVW ka,kx
        LDA  #3
        JSR  k_off16
        JSR  ksw
        MOVW ka,kty
        LDA  #2
        JSR  k_off16
        JSR  ksw
        LDA  #$34                       ; RECT(kx+11, kty+10)
        JSR  kput
        MOVW ka,kx
        LDA  #11
        JSR  k_off16
        JSR  ksw
        MOVW ka,kty
        LDA  #10
        JSR  k_off16
        JSR  ksw
        ; border: PRMFIL 0, COLOR white, MOVE(kx,ky), RECT(kx1,ky1)
        LDA  #$E0
        JSR  kput
        LDA  #0
        JSR  kput
        JSR  kcol_wht
        JSR  kmove_xy
        JSR  krect_11
        ; title: COLOR black on the bar, MOVE3(kx+16, ky+kch-11, 0) -- past the
        ; close box at kx+3..kx+11 -- then TEXT ktlen chars (desk's placement)
        JSR  kcol_blk
        ; anchor x = kx + 16
        MOVW ka,kx
        LDW kb,#16
        JSR  k16add
        MOVW ktx,kw
        ; anchor y = ky + kch - 11
        MOVW ka,ky
        MOVW kb,kch
        JSR  k16add                     ; ky+kch
        MOVW ka,kw
        LDW kb,#11
        JSR  k16sub                     ; ky+kch-11
        MOVW kty,kw
        ; MOVE3 ktx kty 0
        LDA  #$12
        JSR  kput
        MOVW kw,ktx
        JSR  ksw
        MOVW kw,kty
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
        JSR  koff                       ; title = recs + 24*ki + 10
        LDB  #10
        ADD
        JSR  kp1                        ; P1 = recs+24*ki+10 (NB: kp1 clobbers kt)
        LDA  ktlen                      ; set the loop counter AFTER kp1
        STA  kt
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
        MOVW ka,kcw                   ; x2 = kcw - 3
        LDW kb,#3
        JSR  k16sub
        JSR  ksw
        LDA  #0                         ; y1 = 0
        STA  kw
        STA  kw+1
        JSR  ksw
        MOVW ka,kch                   ; y2 = kch - 16
        LDW kb,#16
        JSR  k16sub
        JSR  ksw
        LDA  #$B2                       ; VWPORT vx1 vx2 vy1 vy2
        JSR  kput
        MOVW ka,kx                    ; vx1 = kx + 1
        LDW kb,#1
        JSR  k16add
        JSR  ksw
        MOVW ka,kx                    ; vx2 = kx + kcw - 2
        MOVW kb,kcw
        JSR  k16add
        MOVW ka,kw
        LDW kb,#2
        JSR  k16sub
        JSR  ksw
        LDW ka,#286                   ; vy1 = 286 - ky - kch   (286 = $011E)
        MOVW kb,ky
        JSR  k16sub                     ; 286 - ky
        MOVW ka,kw
        MOVW kb,kch
        JSR  k16sub                     ; - kch
        JSR  ksw
        LDW ka,#270                   ; vy2 = 270 - ky   (270 = $010E)
        MOVW kb,ky
        JSR  k16sub
        JSR  ksw
        RTS

; MOVE(kx,ky)
kmove_xy:
        LDA  #$10
        JSR  kput
        MOVW kw,kx
        JSR  ksw
        MOVW kw,ky
        JSR  ksw
        RTS
; RECT(kx1,ky1)
krect_11:
        LDA  #$34
        JSR  kput
        MOVW kw,kx1
        JSR  ksw
        MOVW kw,ky1
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
kri:    .fill 1                         ; k_raise: the index being raised
ktmp:   .fill 24                        ; k_raise: one record in transit
kcellx: .fill 1                         ; mouse: last cursor column (cell x)
kcelly: .fill 1                         ; mouse: last cursor row (cell y)
kev_arg:.fill 1                         ; SYS_WKARG payload: last key / click column
kgx:    .fill 2
kgy:    .fill 2
ktlen:  .fill 1
sinklst:.fill 1                         ; OUTCH mode-3 sink: target window's card list id
sinky:  .fill 2                         ; OUTCH mode-3 sink: text cursor y (window-local, drops 13/line)
wstate: .fill 16                        ; 4 windows x 4-byte state blob
recs:   .fill 96                        ; 4 windows x 24 bytes
