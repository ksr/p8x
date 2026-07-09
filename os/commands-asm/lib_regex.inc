; lib_regex.inc — shared basic-regex matcher for hand-asm grep/sed (asm
; counterpart of lib_regex.c). Declared with `;#use regex`.
;   match    : rx_re / rx_t (word ptrs) -> A = 1 if re matches anywhere in t
;   matchhere: 1 if re matches a prefix of t; sets rend past the match
; Dialect: . any, * >=0, + >=1, ? 0/1 of the preceding char (or '.'), ^ start,
; $ end. Recursive; re/t live in memory words, saved on the hardware stack across
; non-tail recursive calls (P3 is the stack pointer). Non-greedy (fewest first).

rend:   .fill 2

match:  LDA rx_re
        TAP1L
        LDA rx_re+1
        TAP1H
        LDA (P1)
        LDB #'^'
        CMP
        JNZ m_loop
        LDA rx_re                    ; anchored: matchhere(re+1, t)
        LDB #1
        ADD
        STA rx_re
        JNC m_a
        LDA rx_re+1
        INC
        STA rx_re+1
m_a:    JMP matchhere
m_loop: LDA rx_re
        STA mre
        LDA rx_re+1
        STA mre+1
        LDA rx_t
        STA mct
        LDA rx_t+1
        STA mct+1
m_pl:   LDA mre
        STA rx_re
        LDA mre+1
        STA rx_re+1
        LDA mct
        STA rx_t
        LDA mct+1
        STA rx_t+1
        JSR matchhere
        LDB #0
        CMP
        JNZ m_yes
        LDA mct
        TAP1L
        LDA mct+1
        TAP1H
        LDA (P1)
        LDB #0
        CMP
        JZ m_no
        LDA mct
        LDB #1
        ADD
        STA mct
        JNC m_pl
        LDA mct+1
        INC
        STA mct+1
        JMP m_pl
m_yes:  LDA #1
        RTS
m_no:   LDA #0
        RTS

matchhere:
        LDA rx_re
        TAP1L
        LDA rx_re+1
        TAP1H
        LDA (P1)
        STA rx_c
        INP1
        LDA (P1)
        STA rx_r1
        LDA rx_c
        LDB #0
        CMP
        JZ mh_chk0
        LDA rx_r1
        LDB #'*'
        CMP
        JZ mh_star
        LDA rx_r1
        LDB #'+'
        CMP
        JZ mh_plus
        LDA rx_r1
        LDB #'?'
        CMP
        JZ mh_ques
mh_chk0:LDA rx_c
        LDB #0
        CMP
        JNZ mh_dollar
        LDA rx_t
        STA rend
        LDA rx_t+1
        STA rend+1
        LDA #1
        RTS
mh_dollar:
        LDA rx_c
        LDB #'$'
        CMP
        JNZ mh_lit
        LDA rx_r1
        LDB #0
        CMP
        JNZ mh_lit
        LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        LDB #0
        CMP
        JNZ mh_r0
        LDA rx_t
        STA rend
        LDA rx_t+1
        STA rend+1
        LDA #1
        RTS
mh_lit: LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        STA rx_tc
        LDB #0
        CMP
        JZ mh_r0
        LDA rx_c
        LDB #'.'
        CMP
        JZ mh_adv
        LDA rx_c
        LDB rx_tc
        CMP
        JZ mh_adv
mh_r0:  LDA #0
        RTS
mh_adv: LDA rx_re
        LDB #1
        ADD
        STA rx_re
        JNC mha1
        LDA rx_re+1
        INC
        STA rx_re+1
mha1:   LDA rx_t
        LDB #1
        ADD
        STA rx_t
        JNC mha2
        LDA rx_t+1
        INC
        STA rx_t+1
mha2:   JMP matchhere
mh_r1:  LDA #1
        RTS

; --- c* : zero or more --------------------------------------------------
mh_star:LDA rx_c
        STA rx_cc
        JSR re2                       ; rx_re2 = rx_re + 2
        LDA rx_t
        STA rx_ct
        LDA rx_t+1
        STA rx_ct+1
        JMP mstar_l
