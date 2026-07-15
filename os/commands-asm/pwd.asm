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
; Copy the arg pointer P2 into P1 (16-bit, low then high byte) so we can walk
; the tail with LDA (P1)+ without clobbering the OS-supplied P2. There is no
; direct pointer-to-pointer move, so it is routed byte-wise through A.
        TPA2L                                ; A = P2 low  -> P1 low
        TAP1L
        TPA2H                                ; A = P2 high -> P1 high
        TAP1H
; CMP does A-B without storing: Z=1 when equal, C=1 when A>=B (unsigned).
_skip:  LDA (P1)
        LDB #32                              ; 32 = ASCII space
        CMP                                  ; compare cur char to space; Z set if space
        JNZ _chk
        LDA (P1)+                            ; consume the space, advance P1
        JMP _skip
_chk:   LDA (P1)                             ; first non-space char
        LDB #'-'
        CMP
        JNZ _pwd                             ; not an option -> just print CWD
        LDA (P1)+                            ; consume '-', advance to option letter
        LDA (P1)                             ; the option letter (h or H)
        LDB #'h'
        CMP                                  ; CMP leaves A holding the option letter
        JZ _usage
        LDB #'H'
        CMP
        JZ _usage
; ---- print the working directory ------------------------------------------
; P1 must be reloaded with &_buf before each syscall: SYS_GETCWD (and any
; syscall) may clobber P1/P2, so the pointer set up for GETCWD cannot be
; reused for PUTS.
_pwd:   LDA #<_buf                   ; P1 = &_buf (dest for GETCWD)
        TAP1L
        LDA #>_buf
        TAP1H
        JSR SYS_GETCWD               ; copy CWD string (incl. NUL) into _buf
        LDA #<_buf                   ; reload P1 = &_buf; GETCWD may have trashed it
        TAP1L
        LDA #>_buf
        TAP1H
        JSR SYS_PUTS                 ; print CWD (no trailing newline)
        LDA #10                      ; 10 = '\n'
        JSR SYS_PUTC                 ; emit the newline
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
; Destination for SYS_GETCWD. 52 bytes holds the longest path the OS can
; return (full path incl. separators) plus the terminating NUL.
_buf:   .fill 52
