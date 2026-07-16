; sort.asm — hand-coded SORT command (asm counterpart of os/commands/sort.c).
;   SORT [file]   sort lines ascending (file or stdin).
; Shares the input engine via `;#use stdin`. Reads up to 128 lines x 79 chars
; into a flat buffer, selection-sorts the slots by unsigned byte value, prints.
; Entry: P2 = arg tail.
;
; Buffer layout: `lines` is 128 slots of 80 bytes each (10240 total). A slot holds
; up to 79 chars plus a trailing NUL terminator; laddr computes slot base as
; lines + row*80 + col, with the *80 done as (row<<6)+(row<<4) via shift-add.
; Selection sort reorders slot *contents* (byte copies), not
; pointers. Line compare (lless) is a NUL-terminated unsigned byte compare.
; Registers: laddr/lless clobber A, B, P1; nextc/openarg/SYS_* clobber P1/P2.
; s_arg is a 16-bit walking pointer into the arg tail; all counters are 8-bit,
; so the 128-line and 79-col caps keep every index within a single byte.
;#use stdin
;#use abi

        .org $6A00
        TPA2L                        ; save P2 (arg tail) into 16-bit s_arg
        STA s_arg
        TPA2H
        STA s_arg+1
; skip leading spaces (ASCII 32) in the arg tail so s_arg points at first token
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
        JNC s_sk                     ; no carry from low byte -> loop
        LDA s_arg+1                  ; propagate carry into high byte
        INC
        STA s_arg+1
        JMP s_sk
; if the token starts with '-', treat "-h"/"-H" as a request for usage text
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
; open the source: openarg picks the file at s_arg, or stdin if the tail is empty
s_open: LDA s_arg
        STA oa_a
        LDA s_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2                       ; openarg returns 2 = file-not-found
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
        JSR nextc                    ; fetch next input byte
        JC s_reof                    ; carry set = EOF
        STA sch
        LDB #10                      ; LF terminates the current line
        CMP
        JNZ s_rch
        LDA nline                    ; end of line: NUL-terminate at [nline,col]
        STA la_s
        LDA col
        STA la_c
        JSR laddr
        LDA #0
        STA (P1)
        LDA nline                    ; advance to next slot, reset column
        INC
        STA nline
        LDA #0
        STA col
        JMP s_rl
s_rch:  LDA sch
        LDB #13
        CMP
        JZ s_rl                      ; drop CR (CRLF handled as bare LF)
        LDA col
        LDB #79
        CMP
        JC s_rl                      ; col>=79 -> drop char (leave room for NUL)
        LDA nline                    ; store char at [nline,col]
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
; EOF: if the last line had no trailing LF, terminate and count it too
s_reof: LDA col                      ; nothing buffered -> done
        LDB #0
        CMP
        JZ s_rdone
        LDA nline                    ; buffer full (128)? then discard partial
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
; outer loop: for si in 0..nline-2, find index of the minimum slot in [si..)
so_i:   LDA si                       ; while si+1 < nline (CMP C=1 when si+1>=nline)
        INC
        LDB nline
        CMP
        JC so_done
        LDA si                       ; smin = si (best-so-far index)
        STA smin
        LDA si                       ; sj = si+1 (inner scan start)
        INC
        STA sj
; inner loop: scan sj over [si+1..nline) tracking the smallest line in smin
so_j:   LDA sj
        LDB nline
        CMP
        JC so_swap                   ; sj>=nline -> scan complete
        LDA sj                       ; if line[sj] < line[smin], smin = sj
        STA ll_x
        LDA smin
        STA ll_y
        JSR lless
        LDB #0                       ; lless returns 0 (not-less) or 1
        CMP
        JZ so_jn
        LDA sj
        STA smin
so_jn:  LDA sj
        INC
        STA sj
        JMP so_j
; swap: exchange slot si with slot smin, one byte at a time over all 80 columns
so_swap:LDA smin
        LDB si
        CMP
        JZ so_in                     ; smin==si -> already in place, no swap
        LDA #0
        STA k
