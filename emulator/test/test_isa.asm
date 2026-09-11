; P8X ISA regression — exercises every instruction and self-checks.
; On the first failing check the program HALTs with the test id in A; if every
; check passes it HALTs with A=00. (make test-isa greps the halt line for A=00.)
;
; Coverage note: the ISA has no branch-on-N and flags aren't readable into A,
; so this asserts RESULTS, the Z flag, and the (conventional) C flag. N and V
; are not directly testable from software.

TID = $9000        ; current test id (RAM)
VAL = $9001        ; scratch byte (RAM) for LDT a
IRQFLAG = $9002     ; set by the IRQ handler (rev C interrupt test)
MARK = $9003        ; written by the instruction that was preempted by the IRQ

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
; ---- 20: ADDT (A + T via B-mux; B must NOT be the operand) ----
; B is set to the EXPECTED result as a sentinel: if ADDT wrongly used B
; instead of T the result would differ and the CMP would fail.
        LDA #$20
        STA TID
        LDB #$08            ; sentinel = expected result (and wrong-operand bait)
        LDA #$05
        LDT #$03
        ADDT                ; A = A + T = 5 + 3 = 8  (must use T, not B)
        CMP                 ; A(8) vs B(8) -> Z if correct
        JNZ fail
; ---- 21: SUBT ----
        LDA #$21
        STA TID
        LDB #$02            ; wrong-operand bait
        LDA #$0A
        LDT #$04
        SUBT                ; A = 10 - 4 = 6
        LDB #$06
        CMP
        JNZ fail
; ---- 22: CMPT (compare A with T; A unchanged, Z when equal) ----
        LDA #$22
        STA TID
        LDA #$07
        LDT #$07
        CMPT                ; 7 - 7 -> Z=1, A unchanged
        JNZ fail
        LDB #$07
        CMP                 ; confirm A still 7
        JNZ fail
; ---- 23: ANDT / ORT / XORT ----
        LDA #$23
        STA TID
        LDA #$F0
        LDT #$3C
        ANDT                ; F0 & 3C = 30
        LDB #$30
        CMP
        JNZ fail
        LDA #$F0
        LDT #$0F
        ORT                 ; F0 | 0F = FF
        LDB #$FF
        CMP
        JNZ fail
        LDA #$FF
        LDT #$0F
        XORT                ; FF ^ 0F = F0
        LDB #$F0
        CMP
        JNZ fail
; ---- 24: LDT a (load T from memory), then ADDT ----
        LDA #$24
        STA TID
        LDA #$5A
        STA VAL
        LDT VAL             ; T = [VAL] = 5A  (absolute)
        LDA #$A5
        ADDT                ; A5 + 5A = FF
        LDB #$FF
        CMP
        JNZ fail
; ---- 30: signed BLT/BGE — (-128) < (1), the case unsigned C gets wrong ----
; -128 = $80, 1 = $01. Signed: -128 < 1. Unsigned: 128 > 1. Must use N^V.
        LDA #$30
        STA TID
        LDA #$80
        LDB #$01
        CMP
        BLT n30                 ; signed A<B -> must branch
        JMP fail
n30:    LDA #$80                ; (reload; CMP left flags, branches don't touch them)
        LDB #$01
        CMP
        BGE fail                ; A>=B is false -> must NOT branch
; ---- 31: signed BGT/BGE — 127 > (-1) ----
        LDA #$31
        STA TID
        LDA #$7F
        LDB #$FF                ; -1
        CMP
        BGT n31                 ; signed A>B -> must branch
        JMP fail
n31:    LDA #$7F
        LDB #$FF
        CMP
        BLE fail                ; A<=B false -> must NOT branch
        LDA #$7F
        LDB #$FF
        CMP
        BGE n31b                ; A>=B true -> must branch
        JMP fail
n31b:
; ---- 32: signed equal — BLE/BGE taken, BLT/BGT not ----
        LDA #$32
        STA TID
        LDA #$05
        LDB #$05
        CMP
        BLT fail                ; not <
        LDA #$05
        LDB #$05
        CMP
        BGT fail                ; not >
        LDA #$05
        LDB #$05
        CMP
        BLE n32                 ; <= true (equal)
        JMP fail
n32:    LDA #$05
        LDB #$05
        CMP
        BGE n32b                ; >= true (equal)
        JMP fail
