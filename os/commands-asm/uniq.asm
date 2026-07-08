; uniq.asm — hand-coded UNIQ command (asm counterpart of os/commands/uniq.c).
;   UNIQ [file]   collapse adjacent duplicate lines (file or stdin).
; Shares the input engine via `;#use stdin`. readline() + streq() are inline.
; Entry: P2 = arg tail.
;#use stdin

        .org $7A00
        TPA2L
        STA u_arg
        TPA2H
        STA u_arg+1
u_sk:   LDA u_arg
        TAP2L
        LDA u_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ u_chk
        LDA u_arg
        LDB #1
        ADD
        STA u_arg
        JNC u_sk
        LDA u_arg+1
        INC
        STA u_arg+1
        JMP u_sk
u_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ u_open
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ u_usage
        LDB #'H'
        CMP
        JZ u_usage
u_open: LDA u_arg
        STA oa_a
        LDA u_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ u_nf
        LDA #1
        STA first
u_loop: LDA #<cur
        STA rl_buf
        LDA #>cur
        STA rl_buf+1
        JSR readline
        LDB #0
        CMP
        JZ u_end
        LDA first
        LDB #0
        CMP
        JNZ u_put                    ; first line -> print
        LDA #<cur
        STA se_p
        LDA #>cur
        STA se_p+1
        LDA #<prev
        STA se_q
        LDA #>prev
        STA se_q+1
        JSR streq
        LDB #0
        CMP
        JNZ u_copy                   ; equal to prev -> skip
u_put:  LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        JSR $400F                    ; SYS_PUTS
        LDA #10
        JSR $4009
u_copy: LDA #<cur                    ; prev = cur
        TAP2L
        LDA #>cur
        TAP2H
        LDA #<prev
        TAP1L
        LDA #>prev
        TAP1H
uc_l:   LDA (P2)
        LDB #0
        CMP
        JZ uc_d
        STA (P1)+
        INP2
        JMP uc_l
uc_d:   LDA #0
        STA (P1)
        LDA #0
        STA first
        JMP u_loop
u_end:  RTS
u_nf:   LDA #<m_nf
        TAP1L
        LDA #>m_nf
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS
u_usage:LDA #<m_use
        TAP1L
        LDA #>m_use
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS

; readline: rl_buf (word) = dest. Returns A=1 line read / 0 EOF. Because nextc
; clobbers P1/P2, the write cursor is a memory word (rlp) reloaded per store.
readline:
        LDA rl_buf
        STA rlp
        LDA rl_buf+1
        STA rlp+1
        LDA #0
        STA rln
        JSR nextc
        JC rl_eof0
rl_l:   STA rlc
        LDB #10
        CMP
        JZ rl_done
        LDA rlc
        LDB #13
        CMP
        JZ rl_skip
        LDA rln
        LDB #255
        CMP
        JC rl_skip
        LDA rlp
        TAP1L
        LDA rlp+1
        TAP1H
        LDA rlc
        STA (P1)
        LDA rlp
        LDB #1
        ADD
        STA rlp
        JNC rl_s1
        LDA rlp+1
        INC
        STA rlp+1
rl_s1:  LDA rln
        INC
        STA rln
rl_skip:JSR nextc
        JC rl_done
        JMP rl_l
rl_done:LDA rlp
        TAP1L
        LDA rlp+1
        TAP1H
        LDA #0
        STA (P1)
        LDA #1
        RTS
rl_eof0:LDA #0
        RTS

; streq: A = 1 if strings at se_p and se_q are equal, else 0.
streq:  LDA se_p
        TAP1L
        LDA se_p+1
        TAP1H
        LDA se_q
        TAP2L
        LDA se_q+1
        TAP2H
se_l:   LDA (P1)
        STA se_c
        LDA (P2)
        LDB se_c
        CMP
        JNZ se_ne
        LDA se_c
        LDB #0
        CMP
        JZ se_eq
        INP1
        INP2
        JMP se_l
se_ne:  LDA #0
        RTS
se_eq:  LDA #1
        RTS

m_nf:   .asciiz "uniq: not found"
m_use:  .asciiz "usage: UNIQ [file]   collapse adjacent duplicate lines"

u_arg:  .fill 2
first:  .fill 1
rl_buf: .fill 2
rlp:    .fill 2
rln:    .fill 1
rlc:    .fill 1
se_p:   .fill 2
se_q:   .fill 2
se_c:   .fill 1
cur:    .fill 260
prev:   .fill 260
