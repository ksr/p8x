;==============================================================================
; P8X BASIC — interpreter for the P8X TTL computer
;
; 6850 ACIA console at $FF04/05. Self-contained (own console + RAM), so it can
; run standalone, from ROM (launched by the monitor), or be booted from disk.
;
; Build targets differ only in their -D symbols (see basic/README.md):
;   BASORG  code origin   ($0000 standalone, $2000 in monitor ROM, $6A00 in the TPA)
;   BASRAM  data base      ($8000 standalone, $C500 for the TPA build)
;   PBUF    rebuild scratch ($C000 default; the TPA build moves it to $E000)
;   MONITOR where BYE returns ($2000 = the OS cold start for the TPA build)
; The defaults below give the standalone $0000/$8000 build; the disk/ROM builds
; pass all four on the command line -- see os/run.sh for the canonical invocation.
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
; Graphics display ($FF20 device). The canonical definitions live in
; generators/gen_memmap.py; they are repeated here because this file predates
; that generator and still hand-declares its I/O addresses, as ACIAS/ACIAD above.
GX0    = $FF20               ; coordinate LOW bytes. Writing one CLEARS its high
GY0    = $FF21               ;   byte, which sits GCHI above it ($FF29-$FF2C),
GX1    = $FF22               ;   so the low byte must always be written first.
GY1    = $FF23
GCOL   = $FF24               ; pen LOW byte (write-only; GPEN shadows it).
                             ;   The pen is a whole RGB565 colour: a GCOL
                             ;   write CLEARS GCOLH, same as the coordinates.
