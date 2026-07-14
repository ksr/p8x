; cp.asm — hand-coded CP command (asm counterpart of os/commands/cp.c).
;   CP [-r] src dst   copy a file, or -r a directory tree.
; abspath() inline; copy_tree recursion uses depth-indexed per-level arrays
; (sp/dp/names/isd/n/idx) keyed by a global w_depth (P3 is the stack pointer).
; Iterates on FSDIRBUF page $A0. BIOS: FRESOLVE $0133, FOPEN $0124, FGETB $0127,
; FWOPEN $012A, FPUTB $012D, FCLOSE $0130, FOPENDIR $0139, FNEXT $013C, FSDIRBUF
; $0145, SYS_DIRENTRY $201B. OS: SYS_GETCWD $2003, SYS_MKDIR $2021, SYS_PUTS/PUTC.
; A `*`/`?` source is a glob (lib_globx): every match is copied into the dst
; directory. copy_tree iterates on FSDIRBUF page $E0 (above the enlarged binary).
; Entry: P2 = arg tail.
;#use glob
;#use globx
;#use abi

        .org $6A00
        TPA2L
        STA c_arg
        TPA2H
        STA c_arg+1
        LDA #0
        STA rec
c_sk:   LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ c_opt
        LDA c_arg
        LDB #1
        ADD
        STA c_arg
        JNC c_sk
        LDA c_arg+1
        INC
        STA c_arg+1
        JMP c_sk
c_opt:  LDA (P2)
        LDB #'-'
        CMP
        JNZ c_args
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ c_usage
        LDB #'H'
        CMP
        JZ c_usage
        LDB #'r'
        CMP
        JZ c_setr
        LDB #'R'
        CMP
        JZ c_setr
        JMP c_args
c_setr: LDA #1
        STA rec
        LDA c_arg
        LDB #2
        ADD
        STA c_arg
        JNC csr_s
        LDA c_arg+1
        INC
        STA c_arg+1
csr_s:  LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ c_args
        LDA c_arg
        LDB #1
        ADD
        STA c_arg
        JNC csr_s
        LDA c_arg+1
        INC
        STA c_arg+1
        JMP csr_s
c_args: LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ c_usage2
        LDB #13
        CMP
        JZ c_usage2
        LDA #0                       ; copy src WORD into patw, note glob (cg)
        STA cg
        LDA #<patw
        TAP1L
        LDA #>patw
        TAP1H
        LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
        LDA #0
        STA cpw
cpw_l:  LDA (P2)
        LDB #0
        CMP
        JZ cpw_d
        LDB #13
        CMP
        JZ cpw_d
        LDB #32
        CMP
        JZ cpw_d
        LDB #'*'
        CMP
        JZ cpw_g
        LDB #'?'
        CMP
        JZ cpw_g
        JMP cpw_s
cpw_g:  LDA #1
        STA cg
        LDA (P2)
cpw_s:  STA (P1)+
        INP2
        LDA cpw
        INC
        STA cpw
        JMP cpw_l
cpw_d:  LDA #0
        STA (P1)
        LDA c_arg                    ; c_arg += cpw
        LDB cpw
        ADD
        STA c_arg
        JNC ca_sk
        LDA c_arg+1
        INC
        STA c_arg+1
ca_sk:  LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ ca_d
        LDA c_arg
        LDB #1
        ADD
        STA c_arg
        JNC ca_sk
        LDA c_arg+1
        INC
        STA c_arg+1
        JMP ca_sk
ca_d:   LDA (P2)
        LDB #0
        CMP
        JZ c_usage2
        LDB #13
        CMP
        JZ c_usage2
        LDA #<dst
        STA ap_out
        LDA #>dst
        STA ap_out+1
        LDA c_arg
        STA ap_a
        LDA c_arg+1
        STA ap_a+1
        JSR abspath                  ; abspath(dst, arg)
        LDA cg                       ; glob source? -> c_glob
        LDB #0
        CMP
        JNZ c_glob
        LDA #<src                    ; single: abspath(src, patw)
        STA ap_out
        LDA #>src
        STA ap_out+1
        LDA #<patw
        STA ap_a
        LDA #>patw
        STA ap_a+1
        JSR abspath
        LDA rec
        LDB #0
        CMP
        JZ c_dofile
        LDA #<src
        STA id_p
        LDA #>src
        STA id_p+1
        JSR isdir
        LDB #0
        CMP
        JZ c_dofile
        LDA #<src
        STA ct_s
        LDA #>src
        STA ct_s+1
        LDA #<dst
        STA ct_d
        LDA #>dst
        STA ct_d+1
        LDA #0
        STA w_depth
        JSR copy_tree
        RTS
