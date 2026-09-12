; touch.asm — hand-coded TOUCH command (asm counterpart of os/commands/touch.c).
;   TOUCH name [name...]   create empty file(s) if missing (no mtime yet).
; abspath inlined (P2 source, P1 dest). For each name: FRESOLVE+FOPEN to test
; existence; if not found, FRESOLVE+FWOPEN+FCLOSE to create a zero-byte file
; (an existing file is left untouched, NOT truncated). No shared include.
; BIOS: FRESOLVE $0133, FOPEN $0124, FWOPEN $012A, FCLOSE $0130. OS: SYS_GETCWD
; $2003 (via abspath). Entry: P2 = arg tail.
;#use abi

; Entry: TPA points P2 at the raw argument tail. Stash it in t_arg (a 16-bit
; RAM cursor) since P2 gets reused for every dereference below.
        .org $6A00
        TPA2L
        STA t_arg
        TPA2H
        STA t_arg+1
; t_sk: skip leading spaces so t_chk sees the first real char of the tail.
t_sk:   LPW2 t_arg                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #32
        CMP
        JNZ t_chk
        INCW t_arg                ; <- tierA: 16-bit INCW chain before JMP t_sk (next: JMP t_sk -> LDA)
        JMP t_sk
; t_chk: no operand (NUL or CR) prints usage; a leading '-' is inspected for the
; -h / -H help flag, which also prints usage. Anything else falls to t_loop.
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
        INP2                            ; step past '-' to the flag letter
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
        LDA (P2)                     ; each iteration re-enters at t_ns to reload P2
        LDB #32
        CMP
        JNZ t_ex
        INCW t_arg                ; <- tierA: 16-bit INCW chain before JMP t_ns (next: JMP t_ns -> LDA)
        JMP t_ns
; --- exists? (FRESOLVE + FOPEN) --------------------------------------------
t_ex:   LDP1 #path                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR FRESOLVE                 ; FRESOLVE
        LDA #$00                     ; P1 = $FC00 read-buffer for FOPEN's use
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR FOPEN                    ; FOPEN $FC00 (C=0 -> file exists)
        JNC t_loop                   ; carry clear -> exists -> leave it, next name
; --- create empty (FRESOLVE + FWOPEN + FCLOSE) -----------------------------
        LDP1 #path                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR FRESOLVE                 ; FRESOLVE
        LDA #0
        JSR FWOPEN                   ; FWOPEN
        LDA #0
        JSR FCLOSE                   ; FCLOSE -> zero-byte file
        JMP t_loop
t_done: RTS
t_usage:LDP1 #u_use                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; abspath (P2 source, P1 dest): ap_out <- absolute path of the word at ap_a;
; ap_n = chars consumed. (P3 is the stack pointer, so P2 is the source cursor.)
; A relative word is prefixed with SYS_GETCWD + '/'; an absolute word ('/...')
; is copied verbatim. Copy stops at NUL, CR, or space. Clobbers A, B, P1, P2.
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
; ab_sld: P1 sits on the NUL; back up to inspect the CWD's last char. If it is
; not already '/', append one so the joined path has exactly one separator.
; (Overwriting the NUL is fine; ab_cp/ab_dn re-terminate the string.)
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

u_use:  .asciiz "usage: TOUCH name [name...]   create empty file(s) if missing"

t_arg:  .fill 2
ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
path:   .fill 80