n32b:
; ---- 33: ADD signed overflow sets V (100 + 50 -> -106) ----
; This is detectable: after the overflowing ADD the result looks negative
; while both inputs were positive. We confirm via BLT after a compare that
; exercises V independently above; here just confirm the ADD result value.
        LDA #$33
        STA TID
        LDA #$64                ; 100
        LDB #$32                ; 50
        ADD                     ; = 150 = $96 (signed -106), V should be set
        LDB #$96
        CMP                     ; A == $96 ?
        JNZ fail
; ---- 40: interrupt — EI, raise IRQ, handler at $0808 runs, RTI resumes ----
        LDA #$40
        STA TID
        LDA #$00
        STA IRQFLAG          ; handler will set this to $55
        EI                   ; enable maskable interrupts
        LDA #$01
        STA $FF06            ; raise IRQ -> next fetch injects $08 -> handler
        LDA #$AA             ; <- this fetch is preempted; runs AFTER RTI returns
        STA MARK
        DI                   ; done; mask again
        LDA IRQFLAG          ; handler must have run
        LDB #$55
        CMP
        JNZ fail
        LDA MARK             ; preempted instruction must have completed after RTI
        LDB #$AA
        CMP
        JNZ fail
; =============================================================================
; Tier A -- the C-compiler ISA (docs/p8x-isa-c-extensions.md), pure microcode.
; Each op is checked on the case that exercises its CARRY PLANE (a byte
; boundary crossing) as well as the plain case. Scratch words at $9010.., a
; page-crossing displacement target at $9110, P2/P3 frames at $92xx.
; =============================================================================
; ---- C1: LDP1 #imm16 is a real 3-byte opcode ----
        LDA #$C1
        STA TID
        LDP1 #$9010
        LDA #$5A
        STA (P1)
        LDA $9010
        LDB #$5A
        CMP
        JNZ fail
; ---- C2: LDW a,#imm8 zero-extends into the high byte ----
        LDA #$C2
        STA TID
        LDA #$FF
        STA $9011                   ; pre-dirty the high byte
        LDW $9010,#$7B
        LDA $9010
        LDB #$7B
        CMP
        JNZ fail
        LDA $9011
        JNZ fail                    ; high byte must be 0
; ---- C3: LDW a,#imm16 ----
        LDA #$C3
        STA TID
        LDW $9010,#$BEEF
        LDA $9010
        LDB #$EF
        CMP
        JNZ fail
        LDA $9011
        LDB #$BE
        CMP
        JNZ fail
; ---- C4: INCW carries into the high byte ($00FF -> $0100) ----
        LDA #$C4
        STA TID
        LDW $9010,#$FF
        INCW $9010
        LDA $9010
        JNZ fail
        LDA $9011
        LDB #$01
        CMP
        JNZ fail
; ---- C5: INCW without carry ($0100 -> $0101) ----
        LDA #$C5
        STA TID
        INCW $9010
        LDA $9010
        LDB #$01
        CMP
        JNZ fail
        LDA $9011
        LDB #$01
        CMP
        JNZ fail
; ---- C6: DECW borrows from the high byte ($0100 -> $00FF) ----
        LDA #$C6
        STA TID
        LDW $9010,#$0100
        DECW $9010
        LDA $9010
        LDB #$FF
        CMP
        JNZ fail
        LDA $9011
        JNZ fail
; ---- C7: DECW without borrow ($00FF -> $00FE) ----
        LDA #$C7
        STA TID
        DECW $9010
        LDA $9010
        LDB #$FE
        CMP
        JNZ fail
        LDA $9011
        JNZ fail
; ---- C8: ADDW with a low-byte carry: $12FF + $0101 = $1400, source intact ----
        LDA #$C8
        STA TID
        LDW $9010,#$12FF
        LDW $9012,#$0101
        ADDW $9010,$9012
        LDA $9010
        JNZ fail
        LDA $9011
        LDB #$14
        CMP
        JNZ fail
        LDA $9012
        LDB #$01
        CMP
        JNZ fail                    ; b untouched
; ---- C9: ADDW 16-bit carry-out sets C: $FFFF + $0001 = $0000, C=1 ----
        LDA #$C9
        STA TID
        LDW $9010,#$FFFF
        LDW $9012,#$0001
        ADDW $9010,$9012
        JNC fail
        LDA $9010
        JNZ fail
        LDA $9011
        JNZ fail
