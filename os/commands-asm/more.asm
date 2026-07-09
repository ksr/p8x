; more.asm — hand-coded MORE command (asm counterpart of os/commands/more.c).
;   MORE [file]   page a file or stdin (space=next, Enter=line, q=quit).
; Shares the input engine via `;#use stdin`. The paging key is read from the
; console via BIOS CONIN ($0100), separate from the (redirectable) stdin stream.
; Entry: P2 = arg tail.
;#use stdin

        .org $7A00
        TPA2L
        STA m_arg
        TPA2H
        STA m_arg+1
m_sk:   LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ m_chk
        LDA m_arg
        LDB #1
        ADD
        STA m_arg
        JNC m_sk
        LDA m_arg+1
        INC
        STA m_arg+1
        JMP m_sk
m_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ m_open
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ m_usage
        LDB #'H'
        CMP
        JZ m_usage
m_open: LDA m_arg
        STA oa_a
        LDA m_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ m_nf
        LDA #0
        STA lines
        STA lines+1
m_loop: JSR nextc
        JC m_done
        STA mch
        JSR $4009                    ; putchar
        LDA mch
        LDB #10
        CMP
        JNZ m_loop
        LDA lines                    ; lines++
        LDB #1
        ADD
        STA lines
        JNC m_lc
        LDA lines+1
        INC
        STA lines+1
m_lc:   LDA lines+1                  ; if lines >= 23 (16-bit; hi!=0 or lo>=23)
        LDB #0
        CMP
        JNZ m_page
        LDA lines
        LDB #23
        CMP
        JNC m_loop                   ; lines < 23
m_page: JSR prompt
        LDB #'q'
        CMP
        JZ m_done
        LDA mkey
        LDB #'Q'
        CMP
        JZ m_done
        LDA mkey
        LDB #13
        CMP
        JNZ m_full
        LDA #22                      ; Enter -> one more line
        STA lines
        LDA #0
        STA lines+1
        JMP m_loop
m_full: LDA #0                       ; space/other -> full page
        STA lines
        STA lines+1
        JMP m_loop
m_done: RTS
m_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS
m_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS

; prompt: print "--More--", read a CONIN key -> mkey (and A), erase the prompt.
prompt: LDA #<s_more
        TAP1L
        LDA #>s_more
        TAP1H
        LDA #0
        JSR $400F                    ; SYS_PUTS "--More--"
        LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $0100                    ; CONIN -> A
        STA mkey
        LDA #<s_erase
        TAP1L
        LDA #>s_erase
        TAP1H
        LDA #0
        JSR $400F                    ; erase: "\r        \r"
        LDA mkey
        RTS

s_more: .asciiz "--More--"
s_erase:.byte 13
        .ascii "        "
        .byte 13,0
u_nf:   .asciiz "more: not found"
u_use:  .asciiz "usage: MORE [file]   page a file or stdin (space=next, Enter=line, q=quit)"

m_arg:  .fill 2
lines:  .fill 2
mch:    .fill 1
mkey:   .fill 1
