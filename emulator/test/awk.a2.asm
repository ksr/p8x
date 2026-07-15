        .org $6A00
        LDA #0
        STA __csp
        LDA #248
        STA __csp+1
        JSR _f_main
        RTS
_f_gmatch:
        JSR __entf
        .word 4
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        LDA #42
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend2
Ltop3:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend4
        JSR __ldw
        .word 4
        JSR __push
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_gmatch
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl7
        LDA __csp+1
        INC
        STA __csp+1
Lcl7:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend6
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_gmatch
Lend6:
        JSR __ldw
        .word 4
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
        JZ Lend9
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_gmatch
Lend9:
        JSR __ldw
        .word 4
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 4
        JMP Ltop3
Lend4:
Lend2:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend11
        JSR __ldw
        .word 4
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
        JMP _ret_gmatch
Lend11:
        JSR __ldw
        .word 4
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
        JZ Lend13
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_gmatch
Lend13:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        LDA #63
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend15
        JSR __ldw
        .word 4
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_gmatch
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl16
        LDA __csp+1
        INC
        STA __csp+1
Lcl16:
        JMP _ret_gmatch
Lend15:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        JSR __stw
        .word 65534
        JSR __ldw
        .word 65534
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
        JZ Land019
        LDA #122
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land019
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande20
Land019:    LDA #0
        STA __ax
        STA __ax+1
Lande20:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend18
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #32
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        JSR __stw
        .word 65534
Lend18:
        JSR __ldw
        .word 4
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65532
        JSR __ldw
        .word 65532
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
        JZ Land023
        LDA #122
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65532
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land023
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande24
Land023:    LDA #0
        STA __ax
        STA __ax+1
Lande24:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend22
        JSR __ldw
        .word 65532
        PHW __ax
        LDA #32
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        JSR __stw
        .word 65532
Lend22:
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65532
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend26
        JSR __ldw
        .word 4
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_gmatch
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl27
        LDA __csp+1
        INC
        STA __csp+1
Lcl27:
        JMP _ret_gmatch
Lend26:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_gmatch
_ret_gmatch:
        JSR __leave
        RTS
_f_de_read:
        JSR __enter
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
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
        JSR $201B
        STA __ax
        LDA #0
        JNC Lbc28
        LDA #1
Lbc28:    STA __ax+1
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_de_read
_ret_de_read:
        JSR __leave
        RTS
_f_de_isfile:
        JSR __enter
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        LDA #12
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
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JMP _ret_de_isfile
_ret_de_isfile:
        JSR __leave
        RTS
_f_de_isdir:
        JSR __enter
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        LDA #12
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
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JMP _ret_de_isdir
_ret_de_isdir:
        JSR __leave
        RTS
_f_de_isdot:
        JSR __enter
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        LDA #0
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
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #46
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JMP _ret_de_isdot
_ret_de_isdot:
        JSR __leave
        RTS
_f_de_len:
        JSR __enter
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        LDA #13
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
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        LDA #14
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
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #0
        STA __ax
        LDA #1
        STA __ax+1
        PLW __t
        JSR __mul
        PLW __t
        JSR __add
        JMP _ret_de_len
_ret_de_len:
        JSR __leave
        RTS
_f_de_lba:
        JSR __enter
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        LDA #15
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
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        LDA #16
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
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PHW __ax
        LDA #0
        STA __ax
        LDA #1
        STA __ax+1
        PLW __t
        JSR __mul
        PLW __t
        JSR __add
        JMP _ret_de_lba
_ret_de_lba:
        JSR __leave
        RTS
_f_de_opendir:
        JSR __enter
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
        JSR $201E
        STA __ax
        LDA #0
        JNC Lbc29
        LDA #1
Lbc29:    STA __ax+1
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_de_opendir
_ret_de_opendir:
        JSR __leave
        RTS
_f_glob_expand:
        JSR __entf
        .word 114
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65438
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65436
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65434
Ltop30:
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65434
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
        JZ Land034
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65434
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
        JZ Land034
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande35
Land034:    LDA #0
        STA __ax
        STA __ax+1
Lande35:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land032
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65434
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
        JZ Land032
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande33
Land032:    LDA #0
        STA __ax
        STA __ax+1
Lande33:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend31
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65434
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
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend37
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65438
        JSR __ldw
        .word 65434
        JSR __stw
        .word 65436
