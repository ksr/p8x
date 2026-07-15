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
        JNC Lbc16
        LDA #1
Lbc16:    STA __ax+1
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
        JNC Lbc17
        LDA #1
Lbc17:    STA __ax+1
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_de_opendir
_ret_de_opendir:
        JSR __leave
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
        JZ Lend19
Ltop20:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend21
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
        JNC Lcl24
        LDA __csp+1
        INC
        STA __csp+1
Lcl24:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend23
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_gmatch
Lend23:
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
        JZ Lend26
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_gmatch
Lend26:
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
        JMP Ltop20
Lend21:
Lend19:
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
        JZ Lend28
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
Lend28:
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
        JZ Lend30
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_gmatch
Lend30:
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
        JZ Lend32
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
        JNC Lcl33
        LDA __csp+1
        INC
        STA __csp+1
Lcl33:
        JMP _ret_gmatch
Lend32:
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
        JZ Land036
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
        JZ Lend35
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
Lend35:
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
        JZ Land040
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
        JZ Land040
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande41
Land040:    LDA #0
        STA __ax
        STA __ax+1
Lande41:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend39
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
Lend39:
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
        JZ Lend43
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
        JNC Lcl44
        LDA __csp+1
        INC
        STA __csp+1
Lcl44:
        JMP _ret_gmatch
Lend43:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_gmatch
_ret_gmatch:
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
Ltop45:
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
        JZ Land049
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
        JZ Land049
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande50
Land049:    LDA #0
        STA __ax
        STA __ax+1
Lande50:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land047
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
        JZ Land047
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande48
Land047:    LDA #0
        STA __ax
        STA __ax+1
Lande48:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend46
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
        JZ Lend52
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
Lend52:
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
        JMP Ltop45
Lend46:
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
        JZ Lend54
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
Ltop55:
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
        JZ Lend56
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
        JMP Ltop55
Lend56:
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
Lend54:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65432
Ltop57:
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
        JZ Lend58
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
        JMP Ltop57
Lend58:
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
        JZ Lelse59
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
        JNC Lbc61
        LDA #1
Lbc61:    STA __ax+1
        JMP Lend60
Lelse59:
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
        JNC Lbc62
        LDA #1
Lbc62:    STA __ax+1
Lend60:
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
        JNC Lbc63
        LDA #1
Lbc63:    STA __ax+1
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
        JNC Lbc64
        LDA #1
Lbc64:    STA __ax+1
        JSR __stw
        .word 65422
Ltop65:
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
        JZ Lend66
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
        JZ Land069
        JSR _f_de_isfile
        LDA __ax
        LDB __ax+1
        OR
        JZ Land069
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande70
Land069:    LDA #0
        STA __ax
        STA __ax+1
Lande70:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend68
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
Ltop71:
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
        JZ Land073
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
        JZ Land073
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande74
Land073:    LDA #0
        STA __ax
        STA __ax+1
Lande74:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend72
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
        JMP Ltop71
Lend72:
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
        JNC Lcl79
        LDA __csp+1
        INC
        STA __csp+1
Lcl79:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land077
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
Ltop80:
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
        JZ Lend81
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
        JMP Ltop80
Lend81:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65432
Ltop82:
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
        JZ Lend83
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
        JMP Ltop82
Lend83:
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
Lend76:
Lend68:
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
        JNC Lbc84
        LDA #1
Lbc84:    STA __ax+1
        JSR __stw
        .word 65422
        JMP Ltop65
Lend66:
        JSR __ldw
        .word 65428
        JMP _ret_glob_expand
_ret_glob_expand:
        JSR __leave
        RTS
_f_scopy:
        JSR __entf
        .word 2
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65534
Ltop85:
        JSR __ldw
        .word 4
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
        JZ Lend86
        JSR __ldw
        .word 4
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
        JMP Ltop85
Lend86:
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
        .word 65534
        JMP _ret_scopy
_ret_scopy:
        JSR __leave
        RTS
_f_joinp:
        JSR __entf
        .word 4
        JSR __ldw
        .word 4
        JSR __push
        JSR __ldw
        .word 2
        JSR __push
        JSR _f_scopy
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl87
        LDA __csp+1
        INC
        STA __csp+1
