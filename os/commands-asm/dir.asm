; dir.asm — hand-coded DIR command (asm counterpart of os/commands/dir.c).
;   DIR [-R] [path|glob]   list a directory (size column + name; '/' = dir).
;
; Mirrors dir.c: optional -R recursion, a `*`/`?` glob in the last path
; component (dir split + case-insensitive gmatch filter), a 6-wide right-
; justified size column (blank for dirs), streamed one entry at a time.
; Recursion uses depth-indexed arrays + a global w_depth (see tree.asm; P3 is the
; stack pointer so only P1/P2 are usable). Iterates on FSDIRBUF page $FA.
;
; BIOS: FOPENDIR $0139, FNEXT $013C, FSDIRBUF $0145, SYS_DIRENTRY $401B,
; SYS_OPENDIR $401E. OS: SYS_OPENCWD $4012, SYS_PUTC $4009, SYS_PUTS $400F.
; The CPU has no divide, so putnum/ndigits use a divmod10 subtraction routine.
; Entry: P2 = arg tail.

        .org $7A00
; ======================= main ==============================================
        TPA2L
        STA m_arg
        TPA2H
        STA m_arg+1
        LDA #0
        STA rec
        STA gpat                     ; gpat[0]=0 (no filter)
; skip spaces (advance m_arg)
d_sk:   LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ d_opt
        JSR arg_inc
        JMP d_sk
; -h / -R
d_opt:  LDA (P2)
        LDB #'-'
        CMP
        JNZ d_scan
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ d_usage
        LDB #'H'
        CMP
        JZ d_usage
        LDB #'R'
        CMP
        JZ d_rec
        LDB #'r'
        CMP
        JZ d_rec
        JMP d_scan                   ; some other '-x': fall through (m_arg at '-')
d_rec:  LDA #1
        STA rec
        JSR arg_inc                  ; skip '-'
        JSR arg_inc                  ; skip 'R'
d_rsk:  LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ d_scan
        JSR arg_inc
        JMP d_rsk
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
        LDA m_arg                    ; FOPENDIR(arg)
        TAP1L
        LDA m_arg+1
        TAP1H
        LDA #0
        JSR $0139
        JNC d_ok
        LDA #1
        STA notf
        JMP d_ok
d_cwd:  LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $4012                    ; SYS_OPENCWD
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
        LDA #<dbuf
        TAP1L
        LDA #>dbuf
        TAP1H
        LDA #0
        JSR $0139                    ; FOPENDIR(dbuf)
        JNC d_ok
        LDA #1
        STA notf
        JMP d_ok
d_gcwd: LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $4012
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
        JSR $400F
        LDA #10
        JSR $4009
        RTS
d_go:   LDA #0                        ; FSDIRBUF page $FA
        TAP1L
        TAP1H
        LDA #$FA
        JSR $0145
        LDA rec
        LDB #0
        CMP
        JZ d_flat
        LDA #0
        STA w_depth
        JSR walk
        RTS
; single-level listing
d_flat: LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $013C                    ; FNEXT
        JC d_fdone
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR $401B                    ; de_read
        JSR getname
        LDA #0
        STA sh_depth
        JSR set_dirsz                ; sh_dir, sh_sz from de[]
        JSR show
        JMP d_flat
d_fdone:RTS
d_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
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

; set_dirsz: sh_dir = (de[12]==2), sh_sz = de[13]+de[14]*256
set_dirsz:
        LDA de+12
        LDB #2
        CMP
        JNZ sd_file
        LDA #1
        STA sh_dir
        JMP sd_sz
sd_file:LDA #0
        STA sh_dir
sd_sz:  LDA de+13
        STA sh_sz
        LDA de+14
        STA sh_sz+1
        RTS