Lend37:
        JSR __ldw
        .word 65434
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65434
        JMP Ltop30
Lend31:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65430
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65456
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65438
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend39
        JSR __ldw
        .word 65436
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65430
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65432
Ltop40:
        JSR __ldw
        .word 65436
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend41
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65456
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65432
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65432
        JMP Ltop40
Lend41:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65456
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
Lend39:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65432
Ltop42:
        JSR __ldw
        .word 65430
        PHW __ax
        JSR __ldw
        .word 65434
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend43
        JSR __ldw
        .word 2
        PHW __ax
        JSR __ldw
        .word 65430
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65520
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65432
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65432
        JSR __ldw
        .word 65430
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65430
        JMP Ltop42
Lend43:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65520
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65438
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse44
        JSR __lea
        .word 65456
        TPA1L
        STA __ax
        TPA1H
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
        JSR $0139
        STA __ax
        LDA #0
        JNC Lbc46
        LDA #1
Lbc46:    STA __ax+1
        JMP Lend45
Lelse44:
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
        JSR $2012
        STA __ax
        LDA #0
        JNC Lbc47
        LDA #1
Lbc47:    STA __ax+1
Lend45:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #250
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $0145
        STA __ax
        LDA #0
        JNC Lbc48
        LDA #1
Lbc48:    STA __ax+1
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65428
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
        JSR $013C
        STA __ax
        LDA #0
        JNC Lbc49
        LDA #1
Lbc49:    STA __ax+1
        JSR __stw
        .word 65422
Ltop50:
        JSR __ldw
        .word 65422
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
        JZ Lend51
        JSR _f_de_read
        JSR _f_de_isdot
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
        JZ Land054
        JSR _f_de_isfile
        LDA __ax
        LDB __ax+1
        OR
        JZ Land054
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande55
Land054:    LDA #0
        STA __ax
        STA __ax+1
Lande55:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend53
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65432
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        LDA #0
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
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        JSR __stw
        .word 65424
Ltop56:
        JSR __ldw
        .word 65432
        PHW __ax
        LDA #12
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Land058
        JSR __ldw
        .word 65424
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
        JZ Land058
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande59
Land058:    LDA #0
        STA __ax
        STA __ax+1
Lande59:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend57
        JSR __ldw
        .word 65424
        PHW __ax
        JSR __lea
        .word 65440
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65432
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65432
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
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
        JSR __stw
        .word 65424
        JMP Ltop56
Lend57:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65440
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __lea
        .word 65440
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        JSR __push
        JSR __lea
        .word 65520
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        JSR __push
        JSR _f_gmatch
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl64
        LDA __csp+1
        INC
        STA __csp+1
Lcl64:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land062
        JSR __ldw
        .word 65428
        PHW __ax
        JSR __ldw
        .word 6
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Land062
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande63
Land062:    LDA #0
        STA __ax
        STA __ax+1
Lande63:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend61
        JSR __ldw
        .word 65428
        PHW __ax
        LDA #64
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        JSR __stw
        .word 65426
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65432
Ltop65:
        JSR __lea
        .word 65456
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
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
        JZ Lend66
        JSR __lea
        .word 65456
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 4
        PHW __ax
        JSR __ldw
        .word 65426
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65426
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65426
        JSR __ldw
        .word 65432
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65432
        JMP Ltop65
Lend66:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65432
Ltop67:
        JSR __lea
        .word 65440
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
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
        JZ Lend68
        JSR __lea
        .word 65440
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65432
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 4
        PHW __ax
        JSR __ldw
        .word 65426
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65426
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65426
        JSR __ldw
        .word 65432
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65432
        JMP Ltop67
Lend68:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 4
        PHW __ax
        JSR __ldw
        .word 65426
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65428
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65428
Lend61:
Lend53:
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
        JSR $013C
        STA __ax
        LDA #0
        JNC Lbc69
        LDA #1
Lbc69:    STA __ax+1
        JSR __stw
        .word 65422
        JMP Ltop50
Lend51:
        JSR __ldw
        .word 65428
        JMP _ret_glob_expand
_ret_glob_expand:
        JSR __leave
        RTS
_f_open_path:
        JSR __entf
        .word 4
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65534
        JSR __ldw
        .word 2
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
        JZ Lend71
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
        JSR $2003
        STA __ax
        LDA #0
        JNC Lbc72
        LDA #1
