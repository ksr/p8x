; =============================================================================
; P8X ASM - native two-pass assembler (standalone TPA program)
; =============================================================================
;     RUN ASM.BIN SRC.ASM OUT.BIN
; Reads SRC.ASM from disk and writes the binary OUT, both through the BIOS
; file streams (FOPEN/FGETB for input, FWOPEN/FPUTB/FCLOSE for output), so
; neither is bounded by RAM — the assembler even assembles its own source.
; Output carries load/exec 0, which the OS treats as the TPA base $6A00 — so a
; program written `.org $6A00` is directly RUNnable after assembly.
;
; Supported syntax (a subset of the host assembler, same encodings):
;   label:                 define label = PC
;   NAME = expr            equate
;   MNEMONIC [operand]     operand: #expr | (Pn) | (Pn)+ | expr | none
;   MOVW dst,src           the ISA's only TWO-operand instruction ($78): a 16-bit
;                          mem->mem word move, encoded op + dst16 + src16 (5 B).
;                          Handled as a special case before the ordinary
;                          one-operand path (as the host assembler does).
;   LDPn #expr16           pseudo -> LPLn #<expr ; LPHn #>expr
;   .org .byte .word .ascii .asciiz .fill
;   .include "path"        at line start: append the file (resolved relative to
;                          THIS source's directory, so `.include "../x/y.inc"`
;                          works) after the source. Equates are order-independent
;                          (two-pass), so an EOF-append matches an inline splice.
;                          One per file. Mirrors the host assembler's .include and
;                          lets /src/os-bios build the OS/monitor on-target (they
;                          .include "../generators/memmap.inc").
;   ;#use NAME             at line start: append /lib/NAME.inc after the source,
;                          so a command shares helpers (stdin/glob/regex) just as
;                          the host mkasm.sh splices lib_NAME.inc. Up to 4 per file,
;                          read in the order declared (each command lists each once).
;   expr: $hex | decimal | 'c' | symbol, joined with + / -, optional </> prefix
;
; The opcode table (OPCTAB) is generated from genucode.OPC by
; generators/gen_p8xopc.py and concatenated after this source at build time.
;
; Conventions: P1 is the source cursor (preserved across helper calls); P3 is
; the system stack (never touched); helpers needing a 2nd pointer save P1 first.
; Limits: ~1097 symbols, 12-char names, 127-char source lines, single .org.
; =============================================================================

