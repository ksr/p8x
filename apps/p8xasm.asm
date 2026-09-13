; =============================================================================
; P8X ASM - native two-pass assembler (standalone TPA program), Tier A edition
; =============================================================================
;     RUN ASM.BIN SRC.ASM OUT.BIN
; Reads SRC.ASM from disk and writes the binary OUT, both through the BIOS
; file streams (FOPEN/FGETB for input, FWOPEN/FPUTB/FCLOSE for output), so
; neither is bounded by RAM -- the assembler even assembles its own source.
; Output carries load/exec 0, which the OS treats as the TPA base $6100 -- so a
; program written `.org $6100` is directly RUNnable after assembly.
;
; This is the 2026-09-12 from-scratch rewrite for the Tier A ISA. It is a
; drop-in for the original: same syntax, same error messages, and its output
; is byte-identical to the host assembler's (assembler/p8xasm.py) -- the test
; suite checks all three. What changed is HOW it works:
;
;   * 16-bit values live in word variables and are handled with the word ops
;     (ADDW/SUBW/CMPW/INCW/DECW/MOVW/LDW), not byte pairs with carry chains.
;   * The symbol table is a 256-bucket chained hash: an entry is name[12] +
;     value[2] + next[2] (16 bytes) and is read/written through (P2+d) --
;     `LDW CNT,(P2+12)` fetches a symbol's value in one instruction. A lookup
;     hashes the name (~200 cycles) and walks a chain of ~4 entries; the old
;     table scanned every entry, comparing all 12 bytes of each (~25,000
;     cycles per lookup on a 1,000-symbol source).
;   * The opcode table is indexed by first letter at startup (LETIDX), so a
;     mnemonic lookup scans only its letter group (35 entries at worst, for
;     'L') instead of all ~140; the shape byte is compared before the name.
;   * Operand emission is table-driven: DISPTAB maps the operand shape to its
;     emitter, entered with `LPW1 CUR / JSR (P1)` -- no compare chain.
;   * MOVW and LDPn no longer need special cases: PARSEOP classifies two
;     operands generically, and a lone `#` immediate that fails as imm8 is
;     retried as the imm16 shape (that is how LDPn #w resolves).
;   * `.org` does the forward zero-padding itself (and reports a backward .org
;     on the .org line); EMIT is a plain "write one byte, PC++".
;   * Fixed-size copies are MOVW/STW sequences, not byte loops; the 32-byte
;     token buffers are cleared with 16 LDW #0.
;
; Supported syntax (a subset of the host assembler, same encodings):
;   label:                 define label = PC
;   NAME = expr            equate
;   MNEMONIC operands      operand: #expr | (Pn) | (Pn)+ | (Pn+d) | expr | none;
;                          two-operand forms a,a  a,#imm  a,(Pn+d)  (Pn+d),a
;                          (imm8 vs imm16 follows the host's lit8() text rule)
;   LDPn #expr16           the 3-byte LDPn opcode + imm16
;   .org .byte .word .ascii .asciiz .fill
;   .include "path"        at line start: append the file (resolved relative to
;                          THIS source's directory, so `.include "../x/y.inc"`
;                          works) after the source. Equates are order-independent
;                          (two-pass), so an EOF-append matches an inline splice.
;                          One per file.
;   ;#use NAME  (at line start) append /lib/NAME.inc after the source, so a
;                          command shares helpers (stdin/glob/regex) just as
;                          the host mkasm.sh splices lib_NAME.inc. Up to 4 per
;                          file, read in the order declared.
;   expr: $hex | decimal | 'c' | symbol, joined with + / -, optional </> prefix
;
; The opcode table (OPCTAB) is generated from genucode.OPC by
; generators/gen_p8xopc.py and concatenated after this source at build time.
; Record: .byte shape,opcode / .ascii "MNEMONIC" / .byte 0; $FF ends the table.
; It is sorted by mnemonic, which the first-letter index relies on.
;
; Conventions: P1 is the line cursor while a line is being parsed; routines
; that borrow P1 (OPCFIND, the emitters) reload it from OP1P/OP2P/DISPP, the
; cursors PARSEOP recorded. P2 is scratch everywhere. P3 is the system stack.
; EMIT preserves P1 (FPUTB clobbers it). Word ops clobber A ("A!" on the ISA
; card) -- never keep a value in A across one.
;
; Memory (code + OPCTAB must stay below SYMTAB = $8000; os_asm_test checks):
;   $6100-$7FFF code + opcode table       $C900-$CAFF SECBUF (source sector)
;   $8000-$C5FF SYMTAB 1120 x 16 bytes    $CB00-$CB7F LINEBUF (<=127 chars)
;   $C600-$C7FF HEADS  256 chain heads    $CC00-$CDFF INCBUF (include sector)
;   $C800-$C8FF variables                 $CE00-$CFFF BIOS directory-scan page
;   $D000-$D1FF path buffers              $D200-      free up to the stack
; Limits: 1120 symbols, 12-char names, 127-char source lines, single .org,
; 4 ;#use + 1 .include per file.
; =============================================================================

; ---- BIOS / OS ----
CONOUT  = $0103
PUTS    = $0112
FFIND   = $0118   ; confirm the source exists (reports a missing source)
FDELETE = $011E   ; tombstone an existing output file (overwrite = delete + create)
FOPEN   = $0124   ; open the read stream on FNAME in DIRLBA (P1 = 512-byte buffer)
FGETB   = $0127   ; next byte of the read stream -> A; C=1 at EOF. Clobbers P1
FWOPEN  = $012A   ; open the output write stream
FPUTB   = $012D   ; append A to the write stream. Clobbers P1
FCLOSE  = $0130   ; flush + register the output file FNAME; C=1 if the volume is full
FRESOLVE= $0133   ; resolve a path (P1) -> DIRLBA/DIRN/DIRLBA1 + leaf FNAME; C=1 if no dir
FSDIRBUF= $0145   ; repoint directory scans (FSCAN/FFIND/FNEXT) at page A
SYS_GETCWD = $2003 ; OS: write the CWD path (NUL-terminated) to (P1)
FNAME   = $604A   ; BIOS: current file name (12)
DIRLBA  = $6073   ; BIOS: current directory start LBA low
DIRN    = $6074   ; BIOS: current directory sector count (DIRLBA+1)
DIRLBA1 = $6080   ; BIOS: current directory start LBA high

CR      = $0D
LF      = $0A
QUOTE   = $22
TICK    = $27

; ---- word variables ($C800 page; pairs are little-endian words) ----
PC      = $C800   ; current program counter
ORGBASE = $C802   ; address of output byte 0 (the first .org)
VAL     = $C804   ; expression result
CNT     = $C806   ; term value (RDTERM) / symbol value (SYMFIND)
TERM    = $C808   ; scratch word (decimal x10)
SYMP    = $C80A   ; symbol-table append pointer
CUR     = $C80C   ; chain / table cursor, dispatch vector
HEADP   = $C80E   ; address of the chain head the last SYMFIND used
HEAD0   = $C810   ; the value that head held (first entry of the chain)
SAVP    = $C812   ; EMIT: P1 save around FPUTB
SP0     = $C814   ; system SP at entry (error abort long-jumps back to the OS)
OP1P    = $C816   ; PARSEOP: line cursor at operand 1's expression
OP2P    = $C818   ; PARSEOP: line cursor at operand 2's expression
DISPP   = $C81A   ; PARSEOP: line cursor at a (Pn+d) displacement expression
FILLN   = $C81C   ; .fill count
P2SAV   = $C81E   ; SRCGET: NEXTLINE's P2 across NEXTUSE
ABDST   = $C820   ; ABSPATH destination
ACSAV   = $C822   ; PARSEARGS: arg cursor across ABSPATH
PATHSAV = $C824   ; CHKINC: LINEBUF path cursor across CI_PREFIX
LSPOS   = $C826   ; CHKINC: INCPATH position just after the source dir's last '/'
; ---- byte variables ----
PASS    = $C830   ; 0 = pass 1 (symbols), 1 = pass 2 (emit)
SHAPE   = $C831   ; operand shape code (see PARSEOP)
SHAPE2  = $C832   ; PARSEOP: operand 1's shape while operand 2 is classified
OPCB    = $C833   ; resolved opcode byte
TMP     = $C834
SIGN    = $C835   ; EVAL: 1 = add the next term, 0 = subtract
HILO    = $C836   ; EVAL: 0 none, 1 '<' low byte, 2 '>' high byte
ORGSET  = $C837   ; 1 once the first .org fixed ORGBASE
HASH    = $C838   ; SYMHASH result
LEOF    = $C839   ; 1 when NEXTLINE hit the end of the source (+ includes)
SB2     = $C83A   ; EMIT: the byte being written
FVAL    = $C83B   ; .fill byte value
USECOUNT= $C83C   ; ;#use names recorded this pass
USEDONE = $C83D   ; how many of them have been opened
INCHAVE = $C83E   ; 1 = a .include was recorded this pass
INCDONE = $C83F   ; 1 = it has been opened
DIG     = $C840   ; small counter
LASTC   = $C841   ; OPCINDEX: letter of the group being indexed
NAMBUF  = $C850   ; identifier as written (16; 12 used, NUL-padded)
MNBUF   = $C860   ; the same, upcased (16) -- NAMBUF+16, so READTOK fills both
                  ; through one pointer: STA (P2) / STA (P2+16)
LETIDX  = $C880   ; 26 words: first OPCTAB record per initial letter, 0 = none
OUTDIR  = $C8C0   ; output parent dir stashed by OUTINIT: DIRLBA, DIRN, DIRLBA1 (3)
SRCDIR  = $C8C4   ; the source's dir context: DIRLBA, DIRN, DIRLBA1 (3)
OUTFN   = $C8D0   ; output leaf name stashed by OUTINIT (12)
SRCFN   = $C8E0   ; the source's own FNAME (12), so PASSINIT re-opens it each pass

; ---- buffers ----
SYMTAB  = $8000   ; 16-byte entries: name[12] + value[2] + next[2]
SYMEND  = $C600   ; symbol-table limit
HEADS   = $C600   ; 256 chain heads (words), indexed by SYMHASH
SECBUF  = $C900   ; source read-stream sector (512)
LINEBUF = $CB00   ; current source line (NUL-terminated, <=127 chars)
INCBUF  = $CC00   ; include read-stream sector (512) -- its own page, so the
                  ; source stream's state in SECBUF is untouched
DIRPAGE = $CE     ; BIOS directory-scan page ($CE00-$CFFF), off the shared SBUF
                  ; so a ;#use FOPEN in pass 2 cannot clobber the write stream
SRCPATH = $D000   ; full SRC path (NUL-terminated, absolute)
OUTPATH = $D030   ; full OUT path
ARGTMP  = $D060   ; raw path argument before ABSPATH
INCPATH = $D090   ; resolved absolute .include path (<=128)
UPATH   = $D110   ; built ;#use path "/lib/NAME.inc"
USELIST = $D140   ; 4 x 16: the ;#use names (NUL-terminated)

        .org $6100
; =============================================================================
; Main
; =============================================================================
START:  TPA3L                   ; remember SP: an error long-jumps back to the OS
        STA  SP0
        TPA3H
        STA  SP0+1
        LDA  #DIRPAGE
        JSR  FSDIRBUF
        JSR  PARSEARGS          ; SRCPATH / OUTPATH <- the two arguments
        LDA  OUTPATH
        JZ   ST_USAGE
        LDP1 #SRCPATH
        JSR  FRESOLVE           ; DIRLBA.. = the source's directory, FNAME = its leaf
        JC   ST_NOSRC
        JSR  SAVESRC            ; keep them: FFIND ends in FRESET (back to root),
        JSR  FFIND              ;   and a ;#use re-resolves FNAME/DIRLBA
        JC   ST_NOSRC
        JSR  OPCINDEX           ; first-letter index over OPCTAB
        JSR  SYMINIT            ; empty symbol table
        LDA  #0                 ; ---- pass 1: define every symbol ----
        STA  PASS
        STA  ORGSET
        LDW  ORGBASE,#0
        JSR  ASSEMBLE
        JSR  OUTINIT            ; ---- pass 2: emit, streamed to disk ----
        LDA  #1
        STA  PASS
        JSR  ASSEMBLE
        JSR  FINISHOUT
        JC   ST_WERR
        LDP1 #MOK
        JSR  PUTS
        RTS
ST_USAGE:
        LDP1 #MUSAGE            ; balanced stack here: plain RTS to the shell
        JSR  PUTS
        RTS
ST_NOSRC:
        LDP1 #ENOSRC
        JMP  ASM_ERR
ST_WERR:LDP1 #EWRITE
        JMP  ASM_ERR

; SYMINIT - empty the symbol table: all 256 chain heads = 0, append pointer at
;   the start. (Pass 2 keeps the table and only updates values.)
SYMINIT:LDW  SYMP,#SYMTAB
        LDP2 #HEADS
SI_LP:  LDA  #0
        STA  (P2)+
        TPA2H
        LDB  #>HEADS+512        ; the page after the two HEADS pages ($C8)
        CMP
        JNZ  SI_LP
        RTS

; OPCINDEX - LETIDX[c-'A'] = address of the first OPCTAB record whose mnemonic
;   starts with c (the table is sorted, so each letter's records are contiguous).
OPCINDEX:
        LDP2 #LETIDX
        LDA  #52
        STA  DIG
OI_Z:   LDA  #0
        STA  (P2)+
        LDA  DIG
        DEC
        STA  DIG
        JNZ  OI_Z
        LDA  #0
        STA  LASTC
        LDP2 #OPCTAB
OI_LP:  LDA  (P2)               ; shape byte; $FF = end of table
        LDB  #$FF
        CMP
        JZ   OI_RET
        LDA  (P2+2)             ; first letter of the mnemonic
        LDB  LASTC
        CMP
        JZ   OI_SKIP            ; same group as the previous record
        STA  LASTC
        LDB  #'A'
        SUB
        SHL                     ; word index -> byte offset (LETIDX is in one page)
        LDB  #<LETIDX
        ADD
        TAP1L
        LDA  #>LETIDX
        TAP1H
        TPA2L
        STA  (P1)+
        TPA2H
        STA  (P1)
OI_SKIP:INP2                    ; skip shape, opcode, name, NUL
        INP2
OI_NM:  LDA  (P2)+
        JNZ  OI_NM
        JMP  OI_LP
OI_RET: RTS

; =============================================================================
; Line driver
; =============================================================================
ASSEMBLE:
        MOVW PC,ORGBASE         ; pass 1: 0 until the first .org; pass 2: the origin
        JSR  PASSINIT
PROCLINE:
        JSR  NEXTLINE           ; LINEBUF <- next source line
        LDA  LEOF
        JNZ  ASM_RET
        LDP1 #LINEBUF
PL_SOL: JSR  SKIPSP
        LDA  (P1)
        JZ   PROCLINE           ; blank line
        LDB  #$3B               ; ';' comment-only line
        CMP
        JZ   PROCLINE
PL_TOK: JSR  READTOK            ; NAMBUF / MNBUF <- identifier
        JSR  SKIPSP
        LDA  (P1)
        LDB  #':'
        CMP
        JZ   PL_LABEL
        LDB  #'='
        CMP
        JZ   PL_EQU
        JSR  DOINSTR
        JMP  PROCLINE           ; the rest of the line (a comment) is discarded
PL_LABEL:
        INP1                    ; ':'
        LDA  PASS
        JNZ  PL_LBSK            ; pass 2: labels are already defined
        MOVW VAL,PC
        JSR  SYMDEF
PL_LBSK:JSR  SKIPSP
        LDA  (P1)
        JZ   PROCLINE
        LDB  #$3B
        CMP
        JZ   PROCLINE
        JMP  PL_TOK             ; an instruction after the label
PL_EQU: INP1                    ; '='
        JSR  SKIPSP
        JSR  EVAL
        JSR  SYMDEF
        JMP  PROCLINE
ASM_RET:RTS

; =============================================================================
; Instruction / directive dispatch
; =============================================================================
DOINSTR:LDA  MNBUF
        LDB  #'.'
        CMP
        JZ   DO_DIR
        JSR  PARSEOP            ; SHAPE + operand cursors
        JSR  OPCFIND            ; (MNBUF, SHAPE) -> OPCB
        JNZ  DI_OK
        LDA  SHAPE              ; a lone #imm that has no imm8 form: try imm16
        LDB  #1                 ;   (this is how LDPn #w resolves)
        CMP
        JNZ  DI_ERR
        LDA  #9
        STA  SHAPE
        JSR  OPCFIND
        JZ   DI_ERR
DI_OK:  LDA  OPCB
        JSR  EMIT
        LDA  SHAPE              ; P2 = &DISPTAB[SHAPE]
        SHL
        LDB  #<DISPTAB
        ADD
        TAP2L
        LDA  #0
        ROL                     ; the carry of that add
        LDB  #>DISPTAB
        ADD
        TAP2H
        LDW  CUR,(P2+0)
        LPW1 CUR
        JSR  (P1)               ; emit the operand bytes for this shape
        RTS
DI_ERR: LDP1 #EBADOP
        JMP  ASM_ERR

; Operand emitters, by shape. Each reloads P1 from the cursor it needs. The
; byte order is the host's: every 16-bit address first, then the imm8/imm16 or
; the displacement -- so `STW (P3+d),a` emits a before d like the host does.
DISPTAB:.word DI_NONE,DI_IMM,DI_ABS               ; 0 implied, 1 #imm8, 2 abs
        .word DI_NONE,DI_NONE,DI_NONE             ; 3..5 (P1) (P1)+ (P2)
        .word DI_NONE,DI_NONE,DI_NONE             ; 6..8 (P2)+ (P3) (P3)+
        .word DI_ABS                              ; 9  #imm16
        .word DI_AA,DI_AI8,DI_AA                  ; 10 a,a  11 a,#imm8  12 a,#imm16
        .word DI_PD,DI_PD,DI_PD                   ; 13..15 (Pn+d)
        .word DI_APD,DI_APD,DI_APD                ; 16..18 a,(Pn+d)
        .word DI_PDA,DI_PDA,DI_PDA                ; 19..21 (Pn+d),a
DI_NONE:RTS
DI_IMM: LPW1 OP1P               ; imm8 at operand 1
DI_IMM1:JSR  EVAL
        LDA  VAL
        JMP  EMIT
DI_ABS: LPW1 OP1P               ; 16-bit at operand 1
DI_ABS1:JSR  EVAL
        LDA  VAL
        JSR  EMIT
        LDA  VAL+1
        JMP  EMIT
DI_AA:  JSR  DI_ABS             ; operand 1 word, operand 2 word
DI_ABS2:LPW1 OP2P
        JMP  DI_ABS1
DI_AI8: JSR  DI_ABS             ; operand 1 word, operand 2 imm8
        LPW1 OP2P
        JMP  DI_IMM1
DI_PD:  LPW1 DISPP              ; the displacement byte
        JMP  DI_IMM1
DI_APD: JSR  DI_ABS             ; a,(Pn+d): address, then d
        JMP  DI_PD
DI_PDA: JSR  DI_ABS2            ; (Pn+d),a: the address (operand 2) first, then d
        JMP  DI_PD

; ---- directives ----
DO_DIR: LDA  MNBUF+1
        LDB  #'O'
        CMP
        JZ   DD_ORG
        LDB  #'B'
        CMP
        JZ   DD_BYTE
        LDB  #'W'
        CMP
        JZ   DD_WORD
        LDB  #'A'
        CMP
        JZ   DD_ASC
        LDB  #'F'
        CMP
        JZ   DD_FILL
        JMP  DI_ERR
; .org: pass 1 fixes ORGBASE on the first one; pass 2 zero-pads forward to the
; new origin (a backward .org cannot be represented in a streamed output).
DD_ORG: JSR  EVAL
        LDA  PASS
        JNZ  DO_ORG2
        LDA  ORGSET
        JNZ  DO_SET
        MOVW ORGBASE,VAL
        LDA  #1
        STA  ORGSET
DO_SET: MOVW PC,VAL
        RTS
DO_ORG2:CMPW VAL,PC
        JNC  DO_BACK            ; VAL < PC
DO_PAD: CMPW PC,VAL
        JC   DD_RET             ; PC >= VAL: there
        LDA  #0
        JSR  EMIT
        JMP  DO_PAD
DO_BACK:LDP1 #EBACK
        JMP  ASM_ERR
DD_BYTE:JSR  EVAL
        LDA  VAL
        JSR  EMIT
        JSR  COMMA
        JC   DD_BYTE
DD_RET: RTS
DD_WORD:JSR  EVAL
        LDA  VAL
        JSR  EMIT
        LDA  VAL+1
        JSR  EMIT
        JSR  COMMA
        JC   DD_WORD
        RTS
DD_FILL:JSR  EVAL
        MOVW FILLN,VAL
        LDA  #0
        STA  FVAL               ; fill value defaults to 0
        JSR  COMMA
        JNC  DF_GO
        JSR  EVAL
        LDA  VAL
        STA  FVAL
DF_GO:  CMPW FILLN,#0
        JZ   DD_RET
        LDA  FVAL
        JSR  EMIT
        DECW FILLN
        JMP  DF_GO
DD_ASC: JSR  SKIPSP
        LDA  (P1)
        LDB  #QUOTE
        CMP
        JNZ  DI_ERR
        INP1
DA_LP:  LDA  (P1)+
        JZ   DI_ERR             ; unterminated string
        LDB  #QUOTE
        CMP
        JZ   DA_CLOSE
        LDB  #$5C               ; a backslash escape, as the host assembler
        CMP                     ;   decodes them: \n \t \r \0, else the char
        JNZ  DA_EM              ;   itself (\\ \" \')
        LDA  (P1)+
        JZ   DI_ERR
        LDB  #'n'
        CMP
        JNZ  DA_E1
        LDA  #$0A
        JMP  DA_EM
DA_E1:  LDB  #'t'
        CMP
        JNZ  DA_E2
        LDA  #$09
        JMP  DA_EM
DA_E2:  LDB  #'r'
        CMP
        JNZ  DA_E3
        LDA  #$0D
        JMP  DA_EM
DA_E3:  LDB  #'0'
        CMP
        JNZ  DA_EM
        LDA  #0
DA_EM:  JSR  EMIT
        JMP  DA_LP
DA_CLOSE:
        LDA  MNBUF+6            ; .ASCIIZ -> trailing NUL
        LDB  #'Z'
        CMP
        JNZ  DD_RET
        LDA  #0
        JMP  EMIT

; COMMA - skip blanks; at a ',' step over it and the blanks after it, C=1;
;   otherwise C=0 with P1 on the non-blank.
COMMA:  JSR  SKIPSP
        LDA  (P1)
        LDB  #','
        CMP
        JNZ  CM_NO
        INP1
        JSR  SKIPSP
        SEC
        RTS
CM_NO:  CLC
        RTS

; =============================================================================
; Operand shapes
; =============================================================================
; PARSEOP - classify the operand field at P1 -> SHAPE, recording the line
;   cursors OP1P (operand 1's expression), OP2P (operand 2's) and DISPP (a
;   (Pn+d) displacement). Shape codes (the OPCTAB's, from gen_p8xopc.py):
;     0 none  1 #  2 abs  3..8 (Pn)/(Pn)+  9 #imm16 (never from syntax)
;     10 a,a  11 a,#imm8  12 a,#imm16  13..15 (Pn+d)  16..18 a,(Pn+d)
;     19..21 (Pn+d),a
;   imm8 vs imm16 (11 vs 12) follows the host's lit8() rule on the operand
;   TEXT, never the value, so both assemblers agree. P1 is left wherever the
;   classification stopped; the emitters reload the cursor they need.
PARSEOP:JSR  CLASSOP            ; operand 1
        TPA1L
        STA  OP1P
        TPA1H
        STA  OP1P+1
        LDA  SHAPE
        STA  SHAPE2
PO_SCN: LDA  (P1)               ; scan operand 1 for a ',' (a 'c' literal may be ',')
        JZ   PO_RET
        LDB  #CR
        CMP
        JZ   PO_RET
        LDB  #LF
        CMP
        JZ   PO_RET
        LDB  #$3B
        CMP
        JZ   PO_RET
        LDB  #TICK
        CMP
        JNZ  PO_SC2
        INP1                    ; step over the quoted character
        INP1
        JMP  PO_SC3
PO_SC2: LDB  #','
        CMP
        JZ   PO_TWO
PO_SC3: INP1
        JMP  PO_SCN
PO_TWO: INP1                    ; ','
        JSR  SKIPSP
        JSR  CLASSOP            ; operand 2
        TPA1L
        STA  OP2P
        TPA1H
        STA  OP2P+1
        LDA  SHAPE2
        LDB  #2
        CMP
        JNZ  PO_C2              ; operand 1 not abs: must be (Pn+d),a
        LDA  SHAPE              ; operand 1 abs; operand 2:
        LDB  #2
        CMP
        JZ   PO_AA              ;   abs      -> a,a
        LDB  #1
        CMP
        JZ   PO_AI              ;   #        -> a,#imm8 / a,#imm16
        JSR  ISPD
        JNC  DI_ERR
        LDA  SHAPE              ;   (Pn+d)   -> 16..18
        LDB  #3
        ADD
        STA  SHAPE
        RTS
PO_AA:  LDA  #10
        STA  SHAPE
        RTS
PO_AI:  LPW1 OP2P
        JSR  LIT8               ; A = 1 byte literal / 0 not
        STA  TMP
        LDA  #12
        LDB  TMP
        SUB                     ; 11 if a byte literal, else 12
        STA  SHAPE
        RTS
PO_C2:  LDA  SHAPE2             ; (Pn+d),a: operand 1 in 13..15 ...
        JSR  ISPD
        JNC  DI_ERR
        LDA  SHAPE              ; ... operand 2 abs
        LDB  #2
        CMP
        JNZ  DI_ERR
        LDA  SHAPE2
        LDB  #6                 ; 13..15 -> 19..21
        ADD
        STA  SHAPE
PO_RET: RTS

; ISPD - C=1 if A is a (Pn+d) shape (13..15).
ISPD:   LDB  #13
        CMP
        JNC  IP_NO
        LDB  #16
        CMP
        JC   IP_NO
        SEC
        RTS
IP_NO:  CLC
        RTS

; CLASSOP - classify ONE operand at P1 -> SHAPE: 0 none, 1 #, 2 abs, 3..8
;   (Pn)/(Pn)+, 13..15 (Pn+d) (DISPP = its displacement expression). Leaves P1
;   at the expression for # / abs, after the ')' / '+' otherwise.
CLASSOP:LDA  (P1)
        JZ   CO_IMP
        LDB  #CR
        CMP
        JZ   CO_IMP
        LDB  #LF
        CMP
        JZ   CO_IMP
        LDB  #$3B
        CMP
        JZ   CO_IMP
        LDB  #'#'
        CMP
        JZ   CO_IMM
        LDB  #'('
        CMP
        JZ   CO_PTR
        LDA  #2
        STA  SHAPE
        RTS
CO_IMP: LDA  #0
        STA  SHAPE
        RTS
CO_IMM: INP1
        LDA  #1
        STA  SHAPE
        RTS
CO_PTR: LDA  (P1+2)             ; "(Pn": the pointer digit
        LDB  #'0'
        SUB
        STA  TMP                ; n
        LDA  (P1+3)
        LDB  #'+'
        CMP
        JZ   CO_DISP            ; (Pn+d)
        LDB  #')'
        CMP
        JNZ  DI_ERR
        LDA  (P1+4)
        LDB  #'+'
        CMP
        JZ   CO_PLUS            ; (Pn)+
        INP1                    ; past "(Pn)"
        INP1
        INP1
        INP1
        LDA  TMP                ; shape = 3 + (n-1)*2
        DEC
        SHL
        LDB  #3
        ADD
        STA  SHAPE
        RTS
CO_PLUS:INP1                    ; past "(Pn)+"
        INP1
        INP1
        INP1
        INP1
        LDA  TMP                ; shape = 4 + (n-1)*2
        DEC
        SHL
        LDB  #4
        ADD
        STA  SHAPE
        RTS
CO_DISP:INP1                    ; past "(Pn+": the displacement expression
        INP1
        INP1
        INP1
        TPA1L
        STA  DISPP
        TPA1H
        STA  DISPP+1
CO_DSK: LDA  (P1)+              ; skip to just past the closing ')'
        JZ   DI_ERR
        LDB  #')'
        CMP
        JNZ  CO_DSK
        LDA  TMP                ; shape = 13 + (n-1)
        LDB  #12
        ADD
        STA  SHAPE
        RTS

; LIT8 - is the immediate TEXT at P1 a byte-sized literal by the host's lit8()
;   rule?  <x  >x  $h $hh  0xh 0xhh  'c'  decimal 0..255 -- followed only by
;   blanks up to the end of the operand (NUL / CR / LF / ';'). Labels, longer
;   literals and expressions are 16-bit. A=1 yes / A=0 no (Z accordingly).
;   Advances P1 (the caller reloads it).
LIT8:   LDA  (P1)
        LDB  #'<'
        CMP
        JZ   L8_YES
        LDB  #'>'
        CMP
        JZ   L8_YES
        LDB  #TICK
        CMP
        JZ   L8_CHR
        LDB  #'$'
        CMP
        JZ   L8_HEX
        LDB  #'0'
        CMP
        JNC  L8_NO              ; < '0'
        LDB  #$3A
        CMP
        JC   L8_NO              ; > '9'
        LDB  #'0'
        CMP
        JNZ  L8_DEC             ; 1..9: decimal
        LDA  (P1+1)             ; "0x" hex, or a decimal with a leading 0
        LDB  #'x'
        CMP
        JZ   L8_0X
        LDB  #'X'
        CMP
        JZ   L8_0X
L8_DEC: JSR  RDDEC              ; CNT = the value, P1 past the digits
        LDA  CNT+1
        JNZ  L8_NO              ; > 255
        JMP  L8_TERM
L8_0X:  INP1
L8_HEX: INP1                    ; past '$' / 'x'
        LDA  #0
        STA  DIG
L8_HL:  LDA  (P1)
        JSR  HEXVAL
        JNC  L8_HEND
        LDA  DIG
        INC
        STA  DIG
        INP1
        JMP  L8_HL
L8_HEND:LDA  DIG
        JZ   L8_NO              ; no digits
        LDB  #3
        CMP
        JC   L8_NO              ; 3+ digits: 16-bit
        JMP  L8_TERM
L8_CHR: LDA  (P1+2)             ; 'c': the closing tick
        LDB  #TICK
        CMP
        JNZ  L8_NO
        INP1
        INP1
        INP1
L8_TERM:JSR  SKIPSP             ; only blanks may follow
        LDA  (P1)
        JZ   L8_YES
        LDB  #CR
        CMP
        JZ   L8_YES
        LDB  #LF
        CMP
        JZ   L8_YES
        LDB  #$3B
        CMP
        JZ   L8_YES
L8_NO:  LDA  #0
        RTS
L8_YES: LDA  #1
        RTS

; =============================================================================
; OPCFIND - (MNBUF, SHAPE) -> OPCB. A=1 found / A=0 not (Z accordingly).
;   Scans only the mnemonic's first-letter group (LETIDX), shape byte first.
;   Clobbers P1 and P2.
; =============================================================================
OPCFIND:LDA  MNBUF
        LDB  #'A'
        SUB
        JNC  OF_NF              ; below 'A'
        LDB  #26
        CMP
        JC   OF_NF              ; past 'Z'
        SHL
        LDB  #<LETIDX
        ADD
        TAP1L
        LDA  #>LETIDX
        TAP1H
        LDW  CUR,(P1+0)
        LDA  CUR+1
        JZ   OF_NF              ; no mnemonic starts with this letter
        LPW2 CUR
OF_LP:  LDA  (P2)               ; shape byte; $FF = end of table
        LDB  #$FF
        CMP
        JZ   OF_NF
        LDA  (P2+2)
        LDB  MNBUF
        CMP
        JNZ  OF_NF              ; left the letter group
        LDA  (P2)
        LDB  SHAPE
        CMP
        JNZ  OF_NEXT
        LDA  (P2+3)             ; the name, up to and including its NUL (<= 5
        LDB  MNBUF+1            ;   letters). After an equal CMP, A AND B = A,
        CMP                     ;   so `AND / JZ` asks "was that the NUL?"
        JNZ  OF_NEXT
        AND
        JZ   OF_HIT
        LDA  (P2+4)
        LDB  MNBUF+2
        CMP
        JNZ  OF_NEXT
        AND
        JZ   OF_HIT
        LDA  (P2+5)
        LDB  MNBUF+3
        CMP
        JNZ  OF_NEXT
        AND
        JZ   OF_HIT
        LDA  (P2+6)
        LDB  MNBUF+4
        CMP
        JNZ  OF_NEXT
        AND
        JZ   OF_HIT
        LDA  (P2+7)
        LDB  MNBUF+5
        CMP
        JNZ  OF_NEXT
        AND
        JZ   OF_HIT
OF_NEXT:INP2                    ; next record: past shape, opcode, name, NUL
        INP2
        INP2
OF_SK:  LDA  (P2)+
        JNZ  OF_SK
        JMP  OF_LP
OF_HIT: LDA  (P2+1)
        STA  OPCB
        LDA  #1
        RTS
OF_NF:  LDA  #0
        RTS

; =============================================================================
; Symbol table: 256 chains through 16-byte entries name[12] value[2] next[2]
; =============================================================================
; SYMHASH - HASH = hash of NAMBUF (rotate-add over its bytes up to the NUL);
;   P2 = &HEADS[HASH]. Clobbers A, B.
SYMHASH:LDP2 #NAMBUF
        LDA  #0
        STA  HASH
SH_LP:  LDA  (P2)+
        JZ   SH_D
        LDB  HASH
        ADD
        ROL                     ; rotate the sum left through the add's carry
        STA  HASH
        JMP  SH_LP
SH_D:   LDA  HASH
        SHL                     ; word index -> byte offset ...
        TAP2L
        LDA  #0
        ROL                     ; ... whose carry selects the second page
        LDB  #>HEADS
        ADD
        TAP2H
        RTS

; SYMFIND - look up NAMBUF. A=1 found (P2 = the entry, CNT = its value) or
;   A=0 (Z accordingly). HEADP/HEAD0 remember the chain head for SYMDEF.
SYMFIND:JSR  SYMHASH
        LEAW HEADP,(P2+0)
        LDW  HEAD0,(P2+0)
        MOVW CUR,HEAD0
SF_LP:  LDA  CUR+1
        JZ   SF_NF              ; end of chain (entries live above $8000)
        LPW2 CUR
        LDA  (P2)               ; 12 name bytes, first mismatch moves on
        LDB  NAMBUF
        CMP
        JNZ  SF_NX
        LDA  (P2+1)
        LDB  NAMBUF+1
        CMP
        JNZ  SF_NX
        LDA  (P2+2)
        LDB  NAMBUF+2
        CMP
        JNZ  SF_NX
        LDA  (P2+3)
        LDB  NAMBUF+3
        CMP
        JNZ  SF_NX
        LDA  (P2+4)
        LDB  NAMBUF+4
        CMP
        JNZ  SF_NX
        LDA  (P2+5)
        LDB  NAMBUF+5
        CMP
        JNZ  SF_NX
        LDA  (P2+6)
        LDB  NAMBUF+6
        CMP
        JNZ  SF_NX
        LDA  (P2+7)
        LDB  NAMBUF+7
        CMP
        JNZ  SF_NX
        LDA  (P2+8)
        LDB  NAMBUF+8
        CMP
        JNZ  SF_NX
        LDA  (P2+9)
        LDB  NAMBUF+9
        CMP
        JNZ  SF_NX
        LDA  (P2+10)
        LDB  NAMBUF+10
        CMP
        JNZ  SF_NX
        LDA  (P2+11)
        LDB  NAMBUF+11
        CMP
        JNZ  SF_NX
        LDW  CNT,(P2+12)        ; found: the value
        LDA  #1
        RTS
SF_NX:  LDW  CUR,(P2+14)        ; next in chain
        JMP  SF_LP
SF_NF:  LDA  #0
        RTS

; SYMDEF - define or update NAMBUF = VAL. A new entry is appended to the table
;   and pushed on the front of its chain. Preserves P1.
SYMDEF: JSR  SYMFIND
        JNZ  SD_UPD
        CMPW SYMP,#SYMEND-15    ; room for one more 16-byte entry?
        JC   SD_FULL
        LPW2 SYMP
        STW  (P2+0),NAMBUF      ; name (12 bytes, NUL-padded)
        STW  (P2+2),NAMBUF+2
        STW  (P2+4),NAMBUF+4
        STW  (P2+6),NAMBUF+6
        STW  (P2+8),NAMBUF+8
        STW  (P2+10),NAMBUF+10
        STW  (P2+12),VAL        ; value
        STW  (P2+14),HEAD0      ; next = the chain's old first entry
        LPW2 HEADP
        STW  (P2+0),SYMP        ; head = this entry
        ADDW SYMP,#16
        RTS
SD_UPD: STW  (P2+12),VAL
        RTS
SD_FULL:LDP1 #ESYMS
        JMP  ASM_ERR

; =============================================================================
; Expressions
; =============================================================================
; EVAL - expression at P1 -> VAL; P1 advanced past it.
;   [<|>] term { (+|-) term }   with term = $hex | decimal | 'c' | symbol
EVAL:   LDA  #0
        STA  HILO
        LDA  (P1)
        LDB  #'<'
        CMP
        JNZ  EV_GT
        LDA  #1
        STA  HILO
        INP1
        JMP  EV_INIT
EV_GT:  LDB  #'>'
        CMP
        JNZ  EV_INIT
        LDA  #2
        STA  HILO
        INP1
EV_INIT:LDW  VAL,#0
        LDA  #1
        STA  SIGN
EV_TERM:JSR  RDTERM             ; CNT = term
        LDA  SIGN
        JZ   EV_SUB
        ADDW VAL,CNT
        JMP  EV_OP
EV_SUB: SUBW VAL,CNT
EV_OP:  LDA  (P1)
        LDB  #'+'
        CMP
        JZ   EV_PLUS
        LDB  #'-'
        CMP
        JZ   EV_MINUS
        LDA  HILO
        JZ   EV_DONE
        LDB  #1
        CMP
        JNZ  EV_HI
        LDA  #0                 ; '<' low byte
        STA  VAL+1
        RTS
EV_HI:  LDA  VAL+1              ; '>' high byte
        STA  VAL
        LDA  #0
        STA  VAL+1
EV_DONE:RTS
EV_PLUS:LDA  #1
        STA  SIGN
        INP1
        JMP  EV_TERM
EV_MINUS:
        LDA  #0
        STA  SIGN
        INP1
        JMP  EV_TERM

; RDTERM - one term at P1 -> CNT; P1 advanced. An unknown symbol is 0 in pass
;   1 (a forward reference) and "?undefined" in pass 2.
RDTERM: LDW  CNT,#0
        LDA  (P1)
        LDB  #'$'
        CMP
        JZ   RT_HEX
        LDB  #TICK
        CMP
        JZ   RT_CHR
        LDB  #'0'
        CMP
        JNC  RT_SYM             ; < '0'
        LDB  #$3A
        CMP
        JNC  RD_LP              ; '0'..'9': decimal
RT_SYM: JSR  READTOK
        JSR  SYMFIND            ; CNT = value when found
        JNZ  RT_RET
        LDA  PASS
        JZ   RT_RET
        LDP1 #EUNDEF
        JMP  ASM_ERR
RT_HEX: INP1
RH_LP:  LDA  (P1)
        JSR  HEXVAL
        JNC  RT_RET             ; not a hex digit: done
        STA  TMP
        ADDW CNT,CNT            ; CNT = CNT*16 + nibble
        ADDW CNT,CNT
        ADDW CNT,CNT
        ADDW CNT,CNT
        LDA  CNT
        LDB  TMP
        OR
        STA  CNT
        INP1
        JMP  RH_LP
RT_CHR: INP1                    ; 'c'
        LDA  (P1)
        STA  CNT
        INP1
        LDA  (P1)
        LDB  #TICK
        CMP
        JNZ  RT_RET
        INP1
RT_RET: RTS

; RDDEC - decimal digits at P1 -> CNT (16-bit, wraps); P1 advanced.
RDDEC:  LDW  CNT,#0
RD_LP:  LDA  (P1)
        LDB  #'0'
        CMP
        JNC  RT_RET
        LDB  #$3A
        CMP
        JC   RT_RET             ; > '9'
        LDB  #'0'
        SUB
        STA  TMP                ; the digit
        ADDW CNT,CNT            ; x2
        MOVW TERM,CNT
        ADDW CNT,CNT            ; x4
        ADDW CNT,CNT            ; x8
        ADDW CNT,TERM           ; x10
        LDA  CNT
        LDB  TMP
        ADD
        STA  CNT
        JNC  RD_NC
        LDA  CNT+1
        INC
        STA  CNT+1
RD_NC:  INP1
        JMP  RD_LP

; HEXVAL - A = character -> A = its hex value with C=1; C=0 if not a hex digit.
HEXVAL: LDB  #'0'
        CMP
        JNC  HV_NO              ; < '0'
        LDB  #$3A
        CMP
        JNC  HV_DIG             ; '0'..'9'
        LDB  #'a'
        CMP
        JNC  HV_UP              ; already upper case
        LDB  #$20
        SUB                     ; a..z -> A..Z
HV_UP:  LDB  #'A'
        CMP
        JNC  HV_NO
        LDB  #'G'
        CMP
        JC   HV_NO              ; > 'F'
        LDB  #$37               ; 'A' - 10
        SUB                     ; leaves C=1 (no borrow)
        RTS
HV_DIG: LDB  #'0'
        SUB                     ; leaves C=1
        RTS
HV_NO:  CLC
        RTS

; =============================================================================
; Tokens
; =============================================================================
; READTOK - identifier at P1 -> NAMBUF (as written) and MNBUF (upcased), both
;   NUL-padded to 16; the first 12 characters are kept, the rest skipped.
READTOK:LDW  NAMBUF,#0          ; clear both buffers (32 bytes)
        LDW  NAMBUF+2,#0
        LDW  NAMBUF+4,#0
        LDW  NAMBUF+6,#0
        LDW  NAMBUF+8,#0
        LDW  NAMBUF+10,#0
        LDW  NAMBUF+12,#0
        LDW  NAMBUF+14,#0
        LDW  MNBUF,#0
        LDW  MNBUF+2,#0
        LDW  MNBUF+4,#0
        LDW  MNBUF+6,#0
        LDW  MNBUF+8,#0
        LDW  MNBUF+10,#0
        LDW  MNBUF+12,#0
        LDW  MNBUF+14,#0
        LDP2 #NAMBUF
        LDA  #12
        STA  DIG
RK_LP:  LDA  (P1)
        JSR  ISIDCH
        JNZ  RK_DONE
        LDA  DIG
        JZ   RK_NEXT            ; 12 stored: skip the rest of the name
        DEC
        STA  DIG
        LDA  (P1)
        STA  (P2)               ; as written ...
        JSR  UPCASE
        STA  (P2+16)            ; ... and upcased, 16 bytes along
        INP2
RK_NEXT:INP1
        JMP  RK_LP
RK_DONE:RTS

; ISIDCH - Z=1 if A is an identifier character [A-Za-z0-9_.]. A clobbered.
ISIDCH: LDB  #'.'
        CMP
        JZ   IC_YES
        LDB  #'_'
        CMP
        JZ   IC_YES
        LDB  #'0'
        CMP
        JNC  IC_NO
        LDB  #$3A
        CMP
        JNC  IC_YES             ; '0'..'9'
        LDB  #'A'
        CMP
        JNC  IC_NO
        LDB  #$5B
        CMP
        JNC  IC_YES             ; 'A'..'Z'
        LDB  #'a'
        CMP
        JNC  IC_NO
        LDB  #$7B
        CMP
        JNC  IC_YES             ; 'a'..'z'
IC_NO:  LDA  #1
        RTS
IC_YES: LDA  #0
        RTS

; UPCASE - A -> upper case if 'a'..'z', else unchanged.
UPCASE: LDB  #'a'
        CMP
        JNC  UC_R
        LDB  #$7B
        CMP
        JC   UC_R
        LDB  #$20
        SUB
UC_R:   RTS

; SKIPSP - advance P1 over blanks and tabs.
SKIPSP: LDA  (P1)
        LDB  #' '
        CMP
        JZ   SK_A
        LDB  #$09
        CMP
        JZ   SK_A
        RTS
SK_A:   INP1
        JMP  SKIPSP

; MATCH - does the text at P1 start with the NUL-terminated string at P2?
;   Z=1 yes (P1 just past it) / Z=0 no.
MATCH:  LDA  (P2)+
        JZ   MA_RET             ; pattern exhausted: match
        STA  TMP
        LDA  (P1)+
        LDB  TMP
        CMP
        JZ   MATCH
MA_RET: RTS

; =============================================================================
; Output
; =============================================================================
; EMIT - emit byte A: pass 1 only advances PC; pass 2 also writes it to the
;   output stream. Preserves P1 (FPUTB clobbers it).
EMIT:   STA  SB2
        LDA  PASS
        JZ   EM_ADV
        TPA1L
        STA  SAVP
        TPA1H
        STA  SAVP+1
        LDA  SB2
        JSR  FPUTB
        LPW1 SAVP
EM_ADV: INCW PC
        RTS

; OUTINIT - resolve the output path's parent dir + leaf NOW, before the write
;   stream is opened (a FRESOLVE while it is live would disturb its state),
;   stash them for FINISHOUT, delete any old file of that name, open the stream.
OUTINIT:LDP1 #OUTPATH
        JSR  FRESOLVE           ; parent must exist; the leaf may be new
        MOVW OUTDIR,DIRLBA      ; DIRLBA + DIRN
        LDA  DIRLBA1
        STA  OUTDIR+2
        MOVW OUTFN,FNAME        ; the leaf (12)
        MOVW OUTFN+2,FNAME+2
        MOVW OUTFN+4,FNAME+4
        MOVW OUTFN+6,FNAME+6
        MOVW OUTFN+8,FNAME+8
        MOVW OUTFN+10,FNAME+10
        JSR  FDELETE            ; overwrite semantics (C=1 "absent" is fine)
        JMP  FWOPEN

; FINISHOUT - restore the stashed dir + leaf and FCLOSE: flushes, writes the
;   directory entry (length = bytes written), bumps the free pointer. C=1 full.
FINISHOUT:
        MOVW DIRLBA,OUTDIR
        LDA  OUTDIR+2
        STA  DIRLBA1
        MOVW FNAME,OUTFN
        MOVW FNAME+2,OUTFN+2
        MOVW FNAME+4,OUTFN+4
        MOVW FNAME+6,OUTFN+6
        MOVW FNAME+8,OUTFN+8
        MOVW FNAME+10,OUTFN+10
        JMP  FCLOSE

; =============================================================================
; Source input: lines over the BIOS read stream, plus the ;#use / .include
; appends (read after the source is exhausted, so their code lands AFTER the
; program body -- exactly like the host `cat SRC lib_*.inc`).
; =============================================================================
; PASSINIT - (re)open the source for a pass and forget last pass's includes.
PASSINIT:
        JSR  RESTSRC            ; FNAME + dir context <- the source
        LDA  #0
        STA  USECOUNT
        STA  USEDONE
        STA  INCHAVE
        STA  INCDONE
        LDP1 #SECBUF
        JMP  FOPEN              ; existence was checked at startup

; NEXTLINE - LINEBUF <- the next line (NUL-terminated, newline stripped, at
;   most 127 chars kept). LEOF=1 when the source and its includes are exhausted.
;   ;#use / .include lines are recorded here and skipped.
NEXTLINE:
        LDP2 #LINEBUF
NL_LP:  JSR  SRCGET
        JC   NL_EOF
        LDB  #LF
        CMP
        JZ   NL_DONE
        LDB  #CR
        CMP
        JZ   NL_LP              ; CR of a CRLF
        STA  (P2)               ; store; only advance while the line has room
        TPA2L                   ;   (LINEBUF is page-aligned: low byte = length)
        LDB  #127
        CMP
        JC   NL_LP
        INP2
        JMP  NL_LP
NL_EOF: TPA2L
        JZ   NL_END             ; nothing read: the end
NL_DONE:LDA  #0                 ; a last line without a newline still counts
        STA  (P2)
        STA  LEOF
        JSR  CHKUSE
        JC   NEXTLINE
        JSR  CHKINC
        JC   NEXTLINE
        RTS
NL_END: LDA  #1
        STA  LEOF
        RTS

; SRCGET - FGETB, but at a file's EOF opens the next recorded include and
;   keeps reading. C=1 only when the source AND all includes are exhausted.
;   Preserves P2 (NEXTLINE's line cursor).
SRCGET: JSR  FGETB
        JNC  SG_RET
        TPA2L
        STA  P2SAV
        TPA2H
        STA  P2SAV+1
        JSR  NEXTUSE
        JC   SG_EOF
        LPW2 P2SAV
        JMP  SRCGET
SG_EOF: LPW2 P2SAV
        SEC
SG_RET: RTS

; NEXTUSE - open the next unread include (the ;#use names in order, then the
;   .include) on INCBUF: C=0 opened / C=1 none left.
NEXTUSE:LDA  USEDONE
        LDB  USECOUNT
        CMP
        JC   NU_INC             ; all ;#use done -> the .include
        JSR  USESLOT            ; A = low byte of USELIST[USEDONE]
        TAP1L
        LDA  #>USELIST
        TAP1H
        JSR  BUILDINC           ; UPATH = "/lib/NAME.inc"
        LDA  USEDONE
        INC
        STA  USEDONE
        LDP1 #UPATH
NU_OPEN:JSR  FRESOLVE
        JC   NU_ERR
        LDP1 #INCBUF
        JSR  FOPEN
        JC   NU_ERR
        CLC
        RTS
NU_INC: LDA  INCDONE
        LDB  INCHAVE
        CMP
        JC   NU_END             ; none recorded, or already opened
        LDA  #1
        STA  INCDONE
        LDP1 #INCPATH
        JMP  NU_OPEN
NU_END: SEC
        RTS
NU_ERR: LDP1 #EUSE
        JMP  ASM_ERR

; USESLOT - A = index -> A = low byte of USELIST + index*16 (one page).
USESLOT:SHL
        SHL
        SHL
        SHL
        LDB  #<USELIST
        ADD
        RTS

; BUILDINC - UPATH = "/lib/" + name at P1 + ".inc".
BUILDINC:
        MOVW UPATH,SLIB         ; "/lib/"
        MOVW UPATH+2,SLIB+2
        LDA  SLIB+4
        STA  UPATH+4
        LDP2 #UPATH+5
BI_CP:  LDA  (P1)+
        JZ   BI_EXT
        STA  (P2)+
        JMP  BI_CP
BI_EXT: STW  (P2+0),SINC        ; ".inc" + NUL
        STW  (P2+2),SINC+2
        LDA  #0
        STA  (P2+4)
        RTS

; CHKUSE - LINEBUF = ";#use NAME"? record the name, C=1 (skip the line); else C=0.
CHKUSE: LDP1 #LINEBUF
        JSR  SKIPSP
        LDP2 #SUSE
        JSR  MATCH
        JNZ  CK_NO
        LDA  (P1)               ; a blank must follow "use"
        LDB  #' '
        CMP
        JZ   CU_SP
        LDB  #$09
        CMP
        JNZ  CK_NO
CU_SP:  JSR  SKIPSP
        LDA  (P1)               ; the NAME; empty -> ignore
        JZ   CK_NO
        LDB  #CR
        CMP
        JZ   CK_NO
        JSR  ADDUSE
        SEC
        RTS
CK_NO:  CLC
        RTS

; ADDUSE - append the name at P1 (to a blank / CR / NUL) to USELIST[USECOUNT];
;   at most 4 are kept.
ADDUSE: LDA  USECOUNT
        LDB  #4
        CMP
        JC   AU_RET
        JSR  USESLOT
        TAP2L
        LDA  #>USELIST
        TAP2H
AU_CP:  LDA  (P1)
        JZ   AU_END
        LDB  #' '
        CMP
        JZ   AU_END
        LDB  #CR
        CMP
        JZ   AU_END
        LDB  #$09
        CMP
        JZ   AU_END
        STA  (P2)+
        INP1
        JMP  AU_CP
AU_END: LDA  #0
        STA  (P2)
        LDA  USECOUNT
        INC
        STA  USECOUNT
AU_RET: RTS

; CHKINC - LINEBUF = '.include "path"'? resolve the path (relative to the
;   source's directory) into INCPATH, C=1 (skip the line); else C=0. One per file.
CHKINC: LDA  INCHAVE
        JNZ  CK_NO
        LDP1 #LINEBUF
        JSR  SKIPSP
        LDP2 #SINCL
        JSR  MATCH
        JNZ  CK_NO
        JSR  SKIPSP
        LDA  (P1)
        LDB  #QUOTE
        CMP
        JNZ  CK_NO
        INP1                    ; the path text
        LDA  (P1)
        LDB  #'/'
        CMP
        JZ   CI_ABS             ; absolute: INCPATH from its start
        TPA1L
        STA  PATHSAV
        TPA1H
        STA  PATHSAV+1
        JSR  CI_PREFIX          ; INCPATH = the source's dir; P2 = append point
        LPW1 PATHSAV
        JMP  CI_CP
CI_ABS: LDP2 #INCPATH
CI_CP:  LDA  (P1)+              ; append the path up to the closing quote
        JZ   CI_END
        LDB  #QUOTE
        CMP
        JZ   CI_END
        STA  (P2)+
        JMP  CI_CP
CI_END: LDA  #0
        STA  (P2)
        LDA  #1
        STA  INCHAVE
        SEC
        RTS

; CI_PREFIX - INCPATH = SRCPATH up to and including its last '/'; P2 = the
;   position after it.
CI_PREFIX:
        LDP1 #SRCPATH
        LDP2 #INCPATH
        LDW  LSPOS,#INCPATH
CP_LP:  LDA  (P1)+
        JZ   CP_DONE
        STA  (P2)+
        LDB  #'/'
        CMP
        JNZ  CP_LP
        LEAW LSPOS,(P2+0)       ; just past this '/'
        JMP  CP_LP
CP_DONE:LPW2 LSPOS
        RTS

; SAVESRC / RESTSRC - the source's FNAME + directory context, so PASSINIT can
;   re-open it each pass whatever a ;#use / FFIND did to the BIOS state.
SAVESRC:MOVW SRCFN,FNAME
        MOVW SRCFN+2,FNAME+2
        MOVW SRCFN+4,FNAME+4
        MOVW SRCFN+6,FNAME+6
        MOVW SRCFN+8,FNAME+8
        MOVW SRCFN+10,FNAME+10
        MOVW SRCDIR,DIRLBA      ; DIRLBA + DIRN
        LDA  DIRLBA1
        STA  SRCDIR+2
        RTS
RESTSRC:MOVW FNAME,SRCFN
        MOVW FNAME+2,SRCFN+2
        MOVW FNAME+4,SRCFN+4
        MOVW FNAME+6,SRCFN+6
        MOVW FNAME+8,SRCFN+8
        MOVW FNAME+10,SRCFN+10
        MOVW DIRLBA,SRCDIR
        LDA  SRCDIR+2
        STA  DIRLBA1
        RTS

; =============================================================================
; Arguments
; =============================================================================
; PARSEARGS - P2 = the command tail "SRC OUT": SRCPATH / OUTPATH <- the two
;   words, made absolute.
PARSEARGS:
        JSR  ASKIP
        LDP1 #ARGTMP            ; raw SRC word
        JSR  PATHCOPY
        JSR  ASKIP
        TPA2L                   ; ABSPATH clobbers P2: keep the arg cursor
        STA  ACSAV
        TPA2H
        STA  ACSAV+1
        LDW  ABDST,#SRCPATH
        JSR  ABSPATH
        LPW2 ACSAV
        LDP1 #ARGTMP            ; raw OUT word
        JSR  PATHCOPY
        LDW  ABDST,#OUTPATH
        JMP  ABSPATH

; ABSPATH - (ABDST) <- ARGTMP made absolute: a leading '/' is copied as-is, a
;   relative path is prefixed with the CWD + '/' (FRESOLVE starts at root, not
;   the CWD). An empty argument stays empty (the "no arg -> usage" check).
ABSPATH:LPW1 ABDST
        LDA  ARGTMP
        JZ   AB_EMPTY
        LDB  #'/'
        CMP
        JZ   AB_CAT
        LDA  #0
        JSR  SYS_GETCWD         ; (P1) <- CWD, NUL-terminated
        LPW1 ABDST
AB_EN:  LDA  (P1)+              ; to the NUL
        JNZ  AB_EN
        DEP1
        DEP1                    ; the last CWD character
        LDA  (P1)+
        LDB  #'/'
        CMP
        JZ   AB_CAT             ; root "/" already ends in one
        LDA  #'/'
        STA  (P1)+
AB_CAT: LDP2 #ARGTMP
AB_CL:  LDA  (P2)+              ; append the argument, NUL included
        STA  (P1)+
        JNZ  AB_CL
        RTS
AB_EMPTY:
        STA  (P1)               ; A = 0
        RTS

; PATHCOPY - copy the word at P2 to (P1), NUL-terminated, up to a blank / CR /
;   NUL (case kept: the file system is case-sensitive). P2 stops on the delimiter.
PATHCOPY:
        LDA  (P2)
        JZ   PC_END
        LDB  #' '
        CMP
        JZ   PC_END
        LDB  #CR
        CMP
        JZ   PC_END
        STA  (P1)+
        INP2
        JMP  PATHCOPY
PC_END: LDA  #0
        STA  (P1)
        RTS

; ASKIP - advance P2 over blanks.
ASKIP:  LDA  (P2)
        LDB  #' '
        CMP
        JNZ  AS_D
        INP2
        JMP  ASKIP
AS_D:   RTS

; =============================================================================
; Error abort: message at P1, the offending line, CRLF; unwind to the shell
; =============================================================================
ASM_ERR:JSR  PUTS
        LDP1 #LINEBUF
AE_PL:  LDA  (P1)+
        JZ   AE_DONE
        LDB  #CR
        CMP
        JZ   AE_DONE
        LDB  #LF
        CMP
        JZ   AE_DONE
        JSR  CONOUT
        JMP  AE_PL
AE_DONE:LDA  #CR
        JSR  CONOUT
        LDA  #LF
        JSR  CONOUT
        LPW3 SP0                ; SP as it was at entry: RTS returns to the OS
        RTS

; =============================================================================
; Strings
; =============================================================================
MOK:    .ascii "OK"
        .byte CR,LF,0
MUSAGE: .ascii "USAGE: ASM SRC.ASM OUT.BIN"
        .byte CR,LF,0
ENOSRC: .asciiz "?no source: "
EWRITE: .asciiz "?write: "
EBADOP: .asciiz "?syntax: "
EUNDEF: .asciiz "?undefined: "
EBACK:  .asciiz "?backward .org: "
ESYMS:  .asciiz "?too many symbols: "
EUSE:   .asciiz "?missing #use include: "
SUSE:   .byte $3B               ; ";#use"  (the ';' as a byte: not a comment)
        .asciiz "#use"
SINCL:  .asciiz ".include"
SLIB:   .asciiz "/lib/"
SINC:   .asciiz ".inc"
; OPCTAB (generators/gen_p8xopc.py) is concatenated here at build time.
