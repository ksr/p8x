; diff.asm — hand-coded DIFF command (asm counterpart of os/commands/diff.c).
;   DIFF file1 file2   show differing lines (< file1, > file2).
; Loads both files (<=96 lines x 79 chars) into memory, skips the common leading
; and trailing lines, prints the differing middle. abspath inline; no shared
; include. BIOS: FRESOLVE $0133, FOPEN $0124, FGETB $0127. OS: SYS_GETCWD $2003.
; Entry: P2 = arg tail.
;#use abi

; Memory model: each file's lines live in a fixed 80-byte-per-line grid
; (alines/blines, 7680 = 96 lines x 80). A line holds up to 79 chars + a NUL
; terminator; laddr computes base + line*80 + col. na/nb hold each file's line
; count. dp = length of common prefix; dsa/dsb = end index of each file's
; differing region (everything from dsa..na / dsb..nb is the common suffix).

        .org $6A00
        TPA2L                        ; stash arg-tail pointer (P2) into d_arg
        STA d_arg
        TPA2H
        STA d_arg+1
; d_sk: advance d_arg past leading spaces (ASCII 32) in the arg tail.
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
; d_chk: first non-space char. NUL or CR (13) = empty tail -> usage. A leading
; '-' means an option; the only options accepted are -h / -H, both print usage.
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
        LDA d_arg                    ; advance d_arg past the token just consumed
        LDB ap_n                     ; ap_n = char count abspath copied from arg
        ADD
        STA d_arg
        JNC d_f1s
        LDA d_arg+1
        INC
        STA d_arg+1
; d_f1s: skip spaces between file1 and file2 tokens in the arg tail.
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
; d_open1: open file1; openf returns A=0 on not-found. Load its lines into
; alines and record the count in na.
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
; Walk dp forward while alines[dp] == blines[dp]. Stop when dp reaches either
; line count (CMP sets C=1 when A>=B, i.e. dp >= na or dp >= nb) or a line differs.
        LDA #0
        STA dp
pfx_l:  LDA dp
        LDB na
        CMP
        JC pfx_d                      ; dp >= na -> ran off file1
        LDB nb                        ; CMP left A = dp
        CMP
        JC pfx_d                      ; dp >= nb -> ran off file2
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
        JSR leq                       ; leq -> A=1 if the two lines are equal
        LDB #0
        CMP
        JZ pfx_d                      ; unequal -> prefix ends here
        LDA dp
        INC
        STA dp
        JMP pfx_l
; ---- common suffix --------------------------------------------------------
; From the ends, walk dsa/dsb backward while alines[dsa-1]==blines[dsb-1], but
; never past dp (stop when either end index equals dp). After this, the
; differing region is alines[dp..dsa) vs blines[dp..dsb).
pfx_d:  LDA na                       ; dsa/dsb start one past the last line
        STA dsa
        LDA nb
        STA dsb
sfx_l:  LDA dsa
        LDB dp
        CMP
        JZ sfx_d                      ; dsa reached prefix end -> done
        LDA dsb
        LDB dp
        CMP
        JZ sfx_d                      ; dsb reached prefix end -> done
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
; sfx_d: if both differing regions are empty (dp==dsa and dp==dsb) the files
; are identical -> print nothing and return.
sfx_d:  LDA dp                       ; identical?
        LDB dsa
        CMP
        JNZ d_emit
        LDB dsb                       ; CMP left A = dp
        CMP
        JNZ d_emit
        RTS
; d_emit: print file1's differing lines tagged "< ", then file2's tagged "> ".
d_emit: LDA dp
        STA di
de_a:   LDA di
        LDB dsa
        CMP
        JC de_ad                      ; di >= dsa -> file1 region done
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
        JC de_bd                      ; di >= dsb -> file2 region done
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
; Error/usage exits: point P1 at a message string, fall through to d_pm which
; prints it (SYS_PUTS) followed by a newline, then returns.
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
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; openf: resolve the absolute path in 'path', then open it. FOPEN needs a
; caller-supplied file-handle/descriptor buffer; $FC00 is the fixed scratch
; page this command uses for it. FOPEN sets carry on failure.
; Out: A = 1 opened / 0 not found. Clobbers P1 (and P1/P2 via FRESOLVE/FOPEN).
openf:  LDA #<path
        TAP1L
        LDA #>path
        TAP1H
        LDA #0
        JSR FRESOLVE
        LDA #$00                     ; P1 = $FC00 = FOPEN handle buffer
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR FOPEN
        JC of_no                     ; carry set -> open failed
        LDA #1
        RTS
of_no:  LDA #0
        RTS

