; =============================================================================
; P8X CC - native C compiler (standalone TPA program) - MILESTONE B, path B
; =============================================================================
;     RUN CC.BIN SRC.C >OUT.ASM      (then: ASM OUT.ASM  ->  a RUNnable .BIN)
;
; A from-scratch, single-pass C compiler written directly in assembly, small and
; dense enough to run ON the P8X (unlike the p8cc.c codegen, which compiles to
; ~82 KB). It streams the source through the BIOS read stream (FOPEN/FGETB) and
; emits assembly text to stdout via SYS_PUTC, so `>OUT.ASM` captures it and the
; program's own I/O stays shell-redirectable.
;
; THIS IS THE WALKING SKELETON (v0.1). Supported so far:
;     int main() { <stmt>* }
;     stmt : putchar( <expr> ) ;  |  return [<expr>] ;
;     expr : term (('+'|'-') term)*        term : NUMBER | '(' expr ')'
; Values are 8-bit for now (putchar takes a byte). Codegen is a stack machine on
; the hardware stack + one memory temp (__t0), since the ISA has no A<->B move.
; Grows one tested feature at a time (params/locals, *, if/while, ... ) toward
; the p8cc subset; verification is behavioural (compile on-target, run, diff
; output against the p8cc.py reference).
;
; Conventions: source is the BIOS read stream (no cursor pointer); output is
; SYS_PUTC. P3 is the system stack. Emit walks strings via EMP (survives any
; SYS_PUTC register clobber).
; =============================================================================

; ---- BIOS / OS ----
FSDIRBUF = $0145   ; repoint the directory-scan buffer (A = page) off SBUF
FRESOLVE = $0133   ; resolve a path -> dir extent + leaf FNAME (P1 = path)
FOPEN    = $0124   ; open the resolved file for reading (P1 = 512-byte buffer)
FGETB    = $0127   ; next source byte -> A; C=1 at EOF
SYS_PUTC = $4009   ; emit A to stdout (redirectable by the shell)
RDBUF    = $FC00   ; FOPEN read buffer

CR       = $0D
LF       = $0A

; Variables live in this program's OWN space (the BSS labelled at the end), NOT
; a fixed high page — a high page collides with the OS/shell scratch used by the
; SYS_PUTC output-redirect path, corrupting state between calls.

        .org $7A00
START:  TPA3L
        STA  STK0
        TPA3H
        STA  STK0+1
        JSR  GETARG                  ; PATH <- first arg word (the source path)
        LDA  PATH
        JZ   USAGE                   ; no arg -> usage
        LDA  #$E0                    ; FSDIRBUF: move the directory-scan buffer to
        JSR  FSDIRBUF                ;   $E000 so FRESOLVE's scan doesn't clobber a
                                     ;   redirected write stream's SBUF partial
        LDA  #<PATH                  ; FRESOLVE(PATH)
        TAP1L
        LDA  #>PATH
        TAP1H
        LDA  #0
        JSR  FRESOLVE
        LDA  #<RDBUF                 ; FOPEN(read buffer)
        TAP1L
        LDA  #>RDBUF
        TAP1H
        LDA  #0
        JSR  FOPEN
        JC   OPENERR
        LDA  #0                      ; reset the lexer + symbol table + labels
        STA  PBF
        STA  SYMCNT
        STA  LBLCNT
        STA  USEMUL
        STA  USEDIV
        JSR  COMPILE
        RTS
USAGE:  LDP1 #MUSAGE
        JSR  EMIT
        RTS
OPENERR:LDP1 #MNOSRC
        JSR  EMIT
        RTS

; --- GETARG: copy the first whitespace-delimited word of the arg tail (P2 at
;     entry) into PATH, NUL-terminated. Leaves PATH[0]=0 if there is no arg. ---
GETARG: LDA  #0
        STA  PATH
ga_ss:  LDA  (P2)                    ; skip leading spaces
        LDB  #' '
        CMP
        JNZ  ga_cp
        INP2
        JMP  ga_ss
ga_cp:  LDA  #<PATH
        TAP1L
        LDA  #>PATH
        TAP1H
ga_l:   LDA  (P2)
        JZ   ga_end
        LDB  #CR
        CMP
        JZ   ga_end
        LDB  #' '
        CMP
        JZ   ga_end
        STA  (P1)
        INP1
        INP2
        JMP  ga_l
ga_end: LDA  #0
        STA  (P1)
        RTS

; =============================================================================
; Output (emit assembly text via SYS_PUTC)
; =============================================================================
; EMIT: P1 -> NUL-terminated string. Walks via EMP so a SYS_PUTC clobber of P1
;       is harmless.
EMIT:   TPA1L
        STA  EMP
        TPA1H
        STA  EMP+1
em_l:   LDA  EMP
        TAP1L
        LDA  EMP+1
        TAP1H
        LDA  (P1)
        JZ   em_d
        JSR  SYS_PUTC
        LDA  EMP
        LDB  #1
        ADD
        STA  EMP
        JNC  em_l
        LDA  EMP+1
        INC
        STA  EMP+1
        JMP  em_l
