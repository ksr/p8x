; find.asm — hand-coded FIND command (asm counterpart of os/commands/find.c).
;   FIND pattern   CWD paths matching pattern (glob if * or ?, else substring).
; Shares gmatch + de[] via `;#use glob`. Recursive CWD walk building each path in
; cur[], with per-level child LBA+name arrays indexed by a global w_depth (P3 is
; the stack pointer, so no software-stack frames). MAXD=10 deep, 24 children/lvl.
; BIOS: FNEXT $013C, FSDIRBUF $0145, SYS_DIRENTRY $401B, SYS_OPENDIR $401E.
; OS: SYS_GETCWD $4003, SYS_OPENCWD $4012, SYS_PUTC $4009, SYS_PUTS $400F.
; Entry: P2 = arg tail.
;#use glob

        .org $7A00
        TPA2L
        STA f_arg
        TPA2H
        STA f_arg+1
f_sk:   LDA f_arg
        TAP2L
        LDA f_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ f_chk
        LDA f_arg
        LDB #1
        ADD
        STA f_arg
        JNC f_sk
        LDA f_arg+1
        INC
        STA f_arg+1
        JMP f_sk
f_chk:  LDA (P2)
        LDB #0
        CMP
        JZ f_usage
        LDB #13
        CMP
        JZ f_usage
        LDB #'-'
        CMP
        JNZ f_pat
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ f_usage
        LDB #'H'
        CMP
        JZ f_usage
; build pat[] from the arg word, note glob chars
f_pat:  LDA #0
        STA isglob
        LDA f_arg
        TAP2L
        LDA f_arg+1
        TAP2H
        LDA #<pat
        TAP1L
        LDA #>pat
        TAP1H
        LDA #0
        STA fi
f_pl:   LDA fi
        LDB #63
        CMP
        JC f_pd                      ; i>=63 stop
        LDA (P2)
        LDB #0
        CMP
        JZ f_pd
        LDB #32
        CMP
        JZ f_pd
        LDB #13
        CMP
        JZ f_pd
        LDA (P2)
        LDB #'*'
        CMP
        JZ f_pg
        LDB #'?'
        CMP
        JNZ f_ps
f_pg:   LDA #1
        STA isglob
f_ps:   LDA (P2)
        STA (P1)+
        INP2
        LDA fi
        INC
        STA fi
        JMP f_pl
f_pd:   LDA #0
        STA (P1)                     ; pat NUL
; cur = CWD path ; plen at level 0
        LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        JSR $4003                    ; SYS_GETCWD -> cur
        LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        STA fi
f_len:  LDA (P1)
        LDB #0
        CMP
        JZ f_len0
        INP1
        LDA fi
        INC
        STA fi
        JMP f_len
f_len0: LDA #0                        ; w_depth=0; parr[0]=plen
        STA w_depth
        JSR parr_a
        LDA fi
        STA (P1)
        LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $4012                    ; SYS_OPENCWD
        LDA #0
        TAP1L
        TAP1H
        LDA #$EA
        JSR $0145                    ; FSDIRBUF $EA
        JSR walk
        RTS
f_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS

; ======================= walk ==============================================
walk:   JSR nsub_a
        LDA #0
        STA (P1)
        JSR parr_a
        LDA (P1)
        STA fpl                      ; level base plen
w_next: LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $013C                    ; FNEXT
        JC w_desc
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR $401B                    ; de_read
        LDA de
        LDB #'.'
        CMP
        JZ w_next
        JSR rdname
        LDA #<nm
        STA nm_p
        LDA #>nm
        STA nm_p+1
        JSR nmatch
        LDB #0
        CMP
        JZ w_nomatch
        JSR print_match
w_nomatch:
        LDA de+12
        LDB #2
        CMP
        JNZ w_next
        JSR nsub_a
        LDA (P1)
        LDB #24
        CMP
        JC w_next                    ; nsub>=24 -> skip
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
wcn_l:  JSR cn_a                     ; P1 = cn[d][fi][fk]
        LDA #<nm
        LDB fk
        ADD
        TAP2L
        LDA #>nm
        JNC wcn1
        INC