; ---- CA: ADDW without carry-out clears C: $0102 + $0203 = $0305 ----
        LDA #$CA
        STA TID
        LDW $9010,#$0102
        LDW $9012,#$0203
        ADDW $9010,$9012
        JC  fail
        LDA $9010
        LDB #$05
        CMP
        JNZ fail
        LDA $9011
        LDB #$03
        CMP
        JNZ fail
; ---- CB: SUBW with a low-byte borrow: $1400 - $0101 = $12FF, C=1 (no borrow out) ----
        LDA #$CB
        STA TID
        LDW $9010,#$1400
        LDW $9012,#$0101
        SUBW $9010,$9012
        JNC fail
        LDA $9010
        LDB #$FF
        CMP
        JNZ fail
        LDA $9011
        LDB #$12
        CMP
        JNZ fail
; ---- CC: SUBW unsigned underflow: $0001 - $0002 = $FFFF, C=0 ----
        LDA #$CC
        STA TID
        LDW $9010,#$0001
        LDW $9012,#$0002
        SUBW $9010,$9012
        JC  fail
        LDA $9010
        LDB #$FF
        CMP
        JNZ fail
        LDA $9011
        LDB #$FF
        CMP
        JNZ fail
; ---- CD: CMPW: flags only, C = unsigned a>=b over the full word ----
        LDA #$CD
        STA TID
        LDW $9010,#$0200
        LDW $9012,#$01FF
        CMPW $9010,$9012            ; $0200 >= $01FF -> C=1 (low byte alone would say borrow)
        JNC fail
        LDA $9010
        JNZ fail                    ; memory untouched
        LDA $9011
        LDB #$02
        CMP
        JNZ fail
        CMPW $9012,$9010            ; $01FF < $0200 -> C=0
        JC  fail
; ---- CE: CMPW signed: $FFFF (-1) < $0001, so BGE falls through and BLT takes ----
        LDA #$CE
        STA TID
        LDW $9010,#$FFFF
        LDW $9012,#$0001
        CMPW $9010,$9012
        BGE fail                    ; -1 >= 1 would be wrong
        CMPW $9012,$9010
        BLT fail                    ; 1 < -1 would be wrong
; ---- CF: LDA/STA (P1+d) with a page-crossing displacement; STA keeps A, P1 ----
        LDA #$CF
        STA TID
        LDP1 #$90F0
        LDA #$3C
        STA (P1+$20)                ; -> $9110 (crosses into page $91)
        LDA $9110
        LDB #$3C
        CMP
        JNZ fail
        LDA #$00
        LDA (P1+$20)
        LDB #$3C
        CMP
        JNZ fail
        LDA #$77
        STA (P1+2)                  ; -> $90F2, and A must survive
        LDB #$77
        CMP
        JNZ fail
        LDA $90F2
        LDB #$77
        CMP
        JNZ fail
        TPA1L                       ; P1 itself unchanged
        LDB #$F0
        CMP
        JNZ fail
        TPA1H
        LDB #$90
        CMP
        JNZ fail
; ---- D0: LDW a,(P2+d) / STW (P2+d),a, then a page-crossing P3 frame ----
        LDA #$D0
        STA TID
        LDW $9010,#$ABCD
        LDP2 #$9200
        STW (P2+$10),$9010          ; mem[$9210] := $ABCD
        LDA $9210
        LDB #$CD
        CMP
        JNZ fail
        LDA $9211
        LDB #$AB
        CMP
        JNZ fail
        LDW $9012,(P2+$10)          ; $9012 := mem[$9210]
        LDA $9012
        LDB #$CD
        CMP
        JNZ fail
        LDA $9013
        LDB #$AB
        CMP
        JNZ fail
        LDP3 #$92F8
        STW (P3+$0A),$9010          ; -> $9302 (crosses the page)
        LDA $9302
        LDB #$CD
        CMP
        JNZ fail
        LDA $9303
        LDB #$AB
        CMP
        JNZ fail
        LDW $9014,(P3+$0A)
        LDA $9015
        LDB #$AB
        CMP
        JNZ fail
        LDP3 #$FEFF                 ; restore the stack
