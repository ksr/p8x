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
RESULT = $807C          ; 16-bit expression result
ACC    = $807E          ; 16-bit mul/div accumulator
MCNT   = $8080          ; mul/div bit counter
REM    = $8082          ; 16-bit division remainder
CURLINE= $8084          ; RUN: pointer to current program line record
BRANCHF= $8086          ; RUN: 1 if a GOTO target is pending
ENDF   = $8087          ; RUN: 1 to stop the program
BRANCHN= $8088          ; RUN: pending GOTO target line number
RELOP  = $808A          ; comparison operator code (0..5)
GEF    = $808B          ; compare: left >= right
EQF    = $808C          ; compare: left == right
LFT    = $808D          ; comparison left operand (2)
FNDF   = $808F          ; FINDLINE: 1 if line found
GSTK   = $8090          ; GOSUB return stack (3 x 4 bytes: line record + text ptr)
GSP    = $809C          ; GOSUB stack depth
JUMPF  = $809D          ; RUN: 1 -> set CURLINE = JUMPADDR directly
JUMPADDR= $809E         ; direct jump target (line record pointer)
GTMP   = $80A0          ; scratch (2)
FSP    = $80A2          ; FOR stack depth
FFP    = $80A3          ; pointer to top FOR frame (2)
FSTK   = $80A5          ; FOR frames (2 x 9): letter, limit(2), step(2), LR(2), TP(2)
FORVAR = $80B7          ; FOR/NEXT scratch: loop variable letter
FLIM   = $80B8          ; FOR/NEXT scratch: limit (2)
FSTEP  = $80BA          ; FOR/NEXT scratch: step (2)
FLR    = $80BC          ; FOR/NEXT scratch: loop-back line record (2)
FTP    = $80BE          ; FOR/NEXT scratch: loop-back text pointer (2)
VARS   = $80C0          ; variables A-Z: 26 x 2 bytes ($80C0..$80F3)
SEED   = $80F4          ; RND state (2)
POKEA  = $80F6          ; POKE address (2)

; keyword tokens (>= $80 so they never collide with text or the 00 terminator)
TOK_PRINT = $80
TOK_LET  = $81
TOK_IF   = $82
TOK_THEN = $83
TOK_FOR  = $84
TOK_TO   = $85
TOK_NEXT = $86
TOK_GOTO = $87
TOK_GOSUB = $88
TOK_RETURN = $89
TOK_INPUT = $8A
TOK_REM  = $8B
TOK_END  = $8C
TOK_RUN  = $8D
TOK_LIST = $8E
TOK_NEW  = $8F
TOK_ABS  = $90
TOK_RND  = $91
TOK_PEEK = $92
TOK_POKE = $93
TOK_STEP = $94

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
        LDA  #$E1            ; seed the RNG
        STA  SEED
        LDA  #$AC
        STA  SEED+1
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
        JNC  RSTMT           ; ch < '0'
        LDB  #10
        CMP
        JC   RSTMT           ; ch > '9'
        JMP  DOLINE
RSTMT:  JSR  STMTLINE        ; immediate statement(s)
        JMP  REPL

; STMTLINE — execute a line: ':'-separated statements until end-of-line or a
; pending branch/jump/end. Used by RUN and immediate mode.
STMTLINE: JSR STMT
        LDA  ENDF
        JNZ  sl_d
        LDA  BRANCHF
        JNZ  sl_d
        LDA  JUMPF
        JNZ  sl_d
        JSR  SKIPSP
        LDA  (P2)
        LDB  #':'
        CMP
        JNZ  sl_d
        INP2
        JMP  STMTLINE
sl_d:   RTS

; STMT — execute the statement at (P2).  RTS when done.
STMT:   JSR  SKIPSP
        LDA  (P2)
        JZ   stmt_nop               ; empty statement (end of line / after ':')
        LDA  (P2)
        LDB  #TOK_PRINT
        CMP
        JZ   DOPRINT
        LDA  (P2)
        LDB  #TOK_LET
        CMP
        JZ   DOLET
        LDA  (P2)
        LDB  #TOK_RUN
        CMP
        JZ   DORUN
        LDA  (P2)
        LDB  #TOK_GOTO
        CMP
        JZ   DOGOTO
        LDA  (P2)
        LDB  #TOK_GOSUB
        CMP
        JZ   DOGOSUB
        LDA  (P2)
        LDB  #TOK_RETURN
        CMP
        JZ   DORET
        LDA  (P2)
        LDB  #TOK_FOR
        CMP
        JZ   DOFOR
        LDA  (P2)
        LDB  #TOK_NEXT
        CMP
        JZ   DONEXT
        LDA  (P2)
        LDB  #TOK_INPUT
        CMP
        JZ   DOINPUT
        LDA  (P2)
        LDB  #TOK_POKE
        CMP
        JZ   DOPOKE
        LDA  (P2)
        LDB  #TOK_REM
        CMP
        JZ   DOREM
        LDA  (P2)
        LDB  #TOK_IF
        CMP
        JZ   DOIF
        LDA  (P2)
        LDB  #TOK_END
        CMP
        JZ   DOEND
        LDA  (P2)
        LDB  #TOK_LIST
        CMP
        JZ   st_list
        LDA  (P2)
        LDB  #TOK_NEW
        CMP
        JZ   st_new
        LDA  (P2)            ; bare variable -> implicit LET
        LDB  #'A'
        SUB
        JNC  st_err
        LDB  #26
        CMP
        JC   st_err
        JMP  DOLET
