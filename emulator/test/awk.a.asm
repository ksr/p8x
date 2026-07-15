; awk.asm — hand-coded AWK command (asm counterpart of os/commands/awk.c).
;   awk [-F c] 'program' [file]
; program = [/regex/] { print items } ; items: $0 $N $NF NF NR "str" (comma=space).
; Records split on whitespace (or -F c). Input = file arg or stdin (pipes).
; The program is one quoted arg (awk strips the quotes; the shell doesn't).
; Shares nextc/openarg via `;#use stdin` and match() via `;#use regex`.
; (spliced below by mkasm.sh) use stdin
; (spliced below by mkasm.sh) use regex
; (spliced below by mkasm.sh) use abi

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

; lib_abi.inc — the BIOS/OS entry-point address book for hand-asm /BIN commands.
; A twin declares `;#use abi` and mkasm.sh appends this file, after which it can
; `JSR FOPEN` / `JSR SYS_PUTC` instead of hand-coding `JSR $0124` / `JSR $2009`.
;
; These are pure equates: they emit NO bytes, so a twin that switches its raw
; `JSR $NNNN` calls to symbolic ones assembles to the byte-identical binary — the
; magic numbers just get names, and the firmware jump table / syscall vector can
; be renumbered by editing this one file. (The C side splits the same names across
; lib_fsread/fswrite/fsdir/con.c because there each wrapper costs code space; on
; the asm side an equate is free, so one address book is simplest.)
;
; Unused equates are harmless, so a twin can blanket `;#use abi` even if it only
; needs a couple — which also lets a shared include, e.g. lib_stdin.inc, use these
; names as long as its host command pulls in this file too.

; --- OS syscalls ($20xx) — the redirectable stream + FS/CWD calls ---
SYS_GETCWD   = $2003    ; copy CWD path string -> (P1), incl. NUL
SYS_CWDLBA   = $2006    ; CWD directory start LBA -> A
SYS_PUTC     = $2009    ; A -> current stdout (console or redirected file)
SYS_GETC     = $200C    ; next stdin byte -> A (carry/EOF per ABI)
SYS_PUTS     = $200F    ; write (P1) string to stdout
SYS_OPENCWD  = $2012    ; begin iterating the CWD (16-bit LBA)
; Note the gap: $2015/$2018 are reserved/unused vectors, so the numbering
; jumps from $2012 straight to $201B — keep new syscalls at the +3 stride.
SYS_DIRENTRY = $201B    ; snapshot the current dir entry -> (P1) 18 bytes
SYS_OPENDIR  = $201E    ; P1 = 16-bit dir start LBA -> open for FNEXT
SYS_MKDIR    = $2021    ; P1 = path -> create a directory; C=1 on real failure

; --- BIOS jump table ($01xx) ---
CONIN      = $0100      ; wait for key, char -> A (raw console, not stdin)
CONOUT     = $0103      ; A -> serial (raw console, not stdout)
PUTS       = $0112      ; print (P1)+ until $00 (raw console)
PHEX8      = $0115      ; print A as two hex digits
FFIND      = $0118      ; root file FNAME -> LBA+FLEN; C=0 found
FCREATE    = $011B      ; create root file FNAME from FSRC/FLEN; C=1 err
FDELETE    = $011E      ; tombstone root file FNAME; C=1 not found
FCOMMIT    = $0121      ; register streamed file (entry+free); C=1 full
FOPEN      = $0124      ; open file FNAME for reading (P1=buffer); C=1 missing
; FGETB/FPUTB stream one byte at a time and clobber P1/P2 (they walk the
; sector buffer), so save any live pointer regs around the call.
FGETB      = $0127      ; next byte -> A; C=1 at end of file
FWOPEN     = $012A      ; open a write stream at the free pointer (uses SBUF)
FPUTB      = $012D      ; append byte A to the write stream
FCLOSE     = $0130      ; flush + register file FNAME; C=1 full
FRESOLVE   = $0133      ; resolve path (P1) -> dir extent + leaf FNAME; C=1 bad path
FNORM      = $0136      ; copy string (P1) -> FNAME, case-preserved, padded to 12
FOPENDIR   = $0139      ; begin iterating directory at path (P1); C=1 bad path
FNEXT      = $013C      ; next live entry -> FNAME/FFLAG/LBA/FLEN; C=1 at end
FLOADAT    = $013F      ; read FLEN bytes from LBA into (P1) (whole sectors)
FOPENDIRAT = $0142      ; iterate the 4-sector directory at LBA = A (low)+LBA1 (high)
FSDIRBUF   = $0145      ; point FNEXT's sector buffer at page A (call after FOPENDIR)

; lib_regex.inc — shared basic-regex matcher for hand-asm grep/sed (asm
; counterpart of lib_regex.c). Declared with `;#use regex`.
;   match    : rx_re / rx_t (word ptrs) -> A = 1 if re matches anywhere in t
;   matchhere: 1 if re matches a prefix of t; sets rend past the match
; Dialect: . any, * >=0, + >=1, ? 0/1 of the preceding char (or '.'), ^ start,
; $ end. Recursive; re/t live in memory words, saved on the hardware stack across
; non-tail recursive calls (P3 is the stack pointer). Non-greedy (fewest first).

rend:   .fill 2                       ; ptr one past the last char matched (set by matchhere)

; match(rx_re, rx_t) -> A = 1 if re matches anywhere in t, else 0.
; If re starts with '^' it only tries at t's start; otherwise it slides the
; start point right one char at a time until a match or end-of-text.
; Clobbers A/B/P1; uses rx_* scratch. mre/mct hold the saved re/t across the slide.
match:  LDA rx_re                    ; P1 <- rx_re, then peek first regex char
        TAP1L
        LDA rx_re+1
        TAP1H
        LDA (P1)
        LDB #'^'
        CMP
        JNZ m_loop
        LDA rx_re                    ; anchored '^': advance re past it, then matchhere(re+1, t)
        LDB #1
        ADD
        STA rx_re
        JNC m_a
        LDA rx_re+1
        INC
        STA rx_re+1
m_a:    JMP matchhere                ; tail call; its RTS returns to match's caller
; Unanchored: save the working re/t in mre/mct, then try each start position.
m_loop: LDA rx_re
        STA mre
        LDA rx_re+1
        STA mre+1
        LDA rx_t
        STA mct
        LDA rx_t+1
        STA mct+1
; Loop: restore re/t from the saved copies (matchhere mutates rx_re/rx_t) and try.
m_pl:   LDA mre
        STA rx_re
        LDA mre+1
        STA rx_re+1
        LDA mct
        STA rx_t
        LDA mct+1
        STA rx_t+1
        JSR matchhere
        LDB #0
        CMP
        JNZ m_yes                     ; matched at this start position -> done
        LDA mct                       ; else: if *mct == 0 we've exhausted the text
        TAP1L
        LDA mct+1
        TAP1H
        LDA (P1)
        LDB #0
        CMP
        JZ m_no
        LDA mct                       ; advance saved text ptr and retry one char over
        LDB #1
        ADD
        STA mct
        JNC m_pl
        LDA mct+1
        INC
        STA mct+1
        JMP m_pl
m_yes:  LDA #1
        RTS
m_no:   LDA #0
        RTS

; matchhere(rx_re, rx_t) -> A = 1 if re matches a PREFIX of t, else 0.
; On success sets rend to the text ptr just past the match. Recursive: literal
; match tail-recurses; the *, +, ? branches recurse via JSR matchhere and save
; their loop state on the hardware stack (P3) across the call.
; rx_c = re[0] (the char being matched), rx_r1 = re[1] (possible quantifier).
matchhere:
        LDA rx_re
        TAP1L
        LDA rx_re+1
        TAP1H
        LDA (P1)
        STA rx_c                      ; rx_c = re[0]
        INP1
        LDA (P1)
        STA rx_r1                     ; rx_r1 = re[1] (look one ahead for * + ?)
        LDA rx_c
        LDB #0
        CMP
        JZ mh_chk0                    ; re[0]==0 (end of pattern): skip quantifier checks
        LDA rx_r1
        LDB #'*'
        CMP
        JZ mh_star
        LDA rx_r1
        LDB #'+'
        CMP
        JZ mh_plus
        LDA rx_r1
        LDB #'?'
        CMP
        JZ mh_ques
; Empty pattern matches here: record end ptr = current text ptr, return 1.
mh_chk0:LDA rx_c
        LDB #0
        CMP
        JNZ mh_dollar
        LDA rx_t
        STA rend
        LDA rx_t+1
        STA rend+1
        LDA #1
        RTS
; '$' end-anchor, only special when it is the last pattern char (re[1]==0).
mh_dollar:
        LDA rx_c
        LDB #'$'
        CMP
        JNZ mh_lit
        LDA rx_r1
        LDB #0
        CMP
        JNZ mh_lit                    ; '$' not at end of pattern -> treat as literal
        LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        LDB #0
        CMP
        JNZ mh_r0
        LDA rx_t
        STA rend
        LDA rx_t+1
        STA rend+1
        LDA #1                        ; '$' matched: at end of text -> success
        RTS
; Single literal char (or '.'): must match one text char, then advance both.
mh_lit: LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        STA rx_tc                     ; rx_tc = current text char
        LDB #0
        CMP
        JZ mh_r0                      ; text exhausted -> fail
        LDA rx_c
        LDB #'.'
        CMP
        JZ mh_adv                     ; '.' matches any char
        LDA rx_c
        LDB rx_tc
        CMP
        JZ mh_adv                     ; exact char match
mh_r0:  LDA #0                        ; common failure exit
        RTS
mh_adv: LDA rx_re                     ; re++ , t++ , then tail-recurse into matchhere
        LDB #1
        ADD
        STA rx_re
        JNC mha1
        LDA rx_re+1
        INC
        STA rx_re+1
mha1:   LDA rx_t
        LDB #1
        ADD
        STA rx_t
        JNC mha2
        LDA rx_t+1
        INC
        STA rx_t+1
mha2:   JMP matchhere
mh_r1:  LDA #1                        ; common success exit
        RTS

; --- c* : zero or more --------------------------------------------------
; c* : cc=the char, re2=re+2 (pattern after 'c*'), ct=t (zero matches to start).
; Non-greedy: try matching the rest at ct first, then consume one 'c' and retry.
mh_star:LDA rx_c
        STA rx_cc
        JSR re2                       ; rx_re2 = rx_re + 2
        LDA rx_t
        STA rx_ct
        LDA rx_t+1
        STA rx_ct+1
        JMP mstar_l
; --- c+ : one or more ---------------------------------------------------
; c+ : like c* but requires at least one 'c'. Verify t[0] matches c, then enter
; the shared loop starting at ct=t+1 (one char already consumed).
mh_plus:LDA rx_c
        STA rx_cc
        LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        STA rx_tc
        LDB #0
        CMP
        JZ mh_r0                      ; text exhausted -> no first match -> fail
        LDA rx_cc
        LDB #'.'
        CMP
        JZ mp_ok                      ; '.' matches the first char
        LDA rx_tc
        LDB rx_cc
        CMP
        JNZ mh_r0                     ; first text char != c -> fail
mp_ok:  JSR re2
        LDA rx_t                      ; ct = t+1
        LDB #1
        ADD
        STA rx_ct
        LDA rx_t+1
        JNC mp1
        INC
mp1:    STA rx_ct+1
        JMP mstar_l
; shared star/plus loop over rx_ct (re2 fixed, cc = the char)
; Shared *, + loop. Each pass: point re at re2 and t at ct, then try matchhere
; on the tail. Because matchhere clobbers rx_re/rx_t/rx_re2/rx_ct/rx_cc (and
; recursion nests), save cc/re2/ct on the hardware stack around the JSR and
; restore after. On success -> mh_r1; else consume one more 'c' and loop.
mstar_l:LDA rx_re2
        STA rx_re
        LDA rx_re2+1
        STA rx_re+1
        LDA rx_ct
        STA rx_t
        LDA rx_ct+1
        STA rx_t+1
        LDA rx_cc                     ; push loop state (pulled back in reverse order)
        PHA
        LDA rx_re2
        PHA
        LDA rx_re2+1
        PHA
        LDA rx_ct
        PHA
        LDA rx_ct+1
        PHA
        JSR matchhere
        STA rx_res                    ; save result before restoring registers
        PLA
        STA rx_ct+1
        PLA
        STA rx_ct
        PLA
        STA rx_re2+1
        PLA
        STA rx_re2
        PLA
        STA rx_cc
        LDA rx_res
        LDB #0
        CMP
        JNZ mh_r1                     ; tail matched -> whole quantifier matched
        LDA rx_ct                     ; tail failed: can we consume one more 'c'?
        TAP1L
        LDA rx_ct+1
        TAP1H
        LDA (P1)
        STA rx_tc
        LDB #0
        CMP
        JZ mh_r0                      ; text exhausted -> fail
        LDA rx_cc
        LDB #'.'
        CMP
        JZ mstar_adv                  ; '.' consumes any char
        LDA rx_tc
        LDB rx_cc
        CMP
        JNZ mh_r0                     ; next char isn't 'c' -> can't extend -> fail
mstar_adv:                            ; ct++ and loop for another try
        LDA rx_ct
        LDB #1
        ADD
        STA rx_ct
        JNC mstar_l
        LDA rx_ct+1
        INC
        STA rx_ct+1
        JMP mstar_l
; --- c? : zero or one ---------------------------------------------------
; c? : zero or one 'c'. Non-greedy would try zero first, but here the "one"
; branch is attempted first only when the char actually matches; on failure it
; falls through to mq_zero (the zero-width tail). If t[0] can't match c, skip
; straight to mq_zero.
mh_ques:LDA rx_t
        TAP1L
        LDA rx_t+1
        TAP1H
        LDA (P1)
        STA rx_tc
        LDB #0
        CMP
        JZ mq_zero                    ; text exhausted -> only the zero branch
        LDA rx_c
        LDB #'.'
        CMP
        JZ mq_one                     ; '.' matches -> try consuming one
        LDA rx_tc
        LDB rx_c
        CMP
        JNZ mq_zero                   ; char mismatch -> zero branch only
; "one" branch: save re/t, try matchhere(re+2, t+1); on fail restore and fall
; through to the "zero" branch.
mq_one: LDA rx_re                     ; try matchhere(re+2, t+1)
        PHA
        LDA rx_re+1
        PHA
        LDA rx_t
        PHA
        LDA rx_t+1
        PHA
        JSR re2
        LDA rx_re2
        STA rx_re
        LDA rx_re2+1
        STA rx_re+1
        LDA rx_t
        LDB #1
        ADD
        STA rx_t
        JNC mq1
        LDA rx_t+1
        INC
        STA rx_t+1
mq1:    JSR matchhere
        STA rx_res
        PLA
        STA rx_t+1
        PLA
        STA rx_t
        PLA
        STA rx_re+1
        PLA
        STA rx_re
        LDA rx_res
        LDB #0
        CMP
        JNZ mh_r1                     ; the "one" branch matched -> success
mq_zero:JSR re2                       ; tail: matchhere(re+2, t)  (skip 'c?' entirely)
        LDA rx_re2
        STA rx_re
        LDA rx_re2+1
        STA rx_re+1
        JMP matchhere

; re2: helper computing rx_re2 = rx_re + 2 (skip a char and its quantifier).
; 16-bit add with carry into the high byte. Clobbers A/B. Returns via RTS.
re2:    LDA rx_re
        LDB #2
        ADD
        STA rx_re2
        LDA rx_re+1
        JNC re2a
        INC
re2a:   STA rx_re2+1
        RTS

; --- scratch state (module-global; regex is not reentrant across calls) -------
rx_re:  .fill 2                       ; current regex pointer (matchhere input)
rx_t:   .fill 2                       ; current text pointer (matchhere input)
rx_re2: .fill 2                       ; re+2, pattern tail after a quantified char
rx_ct:  .fill 2                       ; text cursor for the *, + scan loop
rx_c:   .fill 1                       ; re[0], the char currently being matched
rx_r1:  .fill 1                       ; re[1], the possible quantifier (* + ?)
rx_tc:  .fill 1                       ; current text char under test
rx_cc:  .fill 1                       ; the char repeated by a *, + quantifier
rx_res: .fill 1                       ; saved matchhere result across stack restore
mre:    .fill 2                       ; saved regex ptr for the unanchored slide
mct:    .fill 2                       ; saved text start ptr for the unanchored slide

; lib_stdin.inc — shared "file(s)-or-stdin input" helpers for hand-asm /BIN
; commands (asm counterpart of lib_stdin.c + lib_globx.c + lib_glob.c). A command
; declares `;#use stdin` and mkasm.sh appends this file (mirroring clib.py's
; //#use splice), so wc/head/tail/uniq/cat share one copy of the open/read/glob
; logic — and each binary counts it, keeping the size comparison fair.
;
; Entry points (args/returns via memory words; P3 is the stack pointer so only
; P1/P2 are used, and a pointer cursor is reloaded after any syscall):
;   openarg      : oa_a = arg word -> A = 0 stdin / 1 opened / 2 not found
;                  (also sets `fromfile`; a *|? glob is expanded and read as one
;                  concatenated stream)
;   nextc        : -> A = next byte, carry SET at EOF (spans glob matches)
;   open_path    : op_a = path word -> A = 1 opened / 2 not found (read buf $FC00)
;   glob_expand  : ge_pat/ge_out/ge_max -> ge_cnt files, ge_out[i*64] = path
;   gmatch       : gp/gs -> A = 1 if pattern gp matches string gs (case-insens.)
;
; BIOS: FGETB $0127, FRESOLVE $0133, FOPEN $0124, FOPENDIR $0139, FNEXT $013C,
; FSDIRBUF $0145, SYS_DIRENTRY $201B. OS: SYS_GETCWD $2003, SYS_GETC $200C,
; SYS_OPENCWD $2012.

; ---- openarg --------------------------------------------------------------
; Decide how to source input for one argv word.
;   in : oa_a  = pointer to the arg string (word)
;   out: A = 0 read from stdin (empty/CR arg), 1 opened a file, 2 not found
;        fromfile set; on a *|? arg, gfiles[]/gnf hold the expanded match list
;        and the first match is opened (nextc walks the rest).
; Clobbers A/B/P2; leaves the open file positioned at byte 0.
openarg:
        LDA #0
        STA fromfile
        STA gnf
        STA gidx
        LDA oa_a
        TAP2L
        LDA oa_a+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ oa_stdin
        LDB #13
        CMP
        JZ oa_stdin
        LDA #0
        STA oa_g
        LDA oa_a
        TAP2L
        LDA oa_a+1
        TAP2H
oa_scl: LDA (P2)                       ; scan arg for a '*' or '?' -> oa_g (is-glob)
        LDB #0
        CMP
        JZ oa_scd
        LDB #13
        CMP
        JZ oa_scd
        LDB #32
        CMP
        JZ oa_scd
        LDB #'*'
        CMP
        JZ oa_setg
        LDB #'?'
        CMP
        JZ oa_setg
        INP2
        JMP oa_scl
oa_setg:LDA #1
        STA oa_g
        INP2
        JMP oa_scl
oa_scd: LDA oa_g
        LDB #0
        CMP
        JZ oa_single
        LDA oa_a                      ; glob: ge = glob_expand(arg, gfiles, 24)
        STA ge_pat
        LDA oa_a+1
        STA ge_pat+1
        LDA #<gfiles
        STA ge_out
        LDA #>gfiles
        STA ge_out+1
        LDA #24
        STA ge_max
        JSR glob_expand
        LDA ge_cnt
        STA gnf
        LDB #0
        CMP
        JZ oa_nf
        LDA #1
        STA fromfile
        LDA #<gfiles
        STA op_a
        LDA #>gfiles
        STA op_a+1
        JSR open_path
        RTS
oa_single:
        LDA #1
        STA fromfile
        LDA oa_a
        STA op_a
        LDA oa_a+1
        STA op_a+1
        JSR open_path
        RTS
oa_stdin:
        LDA #0
        RTS
oa_nf:  LDA #2
        RTS

; ---- nextc ----------------------------------------------------------------
; Return the next input byte, transparently spanning glob matches.
;   out: A = byte, carry CLEAR on success / SET at end-of-input
; On file EOF it advances gidx to the next glob match and reopens; when no
; more matches remain it reports EOF. Clobbers A/B/P1/P2 (FGETB clobbers P1/P2).
nextc:  LDA fromfile
        LDB #0
        CMP
        JNZ nc_file
        LDA #0
        JSR $200C                     ; stdin: A=byte, C=EOF (passthrough)
        RTS
nc_file:LDA #0
        JSR $0127                     ; FGETB
        JNC nc_ok
nc_adv: LDA gnf                       ; end of current file
        LDB #0
        CMP
        JZ nc_eof                     ; single file -> done
        LDA gidx
        INC
        STA gtmp
        LDA gtmp
        LDB gnf
        CMP                           ; CMP sets C when gtmp(=gidx+1) >= gnf
        JC nc_eof                     ; gidx+1 >= gnf -> done
        LDA gtmp
        STA gidx
        JSR gfile_ptr                 ; op_a = &gfiles[gidx*64]
        JSR open_path
        LDA #0
        JSR $0127
        JNC nc_ok
        JMP nc_adv
nc_ok:  CLC
        RTS
nc_eof: SEC
        RTS

; gfile_ptr: op_a = &gfiles[gidx]  (64-byte fixed-stride path slots)
; Computes gidx*64 by repeated add (no MUL), then adds the gfiles base as a
; 16-bit sum via gcarry. In: gidx. Out: op_a word. Clobbers A/B, gtmp2, gcarry.
gfile_ptr:
        LDA #0
        STA op_a
        STA op_a+1
        LDA gidx
        STA gtmp2
gfp_l:  LDA gtmp2
        LDB #0
        CMP
        JZ gfp_d
        LDA op_a
        LDB #64
        ADD
        STA op_a
        JNC gfp_1
        LDA op_a+1
        INC
        STA op_a+1
gfp_1:  LDA gtmp2
        DEC
        STA gtmp2
        JMP gfp_l
gfp_d:  LDA op_a
        LDB #<gfiles
        ADD
        STA op_a
        LDA #0
        JNC gfp_2
        LDA #1
gfp_2:  STA gcarry
        LDA op_a+1
        LDB #>gfiles
        ADD
        LDB gcarry
        ADD
        STA op_a+1
        RTS

; ---- open_path (abspath + FRESOLVE + FOPEN) -------------------------------
; Open the file named by op_a into the read buffer at $FC00.
;   in : op_a = path word (relative or absolute)
;   out: A = 1 opened / 2 not found
; A relative path (no leading '/') is prefixed with SYS_GETCWD into spath so
; FRESOLVE/FOPENDIR, which start at root rather than CWD, resolve it correctly.
; Clobbers A/B/P1/P2 and spath.
open_path:
        LDA op_a
        TAP2L
        LDA op_a+1
        TAP2H
        LDA (P2)
        LDB #'/'
        CMP
        JZ opa_abs
        LDA #<spath                   ; relative -> SYS_GETCWD(spath)
        TAP1L
        LDA #>spath
        TAP1H
        LDA #0
        JSR $2003
        LDA #<spath
        TAP1L
        LDA #>spath
        TAP1H
opa_sl: LDA (P1)
        LDB #0
        CMP
        JZ opa_sld
        INP1
        JMP opa_sl
opa_sld:DEP1
        LDA (P1)
        INP1
        LDB #'/'
        CMP
        JZ opa_cp
        LDA #'/'
        STA (P1)+
        JMP opa_cp
opa_abs:LDA #<spath
        TAP1L
        LDA #>spath
        TAP1H
opa_cp: LDA op_a                      ; reload source (SYS_GETCWD clobbered P2)
        TAP2L
        LDA op_a+1
        TAP2H
opa_cl: LDA (P2)
        LDB #0
        CMP
        JZ opa_end
        LDB #13
        CMP
        JZ opa_end
        LDB #32
        CMP
        JZ opa_end
        STA (P1)+
        INP2
        JMP opa_cl
opa_end:LDA #0
        STA (P1)
        LDA #<spath
        TAP1L
        LDA #>spath
        TAP1H
        LDA #0
        JSR $0133                     ; FRESOLVE
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR $0124                     ; FOPEN $FC00
        JC opa_nf
        LDA #1
        RTS
opa_nf: LDA #2
        RTS

; ---- glob_expand ----------------------------------------------------------
; Expand a single *|? pattern into a list of matching regular-file paths.
;   in : ge_pat = pattern word, ge_out = dest array word, ge_max = slot cap
;   out: ge_cnt files written, ge_out[i*64] = full path (dir prefix + name)
; The pattern is split at its last '/': ge_dir holds the directory prefix
; (or none -> current dir via SYS_OPENCWD) and ge_leaf the wildcard leaf.
; Directory is read with FSDIRBUF at page $FA; entries are matched with gmatch,
; '.'-prefixed and non-regular (de+12 != 1) entries skipped, and the list is
; truncated at ge_max. Clobbers A/B/P1/P2 and most ge_* scratch.
glob_expand:
        LDA #0
        STA ge_hs
        STA ge_sp
        STA ge_pl
        LDA ge_pat
        TAP2L
        LDA ge_pat+1
        TAP2H
ge_scl: LDA (P2)                       ; scan pattern; ge_sp=last '/' index, ge_hs=has-slash
        LDB #0
        CMP
        JZ ge_scd
        LDB #13
        CMP
        JZ ge_scd
        LDB #32
        CMP
        JZ ge_scd
        LDB #'/'
        CMP
        JNZ ge_sci
        LDA ge_pl
        STA ge_sp
        LDA #1
        STA ge_hs
ge_sci: INP2
        LDA ge_pl
        INC
        STA ge_pl
        JMP ge_scl
ge_scd: LDA #0
        STA ge_ls
        STA ge_dir
        LDA ge_hs
        LDB #0
        CMP
        JZ ge_leaf0
        LDA ge_sp
        INC
        STA ge_ls
        LDA ge_pat                    ; ge_dir = pat[0..slashpos]
        TAP2L
        LDA ge_pat+1
        TAP2H
        LDA #<ge_dir
        TAP1L
        LDA #>ge_dir
        TAP1H
        LDA #0
        STA ge_j
ge_dl:  LDA (P2)
        STA (P1)+
        INP2
        LDA ge_j
        LDB ge_sp
        CMP
        JZ ge_dde
        LDA ge_j
        INC
        STA ge_j
        JMP ge_dl
ge_dde: LDA #0
        STA (P1)
ge_leaf0:
        LDA ge_pat                    ; P2 = pat + ls
        LDB ge_ls
        ADD
        TAP2L
        LDA ge_pat+1
        JNC ge_l0
        INC
ge_l0:  TAP2H
        LDA #<ge_leaf
        TAP1L
        LDA #>ge_leaf
        TAP1H
        LDA ge_ls
        STA ge_j
ge_ll:  LDA ge_j
        LDB ge_pl
        CMP
        JZ ge_lle
        LDA (P2)
        STA (P1)+
        INP2
        LDA ge_j
        INC
        STA ge_j
        JMP ge_ll
ge_lle: LDA #0
        STA (P1)
        LDA ge_hs                     ; open the directory
        LDB #0
        CMP
        JZ ge_ocwd
        LDA #<ge_dir
        TAP1L
        LDA #>ge_dir
        TAP1H
        LDA #0
        JSR $0139                     ; FOPENDIR(dir)
        JMP ge_fsd
ge_ocwd:LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $2012                     ; SYS_OPENCWD
ge_fsd: LDA #0
        TAP1L
        TAP1H
        LDA #$FA
        JSR $0145                     ; FSDIRBUF $FA
        LDA #0
        STA ge_cnt
ge_nl:  LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR $013C                     ; FNEXT
        JC ge_gdone
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR $201B                     ; de_read
        LDA de
        LDB #'.'
        CMP
        JZ ge_nl
        LDA de+12
        LDB #1
        CMP
        JNZ ge_nl                     ; files only
        LDA #<de                      ; trim name -> ge_nm
        TAP2L
        LDA #>de
        TAP2H
        LDA #<ge_nm
        TAP1L
        LDA #>ge_nm
        TAP1H
        LDA #0
        STA ge_j
ge_tl:  LDA ge_j
        LDB #12
        CMP
        JZ ge_tld
        LDA (P2)
        LDB #32
        CMP
        JZ ge_tld
        STA (P1)+
        INP2
        LDA ge_j
        INC
        STA ge_j
        JMP ge_tl
ge_tld: LDA #0
        STA (P1)
        LDA #<ge_leaf
        STA gp
        LDA #>ge_leaf
        STA gp+1
        LDA #<ge_nm
        STA gs
        LDA #>ge_nm
        STA gs+1
        JSR gmatch
        LDB #0
        CMP
        JZ ge_nl                      ; no match
        LDA ge_cnt
        LDB ge_max
        CMP
        JC ge_nl                      ; cnt >= max -> drop
        JSR ge_slot                   ; P1 = ge_out + cnt*64
        LDA #<ge_dir
        TAP2L
        LDA #>ge_dir
        TAP2H
ge_od:  LDA (P2)
        LDB #0
        CMP
        JZ ge_odn
        STA (P1)+
        INP2
        JMP ge_od
ge_odn: LDA #<ge_nm
        TAP2L
        LDA #>ge_nm
        TAP2H
ge_onl: LDA (P2)
        LDB #0
        CMP
        JZ ge_ot
        STA (P1)+
        INP2
        JMP ge_onl
ge_ot:  LDA #0
        STA (P1)
        LDA ge_cnt
        INC
        STA ge_cnt
        JMP ge_nl
ge_gdone:
        RTS

; ge_slot: P1 = &ge_out[ge_cnt]  (ge_out + ge_cnt*64, same stride as gfile_ptr)
; In: ge_cnt, ge_out. Out: P1. Clobbers A/B, getmp, ge_j2, gecar.
ge_slot:
        LDA #0
        STA getmp
        STA getmp+1
        LDA ge_cnt
        STA ge_j2
ges_l:  LDA ge_j2
        LDB #0
        CMP
        JZ ges_d
        LDA getmp
        LDB #64
        ADD
        STA getmp
        JNC ges_1
        LDA getmp+1
        INC
        STA getmp+1
ges_1:  LDA ge_j2
        DEC
        STA ge_j2
        JMP ges_l
ges_d:  LDA getmp
        LDB ge_out
        ADD
        STA getmp
        LDA #0
        JNC ges_2
        LDA #1
ges_2:  STA gecar
        LDA getmp+1
        LDB ge_out+1
        ADD
        LDB gecar
        ADD
        STA getmp+1
        LDA getmp
        TAP1L
        LDA getmp+1
        TAP1H
        RTS

; ---- gmatch / upper (case-insensitive * ? whole-string matcher) -----------
; gmatch: does glob pattern gp match the whole string gs? (case-insensitive)
;   in : gp = pattern word, gs = string word
;   out: A = 1 match / 0 no match
; '?' matches any one char; '*' matches zero-or-more via recursion: it saves
; gp/gs on the stack, tries matching the tail here, and on failure advances gs
; and retries (classic backtracking). Recurses through JSR gmatch, so it leans
; on the return stack. Clobbers A/B/P1/P2 and gpc/gsc/gmr.
gmatch: LDA gp
        TAP1L
        LDA gp+1
        TAP1H
        LDA (P1)
        STA gpc
        LDB #'*'
        CMP
        JZ gm_star
        LDB #0
        CMP
        JZ gm_pend
        LDA gs
        TAP2L
        LDA gs+1
        TAP2H
        LDA (P2)
        STA gsc
        LDB #0
        CMP
        JZ gm_r0
        LDA gpc
        LDB #'?'
        CMP
        JZ gm_adv
        LDA gpc
        JSR upper
        STA gpc
        LDA gsc
        JSR upper
        LDB gpc
        CMP
        JZ gm_adv
        LDA #0
        RTS
gm_adv: LDA gp
        LDB #1
        ADD
        STA gp
        JNC gm_a1
        LDA gp+1
        INC
        STA gp+1
gm_a1:  LDA gs
        LDB #1
        ADD
        STA gs
        JNC gm_a2
        LDA gs+1
        INC
        STA gs+1
gm_a2:  JMP gmatch
gm_pend:LDA gs
        TAP2L
        LDA gs+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ gm_r1
        LDA #0
        RTS
gm_r0:  LDA #0
        RTS
gm_r1:  LDA #1
        RTS
gm_star:LDA gp
        LDB #1
        ADD
        STA gp
        JNC gm_s0
        LDA gp+1
        INC
        STA gp+1
gm_s0:  LDA gp
        PHA
        LDA gp+1
        PHA
        LDA gs
        PHA
        LDA gs+1
        PHA
        JSR gmatch
        STA gmr
        PLA
        STA gs+1
        PLA
        STA gs
        PLA
        STA gp+1
        PLA
        STA gp
        LDA gmr
        LDB #0
        CMP
        JNZ gm_r1
        LDA gs
        TAP2L
        LDA gs+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ gm_r0
        LDA gs
        LDB #1
        ADD
        STA gs
        JNC gm_s0
        LDA gs+1
        INC
        STA gs+1
        JMP gm_s0
; upper: fold A to upper-case (ASCII), leave other bytes unchanged.
; In: A = char. Out: A = folded char. Clobbers B, uch.
upper:  STA uch
        LDB #'a'                       ; below 'a' (97)? CMP clears C when A<B
        CMP
        JNC up_no
        LDA uch
        LDB #123                       ; at/above 'z'+1 (123)? CMP sets C when A>=B
        CMP
        JC up_no
        LDA uch
        LDB #32                        ; in a..z: clear bit 5 by subtracting 32
        SUB
        RTS
up_no:  LDA uch
        RTS

; ---- shared data ----------------------------------------------------------
fromfile:.fill 1
gnf:    .fill 1
gidx:   .fill 1
gtmp:   .fill 1
gtmp2:  .fill 1
gcarry: .fill 1
oa_a:   .fill 2
oa_g:   .fill 1
op_a:   .fill 2
ge_pat: .fill 2
ge_out: .fill 2
ge_max: .fill 1
ge_cnt: .fill 1
ge_hs:  .fill 1
ge_sp:  .fill 1
ge_pl:  .fill 1
ge_ls:  .fill 1
ge_j:   .fill 1
ge_j2:  .fill 1
getmp:  .fill 2
gecar:  .fill 1
gp:     .fill 2
gs:     .fill 2
gpc:    .fill 1
gsc:    .fill 1
gmr:    .fill 1
uch:    .fill 1
spath:  .fill 80
ge_dir: .fill 64
ge_leaf:.fill 16
ge_nm:  .fill 16
de:     .fill 18   ; +[17] = length bits 16..23 (24-bit file size)
gfiles: .fill 1536
