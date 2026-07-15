; dir.asm — hand-coded DIR command (asm counterpart of os/commands/dir.c).
;   DIR [-R] [-S] [path|glob]   list a directory (size column + name; '/' = dir).
;
; Mirrors dir.c: optional -R recursion, -S size sort, a `*`/`?` glob in the last
; path component (dir split + case-insensitive gmatch filter), a 6-wide right-
; justified size column (blank for dirs).
;
; SORT: entries are buffered per directory (name/len/dir-flag/LBA into single
; global arrays reused at every recursion level), then a selection sort orders an
; index array `eidx`, and the level is printed in that order. Default key is name,
; raw ASCII; -S sorts by byte size LARGEST first with a name tiebreak, and a
; directory (blank size) counts as size 0 so it sorts after all files. Sizes are
; 24-bit (elen2 = de[17]); the column prints via a byte-wise divmod10 (dm10) and
; sorts with a 24-bit compare. CMP is unsigned, matching p8cc's unsigned < / >. A level is fully collected+printed (recording child LBAs
; into the per-depth csub[] array) BEFORE descending, so a child's collect() may
; reuse the global buffers freely.
;
; Recursion uses depth-indexed arrays + a global w_depth (see tree.asm; P3 is the
; stack pointer so only P1/P2 are usable). Iterates on FSDIRBUF page $FA.
;
; BIOS: FOPENDIR $0139, FNEXT $013C, FSDIRBUF $0145, SYS_DIRENTRY $201B,
; SYS_OPENDIR $201E. OS: SYS_OPENCWD $2012, SYS_PUTC $2009, SYS_PUTS $200F.
; The CPU has no divide, so the size printer uses a divmod10 subtraction routine.
; Entry: P2 = arg tail.
;#use abi

        .org $6A00
; ======================= main ==============================================
        TPA2L
        STA m_arg
        TPA2H
        STA m_arg+1
        LDA #0
        STA rec
        STA szmode
        STA filemode                 ; not listing a single file (yet)
        STA gpat                     ; gpat[0]=0 (no filter)
; skip spaces (advance m_arg)
d_sk:   LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ d_hchk
        JSR arg_inc
        JMP d_sk
; -h is only recognized as the FIRST token (mirror dir.c: the -h check precedes
; the flag loop, so `dir -R -h` treats -h as a path, not a usage request).
d_hchk: LDA (P2)
        LDB #'-'
        CMP
        JNZ d_opt
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ d_usage
        LDB #'H'
        CMP
        JZ d_usage
; flag loop: -R/-r recurse, -S/-s size sort (each its own '-x' token, any order)
d_opt:  LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #'-'
        CMP
        JNZ d_scan
        INP2
        LDA (P2)
        LDB #'R'
        CMP
        JZ d_setr
        LDB #'r'
        CMP
        JZ d_setr
        LDB #'S'
        CMP
        JZ d_sets
        LDB #'s'
        CMP
        JZ d_sets
        JMP d_scan                   ; some other '-x': fall through (m_arg at '-')
d_setr: LDA #1
        STA rec
        JMP d_oadv
d_sets: LDA #1
        STA szmode
d_oadv: JSR arg_inc                  ; skip '-'
        JSR arg_inc                  ; skip flag char
d_osk:  LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ d_opt                    ; next flag or the path
        JSR arg_inc
        JMP d_osk
; scan path token: hasslash/slashpos, g(glob), i(length)
d_scan: LDA #0
        STA hasslash
        STA slashpos
        STA gflag
        STA plen
        LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
d_scl:  LDA (P2)
        LDB #0
        CMP
        JZ d_scd
        LDB #13
        CMP
        JZ d_scd
        LDB #32
        CMP
        JZ d_scd
        LDB #'/'
        CMP
        JNZ d_scg
        LDA plen                     ; slashpos = current index
        STA slashpos
        LDA #1
        STA hasslash
d_scg:  LDA (P2)
        LDB #'*'
        CMP
        JZ d_scgy
        LDB #'?'
        CMP
        JNZ d_sci
d_scgy: LDA #1
        STA gflag
d_sci:  INP2
        LDA plen
        INC
        STA plen
        JMP d_scl
d_scd:  LDA #0
        STA notf
