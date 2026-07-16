; dep.asm — hand-coded DEP command (asm counterpart of os/commands/dep.c).
;   DEP addr b b ...   store hex byte values at hex address addr.
; Memory-only (no filesystem): parse hex, poke each byte, addr++. Quiet on
; success; usage on -h / empty; "dep: bad address" on a non-hex address.
; Each value parses as 16-bit but only its low byte is stored, so "1FF" deposits
; $FF; an address with no byte values is a no-op. Both match dep.c.
; Entry: P2 = arg tail.  SYS_PUTS=$200F, SYS_PUTC=$2009.
;#use abi

        .org $6A00
; Main entry (loaded/run at $6A00, the TPA). Walks the arg tail at (P2):
;   parse the address, then loop parsing byte values and poking them into
;   ascending memory. Clobbers A/B, P1 (poke target), P2 (advanced past args)
;   and the scratch cells at file end (HXLO..ADHI). Falls through to RTS.
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
        LDB #'-'
        CMP
        JNZ d_addr
        INP2                         ; '-': -h/-H -> usage, else bad address
        LDA (P2)
        LDB #'h'
        CMP
        JZ d_use
        LDB #'H'
        CMP
        JZ d_use
        JMP d_bad
d_addr: JSR GETHEX                   ; address -> HXLO/HXHI, MATCH
        LDA MATCH
        JZ d_bad
        LDA HXLO
        STA ADLO
        LDA HXHI
        STA ADHI
d_lp:   JSR GETHEX                   ; each following byte value
        LDA MATCH
        JZ d_done
        LDA ADLO                     ; poke(addr, value low); P1 = 16-bit addr
        TAP1L
        LDA ADHI
        TAP1H
        LDA HXLO
        STA (P1)
        LDA ADLO                     ; addr++
        LDB #1
        ADD
        STA ADLO
        LDA ADHI                     ; 16-bit carry: only bump ADHI on low wrap
        JNC d_lp
        INC
        STA ADHI
        JMP d_lp
d_done: RTS
; d_bad is an ERROR: print it to the raw console (PUTS/CONOUT), never to stdout.
; stdout may be a redirect or a pipe — `dep zz >F` would otherwise write the
; message INTO F, and `dep zz | wc` would feed it to wc as data. Matches dep.c's
; eputs(). d_use below is NOT an error (the user asked with -h), so it stays on
; stdout and `dep -h >notes` still captures it.
d_bad:  LDA #<m_bad
        TAP1L
        LDA #>m_bad
        TAP1H
        JSR PUTS
        LDA #10
        JSR CONOUT
        RTS
d_use:  LDA #<m_use
        TAP1L
        LDA #>m_use
        TAP1H
        JSR SYS_PUTS
        LDA #10
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
        LDA #4                       ; accumulator <<= 4
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
        LDA HXLO                     ; merge digit into the nibble the shift
        LDB DIGIT                    ; just cleared: HXLO's low 4 bits are 0 and
        ADD                          ; DIGIT is 0..15, so this cannot carry out
        STA HXLO                     ; of the low byte -- HXHI stands as the ROL
        INP2                         ; chain left it.
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
; Range checks use CMP (C=1 when A>=B). Boundary constants are one-past the
; range end: $3A = ':' (just after '9'), $47 = 'G' (just after 'F').
HEXVAL: STA HVT
        LDB #'a'                     ; lower-case a..f -> upper
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
        LDA HVT                      ; 0..9
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
        LDA HVT                      ; A..F
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

m_bad:  .asciiz "dep: bad address"
m_use:  .asciiz "usage: DEP addr b b ...   store hex bytes at hex address addr"
HXLO:   .fill 1
HXHI:   .fill 1
GCNT:   .fill 1
SHC:    .fill 1
DIGIT:  .fill 1
MATCH:  .fill 1
HVT:    .fill 1
ADLO:   .fill 1
ADHI:   .fill 1
