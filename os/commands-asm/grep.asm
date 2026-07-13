; grep.asm — hand-coded GREP command (asm counterpart of os/commands/grep.c).
;   GREP [-r] regex [file|glob]   print lines matching a basic regex (. * + ? ^ $)
; Shares match() via `;#use regex` and the file/glob/stdin engine + de[] via
; `;#use stdin`. Non-recursive: read a file/glob/stdin and print matching lines.
; -r: walk the CWD tree (collect file paths, find-style depth-indexed recursion
; on FSDIRBUF page $EA), then grep each, printing "path:line".
; Entry: P2 = arg tail.
;#use stdin
;#use regex

        .org $6A00
        TPA2L
        STA g_arg
        TPA2H
        STA g_arg+1
        LDA #0
        STA recurse
g_sk:   LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ g_chk
        LDA g_arg
        LDB #1
        ADD
        STA g_arg
        JNC g_sk
        LDA g_arg+1
        INC
        STA g_arg+1
        JMP g_sk
g_chk:  LDA (P2)
        LDB #0
        CMP
        JZ g_usage
        LDB #13
        CMP
        JZ g_usage
        LDB #'-'
        CMP
        JNZ g_re
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ g_usage
        LDB #'H'
        CMP
        JZ g_usage
        LDB #'r'
        CMP
        JNZ g_re                      ; '-' not -r/-h: treat rest as regex (from g_arg)
        LDA #1
        STA recurse
        LDA g_arg
        LDB #2
        ADD
        STA g_arg
        JNC grs
        LDA g_arg+1
        INC
        STA g_arg+1
grs:    LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ g_re
        LDA g_arg
        LDB #1
        ADD
        STA g_arg
        JNC grs
        LDA g_arg+1
        INC
        STA g_arg+1
        JMP grs
; extract regex word into re[]
g_re:   LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
        LDA #<re
        TAP1L
        LDA #>re
        TAP1H
        LDA #0
        STA fi
gre_l:  LDA fi
        LDB #63
        CMP
        JC gre_d
        LDA (P2)
        LDB #0
        CMP
        JZ gre_d
        LDB #32
        CMP
        JZ gre_d
        LDB #13
        CMP
        JZ gre_d
        LDA (P2)
        STA (P1)+
        INP2
        LDA fi
        INC
        STA fi
        JMP gre_l
gre_d:  LDA #0
        STA (P1)
        ; g_arg += fi  (advance past the regex word)
        LDA g_arg
        LDB fi
        ADD
        STA g_arg
        JNC gad
        LDA g_arg+1
        INC
        STA g_arg+1
gad:    LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
gad_s:  LDA (P2)
        LDB #32
        CMP
        JNZ g_go
        LDA g_arg
        LDB #1
        ADD
        STA g_arg
        JNC gad_s2
        LDA g_arg+1
        INC
        STA g_arg+1
gad_s2: LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
        JMP gad_s
g_go:   LDA recurse
        LDB #0
        CMP
        JZ g_plain
; ---- -r : collect CWD tree, grep each --------------------------------------
        LDA #0
        STA nrf
        LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        JSR $2003                     ; SYS_GETCWD -> cur
        LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        STA fi
gcl:    LDA (P1)
        LDB #0
        CMP
        JZ gcl0
        INP1
        LDA fi
        INC
        STA fi
        JMP gcl
gcl0:   LDA #0
        STA w_depth
        JSR parr_a
        LDA fi
        STA (P1)
        LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $2012                     ; SYS_OPENCWD
        LDA #0
        TAP1L
        TAP1H
        LDA #$EA
        JSR $0145
        JSR collect
        LDA #0
        STA gi
gp2_l:  LDA gi
        LDB nrf
        CMP
        JC gp2_d
        LDA gi
        STA rfi
        JSR rf_addr
        LDA #0
        STA fromfile
        LDA rfp
        STA op_a
        LDA rfp+1
        STA op_a+1
        JSR open_path
        LDB #1
        CMP
        JNZ gp2_n
        LDA #1
        STA fromfile
        LDA rfp
        STA gs_pfx
        LDA rfp+1
        STA gs_pfx+1
        JSR grep_stream
gp2_n:  LDA gi
        INC
        STA gi
        JMP gp2_l
gp2_d:  RTS
; ---- non-recursive: file/glob/stdin ----------------------------------------
g_plain:LDA g_arg
        STA oa_a
        LDA g_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ g_nf
        LDA #0
        STA gs_pfx
        STA gs_pfx+1
        JSR grep_stream
        RTS
