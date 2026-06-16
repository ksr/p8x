;==============================================================================
; P8X BASIC — interpreter for the P8X TTL computer
;
; Boots at $0000 (EEPROM), 6850 ACIA console at $FF04/05.
; Milestone 2 — line editor: enter numbered lines (stored sorted; same number
; replaces, a bare number deletes), LIST, NEW. Integer 16-bit line numbers.
; Tokenizing and execution (RUN, statements) are TODO — see basic/README.md.
;
; Program storage (PROG): a sorted sequence of records
;     [num-lo][num-hi][text bytes ...][00]
; terminated by a 00,00 line-number marker (line 0 is invalid in BASIC).
; Edits are done by rebuilding into a scratch buffer (PBUF) then copying back —
; simplest correct approach for variable-length records on this ISA.
;==============================================================================

ACIAS  = $FF04
ACIAD  = $FF05
CR     = $0D
LF     = $0A
BS     = $08

LBUF   = $8000          ; input line buffer
NUM1   = $8060          ; 16-bit math operands / results
NUM2   = $8062
LNUM   = $8064          ; entered/printed line number
RNUM   = $8066          ; record line number during scan
TSRC   = $8068          ; address of entered line text (in LBUF)
SAVE1  = $806A          ; pointer save slots
SAVE2  = $806C
DIG    = $806E
LZ     = $806F
PCNT   = $8070
CYTMP  = $8071
INSF   = $8072          ; 1 once the new line has been emitted
TXTMT  = $8073          ; 1 if entered line has empty text (delete)
WP     = $8074          ; crunch write pointer
RP     = $8076          ; pointer save (match / uncrunch)
TOKEN  = $8078          ; token matched by MATCHKW
MATCHF = $8079          ; 1 if MATCHKW found a keyword
TMPC   = $807A          ; byte scratch
TOKW   = $807B          ; token being uncrunched

; keyword tokens (>= $80 so they never collide with text or the 00 terminator)
TOK_LIST = $8E
TOK_NEW  = $8F

PROG   = $8100          ; program storage
PBUF   = $C000          ; rebuild scratch buffer
STKTOP = $FEFF

;==============================================================================
        .org $0000
        LDP3 #STKTOP
        LDA  #$03            ; ACIA master reset
        STA  ACIAS
        LDA  #$15            ; /16 clock, 8N1
        STA  ACIAS
        JSR  NEWPROG         ; empty program
        LDP1 #BANNER
        JSR  PUTS

; ---------------- REPL -------------------------------------------------------
REPL:   JSR  GETLINE         ; line -> LBUF
        JSR  CRUNCH          ; tokenize keywords in place
        LDP2 #LBUF
        JSR  SKIPSP
        LDA  (P2)
        JZ   REPL            ; blank line
        LDB  #'0'            ; leading digit -> line entry
        SUB
        JNC  RCMD            ; ch < '0'
        LDB  #10
        CMP
        JC   RCMD            ; ch > '9'
        JMP  DOLINE
RCMD:   LDA  (P2)            ; immediate command = a leading token byte
        LDB  #TOK_LIST
        CMP
        JZ   DOLIST
        LDA  (P2)
        LDB  #TOK_NEW
        CMP
        JZ   DONEW
        LDP1 #MWHAT
        JSR  PUTS
        JMP  REPL

DONEW:  JSR  NEWPROG
        LDP1 #MOK
        JSR  PUTS
        JMP  REPL

DOLIST: JSR  LIST
        LDP1 #MOK
        JSR  PUTS
        JMP  REPL

; ---- enter / replace / delete a numbered line ----
DOLINE: JSR  PARSEDEC        ; LNUM = number (P2 advanced past digits)
        JSR  SKIPSP
        TPA2L                ; TSRC = current text pointer
        STA  TSRC
        TPA2H
        STA  TSRC+1
        LDA  #0
        STA  TXTMT
        LDA  (P2)            ; empty text -> delete
        JNZ  dl1
        LDA  #1
        STA  TXTMT
