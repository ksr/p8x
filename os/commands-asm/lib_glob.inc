; lib_glob.inc — shared glob matcher + directory-entry buffer for hand-asm
; commands that do their own directory walk (find). Declared with `;#use glob`.
; Lean counterpart of lib_glob.c + lib_dirent.c's de[] (no openarg/nextc/glob
; expansion — those live in lib_stdin.inc). Do not use both includes in one
; command (they would both define gmatch/de).
;   gmatch : gp/gs -> A = 1 if pattern gp matches string gs (case-insensitive)
;   de[17] : directory-entry snapshot buffer for SYS_DIRENTRY ($201B)

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
        JZ gm_r0
        LDA gpc
        LDB #'?'
        CMP
        JZ gm_adv
        LDA gpc
        JSR gupper
        STA gpc
        LDA gsc
        JSR gupper
        LDB gpc
        CMP
        JZ gm_adv
        LDA #0
        RTS
gm_adv: LDA gp
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
gm_star:LDA gp
        LDB #1
        ADD
        STA gp
        JNC gm_s0
        LDA gp+1
        INC
        STA gp+1
gm_s0:  LDA gp
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
gupper: STA guch
        LDB #'a'
        CMP
        JNC gup_no
        LDA guch
        LDB #123
        CMP
        JC gup_no
        LDA guch
        LDB #32
        SUB
        RTS
gup_no: LDA guch
        RTS

gp:     .fill 2
gs:     .fill 2
gpc:    .fill 1
gsc:    .fill 1
gmr:    .fill 1
guch:   .fill 1
de:     .fill 18   ; +[17] = length bits 16..23 (24-bit file size)