em_d:   RTS

; EMITNUM: emit A (0..255) as decimal, no leading zeros.
EMITNUM: STA VN
        LDA  #0
        STA  HADH
        LDA  #0                      ; hundreds
        STA  DQ
en_h:   LDA  VN
        LDB  #100
        CMP
        JNC  en_hd
        LDA  VN
        LDB  #100
        SUB
        STA  VN
        LDA  DQ
        INC
        STA  DQ
        JMP  en_h
en_hd:  LDA  DQ
        JZ   en_t
        LDB  #'0'
        ADD
        JSR  SYS_PUTC
        LDA  #1
        STA  HADH
en_t:   LDA  #0                      ; tens
        STA  DQ
en_tl:  LDA  VN
        LDB  #10
        CMP
        JNC  en_td
        LDA  VN
        LDB  #10
        SUB
        STA  VN
        LDA  DQ
        INC
        STA  DQ
        JMP  en_tl
en_td:  LDA  DQ
        JNZ  en_tp
        LDA  HADH
        JZ   en_o
en_tp:  LDA  DQ
        LDB  #'0'
        ADD
        JSR  SYS_PUTC
en_o:   LDA  VN                      ; ones (always)
        LDB  #'0'
        ADD
        JSR  SYS_PUTC
        RTS

; =============================================================================
; Lexer  (source via the BIOS read stream; one-char pushback)
; =============================================================================
; GC: next source char -> A, or A=0 with C=1 at EOF.
GC:     LDA  PBF
        JZ   gc_rd
        LDA  #0
        STA  PBF
        LDA  PBC
        CLC
        RTS
gc_rd:  JSR  FGETB                   ; C=1 at EOF
        RTS
UNGC:   STA  PBC                     ; push A back
        LDA  #1
        STA  PBF
        RTS

ISDIG:  LDB  #'0'                    ; C=1 if A is a digit
        CMP
        JNC  isd_no
        LDB  #':'                    ; '9'+1
        CMP
        JC   isd_no
        SEC
        RTS
isd_no: CLC
        RTS
ISALP:  LDB  #'A'                    ; C=1 if A is a letter or '_'
        CMP
        JNC  isa_us
        LDB  #'['                    ; 'Z'+1
        CMP
        JNC  isa_yes
        LDB  #'a'
        CMP
        JNC  isa_us
        LDB  #'{'                    ; 'z'+1
        CMP
        JNC  isa_yes
isa_us: LDB  #'_'
        CMP
        JZ   isa_yes
        CLC
        RTS
isa_yes: SEC
        RTS

; ADVANCE: read the next token into CURK/CURV/TID.
ADVANCE:
adv_ws: JSR  GC                      ; skip whitespace
        JC   adv_eof
        LDB  #' '
        CMP
        JZ   adv_ws
        LDB  #LF
        CMP
        JZ   adv_ws
        LDB  #CR
        CMP
        JZ   adv_ws
        LDB  #$09
        CMP
        JZ   adv_ws
        STA  TMPB
        JSR  ISDIG
        JC   adv_num
        LDA  TMPB
        JSR  ISALP
        JC   adv_id
        LDA  #3                      ; punctuation
        STA  CURK
        LDA  TMPB
        STA  CURV
        LDA  #0
        STA  CUR2                    ; default: single-char op
        LDA  TMPB                    ; a two-char op?  == != <= >=  (c2 is '=')
        LDB  #'='
        CMP
        JZ   adv_2ck
        LDB  #'!'
        CMP
        JZ   adv_2ck
        LDB  #'<'
        CMP
        JZ   adv_2ck
        LDB  #'>'
        CMP
        JZ   adv_2ck
        RTS
adv_2ck: JSR GC                      ; peek the next char
        JC   adv_pd                  ; EOF -> single
        STA  TMPC
        LDB  #'='
        CMP
        JZ   adv_2set
        LDA  TMPC                    ; not '=' -> push back, stay single
        JSR  UNGC
        RTS
adv_2set: LDA #'='
        STA  CUR2
        RTS
adv_pd: RTS
adv_eof: LDA #0
        STA  CURK
        RTS
adv_num: LDA #0                      ; decimal number -> CURV
        STA  NACC
        STA  NACC+1
an_l:   LDA  TMPB                    ; NACC = NACC*10 + digit  (low byte only kept 8-bit-ish)
        LDB  #'0'
        SUB
        STA  DQ                      ; digit
        LDA  NACC                    ; *10 = *8 + *2  (8-bit is enough for v0.1)
        SHL
        STA  TMPB                    ; *2
        SHL
        SHL                          ; *8
        LDB  TMPB
        ADD                          ; *10
        LDB  DQ
        ADD
        STA  NACC
        JSR  GC
        JC   an_done
        STA  TMPB
        JSR  ISDIG
        JC   an_l
        LDA  TMPB
        JSR  UNGC
