        .org $6A00
        LDA #0
        STA __csp
        LDA #248
        STA __csp+1
        JSR _f_main
        RTS
_f_ph2:
        JSR __enter
        MOVW __ax,_g_HD
        PHW __ax
        JSR __ldw
        .word 2
        PHW __ax
        LDA #4
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __shr
        PHW __ax
        LDA #15
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        MOVW __ax,_g_HD
        PHW __ax
        JSR __ldw
        .word 2
        PHW __ax
        LDA #15
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_ph2
_ret_ph2:
        JSR __leave
        RTS
_f_ph4:
        JSR __enter
        JSR __ldw
        .word 2
        PHW __ax
        LDA #8
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __shr
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        JSR __push
        JSR _f_ph2
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl2
        LDA __csp+1
        INC
        STA __csp+1
Lcl2:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        JSR __push
        JSR _f_ph2
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl3
        LDA __csp+1
        INC
        STA __csp+1
Lcl3:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_ph4
_ret_ph4:
        JSR __leave
        RTS
_f_hx:
        JSR __enter
        JSR __ldw
        .word 2
        PHW __ax
        LDA #48
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land06
        LDA #57
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 2
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land06
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande7
Land06:    LDA #0
        STA __ax
        STA __ax+1
Lande7:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend5
        JSR __ldw
        .word 2
        PHW __ax
        LDA #48
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        JMP _ret_hx
Lend5:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #65
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land010
        LDA #70
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 2
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land010
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande11
Land010:    LDA #0
        STA __ax
        STA __ax+1
Lande11:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend9
        JSR __ldw
        .word 2
        PHW __ax
        LDA #65
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        PHW __ax
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JMP _ret_hx
Lend9:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #97
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land014
        LDA #102
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 2
        PLW __t
        JSR __lt
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
        JZ Lend13
        JSR __ldw
        .word 2
        PHW __ax
        LDA #97
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        PHW __ax
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JMP _ret_hx
Lend13:
        LDA #99
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_hx
_ret_hx:
        JSR __leave
        RTS
_f_nl:
        JSR __enter
        LDA #13
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_nl
_ret_nl:
        JSR __leave
        RTS
_f_main:
        JSR __entf
        .word 14
        TPA2L
        STA __ax
        TPA2H
        STA __ax+1
        JSR __stw
        .word 65534
Ltop16:
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
        JZ Lend17
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
        JMP Ltop16
Lend17:
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
        JNZ Lor122
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
        JNZ Lor122
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore23
Lor122:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore23:
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor120
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
        JZ Land024
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
        JNZ Lor126
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
        JNZ Lor126
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore27
Lor126:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore27:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land024
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande25
Land024:    LDA #0
        STA __ax
        STA __ax+1
Lande25:
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor120
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore21
Lor120:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore21:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend19
        LDA #<__s28
        STA __ax
        LDA #>__s28
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
Lend19:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65532
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65528
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        JSR __push
        JSR _f_hx
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl29
        LDA __csp+1
        INC
        STA __csp+1
Lcl29:
        JSR __stw
        .word 65530
Ltop30:
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #16
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend31
        JSR __ldw
        .word 65532
        PHW __ax
        LDA #16
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        PHW __ax
        JSR __ldw
        .word 65530
        PLW __t
        JSR __add
        JSR __stw
        .word 65532
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
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65528
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        JSR __push
        JSR _f_hx
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl32
        LDA __csp+1
        INC
        STA __csp+1
Lcl32:
        JSR __stw
        .word 65530
        JMP Ltop30
Lend31:
        JSR __ldw
        .word 65528
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
        JZ Lend34
        LDA #<__s35
        STA __ax
        LDA #>__s35
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
Lend34:
Ltop36:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend37
        JSR __ldw
        .word 65532
        JSR __push
        JSR _f_ph4
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl38
        LDA __csp+1
        INC
        STA __csp+1
Lcl38:
        LDA #58
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        LDA #32
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        JSR __ldw
        .word 65532
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
        JSR __push
        JSR _f_ph2
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl39
        LDA __csp+1
        INC
        STA __csp+1
Lcl39:
        LDA #32
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
        JSR $200C
        STA __ax
        LDA #0
        STA __ax+1
        JNC Lge40
        LDA #255
        STA __ax
        STA __ax+1
Lge40:
        JSR __stw
        .word 65526
        JSR __ldw
        .word 65526
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        LDA #0
        STA __t
        STA __t+1
        JSR __sub
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend42
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend42:
        JSR __ldw
        .word 65526
        PHW __ax
        LDA #46
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend44
        JSR _f_nl
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend44:
        JSR __ldw
        .word 65526
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
        JZ Lelse45
        JSR $200C
        STA __ax
        LDA #0
        STA __ax+1
        JNC Lge47
        LDA #255
        STA __ax
        STA __ax+1
Lge47:
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
        JMP Lend46
Lelse45:
        JSR __ldw
        .word 65526
        JSR __push
        JSR _f_hx
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl48
        LDA __csp+1
        INC
        STA __csp+1
Lcl48:
        JSR __stw
        .word 65524
        JSR __ldw
        .word 65524
        PHW __ax
        LDA #16
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse49
        JSR _f_nl
        JMP Lend50
Lelse49:
        JSR $200C
        STA __ax
        LDA #0
        STA __ax+1
        JNC Lge51
        LDA #255
        STA __ax
        STA __ax+1
Lge51:
        JSR __stw
        .word 65526
        JSR __ldw
        .word 65526
        JSR __push
        JSR _f_hx
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl52
        LDA __csp+1
        INC
        STA __csp+1
Lcl52:
        JSR __stw
        .word 65522
        JSR __ldw
        .word 65522
        PHW __ax
        LDA #16
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse53
        JSR _f_nl
        JMP Lend54
Lelse53:
        JSR __ldw
        .word 65524
        PHW __ax
        LDA #16
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        PHW __ax
        JSR __ldw
        .word 65522
        PLW __t
        JSR __add
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        JSR __ldw
        .word 65532
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        JSR _f_nl
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
Lend54:
Lend50:
Lend46:
        JMP Ltop36
Lend37:
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
__and:  LDA __t
        LDB __ax
        AND
        STA __ax
        LDA __t+1
        LDB __ax+1
        AND
        STA __ax+1
        RTS
__shr:  LDA __ax
        STA __n
        LDA __t
        STA __ax
        LDA __t+1
        STA __ax+1
__shr_l: LDA __n
        JZ __shr_e
        LDA __ax+1
        SHR
        STA __ax+1
        LDA __ax
        ROR
        STA __ax
        LDA __n
        DEC
        STA __n
        JMP __shr_l
__shr_e: RTS
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
__s1:    .byte 48,49,50,51,52,53,54,55,56,57,65,66,67,68,69,70,0
_g_HD:
        .word __s1
__s28:    .byte 117,115,97,103,101,58,32,69,88,65,77,73,78,69,32,97,100,100,114,32,32,32,118,105,101,119,47,109,111,100,105,102,121,32,109,101,109,111,114,121,32,40,69,110,116,101,114,61,110,101,120,116,44,32,50,32,104,101,120,61,119,114,105,116,101,44,32,46,61,113,117,105,116,41,0
__s35:    .byte 101,120,97,109,105,110,101,58,32,98,97,100,32,97,100,100,114,101,115,115,0