st_list: JSR LIST
        LDP1 #MOK
        JSR  PUTS
        RTS
st_new: JSR  NEWPROG
        LDP1 #MOK
        JSR  PUTS
        RTS
st_err: LDP1 #MWHAT
        JSR  PUTS
stmt_nop: RTS

; SYNERR — abort current statement to the prompt (resets the stack)
SYNERR: LDP3 #STKTOP
        LDP1 #MSYN
        JSR  PUTS
        JMP  REPL

;==============================================================================
; STATEMENTS
;==============================================================================
; PRINT <expr> | PRINT "string" | PRINT
DOPRINT: INP2                       ; skip PRINT token
dp_item: JSR  SKIPSP
        LDA  (P2)
        JZ   dp_nl                  ; end of statement -> newline
        LDB  #':'
        CMP
        JZ   dp_nl
        LDB  #'"'
        CMP
        JZ   dp_str
        JSR  EVAL                   ; numeric item
        LDA  RESULT
        STA  LNUM
        LDA  RESULT+1
        STA  LNUM+1
        JSR  PRDEC
        JMP  dp_sep
dp_str: INP2                        ; string literal
ds_l:   LDA  (P2)
        JZ   dp_nl
        LDB  #'"'
        CMP
        JZ   ds_e
        LDA  (P2)
        JSR  PUTC
        INP2
        JMP  ds_l
ds_e:   INP2
dp_sep: JSR  SKIPSP
        LDA  (P2)
        LDB  #$3B                   ; ';' (byte value: ';' can't be a char literal here)
        CMP
        JZ   dp_semi
        LDB  #','
        CMP
        JZ   dp_comma
        JMP  dp_nl                  ; no separator -> newline
dp_semi: INP2
        JMP  dp_more
dp_comma: INP2
        LDA  #' '
        JSR  PUTC
dp_more: JSR  SKIPSP
        LDA  (P2)
        JZ   dp_done                ; trailing separator -> suppress newline
        LDB  #':'
        CMP
        JZ   dp_done
        JMP  dp_item
dp_nl:  JSR  CRLF
dp_done: RTS

; LET [LET] <var> = <expr>   (LET token optional -> implicit assignment)
DOLET:  LDA  (P2)
        LDB  #TOK_LET
        CMP
        JNZ  dl_var
        INP2                        ; skip LET token
        JSR  SKIPSP
dl_var: LDA  (P2)
        STA  TMPC
        LDB  #'A'
        SUB
        JNC  dl_err
        LDB  #26
        CMP
        JC   dl_err
        LDA  TMPC
        JSR  VARADDR                ; P1 = &var
        INP2                        ; consume letter
        TPA1L                       ; save var address across EXPR (uses P1)
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'='
        CMP
        JNZ  dl_err
        INP2
        JSR  EVAL                   ; RESULT = value (expr, optional comparison)
        LDA  SAVE1
        TAP1L
        LDA  SAVE1+1
        TAP1H
        LDA  RESULT
        STA  (P1)
        INP1
        LDA  RESULT+1
        STA  (P1)
        RTS
dl_err: JMP  SYNERR

;==============================================================================
; PROGRAM EXECUTION (RUN, GOTO, IF/THEN, END)
;==============================================================================
; RUN — execute the stored program from the lowest line number
DORUN:  LDA  #0
        STA  ENDF
        STA  GSP                    ; reset GOSUB and FOR stacks
        STA  FSP
        LDA  #<PROG
        STA  CURLINE
        LDA  #>PROG
        STA  CURLINE+1
run_l:  LDA  CURLINE
        TAP1L
        LDA  CURLINE+1
        TAP1H
        LDA  (P1)+
        STA  NUM1
        LDA  (P1)+
        STA  NUM1+1
        LDA  NUM1
        LDB  NUM1+1
        OR
        JZ   run_done               ; 00,00 marker = end of program
        TPA1L                       ; P2 = P1 (line text)
        TAP2L
        TPA1H
        TAP2H
run_exec: LDA #0                    ; entry point with P2 already positioned
        STA  BRANCHF
        STA  JUMPF
        JSR  STMTLINE
        LDA  ENDF
        JNZ  run_done
        LDA  JUMPF
        JNZ  run_jump
        LDA  BRANCHF
        JNZ  run_goto
        LDA  CURLINE                ; advance to next record
        TAP1L
        LDA  CURLINE+1
        TAP1H
        INP1
        INP1
