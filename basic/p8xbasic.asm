;==============================================================================
; P8X BASIC — interpreter for the P8X TTL computer
;
; 6850 ACIA console at $FF04/05. Self-contained (own console + RAM), so it can
; run standalone, from ROM (launched by the monitor), or be booted from disk.
;
; Build targets differ only in two -D symbols (see basic/README.md):
;   BASORG  code origin   ($0000 standalone, $2000 in monitor ROM, $8000 disk)
;   BASRAM  data base      ($8000 standalone, $A000 when code lives in low RAM)
; PBUF (rebuild scratch) is fixed at $C000 for all. Defaults below give the
; standalone $0000/$8000 build; the disk/ROM builds pass -D to relocate.
;
; Program storage (PROG): a sorted sequence of records
;     [num-lo][num-hi][text bytes ...][00]
; terminated by a 00,00 line-number marker (line 0 is invalid in BASIC).
; Edits are done by rebuilding into a scratch buffer (PBUF) then copying back —
; simplest correct approach for variable-length records on this ISA.
;==============================================================================

BASORG = $0000          ; code origin (override with -D BASORG=...)
BASRAM = $8000          ; data base   (override with -D BASRAM=...)

ACIAS  = $FF04
ACIAD  = $FF05
CR     = $0D
LF     = $0A
BS     = $08

; BIOS filesystem calls (monitor ROM at $0100). Available in the ROM-in-monitor
; and disk builds, where the monitor is resident; NOT in the standalone build.
FLOADAT = $013F          ; bulk-read FLEN bytes from LBA into (P1)
; Files are found/created in the FRESOLVE-set directory (root if no FRESOLVE),
; so SAVE/LOAD and data files reach subdirectories by FRESOLVE-ing a path first.
FFIND   = $0118          ; find file FNAME in the resolved dir -> LBA + FLEN; C=1 if not found
FCREATE = $011B          ; create file FNAME (FSRC/FLEN) in the resolved dir; C=1 on error
FRESOLVE= $0133          ; resolve NUL-terminated path (P1) -> dir extent + leaf FNAME; C=1 bad path
; sequential byte streams (for BASIC data files):
FOPEN   = $0124          ; open file FNAME for reading (P1=512-byte buf); C=1 missing
FGETB   = $0127          ; next byte -> A; C=1 at end of file
FWOPEN  = $012A          ; open a write stream at the free pointer (uses SBUF)
FPUTB   = $012D          ; append byte A to the write stream
FCLOSE  = $0130          ; flush + register file FNAME (len = bytes written); C=1 if full
FNORM   = $0136          ; copy string (P1) -> FNAME, case-preserved, space-padded to 12
LBA     = $7047          ; CFREAD target LBA (byte 0); LBA1 = byte 1
LBA1    = $7048
FNAME   = $704A          ; 12-byte filename (space-padded)
FSRC    = $7056          ; FCREATE source address
FLEN    = $7058          ; file length in bytes

LBUF   = BASRAM+$00          ; input line buffer
NUM1   = BASRAM+$60          ; 16-bit math operands / results
NUM2   = BASRAM+$62
LNUM   = BASRAM+$64          ; entered/printed line number
RNUM   = BASRAM+$66          ; record line number during scan
TSRC   = BASRAM+$68          ; address of entered line text (in LBUF)
SAVE1  = BASRAM+$6A          ; pointer save slots
SAVE2  = BASRAM+$6C
DIG    = BASRAM+$6E
LZ     = BASRAM+$6F
PCNT   = BASRAM+$70
CYTMP  = BASRAM+$71
INSF   = BASRAM+$72          ; 1 once the new line has been emitted
TXTMT  = BASRAM+$73          ; 1 if entered line has empty text (delete)
WP     = BASRAM+$74          ; crunch write pointer
RP     = BASRAM+$76          ; pointer save (match / uncrunch)
TOKEN  = BASRAM+$78          ; token matched by MATCHKW
MATCHF = BASRAM+$79          ; 1 if MATCHKW found a keyword
TMPC   = BASRAM+$7A          ; byte scratch
TOKW   = BASRAM+$7B          ; token being uncrunched
RESULT = BASRAM+$7C          ; 16-bit expression result
ACC    = BASRAM+$7E          ; 16-bit mul/div accumulator
MCNT   = BASRAM+$80          ; mul/div bit counter
REM    = BASRAM+$82          ; 16-bit division remainder
CURLINE= BASRAM+$84          ; RUN: pointer to current program line record
BRANCHF= BASRAM+$86          ; RUN: 1 if a GOTO target is pending
ENDF   = BASRAM+$87          ; RUN: 1 to stop the program
BRANCHN= BASRAM+$88          ; RUN: pending GOTO target line number
RELOP  = BASRAM+$8A          ; comparison operator code (0..5)
GEF    = BASRAM+$8B          ; compare: left >= right
EQF    = BASRAM+$8C          ; compare: left == right
LFT    = BASRAM+$8D          ; comparison left operand (2)
FNDF   = BASRAM+$8F          ; FINDLINE: 1 if line found
GSTK   = BASRAM+$90          ; GOSUB return stack (3 x 4 bytes: line record + text ptr)
GSP    = BASRAM+$9C          ; GOSUB stack depth
CKDEP  = BASRAM+$9E          ; CHECKLINE: running parenthesis-nesting depth
CKREM  = BASRAM+$9F          ; CHECKLINE: 1 once a REM is seen (rest is a comment)
JUMPF  = BASRAM+$E3          ; RUN: 1 -> set CURLINE = JUMPADDR directly (was $70,
JUMPADDR= BASRAM+$E4         ;   which ALIASED PCNT — VARFIND's counter clobbered it,
                             ;   so any var past the first broke RUN's jump handling)
GTMP   = BASRAM+$A0          ; scratch (2)
FSP    = BASRAM+$A2          ; FOR stack depth
FFP    = BASRAM+$A3          ; pointer to top FOR frame (2)
FSTK   = BASRAM+$A5          ; FOR frames (2 x 9): var-index, limit(2), step(2), LR(2), TP(2)
FORIDX = BASRAM+$B7          ; FOR: loop variable's table index (saved across EVAL)
FLIM   = BASRAM+$B8          ; FOR/NEXT scratch: limit (2)
FSTEP  = BASRAM+$BA          ; FOR/NEXT scratch: step (2)
FLR    = BASRAM+$BC          ; FOR/NEXT scratch: loop-back line record (2)
FTP    = BASRAM+$BE          ; FOR/NEXT scratch: loop-back text pointer (2)
; variables are a name->value symbol table (replaces the old 26-letter array):
VARCNT = BASRAM+$C0          ; number of variables defined (0..NVARS)
VARIDX = BASRAM+$C1          ; VARGET result: the variable's table index
NMBUF  = BASRAM+$C2          ; parsed variable name, NAMLEN chars, space-padded
; string-variable scratch (all one-byte unless noted):
SVARCNT= BASRAM+$C8          ; number of string variables defined (0..NSVARS)
SVIDX  = BASRAM+$C9          ; SVARFIND result index
SLENV  = BASRAM+$CA          ; string length scratch
SI     = BASRAM+$CB          ; string byte-index / count scratch
SJ     = BASRAM+$CC          ; string byte-count scratch
FMODE  = BASRAM+$CD          ; data file: 0 closed, 1 open for input, 2 for output
OUTFILE= BASRAM+$CE          ; 1 while PRINT emits to the data file (via PUTCH)
SPA    = BASRAM+$D0          ; string source pointer (2)
SPD    = BASRAM+$D2          ; string dest pointer (2)
STRSINK= BASRAM+$D4          ; 1 while PUTCH captures into a string buffer (STR$)
STRSP  = BASRAM+$D5          ; string-sink append pointer (2)
STRSN  = BASRAM+$D7          ; string-sink char count
FLOOK  = BASRAM+$D8          ; input-file 1-byte lookahead (for EOF)
FLOOKC = BASRAM+$D9          ; 1 if the lookahead position is end-of-file
SEED   = BASRAM+$F4          ; RND state (2)
POKEA  = BASRAM+$F6          ; POKE address (2)
NAMLEN = 6                   ; significant variable-name length
NVARS  = 32                  ; symbol-table capacity (entry = NAMLEN+2 = 8 bytes)
VARTAB = BASRAM+$100         ; NVARS x 8 = 256 bytes ($x100..$x1FF)
; string values are [len byte][data...]; length is capped at SLEN. Four fixed
; work buffers live below the string-variable table, which lives below PROG.
SLEN   = 32                  ; maximum stored string length
SVENT  = 40                  ; string-var entry: NAMLEN name + 1 len + 32 data + pad
NSVARS = 16                  ; string-variable table capacity
STRACC = BASRAM+$200         ; SEVAL result accumulator (64 bytes)
STRTMP = BASRAM+$240         ; current term being produced (64)
STRTMPD= BASRAM+$241         ; STRTMP data area (past the length byte)
STRARG = BASRAM+$280         ; a string function's string argument (64)
STRCMP = BASRAM+$2C0         ; saved left operand during a string comparison (64)
SVARTAB= BASRAM+$300         ; NSVARS x SVENT = 640 bytes ($x300..$x57F)

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
TOK_BYE  = $95
TOK_HELP = $96
TOK_SAVE = $97
TOK_LOAD = $98
; string tokens
TOK_CHRS  = $99          ; CHR$
TOK_LEFTS = $9A          ; LEFT$
TOK_RIGHTS= $9B          ; RIGHT$
TOK_MIDS  = $9C          ; MID$
TOK_LEN   = $9D          ; LEN   (numeric result)
TOK_ASC   = $9E          ; ASC   (numeric result)
; data-file tokens
TOK_OPEN  = $9F          ; OPEN
TOK_CLOSE = $A0          ; CLOSE
TOK_OUTPUT= $A1          ; OUTPUT (OPEN ... FOR OUTPUT)
TOK_STRS  = $A2          ; STR$  (number -> string)
TOK_VAL   = $A3          ; VAL   (string -> number)
TOK_EOF   = $A4          ; EOF   (input channel at end -> 1/0)

MONITOR = $0000          ; reset vector — BYE returns here

PROG   = BASRAM+$580          ; program storage (string table occupies $300..$57F)
PBUF   = $C000          ; rebuild scratch buffer
STKTOP = $FEFF

;==============================================================================
        .org BASORG
        LDP3 #STKTOP
        LDA  #$03            ; ACIA master reset
        STA  ACIAS
        LDA  #$15            ; /16 clock, 8N1
        STA  ACIAS
        JSR  NEWPROG         ; empty program
        LDA  #0              ; no data file open
        STA  FMODE
        STA  OUTFILE
        STA  STRSINK         ; PUTCH not capturing into a string
        LDA  #$E1            ; seed the RNG
        STA  SEED
        LDA  #$AC
        STA  SEED+1
        LDP1 #BANNER
        JSR  PUTS

; ---------------- REPL -------------------------------------------------------
REPL:   JSR  GETLINE         ; line -> LBUF
        JSR  CRUNCH          ; tokenize keywords in place
        JSR  CHECKLINE       ; reject malformed lines at entry (C=1 -> reported)
        JC   REPL
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
        JZ   sl_d                   ; end of line -> done
        LDB  #':'
        CMP
        JNZ  sl_err                 ; not ':' and not EOL -> leftover garbage
        INP2
        JMP  STMTLINE
sl_err: JMP  SYNERR                 ; e.g. an unsupported operator like '^'
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
        LDA  (P2)
        LDB  #TOK_BYE
        CMP
        JZ   DOBYE
        LDA  (P2)
        LDB  #TOK_HELP
        CMP
        JZ   st_help
        LDA  (P2)
        LDB  #TOK_SAVE
        CMP
        JZ   st_save
        LDA  (P2)
        LDB  #TOK_LOAD
        CMP
        JZ   st_load
        LDA  (P2)
        LDB  #TOK_OPEN
        CMP
        JZ   DOOPEN
        LDA  (P2)
        LDB  #TOK_CLOSE
        CMP
        JZ   DOCLOSE
        LDA  (P2)            ; bare variable -> implicit LET
        LDB  #'A'
        SUB
        JNC  st_err
        LDB  #26
        CMP
        JC   st_err
        JMP  DOLET
st_list: INP2               ; consume the LIST token (so STMTLINE sees end-of-line)
        JSR  LIST
        LDP1 #MOK
        JSR  PUTS
        RTS
st_new: INP2                ; consume the NEW token
        JSR  NEWPROG
        LDP1 #MOK
        JSR  PUTS
        RTS
st_help: INP2               ; consume the HELP token
        LDP1 #MHELP
        JSR  PUTS
        RTS
; BYE — leave BASIC by jumping to the reset vector ($0000). In the ROM and
; disk builds that re-enters the monitor (its ROM lives at $0000); standalone,
; it just restarts BASIC.
DOBYE:  JMP  MONITOR

; ---------------------------------------------------------------------------
; SAVE "name" / LOAD "name" — persist the program to a P8XFS v2 root file via
; the monitor's BIOS FS calls (works in the ROM-in-monitor and disk builds;
; the standalone build has no resident monitor/BIOS).
; ---------------------------------------------------------------------------
st_save:INP2                        ; consume the SAVE token
        JSR  GETPATH                ; "path" -> PBUF ; C set = syntax error
        JC   fs_serr
        LDP1 #PBUF                   ; resolve it: subdir path or bare name (=root)
        JSR  FRESOLVE                ; -> DIRLBA + leaf FNAME ; C=1 bad path
        JC   sv_ferr
        JSR  PROGLEN                 ; FLEN = program length (incl 00,00 marker)
        LDA  #<PROG
        STA  FSRC
        LDA  #>PROG
        STA  FSRC+1
        JSR  FCREATE
        JC   sv_ferr
        LDP1 #MSAVED
        JSR  PUTS
        RTS
