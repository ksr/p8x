; cat.asm — hand-coded CAT command (asm counterpart of os/commands/cat.c).
;   CAT [file|glob]   print file(s), or copy stdin to stdout if none.
; Shares open_path/glob_expand/gfile_ptr via `;#use stdin`. A named file (or each
; glob match) is streamed with FGETB; with no arg it filters stdin (SYS_GETC).
; Entry: P2 = arg tail.
;#use stdin
;#use abi

        .org $6A00                   ; loads at TPA base (see memory-map: $6A00)
; Save the incoming arg-tail pointer (P2) into the c_arg 16-bit variable so we
; can freely reload/advance it while scanning. TPA2L/TPA2H read P2's low/high.
        TPA2L
        STA c_arg
        TPA2H
        STA c_arg+1
; Move directory scans off SBUF ($6100): catpath's FRESOLVE reads dir sectors into
; the DIBUFH page, which defaults to SBUF — the same buffer the shell's redirect
; write-stream (`cat a b >OUT`) holds pending output in. Without this the second
; file's FRESOLVE overwrites the first file's buffered bytes with a dir sector.
; $FA00 is a free scratch page below the $FC00 read buffer (the glob path's page).
        LDA #0
        TAP1L
        TAP1H
        LDA #$FA
        JSR FSDIRBUF
; c_sk: skip leading spaces (ASCII 32) in the arg tail, advancing c_arg past them.
c_sk:   LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
        LDA (P2)                     ; A = current char
        LDB #32
        CMP
        JNZ c_chk                    ; not a space -> done skipping
; advance c_arg by 1 (16-bit); carry out of the low byte bumps the high byte
        LDA c_arg
        LDB #1
        ADD
        STA c_arg
        JNC c_sk                     ; no carry -> low byte only
        LDA c_arg+1
        INC
        STA c_arg+1
        JMP c_sk
; c_chk: first non-space char reached. Handle the "-h"/"-H" help flag. Only the
; single char after '-' is tested, so any "-h..." word ("-help") also prints
; usage; cat.c matches the same way, so the two twins agree.
c_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ c_noarg                  ; not '-' -> ordinary filename
        INP2                         ; peek char after '-'
        LDA (P2)
        LDB #'h'
        CMP
        JZ c_usage
        LDB #'H'
        CMP
        JZ c_usage
        ; '-' but not -h: fall through and treat as a filename (from c_arg)
; c_noarg: reload c_arg into P2 and test the first char. NUL or CR (13) means
; there was no filename, so fall through to the stdin filter.
c_noarg:LDA c_arg                    ; empty arg -> filter stdin
        TAP2L
        LDA c_arg+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ c_stdin
        LDB #13
        CMP
        JZ c_stdin
; c_next: loop head for one file/glob TOKEN. cat takes several space-separated
; arguments (Unix `cat a b c`); c_arg points at the current token's first char.
; scan the word for a glob metachar ('*' or '?'); c_g = 1 if found, else 0
c_next: LDA #0
        STA c_g
        LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
; c_scl: scan loop. Word terminates at NUL, CR (13), or space (32).
c_scl:  LDA (P2)
        LDB #0
        CMP
        JZ c_scd
        LDB #13
        CMP
        JZ c_scd
        LDB #32
        CMP
        JZ c_scd
        LDB #'*'
        CMP
        JZ c_setg
        LDB #'?'
        CMP
        JZ c_setg
        INP2
        JMP c_scl
; c_setg: glob char found -> set flag and keep scanning to word end
c_setg: LDA #1
        STA c_g
        INP2
        JMP c_scl
; c_scd: end of word. c_g==0 -> plain single file; else glob-expand.
c_scd:  LDA c_g
        LDB #0
        CMP
        JZ c_single
; glob path: fill glob_expand's ABI vars (pattern, output buf, max count),
; then cat each returned match. gfiles is a 24 x 64-byte name buffer.
        LDA c_arg
        STA ge_pat
        LDA c_arg+1
        STA ge_pat+1
        LDA #<gfiles
        STA ge_out
        LDA #>gfiles
        STA ge_out+1
        LDA #24
        STA ge_max
        JSR glob_expand              ; ge_cnt = number of matches
        LDA #0
        STA c_i                      ; i = 0
; cg_l: loop i over the matches. CMP sets C when A>=B, i.e. i>=ge_cnt.
cg_l:   LDA c_i
        LDB ge_cnt
        CMP
        JC cg_d                      ; i >= cnt -> done
        STA gidx                     ; CMP preserves A, so A is still c_i
        JSR gfile_ptr                ; op_a = &gfiles[i*64]
        JSR catpath
        LDA c_i
        INC
        STA c_i
        JMP cg_l
cg_d:   JMP c_adv                     ; this glob token done -> next token
; c_single: no glob chars -> cat the one named file. catpath returns A=1 if
; the file was not found, in which case we print the not-found message.
c_single:
        LDA c_arg
        STA op_a
        LDA c_arg+1
        STA op_a+1
        JSR catpath
        LDB #1
        CMP
        JZ c_nf                      ; A==1 -> not found (prints, then stops)
        ; fall through to c_adv: this single-file token done -> next token
; c_adv: advance c_arg past the token just consumed, then past trailing spaces.
; If the next char is NUL or CR all arguments are done -> RTS; else -> c_next.
c_adv:  LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
ca_tok: LDA (P2)                     ; skip the rest of this token
        LDB #0
        CMP
        JZ ca_fin
        LDB #13
        CMP
        JZ ca_fin
        LDB #32
        CMP
        JZ ca_spc
        INP2
        JMP ca_tok
ca_spc: INP2                         ; skip the space run between tokens
        LDA (P2)
        LDB #32
        CMP
        JZ ca_spc
ca_fin: TPA2L                        ; write the advanced cursor back to c_arg
        STA c_arg
        TPA2H
        STA c_arg+1
        LDA (P2)                     ; more arguments?
        LDB #0
        CMP
        JZ ca_ret
        LDB #13
        CMP
        JZ ca_ret
        JMP c_next
ca_ret: RTS
; c_stdin: no filename given -> copy stdin to stdout byte by byte.
; SYS_GETC returns C=1 at EOF; each byte is echoed with SYS_PUTC.
c_stdin:LDA #0                       ; stdin -> stdout filter
        JSR SYS_GETC
        JC cs_d
        JSR SYS_PUTC
        JMP c_stdin
cs_d:   RTS
; c_nf / c_usage: print a message via SYS_PUTS (P1 = string ptr, A=0 flags),
; then emit a trailing newline (LF, 10). Both return to the shell.
c_nf:   LDA #<m_nf
        TAP1L
        LDA #>m_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
c_usage:LDA #<m_use
        TAP1L
        LDA #>m_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; catpath: op_a = path word -> open and stream its bytes to stdout.
;   In:  op_a = pointer to the path/name word (NUL/CR/space terminated)
;   Out: A = 0 on success, A = 1 if the file was not found
;   Clobbers: A, B, P1/P2 (FGETB clobbers the pointer regs)
catpath:JSR open_path                ; returns 1 = opened, 2 = not found
        LDB #2
        CMP
        JZ cp_nf
; cp_l: read/echo loop. FGETB returns the byte in A and sets C=1 at EOF.
cp_l:   LDA #0
        JSR FGETB                    ; FGETB -> A, C=EOF
        JC cp_ok
        JSR SYS_PUTC                 ; putchar
        JMP cp_l
cp_ok:  LDA #0
        RTS
cp_nf:  LDA #1
        RTS

m_nf:   .asciiz "cat: not found"
m_use:  .asciiz "usage: CAT [file|glob]   print file(s), or filter stdin if none"

; command-local scratch variables
c_arg:  .fill 2                      ; 16-bit pointer to the current arg word
c_g:    .fill 1                      ; glob flag: 1 if word contains '*' or '?'
c_i:    .fill 1                      ; glob match loop index
