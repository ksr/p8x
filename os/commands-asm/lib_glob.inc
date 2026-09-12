; lib_glob.inc — shared glob matcher + directory-entry buffer for hand-asm
; commands that do their own directory walk (find). Declared with `;#use glob`.
; Lean counterpart of lib_glob.c + lib_dirent.c's de[] (no openarg/nextc/glob
; expansion — those live in lib_stdin.inc). Do not use both includes in one
; command (they would both define gmatch/de).
;   gmatch : gp/gs -> A = 1 if pattern gp matches string gs (case-insensitive)
;   de[17] : directory-entry snapshot buffer for SYS_DIRENTRY ($201B)

; gmatch — recursive glob matcher, mirrors lib_glob.c's gmatch().
; In:  gp = ptr to pattern (NUL-terminated), gs = ptr to string.
;      Both are 16-bit zero-page pointer variables (lo,hi) advanced in place.
; Out: A = 1 on match, 0 on no match.
; Supports '?' (any one char) and '*' (any run, incl. empty); other chars
; compare case-insensitively (via gupper). Clobbers A, B, P1, P2 and the
; scratch vars gpc/gsc/gmr/guch. Recurses through gm_star (uses the SP stack
; to save/restore gp/gs across the trial call).
gmatch: LPW1 gp                ; <- tierA: pointer load (next: LDA)
        LDA (P1)
        STA gpc
        LDB #'*'
        CMP
        JZ gm_star             ; pattern char is '*' -> wildcard-run handler
        LDB #0
        CMP
        JZ gm_pend             ; pattern exhausted -> match iff string also ends
        LPW2 gs                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        STA gsc                ; gsc = *gs (current string char)
        LDB #0
        CMP
        JZ gm_r0               ; string ended but pattern has a literal -> no match
        LDA gpc
        LDB #'?'
        CMP
        JZ gm_adv              ; '?' matches any single char -> advance both
        LDA gpc                ; case-insensitive compare of the two chars
        JSR gupper
        STA gpc
        LDA gsc
        JSR gupper
        LDB gpc
        CMP
        JZ gm_adv              ; equal (folded) -> advance both, tail-loop
        LDA #0                 ; mismatch
        RTS
; gm_adv: gp++, gs++ (16-bit increments with carry into hi byte), then re-enter
; gmatch as a tail loop for the next char pair.
gm_adv: INCW gp                ; <- tierA: 16-bit INCW chain, skip label gm_a1 dropped (next: LDA)
gm_a1:  INCW gs                ; <- tierA: 16-bit INCW chain, skip label gm_a2 dropped (next: JMP gmatch -> LDA)
        JMP gmatch
; gm_pend: pattern is at its NUL terminator. Match succeeds only if the string
; is also at its terminator (no trailing chars left unmatched).
gm_pend:LPW2 gs                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #0
        CMP
        JZ gm_r1
        LDA #0
        RTS
gm_r0:  LDA #0                 ; common "return 0 / no match" exit
        RTS
gm_r1:  LDA #1                 ; common "return 1 / match" exit
        RTS
; gm_star: handle '*'. Skip the '*' in the pattern, then try to match the rest
; of the pattern against successively longer suffixes of the string (starting
; with the empty suffix). Classic backtracking: for each try, save gp/gs on the
; SP stack, recurse into gmatch, restore, and if it returned 1 succeed; else
; consume one more string char and retry. Fail when the string runs out.
gm_star:LDA gp                 ; gp++ past the '*'
        LDB #1
        ADD
        STA gp
        JNC gm_s0
        LDA gp+1
        INC
        STA gp+1
; gm_s0: one backtracking trial. Push gp,gs (order matters: they pop LIFO), try
; matching the post-'*' pattern at the current string position, then restore.
gm_s0:  LDA gp
        PHA
        LDA gp+1
        PHA
        LDA gs
        PHA
        LDA gs+1
        PHA
        JSR gmatch
        STA gmr                ; gmr = result of the trial match
        PLA
        STA gs+1               ; restore gp/gs (popped in reverse push order)
        PLA
        STA gs
        PLA
        STA gp+1
        PLA
        STA gp
        LDA gmr
        LDB #0
        CMP
        JNZ gm_r1              ; trial matched -> '*' succeeds
        LPW2 gs                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #0
        CMP
        JZ gm_r0
        INCW gs                ; <- tierA: 16-bit INCW chain before JMP gm_s0 (next: JMP gm_s0 -> LDA)
        JMP gm_s0
; gupper — fold a lowercase ASCII letter to uppercase (used for case-insensitive
; matching). In: A = char. Out: A = uppercased char. Clobbers B and guch.
; Only 'a'..'z' (0x61..0x7A) are shifted by 32; all other bytes pass through.
; The bounds test uses CMP semantics: C=1 when A>=B, so #123 (='z'+1) with JC
; rejects chars >= 123, and #'a' with JNC rejects chars < 'a'.
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