sv_ferr:LDP1 #MFSERR                 ; ?SAVE FAILED (exists or disk full)
        JSR  PUTS
        RTS
fs_serr:JMP  SYNERR

st_load:INP2                        ; consume the LOAD token
        JSR  GETPATH
        JC   fs_serr
        LDP1 #PBUF
        JSR  FRESOLVE                ; -> DIRLBA + leaf FNAME ; C=1 bad path
        JC   ld_nf
        JSR  FFIND                   ; -> LBA + FLEN, or C set if missing
        JC   ld_nf
        LDP1 #PROG                   ; bulk-read the whole file into PROG
        JSR  FLOADAT
        LDP1 #MLOADED
        JSR  PUTS
        RTS
ld_nf:  LDP1 #MNOFILE
        JSR  PUTS
        RTS

; GETPATH — parse a quoted "path" at (P2) into PBUF as a NUL-terminated string,
;   CASE-PRESERVED (slashes kept), P2 past the closing quote. C set on syntax
;   error (no opening quote). The caller FRESOLVEs it, so a bare "NAME" resolves
;   in the root and "/SUB/NAME" descends — SAVE/LOAD reach subdirectories.
;   PBUF (the edit scratch) is free during immediate SAVE/LOAD; a path >47 chars
;   is truncated. Case-preserving matches the case-sensitive filesystem.
GETPATH: JSR  SKIPSP
        LDA  (P2)
        LDB  #'"'
        CMP
        JNZ  gf_err
        INP2                         ; past opening quote
        LDA  #<PBUF
        TAP1L
        LDA  #>PBUF
        TAP1H
        LDA  #47
        STA  RP                      ; chars of room left
gf_lp:  LDA  (P2)
        JZ   gf_ok                   ; line ended before the quote -> accept
        LDB  #'"'
        CMP
        JZ   gf_cl
        LDA  RP
        JZ   gf_adv                  ; full: consume but don't store
        LDA  (P2)                    ; store the char as typed (case preserved)
        STA  (P1)+
        LDA  RP
        DEC
        STA  RP
gf_adv: INP2
        JMP  gf_lp
gf_cl:  INP2                         ; past closing quote
gf_ok:  LDA  #0
        STA  (P1)                    ; NUL-terminate the path
        CLC
        RTS
gf_err: SEC
        RTS

; PROGLEN — FLEN = byte length of the program (PROG .. past the 00,00 marker).
PROGLEN:LDA  #<PROG
        TAP1L
        LDA  #>PROG
        TAP1H
pl_l:   LDA  (P1)+                   ; line# lo
        STA  TOKW
        LDA  (P1)+                   ; line# hi
        LDB  TOKW
        OR
        JZ   pl_end                  ; 00,00 marker -> end (P1 just past it)
pl_sk:  LDA  (P1)+                   ; skip the text to its 00 terminator
        JNZ  pl_sk
        JMP  pl_l
pl_end: TPA1L                        ; NUM1 = end pointer
        STA  NUM1
        TPA1H
        STA  NUM1+1
        LDA  #<PROG                  ; NUM2 = PROG
        STA  NUM2
        LDA  #>PROG
        STA  NUM2+1
        JSR  SUB16                   ; NUM1 = end - PROG = length
        LDA  NUM1
        STA  FLEN
        LDA  NUM1+1
        STA  FLEN+1
        RTS
st_err: LDP1 #MWHAT
        JSR  PUTS
stmt_nop: RTS

; SYNERR — abort current statement to the prompt (resets the stack)
SYNERR: LDP3 #STKTOP
        LDA  #0                      ; a PRINT# aborted mid-record must not leave
        STA  OUTFILE                 ; console output redirected to the file
        LDP1 #MSYN
        JSR  PUTS
        JMP  REPL

;==============================================================================
; STATEMENTS
;==============================================================================
; PRINT <expr> | PRINT "string" | PRINT
DOPRINT: INP2                       ; skip PRINT token
        JSR  SKIPSP
        LDA  (P2)                    ; PRINT# writes one value + CR to the data file
        LDB  #'#'
        CMP
        JZ   DOPRINTF
dp_item: JSR  SKIPSP
        LDA  (P2)
        JZ   dp_nl                  ; end of statement -> newline
        LDB  #':'
        CMP
        JZ   dp_nl
        JSR  SPEEK                  ; string item (literal / var / concat / function)?
        LDA  MATCHF
        JNZ  dp_pstr
        JSR  EVAL                   ; numeric item
        LDA  RESULT
        STA  LNUM
        LDA  RESULT+1
        STA  LNUM+1
        JSR  PRDEC
        JMP  dp_sep
dp_pstr: JSR  SEVAL                  ; string item -> STRACC
        JSR  SPUT
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
        JNZ  dl_chk
        INP2                        ; skip LET token
        JSR  SKIPSP
dl_chk: JSR  SPEEK                   ; string target (NAME$)?  -> string assignment
        LDA  MATCHF
        JNZ  dl_str
dl_var: JSR  VARGET                  ; parse name, look up/create -> P1 = &value
        LDA  MATCHF
        JZ   dl_err
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
; string assignment: NAME$ = <string expr>
dl_str: JSR  SVARGET                 ; parse NAME$, look up/create -> P1 = &entry
        LDA  MATCHF
        JZ   dl_err
        TPA1L                        ; save entry address across SEVAL
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'='
        CMP
        JNZ  dl_err
        INP2
        JSR  SEVAL                   ; STRACC = string value
        LDA  #<STRACC                ; store STRACC into the variable's data field
        STA  SPA
        LDA  #>STRACC
        STA  SPA+1
        LDA  SAVE1                   ; SPD = entry + NAMLEN (the len byte)
        LDB  #NAMLEN
        ADD
        STA  SPD
        LDA  SAVE1+1
        JNC  dls1
        INC
