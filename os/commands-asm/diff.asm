; diff.asm — hand-coded DIFF command (asm counterpart of os/commands/diff.c).
;   DIFF file1 file2   show differing lines (< file1, > file2).
; Loads both files (<=96 lines x 79 chars) into memory, skips the common leading
; and trailing lines, prints the differing middle. abspath inline; no shared
; include. BIOS: FRESOLVE $0133, FOPEN $0124, FGETB $0127. OS: SYS_GETCWD $4003.
; Entry: P2 = arg tail.

        .org $7A00
        TPA2L
        STA d_arg
        TPA2H
        STA d_arg+1
d_sk:   LDA d_arg
        TAP2L
        LDA d_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ d_chk
        LDA d_arg
        LDB #1
        ADD
        STA d_arg
        JNC d_sk
        LDA d_arg+1
        INC
        STA d_arg+1
        JMP d_sk
d_chk:  LDA (P2)
        LDB #0
        CMP
        JZ d_usage
        LDB #13
        CMP
        JZ d_usage
        LDB #'-'
        CMP
        JNZ d_f1
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ d_usage
        LDB #'H'
        CMP
        JZ d_usage
d_f1:   LDA #<path                   ; abspath(path, arg) - file 1
        STA ap_out
        LDA #>path
        STA ap_out+1
        LDA d_arg
        STA ap_a
        LDA d_arg+1
        STA ap_a+1
        JSR abspath
        LDA d_arg
        LDB ap_n
        ADD
        STA d_arg
        JNC d_f1s
        LDA d_arg+1
        INC
        STA d_arg+1
d_f1s:  LDA d_arg
        TAP2L
        LDA d_arg+1
        TAP2H
d_f1sk: LDA (P2)
        LDB #32
        CMP
        JNZ d_open1
        LDA d_arg
        LDB #1
        ADD
        STA d_arg
        JNC d_f1s
        LDA d_arg+1
        INC
        STA d_arg+1
        JMP d_f1s
d_open1:JSR openf
        LDB #0
        CMP
        JZ d_nf1
        LDA #<alines
        STA ll_buf
        LDA #>alines
        STA ll_buf+1
        JSR loadlines
        STA na
        LDA d_arg                    ; file 2 must be present
        TAP2L
        LDA d_arg+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ d_usage2
        LDB #13
        CMP
        JZ d_usage2
        LDA #<path
        STA ap_out
        LDA #>path
        STA ap_out+1
        LDA d_arg
        STA ap_a
        LDA d_arg+1
        STA ap_a+1
        JSR abspath
        JSR openf
        LDB #0
        CMP
        JZ d_nf2
        LDA #<blines
        STA ll_buf
        LDA #>blines
        STA ll_buf+1
        JSR loadlines
        STA nb
; ---- common prefix --------------------------------------------------------
        LDA #0
        STA dp
pfx_l:  LDA dp
        LDB na
        CMP
        JC pfx_d
        LDA dp
        LDB nb
        CMP
        JC pfx_d
        LDA #<alines
        STA le_x
        LDA #>alines
        STA le_x+1
        LDA dp
        STA le_xi
        LDA #<blines
        STA le_y
        LDA #>blines
        STA le_y+1
        LDA dp
        STA le_yi
        JSR leq
        LDB #0
        CMP
        JZ pfx_d
        LDA dp
        INC
        STA dp
        JMP pfx_l
pfx_d:  LDA na                       ; common suffix
        STA dsa
        LDA nb
        STA dsb
sfx_l:  LDA dsa
        LDB dp
        CMP
        JZ sfx_d
        LDA dsb
        LDB dp
        CMP
        JZ sfx_d
        LDA dsa
        LDB #1
        SUB
        STA le_xi
        LDA #<alines
        STA le_x
        LDA #>alines
        STA le_x+1
        LDA dsb
        LDB #1
        SUB
        STA le_yi
        LDA #<blines
        STA le_y
        LDA #>blines
        STA le_y+1
        JSR leq
        LDB #0
        CMP
        JZ sfx_d
        LDA dsa
        DEC
        STA dsa
        LDA dsb
        DEC
        STA dsb
        JMP sfx_l