wcn1:   TAP2H
        LDA (P2)
        STA (P1)
        LDB #0
        CMP
        JZ wcn_d
        LDA fk
        INC
        STA fk
        JMP wcn_l
wcn_d:  JSR nsub_a
        LDA (P1)
        INC
        STA (P1)
        JMP w_next
w_desc: JSR idx_a
        LDA #0
        STA (P1)
w_dl:   JSR idx_a
        LDA (P1)
        STA fi
        JSR nsub_a
        LDA (P1)
        LDB fi
        CMP
        JZ w_ret
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
        JSR $401E                    ; SYS_OPENDIR
        LDA #0
        TAP1L
        TAP1H
        LDA #$EA
        JSR $0145
        JSR parr_a
        LDA (P1)
        STA fpl                      ; oldp
        LDA fpl
        STA cp
        LDA fpl
        LDB #1
        CMP
        JNZ w_addsl
        LDA cur
        LDB #'/'
        CMP
        JZ w_nameonly
w_addsl:LDA #<cur
        LDB cp
        ADD
        TAP1L
        LDA #>cur
        JNC wa1
        INC
wa1:    TAP1H
        LDA #'/'
        STA (P1)
        LDA cp
        INC
        STA cp
w_nameonly:
        LDA #0
        STA fk
wnm_l:  JSR cn_a
        LDA (P1)
        STA fch
        LDB #0
        CMP
        JZ wnm_d
        LDA #<cur
        LDB cp
        ADD
        TAP1L
        LDA #>cur
        JNC wn1
        INC
wn1:    TAP1H
        LDA fch
        STA (P1)
        LDA cp
        INC
        STA cp
        LDA fk
        INC
        STA fk
        JMP wnm_l
wnm_d:  LDA #<cur
        LDB cp
        ADD
        TAP1L
        LDA #>cur
        JNC wn2
        INC
wn2:    TAP1H
        LDA #0
        STA (P1)
        LDA w_depth
        INC
        STA w_depth
        JSR parr_a
        LDA cp
        STA (P1)
        JSR walk
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
        JNC wr1
        INC
wr1:    TAP1H
        LDA #0
        STA (P1)
        JSR idx_a
        LDA (P1)
        INC
        STA (P1)
        JMP w_dl
w_ret:  RTS

; ======================= print_match =======================================
print_match:
        LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        STA pcnt
pm_l:   LDA pcnt
        LDB fpl
        CMP
        JZ pm_sep
        LDA (P1)
        JSR $4009
        INP1
        LDA pcnt
        INC
        STA pcnt
        JMP pm_l
pm_sep: LDA fpl
        LDB #1
        CMP
        JNZ pm_slash
        LDA cur
        LDB #'/'
        CMP
        JZ pm_name
pm_slash:
        LDA #'/'
        JSR $4009
pm_name:LDA #<nm
        TAP1L
        LDA #>nm
        TAP1H
pm_nl:  LDA (P1)
        LDB #0
        CMP
        JZ pm_eol
        JSR $4009
        INP1
        JMP pm_nl
pm_eol: LDA #10
        JSR $4009
        RTS

; ======================= rdname / nmatch / contains ========================
rdname: LDA #<nm
        TAP1L
        LDA #>nm
        TAP1H
        LDA #<de
        TAP2L
        LDA #>de
        TAP2H
        LDA #0
        STA fi2
rd_l:   LDA fi2
        LDB #12
        CMP
        JZ rd_d
        LDA (P2)
        LDB #32
        CMP
        JZ rd_sk
        STA (P1)+
rd_sk:  INP2
        LDA fi2
        INC
        STA fi2
        JMP rd_l
rd_d:   LDA #0
        STA (P1)
        RTS