Lbc72:    STA __ax+1
Ltop73:
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
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
        JZ Lend74
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
        JMP Ltop73
Lend74:
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
        JZ Land077
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
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
        JZ Land077
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande78
Land077:    LDA #0
        STA __ax
        STA __ax+1
Lande78:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend76
        LDA #47
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
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
Lend76:
Lend71:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65532
Ltop79:
        JSR __ldw
        .word 2
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
        JZ Land083
        JSR __ldw
        .word 2
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
        JZ Land083
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande84
Land083:    LDA #0
        STA __ax
        STA __ax+1
Lande84:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land081
        JSR __ldw
        .word 2
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
        JZ Land081
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande82
Land081:    LDA #0
        STA __ax
        STA __ax+1
Lande82:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend80
        JSR __ldw
        .word 2
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
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
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
        JMP Ltop79
Lend80:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_path
        STA __ax
        LDA #>_g_path
        STA __ax+1
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
        JNC Lbc85
        LDA #1
Lbc85:    STA __ax+1
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
        JNC Lbc88
        LDA #1
Lbc88:    STA __ax+1
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
        JZ Lend87
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_open_path
Lend87:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_open_path
_ret_open_path:
        JSR __leave
        RTS
_f_nextc:
        JSR __entf
        .word 4
        MOVW __ax,_g_fromfile
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
        JZ Lend90
        JSR $200C
        STA __ax
        LDA #0
        STA __ax+1
        JNC Lge91
        LDA #255
        STA __ax
        STA __ax+1
Lge91:
        JMP _ret_nextc
Lend90:
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
        JNC Lbc92
        LDA #1
Lbc92:    STA __ax+1
        JSR __stw
        .word 65534
Ltop93:
        JSR __ldw
        .word 65534
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
        JZ Lend94
        MOVW __ax,_g_gnf
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
        JZ Lend96
        LDA #255
        STA __ax
        LDA #255
        STA __ax+1
        JMP _ret_nextc
Lend96:
        MOVW __ax,_g_gidx
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        PHW __ax
        MOVW __ax,_g_gnf
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend98
        LDA #255
        STA __ax
        LDA #255
        STA __ax+1
        JMP _ret_nextc
Lend98:
        MOVW __ax,_g_gidx
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        MOVW _g_gidx,__ax
        LDA #<_g_gfiles
        STA __ax
        LDA #>_g_gfiles
        STA __ax+1
        PHW __ax
        MOVW __ax,_g_gidx
        PHW __ax
        LDA #64
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        PLW __t
        JSR __add
        JSR __stw
        .word 65532
        JSR __ldw
        .word 65532
        JSR __push
        JSR _f_open_path
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl99
        LDA __csp+1
        INC
        STA __csp+1
Lcl99:
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
        JNC Lbc100
        LDA #1
Lbc100:    STA __ax+1
        JSR __stw
        .word 65534
        JMP Ltop93
Lend94:
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        JMP _ret_nextc
_ret_nextc:
        JSR __leave
        RTS
_f_openarg:
        JSR __entf
        .word 4
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_fromfile,__ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_gnf,__ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_gidx,__ax
        JSR __ldw
        .word 2
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
        JNZ Lor1103
        JSR __ldw
        .word 2
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
        JNZ Lor1103
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore104
Lor1103:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore104:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend102
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_openarg
Lend102:
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
        .word 65534
Ltop105:
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
        JZ Land0109
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
        JZ Land0109
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande110
Land0109:    LDA #0
        STA __ax
        STA __ax+1
Lande110:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0107
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
        JZ Land0107
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande108
Land0107:    LDA #0
        STA __ax
        STA __ax+1
Lande108:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend106
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
        LDA #42
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1113
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
        LDA #63
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1113
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore114
Lor1113:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore114:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend112
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65532
Lend112:
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
        JMP Ltop105
Lend106:
        JSR __ldw
        .word 65532
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend116
        LDA #24
        STA __ax
        LDA #0
        STA __ax+1
        JSR __push
        LDA #<_g_gfiles
        STA __ax
        LDA #>_g_gfiles
        STA __ax+1
        JSR __push
        JSR __ldw
        .word 2
        JSR __push
        JSR _f_glob_expand
        LDA __csp
        LDB #6
        ADD
        STA __csp
        JNC Lcl117
        LDA __csp+1
        INC
        STA __csp+1