rn_sk:  LDA  (P1)+
        JNZ  rn_sk
        TPA1L
        STA  CURLINE
        TPA1H
        STA  CURLINE+1
        JMP  run_l
run_goto: JSR FINDLINE
        LDA  FNDF
        JZ   run_undef
        TPA1L
        STA  CURLINE
        TPA1H
        STA  CURLINE+1
        JMP  run_l
run_jump: LDA JUMPF                ; 1 = jump to line record; 2 = resume at text ptr
        LDB  #2
        CMP
        JZ   run_resume
        LDA  JUMPADDR               ; mode 1 (RETURN): CURLINE = JUMPADDR
        STA  CURLINE
        LDA  JUMPADDR+1
        STA  CURLINE+1
        JMP  run_l
run_resume: LDA JUMPADDR            ; mode 2 (FOR loop-back): P2 = TP, CURLINE preset
        TAP2L
        LDA  JUMPADDR+1
        TAP2H
        JMP  run_exec
run_undef: LDP1 #MUNDEF
        JSR  PUTS
        RTS
run_done: LDP1 #MOK
        JSR  PUTS
        RTS

; FINDLINE — find the program line numbered BRANCHN; FNDF=1, P1=record start
FINDLINE: LDA #<PROG
        TAP1L
        LDA  #>PROG
        TAP1H
fl_l:   TPA1L
        STA  RP
        TPA1H
        STA  RP+1
        LDA  (P1)+
        STA  NUM1
        LDA  (P1)+
        STA  NUM1+1
        LDA  NUM1
        LDB  NUM1+1
        OR
        JZ   fl_no
        LDA  BRANCHN
        STA  NUM2
        LDA  BRANCHN+1
        STA  NUM2+1
        JSR  CMP16
        JZ   fl_found
fl_sk:  LDA  (P1)+
        JNZ  fl_sk
        JMP  fl_l
fl_found: LDA RP
        TAP1L
        LDA  RP+1
        TAP1H
        LDA  #1
        STA  FNDF
        RTS
fl_no:  LDA  #0
        STA  FNDF
        RTS

; GOTO <line>
DOGOTO: INP2
        JSR  SKIPSP
DOGOTON: JSR PARSEDEC
        LDA  LNUM
        STA  BRANCHN
        LDA  LNUM+1
        STA  BRANCHN+1
        LDA  #1
        STA  BRANCHF
        RTS

; IF <expr> THEN <statement | line-number>
DOIF:   INP2
        JSR  EVAL
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_THEN
        CMP
        JNZ  if_err
        INP2
        LDA  RESULT
        LDB  RESULT+1
        OR
        JZ   if_false               ; false -> skip rest of line
        JSR  SKIPSP
        LDA  (P2)                   ; digit after THEN -> implicit GOTO
        LDB  #'0'
        SUB
        JNC  if_stmt
        LDB  #10
        CMP
        JC   if_stmt
        JMP  DOGOTON
if_stmt: JMP  STMTLINE        ; THEN clause = rest of the line
if_false: RTS
if_err: JMP  SYNERR

; END — stop the running program
DOEND:  INP2
        LDA  #1
        STA  ENDF
        RTS

; INPUT <var> — prompt "? ", read a number from the console into <var>
DOINPUT: INP2
        JSR  SKIPSP
        LDA  (P2)
        STA  TMPC
        LDB  #'A'
        SUB
        JNC  in_err
        LDB  #26
        CMP
        JC   in_err
        LDA  TMPC
        JSR  VARADDR                ; P1 = &var
        INP2
        TPA1L
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        TPA2L                       ; save program text pointer
        STA  GTMP
        TPA2H
        STA  GTMP+1
        LDA  #'?'
        JSR  PUTC
        LDA  #' '
        JSR  PUTC
        JSR  GETLINE                ; read reply -> LBUF
        LDP2 #LBUF
        JSR  SKIPSP
        JSR  PARSEDEC               ; LNUM = entered value
        LDA  SAVE1
        TAP1L
        LDA  SAVE1+1
        TAP1H
        LDA  LNUM
        STA  (P1)
        INP1
        LDA  LNUM+1
        STA  (P1)
        LDA  GTMP                   ; restore program text pointer
        TAP2L
        LDA  GTMP+1
        TAP2H
        RTS
in_err: JMP  SYNERR

; POKE <addr>, <val> — write the low byte of val to memory (I/O via memory map)
DOPOKE: INP2
        JSR  EVAL
        LDA  RESULT
        STA  POKEA
        LDA  RESULT+1
        STA  POKEA+1
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  pk_err
        INP2
        JSR  EVAL
        LDA  POKEA
        TAP1L
        LDA  POKEA+1
        TAP1H
        LDA  RESULT
        STA  (P1)
        RTS
pk_err: JMP  SYNERR

; REM — comment: ignore the rest of the line
DOREM:  LDA  (P2)
        JZ   rem_d
        INP2
        JMP  DOREM
