; del.asm — hand-coded DEL command (asm counterpart of os/commands/del.c).
;   DEL name [name...]   remove file(s) (Unix `rm`, minus recursion/flags).
; Same arg-loop + inlined abspath as touch.asm; the per-name action is
; FRESOLVE + FDELETE (tombstone the entry). A missing name prints "?No such
; file" and the rest still go. BIOS: FRESOLVE $0133, FDELETE $011E. OS:
; SYS_GETCWD $2003 (via abspath). Entry: P2 = arg tail.
;#use abi

        .org $6A00
        TPA2L
        STA t_arg
        TPA2H
        STA t_arg+1
t_sk:   LDA t_arg
        TAP2L
        LDA t_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ t_chk
        LDA t_arg
        LDB #1
        ADD
        STA t_arg
        JNC t_sk
        LDA t_arg+1
        INC
        STA t_arg+1
        JMP t_sk
t_chk:  LDA (P2)
        LDB #0
        CMP
        JZ t_usage
        LDB #13
        CMP
        JZ t_usage
        LDB #'-'
        CMP
        JNZ t_loop
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ t_usage
        LDB #'H'
        CMP
        JZ t_usage
; --- process each whitespace-separated name --------------------------------
t_loop: LDA t_arg
        TAP2L
        LDA t_arg+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ t_done
        LDB #13
        CMP
        JZ t_done
        LDA #<path                   ; abspath(path, arg)
        STA ap_out
        LDA #>path
        STA ap_out+1
        LDA t_arg
        STA ap_a
        LDA t_arg+1
        STA ap_a+1
        JSR abspath
        LDA ap_n
        LDB #0
        CMP
        JZ t_done                    ; nothing consumed -> done
        LDA t_arg                    ; arg += n
        LDB ap_n
        ADD
        STA t_arg
        JNC t_ns
        LDA t_arg+1
        INC
        STA t_arg+1
t_ns:   LDA t_arg                    ; skip spaces before the next name
        TAP2L
        LDA t_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ t_ex
        LDA t_arg
        LDB #1
        ADD
        STA t_arg
        JNC t_ns
        LDA t_arg+1
        INC
        STA t_arg+1
        JMP t_ns
; --- delete (FRESOLVE + FDELETE) -------------------------------------------
t_ex:   LDA #<path
        TAP1L
        LDA #>path
        TAP1H
        LDA #0
        JSR FRESOLVE                 ; FRESOLVE (path -> DIRLBA + FNAME)
        LDA #0
        JSR FDELETE                  ; tombstone FNAME; C=1 -> not found
        JNC t_loop                   ; deleted -> next name
        LDA #<u_nof                  ; not found -> "?No such file"
        TAP1L
        LDA #>u_nof
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        JMP t_loop
t_done: RTS
t_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; abspath (P2 source, P1 dest): ap_out <- absolute path of the word at ap_a;
; ap_n = chars consumed. Relative word prefixed with SYS_GETCWD + '/'; absolute
; word copied verbatim. Copy stops at NUL, CR, or space. Clobbers A,B,P1,P2.
abspath:LDA #0
        STA ap_n
        LDA ap_a
        TAP2L
        LDA ap_a+1
        TAP2H
        LDA (P2)
        LDB #'/'
        CMP
        JZ ab_abs
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
        LDA #0
        JSR SYS_GETCWD               ; SYS_GETCWD -> out
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
ab_sl:  LDA (P1)
        LDB #0
        CMP
        JZ ab_sld
        INP1
        JMP ab_sl
ab_sld: DEP1
        LDA (P1)
        INP1
        LDB #'/'
        CMP
        JZ ab_setp
        LDA #'/'
        STA (P1)+
        JMP ab_setp
ab_abs: LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
ab_setp:LDA ap_a
        TAP2L
        LDA ap_a+1
        TAP2H
ab_cp:  LDA (P2)
        LDB #0
        CMP
        JZ ab_dn
        LDB #13
        CMP
        JZ ab_dn
        LDB #32
        CMP
        JZ ab_dn
        STA (P1)+
        INP2
        LDA ap_n
        INC
        STA ap_n
        JMP ab_cp
ab_dn:  LDA #0
        STA (P1)
        RTS

u_use:  .asciiz "usage: DEL name [name...]   remove file(s)"
u_nof:  .asciiz "?No such file"

t_arg:  .fill 2
ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
path:   .fill 80