dls1:   STA  SPD+1
        JSR  SMOVE
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
        STA  FMODE                  ; abandon any data file left open by a prior run
        STA  OUTFILE
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
if_false: LDA (P2)            ; false: skip the whole THEN clause (to end of line)
        JZ   iff_d
        INP2
        JMP  if_false
iff_d:  RTS
if_err: JMP  SYNERR

; END — stop the running program
DOEND:  INP2
        LDA  #1
        STA  ENDF
        RTS

; INPUT <var> — prompt "? ", read a number from the console into <var>
DOINPUT: INP2
        JSR  SKIPSP
        LDA  (P2)                    ; INPUT# reads one record from the data file
        LDB  #'#'
        CMP
        JZ   DOINPUTF
        JSR  SPEEK                   ; string variable (NAME$)?  -> read a string
        LDA  MATCHF
        JNZ  in_str
        JSR  VARGET                 ; parse name, look up/create -> P1 = &value
        LDA  MATCHF
        JZ   in_err
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
; INPUT into a string variable: read a whole line into NAME$ (capped at SLEN)
in_str: JSR  SVARGET                 ; P1 = &entry
        TPA1L
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        TPA2L                        ; save program text pointer
        STA  GTMP
        TPA2H
        STA  GTMP+1
        LDA  #'?'
        JSR  PUTC
        LDA  #' '
        JSR  PUTC
        JSR  GETLINE                 ; reply -> LBUF
        LDP2 #LBUF                    ; copy LBUF -> STRACC (len+data, capped)
        LDP1 #STRACC
        INP1
        LDA  #0
        STA  SI
ins_cl: LDA  (P2)
        JZ   ins_ce
        LDA  SI
        LDB  #SLEN
        CMP
        JC   ins_ce
        LDA  (P2)
        STA  (P1)
        INP1
        INP2
        LDA  SI
        INC
        STA  SI
        JMP  ins_cl
ins_ce: LDP1 #STRACC
        LDA  SI
        STA  (P1)
        LDA  #<STRACC                ; store STRACC -> variable data
        STA  SPA
        LDA  #>STRACC
        STA  SPA+1
        LDA  SAVE1
        LDB  #NAMLEN
        ADD
        STA  SPD
        LDA  SAVE1+1
        JNC  ins_s1
        INC
ins_s1: STA  SPD+1
        JSR  SMOVE
        LDA  GTMP                    ; restore program text pointer
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
        JSR  VARGET                 ; loop variable -> P1 = &value, VARIDX
        LDA  MATCHF
        JZ   for_err
        LDA  VARIDX                 ; save its index for the frame (EVAL below
        STA  FORIDX                 ;   calls VARGET again and clobbers VARIDX)
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
        LDA  FORIDX                 ; frame[0] = loop variable's table index
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
        LDA  (P2)                   ; optional variable name -> consume it
        JSR  UPCHAR
        LDB  #'A'
        SUB
        JNC  nx_go
        LDB  #26
        CMP
        JC   nx_go
        JSR  VARGET                 ; consume the whole name (result ignored)
nx_go:  LDA  FSP
        JZ   nx_err
        LDA  FFP                    ; read frame fields
        TAP1L
        LDA  FFP+1
        TAP1H
        LDA  (P1)
        STA  VARIDX                 ; frame[0] = loop variable's index
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
        JSR  IDXADDR                ; var = var + step (P1 = &value, from VARIDX)
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
; EVAL — an arithmetic EXPR, then an optional comparison -> RESULT (1=true/0=false).
; A string-valued operand (detected by SPEEK) routes to EVALSTR, which requires a
; relational operator and yields 1/0 just like the numeric comparison below.
EVAL:   JSR  SPEEK
        LDA  MATCHF
        JNZ  EVALSTR
        JSR  EXPR
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
        LDA  (P2)
        LDB  #'%'
        CMP
        JZ   tm_mod
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
tm_mod: INP2                    ; '%' modulus: RESULT = left mod right (DIV16 REM)
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
        LDA  REM
        STA  RESULT
        LDA  REM+1
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
        LDB  #TOK_LEN
        CMP
        JZ   fa_len
        LDA  (P2)
        LDB  #TOK_ASC
        CMP
        JZ   fa_asc
        LDA  (P2)
        LDB  #TOK_VAL
        CMP
        JZ   fa_val
        LDA  (P2)
        LDB  #TOK_EOF
        CMP
        JZ   fa_eof
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
        LDA  (P2)               ; leading '0' -> maybe "0x" hex
        LDB  #'0'
        CMP
        JNZ  fa_dec
        TPA2L                   ; peek the char after '0' (save P2 on the stack)
        PHA
        TPA2H
        PHA
        INP2
        LDA  (P2)
        LDB  #'x'
        CMP
        JZ   fa_hex
        LDB  #'X'
        CMP
        JZ   fa_hex
        PLA                     ; not hex: restore P2 to the '0', parse decimal
        TAP2H
        PLA
        TAP2L
        JMP  fa_dec
fa_hex: PLA                     ; keep the advanced P2; drop the saved copy
        PLA
        INP2                    ; consume the 'x'
        JSR  PARSEHEX           ; hex digits -> RESULT
        RTS
fa_dec: JSR  PARSEDEC           ; number -> LNUM
        LDA  LNUM
        STA  RESULT
        LDA  LNUM+1
        STA  RESULT+1
        RTS
fa_var: JSR  VARGET            ; parse name, look up/create -> P1 = &value
        LDA  MATCHF
        JZ   fa_err
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

; UPCHAR — A: if 'a'..'z', clear bit 5 to uppercase; else leave A.
UPCHAR: LDB  #'a'
        CMP                     ; C=1 if A >= 'a'
        JNC  uc_ret
        LDB  #$7B               ; 'z' + 1
        CMP                     ; C=1 if A > 'z'
        JC   uc_ret
        LDB  #$DF
        AND
uc_ret: RTS

; ISALNUM — MATCHF=1 if A (upcased) is a letter A-Z or digit 0-9, else 0.
; Uses only A (preserved by CMP) and B.
ISALNUM: JSR UPCHAR
        LDB  #'0'
        CMP                     ; A >= '0' ?
        JNC  ia_no
        LDB  #$3A               ; '9' + 1
        CMP
        JNC  ia_yes             ; '0'..'9'
        LDB  #'A'
        CMP                     ; A >= 'A' ?
        JNC  ia_no
        LDB  #$5B               ; 'Z' + 1
        CMP
        JC   ia_no              ; > 'Z'
ia_yes: LDA  #1
        STA  MATCHF
        RTS
ia_no:  LDA  #0
        STA  MATCHF
        RTS

; VARGET — parse a variable name at (P2) (consuming it), look it up (creating a
; new zeroed entry on first use), and set P1 = &value and VARIDX = its index.
; MATCHF=1 if (P2) started a valid name (letter), else 0 (P2 unchanged).
VARGET: JSR  PARSENAME          ; NMBUF = name; MATCHF=1 if it started with a letter
        LDA  MATCHF
        JZ   vg_bad
        JSR  VARFIND           ; P1 = &value, VARIDX = index
        LDA  #1
        STA  MATCHF
        RTS
vg_bad: LDA  #0
        STA  MATCHF
        RTS

; PARSENAME — parse an identifier at (P2) into NMBUF (NAMLEN chars, upcased,
; space-padded), consuming it. MATCHF=1 if (P2) began with a letter (a name was
; read), else 0 with P2 unchanged. Shared by VARGET (numeric) and SVARGET (string).
PARSENAME: LDA (P2)             ; first char must be a letter
        JSR  UPCHAR
        LDB  #'A'
        SUB
        JNC  pn_bad
        LDB  #26
        CMP
        JC   pn_bad
        LDP1 #NMBUF             ; blank the name field
        LDA  #NAMLEN
        STA  TMPC
pn_fz:  LDA  #' '
        STA  (P1)
        INP1
        LDA  TMPC
        DEC
        STA  TMPC
        JNZ  pn_fz
        LDP1 #NMBUF            ; copy identifier chars (letters/digits), upcased
        LDA  #NAMLEN
        STA  TMPC
pn_cp:  LDA  (P2)
        JSR  ISALNUM
        LDA  MATCHF
        JZ   pn_end            ; non-alnum -> end of name
        LDA  TMPC
        JZ   pn_skip           ; name field full -> consume but don't store
        LDA  (P2)
        JSR  UPCHAR
        STA  (P1)
        INP1
        LDA  TMPC
        DEC
        STA  TMPC
pn_skip: INP2                  ; consume the char
        JMP  pn_cp
pn_end: LDA  #1
        STA  MATCHF
        RTS
pn_bad: LDA  #0
        STA  MATCHF
        RTS

; VARFIND — look up NMBUF in VARTAB; on a match P1 = &value, VARIDX = index.
; If absent, append a new entry (name = NMBUF, value = 0) and return its &value.
; Saves the input cursor (P2) on the stack while it walks the table with P2.
VARFIND: TPA2L
        PHA
        TPA2H
        PHA
        LDA  #0
        STA  PCNT               ; i = 0
