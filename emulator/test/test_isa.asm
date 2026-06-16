; P8X ISA regression — exercises every instruction and self-checks.
; On the first failing check the program HALTs with the test id in A; if every
; check passes it HALTs with A=00. (make test-isa greps the halt line for A=00.)
;
; Coverage note: the ISA has no branch-on-N and flags aren't readable into A,
; so this asserts RESULTS, the Z flag, and the (conventional) C flag. N and V
; are not directly testable from software.

TID = $9000        ; current test id (RAM)

        .org 0
        LDP3 #$FEFF                 ; stack

; ---- 01: LDA # value ----
        LDA #$01
        STA TID
        LDA #$5A
        LDB #$5A
        CMP
        JNZ fail
; ---- 02: LDA # sets Z ----
        LDA #$02
        STA TID
        LDA #$00
        JNZ fail
; ---- 03: LDA # clears Z ----
        LDA #$03
        STA TID
        LDA #$01
        JZ  fail
; ---- 04: LDB # ----
        LDA #$04
        STA TID
        LDB #$3C
        LDA #$3C
        CMP
        JNZ fail
; ---- 05: ADD (no carry) ----
        LDA #$05
        STA TID
        LDA #$05
        LDB #$03
        ADD
        JC  fail
        LDB #$08
        CMP
        JNZ fail
; ---- 06: ADD (carry + zero) ----
        LDA #$06
        STA TID
        LDA #$FF
        LDB #$01
        ADD
        JNC fail
        JNZ fail
; ---- 07: SUB (no borrow, C=1) ----
        LDA #$07
        STA TID
        LDA #$09
        LDB #$04
        SUB
        JNC fail
        LDB #$05
        CMP
        JNZ fail
; ---- 08: SUB (borrow, C=0) ----
        LDA #$08
        STA TID
        LDA #$03
        LDB #$05
        SUB
        JC  fail
        LDB #$FE
        CMP
        JNZ fail
; ---- 09: AND ----
        LDA #$09
        STA TID
        LDA #$F0
        LDB #$3C
        AND
        LDB #$30
        CMP
        JNZ fail
; ---- 0A: OR ----
        LDA #$0A
        STA TID
        LDA #$F0
        LDB #$0C
        OR
        LDB #$FC
        CMP
        JNZ fail
; ---- 0B: XOR ----
        LDA #$0B
        STA TID
        LDA #$FF
        LDB #$0F
        XOR
        LDB #$F0
        CMP
        JNZ fail
; ---- 0C: CMP (equal -> Z, C; A preserved) ----
        LDA #$0C
        STA TID
        LDA #$42
        LDB #$42
        CMP
        JNZ fail
        JNC fail
        LDB #$42
        CMP
        JNZ fail
; ---- 0D: INC ----
        LDA #$0D
        STA TID
        LDA #$7F
        INC
        LDB #$80
        CMP
        JNZ fail
; ---- 0E: DEC (to zero) ----
        LDA #$0E
        STA TID
        LDA #$01
        DEC
        JNZ fail
; ---- 0F: SHL (bit7 -> C) ----
        LDA #$0F
        STA TID
        LDA #$81
        SHL
        JNC fail
        LDB #$02
        CMP
        JNZ fail
; ---- 10: SHR (bit0 -> C) ----
        LDA #$10
        STA TID
        LDA #$03
        SHR
        JNC fail
        LDB #$01
        CMP
        JNZ fail
; ---- 11: ROL (in=C, out->C) ----
        LDA #$11
        STA TID
        SEC
        LDA #$80
        ROL
        JNC fail
        LDB #$01
        CMP
        JNZ fail
; ---- 12: ROR (in=C, out->C) ----
        LDA #$12
        STA TID
        SEC
        LDA #$01
        ROR
        JNC fail
        LDB #$80
        CMP
        JNZ fail
; ---- 13: CLC / SEC ----
        LDA #$13
        STA TID
        SEC
        JNC fail
        CLC
        JC  fail
; ---- 14: STA a / LDA a ----
        LDA #$14
        STA TID
        LDA #$C3
        STA $8000
        LDA #$00
        LDA $8000
        LDB #$C3
        CMP
        JNZ fail
; ---- 15: LDB a ----
        LDA #$15
        STA TID
        LDB $8000
        LDA #$C3
        CMP
        JNZ fail
; ---- 16: STA (Pn)+ / LDA (Pn)+ ----
        LDA #$16
        STA TID
        LDP1 #$8010
        LDA #$11
        STA (P1)+
        LDA #$22
        STA (P1)+
        LDP1 #$8010
        LDA (P1)+
        LDB #$11
        CMP
        JNZ fail
        LDA (P1)+
        LDB #$22
        CMP
        JNZ fail
; ---- 17: LDA (Pn) non-incrementing ----
        LDA #$17
        STA TID
        LDP2 #$8010
        LDA (P2)
        LDB #$11
        CMP
        JNZ fail
        LDA (P2)
        LDB #$11
        CMP
        JNZ fail
        TPA2L
        LDB #$10
        CMP
        JNZ fail
        TPA2H
        LDB #$80
        CMP
        JNZ fail
; ---- 18: STA (Pn) ----
        LDA #$18
        STA TID
        LDP1 #$8020
        LDA #$5E
        STA (P1)
        LDA #$00
        LDA (P1)
        LDB #$5E
        CMP
        JNZ fail
; ---- 19: INP / DEP ----
        LDA #$19
        STA TID
        LDP1 #$1000
        INP1
        INP1
        DEP1
        TPA1L
        LDB #$01
        CMP
        JNZ fail
        TPA1H
        LDB #$10
        CMP
        JNZ fail
; ---- 1A: TAP / TPA round trip ----
        LDA #$1A
        STA TID
        LDA #$34
        TAP1L
        LDA #$12
        TAP1H
        TPA1L
        LDB #$34
        CMP
        JNZ fail
        TPA1H
        LDB #$12
        CMP
        JNZ fail
; ---- 1B: PHA / PLA ----
        LDA #$1B
        STA TID
        LDA #$7E
        PHA
        LDA #$00
        PLA
        LDB #$7E
        CMP
        JNZ fail
; ---- 1C: JSR abs / RTS ----
        LDA #$1C
        STA TID
        JSR subr
        LDB #$99
        CMP
        JNZ fail
; ---- 1D: JSR (P1) / RTS ----
        LDA #$1D
        STA TID
        LDP1 #subr2
        JSR (P1)
        LDB #$77
        CMP
        JNZ fail
; ---- 1E: BZ / BNZ taken and not-taken ----
        LDA #$1E
        STA TID
        LDA #$00
        BZ  b1
        JMP fail            ; BZ should have branched
b1:     LDA #$01
        BZ  fail            ; BZ should NOT branch
        LDA #$01
        BNZ b2
        JMP fail            ; BNZ should have branched
b2:     LDA #$00
        BNZ fail            ; BNZ should NOT branch
; ---- 1F: BCP / JNC carry branches ----
        LDA #$1F
        STA TID
        SEC
        BCP c1
        JMP fail            ; BCP should branch when C=1
c1:     CLC
        BCP fail            ; BCP should NOT branch when C=0
        SEC
        JNC fail            ; JNC should NOT branch when C=1
        CLC
        JNC c2
        JMP fail            ; JNC should branch when C=0
c2:
; ---- all passed ----
        LDA #$00
        HLT

fail:   LDA TID
        HLT

subr:   LDA #$99
        RTS
subr2:  LDA #$77
        RTS
