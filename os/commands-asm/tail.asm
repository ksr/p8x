; tail.asm — hand-coded TAIL command (asm counterpart of os/commands/tail.c).
;   TAIL [-N] [file]   last N lines (default 10, clamped 1..40), file or stdin.
; Shares the input engine via `;#use stdin`. Keeps the last N lines in a ring of
; 40 x 256-byte slots, then prints them in order at EOF. Entry: P2 = arg tail.
;#use stdin
;#use abi

; ---------------------------------------------------------------------------
; Zero-page-ish state lives in the .fill vars at the bottom of the file:
;   t_arg  16-bit walking pointer into the argument string
;   n      16-bit requested line count (parsed, then clamped to 1..40)
;   col    current write column within the active slot (0..254)
;   slot   ring index of the slot currently being filled (0..n-1)
;   total  16-bit count of completed lines seen so far
;   buf    the ring itself: 40 slots x 256 bytes = 10240 bytes
; The ring keeps only the most recent n lines; at EOF we replay them in order.
; ---------------------------------------------------------------------------

        .org $6A00
        LDA #10                          ; default: last 10 lines
        STA n
        LDA #0
        STA n+1
        TPA2L                            ; capture P2 (arg tail) into t_arg
        STA t_arg
        TPA2H
        STA t_arg+1
; Skip leading spaces before any option/filename. LDB #32 = ' '.
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
; If the first non-space char is '-', this is an option. -h / -H print usage;
; -<digits> sets the line count. No dash -> jump straight to clamp (n stays 10).
t_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ t_clamp
        INP2                             ; peek char after '-' (P2 only, t_arg unchanged)
        LDA (P2)
        LDB #'h'
        CMP
        JZ t_usage
        LDB #'H'
        CMP
        JZ t_usage
        JSR t_ainc                   ; skip '-'
        LDA #0
        STA n                            ; restart n at 0 to accumulate digits
        STA n+1
        LDA t_arg
        TAP2L
        LDA t_arg+1
        TAP2H
; Decimal parse loop: for each char in '0'..'9', n = n*10 + digit.
; CMP sets C=1 when A>=B, so C after "CMP #'0'" tells us c>='0', and
; C after "CMP #':'" (58, one past '9') tells us c>='9'+1 i.e. non-digit.
t_dl:   LDA (P2)
        LDB #48
        CMP
        JNC t_dd                     ; c < '0'
        LDA (P2)
        LDB #58
        CMP
        JC t_dd                      ; c >= ':'
        JSR mul10n                       ; n *= 10
        LDA (P2)
        LDB #48
        SUB                              ; A = c - '0' (digit value)
        LDB n
        ADD                              ; add into n low byte
        STA n
        JNC t_d1                         ; carry -> bump n high byte
        LDA n+1
        INC
        STA n+1
t_d1:   JSR t_ainc
        LDA t_arg
        TAP2L
        LDA t_arg+1
        TAP2H
        JMP t_dl
; Digits done. Skip any spaces between the -N option and the filename.
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
; Clamp n to 1..40 (the ring only has 40 slots). n+1 nonzero => n>=256 => clamp
; high to 40. Otherwise: 0 -> 1, and anything >=41 -> 40.
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
; Open the file named at t_arg (or stdin if none). openarg returns a status in
; A; status 2 means "not found" -> error out. (openarg lives in the stdin lib.)
t_open: LDA t_arg
        STA oa_a
        LDA t_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ t_nf
; Fill the ring: read chars, splitting on LF, dropping CR, into the current slot.
; col/slot/total all start at 0.
        LDA #0
        STA col
        STA slot
        STA total
        STA total+1
t_fl:   JSR nextc                     ; next input char; C=1 at EOF
        JC t_feof
        STA tch
        LDB #10
        CMP
        JZ t_nl                      ; LF ends the line
        LDA tch
        LDB #13
        CMP
        JZ t_fl                      ; drop CR
        LDA col
        LDB #255
        CMP
        JC t_fl                      ; col>=255 -> line full, discard extra chars
        LDA slot
        STA tb_slot
        LDA col
        STA tb_col
        JSR tbuf_addr                ; P1 = &buf[slot*256+col]
        LDA tch
        STA (P1)                     ; store the char
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
        LDA slot                     ; slot=(slot+1)%n (ring advance)
        INC
        STA slot
        LDB n
        CMP
        JC t_nlw                     ; slot>=n -> wrap to 0
        JMP t_nlt
t_nlw:  LDA #0
        STA slot
t_nlt:  LDA total                    ; total++ (16-bit)
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
; EOF. If col>0 there is a final unterminated line to commit (same close/advance
; as t_nl); if col==0 the last char was a LF, so nothing pending -> go print.
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
; Decide what to replay. count = min(total,n) lines to print. base = ring index
; of the oldest surviving line: if the ring wrapped (total>n) that is the next
; slot to be overwritten (== slot); otherwise nothing wrapped, oldest is 0.
; total+1 nonzero => total>=256 > n (n<=40), so it is unconditionally the >n case.
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
; Replay loop: print `count` NUL-terminated lines starting at ring slot `base`,
; advancing base with the same (base+1)%n wrap, appending a LF after each.
t_pr:   LDA count
        LDB #0
        CMP
        JZ t_end                     ; count==0 -> done
        LDA base
        STA tb_slot
        LDA #0
        STA tb_col
        JSR tbuf_addr                ; P1 = start of this line's slot
t_pl:   LDA (P1)
        LDB #0
        CMP
        JZ t_peol                    ; NUL terminates the line
        JSR SYS_PUTC
        INP1
        JMP t_pl
t_peol: LDA #10                      ; emit newline after the line
        JSR SYS_PUTC
        LDA base
        INC
        STA base
        LDB n
        CMP
        JC t_pwrap                   ; base>=n -> wrap
        JMP t_pdec
t_pwrap:LDA #0
        STA base
t_pdec: LDA count
        DEC
        STA count
        JMP t_pr
t_end:  RTS
; Error/usage exits: print the message string, then a newline, then return.
t_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
t_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; t_ainc: advance the 16-bit t_arg pointer by one byte. Clobbers A/B.
; Note it does NOT reload P2; callers that need P2 in sync re-TAP2 from t_arg.
t_ainc: LDA t_arg
        LDB #1
        ADD
        STA t_arg
        JNC tai1                         ; carry -> bump high byte
        LDA t_arg+1
        INC
        STA t_arg+1
tai1:   RTS

; tbuf_addr: P1 = buf + tb_slot*256 + tb_col.
; Because slots are exactly 256 bytes, slot*256 is just "add slot to the high
; byte". tb_col adds into the low byte, and any carry out of the low byte is
; folded (tbcar) into the high byte too. Inputs: tb_slot, tb_col. Clobbers A/B,
; taddr, tbcar, P1.
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

; mul10n: n = n*10, done as 10 repeated 16-bit adds of the original n (saved in
; mt) since the ISA has no multiply. Inputs/output: n (16-bit). Clobbers A/B,
; mt, mcnt, mcar.
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

; --- state (see header block) ---
t_arg:  .fill 2                          ; walking pointer into arg string
n:      .fill 2                          ; requested line count, clamped 1..40
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
buf:    .fill 10240                      ; 40 slots x 256 bytes = the line ring
