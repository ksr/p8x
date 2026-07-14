; tree.asm — hand-coded TREE command (asm counterpart of os/commands/tree.c).
;   TREE    depth-first indented listing of the CWD tree.
;
; Mirrors tree.c: each level streams its entries (2 spaces indent per level, '/'
; on directories) while recording child subdir LBAs, then descends — FNEXT's
; cursor is global BIOS state, so children are collected before descending.
;
; Recursion without a software stack: P8X has only P1/P2 general-purpose (P3 is
; the stack pointer), so per-level locals live in depth-indexed arrays and a
; single global w_depth that the descent loop inc/decs around each recursive
; call. MAXD levels deep, 24 child dirs per level (as tree.c).
;
; BIOS: FNEXT $013C, FSDIRBUF $0145, SYS_DIRENTRY $201B, SYS_OPENDIR $201E.
; OS: SYS_OPENCWD $2012, SYS_PUTC $2009, SYS_PUTS $200F. Entry: P2 = arg tail.
;#use abi

        .org $6A00
; --- -h check (P2 = arg) ---------------------------------------------------
tr_sk:  LDA (P2)
        LDB #32
        CMP
        JNZ tr_chk
        INP2
        JMP tr_sk
tr_chk: LDA (P2)
        LDB #'-'
        CMP
        JNZ tr_run
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ tr_usage
        LDB #'H'
        CMP
        JZ tr_usage
tr_run: LDA #0                        ; SYS_OPENCWD
        TAP1L
        TAP1H
        LDA #0
        JSR SYS_OPENCWD
        LDA #0                        ; FSDIRBUF page $EA
        TAP1L
        TAP1H
        LDA #$EA
        JSR FSDIRBUF
        LDA #0                        ; w_depth = 0
        STA w_depth
        JSR walk
        RTS
tr_usage:
        LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; ===========================================================================
; walk: list + descend the directory whose FNEXT is already open, at level
; w_depth. Uses nsub[w_depth], idx[w_depth], csub[w_depth][].
; ===========================================================================
walk:
        LDA #0                        ; nsub[w_depth] = 0
        STA kk                        ; (temp: store 0 via nsub addr)
        JSR nsub_addr                 ; P1 -> nsub[w_depth]
        LDA #0
        STA (P1)
; --- FNEXT loop ------------------------------------------------------------
tw_next:
        LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR FNEXT                    ; FNEXT
        JC tw_desc                    ; carry = end of directory
        LDA #<de                      ; de_read: SYS_DIRENTRY -> de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR SYS_DIRENTRY
        LDA de                        ; skip '.' / '..'
        LDB #'.'
        CMP
        JZ tw_next
; indent: w_depth * 2 spaces
        LDA w_depth
        STA cnt
tw_ind: LDA cnt
        LDB #0
        CMP
        JZ tw_name
        LDA #32
        JSR SYS_PUTC
        LDA #32
        JSR SYS_PUTC
        LDA cnt
        DEC
        STA cnt
        JMP tw_ind
; putname: de[0..11], skip spaces
tw_name:
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        STA cnt                       ; index 0..11
tw_nl:  LDA cnt
        LDB #12
        CMP
        JZ tw_isdir
        LDA (P1)+                     ; de[i]; advance
        STA nch
        LDB #32
        CMP
        JZ tw_ncont                   ; skip spaces
        LDA nch
        JSR SYS_PUTC
tw_ncont:
        LDA cnt
        INC
        STA cnt
        JMP tw_nl
; directory? de[12]==2 -> '/', record LBA
tw_isdir:
        LDA de+12
        LDB #2
        CMP
        JNZ tw_eol
        LDA #'/'
        JSR SYS_PUTC
        JSR nsub_addr                 ; nsub[w_depth] in *P1
        LDA (P1)
        LDB #24
        CMP
        JC tw_eol                     ; nsub >= 24 -> don't record (JC: nsub-24>=0)
        ; kk = nsub ; store LBA at csub[w_depth][kk]
        JSR nsub_addr
        LDA (P1)
        STA kk
        JSR csub_addr                 ; P1 -> csub[w_depth][kk]
        LDA de+15                     ; LBA lo
        STA (P1)+
        LDA de+16                     ; LBA hi
        STA (P1)
        JSR nsub_addr                 ; nsub++
        LDA (P1)
        INC
        STA (P1)
tw_eol: LDA #10
        JSR SYS_PUTC
        JMP tw_next
; --- descend into recorded children ---------------------------------------
tw_desc:
        JSR idx_addr                  ; idx[w_depth] = 0
        LDA #0
        STA (P1)
tw_dl:  JSR idx_addr
        LDA (P1)
        STA kk                        ; kk = idx
        JSR nsub_addr
        LDA (P1)
        LDB kk
        CMP
        JZ tw_ret                     ; idx == nsub -> done (kk-... ; equal)
        ; de_opendir(csub[w_depth][idx])
        JSR csub_addr                 ; P1 -> csub[w_depth][kk]
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
        LDA #0                        ; FSDIRBUF page $EA
        TAP1L
        TAP1H
        LDA #$EA
        JSR FSDIRBUF
        LDA w_depth                   ; recurse at depth+1
        INC
        STA w_depth
        JSR walk
        LDA w_depth
        DEC
        STA w_depth
        JSR idx_addr                  ; idx++
        LDA (P1)
        INC
        STA (P1)
        JMP tw_dl
tw_ret: RTS

; --- address helpers (P1 <- element address for current w_depth / kk) ------
; nsub_addr: P1 = nsub + w_depth
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
; idx_addr: P1 = idx + w_depth
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
; csub_addr: P1 = csub + w_depth*48 + kk*2
csub_addr:
        LDA #0
        STA caddr
        STA caddr+1
        LDA w_depth                   ; caddr = w_depth * 48
        STA cnt
ca_ml:  LDA cnt
        LDB #0
        CMP
        JZ ca_md
        LDA caddr
        LDB #48
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
ca_md:  LDA kk                        ; caddr += kk*2
        SHL
        LDB caddr
        ADD
        STA caddr
        JNC ca_k1
        LDA caddr+1
        INC
        STA caddr+1
ca_k1:  LDA caddr                     ; caddr += csub base
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

u_use:  .asciiz "usage: TREE   depth-first indented listing of the CWD tree"

; --- scratch ---------------------------------------------------------------
w_depth:.fill 1
cnt:    .fill 1
kk:     .fill 1
nch:    .fill 1
lba:    .fill 2
caddr:  .fill 2
de:     .fill 18   ; +[17] = length bits 16..23 (24-bit file size)
nsub:   .fill 16                      ; nsub[MAXD], MAXD=16
idx:    .fill 16
csub:   .fill 768                     ; csub[16][24] 16-bit