dl1:    JSR  EDIT
        JMP  REPL

;==============================================================================
; EDIT — rebuild PROG into PBUF inserting/replacing/deleting LNUM, then copy back
;==============================================================================
EDIT:   LDA  #0
        STA  INSF
        LDP1 #PROG           ; src
        LDP2 #PBUF           ; dst
ed_loop:
        LDA  (P1)+           ; read record number
        STA  RNUM
        LDA  (P1)+
        STA  RNUM+1
        LDA  RNUM            ; end marker? (num == 0)
        LDB  RNUM+1
        OR
        JZ   ed_end
        LDA  INSF
        JNZ  ed_copy         ; new line already placed -> just copy rest
        LDA  RNUM            ; compare RNUM vs LNUM
        STA  NUM1
        LDA  RNUM+1
        STA  NUM1+1
        LDA  LNUM
        STA  NUM2
        LDA  LNUM+1
        STA  NUM2+1
        JSR  CMP16           ; Z=equal, C=RNUM>=LNUM
        JZ   ed_repl
        JC   ed_ins
        JMP  ed_copy         ; RNUM < LNUM -> keep this record
ed_ins: JSR  EMITNEW         ; RNUM > LNUM -> insert new before this
        LDA  #1
        STA  INSF
        JMP  ed_copy
ed_repl: JSR EMITNEW         ; same number -> emit new, drop the old
        LDA  #1
        STA  INSF
ed_skip: LDA (P1)+           ; skip old text incl terminator
        JNZ  ed_skip
        JMP  ed_loop
ed_copy: LDA RNUM            ; write number then copy text incl terminator
        STA  (P2)+
        LDA  RNUM+1
        STA  (P2)+
ed_ct:  LDA  (P1)+
        STA  (P2)+
        JNZ  ed_ct
        JMP  ed_loop
ed_end: LDA  INSF            ; src done; append new if not yet placed
        JNZ  ed_wm
        JSR  EMITNEW
ed_wm:  LDA  #0              ; write end marker 00,00
        STA  (P2)+
        LDA  #0
        STA  (P2)+
        JMP  PB2PROG         ; copy PBUF back to PROG (tail call)

; EMITNEW — write the entered line (LNUM + text) to dst (P2); nothing if deleting
EMITNEW: LDA TXTMT
        JNZ  en_done
        LDA  LNUM
        STA  (P2)+
        LDA  LNUM+1
        STA  (P2)+
        TPA1L                ; save src pointer
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        LDA  TSRC            ; P1 = text source in LBUF
        TAP1L
        LDA  TSRC+1
        TAP1H
en_ct:  LDA  (P1)+
        STA  (P2)+
        JNZ  en_ct           ; copy text incl terminator
        LDA  SAVE1           ; restore src pointer
        TAP1L
        LDA  SAVE1+1
        TAP1H
en_done: RTS

; PB2PROG — copy PBUF back to PROG up to and including the 00,00 marker
PB2PROG: LDP1 #PBUF
        LDP2 #PROG
pp_l:   LDA  (P1)+
        STA  (P2)+
        STA  RNUM
        LDA  (P1)+
        STA  (P2)+
        STA  RNUM+1
        LDA  RNUM
        LDB  RNUM+1
        OR
        JZ   pp_done         ; marker copied -> done
pp_t:   LDA  (P1)+
        STA  (P2)+
        JNZ  pp_t
        JMP  pp_l
pp_done: RTS

NEWPROG: LDA #0              ; empty program = bare 00,00 marker at PROG
        STA  PROG
        STA  PROG+1
        RTS

