; cat.asm — hand-coded CAT command (asm counterpart of os/commands/cat.c).
;   CAT [file|glob]   print file(s), or copy stdin to stdout if none.
; Shares open_path/glob_expand/gfile_ptr via `;#use stdin`. A named file (or each
; glob match) is streamed with FGETB; with no arg it filters stdin (SYS_GETC).
; Entry: P2 = arg tail.
;#use stdin
;#use abi

        .org $6A00
        TPA2L
        STA c_arg
        TPA2H
        STA c_arg+1
c_sk:   LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ c_chk
        LDA c_arg
        LDB #1
        ADD
        STA c_arg
        JNC c_sk
        LDA c_arg+1
        INC
        STA c_arg+1
        JMP c_sk
c_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ c_noarg
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ c_usage
        LDB #'H'
        CMP
        JZ c_usage
        ; '-' but not -h: fall through and treat as a filename (from c_arg)
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
; scan for a glob char in the word
        LDA #0
        STA c_g
        LDA c_arg
        TAP2L
        LDA c_arg+1
        TAP2H
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
c_setg: LDA #1
        STA c_g
        INP2
        JMP c_scl
c_scd:  LDA c_g
        LDB #0
        CMP
        JZ c_single
; glob: expand and cat each match
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
        JSR glob_expand
        LDA #0
        STA c_i
cg_l:   LDA c_i
        LDB ge_cnt
        CMP
        JC cg_d                      ; i >= cnt -> done
        LDA c_i
        STA gidx
        JSR gfile_ptr                ; op_a = &gfiles[i*64]
        JSR catpath
        LDA c_i
        INC
        STA c_i
        JMP cg_l
cg_d:   RTS
c_single:
        LDA c_arg
        STA op_a
        LDA c_arg+1
        STA op_a+1
        JSR catpath
        LDB #1
        CMP
        JZ c_nf                      ; not found
        RTS
c_stdin:LDA #0                       ; stdin -> stdout filter
        JSR SYS_GETC
        JC cs_d
        JSR SYS_PUTC
        JMP c_stdin
cs_d:   RTS
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

; catpath: op_a = path word -> stream it. A = 0 ok / 1 not found.
catpath:JSR open_path                ; 1 opened / 2 not found
        LDB #2
        CMP
        JZ cp_nf
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

c_arg:  .fill 2
c_g:    .fill 1
c_i:    .fill 1
