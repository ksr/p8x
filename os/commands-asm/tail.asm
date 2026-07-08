; tail.asm — hand-coded TAIL command (asm counterpart of os/commands/tail.c).
;   TAIL [-N] [file]   last N lines (default 10, clamped 1..40), file or stdin.
; Shares the input engine via `;#use stdin`. Keeps the last N lines in a ring of
; 40 x 256-byte slots, then prints them in order at EOF. Entry: P2 = arg tail.
;#use stdin

        .org $7A00
        LDA #10
        STA n
        LDA #0
        STA n+1
        TPA2L
        STA t_arg
        TPA2H
        STA t_arg+1
t_sk:   LDA t_arg
        TAP2L
        LDA t_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ t_chk
        JSR t_ainc
        JMP t_sk
t_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ t_clamp
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ t_usage
        LDB #'H'
        CMP
        JZ t_usage
        JSR t_ainc                   ; skip '-'
        LDA #0
        STA n
        STA n+1
        LDA t_arg
        TAP2L
        LDA t_arg+1
        TAP2H
t_dl:   LDA (P2)
        LDB #48
        CMP
        JNC t_dd                     ; c < '0'
        LDA (P2)
        LDB #58
        CMP
        JC t_dd                      ; c >= ':'
        JSR mul10n
        LDA (P2)
        LDB #48
        SUB
        LDB n
        ADD
        STA n
        JNC t_d1
        LDA n+1
        INC
        STA n+1
t_d1:   JSR t_ainc
        LDA t_arg
        TAP2L
        LDA t_arg+1
        TAP2H
        JMP t_dl
t_dd:   LDA t_arg
        TAP2L
        LDA t_arg+1
        TAP2H
t_dsk:  LDA (P2)
        LDB #32
        CMP
        JNZ t_clamp
        JSR t_ainc
        LDA t_arg
        TAP2L
        LDA t_arg+1
        TAP2H
        JMP t_dsk
; clamp n to 1..40
t_clamp:LDA n+1
        LDB #0
        CMP
        JNZ t_c40
        LDA n
        LDB #0
        CMP
        JZ t_c1
        LDA n
        LDB #41
        CMP
        JC t_c40
        JMP t_open
t_c1:   LDA #1
        STA n
        JMP t_open
t_c40:  LDA #40
        STA n
        LDA #0
        STA n+1
t_open: LDA t_arg
        STA oa_a
        LDA t_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ t_nf
; fill the ring
        LDA #0
        STA col
        STA slot
        STA total
        STA total+1
t_fl:   JSR nextc
        JC t_feof
        STA tch
        LDB #10
        CMP
        JZ t_nl
        LDA tch
        LDB #13
        CMP
        JZ t_fl                      ; drop CR
        LDA col
        LDB #255
        CMP
        JC t_fl                      ; col>=255 -> skip
        LDA slot
        STA tb_slot
        LDA col
        STA tb_col
        JSR tbuf_addr
        LDA tch
        STA (P1)
        LDA col
        INC
        STA col
        JMP t_fl
t_nl:   LDA slot                     ; close line: buf[slot*256+col]=0
        STA tb_slot
        LDA col
        STA tb_col
        JSR tbuf_addr
        LDA #0
        STA (P1)
        LDA slot                     ; slot=(slot+1)%n
        INC
        STA slot
        LDB n
        CMP
        JC t_nlw
        JMP t_nlt
t_nlw:  LDA #0
        STA slot
t_nlt:  LDA total                    ; total++
        LDB #1
        ADD
        STA total
        JNC t_nlc
        LDA total+1
        INC
        STA total+1
t_nlc:  LDA #0
        STA col
        JMP t_fl
t_feof: LDA col                      ; final line with no LF
        LDB #0
        CMP
        JZ t_print
        LDA slot
        STA tb_slot
        LDA col
        STA tb_col
        JSR tbuf_addr
        LDA #0
        STA (P1)
        LDA slot
        INC
        STA slot
        LDB n
        CMP
        JC t_fw
        JMP t_ft
t_fw:   LDA #0
        STA slot
t_ft:   LDA total
        LDB #1
        ADD
        STA total
        JNC t_print
        LDA total+1
        INC
        STA total+1
; count = min(total,n); base = (total>n)?slot:0
t_print:LDA total+1
        LDB #0
        CMP
        JNZ t_gt
        LDA total
        LDB n
        CMP
        JC t_ge                      ; total_lo >= n
        LDA total                    ; total < n
        STA count
        LDA #0
        STA base
        JMP t_pr
t_ge:   LDA total
        LDB n
        CMP
        JZ t_eq                      ; total == n
t_gt:   LDA n                        ; total > n
        STA count
        LDA slot
        STA base
        JMP t_pr
t_eq:   LDA n
        STA count
        LDA #0
        STA base
t_pr:   LDA count
        LDB #0
        CMP
        JZ t_end
        LDA base
        STA tb_slot
        LDA #0
        STA tb_col
        JSR tbuf_addr
t_pl:   LDA (P1)
        LDB #0
        CMP
        JZ t_peol
        JSR $4009
        INP1
        JMP t_pl
t_peol: LDA #10
        JSR $4009
        LDA base
        INC
        STA base
        LDB n
        CMP
        JC t_pwrap
        JMP t_pdec
t_pwrap:LDA #0
        STA base
t_pdec: LDA count
        DEC
        STA count
        JMP t_pr
t_end:  RTS
t_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS
t_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS

t_ainc: LDA t_arg
        LDB #1
        ADD
        STA t_arg
        JNC tai1
        LDA t_arg+1
        INC
        STA t_arg+1
tai1:   RTS

; tbuf_addr: P1 = buf + tb_slot*256 + tb_col
tbuf_addr:
        LDA #<buf
        LDB tb_col
        ADD
        STA taddr
        LDA #0
        JNC tba1
        LDA #1
tba1:   STA tbcar
        LDA #>buf
        LDB tb_slot
        ADD
        LDB tbcar
        ADD
        STA taddr+1
        LDA taddr
        TAP1L
        LDA taddr+1
        TAP1H
        RTS

; mul10n: n = n*10 (16-bit repeated add)
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

u_nf:   .asciiz "tail: not found"
u_use:  .asciiz "usage: TAIL [-N] [file]   last N lines (default 10), file or stdin"

t_arg:  .fill 2
n:      .fill 2
col:    .fill 1
slot:   .fill 1
total:  .fill 2
count:  .fill 1
base:   .fill 1
tch:    .fill 1
tb_slot:.fill 1
tb_col: .fill 1
taddr:  .fill 2
tbcar:  .fill 1
mt:     .fill 2
mcnt:   .fill 1
mcar:   .fill 1
buf:    .fill 10240