an_done: LDA #1
        STA  CURK
        LDA  NACC
        STA  CURV
        LDA  #0
        STA  CURV+1
        RTS
adv_id: LDA #<TID                    ; identifier -> TID  (built via P2, which
        TAP2L                        ;   FGETB preserves; P1 is clobbered by it)
        LDA  #>TID
        TAP2H
        LDA  TMPB
        STA  (P2)
        INP2
ai_l:   JSR  GC
        JC   ai_done
        STA  TMPB
        JSR  ISDIG
        JC   ai_put
        LDA  TMPB
        JSR  ISALP
        JC   ai_put
        LDA  TMPB                    ; not alnum -> push back, done
        JSR  UNGC
        JMP  ai_done
ai_put: LDA  TMPB
        STA  (P2)
        INP2
        JMP  ai_l
ai_done: LDA #0
        STA  (P2)                    ; NUL-terminate
        LDA  #2
        STA  CURK
        RTS

; =============================================================================
; Parser + codegen (single pass; emits as it parses)
; =============================================================================
COMPILE:
        LDP1 #MORG                   ; .org $7A00
        JSR  EMIT
        JSR  ADVANCE
        LDP1 #KW_INT                 ; int main ( ) {
        JSR  EXPECTID
        LDP1 #KW_MAIN
        JSR  EXPECTID
        LDA  #'('
        JSR  EXPECTP
        LDA  #')'
        JSR  EXPECTP
        LDA  #'{'
        JSR  EXPECTP
co_s:   LDA  CURK                    ; statements until '}'
        LDB  #3
        CMP
        JNZ  co_stmt
        LDA  CURV
        LDB  #'}'
        CMP
        JZ   co_end
co_stmt: JSR STMT
        JMP  co_s
co_end: LDP1 #MRTS                   ; fall-through return
        JSR  EMIT
        LDA  USEMUL                  ; the multiply helper, if the program used '*'
        JZ   ce_nomul
        LDP1 #MMULDEF
        JSR  EMIT
ce_nomul: LDA USEDIV                 ; the divide/modulo helper, if '/' or '%' used
        JZ   ce_nodiv
        LDP1 #MDMDEF
        JSR  EMIT
ce_nodiv: LDP1 #MTEMP                ; the codegen temp
        JSR  EMIT
        LDA  #0                      ; storage for each declared variable:
        STA  VITER                   ;   V0:  .fill 1  /  V1:  .fill 1  / ...
ce_vl:  LDA  VITER
        LDB  SYMCNT
        CMP
        JC   ce_vd                   ; VITER >= SYMCNT -> done
        LDP1 #MVL                    ; "V"
        JSR  EMIT
        LDA  VITER
        JSR  EMITNUM
        LDP1 #MVF                    ; ":   .fill 1" + LF
        JSR  EMIT
        LDA  VITER
        INC
        STA  VITER
        JMP  ce_vl
ce_vd:  RTS

; one statement
STMT:   LDA  CURK
        LDB  #3
        CMP
        JZ   st_punct                ; '{' -> block
        LDB  #2
        CMP
        JNZ  st_err
        LDP1 #KW_INT
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_decl
        LDP1 #KW_IF
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_if
        LDP1 #KW_WHILE
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_while
        LDP1 #KW_PUTC
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_putc
        LDP1 #KW_RET
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_ret
        JMP  st_assign               ; an identifier LHS -> assignment
st_punct: LDA CURV
        LDB  #'{'
        CMP
        JZ   st_block
st_err: RTS                          ; (unknown statement -> stop quietly)

; { <stmt>* }
st_block: LDA #'{'
        JSR  EXPECTP
sb_l:   LDA  CURK
        LDB  #3
        CMP
        JNZ  sb_st
        LDA  CURV
        LDB  #'}'
        CMP
        JZ   sb_end
sb_st:  JSR  STMT
        JMP  sb_l
sb_end: LDA  #'}'
        JSR  EXPECTP
        RTS

; if ( <expr> ) <stmt> [ else <stmt> ]
st_if:  JSR  ADVANCE                 ; past "if"
        LDA  #'('
        JSR  EXPECTP
        JSR  GEXPR                   ; condition -> A
        LDA  #')'
        JSR  EXPECTP
        JSR  NEWLBL                  ; la = false-branch target
        PHA
        LDP1 #MJZ
        PLA
        PHA
        JSR  EMITJ                   ; JZ L<la>
        JSR  STMT                    ; then-branch
        LDA  CURK                    ; an "else"?
        LDB  #2
        CMP
        JNZ  if_ne
        LDP1 #KW_ELSE
        JSR  IDEQ
        LDA  TMPB
        JZ   if_ne
        JSR  ADVANCE                 ; past "else"
        PLA                          ; la
        STA  IFTMP
        JSR  NEWLBL                  ; lb = end target
        PHA
        LDP1 #MJMP
        PLA
        PHA
        JSR  EMITJ                   ; JMP L<lb>
        LDA  IFTMP
        JSR  EMITLBL                 ; L<la>:
        JSR  STMT                    ; else-branch
        PLA
        JSR  EMITLBL                 ; L<lb>:
        RTS