Lcl117:
        MOVW _g_gnf,__ax
        MOVW __ax,_g_gnf
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
        JZ Lend119
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_openarg
Lend119:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_fromfile,__ax
        LDA #<_g_gfiles
        STA __ax
        LDA #>_g_gfiles
        STA __ax+1
        JSR __push
        JSR _f_open_path
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl120
        LDA __csp+1
        INC
        STA __csp+1
Lcl120:
        JMP _ret_openarg
Lend116:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_fromfile,__ax
        JSR __ldw
        .word 2
        JSR __push
        JSR _f_open_path
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl121
        LDA __csp+1
        INC
        STA __csp+1
Lcl121:
        JMP _ret_openarg
_ret_openarg:
        JSR __leave
        RTS
_f_matchhere:
        JSR __entf
        .word 2
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        JSR __stw
        .word 65534
        JSR __ldw
        .word 65534
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
        JZ Land0124
        JSR __ldw
        .word 2
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
        LDA #42
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0124
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande125
Land0124:    LDA #0
        STA __ax
        STA __ax+1
Lande125:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend123
Ltop126:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend127
        JSR __ldw
        .word 4
        JSR __push
        JSR __ldw
        .word 2
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_matchhere
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl130
        LDA __csp+1
        INC
        STA __csp+1
Lcl130:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend129
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend129:
        JSR __ldw
        .word 4
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
        JZ Lend132
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend132:
        JSR __ldw
        .word 4
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0135
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #46
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0135
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande136
Land0135:    LDA #0
        STA __ax
        STA __ax+1
Lande136:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend134
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend134:
        JSR __ldw
        .word 4
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 4
        JMP Ltop126
Lend127:
Lend123:
        JSR __ldw
        .word 65534
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
        JZ Land0139
        JSR __ldw
        .word 2
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
        LDA #43
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0139
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande140
Land0139:    LDA #0
        STA __ax
        STA __ax+1
Lande140:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend138
        JSR __ldw
        .word 4
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
        JNZ Lor1143
        JSR __ldw
        .word 4
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0145
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #46
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0145
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande146
Land0145:    LDA #0
        STA __ax
        STA __ax+1
Lande146:
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1143
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore144
Lor1143:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore144:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend142
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend142:
        JSR __ldw
        .word 4
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 4
Ltop147:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend148
        JSR __ldw
        .word 4
        JSR __push
        JSR __ldw
        .word 2
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_matchhere
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl151
        LDA __csp+1
        INC
        STA __csp+1
Lcl151:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend150
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend150:
        JSR __ldw
        .word 4
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
        JZ Lend153
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend153:
        JSR __ldw
        .word 4
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0156
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #46
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0156
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande157
Land0156:    LDA #0
        STA __ax
        STA __ax+1
Lande157:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend155
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend155:
        JSR __ldw
        .word 4
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 4
        JMP Ltop147
Lend148:
Lend138:
        JSR __ldw
        .word 65534
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
        JZ Land0160
        JSR __ldw
        .word 2
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
        LDA #63
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0160
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande161
Land0160:    LDA #0
        STA __ax
        STA __ax+1
Lande161:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend159
        JSR __ldw
        .word 4
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
        JZ Land0164
        JSR __ldw
        .word 4
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1166
        JSR __ldw
        .word 65534
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
        JNZ Lor1166
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore167
Lor1166:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore167:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0164
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande165
Land0164:    LDA #0
        STA __ax
        STA __ax+1
Lande165:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend163
        JSR __ldw
        .word 4
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR __ldw
        .word 2
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_matchhere
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl170
        LDA __csp+1
        INC
        STA __csp+1
Lcl170:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend169
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend169:
Lend163:
        JSR __ldw
        .word 4
        JSR __push
        JSR __ldw
        .word 2
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_matchhere
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl171
        LDA __csp+1
        INC
        STA __csp+1
Lcl171:
        JMP _ret_matchhere
Lend159:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend173
        JSR __ldw
        .word 4
        MOVW _g_rend,__ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend173:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        LDA #36
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0176
        JSR __ldw
        .word 2
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
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0176
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande177
Land0176:    LDA #0
        STA __ax
        STA __ax+1
Lande177:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend175
        JSR __ldw
        .word 4
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
        JZ Lend179
        JSR __ldw
        .word 4
        MOVW _g_rend,__ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend179:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
