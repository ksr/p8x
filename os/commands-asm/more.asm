; more.asm — hand-coded MORE command (asm counterpart of os/commands/more.c).
;   MORE [file]   page a file or stdin (space=next, Enter=line, q=quit).
; Shares the input engine via `;#use stdin`. The paging key is read from the
; console via BIOS CONIN ($0100), separate from the (redirectable) stdin stream.
; Entry: P2 = arg tail.
;#use stdin
;#use abi

        .org $6A00                   ; loads into TPA (transient program area)
; Save the incoming arg-tail pointer (P2) into the 16-bit var m_arg so it can
; be advanced and re-loaded across the leading-space skip loop below.
        TPA2L
        STA m_arg
        TPA2H
        STA m_arg+1
; m_sk: skip leading spaces in the arg tail. Reload P2 from m_arg each pass
; (INP2 isn't used here because m_arg is bumped as a 16-bit value with carry).
m_sk:   LDA m_arg
        TAP2L
        LDA m_arg+1
        TAP2H
        LDA (P2)
        LDB #32                      ; 32 = ASCII space
        CMP
        JNZ m_chk                    ; first non-space -> done skipping
        LDA m_arg                    ; m_arg++ (16-bit, propagate carry to hi)
        LDB #1
        ADD
        STA m_arg
        JNC m_sk
        LDA m_arg+1
        INC
        STA m_arg+1
        JMP m_sk
; m_chk: detect the "-h"/"-H" help flag; anything else is treated as a filename.
m_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ m_open
        INP2                         ; look at the char after '-'
        LDA (P2)
        LDB #'h'
        CMP
        JZ m_usage
        LDB #'H'
        CMP
        JZ m_usage
; m_open: open the file named at m_arg (or fall through to stdin). openarg reads
; oa_a as the name pointer; returns status in A (2 = not found, via CMP #2).
m_open: LDA m_arg
        STA oa_a
        LDA m_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ m_nf                      ; status 2 -> file not found
        LDA #0                       ; lines printed on this screen = 0
        STA lines
        STA lines+1
; m_loop: copy input to output one char at a time; count newlines; page at 23.
; nextc (from stdin engine) returns C=1 at EOF, else next byte in A.
m_loop: JSR nextc
        JC m_done
        STA mch
        JSR SYS_PUTC                 ; putchar
        LDA mch
        LDB #10                      ; 10 = LF; only newlines advance the count
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
; m_page: screen full. prompt returns the pressed key in A (and mkey).
; 'q'/'Q' quit; Enter (13) advances one line; space/anything else a full page.
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
        LDA #22                      ; Enter -> preset count to 22 so 1 more line
        STA lines                    ;   (23rd) triggers the next prompt
        LDA #0
        STA lines+1
        JMP m_loop
m_full: LDA #0                       ; space/other -> reset count, show full page
        STA lines
        STA lines+1
        JMP m_loop
m_done: RTS
; m_nf / m_usage: print a message via SYS_PUTS (P1 = string ptr), add a newline,
; and return. SYS_PUTS/SYS_PUTC clobber P1/P2 per the syscall ABI.
m_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
m_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; prompt: print "--More--", read a CONIN key -> mkey (and A), erase the prompt.
prompt: LDA #<s_more
        TAP1L
        LDA #>s_more
        TAP1H
        LDA #0
        JSR SYS_PUTS                 ; SYS_PUTS "--More--"
        LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR CONIN                    ; CONIN -> A
        STA mkey
        LDA #<s_erase
        TAP1L
        LDA #>s_erase
        TAP1H
        LDA #0
        JSR SYS_PUTS                 ; erase: "\r        \r"
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
