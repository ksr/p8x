        .org $6A00
        LDA #0
        STA __csp
        LDA #248
        STA __csp+1
        JSR _f_main
        RTS
_f_abspath:
        JSR __entf
        .word 4
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65534
        JSR __ldw
        .word 4
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #47
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend2
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $2003
        STA __ax
        LDA #0
        JNC Lbc3
        LDA #1
Lbc3:    STA __ax+1
Ltop4:
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend5
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
        JMP Ltop4
Lend5:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Land08
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #47
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land08
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande9
Land08:    LDA #0
        STA __ax
        STA __ax+1
Lande9:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend7
        LDA #47
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
Lend7:
Lend2:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65532
Ltop10:
        JSR __ldw
        .word 4
        PHW __ax
        JSR __ldw
        .word 65532
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land014
        JSR __ldw
        .word 4
        PHW __ax
        JSR __ldw
        .word 65532
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #13
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land014
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande15
Land014:    LDA #0
        STA __ax
        STA __ax+1
Lande15:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land012
        JSR __ldw
        .word 4
        PHW __ax
        JSR __ldw
        .word 65532
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #32
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land012
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande13
Land012:    LDA #0
        STA __ax
        STA __ax+1
Lande13:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend11
        JSR __ldw
        .word 4
        PHW __ax
        JSR __ldw
        .word 65532
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
        JSR __ldw
        .word 65532
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65532
        JMP Ltop10
Lend11:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65532
        JMP _ret_abspath
_ret_abspath:
        JSR __leave
        RTS
_f_openf:
        JSR __enter
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $0133
        STA __ax
        LDA #0
        JNC Lbc16
        LDA #1
Lbc16:    STA __ax+1
        LDA #0
        STA __ax
        LDA #252
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $0124
        STA __ax
        LDA #0
        JNC Lbc19
        LDA #1
Lbc19:    STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #1
        STA __ax+1
        PLW __t
        JSR __and
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend18
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_openf
Lend18:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_openf
_ret_openf:
        JSR __leave
        RTS
_f_pstr:
        JSR __entf
        .word 2
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65534
Ltop20:
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend21
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
        JMP Ltop20
Lend21:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_pstr
_ret_pstr:
        JSR __leave
        RTS
_f_pnum:
        JSR __entf
        .word 10
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend23
        LDA #48
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_pnum
Lend23:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65526
Ltop24:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend25
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 2
        PHW __ax
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __div
        PHW __ax
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        PLW __t
        JSR __sub
        PHW __ax
        LDA #48
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        PHW __ax
        JSR __lea
        .word 65528
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65526
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65526
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65526
        JSR __ldw
        .word 2
        PHW __ax
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __div
        JSR __stw
        .word 2
        JMP Ltop24
Lend25:
Ltop26:
        JSR __ldw
        .word 65526
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend27
        JSR __ldw
        .word 65526
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        JSR __stw
        .word 65526
        JSR __lea
        .word 65528
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65526
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        JMP Ltop26
Lend27:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_pnum
_ret_pnum:
        JSR __leave
        RTS
_f_main:
        JSR __entf
        .word 10
        TPA2L
        STA __ax
        TPA2H
        STA __ax+1
        JSR __stw
        .word 65534
Ltop28:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #32
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend29
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
        JMP Ltop28
Lend29:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor134
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #13
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor134
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore35
Lor134:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore35:
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor132
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #45
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land036
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #104
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor138
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #72
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor138
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore39
Lor138:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore39:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land036
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande37
Land036:    LDA #0
        STA __ax
        STA __ax+1
Lande37:
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor132
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore33
Lor132:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore33:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend31
        LDA #<__s40
        STA __ax
        LDA #>__s40
        STA __ax+1
        LDA __ax
        TAP1L
        LDA __ax+1
        TAP1H
        JSR $200F
        LDA #10
        JSR $2009
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend31:
        JSR __ldw
        .word 65534
        JSR __push
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
        JSR __push
        JSR _f_abspath
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl41
        LDA __csp+1
        INC
        STA __csp+1
Lcl41:
        JSR __stw
        .word 65532
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65532
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
Ltop42:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #32
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend43
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
        JMP Ltop42
Lend43:
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
        JSR __push
        JSR _f_openf
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl46
        LDA __csp+1
        INC
        STA __csp+1
Lcl46:
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend45
        LDA #<__s47
        STA __ax
        LDA #>__s47
        STA __ax+1
        LDA __ax
        TAP1L
        LDA __ax+1
        TAP1H
        JSR $200F
        LDA #10
        JSR $2009
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend45:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_n1,__ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $0127
        STA __ax
        LDA #0
        JNC Lbc48
        LDA #1