;==============================================================================
; LIST — print every stored line in order
;==============================================================================
LIST:   LDP1 #PROG
ls_l:   LDA  (P1)+
        STA  LNUM
        LDA  (P1)+
        STA  LNUM+1
        LDA  LNUM
        LDB  LNUM+1
        OR
        JZ   ls_done
        TPA1L                ; PRDEC uses P1 -> save/restore
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        JSR  PRDEC           ; print LNUM
        LDA  SAVE1
        TAP1L
        LDA  SAVE1+1
        TAP1H
        LDA  #' '
        JSR  PUTC
        JSR  PRTEXT          ; print tokenized text; leaves P1 at next record
        JSR  CRLF
        JMP  ls_l
ls_done: RTS

; PRTEXT — print tokenized text at (P1), expanding token bytes back to keywords;
;          leaves P1 just past the 00 terminator.
PRTEXT: LDA  (P1)+
        JZ   pt_done
        STA  TMPC
        LDB  #$80
        AND
        JZ   pt_lit
        TPA1L                ; token: save program ptr, print keyword, restore
        STA  SAVE2
        TPA1H
        STA  SAVE2+1
        LDA  TMPC
        JSR  PRKW
        LDA  SAVE2
        TAP1L
        LDA  SAVE2+1
        TAP1H
        JMP  PRTEXT
pt_lit: LDA  TMPC
        JSR  PUTC
        JMP  PRTEXT
pt_done: RTS

;==============================================================================
; 16-bit helpers — operands NUM1/NUM2 (lo,hi); results in NUM1
;==============================================================================
ADD16:  LDA  NUM1
        LDB  NUM2
        ADD
        STA  NUM1
        LDA  #0
        JNC  a16nc
        LDA  #1
a16nc:  STA  CYTMP
        LDA  NUM1+1
        LDB  NUM2+1
        ADD
        LDB  CYTMP
        ADD
        STA  NUM1+1
        RTS
SUB16:  LDA  NUM1
        LDB  NUM2
        SUB
        STA  NUM1
        LDA  #0
        JC   s16nb
        LDA  #1
s16nb:  STA  CYTMP
        LDA  NUM1+1
        LDB  NUM2+1
        SUB
        STA  NUM1+1
        LDA  CYTMP
        JZ   s16d
        LDA  NUM1+1
        DEC
        STA  NUM1+1
s16d:   RTS
CMP16:  LDA  NUM1+1          ; Z=equal, C=NUM1>=NUM2
        LDB  NUM2+1
        CMP
        JNZ  c16d
        LDA  NUM1
        LDB  NUM2
        CMP
c16d:   RTS
SHL16:  LDA  NUM1
        SHL
        STA  NUM1
        LDA  NUM1+1
        ROL
        STA  NUM1+1
        RTS

; PARSEDEC — digits at (P2) -> LNUM (P2 left at first non-digit)
PARSEDEC: LDA #0
        STA  LNUM
        STA  LNUM+1
pd1:    LDA  (P2)
        LDB  #'0'
        SUB
        JNC  pdd
        LDB  #10
        CMP
        JC   pdd
        STA  DIG
        INP2
        LDA  LNUM            ; NUM1 = LNUM
        STA  NUM1
        LDA  LNUM+1
        STA  NUM1+1
        JSR  SHL16           ; x2
        LDA  NUM1            ; NUM2 = x2
        STA  NUM2
        LDA  NUM1+1
        STA  NUM2+1
        JSR  SHL16           ; x4
        JSR  SHL16           ; x8
        JSR  ADD16           ; x8 + x2 = x10
        LDA  DIG             ; + digit
        STA  NUM2
        LDA  #0
        STA  NUM2+1
        JSR  ADD16
        LDA  NUM1
        STA  LNUM
        LDA  NUM1+1
        STA  LNUM+1
        JMP  pd1
pdd:    RTS

; PRDEC — print LNUM as unsigned decimal (no leading zeros)
PRDEC:  LDA  LNUM
        STA  NUM1
        LDA  LNUM+1
        STA  NUM1+1
        LDA  #1
        STA  LZ
        LDP1 #POW10
        LDA  #5
        STA  PCNT