; ---- decide the source directory ------------------------------------------
        LDA gflag
        LDB #0
        CMP
        JNZ d_glob
        ; not glob: empty -> OPENCWD, else FOPENDIR(arg)
        LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ d_cwd
        LDB #13
        CMP
        JZ d_cwd
        LDA m_arg                    ; abspath(apath, m_arg) — CWD-prefix if relative
        STA ap_a
        LDA m_arg+1
        STA ap_a+1
        LDA #<apath
        STA ap_out
        LDA #>apath
        STA ap_out+1
        JSR abspath
        LDA #<apath                  ; FOPENDIR(apath)
        TAP1L
        LDA #>apath
        TAP1H
        LDA #0
        JSR FOPENDIR
        JNC d_ok
        ; not a directory -> list it as a single file: reuse the glob split
        ; (gpat = the leaf, open its parent) and note filemode for the not-found
        ; check. A file has no subtree, so force rec off.
        LDA #1
        STA filemode
        LDA #0
        STA rec
        JMP d_glob
d_cwd:  LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR SYS_OPENCWD              ; SYS_OPENCWD
        JMP d_ok
; ---- glob: split dir + pattern --------------------------------------------
d_glob: ; ls = hasslash ? slashpos+1 : 0 ; gpat = arg[ls..plen)
        LDA #0
        STA ls
        LDA hasslash
        LDB #0
        CMP
        JZ d_gp
        LDA slashpos
        INC
        STA ls
d_gp:   ; P2 = arg + ls ; copy to gpat until index==plen
        LDA m_arg
        LDB ls
        ADD
        TAP2L
        LDA m_arg+1
        JNC d_gp0
        INC
d_gp0:  TAP2H
        LDA #<gpat
        TAP1L
        LDA #>gpat
        TAP1H
        LDA ls
        STA cnt                      ; index runs ls..plen
d_gpl:  LDA cnt
        LDB plen
        CMP
        JZ d_gpe
        LDA (P2)
        STA (P1)+
        INP2
        LDA cnt
        INC
        STA cnt
        JMP d_gpl
d_gpe:  LDA #0
        STA (P1)                     ; gpat NUL
        ; if hasslash: dbuf = arg[0..slashpos] ; FOPENDIR(dbuf) else OPENCWD
        LDA hasslash
        LDB #0
        CMP
        JZ d_gcwd
        LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA #<dbuf
        TAP1L
        LDA #>dbuf
        TAP1H
        LDA #0
        STA cnt                      ; j 0..slashpos inclusive
d_gdl:  LDA (P2)
        STA (P1)+
        INP2
        LDA cnt
        LDB slashpos
        CMP
        JZ d_gde                     ; just copied index==slashpos
        LDA cnt
        INC
        STA cnt
        JMP d_gdl
d_gde:  LDA #0
        STA (P1)
        LDA #<dbuf                    ; abspath(apath, dbuf) — CWD-prefix if relative
        STA ap_a
        LDA #>dbuf
        STA ap_a+1
        LDA #<apath
        STA ap_out
        LDA #>apath
        STA ap_out+1
        JSR abspath
        LDA #<apath                  ; FOPENDIR(apath)
        TAP1L
        LDA #>apath
        TAP1H
        LDA #0
        JSR FOPENDIR                 ; FOPENDIR(dbuf via apath)
        JNC d_ok
        LDA #1
        STA notf
        JMP d_ok
d_gcwd: LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR SYS_OPENCWD
; ---- opened (or not) ------------------------------------------------------
d_ok:   LDA notf
        LDB #0
        CMP
        JZ d_go
        LDA #<u_nf                   ; "dir: not found"
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
d_go:   LDA #0                        ; FSDIRBUF page $FA
        TAP1L
        TAP1H
        LDA #$FA
        JSR FSDIRBUF
        LDA rec
        LDB #0
        CMP
        JZ d_flat
        LDA #0
        STA w_depth
        JSR walk
        RTS
; single-level listing: collect + sort, then print in sorted order
d_flat: JSR collect
        LDA #0
        STA shown
        LDA #0
        STA pri
df_l:   LDA pri
        LDB ecnt
        CMP
        JZ d_fdone
        LDA pri
        JSR eidx_get                 ; A = eidx[pri]
        STA em
        JSR nameat                   ; nbuf <- enam[em]
        LDA #0
        STA sh_depth
        JSR setbuf                   ; sh_dir/sh_sz from eisd[em]/elen[em]
        JSR show
        LDA pri
        INC
        STA pri
        JMP df_l
d_fdone:LDA filemode                 ; a single-file arg that matched nothing?
        LDB #0
        CMP
        JZ df_ok
        LDA shown
        LDB #0
        CMP
        JNZ df_ok
        LDA #<u_nf                    ; "dir: not found"
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
df_ok:  RTS
d_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; arg_inc: m_arg += 1
arg_inc:
        LDA m_arg
        LDB #1
        ADD
        STA m_arg
        JNC ai1
        LDA m_arg+1
        INC
        STA m_arg+1
ai1:    RTS

