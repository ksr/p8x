; lib_globx.inc — expand a filename glob into a path list, for hand-asm
; commands that copy/move multiple files (cp, mv). Declared with ';#use globx'.
; Asm counterpart of lib_globx.c. Depends on gmatch + de[] from lib_glob.inc,
; so a command using globx must ALSO ';#use glob'. glob_expand(ge_pat, ge_out,
; ge_max) -> ge_cnt files written to ge_out[i*64] (dir prefix + name). Iterates
; on FSDIRBUF page $FA. BIOS: FOPENDIR $0139, FNEXT $013C, FSDIRBUF $0145,
; SYS_DIRENTRY $201B; OS: SYS_OPENCWD $2012.

; glob_expand(ge_pat, ge_out, ge_max) -> ge_cnt
;   Scan the pattern to split it into a directory prefix (ge_dir) and a leaf
;   glob (ge_leaf), open that directory, then walk it matching each filename
;   against the leaf with gmatch. Matches are written as full "dir+name" paths
;   into ge_out[i*64], capped at ge_max entries. Returns count in ge_cnt.
;   Clobbers A, B, P1, P2 and all ge_* scratch. Uses de[]/gp/gs/gmatch from
;   lib_glob.inc. FNEXT/de_read (syscalls) clobber P1/P2 each iteration.
;
; Phase 1: scan pattern. ge_hs=1 if a '/' was seen (has dir prefix),
;   ge_sp = index of last '/', ge_pl = pattern length. Stop at NUL/CR/space.
glob_expand:
        LDA #0
        STA ge_hs                     ; has-slash flag = 0
        STA ge_sp                     ; slash position
        STA ge_pl                     ; pattern length
        LDA ge_pat
        TAP2L
        LDA ge_pat+1
        TAP2H
ge_scl: LDA (P2)
        LDB #0
        CMP
        JZ ge_scd                     ; NUL ends the pattern
        LDB #13
        CMP
        JZ ge_scd                     ; CR ends the pattern
        LDB #32
        CMP
        JZ ge_scd                     ; space ends the pattern
        LDB #'/'
        CMP
        JNZ ge_sci
        LDA ge_pl                     ; remember position of this '/'
        STA ge_sp
        LDA #1
        STA ge_hs
ge_sci: INP2                          ; advance ptr and length, loop
        LDA ge_pl
        INC
        STA ge_pl
        JMP ge_scl
; Phase 2: if a '/' was present, copy pat[0..ge_sp] into ge_dir (dir prefix,
;   including the trailing slash) and set ge_ls = index where the leaf starts.
;   With no '/', ge_dir stays empty and the leaf starts at 0.
ge_scd: LDA #0
        STA ge_ls                     ; leaf start index
        STA ge_dir                    ; empty dir prefix by default
        LDA ge_hs
        LDB #0
        CMP
        JZ ge_leaf0                   ; no slash -> leaf starts at 0
        LDA ge_sp
        INC
        STA ge_ls                     ; leaf starts just past the slash
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
; Copy chars 0..ge_sp inclusive (the slash itself) from pat (P2) to ge_dir (P1).
ge_dl:  LDA (P2)
        STA (P1)+
        INP2
        LDA ge_j
        LDB ge_sp
        CMP
        JZ ge_dde                     ; stop once we've copied the slash
        LDA ge_j
        INC
        STA ge_j
        JMP ge_dl
ge_dde: LDA #0
        STA (P1)                      ; NUL-terminate ge_dir
; Phase 3: copy the leaf (pat[ge_ls..ge_pl]) into ge_leaf as the glob pattern.
ge_leaf0:
        LDA ge_pat                    ; P2 = pat + ls  (16-bit add, carry to hi)
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
        STA ge_j                      ; source index runs ge_ls..ge_pl
ge_ll:  LDA ge_j
        LDB ge_pl
        CMP
        JZ ge_lle                     ; stop at end of pattern
        LDA (P2)
        STA (P1)+
        INP2
        LDA ge_j
        INC
        STA ge_j
        JMP ge_ll
ge_lle: LDA #0
        STA (P1)                      ; NUL-terminate ge_leaf
; Phase 4: open the target dir. With a prefix, FOPENDIR(ge_dir); otherwise the
;   current working directory via SYS_OPENCWD.
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
        JSR $0145                     ; FSDIRBUF: use RAM page $FA as dir buffer
        LDA #0
        STA ge_cnt                    ; match count = 0