sfx_d:  LDA dp                       ; identical?
        LDB dsa
        CMP
        JNZ d_emit
        LDA dp
        LDB dsb
        CMP
        JNZ d_emit
        RTS
d_emit: LDA dp
        STA di
de_a:   LDA di
        LDB dsa
        CMP
        JC de_ad
        LDA #<tag_lt
        STA em_tag
        LDA #>tag_lt
        STA em_tag+1
        LDA #<alines
        STA em_buf
        LDA #>alines
        STA em_buf+1
        LDA di
        STA em_li
        JSR emit
        LDA di
        INC
        STA di
        JMP de_a
de_ad:  LDA dp
        STA di
de_b:   LDA di
        LDB dsb
        CMP
        JC de_bd
        LDA #<tag_gt
        STA em_tag
        LDA #>tag_gt
        STA em_tag+1
        LDA #<blines
        STA em_buf
        LDA #>blines
        STA em_buf+1
        LDA di
        STA em_li
        JSR emit
        LDA di
        INC
        STA di
        JMP de_b
de_bd:  RTS
d_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        JMP d_pm
d_usage2:
        LDA #<u_use2
        TAP1L
        LDA #>u_use2
        TAP1H
        JMP d_pm
d_nf1:  LDA #<u_nf1
        TAP1L
        LDA #>u_nf1
        TAP1H
        JMP d_pm
d_nf2:  LDA #<u_nf2
        TAP1L
        LDA #>u_nf2
        TAP1H
d_pm:   LDA #0
        JSR $400F
        LDA #10
        JSR $4009
        RTS

; openf: FRESOLVE(path)+FOPEN($FC00) -> A = 1 ok / 0 not found
openf:  LDA #<path
        TAP1L
        LDA #>path
        TAP1H
        LDA #0
        JSR $0133
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR $0124
        JC of_no
        LDA #1
        RTS
of_no:  LDA #0
        RTS

; loadlines: read the open stream into ll_buf; return line count in A.
loadlines:
        LDA #0
        STA lln
        STA llcol
ll_rd:  LDA #0
        JSR $0127
        JC ll_fin
        STA llc
        LDA lln
        LDB #96
        CMP
        JC ll_fin
        LDA llc
        LDB #10
        CMP
        JZ ll_nl
        LDA llc
        LDB #13
        CMP
        JZ ll_rd
        LDA llcol
        LDB #79
        CMP
        JC ll_rd
        LDA ll_buf
        STA la_base
        LDA ll_buf+1
        STA la_base+1
        LDA lln
        STA la_s
        LDA llcol
        STA la_c
        JSR laddr
        LDA llc
        STA (P1)
        LDA llcol
        INC
        STA llcol
        JMP ll_rd
ll_nl:  LDA ll_buf
        STA la_base
        LDA ll_buf+1
        STA la_base+1
        LDA lln
        STA la_s
        LDA llcol
        STA la_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA lln
        INC
        STA lln
        LDA #0
        STA llcol
        JMP ll_rd
ll_fin: LDA llcol
        LDB #0
        CMP
        JZ ll_ret
        LDA lln
        LDB #96
        CMP
        JC ll_ret
        LDA ll_buf
        STA la_base
        LDA ll_buf+1
        STA la_base+1
        LDA lln
        STA la_s
        LDA llcol
        STA la_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA lln
        INC
        STA lln
ll_ret: LDA lln
        RTS

; leq: A = 1 if line le_xi of le_x equals line le_yi of le_y
leq:    LDA #0
        STA le_i