g_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR $200F
        LDA #10
        JSR $2009
        RTS
g_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR $200F
        LDA #10
        JSR $2009
        RTS

; ======================= grep_stream =======================================
; gs_pfx (word): 0 = no prefix, else print "pfx:" before each matching line.
grep_stream:
        LDA #0
        STA gn
gst_l:  JSR nextc
        JC gst_end
        STA g_sc
        LDB #10
        CMP
        JZ gst_eol
        LDA g_sc
        LDB #13
        CMP
        JZ gst_eol
        LDA gn
        LDB #255
        CMP
        JC gst_l
        LDA #<line
        LDB gn
        ADD
        TAP1L
        LDA #>line
        JNC gsl1
        INC
gsl1:   TAP1H
        LDA g_sc
        STA (P1)
        LDA gn
        INC
        STA gn
        JMP gst_l
gst_eol:LDA #<line
        LDB gn
        ADD
        TAP1L
        LDA #>line
        JNC gse1
        INC
gse1:   TAP1H
        LDA #0
        STA (P1)
        LDA gn
        LDB #0
        CMP
        JZ gst_reset
        JSR do_match
gst_reset:
        LDA #0
        STA gn
        JMP gst_l
gst_end:LDA gn
        LDB #0
        CMP
        JZ gst_ret
        LDA #<line
        LDB gn
        ADD
        TAP1L
        LDA #>line
        JNC gsf1
        INC
gsf1:   TAP1H
        LDA #0
        STA (P1)
        JSR do_match
gst_ret:RTS

do_match:
        LDA #<re
        STA rx_re
        LDA #>re
        STA rx_re+1
        LDA #<line
        STA rx_t
        LDA #>line
        STA rx_t+1
        JSR match
        LDB #0
        CMP
        JZ dm_ret
        LDA gs_pfx
        LDB #0
        CMP
        JNZ dm_pfx
        LDA gs_pfx+1
        LDB #0
        CMP
        JZ dm_line
dm_pfx: LDA gs_pfx
        TAP1L
        LDA gs_pfx+1
        TAP1H
dmp_l:  LDA (P1)
        LDB #0
        CMP
        JZ dmp_d
        JSR $2009
        INP1
        JMP dmp_l
dmp_d:  LDA #':'
        JSR $2009
dm_line:LDA #<line
        TAP1L
        LDA #>line
        TAP1H
        LDA #0
        JSR $200F
        LDA #10
        JSR $2009
dm_ret: RTS

; ======================= collect (-r walk) =================================
collect:JSR nsub_a
        LDA #0
        STA (P1)
        JSR parr_a
        LDA (P1)
        STA fpl
c_next: LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $013C
        JC c_desc
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR $201B
        LDA de
        LDB #'.'
        CMP
        JZ c_next
        JSR rdname
        LDA de+12
        LDB #1
        CMP
        JNZ c_chkdir
        LDA nrf
        LDB #36
        CMP
        JC c_chkdir
        JSR append_file
c_chkdir:
        LDA de+12
        LDB #2
        CMP
        JNZ c_next
        JSR nsub_a
        LDA (P1)
        LDB #24
        CMP
        JC c_next
        JSR nsub_a
        LDA (P1)
        STA fi
        JSR clba_a
        LDA de+15
        STA (P1)+
        LDA de+16
        STA (P1)
        LDA #0
        STA fk
crn_l:  JSR cn_a
        LDA #<nm
        LDB fk
        ADD
        TAP2L
        LDA #>nm
        JNC crn1
        INC
crn1:   TAP2H
        LDA (P2)
        STA (P1)
        LDB #0
        CMP
        JZ crn_d
        LDA fk
        INC
        STA fk
        JMP crn_l
crn_d:  JSR nsub_a
        LDA (P1)
        INC
        STA (P1)
        JMP c_next
c_desc: JSR idx_a
        LDA #0
        STA (P1)
c_dl:   JSR idx_a
        LDA (P1)
        STA fi
        JSR nsub_a
        LDA (P1)
        LDB fi
        CMP
        JZ c_ret
        JSR clba_a
        LDA (P1)+
        STA flba
        LDA (P1)
        STA flba+1
        LDA flba
        TAP1L
        LDA flba+1
        TAP1H
        LDA #0
        JSR $201E
        LDA #0
        TAP1L
        TAP1H
        LDA #$EA
        JSR $0145
        JSR parr_a
        LDA (P1)
        STA fpl
        LDA fpl
        STA cp
        LDA fpl
        LDB #1
        CMP
        JNZ c_addsl
        LDA cur
        LDB #'/'
        CMP
        JZ c_nameonly
