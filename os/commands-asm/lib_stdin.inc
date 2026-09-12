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
; FSDIRBUF $0145, SYS_DIRENTRY $201B. OS: SYS_GETCWD $2003, SYS_GETC $200C,
; SYS_OPENCWD $2012.

; ---- openarg --------------------------------------------------------------
; Decide how to source input for one argv word.
;   in : oa_a  = pointer to the arg string (word)
;   out: A = 0 read from stdin (empty/CR arg), 1 opened a file, 2 not found
;        fromfile set; on a *|? arg, gfiles[]/gnf hold the expanded match list
;        and the first match is opened (nextc walks the rest).
; Clobbers A/B/P2; leaves the open file positioned at byte 0.
openarg:
        LDA #0
        STA fromfile
        STA gnf
        STA gidx
        LPW2 oa_a                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #0
        CMP
        JZ oa_stdin
        LDB #13
        CMP
        JZ oa_stdin
        LDA #0
        STA oa_g
        LPW2 oa_a                ; <- tierA: pointer load (next: LDA)
oa_scl: LDA (P2)                       ; scan arg for a '*' or '?' -> oa_g (is-glob)
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
        MOVW ge_pat,oa_a                ; <- tierA: word move (next: LDA)
        LDW ge_out,#gfiles                ; <- tierA: address constant (next: LDA)
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
        LDW op_a,#gfiles                ; <- tierA: address constant (next: JSR open_path)
        JSR open_path
        RTS
oa_single:
        LDA #1
        STA fromfile
        MOVW op_a,oa_a                ; <- tierA: word move (next: JSR open_path)
        JSR open_path
        RTS
oa_stdin:
        LDA #0
        RTS
oa_nf:  LDA #2
        RTS

; ---- nextc ----------------------------------------------------------------
; Return the next input byte, transparently spanning glob matches.
;   out: A = byte, carry CLEAR on success / SET at end-of-input
; On file EOF it advances gidx to the next glob match and reopens; when no
; more matches remain it reports EOF. Clobbers A/B/P1/P2 (FGETB clobbers P1/P2).
nextc:  LDA fromfile
        LDB #0
        CMP
        JNZ nc_file
        LDA #0
        JSR $200C                     ; stdin: A=byte, C=EOF (passthrough)
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
        CMP                           ; CMP sets C when gtmp(=gidx+1) >= gnf
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

; gfile_ptr: op_a = &gfiles[gidx]  (64-byte fixed-stride path slots)
; Computes gidx*64 by repeated add (no MUL), then adds the gfiles base as a
; 16-bit sum via gcarry. In: gidx. Out: op_a word. Clobbers A/B, gtmp2, gcarry.
gfile_ptr:
        LDW op_a,#0                ; <- tierA: zero word (next: LDA)
        LDA gidx
        STA gtmp2
gfp_l:  LDA gtmp2
        LDB #0
        CMP
        JZ gfp_d
        ADDW op_a,#64                ; <- tierA: 16-bit ADDW chain, skip label gfp_1 dropped (next: LDA)
        LDA gtmp2
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
; Open the file named by op_a into the read buffer at $FC00.
;   in : op_a = path word (relative or absolute)
;   out: A = 1 opened / 2 not found
; A relative path (no leading '/') is prefixed with SYS_GETCWD into spath so
; FRESOLVE/FOPENDIR, which start at root rather than CWD, resolve it correctly.
; spath[80] holds 79 chars + NUL; op_n counts what has been written so a long
; CWD+name truncates (FRESOLVE then fails -> 2) instead of running past spath.
; Clobbers A/B/P1/P2, op_n and spath.
open_path:
        LDA #0
        STA op_n
        LPW2 op_a                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #'/'
        CMP
        JZ opa_abs
        LDP1 #spath                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR $2003
        LDP1 #spath                ; <- tierA: pointer constant (next: LDA)
opa_sl: LDA (P1)
        LDB #0
        CMP
        JZ opa_sld
        INP1
        LDA op_n                      ; count the CWD prefix as written
        INC
        STA op_n
        JMP opa_sl
opa_sld:DEP1
        LDA (P1)
        INP1
        LDB #'/'
        CMP
        JZ opa_cp
        LDA #'/'
        STA (P1)+
        LDA op_n
        INC
        STA op_n
        JMP opa_cp
opa_abs:LDP1 #spath                ; <- tierA: pointer constant (next: LDA)
opa_cp: LPW2 op_a                ; <- tierA: pointer load (next: LDA)
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
        LDA op_n                      ; C=1 -> op_n >= 79 chars: truncate here
        LDB #79
        CMP
        JC opa_end
        LDA (P2)                      ; reload the char (the cap CMP took A)
        STA (P1)+
        LDA op_n
        INC
        STA op_n
        INP2
        JMP opa_cl
