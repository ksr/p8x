; mv.asm — hand-coded MV command (asm counterpart of os/commands/mv.c).
;   MV src dst        move/rename a file (copy-then-delete; P8XFS has no rename).
;   MV *.TMP TRASH    glob source -> move each match into the dst directory.
;
; abspath()/streq() inlined; move_one() = copy (FOPEN/FWOPEN stream) then FDELETE.
; A `*`/`?` source is expanded (lib_globx) and each match moved into the dst dir
; (which must exist). BIOS: FRESOLVE $0133, FOPEN $0124, FGETB $0127, FWOPEN
; $012A, FPUTB $012D, FCLOSE $0130, FDELETE $011E, FOPENDIR $0139, FNEXT $013C,
; FSDIRBUF $0145, SYS_DIRENTRY $201B. OS: SYS_GETCWD $2003, SYS_OPENCWD $2012,
; SYS_PUTS $200F, SYS_PUTC $2009, PUTS $0112, CONOUT $0103. Read buf $FC00.
; Entry: P2 = arg tail.
;#use glob
;#use globx
;#use abi

        .org $6A00
; Entry: the shell passes the argument tail (everything after "MV ") in P2.
; Stash that pointer in the m_arg word so we can walk it byte-by-byte and
; advance it by adding to the low/high halves (P8X has no 16-bit add).
        TPA2L
        STA m_arg
        TPA2H
        STA m_arg+1
; mv_sk: skip leading spaces (32) at m_arg. Falls through once a non-space
; is seen. m_arg is bumped a byte at a time; JNC/INC handles the low->high carry.
mv_sk:  LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ mv_chk
        LDA m_arg
        LDB #1
        ADD
        STA m_arg
        JNC mv_sk
        LDA m_arg+1
        INC
        STA m_arg+1
        JMP mv_sk
; mv_chk: no args (NUL / CR) -> usage. A leading '-' means a flag; only
; -h / -H are recognized and both just print usage/help.
mv_chk: LDA (P2)
        LDB #0
        CMP
        JZ mv_usage
        LDB #13
        CMP
        JZ mv_usage
        LDB #'-'
        CMP
        JNZ mv_word
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ mv_usage
        LDB #'H'
        CMP
        JZ mv_usage
; --- copy src WORD into patw, note glob (mg) --------------------------------
; Copy the source token (up to the next space/CR/NUL) into the patw buffer,
; setting mg=1 if any '*'/'?' is seen. Keeping the raw, un-abspath'd word lets
; the globber match against it later. mpw counts chars so we can advance m_arg
; past the token afterward.
mv_word:LDA #0
        STA mg
        LDA #<patw
        TAP1L
        LDA #>patw
        TAP1H
        LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA #0
        STA mpw
mpw_l:  LDA (P2)
        LDB #0
        CMP
        JZ mpw_d
        LDB #13
        CMP
        JZ mpw_d
        LDB #32
        CMP
        JZ mpw_d
        LDB #'*'
        CMP
        JZ mpw_g
        LDB #'?'
        CMP
        JZ mpw_g
        JMP mpw_s
mpw_g:  LDA #1                        ; wildcard seen: mark this a glob
        STA mg
        LDA (P2)                      ; reload the wildcard char to store it
mpw_s:  STA (P1)+
        INP2
        LDA mpw
        INC
        STA mpw
        JMP mpw_l
mpw_d:  LDA #0                        ; NUL-terminate patw
        STA (P1)
        LDA mpw
        LDB #0
        CMP
        JZ mv_usage2                 ; empty word
        LDA m_arg                    ; m_arg += mpw
        LDB mpw
        ADD
        STA m_arg
        JNC mv_dsk
        LDA m_arg+1
        INC
        STA m_arg+1
mv_dsk: LDA m_arg                    ; skip spaces before dst
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ mv_dchk
        LDA m_arg
        LDB #1
        ADD
        STA m_arg
        JNC mv_dsk
        LDA m_arg+1
        INC
        STA m_arg+1
        JMP mv_dsk