; ======================= walk (recursive, like tree) =======================
; collect+sort this level, print it (recording child LBAs into csub[depth] in
; sorted order), then descend into each recorded child.
walk:   JSR collect
        JSR nsub_addr
        LDA #0
        STA (P1)                     ; nsub[depth]=0
        LDA #0
        STA pri
w_pl:   LDA pri
        LDB ecnt
        CMP
        JZ w_desc
        LDA pri
        JSR eidx_get
        STA em
        JSR nameat
        LDA w_depth
        STA sh_depth
        JSR setbuf
        JSR show
        LDA em                       ; if dir, record LBA
        JSR eisd_get
        LDB #0
        CMP
        JZ w_pnext
        JSR nsub_addr
        LDA (P1)
        LDB #64
        CMP
        JC w_pnext                   ; nsub>=64 -> skip
        JSR nsub_addr
        LDA (P1)
        STA kk
        JSR csub_addr                ; P1 = csub[depth][kk]
        TPA1L
        STA cdst
        TPA1H
        STA cdst+1
        LDA em                       ; P2 = elba + em*2
        STA mi
        JSR elba_ptr
        LDA (P2)
        STA lba
        INP2
        LDA (P2)
        STA lba+1
        LDA cdst                     ; store lba into csub slot
        TAP1L
        LDA cdst+1
        TAP1H
        LDA lba
        STA (P1)+
        LDA lba+1
        STA (P1)
        JSR nsub_addr
        LDA (P1)
        INC
        STA (P1)
w_pnext:LDA pri
        INC
        STA pri
        JMP w_pl
w_desc: JSR idx_addr
        LDA #0
        STA (P1)
w_dl:   JSR idx_addr
        LDA (P1)
        STA kk
        JSR nsub_addr
        LDA (P1)
        LDB kk
        CMP
        JZ w_ret
        JSR csub_addr
        LDA (P1)+
        STA lba
        LDA (P1)
        STA lba+1
        LDA lba
        TAP1L
        LDA lba+1
        TAP1H
        LDA #0
        JSR SYS_OPENDIR              ; SYS_OPENDIR
        LDA #0
        TAP1L
        TAP1H
        LDA #$FA
        JSR FSDIRBUF                 ; FSDIRBUF $FA
; Depth cap: nsub/idx hold 16 and csub is 16*128, so descending at w_depth==16
; would index one past every per-level array. Stop descending instead — the same
; silent-cap behaviour this command already has for >24 children per level.
        LDA w_depth
        INC
        LDB #16                      ; MAXD (nsub/idx .fill 16, csub 16*128)
        CMP
        JC  w_deep                   ; depth+1 >= 16 -> too deep, don't descend
        STA w_depth
        JSR walk
        LDA w_depth
        DEC
        STA w_depth
w_deep: JSR idx_addr
        LDA (P1)
        INC
        STA (P1)
        JMP w_dl
w_ret:  RTS

; ======================= collect (buffer + selection sort) =================
; Iterate the ALREADY-open directory, snapshot every non-dot entry into the
; global buffers (enam/elen/eisd/elba) up to 64, then sort eidx[] via before().
collect:LDA #0
        STA ecnt
col_nx: LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR FNEXT                    ; FNEXT
        JC col_srt
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR SYS_DIRENTRY             ; de_read
        LDA de                       ; skip '.'/'..'
        LDB #'.'
        CMP
        JZ col_nx
        LDA ecnt
        LDB #64
        CMP
        JC col_nx                    ; ecnt>=64 -> don't store
        ; enam + ecnt*12 <- de[0..11]
        LDA ecnt
        STA mi
        JSR enam_ptr                 ; dptr = enam + ecnt*12
        LDA dptr
        TAP1L
        LDA dptr+1
        TAP1H
        LDA #<de
        TAP2L
        LDA #>de
        TAP2H
        LDA #0
        STA cnt
col_cp: LDA cnt
        LDB #12
        CMP
        JZ col_meta
        LDA (P2)
        STA (P1)+
        INP2
        LDA cnt
        INC
        STA cnt
        JMP col_cp
col_meta:
        LDA de+12                    ; eisd = (de[12]==2)
        LDB #2
        CMP
        JNZ col_file
        LDA #1
        STA cflg2
        JMP col_sisd
col_file:
        LDA #0
        STA cflg2
col_sisd:
        LDA ecnt                     ; eisd[ecnt] = cflg2
        LDB #<eisd
        ADD
        TAP1L
        LDA #>eisd
        JNC col_i1
        INC
