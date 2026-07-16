; uniq.asm — hand-coded UNIQ command (asm counterpart of os/commands/uniq.c).
;   UNIQ [file]   collapse adjacent duplicate lines (file or stdin).
; Shares the input engine via `;#use stdin`. readline() + streq() are inline.
; Entry: P2 = arg tail.
;#use stdin
;#use abi

; Main entry (TPA load address $6A00). On entry P2 points at the raw argument
; tail. Stash it as a 16-bit pointer word (u_arg) so we can walk it with plain
; 8-bit adds even though (P2) dereferences clobber-prone pointer registers.
        .org $6A00
        TPA2L
        STA u_arg
        TPA2H
        STA u_arg+1
; u_sk: skip leading spaces (ASCII 32) in the arg tail, advancing u_arg. The
; ADD/JNC/INC dance is a 16-bit pointer increment: bump the low byte, and only
; ripple into the high byte when the low-byte add carried (JNC skips the INC).
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
; u_chk: first non-space char, still in A from u_sk's compare (CMP preserves A).
; If it is '-', peek the next char for the -h/-H help flag and jump to the usage
; message; otherwise fall through to open.
u_chk:  LDB #'-'
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
; u_open: hand u_arg to the shared stdin engine's openarg (via ;#use stdin).
; openarg returns A=2 when the named file was not found -> u_nf error path.
; With no filename it selects stdin. Then first=1 marks the initial line.
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
; u_loop: read next line into cur[]. readline returns A=0 at EOF -> done.
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
        JNZ u_put                    ; first line -> always print (no prev yet)
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
        JNZ u_copy                   ; equal to prev -> skip print, just refresh prev
; u_put: emit cur[] followed by a newline (LF=10). SYS_PUTS' A=0 arg selects
; stdout. Falls through into u_copy to update prev.
u_put:  LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
; u_copy: prev = cur (byte copy P2=cur -> P1=prev until NUL), clear first, loop.
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
        STA first                    ; A still 0: STA writes memory only
        JMP u_loop
u_end:  RTS                          ; EOF reached, normal exit
; u_nf: "not found" error, u_usage: help text. Both print msg + newline, return.
; u_nf is an ERROR: it goes to the raw console (PUTS/CONOUT), not stdout, which
; may be a redirect or a pipe — `uniq missing >F` would otherwise write the
; message INTO F, and `uniq missing | wc` would count it as data. Matches uniq.c's
; eputs(). u_usage is NOT an error (the user asked with -h), so it stays on stdout
; and `uniq -h >notes` still captures it.
u_nf:   LDA #<m_nf
        TAP1L
        LDA #>m_nf
        TAP1H
        LDA #0
        JSR PUTS
        LDA #10
        JSR CONOUT
        RTS
u_usage:LDA #<m_use
        TAP1L
        LDA #>m_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
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
rl_l:   STA rlc                      ; rlc = current char from nextc
        LDB #10
        CMP
        JZ rl_done                   ; LF ends the line
        LDB #13                      ; A still holds rlc (CMP preserves A)
        CMP
        JZ rl_skip                   ; drop CR (CRLF -> LF), don't store
        LDA rln
        LDB #255
        CMP
        JC rl_skip                   ; buffer full (len>=255): swallow rest of line
        LDA rlp
        TAP1L
        LDA rlp+1
        TAP1H
        LDA rlc
        STA (P1)                     ; store char at rlp
        LDA rlp                      ; 16-bit rlp++ (ripple carry into high byte)
        LDB #1
        ADD
        STA rlp
        JNC rl_s1
        LDA rlp+1
        INC
        STA rlp+1
rl_s1:  LDA rln
        INC
        STA rln                      ; rln++ (bytes stored this line)
rl_skip:JSR nextc                    ; fetch next char; C set = EOF
        JC rl_done
        JMP rl_l
; rl_done: NUL-terminate at rlp and return A=1 (a line, possibly empty, was read)
rl_done:LDA rlp
        TAP1L
        LDA rlp+1
        TAP1H
        LDA #0
        STA (P1)
        LDA #1
        RTS
rl_eof0:LDA #0                        ; EOF hit before any char -> A=0, no line
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
; Compare byte-by-byte until a mismatch or a shared terminating NUL.
se_l:   LDA (P1)
        STA se_c                      ; se_c = *P1 (needed: (P2) load clobbers regs)
        LDA (P2)
        LDB se_c
        CMP
        JNZ se_ne                     ; bytes differ -> not equal
        LDA se_c
        LDB #0
        CMP
        JZ se_eq                      ; both NUL at same spot -> equal
        INP1
        INP2
        JMP se_l
se_ne:  LDA #0
        RTS
se_eq:  LDA #1
        RTS

m_nf:   .asciiz "uniq: not found"
m_use:  .asciiz "usage: UNIQ [file]   collapse adjacent duplicate lines"

; --- variables / buffers ---
u_arg:  .fill 2                       ; 16-bit pointer into the arg tail
first:  .fill 1                       ; 1 until first line printed (no prev yet)
rl_buf: .fill 2
rlp:    .fill 2
rln:    .fill 1
rlc:    .fill 1
se_p:   .fill 2
se_q:   .fill 2
se_c:   .fill 1
cur:    .fill 260                     ; current line (255 max chars + NUL + slack)
prev:   .fill 260                     ; previous line, for adjacent-dup compare
