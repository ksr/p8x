; isa_test.asm -- directed all-opcode exerciser for the Milestone-1 co-sim.
;
; Executes every opcode in microcode/genucode.py's OPC table (88 distinct codes)
; at least once, with operands chosen to move the flags -- carry out, borrow,
; signed overflow at the sign boundary, zero -- rather than merely to execute.
;
; This is a co-sim PAYLOAD, not a self-checking test. It never compares anything
; itself; correctness is decided by fpga/sim/run.sh diffing the RTL trace against
; p8xemu -T cycle by cycle. A wrong ALU result or a mis-set flag shows up because
; it makes the two traces differ, naming the exact microcycle.
;
;   ./run.sh 60000 isa_test.asm
;
; Constraints it respects:
;   - runs from reset at $0000, in ROM ($0000..$1FFF, read-only)
;   - writes only to the $3000 scratch page (RAM is $2000..$FEFF)
;   - $0808 is the IRQ vector, so the handler is pinned there and main code
;     must stay below it
;   - ends in HLT so the RTL testbench and the emulator stop together

SCRATCH = $3000                 ; general byte scratch
W1      = $3010                 ; 16-bit scratch words (PHW/PLW/LPW/MOVW)
W2      = $3012
STKL    = $00                   ; stack top $3F00 (P3 = SP, grows down)
STKH    = $3F
IRQREQ  = $FF06                 ; write here raises a maskable IRQ

        .org $0000

;=== 0. stack pointer (P3 is SP) ===========================================
        LPL3 #STKL
        LPH3 #STKH

;=== 1. immediate and absolute load/store ==================================
        LDA  #$5A               ; 10  LDA #
        STA  SCRATCH            ; 14  STA a
        LDB  #$0F               ; 11  LDB #
        LDA  SCRATCH            ; 12  LDA a
        LDB  SCRATCH            ; 13  LDB a

;=== 2. carry control and the A/B ALU group ================================
        CLC                     ; 72
        SEC                     ; 73
        LDA  #$7F               ; +127
        LDB  #$01
        ADD                     ; 20  -> $80: signed overflow, N set
        LDA  #$80               ; -128
        LDB  #$01
        SUB                     ; 21  -> $7F: signed overflow the other way
        LDA  #$FF
        LDB  #$01
        ADD                     ; 20  -> $00 with carry out, Z set
        LDA  #$00
        LDB  #$01
        SUB                     ; 21  -> $FF with borrow
        LDA  #$F0
        LDB  #$0F
        AND                     ; 22  -> $00, Z set
        OR                      ; 23  -> $0F
        XOR                     ; 24  -> $00
        LDA  #$3C
        LDB  #$3C
        CMP                     ; 25  equal: Z set, A preserved
        INC                     ; 26
        DEC                     ; 27
        CLC
        SHL                     ; 28  carry-in clear
        SHR                     ; 29
        SEC
        ROL                     ; 2a  carry-in set
        ROR                     ; 2b

;=== 3. T register and the T ALU group =====================================
        LDA  #$12
        STA  W1
        LDA  #$34
        STA  W1+1
        LDT  #$34               ; 86  LDT #
        LDT  W1                 ; 87  LDT a
        LDA  #$10
        ADDT                    ; 80
        SUBT                    ; 81
        ANDT                    ; 82
        ORT                     ; 83
        XORT                    ; 84
        CMPT                    ; 85

;=== 4. pointer immediate loads ============================================
        LPL1 #$00               ; 31
        LPH1 #$30               ; 35   P1 = $3000
        LPL2 #$20               ; 32
        LPH2 #$30               ; 36   P2 = $3020
        LPL3 #$40               ; 33
        LPH3 #$30               ; 37   P3 = $3040 (SP restored in section 8)

;=== 5. pointer-indirect load/store ========================================
        LDA  #$A5
        STA  (P1)               ; 1d
        LDA  (P1)               ; 51
        STA  (P1)+              ; 19
        LDA  (P1)+              ; 15
        LDA  #$5A
        STA  (P2)               ; 1e
        LDA  (P2)               ; 52
        STA  (P2)+              ; 1a
        LDA  (P2)+              ; 16
        LDA  #$3C
        STA  (P3)               ; 1f
        LDA  (P3)               ; 53
        STA  (P3)+              ; 1b
        LDA  (P3)+              ; 17