Lcl87:
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
        LDA __ax
        LDB __ax+1
        OR
        JNZ Lor190
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
        JNZ Lor190
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore91
Lor190:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore91:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend89
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
Lend89:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65532
Ltop92:
        JSR __ldw
        .word 6
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
        JZ Lend93
        JSR __ldw
        .word 6
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
        JMP Ltop92
Lend93:
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
        .word 65534
        JMP _ret_joinp
_ret_joinp:
        JSR __leave
        RTS
_f_copy_file:
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
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $0133
        STA __ax
        LDA #0
        JNC Lbc94
        LDA #1
Lbc94:    STA __ax+1
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
        JNC Lbc97
        LDA #1
Lbc97:    STA __ax+1
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
        JZ Lend96
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_copy_file
Lend96:
        JSR __ldw
        .word 4
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
        JNC Lbc98
        LDA #1
Lbc98:    STA __ax+1
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
        JSR $012A
        STA __ax
        LDA #0
        JNC Lbc99
        LDA #1
Lbc99:    STA __ax+1
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
Ltop101:
        JSR __ldw
        .word 65534
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
        JZ Lend102
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65534
        PHW __ax
        LDA #255
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __and
        PLW __t
        LDA __t
        TAP1L
        LDA __t+1
        TAP1H
        LDA __ax
        JSR $012D
        STA __ax
        LDA #0
        JNC Lbc103
        LDA #1
Lbc103:    STA __ax+1
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
        JNC Lbc104
        LDA #1
Lbc104:    STA __ax+1
        JSR __stw
        .word 65534
        JMP Ltop101
Lend102:
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
        JSR $0130
        STA __ax
        LDA #0
        JNC Lbc105
        LDA #1
Lbc105:    STA __ax+1
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_copy_file
_ret_copy_file:
        JSR __leave
        RTS
_f_isdir:
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
        JSR $0139
        STA __ax
        LDA #0
        JNC Lbc108
        LDA #1
Lbc108:    STA __ax+1
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
        JZ Lend107
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_isdir
Lend107:
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_isdir
_ret_isdir:
        JSR __leave
        RTS
_f_copy_tree:
        JSR __entf
        .word 504
        JSR __ldw
        .word 2
        JSR __push
        JSR __lea
        .word 65456
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        JSR __push
        JSR _f_scopy
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl109
        LDA __csp+1
        INC
        STA __csp+1
Lcl109:
        JSR __ldw
        .word 4
        JSR __push
        JSR __lea
        .word 65376
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        JSR __push
        JSR _f_scopy
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl110
        LDA __csp+1
        INC
        STA __csp+1
Lcl110:
        JSR __lea
        .word 65376
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
        JSR $2021
        STA __ax
        LDA #0
        JNC Lbc111
        LDA #1
Lbc111:    STA __ax+1
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65038
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
        JNC Lbc112
        LDA #1
Lbc112:    STA __ax+1
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #224
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
        JNC Lbc113
        LDA #1
Lbc113:    STA __ax+1
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
        JNC Lbc114
        LDA #1
Lbc114:    STA __ax+1
        JSR __stw
        .word 65032
Ltop115:
        JSR __ldw
        .word 65032
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
        JZ Lend116
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
        JZ Land0119
        JSR __ldw
        .word 65038
        PHW __ax
        LDA #24
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0119
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande120
Land0119:    LDA #0
        STA __ax
        STA __ax+1
Lande120:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend118
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65034
Ltop121:
        JSR __ldw
        .word 65034
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
        JZ Land0123
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65034
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
        JZ Land0123
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande124
Land0123:    LDA #0
        STA __ax
        STA __ax+1
Lande124:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend122
        LDA #<_g_de
        STA __ax
        LDA #>_g_de
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65034
        PLW __t
        JSR __add
        LPW1 __ax
        LDA (P1)
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65088
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65038
        PHW __ax
        LDA #12
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        PHW __ax
        JSR __ldw
        .word 65034
        PLW __t
        JSR __add
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65034
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65034
        JMP Ltop121