nmatch: LDA isglob
        LDB #0
        CMP
        JZ nm_sub
        LDA #<pat
        STA gp
        LDA #>pat
        STA gp+1
        LDA nm_p
        STA gs
        LDA nm_p+1
        STA gs+1
        JSR gmatch
        RTS
nm_sub: LDA nm_p
        STA cn_h
        LDA nm_p+1
        STA cn_h+1
        LDA #<pat
        STA cn_n
        LDA #>pat
        STA cn_n+1
        JSR contains
        RTS

; contains: A = 1 if string cn_n is a substring of cn_h
contains:
        LDA #0
        STA ct_i
ct_iloop:
        LDA cn_h
        LDB ct_i
        ADD
        TAP1L
        LDA cn_h+1
        JNC ci1
        INC
ci1:    TAP1H
        LDA (P1)
        LDB #0
        CMP
        JZ ct_no
        LDA #0
        STA ct_j
ct_jloop:
        LDA cn_n
        LDB ct_j
        ADD
        TAP2L
        LDA cn_n+1
        JNC cj1
        INC
cj1:    TAP2H
        LDA (P2)
        STA ct_nc
        LDB #0
        CMP
        JZ ct_yes
        LDA ct_i
        LDB ct_j
        ADD
        STA ct_ij
        LDA cn_h
        LDB ct_ij
        ADD
        TAP1L
        LDA cn_h+1
        JNC cj2
        INC
cj2:    TAP1H
        LDA (P1)
        LDB ct_nc
        CMP
        JNZ ct_inext
        LDA ct_j
        INC
        STA ct_j
        JMP ct_jloop
ct_inext:
        LDA ct_i
        INC
        STA ct_i
        JMP ct_iloop
ct_yes: LDA #1
        RTS
ct_no:  LDA #0
        RTS

; ======================= index helpers =====================================
nsub_a: LDA #<nsub
        LDB w_depth
        ADD
        TAP1L
        LDA #>nsub
        JNC nsa1
        INC
nsa1:   TAP1H
        RTS
idx_a:  LDA #<idx
        LDB w_depth
        ADD
        TAP1L
        LDA #>idx
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
; clba_a: P1 = clba + w_depth*48 + fi*2
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
; cn_a: P1 = cn + w_depth*384 + fi*16 + fk
cn_a:   LDA #0
        STA ft
        STA ft+1
        LDA w_depth
        STA fn
cna_m:  LDA fn
        LDB #0
        CMP
        JZ cna_md
        LDA ft
        LDB #128
        ADD
        STA ft
        JNC cna_1
        LDA ft+1
        INC
        STA ft+1
cna_1:  LDA ft
        LDB #128
        ADD
        STA ft
        JNC cna_2
        LDA ft+1
        INC
        STA ft+1
cna_2:  LDA ft
        LDB #128
        ADD
        STA ft
        JNC cna_3
        LDA ft+1
        INC
        STA ft+1
cna_3:  LDA fn
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

u_use:  .asciiz "usage: FIND pattern   CWD paths matching pattern (glob if * or ?, else substring)"

f_arg:  .fill 2
isglob: .fill 1
w_depth:.fill 1
fpl:    .fill 1
cp:     .fill 1
fi:     .fill 1
fk:     .fill 1
fk2:    .fill 1
fch:    .fill 1
fi2:    .fill 1
pcnt:   .fill 1
flba:   .fill 2
nm_p:   .fill 2
cn_h:   .fill 2
cn_n:   .fill 2
ct_i:   .fill 1
ct_j:   .fill 1
ct_ij:  .fill 1
ct_nc:  .fill 1
ft:     .fill 2
fn:     .fill 1
fcar:   .fill 1
pat:    .fill 64
nm:     .fill 16
cur:    .fill 256
nsub:   .fill 10
idx:    .fill 10
parr:   .fill 10
clba:   .fill 480
cn:     .fill 3840