vf_lp:  LDA  PCNT
        LDB  VARCNT
        CMP
        JZ   vf_new             ; i == VARCNT -> not found
        LDA  PCNT               ; P1 = VARTAB + i*8
        SHL
        SHL
        SHL
        TAP1L
        LDA  #>VARTAB
        TAP1H
        LDP2 #NMBUF             ; compare NAMLEN name bytes
        LDA  #NAMLEN
        STA  TMPC
        LDA  #1
        STA  MATCHF
vf_cmp: LDA  (P1)
        STA  CYTMP
        LDA  (P2)
        LDB  CYTMP
        CMP
        JZ   vf_c1
        LDA  #0
        STA  MATCHF
vf_c1:  INP1
        INP2
        LDA  TMPC
        DEC
        STA  TMPC
        JNZ  vf_cmp
        LDA  MATCHF
        JNZ  vf_hit             ; P1 now at &value (entry+NAMLEN)
        LDA  PCNT
        INC
        STA  PCNT
        JMP  vf_lp
vf_hit: LDA  PCNT
        STA  VARIDX
        JMP  vf_done
vf_new: LDA  VARCNT             ; create entry at index VARCNT
        STA  VARIDX
        SHL
        SHL
        SHL
        TAP1L
        LDA  #>VARTAB
        TAP1H
        LDP2 #NMBUF             ; copy the name in
        LDA  #NAMLEN
        STA  TMPC
vf_cp:  LDA  (P2)
        STA  (P1)
        INP1
        INP2
        LDA  TMPC
        DEC
        STA  TMPC
        JNZ  vf_cp
        LDA  #0                 ; zero the value (P1 now at &value)
        STA  (P1)
        TPA1L                   ; remember &value across the second store
        STA  RP
        TPA1H
        STA  RP+1
        INP1
        LDA  #0
        STA  (P1)
        LDA  VARCNT
        INC
        STA  VARCNT
        LDA  RP                 ; P1 = &value
        TAP1L
        LDA  RP+1
        TAP1H
vf_done: PLA                    ; restore the input cursor
        TAP2H
        PLA
        TAP2L
        RTS

; IDXADDR — VARIDX -> P1 = &value of that variable (VARTAB + VARIDX*8 + NAMLEN).
IDXADDR: LDA  VARIDX
        SHL
        SHL
        SHL
        LDB  #NAMLEN
        ADD
        TAP1L
        LDA  #>VARTAB
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
        STA  VARCNT          ; and no variables defined
        STA  SVARCNT         ; and no string variables defined
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

; PARSEHEX — parse hex digits at (P2) (after the "0x") -> RESULT. Accumulates
; LNUM = LNUM*16 + digit (16-bit, wraps past 4 digits). Stops at a non-hex char.
PARSEHEX: LDA #0
        STA  LNUM
        STA  LNUM+1
px1:    JSR  HEXDIG             ; (P2) -> DIG, MATCHF=1 if a hex digit
        LDA  MATCHF
        JZ   pxd
        LDA  LNUM               ; NUM1 = LNUM, then x16 (four left shifts)
        STA  NUM1
        LDA  LNUM+1
        STA  NUM1+1
        JSR  SHL16
        JSR  SHL16
        JSR  SHL16
        JSR  SHL16
        LDA  DIG                ; NUM2 = digit
        STA  NUM2
        LDA  #0
        STA  NUM2+1
        JSR  ADD16              ; NUM1 = NUM1 + digit
        LDA  NUM1
        STA  LNUM
        LDA  NUM1+1
        STA  LNUM+1
        INP2                    ; consume the hex digit
        JMP  px1
pxd:    LDA  LNUM
        STA  RESULT
        LDA  LNUM+1
        STA  RESULT+1
        RTS

; HEXDIG — classify the char at (P2) (not consumed). If a hex digit, DIG = its
; value 0..15 and MATCHF=1; else MATCHF=0. Accepts 0-9, A-F, a-f.
HEXDIG: LDA  (P2)
        LDB  #'0'
        SUB                     ; A = c - '0'; C=1 if c >= '0'
        JNC  hd_bad
        LDB  #10
        CMP                     ; C=1 if A >= 10 (letter range)
        JC   hd_alpha
        STA  DIG                ; 0-9
        LDA  #1
        STA  MATCHF
        RTS
hd_alpha: LDA (P2)
        LDB  #$DF
        AND                     ; upcase a letter
        LDB  #'A'
        SUB                     ; A = upc - 'A'
        JNC  hd_bad
        LDB  #6
        CMP                     ; C=1 if A >= 6 -> not A..F
        JC   hd_bad
        LDB  #10                ; digit = (upc-'A') + 10
        ADD
        STA  DIG
        LDA  #1
        STA  MATCHF
        RTS
hd_bad: LDA  #0
        STA  MATCHF
        RTS

; PRDEC — print LNUM as SIGNED decimal ('-' for negatives), then magnitude
PRDEC:  LDA  LNUM+1
        LDB  #$80
        AND
        JZ   PRDECU                 ; positive -> just print
        LDA  #'-'
        JSR  PUTCH
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
        JSR  PUTCH
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

