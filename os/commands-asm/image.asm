; image.asm — hand-coded IMAGE command (asm counterpart of os/commands/image.c).
;   IMAGE x y file               draw a P8I picture with its top-left at x,y
;   IMAGE READ x0 y0 x1 y1 file  grab that screen rectangle INTO a P8I file
; Behaviour-identical to the C build (same messages, same files, same pixels):
; header validation ("?NOT P8I" on bad magic/version/depth/truncation, "?No
; file" if missing), grab corners self-sort, an existing grab target is
; REPLACED, PGSYNC is issued first when the geometry engine answers its probe
; so grabs capture what the panel shows. The pixel loops are the point of this
; twin: the C build costs ~4.4k cycles a pixel through p8cc codegen; this loop
; is the same shape as BASIC's DOIMAGE (~0.6k), so a 256x256 draw is ~2 s.
; abspath inlined from touch.asm. Entry: P2 = arg tail. 16-bit numbers live in
; RAM words; the ×10 of the decimal parser is shift-and-add (SHL/ROL pairs).
;#use abi
;#use gfx

GLIDR   = $FF54                 ; graphics-language probe ('G' when fitted)
GLDATAR = $FF50                 ; its command FIFO: opcode 3 = PGSYNC
GLSTATR = $FF51                 ; bit6 = busy: wait the PGSYNC out

        .org $6A00
        TPA2L
        STA i_arg
        TPA2H
        STA i_arg+1
        JSR skipsp
        LDA (P2)                ; empty tail or -h -> usage
        LDB #0
        CMP
        JZ  i_use0
        LDB #13
        CMP
        JZ  i_use0
        LDB #'-'
        CMP
        JNZ i_disp
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ  i_use0
        LDB #'H'
        CMP
        JZ  i_use0
        DEP2                    ; a '-number' first arg: back onto the '-'
i_disp: LDA GID0                ; display probe: "PG" or ?No display
        LDB #'P'
        CMP
        JNZ i_nodisp
        LDA GID1
        LDB #'G'
        CMP
        JNZ i_nodisp
        LDA #0                  ; READ verb? (a draw starts with a number)
        STA i_rd
        LDA (P2)
        LDB #'r'
        CMP
        JZ  i_isrd
        LDB #'R'
        CMP
        JNZ i_args
i_isrd: LDA #1
        STA i_rd
i_rdsk: LDA (P2)                ; skip the verb word
        LDB #32
        CMP
        JZ  i_args
        LDB #0
        CMP
        JZ  i_args
        LDB #13
        CMP
        JZ  i_args
        JSR arginc
        JMP i_rdsk
i_args: JSR anum                ; x / x0
        LDA i_ok
        LDB #0
        CMP
        JZ  i_use1
        LDA i_num
        STA v_x
        LDA i_num+1
        STA v_x+1
        JSR anum                ; y / y0
        LDA i_ok
        LDB #0
        CMP
        JZ  i_use1
        LDA i_num
        STA v_y
        LDA i_num+1
        STA v_y+1
        LDA i_rd
        LDB #0
        CMP
        JZ  i_path
        JSR anum                ; x1
        LDA i_ok
        LDB #0
        CMP
        JZ  i_use1
        LDA i_num
        STA v_x1
        LDA i_num+1
        STA v_x1+1
        JSR anum                ; y1
        LDA i_ok
        LDB #0
        CMP
        JZ  i_use1
        LDA i_num
        STA v_y1
        LDA i_num+1
        STA v_y1+1
i_path: JSR skipsp
        LDA #<path              ; abspath(path, arg)
        STA ap_out
        LDA #>path
        STA ap_out+1
        LDA i_arg
        STA ap_a
        LDA i_arg+1
        STA ap_a+1
        JSR abspath
        LDA ap_n
        LDB #0
        CMP
        JZ  i_use1
        LDA i_rd
        LDB #0
        CMP
        JZ  draw
        JMP grab

i_use0: JSR usage
        RTS
i_use1: JSR usage
        RTS
i_nodisp:
        LDA #<m_nod
        TAP1L
        LDA #>m_nod
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; ---- DRAW: open, validate the 10-byte header, then the pixel loop ----------
draw:   LDA #<path
        TAP1L
        LDA #>path
        TAP1H
        LDA #0
        JSR FRESOLVE
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR FOPEN               ; C=1 -> not found
        JNC d_hdr
        LDA #<m_nof
        TAP1L
        LDA #>m_nof
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
d_hdr:  LDA #0
        JSR FGETB
        JC  d_bad
        LDB #'P'
        CMP
        JNZ d_bad
        LDA #0
        JSR FGETB
        JC  d_bad
        LDB #'8'
        CMP
        JNZ d_bad
        LDA #0
        JSR FGETB
        JC  d_bad
        LDB #'I'
        CMP
        JNZ d_bad
        LDA #0
        JSR FGETB
        JC  d_bad
        LDB #1                  ; version
        CMP
        JNZ d_bad
        LDA #0
        JSR FGETB
        JC  d_bad
        STA v_w
        LDA #0
        JSR FGETB
        JC  d_bad
        STA v_w+1
        LDA #0
        JSR FGETB
        JC  d_bad
        STA v_h
        LDA #0
        JSR FGETB
        JC  d_bad
        STA v_h+1
        LDA #0
        JSR FGETB
        JC  d_bad
        LDB #16                 ; depth $10 = RGB565
        CMP
        JNZ d_bad
        LDA #0
        JSR FGETB               ; reserved byte
        JC  d_bad
        LDA v_w                 ; w == 0 or h == 0 -> not P8I
        LDB v_w+1
        OR
        LDB #0
        CMP
        JZ  d_bad
        LDA v_h
        LDB v_h+1
        OR
        LDB #0
        CMP
        JZ  d_bad
        LDA v_x+1               ; xe = x + w  (hi first, then lo + carry)
        LDB v_w+1
        ADD
        STA v_xe+1
        LDA v_x
        LDB v_w
        ADD
        STA v_xe
        JNC d_ye
        LDA v_xe+1
        INC
        STA v_xe+1
d_ye:   LDA v_y+1               ; ye = y + h
        LDB v_h+1
        ADD
        STA v_ye+1
        LDA v_y
        LDB v_h
        ADD
        STA v_ye
        JNC d_py0
        LDA v_ye+1
        INC
        STA v_ye+1
d_py0:  LDA v_y
        STA v_py
        LDA v_y+1
        STA v_py+1
; --- row loop: write the Y pair once (nothing below touches GY0) ------------
d_row:  LDA v_py
        LDB v_ye
        CMP
        JNZ d_row1
        LDA v_py+1
        LDB v_ye+1
        CMP
        JNZ d_row1
        RTS                     ; py == ye -> done
d_row1: LDA v_py
        STA GY0
        LDA v_py+1
        STA GY0H
        LDA v_x
        STA v_px
        LDA v_x+1
        STA v_px+1
; --- pixel loop: FGETB x2 -> pen, X pair, wait idle, PLOT -------------------
d_px:   LDA v_px
        LDB v_xe
        CMP
        JNZ d_px1
        LDA v_px+1
        LDB v_xe+1
        CMP
        JNZ d_px1
        LDA v_py                ; row done: py += 1
        LDB #1
        ADD
        STA v_py
        JNC d_row
        LDA v_py+1
        INC
        STA v_py+1
        JMP d_row
d_px1:  LDA #0
        JSR FGETB               ; pixel low byte (C=1 -> truncated)
        JC  d_bad
        STA GCOL                ; clears the pen high byte
        LDA #0
        JSR FGETB
        JC  d_bad
        STA GCOLH
        LDA v_px
        STA GX0                 ; clears GX0's high byte
        LDA v_px+1
        STA GX0H
d_w:    LDA GSTAT               ; wait for the engine
        LDB #$80
        AND
        LDB #0
        CMP
        JNZ d_w
        LDA #GC_PIXW
        STA GCMD
        LDA v_px                ; px += 1
        LDB #1
        ADD
        STA v_px
        JNC d_px
        LDA v_px+1
        INC
        STA v_px+1
        JMP d_px
d_bad:  LDA #<m_bad
        TAP1L
        LDA #>m_bad
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; ---- GRAB: sort corners, PGSYNC, replace the file, header, pixel loop ------
grab:   LDA v_x1+1              ; if x1 < x0 (unsigned): swap
        LDB v_x+1
        CMP
        JNZ g_sx
        LDA v_x1
        LDB v_x
        CMP
g_sx:   JC  g_sy                ; C=1 -> x1 >= x0 -> no swap
        LDA v_x
        STA i_tmp
        LDA v_x1
        STA v_x
        LDA i_tmp
        STA v_x1
        LDA v_x+1
        STA i_tmp
        LDA v_x1+1
        STA v_x+1
        LDA i_tmp
        STA v_x1+1
g_sy:   LDA v_y1+1
        LDB v_y+1
        CMP
        JNZ g_sy1
        LDA v_y1
        LDB v_y
        CMP
g_sy1:  JC  g_dim
        LDA v_y
        STA i_tmp
        LDA v_y1
        STA v_y
        LDA i_tmp
        STA v_y1
        LDA v_y+1
        STA i_tmp
        LDA v_y1+1
        STA v_y+1
        LDA i_tmp
        STA v_y1+1
g_dim:  LDA v_x1                ; w = x1 - x0 + 1  (16-bit subtract: two's
        LDB v_x                 ;   complement add of -x0, then +1)
        SUB
        STA v_w
        LDA v_x1+1
        LDB v_x+1
        JC  g_d1                ; C=1 -> no borrow from the low byte
        SUB
        LDB #1
        SUB
        STA v_w+1
        JMP g_d2
g_d1:   SUB
        STA v_w+1
g_d2:   LDA v_w
        LDB #1
        ADD
        STA v_w
        JNC g_d3
        LDA v_w+1
        INC
        STA v_w+1
g_d3:   LDA v_y1                ; h = y1 - y0 + 1
        LDB v_y
        SUB
        STA v_h
        LDA v_y1+1
        LDB v_y+1
        JC  g_d4
        SUB
        LDB #1
        SUB
        STA v_h+1
        JMP g_d5
g_d4:   SUB
        STA v_h+1
g_d5:   LDA v_h
        LDB #1
        ADD
        STA v_h
        JNC g_sync
        LDA v_h+1
        INC
        STA v_h+1
g_sync: LDA GLIDR               ; GL engine fitted? PGSYNC first, so
        LDB #'G'                ;   the grab reads what the panel shows
        CMP
        JNZ g_open
        LDA #3
        STA GLDATAR
g_syw:  LDA GLSTATR             ; wait the verb out before grabbing
        LDB #64
        AND
        JNZ g_syw
g_open: LDA #<path              ; replace an existing file: resolve, delete,
        TAP1L                   ;   re-resolve (FDELETE walked the dir)
        LDA #>path
        TAP1H
        LDA #0
        JSR FRESOLVE
        LDA #0
        JSR FDELETE
        LDA #<path
        TAP1L
        LDA #>path
        TAP1H
        LDA #0
        JSR FRESOLVE
        LDA #0
        JSR FWOPEN
        LDA #'P'                ; the 10-byte self-describing header
        JSR FPUTB
        LDA #'8'
        JSR FPUTB
        LDA #'I'
        JSR FPUTB
        LDA #1
        JSR FPUTB
        LDA v_w
        JSR FPUTB
        LDA v_w+1
        JSR FPUTB
        LDA v_h
        JSR FPUTB
        LDA v_h+1
        JSR FPUTB
        LDA #16
        JSR FPUTB
        LDA #0
        JSR FPUTB
        LDA v_x1                ; xe = x1 + 1, ye = y1 + 1 (loop bounds)
        LDB #1
        ADD
        STA v_xe
        LDA v_x1+1
        JNC g_e1
        INC
g_e1:   STA v_xe+1
        LDA v_y1
        LDB #1
        ADD
        STA v_ye
        LDA v_y1+1
        JNC g_e2
        INC
g_e2:   STA v_ye+1
        LDA v_y
        STA v_py
        LDA v_y+1
        STA v_py+1
g_row:  LDA v_py
        LDB v_ye
        CMP
        JNZ g_row1
        LDA v_py+1
        LDB v_ye+1
        CMP
        JNZ g_row1
        LDA #0                  ; done: close (C=1 -> ?Disk full)
        JSR FCLOSE
        JNC g_ok
        LDA #<m_ful
        TAP1L
        LDA #>m_ful
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
g_ok:   RTS
g_row1: LDA v_py
        STA GY0
        LDA v_py+1
        STA GY0H
        LDA v_x
        STA v_px
        LDA v_x+1
        STA v_px+1
g_px:   LDA v_px
        LDB v_xe
        CMP
        JNZ g_px1
        LDA v_px+1
        LDB v_xe+1
        CMP
        JNZ g_px1
        LDA v_py                ; row done: py += 1
        LDB #1
        ADD
        STA v_py
        JNC g_row
        LDA v_py+1
        INC
        STA v_py+1
        JMP g_row
g_px1:  LDA v_px
        STA GX0
        LDA v_px+1
        STA GX0H
g_w1:   LDA GSTAT
        LDB #$80
        AND
        LDB #0
        CMP
        JNZ g_w1
        LDA #GC_PIXR
        STA GCMD
g_w2:   LDA GSTAT
        LDB #$80
        AND
        LDB #0
        CMP
        JNZ g_w2
        LDA GDATA               ; low byte, then high — little-endian P8I
        JSR FPUTB
        LDA GDATA
        JSR FPUTB
        LDA v_px
        LDB #1
        ADD
        STA v_px
        JNC g_px
        LDA v_px+1
        INC
        STA v_px+1
        JMP g_px

; ---- helpers ---------------------------------------------------------------
; skipsp: advance i_arg past spaces; leaves P2 on the first non-space
skipsp: LDA i_arg
        TAP2L
        LDA i_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ sk_d
        JSR argincm
        JMP skipsp
sk_d:   RTS
; arginc: i_arg += 1 AND step P2 (caller keeps using P2)
arginc: INP2
argincm:LDA i_arg
        LDB #1
        ADD
        STA i_arg
        JNC ai_d
        LDA i_arg+1
        INC
        STA i_arg+1
ai_d:   RTS
; anum: parse a signed decimal at i_arg -> i_num; i_ok = saw digits.
; num*10 = (num<<3) + (num<<1), 16-bit shifts as SHL/ROL pairs.
anum:   JSR skipsp
        LDA #0
        STA i_ok
        STA i_neg
        STA i_num
        STA i_num+1
        LDA (P2)
        LDB #'-'
        CMP
        JNZ an_lp
        LDA #1
        STA i_neg
        JSR arginc
an_lp:  LDA i_arg
        TAP2L
        LDA i_arg+1
        TAP2H
        LDA (P2)
        LDB #'0'
        CMP
        JC  an_c1               ; A >= '0'
        JMP an_end
an_c1:  LDB #':'                ; '9'+1
        CMP
        JC  an_end              ; A >= ':' -> not a digit
        LDB #'0'
        SUB
        STA i_dig
        LDA #1
        STA i_ok
        LDA i_num               ; t = num << 1
        SHL
        STA i_t
        LDA i_num+1
        ROL
        STA i_t+1
        LDA i_t                 ; num = t << 2  (i.e. num*8)
        SHL
        STA i_num
        LDA i_t+1
        ROL
        STA i_num+1
        LDA i_num
        SHL
        STA i_num
        LDA i_num+1
        ROL
        STA i_num+1
        LDA i_num+1             ; num += t  (now num*10)
        LDB i_t+1
        ADD
        STA i_num+1
        LDA i_num
        LDB i_t
        ADD
        STA i_num
        JNC an_a1
        LDA i_num+1
        INC
        STA i_num+1
an_a1:  LDA i_num               ; num += digit
        LDB i_dig
        ADD
        STA i_num
        JNC an_a2
        LDA i_num+1
        INC
        STA i_num+1
an_a2:  JSR argincm
        JMP an_lp
an_end: LDA i_neg
        LDB #0
        CMP
        JZ  an_rts
        LDA i_num+1             ; negate: ~num + 1
        LDB #$FF
        XOR
        STA i_num+1
        LDA i_num
        LDB #$FF
        XOR
        LDB #1
        ADD
        STA i_num
        JNC an_rts
        LDA i_num+1
        INC
        STA i_num+1
an_rts: RTS
usage:  LDA #<m_us1
        TAP1L
        LDA #>m_us1
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        LDA #<m_us2
        TAP1L
        LDA #>m_us2
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; abspath (from touch.asm): ap_out <- absolute path of the word at ap_a;
; ap_n = chars consumed. Clobbers A, B, P1, P2.
abspath:LDA #0
        STA ap_n
        LDA ap_a
        TAP2L
        LDA ap_a+1
        TAP2H
        LDA (P2)
        LDB #'/'
        CMP
        JZ ab_abs
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
        LDA #0
        JSR SYS_GETCWD
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
ab_sl:  LDA (P1)
        LDB #0
        CMP
        JZ ab_sld
        INP1
        JMP ab_sl
ab_sld: DEP1
        LDA (P1)
        INP1
        LDB #'/'
        CMP
        JZ ab_setp
        LDA #'/'
        STA (P1)+
        JMP ab_setp
ab_abs: LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
ab_setp:LDA ap_a
        TAP2L
        LDA ap_a+1
        TAP2H
ab_cp:  LDA (P2)
        LDB #0
        CMP
        JZ ab_dn
        LDB #13
        CMP
        JZ ab_dn
        LDB #32
        CMP
        JZ ab_dn
        STA (P1)+
        INP2
        LDA ap_n
        INC
        STA ap_n
        JMP ab_cp
ab_dn:  LDA #0
        STA (P1)
        RTS

m_us1:  .asciiz "usage: IMAGE x y file                draw a P8I picture at x,y"
m_us2:  .asciiz "       IMAGE READ x0 y0 x1 y1 file   grab the rectangle to a P8I"
m_nod:  .asciiz "?No display"
m_nof:  .asciiz "?No file"
m_bad:  .asciiz "?NOT P8I"
m_ful:  .asciiz "?Disk full"

i_arg:  .fill 2
i_rd:   .fill 1
i_ok:   .fill 1
i_neg:  .fill 1
i_dig:  .fill 1
i_tmp:  .fill 1
i_num:  .fill 2
i_t:    .fill 2
v_x:    .fill 2
v_y:    .fill 2
v_x1:   .fill 2
v_y1:   .fill 2
v_w:    .fill 2
v_h:    .fill 2
v_xe:   .fill 2
v_ye:   .fill 2
v_px:   .fill 2
v_py:   .fill 2
ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
path:   .fill 80
