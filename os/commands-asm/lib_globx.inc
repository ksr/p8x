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
        LPW2 ge_pat                ; <- tierA: pointer load (next: LDA)
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
        LDA #62                       ; ge_dir[64] holds ge_sp+1 chars + NUL,
        LDB ge_sp                     ; so the last '/' must sit at index <= 62
        CMP
        JC ge_dok                     ; C=1 -> 62 >= ge_sp -> the prefix fits
        LDA #0
        STA ge_cnt                    ; oversize prefix names no openable dir
        RTS
ge_dok: LDA ge_sp
        INC
        STA ge_ls                     ; leaf starts just past the slash
        LPW2 ge_pat                ; <- tierA: pointer load (next: LDA)
        LDP1 #ge_dir                ; <- tierA: pointer constant (next: LDA)
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
        LDP1 #ge_leaf                ; <- tierA: pointer constant (next: LDA)
        LDA ge_ls
        STA ge_j                      ; source index runs ge_ls..ge_pl
        LDA #0
        STA ge_k                      ; chars written: ge_leaf[16] = 15 + NUL
ge_ll:  LDA ge_j
        LDB ge_pl
        CMP
        JZ ge_lle                     ; stop at end of pattern
        LDA ge_k
        LDB #15
        CMP
        JZ ge_lle                     ; leaf > 15 chars -> truncate; P8XFS names
                                      ; are 12, so it could match nothing anyway
        LDA (P2)
        STA (P1)+
        INP2
        LDA ge_k
        INC
        STA ge_k
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
        LDP1 #ge_dir                ; <- tierA: pointer constant (next: LDA)
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
        LDP1 #de                ; <- tierA: pointer constant (next: LDA)
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
        LDP2 #de                ; <- tierA: pointer constant (next: LDA)
        LDP1 #ge_nm                ; <- tierA: pointer constant (next: LDA)
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
        LDW gp,#ge_leaf                ; <- tierA: address constant (next: LDA)
        LDW gs,#ge_nm                ; <- tierA: address constant (next: JSR gmatch)
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
        LDA #0
        STA ge_k                      ; a slot is 64 bytes: 63 chars + NUL
        LDP2 #ge_dir                ; <- tierA: pointer constant (next: LDA)
ge_od:  LDA (P2)                      ; append dir prefix (stops at its NUL)
        LDB #0
        CMP
        JZ ge_odn
        LDA ge_k
        LDB #63
        CMP
        JZ ge_ot                      ; slot full -> truncate, never overrun
        LDA (P2)
        STA (P1)+
        LDA ge_k
        INC
        STA ge_k
        INP2
        JMP ge_od
ge_odn: LDP2 #ge_nm                ; <- tierA: pointer constant (next: LDA)
ge_onl: LDA (P2)
        LDB #0
        CMP
        JZ ge_ot
        LDA ge_k
        LDB #63
        CMP
        JZ ge_ot                      ; slot full -> truncate, never overrun
        LDA (P2)
        STA (P1)+
        LDA ge_k
        INC
        STA ge_k
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
        LDW getmp,#0                ; <- tierA: zero word (next: LDA)
        LDA ge_cnt
        STA ge_j2                     ; loop counter = ge_cnt
ges_l:  LDA ge_j2
        LDB #0
        CMP
        JZ ges_d                      ; counter hit 0 -> getmp = 64*ge_cnt
        ADDW getmp,#64                ; <- tierA: 16-bit ADDW chain, skip label ges_1 dropped (next: LDA)
        LDA ge_j2
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
        LPW1 getmp                ; <- tierA: pointer load (next: RTS)
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
ge_k:   .fill 1
getmp:  .fill 2
gecar:  .fill 1
ge_dir: .fill 64
ge_leaf:.fill 16
ge_nm:  .fill 16