sw_l:   LDA k                        ; for k in 0..79
        LDB #80
        CMP
        JC so_in                     ; k>=80 -> swap done
        LDA si
        STA la_s                     ; ai = &slot[si][k] (cached; laddr reuses P1)
        LDA k
        STA la_c
        JSR laddr
        TPA1L
        STA ai
        TPA1H
        STA ai+1
        LDA smin                     ; am = &slot[smin][k]
        STA la_s
        LDA k
        STA la_c
        JSR laddr
        TPA1L
        STA am
        TPA1H
        STA am+1
        LDA ai                       ; swt = *ai (save si's byte)
        TAP1L
        LDA ai+1
        TAP1H
        LDA (P1)
        STA swt
        LDA am                       ; swu = *am (save smin's byte)
        TAP1L
        LDA am+1
        TAP1H
        LDA (P1)
        STA swu
        LDA ai                       ; *ai = swu
        TAP1L
        LDA ai+1
        TAP1H
        LDA swu
        STA (P1)
        LDA am                       ; *am = swt
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
; walk slots 0..nline-1, emit each NUL-terminated line followed by a newline
        LDA #0
        STA si
sp_l:   LDA si
        LDB nline
        CMP
        JC sp_done                   ; si>=nline -> all lines printed
        LDA si                       ; P1 = &slot[si][0]
        STA la_s
        LDA #0
        STA la_c
        JSR laddr
sp_cl:  LDA (P1)                     ; emit chars until the NUL terminator
        LDB #0
        CMP
        JZ sp_eol
        JSR SYS_PUTC
        INP1
        JMP sp_cl
sp_eol: LDA #10                      ; terminate the printed line with LF
        JSR SYS_PUTC
        LDA si
        INC
        STA si
        JMP sp_l
sp_done:RTS
; s_nf: file-not-found message; s_usage: usage text. Both print a line + RTS.
; s_nf is an error, so it goes to the raw console via PUTS/CONOUT, not SYS_PUTS/
; SYS_PUTC: those are stdout, which the shell may have aimed at a file or a pipe,
; and a diagnostic must never land in the redirect or be read as data downstream.
; s_usage below is output the user asked for with -h, so it stays on stdout.
s_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR PUTS
        LDA #10
        JSR CONOUT
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

; laddr: compute slot byte address P1 = lines + la_s*80 + la_c.
;   In:  la_s = row (0..127), la_c = column (0..79)
;   Out: P1 = absolute address; la_t/la_u/la_car scratch clobbered, A/B clobbered.
; No multiply instruction exists, so *80 is done as (row<<6) + (row<<4) rather
; than by repeated addition: laddr is the hot path (twice per byte in the swap
; loop, twice per char in lless), so a fixed six shifts beats a loop of up to 127
; 16-bit adds. Each <<1 is SHL on the low byte then ROL on the high byte, which
; picks up SHL's shifted-out bit from C — LDA is ldzn-only and STA loads no flags,
; so C survives between the two halves. row <= 127, so row<<6 <= 8128 and the
; product <= 10160: the 16-bit accumulator never overflows and ROL never drops a
; set bit off the top.
laddr:  LDA la_s                      ; la_t (16-bit accumulator) = row
        STA la_t
        LDA #0
        STA la_t+1
        LDA la_t                      ; la_t <<= 1  (row*2)
        SHL
        STA la_t
        LDA la_t+1
        ROL
        STA la_t+1
        LDA la_t                      ; la_t <<= 1  (row*4)
        SHL
        STA la_t
        LDA la_t+1
        ROL
        STA la_t+1
        LDA la_t                      ; la_t <<= 1  (row*8)
        SHL
        STA la_t
        LDA la_t+1
        ROL
        STA la_t+1
        LDA la_t                      ; la_t <<= 1  (row*16)
        SHL
        STA la_t
        LDA la_t+1
        ROL
        STA la_t+1
        LDA la_t                      ; la_u = row*16 (saved for the final add)
        STA la_u
        LDA la_t+1
        STA la_u+1
        LDA la_t                      ; la_t <<= 1  (row*32)
        SHL
        STA la_t
        LDA la_t+1
        ROL
        STA la_t+1
        LDA la_t                      ; la_t <<= 1  (row*64)
        SHL
        STA la_t
        LDA la_t+1
        ROL
        STA la_t+1
        LDA la_t                      ; la_t += la_u -> row*64 + row*16 = row*80
        LDB la_u                      ; low byte first; capture its carry in la_car
        ADD
        STA la_t
        LDA #0
        JNC la_u1
        LDA #1
la_u1:  STA la_car
        LDA la_t+1                    ; high byte += la_u+1, then += saved carry
        LDB la_u+1
        ADD
        LDB la_car
        ADD
        STA la_t+1
la_md:  LDA la_t                      ; la_t += la_c (column offset)
        LDB la_c
        ADD
        STA la_t
        JNC la_c1
        LDA la_t+1
        INC
        STA la_t+1
la_c1:  LDA la_t                      ; la_t += &lines (add 16-bit base address)
        LDB #<lines                   ; low byte first; capture its carry in la_car
        ADD
        STA la_t
        LDA #0
        JNC la_b1
        LDA #1
la_b1:  STA la_car
        LDA la_t+1                    ; high byte += >lines, then += saved carry
        LDB #>lines
        ADD
        LDB la_car
        ADD
        STA la_t+1
        LDA la_t                      ; move result into P1
        TAP1L
        LDA la_t+1
        TAP1H
        RTS

; lless: A = 1 if line ll_x sorts before line ll_y (unsigned bytes), else 0.
;   In:  ll_x, ll_y = row indices.  Uses la_*/ll_* scratch, clobbers A/B/P1.
; Compares byte-by-byte; equal-and-both-nonzero advances, mismatch decides,
; and a shared NUL (a==0 at an equal position) means the lines are equal.
lless:  LDA #0
        STA ll_i
ll_l:   LDA ll_x
        STA la_s
        LDA ll_i
        STA la_c
        JSR laddr
        LDA (P1)                     ; ll_a = ll_x[ll_i]
        STA ll_a
        LDA ll_y
        STA la_s
        LDA ll_i
        STA la_c
        JSR laddr
        LDA (P1)                     ; ll_b = ll_y[ll_i]
        STA ll_b
        LDA ll_a                     ; equal bytes -> defer to ll_eq
        LDB ll_b
        CMP
        JZ ll_eq
        JC ll_no                     ; differ: carry from the CMP above still
                                     ; holds; C=1 means a >= b -> not less
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

; ---- state (BSS) ----------------------------------------------------------
s_arg:  .fill 2                      ; 16-bit walking pointer into arg tail
nline:  .fill 1                      ; number of lines buffered (0..128)
col:    .fill 1                      ; current column while reading a line
sch:    .fill 1                      ; last char read from input
si:     .fill 1                      ; selection-sort outer index / print index
sj:     .fill 1                      ; selection-sort inner scan index
smin:   .fill 1                      ; index of smallest line found so far
k:      .fill 1                      ; column counter during a slot swap
ai:     .fill 2                      ; cached &slot[si][k]
am:     .fill 2                      ; cached &slot[smin][k]
swt:    .fill 1                      ; swap temp: byte from slot si
swu:    .fill 1                      ; swap temp: byte from slot smin
la_s:   .fill 1                      ; laddr input: row
la_c:   .fill 1                      ; laddr input: column
la_t:   .fill 2                      ; laddr scratch: 16-bit address accumulator
la_u:   .fill 2                      ; laddr scratch: row*16, held for the *80 add
la_car: .fill 1                      ; laddr scratch: carry from a low-byte add
ll_x:   .fill 1                      ; lless input: first row
ll_y:   .fill 1                      ; lless input: second row
ll_i:   .fill 1                      ; lless scratch: compare column
ll_a:   .fill 1                      ; lless scratch: byte from row ll_x
ll_b:   .fill 1                      ; lless scratch: byte from row ll_y
lines:  .fill 10240                  ; 128 slots x 80 bytes flat line buffer
