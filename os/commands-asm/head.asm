; head.asm — hand-coded HEAD command (asm counterpart of os/commands/head.c).
;   HEAD [-N] [file]   first N lines (default 10), file or stdin.
;
; Shares the input engine via `;#use stdin`, which supplies openarg / nextc:
;   openarg  — opens the file named at oa_a (or selects stdin if none); returns
;              a status in A (2 == "not found", checked here via CMP with B=2).
;   nextc    — fetch next input byte into A; sets C=1 at end-of-input.
; `;#use abi` supplies the syscall equates (SYS_PUTC, SYS_PUTS, ...).
; Entry: P2 = argument tail (the text after the command name). This code is a
; /BIN command loaded at the TPA origin below; it returns via RTS to the shell.
;
; Registers/ABI notes: A,B are 8-bit; P1/P2 are pointer regs. Syscalls and
; nextc clobber P1/P2, so this code keeps its live pointer in the h_arg word in
; memory and reloads P2 from it after each call. n / lines are 16-bit LE
; counters held in the data section at the bottom of the file.
;#use stdin
;#use abi

        .org $6A00                   ; TPA load address for /BIN commands
        ; --- entry: default line count, then snapshot the arg pointer ---
        LDA #10                      ; n = 10 (default line count)
        STA n
        LDA #0
        STA n+1
        TPA2L                        ; copy entry P2 (arg tail) into h_arg word
        STA h_arg
        TPA2H
        STA h_arg+1
        ; --- skip leading spaces before the first token ---
h_sk:   LDA h_arg                    ; reload P2 <- h_arg (nextc etc. clobber P2)
        TAP2L
        LDA h_arg+1
        TAP2H
        LDA (P2)
        LDB #32                      ; ' '
        CMP
        JNZ h_chk                    ; non-space -> examine the token
        JSR h_ainc
        JMP h_sk
        ; --- is the token an option? ('-' introduces -N or -h/-H) ---
h_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ h_open                   ; not '-' -> treat token as a filename
        INP2                         ; peek char after '-' (P2 unchanged in mem)
        LDA (P2)
        LDB #'h'
        CMP
        JZ h_usage                   ; -h -> print usage and exit
        LDB #'H'
        CMP
        JZ h_usage                   ; -H -> print usage and exit
        ; -N : parse a line count. advance arg past '-', read digits.
        JSR h_ainc                   ; skip '-'
        LDA #0
        STA n
        STA n+1
        LDA h_arg
        TAP2L
        LDA h_arg+1
        TAP2H
        ; CMP sets C=1 when A>=B (unsigned). A digit is '0'(48)..'9'(57):
        ; require c >= 48 AND c < 58 (i.e. NOT c >= 58).
h_dl:   LDA (P2)                     ; while digit: n = n*10 + d
        LDB #48                      ; '0'
        CMP
        JC h_d0                      ; c >= '0' -> maybe a digit
        JMP h_dd                     ; c < '0' -> non-digit, stop parsing
h_d0:   LDA (P2)
        LDB #58                      ; ':' = '9'+1
        CMP
        JC h_dd                      ; c >= ':' -> above '9', not a digit
        ; digit confirmed: n = n*10 + (c-48), carrying the low->high add
        JSR mul10n
        LDA (P2)
        LDB #48
        SUB                          ; A = c - '0'
        LDB n
        ADD                          ; A = low(n) + digit
        STA n
        JNC h_d1                     ; propagate carry into high byte
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
        LDB #32                      ; ' '
        CMP
        JNZ h_open                   ; first non-space -> filename (or EOL)
        JSR h_ainc
        LDA h_arg
        TAP2L
        LDA h_arg+1
        TAP2H
        JMP h_ds
        ; --- open the source: pass h_arg (points at filename or EOL) to openarg ---
h_open: LDA h_arg
        STA oa_a                     ; oa_a = openarg's filename argument
        LDA h_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ h_nf                      ; status 2 -> file not found
        ; --- copy loop: emit chars until we have printed n lines ---
        LDA #0                       ; lines = 0
        STA lines
        STA lines+1
