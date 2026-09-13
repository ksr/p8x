;==============================================================================
; P8X BASIC -- interpreter for the P8X computer, Tier A edition (2026-09-12)
;
; Integer BASIC with strings, data files and the GL graphics language. This is
; the from-scratch rewrite for the Tier A ISA. It is a DROP-IN for the original:
; same tokens (the token values are the on-disk .BAS format), same KWTAB text,
; same messages, HELP and prompts, same GL byte streams, same -D build knobs.
; What changed is the machinery:
;
;   * Statements and functions dispatch through TABLES indexed by the token
;     (STMTTAB / FACTAB): `LDW CUR,(P1+0) / LPW1 CUR / JSR (P1)` replaces a
;     chain of thirty compares. CHECKLINE derives "legal statement leader"
;     from the same table, so the two can never disagree.
;   * All 16-bit arithmetic is on word variables with ADDW/SUBW/CMPW/INCW/
;     DECW/XORW; the recursive-descent evaluator pushes the running value
;     with PHW and pops it with PLW. Signed comparison is one CMPW + BLT.
;   * A comparison produces a relation byte (LT=1 EQ=2 GT=4) and the operator
;     a mask; the result is `rel AND mask <> 0`. Numeric and string compares
;     share it.
;   * Records are addressed with (Pn+d): a variable's value is (P1+6) of its
;     table entry, a FOR frame's fields are (P1+1..8), a GOSUB frame's (P1+0/2),
;     a GL verb's opcode/meta (P1+0/1), a program line's number (P1+0).
;   * Name compares (variables, string variables) are unrolled against the
;     fixed NMBUF, so the table walk never needs a second pointer or a stack
;     save; the program-line search stops as soon as the sorted list passes
;     the target.
;   * The tokenizer only tries the keyword table on a letter.
;
; Build targets differ only in their -D symbols (see basic/README.md):
;   BASORG  code origin   ($0000 standalone, $2000 disk boot, $6300 in the TPA)
;   BASRAM  data base      ($8000 standalone, $A000 disk boot, $C500 for the TPA)
;   PBUF    rebuild scratch ($C000 default; the TPA build moves it to $E000)
;   MONITOR where BYE returns ($2000 = the OS for the TPA build)
;
; Program storage (PROG): a sorted sequence of records
;     [num-lo][num-hi][text bytes ...][00]
; terminated by a 00,00 line-number marker (line 0 is invalid in BASIC).
; Edits rebuild into the scratch buffer (PBUF) and copy back.
;
; Conventions: P2 is the PARSE CURSOR (statement text); every routine that
; borrows P2 saves it. P1 is scratch. P3 is the stack. Word ops clobber A.
; Numbers are signed 16-bit; division and modulus are UNSIGNED (as before).
;==============================================================================

BASORG = $0000          ; code origin (override with -D BASORG=...)
BASRAM = $8000          ; data base   (override with -D BASRAM=...)

ACIAS  = $FF04
ACIAD  = $FF05
GLDATAR = $FF50          ; GL command FIFO: one byte at a time
GLSTATR = $FF51          ; bit7 FIFO full, bit6 busy, bit0 read-back byte ready
GLRBR   = $FF52          ; read-back FIFO pop
GLIDR   = $FF54          ; reads 'G' when the GL engine is fitted
GTSUSP  = $60A7          ; glass TTY suspend flag: 1 = BASIC owns the GL screen
CR     = $0D
LF     = $0A
BS     = $08

; BIOS filesystem calls (monitor ROM at $0100).
FLOADAT = $013F          ; bulk-read FLEN bytes from LBA into (P1)
FFIND   = $0118          ; find file FNAME in the resolved dir -> LBA + FLEN; C=1 if not found
FCREATE = $011B          ; create file FNAME (FSRC/FLEN) in the resolved dir; C=1 on error
FRESOLVE= $0133          ; resolve NUL-terminated path (P1) -> dir extent + leaf FNAME; C=1 bad path
SYS_GETCWD = $2003       ; OS: copy the CWD path string -> (P1), incl NUL (clobbers P2)
FOPEN   = $0124          ; open file FNAME for reading (P1=512-byte buf); C=1 missing
FGETB   = $0127          ; next byte -> A; C=1 at end of file. Clobbers P1 (and P2 on a refill)
FWOPEN  = $012A          ; open a write stream at the free pointer
FPUTB   = $012D          ; append byte A to the write stream. Clobbers P1
FCLOSE  = $0130          ; flush + register file FNAME (len = bytes written); C=1 if full
FNAME   = $604A          ; 12-byte filename (space-padded)
FSRC    = $6056          ; FCREATE source address
FLEN    = $6058          ; file length in bytes (24-bit)

MONITOR = $0000          ; reset vector -- BYE returns here
CONIN   = $0100          ; BIOS: wait for a key -> A
CONOUT  = $0103          ; BIOS: A -> console (expands a bare LF to CR LF)

