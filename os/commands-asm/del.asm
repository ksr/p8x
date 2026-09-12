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
t_sk:   LPW2 t_arg                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #32
        CMP
        JNZ t_chk
        INCW t_arg                ; <- tierA: 16-bit INCW chain before JMP t_sk (next: JMP t_sk -> LDA)
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
t_loop: LPW2 t_arg                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #0
        CMP
        JZ t_done
        LDB #13
        CMP
        JZ t_done
        LDW ap_out,#path                ; <- tierA: address constant (next: LDA)
        MOVW ap_a,t_arg                ; <- tierA: word move (next: JSR abspath)
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
t_ns:   LPW2 t_arg                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #32
        CMP
        JNZ t_ex
        INCW t_arg                ; <- tierA: 16-bit INCW chain before JMP t_ns (next: JMP t_ns -> LDA)
        JMP t_ns
; --- delete (FRESOLVE + FDELETE) -------------------------------------------
t_ex:   LDP1 #path                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR FRESOLVE                 ; FRESOLVE (path -> DIRLBA + FNAME)
        LDA #0
        JSR FDELETE                  ; tombstone FNAME; C=1 -> not found
        JNC t_loop                   ; deleted -> next name
        LDP1 #u_nof                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        JMP t_loop
t_done: RTS
t_usage:LDP1 #u_use                ; <- tierA: pointer constant (next: LDA)
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
        LPW2 ap_a                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #'/'
        CMP
        JZ ab_abs
        LPW1 ap_out                ; <- tierA: pointer load (next: LDA)
        LDA #0
        JSR SYS_GETCWD               ; SYS_GETCWD -> out
        LPW1 ap_out                ; <- tierA: pointer load (next: LDA)
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
ab_abs: LPW1 ap_out                ; <- tierA: pointer load (next: LDA)
ab_setp:LPW2 ap_a                ; <- tierA: pointer load (next: LDA)
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