opa_end:LDA #0
        STA (P1)
        LDP1 #spath                ; <- tierA: pointer constant (next: LDA)
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
; Expand a single *|? pattern into a list of matching regular-file paths.
;   in : ge_pat = pattern word, ge_out = dest array word, ge_max = slot cap
;   out: ge_cnt files written, ge_out[i*64] = full path (dir prefix + name)
; The pattern is split at its last '/': ge_dir holds the directory prefix
; (or none -> current dir via SYS_OPENCWD) and ge_leaf the wildcard leaf.
; Directory is read with FSDIRBUF at page $FA; entries are matched with gmatch,
; '.'-prefixed and non-regular (de+12 != 1) entries skipped, and the list is
; truncated at ge_max. Clobbers A/B/P1/P2 and most ge_* scratch.
glob_expand:
        LDA #0
        STA ge_hs
        STA ge_sp
        STA ge_pl
        LPW2 ge_pat                ; <- tierA: pointer load (next: LDA)
ge_scl: LDA (P2)                       ; scan pattern; ge_sp=last '/' index, ge_hs=has-slash
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
        LPW2 ge_pat                ; <- tierA: pointer load (next: LDA)
        LDP1 #ge_dir                ; <- tierA: pointer constant (next: LDA)
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
        LDP1 #ge_leaf                ; <- tierA: pointer constant (next: LDA)
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
        JSR $0145                     ; FSDIRBUF $FA
        LDA #0
        STA ge_cnt
ge_nl:  LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $013C                     ; FNEXT
        JC ge_gdone
        LDP1 #de                ; <- tierA: pointer constant (next: LDA)
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
        LDP2 #de                ; <- tierA: pointer constant (next: LDA)
        LDP1 #ge_nm                ; <- tierA: pointer constant (next: LDA)
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
        LDW gp,#ge_leaf                ; <- tierA: address constant (next: LDA)
        LDW gs,#ge_nm                ; <- tierA: address constant (next: JSR gmatch)
        JSR gmatch
        LDB #0
        CMP
        JZ ge_nl                      ; no match
        LDA ge_cnt
        LDB ge_max
        CMP
        JC ge_nl                      ; cnt >= max -> drop
        JSR ge_slot                   ; P1 = ge_out + cnt*64
        LDP2 #ge_dir                ; <- tierA: pointer constant (next: LDA)
ge_od:  LDA (P2)
        LDB #0
        CMP
        JZ ge_odn
        STA (P1)+
        INP2
        JMP ge_od
ge_odn: LDP2 #ge_nm                ; <- tierA: pointer constant (next: LDA)
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

; ge_slot: P1 = &ge_out[ge_cnt]  (ge_out + ge_cnt*64, same stride as gfile_ptr)
; In: ge_cnt, ge_out. Out: P1. Clobbers A/B, getmp, ge_j2, gecar.
ge_slot:
        LDW getmp,#0                ; <- tierA: zero word (next: LDA)
        LDA ge_cnt
        STA ge_j2
ges_l:  LDA ge_j2
        LDB #0
        CMP
        JZ ges_d
        ADDW getmp,#64                ; <- tierA: 16-bit ADDW chain, skip label ges_1 dropped (next: LDA)
        LDA ge_j2
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
        LPW1 getmp                ; <- tierA: pointer load (next: RTS)
        RTS

; ---- gmatch / upper (case-insensitive * ? whole-string matcher) -----------
; gmatch: does glob pattern gp match the whole string gs? (case-insensitive)
;   in : gp = pattern word, gs = string word
;   out: A = 1 match / 0 no match
; '?' matches any one char; '*' matches zero-or-more via recursion: it saves
; gp/gs on the stack, tries matching the tail here, and on failure advances gs
; and retries (classic backtracking). Recurses through JSR gmatch, so it leans
; on the return stack. Clobbers A/B/P1/P2 and gpc/gsc/gmr.
gmatch: LPW1 gp                ; <- tierA: pointer load (next: LDA)
        LDA (P1)
        STA gpc
        LDB #'*'
        CMP
        JZ gm_star
        LDB #0
        CMP
        JZ gm_pend
        LPW2 gs                ; <- tierA: pointer load (next: LDA)
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
gm_adv: INCW gp                ; <- tierA: 16-bit INCW chain, skip label gm_a1 dropped (next: LDA)
gm_a1:  INCW gs                ; <- tierA: 16-bit INCW chain, skip label gm_a2 dropped (next: JMP gmatch -> LDA)
        JMP gmatch
gm_pend:LPW2 gs                ; <- tierA: pointer load (next: LDA)
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
        LPW2 gs                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #0
        CMP
        JZ gm_r0
        INCW gs                ; <- tierA: 16-bit INCW chain before JMP gm_s0 (next: JMP gm_s0 -> LDA)
        JMP gm_s0
; upper: fold A to upper-case (ASCII), leave other bytes unchanged.
; In: A = char. Out: A = folded char. Clobbers B, uch.
upper:  STA uch
        LDB #'a'                       ; below 'a' (97)? CMP clears C when A<B
        CMP
        JNC up_no
        LDA uch
        LDB #123                       ; at/above 'z'+1 (123)? CMP sets C when A>=B
        CMP
        JC up_no
        LDA uch
        LDB #32                        ; in a..z: clear bit 5 by subtracting 32
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
op_n:   .fill 1
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