; Phase 5: iterate directory entries. FNEXT sets C=1 when exhausted.
ge_nl:  LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $013C                     ; FNEXT: next raw dir entry
        JC ge_gdone                   ; carry -> no more entries
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR $201B                     ; SYS_DIRENTRY: parse entry into de[]
        LDA de
        LDB #'.'
        CMP
        JZ ge_nl                      ; skip "." / ".." / deleted (name[0]=='.')
        LDA de+12                     ; de+12 = entry type
        LDB #1
        CMP
        JNZ ge_nl                     ; type 1 = regular file; skip others
        LDA #<de                      ; trim 12-char padded name -> ge_nm
        TAP2L
        LDA #>de
        TAP2H
        LDA #<ge_nm
        TAP1L
        LDA #>ge_nm
        TAP1H
        LDA #0
        STA ge_j
; Copy up to 12 name chars, stopping early at the first space (name padding).
ge_tl:  LDA ge_j
        LDB #12
        CMP
        JZ ge_tld                     ; hit 12-char field width
        LDA (P2)
        LDB #32
        CMP
        JZ ge_tld                     ; space -> end of name
        STA (P1)+
        INP2
        LDA ge_j
        INC
        STA ge_j
        JMP ge_tl
ge_tld: LDA #0
        STA (P1)                      ; NUL-terminate ge_nm
; Match name against the leaf glob: gmatch(gp=ge_leaf pattern, gs=ge_nm name).
        LDA #<ge_leaf
        STA gp
        LDA #>ge_leaf
        STA gp+1
        LDA #<ge_nm
        STA gs
        LDA #>ge_nm
        STA gs+1
        JSR gmatch                    ; A=0 no match, nonzero match
        LDB #0
        CMP
        JZ ge_nl                      ; no match -> next entry
        LDA ge_cnt
        LDB ge_max
        CMP
        JC ge_nl                      ; CMP: C=1 when cnt>=max -> table full, drop
; Emit "ge_dir + ge_nm" into the slot; P1 points at ge_out + cnt*64.
        JSR ge_slot                   ; P1 = ge_out + cnt*64
        LDA #<ge_dir
        TAP2L
        LDA #>ge_dir
        TAP2H
ge_od:  LDA (P2)                      ; append dir prefix (stops at its NUL)
        LDB #0
        CMP
        JZ ge_odn
        STA (P1)+
        INP2
        JMP ge_od
ge_odn: LDA #<ge_nm                    ; then append the trimmed name
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
        STA (P1)                      ; NUL-terminate the full path
        LDA ge_cnt
        INC
        STA ge_cnt                    ; one more match recorded
        JMP ge_nl
ge_gdone:
        RTS                           ; ge_cnt holds the number of paths

; ge_slot: P1 = ge_out + ge_cnt*64  (address of the ge_cnt'th 64-byte slot).
;   No multiply instruction, so getmp = 64*ge_cnt is built by repeated 16-bit
;   +64 adds, then ge_out is added. Clobbers A, B, P1, getmp, gecar, ge_j2.
ge_slot:
        LDA #0
        STA getmp                     ; getmp (16-bit) = 0
        STA getmp+1
        LDA ge_cnt
        STA ge_j2                     ; loop counter = ge_cnt
ges_l:  LDA ge_j2
        LDB #0
        CMP
        JZ ges_d                      ; counter hit 0 -> getmp = 64*ge_cnt
        LDA getmp                     ; getmp += 64 (16-bit, carry to hi byte)
        LDB #64
        ADD
        STA getmp
        JNC ges_1                     ; no carry-out -> skip hi-byte bump
        LDA getmp+1
        INC
        STA getmp+1
ges_1:  LDA ge_j2
        DEC
        STA ge_j2
        JMP ges_l
ges_d:  LDA getmp                     ; getmp += ge_out, low byte first
        LDB ge_out
        ADD
        STA getmp
        LDA #0
        JNC ges_2                     ; capture carry-out into gecar
        LDA #1
ges_2:  STA gecar
        LDA getmp+1                   ; high byte + ge_out high + carry
        LDB ge_out+1
        ADD
        LDB gecar
        ADD
        STA getmp+1
        LDA getmp
        TAP1L
        LDA getmp+1
        TAP1H                         ; P1 = getmp
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
