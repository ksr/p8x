; find.asm — hand-coded FIND command (asm counterpart of os/commands/find.c).
;   FIND pattern   CWD paths matching pattern (glob if * or ?, else substring).
; Shares gmatch + de[] via `;#use glob`. Recursive CWD walk building each path in
; cur[], with per-level child LBA+name arrays indexed by a global w_depth (P3 is
; the stack pointer, so no software-stack frames). MAXD=10 deep, 24 children/lvl.
; BIOS: FNEXT $013C, FSDIRBUF $0145, SYS_DIRENTRY $201B, SYS_OPENDIR $201E.
; OS: SYS_GETCWD $2003, SYS_OPENCWD $2012, SYS_PUTC $2009, SYS_PUTS $200F.
; Entry: P2 = arg tail.
;#use glob
;#use abi

; Save the arg-tail pointer (arrives in P2) into f_arg, then skip any leading
; spaces so f_arg points at the first non-blank char of the pattern.
        .org $6A00
        TPA2L
        STA f_arg
        TPA2H
        STA f_arg+1
f_sk:   LDA f_arg                    ; reload P2 from f_arg each pass (16-bit incr below)
        TAP2L
        LDA f_arg+1
        TAP2H
        LDA (P2)
        LDB #32                       ; space?
        CMP
        JNZ f_chk
        LDA f_arg                     ; yes: f_arg++ (16-bit, carry into high byte)
        LDB #1
        ADD
        STA f_arg
        JNC f_sk
        LDA f_arg+1
        INC
        STA f_arg+1
        JMP f_sk
; f_chk: reject empty arg (NUL/CR) or a -h/-H help flag -> usage.
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
; Copy chars into pat[] (cap 63 + NUL = 64-byte buffer) until NUL/space/CR.
; Set isglob=1 if any '*' or '?' is seen, selecting glob vs substring matching.
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
        JSR SYS_GETCWD               ; SYS_GETCWD -> cur
        LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        STA fi
; f_len: measure strlen(cur) into fi -> stored as parr[0], the level-0 path length.
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
        JSR SYS_OPENCWD              ; SYS_OPENCWD
        LDA #0
        TAP1L
        TAP1H
        LDA #$EA
        JSR FSDIRBUF                 ; point FS at the $EA00 sector/dir buffer page
        JSR walk
        RTS
f_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; ======================= walk ==============================================
; walk: recursively scan the directory currently open in the FS at level w_depth.
;   Pass 1 (w_next): iterate FNEXT entries. For each, read the dirent, skip
;     dotfiles, test the name against the pattern and print on a hit. If the
;     entry is a subdirectory (de+12==2) and this level has room (<24 kids),
;     record its start LBA in clba[] and its name in cn[], then bump nsub.
;   Pass 2 (w_desc): FNEXT exhausted (C set). Walk the nsub recorded children:
;     open each, append "/name" onto cur[], w_depth++, recurse, then w_depth--
;     and truncate cur[] back to this level's length (parr[w_depth]).
; Recursion uses the hardware call stack (JSR/RTS); per-level state lives in the
; w_depth-indexed arrays nsub/idx/parr/clba/cn, NOT in software stack frames.
; MAXD=10 levels; guarding recursion depth is the caller's dir-tree shape.
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
        JSR FNEXT                    ; FNEXT
        JC w_desc
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR SYS_DIRENTRY             ; de_read
        LDA de                       ; skip entries whose name starts with '.'
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
        LDA de+12                     ; de+12 = entry type; 2 = subdirectory
        LDB #2
        CMP
        JNZ w_next
        JSR nsub_a
        LDA (P1)
        LDB #24
        CMP
        JC w_next                    ; nsub>=24 children recorded -> drop this one
        JSR nsub_a
        LDA (P1)
        STA fi
        JSR clba_a                    ; store this child's start LBA (de+15..16, LE)
        LDA de+15
        STA (P1)+
        LDA de+16
        STA (P1)
        LDA #0
        STA fk
; Copy the child name nm[] into cn[d][fi][] byte by byte (incl. trailing NUL).
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
; Pass 2: descend into each recorded child. idx[d] is the child cursor 0..nsub-1.
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
        JSR SYS_OPENDIR              ; SYS_OPENDIR
        LDA #0
        TAP1L
        TAP1H
        LDA #$EA
        JSR FSDIRBUF
        JSR parr_a
        LDA (P1)
        STA fpl                      ; oldp
        LDA fpl
        STA cp                        ; cp = write cursor into cur[]
