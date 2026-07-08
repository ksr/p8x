; mv.asm — hand-coded MV command (asm counterpart of os/commands/mv.c).
;   MV src dst    move/rename a file (copy-then-delete; P8XFS has no rename).
;
; Mirrors mv.c exactly: build absolute src/dst paths (CWD-prefixed if relative),
; refuse MV X X, FOPEN src -> FWOPEN dst -> stream bytes -> FCLOSE, then delete
; src. abspath() and streq() are inlined here as subroutines (the C build splices
; lib_abspath + lib_streq).
;
; BIOS: FRESOLVE $0133, FOPEN $0124, FGETB $0127, FWOPEN $012A, FPUTB $012D,
; FCLOSE $0130, FDELETE $011E.  OS: SYS_GETCWD $4003, SYS_PUTS $400F, SYS_PUTC
; $4009.  Read buffer $FC00.  Entry: P2 = arg tail.

        .org $7A00
        TPA2L                        ; save arg pointer
        STA m_arg
        TPA2H
        STA m_arg+1
; --- skip leading spaces ---------------------------------------------------
mv_sk:  LDA (P2)
        LDB #32
        CMP
        JNZ mv_chk
        INP2
        JMP mv_sk
mv_chk: TPA2L                        ; m_arg = first non-space
        STA m_arg
        TPA2H
        STA m_arg+1
        LDA (P2)
        LDB #0
        CMP
        JZ mv_usage
        LDB #13
        CMP
        JZ mv_usage
        LDB #'-'
        CMP
        JNZ mv_go
        INP2                         ; peek option letter (m_arg untouched)
        LDA (P2)
        LDB #'h'
        CMP
        JZ mv_usage
        LDB #'H'
        CMP
        JZ mv_usage
; --- abspath(src, arg) -----------------------------------------------------
mv_go:  LDA #<m_src
        STA ap_out
        LDA #>m_src
        STA ap_out+1
        LDA m_arg
        STA ap_a
        LDA m_arg+1
        STA ap_a+1
        JSR abspath
        LDA ap_n
        LDB #0
        CMP
        JZ mv_usage2                 ; nothing consumed -> usage
        LDA m_arg                    ; arg += n
        LDB ap_n
        ADD
        STA m_arg
        JNC mv_nc
        LDA m_arg+1
        INC
        STA m_arg+1
mv_nc:  LDA m_arg                    ; skip spaces before dst
        TAP2L
        LDA m_arg+1
        TAP2H
mv_sk2: LDA (P2)
        LDB #32
        CMP
        JNZ mv_chk2
        INP2
        JMP mv_sk2
mv_chk2:TPA2L
        STA m_arg
        TPA2H
        STA m_arg+1
        LDA (P2)
        LDB #0
        CMP
        JZ mv_usage2
        LDB #13
        CMP
        JZ mv_usage2
; --- abspath(dst, arg) -----------------------------------------------------
        LDA #<m_dst
        STA ap_out
        LDA #>m_dst
        STA ap_out+1
        LDA m_arg
        STA ap_a
        LDA m_arg+1
        STA ap_a+1
        JSR abspath
; --- refuse identical src/dst ----------------------------------------------
        LDA #<m_src
        STA se_p
        LDA #>m_src
        STA se_p+1
        LDA #<m_dst
        STA se_q
        LDA #>m_dst
        STA se_q+1
        JSR streq
        LDB #0
        CMP
        JNZ mv_same                  ; streq==1 -> same
; --- FOPEN src -------------------------------------------------------------
        LDA #<m_src
        TAP1L
        LDA #>m_src
        TAP1H
        LDA #0
        JSR $0133                    ; FRESOLVE src
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR $0124                    ; FOPEN $FC00
        JC mv_nosrc
; --- FWOPEN dst ------------------------------------------------------------
        LDA #<m_dst
        TAP1L
        LDA #>m_dst
        TAP1H
        LDA #0
        JSR $0133                    ; FRESOLVE dst
        LDA #0
        JSR $012A                    ; FWOPEN