if_ne:  PLA                          ; la
        JSR  EMITLBL                 ; L<la>:
        RTS

; while ( <expr> ) <stmt>
st_while: JSR ADVANCE                ; past "while"
        JSR  NEWLBL                  ; ltop
        PHA
        JSR  EMITLBL                 ; L<ltop>:
        LDA  #'('
        JSR  EXPECTP
        JSR  GEXPR                   ; condition -> A
        LDA  #')'
        JSR  EXPECTP
        JSR  NEWLBL                  ; lend
        PHA
        LDP1 #MJZ
        PLA
        PHA
        JSR  EMITJ                   ; JZ L<lend>
        JSR  STMT                    ; body
        PLA                          ; lend
        STA  IFTMP
        PLA                          ; ltop
        PHA
        LDP1 #MJMP
        PLA
        JSR  EMITJ                   ; JMP L<ltop>
        LDA  IFTMP
        JSR  EMITLBL                 ; L<lend>:
        RTS

; int NAME [ = expr ] ;   -> reserve a variable, optionally initialise it
st_decl: JSR ADVANCE                 ; past "int"
        JSR  SYMADD                  ; add NAME (current id) -> SYMIDX
        LDA  SYMIDX
        STA  LHSIDX
        JSR  ADVANCE                 ; past NAME
        LDA  CURK                    ; optional  = expr
        LDB  #3
        CMP
        JNZ  sd_semi
        LDA  CURV
        LDB  #'='
        CMP
        JNZ  sd_semi
        JSR  ADVANCE                 ; past '='
        JSR  GEXPR
        JSR  EMITSTV                 ; STA V<LHSIDX>
sd_semi: LDA #$3B
        JSR  EXPECTP
        RTS

; NAME = expr ;   -> assignment to an existing variable
st_assign: JSR SYMFIND              ; look up NAME (current id) -> SYMIDX/SYMOK
        LDA  SYMOK
        JZ   st_err                  ; undeclared -> stop
        LDA  SYMIDX
        STA  LHSIDX
        JSR  ADVANCE                 ; past NAME
        LDA  #'='
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EMITSTV                 ; STA V<LHSIDX>
        LDA  #$3B
        JSR  EXPECTP
        RTS
; EMITSTV: emit  "        STA V<LHSIDX>" + newline
EMITSTV: LDP1 #MSTAV
        JSR  EMIT
        LDA  LHSIDX
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        RTS
st_putc: JSR ADVANCE
        LDA  #'('
        JSR  EXPECTP
        JSR  GEXPR                   ; result in A at runtime
        LDA  #')'
        JSR  EXPECTP
        LDA  #$3B
        JSR  EXPECTP
        LDP1 #MPUTC
        JSR  EMIT
        RTS
st_ret: JSR  ADVANCE
        LDA  CURK                    ; return ; | return expr ;
        LDB  #3
        CMP
        JNZ  sr_e
        LDA  CURV
        LDB  #$3B
        CMP
        JZ   sr_semi
sr_e:   JSR  GEXPR
sr_semi: LDA #$3B
        JSR  EXPECTP
        LDP1 #MRTS
        JSR  EMIT
        RTS

; expression: GADD [ relop GADD ]  -> result in the runtime A register.
; A relational compares two additive expressions, yielding 0/1 (single, non-
; associative). Assignment/putchar/return/conditions all call GEXPR.
GEXPR:  JSR  GADD
        LDA  CURK
        LDB  #3
        CMP
        JNZ  grx
        JSR  RELDET                  ; is the current punct a relop? -> RELOP/RELF
        LDA  RELF
        JZ   grx
        LDP1 #MPHA                   ; push the left operand
        JSR  EMIT
        LDA  RELOP                   ; save RELOP across GADD (parens may recurse)
        PHA
        JSR  ADVANCE                 ; past the operator
        JSR  GADD                    ; right operand -> A
        PLA
        STA  RELOP
        LDP1 #MSTAT                  ; STA __t0   (right)
        JSR  EMIT
        LDP1 #MPLA                   ; PLA        (left)
        JSR  EMIT
        LDP1 #MLDBT                  ; LDB __t0   (right)
        JSR  EMIT
        LDP1 #MCMP                   ; CMP        (left - right; C=left>=right, Z=eq)
        JSR  EMIT
        JSR  EMITCMP                 ; emit the 0/1 sequence for RELOP
grx:    RTS

; term: factor (('*'|'/'|'%') factor)*   (8-bit, via __mul8/__divmod8 helpers)
GTERM:  JSR  GFACT
gt_l:   LDA  CURK
        LDB  #3
        CMP
        JNZ  gt_d
        LDA  CURV
        LDB  #'*'
        CMP
        JZ   gt_mul
        LDA  CURV
        LDB  #'/'
        CMP
        JZ   gt_div
        LDA  CURV
        LDB  #'%'
        CMP
        JZ   gt_mod
        JMP  gt_d
