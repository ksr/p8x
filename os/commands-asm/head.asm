; head.asm — hand-coded HEAD command (asm counterpart of os/commands/head.c).
;   HEAD [-N] [file]   first N lines (default 10), file or stdin.
; Shares the input engine via `;#use stdin`. Entry: P2 = arg tail.
;#use stdin
;#use abi

        .org $6A00
        LDA #10                      ; n = 10
        STA n
        LDA #0
        STA n+1
        TPA2L
        STA h_arg
        TPA2H
        STA h_arg+1
h_sk:   LDA h_arg
        TAP2L
        LDA h_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ h_chk
        JSR h_ainc
        JMP h_sk
h_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ h_open
        INP2                         ; peek option
        LDA (P2)
        LDB #'h'
        CMP
        JZ h_usage
        LDB #'H'
        CMP
        JZ h_usage
        ; -N : parse a line count. advance arg past '-', read digits.
        JSR h_ainc                   ; skip '-'
        LDA #0
        STA n
        STA n+1
        LDA h_arg
        TAP2L
        LDA h_arg+1
        TAP2H
h_dl:   LDA (P2)                     ; while digit: n = n*10 + d
        LDB #48
        CMP
        JC h_d0                      ; c >= '0'
        JMP h_dd
h_d0:   LDA (P2)
        LDB #58
        CMP
        JC h_dd                      ; c >= ':' -> not a digit
        ; n = n*10 + (c-48)
        JSR mul10n
        LDA (P2)
        LDB #48
        SUB
        LDB n
        ADD
        STA n
        JNC h_d1
        LDA n+1
        INC
        STA n+1
h_d1:   JSR h_ainc
        LDA h_arg
        TAP2L
        LDA h_arg+1
        TAP2H
        JMP h_dl
h_dd:   LDA h_arg                    ; skip spaces after the count
        TAP2L
        LDA h_arg+1
        TAP2H
h_ds:   LDA (P2)
        LDB #32
        CMP
        JNZ h_open
        JSR h_ainc
        LDA h_arg
        TAP2L
        LDA h_arg+1
        TAP2H
        JMP h_ds
h_open: LDA h_arg
        STA oa_a
        LDA h_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ h_nf
        LDA #0                       ; lines = 0
        STA lines
        STA lines+1
h_loop: JSR less                     ; lines < n ?
        LDB #0
        CMP
        JZ h_done                    ; not less -> stop
        JSR nextc
        JC h_done
        STA hch
        JSR SYS_PUTC                 ; putchar
        LDA hch
        LDB #10
        CMP
        JNZ h_loop
        LDA lines                    ; lines++
        LDB #1
        ADD
        STA lines
        JNC h_loop
        LDA lines+1
        INC
        STA lines+1
        JMP h_loop
h_done: RTS
h_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
h_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

h_ainc: LDA h_arg                    ; h_arg++
        LDB #1
        ADD
        STA h_arg
        JNC hai1
        LDA h_arg+1
        INC
        STA h_arg+1
hai1:   RTS

; mul10n: n = n * 10  (16-bit, via repeated addition — obviously correct)
mul10n: LDA n
        STA mt
        LDA n+1
        STA mt+1
        LDA #0
        STA n
        STA n+1
        LDA #10
        STA mcnt
m10l:   LDA mcnt
        LDB #0
        CMP
        JZ m10d
        LDA n
        LDB mt
        ADD
        STA n
        LDA #0
        JNC m10n
        LDA #1
m10n:   STA mcar
        LDA n+1
        LDB mt+1
        ADD
        LDB mcar
        ADD
        STA n+1
        LDA mcnt
        DEC
        STA mcnt
        JMP m10l
m10d:   RTS

; less: A = 1 if lines < n (unsigned 16-bit) else 0
less:   LDA lines+1
        LDB n+1
        CMP
        JC less_hge                  ; lines_hi >= n_hi
        LDA #1
        RTS
less_hge:
        LDA lines+1
        LDB n+1
        CMP
        JNZ less_no                  ; lines_hi > n_hi
        LDA lines
        LDB n
        CMP
        JC less_no                   ; lines_lo >= n_lo
        LDA #1
        RTS
less_no:LDA #0
        RTS

u_nf:   .asciiz "head: not found"
u_use:  .asciiz "usage: HEAD [-N] [file]   first N lines (default 10), file or stdin"

h_arg:  .fill 2
n:      .fill 2
lines:  .fill 2
hch:    .fill 1
mt:     .fill 2
mcnt:   .fill 1
mcar:   .fill 1