; ======================= walk (recursive, like tree) =======================
walk:   JSR nsub_addr
        LDA #0
        STA (P1)
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
        LDA de                       ; skip '.'/'..'
        LDB #'.'
        CMP
        JZ w_next
        JSR getname
        LDA w_depth
        STA sh_depth
        JSR set_dirsz
        JSR show
        LDA de+12                    ; if dir, record LBA
        LDB #2
        CMP
        JNZ w_next
        JSR nsub_addr
        LDA (P1)
        LDB #64
        CMP
        JC w_next                    ; nsub>=64 -> skip
        JSR nsub_addr
        LDA (P1)
        STA kk
        JSR csub_addr
        LDA de+15
        STA (P1)+
        LDA de+16
        STA (P1)
        JSR nsub_addr
        LDA (P1)
        INC
        STA (P1)
        JMP w_next
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
        JSR $401E                    ; SYS_OPENDIR
        LDA #0
        TAP1L
        TAP1H
        LDA #$FA
        JSR $0145                    ; FSDIRBUF $FA
        LDA w_depth
        INC
        STA w_depth
        JSR walk
        LDA w_depth
        DEC
        STA w_depth
        JSR idx_addr
        LDA (P1)
        INC
        STA (P1)
        JMP w_dl
w_ret:  RTS

; ======================= getname ===========================================
getname:LDA #<nbuf
        TAP1L
        LDA #>nbuf
        TAP1H
        LDA #<de
        TAP2L
        LDA #>de
        TAP2H
        LDA #0
        STA cnt
gn_l:   LDA cnt
        LDB #12
        CMP
        JZ gn_done
        LDA (P2)
        LDB #32
        CMP
        JZ gn_done
        STA (P1)+
        INP2
        LDA cnt
        INC
        STA cnt
        JMP gn_l
gn_done:LDA #0
        STA (P1)
        RTS

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
sh_show:JSR putsize
        LDA #32
        JSR $4009
        LDA #32
        JSR $4009
        LDA sh_depth
        STA cnt
sh_il:  LDA cnt
        LDB #0
        CMP
        JZ sh_pn
        LDA #32
        JSR $4009
        LDA #32
        JSR $4009
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
        JSR $4009
        INP1
        JMP sh_nl
sh_slash:
        LDA sh_dir
        LDB #0
        CMP
        JZ sh_eol
        LDA #'/'
        JSR $4009
sh_eol: LDA #10
        JSR $4009
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
        JSR $4009
        LDA cnt
        DEC
        STA cnt
        JMP ps_dl
ps_ret: RTS
ps_file:LDA sh_sz
        STA ndv
        LDA sh_sz+1
        STA ndv+1
        JSR ndigits
        STA cnt2
ps_pl:  LDA cnt2
        LDB #6
        CMP
        JC ps_num                    ; cnt2>=6 -> done padding
        LDA #32
        JSR $4009
        LDA cnt2
        INC
        STA cnt2
        JMP ps_pl
ps_num: LDA sh_sz
        STA pn
        LDA sh_sz+1
        STA pn+1
        JSR putnum
        RTS

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
        JSR $4009
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
        JSR $4009
        LDA pncnt
        DEC
        STA pncnt
        JMP pn_print
pn_done:RTS

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

; ======================= messages / scratch ===============================
; (assembler strips ';' as a comment even in strings, so the usage line is
;  emitted in two .ascii pieces around a literal ';' byte = 59)
u_use:  .ascii "usage: DIR [-R] [path|glob]   list a dir"
        .byte 59
        .ascii " glob: * ? in the last name"
        .byte 0
u_nf:   .asciiz "dir: not found"

m_arg:  .fill 2
rec:    .fill 1
hasslash:.fill 1
slashpos:.fill 1
gflag:  .fill 1
plen:   .fill 1
ls:     .fill 1
notf:   .fill 1
cnt:    .fill 1
cnt2:   .fill 1
kk:     .fill 1
lba:    .fill 2
caddr:  .fill 2
w_depth:.fill 1
sh_depth:.fill 1
sh_dir: .fill 1
sh_sz:  .fill 2
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
nbuf:   .fill 16
gpat:   .fill 16
dbuf:   .fill 64
de:     .fill 17
nsub:   .fill 16
idx:    .fill 16
csub:   .fill 2048