c_dofile:
        LDA #<src
        STA cf_s
        LDA #>src
        STA cf_s+1
        LDA #<dst
        STA cf_d
        LDA #>dst
        STA cf_d+1
        JSR copy_file
        LDB #1
        CMP
        JZ c_srcnf
        RTS
; --- glob: dst must be a dir; copy each match into it -----------------------
c_glob: LDA #<dst
        STA id_p
        LDA #>dst
        STA id_p+1
        JSR isdir
        LDB #0
        CMP
        JZ c_notdir
        LDA #<patw
        STA ge_pat
        LDA #>patw
        STA ge_pat+1
        LDA #<gfiles
        STA ge_out
        LDA #>gfiles
        STA ge_out+1
        LDA #24
        STA ge_max
        JSR glob_expand
        LDA ge_cnt
        LDB #0
        CMP
        JZ c_nomatch
        LDA #0
        STA cgi
cg_l:   LDA cgi
        LDB ge_cnt
        CMP
        JC cg_done                   ; i >= cnt
        JSR cg_ptr                   ; cgp = gfiles + cgi*64
        LDA #<src                    ; abspath(src, cgp)
        STA ap_out
        LDA #>src
        STA ap_out+1
        LDA cgp
        STA ap_a
        LDA cgp+1
        STA ap_a+1
        JSR abspath
        JSR cg_base                  ; cgbp = basename of the match
        LDA #<jdst                   ; joinp(jdst, dst, basename)
        STA jp_out
        LDA #>jdst
        STA jp_out+1
        LDA #<dst
        STA jp_dir
        LDA #>dst
        STA jp_dir+1
        LDA cgbp
        STA jp_name
        LDA cgbp+1
        STA jp_name+1
        JSR joinp
        LDA rec                      ; -r && dir -> copy_tree, else copy_file
        LDB #0
        CMP
        JZ cg_file
        LDA #<src
        STA id_p
        LDA #>src
        STA id_p+1
        JSR isdir
        LDB #0
        CMP
        JZ cg_file
        LDA #<src
        STA ct_s
        LDA #>src
        STA ct_s+1
        LDA #<jdst
        STA ct_d
        LDA #>jdst
        STA ct_d+1
        LDA #0
        STA w_depth
        JSR copy_tree
        JMP cg_next
cg_file:LDA #<src
        STA cf_s
        LDA #>src
        STA cf_s+1
        LDA #<jdst
        STA cf_d
        LDA #>jdst
        STA cf_d+1
        JSR copy_file
cg_next:LDA cgi
        INC
        STA cgi
        JMP cg_l
cg_done:RTS
c_notdir:
        LDA #<u_notdir
        TAP1L
        LDA #>u_notdir
        TAP1H
        JMP c_put
c_nomatch:
        LDA #<u_nomat
        TAP1L
        LDA #>u_nomat
        TAP1H
        JMP c_put
; cg_ptr: cgp = gfiles + cgi*64
cg_ptr: LDA #0
        STA cgp
        STA cgp+1
        LDA cgi
        STA cgt
cgp_l:  LDA cgt
        LDB #0
        CMP
        JZ cgp_d
        LDA cgp
        LDB #64
        ADD
        STA cgp
        JNC cgp_1
        LDA cgp+1
        INC
        STA cgp+1
cgp_1:  LDA cgt
        DEC
        STA cgt
        JMP cgp_l
cgp_d:  LDA cgp
        LDB #<gfiles
        ADD
        STA cgp
        LDA #0
        JNC cgp_2
        LDA #1
cgp_2:  STA cgcar
        LDA cgp+1
        LDB #>gfiles
        ADD
        LDB cgcar
        ADD
        STA cgp+1
        RTS
; cg_base: cgbp = cgp advanced past the last '/', else cgp
cg_base:LDA cgp
        STA cgbp
        LDA cgp+1
        STA cgbp+1
        LDA cgp
        TAP1L
        LDA cgp+1
        TAP1H
        LDA #0
        STA cgk
cgb_l:  LDA (P1)
        LDB #0
        CMP
        JZ cgb_d
        LDB #'/'
        CMP
        JNZ cgb_adv
        LDA cgk                      ; cgbp = cgp + cgk + 1
        INC
        STA cgt
        LDA cgp
        LDB cgt
        ADD
        STA cgbp
        LDA #0
        JNC cgb_hi
        LDA #1