c_addsl:LDA #<cur
        LDB cp
        ADD
        TAP1L
        LDA #>cur
        JNC ca1
        INC
ca1:    TAP1H
        LDA #'/'
        STA (P1)
        LDA cp
        INC
        STA cp
c_nameonly:
        LDA #0
        STA fk
cnm_l:  JSR cn_a
        LDA (P1)
        STA fch
        LDB #0
        CMP
        JZ cnm_d
        LDA #<cur
        LDB cp
        ADD
        TAP1L
        LDA #>cur
        JNC cn1
        INC
cn1:    TAP1H
        LDA fch
        STA (P1)
        LDA cp
        INC
        STA cp
        LDA fk
        INC
        STA fk
        JMP cnm_l
cnm_d:  LDA #<cur
        LDB cp
        ADD
        TAP1L
        LDA #>cur
        JNC cn2
        INC
cn2:    TAP1H
        LDA #0
        STA (P1)
        LDA w_depth
        INC
        STA w_depth
        JSR parr_a
        LDA cp
        STA (P1)
        JSR collect
        LDA w_depth
        DEC
        STA w_depth
        JSR parr_a
        LDA (P1)
        STA fpl
        LDA #<cur
        LDB fpl
        ADD
        TAP1L
        LDA #>cur
        JNC cr1
        INC
cr1:    TAP1H
        LDA #0
        STA (P1)
        JSR idx_a
        LDA (P1)
        INC
        STA (P1)
        JMP c_dl
c_ret:  RTS

; append_file: rfiles[nrf] = cur[0..fpl) + sep + nm ; nrf++
append_file:
        LDA nrf
        STA rfi
        JSR rf_addr
        LDA #0
        STA afk
af_cl:  LDA afk
        LDB fpl
        CMP
        JZ af_sep
        LDA #<cur
        LDB afk
        ADD
        TAP2L
        LDA #>cur
        JNC af1
        INC
af1:    TAP2H
        LDA (P2)
        STA afc
        LDA rfp
        TAP1L
        LDA rfp+1
        TAP1H
        LDA afc
        STA (P1)
        LDA rfp
        LDB #1
        ADD
        STA rfp
        JNC af2
        LDA rfp+1
        INC
        STA rfp+1
af2:    LDA afk
        INC
        STA afk
        JMP af_cl
af_sep: LDA fpl
        LDB #1
        CMP
        JNZ af_slash
        LDA cur
        LDB #'/'
        CMP
        JZ af_name
af_slash:
        LDA rfp
        TAP1L
        LDA rfp+1
        TAP1H
        LDA #'/'
        STA (P1)
        LDA rfp
        LDB #1
        ADD
        STA rfp
        JNC af_name
        LDA rfp+1
        INC
        STA rfp+1
af_name:LDA #0
        STA afk
af_nl:  LDA #<nm
        LDB afk
        ADD
        TAP2L
        LDA #>nm
        JNC afn1
        INC
afn1:   TAP2H
        LDA (P2)
        STA afc
        LDB #0
        CMP
        JZ af_nd
        LDA rfp
        TAP1L
        LDA rfp+1
        TAP1H
        LDA afc
        STA (P1)
        LDA rfp
        LDB #1
        ADD
        STA rfp
        JNC afn2
        LDA rfp+1
        INC
        STA rfp+1
afn2:   LDA afk
        INC
        STA afk
        JMP af_nl
af_nd:  LDA rfp
        TAP1L
        LDA rfp+1
        TAP1H
        LDA #0
        STA (P1)
        LDA nrf
        INC
        STA nrf
        RTS

; rf_addr: rfp = rfiles + rfi*80
rf_addr:LDA #0
        STA rfp
        STA rfp+1
        LDA rfi
        STA rfn
rfa_l:  LDA rfn
        LDB #0
        CMP
        JZ rfa_d
        LDA rfp
        LDB #80
        ADD
        STA rfp
        JNC rfa1
        LDA rfp+1
        INC
        STA rfp+1
rfa1:   LDA rfn
        DEC
        STA rfn
        JMP rfa_l
rfa_d:  LDA rfp
        LDB #<rfiles
        ADD
        STA rfp
        LDA #0
        JNC rfa2
        LDA #1
rfa2:   STA rfcar
        LDA rfp+1
        LDB #>rfiles
        ADD
        LDB rfcar
        ADD
        STA rfp+1
        RTS