Lend175:
        JSR __ldw
        .word 4
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
        JZ Land0182
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        LDA #46
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1184
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        JSR __ldw
        .word 4
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1184
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore185
Lor1184:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore185:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0182
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande183
Land0182:    LDA #0
        STA __ax
        STA __ax+1
Lande183:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend181
        JSR __ldw
        .word 4
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_matchhere
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl186
        LDA __csp+1
        INC
        STA __csp+1
Lcl186:
        JMP _ret_matchhere
Lend181:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_matchhere
_ret_matchhere:
        JSR __leave
        RTS
_f_match:
        JSR __enter
        JSR __ldw
        .word 2
        PHW __ax
        LDA #0
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
        LDA #94
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend188
        JSR __ldw
        .word 4
        JSR __push
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __push
        JSR _f_matchhere
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl189
        LDA __csp+1
        INC
        STA __csp+1
Lcl189:
        JMP _ret_match
Lend188:
Ltop190:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend191
        JSR __ldw
        .word 4
        JSR __push
        JSR __ldw
        .word 2
        JSR __push
        JSR _f_matchhere
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl194
        LDA __csp+1
        INC
        STA __csp+1
Lcl194:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend193
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_match
Lend193:
        JSR __ldw
        .word 4
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
        JZ Lend196
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_match
Lend196:
        JSR __ldw
        .word 4
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 4
        JMP Ltop190
Lend191:
_ret_match:
        JSR __leave
        RTS
_f_readrec:
        JSR __entf
        .word 4
        JSR _f_nextc
        JSR __stw
        .word 65534
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #255
        STA __ax
        LDA #255
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend198
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_readrec
Lend198:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65532
Ltop199:
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #255
        STA __ax
        LDA #255
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0201
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0201
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande202
Land0201:    LDA #0
        STA __ax
        STA __ax+1
Lande202:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend200
        JSR __ldw
        .word 65534
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
        JZ Lend204
        JSR __ldw
        .word 65532
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend206
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65532
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
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
Lend206:
Lend204:
        JSR _f_nextc
        JSR __stw
        .word 65534
        JMP Ltop199
Lend200:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65532
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_readrec
_ret_readrec:
        JSR __leave
        RTS
_f_split:
        JSR __entf
        .word 8
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
        .word 65534
        MOVW __ax,_g_sepc
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
        JZ Lelse207
Ltop209:
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        JZ Lend210
Ltop211:
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        LDA #32
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1213
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        LDA #9
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1213
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore214
Lor1213:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore214:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend212
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
        JMP Ltop211
Lend212:
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        JZ Lend216
        JSR __ldw
        .word 65534
        JSR __stw
        .word 65530
Ltop217:
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        JZ Land0221
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        JZ Land0221
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande222
Land0221:    LDA #0
        STA __ax
        STA __ax+1
Lande222:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0219
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        LDA #9
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0219
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande220
Land0219:    LDA #0
        STA __ax
        STA __ax+1
Lande220:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend218
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
        JMP Ltop217
Lend218:
        JSR __ldw
        .word 65532
        PHW __ax
        LDA #40
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend224
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #<_g_fstart
        STA __ax
        LDA #>_g_fstart
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65532
        LDA __ax
        SHL
        STA __ax
        LDA __ax+1
        ROL
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)+
        LDA __t+1
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65530
        PLW __t
        JSR __sub
        PHW __ax
        LDA #<_g_flen
        STA __ax
        LDA #>_g_flen
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65532
        LDA __ax
        SHL
        STA __ax
        LDA __ax+1
        ROL
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)+
        LDA __t+1
        STA (P1)
        MOVW __ax,__t
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
Lend224:
Lend216:
        JMP Ltop209
Lend210:
        JMP Lend208
Lelse207:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65530
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65534
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65528
Ltop225:
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
        JZ Lend226
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse227
        JSR __ldw
        .word 65532
        PHW __ax
        LDA #40
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend230
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #<_g_fstart
        STA __ax
        LDA #>_g_fstart
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65532
        LDA __ax
        SHL
        STA __ax
        LDA __ax+1
        ROL
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)+
        LDA __t+1
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65530
        PLW __t
        JSR __sub
        PHW __ax
        LDA #<_g_flen
        STA __ax
        LDA #>_g_flen
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65532
        LDA __ax
        SHL
        STA __ax
        LDA __ax+1
        ROL
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)+
        LDA __t+1
        STA (P1)
        MOVW __ax,__t
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
Lend230:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65528
        JMP Lend228
