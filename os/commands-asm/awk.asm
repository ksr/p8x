; awk.asm — hand-coded AWK command (asm counterpart of os/commands/awk.c).
;   awk [-F c] 'program' [file]
; program = [/regex/] { print items } ; items: $0 $N $NF NF NR "str" (comma=space).
; Records split on whitespace (or -F c). Input = file arg or stdin (pipes).
; The program is one quoted arg (awk strips the quotes; the shell doesn't).
; Shares nextc/openarg via `;#use stdin` and match() via `;#use regex`.
;#use stdin
;#use regex
;#use abi

; Entry: P2 = command-tail pointer (TPA2L/H). We keep our own running cursor
; in `aarg` (16-bit) and advance it byte-by-byte through the tail, parsing in
; order:  [spaces] [-h|-H] [-F c] 'program' [file].  After parsing we open the
; file arg (or stdin) and run the record loop.  No stack frame; all state lives
; in the .fill scratch vars at the bottom of the file.
        .org $6A00
        TPA2L
        STA aarg
        TPA2H
        STA aarg+1
        LDA #0
        STA sepc
; skip leading spaces
a_sk:   LDA aarg
        TAP2L
        LDA aarg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ a_h
        JSR aarg_inc
        JMP a_sk
a_h:    LDA (P2)                     ; -h / -H -> usage
        LDB #'-'
        CMP
        JNZ a_F
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ a_use
        LDB #'H'
        CMP
        JZ a_use
a_F:    LDA aarg                     ; -F c ?
        TAP2L
        LDA aarg+1
        TAP2H
        LDA (P2)
        LDB #'-'
        CMP
        JNZ a_prog
        INP2
        LDA (P2)
        LDB #'F'
        CMP
        JNZ a_prog                   ; "-x" that isn't -F -> treat as program (rare)
        ; consume "-F", skip spaces, sepc = next char, advance, skip spaces
        LDA aarg
        LDB #2
        ADD
        STA aarg
        JNC a_F1
        LDA aarg+1
        INC
        STA aarg+1
a_F1:   LDA aarg                     ; skip spaces
        TAP2L
        LDA aarg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ a_Fc
        JSR aarg_inc
        JMP a_F1
a_Fc:   LDA (P2)
        STA sepc
        LDA (P2)                     ; if sepc != 0, advance past it
        LDB #0
        CMP
        JZ a_Fsk
        JSR aarg_inc
a_Fsk:  LDA aarg                     ; skip spaces after the separator
        TAP2L
        LDA aarg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ a_prog
        JSR aarg_inc
        JMP a_Fsk
; ---- extract the program (quoted, else up to a space) ----
a_prog: LDA #<prog
        STA pp
        LDA #>prog
        STA pp+1
        LDA aarg
        TAP2L
        LDA aarg+1
        TAP2H
        LDA (P2)
        LDB #39                      ; single quote
        CMP
        JZ a_pq
        LDB #34                      ; double quote
        CMP
        JZ a_pq
        ; unquoted: copy until space/CR/NUL
a_pu:   LDA (P2)
        LDB #0
        CMP
        JZ a_pud
        LDB #13
        CMP
        JZ a_pud
        LDB #32
        CMP
        JZ a_pud
        JSR prog_put
        INP2
        JSR aarg_inc
        JMP a_pu
a_pud:  JMP a_pdone
a_pq:   STA aq                       ; quote char
        INP2
        JSR aarg_inc
a_pql:  LDA (P2)
        LDB #0
        CMP
        JZ a_pqd
        LDB aq
        CMP
        JZ a_pqe
        JSR prog_put
        INP2
        JSR aarg_inc
        JMP a_pql
a_pqe:  INP2                         ; consume the closing quote
        JSR aarg_inc
a_pqd:
; Copy done. NUL-terminate prog[] at pl, then hand off to parse_prog.
a_pdone: LDA #0                      ; NUL-terminate prog
        STA pp                       ; (pp used as scratch below — re-point)
        LDA #<prog
        LDB pl
        ADD
        TAP1L
        LDA #>prog
        JNC a_pn
        INC
a_pn:   TAP1H
        LDA #0
        STA (P1)
        JSR parse_prog
        ; ---- rest = input file, else stdin ----
a_rest: LDA aarg
        TAP2L
        LDA aarg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ a_open
        JSR aarg_inc
        JMP a_rest
a_open: LDA aarg
        STA oa_a
        LDA aarg+1
        STA oa_a+1
        JSR openarg                  ; openarg returns 2 in A on "file not found"
        LDB #2
        CMP
        JZ a_nf
        ; ---- main loop ----
        LDA #0
        STA nr
        STA nr+1
a_lp:   JSR readrec
        LDB #0
        CMP
        JZ a_end
        LDA nr                       ; nr++ (16-bit)
        LDB #1
        ADD
        STA nr
        JNC a_l1
        LDA nr+1
        INC
        STA nr+1
a_l1:   JSR split
        LDA hasre                    ; pattern?
        LDB #0
        CMP
        JZ a_run                     ; no pattern -> always
        LDA #<re
        STA rx_re
        LDA #>re
        STA rx_re+1
        LDA #<line
        STA rx_t
        LDA #>line
        STA rx_t+1
        JSR match
        LDB #0
        CMP
        JZ a_lp                      ; no match -> skip
a_run:  JSR run_action
        JMP a_lp
a_end:  RTS
a_nf:   LDA #<m_nf
        TAP1L
        LDA #>m_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
a_use:  LDA #<m_use
        TAP1L
        LDA #>m_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; aarg_inc: aarg += 1
aarg_inc: LDA aarg
        LDB #1
        ADD
        STA aarg
        JNC aai_r
        LDA aarg+1
        INC
        STA aarg+1
aai_r:  RTS

; prog_put: append A to prog[pl++] (cap 127)
prog_put: STA pptmp
        LDA pl
        LDB #127
        CMP
        JC pp_r                      ; pl >= 127 -> drop
        LDA #<prog
        LDB pl
        ADD
        TAP1L
        LDA #>prog
        JNC pp_n
        INC
pp_n:   TAP1H
        LDA pptmp
        STA (P1)
        LDA pl
        INC
        STA pl
pp_r:   RTS

; ---- parse_prog: prog -> re[] (hasre) + act[] ----
parse_prog: LDA #0
        STA hasre
        STA re
        STA act
        LDA #0
        STA ppi                      ; cursor into prog
pp_sk:  JSR prog_ch                  ; A = prog[ppi]
        LDB #32
        CMP
        JNZ pp_re
        JSR ppi_inc
        JMP pp_sk
pp_re:  JSR prog_ch
        LDB #'/'
        CMP
        JNZ pp_act
        JSR ppi_inc                  ; consume '/'
        LDA #0
        STA rei
pp_rl:  JSR prog_ch
        LDB #0
        CMP
        JZ pp_red
        LDB #'/'
        CMP
        JZ pp_res
        ; store into re[rei] (cap 79)
        LDA rei
        LDB #79
        CMP
        JC pp_rn
        JSR prog_ch
        STA rxb
        LDA #<re
        LDB rei
        ADD
        TAP1L
        LDA #>re
        JNC pp_rnn
        INC
pp_rnn: TAP1H
        LDA rxb
        STA (P1)
        LDA rei
        INC
        STA rei
pp_rn:  JSR ppi_inc
        JMP pp_rl
pp_res: JSR ppi_inc                  ; consume closing '/'
pp_red: LDA #<re                     ; NUL-terminate re[rei]
        LDB rei
        ADD
        TAP1L
        LDA #>re
        JNC pp_rd2
        INC
pp_rd2: TAP1H
        LDA #0
        STA (P1)
        LDA #1
        STA hasre
pp_act: JSR prog_ch                  ; skip spaces
        LDB #32
        CMP
        JNZ pp_ab
        JSR ppi_inc
        JMP pp_act
pp_ab:  JSR prog_ch
        LDB #'{'
        CMP
        JNZ pp_done
        JSR ppi_inc                  ; consume '{'
        LDA #0
        STA acti
pp_al:  JSR prog_ch
        LDB #0
        CMP
        JZ pp_ad
        LDB #'}'
        CMP
        JZ pp_ad
        LDA acti
        LDB #119
        CMP
        JC pp_an
        JSR prog_ch
        STA rxb
        LDA #<act
        LDB acti
        ADD
        TAP1L
        LDA #>act
        JNC pp_ann
        INC
pp_ann: TAP1H
        LDA rxb
        STA (P1)
        LDA acti
        INC
        STA acti
pp_an:  JSR ppi_inc
        JMP pp_al
pp_ad:  LDA #<act                    ; NUL-terminate act[acti]
        LDB acti
        ADD
        TAP1L
        LDA #>act
        JNC pp_ad2
        INC
pp_ad2: TAP1H
        LDA #0
        STA (P1)
pp_done: RTS

; prog_ch: A = prog[ppi]
prog_ch: LDA #<prog
        LDB ppi
        ADD
        TAP1L
        LDA #>prog
        JNC pc_n
        INC
pc_n:   TAP1H
        LDA (P1)
        RTS
ppi_inc: LDA ppi
        INC
        STA ppi
        RTS

; ---- readrec: read a record into line[]; A = 1 got one, 0 = EOF ----
readrec: LDA #0
        STA li
        JSR nextc
        JC rr_no
rr_lp:  STA rrc                      ; A = char
        LDB #10
        CMP
        JZ rr_end
        LDA rrc
        LDB #13
        CMP
        JZ rr_nx                     ; skip CR
        LDA li                       ; li < 255 ? store
        LDB #255
        CMP
        JC rr_nx
        LDA #<line
        LDB li
        ADD
        TAP1L
        LDA #>line
        JNC rr_s2
        INC
rr_s2:  TAP1H
        LDA rrc
        STA (P1)
        LDA li
        INC
        STA li
rr_nx:  JSR nextc
        JC rr_end
        JMP rr_lp
rr_end: LDA #<line                   ; NUL-terminate line[li]
        LDB li
        ADD
        TAP1L
        LDA #>line
        JNC rr_e2
        INC
rr_e2:  TAP1H
        LDA #0
        STA (P1)
        LDA #1
        RTS
rr_no:  LDA #0
        RTS

; ---- split: fill fstart/flen/nf from line[] using sepc ----
split:  LDA #0
        STA nf
        STA si
        LDA sepc
        LDB #0
        CMP
        JNZ sp_sep
; whitespace mode
sp_ws:  JSR line_ch                  ; A = line[si]
        LDB #0
        CMP
        JZ sp_dn
sp_wsk: JSR line_ch                  ; skip leading spaces/tabs
        LDB #32
        CMP
        JZ sp_wa
        LDB #9
        CMP
        JZ sp_wa
        JMP sp_wf
sp_wa:  JSR si_inc
        JMP sp_wsk
sp_wf:  JSR line_ch
        LDB #0
        CMP
        JZ sp_dn
        LDA si                       ; field start
        STA fst
sp_wfl: JSR line_ch
        LDB #0
        CMP
        JZ sp_wfe
        LDB #32
        CMP
        JZ sp_wfe
        LDB #9
        CMP
        JZ sp_wfe
        JSR si_inc
        JMP sp_wfl
sp_wfe: JSR emit_field
        JMP sp_ws
; explicit-separator mode
sp_sep: LDA #0
        STA fst
        STA si
sp_sl:  JSR line_ch
        LDB #0
        CMP
        JZ sp_slz                    ; end -> emit last field, done
        LDB sepc
        CMP
        JZ sp_ss                     ; separator -> emit field
        JSR si_inc
        JMP sp_sl
sp_ss:  JSR emit_field
        LDA si                       ; fst = si+1
        LDB #1
        ADD
        STA fst
        JSR si_inc
        JMP sp_sl
sp_slz: JSR emit_field
sp_dn:  RTS

; emit_field: record field [fst, si) if nf < 40
emit_field: LDA nf
        LDB #40
        CMP
        JC ef_r
        LDA #<fstart
        LDB nf
        ADD
        TAP1L
        LDA #>fstart
        JNC ef_n1
        INC
ef_n1:  TAP1H
        LDA fst
        STA (P1)
        LDA #<flen
        LDB nf
        ADD
        TAP1L
        LDA #>flen
        JNC ef_n2
        INC
ef_n2:  TAP1H
        LDA si                       ; len = si - fst
        LDB fst
        SUB
        STA (P1)
        LDA nf
        INC
        STA nf
ef_r:   RTS

; line_ch: A = line[si]
line_ch: LDA #<line
        LDB si
        ADD
        TAP1L
        LDA #>line
        JNC lc_n
        INC
lc_n:   TAP1H
        LDA (P1)
        RTS
si_inc: LDA si
        INC
        STA si
        RTS

; ---- pfield: print $A (0 = whole line, 1..nf = a field) ----
pfield: STA pf_fi
        LDB #0
        CMP
        JNZ pf_num
        ; $0 -> whole line
        LDA #0
        STA pf_i
pf0l:   LDA #<line
        LDB pf_i
        ADD
        TAP1L
        LDA #>line
        JNC pf0n
        INC
pf0n:   TAP1H
        LDA (P1)
        LDB #0
        CMP
        JZ pf_r
        JSR SYS_PUTC
        LDA pf_i
        INC
        STA pf_i
        JMP pf0l
pf_num: LDA pf_fi                     ; fi <= nf ?
        LDB nf
        CMP
        JZ pf_go                      ; fi == nf -> ok
        JC pf_r                       ; fi > nf  -> nothing
pf_go:  ; fi <= nf: index = fi-1
        LDA pf_fi
        LDB #1
        SUB
        STA pf_k
        ; start = fstart[k]
        LDA #<fstart
        LDB pf_k
        ADD
        TAP1L
        LDA #>fstart
        JNC pf_g1
        INC
pf_g1:  TAP1H
        LDA (P1)
        STA pf_st
        ; len = flen[k]
        LDA #<flen
        LDB pf_k
        ADD
        TAP1L
        LDA #>flen
        JNC pf_g2
        INC
pf_g2:  TAP1H
        LDA (P1)
        STA pf_ln
        ; print line[start .. start+len)
        LDA #0
        STA pf_j
pf_pl:  LDA pf_j
        LDB pf_ln
        CMP
        JC pf_r                      ; j >= len -> done
        LDA pf_st
        LDB pf_j
        ADD
        LDB #<line
        ADD
        TAP1L
        LDA #>line
        ; (start+j < 256 so at most one carry; recompute high with carry)
        LDA pf_st
        LDB pf_j
        ADD
        STA pf_ix
        LDA #<line
        LDB pf_ix
        ADD
        TAP1L
        LDA #>line
        JNC pf_pn
        INC
pf_pn:  TAP1H
        LDA (P1)
        JSR SYS_PUTC
        LDA pf_j
        INC
        STA pf_j
        JMP pf_pl
pf_r:   RTS

; ---- pnum: print the 16-bit value in dv as decimal (no leading zeros) ----
; Classic subtract-and-count: for each power of ten (10000,1000,100,10,1) held
; in pv, count how many times pv fits into dv (that digit), leaving the
; remainder in dv.  pd_any suppresses leading zeros; it is forced to 1 before
; the ones digit so a value of 0 still prints "0".  dv is destroyed. Uses A/B.
pnum:   LDA #0
        STA pd_any
        LDA #$10
        STA pv
        LDA #$27
        STA pv+1
        JSR pd_dig                   ; 10000
        LDA #$E8
        STA pv
        LDA #$03
        STA pv+1
        JSR pd_dig                   ; 1000
        LDA #100
        STA pv
        LDA #0
        STA pv+1
        JSR pd_dig                   ; 100
        LDA #10
        STA pv
        LDA #0
        STA pv+1
        JSR pd_dig                   ; 10
        LDA #1
        STA pv
        LDA #0
        STA pv+1
        LDA #1
        STA pd_any                   ; ones always print
        JSR pd_dig
        RTS
; pd_dig: emit one digit for the current place value pv. pd_n = digit count.
pd_dig: LDA #0
        STA pd_n
        ; 16-bit compare dv vs pv: high byte first; if equal fall through to
        ; compare low bytes. CMP sets C=1 when A>=B (unsigned).
pd_l:   LDA dv+1                     ; dv >= pv ? (16-bit)
        LDB pv+1
        CMP
        JZ pd_lo
        JC pd_ge
        JMP pd_d
pd_lo:  LDA dv
        LDB pv
        CMP
        JNC pd_d                     ; low byte borrows -> dv < pv, digit done
        ; 16-bit dv -= pv: subtract low byte; SUB clears C on borrow, so on
        ; borrow (JC not taken) decrement the high byte, then subtract pv high.
pd_ge:  LDA dv                       ; dv -= pv
        LDB pv
        SUB
        STA dv
        JC pd_nb
        LDA dv+1
        DEC
        STA dv+1
pd_nb:  LDA dv+1
        LDB pv+1
        SUB
        STA dv+1
        LDA pd_n
        INC
        STA pd_n
        JMP pd_l
pd_d:   LDA pd_n
        LDB #0
        CMP
        JNZ pd_pr
        LDA pd_any
        LDB #0
        CMP
        JZ pd_r
pd_pr:  LDA pd_n
        LDB #'0'
        ADD
        JSR SYS_PUTC
        LDA #1
        STA pd_any
pd_r:   RTS

; ---- run_action: interpret act = "print item, item, ..." ----
; Items: $0 $N $NF NF NR "str". A comma between items emits one space (OFS).
; rfirst: 1 = no item printed yet (suppress the leading OFS); cleared to 0 once
; the first item prints. At end, if rfirst is still 1 (`print` with no items),
; fall back to printing $0. A trailing newline always closes the record.
run_action: LDA #0
        STA aci                      ; cursor into act
        LDA #1
        STA rfirst                   ; no item printed yet
ra_sk:  JSR act_ch
        LDB #32
        CMP
        JNZ ra_chk
        JSR aci_inc
        JMP ra_sk
ra_chk: JSR act_ch
        LDB #0
        CMP
        JNZ ra_pr
        ; empty action -> print $0 + newline
        LDA #0
        JSR pfield
        LDA #10
        JSR SYS_PUTC
        RTS
ra_pr:  ; expect "print"
        JSR act_ch
        LDB #'p'
        CMP
        JNZ ra_lp
        LDA aci
        LDB #5
        ADD
        STA aci                      ; skip "print"
ra_lp:  JSR act_ch
        LDB #32
        CMP
        JNZ ra_c1
        JSR aci_inc
        JMP ra_lp
ra_c1:  JSR act_ch                   ; comma?
        LDB #44
        CMP
        JNZ ra_c2
        JSR aci_inc
ra_cs:  JSR act_ch
        LDB #32
        CMP
        JNZ ra_c2
        JSR aci_inc
        JMP ra_cs
ra_c2:  JSR act_ch                   ; end of items?
        LDB #0
        CMP
        JZ ra_end
        ; OFS between items
        LDA rfirst
        LDB #0
        CMP
        JNZ ra_it                    ; rfirst != 0 (first item) -> no OFS
        LDA #32
        JSR SYS_PUTC
ra_it:  LDA #0
        STA rfirst                   ; an item is being printed
        JSR act_ch                   ; item type
        LDB #34                      ; "string"
        CMP
        JZ ra_str
        LDB #'$'
        CMP
        JZ ra_fld
        LDB #'N'
        CMP
        JZ ra_N
        JSR aci_inc                  ; unknown -> skip one char
        JMP ra_lp
ra_str: JSR aci_inc                  ; consume opening quote
ra_stl: JSR act_ch
        LDB #0
        CMP
        JZ ra_lp
        LDB #34
        CMP
        JZ ra_ste
        JSR act_ch
        JSR SYS_PUTC
        JSR aci_inc
        JMP ra_stl
ra_ste: JSR aci_inc                  ; consume closing quote
        JMP ra_lp
ra_fld: JSR aci_inc                  ; consume '$'
        JSR act_ch
        LDB #'N'
        CMP
        JNZ ra_fnum
        ; $NF ?
        LDA aci
        INC
        STA actmp
        JSR act_at                   ; A = act[aci+1]
        LDB #'F'
        CMP
        JNZ ra_fnum                  ; "$N" but not "$NF" -> treat as number 0
        LDA aci
        LDB #2
        ADD
        STA aci                      ; skip "NF"
        LDA nf
        JSR pfield
        JMP ra_lp
ra_fnum: LDA #0
        STA fnum
ra_fdl: JSR act_ch
        LDB #'0'
        CMP
        JNC ra_fde                   ; < '0'
        LDB #':'                     ; '9'+1
        CMP
        JC ra_fde                    ; > '9'
        ; digit: fnum = fnum*10 + (c-'0'); 10*x built as (x<<1)+(x<<3)
        LDA fnum
        SHL
        STA ftmp                     ; *2
        LDA fnum
        SHL
        SHL
        SHL                          ; *8
        LDB ftmp
        ADD                          ; *10
        STA fnum
        JSR act_ch
        LDB #'0'
        SUB
        LDB fnum
        ADD
        STA fnum
        JSR aci_inc
        JMP ra_fdl
ra_fde: LDA fnum
        JSR pfield
        JMP ra_lp
ra_N:   ; NR or NF
        LDA aci
        INC
        STA actmp
        JSR act_at
        LDB #'R'
        CMP
        JNZ ra_NF
        LDA aci
        LDB #2
        ADD
        STA aci
        LDA nr
        STA dv
        LDA nr+1
        STA dv+1
        JSR pnum
        JMP ra_lp
ra_NF:  LDB #'F'
        CMP
        JNZ ra_Nsk
        LDA aci
        LDB #2
        ADD
        STA aci
        LDA nf
        STA dv
        LDA #0
        STA dv+1
        JSR pnum
        JMP ra_lp
ra_Nsk: JSR aci_inc
        JMP ra_lp
ra_end: LDA rfirst                   ; `print` with no items -> $0
        LDB #0
        CMP
        JZ ra_nl                     ; rfirst == 0 (items printed) -> no $0
        LDA #0
        JSR pfield
ra_nl:  LDA #10
        JSR SYS_PUTC
        RTS

; act_ch: A = act[aci]
act_ch: LDA #<act
        LDB aci
        ADD
        TAP1L
        LDA #>act
        JNC ac_n
        INC
ac_n:   TAP1H
        LDA (P1)
        RTS
; act_at: A = act[actmp]
act_at: LDA #<act
        LDB actmp
        ADD
        TAP1L
        LDA #>act
        JNC aa_n
        INC
aa_n:   TAP1H
        LDA (P1)
        RTS
aci_inc: LDA aci
        INC
        STA aci
        RTS

m_nf:   .asciiz "awk: not found"
m_use:  .asciiz "usage: awk [-F c] '[/re/]{print items}' [file]   items: $0 $N NF NR \"str\""

; ---- scratch / state (uninitialized RAM; flat global labels) ----
; aarg  = running cursor through the command tail
; sepc  = field separator from -F (0 = whitespace mode)
; nr/nf = record number (16-bit) / field count for current line
; re[]  = compiled regex pattern; act[] = action body; prog[] = raw program
; line[]= current record; fstart[]/flen[] = field offsets+lengths within line[]
aarg:   .fill 2
sepc:   .fill 1
pp:     .fill 2
pl:     .fill 1
pptmp:  .fill 1
aq:     .fill 1
ppi:    .fill 1
rei:    .fill 1
acti:   .fill 1
rxb:    .fill 1
nr:     .fill 2
nf:     .fill 1
li:     .fill 1
rrc:    .fill 1
si:     .fill 1
fst:    .fill 1
pf_fi:  .fill 1
pf_i:   .fill 1
pf_k:   .fill 1
pf_st:  .fill 1
pf_ln:  .fill 1
pf_j:   .fill 1
pf_ix:  .fill 1
dv:     .fill 2
pv:     .fill 2
pd_n:   .fill 1
pd_any: .fill 1
aci:    .fill 1
rfirst: .fill 1
actmp:  .fill 1
fnum:   .fill 1
ftmp:   .fill 1
hasre:  .fill 1
re:     .fill 80
act:    .fill 120
prog:   .fill 128
line:   .fill 256
fstart: .fill 40
flen:   .fill 40
