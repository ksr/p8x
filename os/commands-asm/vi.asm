; vi.asm — hand-coded VI command (asm counterpart of os/commands/vi.c).
;   VI name   modal VT100 screen editor (:wq to save+quit).
; Raw keys via BIOS CONIN ($0100, no echo), output via CONOUT ($0103). Flat line
; buffer (110 x 80); line i at line[i*80..]. All indices < 256 so byte math
; matches p8cc's 16-bit-unsigned comparisons on these small values. No shared
; include. BIOS: CONIN $0100, CONOUT $0103, FRESOLVE $0133, FOPEN $0124, FGETB
; $0127, FWOPEN $012A, FPUTB $012D, FCLOSE $0130. Entry: P2 = arg tail.

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
        JSR $200F
        LDA #10
        JSR $2009
        RTS

; ---- INSERT mode ----------------------------------------------------------
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
rawkey: LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $0100
        RTS
outc:   STA oc
        LDA #0
        TAP1L
        TAP1H
        LDA oc
        JSR $0103
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
; laddr: P1 = line + va_i*80 + va_c
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
load:   LDA ld_p
        TAP1L
        LDA ld_p+1
        TAP1H
        LDA #0
        JSR $0133
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
        JSR $0124
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
        JSR $0127
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
save:   LDA sv_p
        TAP1L
        LDA sv_p+1
        TAP1H
        LDA #0
        JSR $0133
        LDA #0
        JSR $012A
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
        JSR $012D
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
        JSR $012D
        LDA sv_i
        INC
        STA sv_i
        JMP sv_il
sv_done:LDA #0
        JSR $0130
        LDA #0
        STA dirty
        RTS

; ======================= redraw ============================================
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
snap1:  JSR saveline
        LDA #1
        STA uop
        LDA cy
        STA uy
        LDA cx
        STA ux
        RTS
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
        JSR $2003                    ; SYS_GETCWD -> out
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
cmd:    .fill 40
pat:    .fill 40
usave:  .fill 80
path:   .fill 80
line:   .fill 8800