rem_d:  RTS

; GOSUB <line> — push return (line after this one), then branch to <line>
DOGOSUB: INP2
        JSR  SKIPSP
        JSR  DOGOTON                ; target -> BRANCHN, BRANCHF; P2 past number
        JSR  SKIPSP                 ; return point = next statement after GOSUB
        LDA  (P2)
        LDB  #':'
        CMP
        JNZ  gs_tp
        INP2                        ; skip ':' so resume lands on the next statement
gs_tp:  TPA2L
        STA  GTMP
        TPA2H
        STA  GTMP+1
        LDA  GSP                    ; GSTK entry addr = GSTK + GSP*4 -> P2
        SHL
        SHL
        LDB  #<GSTK
        ADD
        TAP2L
        LDA  #>GSTK
        TAP2H
        LDA  CURLINE                ; entry = (CURLINE, return-text-ptr)
        STA  (P2)
        INP2
        LDA  CURLINE+1
        STA  (P2)
        INP2
        LDA  GTMP
        STA  (P2)
        INP2
        LDA  GTMP+1
        STA  (P2)
        LDA  GSP
        INC
        STA  GSP
        RTS

; RETURN — pop a return point and resume just after the GOSUB
DORET:  INP2
        LDA  GSP
        JZ   ret_err
        DEC
        STA  GSP
        SHL
        SHL
        LDB  #<GSTK
        ADD
        TAP2L
        LDA  #>GSTK
        TAP2H
        LDA  (P2)
        STA  CURLINE
        INP2
        LDA  (P2)
        STA  CURLINE+1
        INP2
        LDA  (P2)
        STA  JUMPADDR
        INP2
        LDA  (P2)
        STA  JUMPADDR+1
        LDA  #2
        STA  JUMPF
        RTS
ret_err: LDP1 #MRG
        JSR  PUTS
        LDA  #1
        STA  ENDF
        RTS

; FOR <var> = <start> TO <limit> [STEP <n>]
DOFOR:  INP2
        JSR  SKIPSP
        LDA  (P2)
        STA  TMPC
        LDB  #'A'
        SUB
        JNC  for_err
        LDB  #26
        CMP
        JC   for_err
        LDA  TMPC
        STA  FORVAR
        JSR  VARADDR
        INP2
        TPA1L
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'='
        CMP
        JNZ  for_err
        INP2
        JSR  EVAL                   ; start value
        LDA  SAVE1
        TAP1L
        LDA  SAVE1+1
        TAP1H
        LDA  RESULT
        STA  (P1)
        INP1
        LDA  RESULT+1
        STA  (P1)
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_TO
        CMP
        JNZ  for_err
        INP2
        JSR  EVAL                   ; limit
        LDA  RESULT
        STA  FLIM
        LDA  RESULT+1
        STA  FLIM+1
        LDA  #1                     ; default STEP 1
        STA  FSTEP
        LDA  #0
        STA  FSTEP+1
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_STEP
        CMP
        JNZ  for_push
        INP2
        JSR  EVAL
        LDA  RESULT
        STA  FSTEP
        LDA  RESULT+1
        STA  FSTEP+1
for_push: JSR SKIPSP                ; loop-back = the statement after FOR
        LDA  (P2)
        LDB  #':'
        CMP
        JZ   fp_same                ; more on this line -> loop back mid-line
        ; FOR ends the line -> loop back to the next line
        LDA  CURLINE
        TAP1L
        LDA  CURLINE+1
        TAP1H
        INP1
        INP1
fp_sk:  LDA  (P1)+
        JNZ  fp_sk
        TPA1L                       ; P1 = next line record
        STA  FLR
        TPA1H
        STA  FLR+1
        INP1
        INP1
        TPA1L                       ; TP = its text
        STA  FTP
        TPA1H
        STA  FTP+1
        JMP  fp_alloc
fp_same: INP2                       ; advance past ':'
        TPA2L                       ; loop-back text = right after the ':'
        STA  FTP
        TPA2H
        STA  FTP+1
        DEP2                        ; leave P2 on the ':' so STMTLINE keeps going now
        LDA  CURLINE
        STA  FLR
        LDA  CURLINE+1
        STA  FLR+1
fp_alloc: LDA FSP                   ; advance FFP to a fresh frame
        JNZ  fp_adv
        LDA  #<FSTK
        STA  FFP
        LDA  #>FSTK
        STA  FFP+1
        JMP  fp_w
fp_adv: LDA  FFP
        LDB  #9
        ADD
        STA  FFP
        JNC  fp_w
        LDA  FFP+1
        INC
        STA  FFP+1