; Append a '/' separator, unless cur[] is exactly the root "/" (len 1, cur[0]=='/')
; in which case the name is written directly after it (no doubled slash).
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
; Append the child's name (from cn[d][idx][]) onto cur[], advancing cp.
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
; Descend: w_depth++, record new level's path length (cp) in parr[d], recurse.
; Depth cap: the per-level arrays hold MAXD=10 (nsub/idx/parr .fill 10, clba
; 10*24*2), so descending at w_depth==10 would index past all of them. Skip the
; subtree instead — the header's "guarding recursion depth is the caller's" note
; was wishful thinking; nothing bounded it. Landing on the parr_a restore with
; w_depth UNCHANGED reads parr[depth] and truncates cur back to the parent
; length, which is what the next sibling needs.
        LDA w_depth
        INC
        LDB #10                       ; MAXD (nsub/idx/parr .fill 10)
        CMP
        JC  w_deep                    ; depth+1 >= MAXD -> too deep, don't descend
        STA w_depth
        JSR parr_a
        LDA cp
        STA (P1)
        JSR walk
; Back up: w_depth--, then truncate cur[] to this level's length (NUL at parr[d]).
        LDA w_depth
        DEC
        STA w_depth
w_deep: JSR parr_a
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
; print_match: emit the matched path + newline. Prints fpl bytes of cur[] (the
; current directory prefix), a '/' separator (suppressed when cur is root "/"),
; then the NUL-terminated name in nm[]. Uses SYS_PUTC, which preserves P1/P2 (the
; pm_l/pm_nl loops hold P1 live across it); only A is clobbered. Unlike the FS
; syscalls, no pointer reload is needed after a PUTC.
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
        JSR SYS_PUTC
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
        JSR SYS_PUTC
pm_name:LDA #<nm
        TAP1L
        LDA #>nm
        TAP1H
pm_nl:  LDA (P1)
        LDB #0
        CMP
        JZ pm_eol
        JSR SYS_PUTC
        INP1
        JMP pm_nl
pm_eol: LDA #10
        JSR SYS_PUTC
        RTS

; ======================= rdname / nmatch / contains ========================
; rdname: copy the 12-byte fixed-width name field de[0..11] into NUL-terminated
; nm[], dropping embedded spaces (name is space-padded on disk). Clobbers P1/P2.
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

; nmatch: return A=1 if the name at nm_p matches pat[]. isglob picks the engine:
; shared gmatch (glob, via gp/gs) when '*'/'?' present, else substring contains.
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

; contains: A = 1 if string cn_n is a substring of cn_h (naive O(n*m) scan;
; ct_i = haystack start, ct_j = match offset, ct_ij = ct_i+ct_j). A=0 if no match.
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
; Each returns a pointer in P1 to a w_depth-indexed slot. nsub/idx/parr are flat
; byte arrays (1 per level); clba/cn are 2-D/3-D and computed by strided add.
; nsub_a: P1 = &nsub[w_depth]  (child count at this level)
nsub_a: LDA #<nsub
        LDB w_depth
        ADD
        TAP1L
        LDA #>nsub
        JNC nsa1
        INC
nsa1:   TAP1H
        RTS
; idx_a: P1 = &idx[w_depth]  (pass-2 descent cursor at this level)
idx_a:  LDA #<idx
        LDB w_depth
        ADD
        TAP1L
        LDA #>idx
        JNC ixa1
        INC
ixa1:   TAP1H
        RTS
; parr_a: P1 = &parr[w_depth]  (cur[] path length at this level)
parr_a: LDA #<parr
        LDB w_depth
        ADD
        TAP1L
        LDA #>parr
        JNC pra1
        INC
pra1:   TAP1H
        RTS
; clba_a: P1 = &clba[w_depth][fi] (child start-LBA, 2 bytes). Stride 48 = 24*2.
; No MUL opcode, so w_depth*48 is done by adding 48 in a loop (cla_m), then fi*2
; via SHL, then the 16-bit base &clba. ft holds the running 16-bit offset/address.
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
; cn_a: P1 = &cn[w_depth][fi][fk] (child name char). Level stride 384 = 24*16 is
; summed as 3 x 128 per level (cna_1/2/3); the fi*16 term as 16 added fi times
; (cna_fl); then + fk + 16-bit base &cn. Again no MUL, all repeated 8-bit adds.
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

; ---- scratch vars and per-level arrays (all in TPA, uninitialized) ----------
f_arg:  .fill 2                       ; 16-bit ptr to current char of the arg tail
isglob: .fill 1                       ; 1 if pattern has '*'/'?' -> use gmatch
w_depth:.fill 1                       ; current recursion depth, 0..MAXD-1, indexes arrays below
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
pat:    .fill 64                      ; pattern buffer (63 chars + NUL)
nm:     .fill 16                      ; current entry name, NUL-terminated
cur:    .fill 256                     ; running absolute path being built
nsub:   .fill 10                      ; nsub[MAXD]:  child count per level
idx:    .fill 10                      ; idx[MAXD]:   pass-2 descent cursor per level
parr:   .fill 10                      ; parr[MAXD]:  cur[] length (path prefix) per level
clba:   .fill 480                     ; clba[MAXD][24] x 2B: child start LBAs (10*24*2)
cn:     .fill 3840                    ; cn[MAXD][24][16]: child names (10*24*16)