prl:    LDA  (P1)+
        STA  NUM2
        LDA  (P1)+
        STA  NUM2+1
        LDA  #0
        STA  DIG
prs:    JSR  CMP16
        JNC  pre
        JSR  SUB16
        LDA  DIG
        INC
        STA  DIG
        JMP  prs
pre:    LDA  PCNT
        LDB  #1
        CMP
        JZ   prf             ; units: always print
        LDA  DIG
        JNZ  prsh
        LDA  LZ
        JNZ  prsk            ; suppress leading zero
prsh:   LDA  #0
        STA  LZ
prf:    LDA  DIG
        LDB  #'0'
        ADD
        JSR  PUTC
prsk:   LDA  PCNT
        DEC
        STA  PCNT
        JNZ  prl
        RTS
POW10:  .word 10000,1000,100,10,1

;==============================================================================
; TOKENIZER
;==============================================================================
; CRUNCH — tokenize LBUF in place: keywords -> single token bytes, strings and
; everything else left literal. (Output never overtakes input since tokens
; shrink, so in-place is safe.)
CRUNCH: LDP1 #LBUF                  ; read pointer
        LDA  #<LBUF
        STA  WP                     ; write pointer
        LDA  #>LBUF
        STA  WP+1
cr_lp:  LDA  (P1)
        JZ   cr_end
        LDB  #'"'
        CMP
        JZ   cr_str
        JSR  MATCHKW                ; keyword at (P1)?
        LDA  MATCHF
        JZ   cr_chr
        LDA  TOKEN                  ; yes: emit token byte
        JSR  CR_PUTW
        JMP  cr_lp
cr_chr: LDA  (P1)+                  ; no: copy one char
        JSR  CR_PUTW
        JMP  cr_lp
cr_str: LDA  (P1)+                  ; copy quote + body + closing quote literally
        JSR  CR_PUTW
cr_s1:  LDA  (P1)
        JZ   cr_end
        LDA  (P1)+
        JSR  CR_PUTW
        LDB  #'"'
        CMP
        JNZ  cr_s1
        JMP  cr_lp
cr_end: LDA  #0                     ; terminator
        JSR  CR_PUTW
        RTS

CR_PUTW: STA TMPC                   ; write A to (WP), WP++
        LDA  WP
        TAP2L
        LDA  WP+1
        TAP2H
        LDA  TMPC
        STA  (P2)
        INP2
        TPA2L
        STA  WP
        TPA2H
        STA  WP+1
        RTS

; MATCHKW — keyword at (P1)? sets MATCHF=1 + TOKEN and advances P1 past it,
;           else MATCHF=0 and P1 unchanged.  Uses P2 to walk KWTAB.
MATCHKW: TPA1L                      ; save input position
        STA  RP
        TPA1H
        STA  RP+1
        LDA  #<KWTAB
        TAP2L
        LDA  #>KWTAB
        TAP2H
mk_e:   LDA  (P2)
        JZ   mk_no                  ; end of table
mk_in:  LDA  (P2)
        STA  TMPC
        LDB  #$80
        AND
        JNZ  mk_hit                 ; reached token byte -> all letters matched
        LDA  (P1)                   ; compare input vs table letter
        LDB  TMPC
        CMP
        JNZ  mk_sk
        INP1
        INP2
        JMP  mk_in
mk_hit: LDA  TMPC
        STA  TOKEN
        LDA  #1
        STA  MATCHF
        RTS
mk_sk:  LDA  (P2)                   ; skip rest of this entry (letters + token)
        STA  TMPC
        INP2
        LDB  #$80
        AND
        JZ   mk_sk
        LDA  RP                     ; restore input, try next entry
        TAP1L
        LDA  RP+1
        TAP1H
        JMP  mk_e
mk_no:  LDA  #0
        STA  MATCHF
        LDA  RP
        TAP1L
        LDA  RP+1
        TAP1H
        RTS