Lelse227:
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        MOVW __ax,_g_sepc
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend232
        JSR __ldw
        .word 65532
        PHW __ax
        LDA #40
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend234
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #<_g_fstart
        STA __ax
        LDA #>_g_fstart
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65532
        LDA __ax
        SHL
        STA __ax
        LDA __ax+1
        ROL
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)+
        LDA __t+1
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65530
        PLW __t
        JSR __sub
        PHW __ax
        LDA #<_g_flen
        STA __ax
        LDA #>_g_flen
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65532
        LDA __ax
        SHL
        STA __ax
        LDA __ax+1
        ROL
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)+
        LDA __t+1
        STA (P1)
        MOVW __ax,__t
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
Lend234:
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
        .word 65530
Lend232:
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
Lend228:
        JMP Ltop225
Lend226:
Lend208:
        JSR __ldw
        .word 65532
        MOVW _g_nf,__ax
        JSR __ldw
        .word 65532
        JMP _ret_split
_ret_split:
        JSR __leave
        RTS
_f_pfield:
        JSR __entf
        .word 2
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
        JZ Lelse235
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65534
Ltop237:
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        JZ Lend238
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
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
        JMP Ltop237
Lend238:
        JMP Lend236
Lelse235:
        MOVW __ax,_g_nf
        PHW __ax
        JSR __ldw
        .word 2
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend240
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65534
Ltop241:
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #<_g_flen
        STA __ax
        LDA #>_g_flen
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        LDA __ax
        SHL
        STA __ax
        LDA __ax+1
        ROL
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)+
        STA __ax
        LDA (P1)
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend242
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
        PHW __ax
        LDA #<_g_fstart
        STA __ax
        LDA #>_g_fstart
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        LDA __ax
        SHL
        STA __ax
        LDA __ax+1
        ROL
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)+
        STA __ax
        LDA (P1)
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65534
        PLW __t
        JSR __add
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
        JMP Ltop241
Lend242:
Lend240:
Lend236:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_pfield
_ret_pfield:
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
        JZ Lend244
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
Lend244:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65526
Ltop245:
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
        JZ Lend246
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
        JMP Ltop245
Lend246:
Ltop247:
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
        JZ Lend248
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
        JMP Ltop247
Lend248:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_pnum
_ret_pnum:
        JSR __leave
        RTS
_f_run_action:
        JSR __entf
        .word 6
        LDA #<_g_act
        STA __ax
        LDA #>_g_act
        STA __ax+1
        JSR __stw
        .word 65534
Ltop249:
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
        JZ Lend250
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
        JMP Ltop249
Lend250:
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
        JZ Lend252
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __push
        JSR _f_pfield
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl253
        LDA __csp+1
        INC
        STA __csp+1
Lcl253:
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
        JMP _ret_run_action
Lend252:
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #0
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
        LDA #112
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0262
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
        LDA #114
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0262
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande263
Land0262:    LDA #0
        STA __ax
        STA __ax+1
Lande263:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0260
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #2
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
        LDA #105
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0260
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande261
Land0260:    LDA #0
        STA __ax
        STA __ax+1
Lande261:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0258
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #3
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
        LDA #110
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0258
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande259
Land0258:    LDA #0
        STA __ax
        STA __ax+1
Lande259:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0256
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #4
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
        LDA #116
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0256
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande257
Land0256:    LDA #0
        STA __ax
        STA __ax+1
Lande257:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend255
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #5
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
Lend255:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65532
Ltop264:
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
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend265
Ltop266:
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
        JZ Lend267
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
        JMP Ltop266
Lend267:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #44
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend269
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
Ltop270:
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
        JZ Lend271
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
        JMP Ltop270
Lend271:
Lend269:
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
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend273
        JSR __ldw
        .word 65532
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
        JZ Lend275
        LDA #32
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        JSR $2009
Lend275:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65532
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #34
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse276
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
Ltop278:
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
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0280
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #34
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0280
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande281
Land0280:    LDA #0
        STA __ax
        STA __ax+1
Lande281:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend279
        JSR __ldw
        .word 65534
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
        JMP Ltop278
Lend279:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #34
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend283
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
Lend283:
        JMP Lend277
