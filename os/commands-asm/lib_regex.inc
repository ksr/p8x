; lib_regex.inc — shared basic-regex matcher for hand-asm grep/sed (asm
; counterpart of lib_regex.c). Declared with `;#use regex`.
;   match    : rx_re / rx_t (word ptrs) -> A = 1 if re matches anywhere in t
;   matchhere: 1 if re matches a prefix of t; sets rend past the match
; Dialect: . any, * >=0, + >=1, ? 0/1 of the preceding char (or '.'), ^ start,
; $ end. Recursive; re/t live in memory words, saved on the hardware stack across
; non-tail recursive calls (P3 is the stack pointer). Non-greedy (fewest first).

rend:   .fill 2                       ; ptr one past the last char matched (set by matchhere)

; match(rx_re, rx_t) -> A = 1 if re matches anywhere in t, else 0.
; If re starts with '^' it only tries at t's start; otherwise it slides the
; start point right one char at a time until a match or end-of-text.
; Clobbers A/B/P1; uses rx_* scratch. mre/mct hold the saved re/t across the slide.
match:  LDA rx_re                    ; P1 <- rx_re, then peek first regex char
        TAP1L
        LDA rx_re+1
        TAP1H
        LDA (P1)
        LDB #'^'
        CMP
        JNZ m_loop
        LDA rx_re                    ; anchored '^': advance re past it, then matchhere(re+1, t)
        LDB #1
        ADD
        STA rx_re
        JNC m_a
        LDA rx_re+1
        INC
        STA rx_re+1
m_a:    JMP matchhere                ; tail call; its RTS returns to match's caller
; Unanchored: save the working re/t in mre/mct, then try each start position.
m_loop: LDA rx_re
        STA mre
        LDA rx_re+1
        STA mre+1
        LDA rx_t
        STA mct
        LDA rx_t+1
        STA mct+1
; Loop: restore re/t from the saved copies (matchhere mutates rx_re/rx_t) and try.
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
        JNZ m_yes                     ; matched at this start position -> done
        LDA mct                       ; else: if *mct == 0 we've exhausted the text
        TAP1L
        LDA mct+1
        TAP1H
        LDA (P1)
        LDB #0
        CMP
        JZ m_no
        LDA mct                       ; advance saved text ptr and retry one char over
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

; matchhere(rx_re, rx_t) -> A = 1 if re matches a PREFIX of t, else 0.
; On success sets rend to the text ptr just past the match. Recursive: literal
; match tail-recurses; the *, +, ? branches recurse via JSR matchhere and save
; their loop state on the hardware stack (P3) across the call.
; rx_c = re[0] (the char being matched), rx_r1 = re[1] (possible quantifier).
matchhere:
        LDA rx_re
        TAP1L
        LDA rx_re+1
        TAP1H
        LDA (P1)
        STA rx_c                      ; rx_c = re[0]
        INP1
        LDA (P1)
        STA rx_r1                     ; rx_r1 = re[1] (look one ahead for * + ?)
        LDA rx_c
        LDB #0
        CMP
        JZ mh_chk0                    ; re[0]==0 (end of pattern): skip quantifier checks
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
; Empty pattern matches here: record end ptr = current text ptr, return 1.
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
; '$' end-anchor, only special when it is the last pattern char (re[1]==0).
mh_dollar:
        LDA rx_c
        LDB #'$'
        CMP
        JNZ mh_lit
        LDA rx_r1
        LDB #0
        CMP
        JNZ mh_lit                    ; '$' not at end of pattern -> treat as literal
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
        LDA #1                        ; '$' matched: at end of text -> success
        RTS
; Single literal char (or '.'): must match one text char, then advance both.
mh_lit: LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        STA rx_tc                     ; rx_tc = current text char
        LDB #0
        CMP
        JZ mh_r0                      ; text exhausted -> fail
        LDA rx_c
        LDB #'.'
        CMP
        JZ mh_adv                     ; '.' matches any char
        LDA rx_c
        LDB rx_tc
        CMP
        JZ mh_adv                     ; exact char match
mh_r0:  LDA #0                        ; common failure exit
        RTS
mh_adv: LDA rx_re                     ; re++ , t++ , then tail-recurse into matchhere
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
mh_r1:  LDA #1                        ; common success exit
        RTS