; ---- variables (one page at BASRAM) ----
LBUF   = BASRAM+$00          ; input line buffer (96)
; word variables
RESULT = BASRAM+$60          ; expression result
NUM1   = BASRAM+$62          ; 16-bit math operands / results
NUM2   = BASRAM+$64
REM    = BASRAM+$66          ; division remainder
ACC    = BASRAM+$68          ; multiply accumulator
LNUM   = BASRAM+$6A          ; entered / printed line number, number being printed
RNUM   = BASRAM+$6C          ; record line number during a scan
TSRC   = BASRAM+$6E          ; address of the entered line's text (in LBUF)
SAVE1  = BASRAM+$70          ; pointer save slots
SAVE2  = BASRAM+$72
GTMP   = BASRAM+$74
RP     = BASRAM+$76
WP     = BASRAM+$78          ; crunch write pointer
CURLINE= BASRAM+$7A          ; RUN: pointer to the current program line record
BRANCHN= BASRAM+$7C          ; pending GOTO target line number
JUMPADDR= BASRAM+$7E         ; RUN: JUMPF 1 = next line record, 2 = resume text pointer
LFT    = BASRAM+$80          ; comparison left operand
FLIM   = BASRAM+$82          ; FOR/NEXT scratch: limit
FSTEP  = BASRAM+$84          ;   step
FLR    = BASRAM+$86          ;   loop-back line record
FTP    = BASRAM+$88          ;   loop-back text pointer
FFP    = BASRAM+$8A          ; pointer to the top FOR frame
SPA    = BASRAM+$8C          ; string source pointer
SPD    = BASRAM+$8E          ; string destination pointer
STRSP  = BASRAM+$90          ; string-sink append pointer (STR$)
SEED   = BASRAM+$92          ; RND state
POKEA  = BASRAM+$94          ; POKE address
SPSAV  = BASRAM+$96          ; stack pointer to return to (the caller's under the OS)
CUR    = BASRAM+$98          ; dispatch vector / scan cursor
IMX    = BASRAM+$9A          ; IMAGE: left edge
IMYC   = BASRAM+$9C          ;   current row y
IMW    = BASRAM+$9E          ;   width
IMH    = BASRAM+$A0          ;   rows remaining
IMCX   = BASRAM+$A2          ;   payload bytes remaining in the row
BXS    = BASRAM+$A4          ; BOX/CIRCLE/GTEXT argument shadow: 4 int16 (8)
; byte variables
DIG    = BASRAM+$B0
LZ     = BASRAM+$B1          ; PRDECU: still suppressing leading zeros
PCNT   = BASRAM+$B2
CYTMP  = BASRAM+$B3
INSF   = BASRAM+$B4          ; EDIT: 1 once the new line has been emitted
TXTMT  = BASRAM+$B5          ; EDIT: 1 if the entered line has empty text (delete)
TOKEN  = BASRAM+$B6          ; token matched by MATCHKW
MATCHF = BASRAM+$B7          ; 1 if the last match / parse succeeded
TMPC   = BASRAM+$B8          ; byte scratch
TOKW   = BASRAM+$B9          ; token being uncrunched
MCNT   = BASRAM+$BA          ; mul/div bit counter
BRANCHF= BASRAM+$BB          ; RUN: 1 if a GOTO target is pending
ENDF   = BASRAM+$BC          ; RUN: 1 to stop the program
RELM   = BASRAM+$BD          ; comparison operator as a relation mask (LT=1 EQ=2 GT=4)
REL    = BASRAM+$BE          ; the relation of the last compare (LT / EQ / GT)
FNDF   = BASRAM+$BF          ; FINDLINE: 1 if the line was found
GSP    = BASRAM+$C0          ; GOSUB stack depth
CKDEP  = BASRAM+$C1          ; CHECKLINE: parenthesis depth
CKREM  = BASRAM+$C2          ; CHECKLINE: 1 once a REM is seen
JUMPF  = BASRAM+$C3          ; RUN: 1 = CURLINE := JUMPADDR, 2 = resume at text JUMPADDR
FSP    = BASRAM+$C4          ; FOR stack depth
FORIDX = BASRAM+$C5          ; FOR: loop variable's table index
VARCNT = BASRAM+$C6          ; number of variables defined (0..NVARS)
VARIDX = BASRAM+$C7          ; VARGET result: the variable's table index
SVARCNT= BASRAM+$C8          ; number of string variables defined (0..NSVARS)
SVIDX  = BASRAM+$C9          ; SVARFIND result index
SLENV  = BASRAM+$CA          ; string length scratch
SI     = BASRAM+$CB          ; string index / count scratch
SJ     = BASRAM+$CC          ; string count scratch
FMODE  = BASRAM+$CD          ; data file: 0 closed, 1 open for input, 2 for output
OUTFILE= BASRAM+$CE          ; 1 while PRINT# emits to the data file (via PUTCH)
STRSINK= BASRAM+$CF          ; 1 while PUTCH captures into a string buffer (STR$)
STRSN  = BASRAM+$D0          ; string-sink char count
FLOOK  = BASRAM+$D1          ; input-file 1-byte lookahead
FLOOKC = BASRAM+$D2          ; 1 if the lookahead position is end-of-file
RUNNING= BASRAM+$D3          ; 1 while a program is RUNning (else immediate mode)
PRMSH  = BASRAM+$D4          ; shadow of the GL PRMFIL flag (BOX/CIRCLE restore it)
RGBH   = BASRAM+$D5          ; RGB(): the packed high byte across the g/b arguments
GLN    = BASRAM+$D6          ; GL: bytes / vertices left to send
GLTMP  = BASRAM+$D7          ; GLPUT's byte
GLOP   = BASRAM+$D8          ; GL verb: opcode
GLMETA = BASRAM+$D9          ;   meta byte {var<<7 | bcnt<<4 | word-arity}
GLCNT  = BASRAM+$DA          ;   loop count
GLDIM  = BASRAM+$DB          ;   POLY*: words per vertex (2 or 3)
GLFST  = BASRAM+$DC          ;   1 until the first argument is parsed
NMBUF  = BASRAM+$E0          ; parsed variable name, NAMLEN chars, upcased, space-padded (6)
; tables
NAMLEN = 6                   ; significant variable-name length
NVARS  = 32                  ; numeric variables: entry = name[6] + value[2]
VARTAB = BASRAM+$100         ; NVARS x 8 = 256 bytes (one page)
; a string value is [len byte][data...], length capped at SLEN. The four work
; buffers are 64 bytes apart; a value uses at most 33, so each buffer's tail is
; free -- the GOSUB and FOR stacks live there.
SLEN   = 32                  ; maximum stored string length
SVENT  = 40                  ; string-var entry: NAMLEN name + 1 len + 32 data + pad
NSVARS = 16                  ; string-variable table capacity
STRACC = BASRAM+$200         ; SEVAL result accumulator
STRACCD= BASRAM+$201         ;   its data
STRTMP = BASRAM+$240         ; the string term being produced
STRTMPD= BASRAM+$241
STRARG = BASRAM+$280         ; a string function's string argument
STRCMP = BASRAM+$2C0         ; saved left operand of a string comparison
GSTK   = BASRAM+$268         ; GOSUB return stack: GSMAX x 4 (line record, text ptr)
GSMAX  = 3
FSTK   = BASRAM+$2E4         ; FOR frames: FSMAX x 9 (var index, limit, step, LR, TP)
FSMAX  = 3
SVARTAB= BASRAM+$300         ; NSVARS x SVENT = 640 bytes
PROG   = BASRAM+$580         ; program storage
PBUF   = $C000               ; rebuild scratch buffer
APBUF  = PBUF+128            ; absolute-path scratch (APATH; paths are <= 47 chars)
STKTOP = $FEFF

; keyword tokens (>= $80; the values are the .BAS file format -- append only)
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
TOK_CHRS  = $99          ; CHR$
TOK_LEFTS = $9A          ; LEFT$
TOK_RIGHTS= $9B          ; RIGHT$
TOK_MIDS  = $9C          ; MID$
TOK_LEN   = $9D
TOK_ASC   = $9E
TOK_OPEN  = $9F
TOK_CLOSE = $A0
TOK_OUTPUT= $A1
TOK_STRS  = $A2          ; STR$
TOK_VAL   = $A3
TOK_EOF   = $A4
TOK_LINE  = $A5
TOK_COLOR = $A6
TOK_BOX   = $A7
TOK_FILL  = $A8
TOK_NOFILL= $A9
TOK_CLS   = $AA
TOK_PIXELW= $AB
TOK_CIRCLE= $AC
TOK_PIXELR= $AE          ; ($AD was PALETTE: unassigned, kept so old files still load)
TOK_GTEXT = $AF
TOK_RGB   = $B1          ; ($B0 was SCREEN: unassigned)
TOK_IMAGE = $B2
TOK_GL    = $B3
TOK_GLRD  = $FB          ; GLRD: a bare factor; $B4.. are the GL verbs (glvtab.inc)
NTOK      = 52           ; tokens $80..$B3 have STMTTAB / FACTAB entries

; relation bits (REL) and operator masks (RELM)
R_LT   = 1
R_EQ   = 2
R_GT   = 4

;==============================================================================
        .org BASORG
; Under P8X/OS we were reached with `JSR (P1)` and the shell expects an RTS
; back, so we ADOPT the caller's stack and remember where it was (SPSAV); BYE
; and every error unwind to it. Standalone / disk-boot there is no caller.
        LDA  #>MONITOR
        JZ   bs_own
        TPA3L
        STA  SPSAV
        TPA3H
        STA  SPSAV+1
        JMP  bs_go
bs_own: LDP3 #STKTOP
        LDW  SPSAV,#STKTOP
bs_go:  LDA  #$03            ; ACIA master reset
        STA  ACIAS
        LDA  #$15            ; /16 clock, 8N1
        STA  ACIAS
        JSR  NEWPROG
        LDA  #0
        STA  FMODE           ; no data file open
        STA  OUTFILE
        STA  STRSINK
        STA  PRMSH           ; the card powers up outline
        LDW  SEED,#44257
        LDA  GLIDR           ; a GL engine? establish BASIC's full-screen window
        LDB  #'G'            ;   (the raw port powers up DEGENERATE) and claim
        CMP                  ;   the screen from the glass TTY
        JNZ  bnr_ng
        JSR  glwin
        LDA  #1
        STA  GTSUSP
        LDA  #$B0            ; PROJCT 0: 2D first; TEXT strokes live at z=0,
        JSR  GLPUT           ;   which the native camera would near-clip
        LDA  #0
        JSR  GLPUT
        JSR  GLPUT
bnr_ng: LDP1 #BANNER
        JSR  PUTS

; ---------------- REPL -------------------------------------------------------
REPL:   LDA  #0
        STA  RUNNING         ; at the prompt: not running a program
        JSR  GETLINE         ; line -> LBUF
        JSR  CRUNCH          ; keywords -> tokens, in place
        JSR  CHECKLINE       ; reject a malformed line at entry (C=1 reported)
        JC   REPL
        LDP2 #LBUF
        JSR  SKIPSP
        LDA  (P2)
        JZ   REPL            ; blank line
        JSR  ISDIGIT
        JC   DOLINE          ; leading digit -> a numbered line
        LDA  #0              ; a fresh statement line: no pending end / branch
        STA  ENDF
        STA  BRANCHF
        STA  JUMPF
        JSR  STMTLINE        ; immediate statement(s)
        JMP  REPL

; ISDIGIT - C=1 if A is '0'..'9'. A preserved.
ISDIGIT:LDB  #'0'
        CMP
        JNC  isd_no
        LDB  #$3A
        CMP
        JC   isd_no
        SEC
        RTS
isd_no: CLC
        RTS

; STMTLINE - execute ':'-separated statements until the end of the line or a
;   pending branch / jump / end. Used by RUN and immediate mode.
STMTLINE:
        JSR  STMT
        LDA  ENDF
        JNZ  sl_d
        LDA  BRANCHF
        JNZ  sl_d
        LDA  JUMPF
        JNZ  sl_d
        JSR  SKIPSP
        LDA  (P2)
        JZ   sl_d            ; end of line
        LDB  #':'
        CMP
        JNZ  SYNERR          ; leftover text (an unsupported operator, say)
        INP2
        JMP  STMTLINE
sl_d:   RTS

; STMT - execute the statement at (P2), P2 left after it. A statement keyword
;   dispatches through STMTTAB; a GL verb token goes to DOGLV with its index; a
;   letter is an implicit LET; anything else prints "?".
STMT:   JSR  SKIPSP
        LDA  (P2)
        JZ   st_rts          ; empty statement
        LDB  #GLV0
        SUB                  ; A = token - GLV0
        JNC  st_low
        LDB  #GLVN
        CMP
        JC   st_what         ; past the verb block (GLRD, unassigned)
        JMP  DOGLV           ; verb index in A
st_low: LDA  (P2)
        LDB  #$80
        SUB
        JNC  st_text         ; not a token
        SHL                  ; P1 = &STMTTAB[token]
        LDB  #<STMTTAB
        ADD
        TAP1L
        LDA  #0
        ROL
        LDB  #>STMTTAB
        ADD
        TAP1H
        LDW  CUR,(P1+0)
        LPW1 CUR
        JSR  (P1)
st_rts: RTS
st_text:LDA  (P2)
        JSR  ISLETTER
        JC   DOLET           ; bare variable -> implicit LET
st_what:LDP1 #MWHAT          ; "?"
        JMP  PUTS

; ISLETTER - C=1 if A (either case) is a letter. A and every variable preserved
;   (MATCHKW relies on TMPC surviving this).
ISLETTER:
        LDB  #'a'
        CMP
        JNC  isl_up          ; below 'a': try the upper-case range
        LDB  #$7B            ; 'z'+1
        CMP
        JNC  isl_yes
        CLC
        RTS
isl_up: LDB  #'A'
        CMP
        JNC  isl_no
        LDB  #$5B            ; 'Z'+1
        CMP
        JNC  isl_yes
isl_no: CLC
        RTS
isl_yes:SEC
        RTS

; Statement handlers by token ($80..$B3). A function / modifier keyword at the
; head of a statement is st_what ("?"), which CKLEAD also reads as "illegal".
STMTTAB:.word DOPRINT,DOLET,DOIF,st_what              ; $80 PRINT LET IF THEN
        .word DOFOR,st_what,DONEXT,DOGOTO             ; $84 FOR TO NEXT GOTO
        .word DOGOSUB,DORET,DOINPUT,DOREM             ; $88 GOSUB RETURN INPUT REM
        .word DOEND,DORUN,st_list,st_new              ; $8C END RUN LIST NEW
        .word st_what,st_what,st_what,DOPOKE          ; $90 ABS RND PEEK POKE
        .word st_what,DOBYE,st_help,st_save           ; $94 STEP BYE HELP SAVE
        .word st_load,st_what,st_what,st_what         ; $98 LOAD CHR$ LEFT$ RIGHT$
        .word st_what,st_what,st_what,DOOPEN          ; $9C MID$ LEN ASC OPEN
        .word DOCLOSE,st_what,st_what,st_what         ; $A0 CLOSE OUTPUT STR$ VAL
        .word st_what,DOGLINE,DOCOLOR,DOBOX           ; $A4 EOF LINE COLOR BOX
        .word st_what,st_what,DOCLS,DOPIXW            ; $A8 FILL NOFILL CLS PIXELW
        .word DOCIRC,st_what,st_what,DOGTEXT          ; $AC CIRCLE (PALETTE) PIXELR GTEXT
        .word st_what,st_what,DOIMAGE,DOGL            ; $B0 (SCREEN) RGB IMAGE GL

st_list:INP2                 ; consume the token so STMTLINE sees the line end
        JSR  LIST
        JMP  st_ok
st_new: INP2
        JSR  NEWPROG
st_ok:  LDP1 #MOK
        JMP  PUTS
st_help:INP2
        LDP1 #MHELP
        JMP  PUTS

; BYE - leave BASIC. Under P8X/OS: back to the shell that ran us, stack
; restored, CWD and redirection intact. Disk boot / standalone: the reset vector.
DOBYE:  LDA  #>MONITOR
        JZ   by_rst
        LPW3 SPSAV
        RTS
by_rst: JMP  MONITOR

; SYNERR - abort the current statement to the prompt: unwind the stack to our
;   entry SP, cancel any output redirection, report (with the line number when
;   a program is running).
SYNERR: LPW3 SPSAV
        LDA  #0
        STA  OUTFILE
        STA  STRSINK
        LDA  RUNNING
        JZ   syn_imm
        LDP1 #MSYNIN         ; "?SYNTAX ERROR IN "
        JSR  PUTS
        LPW1 CURLINE
        LDW  LNUM,(P1+0)
        JSR  PRDECU
        JSR  CRLF
        JMP  REPL
syn_imm:LDP1 #MSYN
        JSR  PUTS
        JMP  REPL

;==============================================================================
; SAVE "path" / LOAD "path" -- the program as a P8XFS file, relative to the OS
; current directory (APATH); a leading '/' is absolute.
;==============================================================================
; APATH - make the path at (P1) absolute, honouring the OS CWD: the BIOS
;   resolvers start at the ROOT. Returns P1 -> the absolute path (the input
;   itself, or APBUF). No OS underneath (MONITOR = 0): the path is left alone.
;   Preserves P2 (SYS_GETCWD clobbers it).
APATH:  LDA  #>MONITOR
        JZ   ap_ret
        LDA  (P1)
        LDB  #'/'
        CMP
        JZ   ap_ret          ; already absolute
        TPA1L
        STA  RP              ; the relative path
        TPA1H
        STA  RP+1
        TPA2L
        PHA                  ; keep the parse cursor
        TPA2H
        PHA
        LDP1 #APBUF
        JSR  SYS_GETCWD      ; APBUF <- CWD (clobbers P2)
        LDP1 #APBUF
ap_f:   LDA  (P1)+           ; to the NUL
        JNZ  ap_f
        DEP1
        DEP1                 ; the last CWD character
        LDA  (P1)+
        LDB  #'/'
        CMP
        JZ   ap_c            ; CWD is "/" (or ends in one): no separator
        LDA  #'/'
        STA  (P1)+
ap_c:   LPW2 RP
ap_c1:  LDA  (P2)+           ; append the relative path, NUL included
        STA  (P1)+
        JNZ  ap_c1
        PLA
        TAP2H
        PLA
        TAP2L
        LDP1 #APBUF
ap_ret: RTS

st_save:INP2
        JSR  GETPATH         ; "path" -> PBUF; C=1 syntax error
        JC   SYNERR
        LEAW GTMP,(P2+0)     ; the BIOS calls may clobber the parse cursor
        LDP1 #PBUF
        JSR  APATH
        JSR  FRESOLVE        ; -> dir + leaf FNAME
        JC   sv_ferr
        JSR  PROGLEN         ; FLEN = program length (incl. the 00,00 marker)
        LDW  FSRC,#PROG
        JSR  FCREATE
        JC   sv_ferr
        LDP1 #MSAVED
fs_msg: JSR  PUTS
        LPW2 GTMP
        RTS
sv_ferr:LDP1 #MFSERR         ; ?Save failed (exists or disk full)
        JMP  fs_msg

st_load:INP2
        JSR  GETPATH
        JC   SYNERR
        LEAW GTMP,(P2+0)
        LDP1 #PBUF
        JSR  APATH
        JSR  FRESOLVE
        JC   ld_nf
        JSR  FFIND           ; -> LBA + FLEN
        JC   ld_nf
        LDP1 #PROG
        JSR  FLOADAT         ; the whole file into PROG
        LDP1 #MLOADED
        JMP  fs_msg
ld_nf:  LDP1 #MNOFILE
        JMP  fs_msg

; GETPATH - parse a quoted "path" at (P2) into PBUF, NUL-terminated, case
;   preserved, at most 47 chars; P2 past the closing quote. C=1 if no quote.
GETPATH:JSR  SKIPSP
        LDA  (P2)
        LDB  #'"'
        CMP
        JNZ  gp_err
        INP2
        LDP1 #PBUF
        LDA  #47
        STA  RP              ; room left
gp_lp:  LDA  (P2)
        JZ   gp_ok           ; line ended before the quote: accept
        LDB  #'"'
        CMP
        JZ   gp_cl
        LDA  RP
        JZ   gp_adv          ; full: consume, don't store
        DEC
        STA  RP
        LDA  (P2)
        STA  (P1)+
gp_adv: INP2
        JMP  gp_lp
gp_cl:  INP2
gp_ok:  LDA  #0
        STA  (P1)
        CLC
        RTS
gp_err: SEC
        RTS

; PROGLEN - FLEN = byte length of the program (PROG up to and including 00,00).
PROGLEN:LDP1 #PROG
pl_l:   LDA  (P1)+           ; line number, or the 00,00 marker
        STA  TMPC
        LDA  (P1)+
        LDB  TMPC
        OR
        JZ   pl_end
pl_sk:  LDA  (P1)+           ; skip the text and its terminator
        JNZ  pl_sk
        JMP  pl_l
pl_end: LEAW FLEN,(P1+0)     ; end pointer ...
        SUBW FLEN,#PROG      ; ... minus the start
        LDA  #0
        STA  FLEN+2          ; FLEN is 24-bit
        RTS

;==============================================================================
; STATEMENTS
;==============================================================================
; PRINT [# ] item {; | , item} [; | ,]   -- ';' no gap, ',' one space, a
; trailing separator suppresses the newline.
DOPRINT:INP2
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'#'
        CMP
        JZ   DOPRINTF        ; PRINT# -> the data file
dp_item:JSR  SKIPSP
        LDA  (P2)
        JZ   dp_nl           ; end of statement -> newline
        LDB  #':'
        CMP
        JZ   dp_nl
        JSR  SPEEK           ; a string item?
        LDA  MATCHF
        JNZ  dp_pstr
        JSR  EVAL            ; numeric item
        MOVW LNUM,RESULT
        JSR  PRDEC
        JMP  dp_sep
dp_pstr:JSR  SEVAL           ; string item -> STRACC
        JSR  SPUT
dp_sep: JSR  SKIPSP
        LDA  (P2)
        LDB  #$3B            ; ';'
        CMP
        JZ   dp_semi
        LDB  #','
        CMP
        JNZ  dp_nl           ; no separator -> newline
        INP2
        LDA  #' '
        JSR  PUTC
        JMP  dp_more
dp_semi:INP2
dp_more:JSR  SKIPSP
        LDA  (P2)
        JZ   dp_done         ; trailing separator: no newline
        LDB  #':'
        CMP
        JZ   dp_done
        JMP  dp_item
dp_nl:  JMP  CRLF
dp_done:RTS

; LET [LET] var = expr  |  var$ = string expr   (the LET token is optional)
DOLET:  LDA  (P2)
        LDB  #TOK_LET
        CMP
        JNZ  dl_chk
        INP2
        JSR  SKIPSP
dl_chk: JSR  SPEEK           ; string target (NAME$)?
        LDA  MATCHF
        JNZ  dl_str
        JSR  VARGET          ; P1 = the variable's entry
        LDA  MATCHF
        JZ   SYNERR
        LEAW SAVE1,(P1+6)    ; &value, kept across the expression
        JSR  EXPECTEQ
        JSR  EVAL
        LPW1 SAVE1
        STW  (P1+0),RESULT
        RTS
dl_str: JSR  SVARGET         ; P1 = the string variable's entry
        LDA  MATCHF
        JZ   SYNERR
        LEAW SAVE1,(P1+6)    ; its value ([len][data]) is the assignment target
        JSR  EXPECTEQ
        JSR  SEVAL           ; STRACC = the value (SEVAL uses SPA/SPD itself)
        LDW  SPA,#STRACC
        MOVW SPD,SAVE1
        JMP  SMOVE

; EXPECTEQ - skip blanks, consume '=' or SYNERR.
EXPECTEQ:
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'='
        CMP
        JNZ  SYNERR
        INP2
        RTS

; EXPECTCOMMA - skip blanks, consume ',' or SYNERR.
EXPECTCOMMA:
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  SYNERR
        INP2
        RTS

;==============================================================================
; PROGRAM EXECUTION: RUN, GOTO, GOSUB/RETURN, IF/THEN, END, FOR/NEXT
;==============================================================================
DORUN:  INP2
        LDA  #0
        STA  GSP             ; reset the GOSUB and FOR stacks
        STA  FSP
        STA  FMODE           ; abandon any data file a previous run left open
        STA  OUTFILE
        LDA  #1
        STA  RUNNING         ; errors now report their line number
        LDW  CURLINE,#PROG
run_l:  LPW1 CURLINE
        LDA  (P1)+
        STA  TMPC
        LDA  (P1)+
        LDB  TMPC
        OR
        JZ   run_done        ; 00,00 marker: end of the program
        TPA1L                ; P2 = the line text
        TAP2L
        TPA1H
        TAP2H
run_exec:
        LDA  #0
        STA  BRANCHF
        STA  JUMPF
        STA  ENDF
        JSR  STMTLINE
        LDA  ENDF
        JNZ  run_done
        LDA  JUMPF
        JNZ  run_jump
        LDA  BRANCHF
        JNZ  run_goto
        LPW1 CURLINE         ; next line: past the number and the text
        INP1
        INP1
rn_sk:  LDA  (P1)+
        JNZ  rn_sk
        LEAW CURLINE,(P1+0)
        JMP  run_l
run_goto:
        JSR  FINDLINE        ; BRANCHN -> P1 = its record
        LDA  FNDF
        JZ   run_undef
        LEAW CURLINE,(P1+0)
        JMP  run_l
run_jump:
        LDA  JUMPF           ; 1 = jump to a line record; 2 = resume at a text pointer
        LDB  #2
        CMP
        JZ   run_resume
        MOVW CURLINE,JUMPADDR
        JMP  run_l
run_resume:
        LPW2 JUMPADDR
        JMP  run_exec
run_undef:
        LDP1 #MUNDEF
        JSR  PUTS
run_done:
        LDA  #1              ; stop STMTLINE (RUN consumed the rest of its line)
        STA  ENDF
        LDP1 #MOK
        JMP  PUTS

; FINDLINE - find the program line numbered BRANCHN: FNDF=1 and P1 = its
;   record. The list is sorted, so the scan stops once it passes the target.
FINDLINE:
        LDP1 #PROG
fl_l:   LDW  RNUM,(P1+0)
        LDA  RNUM
        LDB  RNUM+1
        OR
        JZ   fl_no           ; end marker
        CMPW RNUM,BRANCHN
        JNC  fl_sk           ; RNUM < target: keep going
        JNZ  fl_no           ; high bytes differ, so RNUM > target
        LDA  RNUM
        LDB  BRANCHN
        CMP
        JNZ  fl_no           ; low bytes differ: passed it
        LDA  #1
        STA  FNDF
        RTS
fl_sk:  INP1
        INP1
fl_s1:  LDA  (P1)+
        JNZ  fl_s1
        JMP  fl_l
fl_no:  LDA  #0
        STA  FNDF
        RTS

; GOTO line
DOGOTO: INP2
        JSR  SKIPSP
DOGOTON:JSR  PARSEDEC        ; LNUM = the target
        MOVW BRANCHN,LNUM
        LDA  #1
        STA  BRANCHF
        RTS

; IF expr THEN statement(s) | line-number
DOIF:   INP2
        JSR  EVAL
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_THEN
        CMP
        JNZ  SYNERR
        INP2
        LDA  RESULT
        LDB  RESULT+1
        OR
        JZ   if_false
        JSR  SKIPSP
        LDA  (P2)
        JSR  ISDIGIT
        JC   DOGOTON         ; THEN 100 -> implicit GOTO
        JMP  STMTLINE        ; THEN clause = the rest of the line
if_false:                    ; false: skip the whole rest of the line
        LDA  (P2)
        JZ   iff_d
        INP2
        JMP  if_false
iff_d:  RTS

; END
DOEND:  INP2
        LDA  #1
        STA  ENDF
        RTS

; REM - the rest of the line is a comment
DOREM:  LDA  (P2)
        JZ   rem_d
        INP2
        JMP  DOREM
rem_d:  RTS

; POKE addr,val
DOPOKE: INP2
        JSR  EVAL
        MOVW POKEA,RESULT
        JSR  EXPECTCOMMA
        JSR  EVAL
        LPW1 POKEA
        LDA  RESULT
        STA  (P1)
        RTS

; INPUT [# ] var | var$   -- prompt "? " and read a line
DOINPUT:INP2
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'#'
        CMP
        JZ   DOINPUTF        ; INPUT# -> one record from the data file
        JSR  SPEEK
        LDA  MATCHF
        JNZ  in_str
        JSR  VARGET
        LDA  MATCHF
        JZ   SYNERR
        LEAW SAVE1,(P1+6)
        JSR  in_ask          ; GTMP = parse cursor, LBUF = the reply, P2 -> LBUF
        JSR  PARSEDEC        ; LNUM = the number
        LPW1 SAVE1
        STW  (P1+0),LNUM
        LPW2 GTMP
        RTS
in_str: JSR  SVARGET
        LDA  MATCHF
        JZ   SYNERR
        LEAW SPD,(P1+6)      ; the string variable's value
        JSR  in_ask
        LDP1 #STRACCD        ; LBUF -> STRACC (len + data, capped at SLEN)
        LDA  #0
        STA  SI
ins_cl: LDA  (P2)
        JZ   ins_ce
        LDA  SI
        LDB  #SLEN
        CMP
        JC   ins_ce
        INC
        STA  SI
        LDA  (P2)+
        STA  (P1)+
        JMP  ins_cl
ins_ce: LDA  SI
        STA  STRACC
        LDW  SPA,#STRACC
        JSR  SMOVE
        LPW2 GTMP
        RTS
; in_ask - save the parse cursor, prompt, read the reply into LBUF; P2 -> LBUF
;   at the first non-blank.
in_ask: TPA2L
        STA  GTMP
        TPA2H
        STA  GTMP+1
        LDA  #'?'
        JSR  PUTC
        LDA  #' '
        JSR  PUTC
        JSR  GETLINE
        LDP2 #LBUF
        JMP  SKIPSP

; GOSUB line - push (this line record, the text after the GOSUB), then branch
DOGOSUB:INP2
        JSR  SKIPSP
        JSR  DOGOTON         ; target -> BRANCHN / BRANCHF; P2 past the number
        JSR  SKIPSP          ; the return point is the next statement
        LDA  (P2)
        LDB  #':'
        CMP
        JNZ  gs_tp
        INP2
gs_tp:  LEAW GTMP,(P2+0)
        LDA  GSP
        LDB  #GSMAX
        CMP
        JC   SYNERR          ; too deep
        SHL                  ; P1 = &GSTK[GSP] (4-byte frames, one page)
        SHL
        LDB  #<GSTK
        ADD
        TAP1L
        LDA  #>GSTK
        TAP1H
        STW  (P1+0),CURLINE
        STW  (P1+2),GTMP
        LDA  GSP
        INC
        STA  GSP
        RTS

; RETURN - pop a return point and resume just after its GOSUB
DORET:  INP2
        LDA  GSP
        JZ   ret_err
        DEC
        STA  GSP
        SHL
        SHL
        LDB  #<GSTK
        ADD
        TAP1L
        LDA  #>GSTK
        TAP1H
        LDW  CURLINE,(P1+0)
        LDW  JUMPADDR,(P1+2)
        LDA  #2
        STA  JUMPF
        RTS
ret_err:LDP1 #MRG            ; ?RETURN WITHOUT GOSUB
        JSR  PUTS
        LDA  #1
        STA  ENDF
        RTS

; FOR var = start TO limit [STEP n]
; frame (9 bytes at FFP): [0] var index, [1..2] limit, [3..4] step,
;   [5..6] loop-back line record, [7..8] loop-back text pointer
DOFOR:  INP2
        JSR  SKIPSP
        JSR  VARGET          ; P1 = the loop variable's entry
        LDA  MATCHF
        JZ   SYNERR
        LDA  VARIDX
        STA  FORIDX          ; (EVAL below may call VARGET and clobber VARIDX)
        LEAW SAVE1,(P1+6)
        JSR  EXPECTEQ
        JSR  EVAL            ; start value
        LPW1 SAVE1
        STW  (P1+0),RESULT
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_TO
        CMP
        JNZ  SYNERR
        INP2
        JSR  EVAL            ; limit
        MOVW FLIM,RESULT
        LDW  FSTEP,#1
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_STEP
        CMP
        JNZ  for_push
        INP2
        JSR  EVAL
        MOVW FSTEP,RESULT
for_push:
        JSR  SKIPSP          ; loop-back point = the statement after the FOR
        LDA  (P2)
        LDB  #':'
        CMP
        JZ   fp_same
        LPW1 CURLINE         ; FOR ends the line: loop back to the next line
        INP1
        INP1
fp_sk:  LDA  (P1)+
        JNZ  fp_sk
        LEAW FLR,(P1+0)      ; the next record ...
        LEAW FTP,(P1+2)      ; ... and its text
        JMP  fp_alloc
fp_same:LEAW FTP,(P2+1)      ; loop back to just after the ':' (P2 stays on it,
        MOVW FLR,CURLINE     ;   so STMTLINE carries on now)
fp_alloc:
        LDA  FSP
        JNZ  fp_adv
        LDW  FFP,#FSTK       ; first frame
        JMP  fp_w
fp_adv: LDB  #FSMAX
        CMP
        JC   SYNERR          ; nested too deep
        ADDW FFP,#9
fp_w:   LPW1 FFP
        LDA  FORIDX
        STA  (P1)
        STW  (P1+1),FLIM
        STW  (P1+3),FSTEP
        STW  (P1+5),FLR
        STW  (P1+7),FTP
        LDA  FSP
        INC
        STA  FSP
        RTS

; NEXT [var] - step the innermost FOR; loop back or pop the frame
DONEXT: INP2
        JSR  SKIPSP
        LDA  (P2)            ; an optional variable name is consumed, not checked
        JSR  ISLETTER
        JNC  nx_go
        JSR  VARGET
nx_go:  LDA  FSP
        JZ   SYNERR          ; NEXT without FOR
        LPW1 FFP
        LDA  (P1)
        STA  VARIDX
        LDW  FLIM,(P1+1)
        LDW  FSTEP,(P1+3)
        LDW  FLR,(P1+5)
        LDW  FTP,(P1+7)
        JSR  IDXADDR         ; P1 = the loop variable's entry
        LDW  NUM1,(P1+6)
        ADDW NUM1,FSTEP      ; var += step
        STW  (P1+6),NUM1
        CMPW NUM1,FLIM       ; signed: BLT = var < limit
        BLT  nx_below
        JNZ  nx_above        ; high bytes differ and not below: above
        LDA  NUM1
        LDB  FLIM
        CMP
        JZ   nx_loop         ; var == limit: the limit is inclusive
nx_above:                    ; var > limit: an UP loop is finished
        LDA  FSTEP+1
        LDB  #$80
        AND
        JZ   nx_done
        JMP  nx_loop
nx_below:                    ; var < limit: a DOWN loop is finished
        LDA  FSTEP+1
        LDB  #$80
        AND
        JNZ  nx_done
nx_loop:MOVW CURLINE,FLR
        MOVW JUMPADDR,FTP
        LDA  #2
        STA  JUMPF
        RTS
nx_done:LDA  FSP             ; pop the frame
        DEC
        STA  FSP
        JZ   nx_ret
        SUBW FFP,#9
nx_ret: RTS

;==============================================================================
; GRAPHICS -- everything EMITS GL bytes through GLPUT: the classic statements
; (COLOR / CLS / PIXELW / LINE / BOX / CIRCLE, PIXELR()) are spellings of the
; same verbs the generated PGC statements expose directly. The drawing engine
; is in the card. Window space, y UP, 480x272 RGB565.
;==============================================================================
; GCHECK - a display fitted? An absent card floats the bus to $FF; 'G' at GLID
;   is the one presence signal. Without one, abandon the statement.
GCHECK: LDA  GLIDR
        LDB  #'G'
        CMP
        JNZ  GNODEV
        RTS
GNODEV: LPW3 SPSAV           ; same unwind as SYNERR
        LDA  #0
        STA  OUTFILE
        STA  STRSINK
        LDP1 #MNOGFX
        JSR  PUTS
        JMP  REPL

; glchk - graphics present, and prime GLFST for the GLVSEP argument walk
glchk:  JSR  GCHECK
        LDA  #1
        STA  GLFST
        RTS

; glwin - the FULL-SCREEN window + viewport and a white pen. The raw port
;   powers up (and RESETF resets to) a degenerate all-zero window that draws
;   nothing; BASIC emits this at cold start and after the native RESETF.
glwin:  LDP1 #glwtab
        LDA  #22
        STA  GLCNT
glw_l:  LDA  (P1)+
        JSR  GLPUT
        LDA  GLCNT
        DEC
        STA  GLCNT
        JNZ  glw_l
        RTS
glwtab: .byte $B3,$00,$00,$DF,$01,$00,$00,$0F,$01   ; WINDOW 0,479,0,271
        .byte $B2,$00,$00,$DF,$01,$00,$00,$0F,$01   ; VWPORT 0,479,0,271
        .byte $06,$1F,$3F,$1F                       ; COLOR 31,63,31

; GLPUT - one byte to the GL FIFO, honouring the full bit (GLSTAT bit 7).
;   Preserves nothing but the byte's meaning; A is clobbered.
GLPUT:  STA  GLTMP
glp_w:  LDA  GLSTATR
        LDB  #$80
        AND
        JNZ  glp_w
        LDA  GLTMP
        STA  GLDATAR
        RTS

; GLPW - RESULT to the FIFO as an int16, little-endian
GLPW:   LDA  RESULT
        JSR  GLPUT
        LDA  RESULT+1
        JMP  GLPUT

; bxw - one shadowed int16 at (P1) to the FIFO (P1 advanced)
bxw:    LDA  (P1)+
        JSR  GLPUT
        LDA  (P1)+
        JMP  GLPUT

; bx_pf - emit PRMFIL <A> raw (BOX/CIRCLE's temporary flip is not the program's
;   setting; bx_rs restores PRMSH afterwards)
bx_pf:  STA  GLDIM
        LDA  #$E0
        JSR  GLPUT
        LDA  GLDIM
        JMP  GLPUT

; glarg0/1/2/3 - one comma-separated argument into BXS slot 0..3
glarg0: JSR  GLVSEP
        MOVW BXS,RESULT
        RTS
glarg1: JSR  GLVSEP
        MOVW BXS+2,RESULT
        RTS
glarg2: JSR  GLVSEP
        MOVW BXS+4,RESULT
        RTS
glarg3: JSR  GLVSEP
        MOVW BXS+6,RESULT
        RTS

; LINE x0,y0,x1,y1 -- GL: MOVE x0 y0, DRAW x1 y1 (streamed as the arguments parse)
DOGLINE:INP2
        JSR  glchk
        LDA  #$10            ; MOVE
        JSR  GLPUT
        JSR  GLVSEP
        JSR  GLPW
        JSR  GLVSEP
        JSR  GLPW
        LDA  #$28            ; DRAW
        JSR  GLPUT
        JSR  GLVSEP
        JSR  GLPW
        JSR  GLVSEP
        JSR  GLPW
        JMP  glv_dn

; COLOR c  |  COLOR r,g,b -- the pen is a whole RGB565 colour: one number is a
; PACKED colour (RGB() builds one, PIXELR() returns one), three are r,b 0-31 and
; g 0-63 packed by RGBTAIL. Emitted as GL COLOR r g b.
DOCOLOR:INP2
        JSR  GCHECK
        JSR  EVAL
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  dc_st
        JSR  RGBTAIL         ; RESULT was r; parse ,g,b and pack
dc_st:  LDA  GLIDR
        LDB  #'G'
        CMP
        JNZ  dc_rts
        LDA  #$06            ; GL COLOR
        JSR  GLPUT
        LDA  RESULT+1        ; r = pen[15:11]
        SHR
        SHR
        SHR
        JSR  GLPUT
        LDA  RESULT+1        ; g = pen[10:8] over pen[7:5]
        LDB  #$07
        AND
        SHL
        SHL
        SHL
        STA  GLCNT
        LDA  RESULT
        SHR
        SHR
        SHR
        SHR
        SHR
        LDB  GLCNT
        OR
        JSR  GLPUT
        LDA  RESULT          ; b = pen[4:0]
        LDB  #$1F
        AND
        JMP  GLPUT
dc_rts: RTS

; BOX x0,y0,x1,y1 [,FILL | ,NOFILL] -- GL: PRMFIL, MOVE, RECT, PRMFIL restored.
; The coordinates buffer in BXS because the PRMFIL byte must precede them and
; the FILL/NOFILL decision arrives last. (NOFILL is a real keyword: otherwise
; CRUNCH would match FILL inside the word and draw a solid box.)
DOBOX:  INP2
        JSR  glchk
        JSR  glarg0
        JSR  glarg1
        JSR  glarg2
        JSR  glarg3
        JSR  FILLMOD         ; A = 0 outline / 1 filled
        JSR  bx_pf
        LDA  #$10            ; MOVE x0 y0
        JSR  GLPUT
        LDP1 #BXS
        JSR  bxw
        JSR  bxw
        LDA  #$34            ; RECT x1 y1
        JSR  GLPUT
        JSR  bxw
        JSR  bxw
bx_rs:  LDA  #$E0            ; PRMFIL back to the program's setting
        JSR  GLPUT
        LDA  PRMSH
        JSR  GLPUT
        JMP  glv_dn

; FILLMOD - an optional ",FILL" / ",NOFILL" at (P2): A = 1 / 0 (0 if absent),
;   consumed. Anything else after the comma is a syntax error.
FILLMOD:JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  fm_out
        INP2
        JSR  SKIPSP
        JSR  FILLKW          ; C=1: FILL/NOFILL consumed, A = 1/0
        JNC  SYNERR
        RTS
fm_out: LDA  #0
        RTS

; FILLKW - is (P2) the FILL or NOFILL token? C=1 and A = 1 / 0 with it consumed;
;   C=0 (P2 unchanged) otherwise.
FILLKW: LDA  (P2)
        LDB  #TOK_FILL
        CMP
        JZ   fk_fill
        LDB  #TOK_NOFILL
        CMP
        JNZ  fk_no
        INP2
        LDA  #0
        SEC
        RTS
fk_fill:INP2
        LDA  #1
        SEC
        RTS
fk_no:  CLC
        RTS

; CLS -- GL FLOOD 0,0,0: clear to the background across the current viewport
DOCLS:  INP2
        JSR  glchk
        LDA  #$07            ; FLOOD r g b
        JSR  GLPUT
        LDA  #0
        JSR  GLPUT
        LDA  #0
        JSR  GLPUT
        LDA  #0
        JSR  GLPUT
        JMP  glv_dn

; PIXELW x,y -- GL: MOVE then POINT, current pen
DOPIXW: INP2
        JSR  glchk
        LDA  #$10            ; MOVE
        JSR  GLPUT
        JSR  GLVSEP
        JSR  GLPW
        JSR  GLVSEP
        JSR  GLPW
        LDA  #$08            ; POINT
        JSR  GLPUT
        JMP  glv_dn

; CIRCLE x,y,r [,ry] [,FILL | ,NOFILL] -- GL: PRMFIL, MOVE, ELIPSE rx ry,
; PRMFIL restored. After a comma the TOKEN decides: FILL/NOFILL is a keyword
; (>= $80), anything else starts the second radius's expression.
DOCIRC: INP2
        JSR  glchk
        JSR  glarg0          ; x
        JSR  glarg1          ; y
        JSR  glarg2          ; r -> rx ...
        MOVW BXS+6,RESULT    ; ... and ry until a second radius says otherwise
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  ci_out
        INP2
        JSR  SKIPSP
        JSR  FILLKW
        JC   ci_go
        JSR  EVAL            ; a second radius -> ellipse
        MOVW BXS+6,RESULT
        JSR  FILLMOD         ; ... and it may still take a modifier
        JMP  ci_go
ci_out: LDA  #0
ci_go:  JSR  bx_pf
        LDA  #$10            ; MOVE x y
        JSR  GLPUT
        LDP1 #BXS
        JSR  bxw
        JSR  bxw
        LDA  #$39            ; ELIPSE rx ry
        JSR  GLPUT
        JSR  bxw
        JSR  bxw
        JMP  bx_rs

; GTEXT x,y,size,s$ -- easy 2D text: PROJCT 0, MDIDEN, TSIZE size*256,
; MDTRAN x y 0, MOVE3 0 0 0, TEXT s$. Window coords, baseline-left anchor,
; absolute size (0 clamps to 1); the modeling matrix and camera are reset on
; purpose -- 3D work uses the raw TEXT/TSIZE/TANGLE/TJUST verbs.
DOGTEXT:INP2
        JSR  glchk
        JSR  glarg0          ; x
        JSR  glarg1          ; y
        JSR  GLVSEP          ; size
        LDA  RESULT
        JNZ  gt_sz
        LDA  #1
gt_sz:  STA  BXS+4           ; TSIZE's high byte (= *256)
        JSR  EXPECTCOMMA
        LDP1 #gttab          ; PROJCT 0 ; MDIDEN ; TSIZE 0,
        LDA  #6
        STA  GLCNT
gt_l:   LDA  (P1)+
        JSR  GLPUT
        LDA  GLCNT
        DEC
        STA  GLCNT
        JNZ  gt_l
        LDA  BXS+4
        JSR  GLPUT
        LDA  #$96            ; MDTRAN x y 0
        JSR  GLPUT
        LDP1 #BXS
        JSR  bxw
        JSR  bxw
        LDA  #0
        JSR  GLPUT
        LDA  #0
        JSR  GLPUT
        LDA  #$12            ; MOVE3 0 0 0
        JSR  GLPUT
        LDA  #6
        STA  GLCNT
gt_z:   LDA  #0
        JSR  GLPUT
        LDA  GLCNT
        DEC
        STA  GLCNT
        JNZ  gt_z
        LDA  #$80            ; TEXT, then glv_str sends the string
        JSR  GLPUT
        JMP  glv_str
gttab:  .byte $B0,$00,$00,$90,$81,$00

; GL string$ -- one ASCII graphics-language line, wrapped "CA " ... CR "CX "
; so the card is back in HEX mode afterwards. Asynchronous (no drain).
DOGL:   INP2
        JSR  GCHECK
        JSR  SEVAL           ; STRACC = the line
        LDA  #'C'
        JSR  GLPUT
        LDA  #'A'
        JSR  GLPUT
        LDA  #' '
        JSR  GLPUT
        JSR  glsend          ; the characters
        LDA  #13             ; a CR finishes the last token
        JSR  GLPUT
        LDA  #'C'
        JSR  GLPUT
        LDA  #'X'
        JSR  GLPUT
        LDA  #' '
        JMP  GLPUT

; glsend - the STRACC characters to the FIFO
glsend: LDP1 #STRACCD
        LDA  STRACC
        STA  GLN
gls_l:  LDA  GLN
        JZ   gls_d
        DEC
        STA  GLN
        LDA  (P1)+
        JSR  GLPUT
        JMP  gls_l
gls_d:  RTS

; ---- the native GL verb statements (tokens GLV0..GLV0+GLVN-1) ---------------
; ONE handler for all of them. The verb index (in A from STMT) picks the GLVTAB
; entry gen_glkw.py wrote: the GL opcode and a meta byte {var<<7 | bcnt<<4 |
; word-arity}. The opcode goes to the FIFO, then bcnt byte-width params, then
; the int16 params little-endian -- every argument an expression, the first
; bare, the rest after commas. POLY* (var) take a count then count vertices of
; 2 or 3 words (3 when opcode bit 1). Synchronous: glv_dn drains busy.
DOGLV:  STA  GLTMP
        INP2
        JSR  GCHECK
        LDA  GLTMP           ; P1 = &GLVTAB[index]
        SHL
        LDB  #<GLVTAB
        ADD
        TAP1L
        LDA  #0
        ROL
        LDB  #>GLVTAB
        ADD
        TAP1H
        LDA  (P1)            ; read BEFORE any EVAL (expressions walk P1)
        STA  GLOP
        LDA  (P1+1)
        STA  GLMETA
        LDA  GLOP
        JSR  GLPUT           ; the opcode
        LDA  GLOP
        LDB  #$04            ; RESETF: the card's PRMFIL goes home and the
        CMP                  ;   window comes back degenerate -- follow it
        JNZ  glv_nr
        LDA  #0
        STA  PRMSH
        JSR  glwin
glv_nr: LDA  GLMETA
        LDB  #$FF            ; meta $FF: the string statement (TEXT)
        CMP
        JZ   glv_str
        LDA  #1
        STA  GLFST
        LDA  GLMETA
        LDB  #$80
        AND
        JNZ  glv_var         ; POLY*: count then vertices
        LDA  GLMETA          ; bcnt byte params first
        SHR
        SHR
        SHR
        SHR
        STA  GLCNT
glv_bl: LDA  GLCNT
        JZ   glv_w0
        DEC
        STA  GLCNT
        JSR  GLVSEP
        LDA  GLOP
        LDB  #$E0            ; PRMFIL: shadow the program's setting
        CMP
        JNZ  glv_np
        LDA  RESULT
        STA  PRMSH
glv_np: LDA  RESULT
        JSR  GLPUT           ; the low byte only
        JMP  glv_bl
glv_w0: LDA  GLMETA          ; then the int16 params
        LDB  #$0F
        AND
        STA  GLCNT
glv_wl: LDA  GLCNT
        JZ   glv_dn
        DEC
        STA  GLCNT
        JSR  GLVSEP
        JSR  GLPW
        JMP  glv_wl
glv_dn: LDA  GLSTATR         ; drain busy (bit 6): a PIXELR right after a draw
        LDB  #$40            ;   reads finished pixels, on silicon as in the emulator
        AND
        JNZ  glv_dn
        RTS

glv_str:JSR  SEVAL           ; TEXT s$: count byte, the chars, then the drain
        LDA  STRACC
        JSR  GLPUT
        JSR  glsend
        JMP  glv_dn

glv_var:JSR  GLVSEP          ; the vertex count, to the FIFO as a byte
        LDA  RESULT
        STA  GLN
        JSR  GLPUT
        LDA  #2
        STA  GLDIM
        LDA  GLOP            ; opcode bit 1 -> 3D: three words per vertex
        LDB  #2
        AND
        JZ   glv_vl
        LDA  #3
        STA  GLDIM
glv_vl: LDA  GLN
        JZ   glv_dn
        DEC
        STA  GLN
        LDA  GLDIM
        STA  GLCNT
glv_vw: LDA  GLCNT
        JZ   glv_vl
        DEC
        STA  GLCNT
        JSR  GLVSEP
        JSR  GLPW
        JMP  glv_vw

; GLVSEP - the comma rule + an expression: the first argument follows the
;   keyword bare, every later one needs its comma. Result in RESULT.
GLVSEP: LDA  GLFST
        JZ   glvs_c
        LDA  #0
        STA  GLFST
        JMP  EVAL
glvs_c: JSR  EXPECTCOMMA
        JMP  EVAL

; IMAGE x,y,name$ -- draw a P8I file, bottom-left at (x,y): one GL BLIT per
; row -- header (x, row y, w, 1) then 2*w raw file bytes straight to the FIFO
; (P8I rows are top-down RGB565 little-endian, the BLIT payload verbatim). A
; short file pads the row in flight with zeros (the walker must get every byte
; it is owed) and stops with ?NOT P8I. Uses the data channel's machinery, so an
; OPEN file is closed by IMAGE.
DOIMAGE:INP2
        JSR  GCHECK
        JSR  EVAL            ; x
        MOVW IMX,RESULT
        JSR  EXPECTCOMMA
        JSR  EVAL            ; y
        MOVW IMYC,RESULT
        JSR  EXPECTCOMMA
        JSR  SETFNAME        ; dir + FNAME = the resolved path
        TPA2L                ; the parse cursor sleeps through the file phase
        PHA                  ;   (FGETB clobbers P1 AND P2 on a refill)
        TPA2H
        PHA
        LDP1 #PBUF
        JSR  FOPEN
        JC   img_nf
        LDA  #0
        STA  FMODE           ; the channel is ours; it stays closed after
        JSR  IMGB            ; ---- header: "P8I", version 1
        LDB  #'P'
        CMP
        JNZ  img_bad
        JSR  IMGB
        LDB  #'8'
        CMP
        JNZ  img_bad
        JSR  IMGB
        LDB  #'I'
        CMP
        JNZ  img_bad
        JSR  IMGB
        LDB  #1
        CMP
        JNZ  img_bad
        JSR  IMGB
        STA  IMW             ; width, little-endian
        JSR  IMGB
        STA  IMW+1
        JSR  IMGB
        STA  IMH             ; height
        JSR  IMGB
        STA  IMH+1
        JSR  IMGB
        LDB  #16             ; depth: RGB565 or nothing
        CMP
        JNZ  img_bad
        JSR  IMGB            ; reserved
        LDA  IMW             ; a zero dimension draws nothing
        LDB  IMW+1
        OR
        JZ   img_done
        LDA  IMH
        LDB  IMH+1
        OR
        JZ   img_done
        ADDW IMYC,IMH        ; the first file row is the image's TOP: y + h - 1
        DECW IMYC
img_row:LDA  #$64            ; BLIT x y w 1
        JSR  GLPUT
        LDA  IMX
        JSR  GLPUT
        LDA  IMX+1
        JSR  GLPUT
        LDA  IMYC
        JSR  GLPUT
        LDA  IMYC+1
        JSR  GLPUT
        LDA  IMW
        JSR  GLPUT
        LDA  IMW+1
        JSR  GLPUT
        LDA  #1
        JSR  GLPUT
        LDA  #0
        JSR  GLPUT
        MOVW IMCX,IMW        ; 2*w payload bytes
        ADDW IMCX,IMCX
img_px: JSR  IMGB
        JC   img_pad         ; short file: pad the row, then abort
        JSR  GLPUT
img_nx: DECW IMCX
        LDA  IMCX
        LDB  IMCX+1
        OR
        JNZ  img_px
        DECW IMYC            ; next row, down the screen
        DECW IMH
        LDA  IMH
        LDB  IMH+1
        OR
        JNZ  img_row
        JMP  img_done
img_pad:LDA  #0
        JSR  GLPUT
        DECW IMCX
        LDA  IMCX
        LDB  IMCX+1
        OR
        JNZ  img_pad
        JMP  img_bad
img_done:
        PLA                  ; the parse cursor, back from before the file
        TAP2H
        PLA
        TAP2L
        RTS
img_nf: LDA  #0
        STA  FMODE
        LDP1 #MNOFILE
        JSR  PUTS
        JMP  img_done
img_bad:LDP1 #MNOTIMG
        JSR  PUTS
        JMP  img_done

; IMGB - the next file byte -> A (C=0). At EOF it ABANDONS the statement: its
;   own return address is popped and control goes to the ?NOT P8I report.
IMGB:   JSR  FGETB
        JC   imgb_e
        RTS
imgb_e: PLA
        PLA
        JMP  img_bad

;==============================================================================
; EXPRESSIONS (recursive descent) -> RESULT
;   EVAL   = EXPR [relop EXPR]          -> value, or 1/0 for a comparison
;   EXPR   = TERM   {(+|-) TERM}
;   TERM   = FACTOR {(*|/|%) FACTOR}
;   FACTOR = [-|+] number | 0xhex | variable | function(...) | GLRD | ( EXPR )
; The running left value rides the P3 stack (PHW/PLW) across the recursion.
; A string-valued operand (SPEEK) routes EVAL to EVALSTR: a string comparison.
;==============================================================================
EVAL:   JSR  SPEEK
        LDA  MATCHF
        JNZ  EVALSTR
        JSR  EXPR
        JSR  RELOPP          ; an optional relational operator -> RELM
        JC   ev_ret
        MOVW LFT,RESULT
        JSR  EXPR
        JSR  CMPLR           ; REL = LFT vs RESULT, signed
ev_res: LDA  REL             ; RESULT = (REL AND RELM) <> 0
        LDB  RELM
        AND
        JZ   ev_z
        LDA  #1
ev_z:   STA  RESULT
        LDA  #0
        STA  RESULT+1
ev_ret: RTS

; RELOPP - parse a relational operator at (P2) into RELM (a relation mask);
;   C=1 if there is none (P2 unchanged).
RELOPP: JSR  SKIPSP
        LDA  (P2)
        LDB  #'='
        CMP
        JZ   ro_eq
        LDB  #'<'
        CMP
        JZ   ro_lt
        LDB  #'>'
        CMP
        JZ   ro_gt
        SEC
        RTS
ro_eq:  LDA  #R_EQ
ro_set: INP2
        STA  RELM
        CLC
        RTS
ro_lt:  LDA  (P2+1)
        LDB  #'='
        CMP
        JZ   ro_le
        LDB  #'>'
        CMP
        JZ   ro_ne
        LDA  #R_LT
        JMP  ro_set
ro_le:  INP2
        LDA  #R_LT+R_EQ
        JMP  ro_set
ro_ne:  INP2
        LDA  #R_LT+R_GT
        JMP  ro_set
ro_gt:  LDA  (P2+1)
        LDB  #'='
        CMP
        JZ   ro_ge
        LDA  #R_GT
        JMP  ro_set
ro_ge:  INP2
        LDA  #R_GT+R_EQ
        JMP  ro_set

; CMPLR - REL = the SIGNED relation of LFT to RESULT (R_LT / R_EQ / R_GT)
CMPLR:  CMPW LFT,RESULT
        BLT  cl_lt
        JNZ  cl_gt           ; high bytes differ and not below: above
        LDA  LFT
        LDB  RESULT
        CMP
        JNZ  cl_gt
        LDA  #R_EQ
        STA  REL
        RTS
cl_lt:  LDA  #R_LT
        STA  REL
        RTS
cl_gt:  LDA  #R_GT
        STA  REL
        RTS

EXPR:   JSR  TERM
ex_l:   JSR  SKIPSP
        LDA  (P2)
        LDB  #'+'
        CMP
        JZ   ex_add
        LDB  #'-'
        CMP
        JZ   ex_sub
        RTS
ex_add: INP2
        PHW  RESULT
        JSR  TERM
        PLW  NUM1
        ADDW RESULT,NUM1
        JMP  ex_l
ex_sub: INP2
        PHW  RESULT
        JSR  TERM
        PLW  NUM1
        SUBW NUM1,RESULT
        MOVW RESULT,NUM1
        JMP  ex_l

TERM:   JSR  FACTOR
tm_l:   JSR  SKIPSP
        LDA  (P2)
        LDB  #'*'
        CMP
        JZ   tm_mul
        LDB  #'/'
        CMP
        JZ   tm_div
        LDB  #'%'
        CMP
        JZ   tm_mod
        RTS
tm_mul: INP2
        PHW  RESULT
        JSR  FACTOR
        PLW  NUM1
        MOVW NUM2,RESULT
        JSR  MUL16
        MOVW RESULT,NUM1
        JMP  tm_l
tm_div: INP2
        JSR  tm_dv
        MOVW RESULT,NUM1     ; the quotient
        JMP  tm_l
tm_mod: INP2
        JSR  tm_dv
        MOVW RESULT,REM      ; the remainder
        JMP  tm_l
tm_dv:  PHW  RESULT          ; left / right -> NUM1, REM (unsigned)
        JSR  FACTOR
        PLW  NUM1
        MOVW NUM2,RESULT
        JMP  DIV16

FACTOR: JSR  SKIPSP
        LDA  (P2)
        LDB  #'-'
        CMP
        JZ   fa_neg
        LDB  #'+'
        CMP
        JZ   fa_plus
        LDB  #'('
        CMP
        JZ   fa_par
        LDB  #TOK_GLRD
        CMP
        JZ   fa_glrd
        LDB  #$80
        SUB
        JNC  fa_text         ; a number or a variable
        LDB  #NTOK
        CMP
        JC   SYNERR          ; a GL verb / unassigned token in an expression
        SHL                  ; P1 = &FACTAB[token]
        LDB  #<FACTAB
        ADD
        TAP1L
        LDA  #0
        ROL
        LDB  #>FACTAB
        ADD
        TAP1H
        LDW  CUR,(P1+0)
        LPW1 CUR
        INP2                 ; consume the function token
        JSR  (P1)
        RTS
fa_text:LDA  (P2)
        JSR  ISDIGIT
        JNC  fa_var
        LDB  #'0'            ; "0x" hex?
        CMP
        JNZ  fa_dec
        LDA  (P2+1)
        LDB  #'x'
        CMP
        JZ   fa_hex
        LDB  #'X'
        CMP
        JZ   fa_hex
fa_dec: JSR  PARSEDEC
        MOVW RESULT,LNUM
        RTS
fa_hex: INP2
        INP2
        JMP  PARSEHEX        ; -> RESULT
fa_var: JSR  VARGET          ; P1 = the variable's entry
        LDA  MATCHF
        JZ   SYNERR
        LDW  RESULT,(P1+6)
        RTS
fa_par: INP2
        JSR  EXPR
        JMP  EXPECTRP
fa_plus:INP2
        JMP  FACTOR
fa_neg: INP2
        JSR  FACTOR
NEGRES: XORW RESULT,#$FFFF   ; RESULT = -RESULT
        INCW RESULT
        RTS

; Function handlers by token ($80..$B3), entered with the token consumed.
; Anything that is not a numeric function is a syntax error.
FACTAB: .word SYNERR,SYNERR,SYNERR,SYNERR             ; $80
        .word SYNERR,SYNERR,SYNERR,SYNERR             ; $84
        .word SYNERR,SYNERR,SYNERR,SYNERR             ; $88
        .word SYNERR,SYNERR,SYNERR,SYNERR             ; $8C
        .word fa_abs,fa_rnd,fa_peek,SYNERR            ; $90 ABS RND PEEK
        .word SYNERR,SYNERR,SYNERR,SYNERR             ; $94
        .word SYNERR,SYNERR,SYNERR,SYNERR             ; $98
        .word SYNERR,fa_len,fa_asc,SYNERR             ; $9C LEN ASC
        .word SYNERR,SYNERR,SYNERR,fa_val             ; $A0 VAL
        .word fa_eof,SYNERR,SYNERR,SYNERR             ; $A4 EOF
        .word SYNERR,SYNERR,SYNERR,SYNERR             ; $A8
        .word SYNERR,SYNERR,fa_point,SYNERR           ; $AC PIXELR
        .word SYNERR,fa_rgb,SYNERR,SYNERR             ; $B0 RGB

; PARGET - '(' EXPR ')' -> RESULT
PARGET: JSR  EXPECTLP
        JSR  EXPR
; EXPECTRP - skip blanks, consume ')' or SYNERR
EXPECTRP:
        JSR  SKIPSP
        LDA  (P2)
        LDB  #')'
        CMP
        JNZ  SYNERR
        INP2
        RTS
; EXPECTLP - skip blanks, consume '(' or SYNERR
EXPECTLP:
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'('
        CMP
        JNZ  SYNERR
        INP2
        RTS

fa_abs: JSR  PARGET
        LDA  RESULT+1
        LDB  #$80
        AND
        JZ   fa_abd
        JMP  NEGRES
fa_abd: RTS

fa_peek:JSR  PARGET
        LPW1 RESULT
        LDA  (P1)            ; I/O is memory-mapped, so PEEK reaches it too
        STA  RESULT
        LDA  #0
        STA  RESULT+1
        RTS

; RND(n) = 1..n  (RND(0) = 0)
fa_rnd: JSR  PARGET
        LDA  RESULT
        LDB  RESULT+1
        OR
        JZ   fa_rz
        PHW  RESULT          ; n
        JSR  RANDOM          ; NUM1 = a random 16-bit value
        PLW  NUM2
        JSR  DIV16           ; REM = random mod n
        MOVW RESULT,REM
        INCW RESULT
fa_rz:  RTS

; RANDOM - LCG: SEED = SEED*25173 + 13849; result in NUM1
RANDOM: MOVW NUM1,SEED
        LDW  NUM2,#25173
        JSR  MUL16
        ADDW NUM1,#13849
        MOVW SEED,NUM1
        RTS

; PIXELR(x,y) -- the GL PIXRD verb: the colour at a window pixel via the
; read-back FIFO (0 off-screen), through BASIC's signed integers.
fa_point:
        JSR  glchk
        JSR  EXPECTLP
        LDA  #$63            ; PIXRD
        JSR  GLPUT
        JSR  EXPR
        JSR  GLPW            ; x
        JSR  EXPECTCOMMA
        JSR  EXPR
        JSR  GLPW            ; y
        JSR  EXPECTRP
        JSR  GLRDW           ; low byte ...
        STA  RESULT
        JSR  GLRDW           ; ... then the high byte
        STA  RESULT+1
        RTS
; GLRDW - wait for a read-back byte (GLSTAT bit 0) and pop it
GLRDW:  LDA  GLSTATR
        LDB  #$01
        AND
        JZ   GLRDW
        LDA  GLRBR
        RTS

; GLRD -- pop one read-back byte (0..255), -1 when the FIFO is empty. A bare
; factor, no parens, so `V=GLRD : IF V>=0 THEN ...` drains it.
fa_glrd:INP2
        LDA  GLSTATR
        LDB  #1
        AND
        JZ   fg_emp
        LDA  GLRBR
        STA  RESULT
        LDA  #0
        STA  RESULT+1
        RTS
fg_emp: LDW  RESULT,#$FFFF
        RTS

; RGB(r,g,b) -- pack a 565 colour: r,b 0-31, g 0-63 (masked to their fields)
fa_rgb: JSR  EXPECTLP
        JSR  EXPR            ; red
        JSR  RGBTAIL
        JMP  EXPECTRP

; RGBTAIL - RESULT holds r; parse ",g,b" and pack (r<<11)|(g<<5)|b into RESULT.
;   Shared with COLOR r,g,b. The (g&7)<<5 half rides the stack across the blue
;   argument (SYNERR unwinds SP, so an error cannot leak it).
RGBTAIL:LDA  RESULT
        LDB  #$1F
        AND
        SHL
        SHL
        SHL                  ; (r&31)<<3: the high byte's top five bits
        STA  RGBH
        JSR  EXPECTCOMMA
        JSR  EXPR            ; green
        LDA  RESULT
        LDB  #$3F
        AND
        STA  RESULT
        SHR
        SHR
        SHR                  ; g>>3: the high byte's low three bits
        LDB  RGBH
        OR
        STA  RGBH
        LDA  RESULT
        LDB  #$07
        AND
        SHL
        SHL
        SHL
        SHL
        SHL                  ; (g&7)<<5: the low byte's top three bits
        PHA
        JSR  EXPECTCOMMA
        JSR  EXPR            ; blue
        LDA  RESULT
        LDB  #$1F
        AND
        STA  RESULT
        PLA
        LDB  RESULT
        OR
        STA  RESULT
        LDA  RGBH
        STA  RESULT+1
        RTS

;==============================================================================
; VARIABLES: a name -> value table, entry = name[6] (upcased, space-padded)
; + value[2]; the value is (entry+6). Names are significant to 6 characters.
;==============================================================================
; VARGET - parse a variable name at (P2), find or create it: P1 = its entry,
;   VARIDX = its index, MATCHF = 1. MATCHF = 0 if (P2) is not a name (P2 kept).
VARGET: JSR  PARSENAME
        LDA  MATCHF
        JZ   vg_ret
        JSR  VARFIND
        LDA  #1
        STA  MATCHF
vg_ret: RTS

; PARSENAME - an identifier at (P2) -> NMBUF (NAMLEN chars, upcased, space-
;   padded), consumed. MATCHF = 1 if it began with a letter, else 0 (P2 kept).
PARSENAME:
        LDA  (P2)
        JSR  ISLETTER
        JNC  pn_bad
        LDW  NMBUF,#$2020    ; blank the name field
        LDW  NMBUF+2,#$2020
        LDW  NMBUF+4,#$2020
        LDP1 #NMBUF
        LDA  #NAMLEN
        STA  TMPC
pn_cp:  LDA  (P2)
        JSR  ISALNUM
        JNC  pn_end
        LDA  TMPC
        JZ   pn_skip         ; the field is full: consume, don't store
        DEC
        STA  TMPC
        LDA  (P2)
        JSR  UPCHAR
        STA  (P1)+
pn_skip:INP2
        JMP  pn_cp
pn_end: LDA  #1
        STA  MATCHF
        RTS
pn_bad: LDA  #0
        STA  MATCHF
        RTS

; ISALNUM - C=1 if A is a letter or a digit. A preserved.
ISALNUM:JSR  ISDIGIT
        JC   ian_r
        JMP  ISLETTER
ian_r:  RTS

; VARFIND - look NMBUF up in VARTAB: P1 = its entry, VARIDX = its index. An
;   absent name gets a new zeroed entry.
VARFIND:LDA  #0
        STA  VARIDX
        LDP1 #VARTAB
vf_lp:  LDA  VARIDX
        LDB  VARCNT
        CMP
        JZ   vf_new
        LDA  (P1)
        LDB  NMBUF
        CMP
        JNZ  vf_nx
        LDA  (P1+1)
        LDB  NMBUF+1
        CMP
        JNZ  vf_nx
        LDA  (P1+2)
        LDB  NMBUF+2
        CMP
        JNZ  vf_nx
        LDA  (P1+3)
        LDB  NMBUF+3
        CMP
        JNZ  vf_nx
        LDA  (P1+4)
        LDB  NMBUF+4
        CMP
        JNZ  vf_nx
        LDA  (P1+5)
        LDB  NMBUF+5
        CMP
        JNZ  vf_nx
        RTS                  ; found
vf_nx:  LDA  VARIDX
        INC
        STA  VARIDX
        LEAW CUR,(P1+8)
        LPW1 CUR
        JMP  vf_lp
vf_new: LDA  VARCNT          ; append (P1 is already the slot)
        LDB  #NVARS
        CMP
        JC   SYNERR          ; table full
        STW  (P1+0),NMBUF
        STW  (P1+2),NMBUF+2
        STW  (P1+4),NMBUF+4
        LDA  #0
        STA  (P1+6)
        STA  (P1+7)
        LDA  VARCNT
        INC
        STA  VARCNT
        RTS

; IDXADDR - VARIDX -> P1 = that variable's entry
IDXADDR:LDA  VARIDX
        SHL
        SHL
        SHL
        TAP1L
        LDA  #>VARTAB
        TAP1H
        RTS

;==============================================================================
; 16-bit multiply / divide (shift-add / restoring) -- operands NUM1, NUM2
;==============================================================================
; MUL16 - NUM1 = NUM1 * NUM2 (low 16 bits). NUM2 is consumed.
MUL16:  LDW  ACC,#0
        LDA  #16
        STA  MCNT
mu_l:   ADDW ACC,ACC         ; result <<= 1
        ADDW NUM2,NUM2       ; the next multiplier bit, MSB first -> C
        JNC  mu_sk
        ADDW ACC,NUM1
mu_sk:  LDA  MCNT
        DEC
        STA  MCNT
        JNZ  mu_l
        MOVW NUM1,ACC
        RTS

; DIV16 - NUM1 = NUM1 / NUM2 (unsigned quotient), REM = the remainder. /0 -> 0.
DIV16:  LDW  REM,#0
        LDA  NUM2
        LDB  NUM2+1
        OR
        JNZ  dv_ok
        LDW  NUM1,#0
        RTS
dv_ok:  LDA  #16
        STA  MCNT
dv_l:   ADDW NUM1,NUM1       ; dividend MSB -> C (bit 0 becomes the quotient bit)
        LDA  #0
        ROL
        STA  CYTMP           ; that bit
        ADDW REM,REM
        LDA  REM
        LDB  CYTMP
        OR
        STA  REM             ; REM = REM*2 + bit
        CMPW REM,NUM2
        JNC  dv_lt
        SUBW REM,NUM2
        INCW NUM1            ; quotient bit
dv_lt:  LDA  MCNT
        DEC
        STA  MCNT
        JNZ  dv_l
        RTS

;==============================================================================
; Numbers: decimal / hex in, decimal out
;==============================================================================
; PARSEDEC - digits at (P2) -> LNUM (P2 left at the first non-digit). Uses NUM2.
PARSEDEC:
        LDW  LNUM,#0
pd_l:   LDA  (P2)
        JSR  ISDIGIT
        JNC  pd_d
        LDB  #'0'
        SUB
        STA  DIG
        INP2
        ADDW LNUM,LNUM       ; x2
        MOVW NUM2,LNUM
        ADDW LNUM,LNUM       ; x4
        ADDW LNUM,LNUM       ; x8
        ADDW LNUM,NUM2       ; x10
        LDA  LNUM
        LDB  DIG
        ADD
        STA  LNUM
        JNC  pd_l
        LDA  LNUM+1
        INC
        STA  LNUM+1
        JMP  pd_l
pd_d:   RTS

; PARSEHEX - hex digits at (P2) (after the "0x") -> RESULT; wraps past 4 digits.
PARSEHEX:
        LDW  LNUM,#0
px_l:   LDA  (P2)
        JSR  HEXVAL
        JNC  px_d
        STA  DIG
        INP2
        ADDW LNUM,LNUM
        ADDW LNUM,LNUM
        ADDW LNUM,LNUM
        ADDW LNUM,LNUM
        LDA  LNUM
        LDB  DIG
        OR
        STA  LNUM
        JMP  px_l
px_d:   MOVW RESULT,LNUM
        RTS

; HEXVAL - A = character -> A = its hex value with C=1; C=0 if not a hex digit.
HEXVAL: LDB  #'0'
        CMP
        JNC  hv_no
        LDB  #$3A
        CMP
        JNC  hv_dig          ; '0'..'9'
        JSR  UPCHAR
        LDB  #'A'
        CMP
        JNC  hv_no
        LDB  #'G'
        CMP
        JC   hv_no
        LDB  #$37            ; 'A' - 10
        SUB                  ; leaves C=1
        RTS
hv_dig: LDB  #'0'
        SUB                  ; leaves C=1
        RTS
hv_no:  CLC
        RTS

; PRDEC - print LNUM as SIGNED decimal through PUTCH (LNUM is consumed)
PRDEC:  LDA  LNUM+1
        LDB  #$80
        AND
        JZ   PRDECU
        LDA  #'-'
        JSR  PUTCH
        XORW LNUM,#$FFFF
        INCW LNUM
; PRDECU - print LNUM as UNSIGNED decimal, no leading zeros
PRDECU: LDA  #1
        STA  LZ
        LDP1 #POW10
        LDA  #5
        STA  PCNT
prl:    LDW  NUM2,(P1+0)     ; the next power of ten
        INP1
        INP1
        LDA  #0
        STA  DIG
prs:    CMPW LNUM,NUM2
        JNC  pre
        SUBW LNUM,NUM2
        LDA  DIG
        INC
        STA  DIG
        JMP  prs
pre:    LDA  PCNT
        LDB  #1
        CMP
        JZ   prf             ; the units digit always prints
        LDA  DIG
        JNZ  prsh
        LDA  LZ
        JNZ  prsk            ; a leading zero
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
; PROGRAM TEXT: enter a line, LIST, tokenize
;==============================================================================
; DOLINE - a numbered line: LNUM = the number, then insert / replace / delete
DOLINE: JSR  PARSEDEC
        JSR  SKIPSP
        LEAW TSRC,(P2+0)     ; the text
        LDA  #0
        STA  TXTMT
        LDA  (P2)
        JNZ  dl1
        LDA  #1
        STA  TXTMT           ; empty text: delete the line
dl1:    JSR  EDIT
        JMP  REPL

; EDIT - rebuild PROG into PBUF inserting / replacing / deleting LNUM, copy back
EDIT:   LDA  #0
        STA  INSF
        LDP1 #PROG
        LDP2 #PBUF
ed_loop:LDW  RNUM,(P1+0)
        INP1
        INP1
        LDA  RNUM
        LDB  RNUM+1
        OR
        JZ   ed_end          ; end marker
        LDA  INSF
        JNZ  ed_copy         ; the new line is already placed: copy the rest
        CMPW RNUM,LNUM
        JNC  ed_copy         ; RNUM < LNUM: keep this record
        JNZ  ed_ins          ; RNUM > LNUM (high bytes differ)
        LDA  RNUM
        LDB  LNUM
        CMP
        JZ   ed_repl
ed_ins: JSR  EMITNEW         ; RNUM > LNUM: the new line goes before this one
        LDA  #1
        STA  INSF
        JMP  ed_copy
ed_repl:JSR  EMITNEW         ; same number: the new text replaces the old
        LDA  #1
        STA  INSF
ed_skip:LDA  (P1)+           ; drop the old text
        JNZ  ed_skip
        JMP  ed_loop
ed_copy:STW  (P2+0),RNUM
        INP2
        INP2
ed_ct:  LDA  (P1)+
        STA  (P2)+
        JNZ  ed_ct
        JMP  ed_loop
ed_end: LDA  INSF
        JNZ  ed_wm
        JSR  EMITNEW         ; append it
ed_wm:  LDA  #0
        STA  (P2)+
        STA  (P2)
        JMP  PB2PROG

; EMITNEW - write the entered line (LNUM + text) at (P2); nothing if deleting
EMITNEW:LDA  TXTMT
        JNZ  en_done
        STW  (P2+0),LNUM
        INP2
        INP2
        LEAW SAVE1,(P1+0)
        LPW1 TSRC
en_ct:  LDA  (P1)+
        STA  (P2)+
        JNZ  en_ct
        LPW1 SAVE1
en_done:RTS

; PB2PROG - copy PBUF back to PROG up to and including the 00,00 marker
PB2PROG:LDP1 #PBUF
        LDP2 #PROG
pp_l:   LDA  (P1)+
        STA  (P2)+
        STA  TMPC
        LDA  (P1)+
        STA  (P2)+
        LDB  TMPC
        OR
        JZ   pp_done
pp_t:   LDA  (P1)+
        STA  (P2)+
        JNZ  pp_t
        JMP  pp_l
pp_done:RTS

; NEWPROG - an empty program (the bare 00,00 marker) and no variables
NEWPROG:LDW  PROG,#0
        LDA  #0
        STA  VARCNT
        STA  SVARCNT
        RTS

; LIST - print every stored line. PRKW walks the keyword table with P2, so the
;   parse cursor is kept on the stack.
LIST:   TPA2L
        PHA
        TPA2H
        PHA
        LDP1 #PROG
ls_l:   LDW  LNUM,(P1+0)
        INP1
        INP1
        LDA  LNUM
        LDB  LNUM+1
        OR
        JZ   ls_done
        LEAW SAVE1,(P1+0)    ; PRDECU uses P1
        JSR  PRDECU          ; line numbers are unsigned
        LDA  #' '
        JSR  PUTC
        LPW1 SAVE1
        JSR  PRTEXT          ; P1 -> the next record
        JSR  CRLF
        JMP  ls_l
ls_done:PLA
        TAP2H
        PLA
        TAP2L
        RTS

; PRTEXT - print the tokenized text at (P1), expanding tokens to keywords;
;   leaves P1 just past the 00 terminator.
PRTEXT: LDA  (P1)+
        JZ   pt_done
        STA  TMPC
        LDB  #$80
        AND
        JZ   pt_lit
        LDA  TMPC
        JSR  PRKW
        JMP  PRTEXT
pt_lit: LDA  TMPC
        JSR  PUTC
        JMP  PRTEXT
pt_done:RTS

; PRKW - print the keyword whose token is A. Walks KWTAB with P2.
PRKW:   STA  TOKW
        LDP2 #KWTAB
pk_e:   LEAW RP,(P2+0)       ; this entry's letters
pk_sc:  LDA  (P2)+
        STA  TMPC
        LDB  #$80
        AND
        JZ   pk_sc           ; skip the letters to the token byte
        LDA  TMPC
        LDB  TOKW
        CMP
        JZ   pk_pr
        LDA  (P2)
        JZ   pk_d            ; table end
        JMP  pk_e
pk_pr:  LPW2 RP
pk_pl:  LDA  (P2)+
        STA  TMPC
        LDB  #$80
        AND
        JNZ  pk_d            ; the token byte ends the word
        LDA  TMPC
        JSR  PUTC
        JMP  pk_pl
pk_d:   RTS

; CRUNCH - tokenize LBUF in place: keywords -> token bytes, strings and
;   everything else literal. Only a letter can start a keyword.
CRUNCH: LDP1 #LBUF           ; read cursor
        LDW  WP,#LBUF        ; write cursor (tokens shrink, so in place is safe)
cr_lp:  LDA  (P1)
        JZ   cr_end
        LDB  #'"'
        CMP
        JZ   cr_str
        JSR  ISLETTER
        JNC  cr_chr
        JSR  MATCHKW         ; a keyword at (P1)? (P1 past it if so)
        LDA  MATCHF
        JZ   cr_chr
        LDA  TOKEN
        JSR  CR_PUTW
        JMP  cr_lp
cr_chr: LDA  (P1)+
        JSR  CR_PUTW
        JMP  cr_lp
cr_str: LDA  (P1)+           ; the opening quote
        JSR  CR_PUTW
cr_s1:  LDA  (P1)
        JZ   cr_end
        LDB  #'"'
        CMP
        JZ   cr_sx
        LDA  (P1)+
        JSR  CR_PUTW
        JMP  cr_s1
cr_sx:  LDA  (P1)+           ; the closing quote, then tokenizing resumes
        JSR  CR_PUTW
        JMP  cr_lp
cr_end: LDA  #0              ; the terminator, then CR_PUTW returns for CRUNCH
CR_PUTW:LPW2 WP              ; write A at (WP), WP++
        STA  (P2)+
        LEAW WP,(P2+0)
        RTS

; MATCHKW - a keyword at (P1)? MATCHF=1 + TOKEN with P1 past it; else MATCHF=0
;   and P1 unchanged. A letter or digit right after the letters means a longer
;   identifier (TOTAL, FORK), not a keyword. Walks KWTAB with P2.
MATCHKW:LEAW RP,(P1+0)
        LDP2 #KWTAB
mk_e:   LDA  (P2)
        JZ   mk_no           ; end of table
mk_in:  LDA  (P2)
        STA  TMPC
        LDB  #$80
        AND
        JNZ  mk_hit          ; the token byte: every letter matched
        LDA  (P1)
        LDB  TMPC
        CMP
        JNZ  mk_sk
        INP1
        INP2
        JMP  mk_in
mk_hit: LDA  (P1)
        JSR  ISALNUM
        JC   mk_no
        LDA  TMPC
        STA  TOKEN
        LDA  #1
        STA  MATCHF
        RTS
mk_sk:  LDA  (P2)+           ; skip the rest of this entry (letters + token)
        LDB  #$80
        AND
        JZ   mk_sk
        LPW1 RP
        JMP  mk_e
mk_no:  LDA  #0
        STA  MATCHF
        LPW1 RP
        RTS

;==============================================================================
; STRINGS -- a value is [len byte][data...], length <= SLEN. String variables
; (NAME$) live in SVARTAB (SVENT-byte entries: name[6] + len + data); their
; value is (entry+6). Work buffers: STRACC (SEVAL's result), STRTMP (one term),
; STRARG (a function's string argument), STRCMP (a comparison's left side).
;==============================================================================
; SPEEK - does (P2) begin a STRING-valued expression? MATCHF=1/0; P2 unchanged.
;   Yes for a "literal", a string function, or an identifier followed by '$'.
SPEEK:  JSR  SKIPSP
        LDA  #0
        STA  MATCHF
        LDA  (P2)
        LDB  #'"'
        CMP
        JZ   sp_yes
        LDB  #TOK_CHRS
        CMP
        JZ   sp_yes
        LDB  #TOK_LEFTS
        CMP
        JZ   sp_yes
        LDB  #TOK_RIGHTS
        CMP
        JZ   sp_yes
        LDB  #TOK_MIDS
        CMP
        JZ   sp_yes
        LDB  #TOK_STRS
        CMP
        JZ   sp_yes
        JSR  ISLETTER
        JNC  sp_no
        TPA2L                ; walk a copy of P2 over the identifier
        TAP1L
        TPA2H
        TAP1H
sp_w:   LDA  (P1)+
        JSR  ISALNUM
        JC   sp_w
        LDB  #'$'            ; the first non-alphanumeric character
        CMP
        JNZ  sp_no
sp_yes: LDA  #1
        STA  MATCHF
sp_no:  RTS

; SVARGET - parse NAME$ at (P2) (consumed, '$' included), find / create the
;   string variable: P1 = its entry, MATCHF=1. MATCHF=0 if not NAME$.
SVARGET:JSR  PARSENAME
        LDA  MATCHF
        JZ   svg_ret
        LDA  (P2)
        LDB  #'$'
        CMP
        JNZ  svg_bad
        INP2
        JSR  SVARFIND
        LDA  #1
        STA  MATCHF
        RTS
svg_bad:LDA  #0
        STA  MATCHF
svg_ret:RTS

; SVENTADDR - P1 = SVARTAB + SI*SVENT (40 = 32 + 8). Uses NUM1/NUM2.
SVENTADDR:
        LDA  SI
        SHL
        SHL
        SHL                  ; SI*8 (SI < 16)
        STA  NUM1
        LDA  #0
        STA  NUM1+1
        MOVW NUM2,NUM1
        ADDW NUM1,NUM1       ; *16
        ADDW NUM1,NUM1       ; *32
        ADDW NUM1,NUM2       ; *40
        ADDW NUM1,#SVARTAB
        LPW1 NUM1
        RTS

; SVARFIND - look NMBUF up in SVARTAB: P1 = its entry, SVIDX = its index. An
;   absent name gets a new empty entry.
SVARFIND:
        LDA  #0
        STA  SI
svf_lp: LDA  SI
        LDB  SVARCNT
        CMP
        JZ   svf_new
        JSR  SVENTADDR
        LDA  (P1)
        LDB  NMBUF
        CMP
        JNZ  svf_nx
        LDA  (P1+1)
        LDB  NMBUF+1
        CMP
        JNZ  svf_nx
        LDA  (P1+2)
        LDB  NMBUF+2
        CMP
        JNZ  svf_nx
        LDA  (P1+3)
        LDB  NMBUF+3
        CMP
        JNZ  svf_nx
        LDA  (P1+4)
        LDB  NMBUF+4
        CMP
        JNZ  svf_nx
        LDA  (P1+5)
        LDB  NMBUF+5
        CMP
        JNZ  svf_nx
        LDA  SI
        STA  SVIDX
        RTS
svf_nx: LDA  SI
        INC
        STA  SI
        JMP  svf_lp
svf_new:LDA  SVARCNT
        LDB  #NSVARS
        CMP
        JC   SYNERR          ; table full
        STA  SVIDX
        JSR  SVENTADDR       ; (SI = SVARCNT)
        STW  (P1+0),NMBUF
        STW  (P1+2),NMBUF+2
        STW  (P1+4),NMBUF+4
        LDA  #0
        STA  (P1+6)          ; empty value
        LDA  SVARCNT
        INC
        STA  SVARCNT
        RTS

; SMOVE - copy the string at (SPA) to (SPD), len byte + data. Preserves P2.
SMOVE:  TPA2L
        PHA
        TPA2H
        PHA
        LPW1 SPA
        LPW2 SPD
        LDA  (P1)+
        STA  (P2)+
        STA  TMPC
        JZ   smv_d           ; (Z from the load: an empty string)
smv_l:  LDA  (P1)+
        STA  (P2)+
        LDA  TMPC
        DEC
        STA  TMPC
        JNZ  smv_l
smv_d:  PLA
        TAP2H
        PLA
        TAP2L
        RTS

; SCPYLIT - copy the "..." literal at (P2) (P2 at the opening quote) into
;   (SPD), capped at SLEN, consuming through the closing quote.
SCPYLIT:INP2
        LPW1 SPD
        INP1                 ; past the len byte
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
        JC   scl_sk          ; full: consume, don't store
        INC
        STA  SI
        LDA  (P2)
        STA  (P1)+
scl_sk: INP2
        JMP  scl_l
scl_cl: INP2
scl_end:LPW1 SPD
        LDA  SI
        STA  (P1)
        RTS

; SAPP - append the string at (SPA) onto (SPD), capping the result at SLEN.
;   Preserves P2.
SAPP:   TPA2L
        PHA
        TPA2H
        PHA
        LPW1 SPA
        LDA  (P1)+
        STA  SJ              ; source length
        LPW2 SPD
        LDA  (P2)+
        STA  SI              ; destination length ...
        STA  TMPC
sap_ad: LDA  TMPC            ; ... advance P2 past its data
        JZ   sap_go
        INP2
        DEC
        STA  TMPC
        JMP  sap_ad
sap_go: LDA  SJ
        JZ   sap_fin
        LDA  SI
        LDB  #SLEN
        CMP
        JC   sap_fin         ; destination full
        INC
        STA  SI
        LDA  (P1)+
        STA  (P2)+
        LDA  SJ
        DEC
        STA  SJ
        JMP  sap_go
sap_fin:LPW1 SPD
        LDA  SI
        STA  (P1)
        PLA
        TAP2H
        PLA
        TAP2L
        RTS

; SPUT - print the string in STRACC (through PUTCH: console, file or STR$ sink)
SPUT:   LDP1 #STRACC
        LDA  (P1)+
        STA  TMPC
spt_l:  LDA  TMPC
        JZ   spt_d
        DEC
        STA  TMPC
        LDA  (P1)+
        JSR  PUTCH
        JMP  spt_l
spt_d:  RTS

; P1ADDA - P1 = P1 + A (unsigned byte)
P1ADDA: STA  TMPC
        TPA1L
        LDB  TMPC
        ADD
        TAP1L
        TPA1H
        JNC  p1a_r
        INC
        TAP1H
p1a_r:  RTS

; SUBSTR - STRTMP = SJ characters of STRARG from 0-based SI, both clamped to
;   the source. Used by LEFT$/RIGHT$/MID$. Preserves P2.
SUBSTR: TPA2L
        PHA
        TPA2H
        PHA
        LDA  STRARG          ; L
        STA  SLENV
        LDA  SI
        LDB  SLENV
        CMP
        JC   sub_empty       ; SI >= L
        LDA  SLENV           ; available = L - SI
        LDB  SI
        SUB
        STA  SLENV
        LDA  SJ
        LDB  SLENV
        CMP
        JNC  sub_pos         ; SJ < available
        LDA  SLENV
        STA  SJ
sub_pos:LDP1 #STRARG+1
        LDA  SI
        JSR  P1ADDA
        LDP2 #STRTMP+1
        LDA  SJ
        STA  TMPC
sub_cp: LDA  TMPC
        JZ   sub_fin
        DEC
        STA  TMPC
        LDA  (P1)+
        STA  (P2)+
        JMP  sub_cp
sub_fin:LDA  SJ
        STA  STRTMP
        JMP  sub_done
sub_empty:
        LDA  #0
        STA  STRTMP
sub_done:
        PLA
        TAP2H
        PLA
        TAP2L
        RTS

; CLAMPN - SJ = RESULT clamped to 0..SLEN (negative -> 0, > 255 -> SLEN)
CLAMPN: LDA  RESULT+1
        JZ   cn_lo
        LDB  #$80
        AND
        JZ   cn_big
        LDA  #0
        STA  SJ
        RTS
cn_big: LDA  #SLEN
        STA  SJ
        RTS
cn_lo:  LDA  RESULT
        STA  SJ
        RTS

; SARG - a string variable or literal at (P2) -> (SPD)
SARG:   JSR  SKIPSP
        LDA  (P2)
        LDB  #'"'
        CMP
        JZ   SCPYLIT
        JSR  SVARGET
        LDA  MATCHF
        JZ   SYNERR
        LEAW SPA,(P1+6)
        JMP  SMOVE

; STERM - one string term at (P2) -> STRTMP
STERM:  JSR  SKIPSP
        LDW  SPD,#STRTMP
        LDA  (P2)
        LDB  #'"'
        CMP
        JZ   SCPYLIT
        LDB  #TOK_CHRS
        CMP
        JZ   stm_chr
        LDB  #TOK_LEFTS
        CMP
        JZ   stm_left
        LDB  #TOK_RIGHTS
        CMP
        JZ   stm_right
        LDB  #TOK_MIDS
        CMP
        JZ   stm_mid
        LDB  #TOK_STRS
        CMP
        JZ   stm_strs
        JMP  SARG            ; a string variable
stm_chr:INP2                 ; CHR$(n)
        JSR  PARGET
        LDA  #1
        STA  STRTMP
        LDA  RESULT
        STA  STRTMPD
        RTS
stm_strs:                    ; STR$(n): PRDEC into the string sink
        INP2
        JSR  PARGET
        MOVW LNUM,RESULT
        LDW  STRSP,#STRTMPD
        LDA  #0
        STA  STRSN
        LDA  #1
        STA  STRSINK
        JSR  PRDEC
        LDA  #0
        STA  STRSINK
        LDA  STRSN
        STA  STRTMP
        RTS
; STM_OPEN - LEFT$/RIGHT$/MID$: consume the token and '(', the string argument
;   -> STRARG, ',', then the first numeric argument -> RESULT
STM_OPEN:
        INP2
        JSR  EXPECTLP
        LDW  SPD,#STRARG
        JSR  SARG
        JSR  EXPECTCOMMA
        JMP  EXPR
; STM_CLOSE - the substring (STRARG[SI..], SJ chars) -> STRTMP, then ')'
STM_CLOSE:
        JSR  SUBSTR
        JMP  EXPECTRP
stm_left:
        JSR  STM_OPEN
        JSR  CLAMPN          ; SJ = n
        LDA  #0
        STA  SI
        JMP  STM_CLOSE
stm_right:
        JSR  STM_OPEN
        JSR  CLAMPN          ; SJ = n
        LDA  STRARG          ; L
        STA  SLENV
        LDA  SJ
        LDB  SLENV
        CMP
        JC   str_all         ; n >= L: the whole string
        LDA  SLENV           ; SI = L - n
        LDB  SJ
        SUB
        STA  SI
        JMP  STM_CLOSE
str_all:LDA  #0
        STA  SI
        JMP  STM_CLOSE
stm_mid:JSR  STM_OPEN        ; RESULT = i (1-based)
        LDA  RESULT+1
        JNZ  mid_hi
        LDA  RESULT
        JZ   mid_zero        ; i = 0 counts as 1
        DEC
        STA  SI
        JMP  mid_len
mid_zero:
        LDA  #0
        STA  SI
        JMP  mid_len
mid_hi: LDB  #$80
        AND
        JZ   mid_big
        LDA  #0              ; negative -> from the start
        STA  SI
        JMP  mid_len
mid_big:LDA  #SLEN           ; a large start -> past the end
        STA  SI
mid_len:JSR  SKIPSP          ; optional length
        LDA  (P2)
        LDB  #','
        CMP
        JZ   mid_hasl
        LDA  #SLEN           ; none: to the end
        STA  SJ
        JMP  STM_CLOSE
mid_hasl:
        INP2
        JSR  EXPR
        JSR  CLAMPN
        JMP  STM_CLOSE

; SEVAL - a string expression at (P2): STERM { '+' STERM } -> STRACC
SEVAL:  LDA  #0
        STA  STRACC
        JSR  STERM
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
sev_app:LDW  SPA,#STRTMP
        LDW  SPD,#STRACC
        JMP  SAPP

; EVALSTR - a string comparison in a numeric context: SEVAL relop SEVAL -> 1/0
EVALSTR:JSR  SEVAL           ; left -> STRACC -> STRCMP
        LDW  SPA,#STRACC
        LDW  SPD,#STRCMP
        JSR  SMOVE
        JSR  RELOPP
        JC   SYNERR          ; a string needs an operator here
        JSR  SEVAL           ; right -> STRACC
        JSR  SCMP
        JMP  ev_res

; SCMP - REL = the relation of STRCMP to STRACC (lexicographic; with an equal
;   prefix the shorter string is less). Preserves P2.
SCMP:   TPA2L
        PHA
        TPA2H
        PHA
        LDP1 #STRCMP+1
        LDP2 #STRACC+1
        LDA  STRCMP
        STA  SLENV           ; La
        LDA  STRACC
        STA  SI              ; Lb
        LDB  SLENV
        CMP
        JC   sc_mina         ; Lb >= La: the common length is La
        STA  SJ
        JMP  sc_lp
sc_mina:LDA  SLENV
        STA  SJ
sc_lp:  LDA  SJ
        JZ   sc_leneq
        DEC
        STA  SJ
        LDA  (P2)+
        STA  TMPC            ; b
        LDA  (P1)+           ; a
        LDB  TMPC
        CMP
        JZ   sc_lp
        JC   sc_gt           ; a > b
sc_lt:  LDA  #R_LT
        JMP  sc_set
sc_gt:  LDA  #R_GT
        JMP  sc_set
sc_leneq:
        LDA  SLENV
        LDB  SI
        CMP
        JZ   sc_eq
        JC   sc_gt
        JMP  sc_lt
sc_eq:  LDA  #R_EQ
sc_set: STA  REL
        PLA
        TAP2H
        PLA
        TAP2L
        RTS

; FN_SARG - LEN/ASC: '(' string argument -> STRARG ')'
FN_SARG:JSR  EXPECTLP
        LDW  SPD,#STRARG
        JSR  SARG
        JMP  EXPECTRP

fa_len: JSR  FN_SARG
        LDA  STRARG
        STA  RESULT
        LDA  #0
        STA  RESULT+1
        RTS
fa_asc: JSR  FN_SARG
        LDA  STRARG
        JZ   fa_asc0         ; empty -> 0
        LDA  STRARG+1
fa_asc0:STA  RESULT
        LDA  #0
        STA  RESULT+1
        RTS

; VAL(s$) - a signed decimal parsed from the start of the string; stops at the
;   first non-digit; 0 if none.
fa_val: JSR  FN_SARG
        LDP1 #STRARG+1
        LDA  STRARG
        JSR  P1ADDA
        LDA  #0
        STA  (P1)            ; NUL after the data so PARSEDEC stops
        TPA2L
        STA  GTMP
        TPA2H
        STA  GTMP+1
        LDP2 #STRARG+1
        JSR  SKIPSP
        LDA  #0
        STA  TMPC            ; sign
        LDA  (P2)
        LDB  #'-'
        CMP
        JNZ  fv_ns
        LDA  #1
        STA  TMPC
        INP2
        JMP  fv_pd
fv_ns:  LDB  #'+'
        CMP
        JNZ  fv_pd
        INP2
fv_pd:  JSR  PARSEDEC
        MOVW RESULT,LNUM
        LDA  TMPC
        JZ   fv_pos
        JSR  NEGRES
fv_pos: LPW2 GTMP
        RTS

; EOF(n) - 1 if the input channel is at its end (or not open for input)
fa_eof: JSR  PARGET          ; the channel number is parsed and ignored
        LDA  FMODE
        LDB  #1
        CMP
        JNZ  fe_true
        LDA  FLOOKC
        JZ   fe_false
fe_true:LDW  RESULT,#1
        RTS
fe_false:
        LDW  RESULT,#0
        RTS

;==============================================================================
; DATA FILES -- one sequential channel over the BIOS byte streams. PRINT#
; writes one value + CR per record, INPUT# reads one CR-delimited record.
;==============================================================================
; SETFNAME - evaluate the file name string at (P2) and resolve it (relative
;   to the OS CWD) into a directory + leaf FNAME. Preserves P2.
SETFNAME:
        JSR  SEVAL           ; STRACC = the name
        TPA2L
        PHA
        TPA2H
        PHA
        LDP1 #STRACC+1
        LDA  STRACC
        JSR  P1ADDA
        LDA  #0
        STA  (P1)            ; NUL-terminate the data in place
        LDP1 #STRACC+1
        JSR  APATH
        JSR  FRESOLVE
        PLA
        TAP2H
        PLA
        TAP2L
        RTS

; OPEN name$ [FOR] OUTPUT|INPUT
DOOPEN: INP2
        JSR  SETFNAME
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_FOR
        CMP
        JNZ  dop_mode
        INP2
        JSR  SKIPSP
dop_mode:
        LDA  (P2)
        LDB  #TOK_OUTPUT
        CMP
        JZ   dop_out
        LDB  #TOK_INPUT
        CMP
        JNZ  SYNERR
        INP2
        LEAW GTMP,(P2+0)
        LDP1 #PBUF           ; the read stream's 512-byte buffer
        JSR  FOPEN
        JC   dop_nf
        LDA  #1
        STA  FMODE
        JSR  FPRIME          ; prime the EOF lookahead
        LPW2 GTMP
        RTS
dop_out:INP2
        LEAW GTMP,(P2+0)
        JSR  FWOPEN
        LDA  #2
        STA  FMODE
        LPW2 GTMP
        RTS
dop_nf: LDA  #0
        STA  FMODE
        LDP1 #MNOFILE
        JSR  PUTS
        LPW2 GTMP
        RTS

; CLOSE - commit a write channel / drop a read channel
DOCLOSE:INP2
        LDA  FMODE
        LDB  #2
        CMP
        JNZ  dcl_ni
        LEAW GTMP,(P2+0)
        JSR  FCLOSE
        LPW2 GTMP
dcl_ni: LDA  #0
        STA  FMODE
        RTS

; PRINT# value - one record: the value's text and a CR. Entered at the '#'.
DOPRINTF:
        LDA  FMODE
        LDB  #2
        CMP
        JNZ  SYNERR          ; not open for output
        INP2
        LDA  #1
        STA  OUTFILE
        JSR  SKIPSP
        LDA  (P2)
        JZ   dpf_cr          ; a bare PRINT#: an empty record
        JSR  SPEEK
        LDA  MATCHF
        JNZ  dpf_str
        JSR  EVAL
        MOVW LNUM,RESULT
        JSR  PRDEC
        JMP  dpf_cr
dpf_str:JSR  SEVAL
        JSR  SPUT
dpf_cr: LDA  #$0D
        JSR  FPUTB
        LDA  #0
        STA  OUTFILE
        RTS

; INPUT# var | var$ - one CR-delimited record. Entered at the '#'.
DOINPUTF:
        LDA  FMODE
        LDB  #1
        CMP
        JNZ  SYNERR          ; not open for input
        INP2
        JSR  SKIPSP
        JSR  SPEEK
        LDA  MATCHF
        JNZ  dif_str
        JSR  VARGET
        LDA  MATCHF
        JZ   SYNERR
        LEAW SAVE1,(P1+6)
        LEAW GTMP,(P2+0)
        JSR  FREADREC        ; STRACC = the record, NUL-terminated
        LDP2 #STRACC+1
        JSR  SKIPSP
        JSR  PARSEDEC
        LPW1 SAVE1
        STW  (P1+0),LNUM
        LPW2 GTMP
        RTS
dif_str:JSR  SVARGET
        LDA  MATCHF
        JZ   SYNERR
        LEAW SPD,(P1+6)
        LEAW GTMP,(P2+0)
        JSR  FREADREC
        LDW  SPA,#STRACC
        JSR  SMOVE
        LPW2 GTMP
        RTS

; FPRIME - prime the one-byte read-ahead when a channel opens for input, so
;   EOF() can report the end BEFORE the read that would hit it.
FPRIME: LDA  #0
        STA  FLOOKC
        JSR  FGETB
        JC   fpr_eof
        STA  FLOOK
        RTS
fpr_eof:LDA  #1
        STA  FLOOKC
        RTS

; GNB - the next input byte via the lookahead: A = byte, C=1 at EOF.
GNB:    LDA  FLOOKC
        JNZ  gnb_eof
        LDA  FLOOK
        STA  TMPC
        JSR  FGETB           ; refill the lookahead
        JC   gnb_reof
        STA  FLOOK
        LDA  TMPC
        CLC
        RTS
gnb_reof:
        LDA  #1
        STA  FLOOKC
        LDA  TMPC
        CLC
        RTS
gnb_eof:SEC
        RTS

; FREADREC - the next CR-delimited record -> STRACC (len + data, capped at
;   SLEN, NUL-terminated after the data). The write cursor lives in CUR:
;   FGETB may clobber both pointers on a sector refill.
FREADREC:
        LDW  CUR,#STRACC+1
        LDA  #0
        STA  SI
frr_l:  JSR  GNB
        JC   frr_end
        LDB  #$0D
        CMP
        JZ   frr_end         ; end of the record
        STA  TMPC
        LDA  SI
        LDB  #SLEN
        CMP
        JC   frr_l           ; too long: discard the overflow
        INC
        STA  SI
        LPW2 CUR
        LDA  TMPC
        STA  (P2)+
        LEAW CUR,(P2+0)
        JMP  frr_l
frr_end:LPW2 CUR
        LDA  #0
        STA  (P2)
        LDA  SI
        STA  STRACC
        RTS

;==============================================================================
; CHECKLINE - structural check of the just-crunched line in LBUF: for each
; ':'-separated statement a legal leader, balanced parentheses and terminated
; strings. A REM ends the check. Forward references are NOT checked (RUN
; reports them). C=1 and "?SYNTAX ERROR" on failure, C=0 silent on success.
;==============================================================================
CHECKLINE:
        LDP2 #LBUF
        JSR  SKIPSP
ckl_dg: LDA  (P2)            ; skip a leading line number
        JSR  ISDIGIT
        JNC  ckl_st
        INP2
        JMP  ckl_dg
ckl_st: LDA  #0              ; a statement: parentheses balance within it
        STA  CKDEP
        JSR  SKIPSP
        JSR  CKLEAD
        JC   ckl_bad
        LDA  CKREM
        JNZ  ckl_ok          ; REM: the rest is free-form
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
ckl_nx: INP2
        JMP  ckl_lp
ckl_op: LDA  CKDEP
        INC
        STA  CKDEP
        JMP  ckl_nx
ckl_cp: LDA  CKDEP
        JZ   ckl_bad         ; ')' with nothing open
        DEC
        STA  CKDEP
        JMP  ckl_nx
ckl_col:LDA  CKDEP
        JNZ  ckl_bad         ; ':' with a '(' still open
        INP2
        JMP  ckl_st
ckl_str:INP2
cks_l:  LDA  (P2)
        JZ   ckl_bad         ; unterminated string
        LDB  #'"'
        CMP
        JZ   ckl_nx          ; past the closing quote
        INP2
        JMP  cks_l
ckl_eol:LDA  CKDEP
        JNZ  ckl_bad
ckl_ok: CLC
        RTS
ckl_bad:LDP1 #MSYN
        JSR  PUTS
        SEC
        RTS

; CKLEAD - may the token / character at (P2) START a statement? A statement
;   keyword (its STMTTAB entry is a handler, not st_what), a GL verb, or a
;   letter (implicit LET) may; a function / modifier keyword, a digit or an
;   operator may not. CKREM=1 for REM. C=1 if illegal; P2 unchanged.
CKLEAD: LDA  #0
        STA  CKREM
        LDA  (P2)
        JZ   ckd_ok          ; an empty statement
        LDB  #TOK_REM
        CMP
        JZ   ckd_rem
        LDB  #GLV0
        SUB
        JNC  ckd_low
        LDB  #GLVN
        CMP
        JC   ckd_bad         ; GLRD / unassigned
ckd_ok: CLC                  ; a GL verb
        RTS
ckd_low:LDA  (P2)
        LDB  #$80
        SUB
        JNC  ckd_alpha
        SHL                  ; the statement table decides
        LDB  #<STMTTAB
        ADD
        TAP1L
        LDA  #0
        ROL
        LDB  #>STMTTAB
        ADD
        TAP1H
        LDW  CUR,(P1+0)
        CMPW CUR,#st_what
        JZ   ckd_bad
        CLC
        RTS
ckd_rem:LDA  #1
        STA  CKREM
        CLC
        RTS
ckd_alpha:
        LDA  (P2)
        JSR  ISLETTER
        JNC  ckd_bad
        CLC
        RTS
ckd_bad:SEC
        RTS

;==============================================================================
; Keyword table: each entry = ASCII letters then the token byte (>= $80);
; a 00 ends the table. The GL verbs come first (generated, longest-first)
; so POINT3 / CLEARS are matched before POINT / CLS.
;==============================================================================
KWTAB:
        .include "glkwtab.inc"
        .ascii "PRINT"
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
        .byte $24,$A2               ; STR$
        .ascii "VAL"
        .byte $A3
        .ascii "EOF"
        .byte $A4
        .ascii "LINE"
        .byte $A5
        .ascii "COLOR"
        .byte $A6
        .ascii "NOFILL"
        .byte $A9
        .ascii "BOX"
        .byte $A7
        .ascii "FILL"
        .byte $A8
        .ascii "CLS"
        .byte $AA
        .ascii "PIXELW"
        .byte $AB
        .ascii "CIRCLE"
        .byte $AC
        .ascii "PIXELR"
        .byte $AE
        .ascii "GTEXT"
        .byte $AF
        .ascii "RGB"
        .byte $B1
        .ascii "IMAGE"
        .byte $B2
        .ascii "GLRD"
        .byte $FB
        .ascii "GL"
        .byte $B3
        .byte $00

        .include "glvtab.inc"

;==============================================================================
; Console
;==============================================================================
; SKIPSP - advance the parse cursor P2 past spaces
SKIPSP: LDA  (P2)
        LDB  #' '
        CMP
        JNZ  sks
        INP2
        JMP  SKIPSP
sks:    RTS

; UPCHAR - A -> upper case if 'a'..'z', else unchanged
UPCHAR: LDB  #'a'
        CMP
        JNC  uc_ret
        LDB  #$7B
        CMP
        JC   uc_ret
        LDB  #$DF
        AND
uc_ret: RTS

; PUTC - A to the console through the BIOS (preserves A and P1, as CONOUT does)
PUTC:   JMP  CONOUT

; PUTCH - A to the current sink: the STR$ capture, the open data file (PRINT#),
;   or the console. Preserves P1.
PUTCH:  PHA
        LDA  STRSINK
        JNZ  pch_str
        LDA  OUTFILE
        JZ   pch_con
        LEAW SAVE2,(P1+0)    ; FPUTB clobbers P1
        PLA
        JSR  FPUTB
        LPW1 SAVE2
        RTS
pch_con:PLA
        JMP  CONOUT
pch_str:LEAW SAVE2,(P1+0)
        LPW1 STRSP
        PLA
        STA  (P1)
        INCW STRSP
        LDA  STRSN
        INC
        STA  STRSN
        LPW1 SAVE2
        RTS

; PUTS - print the NUL-terminated string at (P1) (console only)
PUTS:   LDA  (P1)+
        JZ   putsx
        JSR  CONOUT
        JMP  PUTS
putsx:  RTS

; CRLF
CRLF:   LDA  #CR
        JSR  CONOUT
        LDA  #LF
        JMP  CONOUT

; GETLINE - read one console line into LBUF, echoing; CR ends it, BS / DEL
;   erase (not past the start). NUL-terminated; a CRLF is echoed at the end.
GETLINE:LDP2 #LBUF
gl1:    JSR  CONIN
        LDB  #CR
        CMP
        JZ   gldone
        LDB  #BS
        CMP
        JZ   glbs
        LDB  #$7F
        CMP
        JZ   glbs
        JSR  CONOUT
        STA  (P2)+
        JMP  gl1
glbs:   TPA2L
        LDB  #<LBUF
        CMP
        JZ   gl1             ; nothing to erase
        DEP2
        LDP1 #MBS
        JSR  PUTS
        JMP  gl1
gldone: LDA  #0
        STA  (P2)
        JMP  CRLF
MBS:    .byte BS,$20,BS,0

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
        .ascii "GRAPHICS (window coords, y UP 0-271): COLOR r,g,b : CLS"
        .byte CR,LF
        .ascii "  LINE x0,y0,x1,y1   BOX x0,y0,x1,y1[,FILL|,NOFILL]"
        .byte CR,LF
        .ascii "  CIRCLE x,y,r[,ry][,FILL]  PIXELW x,y  PIXELR(x,y)  RGB(r,g,b)"
        .byte CR,LF
        .ascii "  GTEXT x,y,size,s$  easy 2D text (window coords, absolute size)"
        .byte CR,LF
        .ascii "  raw: MOVE3 x,y,0 then TEXT s$ (TSIZE COMPOUNDS, MDIDEN resets)"
        .byte CR,LF
        .ascii "  IMAGE x,y,f$   draw a P8I file, bottom-left at x,y"
        .byte CR,LF
        .ascii "  + the PGC verbs native: MOVE DRAW POLY RECT AREA TEXT"
        .byte CR,LF
        .ascii "    LINPAT p (dash bits)  LINFUN m (0=set 1=compl 2=OR 3=AND 4=XOR)"
        .byte CR,LF
        .ascii "    and the rest - man basic / man gl"
        .byte CR,LF
        .ascii "  SCREEN IS 480x272 RGB565 - COLOR r,g,b (0-31,0-63,0-31)"
        .byte CR,LF
        .ascii "  or COLOR c, one PACKED value - from RGB() or PIXELR()"
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
MNOTIMG:.ascii "?NOT P8I"
        .byte CR,LF,0
MNOGFX: .ascii "?No display"
        .byte CR,LF,0
MSYN:   .ascii "?SYNTAX ERROR"
        .byte CR,LF,0
MSYNIN: .ascii "?SYNTAX ERROR IN "
        .byte 0
MUNDEF: .ascii "?UNDEF'D LINE"
        .byte CR,LF,0
MRG:    .ascii "?RETURN WITHOUT GOSUB"
        .byte CR,LF,0
