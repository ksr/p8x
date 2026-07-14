; dump.asm — hand-coded DUMP command (asm counterpart of os/commands/dump.c).
;   DUMP addr   show 256 bytes from hex address addr (16 rows, hex + ASCII).
; After each block waits for a console key: '.' returns, else next block.
; Memory-only (no filesystem). Entry: P2 = arg tail.
; BIOS CONIN=$0100.  SYS_PUTS=$200F, SYS_PUTC=$2009.
;#use abi

        .org $6A00
u_sk:   LDA (P2)                     ; skip leading spaces
        LDB #32
        CMP
        JNZ u_c0
        INP2
        JMP u_sk
u_c0:   LDA (P2)                     ; empty / CR -> usage
        LDB #0
        CMP
        JZ u_use
        LDB #13
        CMP
        JZ u_use
        LDB #'-'
        CMP
        JNZ u_addr
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ u_use
        LDB #'H'
        CMP
        JZ u_use
        JMP u_bad
u_addr: JSR GETHEX                   ; address -> HXLO/HXHI, MATCH
        LDA MATCH
        JZ u_bad
        LDA HXLO
        STA ADLO
        LDA HXHI
        STA ADHI
; ---- one 256-byte page: 16 rows of 16 bytes ----
u_page: LDA #16
        STA ROWS
u_row:  LDA ADHI                     ; "AAAA: "
        JSR OPH8
        LDA ADLO
        JSR OPH8
        LDA #':'
        JSR SYS_PUTC
        LDA #32
        JSR SYS_PUTC
        LDA ADLO                     ; P1 = addr, 16 hex bytes
        TAP1L
        LDA ADHI
        TAP1H
        LDA #16
        STA CNT
u_hex:  LDA (P1)+
        JSR OPH8
        LDA #32
        JSR SYS_PUTC
        LDA CNT
        DEC
        STA CNT
        JNZ u_hex
        LDA #32
        JSR SYS_PUTC
        LDA ADLO                     ; P1 = addr again, 16 ASCII bytes
        TAP1L
        LDA ADHI
        TAP1H
        LDA #16
        STA CNT
u_asc:  LDA (P1)+
        STA ATMP
        LDB #32
        CMP                          ; b >= 32 ?
        JNC u_dot
        LDA ATMP
        LDB #127
        CMP                          ; b >= 127 ?
        JC u_dot
        LDA ATMP
        JMP u_put
u_dot:  LDA #'.'
u_put:  JSR $2009
        LDA CNT
        DEC
        STA CNT
        JNZ u_asc
        LDA #13
        JSR SYS_PUTC
        LDA #10
        JSR SYS_PUTC
        LDA ADLO                     ; addr += 16
        LDB #16
        ADD
        STA ADLO
        LDA ADHI
        JNC u_nc
        INC
        STA ADHI
u_nc:   LDA ROWS
        DEC
        STA ROWS
        JNZ u_row
        JSR CONIN                    ; CONIN: '.' quits, else next page
        LDB #'.'
        CMP
        JZ u_end
        JMP u_page
u_end:  RTS
u_bad:  LDA #<m_bad
        TAP1L
        LDA #>m_bad
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
u_use:  LDA #<m_use
        TAP1L
        LDA #>m_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; OPH8: print A as two hex digits (to SYS_PUTC).
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

; GETHEX: skip spaces at (P2), parse hex digits -> HXLO/HXHI, advance P2.
; MATCH=1 if at least one digit was read, else 0.
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

; HEXVAL: A = char -> DIGIT (0..15), MATCH=1 if a hex digit, else MATCH=0.
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

m_bad:  .asciiz "dump: bad address"
m_use:  .asciiz "usage: DUMP addr   show 256 bytes from hex address addr"
HXLO:   .fill 1
HXHI:   .fill 1
GCNT:   .fill 1
SHC:    .fill 1
DIGIT:  .fill 1
MATCH:  .fill 1
HVT:    .fill 1
ADLO:   .fill 1
ADHI:   .fill 1
ROWS:   .fill 1
CNT:    .fill 1
RHX:    .fill 1
ATMP:   .fill 1