fp_w:   LDA  FFP                    ; write the 9-byte frame
        TAP1L
        LDA  FFP+1
        TAP1H
        LDA  FORVAR
        STA  (P1)
        INP1
        LDA  FLIM
        STA  (P1)
        INP1
        LDA  FLIM+1
        STA  (P1)
        INP1
        LDA  FSTEP
        STA  (P1)
        INP1
        LDA  FSTEP+1
        STA  (P1)
        INP1
        LDA  FLR
        STA  (P1)
        INP1
        LDA  FLR+1
        STA  (P1)
        INP1
        LDA  FTP
        STA  (P1)
        INP1
        LDA  FTP+1
        STA  (P1)
        LDA  FSP
        INC
        STA  FSP
        RTS
for_err: JMP  SYNERR

; NEXT [<var>] — step the top FOR loop; loop back or pop the frame
DONEXT: INP2
        JSR  SKIPSP
        LDA  (P2)                   ; optional variable name -> skip it
        LDB  #'A'
        SUB
        JNC  nx_go
        LDB  #26
        CMP
        JC   nx_go
        INP2
nx_go:  LDA  FSP
        JZ   nx_err
        LDA  FFP                    ; read frame fields
        TAP1L
        LDA  FFP+1
        TAP1H
        LDA  (P1)
        STA  FORVAR
        INP1
        LDA  (P1)
        STA  FLIM
        INP1
        LDA  (P1)
        STA  FLIM+1
        INP1
        LDA  (P1)
        STA  FSTEP
        INP1
        LDA  (P1)
        STA  FSTEP+1
        INP1
        LDA  (P1)
        STA  FLR
        INP1
        LDA  (P1)
        STA  FLR+1
        INP1
        LDA  (P1)
        STA  FTP
        INP1
        LDA  (P1)
        STA  FTP+1
        LDA  FORVAR                 ; var = var + step
        JSR  VARADDR
        TPA1L
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        LDA  (P1)
        STA  NUM1
        INP1
        LDA  (P1)
        STA  NUM1+1
        LDA  FSTEP
        STA  NUM2
        LDA  FSTEP+1
        STA  NUM2+1
        JSR  ADD16
        LDA  SAVE1
        TAP1L
        LDA  SAVE1+1
        TAP1H
        LDA  NUM1
        STA  (P1)
        INP1
        LDA  NUM1+1
        STA  (P1)
        LDA  FLIM                   ; compare var (NUM1) vs limit (signed)
        STA  NUM2
        LDA  FLIM+1
        STA  NUM2+1
        LDA  NUM1+1
        LDB  #$80
        XOR
        STA  NUM1+1
        LDA  NUM2+1
        LDB  #$80
        XOR
        STA  NUM2+1
        JSR  CMP16                  ; Z=equal, C=var>=limit
        JZ   nx_loop                ; var == limit -> loop once more
        JC   nx_done                ; var > limit -> finished
        JMP  nx_loop                ; var < limit -> loop
nx_loop: LDA FLR                    ; resume at loop-back (CURLINE=LR, P2=TP)
        STA  CURLINE
        LDA  FLR+1
        STA  CURLINE+1
        LDA  FTP
        STA  JUMPADDR
        LDA  FTP+1
        STA  JUMPADDR+1
        LDA  #2
        STA  JUMPF
        RTS
nx_done: LDA FSP                    ; pop the frame
        DEC
        STA  FSP
        JZ   nx_ret
        LDA  FFP
        LDB  #9
        SUB
        STA  FFP
        JC   nx_ret
        LDA  FFP+1
        DEC
        STA  FFP+1
nx_ret: RTS
nx_err: JMP  SYNERR

;==============================================================================
; EXPRESSION EVALUATOR (recursive descent) — result -> RESULT
;   EXPR   = TERM   (('+'|'-') TERM)*
;   TERM   = FACTOR (('*'|'/') FACTOR)*
;   FACTOR = number | variable | '(' EXPR ')'
; The running left value is pushed (lo,hi) across the recursive call.
;==============================================================================
; EVAL — an arithmetic EXPR, then an optional comparison -> RESULT (1=true/0=false)
EVAL:   JSR  EXPR
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'='
        CMP
        JZ   ev_eq
        LDA  (P2)
        LDB  #'<'
        CMP
        JZ   ev_lt
        LDA  (P2)
        LDB  #'>'
        CMP
        JZ   ev_gt
        RTS                         ; no comparison: RESULT is the arithmetic value
ev_eq:  INP2
        LDA  #0
        STA  RELOP
        JMP  ev_rhs
ev_lt:  INP2
        LDA  (P2)
        LDB  #'='
        CMP
        JZ   ev_le
        LDA  (P2)
        LDB  #'>'
        CMP
        JZ   ev_ne
        LDA  #1
        STA  RELOP
        JMP  ev_rhs
ev_le:  INP2
        LDA  #3
        STA  RELOP
        JMP  ev_rhs
ev_ne:  INP2
        LDA  #5
        STA  RELOP
        JMP  ev_rhs
ev_gt:  INP2
        LDA  (P2)
        LDB  #'='
        CMP
        JZ   ev_ge
        LDA  #2
        STA  RELOP
        JMP  ev_rhs
