; vi.asm — hand-coded VI command (asm counterpart of os/commands/vi.c).
;   VI name   modal VT100 screen editor (:wq to save+quit).
; Raw keys via BIOS CONIN ($0100, no echo), output via CONOUT ($0103). Flat line
; buffer (110 x 80); line i at line[i*80..]. All indices < 256 so byte math
; matches p8cc's 16-bit-unsigned comparisons on these small values. No shared
; include. BIOS: CONIN $0100, CONOUT $0103, FRESOLVE $0133, FOPEN $0124, FGETB
; $0127, FWOPEN $012A, FPUTB $012D, FCLOSE $0130. Entry: P2 = arg tail.
;#use abi

; Entry: P2 holds the argument tail (first char after the command name). The
; block below saves it to v_arg, then v_sk skips leading spaces so v_arg points
; at the first non-space char of the path argument.
        .org $6A00
        TPA2L
        STA v_arg
        TPA2H
        STA v_arg+1
v_sk:   LDA v_arg
        TAP2L
        LDA v_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ v_chk
        LDA v_arg
        LDB #1
        ADD
        STA v_arg
        JNC v_sk
        LDA v_arg+1
        INC
        STA v_arg+1
        JMP v_sk
; No path, a bare CR, or a "-h"/"-H" flag all fall through to v_usage.
v_chk:  LDA (P2)
        LDB #0
        CMP
        JZ v_usage
        LDB #13
        CMP
        JZ v_usage
        LDB #'-'
        CMP
        JNZ v_path
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ v_usage
        LDB #'H'
        CMP
        JZ v_usage
        LDA v_arg                     ; restore P2 to the '-' start
        TAP2L
        LDA v_arg+1
        TAP2H
v_path: LDA v_arg                     ; abspath(path, v_arg) — CWD-prefix if relative
        STA ap_a
        LDA v_arg+1
        STA ap_a+1
        LDA #<path
        STA ap_out
        LDA #>path
        STA ap_out+1
        JSR abspath
        LDA #<path
        STA ld_p
        LDA #>path
        STA ld_p+1
        JSR load
        LDA #0
        STA mode
        STA dirty
        STA done
        STA pend
        STA uop
        STA havepat
        JSR redraw
; ======================= main key loop =====================================
; Read a raw key each pass; dispatch to INSERT (mode==1) or NORMAL handler.
; Exits when done!=0 (set by :q/:wq/:x/:q!), clearing screen and homing cursor.
vi_loop:LDA done
        LDB #0
        CMP
        JNZ vi_quit
        JSR rawkey
        STA key
        LDA mode
        LDB #1
        CMP
        JZ vi_ins
        JMP vi_norm
vi_quit:JSR clrscr
        LDA #1
        STA g_r
        LDA #1
        STA g_c
        JSR gotoxy
        RTS
v_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; ---- INSERT mode ----------------------------------------------------------
; ESC leaves insert (stepping cx back one, like vi); CR/LF splits the line;
; BS/DEL deletes left; printable bytes (32..126) are inserted. Non-printables
; outside that range are ignored (fall through to nm_end).
vi_ins: LDA key
        LDB #27
        CMP
        JNZ im_cr
        LDA #0
        STA mode
        LDA cx
        LDB #0
        CMP
        JZ im_epc
        LDA cx
        DEC
        STA cx
im_epc: JSR status
        JSR placecur
        JMP nm_end
im_cr:  LDA key
        LDB #13
        CMP
        JZ im_split
        LDA key
        LDB #10
        CMP
        JZ im_split
        JMP im_bs
im_split:
        LDA #0
        STA uop
        JSR splitline
        JSR redraw
        JMP nm_end
im_bs:  LDA key
        LDB #8
        CMP
        JZ im_del
        LDA key
        LDB #127
        CMP
        JZ im_del
        JMP im_ins
im_del: LDA cx
        LDB #0
        CMP
        JZ nm_end
        LDA cx
        DEC
        STA cx
        JSR delchar
        LDA cy
        LDB top
        SUB
        STA dr_r
        JSR drawrow
        JSR placecur
        JMP nm_end
im_ins: LDA key
        LDB #32
        CMP
        JNC nm_end
        LDA key
        LDB #127
        CMP
        JC nm_end
        LDA key
        STA ic_c
        JSR inschar
        LDA cy
        LDB top
        SUB
        STA dr_r
        JSR drawrow
        JSR placecur
        JMP nm_end

; ---- NORMAL mode ----------------------------------------------------------
; pend==1 means the previous key was 'd', so we are waiting for the second key
; of a "dd" (delete line). Any other second key just clears pend and is ignored.
; Otherwise dispatch the single-key motions/commands: h l j k 0 $ G i a A o x
; d(d) u / n : each as its own nm_* clause.
vi_norm:LDA pend
        LDB #1
        CMP
        JNZ nm_h
        LDA #0
        STA pend
        LDA key
        LDB #'d'
        CMP
        JNZ nm_end
        JSR saveline
        LDA #3
        STA uop
        LDA cy
        STA uy
        JSR delline
        JSR redraw
        JMP nm_end
nm_h:   LDA key
        LDB #'h'
        CMP
        JNZ nm_l
        LDA cx
        LDB #0
        CMP
        JZ nm_end
        LDA cx
        DEC
        STA cx
        JSR placecur
        JMP nm_end
nm_l:   LDA key
        LDB #'l'
        CMP
        JNZ nm_j
        LDA cy
        STA ll_i
        JSR llen
        LDB #1
        SUB
        STA nm_t
        LDA cx
        LDB nm_t
        CMP
        JNC nm_lok
        JMP nm_end
nm_lok: LDA cx
        INC
        STA cx
        JSR placecur
        JMP nm_end
nm_j:   LDA key
        LDB #'j'
        CMP
        JNZ nm_k
        LDA nlines
        LDB #1
        SUB
        STA nm_t
        LDA cy
        LDB nm_t
        CMP
        JNC nm_jok
        JMP nm_end
nm_jok: LDA cy
        INC
        STA cy
        JSR clampx
        JSR scroll
        LDB #0
        CMP
        JZ nm_jpc
        JSR redraw
        JMP nm_end
nm_jpc: JSR placecur
        JMP nm_end
