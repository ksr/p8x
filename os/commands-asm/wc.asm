; wc.asm — hand-coded WC command (asm counterpart of os/commands/wc.c).
;   WC [file|glob]   count lines, words, bytes (file/glob or stdin).
; Shares the file/glob/stdin input engine via `;#use stdin` (lib_stdin.inc).
; Counts are 24-bit (a file may be up to 16 MB): each counter is 3 bytes, bumped
; by a 24-bit increment, and printed by put24 — a byte-wise divmod10 (the CPU has
; no divide), matching wc.c's dm10/put24. Entry: P2 = arg tail.
;#use stdin
;#use abi

; Entry: P2 points at the raw argument tail. Stash it in w_arg (a 16-bit
; pointer we can advance byte-by-byte, since P2 gets clobbered by nextc/syscalls).
        .org $6A00
        TPA2L
        STA w_arg
        TPA2H
        STA w_arg+1
; w_sk: skip leading spaces in the arg tail. Reload P2 from w_arg each pass
; because the byte fetch below is via (P2), then advance the 16-bit w_arg.
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
; w_chk: first non-space char. If it is '-', peek the next char for a -h/-H
; help flag; anything else (including a bare '-') falls through to open.
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
        JSR openarg                   ; open file/glob (or stdin if empty)
        LDB #2                        ; openarg returns 2 = not found
        CMP
        JZ w_nf
; init 24-bit counters
        LDA #0
        STA lines
        STA lines+1
        STA lines+2
        STA words
        STA words+1
        STA words+2
        STA bytes
        STA bytes+1
        STA bytes+2
        STA inword
; w_loop: main scan. nextc returns next byte in A, or C=1 at EOF (across all
; files of a glob). Carry-out on the low-byte ADDs ripples into the higher
; counter bytes; INC sets Z, so JNZ skips the next byte when there was no carry.
w_loop: JSR nextc
        JC w_done
        STA wch
        LDA bytes                     ; bytes++ (24-bit)
        LDB #1
        ADD
        STA bytes
        JNC w_b1
        LDA bytes+1
        INC
        STA bytes+1
        JNZ w_b1
        LDA bytes+2
        INC
        STA bytes+2
w_b1:   LDA wch                       ; if c==10 lines++ (24-bit)
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
        JNZ w_wsq
        LDA lines+2
        INC
        STA lines+2
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
        ; non-ws char: count a word only on the ws->word transition
        ; (inword==0). w_ws below resets inword=0 on any whitespace.
        LDA inword                    ; non-ws: enter a word?
        LDB #0
        CMP
        JNZ w_loop
        LDA words                     ; words++ (24-bit)
        LDB #1
        ADD
        STA words
        JNC w_wi
        LDA words+1
        INC
        STA words+1
        JNZ w_wi
        LDA words+2
        INC
        STA words+2
w_wi:   LDA #1
        STA inword
        JMP w_loop
w_ws:   LDA #0
        STA inword
        JMP w_loop
w_done: LDA lines                     ; print lines words bytes
        STA pn
        LDA lines+1
        STA pn+1
        LDA lines+2
        STA pn+2
        JSR put24
        LDA #32
        JSR SYS_PUTC
        LDA words
        STA pn
        LDA words+1
        STA pn+1
        LDA words+2
        STA pn+2
        JSR put24
        LDA #32
        JSR SYS_PUTC
        LDA bytes
        STA pn
        LDA bytes+1
        STA pn+1
        LDA bytes+2
        STA pn+2
        JSR put24
        LDA #10
        JSR SYS_PUTC
        RTS
w_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
w_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; put24: print pn (3-byte LE) as an unsigned decimal (no padding).
;   Copies pn -> num24, then repeatedly extracts the low decimal digit via
;   dm10 (which divides num24 by 10 in place, returning the remainder). Digits
;   come out least-significant first, so they are pushed onto dg[] (count in
;   psnd) and replayed in reverse. The first dm10 runs unconditionally so a
;   zero value still prints "0". Uses P1; clobbers A/B, num24, dg, psnd.
put24:  LDA pn
        STA num24
        LDA pn+1
        STA num24+1
        LDA pn+2
        STA num24+2
        LDA #0
        STA psnd
        JSR dm10                      ; first digit (handles 0)
        LDB #48
        ADD
        JSR pu_push
