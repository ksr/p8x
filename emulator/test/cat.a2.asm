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
_f_catpath:
        JSR __entf
        .word 6
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
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_catpath
Lend87:
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
        JNC Lbc89
        LDA #1
Lbc89:    STA __ax+1
        JSR __stw
        .word 65530
Ltop90:
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
        JZ Lend91
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        LDA __ax
        JSR $2009
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
        .word 65530
        JMP Ltop90
Lend91:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_catpath
_ret_catpath:
        JSR __leave
        RTS
_f_main:
        JSR __entf
        .word 12
        TPA2L
        STA __ax
        TPA2H
        STA __ax+1
        JSR __stw
        .word 65534
Ltop93:
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
        JZ Lend94
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
        JMP Ltop93
Lend94:
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
        JZ Land097
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
        JNZ Lor199
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
        JNZ Lor199
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore100
Lor199:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore100:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land097
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande98
Land097:    LDA #0
        STA __ax
        STA __ax+1
Lande98:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend96
        LDA #<__s101
        STA __ax
        LDA #>__s101
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
Lend96:
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
        JNZ Lor1104
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
        JNZ Lor1104
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore105
Lor1104:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore105:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend103
        JSR $200C
        STA __ax
        LDA #0
        STA __ax+1
        JNC Lge106
        LDA #255
        STA __ax
        STA __ax+1
Lge106:
        JSR __stw
        .word 65528
Ltop107:
        JSR __ldw
        .word 65528
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
        JZ Lend108
        JSR __ldw
        .word 65528
        LDA __ax
        JSR $2009
        JSR $200C
        STA __ax
        LDA #0
        STA __ax+1
        JNC Lge109
        LDA #255
        STA __ax
        STA __ax+1
Lge109:
        JSR __stw
        .word 65528
        JMP Ltop107
Lend108:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend103:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65526
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65530
Ltop110:
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65530
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
        JZ Land0114
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65530
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
        JZ Land0114
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande115
Land0114:    LDA #0
        STA __ax
        STA __ax+1
Lande115:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0112
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65530
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
        JZ Land0112
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande113
Land0112:    LDA #0
        STA __ax
        STA __ax+1
Lande113:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend111
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65530
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
        JNZ Lor1118
        JSR __ldw
        .word 65534
        PHW __ax
        JSR __ldw
        .word 65530
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
        JNZ Lor1118
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore119
Lor1118:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore119:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend117
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65526
Lend117:
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65530
        JMP Ltop110
Lend111:
        JSR __ldw
        .word 65526
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend121
        LDA #24
        STA __ax
        LDA #0
        STA __ax+1
        JSR __push
        LDA #<_g_gbuf
        STA __ax
        LDA #>_g_gbuf
        STA __ax+1
        JSR __push
        JSR __ldw
        .word 65534
        JSR __push
        JSR _f_glob_expand
        LDA __csp
        LDB #6
        ADD
        STA __csp
        JNC Lcl122
        LDA __csp+1
        INC
        STA __csp+1
Lcl122:
        JSR __stw
        .word 65524
        LDA #<_g_gbuf
        STA __ax
        LDA #>_g_gbuf
        STA __ax+1
        JSR __stw
        .word 65532
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65530
Ltop123:
        JSR __ldw
        .word 65530
        PHW __ax
        JSR __ldw
        .word 65524
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend124
        JSR __ldw
        .word 65532
        JSR __push
        JSR _f_catpath
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl125
        LDA __csp+1
        INC
        STA __csp+1
Lcl125:
        JSR __ldw
        .word 65532
        PHW __ax
        LDA #64
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65532
        JSR __ldw
        .word 65530
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65530
        JMP Ltop123
Lend124:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend121:
        JSR __ldw
        .word 65534
        JSR __push
        JSR _f_catpath
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl128
        LDA __csp+1
        INC
        STA __csp+1
Lcl128:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend127
        LDA #<__s129
        STA __ax
        LDA #>__s129
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
Lend127:
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
_g_gbuf:    .fill 1536
__s101:    .byte 117,115,97,103,101,58,32,67,65,84,32,91,102,105,108,101,124,103,108,111,98,93,32,32,32,112,114,105,110,116,32,102,105,108,101,40,115,41,44,32,111,114,32,102,105,108,116,101,114,32,115,116,100,105,110,32,105,102,32,110,111,110,101,0
__s129:    .byte 99,97,116,58,32,110,111,116,32,102,111,117,110,100,0