col_i1: TAP1H
        LDA cflg2
        STA (P1)
        LDA ecnt                     ; elen[ecnt] (0 for dir, else de[13..14])
        STA mi
        JSR elen_ptr
        LDA cflg2
        LDB #0
        CMP
        JZ col_lfile
        LDA #0
        STA (P2)
        INP2
        LDA #0
        STA (P2)
        JMP col_lba
col_lfile:
        LDA de+13
        STA (P2)
        INP2
        LDA de+14
        STA (P2)
col_lba:
        LDA ecnt                     ; elen2[ecnt] = (dir ? 0 : de[17])  24-bit size hi
        LDB #<elen2
        ADD
        TAP1L
        LDA #>elen2
        JNC col_e2p
        INC
col_e2p:TAP1H
        LDA cflg2
        LDB #0
        CMP
        JZ col_e2f
        LDA #0
        STA (P1)
        JMP col_e2d
col_e2f:LDA de+17
        STA (P1)
col_e2d:LDA ecnt                     ; elba[ecnt] = de[15..16]
        STA mi
        JSR elba_ptr
        LDA de+15
        STA (P2)
        INP2
        LDA de+16
        STA (P2)
        LDA ecnt
        INC
        STA ecnt
        JMP col_nx
col_srt:
        LDA #0                       ; eidx[i] = i
        STA si
csi_l:  LDA si
        LDB ecnt
        CMP
        JZ csrt
        LDA si
        LDB #<eidx
        ADD
        TAP1L
        LDA #>eidx
        JNC csi_1
        INC
csi_1:  TAP1H
        LDA si
        STA (P1)
        LDA si
        INC
        STA si
        JMP csi_l
csrt:   LDA #0                       ; selection sort
        STA si
srt_i:  LDA si
        LDB ecnt
        CMP
        JZ srt_dn
        LDA si
        STA sm                       ; m = i
        LDA si
        LDB #1
        ADD
        STA sj                       ; j = i+1
srt_j:  LDA sj
        LDB ecnt
        CMP
        JZ srt_sw
        LDA sj                       ; before(eidx[sj], eidx[sm]) ?
        JSR eidx_get
        STA bA
        LDA sm
        JSR eidx_get
        STA bB
        JSR before
        LDB #0
        CMP
        JZ srt_jn
        LDA sj                       ; new minimum
        STA sm
srt_jn: LDA sj
        INC
        STA sj
        JMP srt_j
srt_sw: LDA si                       ; swap eidx[si], eidx[sm]
        JSR eidx_get
        STA tA
        LDA sm
        JSR eidx_get
        STA tB
        LDA si
        LDB #<eidx
        ADD
        TAP1L
        LDA #>eidx
        JNC sw_1
        INC
sw_1:   TAP1H
        LDA tB
        STA (P1)
        LDA sm
        LDB #<eidx
        ADD
        TAP1L
        LDA #>eidx
        JNC sw_2
        INC
sw_2:   TAP1H
        LDA tA
        STA (P1)
        LDA si
        INC
        STA si
        JMP srt_i
srt_dn: RTS

; before: A=1 if entry bA sorts strictly before entry bB, else 0.
;   size mode: larger key first, name ascending on a tie; name mode: name asc.
before: LDA szmode
        LDB #0
        CMP
        JZ bf_name
        LDA bA                       ; keyA = skey(bA)
        STA em2
        JSR skey
        LDA keyw
        STA keyA
        LDA keyw+1
        STA keyA+1
        LDA keyw+2
        STA keyA+2
        LDA bB                       ; keyB = skey(bB)
        STA em2
        JSR skey
        LDA keyw
        STA keyB
        LDA keyw+1
        STA keyB+1
        LDA keyw+2
        STA keyB+2
        LDA keyA+2                   ; 24-bit compare, byte 2 (hi) first (unsigned)
        LDB keyB+2
        CMP
        JZ bf_c1
        JC bf_yes
        LDA #0
        RTS
bf_c1:  LDA keyA+1                   ; byte 1
        LDB keyB+1
        CMP
        JZ bf_lo
        JC bf_yes
        LDA #0
        RTS
bf_lo:  LDA keyA                     ; byte 0
        LDB keyB
        CMP
        JZ bf_name                   ; equal keys -> name tiebreak
        JC bf_yes
        LDA #0
        RTS
bf_yes: LDA #1
        RTS
bf_name:
        JSR name_before              ; A = (name(bA) < name(bB))
        RTS

; name_before: A=1 if the 12-byte padded name of bA < that of bB (raw ASCII).
name_before:
        LDA bA
        STA mi
        JSR enam_ptr
        LDA dptr
        STA naddrA
        LDA dptr+1
        STA naddrA+1
        LDA bB
        STA mi
        JSR enam_ptr
        LDA dptr
        STA naddrB
        LDA dptr+1
        STA naddrB+1
        LDA #0
        STA cnt
