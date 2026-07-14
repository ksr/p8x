; pwd.asm — hand-coded PWD command for the P8X (asm counterpart of
; os/commands/pwd.c). Prints the current working directory via SYS_GETCWD.
;
; This is part of the commands-asm experiment: hand-written assembler versions
; of the C /BIN commands, to compare fill-binary size against the p8cc output.
;
; ABI (same as a p8cc-compiled command):
;   entry at $6A00; P2 = pointer to the command-argument tail (NUL-terminated).
;   SYS_GETCWD = $2003 (P1 = dest buffer, copies CWD incl. NUL).
;   SYS_PUTS   = $200F (P1 = string) prints the string (no newline).
;   SYS_PUTC   = $2009 (A = char).  puts() = SYS_PUTS then SYS_PUTC(10).
;   return to the OS with RTS.
;
;   python3 assembler/p8xasm.py os/commands-asm/pwd.asm -o pwd.bin --base 0x6A00
;#use abi

        .org $6A00
; ---- skip leading spaces in the arg tail, then look for -h / -H ------------
        TPA2L                                ; P1 = P2 (the arg pointer)
        TAP1L
        TPA2H
        TAP1H
_skip:  LDA (P1)
        LDB #32
        CMP                                  ; A - B : Z set if space
        JNZ _chk
        LDA (P1)+                            ; consume the space, advance P1
        JMP _skip
_chk:   LDA (P1)                             ; first non-space char
        LDB #'-'
        CMP
        JNZ _pwd                             ; not an option -> just print CWD
        LDA (P1)+                            ; consume '-'
        LDA (P1)                             ; the option letter
        LDB #'h'
        CMP
        JZ _usage
        LDA (P1)
        LDB #'H'
        CMP
        JZ _usage
; ---- print the working directory ------------------------------------------
_pwd:   LDA #<_buf
        TAP1L
        LDA #>_buf
        TAP1H
        JSR SYS_GETCWD               ; SYS_GETCWD -> _buf
        LDA #<_buf
        TAP1L
        LDA #>_buf
        TAP1H
        JSR SYS_PUTS                 ; SYS_PUTS
        LDA #10
        JSR SYS_PUTC                 ; newline
        RTS
; ---- -h usage --------------------------------------------------------------
_usage: LDA #<_msg
        TAP1L
        LDA #>_msg
        TAP1H
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

_msg:   .asciiz "usage: PWD   print the working directory path"
_buf:   .fill 52