h_loop: JSR less                     ; A = (lines < n) ? 1 : 0
        LDB #0
        CMP
        JZ h_done                    ; lines >= n -> done
        JSR nextc                    ; A = next byte, C=1 at end of input
        JC h_done
        STA hch                      ; stash (SYS_PUTC clobbers A)
        JSR SYS_PUTC                 ; putchar
        LDA hch
        LDB #10                      ; '\n' — count a completed line
        CMP
        JNZ h_loop
        LDA lines                    ; lines++ (16-bit, carry low->high)
        LDB #1
        ADD
        STA lines
        JNC h_loop
        LDA lines+1
        INC
        STA lines+1
        JMP h_loop
h_done: RTS
        ; --- error/usage exits: print message + newline, then return ---
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

; h_ainc: advance the 16-bit arg pointer (h_arg += 1). Clobbers A,B.
h_ainc: LDA h_arg                    ; h_arg++
        LDB #1
        ADD
        STA h_arg
        JNC hai1                     ; no low-byte carry -> done
        LDA h_arg+1
        INC
        STA h_arg+1
hai1:   RTS

; mul10n: n = n * 10  (16-bit, via repeated addition — obviously correct).
;   No multiply instruction exists; add the saved value mt (=old n) to n ten
;   times. Clobbers A,B and scratch mt/mcnt/mcar.
mul10n: LDA n                        ; mt = n (the addend); then zero n
        STA mt
        LDA n+1
        STA mt+1
        LDA #0
        STA n
        STA n+1
        LDA #10                      ; mcnt = 10 (loop count)
        STA mcnt
m10l:   LDA mcnt
        LDB #0
        CMP
        JZ m10d                      ; mcnt == 0 -> done
        LDA n                        ; low: n_lo += mt_lo, capture carry
        LDB mt
        ADD
        STA n
        LDA #0
        JNC m10n                     ; no carry -> mcar = 0
        LDA #1                        ; carry out of low byte -> mcar = 1
m10n:   STA mcar
        LDA n+1                      ; high: n_hi += mt_hi + carry
        LDB mt+1
        ADD
        LDB mcar
        ADD
        STA n+1
        LDA mcnt                     ; mcnt--
        DEC
        STA mcnt
        JMP m10l
m10d:   RTS

; less: A = 1 if lines < n (unsigned 16-bit) else 0. Clobbers A,B.
;   Compare high bytes first; only when they are equal does the low byte decide.
less:   LDA lines+1
        LDB n+1
        CMP
        JC less_hge                  ; lines_hi >= n_hi -> need closer look
        LDA #1                        ; lines_hi < n_hi -> definitely less
        RTS
less_hge:                            ; reached only by the JC above; branches do
                                     ; not touch flags, so Z still holds the
                                     ; lines_hi == n_hi result from that CMP
        JNZ less_no                  ; lines_hi > n_hi -> not less
        LDA lines                    ; high bytes equal: compare low bytes
        LDB n
        CMP
        JC less_no                   ; lines_lo >= n_lo -> not less
        LDA #1                        ; lines_lo < n_lo -> less
        RTS
less_no:LDA #0
        RTS

; --- message strings ---
u_nf:   .asciiz "head: not found"
u_use:  .asciiz "usage: HEAD [-N] [file]   first N lines (default 10), file or stdin"

; --- data section (16-bit values are little-endian: low byte, then +1 high) ---
h_arg:  .fill 2                      ; live arg-tail pointer (reloaded into P2)
n:      .fill 2                      ; requested line count
lines:  .fill 2                      ; lines emitted so far
hch:    .fill 1                      ; saved char across SYS_PUTC
mt:     .fill 2                      ; mul10n: saved multiplicand
mcnt:   .fill 1                      ; mul10n: remaining add iterations
mcar:   .fill 1                      ; mul10n: carry low->high