ev_ge:  INP2
        LDA  #4
        STA  RELOP
ev_rhs: LDA  RESULT                 ; left operand
        STA  LFT
        LDA  RESULT+1
        STA  LFT+1
        JSR  EXPR                   ; right -> RESULT
        LDA  LFT
        STA  NUM1
        LDA  LFT+1
        STA  NUM1+1
        LDA  RESULT
        STA  NUM2
        LDA  RESULT+1
        STA  NUM2+1
        LDA  NUM1+1                  ; bias by $8000 -> signed ordering
        LDB  #$80
        XOR
        STA  NUM1+1
        LDA  NUM2+1
        LDB  #$80
        XOR
        STA  NUM2+1
        JSR  CMP16                  ; Z=equal, C=left>=right (signed)
        JZ   ev_ceq
        JC   ev_cgt
        LDA  #0                     ; left < right
        STA  GEF
        STA  EQF
        JMP  ev_disp
ev_cgt: LDA  #1
        STA  GEF
        LDA  #0
        STA  EQF
        JMP  ev_disp
ev_ceq: LDA  #1
        STA  GEF
        STA  EQF
ev_disp: LDA #0
        STA  RESULT+1
        LDA  RELOP
        JZ   ev_req                 ; '='  -> EQF
        LDB  #1
        CMP
        JZ   ev_rlt                 ; '<'  -> !GEF
        LDA  RELOP
        LDB  #2
        CMP
        JZ   ev_rgt                 ; '>'  -> GEF & !EQF
        LDA  RELOP
        LDB  #3
        CMP
        JZ   ev_rle                 ; '<=' -> !GEF | EQF
        LDA  RELOP
        LDB  #4
        CMP
        JZ   ev_rge                 ; '>=' -> GEF
        LDA  EQF                    ; '<>' -> !EQF
        LDB  #1
        XOR
        STA  RESULT
        RTS
ev_req: LDA  EQF
        STA  RESULT
        RTS
ev_rge: LDA  GEF
        STA  RESULT
        RTS
ev_rlt: LDA  GEF
        LDB  #1
        XOR
        STA  RESULT
        RTS
ev_rgt: LDA  EQF
        LDB  #1
        XOR
        STA  TMPC
        LDA  GEF
        LDB  TMPC
        AND
        STA  RESULT
        RTS
ev_rle: LDA  GEF
        LDB  #1
        XOR
        STA  TMPC
        LDA  EQF
        LDB  TMPC
        OR
        STA  RESULT
        RTS

EXPR:   JSR  TERM
ex_l:   JSR  SKIPSP
        LDA  (P2)
        LDB  #'+'
        CMP
        JZ   ex_add
        LDA  (P2)
        LDB  #'-'
        CMP
        JZ   ex_sub
        RTS
ex_add: INP2
        LDA  RESULT
        PHA
        LDA  RESULT+1
        PHA
        JSR  TERM
        PLA
        STA  NUM1+1
        PLA
        STA  NUM1
        LDA  RESULT
        STA  NUM2
        LDA  RESULT+1
        STA  NUM2+1
        JSR  ADD16
        JMP  ex_store
ex_sub: INP2
        LDA  RESULT
        PHA
        LDA  RESULT+1
        PHA
        JSR  TERM
        PLA
        STA  NUM1+1
        PLA
        STA  NUM1
        LDA  RESULT
        STA  NUM2
        LDA  RESULT+1
        STA  NUM2+1
        JSR  SUB16
ex_store: LDA NUM1
        STA  RESULT
        LDA  NUM1+1
        STA  RESULT+1
        JMP  ex_l

TERM:   JSR  FACTOR
tm_l:   JSR  SKIPSP
        LDA  (P2)
        LDB  #'*'
        CMP
        JZ   tm_mul
        LDA  (P2)
        LDB  #'/'
        CMP
        JZ   tm_div
        RTS
tm_mul: INP2
        LDA  RESULT
        PHA
        LDA  RESULT+1
        PHA
        JSR  FACTOR
        PLA
        STA  NUM1+1
        PLA
        STA  NUM1
        LDA  RESULT
        STA  NUM2
        LDA  RESULT+1
        STA  NUM2+1
        JSR  MUL16
        JMP  tm_store
tm_div: INP2
        LDA  RESULT
        PHA
        LDA  RESULT+1
        PHA
        JSR  FACTOR
        PLA
        STA  NUM1+1
        PLA
        STA  NUM1
        LDA  RESULT
        STA  NUM2
        LDA  RESULT+1
        STA  NUM2+1
        JSR  DIV16
tm_store: LDA NUM1
        STA  RESULT
        LDA  NUM1+1
        STA  RESULT+1
        JMP  tm_l

