; lib_globx.inc — expand a filename glob into a path list, for hand-asm
; commands that copy/move multiple files (cp, mv). Declared with ';#use globx'.
; Asm counterpart of lib_globx.c. Depends on gmatch + de[] from lib_glob.inc,
; so a command using globx must ALSO ';#use glob'. glob_expand(ge_pat, ge_out,
; ge_max) -> ge_cnt files written to ge_out[i*64] (dir prefix + name). Iterates
; on FSDIRBUF page $FA. BIOS: FOPENDIR $0139, FNEXT $013C, FSDIRBUF $0145,
; SYS_DIRENTRY $201B; OS: SYS_OPENCWD $2012.

glob_expand:
        LDA #0
        STA ge_hs
        STA ge_sp
        STA ge_pl
        LDA ge_pat
        TAP2L
        LDA ge_pat+1
        TAP2H
ge_scl: LDA (P2)
        LDB #0
        CMP
        JZ ge_scd
        LDB #13
        CMP
        JZ ge_scd
        LDB #32
        CMP
        JZ ge_scd
        LDB #'/'
        CMP
        JNZ ge_sci
        LDA ge_pl
        STA ge_sp
        LDA #1
        STA ge_hs
ge_sci: INP2
        LDA ge_pl
        INC
        STA ge_pl
        JMP ge_scl
ge_scd: LDA #0
        STA ge_ls
        STA ge_dir
        LDA ge_hs
        LDB #0
        CMP
        JZ ge_leaf0
        LDA ge_sp
        INC
        STA ge_ls
        LDA ge_pat                    ; ge_dir = pat[0..slashpos]
        TAP2L
        LDA ge_pat+1
        TAP2H
        LDA #<ge_dir
        TAP1L
        LDA #>ge_dir
        TAP1H
        LDA #0
        STA ge_j
ge_dl:  LDA (P2)
        STA (P1)+
        INP2
        LDA ge_j
        LDB ge_sp
        CMP
        JZ ge_dde
        LDA ge_j
        INC
        STA ge_j
        JMP ge_dl
ge_dde: LDA #0
        STA (P1)
ge_leaf0:
        LDA ge_pat                    ; P2 = pat + ls
        LDB ge_ls
        ADD
        TAP2L
        LDA ge_pat+1
        JNC ge_l0
        INC
ge_l0:  TAP2H
        LDA #<ge_leaf
        TAP1L
        LDA #>ge_leaf
        TAP1H
        LDA ge_ls
        STA ge_j
ge_ll:  LDA ge_j
        LDB ge_pl
        CMP
        JZ ge_lle
        LDA (P2)
        STA (P1)+
        INP2
        LDA ge_j
        INC
        STA ge_j
        JMP ge_ll
ge_lle: LDA #0
        STA (P1)
        LDA ge_hs                     ; open the directory
        LDB #0
        CMP
        JZ ge_ocwd
        LDA #<ge_dir
        TAP1L
        LDA #>ge_dir
        TAP1H
        LDA #0
        JSR $0139                     ; FOPENDIR(dir)
        JMP ge_fsd
ge_ocwd:LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $2012                     ; SYS_OPENCWD
ge_fsd: LDA #0
        TAP1L
        TAP1H
        LDA #$FA
        JSR $0145                     ; FSDIRBUF $FA
        LDA #0
        STA ge_cnt
ge_nl:  LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $013C                     ; FNEXT
        JC ge_gdone
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR $201B                     ; de_read
        LDA de
        LDB #'.'
        CMP
        JZ ge_nl
        LDA de+12
        LDB #1
        CMP
        JNZ ge_nl                     ; files only
        LDA #<de                      ; trim name -> ge_nm
        TAP2L
        LDA #>de
        TAP2H
        LDA #<ge_nm
        TAP1L
        LDA #>ge_nm
        TAP1H
        LDA #0
        STA ge_j
ge_tl:  LDA ge_j
        LDB #12
        CMP
        JZ ge_tld
        LDA (P2)
        LDB #32
        CMP
        JZ ge_tld
        STA (P1)+
        INP2
        LDA ge_j
        INC
        STA ge_j
        JMP ge_tl
ge_tld: LDA #0
        STA (P1)
        LDA #<ge_leaf
        STA gp
        LDA #>ge_leaf
        STA gp+1
        LDA #<ge_nm
        STA gs
        LDA #>ge_nm
        STA gs+1
        JSR gmatch
        LDB #0
        CMP
        JZ ge_nl                      ; no match
        LDA ge_cnt
        LDB ge_max
        CMP
        JC ge_nl                      ; cnt >= max -> drop
        JSR ge_slot                   ; P1 = ge_out + cnt*64
        LDA #<ge_dir
        TAP2L
        LDA #>ge_dir
        TAP2H
ge_od:  LDA (P2)
        LDB #0
        CMP
        JZ ge_odn
        STA (P1)+
        INP2
        JMP ge_od
ge_odn: LDA #<ge_nm
        TAP2L
        LDA #>ge_nm
        TAP2H
ge_onl: LDA (P2)
        LDB #0
        CMP
        JZ ge_ot
        STA (P1)+
        INP2
        JMP ge_onl
ge_ot:  LDA #0
        STA (P1)
        LDA ge_cnt
        INC
        STA ge_cnt
        JMP ge_nl
ge_gdone:
        RTS

; ge_slot: P1 = ge_out + ge_cnt*64
ge_slot:
        LDA #0
        STA getmp
        STA getmp+1
        LDA ge_cnt
        STA ge_j2
ges_l:  LDA ge_j2
        LDB #0
        CMP
        JZ ges_d
        LDA getmp
        LDB #64
        ADD
        STA getmp
        JNC ges_1
        LDA getmp+1
        INC
        STA getmp+1
ges_1:  LDA ge_j2
        DEC
        STA ge_j2
        JMP ges_l
ges_d:  LDA getmp
        LDB ge_out
        ADD
        STA getmp
        LDA #0
        JNC ges_2
        LDA #1
ges_2:  STA gecar
        LDA getmp+1
        LDB ge_out+1
        ADD
        LDB gecar
        ADD
        STA getmp+1
        LDA getmp
        TAP1L
        LDA getmp+1
        TAP1H
        RTS

; ---- data (gmatch/de/gp/gs live in lib_glob.inc; gfiles is caller-provided) --
ge_pat: .fill 2
ge_out: .fill 2
ge_max: .fill 1
ge_cnt: .fill 1
ge_hs:  .fill 1
ge_sp:  .fill 1
ge_pl:  .fill 1
ge_ls:  .fill 1
ge_j:   .fill 1
ge_j2:  .fill 1
getmp:  .fill 2
gecar:  .fill 1
ge_dir: .fill 64
ge_leaf:.fill 16
ge_nm:  .fill 16
