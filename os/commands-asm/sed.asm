; sed.asm — hand-coded SED command (asm counterpart of os/commands/sed.c).
;   SED s/re/new/[g] [file]   substitute (regex LHS: . * + ? ^ $; literal RHS).
; Shares matchhere+rend via `;#use regex` and the stdin/readline engine via
; `;#use stdin`. Per line: scan, replace the first (or all with g) regex match
; span with the literal replacement, print. Entry: P2 = arg tail.
;#use stdin
;#use regex
;#use abi

        .org $6A00                   ; TPA load address (see reference_p8x_memory_map)
; Entry: P2 -> arg tail. s_sav is a 2-byte scratch used throughout to stash a
; pointer (P2) so a lookahead can be undone. Here it just round-trips P2 through
; s_sav (no net effect) before the leading-space skip.
        TPA2L
        STA s_sav
        TPA2H
        STA s_sav+1
        LDA s_sav
        TAP2L
        LDA s_sav+1
        TAP2H
sed_sk: LDA (P2)                     ; skip leading spaces in the arg tail
        LDB #32
        CMP
        JNZ sed_c0
        INP2
        JMP sed_sk
sed_c0: LDA (P2)                     ; empty/CR arg -> print usage
        LDB #0
        CMP
        JZ sed_usage
        LDB #13
        CMP
        JZ sed_usage
        LDA (P2)                     ; leading '-'? only -h/-H accepted (usage)
        LDB #'-'
        CMP
        JNZ sed_s
        TPA2L                        ; save P2 so a non-h flag can rewind
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
        LDA s_sav                    ; not -h: restore P2, fall through to expr
        TAP2L
        LDA s_sav+1
        TAP2H
sed_s:  LDA (P2)                     ; require leading 's' of s/re/new/
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
        STA si                       ; si = count of pattern chars copied
sp_l:   LDA si
        LDB #63                       ; cap at 63 (pat is 64 bytes incl NUL)
        CMP
        JC sp_d
        LDA (P2)                     ; stop at end-of-arg or the closing '/'
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
sp_d:   LDA #0                        ; NUL-terminate pat
        STA (P1)
; A leading '^' anchors the match to start-of-line. rpat is the pattern pointer
; handed to the regex engine; if anchored, advance it past the '^' (16-bit add
; with carry into the high byte).
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
sp_nosl:LDA (P2)                     ; second '/' required after the pattern
        LDB #'/'
        CMP
        JNZ sed_nosl
        INP2
        LDA #<rep                    ; parse replacement up to '/'
        TAP1L
        LDA #>rep
        TAP1H
        LDA #0
        STA sj                       ; sj = count of replacement chars copied
srp_l:  LDA sj
        LDB #63                       ; cap at 63 (rep is 64 bytes incl NUL)
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
srp_d:  LDA #0                        ; NUL-terminate rep
        STA (P1)
; Optional trailing '/g' (or /G) sets the global flag (replace all matches).
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
sg_done:LDA (P2)                     ; skip spaces before optional filename arg
        LDB #32
        CMP
        JNZ sof_d
        INP2
        JMP sg_done
sof_d:  TPA2L                        ; openarg: P2 -> filename (empty = stdin)
        STA oa_a
        TPA2H
        STA oa_a+1
        JSR openarg
        LDB #2                        ; return 2 = file not found
        CMP
        JZ sed_nf
; ---- substitution loop ----------------------------------------------------
; For each input line: build the result in `out` while scanning `line`.
;   si = read index into line, sn = write index into out,
;   sdone = 1 once the first (non-global) replacement has been made.
; Address math is 16-bit (base + index with carry into the high byte) because
; line/out can straddle a page boundary.
sed_loop:
        LDA #<line
        STA rl_buf
        LDA #>line
        STA rl_buf+1
        JSR readline
        LDB #0                        ; readline -> 0 = EOF, done
        CMP
        JZ sed_end
        LDA #0
        STA sn
        STA si
        STA sdone
sl_l:   LDA #<line                   ; P1 = &line[si]
        LDB si
        ADD
        TAP1L
        LDA #>line
        JNC sl1
        INC