FACTOR: JSR  SKIPSP
        LDA  (P2)
        LDB  #'-'                ; unary minus
        CMP
        JZ   fa_neg
        LDA  (P2)
        LDB  #'+'                ; unary plus (no-op)
        CMP
        JZ   fa_plus
        LDA  (P2)
        LDB  #TOK_ABS
        CMP
        JZ   fa_abs
        LDA  (P2)
        LDB  #TOK_RND
        CMP
        JZ   fa_rnd
        LDA  (P2)
        LDB  #TOK_PEEK
        CMP
        JZ   fa_peek
        LDA  (P2)
        LDB  #'('
        CMP
        JZ   fa_par
        LDA  (P2)               ; digit?
        LDB  #'0'
        SUB
        JNC  fa_var
        LDB  #10
        CMP
        JC   fa_var
        JSR  PARSEDEC           ; number -> LNUM
        LDA  LNUM
        STA  RESULT
        LDA  LNUM+1
        STA  RESULT+1
        RTS
fa_var: LDA  (P2)               ; variable A-Z?
        STA  TMPC
        LDB  #'A'
        SUB
        JNC  fa_err
        LDB  #26
        CMP
        JC   fa_err
        LDA  TMPC
        JSR  VARADDR            ; P1 = &var
        INP2
        LDA  (P1)
        STA  RESULT
        INP1
        LDA  (P1)
        STA  RESULT+1
        RTS
fa_par: INP2                    ; '('
        JSR  EXPR
        JSR  SKIPSP
        LDA  (P2)
        LDB  #')'
        CMP
        JNZ  fa_err
        INP2
        RTS
fa_plus: INP2                   ; unary plus: skip and parse the factor
        JMP  FACTOR
fa_neg: INP2                    ; unary minus: parse factor, negate RESULT
        JSR  FACTOR
        LDA  RESULT
        LDB  #$FF
        XOR
        STA  RESULT
        LDA  RESULT+1
        LDB  #$FF
        XOR
        STA  RESULT+1
        LDA  RESULT
        LDB  #1
        ADD
        STA  RESULT
        JNC  fa_nd
        LDA  RESULT+1
        INC
        STA  RESULT+1
fa_nd:  RTS
fa_err: JMP  SYNERR

; functions: ABS(x), RND(n), PEEK(addr) — RESULT set
fa_abs: INP2
        JSR  PARGET
        LDA  RESULT+1
        LDB  #$80
        AND
        JZ   fa_abd              ; non-negative
        LDA  RESULT
        LDB  #$FF
        XOR
        STA  RESULT
        LDA  RESULT+1
        LDB  #$FF
        XOR
        STA  RESULT+1
        LDA  RESULT
        LDB  #1
        ADD
        STA  RESULT
        JNC  fa_abd
        LDA  RESULT+1
        INC
        STA  RESULT+1
fa_abd: RTS
fa_peek: INP2
        JSR  PARGET              ; RESULT = address
        LDA  RESULT
        TAP1L
        LDA  RESULT+1
        TAP1H
        LDA  (P1)                ; read byte (I/O handled by memory map)
        STA  RESULT
        LDA  #0
        STA  RESULT+1
        RTS
fa_rnd: INP2
        JSR  PARGET              ; RESULT = n
        LDA  RESULT
        LDB  RESULT+1
        OR
        JZ   fa_rz               ; RND(0) -> 0
        LDA  RESULT
        STA  LFT
        LDA  RESULT+1
        STA  LFT+1
        JSR  RANDOM              ; NUM1 = random 16-bit
        LDA  LFT
        STA  NUM2
        LDA  LFT+1
        STA  NUM2+1
        JSR  DIV16               ; REM = random mod n
        LDA  REM                 ; RESULT = REM + 1  (range 1..n)
        LDB  #1
        ADD
        STA  RESULT
        LDA  REM+1
        STA  RESULT+1
        JNC  fa_rd
        LDA  RESULT+1
        INC
        STA  RESULT+1
fa_rd:  RTS
fa_rz:  LDA  #0
        STA  RESULT
        STA  RESULT+1
        RTS

; PARGET — parse '(' EXPR ')' into RESULT
PARGET: JSR  SKIPSP
        LDA  (P2)
        LDB  #'('
        CMP
        JNZ  pg_err
        INP2
        JSR  EXPR
        JSR  SKIPSP
        LDA  (P2)
        LDB  #')'
        CMP
        JNZ  pg_err
        INP2
        RTS
pg_err: JMP  SYNERR

; RANDOM — LCG: SEED = SEED*25173 + 13849; result in NUM1
RANDOM: LDA  SEED
        STA  NUM1
        LDA  SEED+1
        STA  NUM1+1
        LDA  #$55               ; 25173 = $6255
        STA  NUM2
        LDA  #$62
        STA  NUM2+1
        JSR  MUL16
        LDA  #$19               ; 13849 = $3619
        STA  NUM2
        LDA  #$36
        STA  NUM2+1
        JSR  ADD16
        LDA  NUM1
        STA  SEED
        LDA  NUM1+1
        STA  SEED+1
        RTS