Lbc48:    STA __ax+1
        JSR __stw
        .word 65530
Ltop49:
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #0
        STA __ax
        LDA #1
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend50
        MOVW __ax,_g_n1
        PHW __ax
        LDA #0
        STA __ax
        LDA #32
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend52
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #<_g_b1
        STA __ax
        LDA #>_g_b1
        STA __ax+1
        PHW __ax
        MOVW __ax,_g_n1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
Lend52:
        MOVW __ax,_g_n1
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        MOVW _g_n1,__ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $0127
        STA __ax
        LDA #0
        JNC Lbc53
        LDA #1
Lbc53:    STA __ax+1
        JSR __stw
        .word 65530
        JMP Ltop49
Lend50:
        LDA #0
        STA __ax
        LDA #32
        STA __ax+1
        PHW __ax
        MOVW __ax,_g_n1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend55
        LDA #<__s56
        STA __ax
        LDA #>__s56
        STA __ax+1
        LDA __ax
        TAP1L
        LDA __ax+1
        TAP1H
        JSR $200F
        LDA #10
        JSR $2009
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend55:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor159
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #13
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor159
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore60
Lor159:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore60:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend58
        LDA #<__s61
        STA __ax
        LDA #>__s61
        STA __ax+1
        LDA __ax
        TAP1L
        LDA __ax+1
        TAP1H
        JSR $200F
        LDA #10
        JSR $2009
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend58:
        JSR __ldw
        .word 65534
        JSR __push
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
        JSR __push
        JSR _f_abspath
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl62
        LDA __csp+1
        INC
        STA __csp+1
Lcl62:
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
        JSR __push
        JSR _f_openf
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl65
        LDA __csp+1
        INC
        STA __csp+1
Lcl65:
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend64
        LDA #<__s66
        STA __ax
        LDA #>__s66
        STA __ax+1
        LDA __ax
        TAP1L
        LDA __ax+1
        TAP1H
        JSR $200F
        LDA #10
        JSR $2009
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend64:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65528
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65526
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $0127
        STA __ax
        LDA #0
        JNC Lbc67
        LDA #1
Lbc67:    STA __ax+1
        JSR __stw
        .word 65530
Ltop68:
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #0
        STA __ax
        LDA #1
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend69
        JSR __ldw
        .word 65528
        PHW __ax
        MOVW __ax,_g_n1
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend71
        LDA #<__s72
        STA __ax
        LDA #>__s72
        STA __ax+1
        LDA __ax
        TAP1L
        LDA __ax+1
        TAP1H
        JSR $200F
        LDA #10
        JSR $2009
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend71:
        LDA #<_g_b1
        STA __ax
        LDA #>_g_b1
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65528
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend74
        LDA #<__s75
        STA __ax
        LDA #>__s75
        STA __ax+1
        JSR __push
        JSR _f_pstr
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl76
        LDA __csp+1
        INC
        STA __csp+1
Lcl76:
        JSR __ldw
        .word 65528
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_pnum
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl77
        LDA __csp+1
        INC
        STA __csp+1
Lcl77:
        LDA #<__s78
        STA __ax
        LDA #>__s78
        STA __ax+1
        JSR __push
        JSR _f_pstr
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl79
        LDA __csp+1
        INC
        STA __csp+1
Lcl79:
        JSR __ldw
        .word 65526
        JSR __push
        JSR _f_pnum
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl80
        LDA __csp+1
        INC
        STA __csp+1
Lcl80:
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend74:
        LDA #<_g_b1
        STA __ax
        LDA #>_g_b1
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65528
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend82
        JSR __ldw
        .word 65526
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65526
Lend82:
        JSR __ldw
        .word 65528
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65528
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $0127
        STA __ax
        LDA #0
        JNC Lbc83
        LDA #1
Lbc83:    STA __ax+1
        JSR __stw
        .word 65530
        JMP Ltop68
Lend69:
        JSR __ldw
        .word 65528
        PHW __ax
        MOVW __ax,_g_n1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend85
        LDA #<__s86
        STA __ax
        LDA #>__s86
        STA __ax+1
        LDA __ax
        TAP1L
        LDA __ax+1
        TAP1H
        JSR $200F
        LDA #10
        JSR $2009
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend85:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
_ret_main:
        JSR __leave
        RTS
__add:  LDA __t
        LDB __ax
        ADD
        STA __ax
        LDA #0
        JNC __add1
        LDA #1