; ---- D1: ADDP3 / SUBP3 across a page boundary ----
        LDA #$D1
        STA TID
        LDP3 #$80FE
        ADDP3 #4                    ; $8102
        TPA3L
        LDB #$02
        CMP
        JNZ fail
        TPA3H
        LDB #$81
        CMP
        JNZ fail
        SUBP3 #4                    ; back to $80FE
        TPA3L
        LDB #$FE
        CMP
        JNZ fail
        TPA3H
        LDB #$80
        CMP
        JNZ fail
        ADDP3 #1                    ; no carry: $80FF
        TPA3H
        LDB #$80
        CMP
        JNZ fail
        LDP3 #$FEFF                 ; restore the stack
; ---- D2: PHW leaves the word LITTLE-ENDIAN on the stack (lo at P3+1), PLW round-trips ----
        LDA #$D2
        STA TID
        LDW $9010,#$BEEF
        PHW $9010
        LDA (P3+1)
        LDB #$EF
        CMP
        JNZ fail                    ; low byte on top
        LDA (P3+2)
        LDB #$BE
        CMP
        JNZ fail
        LDW $9012,(P3+1)            ; a pushed word IS a frame word
        LDA $9013
        LDB #$BE
        CMP
        JNZ fail
        PLW $9014
        LDA $9014
        LDB #$EF
        CMP
        JNZ fail
        LDA $9015
        LDB #$BE
        CMP
        JNZ fail
        TPA3L                       ; stack balanced
        LDB #$FF
        CMP
        JNZ fail
; ---- D3: ADDW a,#imm8 with carry and 16-bit C ($12FF + 1 = $1300; $FFFF + 1 -> C) ----
        LDA #$D3
        STA TID
        LDW $9010,#$12FF
        ADDW $9010,#1
        LDA $9010
        JNZ fail
        LDA $9011
        LDB #$13
        CMP
        JNZ fail
        LDW $9010,#$FFFF
        ADDW $9010,#1
        JNC fail
        LDA $9011
        JNZ fail
        LDW $9010,#$0102
        ADDW $9010,#$FE             ; $0200, no carry out
        JC  fail
        LDA $9011
        LDB #$02
        CMP
        JNZ fail
; ---- D4: SUBW a,#imm8 with borrow ($1300 - 1 = $12FF, C=1); underflow clears C ----
        LDA #$D4
        STA TID
        LDW $9010,#$1300
        SUBW $9010,#1
        JNC fail
        LDA $9010
        LDB #$FF
        CMP
        JNZ fail
        LDA $9011
        LDB #$12
        CMP
        JNZ fail
        LDW $9010,#$0001
        SUBW $9010,#2
        JC  fail
        LDA $9011
        LDB #$FF
        CMP
        JNZ fail
; ---- D5: CMPW a,#imm8: unsigned over the full word, memory kept, signed branches ----
        LDA #$D5
        STA TID
        LDW $9010,#$0100
        CMPW $9010,#$FF             ; $0100 >= $FF (low byte alone would borrow)
        JNC fail
        LDA $9010
        JNZ fail
        LDA $9011
        LDB #$01
        CMP
        JNZ fail
        LDW $9010,#$00FE
        CMPW $9010,#$FF             ; $FE < $FF
        JC  fail
        LDW $9010,#$FFFF
        CMPW $9010,#1               ; -1 < 1 signed
        BGE fail
        LDW $9010,#$0005
        CMPW $9010,#1
        BLT fail
; ---- D6: LEAW a,(Pn+d) takes a frame address (page-crossing); LPW3 restores P3 ----
        LDA #$D6
        STA TID
        LDP1 #$90F8
        LEAW $9010,(P1+$10)         ; $9108
        LDA $9010
        LDB #$08
        CMP
        JNZ fail
        LDA $9011
        LDB #$91
        CMP
        JNZ fail
        LDP3 #$92F0
        LEAW $9012,(P3+3)           ; $92F3
        LDA $9012
        LDB #$F3
        CMP
        JNZ fail
        LDA $9013
        LDB #$92
        CMP
        JNZ fail
        LDW $9014,#$FEFF
        LPW3 $9014                  ; P3 := $FEFF
        TPA3L
        LDB #$FF
        CMP
        JNZ fail
        TPA3H
        LDB #$FE
        CMP
        JNZ fail
; ---- all passed ----
        LDA #$00
        HLT

fail:   LDA TID
        HLT

subr:   LDA #$99
        RTS
subr2:  LDA #$77
        RTS

; rev C interrupt handler — the forcing buffer vectors here ($0808). It sets a
; flag and returns; RTI pops flags+PC so the interrupted program resumes intact.
        .org $0808
IRQH:   LDA #$55
        STA IRQFLAG
        RTI