gt_mul: JSR  ADVANCE
        LDA  #1
        STA  USEMUL
        JSR  GT_COMB
        LDP1 #MMUL                   ; JSR __mul8 -> A = left * right
        JSR  EMIT
        JMP  gt_l
gt_div: JSR  ADVANCE
        LDA  #1
        STA  USEDIV
        JSR  GT_COMB
        LDP1 #MDIV                   ; JSR __divmod8 ; LDA __d1  (quotient)
        JSR  EMIT
        JMP  gt_l
gt_mod: JSR  ADVANCE
        LDA  #1
        STA  USEDIV
        JSR  GT_COMB
        LDP1 #MMOD                   ; JSR __divmod8 ; LDA __d0  (remainder)
        JSR  EMIT
        JMP  gt_l
gt_d:   RTS
; GT_COMB: emit  push-left ; <right factor> ; STA __t0 ; PLA  (left in A, right in __t0)
GT_COMB: LDP1 #MPHA
        JSR  EMIT
        JSR  GFACT
        LDP1 #MSTAT
        JSR  EMIT
        LDP1 #MPLA
        JSR  EMIT
        RTS

; additive: term (('+'|'-') term)*
GADD:   JSR  GTERM
ge_l:   LDA  CURK
        LDB  #3
        CMP
        JNZ  ge_d
        LDA  CURV
        LDB  #'+'
        CMP
        JZ   ge_add
        LDA  CURV
        LDB  #'-'
        CMP
        JZ   ge_sub
        JMP  ge_d
ge_add: JSR  ADVANCE
        LDP1 #MPHA
        JSR  EMIT
        JSR  GTERM
        LDP1 #MSTAT
        JSR  EMIT
        LDP1 #MPLA
        JSR  EMIT
        LDP1 #MLDBT
        JSR  EMIT
        LDP1 #MADD
        JSR  EMIT
        JMP  ge_l
ge_sub: JSR  ADVANCE
        LDP1 #MPHA
        JSR  EMIT
        JSR  GTERM
        LDP1 #MSTAT
        JSR  EMIT
        LDP1 #MPLA
        JSR  EMIT
        LDP1 #MLDBT
        JSR  EMIT
        LDP1 #MSUB
        JSR  EMIT
        JMP  ge_l
ge_d:   RTS

; factor: NUMBER | IDENT | '(' expr ')'
GFACT:  LDA  CURK
        LDB  #1
        CMP
        JZ   gf_num
        LDB  #2
        CMP
        JZ   gf_id
        LDB  #3
        CMP
        JNZ  gf_err
        LDA  CURV
        LDB  #'('
        CMP
        JNZ  gf_err
        JSR  ADVANCE
        JSR  GEXPR
        LDA  #')'
        JSR  EXPECTP
        RTS
gf_num: LDP1 #MLDAI                  ; LDA #<n>
        JSR  EMIT
        LDA  CURV
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        JSR  ADVANCE
        RTS
gf_id:  JSR  SYMFIND                 ; a variable read -> LDA V<idx>
        LDA  SYMOK
        JZ   gf_err
        LDP1 #MLDAV
        JSR  EMIT
        LDA  SYMIDX
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        JSR  ADVANCE
        RTS
gf_err: RTS

; =============================================================================
; Symbol table - each declared variable maps to an index (emitted as V<index>).
; Names are packed NUL-terminated in SYMPOOL; SYMCNT counts them.
; =============================================================================
; SYMFIND: search SYMPOOL for the current id (TID). SYMOK=1 & SYMIDX=index if
;          found, else SYMOK=0.
SYMFIND: LDA #0
        STA  SYMIDX
        STA  SYMOK
        LDA  #<SYMPOOL
        TAP1L
        LDA  #>SYMPOOL
        TAP1H
sf_e:   LDA  SYMIDX
        LDB  SYMCNT
        CMP
        JC   sf_no                   ; SYMIDX >= SYMCNT -> not found
        LDA  #<TID
        TAP2L
        LDA  #>TID
        TAP2H
sf_c:   LDA  (P1)                    ; pool char vs TID char
        STA  TMPC
        LDA  (P2)
        LDB  TMPC
        CMP
        JNZ  sf_nx
        LDA  (P1)
        JZ   sf_yes                  ; equal and both at NUL -> match
        INP1
        INP2
        JMP  sf_c
sf_nx:  LDA  (P1)                    ; skip the rest of this pool name + its NUL
        JZ   sf_np
        INP1
        JMP  sf_nx
sf_np:  INP1
        LDA  SYMIDX
        INC
        STA  SYMIDX
        JMP  sf_e
sf_yes: LDA  #1
        STA  SYMOK
        RTS
sf_no:  LDA  #0
        STA  SYMOK
        RTS

; SYMADD: append the current id (TID) to SYMPOOL; SYMIDX = its (new) index.
SYMADD: LDA #<SYMPOOL
        TAP1L
        LDA  #>SYMPOOL
        TAP1H
        LDA  #0
        STA  TMPB                    ; names skipped
