; lib_stdin.inc — shared "file(s)-or-stdin input" helpers for hand-asm /BIN
; commands (asm counterpart of lib_stdin.c + lib_globx.c + lib_glob.c). A command
; declares `;#use stdin` and mkasm.sh appends this file (mirroring clib.py's
; //#use splice), so wc/head/tail/uniq/cat share one copy of the open/read/glob
; logic — and each binary counts it, keeping the size comparison fair.
;
; Entry points (args/returns via memory words; P3 is the stack pointer so only
; P1/P2 are used, and a pointer cursor is reloaded after any syscall):
;   openarg      : oa_a = arg word -> A = 0 stdin / 1 opened / 2 not found
;                  (also sets `fromfile`; a *|? glob is expanded and read as one
;                  concatenated stream)
;   nextc        : -> A = next byte, carry SET at EOF (spans glob matches)
;   open_path    : op_a = path word -> A = 1 opened / 2 not found (read buf $FC00)
;   glob_expand  : ge_pat/ge_out/ge_max -> ge_cnt files, ge_out[i*64] = path
;   gmatch       : gp/gs -> A = 1 if pattern gp matches string gs (case-insens.)
;
; BIOS: FGETB $0127, FRESOLVE $0133, FOPEN $0124, FOPENDIR $0139, FNEXT $013C,
; FSDIRBUF $0145, SYS_DIRENTRY $401B. OS: SYS_GETCWD $4003, SYS_GETC $400C,
; SYS_OPENCWD $4012.

; ---- openarg --------------------------------------------------------------
openarg:
        LDA #0
        STA fromfile
        STA gnf
        STA gidx
        LDA oa_a
        TAP2L
        LDA oa_a+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ oa_stdin
        LDB #13
        CMP
        JZ oa_stdin
        LDA #0
        STA oa_g
        LDA oa_a
        TAP2L
        LDA oa_a+1
        TAP2H
oa_scl: LDA (P2)
        LDB #0
        CMP
        JZ oa_scd
        LDB #13
        CMP
        JZ oa_scd
        LDB #32
        CMP
        JZ oa_scd
        LDB #'*'
        CMP
        JZ oa_setg
        LDB #'?'
        CMP
        JZ oa_setg
        INP2
        JMP oa_scl
oa_setg:LDA #1
        STA oa_g
        INP2
        JMP oa_scl
oa_scd: LDA oa_g
        LDB #0
        CMP
        JZ oa_single
        LDA oa_a                      ; glob: ge = glob_expand(arg, gfiles, 24)
        STA ge_pat
        LDA oa_a+1
        STA ge_pat+1
        LDA #<gfiles
        STA ge_out
        LDA #>gfiles
        STA ge_out+1
        LDA #24
        STA ge_max
        JSR glob_expand
        LDA ge_cnt
        STA gnf
        LDB #0
        CMP
        JZ oa_nf
        LDA #1
        STA fromfile
        LDA #<gfiles
        STA op_a
        LDA #>gfiles
        STA op_a+1
        JSR open_path
        RTS
oa_single:
        LDA #1
        STA fromfile
        LDA oa_a
        STA op_a
        LDA oa_a+1
        STA op_a+1
        JSR open_path
        RTS
oa_stdin:
        LDA #0
        RTS
oa_nf:  LDA #2
        RTS

; ---- nextc ----------------------------------------------------------------
nextc:  LDA fromfile
        LDB #0
        CMP
        JNZ nc_file
        LDA #0
        JSR $400C                     ; stdin: A=byte, C=EOF (passthrough)
        RTS
nc_file:LDA #0
        JSR $0127                     ; FGETB
        JNC nc_ok
nc_adv: LDA gnf                       ; end of current file
        LDB #0
        CMP
        JZ nc_eof                     ; single file -> done
        LDA gidx
        INC
        STA gtmp
        LDA gtmp
        LDB gnf
        CMP
        JC nc_eof                     ; gidx+1 >= gnf -> done
        LDA gtmp
        STA gidx
        JSR gfile_ptr                 ; op_a = &gfiles[gidx*64]
        JSR open_path
        LDA #0
        JSR $0127
        JNC nc_ok
        JMP nc_adv
nc_ok:  CLC
        RTS
nc_eof: SEC
        RTS

; gfile_ptr: op_a = gfiles + gidx*64
gfile_ptr:
        LDA #0
        STA op_a
        STA op_a+1
        LDA gidx
        STA gtmp2
gfp_l:  LDA gtmp2
        LDB #0
        CMP
        JZ gfp_d
        LDA op_a
        LDB #64
        ADD
        STA op_a
        JNC gfp_1
        LDA op_a+1
        INC
        STA op_a+1
gfp_1:  LDA gtmp2
        DEC
        STA gtmp2
        JMP gfp_l
gfp_d:  LDA op_a
        LDB #<gfiles
        ADD
        STA op_a
        LDA #0
        JNC gfp_2
        LDA #1
gfp_2:  STA gcarry
        LDA op_a+1
        LDB #>gfiles
        ADD
        LDB gcarry
        ADD
        STA op_a+1
        RTS

; ---- open_path (abspath + FRESOLVE + FOPEN) -------------------------------
open_path:
        LDA op_a
        TAP2L
        LDA op_a+1
        TAP2H
        LDA (P2)
        LDB #'/'
        CMP
        JZ opa_abs
        LDA #<spath                   ; relative -> SYS_GETCWD(spath)
        TAP1L
        LDA #>spath
        TAP1H
        LDA #0
        JSR $4003
        LDA #<spath
        TAP1L
        LDA #>spath
        TAP1H
opa_sl: LDA (P1)
        LDB #0
        CMP
        JZ opa_sld
        INP1
        JMP opa_sl
opa_sld:DEP1
        LDA (P1)
        INP1
        LDB #'/'
        CMP
        JZ opa_cp
        LDA #'/'
        STA (P1)+
        JMP opa_cp
opa_abs:LDA #<spath
        TAP1L
        LDA #>spath
        TAP1H
opa_cp: LDA op_a                      ; reload source (SYS_GETCWD clobbered P2)
        TAP2L
        LDA op_a+1
        TAP2H
opa_cl: LDA (P2)
        LDB #0
        CMP
        JZ opa_end
        LDB #13
        CMP
        JZ opa_end
        LDB #32
        CMP
        JZ opa_end
        STA (P1)+
        INP2
        JMP opa_cl
opa_end:LDA #0
        STA (P1)
        LDA #<spath
        TAP1L
        LDA #>spath
        TAP1H
        LDA #0
        JSR $0133                     ; FRESOLVE
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR $0124                     ; FOPEN $FC00
        JC opa_nf
        LDA #1
        RTS
opa_nf: LDA #2
        RTS

; ---- glob_expand ----------------------------------------------------------
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
        JSR $4012                     ; SYS_OPENCWD
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
        JSR $401B                     ; de_read
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

; ---- gmatch / upper (case-insensitive * ? whole-string matcher) -----------
gmatch: LDA gp
        TAP1L
        LDA gp+1
        TAP1H
        LDA (P1)
        STA gpc
        LDB #'*'
        CMP
        JZ gm_star
        LDB #0
        CMP
        JZ gm_pend
        LDA gs
        TAP2L
        LDA gs+1
        TAP2H
        LDA (P2)
        STA gsc
        LDB #0
        CMP
        JZ gm_r0
        LDA gpc
        LDB #'?'
        CMP
        JZ gm_adv
        LDA gpc
        JSR upper
        STA gpc
        LDA gsc
        JSR upper
        LDB gpc
        CMP
        JZ gm_adv
        LDA #0
        RTS
gm_adv: LDA gp
        LDB #1
        ADD
        STA gp
        JNC gm_a1
        LDA gp+1
        INC
        STA gp+1
gm_a1:  LDA gs
        LDB #1
        ADD
        STA gs
        JNC gm_a2
        LDA gs+1
        INC
        STA gs+1
gm_a2:  JMP gmatch
gm_pend:LDA gs
        TAP2L
        LDA gs+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ gm_r1
        LDA #0
        RTS
gm_r0:  LDA #0
        RTS
gm_r1:  LDA #1
        RTS
gm_star:LDA gp
        LDB #1
        ADD
        STA gp
        JNC gm_s0
        LDA gp+1
        INC
        STA gp+1
gm_s0:  LDA gp
        PHA
        LDA gp+1
        PHA
        LDA gs
        PHA
        LDA gs+1
        PHA
        JSR gmatch
        STA gmr
        PLA
        STA gs+1
        PLA
        STA gs
        PLA
        STA gp+1
        PLA
        STA gp
        LDA gmr
        LDB #0
        CMP
        JNZ gm_r1
        LDA gs
        TAP2L
        LDA gs+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ gm_r0
        LDA gs
        LDB #1
        ADD
        STA gs
        JNC gm_s0
        LDA gs+1
        INC
        STA gs+1
        JMP gm_s0
upper:  STA uch
        LDB #'a'
        CMP
        JNC up_no
        LDA uch
        LDB #123
        CMP
        JC up_no
        LDA uch
        LDB #32
        SUB
        RTS
up_no:  LDA uch
        RTS

; ---- shared data ----------------------------------------------------------
fromfile:.fill 1
gnf:    .fill 1
gidx:   .fill 1
gtmp:   .fill 1
gtmp2:  .fill 1
gcarry: .fill 1
oa_a:   .fill 2
oa_g:   .fill 1
op_a:   .fill 2
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
gp:     .fill 2
gs:     .fill 2
gpc:    .fill 1
gsc:    .fill 1
gmr:    .fill 1
uch:    .fill 1
spath:  .fill 80
ge_dir: .fill 64
ge_leaf:.fill 16
ge_nm:  .fill 16
de:     .fill 18   ; +[17] = length bits 16..23 (24-bit file size)
gfiles: .fill 1536