; mv_dchk: a missing dst (NUL/CR after the source) is a usage error. Otherwise
; resolve dst to an absolute path in m_dst, then branch on mg: glob vs single.
mv_dchk:LDA (P2)
        LDB #0
        CMP
        JZ mv_usage2
        LDB #13
        CMP
        JZ mv_usage2
        LDA #<m_dst                  ; abspath(m_dst, m_arg)
        STA ap_out
        LDA #>m_dst
        STA ap_out+1
        LDA m_arg
        STA ap_a
        LDA m_arg+1
        STA ap_a+1
        JSR abspath
        LDA mg
        LDB #0
        CMP
        JNZ mv_glob
; --- single source ---------------------------------------------------------
; Resolve the source word to absolute m_src, refuse a no-op (src == dst via
; streq), otherwise move_one. move_one returns A=1 when src wasn't found.
        LDA #<m_src
        STA ap_out
        LDA #>m_src
        STA ap_out+1
        LDA #<patw
        STA ap_a
        LDA #>patw
        STA ap_a+1
        JSR abspath
        LDA #<m_src
        STA se_p
        LDA #>m_src
        STA se_p+1
        LDA #<m_dst
        STA se_q
        LDA #>m_dst
        STA se_q+1
        JSR streq
        LDB #0
        CMP
        JNZ mv_same
        LDA #<m_src
        STA mo_s
        LDA #>m_src
        STA mo_s+1
        LDA #<m_dst
        STA mo_d
        LDA #>m_dst
        STA mo_d+1
        JSR move_one
        LDB #1
        CMP
        JZ mv_nosrc
        RTS
; --- glob: dst must be a dir; move each match into it -----------------------
mv_glob:LDA #<m_dst
        TAP1L
        LDA #>m_dst
        TAP1H
        LDA #0
        JSR FOPENDIR                 ; FOPENDIR(dst)
        JC mv_notdir
        LDA #<patw
        STA ge_pat
        LDA #>patw
        STA ge_pat+1
        LDA #<gfiles
        STA ge_out
        LDA #>gfiles
        STA ge_out+1
        LDA #24                      ; gfiles holds 24 * 64-byte name slots
        STA ge_max
        JSR glob_expand
        LDA ge_cnt
        LDB #0
        CMP
        JZ mv_nomatch                ; nothing matched the pattern
        LDA #0
        STA mgi
; mg_l: loop mgi = 0 .. ge_cnt-1. CMP sets C when mgi >= ge_cnt, so JC exits.
mg_l:   LDA mgi
        LDB ge_cnt
        CMP
        JC mg_done
        JSR cg_ptr                   ; cgp = gfiles + mgi*64
        LDA #<m_src                  ; abspath(m_src, cgp)
        STA ap_out
        LDA #>m_src
        STA ap_out+1
        LDA cgp
        STA ap_a
        LDA cgp+1
        STA ap_a+1
        JSR abspath
        JSR cg_base                  ; cgbp = basename
        LDA #<m_jdst                 ; joinp(m_jdst, m_dst, basename)
        STA jp_out
        LDA #>m_jdst
        STA jp_out+1
        LDA #<m_dst
        STA jp_dir
        LDA #>m_dst
        STA jp_dir+1
        LDA cgbp
        STA jp_name
        LDA cgbp+1
        STA jp_name+1
        JSR joinp
        LDA #<m_src                  ; skip a same-path match (src == jdst): moving
        STA se_p                     ;   a file onto itself would truncate+delete it
        LDA #>m_src
        STA se_p+1
        LDA #<m_jdst
        STA se_q
        LDA #>m_jdst
        STA se_q+1
        JSR streq
        LDB #0
        CMP
        JNZ mg_skip                  ; streq != 0 -> equal -> don't move
        LDA #<m_src
        STA mo_s
        LDA #>m_src
        STA mo_s+1
        LDA #<m_jdst
        STA mo_d
        LDA #>m_jdst
        STA mo_d+1
        JSR move_one
