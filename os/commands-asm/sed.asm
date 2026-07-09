; sed.asm — hand-coded SED command (asm counterpart of os/commands/sed.c).
;   SED s/re/new/[g] [file]   substitute (regex LHS: . * + ? ^ $; literal RHS).
; Shares matchhere+rend via `;#use regex` and the stdin/readline engine via
; `;#use stdin`. Per line: scan, replace the first (or all with g) regex match
; span with the literal replacement, print. Entry: P2 = arg tail.
;#use stdin
;#use regex

        .org $7A00
        TPA2L
        STA s_sav
        TPA2H
        STA s_sav+1
        LDA s_sav
        TAP2L
        LDA s_sav+1
        TAP2H
sed_sk: LDA (P2)
        LDB #32
        CMP
        JNZ sed_c0
        INP2
        JMP sed_sk
sed_c0: LDA (P2)
        LDB #0
        CMP
        JZ sed_usage
        LDB #13
        CMP
        JZ sed_usage
        LDA (P2)
        LDB #'-'
        CMP
        JNZ sed_s
        TPA2L
        STA s_sav
        TPA2H
        STA s_sav+1
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ sed_usage
        LDB #'H'
        CMP
        JZ sed_usage
        LDA s_sav
        TAP2L
        LDA s_sav+1
        TAP2H
sed_s:  LDA (P2)
        LDB #'s'
        CMP
        JNZ sed_only
        TPA2L
        STA s_sav
        TPA2H
        STA s_sav+1
        INP2
        LDA (P2)
        LDB #'/'
        CMP
        JNZ sed_only
        INP2
        LDA #<pat                    ; parse pattern up to '/'
        TAP1L
        LDA #>pat
        TAP1H
        LDA #0
        STA si
sp_l:   LDA si
        LDB #63
        CMP
        JC sp_d
        LDA (P2)
        LDB #0
        CMP
        JZ sp_d
        LDB #'/'
        CMP
        JZ sp_d
        STA (P1)+
        INP2
        LDA si
        INC
        STA si
        JMP sp_l
sp_d:   LDA #0
        STA (P1)
        LDA #0
        STA anchored
        LDA #<pat
        STA rpat
        LDA #>pat
        STA rpat+1
        LDA pat
        LDB #'^'
        CMP
        JNZ sp_nosl
        LDA #1
        STA anchored
        LDA #<pat
        LDB #1
        ADD
        STA rpat
        JNC sp_r
        LDA #>pat
        INC
        STA rpat+1
        JMP sp_nosl
sp_r:   LDA #>pat
        STA rpat+1
sp_nosl:LDA (P2)
        LDB #'/'
        CMP
        JNZ sed_nosl
        INP2
        LDA #<rep                    ; parse replacement up to '/'
        TAP1L
        LDA #>rep
        TAP1H
        LDA #0
        STA sj
srp_l:  LDA sj
        LDB #63
        CMP
        JC srp_d
        LDA (P2)
        LDB #0
        CMP
        JZ srp_d
        LDB #'/'
        CMP
        JZ srp_d
        STA (P1)+
        INP2
        LDA sj
        INC
        STA sj
        JMP srp_l
srp_d:  LDA #0
        STA (P1)
        LDA #0
        STA global
        LDA (P2)
        LDB #'/'
        CMP
        JNZ sg_done
        INP2
        LDA (P2)
        LDB #'g'
        CMP
        JZ sg_set
        LDB #'G'
        CMP
        JZ sg_set
        JMP sg_done
sg_set: LDA #1
        STA global
        INP2
sg_done:LDA (P2)
        LDB #32
        CMP
        JNZ sof_d
        INP2
        JMP sg_done
sof_d:  TPA2L
        STA oa_a
        TPA2H
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ sed_nf
; ---- substitution loop ----------------------------------------------------
sed_loop:
        LDA #<line
        STA rl_buf
        LDA #>line
        STA rl_buf+1
        JSR readline
        LDB #0
        CMP
        JZ sed_end
        LDA #0
        STA sn
        STA si
        STA sdone
sl_l:   LDA #<line
        LDB si
        ADD
        TAP1L
        LDA #>line
        JNC sl1
        INC
sl1:    TAP1H
        LDA (P1)
        LDB #0
        CMP
        JZ sl_end
        LDA #0
        STA smlen
        LDA global
        LDB #0
        CMP
        JNZ sl_re
        LDA sdone
        LDB #0
        CMP
        JNZ sl_lit
sl_re:  LDA si
        STA ra_i
        JSR re_at
        STA smlen
        LDB #0
        CMP
        JZ sl_lit
        LDA #0                        ; copy replacement
        STA sj
sr_l:   LDA #<rep
        LDB sj
        ADD
        TAP2L
        LDA #>rep
        JNC sr1
        INC