sa_e:   LDA  TMPB
        LDB  SYMCNT
        CMP
        JC   sa_ap                   ; skipped SYMCNT names -> at the append point
sa_sk:  LDA  (P1)
        JZ   sa_np
        INP1
        JMP  sa_sk
sa_np:  INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  sa_e
sa_ap:  LDA  #<TID                   ; copy TID (+ its NUL) into the pool
        TAP2L
        LDA  #>TID
        TAP2H
sa_cp:  LDA  (P2)
        STA  (P1)
        JZ   sa_dn
        INP1
        INP2
        JMP  sa_cp
sa_dn:  LDA  SYMCNT                  ; index = old count; bump the count
        STA  SYMIDX
        LDA  SYMCNT
        INC
        STA  SYMCNT
        RTS

; =============================================================================
; Comparisons + labels (for relational operators and if/while)
; =============================================================================
; RELDET: is the current punct token a relational operator? RELF=1 and RELOP set
;         (0 LT, 1 LE, 2 GT, 3 GE, 4 EQ, 5 NE), else RELF=0. Does not advance.
RELDET: LDA #0
        STA  RELF
        LDA  CURV
        LDB  #'<'
        CMP
        JZ   rd_l
        LDB  #'>'
        CMP
        JZ   rd_g
        LDB  #'='
        CMP
        JZ   rd_e
        LDB  #'!'
        CMP
        JZ   rd_x
        RTS
rd_l:   LDA  CUR2                    ; '<' or '<='
        LDB  #'='
        CMP
        JZ   rd_le
        LDA  #0
        STA  RELOP
        JMP  rd_ok
rd_le:  LDA  #1
        STA  RELOP
        JMP  rd_ok
rd_g:   LDA  CUR2                    ; '>' or '>='
        LDB  #'='
        CMP
        JZ   rd_ge
        LDA  #2
        STA  RELOP
        JMP  rd_ok
rd_ge:  LDA  #3
        STA  RELOP
        JMP  rd_ok
rd_e:   LDA  CUR2                    ; only '==' is relational ('=' is assignment)
        LDB  #'='
        CMP
        JNZ  rd_no
        LDA  #4
        STA  RELOP
        JMP  rd_ok
rd_x:   LDA  CUR2                    ; '!='
        LDB  #'='
        CMP
        JNZ  rd_no
        LDA  #5
        STA  RELOP
rd_ok:  LDA  #1
        STA  RELF
rd_no:  RTS

; EMITCMP: given a preceding CMP (left-right, setting C=left>=right and Z=equal),
;          emit code leaving 0/1 in A per RELOP.  The conditional branch must come
;          BEFORE any LDA — an LDA clobbers Z (though not C), which would destroy
;          the comparison result.  Two fresh labels: la (branch target), lb (end).
EMITCMP: JSR NEWLBL
        STA  LBLA
        JSR  NEWLBL
        STA  LBLB
        LDA  RELOP
        LDB  #0
        CMP
        JZ   ec_lt
        LDB  #1
        CMP
        JZ   ec_le
        LDB  #2
        CMP
        JZ   ec_gt
        LDB  #3
        CMP
        JZ   ec_ge
        LDB  #4
        CMP
        JZ   ec_eq
        JMP  ec_ne
; simple ops: one conditional jump (on the CMP flags) to la=TRUE, else fall to 0.
ec_lt:  LDP1 #MJNC                   ; a<b : true when C=0
        LDA  LBLA
        JSR  EMITJ
        JMP  ec_t
ec_ge:  LDP1 #MJC                    ; a>=b : true when C=1
        LDA  LBLA
        JSR  EMITJ
        JMP  ec_t
ec_eq:  LDP1 #MJZ                    ; a==b : true when Z=1
        LDA  LBLA
        JSR  EMITJ
        JMP  ec_t
ec_ne:  LDP1 #MJNZ                   ; a!=b : true when Z=0
        LDA  LBLA
        JSR  EMITJ
        JMP  ec_t
ec_t:   LDP1 #MLDA0                  ; false path, then jump over the true value
        JSR  EMIT
        LDP1 #MJMP
        LDA  LBLB
        JSR  EMITJ
        LDA  LBLA                    ; la: (true)
        JSR  EMITLBL
        LDP1 #MLDA1
        JSR  EMIT
        JMP  ec_end
ec_gt:  LDP1 #MJZ                    ; a>b : false when Z=1 (eq) or C=0 (a<b)
        LDA  LBLA
        JSR  EMITJ
        LDP1 #MJNC
        LDA  LBLA
        JSR  EMITJ
        LDP1 #MLDA1                  ; a>b -> true
        JSR  EMIT
        LDP1 #MJMP
        LDA  LBLB
        JSR  EMITJ
        LDA  LBLA                    ; la: (false)
        JSR  EMITLBL
        LDP1 #MLDA0
        JSR  EMIT
        JMP  ec_end