cgb_hi: LDB cgp+1
        ADD
        STA cgbp+1
cgb_adv:INP1
        LDA cgk
        INC
        STA cgk
        JMP cgb_l
cgb_d:  RTS
c_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        JMP c_put
c_usage2:
        LDA #<u_use2
        TAP1L
        LDA #>u_use2
        TAP1H
        JMP c_put
c_srcnf:LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
c_put:  LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; ======================= copy_file / isdir =================================
copy_file:
        LDA cf_s
        TAP1L
        LDA cf_s+1
        TAP1H
        LDA #0
        JSR FRESOLVE
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR FOPEN
        JC cf_nf
        LDA cf_d
        TAP1L
        LDA cf_d+1
        TAP1H
        LDA #0
        JSR FRESOLVE
        LDA #0
        JSR FWOPEN
cf_cp:  LDA #0
        JSR FGETB
        JC cf_done
        STA cfch
        LDA #0
        TAP1L
        TAP1H
        LDA cfch
        JSR FPUTB
        JMP cf_cp
cf_done:LDA #0
        JSR FCLOSE
        LDA #0
        RTS
cf_nf:  LDA #1
        RTS
isdir:  LDA id_p
        TAP1L
        LDA id_p+1
        TAP1H
        LDA #0
        JSR FOPENDIR
        JC id_no
        LDA #1
        RTS
id_no:  LDA #0
        RTS

; ======================= copy_tree =========================================
copy_tree:
        JSR spd_a                    ; sp[d] = *ct_s
        TPA1L
        STA sc_d
        TPA1H
        STA sc_d+1
        LDA ct_s
        STA sc_s
        LDA ct_s+1
        STA sc_s+1
        JSR scopy
        JSR dpd_a                    ; dp[d] = *ct_d
        TPA1L
        STA sc_d
        TPA1H
        STA sc_d+1
        LDA ct_d
        STA sc_s
        LDA ct_d+1
        STA sc_s+1
        JSR scopy
        JSR dpd_a                    ; SYS_MKDIR(dp[d])
        LDA #0
        JSR SYS_MKDIR
        JSR spd_a                    ; FOPENDIR(sp[d])
        LDA #0
        JSR FOPENDIR
        LDA #0
        TAP1L
        TAP1H
        LDA #$E0
        JSR FSDIRBUF
        JSR nn_a
        LDA #0
        STA (P1)
ct_nl:  LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR FNEXT
        JC ct_proc
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR SYS_DIRENTRY
        LDA de
        LDB #'.'
        CMP
        JZ ct_nl
        JSR nn_a
        LDA (P1)
        LDB #24
        CMP
        JC ct_nl                     ; n>=24 -> skip
        JSR nn_a
        LDA (P1)
        STA cti
        LDA #0
        STA ctk
ct_tl:  LDA ctk
        LDB #12
        CMP
        JZ ct_isd
        LDA #<de
        LDB ctk
        ADD
        TAP2L
        LDA #>de
        JNC ct1
        INC
ct1:    TAP2H
        LDA (P2)
        STA ctc
        LDB #32
        CMP
        JZ ct_padl
        JSR names_a
        LDA ctc
        STA (P1)
        LDA ctk
        INC
        STA ctk
        JMP ct_tl
ct_padl:LDA ctk
        LDB #12
        CMP
        JZ ct_isd
        JSR names_a
        LDA #0
        STA (P1)
        LDA ctk
        INC
        STA ctk
        JMP ct_padl
ct_isd: LDA de+12
        LDB #2
        CMP
        JZ ct_isd1
        JSR isd_a
        LDA #0
        STA (P1)
        JMP ct_ninc
ct_isd1:JSR isd_a
        LDA #1
        STA (P1)
ct_ninc:JSR nn_a
        LDA (P1)
        INC
        STA (P1)
        JMP ct_nl
ct_proc:JSR idx_a
        LDA #0
        STA (P1)