Lelse276:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #36
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse284
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
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #78
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0288
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
        LDA #70
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0288
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande289
Land0288:    LDA #0
        STA __ax
        STA __ax+1
Lande289:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse286
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
        MOVW __ax,_g_nf
        JSR __push
        JSR _f_pfield
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl290
        LDA __csp+1
        INC
        STA __csp+1
Lcl290:
        JMP Lend287
Lelse286:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65530
Ltop291:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
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
        JZ Land0293
        LDA #57
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0293
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande294
Land0293:    LDA #0
        STA __ax
        STA __ax+1
Lande294:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend292
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #10
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        PHW __ax
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #48
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __sub
        PLW __t
        JSR __add
        JSR __stw
        .word 65530
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
        JMP Ltop291
Lend292:
        JSR __ldw
        .word 65530
        JSR __push
        JSR _f_pfield
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl295
        LDA __csp+1
        INC
        STA __csp+1
Lcl295:
Lend287:
        JMP Lend285
Lelse284:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #78
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0298
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
        LDA #82
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0298
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande299
Land0298:    LDA #0
        STA __ax
        STA __ax+1
Lande299:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse296
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
        MOVW __ax,_g_nr
        JSR __push
        JSR _f_pnum
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl300
        LDA __csp+1
        INC
        STA __csp+1
Lcl300:
        JMP Lend297
Lelse296:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #78
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0303
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
        LDA #70
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0303
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande304
Land0303:    LDA #0
        STA __ax
        STA __ax+1
Lande304:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse301
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
        MOVW __ax,_g_nf
        JSR __push
        JSR _f_pnum
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl305
        LDA __csp+1
        INC
        STA __csp+1
Lcl305:
        JMP Lend302
Lelse301:
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
Lend302:
Lend297:
Lend285:
Lend277:
Lend273:
        JMP Ltop264
Lend265:
        JSR __ldw
        .word 65532
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend307
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __push
        JSR _f_pfield
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl308
        LDA __csp+1
        INC
        STA __csp+1
Lcl308:
Lend307:
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
        JMP _ret_run_action
_ret_run_action:
        JSR __leave
        RTS
_f_parse_prog:
        JSR __entf
        .word 2
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_hasre,__ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_re
        STA __ax
        LDA #>_g_re
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_act
        STA __ax
        LDA #>_g_act
        STA __ax+1
        PHW __ax
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
Ltop309:
        JSR __ldw
        .word 2
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
        JZ Lend310
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 2
        JMP Ltop309
Lend310:
        JSR __ldw
        .word 2
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
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend312
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 2
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65534
Ltop313:
        JSR __ldw
        .word 2
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
        JZ Land0315
        JSR __ldw
        .word 2
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
        JZ Land0315
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande316
Land0315:    LDA #0
        STA __ax
        STA __ax+1
Lande316:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend314
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #79
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend318
        JSR __ldw
        .word 2
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_re
        STA __ax
        LDA #>_g_re
        STA __ax+1
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
Lend318:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 2
        JMP Ltop313
Lend314:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_re
        STA __ax
        LDA #>_g_re
        STA __ax+1
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
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_hasre,__ax
        JSR __ldw
        .word 2
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
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend320
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 2
Lend320:
Lend312:
Ltop321:
        JSR __ldw
        .word 2
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
        JZ Lend322
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 2
        JMP Ltop321
Lend322:
        JSR __ldw
        .word 2
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #123
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend324
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 2
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65534
Ltop325:
        JSR __ldw
        .word 2
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
        JZ Land0327
        JSR __ldw
        .word 2
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #125
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0327
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande328
Land0327:    LDA #0
        STA __ax
        STA __ax+1
Lande328:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend326
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #119
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend330
        JSR __ldw
        .word 2
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_act
        STA __ax
        LDA #>_g_act
        STA __ax+1
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
Lend330:
        JSR __ldw
        .word 2
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 2
        JMP Ltop325
Lend326:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_act
        STA __ax
        LDA #>_g_act
        STA __ax+1
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
Lend324:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_parse_prog
_ret_parse_prog:
        JSR __leave
        RTS
_f_main:
        JSR __entf
        .word 136
        TPA2L
        STA __ax
        TPA2H
        STA __ax+1
        JSR __stw
        .word 65534
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_sepc,__ax
Ltop331:
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
        JZ Lend332
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
        JMP Ltop331