nb_l:   LDA cnt
        LDB #12
        CMP
        JZ nb_eq
        LDA naddrA                   ; ca = [naddrA + cnt]
        LDB cnt
        ADD
        TAP1L
        LDA naddrA+1
        JNC nb_a1
        INC
nb_a1:  TAP1H
        LDA (P1)
        STA nca
        LDA naddrB                   ; cb = [naddrB + cnt]
        LDB cnt
        ADD
        TAP2L
        LDA naddrB+1
        JNC nb_b1
        INC
nb_b1:  TAP2H
        LDA (P2)
        STA ncb
        LDA nca
        LDB ncb
        CMP
        JZ nb_nx                     ; equal byte -> keep comparing
        JC nb_no                     ; nca > ncb -> a > b -> not before
        LDA #1
        RTS
nb_no:  LDA #0
        RTS
nb_nx:  LDA cnt
        INC
        STA cnt
        JMP nb_l
nb_eq:  LDA #0
        RTS

; skey: keyw = size sort key of entry em2 (0 for a directory, else elen[em2]).
skey:   LDA em2
        JSR eisd_get
        LDB #0
        CMP
        JZ sk_file
        LDA #0
        STA keyw
        STA keyw+1
        STA keyw+2
        RTS
sk_file:LDA em2
        STA mi
        JSR elen_ptr
        LDA (P2)
        STA keyw
        INP2
        LDA (P2)
        STA keyw+1
        LDA em2
        JSR elen2_get
        STA keyw+2
        RTS

; nameat: nbuf <- enam[em] (12 space-padded bytes), trailing pad trimmed.
nameat: LDA em
        STA mi
        JSR enam_ptr
        LDA dptr
        TAP2L
        LDA dptr+1
        TAP2H
        LDA #<nbuf
        TAP1L
        LDA #>nbuf
        TAP1H
        LDA #0
        STA cnt
na_l:   LDA cnt
        LDB #12
        CMP
        JZ na_d
        LDA (P2)
        LDB #32
        CMP
        JZ na_d
        STA (P1)+
        INP2
        LDA cnt
        INC
        STA cnt
        JMP na_l
na_d:   LDA #0
        STA (P1)
        RTS

; setbuf: sh_dir = eisd[em], sh_sz = elen[em] (for show/putsize).
setbuf: LDA em
        JSR eisd_get
        STA sh_dir
        LDA em
        STA mi
        JSR elen_ptr
        LDA (P2)
        STA sh_sz
        INP2
        LDA (P2)
        STA sh_sz+1
        LDA em
        JSR elen2_get
        STA sh_sz2
        RTS

; eidx_get: A(index) -> A = eidx[index]
eidx_get:
        LDB #<eidx
        ADD
        TAP1L
        LDA #>eidx
        JNC eg_1
        INC
eg_1:   TAP1H
        LDA (P1)
        RTS

; eisd_get: A(index) -> A = eisd[index]
eisd_get:
        LDB #<eisd
        ADD
        TAP1L
        LDA #>eisd
        JNC eis_1
        INC
eis_1:  TAP1H
        LDA (P1)
        RTS

; elen2_get: A(index) -> A = elen2[index]  (size bits 16..23)
elen2_get:
        LDB #<elen2
        ADD
        TAP1L
        LDA #>elen2
        JNC el2_1
        INC
el2_1:  TAP1H
        LDA (P1)
        RTS

; enam_ptr: dptr = enam + mi*12  (16-bit offset up to 756)
enam_ptr:
        JSR amul12
        LDA #<enam
        LDB macc
        ADD
        STA dptr
        LDA #0
        JNC ep_0
        LDA #1
ep_0:   STA cflg
        LDA #>enam
        LDB macc+1
        ADD
        LDB cflg
        ADD
        STA dptr+1
        RTS

; elen_ptr: P2 = elen + mi*2  (mi<64 so offset<128, single byte)
elen_ptr:
        LDA mi
        SHL
        LDB #<elen
        ADD
        TAP2L
        LDA #>elen
        JNC el_1
        INC
el_1:   TAP2H
        RTS

; elba_ptr: P2 = elba + mi*2
elba_ptr:
        LDA mi
        SHL
        LDB #<elba
        ADD
        TAP2L
        LDA #>elba
        JNC eb_1
        INC
eb_1:   TAP2H
        RTS

; amul12: macc (word) = mi * 12  (repeated add; no 16-bit multiply on the CPU)
amul12: LDA #0
        STA macc
        STA macc+1
        LDA mi
        STA cnt