nm_k:   LDA key
        LDB #'k'
        CMP
        JNZ nm_0
        LDA cy
        LDB #0
        CMP
        JZ nm_end
        LDA cy
        DEC
        STA cy
        JSR clampx
        JSR scroll
        LDB #0
        CMP
        JZ nm_kpc
        JSR redraw
        JMP nm_end
nm_kpc: JSR placecur
        JMP nm_end
nm_0:   LDA key
        LDB #'0'
        CMP
        JNZ nm_dol
        LDA #0
        STA cx
        JSR placecur
        JMP nm_end
nm_dol: LDA key
        LDB #'$'
        CMP
        JNZ nm_G
        LDA cy
        STA ll_i
        JSR llen
        STA cx
        LDA cx
        LDB #0
        CMP
        JZ nm_dpc
        LDA cx
        DEC
        STA cx
nm_dpc: JSR placecur
        JMP nm_end
nm_G:   LDA key
        LDB #'G'
        CMP
        JNZ nm_i
        LDA nlines
        LDB #1
        SUB
        STA cy
        JSR clampx
        JSR scroll
        LDB #0
        CMP
        JZ nm_Gpc
        JSR redraw
        JMP nm_end
nm_Gpc: JSR placecur
        JMP nm_end
nm_i:   LDA key
        LDB #'i'
        CMP
        JNZ nm_a
        JSR snap1
        LDA #1
        STA mode
        JSR status
        JSR placecur
        JMP nm_end
nm_a:   LDA key
        LDB #'a'
        CMP
        JNZ nm_A
        JSR snap1
        LDA cy
        STA ll_i
        JSR llen
        LDB #0
        CMP
        JZ nm_anc
        LDA cx
        INC
        STA cx
nm_anc: JSR clampx
        LDA #1
        STA mode
        JSR status
        JSR placecur
        JMP nm_end
nm_A:   LDA key
        LDB #'A'
        CMP
        JNZ nm_o
        JSR snap1
        LDA cy
        STA ll_i
        JSR llen
        STA cx
        LDA #1
        STA mode
        JSR status
        JSR placecur
        JMP nm_end
nm_o:   LDA key
        LDB #'o'
        CMP
        JNZ nm_x
        LDA #2
        STA uop
        LDA cy
        INC
        STA uy
        JSR opendown
        LDA #1
        STA mode
        JSR redraw
        JMP nm_end
nm_x:   LDA key
        LDB #'x'
        CMP
        JNZ nm_d
        JSR snap1
        JSR delchar
        JSR clampx
        LDA cy
        LDB top
        SUB
        STA dr_r
        JSR drawrow
        JSR placecur
        JMP nm_end
nm_d:   LDA key
        LDB #'d'
        CMP
        JNZ nm_u
        LDA #1
        STA pend
        JMP nm_end
nm_u:   LDA key
        LDB #'u'
        CMP
        JNZ nm_sl
        JSR undo
        JMP nm_end
nm_sl:  LDA key
        LDB #'/'
        CMP
        JNZ nm_n
        JSR getpat
        LDB #0
        CMP
        JZ nm_sl_rd
        LDA havepat
        LDB #0
        CMP
        JZ nm_sl_rd
        JSR search
        LDB #0
        CMP
        JZ nm_sl_nf
        JSR redraw
        JMP nm_end
nm_sl_nf:
        JSR redraw
        LDA #<s_nf
        STA os_p
        LDA #>s_nf
        STA os_p+1
        JSR msg24
        JSR placecur
        JMP nm_end
nm_sl_rd:
        JSR redraw
        JMP nm_end
nm_n:   LDA key
        LDB #'n'
        CMP
        JNZ nm_col
        LDA havepat
        LDB #0
        CMP
        JZ nm_end
        JSR search
        LDB #0
        CMP
        JZ nm_n_nf
        JSR redraw
        JMP nm_end
nm_n_nf:LDA #<s_nf
        STA os_p
        LDA #>s_nf
        STA os_p+1
        JSR msg24
        JSR placecur
        JMP nm_end
nm_col: LDA key
        LDB #':'
        CMP
        JNZ nm_end
        JSR docmd
        LDA done
        LDB #0
        CMP
        JNZ nm_end
        JSR redraw
nm_end: JMP vi_loop

; ======================= terminal primitives ===============================
; rawkey: blocking read of one key via BIOS CONIN, no echo. Returns byte in A.
; Clobbers P1 (and P1/P2 per CONIN). outc: write byte in A via CONOUT.
; outs: write NUL-terminated string at os_p. outn: print on_n as decimal.
; esc/clrscr/clreol/gotoxy: emit the matching VT100/ANSI escape sequences.
rawkey: LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR CONIN
        RTS
outc:   STA oc
        LDA #0
        TAP1L
        TAP1H
        LDA oc
        JSR CONOUT
        RTS
outs:   LDA #0
        STA osk
os_l:   LDA os_p
        LDB osk
        ADD
        TAP1L
        LDA os_p+1
        JNC os1
        INC
os1:    TAP1H
        LDA (P1)
        LDB #0
        CMP
        JZ os_d
        JSR outc
        LDA osk
        INC
        STA osk
        JMP os_l
os_d:   RTS
; outn: print on_n (0..255) as decimal. Values < 10 print one digit directly;
; larger values recurse on the quotient (dm10 divides on_n by 10) then print the
; remainder digit, so digits come out most-significant first.
outn:   LDA on_n
        LDB #10
        CMP
        JC on_rec
        LDA on_n
        LDB #48
        ADD
        JSR outc
        RTS
on_rec: LDA on_n
        STA dv
        JSR dm10
        LDA dvr
        PHA
        LDA dvq
        STA on_n
        JSR outn
        PLA
        LDB #48
        ADD
        JSR outc
        RTS
; dm10: divide dv by 10 by repeated subtraction. Result: dvq=quotient, dvr=rem.
dm10:   LDA #0
        STA dvq
dm_l:   LDA dv
        LDB #10
        CMP
        JNC dm_d
        LDA dv
        LDB #10
        SUB
        STA dv
        LDA dvq
        INC
        STA dvq
        JMP dm_l
dm_d:   LDA dv
        STA dvr
        RTS
esc:    LDA #27
        JSR outc
        LDA #'['
        JSR outc
        RTS