__add1: STA __c
        LDA __t+1
        LDB __ax+1
        ADD
        LDB __c
        ADD
        STA __ax+1
        RTS
__sub:  LDA __t
        LDB __ax
        SUB
        STA __ax
        LDA #0
        JC __sub1
        LDA #1
__sub1: STA __c
        LDA __t+1
        LDB __ax+1
        SUB
        STA __ax+1
        LDA __c
        JZ __sub2
        LDA __ax+1
        LDB #1
        SUB
        STA __ax+1
__sub2: RTS
__mul:  LDA #0
        STA __r
        STA __r+1
        LDA #16
        STA __n
__mul_l: LDA __ax
        LDB #1
        AND
        JZ __mul_s
        LDA __r
        LDB __t
        ADD
        STA __r
        LDA #0
        JNC __mul_a
        LDA #1
__mul_a: STA __c
        LDA __r+1
        LDB __t+1
        ADD
        LDB __c
        ADD
        STA __r+1
__mul_s: LDA __t
        SHL
        STA __t
        LDA __t+1
        ROL
        STA __t+1
        LDA __ax+1
        SHR
        STA __ax+1
        LDA __ax
        ROR
        STA __ax
        LDA __n
        DEC
        STA __n
        JNZ __mul_l
        MOVW __ax,__r
        RTS
__div:  JSR __divmod
        MOVW __ax,__t
        RTS
__divmod: LDA #0
        STA __dr
        STA __dr+1
        LDA #16
        STA __n
__dm_l: LDA __t
        SHL
        STA __t
        LDA __t+1
        ROL
        STA __t+1
        LDA __dr
        ROL
        STA __dr
        LDA __dr+1
        ROL
        STA __dr+1
        LDA __dr+1
        LDB __ax+1
        CMP
        JZ __dm_lo
        JC __dm_ge
        JMP __dm_no
__dm_lo: LDA __dr
        LDB __ax
        CMP
        JNC __dm_no
__dm_ge: LDA __dr
        LDB __ax
        SUB
        STA __dr
        LDA #0
        JC __dm_b
        LDA #1
__dm_b: STA __c
        LDA __dr+1
        LDB __ax+1
        SUB
        LDB __c
        SUB
        STA __dr+1
        LDA __t
        LDB #1
        OR
        STA __t
__dm_no: LDA __n
        DEC
        STA __n
        JNZ __dm_l
        RTS
__and:  LDA __t
        LDB __ax
        AND
        STA __ax
        LDA __t+1
        LDB __ax+1
        AND
        STA __ax+1
        RTS
__not:  LDA __ax
        LDB __ax+1
        OR
        JZ __not1
        LDA #0
        JMP __nots
__not1: LDA #1
__nots: STA __ax
        LDA #0
        STA __ax+1
        RTS
__eq:   LDA __t
        LDB __ax
        CMP
        JNZ __eq0
        LDA __t+1
        LDB __ax+1
        CMP
        JNZ __eq0
        LDA #1
        JMP __eqs
__eq0:  LDA #0
__eqs:  STA __ax
        LDA #0
        STA __ax+1
        RTS
__lt:   LDA __t+1
        LDB __ax+1
        CMP
        JZ __lt_lo
        JC __lt0
        JMP __lt1
__lt_lo: LDA __t
        LDB __ax
        CMP
        JC __lt0
__lt1:  LDA #1
        JMP __lts
__lt0:  LDA #0
__lts:  STA __ax
        LDA #0
        STA __ax+1
        RTS
__push: LDA __csp
        LDB #2
        SUB
        STA __csp
        JC __pu1
        LDA __csp+1
        LDB #1
        SUB
        STA __csp+1
__pu1:  LDA __csp
        TAP1L
        LDA __csp+1
        TAP1H
        LDA __ax
        STA (P1)+
        LDA __ax+1
        STA (P1)
        RTS
__enter: LDA __csp
        LDB #2
        SUB
        STA __csp
        JC __en1
        LDA __csp+1
        LDB #1
        SUB
        STA __csp+1
__en1:  LDA __csp
        TAP1L
        LDA __csp+1
        TAP1H
        LDA __fp
        STA (P1)+
        LDA __fp+1
        STA (P1)
        MOVW __fp,__csp
        RTS
__entf: PLA
        TAP1L
        PLA
        TAP1H
        LDA (P1)+
        STA __off
        LDA (P1)+
        STA __off+1
        TPA1L
        STA __ra
        TPA1H
        STA __ra+1
        LDA __csp
        LDB #2
        SUB
        STA __csp
        JC __ef1
        LDA __csp+1
        LDB #1
        SUB
        STA __csp+1
