; man.asm — hand-coded MAN command (asm counterpart of os/commands/man.c).
;   MAN name   print /man/NAME (a manual page). Missing -> "no manual entry for".
; man is `cat` with a fixed "/man/" prefix: it builds the path, FRESOLVEs it
; (always from root, so CWD-independent) and streams the file with FGETB.
; Entry: P2 = arg tail.  BIOS FRESOLVE=$0133, FOPEN=$0124, FGETB=$0127; the
; 512-byte read buffer is $FC00.  SYS_PUTS=$200F, SYS_PUTC=$2009 (stdout);
; PUTS=$0112, CONOUT=$0103 (raw console — used for the not-found error).
;#use abi

        .org $6A00
; --- Parse the argument: skip spaces, reject empty/usage, find the name word.
;     P2 walks the arg tail; m_arg saves the name's start for the '-' rewind.
m_sk:   LDA (P2)                     ; skip leading spaces
        LDB #32
        CMP
        JNZ m_save
        INP2
        JMP m_sk
m_save: TPA2L                        ; m_arg = start of the name word
        STA m_arg
        TPA2H
        STA m_arg+1
        LDA (P2)                     ; empty / CR -> usage
        LDB #0
        CMP
        JZ m_usage
        LDB #13
        CMP
        JZ m_usage
        LDB #'-'                     ; -h / -H -> usage
        CMP
        JNZ m_build
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ m_usage
        LDB #'H'
        CMP
        JZ m_usage
        LDA m_arg                    ; '-' but not -h: rewind P2 to m_arg and
        TAP2L                        ;   treat the whole word (dash included) as name
        LDA m_arg+1
        TAP2H
; --- Build "/man/" + name into the path buffer via P1, then open and stream it.
m_build: LDP1 #path                  ; path = "/man/" + name (prefix written inline)
        LDA #'/'
        STA (P1)+
        LDA #'m'
        STA (P1)+
        LDA #'a'
        STA (P1)+
        LDA #'n'
        STA (P1)+
        LDA #'/'
        STA (P1)+
        LDA #5                       ; mb_n = bytes written so far (the prefix)
        STA mb_n
; path is 80 bytes: "/man/" (5) + name + NUL caps the name at 74 chars. The
; length test runs before LDA (P2) because the char must survive the CMP chain.
mb_l:   LDA mb_n                     ; path full at 79 -> truncate, leave room for NUL
        LDB #79
        CMP
        JZ mb_e
        LDA (P2)                     ; copy the name (stop at NUL/CR/space)
        LDB #0
        CMP
        JZ mb_e
        LDB #13
        CMP
        JZ mb_e
        LDB #32
        CMP
        JZ mb_e
        STA (P1)+
        LDA mb_n                     ; mb_n++ (bounded by 79, so no carry chain)
        LDB #1
        ADD
        STA mb_n
        INP2
        JMP mb_l
mb_e:   LDA #0
        STA (P1)                     ; NUL-terminate
        LDP1 #path
        JSR FRESOLVE                 ; resolve absolute path from root (CWD-independent)
        LDP1 #$FC00                  ; P1 = 512-byte read buffer for the open file
        JSR FOPEN                    ; FOPEN; C=1 -> not found (clobbers P1/P2)
        JC m_nf
; --- Copy loop: stream the whole file byte-by-byte to the console.
mo_l:   LDA #0
        JSR FGETB                    ; FGETB -> A, C=1 at EOF (clobbers P1/P2)
        JC mo_d
        JSR SYS_PUTC                 ; putchar
        JMP mo_l
mo_d:   RTS
; --- Not-found path: print "no manual entry for " then the requested name + LF.
; This is an ERROR, so the whole message goes to the raw console (PUTS/CONOUT),
; never to stdout: stdout may be a redirect or a pipe, and `man nope >notes`
; would otherwise write the message INTO notes while `man nope | wc` would feed
; it to wc as data. Matches man.c's eputs(). CONOUT preserves P1, so the name
; loop below can keep its cursor across the call. m_usage is NOT an error (the
; user asked for it), so it stays on stdout.
m_nf:   LDA #<m_msg                  ; "no manual entry for " (no newline)
        TAP1L
        LDA #>m_msg
        TAP1H
        LDA #0
        JSR PUTS
        LDP1 #path                   ; then the name: skip the 5-char "/man/"
        INP1                         ;   prefix (path+5 = start of copied name)
        INP1
        INP1
        INP1
        INP1
mn_l:   LDA (P1)
        LDB #0
        CMP
        JZ mn_d
        JSR CONOUT
        INP1
        JMP mn_l
mn_d:   LDA #10
        JSR CONOUT
        RTS
; --- Usage: emit the one-line help string plus a trailing newline.
m_usage: LDA #<m_use
        TAP1L
        LDA #>m_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

m_use:  .asciiz "usage: MAN name   show the manual page for a command"
m_msg:  .asciiz "no manual entry for "
path:   .fill 80
m_arg:  .fill 2
mb_n:   .fill 1