sl1:    TAP1H
        LDA (P1)                     ; end of line reached? emit result
        LDB #0
        CMP
        JZ sl_end
        LDA #0
        STA smlen                     ; smlen = length of match at this position
; Try a match here only if global, or (non-global) no replacement done yet;
; otherwise fall through to copying this char literally.
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
        JSR re_at                     ; A = match length at line[si], 0 = none
        STA smlen
        LDB #0
        CMP
        JZ sl_lit
        LDA #0                        ; matched: copy replacement text into out
        STA sj
sr_l:   LDA #<rep                    ; P2 = &rep[sj]
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
        JZ sr_d                       ; end of replacement string
        LDA sn
        LDB #255                      ; stop if out buffer is full (255 chars)
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
sr_d:   LDA si                        ; consume the matched span: si += smlen
        LDB smlen
        ADD
        STA si
        LDA global                    ; global: keep scanning for more matches
        LDB #0
        CMP
        JNZ sl_l
        LDA #1                         ; non-global: mark first replacement done
        STA sdone
        JMP sl_l
; No match here: copy line[si] verbatim into out (if room), then advance si.
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
sl_end: LDA #<out                    ; NUL-terminate out at [sn]
        LDB sn
        ADD
        TAP1L
        LDA #>out
        JNC sle1
        INC
sle1:   TAP1H
        LDA #0
        STA (P1)
        LDA #<out                     ; print the rewritten line + newline
        TAP1L
        LDA #>out
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        JMP sed_loop
sed_end:RTS

; Error/usage exits: point P1 at a message, fall into sed_pm to print it.
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
sed_pm: LDA #0                        ; print message in P1 + newline, return
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; re_at: ra_i = start index in line -> A = length of a regex match here (0=none).
; If the pattern is anchored (^), only offset 0 can match; anywhere else -> 0.
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
ra_go:  LDA #<line                   ; ra_lp = &line[ra_i] (16-bit)
        LDB ra_i
        ADD
        STA ra_lp
        LDA #>line
        JNC ra1
        INC
ra1:    STA ra_lp+1
        LDA rpat                     ; matchhere inputs: rx_re = pattern ptr,
        STA rx_re
        LDA rpat+1
        STA rx_re+1
        LDA ra_lp                    ; rx_t = text ptr; sets rend past the match
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
        JSR nextc                     ; nextc: A = next char, C=1 at EOF
        JC rl_eof0
rl_l:   STA rlc
        LDB #10                        ; LF ends the line
        CMP
        JZ rl_done
        LDA rlc
        LDB #13                        ; drop CR (CRLF -> LF)
        CMP
        JZ rl_skip
        LDA rln
        LDB #255                       ; ignore chars past 255 (buffer cap)
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

; ---- scratch / buffers (uninitialized RAM after the code) -----------------
s_sav:  .fill 2                       ; saved P2 for lookahead rewinds
si:     .fill 1                       ; read index into line
sj:     .fill 1                       ; index into pat/rep during copy
sn:     .fill 1                       ; write index into out
sdone:  .fill 1                       ; 1 = first (non-global) sub already done
smlen:  .fill 1                       ; length of current match
sch:    .fill 1                       ; char in transit (copies clobber P1/P2)
global: .fill 1                       ; 1 = /g, replace all matches
anchored:.fill 1                      ; 1 = pattern began with ^
rpat:   .fill 2                       ; pattern ptr for regex (past ^ if anchored)
ra_i:   .fill 1                       ; re_at: start index into line
ra_lp:  .fill 2                       ; re_at: &line[ra_i]
rl_buf: .fill 2                       ; readline: destination buffer ptr
rlp:    .fill 2                       ; readline: current write cursor
rln:    .fill 1                       ; readline: chars stored so far
rlc:    .fill 1                       ; readline: last char from nextc
pat:    .fill 64                       ; regex source (LHS of s///)
rep:    .fill 64                       ; literal replacement (RHS of s///)
line:   .fill 260                      ; current input line (NUL-terminated)
out:    .fill 260                      ; rewritten output line