am_l:   LDA cnt
        LDB #0
        CMP
        JZ am_d
        LDA macc
        LDB #12
        ADD
        STA macc
        JNC am_n
        LDA macc+1
        INC
        STA macc+1
am_n:   LDA cnt
        DEC
        STA cnt
        JMP am_l
am_d:   RTS

; ======================= show ==============================================
; sh_depth, sh_dir, sh_sz ; nbuf holds the name; gpat is the optional filter.
show:   LDA gpat
        LDB #0
        CMP
        JZ sh_show
        LDA #<gpat
        STA gp
        LDA #>gpat
        STA gp+1
        LDA #<nbuf
        STA gs
        LDA #>nbuf
        STA gs+1
        JSR gmatch
        LDB #0
        CMP
        JZ sh_ret                    ; no match -> filtered out
sh_show:LDA shown                    ; count entries that actually print
        INC
        STA shown
        JSR putsize
        LDA #32
        JSR SYS_PUTC
        LDA #32
        JSR SYS_PUTC
        LDA sh_depth
        STA cnt
sh_il:  LDA cnt
        LDB #0
        CMP
        JZ sh_pn
        LDA #32
        JSR SYS_PUTC
        LDA #32
        JSR SYS_PUTC
        LDA cnt
        DEC
        STA cnt
        JMP sh_il
sh_pn:  LDA #<nbuf
        TAP1L
        LDA #>nbuf
        TAP1H
sh_nl:  LDA (P1)
        LDB #0
        CMP
        JZ sh_slash
        JSR SYS_PUTC
        INP1
        JMP sh_nl
sh_slash:
        LDA sh_dir
        LDB #0
        CMP
        JZ sh_eol
        LDA #'/'
        JSR SYS_PUTC
sh_eol: LDA #10
        JSR SYS_PUTC
sh_ret: RTS

; ======================= putsize / putnum / ndigits / divmod10 =============
putsize:LDA sh_dir
        LDB #0
        CMP
        JZ ps_file
        LDA #6
        STA cnt
ps_dl:  LDA cnt
        LDB #0
        CMP
        JZ ps_ret
        LDA #32
        JSR SYS_PUTC
        LDA cnt
        DEC
        STA cnt
        JMP ps_dl
ps_ret: RTS
; 24-bit size print (mirrors dir.c putsize24): num24 = sh_sz2:sh_sz+1:sh_sz,
; extract decimal digits LS-first into dg[], pad to 6, print reversed.
ps_file:LDA sh_sz
        STA num24
        LDA sh_sz+1
        STA num24+1
        LDA sh_sz2
        STA num24+2
        LDA #0
        STA psnd
        JSR dm10                     ; first digit (handles 0)
        LDB #48
        ADD
        JSR ps_push
ps_wl:  JSR nz24
        LDB #0
        CMP
        JZ ps_pad2
        JSR dm10
        LDB #48
        ADD
        JSR ps_push
        JMP ps_wl
ps_pad2:LDA psnd                     ; pad: while nd < 6 -> space
        STA cnt2
ps_pl:  LDA cnt2
        LDB #6
        CMP
        JC ps_rev                    ; nd>=6 -> done padding
        LDA #32
        JSR SYS_PUTC
        LDA cnt2
        INC
        STA cnt2
        JMP ps_pl
ps_rev: LDA psnd                     ; while nd != 0 -> nd--, print dg[nd]
        LDB #0
        CMP
        JZ ps_rdn
        LDA psnd
        LDB #1
        SUB
        STA psnd
        LDA #<dg
        LDB psnd
        ADD
        TAP1L
        LDA #>dg
        JNC ps_rp
        INC
ps_rp:  TAP1H
        LDA (P1)
        JSR SYS_PUTC
        JMP ps_rev
ps_rdn: RTS

; ps_push: dg[psnd] = A ; psnd++
ps_push:STA pstmp
        LDA #<dg
        LDB psnd
        ADD
        TAP1L
        LDA #>dg
        JNC pp_1
        INC
pp_1:   TAP1H
        LDA pstmp
        STA (P1)
        LDA psnd
        INC
        STA psnd
        RTS

; dm10: num24[0..2] /= 10 (24-bit LE); remainder -> A. divmod10 does each byte's
; 16-bit divide (cur = dmrem*256 + num24[i], < 2560).
dm10:   LDA #0
        STA dmrem
        LDA #2
        STA dmi
dm_lp:  LDA #<num24                  ; P1 = num24 + dmi
        LDB dmi
        ADD
        TAP1L
        LDA #>num24
        JNC dm_p1
        INC