; keep extracting digits while num24 is still non-zero
pu_wl:  JSR nz24
        LDB #0
        CMP
        JZ pu_rev
        JSR dm10
        LDB #48
        ADD
        JSR pu_push
        JMP pu_wl
pu_rev: LDA psnd                      ; while nd != 0 -> nd--, print dg[nd]
        LDB #0
        CMP
        JZ pu_dn
        LDA psnd
        LDB #1
        SUB
        STA psnd
        LDA #<dg
        LDB psnd
        ADD
        TAP1L
        LDA #>dg
        JNC pu_rp
        INC
pu_rp:  TAP1H
        LDA (P1)
        JSR SYS_PUTC
        JMP pu_rev
pu_dn:  RTS

; pu_push: dg[psnd] = A ; psnd++
pu_push:STA pstmp
        LDA #<dg
        LDB psnd
        ADD
        TAP1L
        LDA #>dg
        JNC pp_1
        INC
pp_1:   TAP1H
        LDA pstmp
        STA (P1)
        LDA psnd
        INC
        STA psnd
        RTS

; dm10: num24[0..2] /= 10 (24-bit LE); remainder -> A (divmod10 per byte).
;   Walks bytes MSB-first (dmi 2->0). For each byte, dv = {byte, carry-in
;   remainder}, so divmod10 folds the running remainder into the high half;
;   quotient stored back in place, remainder carried down. Final remainder in A.
;   Uses P1; clobbers dmrem, dmi, dv/dvq/dvr.
dm10:   LDA #0
        STA dmrem
        LDA #2
        STA dmi
dm_lp:  LDA #<num24
        LDB dmi
        ADD
        TAP1L
        LDA #>num24
        JNC dm_p1
        INC
dm_p1:  TAP1H
        LDA (P1)
        STA dv
        LDA dmrem
        STA dv+1
        JSR divmod10
        LDA dvq
        STA (P1)
        LDA dvr
        STA dmrem
        LDA dmi
        LDB #0
        CMP
        JZ dm_dn
        LDA dmi
        LDB #1
        SUB
        STA dmi
        JMP dm_lp
dm_dn:  LDA dmrem
        RTS

; nz24: A = 1 if num24 != 0 else 0
nz24:   LDA num24
        LDB #0
        CMP
        JNZ nz_y
        LDA num24+1
        LDB #0
        CMP
        JNZ nz_y
        LDA num24+2
        LDB #0
        CMP
        JNZ nz_y
        LDA #0
        RTS
nz_y:   LDA #1
        RTS

; divmod10: dv (word) -> dvq=dv/10, dvr=dv%10  (P1 preserved)
divmod10:
        LDA #0
        STA dvq
        STA dvq+1
dv_l:   LDA dv+1
        LDB #0
        CMP
        JNZ dv_sub
        LDA dv
        LDB #10
        CMP
        JC dv_sub
        LDA dv
        STA dvr
        RTS
dv_sub: LDA dv
        LDB #10
        SUB
        STA dv
        JC dv_nc
        LDA dv+1
        DEC
        STA dv+1
dv_nc:  LDA dvq
        LDB #1
        ADD
        STA dvq
        JNC dv_l
        LDA dvq+1
        INC
        STA dvq+1
        JMP dv_l

u_nf:   .asciiz "wc: not found"
u_use:  .asciiz "usage: WC [file|glob]   count lines words bytes (file/glob or stdin)"

w_arg:  .fill 2
wch:    .fill 1
lines:  .fill 3
words:  .fill 3
bytes:  .fill 3
inword: .fill 1
pn:     .fill 3
num24:  .fill 3
dg:     .fill 10
dmrem:  .fill 1
dmi:    .fill 1
psnd:   .fill 1
pstmp:  .fill 1
dv:     .fill 2
dvq:    .fill 2
dvr:    .fill 1
