; =============================================================================
; P8X ASM - native two-pass assembler (standalone TPA program)
; =============================================================================
;     RUN ASM.BIN SRC.ASM OUT.BIN
; Reads SRC.ASM from disk and writes the binary OUT, both through the BIOS
; file streams (FOPEN/FGETB for input, FWOPEN/FPUTB/FCLOSE for output), so
; neither is bounded by RAM — the assembler even assembles its own source.
; Output carries load/exec 0, which the OS treats as the TPA base $7A00 — so a
; program written `.org $7A00` is directly RUNnable after assembly.
;
; Supported syntax (a subset of the host assembler, same encodings):
;   label:                 define label = PC
;   NAME = expr            equate
;   MNEMONIC [operand]     operand: #expr | (Pn) | (Pn)+ | expr | none
;   LDPn #expr16           pseudo -> LPLn #<expr ; LPHn #>expr
;   .org .byte .word .ascii .asciiz .fill
;   expr: $hex | decimal | 'c' | symbol, joined with + / -, optional </> prefix
;
; The opcode table (OPCTAB) is generated from genucode.OPC by
; generators/gen_p8xopc.py and concatenated after this source at build time.
;
; Conventions: P1 is the source cursor (preserved across helper calls); P3 is
; the system stack (never touched); helpers needing a 2nd pointer save P1 first.
; Limits: ~850 symbols, 12-char names, 127-char source lines, single .org.
; =============================================================================

; ---- BIOS ---- (file I/O now goes entirely through the read/write streams)
CONIN   = $0100
CONOUT  = $0103
PUTS    = $0112
PHEX8   = $0115
FFIND   = $0118   ; used once at startup to report a missing source
FOPEN   = $0124   ; open source for reading (P1 = 512-byte buffer)
FGETB   = $0127   ; next source byte -> A; C=1 at EOF
FWOPEN  = $012A   ; open the output write stream
FPUTB   = $012D   ; append a byte to the output stream
FCLOSE  = $0130   ; flush + register the output file FNAME; C=1 if full
LBA     = $7047
LBA1    = $7048
LBA2    = $7049
FNAME   = $704A
FSRC    = $7056
FLEN    = $7058

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
OUTNAME = $C850   ; output file name (12)
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
; no output RAM buffer — output size is bounded by the disk too. All of the TPA
; above the line buffer is the symbol table (~850 symbols).
SECBUF  = $C900   ; one streamed source sector (512)
LINEBUF = $CB00   ; current source line (NUL-terminated, <=127 chars)
SYMTAB  = $CC00   ; 14-byte entries: name[12] + value[2]  (~850 symbols)
SYMEND  = $FB00   ; symbol-table limit (stack lives above)

        .org $7A00
; =============================================================================
START:  TPA3L                   ; save SP so an error can long-jump back to OS
        STA  SP0
        TPA3H
        STA  SP0+1
        JSR  PARSEARGS          ; FNAME <- SRC, OUTNAME <- OUT
        LDA  OUTNAME            ; no output name given -> show usage
        LDB  #' '
        CMP
        JZ   ST_USAGE
        JSR  FFIND              ; just to report a missing source cleanly
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
        LDA  MNBUF              ; LDPn pseudo?
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
        LDA  SYMP+1            ; table full?
        LDB  #>SYMEND
        CMP
        JC   SD_FULL          ; SYMP hi >= SYMEND hi
        LDA  SYMP
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
OUTINIT:JSR  FWOPEN
        LDA  #0
        STA  OUTPOS
        STA  OUTPOS+1
        RTS

; FINISHOUT - register the assembled file (FCLOSE flushes + writes the entry +
; bumps the free pointer; its length comes from the bytes written). C=1 if full.
FINISHOUT:
        JSR  SETFNOUT          ; FNAME <- OUTNAME
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
NL_LP:  JSR  FGETB
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
        RTS
NL_END: LDA  #1
        STA  LEOF
        RTS

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
        LDP1 #FNAME
        JSR  WORDCOPY
        JSR  ASKIPSP2
        LDP1 #OUTNAME
        JSR  WORDCOPY
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
        LDA  (P2)
        JSR  UPCASE
        STA  (P1)+
        INP2
        LDA  DIG
        DEC
        STA  DIG
        JMP  WC_CP
WC_DONE:RTS
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