ec_le:  LDP1 #MJZ                    ; a<=b : true when Z=1 (eq) or C=0 (a<b)
        LDA  LBLA
        JSR  EMITJ
        LDP1 #MJNC
        LDA  LBLA
        JSR  EMITJ
        LDP1 #MLDA0                  ; a>b -> false
        JSR  EMIT
        LDP1 #MJMP
        LDA  LBLB
        JSR  EMITJ
        LDA  LBLA                    ; la: (true)
        JSR  EMITLBL
        LDP1 #MLDA1
        JSR  EMIT
ec_end: LDA  LBLB                    ; lb: (end)
        JSR  EMITLBL
        RTS

; NEWLBL: A = a fresh label number; bump the counter.
NEWLBL: LDA LBLCNT
        STA  TMPC
        INC
        STA  LBLCNT
        LDA  TMPC
        RTS
; EMITJ: emit a jump (P1 = "... L" prefix) to the label number in A + newline.
EMITJ:  STA JLBL
        JSR  EMIT
        LDA  JLBL
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        RTS
; EMITLBL: emit  "L<A>:"  + newline (a label definition at column 0).
EMITLBL: STA JLBL
        LDP1 #MLBP
        JSR  EMIT
        LDA  JLBL
        JSR  EMITNUM
        LDP1 #MLBC
        JSR  EMIT
        RTS

; EXPECTP: current token must be punct char A, else quietly stop; then ADVANCE.
EXPECTP: STA TMPB
        LDA  CURK
        LDB  #3
        CMP
        JNZ  ep_ret
        LDA  CUR2                    ; a single-char punct only (not ==, <=, ...)
        JNZ  ep_ret
        LDA  CURV
        LDB  TMPB
        CMP
        JNZ  ep_ret
        JSR  ADVANCE
ep_ret: RTS

; EXPECTID: current token must be the identifier at P1, then ADVANCE.
EXPECTID: JSR IDEQ
        LDA  TMPB
        JZ   ei_ret
        JSR  ADVANCE
ei_ret: RTS

; IDEQ: TMPB=1 if CURK==ID and TID==string at P1, else 0.  P1 preserved-ish.
IDEQ:   LDA  CURK
        LDB  #2
        CMP
        JNZ  id_no
        TPA1L                        ; P2 = the compare string; walk TID vs it
        TAP2L
        TPA1H
        TAP2H
        LDA  #<TID
        TAP1L
        LDA  #>TID
        TAP1H
id_l:   LDA  (P1)                    ; TID char -> scratch
        STA  TMPC
        LDA  (P2)                    ; compare-string char
        LDB  TMPC
        CMP
        JNZ  id_no
        LDA  (P1)
        JZ   id_yes                  ; equal AND both at NUL -> match
        INP1
        INP2
        JMP  id_l
id_yes: LDA  #1
        STA  TMPB
        RTS
id_no:  LDA  #0
        STA  TMPB
        RTS

; =============================================================================
; Strings
; =============================================================================
KW_INT:  .asciiz "int"
KW_MAIN: .asciiz "main"
KW_PUTC: .asciiz "putchar"
KW_RET:  .asciiz "return"
KW_IF:   .asciiz "if"
KW_WHILE: .asciiz "while"
KW_ELSE: .asciiz "else"

; whole-line mnemonics end with LF (8-space indent + text + newline)
MORG:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii ".org $7A00"
        .byte LF,0
MLDAI:  .byte $20,$20,$20,$20,$20,$20,$20,$20   ; prefix: a number + MNL follow
        .asciiz "LDA #"
MLDAV:  .byte $20,$20,$20,$20,$20,$20,$20,$20   ; prefix: "LDA V" + index + MNL
        .asciiz "LDA V"
MSTAV:  .byte $20,$20,$20,$20,$20,$20,$20,$20   ; prefix: "STA V" + index + MNL
        .asciiz "STA V"
MVL:    .asciiz "V"                             ; a variable's storage label prefix
MVF:    .ascii ":   .fill 1"
        .byte LF,0
MNL:    .byte LF,0
MPHA:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "PHA"
        .byte LF,0
MPLA:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "PLA"
        .byte LF,0
MSTAT:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __t0"
        .byte LF,0
MLDBT:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDB __t0"
        .byte LF,0
MADD:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "ADD"
        .byte LF,0
MSUB:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "SUB"
        .byte LF,0
MPUTC:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR $4009"
        .byte LF,0
MRTS:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "RTS"
        .byte LF,0
MCMP:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "CMP"
        .byte LF,0
MMUL:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __mul8"
        .byte LF,0