Lend122:
Ltop125:
        JSR __ldw
        .word 65034
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
        JZ Lend126
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        JSR __lea
        .word 65088
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65038
        PHW __ax
        LDA #12
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        PHW __ax
        JSR __ldw
        .word 65034
        PLW __t
        JSR __add
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
        JSR __ldw
        .word 65034
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65034
        JMP Ltop125
Lend126:
        JSR _f_de_isdir
        PHW __ax
        JSR __lea
        .word 65040
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65038
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
        .word 65038
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65038
Lend118:
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
        JNC Lbc127
        LDA #1
Lbc127:    STA __ax+1
        JSR __stw
        .word 65032
        JMP Ltop115
Lend116:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65036
Ltop128:
        JSR __ldw
        .word 65036
        PHW __ax
        JSR __ldw
        .word 65038
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend129
        JSR __lea
        .word 65088
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65036
        PHW __ax
        LDA #12
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        PLW __t
        JSR __add
        JSR __push
        JSR __lea
        .word 65456
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        JSR __push
        LDA #<_g_jsrc
        STA __ax
        LDA #>_g_jsrc
        STA __ax+1
        JSR __push
        JSR _f_joinp
        LDA __csp
        LDB #6
        ADD
        STA __csp
        JNC Lcl130
        LDA __csp+1
        INC
        STA __csp+1
Lcl130:
        JSR __lea
        .word 65088
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65036
        PHW __ax
        LDA #12
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __mul
        PLW __t
        JSR __add
        JSR __push
        JSR __lea
        .word 65376
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        JSR __push
        LDA #<_g_jdst
        STA __ax
        LDA #>_g_jdst
        STA __ax+1
        JSR __push
        JSR _f_joinp
        LDA __csp
        LDB #6
        ADD
        STA __csp
        JNC Lcl131
        LDA __csp+1
        INC
        STA __csp+1
Lcl131:
        JSR __lea
        .word 65040
        TPA1L
        STA __ax
        TPA1H
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65036
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
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse132
        LDA #<_g_jdst
        STA __ax
        LDA #>_g_jdst
        STA __ax+1
        JSR __push
        LDA #<_g_jsrc
        STA __ax
        LDA #>_g_jsrc
        STA __ax+1
        JSR __push
        JSR _f_copy_tree
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl134
        LDA __csp+1
        INC
        STA __csp+1
Lcl134:
        JMP Lend133
Lelse132:
        LDA #<_g_jdst
        STA __ax
        LDA #>_g_jdst
        STA __ax+1
        JSR __push
        LDA #<_g_jsrc
        STA __ax
        LDA #>_g_jsrc
        STA __ax+1
        JSR __push
        JSR _f_copy_file
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl135
        LDA __csp+1
        INC
        STA __csp+1
Lcl135:
Lend133:
        JSR __ldw
        .word 65036
        PHW __ax
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __add
        JSR __stw
        .word 65036
        JMP Ltop128
Lend129:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_copy_tree
_ret_copy_tree:
        JSR __leave
        RTS
_f_main:
        JSR __entf
        .word 16
        TPA2L
        STA __ax
        TPA2H
        STA __ax+1
        JSR __stw
        .word 65534
Ltop136:
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
        JZ Lend137
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
        JMP Ltop136
Lend137:
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
        JZ Land0140
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
        JNZ Lor1142
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
        JNZ Lor1142
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore143
Lor1142:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore143:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0140
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande141
Land0140:    LDA #0
        STA __ax
        STA __ax+1
Lande141:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend139
        LDA #<__s144
        STA __ax
        LDA #>__s144
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
Lend139:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65520
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
        JZ Land0147
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
        JNZ Lor1149
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
        JNZ Lor1149
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore150
Lor1149:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore150:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0147
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande148
Land0147:    LDA #0
        STA __ax
        STA __ax+1
Lande148:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend146
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65520
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
Ltop151:
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
        JZ Lend152
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
        JMP Ltop151
Lend152:
Lend146:
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
        JNZ Lor1155
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
        JNZ Lor1155
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore156
Lor1155:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore156:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend154
        LDA #<__s157
        STA __ax
        LDA #>__s157
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
Lend154:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65524
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65530
Ltop158:
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
        JZ Land0162
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
        JZ Land0162
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande163
Land0162:    LDA #0
        STA __ax
        STA __ax+1