; rdname: de[0..11] (non-space) -> nm
rdname: LDA #<nm
        TAP1L
        LDA #>nm
        TAP1H
        LDA #<de
        TAP2L
        LDA #>de
        TAP2H
        LDA #0
        STA fk
rd_l:   LDA fk
        LDB #12
        CMP
        JZ rd_d
        LDA (P2)
        LDB #32
        CMP
        JZ rd_sk
        STA (P1)+
rd_sk:  INP2
        LDA fk
        INC
        STA fk
        JMP rd_l
rd_d:   LDA #0
        STA (P1)
        RTS

; ======================= index helpers (find-style) ========================
nsub_a: LDA #<nsub
        LDB w_depth
        ADD
        TAP1L
        LDA #>nsub
        JNC nsa1
        INC
nsa1:   TAP1H
        RTS
idx_a:  LDA #<gidxr
        LDB w_depth
        ADD
        TAP1L
        LDA #>gidxr
        JNC ixa1
        INC
ixa1:   TAP1H
        RTS
parr_a: LDA #<parr
        LDB w_depth
        ADD
        TAP1L
        LDA #>parr
        JNC pra1
        INC
pra1:   TAP1H
        RTS
clba_a: LDA #0
        STA ft
        STA ft+1
        LDA w_depth
        STA fn
cla_m:  LDA fn
        LDB #0
        CMP
        JZ cla_md
        LDA ft
        LDB #48
        ADD
        STA ft
        JNC cla_1
        LDA ft+1
        INC
        STA ft+1
cla_1:  LDA fn
        DEC
        STA fn
        JMP cla_m
cla_md: LDA fi
        SHL
        LDB ft
        ADD
        STA ft
        JNC cla_2
        LDA ft+1
        INC
        STA ft+1
cla_2:  LDA ft
        LDB #<clba
        ADD
        STA ft
        LDA #0
        JNC cla_3
        LDA #1
cla_3:  STA fcar
        LDA ft+1
        LDB #>clba
        ADD
        LDB fcar
        ADD
        STA ft+1
        LDA ft
        TAP1L
        LDA ft+1
        TAP1H
        RTS
cn_a:   LDA #0
        STA ft
        STA ft+1
        LDA w_depth
        STA fn
cna_m:  LDA fn
        LDB #0
        CMP
        JZ cna_md
        LDA ft+1
        INC
        STA ft+1
        LDA ft
        LDB #32
        ADD
        STA ft
        JNC cna_1
        LDA ft+1
        INC
        STA ft+1
cna_1:  LDA fn
        DEC
        STA fn
        JMP cna_m
cna_md: LDA fi
        STA fk2
cna_fl: LDA fk2
        LDB #0
        CMP
        JZ cna_fd
        LDA ft
        LDB #16
        ADD
        STA ft
        JNC cna_f1
        LDA ft+1
        INC
        STA ft+1
cna_f1: LDA fk2
        DEC
        STA fk2
        JMP cna_fl
cna_fd: LDA ft
        LDB fk
        ADD
        STA ft
        JNC cna_k1
        LDA ft+1
        INC
        STA ft+1
cna_k1: LDA ft
        LDB #<cn
        ADD
        STA ft
        LDA #0
        JNC cna_b
        LDA #1
cna_b:  STA fcar
        LDA ft+1
        LDB #>cn
        ADD
        LDB fcar
        ADD
        STA ft+1
        LDA ft
        TAP1L
        LDA ft+1
        TAP1H
        RTS

u_nf:   .asciiz "grep: not found"
u_use:  .ascii "usage: GREP [-r] regex [file|glob]   match regex (. * + ? ^ $)"
        .byte 59
        .ascii " -r walks the CWD tree"
        .byte 0

g_arg:  .fill 2
recurse:.fill 1
gi:     .fill 1
gn:     .fill 1
g_sc:    .fill 1
gs_pfx: .fill 2
w_depth:.fill 1
fpl:    .fill 1
cp:     .fill 1
fi:     .fill 1
fk:     .fill 1
fk2:    .fill 1
fch:    .fill 1
flba:   .fill 2
nrf:    .fill 1
rfi:    .fill 1
rfp:    .fill 2
rfn:    .fill 1
rfcar:  .fill 1
afk:    .fill 1
afc:    .fill 1
ft:     .fill 2
fn:     .fill 1
fcar:   .fill 1
re:     .fill 64
line:   .fill 176
nm:     .fill 16
cur:    .fill 176
nsub:   .fill 8
gidxr:  .fill 8
parr:   .fill 8
clba:   .fill 384
cn:     .fill 3072
rfiles: .fill 2880