clrscr: JSR esc
        LDA #'2'
        JSR outc
        LDA #'J'
        JSR outc
        RTS
clreol: JSR esc
        LDA #'K'
        JSR outc
        RTS
; gotoxy: move cursor to row g_r, col g_c (1-based) via ESC [ row ; col H.
; The literal 59 emitted between the numbers is ';' (kept as a number here to
; avoid a ';' in source, which the assembler would strip as a comment).
gotoxy: JSR esc
        LDA g_r
        STA on_n
        JSR outn
        LDA #59
        JSR outc
        LDA g_c
        STA on_n
        JSR outn
        LDA #'H'
        JSR outc
        RTS
msg24:  LDA #24
        STA g_r
        LDA #1
        STA g_c
        JSR gotoxy
        JSR outs
        JSR clreol
        RTS

; ======================= line buffer helpers ===============================
; laddr: compute the 16-bit address of column va_c on line va_i and load it into
; P1. Address = line + va_i*80 + va_c. va_i*80 is built by repeated +80 into the
; 16-bit accumulator vat (va_ml loop), then va_c and the base label `line` are
; added; vacar carries the low-byte overflow into the high byte. Clobbers A/B/P1.
laddr:  LDA #0
        STA vat
        STA vat+1
        LDA va_i
        STA van
va_ml:  LDA van
        LDB #0
        CMP
        JZ va_md
        LDA vat
        LDB #80
        ADD
        STA vat
        JNC va_1
        LDA vat+1
        INC
        STA vat+1
va_1:   LDA van
        DEC
        STA van
        JMP va_ml
va_md:  LDA vat
        LDB va_c
        ADD
        STA vat
        JNC va_2
        LDA vat+1
        INC
        STA vat+1
va_2:   LDA vat
        LDB #<line
        ADD
        STA vat
        LDA #0
        JNC va_3
        LDA #1
va_3:   STA vacar
        LDA vat+1
        LDB #>line
        ADD
        LDB vacar
        ADD
        STA vat+1
        LDA vat
        TAP1L
        LDA vat+1
        TAP1H
        RTS
; llen: return in A the length (chars before the NUL) of line ll_i. Clobbers P1.
llen:   LDA ll_i
        STA va_i
        LDA #0
        STA va_c
        JSR laddr
        LDA #0
        STA ll_n
lln_l:  LDA (P1)
        LDB #0
        CMP
        JZ lln_d
        INP1
        LDA ll_n
        INC
        STA ll_n
        JMP lln_l
lln_d:  LDA ll_n
        RTS
; clampx: if cx runs past the end of the current line, pull it back to the last
; valid column (line length). Used after vertical moves onto a shorter line.
clampx: LDA cy
        STA ll_i
        JSR llen
        STA cxn
        LDA cx
        LDB cxn
        CMP
        JNC cx_ok
        JZ cx_ok
        LDA cxn
        STA cx
cx_ok:  RTS

; ======================= load / save =======================================
; load: read the file whose path is at ld_p into the line buffer. Resets cursor
; and scroll state. Uses BIOS FOPEN with a fixed read buffer at $FC00 (P1). If
; FOPEN fails (JNC ld_read taken only on success/carry-clear), start with one
; empty line. LF ('\n') ends a line; CR ('\r') is dropped; columns past 79 are
; truncated; the buffer holds at most 110 lines. Trailing partial line and the
; empty-file case are normalized so nlines >= 1 on return.
load:   LDA ld_p
        TAP1L
        LDA ld_p+1
        TAP1H
        LDA #0
        JSR FRESOLVE
        LDA #0
        STA nlines
        STA cx
        STA cy
        STA top
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR FOPEN
        JNC ld_read
        LDA #1
        STA nlines
        LDA #0
        STA va_i
        STA va_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA #1
        RTS
ld_read:LDA #0
        STA ld_col
ld_l:   LDA #0
        JSR FGETB
        JC ld_fin
        STA ld_c
        LDB #10
        CMP
        JZ ld_nl
        LDA ld_c
        LDB #13
        CMP
        JZ ld_l
        LDA ld_col
        LDB #79
        CMP
        JC ld_l
        LDA nlines
        STA va_i
        LDA ld_col
        STA va_c
        JSR laddr
        LDA ld_c
        STA (P1)
        LDA ld_col
        INC
        STA ld_col
        JMP ld_l
ld_nl:  LDA nlines
        STA va_i
        LDA ld_col
        STA va_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA nlines
        INC
        STA nlines
        LDA #0
        STA ld_col
        LDA nlines
        LDB #110
        CMP
        JC ld_ret0
        JMP ld_l
ld_fin: LDA nlines
        STA va_i
        LDA ld_col
        STA va_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA ld_col
        LDB #0
        CMP
        JNZ ld_inc
        LDA nlines
        LDB #0
        CMP
        JZ ld_inc
        JMP ld_chk0
ld_inc: LDA nlines
        INC
        STA nlines
ld_chk0:LDA nlines
        LDB #0
        CMP
        JNZ ld_ret0
        LDA #1
        STA nlines
        LDA #0
        STA va_i
        STA va_c
        JSR laddr
        LDA #0
        STA (P1)
ld_ret0:LDA #0
        RTS
; save: write all nlines lines to the path at sv_p via BIOS FWOPEN/FPUTB/FCLOSE.
; Each line's chars are emitted up to its NUL, then a single LF (Unix newline).
; Clears dirty on success. sv_p2 is a working copy of the line pointer because
; FPUTB clobbers P1/P2, so it is reloaded before every byte.
save:   LDA sv_p
        TAP1L
        LDA sv_p+1
        TAP1H
        LDA #0
        JSR FRESOLVE
        LDA #0
        JSR FWOPEN
        LDA #0
        STA sv_i
sv_il:  LDA sv_i
        LDB nlines
        CMP
        JC sv_done
        LDA sv_i
        STA va_i
        LDA #0
        STA va_c
        JSR laddr
        TPA1L
        STA sv_p2
        TPA1H
        STA sv_p2+1
sv_cl:  LDA sv_p2
        TAP1L
        LDA sv_p2+1
        TAP1H
        LDA (P1)
        LDB #0
        CMP
        JZ sv_eol
        STA sv_c
        LDA #0
        TAP1L
        TAP1H
        LDA sv_c
        JSR FPUTB
        LDA sv_p2
        LDB #1
        ADD
        STA sv_p2
        JNC sv_c1
        LDA sv_p2+1
        INC
        STA sv_p2+1
sv_c1:  JMP sv_cl
sv_eol: LDA #0
        TAP1L
        TAP1H
        LDA #10                 ; LF (was CRLF; conform to Unix)
        JSR FPUTB
        LDA sv_i
        INC
        STA sv_i
        JMP sv_il
sv_done:LDA #0
        JSR FCLOSE
        LDA #0
        STA dirty
        RTS

; ======================= redraw ============================================
; drawrow: redraw one screen row dr_r (0..22). Screen row = dr_r+1; the buffer
; line shown there is top+dr_r. Rows past the last line print a '~' like vi.
; Clears to end of line afterward.
drawrow:LDA dr_r
        INC
        STA g_r
        LDA #1
        STA g_c
        JSR gotoxy
        LDA top
        LDB dr_r
        ADD
        STA dr_li
        LDA dr_li
        LDB nlines
        CMP
        JC dr_tilde
        LDA dr_li
        STA va_i
        LDA #0
        STA va_c
        JSR laddr
        TPA1L
        STA dptr
        TPA1H
        STA dptr+1
dr_pl:  LDA dptr
        TAP1L
        LDA dptr+1
        TAP1H
        LDA (P1)
        LDB #0
        CMP
        JZ dr_eol
        JSR outc
        LDA dptr
        LDB #1
        ADD
        STA dptr
        JNC dr_p1
        LDA dptr+1
        INC
        STA dptr+1
dr_p1:  JMP dr_pl
dr_tilde:
        LDA #'~'
        JSR outc
dr_eol: JSR clreol
        RTS
; status: draw the status line (screen row 24): "-- INSERT --" when in insert
; mode (else blanks), then the file path, then " [+]" if the buffer is dirty.
status: LDA #24
        STA g_r
        LDA #1
        STA g_c
        JSR gotoxy
        LDA mode
        LDB #1
        CMP
        JNZ st_norm
        LDA #<s_ins
        STA os_p
        LDA #>s_ins
        STA os_p+1
        JSR outs
        JMP st_path
st_norm:LDA #<s_blank
        STA os_p
        LDA #>s_blank
        STA os_p+1
        JSR outs
st_path:LDA #<path
        STA os_p
        LDA #>path
        STA os_p+1
        JSR outs
        LDA dirty
        LDB #0
        CMP
        JZ st_eol
        LDA #<s_plus
        STA os_p
        LDA #>s_plus
        STA os_p+1
        JSR outs
st_eol: JSR clreol
        RTS
; placecur: position the terminal cursor at the logical cursor (cx,cy). Screen
; row = cy-top+1, screen col = cx+1 (both 1-based for gotoxy).
placecur:
        LDA cy
        LDB top
        SUB
        INC
        STA g_r
        LDA cx
        INC
        STA g_c
        JSR gotoxy
        RTS
; redraw: repaint the whole screen: clear, draw text rows 0..22, status, cursor.
redraw: JSR clrscr
        LDA #0
        STA rd_r
rd_l:   LDA rd_r
        LDB #23
        CMP
        JC rd_d
        LDA rd_r
        STA dr_r
        JSR drawrow
        LDA rd_r
        INC
        STA rd_r
        JMP rd_l
rd_d:   JSR status
        JSR placecur
        RTS
; scroll: adjust the viewport origin `top` so the cursor line cy stays visible
; in the 23-row text window (rows top..top+22). If cy < top, snap top to cy; if
; cy is below the window, set top = cy-22. Returns A=1 when top changed (caller
; must redraw), A=0 when no scroll was needed (caller only repositions cursor).
scroll: LDA cy
        LDB top
        CMP
        JNC sc_lt
        LDA top
        LDB #22
        ADD
        STA sc_t
        LDA cy
        LDB sc_t
        CMP
        JZ sc_no
        JNC sc_no
        LDA cy
        LDB #22
        SUB
        STA top
        LDA #1
        RTS
sc_lt:  LDA cy
        STA top
        LDA #1
        RTS
sc_no:  LDA #0
        RTS

; ======================= editing ===========================================
; inschar: insert char ic_c at column cx of the current line, shifting the tail
; right by one and re-terminating. No-op if the line is already at the 78-char
; cap (ic_ret). Advances cx and sets dirty.
inschar:LDA cy
        STA ll_i
        JSR llen
        STA ic_n
        LDA ic_n
        LDB #78
        CMP
        JC ic_ret
        LDA ic_n
        STA ic_j
ic_l:   LDA ic_j
        LDB cx
        CMP
        JZ ic_set
        JNC ic_set
        LDA cy
        STA va_i
        LDA ic_j
        LDB #1
        SUB
        STA va_c
        JSR laddr
        LDA (P1)
        STA ic_ch
        LDA cy
        STA va_i
        LDA ic_j
        STA va_c
        JSR laddr
        LDA ic_ch
        STA (P1)
        LDA ic_j
        DEC
        STA ic_j
        JMP ic_l
ic_set: LDA cy
        STA va_i
        LDA cx
        STA va_c
        JSR laddr
        LDA ic_c
        STA (P1)
        LDA cy
        STA va_i
        LDA ic_n
        INC
        STA va_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA cx
        INC
        STA cx
        LDA #1
        STA dirty
ic_ret: RTS
; delchar: delete the char at column cx of the current line, shifting the tail
; left over it. No-op if cx is past the line end. Sets dirty when a char moved.
delchar:LDA cy
        STA ll_i
        JSR llen
        STA dc_n
        LDA cx
        LDB dc_n
        CMP
        JC dc_ret
        LDA cx
        STA dc_j
dc_l:   LDA cy
        STA va_i
        LDA dc_j
        STA va_c
        JSR laddr
        LDA (P1)
        LDB #0
        CMP
        JZ dc_done
        LDA cy
        STA va_i
        LDA dc_j
        INC
        STA va_c
        JSR laddr
        LDA (P1)
        STA dc_c
        LDA cy
        STA va_i
        LDA dc_j
        STA va_c
        JSR laddr
        LDA dc_c
        STA (P1)
        LDA dc_j
        INC
        STA dc_j
        JMP dc_l
dc_done:LDA #1
        STA dirty
dc_ret: RTS
; copyline: copy line cp_s to line cp_d, byte by byte including the NUL.
; Used to shift whole lines up/down when opening, deleting, or splitting lines.
copyline:
        LDA #0
        STA cl_k
cl_l:   LDA cp_s
        STA va_i
        LDA cl_k
        STA va_c
        JSR laddr
        LDA (P1)
        STA cl_c
        LDA cp_d
        STA va_i
        LDA cl_k
        STA va_c
        JSR laddr
        LDA cl_c
        STA (P1)
        LDA cl_c
        LDB #0
        CMP
        JZ cl_d
        LDA cl_k
        INC
        STA cl_k
        JMP cl_l
cl_d:   RTS
; opendown: open a new empty line below cy (vi 'o'). Shifts lines cy+1..end down
; one slot, blanks the new line, bumps nlines, moves the cursor onto it, cx=0.
; No-op if the buffer is full (110 lines). Sets dirty.
opendown:
        LDA nlines
        LDB #110
        CMP
        JC od_ret
        LDA nlines
        STA od_i
od_l:   LDA cy
        INC
        STA od_t
        LDA od_i
        LDB od_t
        CMP
        JZ od_set
        JNC od_set
        LDA od_i
        STA cp_d
        LDA od_i
        LDB #1
        SUB
        STA cp_s
        JSR copyline
        LDA od_i
        DEC
        STA od_i
        JMP od_l
od_set: LDA cy
        INC
        STA va_i
        LDA #0
        STA va_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA nlines
        INC
        STA nlines
        LDA cy
        INC
        STA cy
        LDA #0
        STA cx
        LDA #1
        STA dirty
od_ret: RTS
; delline: delete line cy (vi 'dd'). Shifts lines below it up one slot and
; decrements nlines; if cy was the last line, cy steps back one. When only one
; line exists (dl_one) the line is just blanked. Sets cx=0 and dirty.
delline:LDA nlines
        LDB #1
        CMP
        JZ dl_one
        LDA cy
        STA dl_i
dl_l:   LDA nlines
        LDB #1
        SUB
        STA dl_t
        LDA dl_i
        LDB dl_t
        CMP
        JC dl_dec
        LDA dl_i
        STA cp_d
        LDA dl_i
        INC
        STA cp_s
        JSR copyline
        LDA dl_i
        INC
        STA dl_i
        JMP dl_l
dl_dec: LDA nlines
        DEC
        STA nlines
        LDA cy
        LDB nlines
        CMP
        JNC dl_cx
        LDA nlines
        LDB #1
        SUB
        STA cy
dl_cx:  LDA #0
        STA cx
        LDA #1
        STA dirty
        RTS
dl_one: LDA #0
        STA va_i
        STA va_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA #0
        STA cx
        LDA #1
        STA dirty
        RTS
; splitline: break the current line at cx (Enter in insert mode). Shifts lines
; below cy down one to make room, copies the tail (from cx) into the new line
; cy+1, truncates the current line at cx, then moves the cursor to col 0 of the
; new line. No-op if the buffer is full. Sets dirty.
splitline:
        LDA nlines
        LDB #110
        CMP
        JC sp_ret
        LDA nlines
        STA sp_i
sp_l:   LDA cy
        INC
        STA sp_t
        LDA sp_i
        LDB sp_t
        CMP
        JZ sp_split
        JNC sp_split
        LDA sp_i
        STA cp_d
        LDA sp_i
        LDB #1
        SUB
        STA cp_s
        JSR copyline
        LDA sp_i
        DEC
        STA sp_i
        JMP sp_l
sp_split:
        LDA #0
        STA sp_k
sps_l:  LDA cx
        LDB sp_k
        ADD
        STA sp_jc
        LDA cy
        STA va_i
        LDA sp_jc
        STA va_c
        JSR laddr
        LDA (P1)
        STA sp_c
        LDB #0
        CMP
        JZ sps_d
        LDA cy
        INC
        STA va_i
        LDA sp_k
        STA va_c
        JSR laddr
        LDA sp_c
        STA (P1)
        LDA sp_k
        INC
        STA sp_k
        JMP sps_l
sps_d:  LDA cy
        INC
        STA va_i
        LDA sp_k
        STA va_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA cy
        STA va_i
        LDA cx
        STA va_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA nlines
        INC
        STA nlines
        LDA cy
        INC
        STA cy
        LDA #0
        STA cx
        LDA #1
        STA dirty
sp_ret: RTS

; ======================= undo ==============================================
; Single-level undo. `uop` records the kind of the last undoable edit:
;   0 = nothing to undo
;   1 = in-place line edit  -> usave holds the pre-edit text of line uy; undo
;                              copies usave back and restores cursor ux,uy
;   2 = line opened (o)      -> undo deletes line uy
;   3 = line deleted (dd)    -> usave holds the removed text; undo re-inserts it
;                              at uy
; usave is the 80-byte scratch line holding the saved copy.
; saveline: copy the current line (cy) into usave. Uses (P1)+ auto-increment.
saveline:
        LDA cy
        STA va_i
        LDA #0
        STA va_c
        JSR laddr
        TPA1L
        STA sl_p
        TPA1H
        STA sl_p+1
        LDA sl_p
        TAP2L
        LDA sl_p+1
        TAP2H
        LDA #<usave
        TAP1L
        LDA #>usave
        TAP1H
sl_l:   LDA (P2)
        STA (P1)+
        LDB #0
        CMP
        JZ sl_d
        INP2
        JMP sl_l
sl_d:   RTS
; snap1: take an undo snapshot before an in-place edit: save the line and record
; uop=1 with the current cursor (uy=cy, ux=cx).
snap1:  JSR saveline
        LDA #1
        STA uop
        LDA cy
        STA uy
        LDA cx
        STA ux
        RTS
; insline: insert a new line at index in_y, filling it from usave. Shifts lines
; in_y..end down one and bumps nlines. No-op if the buffer is full. Used by undo
; of a 'dd' (uop==3) to bring the deleted line back.
insline:LDA nlines
        LDB #110
        CMP
        JC il_ret
        LDA nlines
        STA il_i
il_l:   LDA il_i
        LDB in_y
        CMP
        JZ il_set
        JNC il_set
        LDA il_i
        STA cp_d
        LDA il_i
        LDB #1
        SUB
        STA cp_s
        JSR copyline
        LDA il_i
        DEC
        STA il_i
        JMP il_l
il_set: LDA in_y
        STA va_i
        LDA #0
        STA va_c
        JSR laddr
        TPA1L
        STA sl_p
        TPA1H
        STA sl_p+1
        LDA #<usave
        TAP2L
        LDA #>usave
        TAP2H
        LDA sl_p
        TAP1L
        LDA sl_p+1
        TAP1H
ils_l:  LDA (P2)
        STA (P1)+
        LDB #0
        CMP
        JZ ils_d
        INP2
        JMP ils_l
ils_d:  LDA nlines
        INC
        STA nlines
il_ret: RTS
; undo: reverse the last edit per the uop code (see table above). Prints
; "nothing to undo" when uop==0. Consumes uop (sets it to 0) so undo is single
; level, then rescrolls and repaints. Note it marks the buffer dirty.
undo:   LDA uop
        LDB #0
        CMP
        JNZ un_go
        LDA #<s_noundo
        STA os_p
        LDA #>s_noundo
        STA os_p+1
        JSR msg24
        JSR placecur
        RTS
un_go:  LDA uop
        STA un_t
        LDA #0
        STA uop
        LDA un_t
        LDB #1
        CMP
        JNZ un_c2
        LDA uy
        STA va_i
        LDA #0
        STA va_c
        JSR laddr
        TPA1L
        STA sl_p
        TPA1H
        STA sl_p+1
        LDA #<usave
        TAP2L
        LDA #>usave
        TAP2H
        LDA sl_p
        TAP1L
        LDA sl_p+1
        TAP1H
un1_l:  LDA (P2)
        STA (P1)+
        LDB #0
        CMP
        JZ un1_d
        INP2
        JMP un1_l
un1_d:  LDA uy
        STA cy
        LDA ux
        STA cx
        JSR clampx
        JMP un_fin
un_c2:  LDA un_t
        LDB #2
        CMP
        JNZ un_c3
        LDA uy
        STA cy
        JSR delline
        JMP un_fin
un_c3:  LDA un_t
        LDB #3
        CMP
        JNZ un_fin
        LDA uy
        STA in_y
        JSR insline
        LDA uy
        STA cy
        LDA #0
        STA cx
un_fin: LDA #1
        STA dirty
        JSR scroll
        JSR redraw
        RTS

; ======================= search ============================================
; matchat: test whether pattern `pat` matches line ma_i starting at column ma_j.
; Walks pat until its NUL (full match -> A=1) or a mismatched char (A=0).
matchat:LDA #0
        STA ma_m
mat_l:  LDA #<pat
        LDB ma_m
        ADD
        TAP2L
        LDA #>pat
        JNC ma1
        INC
ma1:    TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ ma_yes
        LDA ma_j
        LDB ma_m
        ADD
        STA ma_jc
        LDA ma_i
        STA va_i
        LDA ma_jc
        STA va_c
        JSR laddr
        LDA (P1)
        STA ma_lc
        LDA #<pat
        LDB ma_m
        ADD
        TAP2L
        LDA #>pat
        JNC ma2
        INC
ma2:    TAP2H
        LDA (P2)
        LDB ma_lc
        CMP
        JNZ ma_no
        LDA ma_m
        INC
        STA ma_m
        JMP mat_l
ma_yes: LDA #1
        RTS
ma_no:  LDA #0
        RTS
; findfrom: scan forward from line ff_sy, column ff_sx for `pat`. On the first
; line the scan starts at ff_sx; later lines start at column 0. On a hit, sets
; cy,cx to the match position and returns A=1; returns A=0 if none through EOF.
findfrom:
        LDA ff_sy
        STA ff_i
ff_il:  LDA ff_i
        LDB nlines
        CMP
        JC ff_no
        LDA ff_i
        LDB ff_sy
        CMP
        JNZ ff_j0
        LDA ff_sx
        STA ff_j
        JMP ff_jl
ff_j0:  LDA #0
        STA ff_j
ff_jl:  LDA ff_i
        STA va_i
        LDA ff_j
        STA va_c
        JSR laddr
        LDA (P1)
        LDB #0
        CMP
        JZ ff_in
        LDA ff_i
        STA ma_i
        LDA ff_j
        STA ma_j
        JSR matchat
        LDB #0
        CMP
        JZ ff_jn
        LDA ff_i
        STA cy
        LDA ff_j
        STA cx
        LDA #1
        RTS
ff_jn:  LDA ff_j
        INC
        STA ff_j
        JMP ff_jl
ff_in:  LDA ff_i
        INC
        STA ff_i
        JMP ff_il
ff_no:  LDA #0
        RTS
; search: find the next occurrence of `pat` after the cursor, wrapping to the
; top of the buffer if not found ahead. Returns A=1 on a hit (cursor moved),
; A=0 if the pattern is nowhere in the buffer.
search: LDA cy
        STA ff_sy
        LDA cx
        INC
        STA ff_sx
        JSR findfrom
        LDB #0
        CMP
        JNZ se_yes
        LDA #0
        STA ff_sy
        STA ff_sx
        JSR findfrom
        LDB #0
        CMP
        JNZ se_yes
        LDA #0
        RTS
se_yes: LDA #1
        RTS
; getpat: prompt on row 24 with '/' and read a search pattern into `pat` (max 38
; chars, echoing keystrokes, BS/DEL erases). ESC cancels and returns A=0. On
; Enter, NUL-terminates pat; a non-empty pattern sets havepat. Returns A=1 when
; the prompt completed (whether or not text was entered).
getpat: LDA #24
        STA g_r
        LDA #1
        STA g_c
        JSR gotoxy
        LDA #'/'
        JSR outc
        JSR clreol
        LDA #0
        STA gp_k
        JSR rawkey
        STA gp_c
gp_l:   LDA gp_c
        LDB #13
        CMP
        JZ gp_done
        LDA gp_c
        LDB #10
        CMP
        JZ gp_done
        LDA gp_c
        LDB #27
        CMP
        JNZ gp_bs
        LDA #0
        RTS
gp_bs:  LDA gp_c
        LDB #8
        CMP
        JZ gp_del
        LDA gp_c
        LDB #127
        CMP
        JZ gp_del
        LDA gp_k
        LDB #38
        CMP
        JC gp_next
        LDA #<pat
        LDB gp_k
        ADD
        TAP1L
        LDA #>pat
        JNC gp1
        INC
gp1:    TAP1H
        LDA gp_c
        STA (P1)
        LDA gp_k
        INC
        STA gp_k
        LDA gp_c
        JSR outc
        JMP gp_next
gp_del: LDA gp_k
        LDB #0
        CMP
        JZ gp_next
        LDA gp_k
        DEC
        STA gp_k
        LDA #8
        JSR outc
        LDA #32
        JSR outc
        LDA #8
        JSR outc
gp_next:JSR rawkey
        STA gp_c
        JMP gp_l
gp_done:LDA #<pat
        LDB gp_k
        ADD
        TAP1L
        LDA #>pat
        JNC gp2
        INC
gp2:    TAP1H
        LDA #0
        STA (P1)
        LDA gp_k
        LDB #0
        CMP
        JZ gp_r1
        LDA #1
        STA havepat
gp_r1:  LDA #1
        RTS

; ======================= ':' command line ==================================
; docmd: prompt on row 24 with ':' and read a colon command into `cmd` (max 38
; chars, echoed; BS/DEL erases; ESC cancels). Recognized commands:
;   q      quit (refuses with a message if the buffer is dirty)
;   q!     quit discarding changes
;   w      write to `path`
;   wq / x write then quit
; Anything else prints "?unknown command". Sets `done` for the quitting cases;
; the main loop checks `done` and exits.
docmd:  LDA #24
        STA g_r
        LDA #1
        STA g_c
        JSR gotoxy
        LDA #':'
        JSR outc
        JSR clreol
        LDA #0
        STA dc_k
        JSR rawkey
        STA dc_c
dcl:    LDA dc_c
        LDB #13
        CMP
        JZ dc_go
        LDA dc_c
        LDB #10
        CMP
        JZ dc_go
        LDA dc_c
        LDB #27
        CMP
        JNZ dc_bs
        RTS
dc_bs:  LDA dc_c
        LDB #8
        CMP
        JZ dc_del
        LDA dc_c
        LDB #127
        CMP
        JZ dc_del
        LDA dc_k
        LDB #38
        CMP
        JC dc_next
        LDA #<cmd
        LDB dc_k
        ADD
        TAP1L
        LDA #>cmd
        JNC dc1
        INC
dc1:    TAP1H
        LDA dc_c
        STA (P1)
        LDA dc_k
        INC
        STA dc_k
        LDA dc_c
        JSR outc
        JMP dc_next
dc_del: LDA dc_k
        LDB #0
        CMP
        JZ dc_next
        LDA dc_k
        DEC
        STA dc_k
        LDA #8
        JSR outc
        LDA #32
        JSR outc
        LDA #8
        JSR outc
dc_next:JSR rawkey
        STA dc_c
        JMP dcl
dc_go:  LDA #<cmd
        LDB dc_k
        ADD
        TAP1L
        LDA #>cmd
        JNC dc2
        INC
dc2:    TAP1H
        LDA #0
        STA (P1)
        LDA cmd
        LDB #'q'
        CMP
        JNZ dc_w
        LDA cmd+1
        LDB #0
        CMP
        JZ dc_q0
        LDA cmd+1
        LDB #'!'
        CMP
        JZ dc_force
        JMP dc_unk
dc_q0:  LDA dirty
        LDB #0
        CMP
        JZ dc_qquit
        LDA #<s_nowrite
        STA os_p
        LDA #>s_nowrite
        STA os_p+1
        JSR msg24
        RTS
dc_qquit:
        LDA #1
        STA done
        RTS
dc_force:
        LDA #1
        STA done
        RTS
dc_w:   LDA cmd
        LDB #'w'
        CMP
        JNZ dc_x
        LDA cmd+1
        LDB #0
        CMP
        JZ dc_wsave
        LDA cmd+1
        LDB #'q'
        CMP
        JZ dc_wqsave
        JMP dc_unk
dc_wsave:
        LDA #<path
        STA sv_p
        LDA #>path
        STA sv_p+1
        JSR save
        RTS
dc_wqsave:
        LDA #<path
        STA sv_p
        LDA #>path
        STA sv_p+1
        JSR save
        LDA #1
        STA done
        RTS
dc_x:   LDA cmd
        LDB #'x'
        CMP
        JNZ dc_unk
        LDA cmd+1
        LDB #0
        CMP
        JNZ dc_unk
        LDA #<path
        STA sv_p
        LDA #>path
        STA sv_p+1
        JSR save
        LDA #1
        STA done
        RTS
dc_unk: LDA #<s_unknown
        STA os_p
        LDA #>s_unknown
        STA os_p+1
        JSR msg24
        RTS

; abspath (mirrors os/commands/lib_apath.c): ap_out <- absolute path of the word
; at ap_a; a relative word is prefixed with the CWD (SYS_GETCWD $2003), since
; FRESOLVE starts at root. P2 = source cursor, P1 = dest. (Ported from dir.asm.)
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
        JSR SYS_GETCWD               ; SYS_GETCWD -> out
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

; ======================= strings / data ====================================
u_use:  .asciiz "usage: VI name   modal VT100 screen editor (:wq to save+quit)"
s_ins:  .asciiz "-- INSERT --  "
s_blank:.asciiz "              "
s_plus: .asciiz " [+]"
s_nf:   .asciiz "pattern not found"
s_noundo:.asciiz "nothing to undo"
s_unknown:.asciiz "?unknown command"
; "no write since change (:q! to force)" — no ';' so a plain string is fine
s_nowrite:.asciiz "no write since change (:q! to force)"

v_arg:  .fill 2
ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
key:    .fill 1
mode:   .fill 1
dirty:  .fill 1
done:   .fill 1
pend:   .fill 1
nlines: .fill 1
cy:     .fill 1
cx:     .fill 1
top:    .fill 1
havepat:.fill 1
uop:    .fill 1
uy:     .fill 1
ux:     .fill 1
oc:     .fill 1
osk:    .fill 1
os_p:   .fill 2
on_n:   .fill 1
dv:     .fill 1
dvq:    .fill 1
dvr:    .fill 1
g_r:    .fill 1
g_c:    .fill 1
va_i:   .fill 1
va_c:   .fill 1
van:    .fill 1
vat:    .fill 2
vacar:  .fill 1
ll_i:   .fill 1
ll_n:   .fill 1
cxn:    .fill 1
nm_t:   .fill 1
ld_p:   .fill 2
ld_col: .fill 1
ld_c:   .fill 1
sv_p:   .fill 2
sv_p2:  .fill 2
sv_i:   .fill 1
sv_c:   .fill 1
dr_r:   .fill 1
dr_li:  .fill 1
dptr:   .fill 2
rd_r:   .fill 1
sc_t:   .fill 1
ic_c:   .fill 1
ic_n:   .fill 1
ic_j:   .fill 1
ic_ch:  .fill 1
dc_n:   .fill 1
dc_j:   .fill 1
dc_c:   .fill 1
dc_k:   .fill 1
cp_d:   .fill 1
cp_s:   .fill 1
cl_k:   .fill 1
cl_c:   .fill 1
od_i:   .fill 1
od_t:   .fill 1
dl_i:   .fill 1
dl_t:   .fill 1
sp_i:   .fill 1
sp_t:   .fill 1
sp_k:   .fill 1
sp_jc:  .fill 1
sp_c:   .fill 1
sl_p:   .fill 2
in_y:   .fill 1
il_i:   .fill 1
un_t:   .fill 1
ma_m:   .fill 1
ma_i:   .fill 1
ma_j:   .fill 1
ma_jc:  .fill 1
ma_lc:  .fill 1
ff_sy:  .fill 1
ff_sx:  .fill 1
ff_i:   .fill 1
ff_j:   .fill 1
gp_k:   .fill 1
gp_c:   .fill 1
cmd:    .fill 40                ; ':' command input buffer (uses up to 38 + NUL)
pat:    .fill 40                ; '/' search pattern buffer (uses up to 38 + NUL)
usave:  .fill 80                ; undo scratch: one saved line
path:   .fill 80                ; absolute path of the file being edited
; Flat line buffer: 110 lines x 80 bytes. Line i occupies line[i*80 .. i*80+79];
; each line is NUL-terminated, so the usable text width is 79 chars.
line:   .fill 8800

; lib_abi.inc — the BIOS/OS entry-point address book for hand-asm /BIN commands.
; A twin declares `;#use abi` and mkasm.sh appends this file, after which it can
; `JSR FOPEN` / `JSR SYS_PUTC` instead of hand-coding `JSR $0124` / `JSR $2009`.
;
; These are pure equates: they emit NO bytes, so a twin that switches its raw
; `JSR $NNNN` calls to symbolic ones assembles to the byte-identical binary — the
; magic numbers just get names, and the firmware jump table / syscall vector can
; be renumbered by editing this one file. (The C side splits the same names across
; lib_fsread/fswrite/fsdir/con.c because there each wrapper costs code space; on
; the asm side an equate is free, so one address book is simplest.)
;
; Unused equates are harmless, so a twin can blanket `;#use abi` even if it only
; needs a couple — which also lets a shared include, e.g. lib_stdin.inc, use these
; names as long as its host command pulls in this file too.

; --- OS syscalls ($20xx) — the redirectable stream + FS/CWD calls ---
SYS_GETCWD   = $2003    ; copy CWD path string -> (P1), incl. NUL
SYS_CWDLBA   = $2006    ; CWD directory start LBA -> A
SYS_PUTC     = $2009    ; A -> current stdout (console or redirected file)
SYS_GETC     = $200C    ; next stdin byte -> A (carry/EOF per ABI)
SYS_PUTS     = $200F    ; write (P1) string to stdout
SYS_OPENCWD  = $2012    ; begin iterating the CWD (16-bit LBA)
; Note the gap: $2015/$2018 are reserved/unused vectors, so the numbering
; jumps from $2012 straight to $201B — keep new syscalls at the +3 stride.
SYS_DIRENTRY = $201B    ; snapshot the current dir entry -> (P1) 18 bytes
SYS_OPENDIR  = $201E    ; P1 = 16-bit dir start LBA -> open for FNEXT
SYS_MKDIR    = $2021    ; P1 = path -> create a directory; C=1 on real failure

; --- BIOS jump table ($01xx) ---
CONIN      = $0100      ; wait for key, char -> A (raw console, not stdin)
CONOUT     = $0103      ; A -> serial (raw console, not stdout)
PUTS       = $0112      ; print (P1)+ until $00 (raw console)
PHEX8      = $0115      ; print A as two hex digits
FFIND      = $0118      ; root file FNAME -> LBA+FLEN; C=0 found
FCREATE    = $011B      ; create root file FNAME from FSRC/FLEN; C=1 err
FDELETE    = $011E      ; tombstone root file FNAME; C=1 not found
FCOMMIT    = $0121      ; register streamed file (entry+free); C=1 full
FOPEN      = $0124      ; open file FNAME for reading (P1=buffer); C=1 missing
; FGETB/FPUTB stream one byte at a time and clobber P1/P2 (they walk the
; sector buffer), so save any live pointer regs around the call.
FGETB      = $0127      ; next byte -> A; C=1 at end of file
FWOPEN     = $012A      ; open a write stream at the free pointer (uses SBUF)
FPUTB      = $012D      ; append byte A to the write stream
FCLOSE     = $0130      ; flush + register file FNAME; C=1 full
FRESOLVE   = $0133      ; resolve path (P1) -> dir extent + leaf FNAME; C=1 bad path
FNORM      = $0136      ; copy string (P1) -> FNAME, case-preserved, padded to 12
FOPENDIR   = $0139      ; begin iterating directory at path (P1); C=1 bad path
FNEXT      = $013C      ; next live entry -> FNAME/FFLAG/LBA/FLEN; C=1 at end
FLOADAT    = $013F      ; read FLEN bytes from LBA into (P1) (whole sectors)
FOPENDIRAT = $0142      ; iterate the 4-sector directory at LBA = A (low)+LBA1 (high)
FSDIRBUF   = $0145      ; point FNEXT's sector buffer at page A (call after FOPENDIR)