ct_pl:  JSR idx_a
        LDA (P1)
        STA cti
        JSR nn_a
        LDA (P1)
        LDB cti
        CMP
        JZ ct_ret
        LDA #<jsrc                   ; joinp(jsrc, sp[d], names[d][cti])
        STA jp_out
        LDA #>jsrc
        STA jp_out+1
        JSR spd_a
        TPA1L
        STA jp_dir
        TPA1H
        STA jp_dir+1
        LDA #0
        STA ctk
        JSR names_a
        TPA1L
        STA jp_name
        TPA1H
        STA jp_name+1
        JSR joinp
        LDA #<jdst                   ; joinp(jdst, dp[d], names[d][cti])
        STA jp_out
        LDA #>jdst
        STA jp_out+1
        JSR dpd_a
        TPA1L
        STA jp_dir
        TPA1H
        STA jp_dir+1
        LDA #0
        STA ctk
        JSR names_a
        TPA1L
        STA jp_name
        TPA1H
        STA jp_name+1
        JSR joinp
        JSR isd_a
        LDA (P1)
        LDB #0
        CMP
        JZ ct_file
        LDA #<jsrc                   ; recurse: copy_tree(jsrc,jdst)
        STA ct_s
        LDA #>jsrc
        STA ct_s+1
        LDA #<jdst
        STA ct_d
        LDA #>jdst
        STA ct_d+1
        LDA w_depth
        INC
        STA w_depth
        JSR copy_tree
        LDA w_depth
        DEC
        STA w_depth
        JMP ct_pinc
ct_file:LDA #<jsrc
        STA cf_s
        LDA #>jsrc
        STA cf_s+1
        LDA #<jdst
        STA cf_d
        LDA #>jdst
        STA cf_d+1
        JSR copy_file
ct_pinc:JSR idx_a
        LDA (P1)
        INC
        STA (P1)
        JMP ct_pl
ct_ret: RTS

; ======================= scopy / joinp =====================================
scopy:  LDA sc_d
        TAP1L
        LDA sc_d+1
        TAP1H
        LDA sc_s
        TAP2L
        LDA sc_s+1
        TAP2H
        LDA #0
        STA sc_n
sc_l:   LDA (P2)
        LDB #0
        CMP
        JZ sc_dn
        STA (P1)+
        INP2
        LDA sc_n
        INC
        STA sc_n
        JMP sc_l
sc_dn:  LDA #0
        STA (P1)
        LDA sc_n
        RTS
joinp:  LDA jp_out
        STA sc_d
        LDA jp_out+1
        STA sc_d+1
        LDA jp_dir
        STA sc_s
        LDA jp_dir+1
        STA sc_s+1
        JSR scopy
        STA jp_i
        LDB #0
        CMP
        JZ jp_addsl
        LDA jp_out                   ; out[i-1] == '/' ?
        LDB jp_i
        ADD
        TAP1L
        LDA jp_out+1
        JNC jp1
        INC
jp1:    TAP1H
        DEP1
        LDA (P1)
        LDB #'/'
        CMP
        JZ jp_cn
jp_addsl:
        LDA jp_out
        LDB jp_i
        ADD
        TAP1L
        LDA jp_out+1
        JNC jp2
        INC
jp2:    TAP1H
        LDA #'/'
        STA (P1)
        LDA jp_i
        INC
        STA jp_i
jp_cn:  LDA jp_name
        TAP2L
        LDA jp_name+1
        TAP2H
        LDA jp_out
        LDB jp_i
        ADD
        TAP1L
        LDA jp_out+1
        JNC jp3
        INC
jp3:    TAP1H
jp_nl:  LDA (P2)
        LDB #0
        CMP
        JZ jp_nd
        STA (P1)+
        INP2
        LDA jp_i
        INC
        STA jp_i
        JMP jp_nl
jp_nd:  LDA #0
        STA (P1)
        LDA jp_i
        RTS

; ======================= abspath (P2 source, P1 dest) ======================
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

; ======================= index helpers =====================================
nn_a:   LDA #<nn
        LDB w_depth
        ADD
        TAP1L
        LDA #>nn
        JNC nna1
        INC
nna1:   TAP1H
        RTS
idx_a:  LDA #<cidx
        LDB w_depth
        ADD
        TAP1L
        LDA #>cidx
        JNC ixa1
        INC
ixa1:   TAP1H
        RTS
; spd_a: P1 = sp + w_depth*80
spd_a:  LDA #<sp
        STA ha
        LDA #>sp
        STA ha+1
        JMP mul80
; dpd_a: P1 = dp + w_depth*80
dpd_a:  LDA #<dp
        STA ha
        LDA #>dp
        STA ha+1
mul80:  LDA #0
        STA ht
        STA ht+1
        LDA w_depth
        STA hn
m80l:   LDA hn
        LDB #0
        CMP
        JZ m80d
        LDA ht
        LDB #80
        ADD
        STA ht
        JNC m801
        LDA ht+1
        INC
        STA ht+1