mg_skip:LDA mgi
        INC
        STA mgi
        JMP mg_l
mg_done:RTS
; --- message exits ---------------------------------------------------------
; Two sinks, because a message's kind decides where it may go. mv_put uses
; SYS_PUTS/SYS_PUTC (stdout) and mv_eput uses PUTS/CONOUT (raw console).
;
; mv_usage is reached from -h/-H AND from a bare `MV` with no args, and both
; just print help — the user asking for usage is requested OUTPUT, so it stays
; on stdout and `MV -h >notes` still captures it.
mv_usage:
        LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
mv_put: LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
; Everything below is an ERROR exit (mv.c returns 1 on each), so it goes to the
; raw console: stdout may be a redirect or a pipe, and `mv X Y >F` must not write
; "mv: source not found" INTO F, nor feed it to a pipe reader as data. The
; trailing newline uses CONOUT for the same reason — splitting the text and its
; terminator across two sinks would be worse than either. Matches mv.c's eputs().
mv_usage2:
        LDA #<u_use2
        TAP1L
        LDA #>u_use2
        TAP1H
        JMP mv_eput
mv_same:LDA #<u_same
        TAP1L
        LDA #>u_same
        TAP1H
        JMP mv_eput
mv_nosrc:
        LDA #<u_nosrc
        TAP1L
        LDA #>u_nosrc
        TAP1H
        JMP mv_eput
mv_notdir:
        LDA #<u_notdir
        TAP1L
        LDA #>u_notdir
        TAP1H
        JMP mv_eput
mv_nomatch:
        LDA #<u_nomat
        TAP1L
        LDA #>u_nomat
        TAP1H
mv_eput:LDA #0
        JSR PUTS
        LDA #10
        JSR CONOUT
        RTS

; move_one: copy file mo_s -> mo_d then delete mo_s (P8XFS has no rename).
;   in:  mo_s = src path, mo_d = dst path (both NUL-terminated, absolute)
;   out: A = 1 if src not found (nothing done), A = 0 on success
;   clobbers: P1/P2 (BIOS file calls), m_ch. Streams a byte at a time.
; FOPEN is pointed at the read buffer $FC00 (P1); the copy loop then FGETBs from
; the open read file and FPUTBs to the open write file until FGETB sets C (EOF).
move_one:
        LDA mo_s
        TAP1L
        LDA mo_s+1
        TAP1H
        LDA #0
        JSR FRESOLVE                 ; FRESOLVE src
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR FOPEN                    ; FOPEN $FC00 (C set => not found)
        JC mo_nf
        LDA mo_d
        TAP1L
        LDA mo_d+1
        TAP1H
        LDA #0
        JSR FRESOLVE                 ; FRESOLVE dst
        LDA #0
        JSR FWOPEN                   ; FWOPEN
mo_cp:  LDA #0
        JSR FGETB                    ; FGETB: byte in A, C set at EOF
        JC mo_end
        STA m_ch
        LDA #0
        TAP1L
        TAP1H
        LDA m_ch
        JSR FPUTB                    ; FPUTB
        JMP mo_cp
mo_end: LDA #0
        JSR FCLOSE                   ; FCLOSE
        LDA mo_s
        TAP1L
        LDA mo_s+1
        TAP1H
        LDA #0
        JSR FRESOLVE                 ; FRESOLVE src
        LDA #0
        JSR FDELETE                  ; FDELETE
        LDA #0
        RTS
mo_nf:  LDA #1
        RTS

; joinp: jp_out = jp_dir + "/" + jp_name
joinp:  LDA jp_out
        TAP1L
        LDA jp_out+1
        TAP1H
        LDA jp_dir
        TAP2L
        LDA jp_dir+1
        TAP2H
        LDA #0
        STA jp_i
