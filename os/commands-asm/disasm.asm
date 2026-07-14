; disasm.asm — hand-coded DISASM command (asm counterpart of os/commands/disasm.c).
;   DISASM start end   disassemble the hex range [start, end).
; Reads memory with peek (LDA (P1)) and decodes each byte via the generated
; opcode table DISTAB (`;#use distab` -> lib_distab.inc, from genucode.OPC — the
; same source disasm.c's //#use distab table comes from, so the two never drift).
; Output is byte-identical to disasm.c:  AAAA: bb bb ..   MNEMONIC operand.
; Entry: P2 = arg tail.  SYS_PUTS=$200F, SYS_PUTC=$2009.
;#use distab
;#use abi

        .org $6A00
        ; ---- parse "start end" ------------------------------------------------
d_sk:   LDA (P2)                     ; skip leading spaces
        LDB #32
        CMP
        JNZ d_c0
        INP2
        JMP d_sk
d_c0:   LDA (P2)                     ; empty / CR -> usage
        LDB #0
        CMP
        JZ d_use
        LDB #13
        CMP
        JZ d_use
        LDB #'-'                     ; '-h'/'-H' -> usage; any other '-x' -> bad addr
        CMP
        JNZ d_go
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ d_use
        LDB #'H'
        CMP
        JZ d_use
        JMP d_bads
d_go:   JSR GETHEX                   ; start address
        LDA MATCH
        JZ d_bads
        LDA HXLO
        STA START
        LDA HXHI
        STA START+1
        JSR GETHEX                   ; end address
        LDA MATCH
        JZ d_nend
        LDA HXLO
        STA END
        LDA HXHI
        STA END+1
        LDA START                    ; addr = start
        STA ADDR
        LDA START+1
        STA ADDR+1

        ; ---- main loop: while (addr < end) ----------------------------------
d_loop: LDA ADDR+1                   ; unsigned 16-bit  addr < end ?
        LDB END+1
        CMP                          ; C=1 if addr_hi >= end_hi
        JNC d_body                   ; addr_hi < end_hi -> continue
        JNZ d_ret                    ; addr_hi > end_hi -> done
        LDA ADDR                     ; hi equal -> compare low
        LDB END
        CMP
        JC d_ret                     ; addr_lo >= end_lo -> done
d_body: LDA ADDR                     ; op = peek(addr)
        TAP1L
        LDA ADDR+1
        TAP1H
        LDA (P1)
        STA OP
        JSR DIS_FIND                 ; -> FOUNDF, SHAPE, MNL/MNH
        LDA ADDR+1                   ; print "AAAA: "
        JSR OPH8
        LDA ADDR
        JSR OPH8
        LDA #':'
        JSR SYS_PUTC
        LDA #32
        JSR SYS_PUTC
        LDA FOUNDF
        JZ d_unk
        ; known opcode -----------------------------------------------------
        JSR CALC_LN                  ; LN = ilen(SHAPE)
        LDA #0                       ; raw bytes: k=0..LN-1
        STA KCNT
d_rb:   LDA KCNT
        LDB LN
        CMP
        JC d_rbd                     ; k >= LN -> done
        LDA KCNT
        JSR PEEKAT                   ; peek(addr+k)
        JSR OPH8
        LDA #32
        JSR SYS_PUTC
        LDA KCNT
        INC
        STA KCNT
        JMP d_rb
d_rbd:  LDA KCNT                     ; pad byte column: k=LN..4, 3 spaces each
        LDB #5
        CMP
        JC d_rpd
        LDA #32
        JSR SYS_PUTC
        LDA #32
        JSR SYS_PUTC
        LDA #32
        JSR SYS_PUTC
        LDA KCNT
        INC
        STA KCNT
        JMP d_rbd
d_rpd:  LDA #32                      ; the extra space before the mnemonic
        JSR SYS_PUTC
        LDA MNL                      ; prs(mnemonic)
        TAP1L
        LDA MNH
        TAP1H
        JSR PRS
        JSR DS_OPER                  ; operand for SHAPE
        LDA #13
        JSR SYS_PUTC
        LDA #10
        JSR SYS_PUTC
        LDA ADDR                     ; addr += LN
        LDB LN
        ADD
        STA ADDR
        LDA ADDR+1
        JNC d_loop
        INC
        STA ADDR+1
        JMP d_loop
d_unk:  LDA OP                       ; unknown byte: op + pad + "???"
        JSR OPH8
        LDA #<M_UNK
        TAP1L
        LDA #>M_UNK
        TAP1H
        JSR PRS
        LDA #13
        JSR SYS_PUTC
        LDA #10
        JSR SYS_PUTC
        LDA ADDR                     ; addr += 1
        LDB #1
        ADD
        STA ADDR
        LDA ADDR+1
        JNC d_loop
        INC
        STA ADDR+1
        JMP d_loop
d_ret:  RTS

; usage / errors (puts = string + LF) -----------------------------------------
d_use:  LDA #<M_USE
        TAP1L
        LDA #>M_USE
        TAP1H
        JMP d_puts
d_bads: LDA #<M_BADS
        TAP1L
        LDA #>M_BADS
        TAP1H
        JMP d_puts
d_nend: LDA #<M_NEND
        TAP1L
        LDA #>M_NEND
        TAP1H
d_puts: LDA #0                       ; P1 = the string -> SYS_PUTS + LF
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; CALC_LN: LN = ilen(SHAPE): sh1->2, sh2->3, sh9->5, else 1.
CALC_LN:LDA SHAPE
        LDB #1
        CMP
        JZ cl_2
        LDA SHAPE
        LDB #2
        CMP
        JZ cl_3
        LDA SHAPE
        LDB #9
        CMP
        JZ cl_5
        LDA #1
        STA LN
        RTS
cl_2:   LDA #2
        STA LN
        RTS
cl_3:   LDA #3
        STA LN
        RTS
cl_5:   LDA #5
        STA LN
        RTS

; DS_OPER: print the operand for SHAPE (mirrors disasm.c).
DS_OPER:LDA SHAPE
        LDB #1
        CMP
        JZ do_imm
        LDA SHAPE
        LDB #2
        CMP
        JZ do_adr
        LDA SHAPE
        LDB #9
        CMP
        JZ do_mvw
        LDA SHAPE                     ; 3..8 -> (Pn) ; else nothing
        LDB #3
        CMP
        JNC do_non
        LDA SHAPE
        LDB #9
        CMP
        JC do_non
        JMP do_preg
do_non: RTS
do_imm: LDA #32                       ; " #$" + ph2(peek(addr+1))
        JSR SYS_PUTC
        LDA #'#'
        JSR SYS_PUTC
        LDA #'$'
        JSR SYS_PUTC
        LDA #1
        JSR PEEKAT
        JSR OPH8
        RTS
do_adr: LDA #32                       ; " $" + ph4(w16(addr+1))
        JSR SYS_PUTC
        LDA #'$'
        JSR SYS_PUTC
        LDA #1
        JSR W16OFF
        LDA WH
        JSR OPH8
        LDA WL
        JSR OPH8
        RTS
do_mvw: LDA #32                       ; " $" ph4 ",$" ph4
        JSR SYS_PUTC
        LDA #'$'
        JSR SYS_PUTC
        LDA #1
        JSR W16OFF
        LDA WH
        JSR OPH8
        LDA WL
        JSR OPH8
        LDA #','
        JSR SYS_PUTC
        LDA #'$'
        JSR SYS_PUTC
        LDA #3
        JSR W16OFF
        LDA WH
        JSR OPH8
        LDA WL
        JSR OPH8
        RTS
do_preg:LDA #32                       ; " (P" digit ")" optional "+"
        JSR SYS_PUTC
        LDA #'('
        JSR SYS_PUTC
        LDA #'P'
        JSR SYS_PUTC
        LDA SHAPE                      ; 3,4->1  5,6->2  7,8->3
        LDB #5
        CMP
        JNC dp_1
        LDA SHAPE
        LDB #7
        CMP
        JNC dp_2
        LDA #'3'
        JMP dp_d
dp_1:   LDA #'1'
        JMP dp_d
dp_2:   LDA #'2'
dp_d:   JSR $2009
        LDA #')'
        JSR SYS_PUTC
        LDA SHAPE                      ; '+' when shape is even (4,6,8)
        LDB #1
        AND
        JNZ dp_e
        LDA #'+'
        JSR SYS_PUTC
dp_e:   RTS

; PEEKAT: A = offset (0..4) -> A = peek(ADDR + offset). Clobbers P1, TMPA.
PEEKAT: STA TMPA
        LDA ADDR
        LDB TMPA
        ADD
        TAP1L
        LDA ADDR+1
        JNC pk_nc
        INC
pk_nc:  TAP1H
        LDA (P1)
        RTS

; W16OFF: A = offset -> WL = peek(ADDR+off), WH = peek(ADDR+off+1).
W16OFF: STA TMPB
        LDA TMPB
        JSR PEEKAT
        STA WL
        LDA TMPB
        LDB #1
        ADD
        JSR PEEKAT
        STA WH
        RTS

; DIS_FIND: OP -> FOUNDF (1/0), SHAPE, MNL/MNH. Scans DISTAB. Clobbers P1, TMPA.
DIS_FIND:LDA #<DISTAB
        TAP1L
        LDA #>DISTAB
        TAP1H
df_lp:  LDA (P1)                      ; record opcode byte
        LDB #$FF
        CMP
        JZ df_no                      ; $FF -> end of table
        LDB OP
        CMP
        JZ df_hit                     ; match
        INP1                          ; skip opcode + shape
        INP1
df_sk:  LDA (P1)                      ; skip the mnemonic string past its NUL
        STA TMPA
        INP1
        LDA TMPA
        JZ df_lp
        JMP df_sk
df_hit: INP1                          ; P1 -> shape
        LDA (P1)
        STA SHAPE
        INP1                          ; P1 -> mnemonic
        TPA1L
        STA MNL
        TPA1H
        STA MNH
        LDA #1
        STA FOUNDF
        RTS
df_no:  LDA #0
        STA FOUNDF
        RTS

; PRS: print the NUL-terminated string at P1 (no trailing newline). Uses P2 as a
; save; syscalls clobber P1, so copy the cursor to P2 and re-point each char.
PRS:    TPA1L
        STA PSL
        TPA1H
        STA PSH
ps_lp:  LDA PSL
        TAP1L
        LDA PSH
        TAP1H
        LDA (P1)
        JZ ps_d
        JSR SYS_PUTC
        LDA PSL
        LDB #1
        ADD
        STA PSL
        LDA PSH
        JNC ps_lp
        INC
        STA PSH
        JMP ps_lp
ps_d:   RTS

; OPH8: print A as two hex digits (to SYS_PUTC). ONIB prints one nibble.
OPH8:   STA RHX
        SHR
        SHR
        SHR
        SHR
        JSR ONIB
        LDA RHX
        LDB #$0F
        AND
        JMP ONIB
ONIB:   LDB #10
        CMP
        JC on_hex
        LDB #'0'
        ADD
        JSR SYS_PUTC
        RTS
on_hex: LDB #$37
        ADD
        JSR SYS_PUTC
        RTS

; GETHEX: skip spaces at (P2), parse hex -> HXLO/HXHI, advance P2. MATCH=1 if
; at least one digit was read. (Same as dep.asm's helper.)
GETHEX: LDA #0
        STA HXLO
        STA HXHI
        STA GCNT
gh_sk:  LDA (P2)
        LDB #32
        CMP
        JNZ gh_lp
        INP2
        JMP gh_sk
gh_lp:  LDA (P2)
        JSR HEXVAL
        LDA MATCH
        JZ gh_end
        LDA #4
        STA SHC
gh_shl: LDA HXLO
        SHL
        STA HXLO
        LDA HXHI
        ROL
        STA HXHI
        LDA SHC
        DEC
        STA SHC
        JNZ gh_shl
        LDA HXLO
        LDB DIGIT
        ADD
        STA HXLO
        LDA HXHI
        JNC gh_nc
        INC
gh_nc:  STA HXHI
        INP2
        LDA GCNT
        INC
        STA GCNT
        JMP gh_lp
gh_end: LDA GCNT
        JZ gh_no
        LDA #1
        STA MATCH
        RTS
gh_no:  LDA #0
        STA MATCH
        RTS

; HEXVAL: A = char -> DIGIT (0..15), MATCH=1 if a hex digit else 0.
HEXVAL: STA HVT
        LDB #'a'
        CMP
        JNC hv_u
        LDB #'g'
        CMP
        JC hv_u
        LDA HVT
        LDB #$20
        SUB
        STA HVT
hv_u:   LDA HVT
        LDB #'0'
        CMP
        JNC hv_no
        LDB #$3A
        CMP
        JC hv_af
        LDA HVT
        LDB #'0'
        SUB
        STA DIGIT
        LDA #1
        STA MATCH
        RTS
hv_af:  LDA HVT
        LDB #'A'
        CMP
        JNC hv_no
        LDB #$47
        CMP
        JC hv_no
        LDA HVT
        LDB #'A'
        SUB
        LDB #10
        ADD
        STA DIGIT
        LDA #1
        STA MATCH
        RTS
hv_no:  LDA #0
        STA MATCH
        RTS

M_USE:  .asciiz "usage: disasm start end   disassemble hex range [start,end)"
M_BADS: .asciiz "disasm: bad start address"
M_NEND: .asciiz "disasm: need an end address"
M_UNK:  .asciiz "            ???"

START:  .fill 2
END:    .fill 2
ADDR:   .fill 2
OP:     .fill 1
SHAPE:  .fill 1
MNL:    .fill 1
MNH:    .fill 1
LN:     .fill 1
KCNT:   .fill 1
FOUNDF: .fill 1
WL:     .fill 1
WH:     .fill 1
TMPA:   .fill 2
TMPB:   .fill 1
RHX:    .fill 1
PSL:    .fill 1
PSH:    .fill 1
HXLO:   .fill 1
HXHI:   .fill 1
GCNT:   .fill 1
SHC:    .fill 1
DIGIT:  .fill 1
MATCH:  .fill 1
HVT:    .fill 1
