; sort.asm — hand-coded SORT command (asm counterpart of os/commands/sort.c).
;   SORT [file]   sort lines ascending (file or stdin).
; Shares the input engine via `;#use stdin`. Reads up to 128 lines x 79 chars
; into a flat buffer, selection-sorts the slots by unsigned byte value, prints.
; Entry: P2 = arg tail.
;#use stdin
;#use abi

        .org $6A00
        TPA2L
        STA s_arg
        TPA2H
        STA s_arg+1
s_sk:   LDA s_arg
        TAP2L
        LDA s_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ s_chk
        LDA s_arg
        LDB #1
        ADD
        STA s_arg
        JNC s_sk
        LDA s_arg+1
        INC
        STA s_arg+1
        JMP s_sk
s_chk:  LDA (P2)
        LDB #'-'
        CMP
        JNZ s_open
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ s_usage
        LDB #'H'
        CMP
        JZ s_usage
s_open: LDA s_arg
        STA oa_a
        LDA s_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ s_nf
; ---- read lines into the flat buffer --------------------------------------
        LDA #0
        STA nline
        STA col
s_rl:   LDA nline                    ; stop at 128 lines
        LDB #128
        CMP
        JC s_rdone
        JSR nextc
        JC s_reof
        STA sch
        LDB #10
        CMP
        JNZ s_rch
        LDA nline                    ; end of line
        STA la_s
        LDA col
        STA la_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA nline
        INC
        STA nline
        LDA #0
        STA col
        JMP s_rl
s_rch:  LDA sch
        LDB #13
        CMP
        JZ s_rl                      ; drop CR
        LDA col
        LDB #79
        CMP
        JC s_rl                      ; col>=79 -> skip
        LDA nline
        STA la_s
        LDA col
        STA la_c
        JSR laddr
        LDA sch
        STA (P1)
        LDA col
        INC
        STA col
        JMP s_rl
s_reof: LDA col                      ; final line w/o LF
        LDB #0
        CMP
        JZ s_rdone
        LDA nline
        LDB #128
        CMP
        JC s_rdone
        LDA nline
        STA la_s
        LDA col
        STA la_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA nline
        INC
        STA nline
s_rdone:
; ---- selection sort -------------------------------------------------------
        LDA #0
        STA si
so_i:   LDA si                       ; while si+1 < nline
        INC
        LDB nline
        CMP
        JC so_done
        LDA si
        STA smin
        LDA si
        INC
        STA sj
so_j:   LDA sj
        LDB nline
        CMP
        JC so_swap
        LDA sj
        STA ll_x
        LDA smin
        STA ll_y
        JSR lless
        LDB #0
        CMP
        JZ so_jn
        LDA sj
        STA smin
so_jn:  LDA sj
        INC
        STA sj
        JMP so_j
so_swap:LDA smin
        LDB si
        CMP
        JZ so_in
        LDA #0
        STA k
sw_l:   LDA k
        LDB #80
        CMP
        JC so_in
        LDA si
        STA la_s
        LDA k
        STA la_c
        JSR laddr
        TPA1L
        STA ai
        TPA1H
        STA ai+1
        LDA smin
        STA la_s
        LDA k
        STA la_c
        JSR laddr
        TPA1L
        STA am
        TPA1H
        STA am+1
        LDA ai
        TAP1L
        LDA ai+1
        TAP1H
        LDA (P1)
        STA swt
        LDA am
        TAP1L
        LDA am+1
        TAP1H
        LDA (P1)
        STA swu
        LDA ai
        TAP1L
        LDA ai+1
        TAP1H
        LDA swu
        STA (P1)
        LDA am
        TAP1L
        LDA am+1
        TAP1H
        LDA swt
        STA (P1)
        LDA k
        INC
        STA k
        JMP sw_l
so_in:  LDA si
        INC
        STA si
        JMP so_i
so_done:
; ---- print ----------------------------------------------------------------
        LDA #0
        STA si
sp_l:   LDA si
        LDB nline
        CMP
        JC sp_done
        LDA si
        STA la_s
        LDA #0
        STA la_c
        JSR laddr
sp_cl:  LDA (P1)
        LDB #0
        CMP
        JZ sp_eol
        JSR SYS_PUTC
        INP1
        JMP sp_cl
sp_eol: LDA #10
        JSR SYS_PUTC
        LDA si
        INC
        STA si
        JMP sp_l
sp_done:RTS
s_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
s_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; laddr: P1 = lines + la_s*80 + la_c
laddr:  LDA #0
        STA la_t
        STA la_t+1
        LDA la_s
        STA la_n
la_ml:  LDA la_n
        LDB #0
        CMP
        JZ la_md
        LDA la_t
        LDB #80
        ADD
        STA la_t
        JNC la_m1
        LDA la_t+1
        INC
        STA la_t+1
la_m1:  LDA la_n
        DEC
        STA la_n
        JMP la_ml
la_md:  LDA la_t
        LDB la_c
        ADD
        STA la_t
        JNC la_c1
        LDA la_t+1
        INC
        STA la_t+1
la_c1:  LDA la_t
        LDB #<lines
        ADD
        STA la_t
        LDA #0
        JNC la_b1
        LDA #1
la_b1:  STA la_car
        LDA la_t+1
        LDB #>lines
        ADD
        LDB la_car
        ADD
        STA la_t+1
        LDA la_t
        TAP1L
        LDA la_t+1
        TAP1H
        RTS

; lless: A = 1 if line ll_x sorts before line ll_y (unsigned bytes), else 0
lless:  LDA #0
        STA ll_i
ll_l:   LDA ll_x
        STA la_s
        LDA ll_i
        STA la_c
        JSR laddr
        LDA (P1)
        STA ll_a
        LDA ll_y
        STA la_s
        LDA ll_i
        STA la_c
        JSR laddr
        LDA (P1)
        STA ll_b
        LDA ll_a
        LDB ll_b
        CMP
        JZ ll_eq
        LDA ll_a
        LDB ll_b
        CMP
        JC ll_no                     ; a >= b -> not less
        LDA #1
        RTS
ll_no:  LDA #0
        RTS
ll_eq:  LDA ll_a
        LDB #0
        CMP
        JZ ll_z                      ; a==0 -> equal, not less
        LDA ll_i
        INC
        STA ll_i
        JMP ll_l
ll_z:   LDA #0
        RTS

u_nf:   .asciiz "sort: not found"
u_use:  .asciiz "usage: SORT [file]   sort lines ascending (file or stdin)"

s_arg:  .fill 2
nline:  .fill 1
col:    .fill 1
sch:    .fill 1
si:     .fill 1
sj:     .fill 1
smin:   .fill 1
k:      .fill 1
ai:     .fill 2
am:     .fill 2
swt:    .fill 1
swu:    .fill 1
la_s:   .fill 1
la_c:   .fill 1
la_n:   .fill 1
la_t:   .fill 2
la_car: .fill 1
ll_x:   .fill 1
ll_y:   .fill 1
ll_i:   .fill 1
ll_a:   .fill 1
ll_b:   .fill 1
lines:  .fill 10240