;==============================================================================
; STRING SUPPORT
;
; A string value is [len byte][data...], length capped at SLEN. String variables
; (NAME$) live in SVARTAB (SVENT-byte entries: NAMLEN name + len + data). Four
; fixed buffers carry values around: STRACC (SEVAL result), STRTMP (one term),
; STRARG (a function's string arg), STRCMP (saved LHS of a comparison).
;==============================================================================

; SPEEK — does (P2) begin a STRING-valued expression? MATCHF=1/0; P2 unchanged.
; Yes for a "literal", a string function (CHR$/LEFT$/RIGHT$/MID$), or an
; identifier immediately followed by '$'.
SPEEK:  JSR  SKIPSP                   ; leading spaces are insignificant
        LDA  #0
        STA  MATCHF
        LDA  (P2)
        LDB  #'"'
        CMP
        JZ   sp_yes
        LDA  (P2)
        LDB  #TOK_CHRS
        CMP
        JZ   sp_yes
        LDA  (P2)
        LDB  #TOK_LEFTS
        CMP
        JZ   sp_yes
        LDA  (P2)
        LDB  #TOK_RIGHTS
        CMP
        JZ   sp_yes
        LDA  (P2)
        LDB  #TOK_MIDS
        CMP
        JZ   sp_yes
        LDA  (P2)
        LDB  #TOK_STRS
        CMP
        JZ   sp_yes
        LDA  (P2)                    ; a letter? then look for a trailing '$'
        JSR  UPCHAR
        LDB  #'A'
        CMP                          ; C=1 if >= 'A'
        JNC  sp_no
        LDB  #$5B                    ; 'Z' + 1
        CMP                          ; C=1 if > 'Z'
        JC   sp_no
        TPA2L                         ; walk a copy of P2 over the identifier
        TAP1L
        TPA2H
        TAP1H
sp_w:   LDA  (P1)
        JSR  ISALNUM
        LDA  MATCHF
        JZ   sp_chk
        INP1
        JMP  sp_w
sp_chk: LDA  (P1)
        LDB  #'$'
        CMP
        JZ   sp_yes
        LDA  #0
        STA  MATCHF
        RTS
sp_yes: LDA  #1
        STA  MATCHF
        RTS
sp_no:  LDA  #0
        STA  MATCHF
        RTS

; SVARGET — parse NAME$ at (P2) (consuming it, including the '$'), find/create the
; string variable, and set P1 = &entry (start of name) with MATCHF=1. If the name
; is not followed by '$', MATCHF=0.
SVARGET: JSR PARSENAME
        LDA  MATCHF
        JZ   svg_bad
        LDA  (P2)
        LDB  #'$'
        CMP
        JNZ  svg_bad
        INP2                         ; consume '$'
        JSR  SVARFIND                ; P1 = &entry
        LDA  #1
        STA  MATCHF
        RTS
svg_bad: LDA #0
        STA  MATCHF
        RTS

; SVENTADDR — P1 = SVARTAB + SI*SVENT  (SI = string-var index)
SVENTADDR: LDA SI
        STA  NUM1
        LDA  #0
        STA  NUM1+1
        LDA  #SVENT
        STA  NUM2
        LDA  #0
        STA  NUM2+1
        JSR  MUL16                   ; NUM1 = SI*SVENT
        LDA  #<SVARTAB
        STA  NUM2
        LDA  #>SVARTAB
        STA  NUM2+1
        JSR  ADD16                   ; NUM1 += SVARTAB
        LDA  NUM1
        TAP1L
        LDA  NUM1+1
        TAP1H
        RTS

; SVARFIND — look up NMBUF in SVARTAB. On a hit or after creating a new (empty)
; entry, P1 = &entry, SVIDX = index. Saves the input cursor (P2) on the stack.
SVARFIND: TPA2L
        PHA
        TPA2H
        PHA
        LDA  #0
        STA  SI                       ; i = 0
svf2lp: LDA  SI
        LDB  SVARCNT
        CMP
        JZ   svf2new                  ; i == SVARCNT -> not found
        JSR  SVENTADDR                ; P1 = &entry i
        LDP2 #NMBUF
        LDA  #NAMLEN
        STA  TMPC
        LDA  #1
        STA  MATCHF
svf2cm: LDA  (P1)
        STA  CYTMP
        LDA  (P2)
        LDB  CYTMP
        CMP
        JZ   svf2c1
        LDA  #0
        STA  MATCHF
svf2c1: INP1
        INP2
        LDA  TMPC
        DEC
        STA  TMPC
        JNZ  svf2cm
        LDA  MATCHF
        JNZ  svf2hit
        LDA  SI
        INC
        STA  SI
        JMP  svf2lp
svf2hit: LDA SI
        STA  SVIDX
        JSR  SVENTADDR                ; P1 = &entry
        JMP  svf2done
svf2new: LDA SVARCNT                  ; append a new entry
        STA  SVIDX
        STA  SI
        JSR  SVENTADDR                ; P1 = &entry
        LDP2 #NMBUF                    ; copy the name in
        LDA  #NAMLEN
        STA  TMPC
svf2cp: LDA  (P2)
        STA  (P1)
        INP1
        INP2
        LDA  TMPC
        DEC
        STA  TMPC
        JNZ  svf2cp
        LDA  #0                        ; empty value (P1 now at the len byte)
        STA  (P1)
        LDA  SVARCNT
        INC
        STA  SVARCNT
        JSR  SVENTADDR                ; reset P1 = &entry for the caller
svf2done: PLA
        TAP2H
        PLA
        TAP2L
        RTS

; SMOVE — copy the string at (SPA) to (SPD) (len byte + data). Uses P2 internally
; as the destination walker, so it saves and restores the parse cursor.
SMOVE:  TPA2L
        PHA
        TPA2H
        PHA
        LDA  SPA
        TAP1L
        LDA  SPA+1
        TAP1H
        LDA  SPD
        TAP2L
        LDA  SPD+1
        TAP2H
        LDA  (P1)
        STA  SLENV
        STA  (P2)
        INP1
        INP2
        LDA  SLENV
        JZ   smv_d
        STA  TMPC
smv_l:  LDA  (P1)+
        STA  (P2)
        INP2
        LDA  TMPC
        DEC
        STA  TMPC
        JNZ  smv_l
smv_d:  PLA
        TAP2H
        PLA
        TAP2L
        RTS

; SCPYLIT — copy the "..." literal at (P2) (P2 at the opening quote) into (SPD),
; capping at SLEN and consuming through the closing quote.
SCPYLIT: INP2
        LDA  SPD
        TAP1L
        LDA  SPD+1
        TAP1H
        INP1                          ; skip the len byte -> data
        LDA  #0
        STA  SI
scl_l:  LDA  (P2)
        JZ   scl_end
        LDB  #'"'
        CMP
        JZ   scl_cl
        LDA  SI
        LDB  #SLEN
        CMP
        JC   scl_sk                   ; full -> consume but don't store
        LDA  (P2)
        STA  (P1)
        INP1
        LDA  SI
        INC
        STA  SI
scl_sk: INP2
        JMP  scl_l
scl_cl: INP2
scl_end: LDA SPD
        TAP1L
        LDA  SPD+1
        TAP1H
        LDA  SI
        STA  (P1)
        RTS

; SAPP — append the string at (SPA) onto (SPD), capping the result at SLEN.
; Uses P2 as the destination walker, so it preserves the parse cursor.
SAPP:   TPA2L
        PHA
        TPA2H
        PHA
        LDA  SPA
        TAP1L
        LDA  SPA+1
        TAP1H
        LDA  (P1)
        STA  SJ                        ; src length
        INP1
        LDA  SPD
        TAP2L
        LDA  SPD+1
        TAP2H
        LDA  (P2)
        STA  SI                        ; dst length
        INP2
        LDA  SI                        ; advance P2 past existing data
        STA  TMPC
sap_ad: LDA  TMPC
        JZ   sap_go
        INP2
        LDA  TMPC
        DEC
        STA  TMPC
        JMP  sap_ad
sap_go: LDA  SJ
        JZ   sap_fin
        LDA  SI
        LDB  #SLEN
        CMP
        JC   sap_fin                   ; dst full
        LDA  (P1)+
        STA  (P2)
        INP2
        LDA  SI
        INC
        STA  SI
        LDA  SJ
        DEC
        STA  SJ
        JMP  sap_go
sap_fin: LDA SPD
        TAP1L
        LDA  SPD+1
        TAP1H
        LDA  SI
        STA  (P1)
        PLA
        TAP2H
        PLA
        TAP2L
        RTS

; SPUT — print the string in STRACC.
SPUT:   LDP1 #STRACC
        LDA  (P1)
        STA  TMPC
        INP1
spt_l:  LDA  TMPC
        JZ   spt_d
        LDA  (P1)+
        JSR  PUTCH
        LDA  TMPC
        DEC
        STA  TMPC
        JMP  spt_l
spt_d:  RTS

; SUBSTR — STRTMP = substring of STRARG starting at 0-based SI, length SJ, both
; clamped to the source. Used by LEFT$/RIGHT$/MID$.
SUBSTR: TPA2L
        PHA
        TPA2H
        PHA
        LDP1 #STRARG
        LDA  (P1)
        STA  SLENV                     ; L
        LDA  SI
        LDB  SLENV
        CMP                            ; SI >= L ?
        JC   sub_empty
        LDA  SLENV                     ; avail = L - SI
        LDB  SI
        SUB
        STA  SLENV
        LDA  SJ                        ; count = min(SJ, avail)
        LDB  SLENV
        CMP                            ; C=1 if SJ >= avail
        JNC  sub_pos
        LDA  SLENV
        STA  SJ
sub_pos: LDP1 #STRARG                  ; P1 = STRARG + 1 + SI
        INP1
        LDA  SI
        STA  TMPC
sub_ad: LDA  TMPC
        JZ   sub_go
        INP1
        LDA  TMPC
        DEC
        STA  TMPC
        JMP  sub_ad
sub_go: LDP2 #STRTMP                   ; P2 = STRTMP data
        INP2
        LDA  SJ
        STA  TMPC
sub_cp: LDA  TMPC
        JZ   sub_fin
        LDA  (P1)+
        STA  (P2)
        INP2
        LDA  TMPC
        DEC
        STA  TMPC
        JMP  sub_cp
sub_fin: LDP2 #STRTMP
        LDA  SJ
        STA  (P2)
        JMP  sub_done
sub_empty: LDP2 #STRTMP
        LDA  #0
        STA  (P2)
sub_done: PLA
        TAP2H
        PLA
        TAP2L
        RTS

; CLAMPN — SJ = RESULT clamped to 0..SLEN (negative -> 0, >255 -> SLEN).
CLAMPN: LDA  RESULT+1
        JZ   cn_lo
        LDB  #$80
        AND
        JZ   cn_big
        LDA  #0                        ; negative
        STA  SJ
        RTS
cn_big: LDA  #SLEN
        STA  SJ
        RTS
cn_lo:  LDA  RESULT
        STA  SJ
        RTS

; SARG — read a string variable or literal at (P2) into (SPD).
SARG:   JSR  SKIPSP
        LDA  (P2)
        LDB  #'"'
        CMP
        JZ   SCPYLIT                   ; literal -> (SPD); returns
        JSR  SVARGET
        LDA  MATCHF
        JZ   sarg_err
        TPA1L                          ; SPA = &entry + NAMLEN
        LDB  #NAMLEN
        ADD
        STA  SPA
        TPA1H
        JNC  sarg_v1
        INC
sarg_v1: STA SPA+1
        JSR  SMOVE
        RTS
sarg_err: JMP SYNERR

; STERM — produce one string term at (P2) into STRTMP.
STERM:  JSR  SKIPSP
        LDA  (P2)
        LDB  #'"'
        CMP
        JZ   stm_lit
        LDA  (P2)
        LDB  #TOK_CHRS
        CMP
        JZ   stm_chr
        LDA  (P2)
        LDB  #TOK_LEFTS
        CMP
        JZ   stm_left
        LDA  (P2)
        LDB  #TOK_RIGHTS
        CMP
        JZ   stm_right
        LDA  (P2)
        LDB  #TOK_MIDS
        CMP
        JZ   stm_mid
        LDA  (P2)
        LDB  #TOK_STRS
        CMP
        JZ   stm_strs
        JSR  SVARGET                   ; else: a string variable -> copy its data
        LDA  MATCHF
        JZ   stm_err
        TPA1L                          ; SPA = &entry + NAMLEN
        LDB  #NAMLEN
        ADD
        STA  SPA
        TPA1H
        JNC  stm_v1
        INC
stm_v1: STA  SPA+1
        LDA  #<STRTMP
        STA  SPD
        LDA  #>STRTMP
        STA  SPD+1
        JSR  SMOVE
        RTS
stm_lit: LDA #<STRTMP
        STA  SPD
        LDA  #>STRTMP
        STA  SPD+1
        JSR  SCPYLIT
        RTS
stm_chr: INP2
        JSR  PARGET                    ; RESULT = code
        LDP1 #STRTMP
        LDA  #1
        STA  (P1)
        INP1
        LDA  RESULT
        STA  (P1)
        RTS
; STR$(n) — render the number as decimal text into STRTMP. Reuses PRDEC by
; routing its PUTCH output into a string sink (STRSINK) aimed at STRTMP's data.
stm_strs: INP2
        JSR  PARGET                    ; RESULT = number
        LDA  RESULT
        STA  LNUM
        LDA  RESULT+1
        STA  LNUM+1
        LDA  #<STRTMPD                  ; capture digits after the length byte
        STA  STRSP
        LDA  #>STRTMPD
        STA  STRSP+1
        LDA  #0
        STA  STRSN
        LDA  #1
        STA  STRSINK
        JSR  PRDEC                      ; number text -> string sink
        LDA  #0
        STA  STRSINK
        LDP1 #STRTMP
        LDA  STRSN
        STA  (P1)                       ; length byte
        RTS
stm_err: JMP  SYNERR

; STM_OPEN — for LEFT$/RIGHT$/MID$: consume '(' , read the string arg into STRARG,
; consume ',' , evaluate the first numeric arg -> RESULT.
STM_OPEN: JSR SKIPSP
        LDA  (P2)
        LDB  #'('
        CMP
        JNZ  stm_err
        INP2
        LDA  #<STRARG
        STA  SPD
        LDA  #>STRARG
        STA  SPD+1
        JSR  SARG
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  stm_err
        INP2
        JSR  EXPR
        RTS
; STM_CLOSE — build the substring (STRARG[SI..], SJ chars) into STRTMP, consume ')'.
STM_CLOSE: JSR SUBSTR
        JSR  SKIPSP
        LDA  (P2)
        LDB  #')'
        CMP
        JNZ  stm_err
        INP2
        RTS
stm_left: INP2
        JSR  STM_OPEN                  ; STRARG set, RESULT = n
        JSR  CLAMPN                    ; SJ = n
        LDA  #0
        STA  SI
        JSR  STM_CLOSE
        RTS
stm_right: INP2
        JSR  STM_OPEN
        JSR  CLAMPN                    ; SJ = n
        LDP1 #STRARG
        LDA  (P1)
        STA  SLENV                     ; L
        LDA  SJ
        LDB  SLENV
        CMP                            ; n >= L ?
        JC   str_all
        LDA  SLENV                     ; SI = L - n
        LDB  SJ
        SUB
        STA  SI
        JMP  str_sub
str_all: LDA #0
        STA  SI
str_sub: JSR STM_CLOSE
        RTS
stm_mid: INP2
        JSR  STM_OPEN                  ; STRARG set, RESULT = i (1-based)
        LDA  RESULT+1
        JNZ  mid_hi
        LDA  RESULT
        JZ   mid_zero                  ; i = 0 -> treat as 1
        LDB  #1
        SUB                            ; SI = i - 1
        STA  SI
        JMP  mid_len
mid_zero: LDA #0
        STA  SI
        JMP  mid_len
mid_hi: LDB  #$80
        AND
        JZ   mid_big                   ; large positive start -> past end
        LDA  #0                        ; negative -> start 0
        STA  SI
        JMP  mid_len
mid_big: LDA  #SLEN
        STA  SI
mid_len: JSR SKIPSP                    ; optional length argument
        LDA  (P2)
        LDB  #','
        CMP
        JZ   mid_hasl
        LDA  #SLEN                      ; no length -> to end
        STA  SJ
        JMP  mid_cl
mid_hasl: INP2
        JSR  EXPR
        JSR  CLAMPN                     ; SJ = n
mid_cl: JSR  STM_CLOSE
        RTS

; SEVAL — evaluate a string expression at (P2): STERM { '+' STERM } -> STRACC.
SEVAL:  LDP1 #STRACC                   ; start empty
        LDA  #0
        STA  (P1)
        JSR  STERM                     ; first term -> STRTMP
        JSR  sev_app
sev_l:  JSR  SKIPSP
        LDA  (P2)
        LDB  #'+'
        CMP
        JNZ  sev_d
        INP2
        JSR  STERM
        JSR  sev_app
        JMP  sev_l
sev_d:  RTS
sev_app: LDA #<STRTMP                   ; STRACC += STRTMP
        STA  SPA
        LDA  #>STRTMP
        STA  SPA+1
        LDA  #<STRACC
        STA  SPD
        LDA  #>STRACC
        STA  SPD+1
        JSR  SAPP
        RTS

; EVALSTR — string comparison in a numeric context: SEVAL relop SEVAL -> RESULT
; (1/0). Reached from EVAL when SPEEK sees a string operand.
EVALSTR: JSR SEVAL                      ; LHS -> STRACC
        LDA  #<STRACC                   ; save LHS in STRCMP
        STA  SPA
        LDA  #>STRACC
        STA  SPA+1
        LDA  #<STRCMP
        STA  SPD
        LDA  #>STRCMP
        STA  SPD+1
        JSR  SMOVE
        JSR  SRELOP                     ; RELOP set; C=1 if no operator
        JC   es_err
        JSR  SEVAL                      ; RHS -> STRACC
        TPA2L                            ; SCMP walks P2; preserve the cursor
        PHA
        TPA2H
        PHA
        JSR  SCMP                        ; GEF,EQF from STRCMP vs STRACC
        PLA
        TAP2H
        PLA
        TAP2L
        JMP  ev_disp                     ; reuse numeric relop dispatch
es_err: JMP  SYNERR

; SRELOP — parse a relational operator at (P2) into RELOP (0..5); C=1 if none.
SRELOP: JSR  SKIPSP
        LDA  (P2)
        LDB  #'='
        CMP
        JZ   srl_eq
        LDA  (P2)
        LDB  #'<'
        CMP
        JZ   srl_lt
        LDA  (P2)
        LDB  #'>'
        CMP
        JZ   srl_gt
        SEC
        RTS
srl_eq: INP2
        LDA  #0
        STA  RELOP
        CLC
        RTS
srl_lt: INP2
        LDA  (P2)
        LDB  #'='
        CMP
        JZ   srl_le
        LDA  (P2)
        LDB  #'>'
        CMP
        JZ   srl_ne
        LDA  #1
        STA  RELOP
        CLC
        RTS
srl_le: INP2
        LDA  #3
        STA  RELOP
        CLC
        RTS
srl_ne: INP2
        LDA  #5
        STA  RELOP
        CLC
        RTS
srl_gt: INP2
        LDA  (P2)
        LDB  #'='
        CMP
        JZ   srl_ge
        LDA  #2
        STA  RELOP
        CLC
        RTS
srl_ge: INP2
        LDA  #4
        STA  RELOP
        CLC
        RTS

; SCMP — lexicographic compare STRCMP vs STRACC; sets GEF (>=), EQF (==).
SCMP:   LDP1 #STRCMP
        LDA  (P1)
        STA  SLENV                      ; La
        LDP2 #STRACC
        LDA  (P2)
        STA  SI                         ; Lb
        INP1
        INP2
        LDA  SLENV                       ; min(La,Lb) -> SJ
        LDB  SI
        CMP
        JC   sc_minb
        LDA  SLENV
        STA  SJ
        JMP  sc_lp
sc_minb: LDA SI
        STA  SJ
sc_lp:  LDA  SJ
        JZ   sc_leneq
        LDA  (P1)
        STA  CYTMP                        ; a
        LDA  (P2)
        STA  TMPC                         ; b
        LDA  CYTMP
        LDB  TMPC
        CMP                              ; Z if a==b, C if a>=b
        JZ   sc_next
        JC   sc_gt
        LDA  #0                           ; a < b
        STA  GEF
        STA  EQF
        RTS
sc_gt:  LDA  #1
        STA  GEF
        LDA  #0
        STA  EQF
        RTS
sc_next: INP1
        INP2
        LDA  SJ
        DEC
        STA  SJ
        JMP  sc_lp
sc_leneq: LDA SLENV                       ; equal prefix -> shorter is less
        LDB  SI
        CMP
        JZ   sc_eq
        JC   sc_gt2
        LDA  #0
        STA  GEF
        STA  EQF
        RTS
sc_gt2: LDA  #1
        STA  GEF
        LDA  #0
        STA  EQF
        RTS
sc_eq:  LDA  #1
        STA  GEF
        STA  EQF
        RTS

; FN_SARG — for LEN/ASC: consume '(' , read the string arg into STRARG, consume ')'.
FN_SARG: JSR SKIPSP
        LDA  (P2)
        LDB  #'('
        CMP
        JNZ  fn_err
        INP2
        LDA  #<STRARG
        STA  SPD
        LDA  #>STRARG
        STA  SPD+1
        JSR  SARG
        JSR  SKIPSP
        LDA  (P2)
        LDB  #')'
        CMP
        JNZ  fn_err
        INP2
        RTS
fn_err: JMP  SYNERR

; fa_len / fa_asc — numeric string functions, called from FACTOR.
fa_len: INP2
        JSR  FN_SARG
        LDP1 #STRARG
        LDA  (P1)
        STA  RESULT
        LDA  #0
        STA  RESULT+1
        RTS
fa_asc: INP2
        JSR  FN_SARG
        LDP1 #STRARG
        LDA  (P1)
        JZ   fa_asc0
        INP1
        LDA  (P1)
        STA  RESULT
        LDA  #0
        STA  RESULT+1
        RTS
fa_asc0: LDA #0
        STA  RESULT
        STA  RESULT+1
        RTS

; fa_val — VAL(string$): parse a signed decimal from the string arg -> RESULT.
; Stops at the first non-digit; a non-numeric string yields 0.
fa_val: INP2
        JSR  FN_SARG                    ; STRARG = [len][data]
        LDP1 #STRARG
        LDA  (P1)                       ; len -> counter, walk P1 past the data
        STA  SI
        INP1                            ; P1 -> data[0]
fv_nt:  LDA  SI
        JZ   fv_nt0
        INP1
        LDA  SI
        DEC
        STA  SI
        JMP  fv_nt
fv_nt0: LDA  #0
        STA  (P1)                       ; NUL-terminate the data so PARSEDEC stops
        TPA2L                           ; save the program cursor (repoint P2)
        STA  GTMP
        TPA2H
        STA  GTMP+1
        LDA  #<STRARG                    ; repoint P2 at STRARG's data (STRARG+1)
        LDB  #1
        ADD
        TAP2L
        LDA  #>STRARG
        JNC  fv_p2
        INC
fv_p2:  TAP2H
        JSR  SKIPSP
        LDA  #0
        STA  TMPC                        ; sign flag
        LDA  (P2)
        LDB  #'-'
        CMP
        JNZ  fv_ns
        LDA  #1
        STA  TMPC
        INP2
        JMP  fv_pd
fv_ns:  LDA  (P2)
        LDB  #'+'
        CMP
        JNZ  fv_pd
        INP2
fv_pd:  JSR  PARSEDEC                    ; LNUM = value
        LDA  TMPC
        JZ   fv_pos
        LDA  LNUM                         ; negate LNUM
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
        JNC  fv_pos
        LDA  LNUM+1
        INC
        STA  LNUM+1
fv_pos: LDA  GTMP                         ; restore the program cursor
        TAP2L
        LDA  GTMP+1
        TAP2H
        LDA  LNUM
        STA  RESULT
        LDA  LNUM+1
        STA  RESULT+1
        RTS

; fa_eof — EOF(n): 1 if the input channel is at end (or not open for input),
; else 0. The channel number is parsed and ignored (one channel).
fa_eof: INP2
        JSR  PARGET                       ; consume '(n)'
        LDA  FMODE
        LDB  #1
        CMP
        JNZ  fe_true                      ; not open for input -> EOF
        LDA  FLOOKC
        JZ   fe_false
fe_true: LDA #1
        STA  RESULT
        LDA  #0
        STA  RESULT+1
        RTS
fe_false: LDA #0
        STA  RESULT
        STA  RESULT+1
        RTS

;==============================================================================
; DATA FILES — one sequential channel over the BIOS byte streams (FOPEN/FGETB and
; FWOPEN/FPUTB/FCLOSE). Root files only; PRINT# writes one value + CR per record,
; INPUT# reads one CR-delimited record. Available in the disk / run-from-OS builds
; (the standalone whole-ROM build has no resident BIOS), like SAVE/LOAD.
;==============================================================================

; SETFNAME — evaluate the filename string expression at (P2) and resolve it into
; a target directory + leaf FNAME (via the BIOS FRESOLVE), so a data file can
; name a subdirectory ("/LOGS/A") as well as a bare root name. NUL-terminates
; STRACC's data in place and resolves that, avoiding a second buffer. Preserves
; the parse cursor (FRESOLVE clobbers P2).
SETFNAME: JSR SEVAL                   ; STRACC = filename ([len][data])
        TPA2L
        PHA
        TPA2H
        PHA
        LDP1 #STRACC                   ; NUL-terminate the data in place
        LDA  (P1)
        STA  TMPC                      ; len
        INP1                           ; -> data[0]
sfn_a:  LDA  TMPC
        JZ   sfn_z
        INP1
        LDA  TMPC
        DEC
        STA  TMPC
        JMP  sfn_a
sfn_z:  LDA  #0
        STA  (P1)                      ; NUL after the data
        LDP1 #STRACC                   ; FRESOLVE the path string (STRACC+1)
        INP1
        JSR  FRESOLVE                  ; -> DIRLBA + leaf FNAME
        PLA
        TAP2H
        PLA
        TAP2L
        RTS

; OPEN <name$> [FOR] OUTPUT|INPUT — open the one data channel.
DOOPEN: INP2                           ; skip OPEN token
        JSR  SETFNAME                  ; FNAME = the name
        JSR  SKIPSP
        LDA  (P2)                      ; an optional FOR is accepted
        LDB  #TOK_FOR
        CMP
        JNZ  dop_mode
        INP2
        JSR  SKIPSP
dop_mode: LDA (P2)
        LDB  #TOK_OUTPUT
        CMP
        JZ   dop_out
        LDA  (P2)
        LDB  #TOK_INPUT
        CMP
        JZ   dop_in
        JMP  SYNERR
dop_out: INP2
        JSR  FWOPEN                     ; write stream at the free pointer
        LDA  #2
        STA  FMODE
        RTS
dop_in: INP2
        LDP1 #PBUF                      ; read stream needs a 512-byte buffer
        JSR  FOPEN
        JC   dop_nf
        LDA  #1
        STA  FMODE
        JSR  FPRIME                     ; prime the EOF lookahead
        RTS
dop_nf: LDA  #0
        STA  FMODE
        LDP1 #MNOFILE
        JSR  PUTS
        RTS

; CLOSE — commit a write channel (FCLOSE) / drop a read channel.
DOCLOSE: INP2
        LDA  FMODE
        LDB  #2
        CMP
        JNZ  dcl_ni                     ; only a write channel needs committing
        JSR  FCLOSE
dcl_ni: LDA  #0
        STA  FMODE
        RTS

; PRINT# <expr> — write one value (its text form) plus a CR record terminator.
; Entered from DOPRINT with P2 at the '#'.
DOPRINTF: LDA FMODE
        LDB  #2
        CMP
        JNZ  dpf_err                    ; not open for output
        INP2                            ; consume '#'
        LDA  #1
        STA  OUTFILE
        JSR  SKIPSP
        LDA  (P2)
        JZ   dpf_cr                     ; bare PRINT# -> a blank record
        JSR  SPEEK
        LDA  MATCHF
        JNZ  dpf_str
        JSR  EVAL                       ; numeric value -> decimal text (via PUTCH)
        LDA  RESULT
        STA  LNUM
        LDA  RESULT+1
        STA  LNUM+1
        JSR  PRDEC
        JMP  dpf_cr
dpf_str: JSR SEVAL                       ; string value (via PUTCH)
        JSR  SPUT
dpf_cr: LDA  #$0D                        ; record terminator
        JSR  FPUTB
        LDA  #0
        STA  OUTFILE
        RTS
dpf_err: JMP  SYNERR

; INPUT# <var> — read one CR-delimited record into a numeric or string variable.
; Entered from DOINPUT with P2 at the '#'.
DOINPUTF: LDA FMODE
        LDB  #1
        CMP
        JNZ  dif_err                    ; not open for input
        INP2                            ; consume '#'
        JSR  SKIPSP
        JSR  SPEEK
        LDA  MATCHF
        JNZ  dif_str
        JSR  VARGET                     ; numeric variable -> P1 = &value
        LDA  MATCHF
        JZ   dif_err
        TPA1L
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        TPA2L                           ; save cursor (FREADREC clobbers P2)
        STA  GTMP
        TPA2H
        STA  GTMP+1
        JSR  FREADREC                   ; STRACC = record text (NUL-terminated)
        LDP2 #STRACC                    ; parse it as a decimal number
        INP2
        JSR  SKIPSP
        JSR  PARSEDEC                   ; LNUM = value
        LDA  GTMP
        TAP2L
        LDA  GTMP+1
        TAP2H
        LDA  SAVE1
        TAP1L
        LDA  SAVE1+1
        TAP1H
        LDA  LNUM
        STA  (P1)
        INP1
        LDA  LNUM+1
        STA  (P1)
        RTS
dif_str: JSR SVARGET                     ; string variable -> P1 = &entry
        LDA  MATCHF
        JZ   dif_err
        TPA1L
        STA  SAVE1
        TPA1H
        STA  SAVE1+1
        TPA2L                            ; save cursor (FREADREC clobbers P2)
        STA  GTMP
        TPA2H
        STA  GTMP+1
        JSR  FREADREC                    ; STRACC = record
        LDA  #<STRACC
        STA  SPA
        LDA  #>STRACC
        STA  SPA+1
        LDA  SAVE1
        LDB  #NAMLEN
        ADD
        STA  SPD
        LDA  SAVE1+1
        JNC  dif_s1
        INC
dif_s1: STA  SPD+1
        JSR  SMOVE
        LDA  GTMP                        ; restore the parse cursor
        TAP2L
        LDA  GTMP+1
        TAP2H
        RTS
dif_err: JMP  SYNERR

; FPRIME — prime the 1-byte read-ahead when a channel is opened for input, so
; EOF() can report end-of-file BEFORE the read that would hit it.
FPRIME: LDA  #0
        STA  FLOOKC
        JSR  FGETB
        JC   fpr_eof
        STA  FLOOK
        RTS
fpr_eof: LDA #1
        STA  FLOOKC
        RTS

; GNB — get next byte from the input stream via the lookahead: return FLOOK and
; refill it from FGETB. A = byte, C=1 at EOF. FLOOKC records whether the byte now
; sitting in FLOOK is really end-of-file, which is exactly what EOF() reports.
GNB:    LDA  FLOOKC
        JNZ  gnb_eof
        LDA  FLOOK                       ; byte to deliver
        STA  TMPC
        JSR  FGETB                       ; refill lookahead
        JC   gnb_reof
        STA  FLOOK
        LDA  TMPC
        CLC
        RTS
gnb_reof: LDA #1
        STA  FLOOKC
        LDA  TMPC
        CLC
        RTS
gnb_eof: SEC
        RTS

; FREADREC — read the next CR-delimited record from the open read stream into
; STRACC (len + data, capped at SLEN, and NUL-terminated after the data so the
; numeric path can PARSEDEC it). Uses P2 as the walker (FGETB clobbers P1, not P2).
FREADREC: LDP2 #STRACC
        INP2                            ; data pointer
        LDA  #0
        STA  SI
frr_l:  JSR  GNB                         ; A = byte, C=1 at EOF (via lookahead)
        JC   frr_end
        STA  TMPC
        LDB  #$0D
        CMP
        JZ   frr_end                     ; end of this record
        LDA  SI
        LDB  #SLEN
        CMP
        JC   frr_l                       ; record too long -> discard the overflow
        LDA  TMPC
        STA  (P2)
        INP2
        LDA  SI
        INC
        STA  SI
        JMP  frr_l
frr_end: LDA #0                          ; NUL-terminate after the data
        STA  (P2)
        LDP2 #STRACC
        LDA  SI
        STA  (P2)
        RTS

; ---------------------------------------------------------------------------
; CHECKLINE — structural syntax check of the just-crunched line in LBUF, run at
; entry so a malformed line is rejected immediately (with the program unchanged)
; instead of only blowing up later at RUN. Skips a leading line number, then for
; each ':'-separated statement validates: a legal statement leader, balanced
; parentheses, and a terminated string literal. A REM ends checking (its tail is
; a free-form comment). Forward references (GOTO/GOSUB to a not-yet-entered line)
; are deliberately NOT checked here — those stay legal and are caught at RUN.
; Prints ?SYNTAX ERROR and returns C=1 on failure; C=0 (silent) on success.
CHECKLINE:
        LDP2 #LBUF
        JSR  SKIPSP
ckl_dg: LDA  (P2)                   ; skip a leading decimal line number, if any
        LDB  #'0'
        CMP                         ; C=1 if A >= '0'
        JNC  ckl_st
        LDB  #$3A                   ; '9' + 1
        CMP                         ; C=1 if A >= ':' (i.e. past '9')
        JC   ckl_st
        INP2                        ; it's a digit -> consume
        JMP  ckl_dg
ckl_st: LDA  #0                     ; start of a statement: parens balance here
        STA  CKDEP
        JSR  SKIPSP
        JSR  CKLEAD                 ; legal statement leader?
        JC   ckl_bad
        LDA  CKREM                  ; REM -> rest of line is a comment, accept
        JNZ  ckl_ok
ckl_lp: LDA  (P2)
        JZ   ckl_eol
        LDB  #'"'
        CMP
        JZ   ckl_str
        LDB  #'('
        CMP
        JZ   ckl_op
        LDB  #')'
        CMP
        JZ   ckl_cp
        LDB  #':'
        CMP
        JZ   ckl_col
        INP2
        JMP  ckl_lp
ckl_op: LDA  CKDEP                  ; '(' -> deeper
        INC
        STA  CKDEP
        INP2
        JMP  ckl_lp
ckl_cp: LDA  CKDEP                  ; ')' with no matching '(' -> error
        JZ   ckl_bad
        DEC
        STA  CKDEP
        INP2
        JMP  ckl_lp
ckl_col: LDA CKDEP                  ; ':' with a paren still open -> error
        JNZ  ckl_bad
        INP2
        JMP  ckl_st                 ; next statement: re-check its leader
ckl_str: INP2                       ; opening quote
cks_l:  LDA  (P2)
        JZ   ckl_bad                ; ran off the end -> unterminated string
        LDB  #'"'
        CMP
        JZ   cks_e
        INP2
        JMP  cks_l
cks_e:  INP2
        JMP  ckl_lp
ckl_eol: LDA CKDEP                  ; end of line: any '(' left open -> error
        JNZ  ckl_bad
ckl_ok: CLC
        RTS
ckl_bad: LDP1 #MSYN
        JSR  PUTS
        SEC
        RTS

; CKLEAD — is the token/char at (P2) a legal way to START a statement? A letter
; begins an implicit LET; the statement keywords are all legal; the "operator"
; keywords THEN/TO/STEP and the function keywords ABS/RND/PEEK are not. Anything
; else (a digit, an operator, a ')') is illegal. Sets CKREM=1 for REM so the
; caller stops scanning. C=1 if the leader is illegal; P2 is left unchanged.
CKLEAD: LDA  #0
        STA  CKREM
        LDA  (P2)
        JNZ  ckd_1
        CLC                         ; empty statement (end of line / after ':')
        RTS
ckd_1:  LDB  #TOK_REM
        CMP
        JZ   ckd_rem
        LDA  (P2)                   ; is it a keyword token (bit 7 set)?
        LDB  #$80
        AND
        JZ   ckd_alpha
        LDA  (P2)                   ; a token: reject the non-statement ones
        LDB  #TOK_THEN
        CMP
        JZ   ckd_bad
        LDB  #TOK_TO
        CMP
        JZ   ckd_bad
        LDB  #TOK_STEP
        CMP
        JZ   ckd_bad
        LDB  #TOK_ABS
        CMP
        JZ   ckd_bad
        LDB  #TOK_RND
        CMP
        JZ   ckd_bad
        LDB  #TOK_PEEK
        CMP
        JZ   ckd_bad
        LDB  #TOK_CHRS
        CMP
        JZ   ckd_bad
        LDB  #TOK_LEFTS
        CMP
        JZ   ckd_bad
        LDB  #TOK_RIGHTS
        CMP
        JZ   ckd_bad
        LDB  #TOK_MIDS
        CMP
        JZ   ckd_bad
        LDB  #TOK_LEN
        CMP
        JZ   ckd_bad
        LDB  #TOK_ASC
        CMP
        JZ   ckd_bad
        LDB  #TOK_STRS
        CMP
        JZ   ckd_bad
        LDB  #TOK_VAL
        CMP
        JZ   ckd_bad
        LDB  #TOK_EOF
        CMP
        JZ   ckd_bad
        LDB  #TOK_OUTPUT
        CMP
        JZ   ckd_bad
        CLC                         ; a statement keyword -> ok
        RTS
ckd_rem: LDA  #1
        STA  CKREM
        CLC
        RTS
ckd_alpha: LDA (P2)                 ; not a token: must be a letter (implicit LET)
        JSR  UPCHAR
        LDB  #'A'
        CMP                         ; C=1 if A >= 'A'
        JNC  ckd_bad
        LDB  #$5B                   ; 'Z' + 1
        CMP                         ; C=1 if A > 'Z'
        JC   ckd_bad
        CLC
        RTS
ckd_bad: SEC
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
mk_hit: LDA  (P1)                   ; char right after the matched keyword
        JSR  ISALNUM                ; if a letter/digit, this is really a longer
        LDA  MATCHF                 ;   identifier (e.g. TOTAL, FORK) -> not a kw
        JNZ  mk_no
        LDA  TMPC
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
        .ascii "BYE"
        .byte $95
        .ascii "HELP"
        .byte $96
        .ascii "SAVE"
        .byte $97
        .ascii "LOAD"
        .byte $98
        .ascii "CHR"
        .byte $24,$99               ; '$' then token: CHR$
        .ascii "LEFT"
        .byte $24,$9A               ; LEFT$
        .ascii "RIGHT"
        .byte $24,$9B               ; RIGHT$
        .ascii "MID"
        .byte $24,$9C               ; MID$
        .ascii "LEN"
        .byte $9D
        .ascii "ASC"
        .byte $9E
        .ascii "OPEN"
        .byte $9F
        .ascii "CLOSE"
        .byte $A0
        .ascii "OUTPUT"
        .byte $A1
        .ascii "STR"
        .byte $24,$A2               ; '$' then token: STR$
        .ascii "VAL"
        .byte $A3
        .ascii "EOF"
        .byte $A4
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

; PUTCH — emit A to the current sink: the open data file when OUTFILE is set
; (PRINT#), otherwise the console. Lets PRDEC/SPUT serve both PRINT and PRINT#.
PUTCH:  PHA                          ; preserve the char (and TMPC, used by SPUT)
        LDA  STRSINK                 ; STR$ capture takes priority over the file
        JNZ  pch_str
        LDA  OUTFILE
        JZ   pch_con
        TPA1L                        ; FPUTB clobbers P1; PRDECU/SPUT walk it
        STA  SAVE2
        TPA1H
        STA  SAVE2+1
        PLA
        JSR  FPUTB
        LDA  SAVE2
        TAP1L
        LDA  SAVE2+1
        TAP1H
        RTS
pch_con: PLA
        JSR  PUTC
        RTS
pch_str: TPA1L                        ; string sink: append A to (STRSP), inc STRSN
        STA  SAVE2
        TPA1H
        STA  SAVE2+1
        LDA  STRSP
        TAP1L
        LDA  STRSP+1
        TAP1H
        PLA
        STA  (P1)
        LDA  STRSP
        LDB  #1
        ADD
        STA  STRSP
        JNC  pst_1
        LDA  STRSP+1
        INC
        STA  STRSP+1
pst_1:  LDA  STRSN
        INC
        STA  STRSN
        LDA  SAVE2
        TAP1L
        LDA  SAVE2+1
        TAP1H
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
MHELP:  .byte CR,LF
        .ascii "STATEMENTS: PRINT LET IF/THEN FOR/TO/STEP NEXT"
        .byte CR,LF
        .ascii "  GOTO GOSUB RETURN INPUT POKE REM END"
        .byte CR,LF
        .ascii "FILES: OPEN name OUTPUT|INPUT : PRINT# : INPUT# : CLOSE : EOF(n)"
        .byte CR,LF
        .ascii "COMMANDS: RUN LIST NEW SAVE LOAD HELP BYE"
        .byte CR,LF
        .ascii "FUNCTIONS: ABS(x) RND(n) PEEK(a)"
        .byte CR,LF
        .ascii "  LEN ASC CHR$ LEFT$ RIGHT$ MID$ STR$ VAL"
        .byte CR,LF
        .ascii "STRINGS: A$ B$ (assign, + concat, compare)"
        .byte CR,LF
        .ascii "OPERATORS: + - * / %  = <> < > <= >="
        .byte CR,LF,0
MOK:    .ascii "Ok"
        .byte CR,LF,0
MWHAT:  .byte $3F,CR,LF,0
MSAVED: .ascii "Saved"
        .byte CR,LF,0
MLOADED:.ascii "Loaded"
        .byte CR,LF,0
MFSERR: .ascii "?Save failed"
        .byte CR,LF,0
MNOFILE:.ascii "?No file"
        .byte CR,LF,0
MSYN:   .ascii "?SYNTAX ERROR"
        .byte CR,LF,0
MUNDEF: .ascii "?UNDEF'D LINE"
        .byte CR,LF,0
MRG:    .ascii "?RETURN WITHOUT GOSUB"
        .byte CR,LF,0