; --- c+ : one or more ---------------------------------------------------
mh_plus:LDA rx_c
        STA rx_cc
        LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        STA rx_tc
        LDB #0
        CMP
        JZ mh_r0
        LDA rx_cc
        LDB #'.'
        CMP
        JZ mp_ok
        LDA rx_tc
        LDB rx_cc
        CMP
        JNZ mh_r0
mp_ok:  JSR re2
        LDA rx_t                      ; ct = t+1
        LDB #1
        ADD
        STA rx_ct
        LDA rx_t+1
        JNC mp1
        INC
mp1:    STA rx_ct+1
        JMP mstar_l
; shared star/plus loop over rx_ct (re2 fixed, cc = the char)
mstar_l:LDA rx_re2
        STA rx_re
        LDA rx_re2+1
        STA rx_re+1
        LDA rx_ct
        STA rx_t
        LDA rx_ct+1
        STA rx_t+1
        LDA rx_cc
        PHA
        LDA rx_re2
        PHA
        LDA rx_re2+1
        PHA
        LDA rx_ct
        PHA
        LDA rx_ct+1
        PHA
        JSR matchhere
        STA rx_res
        PLA
        STA rx_ct+1
        PLA
        STA rx_ct
        PLA
        STA rx_re2+1
        PLA
        STA rx_re2
        PLA
        STA rx_cc
        LDA rx_res
        LDB #0
        CMP
        JNZ mh_r1
        LDA rx_ct
        TAP1L
        LDA rx_ct+1
        TAP1H
        LDA (P1)
        STA rx_tc
        LDB #0
        CMP
        JZ mh_r0
        LDA rx_cc
        LDB #'.'
        CMP
        JZ mstar_adv
        LDA rx_tc
        LDB rx_cc
        CMP
        JNZ mh_r0
mstar_adv:
        LDA rx_ct
        LDB #1
        ADD
        STA rx_ct
        JNC mstar_l
        LDA rx_ct+1
        INC
        STA rx_ct+1
        JMP mstar_l
; --- c? : zero or one ---------------------------------------------------
mh_ques:LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        STA rx_tc
        LDB #0
        CMP
        JZ mq_zero
        LDA rx_c
        LDB #'.'
        CMP
        JZ mq_one
        LDA rx_tc
        LDB rx_c
        CMP
        JNZ mq_zero
mq_one: LDA rx_re                     ; try matchhere(re+2, t+1)
        PHA
        LDA rx_re+1
        PHA
        LDA rx_t
        PHA
        LDA rx_t+1
        PHA
        JSR re2
        LDA rx_re2
        STA rx_re
        LDA rx_re2+1
        STA rx_re+1
        LDA rx_t
        LDB #1
        ADD
        STA rx_t
        JNC mq1
        LDA rx_t+1
        INC
        STA rx_t+1
mq1:    JSR matchhere
        STA rx_res
        PLA
        STA rx_t+1
        PLA
        STA rx_t
        PLA
        STA rx_re+1
        PLA
        STA rx_re
        LDA rx_res
        LDB #0
        CMP
        JNZ mh_r1
mq_zero:JSR re2                       ; tail: matchhere(re+2, t)
        LDA rx_re2
        STA rx_re
        LDA rx_re2+1
        STA rx_re+1
        JMP matchhere

; re2: rx_re2 = rx_re + 2
re2:    LDA rx_re
        LDB #2
        ADD
        STA rx_re2
        LDA rx_re+1
        JNC re2a
        INC
re2a:   STA rx_re2+1
        RTS

rx_re:  .fill 2
rx_t:   .fill 2
rx_re2: .fill 2
rx_ct:  .fill 2
rx_c:   .fill 1
rx_r1:  .fill 1
rx_tc:  .fill 1
rx_cc:  .fill 1
rx_res: .fill 1
mre:    .fill 2
mct:    .fill 2