; PRKW — print the keyword whose token == A (>= $80).  Uses P1 to walk KWTAB.
PRKW:   STA  TOKW
        LDA  #<KWTAB
        TAP1L
        LDA  #>KWTAB
        TAP1H
pk_e:   TPA1L                       ; remember this entry's letter start
        STA  RP
        TPA1H
        STA  RP+1
pk_sc:  LDA  (P1)+
        STA  TMPC
        LDB  #$80
        AND
        JZ   pk_sc                  ; skip letters to the token byte
        LDA  TMPC
        LDB  TOKW
        CMP
        JZ   pk_pr                  ; this entry's token matches
        LDA  (P1)
        JZ   pk_d                   ; table end
        JMP  pk_e
pk_pr:  LDA  RP                     ; re-walk letters from start, printing
        TAP1L
        LDA  RP+1
        TAP1H
pk_pl:  LDA  (P1)+
        STA  TMPC
        LDB  #$80
        AND
        JNZ  pk_d                   ; reached token -> done
        LDA  TMPC
        JSR  PUTC
        JMP  pk_pl
pk_d:   RTS

; keyword table: each entry = ASCII letters then the token byte (>= $80);
; a 00 ends the table.  (Token byte doubles as the entry's end marker.)
KWTAB:  .ascii "PRINT"
        .byte $80
        .ascii "LET"
        .byte $81
        .ascii "IF"
        .byte $82
        .ascii "THEN"
        .byte $83
        .ascii "FOR"
        .byte $84
        .ascii "TO"
        .byte $85
        .ascii "NEXT"
        .byte $86
        .ascii "GOTO"
        .byte $87
        .ascii "GOSUB"
        .byte $88
        .ascii "RETURN"
        .byte $89
        .ascii "INPUT"
        .byte $8A
        .ascii "REM"
        .byte $8B
        .ascii "END"
        .byte $8C
        .ascii "RUN"
        .byte $8D
        .ascii "LIST"
        .byte $8E
        .ascii "NEW"
        .byte $8F
        .ascii "ABS"
        .byte $90
        .ascii "RND"
        .byte $91
        .ascii "PEEK"
        .byte $92
        .ascii "POKE"
        .byte $93
        .byte $00

;==============================================================================
; Console
;==============================================================================
SKIPSP: LDA  (P2)
        LDB  #' '
        CMP
        JNZ  sks
        INP2
        JMP  SKIPSP
sks:    RTS
PUTC:   PHA
putc1:  LDA  ACIAS
        LDB  #$02
        AND
        JZ   putc1
        PLA
        STA  ACIAD
        RTS
GETC:   LDA  ACIAS
        LDB  #$01
        AND
        JZ   GETC
        LDA  ACIAD
        RTS
PUTS:   LDA  (P1)+
        JZ   putsx
        JSR  PUTC
        JMP  PUTS
putsx:  RTS
CRLF:   LDA  #CR
        JSR  PUTC
        LDA  #LF
        JSR  PUTC
        RTS
GETLINE: LDP2 #LBUF
gl1:    JSR  GETC
        LDB  #CR
        CMP
        JZ   gldone
        LDB  #BS
        CMP
        JZ   glbs
        LDB  #$7F
        CMP
        JZ   glbs
        JSR  PUTC
        STA  (P2)+
        JMP  gl1
glbs:   TPA2L
        LDB  #<LBUF
        CMP
        JZ   gl1
        DEP2
        LDA  #BS
        JSR  PUTC
        LDA  #' '
        JSR  PUTC
        LDA  #BS
        JSR  PUTC
        JMP  gl1
gldone: LDA  #0
        STA  (P2)
        JSR  CRLF
        RTS

;==============================================================================
BANNER: .byte CR,LF
        .ascii "P8X BASIC V0"
        .byte CR,LF,0
MOK:    .ascii "Ok"
        .byte CR,LF,0
MWHAT:  .byte $3F,CR,LF,0