__ef1:  LDA __csp
        TAP1L
        LDA __csp+1
        TAP1H
        LDA __fp
        STA (P1)+
        LDA __fp+1
        STA (P1)
        MOVW __fp,__csp
        LDA __csp
        LDB __off
        SUB
        STA __csp
        JC __ef2
        LDA __csp+1
        LDB #1
        SUB
        STA __csp+1
__ef2:  LDA __ra+1
        PHA
        LDA __ra
        PHA
        RTS
__leave: MOVW __csp,__fp
        LDA __csp
        TAP1L
        LDA __csp+1
        TAP1H
        LDA (P1)+
        STA __fp
        LDA (P1)
        STA __fp+1
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC __lv1
        LDA __csp+1
        INC
        STA __csp+1
__lv1:  RTS
__lea:  PLA
        TAP1L
        PLA
        TAP1H
        LDA (P1)+
        STA __off
        LDA (P1)+
        STA __off+1
        TPA1L
        STA __ra
        TPA1H
        STA __ra+1
        LDA __fp
        LDB __off
        ADD
        STA __t
        LDA #0
        JNC __la1
        LDA #1
__la1:  STA __c
        LDA __fp+1
        LDB __off+1
        ADD
        LDB __c
        ADD
        STA __t+1
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ra+1
        PHA
        LDA __ra
        PHA
        RTS
__ldw:  PLA
        TAP1L
        PLA
        TAP1H
        LDA (P1)+
        STA __off
        LDA (P1)+
        STA __off+1
        TPA1L
        STA __ra
        TPA1H
        STA __ra+1
        LDA __fp
        LDB __off
        ADD
        STA __t
        LDA #0
        JNC __ldw1
        LDA #1
__ldw1: STA __c
        LDA __fp+1
        LDB __off+1
        ADD
        LDB __c
        ADD
        STA __t+1
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA (P1)+
        STA __ax
        LDA (P1)
        STA __ax+1
        LDA __ra+1
        PHA
        LDA __ra
        PHA
        RTS
__stw:  PLA
        TAP1L
        PLA
        TAP1H
        LDA (P1)+
        STA __off
        LDA (P1)+
        STA __off+1
        TPA1L
        STA __ra
        TPA1H
        STA __ra+1
        LDA __fp
        LDB __off
        ADD
        STA __t
        LDA #0
        JNC __stw1
        LDA #1
__stw1: STA __c
        LDA __fp+1
        LDB __off+1
        ADD
        LDB __c
        ADD
        STA __t+1
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        STA (P1)+
        LDA __ax+1
        STA (P1)
        LDA __ra+1
        PHA
        LDA __ra
        PHA
        RTS
__ax:   .fill 2
__t:    .fill 2
__c:    .fill 1
__fp:   .fill 2
__csp:  .fill 2
__off:  .fill 2
__ra:   .fill 2
__r:    .fill 2
__n:    .fill 1
_g_path:    .fill 80
_g_b1:    .fill 8192
_g_n1:    .fill 2
__s40:    .byte 117,115,97,103,101,58,32,67,77,80,32,102,105,108,101,49,32,102,105,108,101,50,32,32,32,114,101,112,111,114,116,32,116,104,101,32,102,105,114,115,116,32,100,105,102,102,101,114,105,110,103,32,98,121,116,101,32,40,115,105,108,101,110,116,32,105,102,32,101,113,117,97,108,41,0
__s47:    .byte 99,109,112,58,32,102,105,108,101,49,32,110,111,116,32,102,111,117,110,100,0
__s56:    .byte 99,109,112,58,32,102,105,108,101,49,32,116,111,111,32,108,97,114,103,101,32,40,109,97,120,32,56,75,41,0
__s61:    .byte 117,115,97,103,101,58,32,67,77,80,32,102,105,108,101,49,32,102,105,108,101,50,0
__s66:    .byte 99,109,112,58,32,102,105,108,101,50,32,110,111,116,32,102,111,117,110,100,0
__s72:    .byte 99,109,112,58,32,69,79,70,32,111,110,32,102,105,108,101,49,0
__s75:    .byte 99,109,112,58,32,102,105,108,101,115,32,100,105,102,102,101,114,58,32,98,121,116,101,32,0
__s78:    .byte 44,32,108,105,110,101,32,0
__s86:    .byte 99,109,112,58,32,69,79,70,32,111,110,32,102,105,108,101,50,0
__dr:   .fill 2