m801:   LDA hn
        DEC
        STA hn
        JMP m80l
m80d:   LDA ht
        LDB ha
        ADD
        STA ht
        LDA #0
        JNC m80b
        LDA #1
m80b:   STA hcar
        LDA ht+1
        LDB ha+1
        ADD
        LDB hcar
        ADD
        STA ht+1
        LDA ht
        TAP1L
        LDA ht+1
        TAP1H
        RTS
; isd_a: P1 = isd + w_depth*24 + cti
isd_a:  LDA #0
        STA ht
        STA ht+1
        LDA w_depth
        STA hn
isa_m:  LDA hn
        LDB #0
        CMP
        JZ isa_md
        LDA ht
        LDB #24
        ADD
        STA ht
        JNC isa_1
        LDA ht+1
        INC
        STA ht+1
isa_1:  LDA hn
        DEC
        STA hn
        JMP isa_m
isa_md: LDA ht
        LDB cti
        ADD
        STA ht
        JNC isa_2
        LDA ht+1
        INC
        STA ht+1
isa_2:  LDA ht
        LDB #<isd
        ADD
        STA ht
        LDA #0
        JNC isa_b
        LDA #1
isa_b:  STA hcar
        LDA ht+1
        LDB #>isd
        ADD
        LDB hcar
        ADD
        STA ht+1
        LDA ht
        TAP1L
        LDA ht+1
        TAP1H
        RTS
; names_a: P1 = names + w_depth*288 + cti*12 + ctk
names_a:LDA #0
        STA ht
        STA ht+1
        LDA w_depth
        STA hn
na_m:   LDA hn
        LDB #0
        CMP
        JZ na_md
        LDA ht                       ; +288 = +256 +32
        LDB #0
        ADD
        STA ht
        LDA ht+1
        INC
        STA ht+1
        LDA ht
        LDB #32
        ADD
        STA ht
        JNC na_1
        LDA ht+1
        INC
        STA ht+1
na_1:   LDA hn
        DEC
        STA hn
        JMP na_m
na_md:  LDA cti                      ; + cti*12
        STA hk
na_cl:  LDA hk
        LDB #0
        CMP
        JZ na_cd
        LDA ht
        LDB #12
        ADD
        STA ht
        JNC na_c1
        LDA ht+1
        INC
        STA ht+1
na_c1:  LDA hk
        DEC
        STA hk
        JMP na_cl
na_cd:  LDA ht                       ; + ctk
        LDB ctk
        ADD
        STA ht
        JNC na_k
        LDA ht+1
        INC
        STA ht+1
na_k:   LDA ht
        LDB #<names
        ADD
        STA ht
        LDA #0
        JNC na_b
        LDA #1
na_b:   STA hcar
        LDA ht+1
        LDB #>names
        ADD
        LDB hcar
        ADD
        STA ht+1
        LDA ht
        TAP1L
        LDA ht+1
        TAP1H
        RTS

u_use:  .asciiz "usage: CP [-r] src dst   copy a file/glob, or -r a directory tree"
u_use2: .asciiz "usage: CP [-r] src dst"
u_nf:   .asciiz "cp: source not found"
u_notdir:.asciiz "cp: target is not a directory"
u_nomat:.asciiz "cp: no match"

c_arg:  .fill 2
rec:    .fill 1
cg:     .fill 1
cpw:    .fill 1
cgi:    .fill 1
cgp:    .fill 2
cgbp:   .fill 2
cgk:    .fill 1
cgt:    .fill 1
cgcar:  .fill 1
patw:   .fill 80
gfiles: .fill 1536
w_depth:.fill 1
cti:    .fill 1
ctk:    .fill 1
ctc:    .fill 1
cfch:   .fill 1
sc_d:   .fill 2
sc_s:   .fill 2
sc_n:   .fill 1
jp_out: .fill 2
jp_dir: .fill 2
jp_name:.fill 2
jp_i:   .fill 1
ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
cf_s:   .fill 2
cf_d:   .fill 2
id_p:   .fill 2
ct_s:   .fill 2
ct_d:   .fill 2
ha:     .fill 2
ht:     .fill 2
hn:     .fill 1
hk:     .fill 1
hcar:   .fill 1
src:    .fill 80
dst:    .fill 80
jsrc:   .fill 80
jdst:   .fill 80
sp:     .fill 640
dp:     .fill 640
names:  .fill 2304
isd:    .fill 192
nn:     .fill 8
cidx:   .fill 8