; --- c* : zero or more --------------------------------------------------
; c* : cc=the char, re2=re+2 (pattern after 'c*'), ct=t (zero matches to start).
; Non-greedy: try matching the rest at ct first, then consume one 'c' and retry.
mh_star:LDA rx_c
        STA rx_cc
        JSR re2                       ; rx_re2 = rx_re + 2
        LDA rx_t
        STA rx_ct
        LDA rx_t+1
        STA rx_ct+1
        JMP mstar_l
; --- c+ : one or more ---------------------------------------------------
; c+ : like c* but requires at least one 'c'. Verify t[0] matches c, then enter
; the shared loop starting at ct=t+1 (one char already consumed).
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
        JZ mh_r0                      ; text exhausted -> no first match -> fail
        LDA rx_cc
        LDB #'.'
        CMP
        JZ mp_ok                      ; '.' matches the first char
        LDA rx_tc
        LDB rx_cc
        CMP
        JNZ mh_r0                     ; first text char != c -> fail
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
; Shared *, + loop. Each pass: point re at re2 and t at ct, then try matchhere
; on the tail. Because matchhere clobbers rx_re/rx_t/rx_re2/rx_ct/rx_cc (and
; recursion nests), save cc/re2/ct on the hardware stack around the JSR and
; restore after. On success -> mh_r1; else consume one more 'c' and loop.
mstar_l:LDA rx_re2
        STA rx_re
        LDA rx_re2+1
        STA rx_re+1
        LDA rx_ct
        STA rx_t
        LDA rx_ct+1
        STA rx_t+1
        LDA rx_cc                     ; push loop state (pulled back in reverse order)
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
        STA rx_res                    ; save result before restoring registers
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
        JNZ mh_r1                     ; tail matched -> whole quantifier matched
        LDA rx_ct                     ; tail failed: can we consume one more 'c'?
        TAP1L
        LDA rx_ct+1
        TAP1H
        LDA (P1)
        STA rx_tc
        LDB #0
        CMP
        JZ mh_r0                      ; text exhausted -> fail
        LDA rx_cc
        LDB #'.'
        CMP
        JZ mstar_adv                  ; '.' consumes any char
        LDA rx_tc
        LDB rx_cc
        CMP
        JNZ mh_r0                     ; next char isn't 'c' -> can't extend -> fail
mstar_adv:                            ; ct++ and loop for another try
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
; c? : zero or one 'c'. Non-greedy would try zero first, but here the "one"
; branch is attempted first only when the char actually matches; on failure it
; falls through to mq_zero (the zero-width tail). If t[0] can't match c, skip
; straight to mq_zero.
mh_ques:LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        STA rx_tc
        LDB #0
        CMP
        JZ mq_zero                    ; text exhausted -> only the zero branch
        LDA rx_c
        LDB #'.'
        CMP
        JZ mq_one                     ; '.' matches -> try consuming one
        LDA rx_tc
        LDB rx_c
        CMP
        JNZ mq_zero                   ; char mismatch -> zero branch only
; "one" branch: save re/t, try matchhere(re+2, t+1); on fail restore and fall
; through to the "zero" branch.
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
        JNZ mh_r1                     ; the "one" branch matched -> success
mq_zero:JSR re2                       ; tail: matchhere(re+2, t)  (skip 'c?' entirely)
        LDA rx_re2
        STA rx_re
        LDA rx_re2+1
        STA rx_re+1
        JMP matchhere

; re2: helper computing rx_re2 = rx_re + 2 (skip a char and its quantifier).
; 16-bit add with carry into the high byte. Clobbers A/B. Returns via RTS.
re2:    LDA rx_re
        LDB #2
        ADD
        STA rx_re2
        LDA rx_re+1
        JNC re2a
        INC
re2a:   STA rx_re2+1
        RTS

; --- scratch state (module-global; regex is not reentrant across calls) -------
rx_re:  .fill 2                       ; current regex pointer (matchhere input)
rx_t:   .fill 2                       ; current text pointer (matchhere input)
rx_re2: .fill 2                       ; re+2, pattern tail after a quantified char
rx_ct:  .fill 2                       ; text cursor for the *, + scan loop
rx_c:   .fill 1                       ; re[0], the char currently being matched
rx_r1:  .fill 1                       ; re[1], the possible quantifier (* + ?)
rx_tc:  .fill 1                       ; current text char under test
rx_cc:  .fill 1                       ; the char repeated by a *, + quantifier
rx_res: .fill 1                       ; saved matchhere result across stack restore
mre:    .fill 2                       ; saved regex ptr for the unanchored slide
mct:    .fill 2                       ; saved text start ptr for the unanchored slide
