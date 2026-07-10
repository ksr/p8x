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
        LDA  #0                      ; reset the lexer
        STA  PBF
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
        LDA  #3                      ; punctuation: single char
        STA  CURK
        LDA  TMPB
        STA  CURV
        LDA  #0
        STA  CURV+1
        RTS
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
        LDP1 #MTEMP                  ; the codegen temp
        JSR  EMIT
        RTS

; one statement
STMT:   LDA  CURK
        LDB  #2
        CMP
        JNZ  st_err
        LDP1 #KW_PUTC
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_putc
        LDP1 #KW_RET
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_ret
st_err: RTS                          ; (v0.1: unknown statement -> stop quietly)
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

; expression: term (('+'|'-') term)*   -> result in the runtime A register
GEXPR:  JSR  GTERM
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

; term: (v0.1) just a factor
GTERM:  JSR  GFACT
        RTS

; factor: NUMBER | '(' expr ')'
GFACT:  LDA  CURK
        LDB  #1
        CMP
        JZ   gf_num
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
gf_err: RTS

; EXPECTP: current token must be punct char A, else quietly stop; then ADVANCE.
EXPECTP: STA TMPB
        LDA  CURK
        LDB  #3
        CMP
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

; whole-line mnemonics end with LF (8-space indent + text + newline)
MORG:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii ".org $7A00"
        .byte LF,0
MLDAI:  .byte $20,$20,$20,$20,$20,$20,$20,$20   ; prefix: a number + MNL follow
        .asciiz "LDA #"
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