jp_dl:  LDA (P2)
        LDB #0
        CMP
        JZ jp_dd
        STA (P1)+
        INP2
        LDA jp_i
        INC
        STA jp_i
        JMP jp_dl
jp_dd:  LDA jp_i                     ; add '/' unless empty or already ends '/'
        LDB #0
        CMP
        JZ jp_sl
        DEP1
        LDA (P1)
        INP1
        LDB #'/'
        CMP
        JZ jp_nm
jp_sl:  LDA #'/'
        STA (P1)+
        LDA jp_i
        INC
        STA jp_i
jp_nm:  LDA jp_name
        TAP2L
        LDA jp_name+1
        TAP2H
jp_nl:  LDA (P2)
        LDB #0
        CMP
        JZ jp_nd
        STA (P1)+
        INP2
        JMP jp_nl
jp_nd:  LDA #0
        STA (P1)
        RTS

; cg_ptr: cgp = gfiles + mgi*64  (pointer to the mgi-th 64-byte name slot).
; No multiply instruction: add 64 mgi times (cgt is the down-counter), then add
; the 16-bit gfiles base. cgcar carries the low-byte add into the high byte.
cg_ptr: LDA #0
        STA cgp
        STA cgp+1
        LDA mgi
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
        LDA cgk
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

; abspath: ap_out <- absolute path of the word at ap_a. The caller advances the
; argument cursor itself (mpw for the source word; the dst word is the last
; token), so no consumed-char count is returned.
abspath:LDA ap_a
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
ab_copy:LDA (P2)
        LDB #0
        CMP
        JZ ab_done
        LDB #13
        CMP
        JZ ab_done
        LDB #32
        CMP
        JZ ab_done
        STA (P1)+
        INP2
        JMP ab_copy
ab_done:LDA #0
        STA (P1)
        RTS

; streq: A = 1 if the NUL strings at se_p and se_q are equal, else 0.
streq:  LDA se_p
        TAP1L
        LDA se_p+1
        TAP1H
        LDA se_q
        TAP2L
        LDA se_q+1
        TAP2H
se_l:   LDA (P1)
        STA se_c
        LDA (P2)
        LDB se_c
        CMP
        JNZ se_ne
        LDA se_c
        LDB #0
        CMP
        JZ se_eq
        INP1
        INP2
        JMP se_l
se_ne:  LDA #0
        RTS
se_eq:  LDA #1
        RTS

u_use:  .asciiz "usage: MV src dst   move/rename a file (or a glob into a dir)"
u_use2: .asciiz "usage: MV src dst"
u_same: .asciiz "mv: source and dest are the same"
u_nosrc:.asciiz "mv: source not found"
u_notdir:.asciiz "mv: target is not a directory"
u_nomat:.asciiz "mv: no match"

; --- variables / scratch buffers -------------------------------------------
m_arg:  .fill 2                      ; walking pointer into the argument tail
m_ch:   .fill 1                      ; one byte in flight during the copy loop
mg:     .fill 1                      ; 1 if source contains a wildcard (glob)
mpw:    .fill 1                      ; length of the source word copied to patw
mgi:    .fill 1                      ; current glob match index
cgp:    .fill 2
cgbp:   .fill 2
cgk:    .fill 1
cgt:    .fill 1
cgcar:  .fill 1
ap_out: .fill 2
ap_a:   .fill 2
se_p:   .fill 2
se_q:   .fill 2
se_c:   .fill 1
mo_s:   .fill 2
mo_d:   .fill 2
jp_out: .fill 2
jp_dir: .fill 2
jp_name:.fill 2
jp_i:   .fill 1
patw:   .fill 80                     ; raw source word (kept for glob matching)
m_src:  .fill 80                     ; absolute source path
m_dst:  .fill 80                     ; absolute dest path (a dir when globbing)
m_jdst: .fill 80                     ; m_dst + "/" + basename for each match
gfiles: .fill 1536                   ; 24 glob-match slots * 64 bytes each