; ---- BIOS ---- (file I/O now goes entirely through the read/write streams)
CONIN   = $0100
CONOUT  = $0103
PUTS    = $0112
PHEX8   = $0115
FFIND   = $0118   ; used once at startup to report a missing source
FOPEN   = $0124   ; open source for reading (P1 = 512-byte buffer)
FGETB   = $0127   ; next source byte -> A; C=1 at EOF
FDELETE = $011E   ; tombstone an existing file FNAME in DIRLBA (overwrite: del then create)
FWOPEN  = $012A   ; open the output write stream
FPUTB   = $012D   ; append a byte to the output stream
FCLOSE  = $0130   ; flush + register the output file FNAME; C=1 if full
FRESOLVE= $0133   ; resolve a path (P1) -> dir extent + leaf FNAME (for ;#use)
FSDIRBUF= $0145   ; repoint directory scans (FSCAN/FFIND/FNEXT) at page A
SYS_GETCWD = $2003 ; OS: write the CWD path (NUL-terminated) to (P1)
LBA     = $6047
LBA1    = $6048
LBA2    = $6049
FNAME   = $604A
FSRC    = $6056
FLEN    = $6058
; Directory context — saved at startup, restored each pass so PASSINIT re-opens
; the source even after a ;#use has re-resolved FNAME/DIRLBA to an include.
DIRLBA  = $6073   ; current directory start LBA low
DIRN    = $6074   ; current directory sector count
DIRLBA1 = $6080   ; current directory start LBA high

CR      = $0D
LF      = $0A
QUOTE   = $22
TICK    = $27

; ---- variables ($C800 page) ----
SRCP    = $C800   ; source scan cursor mirror
PC      = $C802   ; current program counter
ORGBASE = $C804   ; address of output byte 0
HIWAT   = $C806   ; highest PC reached (+1)
SYMP    = $C808   ; symbol-table append pointer
VAL     = $C80A   ; expression result
PASS    = $C80C
SHAPE   = $C80D
OPCB    = $C80E   ; resolved opcode byte
TMP     = $C80F
TMP2    = $C810
CNTL    = $C811
CNTH    = $C812
SIGN    = $C813   ; 1=+, 0=-
HILO    = $C814   ; 0 none, 1 <low, 2 >high
ORGSET  = $C815
FOUND   = $C816
LINEPL  = $C817
LINEPH  = $C818
DIG     = $C819
SAVP    = $C81A   ; P1 save (SYMFIND/OPCFIND)
SAVP2   = $C81C   ; P1 save (SYMDEFVAL)
EADDR   = $C81E   ; matched symbol value-field address
MTL     = $C820
MTH     = $C821
SP0     = $C822   ; saved system SP for error abort
LDPN    = $C824   ; LDPn pointer digit (survives EVAL, which trashes TMP/MNBUF)
MNBUF   = $C830   ; upcased mnemonic/directive (8)
NAMBUF  = $C840   ; identifier as written (16, 12 used)
OUTNAME = $C850   ; output file name (12, legacy — unused since paths went in)
SRCPATH = $C000   ; full SRC path arg (NUL-terminated, path-aware via FRESOLVE)
OUTPATH = $C030   ; full OUT path arg (NUL-terminated, path-aware via FRESOLVE)
OUTDIR  = $C060   ; output parent dir stashed at OUTINIT: DIRLBA, DIRLBA1, DIRN (3)
OUTFN   = $C063   ; output leaf name stashed at OUTINIT (12)
ARGTMP  = $C070   ; raw path arg before abspath (48)
ABDST   = $C0A0   ; abspath destination pointer (2)
ACSAV   = $C0A2   ; PARSEARGS: saved arg cursor across ABSPATH (2)
LEOF    = $C86A   ; 1 when NEXTLINE hits end of source
SB      = $C86B   ; current source byte from FGETB
LCNT    = $C86C   ; chars in the current line
SB2     = $C872   ; EMIT: byte being emitted
OUTPOS  = $C87A   ; total output bytes emitted (mirrors the write stream length)
OFFL    = $C87C   ; PC-ORGBASE low
OFFH    = $C87D   ; PC-ORGBASE high
SAVPE   = $C87F   ; EMIT P1 save (2)
FVAL    = $C881   ; .fill byte value (EMIT clobbers TMP, so .fill can't use it)

; ---- buffers ----
; The source is streamed a line at a time from disk (no whole-file buffer), so
; source size is bounded by the disk, not RAM. That frees the old 6.5 KB source
; buffer for a much larger symbol table.
; Output is streamed to disk a sector at a time (via the BIOS SBUF), so there is
; no output RAM buffer — output size is bounded by the disk too.
SECBUF  = $C900   ; one streamed source sector (512)
LINEBUF = $CB00   ; current source line (NUL-terminated, <=127 chars)
; Symbol table: the assembler binary loads at $6A00 and is only ~4.3 KB, so the
; whole gap from there up to the $C000 variable block is free. Parking the table
; there ($8400..$C000 = ~1097 symbols) gives far more room than the old slot
; above the buffers ($CC00..$FB00 = ~850), which a growing OS had outgrown — and
; it leaves $CC00..$FEFF entirely to the descending hardware stack.
SYMTAB  = $8400   ; 14-byte entries: name[12] + value[2]  (~1097 symbols)
SYMEND  = $C000   ; symbol-table limit (= start of the variable block above)
; ---- ;#use include support (sequential append, mirroring mkasm.sh) ----
; A ;#use line records a name; at the source's EOF the recorded includes are read
; in turn (over the same SECBUF — the source is done), so their code lands AFTER
; the program body, exactly like the host `cat SRC ; cat lib_*.inc`.
USECOUNT= $CB80   ; number of ;#use names recorded this pass
USEDONE = $CB81   ; how many recorded includes have been opened so far
UCNT    = $CB82   ; byte-copy counter for the helpers (1)
P2SAV   = $CB83   ; SRCGET saves NEXTLINE's P2 (line cursor) across NEXTUSE (2)
INCBUF  = $C400   ; include read buffer — a fresh 512-byte page, NOT the source's
                  ; SECBUF (reusing it leaves stale stream state), and clear of
                  ; the $C600 dir-scan page and SECBUF ($C900)
SRCFN   = $CB90   ; the source's own FNAME (12), so PASSINIT re-opens it each pass
SRCDIR  = $CB9C   ; the source's dir context: DIRLBA, DIRLBA1, DIRN (3)
UPATH   = $CBA0   ; built include path "/lib/NAME.inc" (24)
USELIST = $CBC0   ; up to 4 include names, 12 bytes each (NUL-terminated)
; .include "path" support: one per file, resolved relative to the source's dir
; (SRCPATH minus its leaf) and appended at EOF like ;#use. INCPATH lives in the
; free RAM window between the path args ($C0A4) and INCBUF ($C400).
INCPATH = $C100   ; resolved absolute include path (NUL-terminated, <=128)
INCHAVE = $C1A0   ; 1 = a .include was recorded this pass
INCDONE = $C1A1   ; 1 = the .include has been opened (spliced) this pass
PATHSAV = $C1A2   ; CHKINC: saved LINEBUF path cursor (2)
LSPOS   = $C1A4   ; CHKINC: INCPATH position just after the source dir's last '/' (2)

        .org $6A00
; =============================================================================
START:  TPA3L                   ; save SP so an error can long-jump back to OS
        STA  SP0
        TPA3H
        STA  SP0+1
        LDA  #$C6               ; repoint directory scans (FFIND) off SBUF, so a
        JSR  FSDIRBUF           ; ;#use FOPEN in pass 2 can't clobber the write
                                ; stream's partial output sector (shared SBUF)
        JSR  PARSEARGS          ; SRCPATH <- SRC, OUTPATH <- OUT (full paths)
        LDA  OUTPATH            ; no output path given -> show usage
        JZ   ST_USAGE
        LDP1 #SRCPATH           ; resolve the source path -> DIRLBA + FNAME(leaf)
        JSR  FRESOLVE
        JC   ST_NOSRC
        JSR  SAVESRC            ; remember the source's FNAME + dir BEFORE FFIND,
                                ; because FFIND ends in FRESET (reverts DIRLBA to
                                ; root). PASSINIT re-opens each pass from SRCDIR, so
                                ; a subdir source (e.g. /src/os-bios/asm/x.asm) must
                                ; save its true parent dir, not root. (FRESOLVE also
                                ; sets FNAME=leaf, which a later ;#use would clobber.)
        JSR  FFIND              ; confirm the leaf exists in the resolved dir
        JC   ST_NOSRC
        ; ---- pass 1: build symbol table ----
        LDA  #0
        STA  PASS
        STA  ORGSET
        STA  ORGBASE
        STA  ORGBASE+1
        LDA  #<SYMTAB
        STA  SYMP
        LDA  #>SYMTAB
        STA  SYMP+1
        JSR  INITPC
        JSR  ASSEMBLE
        ; ---- pass 2: emit (streamed to disk) ----
        JSR  OUTINIT            ; output LBA = free pointer; clear the sector buffer
        LDA  #1
        STA  PASS
        JSR  INITPC
        JSR  ASSEMBLE
        JSR  FINISHOUT          ; flush + register the file (dir entry + free bump)
        JC   ST_WERR
        LDP1 #MOK
        JSR  PUTS
        RTS
ST_USAGE:LDP1 #MUSAGE          ; balanced stack here -> plain RTS to the shell
        JSR  PUTS
        RTS
ST_NOSRC:LDP1 #ENOSRC
        JMP  ASM_ERR
ST_WERR:LDP1 #EWRITE
        JMP  ASM_ERR

; INITPC - reset PC and HIWAT to 0 at the start of each pass (ORGBASE/ORGSET are
;   cleared once, before pass 1, so a single .org fixes the load address).
INITPC: LDA  #0
        STA  PC
        STA  PC+1
        STA  HIWAT
        STA  HIWAT+1
        RTS

; =============================================================================
; Line driver
; =============================================================================
ASSEMBLE:
        JSR  PASSINIT           ; (re)start the source stream at the first sector
PROCLINE:
        JSR  NEXTLINE           ; LINEBUF <- next source line (NUL-terminated)
        LDA  LEOF
        JNZ  ASM_RET
        LDA  #<LINEBUF          ; P1 = line cursor; LINEP = line start (for errors)
        TAP1L
        STA  LINEPL
        LDA  #>LINEBUF
        TAP1H
        STA  LINEPH
PL_SOL: JSR  SKIPSP
        LDA  (P1)
        JZ   PROCLINE           ; blank line
        LDB  #$3B            ; ';'
        CMP
        JZ   PROCLINE           ; comment-only line
PL_TOK: JSR  READTOK
        JSR  SKIPSP
        LDA  (P1)
        LDB  #':'
        CMP
        JZ   PL_LABEL
        LDB  #'='
        CMP
        JZ   PL_EQU
        JMP  PL_INSTR
PL_LABEL:
        INP1                    ; consume ':'
        LDA  PASS
        JNZ  PL_LBSK            ; pass 2: labels already known
        LDA  PC
        STA  VAL
        LDA  PC+1
        STA  VAL+1
        JSR  SYMDEFVAL
PL_LBSK:JSR  SKIPSP
        LDA  (P1)
        JZ   PROCLINE
        LDB  #$3B            ; ';'
        CMP
        JZ   PROCLINE
        JMP  PL_TOK             ; trailing instruction after label
PL_EQU: INP1                    ; consume '='
        JSR  SKIPSP
        JSR  EVAL
        JSR  SYMDEFVAL
        JMP  PROCLINE
PL_INSTR:
        JSR  DOINSTR
        JMP  PROCLINE           ; rest of line (incl. comment) is discarded
ASM_RET:RTS

; =============================================================================
; Instruction / directive dispatch
; =============================================================================
DOINSTR:
        LDA  MNBUF              ; MOVW dst,src ? (the only two-operand instruction;
        LDB  #'M'              ;   handled inline since the rest is single-operand)
        CMP
        JNZ  DI_LDPQ
        LDA  MNBUF+1
        LDB  #'O'
        CMP
        JNZ  DI_LDPQ
        LDA  MNBUF+2
        LDB  #'V'
        CMP
        JNZ  DI_LDPQ
        LDA  MNBUF+3
        LDB  #'W'
        CMP
        JNZ  DI_LDPQ
        LDA  MNBUF+4
        JNZ  DI_LDPQ           ; exactly "MOVW"
        JMP  DO_MOVW
DI_LDPQ:LDA  MNBUF             ; LDPn pseudo?
        LDB  #'L'
        CMP
        JNZ  DI_NORM
        LDA  MNBUF+1
        LDB  #'D'
        CMP
        JNZ  DI_NORM
        LDA  MNBUF+2
        LDB  #'P'
        CMP
        JNZ  DI_NORM
        LDA  MNBUF+3
        LDB  #'1'
        CMP
        JNC  DI_NORM            ; < '1'
        LDA  #'3'
        LDB  MNBUF+3
        CMP
        JNC  DI_NORM            ; > '3'
        JMP  DO_LDP
DI_NORM:LDA  MNBUF
        LDB  #'.'
        CMP
        JZ   DO_DIR
        JSR  PARSEOP            ; -> SHAPE (P1 at expr for #/abs)
        JSR  OPCFIND            ; MNBUF+SHAPE -> OPCB, FOUND
        LDA  FOUND
        JNZ  DI_OK
        LDP1 #EBADOP
        JMP  ASM_ERR
DI_OK:  LDA  OPCB
        JSR  EMIT
        LDA  SHAPE
        LDB  #1
        CMP
        JZ   DI_IMM
        LDB  #2
        CMP
        JZ   DI_ABS
        RTS                     ; implied / (Pn): no operand bytes
DI_IMM: JSR  EVAL
        LDA  VAL
        JSR  EMIT
        RTS
DI_ABS: JSR  EVAL
        LDA  VAL
        JSR  EMIT
        LDA  VAL+1
        JSR  EMIT
        RTS

; ---- LDPn #imm16 -> LPLn #<imm ; LPHn #>imm ----
DO_LDP: LDA  MNBUF+3
        STA  LDPN               ; pointer digit char (survives EVAL)
        JSR  SKIPSP
        LDA  (P1)
        LDB  #'#'
        CMP
        JNZ  DL_ERR
        INP1
        JSR  EVAL               ; VAL = imm16 (clobbers MNBUF/TMP)
        LDA  #'L'               ; MNBUF = "LPLn"
        STA  MNBUF
        LDA  #'P'
        STA  MNBUF+1
        LDA  #'L'
        STA  MNBUF+2
        LDA  LDPN
        STA  MNBUF+3
        LDA  #0
        STA  MNBUF+4
        LDA  #1
        STA  SHAPE
        JSR  OPCFIND
        LDA  FOUND
        JZ   DL_ERR
        LDA  OPCB
        JSR  EMIT
        LDA  VAL
        JSR  EMIT
        LDA  #'H'               ; MNBUF = "LPHn"
        STA  MNBUF+2
        LDA  #1
        STA  SHAPE
        JSR  OPCFIND
        LDA  FOUND
        JZ   DL_ERR
        LDA  OPCB
        JSR  EMIT
        LDA  VAL+1
        JSR  EMIT
        RTS
DL_ERR: LDP1 #EBADOP
        JMP  ASM_ERR

; ---- MOVW dst,src -> opcode $78 + dst16 + src16 (two abs16 operands) ----
DO_MOVW:LDA  #$78
        JSR  EMIT               ; opcode
        JSR  SKIPSP
        JSR  EVAL               ; VAL = dst address
        LDA  VAL
        JSR  EMIT
        LDA  VAL+1
        JSR  EMIT
        JSR  SKIPSP
        LDA  (P1)
        LDB  #','
        CMP
        JNZ  DL_ERR             ; need a comma between dst and src
        INP1
        JSR  SKIPSP
        JSR  EVAL               ; VAL = src address
        LDA  VAL
        JSR  EMIT
        LDA  VAL+1
        JSR  EMIT
        RTS

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
        LDP1 #EBADOP
        JMP  ASM_ERR
DD_ORG: JSR  EVAL
        LDA  VAL
        STA  PC
        LDA  VAL+1
        STA  PC+1
        LDA  ORGSET
        JNZ  DD_RET
        LDA  VAL
        STA  ORGBASE
        LDA  VAL+1
        STA  ORGBASE+1
        LDA  #1
        STA  ORGSET
DD_RET: RTS
DD_BYTE:JSR  EVAL
        LDA  VAL
        JSR  EMIT
        JSR  SKIPSP
        LDA  (P1)
        LDB  #','
        CMP
        JNZ  DD_RET
        INP1
        JSR  SKIPSP
        JMP  DD_BYTE
DD_WORD:JSR  EVAL
        LDA  VAL
        JSR  EMIT
        LDA  VAL+1
        JSR  EMIT
        JSR  SKIPSP
        LDA  (P1)
        LDB  #','
        CMP
        JNZ  DD_RET
        INP1
        JSR  SKIPSP
        JMP  DD_WORD
DD_FILL:JSR  EVAL
        LDA  VAL                ; count -> SAVP
        STA  SAVP
        LDA  VAL+1
        STA  SAVP+1
        LDA  #0
        STA  FVAL               ; fill value default 0 (TMP is clobbered by EMIT)
        JSR  SKIPSP
        LDA  (P1)
        LDB  #','
        CMP
        JNZ  DF_GO
        INP1
        JSR  SKIPSP
        JSR  EVAL
        LDA  VAL
        STA  FVAL
DF_GO:  LDA  SAVP
        LDB  SAVP+1
        OR
        JZ   DD_RET
        LDA  FVAL
        JSR  EMIT
        LDA  SAVP
        LDB  #1
        SUB
        STA  SAVP
        JC   DF_GO
        LDA  SAVP+1
        LDB  #1
        SUB
        STA  SAVP+1
        JMP  DF_GO
DD_ASC: JSR  SKIPSP
        LDA  (P1)
        LDB  #QUOTE
        CMP
        JNZ  DA_ERR
        INP1
DA_LP:  LDA  (P1)
        JZ   DA_ERR
        LDB  #QUOTE
        CMP
        JZ   DA_CLOSE
        JSR  EMIT
        INP1
        JMP  DA_LP
DA_CLOSE:
        INP1
        LDA  MNBUF+6            ; .ASCIIZ -> trailing 0
        LDB  #'Z'
        CMP
        JNZ  DD_RET
        LDA  #0
        JSR  EMIT
        RTS
DA_ERR: LDP1 #EBADOP
        JMP  ASM_ERR

; =============================================================================
; Operand shape parse -> SHAPE (0 imp,1 #,2 abs,3..8 (Pn)/(Pn)+)
; =============================================================================
PARSEOP:LDA  (P1)
        JZ   PO_IMP
        LDB  #CR
        CMP
        JZ   PO_IMP
        LDB  #LF
        CMP
        JZ   PO_IMP
        LDB  #$3B            ; ';'
        CMP
        JZ   PO_IMP
        LDB  #'#'
        CMP
        JZ   PO_IMM
        LDB  #'('
        CMP
        JZ   PO_PTR
        LDA  #2
        STA  SHAPE
        RTS
PO_IMP: LDA  #0
        STA  SHAPE
        RTS
PO_IMM: INP1
        LDA  #1
        STA  SHAPE
        RTS
PO_PTR: INP1                    ; '('
        INP1                    ; 'P'
        LDA  (P1)
        LDB  #'0'
        SUB
        STA  TMP                ; n
        INP1
        LDA  (P1)               ; ')'
        LDB  #')'
        CMP
        JNZ  PO_ERR
        INP1
        LDA  (P1)
        LDB  #'+'
        CMP
        JZ   PO_PLUS
        LDA  TMP                ; shape = 3 + (n-1)*2
        LDB  #1
        SUB
        SHL
        LDB  #3
        ADD
        STA  SHAPE
        RTS
PO_PLUS:INP1
        LDA  TMP
        LDB  #1
        SUB
        SHL
        LDB  #4
        ADD
        STA  SHAPE
        RTS
PO_ERR: LDP1 #EBADOP
        JMP  ASM_ERR

; =============================================================================
; OPCFIND - scan OPCTAB for (MNBUF, SHAPE) -> OPCB, FOUND
; =============================================================================
OPCFIND:TPA1L
        STA  SAVP
        TPA1H
        STA  SAVP+1
        LDA  #0
        STA  FOUND
        LDP2 #OPCTAB
OF_LP:  LDA  (P2)
        LDB  #$FF
        CMP
        JZ   OF_NF              ; sentinel
        LDA  (P2)+
        STA  TMP                ; shapecode
        LDA  (P2)+
        STA  OPCB               ; opcode
        LDP1 #MNBUF
        LDA  #1
        STA  FOUND              ; tentative match
OF_NM:  LDA  (P2)+
        STA  TMP2
        JZ   OF_NMEND
        LDA  FOUND
        JZ   OF_NM             ; already mismatched: consume rest
        LDA  (P1)+
        LDB  TMP2
        CMP
        JZ   OF_NM
        LDA  #0
        STA  FOUND
        JMP  OF_NM
OF_NMEND:
        LDA  FOUND
        JZ   OF_CHK
        LDA  (P1)              ; both must end -> full match
        JZ   OF_CHK
        LDA  #0
        STA  FOUND
OF_CHK: LDA  FOUND
        JZ   OF_LP
        LDA  TMP
        LDB  SHAPE
        CMP
        JNZ  OF_LP
        LDA  SAVP              ; hit
        TAP1L
        LDA  SAVP+1
        TAP1H
        RTS
OF_NF:  LDA  #0
        STA  FOUND
        LDA  SAVP
        TAP1L
        LDA  SAVP+1
        TAP1H
        RTS

; =============================================================================
; Symbol table
; =============================================================================
; SYMFIND - look up NAMBUF; FOUND=1/0, value -> CNTL/CNTH, addr -> EADDR
SYMFIND:TPA1L
        STA  SAVP
        TPA1H
        STA  SAVP+1
        LDA  #0
        STA  FOUND
        LDA  #<SYMTAB
        TAP2L
        LDA  #>SYMTAB
        TAP2H
SF_LP:  TPA2L
        LDB  SYMP
        CMP
        JNZ  SF_GO
        TPA2H
        LDB  SYMP+1
        CMP
        JZ   SF_NF             ; reached append pointer
SF_GO:  TPA2L                   ; remember entry start
        STA  TMP
        TPA2H
        STA  TMP2
        LDP1 #NAMBUF
        LDA  #12
        STA  DIG
        LDA  #1
        STA  FOUND
SF_CMP: LDA  (P2)+
        STA  CNTL
        LDA  (P1)+
        LDB  CNTL
        CMP
        JZ   SF_CEQ
        LDA  #0
        STA  FOUND
SF_CEQ: LDA  DIG
        DEC
        STA  DIG
        JNZ  SF_CMP
        LDA  FOUND
        JZ   SF_NEXT
        TPA2L                   ; P2 at entry+12 = value field
        STA  EADDR
        TPA2H
        STA  EADDR+1
        LDA  (P2)+
        STA  CNTL
        LDA  (P2)
        STA  CNTH
        LDA  SAVP
        TAP1L
        LDA  SAVP+1
        TAP1H
        RTS
SF_NEXT:LDA  TMP                ; entry start + 14
        LDB  #14
        ADD
        TAP2L
        LDA  TMP2
        JNC  SF_N1
        INC
SF_N1:  TAP2H
        JMP  SF_LP
SF_NF:  LDA  #0
        STA  FOUND
        LDA  SAVP
        TAP1L
        LDA  SAVP+1
        TAP1H
        RTS

; SYMDEFVAL - define/update NAMBUF = VAL
SYMDEFVAL:
        TPA1L
        STA  SAVP2
        TPA1H
        STA  SAVP2+1
        JSR  SYMFIND
        LDA  FOUND
        JNZ  SD_UPD
        LDA  SYMP+1            ; table full?  A 14-byte entry must fit below SYMEND
        LDB  #$BF             ; ($C000), so it is full when SYMP > SYMEND-14 = $BFF2.
        CMP                   ; full 16-bit test (the old hi-byte-only check let an
        JNC  SD_RM            ;   entry at $BFxx write up to 12 bytes past SYMEND).
        JNZ  SD_FULL          ; SYMP hi > $BF -> full
        LDA  #$F2            ; SYMP hi == $BF -> full iff SYMP lo > $F2
        LDB  SYMP
        CMP                   ; C=1 when $F2 >= SYMP lo (room)
        JNC  SD_FULL          ; $F2 < SYMP lo -> full
SD_RM:  LDA  SYMP
        TAP2L
        LDA  SYMP+1
        TAP2H
        LDP1 #NAMBUF
        LDA  #12
        STA  DIG
SD_NM:  LDA  (P1)+
        STA  (P2)+
        LDA  DIG
        DEC
        STA  DIG
        JNZ  SD_NM
        LDA  VAL
        STA  (P2)+
        LDA  VAL+1
        STA  (P2)+
        LDA  SYMP
        LDB  #14
        ADD
        STA  SYMP
        LDA  SYMP+1
        JNC  SD_RET
        INC
        STA  SYMP+1
SD_RET: LDA  SAVP2
        TAP1L
        LDA  SAVP2+1
        TAP1H
        RTS
SD_UPD: LDA  EADDR
        TAP2L
        LDA  EADDR+1
        TAP2H
        LDA  VAL
        STA  (P2)+
        LDA  VAL+1
        STA  (P2)
        JMP  SD_RET
SD_FULL:LDP1 #ESYMS
        JMP  ASM_ERR

; =============================================================================
; Expression evaluator -> VAL ; advances P1
; =============================================================================
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
EV_GT:  LDA  (P1)
        LDB  #'>'
        CMP
        JNZ  EV_INIT
        LDA  #2
        STA  HILO
        INP1
EV_INIT:LDA  #0
        STA  VAL
        STA  VAL+1
        LDA  #1
        STA  SIGN
EV_TERM:JSR  RDTERM            ; term -> CNTL/CNTH
        LDA  SIGN
        JZ   EV_SUB
        LDA  VAL               ; VAL += term
        LDB  CNTL
        ADD
        STA  VAL
        LDA  #0
        JNC  EV_A1
        LDA  #1
EV_A1:  STA  TMP
        LDA  VAL+1
        LDB  CNTH
        ADD
        LDB  TMP
        ADD
        STA  VAL+1
        JMP  EV_OP
EV_SUB: LDA  VAL               ; VAL -= term
        LDB  CNTL
        SUB
        STA  VAL
        LDA  #0
        JC   EV_S1
        LDA  #1
EV_S1:  STA  TMP
        LDA  VAL+1
        LDB  CNTH
        SUB
        STA  VAL+1
        LDA  TMP
        JZ   EV_OP
        LDA  VAL+1
        LDB  #1
        SUB
        STA  VAL+1
EV_OP:  LDA  (P1)
        LDB  #'+'
        CMP
        JZ   EV_PLUS
        LDA  (P1)
        LDB  #'-'
        CMP
        JZ   EV_MINUS
        JMP  EV_FIN
EV_PLUS:LDA  #1
        STA  SIGN
        INP1
        JMP  EV_TERM
EV_MINUS:LDA #0
        STA  SIGN
        INP1
        JMP  EV_TERM
EV_FIN: LDA  HILO
        JZ   EV_DONE
        LDB  #1
        CMP
        JNZ  EV_HI
        LDA  #0                ; low byte
        STA  VAL+1
        JMP  EV_DONE
EV_HI:  LDA  VAL+1             ; high byte
        STA  VAL
        LDA  #0
        STA  VAL+1
EV_DONE:RTS

; RDTERM - one term at P1 -> CNTL/CNTH ; advances P1
RDTERM: LDA  #0
        STA  CNTL
        STA  CNTH
        LDA  (P1)
        LDB  #'$'
        CMP
        JZ   RT_HEX
        LDB  #TICK
        CMP
        JZ   RT_CHR
        STA  TMP2
        LDB  #'0'
        CMP
        JNC  RT_SYM            ; < '0'
        LDA  #'9'
        LDB  TMP2
        CMP
        JC   RT_DEC            ; '0'..'9'
RT_SYM: JSR  READTOK
        JSR  SYMFIND           ; value -> CNTL/CNTH, FOUND
        LDA  FOUND
        JNZ  RT_RET
        LDA  PASS
        JZ   RT_RET            ; pass1: undefined -> 0
        LDP1 #EUNDEF
        JMP  ASM_ERR
RT_RET: RTS
RT_HEX: INP1
RH_LP:  LDA  (P1)
        STA  TMP2
        LDB  #'0'
        CMP
        JNC  RT_RET            ; not hex
        LDA  #'9'
        LDB  TMP2
        CMP
        JNC  RH_AZ             ; > '9' maybe A-F
        LDA  TMP2              ; digit 0-9
        LDB  #'0'
        SUB
        JMP  RH_ACC
RH_AZ:  LDA  TMP2
        JSR  UPCASE
        STA  TMP2
        LDB  #'A'
        CMP
        JNC  RT_RET            ; < 'A'
        LDA  #'F'
        LDB  TMP2
        CMP
        JNC  RT_RET            ; > 'F'
        LDA  TMP2
        LDB  #'A'
        SUB
        LDB  #10
        ADD
RH_ACC: STA  TMP               ; nibble
        LDA  #4
        STA  DIG
RH_SH:  LDA  CNTL
        SHL
        STA  CNTL
        LDA  CNTH
        ROL
        STA  CNTH
        LDA  DIG
        DEC
        STA  DIG
        JNZ  RH_SH
        LDA  CNTL
        LDB  TMP
        OR
        STA  CNTL
        INP1
        JMP  RH_LP
RT_DEC: LDA  (P1)
        STA  TMP2
        LDB  #'0'
        CMP
        JNC  RT_RET
        LDA  #'9'
        LDB  TMP2
        CMP
        JNC  RT_RET
        JSR  MUL10
        LDA  TMP2
        LDB  #'0'
        SUB
        STA  TMP
        LDA  CNTL
        LDB  TMP
        ADD
        STA  CNTL
        LDA  CNTH
        JNC  RD_NC
        INC
        STA  CNTH
RD_NC:  INP1
        JMP  RT_DEC
RT_CHR: INP1                    ; opening '
        LDA  (P1)
        STA  CNTL
        LDA  #0
        STA  CNTH
        INP1
        LDA  (P1)               ; closing '
        LDB  #TICK
        CMP
        JNZ  RT_RET
        INP1
        RTS

; MUL10 - CNT = CNT * 10
MUL10:  LDA  CNTL
        STA  MTL
        LDA  CNTH
        STA  MTH
        LDA  CNTL              ; CNT *= 2
        SHL
        STA  CNTL
        LDA  CNTH
        ROL
        STA  CNTH
        LDA  MTL               ; MT *= 8
        SHL
        STA  MTL
        LDA  MTH
        ROL
        STA  MTH
        LDA  MTL
        SHL
        STA  MTL
        LDA  MTH
        ROL
        STA  MTH
        LDA  MTL
        SHL
        STA  MTL
        LDA  MTH
        ROL
        STA  MTH
        LDA  CNTL              ; CNT = CNT*2 + MT(=orig*8)
        LDB  MTL
        ADD
        STA  CNTL
        LDA  #0
        JNC  M_NC
        LDA  #1
M_NC:   STA  TMP
        LDA  CNTH
        LDB  MTH
        ADD
        LDB  TMP
        ADD
        STA  CNTH
        RTS

; =============================================================================
; EMIT - append A to output at PC-ORGBASE (pass2); advance PC; track HIWAT
; =============================================================================
; EMIT - append byte A to the output. Pass 1 only advances PC and tracks HIWAT;
; pass 2 streams the byte to disk, zero-padding any gap left by a forward .org.
; P1 (the line cursor) is saved for the whole routine, so OUTBYTE/FLUSHOUT may
; use it freely.
EMIT:   STA  SB2
        TPA1L
        STA  SAVPE
        TPA1H
        STA  SAVPE+1
        LDA  PASS
        JZ   EM_ADV
        LDA  PC                 ; off = PC - ORGBASE
        LDB  ORGBASE
        SUB
        STA  OFFL
        LDA  #0
        JC   EM_NB
        LDA  #1
EM_NB:  STA  TMP
        LDA  PC+1
        LDB  ORGBASE+1
        SUB
        LDB  TMP
        SUB
        STA  OFFH
EM_PAD: LDA  OUTPOS             ; while OUTPOS != off, pad a zero
        LDB  OFFL
        CMP
        JNZ  EM_PCHK
        LDA  OUTPOS+1
        LDB  OFFH
        CMP
        JZ   EM_PUT             ; OUTPOS == off -> emit the real byte
EM_PCHK:LDA  OFFH               ; off < OUTPOS would loop forever -> backward .org
        LDB  OUTPOS+1
        CMP                     ; C = OFFH >= OUTPOS+1
        JNZ  EM_PHI
        LDA  OFFL
        LDB  OUTPOS
        CMP                     ; high equal -> compare low: C = OFFL >= OUTPOS
        JNC  EM_BACK
        JMP  EM_PADZ
EM_PHI: JNC  EM_BACK            ; OFFH < OUTPOS+1 -> off < OUTPOS
EM_PADZ:LDA  #0
        JSR  EMITB
        JMP  EM_PAD
EM_PUT: LDA  SB2
        JSR  EMITB
EM_ADV: LDA  PC                 ; PC++
        INC
        STA  PC
        JNZ  EM_HW
        LDA  PC+1
        INC
        STA  PC+1
EM_HW:  LDA  PC+1               ; HIWAT = max(HIWAT, PC)
        LDB  HIWAT+1
        CMP
        JNZ  EM_HD
        LDA  PC
        LDB  HIWAT
        CMP
EM_HD:  JC   EM_SET
        JMP  EM_RET
EM_SET: LDA  PC
        STA  HIWAT
        LDA  PC+1
        STA  HIWAT+1
EM_RET: LDA  SAVPE              ; restore the line cursor
        TAP1L
        LDA  SAVPE+1
        TAP1H
        RTS
EM_BACK:LDP1 #EBACK
        JMP  ASM_ERR

; EMITB - emit one output byte through the BIOS write stream (FPUTB) and track
; OUTPOS so EMIT can zero-pad forward .org gaps. FPUTB handles the sector buffer,
; flushing, and the running file length itself.
EMITB:  JSR  FPUTB
        LDA  OUTPOS
        LDB  #1
        ADD
        STA  OUTPOS
        LDA  OUTPOS+1
        JNC  EB_1
        INC
        STA  OUTPOS+1
EB_1:   RTS

; OUTINIT - begin streamed output (BIOS write stream at the volume free pointer).
; OUTINIT - resolve the output path's parent dir + leaf NOW, BEFORE opening the
;   write stream (a FRESOLVE while the stream is live corrupts its pending SBUF /
;   length). Stash them; FINISHOUT restores them for FCLOSE.
OUTINIT:LDP1 #OUTPATH
        JSR  FRESOLVE          ; DIRLBA = parent (exists), FNAME = leaf (may be new)
        LDA  DIRLBA
        STA  OUTDIR
        LDA  DIRLBA1
        STA  OUTDIR+1
        LDA  DIRN
        STA  OUTDIR+2
        LDP1 #FNAME            ; OUTFN <- FNAME (12)
        LDP2 #OUTFN
        LDA  #12
        STA  DIG
OI_FN:  LDA  (P1)+
        STA  (P2)+
        LDA  DIG
        DEC
        STA  DIG
        JNZ  OI_FN
        ; overwrite semantics: tombstone any existing output file BEFORE opening
        ; the write stream (FDELETE scans the directory via SBUF, which the open
        ; stream also uses — so it must run first, not between FWOPEN and FCLOSE).
        ; DIRLBA/FNAME still hold the FRESOLVE'd parent + leaf. C=1 (absent) is fine.
        JSR  FDELETE
        JSR  FWOPEN
        LDA  #0
        STA  OUTPOS
        STA  OUTPOS+1
        RTS

; FINISHOUT - register the assembled file (FCLOSE flushes + writes the entry +
; bumps the free pointer; its length comes from the bytes written). C=1 if full.
FINISHOUT:
        LDA  OUTDIR            ; restore the stashed output dir + leaf (pass 2 / a
        STA  DIRLBA            ;   ;#use moved DIRLBA/FNAME); no FRESOLVE here, so the
        LDA  OUTDIR+1          ;   live write stream is untouched. FCLOSE flushes and
        STA  DIRLBA1           ;   registers FNAME in DIRLBA, then reverts to root.
        LDA  OUTDIR+2
        STA  DIRN
        LDP1 #OUTFN
        LDP2 #FNAME
        LDA  #12
        STA  DIG
FO_FN:  LDA  (P1)+
        STA  (P2)+
        LDA  DIG
        DEC
        STA  DIG
        JNZ  FO_FN
        JMP  FCLOSE

; =============================================================================
; Source load + scanning helpers
; =============================================================================
; ---- source reader: a line at a time, over the BIOS read stream ------------
; The byte-level streaming (sector reads, refill, EOF) lives in the BIOS now
; (FOPEN/FGETB); the assembler just re-opens the source each pass and assembles
; lines into LINEBUF. SECBUF is the 512-byte buffer FOPEN/FGETB use.
; PASSINIT - (re)open the source for a pass. FNAME is still the source name
;            (SETFNOUT only runs at FINISHOUT, after both passes).
PASSINIT:
        JSR  RESTSRC           ; FNAME + dir context <- source (undo any ;#use)
        LDA  #0
        STA  USECOUNT          ; re-scan ;#use directives fresh each pass
        STA  USEDONE
        STA  INCHAVE           ; ...and re-scan .include fresh each pass
        STA  INCDONE
        LDP1 #SECBUF
        JSR  FOPEN             ; source existence already checked at startup
        LDA  #0
        STA  LEOF
        RTS
; NEXTLINE - read one line into LINEBUF (NUL-terminated, newline stripped).
;            LEOF=1 when the source is exhausted.
NEXTLINE:
        LDP2 #LINEBUF
        LDA  #0
        STA  LCNT
NL_LP:  JSR  SRCGET
        JC   NL_EOF           ; C=1 -> end of file
        STA  SB
        LDB  #LF
        CMP
        JZ   NL_DONE
        LDB  #CR
        CMP
        JZ   NL_LP            ; drop CR (CRLF)
        LDA  LCNT
        LDB  #127
        CMP
        JC   NL_LP            ; line full -> consume but don't store
        LDA  SB
        STA  (P2)+
        LDA  LCNT
        INC
        STA  LCNT
        JMP  NL_LP
NL_EOF: LDA  LCNT             ; EOF: process a final line with no trailing newline
        JZ   NL_END
NL_DONE:LDA  #0
        STA  (P2)
        LDA  #0
        STA  LEOF
        JSR  CHKUSE           ; ";#use NAME"? -> splice the include, read next line
        JC   NEXTLINE
        JSR  CHKINC           ; '.include "path"'? -> record it, read next line
        JC   NEXTLINE
        RTS
NL_END: LDA  #1
        STA  LEOF
        RTS

; ---- ;#use include machinery (sequential append) ----------------------------
; SRCGET - like FGETB, but at a file's EOF opens the next recorded ;#use include
;   (over SECBUF — the source is done) and keeps reading. C=1 only when the
;   source AND all its includes are exhausted.
SRCGET: JSR  FGETB
        JNC  SG_RET           ; got a byte (FGETB preserves P2)
        TPA2L                 ; EOF: NEXTUSE clobbers P2, but the caller (NEXTLINE)
        STA  P2SAV            ; uses P2 as its LINEBUF write cursor — save/restore it
        TPA2H
        STA  P2SAV+1
        JSR  NEXTUSE          ; open the next include?
        JC   SG_EOF           ; test carry BEFORE the P2 restore can disturb it
        JSR  RESTP2           ; opened one: restore P2 and read from it
        JMP  SRCGET
SG_EOF: JSR  RESTP2           ; none left: restore P2, re-assert EOF
        SEC
SG_RET: RTS
RESTP2: LDA  P2SAV
        TAP2L
        LDA  P2SAV+1
        TAP2H
        RTS

; NEXTUSE - if a recorded include is still unread, open /lib/<name>.inc on SECBUF
;   and return C=0 (advancing USEDONE); else C=1.
NEXTUSE:LDA  USEDONE
        LDB  USECOUNT
        CMP                   ; C=1 if USEDONE >= USECOUNT
        JC   NU_INC           ; ;#use exhausted -> try the .include
        LDA  USEDONE          ; P1 = USELIST + USEDONE*12  (page-local)
        JSR  SLOTLO
        TAP1L
        LDA  #>USELIST
        TAP1H
        JSR  BUILDINC         ; UPATH = "/lib/<name>.inc"
        LDA  USEDONE
        INC
        STA  USEDONE
        LDP1 #UPATH
        JSR  FRESOLVE
        JC   NU_ERR
        LDP1 #INCBUF          ; include streams on its own buffer
        JSR  FOPEN
        JC   NU_ERR
        CLC
        RTS
NU_INC: LDA  INCDONE          ; a recorded .include still unopened?
        LDB  INCHAVE
        CMP                   ; C=1 if INCDONE >= INCHAVE (none left)
        JC   NU_END
        LDA  #1
        STA  INCDONE
        LDP1 #INCPATH         ; the pre-resolved absolute include path
        JSR  FRESOLVE
        JC   NU_ERR
        LDP1 #INCBUF
        JSR  FOPEN
        JC   NU_ERR
        CLC
        RTS
NU_END: SEC
        RTS
NU_ERR: LDP1 #EUSE
        JMP  ASM_ERR

; SLOTLO - A = index -> A = low byte of USELIST + index*12 (all within one page).
SLOTLO: STA  UCNT
        LDA  #0
        STA  TMP
SL_LP:  LDA  UCNT
        JZ   SL_D
        LDA  TMP
        LDB  #12
        ADD
        STA  TMP
        LDA  UCNT
        DEC
        STA  UCNT
        JMP  SL_LP
SL_D:   LDA  #<USELIST
        LDB  TMP
        ADD
        RTS

; BUILDINC - P1 = NUL-terminated name -> UPATH = "/lib/NAME.inc".
BUILDINC:LDP2 #UPATH
        LDA  #'/'
        STA  (P2)+
        LDA  #'l'
        STA  (P2)+
        LDA  #'i'
        STA  (P2)+
        LDA  #'b'
        STA  (P2)+
        LDA  #'/'
        STA  (P2)+
BI_CP:  LDA  (P1)
        JZ   BI_EXT
        STA  (P2)+
        INP1
        JMP  BI_CP
BI_EXT: LDA  #'.'
        STA  (P2)+
        LDA  #'i'
        STA  (P2)+
        LDA  #'n'
        STA  (P2)+
        LDA  #'c'
        STA  (P2)+
        LDA  #0
        STA  (P2)
        RTS

; CHKUSE - if LINEBUF is ";#use NAME", record the include and return C=1 (so the
;   line is skipped); else C=0. Includes are read at the source's EOF (NEXTUSE).
CHKUSE: LDP1 #LINEBUF
CU_SK:  LDA  (P1)            ; skip leading spaces / tabs
        LDB  #' '
        CMP
        JZ   CU_SKA
        LDB  #$09
        CMP
        JNZ  CU_S1
CU_SKA: INP1
        JMP  CU_SK
CU_S1:  LDB  #59             ; ';'  (literal, not written '  ;  ' — that starts a comment)
        CMP
        JNZ  CU_NO
        INP1
        LDA  (P1)
        LDB  #'#'
        CMP
        JNZ  CU_NO
        INP1
        LDA  (P1)
        LDB  #'u'
        CMP
        JNZ  CU_NO
        INP1
        LDA  (P1)
        LDB  #'s'
        CMP
        JNZ  CU_NO
        INP1
        LDA  (P1)
        LDB  #'e'
        CMP
        JNZ  CU_NO
        INP1
        LDA  (P1)            ; require whitespace after "use"
        LDB  #' '
        CMP
        JZ   CU_SP
        LDB  #$09
        CMP
        JNZ  CU_NO
CU_SP:  LDA  (P1)            ; skip spaces to the NAME
        LDB  #' '
        CMP
        JZ   CU_SPA
        LDB  #$09
        CMP
        JNZ  CU_GO
CU_SPA: INP1
        JMP  CU_SP
CU_GO:  LDA  (P1)            ; P1 at NAME; empty -> ignore
        JZ   CU_NO
        LDB  #CR
        CMP
        JZ   CU_NO
        JSR  ADDUSE          ; record the name (P1 = NAME cursor)
        SEC
        RTS
CU_NO:  CLC
        RTS

; CHKINC - if LINEBUF is '.include "path"', resolve it (relative to the source's
;   directory) into INCPATH, mark INCHAVE, and return C=1 (the line is skipped);
;   else C=0. One .include per file; opened at the source's EOF (NU_INC). Since
;   equates are order-independent (two-pass), EOF-append matches an inline splice.
CHKINC: LDA  INCHAVE          ; only one .include per file
        JNZ  CI_NO
        LDP1 #LINEBUF
CI_SK:  LDA  (P1)             ; skip leading spaces / tabs
        LDB  #' '
        CMP
        JZ   CI_SKA
        LDB  #$09
        CMP
        JNZ  CI_M
CI_SKA: INP1
        JMP  CI_SK
CI_M:   LDA  (P1)             ; match ".include"
        LDB  #'.'
        CMP
        JNZ  CI_NO
        INP1
        LDA  (P1)
        LDB  #'i'
        CMP
        JNZ  CI_NO
        INP1
        LDA  (P1)
        LDB  #'n'
        CMP
        JNZ  CI_NO
        INP1
        LDA  (P1)
        LDB  #'c'
        CMP
        JNZ  CI_NO
        INP1
        LDA  (P1)
        LDB  #'l'
        CMP
        JNZ  CI_NO
        INP1
        LDA  (P1)
        LDB  #'u'
        CMP
        JNZ  CI_NO
        INP1
        LDA  (P1)
        LDB  #'d'
        CMP
        JNZ  CI_NO
        INP1
        LDA  (P1)
        LDB  #'e'
        CMP
        JNZ  CI_NO
        INP1
CI_SP:  LDA  (P1)             ; skip spaces to the opening quote
        LDB  #' '
        CMP
        JZ   CI_SPA
        LDB  #$09
        CMP
        JNZ  CI_Q
CI_SPA: INP1
        JMP  CI_SP
CI_Q:   LDA  (P1)             ; expect a '"'
        LDB  #34
        CMP
        JNZ  CI_NO
        INP1                  ; P1 at the path text
        TPA1L                 ; save the path cursor (CI_PREFIX uses P1)
        STA  PATHSAV
        TPA1H
        STA  PATHSAV+1
        LDA  (P1)             ; absolute path -> INCPATH from the start
        LDB  #'/'
        CMP
        JZ   CI_ABS
        JSR  CI_PREFIX        ; else INCPATH = the source dir; P2 = append point
        JMP  CI_APP
CI_ABS: LDA  #<INCPATH
        TAP2L
        LDA  #>INCPATH
        TAP2H
CI_APP: LDA  PATHSAV          ; restore the path cursor
        TAP1L
        LDA  PATHSAV+1
        TAP1H
CI_CP:  LDA  (P1)             ; append the path until '"' / NUL
        JZ   CI_CPD
        LDB  #34
        CMP
        JZ   CI_CPD
        STA  (P2)+
        INP1
        JMP  CI_CP
CI_CPD: LDA  #0
        STA  (P2)
        LDA  #1
        STA  INCHAVE
        SEC
        RTS
CI_NO:  CLC
        RTS

; CI_PREFIX - INCPATH = SRCPATH truncated after its last '/'; leaves P2 at the
;   append point (just past that '/'). Copies all of SRCPATH, tracking LSPOS.
CI_PREFIX: LDP1 #SRCPATH
        LDA  #<INCPATH
        TAP2L
        STA  LSPOS
        LDA  #>INCPATH
        TAP2H
        STA  LSPOS+1
CP_LP:  LDA  (P1)
        JZ   CP_DONE
        STA  (P2)
        LDB  #'/'
        CMP
        JNZ  CP_NS
        TPA2L                 ; LSPOS = P2 + 1 (just past this '/')
        LDB  #1
        ADD
        STA  LSPOS
        TPA2H
        JNC  CP_LS
        INC
CP_LS:  STA  LSPOS+1
CP_NS:  INP1
        INP2
        JMP  CP_LP
CP_DONE: LDA LSPOS            ; P2 = append point
        TAP2L
        LDA  LSPOS+1
        TAP2H
        RTS

; ADDUSE - P1 = NAME cursor in LINEBUF. Append the name (NUL-terminated) to
;   USELIST[USECOUNT] and bump USECOUNT (capped at 4). Duplicates are not
;   dedup'd — each command declares each ;#use once (matches the shipped set).
ADDUSE: LDA  USECOUNT
        LDB  #4
        CMP
        JC   AU_RET          ; USECOUNT >= 4 -> ignore extra (won't happen)
        LDA  USECOUNT        ; P2 = USELIST + USECOUNT*12
        JSR  SLOTLO
        TAP2L
        LDA  #>USELIST
        TAP2H
AU_CP:  LDA  (P1)            ; copy name up to a delimiter
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
        STA  (P2)            ; NUL-terminate the slot
        LDA  USECOUNT
        INC
        STA  USECOUNT
AU_RET: RTS

; SAVESRC / RESTSRC - the source's FNAME + dir context, so PASSINIT re-opens the
;   source each pass regardless of a ;#use having re-resolved FNAME/DIRLBA.
SAVESRC:LDP1 #FNAME
        LDP2 #SRCFN
        LDA  #12
        STA  UCNT
SR_LP:  LDA  (P1)+
        STA  (P2)+
        LDA  UCNT
        DEC
        STA  UCNT
        JNZ  SR_LP
        LDA  DIRLBA
        STA  SRCDIR
        LDA  DIRLBA1
        STA  SRCDIR+1
        LDA  DIRN
        STA  SRCDIR+2
        RTS
RESTSRC:LDP1 #SRCFN
        LDP2 #FNAME
        LDA  #12
        STA  UCNT
RT_LP:  LDA  (P1)+
        STA  (P2)+
        LDA  UCNT
        DEC
        STA  UCNT
        JNZ  RT_LP
        LDA  SRCDIR
        STA  DIRLBA
        LDA  SRCDIR+1
        STA  DIRLBA1
        LDA  SRCDIR+2
        STA  DIRN
        RTS

; SKIPSP - advance P1 over spaces and tabs; returns with (P1) on the first
;   non-blank (or the terminating NUL). Only P1 moves; A/B are scratch.
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

; SKIPTOEOL - advance P1 to the end of the line (stops on NUL, CR, or LF).
SKIPTOEOL:
        LDA  (P1)
        JZ   STE_D
        LDB  #CR
        CMP
        JZ   STE_D
        LDB  #LF
        CMP
        JZ   STE_D
        INP1
        JMP  SKIPTOEOL
STE_D:  RTS

; EATNL - consume one optional CR then one optional LF at P1 (a CRLF or bare LF).
EATNL:  LDA  (P1)
        LDB  #CR
        CMP
        JNZ  EN_1
        INP1
EN_1:   LDA  (P1)
        LDB  #LF
        CMP
        JNZ  EN_2
        INP1
EN_2:   RTS

; READTOK - read identifier at P1 into NAMBUF (as-is) + MNBUF (upcased); advance
READTOK:LDP2 #NAMBUF
        LDA  #16
        STA  TMP2
RT_Z1:  LDA  #0
        STA  (P2)+
        LDA  TMP2
        DEC
        STA  TMP2
        JNZ  RT_Z1
        LDP2 #MNBUF
        LDA  #8
        STA  TMP2
RT_Z2:  LDA  #0
        STA  (P2)+
        LDA  TMP2
        DEC
        STA  TMP2
        JNZ  RT_Z2
        LDA  #0
        STA  TMP                ; index
RK_LP:  LDA  (P1)
        JSR  ISIDCH
        JNZ  RK_DONE
        LDA  TMP
        LDB  #12
        CMP
        JC   RK_NEXT            ; index >= 12: stop storing
        LDA  #<NAMBUF
        LDB  TMP
        ADD
        TAP2L
        LDA  #>NAMBUF
        JNC  RK_N1
        INC
RK_N1:  TAP2H
        LDA  (P1)
        STA  (P2)
        LDA  TMP
        LDB  #8
        CMP
        JC   RK_NEXT
        LDA  #<MNBUF
        LDB  TMP
        ADD
        TAP2L
        LDA  #>MNBUF
        JNC  RK_M1
        INC
RK_M1:  TAP2H
        LDA  (P1)
        JSR  UPCASE
        STA  (P2)
RK_NEXT:INP1
        LDA  TMP
        INC
        STA  TMP
        JMP  RK_LP
RK_DONE:RTS

; ISIDCH - Z=1 if A is [A-Za-z0-9_.]
ISIDCH: STA  TMP2
        LDB  #'.'
        CMP
        JZ   IC_YES
        LDA  TMP2
        LDB  #'_'
        CMP
        JZ   IC_YES
        LDA  TMP2
        LDB  #'0'
        CMP
        JNC  IC_AZ
        LDA  #'9'
        LDB  TMP2
        CMP
        JC   IC_YES
IC_AZ:  LDA  TMP2
        LDB  #'A'
        CMP
        JNC  IC_LZ
        LDA  #'Z'
        LDB  TMP2
        CMP
        JC   IC_YES
IC_LZ:  LDA  TMP2
        LDB  #'a'
        CMP
        JNC  IC_NO
        LDA  #'z'
        LDB  TMP2
        CMP
        JC   IC_YES
IC_NO:  LDA  #1
        RTS
IC_YES: LDA  #0
        RTS

; UPCASE - A -> uppercase if it is 'a'..'z', else A unchanged. Clobbers B/TMP2.
UPCASE: STA  TMP2
        LDB  #'a'
        CMP
        JNC  UC_NO
        LDA  #'z'
        LDB  TMP2
        CMP
        JNC  UC_NO
        LDA  TMP2
        LDB  #$20
        SUB
        RTS
UC_NO:  LDA  TMP2
        RTS

; =============================================================================
; Argument parsing + filename helpers
; =============================================================================
PARSEARGS:
        JSR  ASKIPSP2
        LDP1 #ARGTMP           ; raw SRC token -> ARGTMP
        JSR  PATHCOPY
        JSR  ASKIPSP2          ; advance the arg cursor to the OUT token first...
        TPA2L                  ; ...then save it: ABSPATH clobbers P2
        STA  ACSAV
        TPA2H
        STA  ACSAV+1
        LDA  #<SRCPATH         ; SRCPATH = abspath(ARGTMP)  [SRC]
        STA  ABDST
        LDA  #>SRCPATH
        STA  ABDST+1
        JSR  ABSPATH
        LDA  ACSAV             ; restore the arg cursor -> OUT token
        TAP2L
        LDA  ACSAV+1
        TAP2H
        LDP1 #ARGTMP           ; raw OUT token -> ARGTMP
        JSR  PATHCOPY
        LDA  #<OUTPATH         ; OUTPATH = abspath(ARGTMP)  [OUT]
        STA  ABDST
        LDA  #>OUTPATH
        STA  ABDST+1
        JSR  ABSPATH
        RTS

; ABSPATH: (ABDST) <- ARGTMP made absolute. An absolute arg (leading '/') is copied
; as-is; a relative one is CWD-prefixed (SYS_GETCWD + '/') — because FRESOLVE starts
; at root, not the CWD. This makes `asm T.ASM` read a redirect's T.ASM from ANY
; directory (the redirect registers it in the CWD), so a build script needs no
; `cd /`. An empty arg stays empty (preserves the "no arg -> usage" check).
ABSPATH:LDA  ARGTMP
        LDB  #0
        CMP
        JNZ  AB_NE
        LDA  ABDST             ; empty arg -> empty dest
        TAP1L
        LDA  ABDST+1
        TAP1H
        LDA  #0
        STA  (P1)
        RTS
AB_NE:  LDA  ARGTMP
        LDB  #'/'
        CMP
        JZ   AB_ABS
        LDA  ABDST             ; relative: CWD -> (ABDST)
        TAP1L
        LDA  ABDST+1
        TAP1H
        LDA  #0
        JSR  SYS_GETCWD
        LDA  ABDST             ; walk to the end of the CWD string
        TAP1L
        LDA  ABDST+1
        TAP1H
AB_EN:  LDA  (P1)
        JZ   AB_TSL
        INP1
        JMP  AB_EN
AB_TSL: DEP1                   ; last char == '/'? (root CWD "/" already ends in one)
        LDA  (P1)
        INP1
        LDB  #'/'
        CMP
        JZ   AB_CAT
        LDA  #'/'              ; else append a separator
        STA  (P1)+
AB_CAT: LDA  #<ARGTMP          ; append the relative arg (P2) at P1
        TAP2L
        LDA  #>ARGTMP
        TAP2H
AB_CL:  LDA  (P2)
        STA  (P1)+
        JZ   AB_RT
        INP2
        JMP  AB_CL
AB_RT:  RTS
AB_ABS: LDA  ABDST             ; absolute: copy ARGTMP -> (ABDST)
        TAP1L
        LDA  ABDST+1
        TAP1H
        LDA  #<ARGTMP
        TAP2L
        LDA  #>ARGTMP
        TAP2H
AB_AL:  LDA  (P2)
        STA  (P1)+
        JZ   AB_RT
        INP2
        JMP  AB_AL
; PATHCOPY - copy the path word at P2 into (P1), NUL-terminated, case preserved,
;   stopping at a space / CR / NUL. Advances P2. (Unlike WORDCOPY: no 12-char cap,
;   no upcasing — so SRC/OUT can be sub-directory paths like /src/commands/c/x.c.)
PATHCOPY:
PC_CP:  LDA  (P2)
        JZ   PC_END
        LDB  #' '
        CMP
        JZ   PC_END
        LDB  #CR
        CMP
        JZ   PC_END
        LDA  (P2)
        STA  (P1)+
        INP2
        JMP  PC_CP
PC_END: LDA  #0
        STA  (P1)
        RTS
ASKIPSP2:
        LDA  (P2)
        LDB  #' '
        CMP
        JNZ  AS_D
        INP2
        JMP  ASKIPSP2
AS_D:   RTS
; WORDCOPY - P1=dest (12, space-padded, upcased), P2=src word; advance P2
WORDCOPY:
        TPA1L
        STA  TMP
        TPA1H
        STA  TMP2
        LDA  #12
        STA  DIG
WC_PAD: LDA  #' '
        STA  (P1)+
        LDA  DIG
        DEC
        STA  DIG
        JNZ  WC_PAD
        LDA  TMP
        TAP1L
        LDA  TMP2
        TAP1H
        LDA  #12
        STA  DIG
WC_CP:  LDA  (P2)
        JZ   WC_DONE
        LDB  #' '
        CMP
        JZ   WC_DONE
        LDA  DIG
        JZ   WC_DONE
        LDA  (P2)               ; filename copied as typed (case-sensitive FS)
        STA  (P1)+
        INP2
        LDA  DIG
        DEC
        STA  DIG
        JMP  WC_CP
WC_DONE:RTS
; SETFNOUT - copy the legacy OUTNAME (12) into FNAME. Superseded by the OUTFN /
;   FRESOLVE path handling (OUTINIT/FINISHOUT); kept for reference, not called.
SETFNOUT:
        LDP1 #OUTNAME
        LDP2 #FNAME
        LDA  #12
        STA  DIG
SF2:    LDA  (P1)+
        STA  (P2)+
        LDA  DIG
        DEC
        STA  DIG
        JNZ  SF2
        RTS

; =============================================================================
; Error abort: print message at P1 + the offending line, long-jump to OS
; =============================================================================
ASM_ERR:JSR  PUTS               ; message (P1)+
        LDA  LINEPL
        TAP1L
        LDA  LINEPH
        TAP1H
AE_PL:  LDA  (P1)
        JZ   AE_DONE
        LDB  #CR
        CMP
        JZ   AE_DONE
        LDB  #LF
        CMP
        JZ   AE_DONE
        JSR  CONOUT
        INP1
        JMP  AE_PL
AE_DONE:LDA  #CR
        JSR  CONOUT
        LDA  #LF
        JSR  CONOUT
        LDA  SP0                ; restore SP and RTS to the OS shell
        TAP3L
        LDA  SP0+1
        TAP3H
        RTS

; =============================================================================
; Messages
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