; loadlines: read the currently-open stream into the 80-byte-per-line grid at
; ll_buf, splitting on LF and NUL-terminating each line. lln = current line
; index, llcol = current column. Return the line count in A.
; Caps: at most 96 lines; at most 79 chars/line (excess chars are dropped,
; CR is ignored). Clobbers P1/P2 (FGETB) and the ll*/la* scratch vars.
loadlines:
        LDA #0
        STA lln
        STA llcol
ll_rd:  LDA #0
        JSR FGETB
        JC ll_fin                     ; carry = EOF
        STA llc
        LDA lln
        LDB #96
        CMP
        JC ll_fin                     ; lln >= 96 -> line grid full, stop
        LDA llc
        LDB #10
        CMP
        JZ ll_nl                      ; LF -> terminate current line
        LDB #13                       ; CMP left A = llc
        CMP
        JZ ll_rd                      ; CR -> ignore (handles CRLF)
        LDA llcol
        LDB #79
        CMP
        JC ll_rd                      ; col >= 79 -> line full, drop char
        LDA ll_buf
        STA la_base
        LDA ll_buf+1
        STA la_base+1
        LDA lln
        STA la_s
        LDA llcol
        STA la_c
        JSR laddr                     ; P1 = &ll_buf[lln][llcol]
        LDA llc
        STA (P1)
        LDA llcol
        INC
        STA llcol
        JMP ll_rd
; ll_nl: end of line - write the NUL terminator, bump line index, reset column.
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
; ll_fin: EOF (or grid full). If the last line had no trailing LF (llcol != 0)
; and there is still room, flush it as a final NUL-terminated line.
ll_fin: LDA llcol
        LDB #0
        CMP
        JZ ll_ret                     ; clean line boundary -> nothing pending
        LDA lln
        LDB #96
        CMP
        JC ll_ret                     ; no room for the partial line -> drop it
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

; leq: compare two NUL-terminated lines byte-by-byte.
; In: le_x/le_xi = base+index of line X, le_y/le_yi = base+index of line Y.
; Out: A = 1 if equal (both reach NUL together), else 0. Clobbers P1, le_i/a/b,
; and the la* scratch vars (via laddr).
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
        LDB #0                        ; bytes match (CMP left A = le_a); if both
                                      ; are NUL, the lines are equal
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

; emit: print the NUL-terminated tag at em_tag, then line em_li of grid em_buf,
; then a newline (LF, 10). Clobbers P1 and the la* scratch vars.
emit:   LDA em_tag
        TAP1L
        LDA em_tag+1
        TAP1H
et_l:   LDA (P1)
        LDB #0
        CMP
        JZ et_ln
        JSR SYS_PUTC
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
        JSR SYS_PUTC
        INP1
        JMP el_l
el_d:   LDA #10
        JSR SYS_PUTC
        RTS

; laddr: compute the address of a cell in an 80-byte-per-line grid.
; In: la_base (16-bit grid base), la_s (line/slot index), la_c (column).
; Out: P1 = la_base + la_s*80 + la_c. la_s*80 done by repeated 16-bit add of 80
; (lat is the running 16-bit accumulator; lacar carries into the high byte on
; the final base add). Clobbers A/B, P1, lat/lan/lacar.
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
        LDA #0                        ; LDA sets only Z/N, never C, so the JNC
        JNC lad_3                     ; below still tests the ADD above
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

; abspath: build an absolute path in the buffer at ap_out from the arg token
; at ap_a. If the token starts with '/', copy it verbatim. Otherwise prefix
; the current working directory (SYS_GETCWD), ensure exactly one '/' separator,
; then append the token. Copying stops at NUL, CR (13) or space (32).
; In: ap_a = source ptr, ap_out = dest buffer. Out: ap_n = #chars copied from
; the token; dest is NUL-terminated. Clobbers A/B, P1, P2.
abspath:LDA #0
        STA ap_n
        LDA ap_a
        TAP2L
        LDA ap_a+1
        TAP2H
        LDA (P2)
        LDB #'/'
        CMP
        JZ ab_abs                     ; leading '/' -> already absolute
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
        LDA #0
        JSR SYS_GETCWD
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
; ab_sl: advance P1 to the NUL at the end of the copied CWD string.
ab_sl:  LDA (P1)
        LDB #0
        CMP
        JZ ab_sld
        INP1
        JMP ab_sl
; ab_sld: back up to the CWD's last char; if it is not already '/', append one
; so exactly one separator sits between the directory and the token.
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
; ab_setp: point P2 back at the token and append it to dest (P1), counting
; chars in ap_n and stopping at NUL / CR / space.
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