; the 8-bit multiply runtime helper (A * __t0 -> A), emitted once if '*' is used
MMULDEF: .ascii "__mul8: STA __m0"
        .byte LF
        .ascii "        LDA #0"
        .byte LF
        .ascii "        STA __m1"
        .byte LF
        .ascii "__mml:  LDA __t0"
        .byte LF
        .ascii "        JZ __mmd"
        .byte LF
        .ascii "        LDA __m1"
        .byte LF
        .ascii "        LDB __m0"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        STA __m1"
        .byte LF
        .ascii "        LDA __t0"
        .byte LF
        .ascii "        LDB #1"
        .byte LF
        .ascii "        SUB"
        .byte LF
        .ascii "        STA __t0"
        .byte LF
        .ascii "        JMP __mml"
        .byte LF
        .ascii "__mmd:  LDA __m1"
        .byte LF
        .ascii "        RTS"
        .byte LF
        .ascii "__m0:   .fill 1"
        .byte LF
        .ascii "__m1:   .fill 1"
        .byte LF,0
MDIV:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __divmod8"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA __d1"
        .byte LF,0
MMOD:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __divmod8"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA __d0"
        .byte LF,0
; the 8-bit divide/modulo helper (A / __t0 -> __d1 quotient, __d0 remainder)
MDMDEF: .ascii "__divmod8: STA __d0"
        .byte LF
        .ascii "        LDA #0"
        .byte LF
        .ascii "        STA __d1"
        .byte LF
        .ascii "        LDA __t0"
        .byte LF
        .ascii "        JZ __dmd"
        .byte LF
        .ascii "__dml:  LDA __d0"
        .byte LF
        .ascii "        LDB __t0"
        .byte LF
        .ascii "        CMP"
        .byte LF
        .ascii "        JNC __dmd"
        .byte LF
        .ascii "        LDA __d0"
        .byte LF
        .ascii "        LDB __t0"
        .byte LF
        .ascii "        SUB"
        .byte LF
        .ascii "        STA __d0"
        .byte LF
        .ascii "        LDA __d1"
        .byte LF
        .ascii "        INC"
        .byte LF
        .ascii "        STA __d1"
        .byte LF
        .ascii "        JMP __dml"
        .byte LF
        .ascii "__dmd:  RTS"
        .byte LF
        .ascii "__d0:   .fill 1"
        .byte LF
        .ascii "__d1:   .fill 1"
        .byte LF,0
MLDA0:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA #0"
        .byte LF,0
MLDA1:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA #1"
        .byte LF,0
MJC:    .byte $20,$20,$20,$20,$20,$20,$20,$20     ; jump prefixes: "JXX L" + num
        .asciiz "JC L"
MJNC:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JNC L"
MJZ:    .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JZ L"
MJNZ:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JNZ L"
MJMP:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JMP L"
MLBP:   .asciiz "L"                              ; a label def: "L" + num + MLBC
MLBC:   .ascii ":"
        .byte LF,0
MTEMP:  .ascii "__t0:   .fill 1"
        .byte LF,0
MUSAGE: .asciiz "usage: cc src.c >out.asm"
MNOSRC: .asciiz "cc: cannot open source"

; =============================================================================
; BSS - in this program's own space (safe from OS scratch)
; =============================================================================
PBF:    .fill 1    ; pushback flag (1 = PBC holds a char)
PBC:    .fill 1    ; pushback char
CURK:   .fill 1    ; current token kind: 0 EOF, 1 NUM, 2 ID, 3 PUNCT
CURV:   .fill 2    ; current token value (NUM value / PUNCT char)
TID:    .fill 24   ; identifier text, NUL-terminated
PATH:   .fill 64   ; source path buffer
EMP:    .fill 2    ; emit walk pointer
VN:     .fill 1    ; emitnum working value
DQ:     .fill 1    ; emitnum digit counter
HADH:   .fill 1    ; emitnum: a higher digit was already printed
NACC:   .fill 2    ; lexer number accumulator
STK0:   .fill 2    ; saved SP for a clean bail on error
TMPB:   .fill 1    ; byte scratch (also IDEQ / EXPECT* result flag)
TMPC:   .fill 1    ; byte scratch (IDEQ char compare)
SYMCNT: .fill 1    ; number of declared variables
SYMIDX: .fill 1    ; SYMFIND/SYMADD result index
SYMOK:  .fill 1    ; SYMFIND: 1 if found
LHSIDX: .fill 1    ; index of an assignment/decl target variable
VITER:  .fill 1    ; loop counter emitting variable storage
CUR2:   .fill 1    ; second char of a two-char punct (== != <= >=), else 0
RELOP:  .fill 1    ; relational op code: 0 LT 1 LE 2 GT 3 GE 4 EQ 5 NE
RELF:   .fill 1    ; RELDET: 1 if the current token is a relational op
LBLCNT: .fill 1    ; next codegen label number
LBLA:   .fill 1    ; comparison branch-target label (EMITCMP)
LBLB:   .fill 1    ; comparison end label (EMITCMP)
JLBL:   .fill 1    ; label number scratch for EMITJ/EMITLBL
IFTMP:  .fill 1    ; a label held briefly (non-recursively) in if/while
USEMUL: .fill 1    ; 1 if the program uses '*' (emit the __mul8 helper)
USEDIV: .fill 1    ; 1 if the program uses '/' or '%' (emit __divmod8)
SYMPOOL: .fill 256 ; packed NUL-terminated variable names