le_l:   LDA le_x
        STA la_base
        LDA le_x+1
        STA la_base+1
        LDA le_xi
        STA la_s
        LDA le_i
        STA la_c
        JSR laddr
        LDA (P1)
        STA le_a
        LDA le_y
        STA la_base
        LDA le_y+1
        STA la_base+1
        LDA le_yi
        STA la_s
        LDA le_i
        STA la_c
        JSR laddr
        LDA (P1)
        STA le_b
        LDA le_a
        LDB le_b
        CMP
        JNZ le_no
        LDA le_a
        LDB #0
        CMP
        JZ le_yes
        LDA le_i
        INC
        STA le_i
        JMP le_l
le_no:  LDA #0
        RTS
le_yes: LDA #1
        RTS

; emit: print em_tag then line em_li of em_buf then newline
emit:   LDA em_tag
        TAP1L
        LDA em_tag+1
        TAP1H
et_l:   LDA (P1)
        LDB #0
        CMP
        JZ et_ln
        JSR $4009
        INP1
        JMP et_l
et_ln:  LDA em_buf
        STA la_base
        LDA em_buf+1
        STA la_base+1
        LDA em_li
        STA la_s
        LDA #0
        STA la_c
        JSR laddr
el_l:   LDA (P1)
        LDB #0
        CMP
        JZ el_d
        JSR $4009
        INP1
        JMP el_l
el_d:   LDA #10
        JSR $4009
        RTS

; laddr: P1 = la_base + la_s*80 + la_c
laddr:  LDA #0
        STA lat
        STA lat+1
        LDA la_s
        STA lan
lad_m:  LDA lan
        LDB #0
        CMP
        JZ lad_md
        LDA lat
        LDB #80
        ADD
        STA lat
        JNC lad_1
        LDA lat+1
        INC
        STA lat+1
lad_1:  LDA lan
        DEC
        STA lan
        JMP lad_m
lad_md: LDA lat
        LDB la_c
        ADD
        STA lat
        JNC lad_2
        LDA lat+1
        INC
        STA lat+1
lad_2:  LDA lat
        LDB la_base
        ADD
        STA lat
        LDA #0
        JNC lad_3
        LDA #1
lad_3:  STA lacar
        LDA lat+1
        LDB la_base+1
        ADD
        LDB lacar
        ADD
        STA lat+1
        LDA lat
        TAP1L
        LDA lat+1
        TAP1H
        RTS

; abspath (P2 source, P1 dest)
abspath:LDA #0
        STA ap_n
        LDA ap_a
        TAP2L
        LDA ap_a+1
        TAP2H
        LDA (P2)
        LDB #'/'
        CMP
        JZ ab_abs
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
        LDA #0
        JSR $4003
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
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
ab_abs: LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
ab_setp:LDA ap_a
        TAP2L
        LDA ap_a+1
        TAP2H
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

tag_lt: .asciiz "< "
tag_gt: .asciiz "> "
u_use:  .asciiz "usage: DIFF file1 file2   show differing lines (< file1, > file2)"
u_use2: .asciiz "usage: DIFF file1 file2"
u_nf1:  .asciiz "diff: file1 not found"
u_nf2:  .asciiz "diff: file2 not found"

d_arg:  .fill 2
na:     .fill 1
nb:     .fill 1
dp:     .fill 1
dsa:    .fill 1
dsb:    .fill 1
di:     .fill 1
lln:    .fill 1
llcol:  .fill 1
llc:    .fill 1
ll_buf: .fill 2
le_x:   .fill 2
le_y:   .fill 2
le_xi:  .fill 1
le_yi:  .fill 1
le_i:   .fill 1
le_a:   .fill 1
le_b:   .fill 1
em_tag: .fill 2
em_buf: .fill 2
em_li:  .fill 1
la_base:.fill 2
la_s:   .fill 1
la_c:   .fill 1
lan:    .fill 1
lat:    .fill 2
lacar:  .fill 1
ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
path:   .fill 80
alines: .fill 7680
blines: .fill 7680