; --- copy loop -------------------------------------------------------------
mv_cp:  LDA #0
        JSR $0127                    ; FGETB -> A, C=EOF
        JC mv_cpend
        STA m_ch
        LDA #0
        TAP1L
        TAP1H                        ; P1 = 0 (as mv.c passes)
        LDA m_ch
        JSR $012D                    ; FPUTB(A)
        JMP mv_cp
mv_cpend:
        LDA #0
        JSR $0130                    ; FCLOSE -> commit dst
        LDA #<m_src                  ; delete src
        TAP1L
        LDA #>m_src
        TAP1H
        LDA #0
        JSR $0133                    ; FRESOLVE src
        LDA #0
        JSR $011E                    ; FDELETE
        RTS
; --- message exits (each sets P1 to its message, then falls to mv_put) ------
mv_usage:
        LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        JMP mv_put
mv_usage2:
        LDA #<u_use2
        TAP1L
        LDA #>u_use2
        TAP1H
        JMP mv_put
mv_same:
        LDA #<u_same
        TAP1L
        LDA #>u_same
        TAP1H
        JMP mv_put
mv_nosrc:
        LDA #<u_nosrc
        TAP1L
        LDA #>u_nosrc
        TAP1H
mv_put: LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS

; ===========================================================================
; abspath: ap_out <- absolute path of the word at ap_a; ap_n = chars consumed.
; ===========================================================================
abspath:
        LDA #0
        STA ap_n
        LDA ap_a                     ; P2 = source cursor (P3 is the stack ptr!)
        TAP2L
        LDA ap_a+1
        TAP2H
        LDA (P2)
        LDB #'/'
        CMP
        JZ ab_abs                    ; absolute -> i=0
        LDA ap_out                   ; relative -> SYS_GETCWD(out)
        TAP1L
        LDA ap_out+1
        TAP1H
        LDA #0
        JSR $4003
        LDA ap_out                   ; strlen: advance P1 to the NUL
        TAP1L
        LDA ap_out+1
        TAP1H
ab_sl:  LDA (P1)
        LDB #0
        CMP
        JZ ab_sld
        INP1
        JMP ab_sl
ab_sld: DEP1                         ; look at out[i-1] (i>0: CWD non-empty)
        LDA (P1)
        INP1
        LDB #'/'
        CMP
        JZ ab_setp3                  ; already ends with '/'
        LDA #'/'
        STA (P1)+                    ; append '/'
        JMP ab_setp3
ab_abs: LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
ab_setp3:                            ; (re)load source cursor into P2: a syscall
        LDA ap_a                     ; may have clobbered it
        TAP2L
        LDA ap_a+1
        TAP2H
ab_copy:LDA (P2)                     ; append arg word until NUL/CR/space
        LDB #0
        CMP
        JZ ab_done
        LDB #13
        CMP
        JZ ab_done
        LDB #32
        CMP
        JZ ab_done
        STA (P1)+
        INP2
        LDA ap_n
        INC
        STA ap_n
        JMP ab_copy
ab_done:LDA #0
        STA (P1)
        RTS

; ===========================================================================
; streq: A = 1 if the NUL strings at se_p and se_q are equal, else 0.
; ===========================================================================
streq:  LDA se_p
        TAP1L
        LDA se_p+1
        TAP1H
        LDA se_q
        TAP2L
        LDA se_q+1
        TAP2H
se_l:   LDA (P1)
        STA se_c
        LDA (P2)
        LDB se_c
        CMP
        JNZ se_ne                    ; p[i] != q[i]
        LDA se_c
        LDB #0
        CMP
        JZ se_eq                     ; equal and both 0 -> 1
        INP1
        INP2
        JMP se_l
se_ne:  LDA #0
        RTS
se_eq:  LDA #1
        RTS

; --- messages --------------------------------------------------------------
u_use:  .asciiz "usage: MV src dst   move/rename a file"
u_same: .asciiz "mv: source and dest are the same"
u_nosrc:.asciiz "mv: source not found"
u_use2: .asciiz "usage: MV src dst"

; --- scratch ---------------------------------------------------------------
m_arg:  .fill 2
m_ch:   .fill 1
ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
se_p:   .fill 2
se_q:   .fill 2
se_c:   .fill 1
m_src:  .fill 80
m_dst:  .fill 80