dm_p1:  TAP1H
        LDA (P1)
        STA dv                       ; dv = dmrem*256 + num24[dmi]
        LDA dmrem
        STA dv+1
        JSR divmod10                 ; dvq = dv/10, dvr = dv%10 (P1 preserved)
        LDA dvq
        STA (P1)                     ; num24[dmi] = dvq (dv<2560 -> dvq<256)
        LDA dvr
        STA dmrem
        LDA dmi
        LDB #0
        CMP
        JZ dm_dn                     ; processed dmi==0 -> stop
        LDA dmi
        LDB #1
        SUB
        STA dmi
        JMP dm_lp
dm_dn:  LDA dmrem
        RTS

; nz24: A = 1 if num24 != 0 else 0
nz24:   LDA num24
        LDB #0
        CMP
        JNZ nz_y
        LDA num24+1
        LDB #0
        CMP
        JNZ nz_y
        LDA num24+2
        LDB #0
        CMP
        JNZ nz_y
        LDA #0
        RTS
nz_y:   LDA #1
        RTS

; putnum: print the 16-bit unsigned value in pn as decimal, no padding.
;   Extracts digits LS-first via divmod10, pushing each ASCII digit on the
;   hardware stack (PHA), then pops (PLA) them to emit MS-first. pn==0 prints
;   a single '0'. Clobbers dv/dvq/dvr/pncnt and pn (consumed). (Helper; the
;   size column uses the 24-bit putsize path instead.)
putnum: LDA #0
        STA pncnt
        LDA pn
        LDB #0
        CMP
        JNZ pn_loop
        LDA pn+1
        LDB #0
        CMP
        JNZ pn_loop
        LDA #'0'
        JSR SYS_PUTC
        RTS
pn_loop:LDA pn
        LDB #0
        CMP
        JNZ pn_go
        LDA pn+1
        LDB #0
        CMP
        JZ pn_print
pn_go:  LDA pn
        STA dv
        LDA pn+1
        STA dv+1
        JSR divmod10
        LDA dvr
        LDB #48
        ADD
        PHA
        LDA pncnt
        INC
        STA pncnt
        LDA dvq
        STA pn
        LDA dvq+1
        STA pn+1
        JMP pn_loop
pn_print:
        LDA pncnt
        LDB #0
        CMP
        JZ pn_done
        PLA
        JSR SYS_PUTC
        LDA pncnt
        DEC
        STA pncnt
        JMP pn_print
pn_done:RTS

; ndigits: A = number of decimal digits in the 16-bit value ndv (min 1).
;   Repeatedly divides by 10 (divmod10) counting iterations; ndv unchanged,
;   but dv/dvq are clobbered. (Helper.)
ndigits:LDA #1
        STA ndc
        LDA ndv
        STA dv
        LDA ndv+1
        STA dv+1
nd_l:   LDA dv+1
        LDB #0
        CMP
        JNZ nd_div
        LDA dv
        LDB #10
        CMP
        JNC nd_done                  ; dv<10 -> done
nd_div: JSR divmod10
        LDA dvq
        STA dv
        LDA dvq+1
        STA dv+1
        LDA ndc
        INC
        STA ndc
        JMP nd_l
nd_done:LDA ndc
        RTS

; divmod10: dv (word) -> dvq (word)=dv/10, dvr (byte)=dv%10 (destroys dv)
divmod10:
        LDA #0
        STA dvq
        STA dvq+1
dm_l:   LDA dv+1
        LDB #0
        CMP
        JNZ dm_sub
        LDA dv
        LDB #10
        CMP
        JC dm_sub                    ; dv_low>=10
        LDA dv
        STA dvr
        RTS
dm_sub: LDA dv
        LDB #10
        SUB
        STA dv
        JC dm_nc
        LDA dv+1
        DEC
        STA dv+1
dm_nc:  LDA dvq
        LDB #1
        ADD
        STA dvq
        JNC dm_l
        LDA dvq+1
        INC
        STA dvq+1
        JMP dm_l

; ======================= gmatch / upper ====================================
; gmatch: gp, gs (word ptrs) -> A = 1 if pattern gp matches string gs else 0.
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
        JZ gm_r0                     ; *s==0, p[0]!=0
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
gm_adv: LDA gp                       ; gp++, gs++, tail-call
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
gm_star:LDA gp                       ; gp++ (p+1 is fixed for the loop)
        LDB #1
        ADD
        STA gp
        JNC gm_s0
        LDA gp+1
        INC
        STA gp+1
gm_s0:  LDA gp                       ; save gp,gs ; recurse ; restore
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

; upper: A -> uppercase(A)
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

; ======================= address helpers ===================================
nsub_addr:
        LDA #<nsub
        LDB w_depth
        ADD
        TAP1L
        LDA #>nsub
        JNC na1
        INC
