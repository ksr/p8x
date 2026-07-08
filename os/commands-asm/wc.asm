; wc.asm — hand-coded WC command (asm counterpart of os/commands/wc.c).
;   WC [file|glob]   count lines, words, bytes (file/glob or stdin).
; Shares the file/glob/stdin input engine via `;#use stdin` (lib_stdin.inc).
; Counts are 16-bit (wrap past 65535), matching wc.c. putnum/divmod10 are inline
; (the CPU has no divide). Entry: P2 = arg tail.
;#use stdin

        .org $7A00
        TPA2L
        STA w_arg
        TPA2H
        STA w_arg+1
w_sk:   LDA w_arg
        TAP2L
        LDA w_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ w_chk
        LDA w_arg
        LDB #1
        ADD
        STA w_arg
        JNC w_sk
        LDA w_arg+1
        INC
        STA w_arg+1
        JMP w_sk
w_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ w_open
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ w_usage
        LDB #'H'
        CMP
        JZ w_usage
w_open: LDA w_arg                     ; openarg(arg)
        STA oa_a
        LDA w_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ w_nf
; init counters
        LDA #0
        STA lines
        STA lines+1
        STA words
        STA words+1
        STA bytes
        STA bytes+1
        STA inword
w_loop: JSR nextc
        JC w_done
        STA wch
        LDA bytes                     ; bytes++
        LDB #1
        ADD
        STA bytes
        JNC w_b1
        LDA bytes+1
        INC
        STA bytes+1
w_b1:   LDA wch                       ; if c==10 lines++
        LDB #10
        CMP
        JNZ w_wsq
        LDA lines
        LDB #1
        ADD
        STA lines
        JNC w_wsq
        LDA lines+1
        INC
        STA lines+1
w_wsq:  LDA wch                       ; whitespace?
        LDB #32
        CMP
        JZ w_ws
        LDA wch
        LDB #9
        CMP
        JZ w_ws
        LDA wch
        LDB #10
        CMP
        JZ w_ws
        LDA wch
        LDB #13
        CMP
        JZ w_ws
        LDA inword                    ; non-ws: enter a word?
        LDB #0
        CMP
        JNZ w_loop
        LDA words
        LDB #1
        ADD
        STA words
        JNC w_wi
        LDA words+1
        INC
        STA words+1
w_wi:   LDA #1
        STA inword
        JMP w_loop
w_ws:   LDA #0
        STA inword
        JMP w_loop
w_done: LDA lines
        STA pn
        LDA lines+1
        STA pn+1
        JSR putnum
        LDA #32
        JSR $4009
        LDA words
        STA pn
        LDA words+1
        STA pn+1
        JSR putnum
        LDA #32
        JSR $4009
        LDA bytes
        STA pn
        LDA bytes+1
        STA pn+1
        JSR putnum
        LDA #10
        JSR $4009
        RTS
w_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS
w_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS

; putnum: print pn (word) as unsigned decimal
putnum: LDA #0
        STA pncnt
        LDA pn
        LDB #0
        CMP
        JNZ pn_loop
        LDA pn+1
        LDB #0
        CMP
        JNZ pn_loop
        LDA #'0'
        JSR $4009
        RTS
pn_loop:LDA pn
        LDB #0
        CMP
        JNZ pn_go
        LDA pn+1
        LDB #0
        CMP
        JZ pn_print
pn_go:  LDA pn
        STA dv
        LDA pn+1
        STA dv+1
        JSR divmod10
        LDA dvr
        LDB #48
        ADD
        PHA
        LDA pncnt
        INC
        STA pncnt
        LDA dvq
        STA pn
        LDA dvq+1
        STA pn+1
        JMP pn_loop
pn_print:
        LDA pncnt
        LDB #0
        CMP
        JZ pn_done
        PLA
        JSR $4009
        LDA pncnt
        DEC
        STA pncnt
        JMP pn_print
pn_done:RTS

; divmod10: dv (word) -> dvq=dv/10, dvr=dv%10
divmod10:
        LDA #0
        STA dvq
        STA dvq+1
dm_l:   LDA dv+1
        LDB #0
        CMP
        JNZ dm_sub
        LDA dv
        LDB #10
        CMP
        JC dm_sub
        LDA dv
        STA dvr
        RTS
dm_sub: LDA dv
        LDB #10
        SUB
        STA dv
        JC dm_nc
        LDA dv+1
        DEC
        STA dv+1
dm_nc:  LDA dvq
        LDB #1
        ADD
        STA dvq
        JNC dm_l
        LDA dvq+1
        INC
        STA dvq+1
        JMP dm_l

u_nf:   .asciiz "wc: not found"
u_use:  .asciiz "usage: WC [file|glob]   count lines words bytes (file/glob or stdin)"

w_arg:  .fill 2
wch:    .fill 1
lines:  .fill 2
words:  .fill 2
bytes:  .fill 2
inword: .fill 1
pn:     .fill 2
pncnt:  .fill 1
dv:     .fill 2
dvq:    .fill 2
dvr:    .fill 1