Lande163:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0160
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
        JNZ Lor1166
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
        JZ Lend165
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65524
Lend165:
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
        LDA #<_g_patw
        STA __ax
        LDA #>_g_patw
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65530
        PLW __t
        JSR __add
        LPW1 __ax
        PLW __t
        LDA __t
        STA (P1)
        MOVW __ax,__t
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
        JMP Ltop158
Lend159:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        PHW __ax
        LDA #<_g_patw
        STA __ax
        LDA #>_g_patw
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65530
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
        JSR __ldw
        .word 65530
        PLW __t
        JSR __add
        JSR __stw
        .word 65534
Ltop168:
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
        JZ Lend169
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
        JMP Ltop168
Lend169:
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
        JNZ Lor1172
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
        JNZ Lor1172
        LDA #0
        STA __ax
        STA __ax+1
        JMP Lore173
Lor1172:    LDA #1
        STA __ax
        LDA #0
        STA __ax+1
Lore173:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend171
        LDA #<__s157
        STA __ax
        LDA #>__s157
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
Lend171:
        JSR __ldw
        .word 65534
        JSR __push
        LDA #<_g_dst
        STA __ax
        LDA #>_g_dst
        STA __ax+1
        JSR __push
        JSR _f_abspath
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl174
        LDA __csp+1
        INC
        STA __csp+1
Lcl174:
        JSR __ldw
        .word 65524
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
        JZ Lend176
        LDA #<_g_patw
        STA __ax
        LDA #>_g_patw
        STA __ax+1
        JSR __push
        LDA #<_g_src
        STA __ax
        LDA #>_g_src
        STA __ax+1
        JSR __push
        JSR _f_abspath
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl177
        LDA __csp+1
        INC
        STA __csp+1
Lcl177:
        JSR __ldw
        .word 65520
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0180
        LDA #<_g_src
        STA __ax
        LDA #>_g_src
        STA __ax+1
        JSR __push
        JSR _f_isdir
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl182
        LDA __csp+1
        INC
        STA __csp+1
Lcl182:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0180
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande181
Land0180:    LDA #0
        STA __ax
        STA __ax+1
Lande181:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend179
        LDA #<_g_dst
        STA __ax
        LDA #>_g_dst
        STA __ax+1
        JSR __push
        LDA #<_g_src
        STA __ax
        LDA #>_g_src
        STA __ax+1
        JSR __push
        JSR _f_copy_tree
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl183
        LDA __csp+1
        INC
        STA __csp+1
Lcl183:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend179:
        LDA #<_g_dst
        STA __ax
        LDA #>_g_dst
        STA __ax+1
        JSR __push
        LDA #<_g_src
        STA __ax
        LDA #>_g_src
        STA __ax+1
        JSR __push
        JSR _f_copy_file
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl186
        LDA __csp+1
        INC
        STA __csp+1
Lcl186:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend185
        LDA #<__s187
        STA __ax
        LDA #>__s187
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
Lend185:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JMP _ret_main
Lend176:
        LDA #<_g_dst
        STA __ax
        LDA #>_g_dst
        STA __ax+1
        JSR __push
        JSR _f_isdir
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl190
        LDA __csp+1
        INC
        STA __csp+1
Lcl190:
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
        JZ Lend189
        LDA #<__s191
        STA __ax
        LDA #>__s191
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
Lend189:
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
        LDA #<_g_patw
        STA __ax
        LDA #>_g_patw
        STA __ax+1
        JSR __push
        JSR _f_glob_expand
        LDA __csp
        LDB #6
        ADD
        STA __csp
        JNC Lcl192
        LDA __csp+1
        INC
        STA __csp+1
Lcl192:
        JSR __stw
        .word 65522
        JSR __ldw
        .word 65522
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
        JZ Lend194
        LDA #<__s195
        STA __ax
        LDA #>__s195
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
Lend194:
        LDA #0
        STA __ax
        LDA #0
        STA __ax+1
        JSR __stw
        .word 65530