na1:    TAP1H
        RTS
idx_addr:
        LDA #<idx
        LDB w_depth
        ADD
        TAP1L
        LDA #>idx
        JNC ia1
        INC
ia1:    TAP1H
        RTS
; csub_addr: P1 = csub + w_depth*128 + kk*2  (64 entries x 2 bytes per level)
csub_addr:
        LDA #0
        STA caddr
        STA caddr+1
        LDA w_depth
        STA cnt
ca_ml:  LDA cnt
        LDB #0
        CMP
        JZ ca_md
        LDA caddr
        LDB #128
        ADD
        STA caddr
        JNC ca_m1
        LDA caddr+1
        INC
        STA caddr+1
ca_m1:  LDA cnt
        DEC
        STA cnt
        JMP ca_ml
ca_md:  LDA kk
        SHL
        LDB caddr
        ADD
        STA caddr
        JNC ca_k1
        LDA caddr+1
        INC
        STA caddr+1
ca_k1:  LDA caddr
        LDB #<csub
        ADD
        STA caddr
        LDA caddr+1
        LDB #>csub
        ADD
        JNC ca_b1
        INC
ca_b1:  STA caddr+1
        LDA caddr
        TAP1L
        LDA caddr+1
        TAP1H
        RTS

; abspath (mirrors os/commands/lib_apath.c): ap_out <- absolute path of the word
; at ap_a; ap_n = chars consumed. A relative word is prefixed with the CWD
; (SYS_GETCWD $2003), since FOPENDIR/FRESOLVE start at root. P3 is the stack, so
; P2 is the source cursor and P1 the dest. (Ported from touch.asm/mv.asm.)
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
        JSR SYS_GETCWD               ; SYS_GETCWD -> out
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

; ======================= messages / scratch ===============================
; (assembler strips ';' as a comment even in strings, so the usage line is
;  emitted in .ascii pieces around literal ';' bytes = 59)
u_use:  .ascii "usage: DIR [-R] [-S] [path|glob]   list a dir"
        .byte 59
        .ascii " -S: size sort"
        .byte 59
        .ascii " glob: * ?"
        .byte 0
u_nf:   .asciiz "dir: not found"

ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
apath:  .fill 80

m_arg:  .fill 2
rec:    .fill 1
szmode: .fill 1
hasslash:.fill 1
slashpos:.fill 1
gflag:  .fill 1
plen:   .fill 1
ls:     .fill 1
notf:   .fill 1
filemode:.fill 1
shown:  .fill 1
cnt:    .fill 1
cnt2:   .fill 1
kk:     .fill 1
lba:    .fill 2
caddr:  .fill 2
cdst:   .fill 2
w_depth:.fill 1
sh_depth:.fill 1
sh_dir: .fill 1
sh_sz:  .fill 2
sh_sz2: .fill 1   ; size bits 16..23 (24-bit)
num24:  .fill 3   ; scratch 24-bit LE for the decimal printer
dg:     .fill 8   ; digit buffer
dmrem:  .fill 1
dmi:    .fill 1
psnd:   .fill 1
pstmp:  .fill 1
pn:     .fill 2
pncnt:  .fill 1
ndv:    .fill 2
ndc:    .fill 1
dv:     .fill 2
dvq:    .fill 2
dvr:    .fill 1
gp:     .fill 2
gs:     .fill 2
gpc:    .fill 1
gsc:    .fill 1
gmr:    .fill 1
uch:    .fill 1
; --- sort state ---
pri:    .fill 1
em:     .fill 1
em2:    .fill 1
mi:     .fill 1
si:     .fill 1
sj:     .fill 1
sm:     .fill 1
bA:     .fill 1
bB:     .fill 1
tA:     .fill 1
tB:     .fill 1
cflg:   .fill 1
cflg2:  .fill 1
ecnt:   .fill 1
macc:   .fill 2
dptr:   .fill 2
keyA:   .fill 3
keyB:   .fill 3
keyw:   .fill 3
naddrA: .fill 2
naddrB: .fill 2
nca:    .fill 1
ncb:    .fill 1
nbuf:   .fill 16
gpat:   .fill 16
dbuf:   .fill 64
de:     .fill 18   ; +[17] = length bits 16..23 (24-bit file size)
; --- per-directory entry buffers (reused at every recursion level) ---
enam:   .fill 768
elen:   .fill 128
elen2:  .fill 64    ; size bits 16..23 per entry (24-bit)
eisd:   .fill 64
elba:   .fill 128
eidx:   .fill 64
; --- per-depth recursion arrays ---
nsub:   .fill 16
idx:    .fill 16
csub:   .fill 2048