;=== 6. pointer increment / decrement ======================================
        INP1                    ; 54
        INP2                    ; 55
        INP3                    ; 56
        DEP1                    ; 58
        DEP2                    ; 59
        DEP3                    ; 5a

;=== 7. A <-> pointer byte transfers =======================================
        LDA  #$11
        TAP1L                   ; 5e
        LDA  #$31
        TAP1H                   ; 5f
        LDA  #$22
        TAP2L                   ; 60
        LDA  #$32
        TAP2H                   ; 61
        LDA  #$44
        TAP3L                   ; 62
        LDA  #$33
        TAP3H                   ; 63
        TPA1L                   ; 68
        TPA1H                   ; 69
        TPA2L                   ; 6a
        TPA2H                   ; 6b
        TPA3L                   ; 6c
        TPA3H                   ; 6d

;=== 8. stack (restore SP first -- section 7 clobbered P3) =================
        LPL3 #STKL
        LPH3 #STKH
        LDA  #$77
        PHA                     ; 70
        PLA                     ; 71
        LDA  #$CD
        STA  W1
        LDA  #$AB
        STA  W1+1
        PHW  W1                 ; 74  push the 16-bit word at W1
        PLW  W2                 ; 75  pop it back into W2 (SP now balanced)

;=== 9. pointer word loads and MOVW ========================================
        LPW1 W1                 ; 76  P1 = word at W1
        LPW2 W1                 ; 77  P2 = word at W1
        MOVW W2,W1              ; 78  copy word W1 -> W2

;=== 10. branches -- every one taken AND not taken =========================
        LDA  #$80               ; -128
        LDB  #$01               ; +1
        CMP                     ; signed LT true, GT false
        BLT  B1                 ; 44  taken
        NOP
B1:      BGE  B2                 ; 45  NOT taken
        NOP
B2:      BLE  B3                 ; 46  taken
        NOP
B3:      BGT  B4                 ; 47  NOT taken
        NOP
B4:      LDA  #$01               ; +1
        LDB  #$80               ; -128
        CMP                     ; signed GT true, LT false
        BGE  B5                 ; 45  taken
        NOP
B5:      BGT  B6                 ; 47  taken
        NOP
B6:      BLT  B7                 ; 44  NOT taken
        NOP
B7:      BLE  B8                 ; 46  NOT taken
        NOP
B8:      LDA  #$05
        LDB  #$05
        CMP                     ; equal: Z set
        BZ   B9                 ; 48  taken
        NOP
B9:      BNZ  B10                ; 49  NOT taken
        NOP
B10:     LDA  #$05
        LDB  #$06
        CMP                     ; not equal: Z clear
        BNZ  B11                ; 49  taken
        NOP
B11:     BZ   B12                ; 48  NOT taken
        NOP
B12:     SEC
        BCP  B13                ; 4a  taken (C set)
        NOP
B13:     JNC  B14                ; 4c  NOT taken
        NOP
B14:     CLC
        JNC  B15                ; 4c  taken (C clear)
        NOP
B15:     BCP  B16                ; 4a  NOT taken
        NOP

;=== 11. jumps and subroutines =============================================
B16:     JMP  J1                 ; 40
        NOP                     ; not reached
J1:      JSR  SUB1               ; 43  absolute call
        LDP1 #SUB2              ; pseudo -> LPL1/LPH1
        JSR  (P1)               ; 41  indirect call

;=== 12. interrupts ========================================================
        EI                      ; 02  enable maskable interrupts
        LDA  #$01
        STA  IRQREQ             ; raise IRQ: next fetch injects opcode $08,
                                ; which vectors to the $0808 handler below
        DI                      ; 03  back off again
        NOP                     ; 00
        HLT                     ; 01  stops RTL and emulator together

;=== IRQ vector (fixed address -- main code must stay below this) ==========
        .org $0808
IRQH:    NOP
        RTI                     ; 04  pops flags then return PC

;=== subroutines ===========================================================
        .org $0820
SUB1:    NOP
        RTS                     ; 42
SUB2:    NOP
        RTS
