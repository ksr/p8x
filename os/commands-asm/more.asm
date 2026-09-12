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
m_sk:   LPW2 m_arg                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #32                      ; 32 = ASCII space
        CMP
        JNZ m_chk                    ; first non-space -> done skipping
        INCW m_arg                ; <- tierA: 16-bit INCW chain before JMP m_sk (next: JMP m_sk -> LDA)
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
m_open: MOVW oa_a,m_arg                ; <- tierA: word move (next: JSR openarg)
        JSR openarg
        LDB #2
        CMP
        JZ m_nf                      ; status 2 -> file not found
        LDW lines,#0                ; <- tierA: zero word (next: JSR nextc)
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
        INCW lines                ; <- tierA: 16-bit INCW chain, skip label m_lc dropped (next: LDA)
        LDA lines+1                  ; if lines >= 23 (16-bit; hi!=0 or lo>=23)
        LDB #0
        CMP
        JNZ m_page
        LDA lines
        LDB #23
        CMP
        JNC m_loop                   ; lines < 23
; m_page: screen full. prompt returns the pressed key in A (and mkey).
; 'q'/'Q' quit; Enter (13) advances one line; space/anything else a full page.
m_page: JSR prompt                   ; A = key on return; CMP leaves A intact, so
        LDB #'q'                     ;   the three tests below share the one load
        CMP
        JZ m_done
        LDB #'Q'
        CMP
        JZ m_done
        LDB #13
        CMP
        JNZ m_full
        LDW lines,#22                ; <- tierA: word constant (next: JMP m_loop -> JSR nextc)
        JMP m_loop
m_full: LDW lines,#0                ; <- tierA: zero word (next: JMP m_loop -> JSR nextc)
        JMP m_loop
m_done: RTS
; m_nf / m_usage: print a message (P1 = string ptr), add a newline, and return.
; The print calls clobber P1/P2 per the ABI.
; m_nf is an ERROR: print it to the raw console (PUTS/CONOUT), never to stdout.
; stdout may be a redirect or a pipe — `more missing >F` would otherwise write the
; message INTO F, and `more missing | wc` would feed it to wc as data. Matches
; more.c's eputs(). m_usage below is NOT an error (the user asked with -h), so it
; stays on stdout and `more -h >notes` still captures it.
m_nf:   LDP1 #u_nf                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR PUTS
        LDA #10
        JSR CONOUT
        RTS
m_usage:LDP1 #u_use                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; prompt: print "--More--", read a CONIN key -> mkey (and A), erase the prompt.
prompt: LDP1 #s_more                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR SYS_PUTS                 ; SYS_PUTS "--More--"
        LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR CONIN                    ; CONIN -> A
        STA mkey
        LDP1 #s_erase                ; <- tierA: pointer constant (next: LDA)
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