Ltop196:
        JSR __ldw
        .word 65530
        PHW __ax
        JSR __ldw
        .word 65522
        PLW __t
        JSR __lt
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend197
        LDA #<_g_gfiles
        STA __ax
        LDA #>_g_gfiles
        STA __ax+1
        PHW __ax
        JSR __ldw
        .word 65530
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
        LDA #<_g_src
        STA __ax
        LDA #>_g_src
        STA __ax+1
        JSR __push
        JSR _f_abspath
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl198
        LDA __csp+1
        INC
        STA __csp+1
Lcl198:
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
        .word 65528
Ltop199:
        JSR __ldw
        .word 65532
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
        JZ Lend200
        JSR __ldw
        .word 65532
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
        LDA #47
        STA __ax
        LDA #0
        STA __ax+1
        PLW __t
        JSR __eq
        LDA __ax
        LDB __ax+1
        OR
        JZ Lend202
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
        .word 65526
Lend202:
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
        JMP Ltop199
Lend200:
        JSR __ldw
        .word 65532
        PHW __ax
        JSR __ldw
        .word 65526
        PLW __t
        JSR __add
        JSR __push
        LDA #<_g_dst
        STA __ax
        LDA #>_g_dst
        STA __ax+1
        JSR __push
        LDA #<_g_jdst
        STA __ax
        LDA #>_g_jdst
        STA __ax+1
        JSR __push
        JSR _f_joinp
        LDA __csp
        LDB #6
        ADD
        STA __csp
        JNC Lcl203
        LDA __csp+1
        INC
        STA __csp+1
Lcl203:
        JSR __ldw
        .word 65520
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0206
        LDA #<_g_src
        STA __ax
        LDA #>_g_src
        STA __ax+1
        JSR __push
        JSR _f_isdir
        LDA __csp
        LDB #2
        ADD
        STA __csp
        JNC Lcl208
        LDA __csp+1
        INC
        STA __csp+1
Lcl208:
        LDA __ax
        LDB __ax+1
        OR
        JZ Land0206
        LDA #1
        STA __ax
        LDA #0
        STA __ax+1
        JMP Lande207
Land0206:    LDA #0
        STA __ax
        STA __ax+1
Lande207:
        LDA __ax
        LDB __ax+1
        OR
        JZ Lelse204
        LDA #<_g_jdst
        STA __ax
        LDA #>_g_jdst
        STA __ax+1
        JSR __push
        LDA #<_g_src
        STA __ax
        LDA #>_g_src
        STA __ax+1
        JSR __push
        JSR _f_copy_tree
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl209
        LDA __csp+1
        INC
        STA __csp+1
Lcl209:
        JMP Lend205
Lelse204:
        LDA #<_g_jdst
        STA __ax
        LDA #>_g_jdst
        STA __ax+1
        JSR __push
        LDA #<_g_src
        STA __ax
        LDA #>_g_src
        STA __ax+1
        JSR __push
        JSR _f_copy_file
        LDA __csp
        LDB #4
        ADD
        STA __csp
        JNC Lcl210
        LDA __csp+1
        INC
        STA __csp+1
Lcl210:
Lend205:
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
        JMP Ltop196
Lend197:
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
_g_src:    .fill 80
_g_dst:    .fill 80
_g_jsrc:    .fill 80
_g_jdst:    .fill 80
_g_patw:    .fill 80
_g_gfiles:    .fill 1536
_g_de:    .fill 18
__s144:    .byte 117,115,97,103,101,58,32,67,80,32,91,45,114,93,32,115,114,99,32,100,115,116,32,32,32,99,111,112,121,32,97,32,102,105,108,101,47,103,108,111,98,44,32,111,114,32,45,114,32,97,32,100,105,114,101,99,116,111,114,121,32,116,114,101,101,0
__s157:    .byte 117,115,97,103,101,58,32,67,80,32,91,45,114,93,32,115,114,99,32,100,115,116,0
__s187:    .byte 99,112,58,32,115,111,117,114,99,101,32,110,111,116,32,102,111,117,110,100,0
__s191:    .byte 99,112,58,32,116,97,114,103,101,116,32,105,115,32,110,111,116,32,97,32,100,105,114,101,99,116,111,114,121,0
__s195:    .byte 99,112,58,32,110,111,32,109,97,116,99,104,0