Lend332:
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
        JZ Land0335
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
        JNZ Lor1337
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
        JNZ Lor1337
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore338
Lor1337:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore338:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0335
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande336
Land0335:    LDA #0
        STA __ax
        STA __ax+1
Lande336:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend334
        LDA #<__s339
        STA __ax
        LDA #>__s339
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
Lend334:
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
        JZ Land0342
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
        LDA #70
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0342
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande343
Land0342:    LDA #0
        STA __ax
        STA __ax+1
Lande343:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend341
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
Ltop344:
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
        JZ Lend345
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
        JMP Ltop344
Lend345:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_sepc,__ax
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
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend347
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
Lend347:
Ltop348:
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
        JZ Lend349
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
        JMP Ltop348
Lend349:
Lend341:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65404
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #39
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1352
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #34
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1352
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore353
Lor1352:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore353:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse350
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65402
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
Ltop354:
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
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0356
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65402
        PLW __t
        JSR __eq
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0356
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande357
Land0356:    LDA #0
        STA __ax
        STA __ax+1
Lande357:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend355
        JSR __ldw
        .word 65404
        PHW __ax
        LDA #127
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend359
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65406
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65404
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65404
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65404
Lend359:
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
        JMP Ltop354
Lend355:
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65402
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend361
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
Lend361:
        JMP Lend351
Lelse350:
Ltop362:
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
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0366
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
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0366
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande367
Land0366:    LDA #0
        STA __ax
        STA __ax+1
Lande367:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0364
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
        JSR __not
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0364
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande365
Land0364:    LDA #0
        STA __ax
        STA __ax+1
Lande365:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend363
        JSR __ldw
        .word 65404
        PHW __ax
        LDA #127
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend369
        JSR __ldw
        .word 65534
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65406
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65404
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65404
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65404
Lend369:
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
        JMP Ltop362
Lend363:
Lend351:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65406
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65404
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __lea
        .word 65406
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        JSR __push
        JSR _f_parse_prog
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl370
        LDA __csp+1
        INC
        STA __csp+1
Lcl370:
Ltop371:
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
        JZ Lend372
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
        JMP Ltop371
Lend372:
        JSR __ldw
        .word 65534
        JSR __push
        JSR _f_openarg
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl373
        LDA __csp+1
        INC
        STA __csp+1
Lcl373:
        JSR __stw
        .word 65400
        JSR __ldw
        .word 65400
        PHW __ax
        LDA #2
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend375
        LDA #<__s376
        STA __ax
        LDA #>__s376
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
Lend375:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        MOVW _g_nr,__ax
Ltop377:
        JSR _f_readrec
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend378
        MOVW __ax,_g_nr
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        MOVW _g_nr,__ax
        JSR _f_split
        MOVW __ax,_g_hasre
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
        JNZ Lor1381
        LDA #<_g_line
        STA __ax
        LDA #>_g_line
        STA __ax+1
        JSR __push
        LDA #<_g_re
        STA __ax
        LDA #>_g_re
        STA __ax+1
        JSR __push
        JSR _f_match
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl383
        LDA __csp+1
        INC
        STA __csp+1
Lcl383:
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor1381
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore382
Lor1381:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore382:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend380
        JSR _f_run_action
Lend380:
        JMP Ltop377
Lend378:
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
_g_de:    .fill 18
_g_path:    .fill 80
_g_fromfile:    .fill 2
_g_gfiles:    .fill 1536
_g_gnf:    .fill 2
_g_gidx:    .fill 2
_g_rend:    .fill 2
_g_line:    .fill 256
_g_fstart:    .fill 80
_g_flen:    .fill 80
_g_nf:    .fill 2
_g_nr:    .fill 2
_g_sepc:    .fill 2
_g_re:    .fill 80
_g_hasre:    .fill 2
_g_act:    .fill 120
__s339:    .byte 117,115,97,103,101,58,32,97,119,107,32,91,45,70,32,99,93,32,39,91,47,114,101,47,93,123,112,114,105,110,116,32,105,116,101,109,115,125,39,32,91,102,105,108,101,93,32,32,32,105,116,101,109,115,58,32,36,48,32,36,78,32,78,70,32,78,82,32,34,115,116,114,34,0
__s376:    .byte 97,119,107,58,32,110,111,116,32,102,111,117,110,100,0
__dr:   .fill 2
