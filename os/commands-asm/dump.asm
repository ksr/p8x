; dump.asm — hand-coded DUMP command (asm counterpart of os/commands/dump.c).
;   DUMP addr   show 256 bytes from hex address addr (16 rows, hex + ASCII).
; After each block waits for a console key: '.' returns, else next block.
; Memory-only (no filesystem). Entry: P2 = arg tail (command line past name).
; BIOS CONIN=$0100.  SYS_PUTS=$200F, SYS_PUTC=$2009.
;
; ISA notes for readers: CMP sets C=1 when A>=B (unsigned), Z=1 when A==B; it
;   leaves A untouched.  SUB sets C=1 on NO borrow (A>=B).  JC/JNC test carry.
;   There is no ADC/SBC; 16-bit math is done by hand (see ADD then JNC/INC).
; State is held in the .fill scratch bytes at the tail (ADLO/ADHI = current
;   dump address, HXLO/HXHI = parsed hex, MATCH/DIGIT = parser outputs, etc.).
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
        LDB #'-'                     ; leading '-' introduces a flag
        CMP
        JNZ u_addr
        INP2                         ; consume '-', look at flag letter
        LDA (P2)
        LDB #'h'                     ; -h / -H is a help request -> usage text
        CMP
        JZ u_use
        LDB #'H'
        CMP
        JZ u_use
        JMP u_bad                    ; any other '-x' is an error
u_addr: JSR GETHEX                   ; address -> HXLO/HXHI, MATCH
        LDA MATCH                    ; no hex digits parsed -> bad address
        JZ u_bad
        LDA HXLO                     ; seed the running dump address
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
u_asc:  LDA (P1)+                    ; CMP preserves A, so the byte stays live in
        LDB #32                      ;   A across both range tests (LDB hits B only)
        CMP                          ; char >= 32 (printable low bound)?
        JNC u_dot                    ;   C=0 means char < 32 -> control, show '.'
        LDB #127
        CMP                          ; char >= 127 (DEL/high)?
        JC u_dot                     ;   C=1 means char >= 127 -> non-print, '.'
        JMP u_put                    ; 32..126: print the byte still held in A
u_dot:  LDA #'.'
u_put:  JSR $2009                    ; SYS_PUTC (raw addr; equals SYS_PUTC equate)
        LDA CNT
        DEC
        STA CNT
        JNZ u_asc
        LDA #13
        JSR SYS_PUTC
        LDA #10
        JSR SYS_PUTC
        LDA ADLO                     ; addr += 16 (advance one row)
        LDB #16
        ADD
        STA ADLO
        LDA ADHI                     ; propagate carry into the high byte
        JNC u_nc                     ;   (hand-rolled 16-bit add: no ADC)
        INC
        STA ADHI
u_nc:   LDA ROWS
        DEC
        STA ROWS
        JNZ u_row                    ; loop until 16 rows printed
        JSR CONIN                    ; wait for a key: '.' quits, else next page
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

; OPH8: print A as two hex digits (high nibble first) via SYS_PUTC.
;   In: A = byte.  Out: two chars emitted.  Clobbers A,B; uses RHX scratch.
OPH8:   STA RHX                      ; stash byte; RHX survives the shifts
        SHR                          ; A >>= 4 to isolate the high nibble
        SHR
        SHR
        SHR
        JSR ONIB                     ; print high nibble
        LDA RHX
        LDB #$0F
        AND                          ; isolate low nibble
        JMP ONIB                     ; tail-call: print low nibble, then RTS
; ONIB: print the low nibble of A (0..15) as one hex digit.  Clobbers A,B.
ONIB:   LDB #10
        CMP                          ; nibble >= 10 -> letter A..F
        JC on_hex
        LDB #'0'                     ; 0..9 -> '0'..'9'
        ADD
        JSR SYS_PUTC
        RTS
on_hex: LDB #$37                     ; 10..15 -> 'A'..'F' ($37 = 'A' - 10)
        ADD
        JSR SYS_PUTC
        RTS

; GETHEX: skip spaces at (P2), parse hex digits -> HXLO/HXHI, advance P2.
; MATCH=1 if at least one digit was read, else 0.  Value accumulates as a
;   16-bit big-endian nibble shift: for each digit, (HXHI:HXLO) <<= 4 then OR
;   the digit.  Overflow above 16 bits is silently dropped.  Clobbers A,B.
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
        LDA #4                       ; shift the 16-bit accumulator left 4 bits
        STA SHC
gh_shl: LDA HXLO
        SHL                          ; low byte <<1, MSB -> carry
        STA HXLO
        LDA HXHI
        ROL                          ; high byte <<1, pulling carry into bit 0
        STA HXHI
        LDA SHC
        DEC
        STA SHC
        JNZ gh_shl
        LDA HXLO                     ; OR-in the new nibble (add is safe: low 4
        LDB DIGIT                    ;   bits of HXLO are 0 after the <<4)
        ADD
        STA HXLO
        LDA HXHI                     ; carry out of the low byte bumps HXHI
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
;   Uppercases lowercase a-f in place, then classifies as 0-9 or A-F.
;   Clobbers A,B; uses HVT scratch.
HEXVAL: STA HVT                      ; keep the char in HVT across CMPs
        LDB #'a'
        CMP                          ; char >= 'a' ?
        JNC hv_u                     ;   below 'a' -> not lowercase, skip fold
        LDB #'g'
        CMP                          ; char >= 'g' ? (past 'f') -> skip fold
        JC hv_u
        LDA HVT                      ; 'a'..'f': fold to upper by clearing bit 5
        LDB #$20
        SUB                          ;   'a'-$20 = 'A'
        STA HVT
hv_u:   LDA HVT
        LDB #'0'
        CMP                          ; char >= '0' ?
        JNC hv_no                    ;   below '0' -> not hex
        LDB #$3A                      ; $3A = ':' , one past '9'
        CMP
        JC hv_af                     ; char >= ':' -> try A..F range instead
        LDA HVT                      ; '0'..'9': digit = char - '0'
        LDB #'0'
        SUB
        STA DIGIT
        LDA #1
        STA MATCH
        RTS
hv_af:  LDA HVT
        LDB #'A'
        CMP                          ; char >= 'A' ?
        JNC hv_no
        LDB #$47                     ; $47 = 'G' , one past 'F'
        CMP
        JC hv_no                     ; char >= 'G' -> not hex
        LDA HVT                      ; 'A'..'F': digit = char - 'A' + 10
        LDB #'A'
        SUB
        LDB #10
        ADD
        STA DIGIT
        LDA #1
        STA MATCH
        RTS
hv_no:  LDA #0                       ; not a hex digit
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