GCOLH  = $FF2D               ; pen HIGH byte (the write side of GID0's address)
GCMD   = $FF25               ; write to execute
GSTAT  = $FF26               ; bit7 BUSY
GDATA  = $FF27               ; read-back: POINT result
GPARM  = $FF28               ; scalar argument: CIRCLE radius / ELLIPSE x-radius
GPARM2 = $FF2F               ; ELLIPSE y-radius
GID0   = $FF2D               ; presence signature: 'P'
GID1   = $FF2E               ;                     'G'
GLDATAR = $FF50          ; GL command FIFO (stage 10d): one byte at a time
GLSTATR = $FF51          ; bit7 = FIFO full (wait before pushing)
GLIDR   = $FF54          ; reads 'G' when the GL engine is fitted
GCHI   = 9                   ; a pair's high byte = its low address + GCHI
GC_PLOT = 1
GC_LINE = 2
GC_BOX  = 3
GC_BOXF = 4
GC_CLS  = 5
                             ; 6 was SETPAL; no palette, no command
GC_CIRC = 7
GC_CIRCF= 8
GC_ELL  = $0A
GC_ELLF = $0B
GC_PONT = 9
                              ; $0C was SETMODE. The device is single-mode now
                              ; -- 480x272, 8 bpp -- so there is nothing to set.
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
SYS_GETCWD = $2003       ; OS: copy the CWD path string -> (P1), incl NUL (clobbers P2)
; sequential byte streams (for BASIC data files):
FOPEN   = $0124          ; open file FNAME for reading (P1=512-byte buf); C=1 missing
FGETB   = $0127          ; next byte -> A; C=1 at end of file
FWOPEN  = $012A          ; open a write stream at the free pointer (uses SBUF)
FPUTB   = $012D          ; append byte A to the write stream
FCLOSE  = $0130          ; flush + register file FNAME (len = bytes written); C=1 if full
FNORM   = $0136          ; copy string (P1) -> FNAME, case-preserved, space-padded to 12
LBA     = $6047          ; CFREAD target LBA (byte 0); LBA1 = byte 1
LBA1    = $6048
FNAME   = $604A          ; 12-byte filename (space-padded)
FSRC    = $6056          ; FCREATE source address
FLEN    = $6058          ; file length in bytes

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
RUNNING= BASRAM+$DA          ; 1 while a program is RUNning (else immediate mode)
SEED   = BASRAM+$F4          ; RND state (2)
SPSAV  = BASRAM+$F8          ; stack pointer to return to (2). Under the OS this
                             ; is the caller's SP, captured at entry; standalone
                             ; it is just STKTOP. See the entry code and DOBYE.
POKEA  = BASRAM+$F6          ; POKE address (2)
; Graphics scratch. $DB-$E2 was the only run in this page with no references at
; all -- note the JUMPADDR comment above for what happens when a "free" byte
; turns out to alias something.
GSADR  = BASRAM+$DB          ; GSTORE: target register address (page $FF)
GSTGT  = BASRAM+$DC          ; GARG:   target held across EVAL
GPEN   = BASRAM+$DD          ; shadow of GCOL -- the device register is WRITE-ONLY,
                             ;   so CLS could not otherwise restore the pen
GPENH  = BASRAM+$FA          ; ...and its high byte, now a pen is a whole RGB565
                             ;   colour. NOT $F2: that is GTTMP, GTEXT's carry
                             ;   scratch -- the stale "last spares" comment
                             ;   below said $F2-$F3 were free and was wrong,
                             ;   and a GTEXT would have corrupted the shadow
                             ;   the next CLS restores. $FA-$FF are the real
                             ;   free run; this takes the first byte.
RGBH   = BASRAM+$F3          ; RGB(): the packed high byte, held across the
                             ;   green and blue argument expressions. $F3 IS
                             ;   free (GTTMP is one byte at $F2), and scratch
                             ;   here is safe: nothing else can run inside an
                             ;   RGB() argument expression.
GCTMP  = BASRAM+$DE          ; GEXEC: the command byte, held across GWAIT
GELL   = BASRAM+$DF          ; CIRCLE: 1 once a second radius made it an ellipse
; GTEXT working set. It rasterises glyphs itself (see DOGTEXT), so unlike the
; other statements it needs real state. $E0-$E2 is the tail of the same free run
; as the block above; $E6-$F1 is the next one ($E3 JUMPF, $E4 JUMPADDR are two
; bytes, and SEED starts at $F4) -- which leaves $F2-$F3 as the only spare bytes
; left in this page. Re-read the JUMPADDR note above before claiming any of it.
GTBIT  = BASRAM+$E0          ; the glyph column being shifted out, one bit a row
GTROW  = BASRAM+$E1          ; rows left in this column (7..1)
GTCOL  = BASRAM+$E2          ; columns left in this glyph (5..1); also the scratch
                             ;   the index*5 glyph-offset multiply borrows
GTCX   = BASRAM+$E6          ; pen x (2) -- runs across the glyph AND on to the
                             ;   next character, so no separate origin is kept
GTY    = BASRAM+$E8          ; text top edge (2), constant for the whole string
GTCY   = BASRAM+$EA          ; pen y (2), reset to GTY at the top of each column
GTPTR  = BASRAM+$EC          ; read pointer into STRACC (2)
GTGP   = BASRAM+$EE          ; read pointer into FONT57 (2)
GTSZ   = BASRAM+$F0          ; size multiplier, >= 1
GTN    = BASRAM+$F1          ; characters left to draw
GTTMP  = BASRAM+$F2          ; carry captured between the halves of a 16-bit
                             ;   add -- ADD has a FIXED carry-in and ignores C,
                             ;   so the high half must be given the carry as a
                             ;   number. Same shape as ADD16.
NAMLEN = 6                   ; significant variable-name length
NVARS  = 32                  ; symbol-table capacity (entry = NAMLEN+2 = 8 bytes)
VARTAB = BASRAM+$100         ; NVARS x 8 = 256 bytes ($x100..$x1FF)
; string values are [len byte][data...]; length is capped at SLEN. Four fixed
; work buffers live below the string-variable table, which lives below PROG.
SLEN   = 32                  ; maximum stored string length
SVENT  = 40                  ; string-var entry: NAMLEN name + 1 len + 32 data + pad
NSVARS = 16                  ; string-variable table capacity
STRACC = BASRAM+$200         ; SEVAL result accumulator (64 bytes)
STRACCD= BASRAM+$201         ; STRACC data area (past the length byte)
STRTMP = BASRAM+$240         ; current term being produced (64)
STRTMPD= BASRAM+$241         ; STRTMP data area (past the length byte)
STRARG = BASRAM+$280         ; a string function's string argument (64)
STRCMP = BASRAM+$2C0         ; saved left operand during a string comparison (64)
SVARTAB= BASRAM+$300         ; NSVARS x SVENT = 640 bytes ($x300..$x57F)

; IMAGE working set. Shares GTEXT's scratch run deliberately: two statements
; never execute at once, and this page has no free run left. (IMAGE's own
; sixteen bits of x survive the row loop in IMX; everything else is per-row.)
IMX    = BASRAM+$E6          ; left edge (2)
IMYC   = BASRAM+$E8          ; current row y (2)
IMW    = BASRAM+$EA          ; image width (2)
IMH    = BASRAM+$EC          ; rows remaining (2)
IMXC   = BASRAM+$EE          ; current column x (2)
IMCX   = BASRAM+$F0          ; columns remaining in this row (2)
GLN    = BASRAM+$E6          ; GL: bytes left to send (shares IMAGE's run --
GLTMP  = BASRAM+$E7          ;   two statements never execute at once)
GLOP   = BASRAM+$E0          ; GL verb statements: opcode, meta, loop count
GLMETA = BASRAM+$E1          ;   (GTEXT's scratch block -- a GL verb and a
GLCNT  = BASRAM+$E2          ;   GTEXT never execute at once)
GLDIM  = BASRAM+$E8          ;   POLY*: words per vertex (2 or 3)
GLFST  = BASRAM+$E9          ;   1 until the first argument is parsed

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
; graphics tokens
TOK_LINE  = $A5          ; LINE x0,y0,x1,y1
TOK_COLOR = $A6          ; COLOR pen
TOK_BOX   = $A7          ; BOX x0,y0,x1,y1[,FILL|,NOFILL]
TOK_FILL  = $A8          ; BOX modifier -- NOT a statement leader (see CKLEAD)
TOK_NOFILL= $A9          ; ... the default, spelled out
TOK_CLS   = $AA          ; CLS
TOK_PLOT  = $AB          ; PLOT x,y
TOK_CIRCLE= $AC          ; CIRCLE x,y,r[,FILL|,NOFILL]
                         ; $AD was PALETTE, removed with the palette. Like
                         ; $B0, it stays unassigned: saved .BAS files are
                         ; tokenised and old programs on disk still carry it.
TOK_POINT = $AE          ; POINT(x,y) -- a FUNCTION, not a statement
TOK_GTEXT = $AF          ; GTEXT x,y,size,string$
TOK_RGB   = $B1          ; RGB(r,g,b) -- a FUNCTION: pack r,b 0-31, g 0-63 into 565
TOK_IMAGE = $B2          ; IMAGE x,y,name$ -- draw a P8I file
TOK_GL    = $B3          ; GL string$ -- one ASCII graphics-language line
                         ; $B4..$E6 are the NATIVE GL VERB block (FLIP,
                         ; DRAW3, MDROTY, CLBEG ... 51 statements), all
                         ; dispatched to DOGLV through GLVTAB. Names,
                         ; tokens and encodings are GENERATED by
                         ; generators/gen_glkw.py (glkwtab.inc spliced at
                         ; the head of KWTAB, glvtab.inc after it) -- the
                         ; token ORDER is ABI, append-only, like $AD/$B0.
                         ; $B0 was SCREEN, removed with the display modes. Do
                         ; not reuse it casually: a saved .BAS is tokenised, so
                         ; an old program on disk still has $B0 in it and would
                         ; run as whatever takes the number.

MONITOR = $0000          ; reset vector — BYE returns here
CONIN   = $0100          ; BIOS: wait for a key -> A
CONOUT  = $0103          ; BIOS: A -> console (expands a bare LF to CR LF)

PROG   = BASRAM+$580          ; program storage (string table occupies $300..$57F)
PBUF   = $C000          ; rebuild scratch buffer
APBUF  = PBUF+128       ; absolute-path scratch (see APATH). Safe to overlay the
                        ; rebuild buffer: GETPATH caps a path at 47 chars, and
                        ; APATH only ever runs during SAVE/LOAD/OPEN, never
                        ; during an edit rebuild.
STKTOP = $FEFF

;==============================================================================
        .org BASORG
; Stack: when P8X/OS launched us we were reached with `JSR (P1)` and the shell
; expects an RTS back (that is how every /bin program returns). Resetting the
; stack to STKTOP would overwrite the caller's frame -- including that return
; address -- so under the OS we ADOPT the caller's stack and remember where it
; was. Standalone/disk-boot there is no caller, so we own the whole stack.
; MONITOR is $2000 for the run-from-OS build and $0000 otherwise, so this costs
; two instructions in the build that does not need it.
        LDA  #>MONITOR
        JZ   bs_own
        TPA3L                        ; running under the OS: keep its stack
        STA  SPSAV
        TPA3H
        STA  SPSAV+1
        JMP  bs_go
bs_own: LDP3 #STKTOP                 ; no OS underneath: the stack is ours
        LDA  #<STKTOP
        STA  SPSAV
        LDA  #>STKTOP
        STA  SPSAV+1
bs_go:
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
        LDA  #$FF            ; graphics: pen WHITE ($FFFF), shadow and device
        STA  GPEN            ;   agreeing. Low byte first -- a GCOL write
        STA  GPENH           ;   clears GCOLH, so the order is load-bearing.
        STA  GCOL
        STA  GCOLH
        LDP1 #BANNER
        JSR  PUTS

; ---------------- REPL -------------------------------------------------------
REPL:   LDA  #0              ; back at the prompt: not running a program
        STA  RUNNING
        JSR  GETLINE         ; line -> LBUF
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
        LDB  #TOK_LINE
        CMP
        JZ   DOGLINE
        LDA  (P2)
        LDB  #TOK_COLOR
        CMP
        JZ   DOCOLOR
        LDA  (P2)
        LDB  #TOK_BOX
        CMP
        JZ   DOBOX
        LDA  (P2)
        LDB  #TOK_CLS
        CMP
        JZ   DOCLS
        LDA  (P2)
        LDB  #TOK_PLOT
        CMP
        JZ   DOPLOT
        LDA  (P2)
        LDB  #TOK_CIRCLE
        CMP
        JZ   DOCIRC
        LDA  (P2)
        LDB  #TOK_GTEXT
        CMP
        JZ   DOGTEXT
        LDA  (P2)
        LDB  #TOK_IMAGE
        CMP
        JZ   DOIMAGE
        LDA  (P2)
        LDB  #TOK_GL
        CMP
        JZ   DOGL
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
        LDA  (P2)            ; a native GL verb? one range check covers
        LDB  #GLV0           ;   all 51 -- the verb index rides to DOGLV
        SUB                  ;   in A (CMP preserves it)
        JNC  st_nglv         ; below the block
        LDB  #GLVN
        CMP
        JC   st_nglv         ; past it
        JMP  DOGLV
st_nglv:
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
; BYE — leave BASIC.
;
; Under P8X/OS: restore the entry stack and RTS, so we return to the shell that
; ran us with the CWD, redirection and everything else intact. This used to
; `JMP MONITOR`, which for the TPA build is $2000 = the OS's COLD entry -- a full
; reboot, so it reprinted the banner and dropped you back in the root directory
; however deep you had cd'd.
;
; Disk-boot/standalone: there is no caller, so jump to the reset vector as before.
DOBYE:  LDA  #>MONITOR
        JZ   by_rst
        LDA  SPSAV                   ; back to the shell
        TAP3L
        LDA  SPSAV+1
        TAP3H
        RTS
by_rst: JMP  MONITOR

; ---------------------------------------------------------------------------
; SAVE "name" / LOAD "name" — persist the program to a P8XFS v2 file via the
; monitor's BIOS FS calls. Paths are relative to the OS current directory (see
; APATH); a leading '/' is absolute. Works in the ROM-in-monitor and disk builds;
; the retired standalone build had no resident monitor/BIOS.
; ---------------------------------------------------------------------------
; APATH — turn the path at (P1) into an ABSOLUTE path, honouring the OS's
; current directory.
;
;   in : P1 -> NUL-terminated path
;   out: P1 -> NUL-terminated ABSOLUTE path (the input itself, or APBUF)
;
; Why: the BIOS resolvers (FRESOLVE/FOPEN/FOPENDIR) always start at the ROOT, so
; a bare "T1" saved from /src used to land in /T1. The /bin commands avoid this
; by prefixing the CWD before any BIOS open (lib_apath.c's abspath); BASIC did
; not, because it made no OS calls at all. This is that same step.
;
; Only meaningful when an OS is underneath: MONITOR is $2000 for the run-from-OS
; build and $0000 for the disk-boot build, where there is no OS and the BIOS root
; is already the right base — so the constant test below compiles to a cheap
; runtime no-op in that build rather than needing conditional assembly.
;
; Preserves P2 (the parse cursor); SYS_GETCWD clobbers it, hence the save.
APATH:  LDA  #>MONITOR
        JZ   ap_ret                  ; no OS underneath -> leave the path alone
        LDA  (P1)
        LDB  #'/'
        CMP
        JZ   ap_ret                  ; already absolute
        TPA2L
        PHA                          ; save the caller's parse cursor
        TPA2H
        PHA
        TPA1L
        PHA                          ; save the source path pointer
        TPA1H
        PHA
        LDP1 #APBUF
        JSR  SYS_GETCWD              ; APBUF <- CWD (clobbers P2)
        LDP1 #APBUF                  ; walk to the NUL
ap_f:   LDA  (P1)
        JZ   ap_f2
        INP1
        JMP  ap_f
ap_f2:  DEP1                         ; look at the last CWD character
        LDA  (P1)
        LDB  #'/'
        CMP
        INP1                         ; back to the NUL slot either way
        JZ   ap_c                    ; CWD is "/" (or ends in one): no separator
        LDA  #'/'
        STA  (P1)+
ap_c:   PLA
        TAP2H                        ; source path -> P2 as the read cursor
        PLA
        TAP2L
ap_c1:  LDA  (P2)+                   ; append the relative path, NUL included
        STA  (P1)+
        LDB  #0
        CMP
        JNZ  ap_c1
        PLA
        TAP2H                        ; restore the caller's parse cursor
        PLA
        TAP2L
        LDP1 #APBUF
ap_ret: RTS

st_save:INP2                        ; consume the SAVE token
        JSR  GETPATH                ; "path" -> PBUF ; C set = syntax error
        JC   fs_serr
        LDP1 #PBUF                   ; resolve it: subdir path or bare name
        JSR  APATH                   ; ... relative to the OS CWD, not the root
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
        JSR  APATH                   ; relative to the OS CWD, not the root
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
;   error (no opening quote). The caller runs it through APATH and then FRESOLVE,
;   so a bare "NAME" resolves in the CURRENT directory and "/SUB/NAME" is
;   absolute — SAVE/LOAD reach subdirectories either way.
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
        LDA  #0                      ; FLEN is 24-bit now; a BASIC program is <64 KB
        STA  FLEN+2
        RTS
st_err: LDP1 #MWHAT
        JSR  PUTS
stmt_nop: RTS

; SYNERR — abort current statement to the prompt (resets the stack). When a
; program is RUNning, report the offending line ("?SYNTAX ERROR IN 100"); in
; immediate mode there is no line, so just "?SYNTAX ERROR".
SYNERR: LDA  SPSAV                   ; unwind to our entry SP, not STKTOP: under
        TAP3L                        ;   the OS that would eat the caller's frame
        LDA  SPSAV+1
        TAP3H
        LDA  #0                      ; a PRINT# aborted mid-record must not leave
        STA  OUTFILE                 ; console output redirected to the file
        STA  STRSINK                 ; nor an interrupted STR$ capture
        LDA  RUNNING
        JZ   syn_imm
        LDP1 #MSYNIN                 ; "?SYNTAX ERROR IN "
        JSR  PUTS
        LDA  CURLINE                 ; line number = the word at CURLINE
        TAP1L
        LDA  CURLINE+1
        TAP1H
        LDA  (P1)+
        STA  LNUM
        LDA  (P1)
        STA  LNUM+1
        JSR  PRDECU                  ; unsigned decimal line number
        JSR  CRLF
        JMP  REPL
syn_imm: LDP1 #MSYN
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
        LDA  #1                      ; a runtime error now reports its line number
        STA  RUNNING
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

;==============================================================================
; GRAPHICS — COLOR / CLS / PLOT / LINE / BOX / CIRCLE (and its ellipse form) /
; PALETTE, plus the POINT() function, driving the $FF20 display.
;
; The drawing engine is in the DEVICE: these statements evaluate expressions
; straight into the coordinate registers and write one command byte. There is no
; Bresenham here and no pixel masking -- which is the whole reason the engine was
; put in hardware, since a filled box would otherwise be 32640 read-modify-write
; cycles through a data port.
;==============================================================================

; GCHECK — is a display actually there? An absent card floats the bus to $FF, so
; a single magic byte would prove nothing; GID0/GID1 are two fixed bytes at two
; addresses. Without this, LINE on a machine with no card would silently do
; nothing at all, which is the worst possible failure for a graphics statement.
GCHECK: LDA  GLIDR                  ; a GL engine? let its walker go
        LDB  #'G'                   ;   idle first: the walker MASTERS
        CMP                         ;   the 2D device, and its registers
        JNZ  gchk_p                 ;   (GID0 included) answer garbage
gchk_w: LDA  GLSTATR                ;   while it draws -- found on
        LDB  #$40                   ;   silicon as ?No display right
        AND                         ;   after a CLEARS (the emulator is
        JNZ  gchk_w                 ;   synchronous and cannot see it)
gchk_p: LDA  GID0
        LDB  #'P'
        CMP
        JNZ  GNODEV
        LDA  GID1
        LDB  #'G'
        CMP
        JNZ  GNODEV
        RTS
; No display: abandon the statement. Same unwind as SYNERR -- we are giving up
; part-way through, so the stack has to go back to our entry SP.
GNODEV: LDA  SPSAV
        TAP3L
        LDA  SPSAV+1
        TAP3H
        LDA  #0
        STA  OUTFILE
        STA  STRSINK
        LDP1 #MNOGFX
        JSR  PUTS
        JMP  REPL

; GWAIT — spin until the drawing engine is idle.
; The DEVICE draws in real time: a full-screen fill is ~32640 pixels, a couple of
; milliseconds, and a second command issued meanwhile ABORTS the first. The
; emulator draws instantaneously and always reports not-busy, so this loop costs
; nothing there and is essential on hardware -- and because it costs nothing
; there, one binary is correct on both. Same shape as the CF driver's BSY wait.
GWAIT:  LDA  GSTAT
        LDB  #$80
        AND
        JNZ  GWAIT
        RTS

; GEXEC — wait for the engine, then issue the command in A.
GEXEC:  STA  GCTMP
        JSR  GWAIT
        LDA  GCTMP
        STA  GCMD
        RTS

; GSTORE — RESULT -> a coordinate register PAIR.  A = the pair's LOW register
; address within page $FF (every graphics register is in that page, so one byte
; addresses them all). The DEVICE clears the high byte when the low one is
; written, so low MUST go first -- writing high first would lose it.
GSTORE: STA  GSADR
        TAP1L
        LDA  #$FF
        TAP1H
        LDA  RESULT
        STA  (P1)                   ; low  (device zeroes the matching high byte)
        LDA  GSADR
        LDB  #GCHI
        CLC
        ADD
        TAP1L
        LDA  #$FF
        TAP1H
        LDA  RESULT+1
        STA  (P1)                   ; high (0 for anything on a 240x136 screen)
        RTS

; GARG — consume ',' then an expression, storing it via GSTORE.  A = target.
GARG:   STA  GSTGT
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  g_err
        INP2
        JSR  EVAL
        LDA  GSTGT
        JMP  GSTORE
g_err:  JMP  SYNERR

; GCOORDS — the shared "x0,y0,x1,y1" argument list of LINE and BOX. The first
; coordinate has no leading comma; the other three do.
GCOORDS: JSR EVAL
        LDA  #<GX0
        JSR  GSTORE
        LDA  #<GY0
        JSR  GARG
        LDA  #<GX1
        JSR  GARG
        LDA  #<GY1
        JSR  GARG
        RTS

; LINE x0,y0,x1,y1
; Named DOGLINE, not DOLINE: DOLINE is already the program-line parser.
DOGLINE: INP2                       ; consume the LINE token
        JSR  GCHECK
        JSR  GCOORDS
        LDA  #GC_LINE
        JSR  GEXEC
        RTS

; COLOR c  |  COLOR r,g,b -- the pen is a whole RGB565 colour. One number is
; a PACKED colour (RGB() builds one, and POINT returns one, so C=POINT(X,Y):
; COLOR C round-trips); three numbers are r,b 0-31, g 0-63, packed here by
; the same RGBTAIL the RGB() function uses. The comma decides, the same way
; CIRCLE's optional second radius does.
DOCOLOR: INP2
        JSR  GCHECK
        JSR  EVAL
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  dc_st                  ; no comma: RESULT is the packed colour
        JSR  RGBTAIL                ; comma: RESULT was r; parse ,g,b and pack
dc_st:  LDA  RESULT
        STA  GPEN                   ; shadow first: GCOL cannot be read back
        STA  GCOL                   ; low byte first -- this clears GCOLH
        LDA  RESULT+1
        STA  GPENH
        STA  GCOLH
        LDA  GLIDR                  ; a GL engine? ONE pen statement drives
        LDB  #'G'                   ;   both paths: unpack the 565 back to
        CMP                         ;   r g b and set the card's pen too
        JNZ  dc_rts                 ;   (and it records, inside a list)
        LDA  #$06                   ; GL COLOR
        JSR  GLPUT
        LDA  RESULT+1               ; r = pen[15:11]
        SHR
        SHR
        SHR
        JSR  GLPUT
        LDA  RESULT+1               ; g = pen[10:8] over pen[7:5]
        LDB  #$07
        AND
        SHL
        SHL
        SHL
        STA  GLCNT                  ; (GLPUT owns GLTMP)
        LDA  RESULT
        SHR
        SHR
        SHR
        SHR
        SHR
        LDB  GLCNT
        OR
        JSR  GLPUT
        LDA  RESULT                 ; b = pen[4:0]
        LDB  #$1F
        AND
        JSR  GLPUT
dc_rts: RTS

; BOX x0,y0,x1,y1 [,FILL | ,NOFILL]   -- outline unless FILL is given.
; NOFILL has to be a real keyword, not just the default: with FILL tokenised and
; NOFILL not, CRUNCH would match FILL *inside* the word NOFILL and a request for
; an outline would silently draw a solid box.
DOBOX:  INP2
        JSR  GCHECK
        JSR  GCOORDS
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  bx_out                 ; no fifth argument -> outline
        INP2
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_FILL
        CMP                         ; CMP preserves A, so the next test is valid
        JZ   bx_fill
        LDB  #TOK_NOFILL
        CMP
        JNZ  bx_err
        INP2
bx_out: LDA  #GC_BOX
        JSR  GEXEC
        RTS
bx_fill: INP2
        LDA  #GC_BOXF
        JSR  GEXEC
        RTS
bx_err: JMP  SYNERR

; CLS — clear to the BACKGROUND (pen 0), not to the current pen, which is what
; anyone typing CLS expects. The device fills with whatever GCOL holds, and GCOL
; is write-only, so the pen is restored from the GPEN shadow afterwards.
DOCLS:  INP2
        JSR  GCHECK
        LDA  #0
        STA  GCOL
        LDA  #GC_CLS
        JSR  GEXEC
        JSR  GWAIT                  ; the pen restore must not overtake the clear
        LDA  GPEN
        STA  GCOL                   ; low first -- clears GCOLH
        LDA  GPENH
        STA  GCOLH
        RTS

; PLOT x,y — a single pixel in the current pen.
DOPLOT: INP2
        JSR  GCHECK
        JSR  EVAL
        LDA  #<GX0
        JSR  GSTORE
        LDA  #<GY0
        JSR  GARG
        LDA  #GC_PLOT
        JSR  GEXEC
        RTS

; CIRCLE x,y,r [,FILL | ,NOFILL] — centre and radius, outline unless filled.
; The radius is a SCALAR (GPARM), not a coordinate, so it does not go through
; GSTORE: there is no high-byte partner to clear.
DOCIRC: INP2
        JSR  GCHECK
        LDA  #0
        STA  GELL                   ; a circle until a second radius says otherwise
        JSR  EVAL
        LDA  #<GX0
        JSR  GSTORE
        LDA  #<GY0
        JSR  GARG
        JSR  SKIPSP                 ; ',' then the (x-)radius
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  ci_err
        INP2
        JSR  EVAL
        LDA  RESULT
        STA  GPARM
; What follows a comma here is EITHER the modifier or a second radius, and the
; token tells them apart: FILL/NOFILL are keywords (>= $80), anything else starts
; an expression. That is why NOFILL had to be a real keyword rather than merely
; the default -- without it, `CIRCLE x,y,r,NOFILL` would try to EVAL "NOFILL".
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  ci_out                 ; nothing more: outline circle
        INP2
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_FILL
        CMP
        JZ   ci_fill
        LDB  #TOK_NOFILL
        CMP
        JZ   ci_nof
        JSR  EVAL                   ; a second radius -> ellipse
        LDA  RESULT
        STA  GPARM2
        LDA  #1
        STA  GELL
        JSR  SKIPSP                 ; ... and it may still take a modifier
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  ci_out
        INP2
        JSR  SKIPSP
        LDA  (P2)
        LDB  #TOK_FILL
        CMP
        JZ   ci_fill
        LDB  #TOK_NOFILL
        CMP
        JNZ  ci_err
ci_nof: INP2
ci_out: LDA  GELL
        JNZ  ci_eo
        LDA  #GC_CIRC
        JMP  ci_go
ci_eo:  LDA  #GC_ELL
        JMP  ci_go
ci_fill: INP2
        LDA  GELL
        JNZ  ci_ef
        LDA  #GC_CIRCF
        JMP  ci_go
ci_ef:  LDA  #GC_ELLF
ci_go:  JSR  GEXEC
        RTS
ci_err: JMP  SYNERR

; PALETTE is gone: there is no palette to write. An old tokenised program's
; $AD byte no longer dispatches, so it falls through to the implicit-LET path
; and reports ?SYNTAX ERROR -- the honest outcome for a statement whose
; hardware left. RGB(r,g,b) is the forward path: colours are packed, not
; installed.

;==============================================================================
; GTEXT x,y,size,string$ — draw a string as GRAPHICS, in the current pen.
;
; Unlike every other statement here, the glyphs are rasterised IN SOFTWARE. The
; display has no text command and adding one would mean a font ROM plus a glyph
; state machine in gfx.v, which the FPGA build has no room for: the lcd bitstream
; sits at 44/46 BSRAM and a change with no logical effect at all has already been
; enough to break placement (see BACKLOG.md). Doing it here costs one device
; command per LIT pixel and needs no bitstream change whatsoever, so GTEXT ships
; as a new BASIC.BIN on the card and the board is not reflashed.
;
; Each font pixel becomes a size x size block -- PLOT at size 1, BOXFILL above
; it -- so a big font costs exactly as many device commands as a small one.
;
; Clipping is free: the device DISCARDS off-screen pixels rather than wrapping
; them (see gpu_px in the emulator), so nothing here tests a pixel. The only
; bound checked is the x cursor, and only to stop early once the string has run
; off the right-hand edge -- without which a long string would keep issuing
; commands for pixels that can never appear.
;
; The font is 5x7 in a 6x8 cell: 40 columns across a 240-pixel screen at size 1,
; 20 at size 2. Codes $20-$5F only; lowercase folds onto the uppercase glyph via
; UPCHAR and anything else draws as a blank. See generators/gen_font57.py.
;==============================================================================
DOGTEXT: INP2                       ; consume the GTEXT token
        JSR  GCHECK
        JSR  EVAL                   ; x
        LDA  RESULT
        STA  GTCX
        LDA  RESULT+1
        STA  GTCX+1
        JSR  GTSEP
        JSR  EVAL                   ; y
        LDA  RESULT
        STA  GTY
        LDA  RESULT+1
        STA  GTY+1
        JSR  GTSEP
        JSR  EVAL                   ; size
        LDA  RESULT+1
        JNZ  gt_big                 ; >= 256: clamp, do not let it wrap to a
        LDA  RESULT                 ;   stripe one pixel wide
        JNZ  gt_szok
        LDA  #1                     ; size 0 would draw nothing at all
        JMP  gt_szok
gt_big: LDA  #255
gt_szok: STA GTSZ
        JSR  GTSEP
        JSR  SEVAL                  ; the string -> STRACC = [len][data...]
        LDA  STRACC
        STA  GTN
        JZ   gt_ret                 ; "" is legal and draws nothing
        LDA  #<STRACCD
        STA  GTPTR
        LDA  #>STRACCD
        STA  GTPTR+1

; ---- one character ---------------------------------------------------------
gt_ch:  LDA  GTN
        JZ   gt_ret
        DEC
        STA  GTN
        LDA  GTCX+1                 ; run off the right edge -> stop. 240 is a
        JNZ  gt_ret                 ;   byte, so any high byte is already past it
        LDA  GTCX
        LDB  #240
        CMP
        JC   gt_ret                 ; C=1 here means x >= 240
        LDA  GTPTR                  ; fetch the character
        TAP1L
        LDA  GTPTR+1
        TAP1H
        LDA  (P1)
        JSR  UPCHAR                 ; 'a'-'z' share the uppercase glyphs
        LDB  #$20
        CMP                         ; CMP preserves A, so both bounds can be
        JNC  gt_spc                 ;   tested against the one load
        LDB  #$60
        CMP
        JC   gt_spc
        JMP  gt_have
gt_spc: LDA  #$20                   ; outside the font -> blank
gt_have: LDB #$20
        SUB                         ; glyph index 0..63

; ---- GTGP = FONT57 + index*5  (index*4 + index; no multiply in this ISA) ----
        STA  GTCOL                  ; the index, needed once more for the +index;
        STA  GTGP                   ;   GTCOL becomes the column counter below
        LDA  #0
        STA  GTGP+1
        LDA  GTGP                   ; x2 -- SHL pushes bit 7 into C and ROL takes
        SHL                         ;   it, so the pair shifts as one 16-bit value
        STA  GTGP
        LDA  GTGP+1
        ROL
        STA  GTGP+1
        LDA  GTGP                   ; x4
        SHL
        STA  GTGP
        LDA  GTGP+1
        ROL
        STA  GTGP+1
        LDA  GTGP                   ; + index  ->  index*5
        LDB  GTCOL
        ADD
        STA  GTGP
        LDA  #0                     ; capture the carry (LDA leaves C alone)
        JNC  gt_m1
        LDA  #1
gt_m1:  LDB  GTGP+1
        ADD
        STA  GTGP+1
        LDA  GTGP                   ; + FONT57
        LDB  #<FONT57
        ADD
        STA  GTGP
        LDA  #0
        JNC  gt_m2
        LDA  #1
gt_m2:  LDB  GTGP+1
        ADD
        LDB  #>FONT57
        ADD
        STA  GTGP+1

; ---- five columns ----------------------------------------------------------
        LDA  #5
        STA  GTCOL
gt_col: LDA  GTGP                   ; bits = *GTGP++
        TAP1L
        LDA  GTGP+1
        TAP1H
        LDA  (P1)
        STA  GTBIT
        LDA  GTGP
        INC
        STA  GTGP
        JNZ  gt_c1
        LDA  GTGP+1
        INC
        STA  GTGP+1
gt_c1:  LDA  GTY                    ; every column restarts at the top row
        STA  GTCY
        LDA  GTY+1
        STA  GTCY+1
        LDA  #7
        STA  GTROW
gt_row: LDA  GTBIT                  ; bit 0 is the row we are on
        LDB  #1
        AND
        JZ   gt_off
        JSR  GTBLK
gt_off: LDA  GTBIT
        SHR
        STA  GTBIT
        LDA  GTCY                   ; cury += size
        LDB  GTSZ
        ADD
        STA  GTCY
        LDA  #0
        JNC  gt_y1
        LDA  #1
gt_y1:  LDB  GTCY+1
        ADD
        STA  GTCY+1
        LDA  GTROW
        DEC
        STA  GTROW
        JNZ  gt_row
        JSR  GTADVX                 ; curx += size
        LDA  GTCOL
        DEC
        STA  GTCOL
        JNZ  gt_col
        JSR  GTADVX                 ; the sixth column is the inter-character gap
        LDA  GTPTR                  ; next character
        INC
        STA  GTPTR
        JNZ  gt_ch
        LDA  GTPTR+1
        INC
        STA  GTPTR+1
        JMP  gt_ch
gt_ret: RTS

;------------------------------------------------------------------------------
; GL string$ — send one ASCII graphics-language line to the GL engine
; (stage 10d, man gl). The string is wrapped "CA " ... CR "CX " so the
; card is back in HEX mode afterwards (every other tool assumes hex).
; Build fly-throughs with string arithmetic:  GL "VWY "+STR$(A)+" CR 0".
; No display or no GL engine abandons the statement, the GNODEV way.
DOGL:   INP2                        ; consume the GL token
        JSR  GCHECK
        LDA  GLIDR
        LDB  #'G'
        CMP
        JNZ  GNODEV
        JSR  SEVAL                  ; string -> STRACC=[len], data at STRACCD
        LDA  #'C'
        JSR  GLPUT
        LDA  #'A'
        JSR  GLPUT
        LDA  #' '
        JSR  GLPUT
        LDA  #<STRACCD
        TAP1L
        LDA  #>STRACCD
        TAP1H
        LDA  STRACC
        STA  GLN
gl_ch:  LDA  GLN
        JZ   gl_end
        DEC
        STA  GLN
        LDA  (P1)
        JSR  GLPUT
        INP1
        JMP  gl_ch
gl_end: LDA  #13                    ; a CR finishes the last token
        JSR  GLPUT
        LDA  #'C'
        JSR  GLPUT
        LDA  #'X'
        JSR  GLPUT
        LDA  #' '
        JSR  GLPUT
        RTS

; one byte to the GL FIFO, honouring the full bit (GLSTAT bit 7)
GLPUT:  STA  GLTMP
glp_w:  LDA  GLSTATR
        LDB  #$80
        AND
        JNZ  glp_w
        LDA  GLTMP
        STA  GLDATAR
        RTS

; ---- the native GL verb statements (tokens GLV0..GLV0+GLVN-1) ---------
; ONE handler for all 51. The verb index (in A from the dispatcher)
; picks the GLVTAB entry gen_glkw.py wrote: the GL opcode and a meta
; byte {var<<7 | bcnt<<4 | word-arity}. The opcode goes to the FIFO,
; then bcnt byte-width params, then the int16 params little-endian --
; every argument a full expression, comma-separated, the first bare:
;     MDROTY A*2       DRAW3 90,-90,300     CLOOP 0,72
; POLY/POLYR/POLY3/POLYR3 (var) take a count, then count vertices of 2
; or 3 coordinates (3 when opcode bit 1 -- the 3D forms):
;     POLY3 3,-80,-80,300,80,-80,300,0,40,420
; The card is in HEX mode by invariant -- power-up default, and every
; tool that switches away switches back -- so the bytes go raw, no
; CA/CX. Inside CLBEG/CLEND these statements RECORD instead of draw,
; so a BASIC loop can build a command list. No display or no GL engine
; abandons the statement, the GNODEV way.
DOGLV:  STA  GLTMP                  ; the verb index
        INP2                        ; consume the token
        JSR  GCHECK
        LDA  GLIDR
        LDB  #'G'
        CMP
        JNZ  GNODEV
        LDA  GLTMP                  ; P1 = GLVTAB + index*2
        SHL
        LDB  #<GLVTAB
        ADD
        TAP1L
        LDA  #0                     ; capture the carry (LDA leaves C alone)
        JNC  glv_hi
        LDA  #1
glv_hi: LDB  #>GLVTAB
        ADD
        TAP1H
        LDA  (P1)                   ; opcode, meta -- read BEFORE any EVAL
        STA  GLOP                   ;   (expressions are licensed to walk P1)
        INP1
        LDA  (P1)
        STA  GLMETA
        LDA  GLOP
        JSR  GLPUT                  ; the opcode
        LDA  #1
        STA  GLFST
        LDA  GLMETA
        LDB  #$80
        AND
        JNZ  glv_var                ; POLY* go the count-then-vertices way
        LDA  GLMETA                 ; bcnt: byte-width params first
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
        LDA  RESULT
        JSR  GLPUT                  ; byte param: the low byte only
        JMP  glv_bl
glv_w0: LDA  GLMETA                 ; then the int16 params
        LDB  #$0F
        AND
        STA  GLCNT
glv_wl: LDA  GLCNT
        JZ   glv_dn
        DEC
        STA  GLCNT
        JSR  GLVSEP
        LDA  RESULT
        JSR  GLPUT                  ; little-endian, low then high
        LDA  RESULT+1
        JSR  GLPUT
        JMP  glv_wl
glv_dn: LDA  GLSTATR                ; native statements are SYNCHRONOUS:
        LDB  #$40                   ;   drain busy (bit 6) so a POINT()
        AND                         ;   right after a draw reads finished
        JNZ  glv_dn                 ;   pixels on silicon, exactly as it
        RTS                         ;   does in the emulator. GL s$ stays
                                    ;   the async path (fly-throughs).

glv_var: JSR GLVSEP                 ; the vertex count
        LDA  RESULT
        STA  GLN
        JSR  GLPUT                  ; ... goes to the FIFO as a byte
        LDA  #2
        STA  GLDIM
        LDA  GLOP                   ; opcode bit 1 -> 3D, three words each
        LDB  #2
        AND
        JZ   glv_vl
        LDA  #3
        STA  GLDIM
glv_vl: LDA  GLN                    ; per vertex ...
        JZ   glv_dn
        DEC
        STA  GLN
        LDA  GLDIM
        STA  GLCNT
glv_vw: LDA  GLCNT                  ; ... per coordinate
        JZ   glv_vl
        DEC
        STA  GLCNT
        JSR  GLVSEP
        LDA  RESULT
        JSR  GLPUT
        LDA  RESULT+1
        JSR  GLPUT
        JMP  glv_vw

; comma rule + expression: the first argument follows the keyword bare,
; every later one needs its comma. Result in RESULT.
GLVSEP: LDA  GLFST
        JZ   glvs_c
        LDA  #0
        STA  GLFST
        JMP  glvs_e
glvs_c: JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  glvs_x
        INP2
glvs_e: JMP  EVAL
glvs_x: JMP  SYNERR

; IMAGE x,y,name$ — draw a P8I image file with its top-left corner at (x,y).
;
; The file describes itself — magic, version, geometry, depth (see
; tools/p8img.py and STAGE6-DESIGN.md) — so this statement cannot be lied to
; about the size: geometry in the arguments would let a wrong guess SHEAR the
; picture into plausible garbage. The payload is little-endian RGB565, matching
; the GCOL/GCOLH write order, so the inner loop is two file bytes and a PLOT.
; Off-screen pixels are DISCARDED by the device, so an image at the edge clips
; for free, the same rule everything else follows.
;
; Uses the one data channel's machinery (SETFNAME, FOPEN into PBUF, FGETB), so
; a file OPEN'd for INPUT is closed by IMAGE — same licence SAVE/LOAD take.
; A file that is not P8I, the wrong version or depth, or that ends early says
; ?NOT P8I; whatever pixels arrived before a truncation stay drawn.
DOIMAGE: INP2
        JSR  GCHECK
        JSR  EVAL                   ; x
        LDA  RESULT
        STA  IMX
        LDA  RESULT+1
        STA  IMX+1
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  img_syn
        INP2
        JSR  EVAL                   ; y
        LDA  RESULT
        STA  IMYC
        LDA  RESULT+1
        STA  IMYC+1
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  img_syn
        INP2
        JSR  SETFNAME               ; DIRLBA + FNAME = the resolved path
        TPA2L                       ; the parse cursor sleeps through the file
        PHA                         ; phase: FGETB CLOBBERS P1 *AND* P2 on its
        TPA2H                       ; refill path -- the OS says so at MKSP,
        PHA                         ; and the claim here that it spares P2 was
                                    ; wrong past the first buffer-load
        LDP1 #PBUF
        JSR  FOPEN
        JC   img_nf
        LDA  #0
        STA  FMODE                  ; the channel is ours; it stays closed after
        JSR  IMGB                   ; ---- the header owns the next ten bytes
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
        LDB  #1                     ; version 1 or nothing
        CMP
        JNZ  img_bad
        JSR  IMGB
        STA  IMW                    ; width, little-endian
        JSR  IMGB
        STA  IMW+1
        JSR  IMGB
        STA  IMH                    ; height
        JSR  IMGB
        STA  IMH+1
        JSR  IMGB
        LDB  #16                    ; depth: RGB565 or nothing
        CMP
        JNZ  img_bad
        JSR  IMGB                   ; reserved, ignored
        LDA  IMW                    ; a zero dimension is legal and draws nothing
        LDB  IMW+1
        OR
        JZ   img_done
        LDA  IMH
        LDB  IMH+1
        OR
        JZ   img_done
img_row: LDA IMYC                    ; GY0 pair <- this row; low first (the low
        STA  GY0                    ;   write clears GY0H), constant for the row
        LDA  IMYC+1
        STA  GY0+GCHI
        LDA  IMX                    ; back to the left edge
        STA  IMXC
        LDA  IMX+1
        STA  IMXC+1
        LDA  IMW
        STA  IMCX
        LDA  IMW+1
        STA  IMCX+1
img_px: JSR  IMGB                   ; colour: low byte clears GCOLH...
        STA  GCOL
        JSR  IMGB                   ; ...high byte completes it
        STA  GCOLH
        LDA  IMXC                   ; GX0 pair, low first
        STA  GX0
        LDA  IMXC+1
        STA  GX0+GCHI
        LDA  #GC_PLOT
        JSR  GEXEC
        LDA  IMXC                   ; x++
        INC
        STA  IMXC
        JNZ  img_x1
        LDA  IMXC+1
        INC
        STA  IMXC+1
img_x1: LDA  IMCX                   ; columns--
        LDB  #1
        SUB
        STA  IMCX
        JC   img_c1                 ; C=1: no borrow
        LDA  IMCX+1
        LDB  #1
        SUB
        STA  IMCX+1
img_c1: LDA  IMCX
        LDB  IMCX+1
        OR
        JNZ  img_px
        LDA  IMYC                   ; y++
        INC
        STA  IMYC
        JNZ  img_y1
        LDA  IMYC+1
        INC
        STA  IMYC+1
img_y1: LDA  IMH                    ; rows--
        LDB  #1
        SUB
        STA  IMH
        JC   img_r1
        LDA  IMH+1
        LDB  #1
        SUB
        STA  IMH+1
img_r1: LDA  IMH
        LDB  IMH+1
        OR
        JNZ  img_row
img_done: PLA                     ; the parse cursor, back from before the file
        TAP2H
        PLA
        TAP2L
        RTS
img_syn: JMP  SYNERR                ; pre-push: SYNERR unwinds SP itself
img_nf: LDA  #0
        STA  FMODE
        LDP1 #MNOFILE
        JSR  PUTS
        JMP  img_done
img_bad: LDP1 #MNOTIMG
        JSR  PUTS
        JMP  img_done

; IMGB — the next file byte -> A. On EOF it ABANDONS the statement: the two
; return-address bytes JSR pushed are popped and control goes to the ?NOT P8I
; report, so a truncated file cannot hang the pixel loop waiting for data.
IMGB:   JSR  FGETB
        JC   imgb_e
        RTS
imgb_e: PLA                         ; drop IMGB's own return address...
        PLA
        JMP  img_bad                ; ...and report from the statement's level

; GTSEP — require the ',' between GTEXT's arguments.
GTSEP:  JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  gt_err
        INP2
        RTS
gt_err: JMP  SYNERR

; GTADVX — pen x += size, 16-bit.
GTADVX: LDA  GTCX
        LDB  GTSZ
        ADD
        STA  GTCX
        LDA  #0
        JNC  ax_nc
        LDA  #1
ax_nc:  LDB  GTCX+1
        ADD
        STA  GTCX+1
        RTS

; GTBLK — one lit font pixel: a size x size block at (GTCX,GTCY) in the current
; pen. One device command either way, which is what makes scaling free.
; Low bytes go first throughout: the device CLEARS a high byte when its low
; partner is written, so the reverse order would silently drop it.
GTBLK:  LDA  GTCX
        STA  GX0
        LDA  GTCX+1
        STA  GX0+GCHI
        LDA  GTCY
        STA  GY0
        LDA  GTCY+1
        STA  GY0+GCHI
        LDA  GTSZ
        LDB  #1
        CMP
        JZ   gb_dot
        LDA  GTSZ                   ; x1 = x0 + size-1
        LDB  #1
        SUB
        LDB  GTCX
        ADD
        STA  GTTMP                  ; hold it: GX1 must not be written until the
        LDA  #0                     ;   carry has been read out of C
        JNC  gb_x
        LDA  #1
gb_x:   LDB  GTCX+1
        ADD
        PHA                         ; low first -- writing it CLEARS the high byte
        LDA  GTTMP
        STA  GX1
        PLA
        STA  GX1+GCHI
        LDA  GTSZ                   ; y1 = y0 + size-1
        LDB  #1
        SUB
        LDB  GTCY
        ADD
        STA  GTTMP
        LDA  #0
        JNC  gb_y
        LDA  #1
gb_y:   LDB  GTCY+1
        ADD
        PHA
        LDA  GTTMP
        STA  GY1
        PLA
        STA  GY1+GCHI
        LDA  #GC_BOXF
        JMP  GEXEC
gb_dot: LDA  #GC_PLOT
        JMP  GEXEC

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
        JZ   nx_loop                ; var == limit -> loop once more (limit inclusive)
; Which side of the limit ends the loop depends on the SIGN of STEP: an up-loop
; ends once var > limit, a down-loop once var < limit. Consume C from CMP16 FIRST
; and branch — the sign test below is an AND, which loads flags and would destroy
; the carry we still need.
        JC   nx_gt                  ; var > limit
        LDA  FSTEP+1                ; var < limit: only a DOWN loop finishes here
        LDB  #$80
        AND
        JNZ  nx_done                ; STEP < 0 -> counted past the limit -> finished
        JMP  nx_loop                ; STEP >= 0 -> still climbing toward it -> loop
nx_gt:  LDA  FSTEP+1                ; var > limit: only an UP loop finishes here
        LDB  #$80
        AND
        JNZ  nx_loop                ; STEP < 0 -> still above the limit -> loop
        JMP  nx_done                ; STEP >= 0 -> passed the limit -> finished
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
        LDB  #TOK_POINT
        CMP
        JZ   fa_point
        LDA  (P2)
        LDB  #TOK_RGB
        CMP
        JZ   fa_rgb
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
; POINT(x,y) — the pen (0-3) at a pixel; 0 for anything off-screen, matching the
; write side's "off-screen simply is not there" rule. Two arguments, so PARGET
; (which parses exactly one) does not fit and the parens are handled here.
fa_point: INP2
        JSR  GCHECK
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'('
        CMP
        JNZ  pt_err
        INP2
        JSR  EXPR
        LDA  #<GX0
        JSR  GSTORE
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  pt_err
        INP2
        JSR  EXPR
        LDA  #<GY0
        JSR  GSTORE
        JSR  SKIPSP
        LDA  (P2)
        LDB  #')'
        CMP
        JNZ  pt_err
        INP2
        LDA  #GC_PONT
        JSR  GEXEC
        JSR  GWAIT                  ; the answer is only valid once it is done
        LDA  GDATA                  ; GDATA streams the 16-bit colour: low...
        STA  RESULT
        LDA  GDATA                  ; ...then high (and parks on the high byte)
        STA  RESULT+1
        RTS
pt_err: JMP  SYNERR

; RGB(r,g,b) -- pack a 565 colour: r,b are 0-31, g is 0-63 (its extra bit is
; real: green gets six). Pure arithmetic, so no GCHECK -- RGB() works with no
; display fitted, and COLOR stores whatever it is given either way. Arguments
; are MASKED to their fields, the same forgiveness PEEK's address gets.
; RGBH is not preserved across a nested RGB() in an argument -- the same class
; of limitation POINT has with the coordinate registers, and as pointless to
; hit. The (g&7)<<5 half rides the STACK across the blue argument instead;
; SYNERR unwinds SP, so an error mid-argument cannot leak the push.
fa_rgb: INP2
        JSR  SKIPSP
        LDA  (P2)
        LDB  #'('
        CMP
        JNZ  rgb_err
        INP2
        JSR  EXPR                   ; red
        JSR  RGBTAIL                ; ,green ,blue -> RESULT packed
        JSR  SKIPSP
        LDA  (P2)
        LDB  #')'
        CMP
        JNZ  rgb_err
        INP2
        RTS
rgb_err: JMP SYNERR

; RGBTAIL -- RESULT holds r; parse ",g,b" and pack (r<<11)|(g<<5)|b into
; RESULT. Shared by the RGB() function and COLOR's three-number form, so the
; two can never drift. Arguments are MASKED to their fields. RGBH is not
; preserved across a nested RGB() in an argument -- the same class of
; limitation POINT has -- and the (g&7)<<5 half rides the STACK across the
; blue argument; SYNERR unwinds SP, so an error mid-argument cannot leak it.
RGBTAIL: LDA RESULT
        LDB  #$1F
        AND
        SHL
        SHL
        SHL                         ; (r&31)<<3: the high byte's top five bits
        STA  RGBH
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  rgt_err
        INP2
        JSR  EXPR                   ; green
        LDA  RESULT
        LDB  #$3F
        AND
        STA  RESULT                 ; masked g, parked while both halves pack
        SHR
        SHR
        SHR                         ; g>>3: the high byte's low three bits
        LDB  RGBH
        OR
        STA  RGBH                   ; high byte complete
        LDA  RESULT
        LDB  #$07
        AND
        SHL
        SHL
        SHL
        SHL
        SHL                         ; (g&7)<<5: the low byte's top three bits
        PHA                         ; parked across the blue argument
        JSR  SKIPSP
        LDA  (P2)
        LDB  #','
        CMP
        JNZ  rgt_err
        INP2
        JSR  EXPR                   ; blue
        LDA  RESULT
        LDB  #$1F
        AND
        STA  RESULT                 ; b5
        PLA                         ; the green low bits, back off the stack
        LDB  RESULT
        OR
        STA  RESULT
        LDA  RGBH
        STA  RESULT+1
        RTS
rgt_err: JMP SYNERR

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
        JSR  APATH                     ; relative to the OS CWD, not the root
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
        LDB  #TOK_POINT
        CMP
        JZ   ckd_bad
        LDB  #TOK_RGB
        CMP
        JZ   ckd_bad
        LDB  #TOK_FILL
        CMP
        JZ   ckd_bad
        LDB  #TOK_NOFILL
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
; The 5x7 glyph table used by GTEXT. Generated -- see gen_font57.py.
        .include "font57.inc"

KWTAB:
        ; the GL verbs come FIRST: the fragment is longest-first inside
        ; itself, and ahead of the main table so POINT3 and CLEARS are
        ; matched before POINT and CLS ever get a look
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
        .byte $24,$A2               ; '$' then token: STR$
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
        .ascii "PLOT"
        .byte $AB
        .ascii "CIRCLE"
        .byte $AC
        .ascii "POINT"
        .byte $AE
        .ascii "GTEXT"
        .byte $AF
        .ascii "RGB"
        .byte $B1
        .ascii "IMAGE"
        .byte $B2
        .ascii "GL"
        .byte $B3
        .byte $00

        .include "glvtab.inc"

;==============================================================================
; Console
;==============================================================================
; SKIPSP — advance the parse cursor P2 past ASCII spaces. Stops on the first
; non-space (including the 00 line terminator). Clobbers A/B only.
SKIPSP: LDA  (P2)
        LDB  #' '
        CMP
        JNZ  sks
        INP2
        JMP  SKIPSP
sks:    RTS
; PUTC — emit the byte in A to the console through the BIOS (CONOUT, $0103).
;
; This used to drive the ACIA directly, a leftover from when BASIC could be built
; as the whole ROM with no monitor underneath it. Nothing builds that variant any
; more (every target passes -D BASORG=$2000 or $6A00, and the monitor ROM is
; always present at $0000-$1FFF), so going through the BIOS costs nothing and
; means BASIC inherits the console behaviour every other program gets — in
; particular PUTC's bare-LF -> CR LF expansion, without which BASIC's output
; staircases on a real serial terminal. Preserves A, as CONOUT does.
PUTC:   JMP  CONOUT                  ; tail call: CONOUT RTSs to PUTC's caller

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
; GETC — block until a key arrives, then return it in A. Through the BIOS
; (CONIN, $0100) for the same reason as PUTC above: one console implementation,
; shared by the monitor, the OS and BASIC.
GETC:   JMP  CONIN                   ; tail call: CONIN RTSs to GETC's caller
; PUTS — print the NUL-terminated string at (P1) to the console. Advances P1 past
; the terminator; uses PUTC (console only, never the data-file sink).
PUTS:   LDA  (P1)+
        JZ   putsx
        JSR  PUTC
        JMP  PUTS
putsx:  RTS
; CRLF — emit a carriage return + line feed to the console.
CRLF:   LDA  #CR
        JSR  PUTC
        LDA  #LF
        JSR  PUTC
        RTS
; GETLINE — read one console line into LBUF, echoing as typed. CR ends the line;
; backspace/DEL erase the last char (and rub it out on screen) but not past the
; start of LBUF. NUL-terminates the buffer and prints a trailing CRLF. Uses P2 as
; the write cursor. No length cap here — callers rely on LBUF being large enough.
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
        .ascii "GRAPHICS: COLOR p : LINE x0,y0,x1,y1 : CLS"
        .byte CR,LF
        .ascii "  BOX x0,y0,x1,y1[,FILL|,NOFILL]   PLOT x,y"
        .byte CR,LF
        .ascii "  CIRCLE x,y,r[,ry][,FILL]  POINT(x,y)  RGB(r,g,b)"
        .byte CR,LF
        .ascii "  GTEXT x,y,size,s$   (5x7 text, 80 cols at size 1)"
        .byte CR,LF
        .ascii "  IMAGE x,y,f$   draw a P8I image file (tools/p8img.py makes them)"
        .byte CR,LF
        .ascii "  SCREEN IS 480x272 RGB565 - COLOR R,G,B (0-31,0-63,0-31)"
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