sr1:    TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ sr_d
        LDA sn
        LDB #255
        CMP
        JC sr_d
        LDA (P2)
        STA sch
        LDA #<out
        LDB sn
        ADD
        TAP1L
        LDA #>out
        JNC sr2
        INC
sr2:    TAP1H
        LDA sch
        STA (P1)
        LDA sn
        INC
        STA sn
        LDA sj
        INC
        STA sj
        JMP sr_l
sr_d:   LDA si                        ; i += mlen
        LDB smlen
        ADD
        STA si
        LDA global
        LDB #0
        CMP
        JNZ sl_l
        LDA #1
        STA sdone
        JMP sl_l
sl_lit: LDA sn
        LDB #255
        CMP
        JC sl_inc
        LDA #<line
        LDB si
        ADD
        TAP2L
        LDA #>line
        JNC sll1
        INC
sll1:   TAP2H
        LDA (P2)
        STA sch
        LDA #<out
        LDB sn
        ADD
        TAP1L
        LDA #>out
        JNC sll2
        INC
sll2:   TAP1H
        LDA sch
        STA (P1)
        LDA sn
        INC
        STA sn
sl_inc: LDA si
        INC
        STA si
        JMP sl_l
sl_end: LDA #<out
        LDB sn
        ADD
        TAP1L
        LDA #>out
        JNC sle1
        INC
sle1:   TAP1H
        LDA #0
        STA (P1)
        LDA #<out
        TAP1L
        LDA #>out
        TAP1H
        LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        JMP sed_loop
sed_end:RTS

sed_usage:
        LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        JMP sed_pm
sed_only:
        LDA #<u_only
        TAP1L
        LDA #>u_only
        TAP1H
        JMP sed_pm
sed_nosl:
        LDA #<u_nosl
        TAP1L
        LDA #>u_nosl
        TAP1H
        JMP sed_pm
sed_nf: LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
sed_pm: LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS

; re_at: ra_i = start index in line -> A = length of a regex match here (0=none).
re_at:  LDA anchored
        LDB #0
        CMP
        JZ ra_go
        LDA ra_i
        LDB #0
        CMP
        JZ ra_go
        LDA #0
        RTS
ra_go:  LDA #<line
        LDB ra_i
        ADD
        STA ra_lp
        LDA #>line
        JNC ra1
        INC
ra1:    STA ra_lp+1
        LDA rpat
        STA rx_re
        LDA rpat+1
        STA rx_re+1
        LDA ra_lp
        STA rx_t
        LDA ra_lp+1
        STA rx_t+1
        JSR matchhere
        LDB #0
        CMP
        JZ ra_no
        LDA rend                     ; len = rend - lp (low byte; len < 256)
        LDB ra_lp
        SUB
        RTS
ra_no:  LDA #0
        RTS

; readline: rl_buf -> A=1 line read / 0 EOF (cursor rlp reloaded per store,
; since nextc clobbers P1/P2).
readline:
        LDA rl_buf
        STA rlp
        LDA rl_buf+1
        STA rlp+1
        LDA #0
        STA rln
        JSR nextc
        JC rl_eof0
rl_l:   STA rlc
        LDB #10
        CMP
        JZ rl_done
        LDA rlc
        LDB #13
        CMP
        JZ rl_skip
        LDA rln
        LDB #255
        CMP
        JC rl_skip
        LDA rlp
        TAP1L
        LDA rlp+1
        TAP1H
        LDA rlc
        STA (P1)
        LDA rlp
        LDB #1
        ADD
        STA rlp
        JNC rl_s1
        LDA rlp+1
        INC
        STA rlp+1
rl_s1:  LDA rln
        INC
        STA rln
rl_skip:JSR nextc
        JC rl_done
        JMP rl_l
rl_done:LDA rlp
        TAP1L
        LDA rlp+1
        TAP1H
        LDA #0
        STA (P1)
        LDA #1
        RTS
rl_eof0:LDA #0
        RTS

u_use:  .asciiz "usage: SED s/re/new/[g] [file]   substitute (regex: . * + ? ^ $)"
u_only: .asciiz "sed: only s/re/new/[g]"
u_nosl: .asciiz "sed: bad s/// (no second /)"
u_nf:   .asciiz "sed: not found"

s_sav:  .fill 2
si:     .fill 1
sj:     .fill 1
sn:     .fill 1
sdone:  .fill 1
smlen:  .fill 1
sch:    .fill 1
global: .fill 1
anchored:.fill 1
rpat:   .fill 2
ra_i:   .fill 1
ra_lp:  .fill 2
rl_buf: .fill 2
rlp:    .fill 2
rln:    .fill 1
rlc:    .fill 1
pat:    .fill 64
rep:    .fill 64
line:   .fill 260
out:    .fill 260