; VARADDR — A = variable letter; sets P1 = VARS + (letter-'A')*2
VARADDR: LDB #'A'
        SUB
        SHL                     ; *2 (index 0..25 -> 0..50, no carry)
        LDB  #<VARS
        ADD
        TAP1L
        LDA  #>VARS
        TAP1H
        RTS

;==============================================================================
; 16-bit multiply / divide (shift-add / restoring) — operands NUM1,NUM2
;==============================================================================
; MUL16 — NUM1 = NUM1 * NUM2 (low 16 bits)
MUL16:  LDA  #0
        STA  ACC
        STA  ACC+1
        LDA  #16
        STA  MCNT
mu_l:   LDA  NUM2
        LDB  #1
        AND
        JZ   mu_sk
        LDA  ACC                ; ACC += NUM1
        LDB  NUM1
        ADD
        STA  ACC
        LDA  #0
        JNC  mu_c0
        LDA  #1
mu_c0:  STA  CYTMP
        LDA  ACC+1
        LDB  NUM1+1
        ADD
        LDB  CYTMP
        ADD
        STA  ACC+1
mu_sk:  JSR  SHL16              ; NUM1 <<= 1
        LDA  NUM2+1             ; NUM2 >>= 1
        SHR
        STA  NUM2+1
        LDA  NUM2
        ROR
        STA  NUM2
        LDA  MCNT
        DEC
        STA  MCNT
        JNZ  mu_l
        LDA  ACC
        STA  NUM1
        LDA  ACC+1
        STA  NUM1+1
        RTS

; DIV16 — NUM1 = NUM1 / NUM2 (quotient); remainder left in REM. /0 -> 0
DIV16:  LDA  NUM2
        LDB  NUM2+1
        OR
        JNZ  dv_ok
        LDA  #0
        STA  NUM1
        STA  NUM1+1
        RTS
dv_ok:  LDA  #0
        STA  REM
        STA  REM+1
        LDA  #16
        STA  MCNT
dv_l:   LDA  NUM1               ; dividend <<= 1, MSB -> C
        SHL
        STA  NUM1
        LDA  NUM1+1
        ROL
        STA  NUM1+1
        LDA  REM                ; REM = (REM<<1) | C
        ROL
        STA  REM
        LDA  REM+1
        ROL
        STA  REM+1
        LDA  REM+1              ; compare REM vs NUM2
        LDB  NUM2+1
        CMP
        JNZ  dv_hi
        LDA  REM
        LDB  NUM2
        CMP
        JC   dv_ge
        JMP  dv_lt
dv_hi:  JC   dv_ge
        JMP  dv_lt
dv_ge:  LDA  REM                ; REM -= NUM2
        LDB  NUM2
        SUB
        STA  REM
        LDA  #0
        JC   dv_g0
        LDA  #1
dv_g0:  STA  CYTMP
        LDA  REM+1
        LDB  NUM2+1
        SUB
        STA  REM+1
        LDA  CYTMP
        JZ   dv_g1
        LDA  REM+1
        DEC
        STA  REM+1
dv_g1:  LDA  NUM1               ; set quotient bit 0
        LDB  #1
        OR
        STA  NUM1
dv_lt:  LDA  MCNT
        DEC
        STA  MCNT
        JNZ  dv_l
        RTS

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
        JSR  PRDECU          ; line numbers are unsigned
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

; PRDEC — print LNUM as SIGNED decimal ('-' for negatives), then magnitude
PRDEC:  LDA  LNUM+1
        LDB  #$80
        AND
        JZ   PRDECU                 ; positive -> just print
        LDA  #'-'
        JSR  PUTC
        LDA  LNUM                   ; LNUM = -LNUM (two's complement)
        LDB  #$FF
        XOR
        STA  LNUM
        LDA  LNUM+1
        LDB  #$FF
        XOR
        STA  LNUM+1
        LDA  LNUM
        LDB  #1
        ADD
        STA  LNUM
        JNC  PRDECU
        LDA  LNUM+1
        INC
        STA  LNUM+1
; PRDECU — print LNUM as UNSIGNED decimal (no leading zeros)
PRDECU: LDA  LNUM
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
cr_str: LDA  (P1)+                  ; copy opening quote
        JSR  CR_PUTW
cr_s1:  LDA  (P1)
        JZ   cr_end
        LDB  #'"'                   ; closing quote? test BEFORE CR_PUTW clobbers A
        CMP
        JZ   cr_sx
        LDA  (P1)+
        JSR  CR_PUTW
        JMP  cr_s1
cr_sx:  LDA  (P1)+                  ; copy the closing quote and resume tokenizing
        JSR  CR_PUTW
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
        .ascii "STEP"
        .byte $94
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
MSYN:   .ascii "?SYNTAX ERROR"
        .byte CR,LF,0
MUNDEF: .ascii "?UNDEF'D LINE"
        .byte CR,LF,0
MRG:    .ascii "?RETURN WITHOUT GOSUB"
        .byte CR,LF,0
