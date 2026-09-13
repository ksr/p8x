; =============================================================================
; P8X CC - native C compiler (standalone TPA program), Tier A edition
; =============================================================================
;     RUN CC.BIN SRC.C >OUT.ASM      (then: ASM OUT.ASM  ->  a RUNnable .BIN)
;
; A single-pass C compiler written directly in assembly, small enough to run ON
; the P8X. It streams the source through the BIOS read stream (FOPEN/FGETB) and
; emits assembly text to stdout via SYS_PUTC, so `>OUT.ASM` captures it.
;
; This is the 2026-09-13 from-scratch rewrite for the Tier A ISA. The CODE IT
; GENERATES is the same as before, instruction for instruction (only the
; indentation of the emitted text changed from eight spaces to one tab), so
; every compiled command behaves exactly as it did; what changed is the
; compiler itself:
;   * every name table (locals, globals, functions, macros, struct tags and
;     members, spliced libraries) is ONE mechanism: entries in an arena, chained
;     from a 32-way first-letter head array, read and written through (P1+d):
;     [next:2][len:1][flag:1][value:2][chars]. A lookup walks one chain and
;     rejects an entry on its length before touching a character; the old
;     packed pools walked every name byte by byte, and every identifier paid
;     that for the macro table alone.
;   * the lexer classifies keywords once (KWFIND -> CURKW) instead of the
;     parser running up to ten string compares per statement.
;   * all 16-bit arithmetic (slot numbers, literals, decimal output) uses the
;     word ops; the decimal emitter is CMPW/SUBW against the powers of ten.
;   * emitted text is walked with one pointer (the OS's SYS_PUTC preserves
;     P1/P2), one instruction per character instead of a reload each time.
;   * the variables and tables live at BSS ($A000-$DFFF, free TPA while the
;     compiler runs) and are cleared at start, so the binary is code only.
;   * a syntax error stops the compile with a message instead of looping.
;   * (2026-09-13, later the same day, found by writing the C twin apps/cc.c
;     and diffing the two compilers' output) three fixes: the right operand of
;     '&&' leaves condition mode (`if (a && b == c)` used to branch on the
;     relational alone and fall into the body when `a` was false); label
;     numbers are 16-bit (a byte counter wrapped at 256 and grep got duplicate
;     labels); a local array's size is 16-bit arithmetic (`char b[300]` got 21
;     slots instead of 150). Function and macro caps 250 (were 64), the global
;     arena 11.5 KB (was 3.5): enough to compile apps/cc.c on the machine.
;
; Language (unchanged): type = int (16-bit) | char (1-byte elements)
;     program : (func | global | struct-def)*   global : type [*]NAME [[N]] ;
;     struct-def : struct TAG { (type [*]member;)* } ;   access: v.m  p->m
;     func : type NAME([type [*]P,...]) { <stmt>* }    (prototype: ... ) ;)
;     stmt : type [*]NAME [= expr]; | type NAME[N]; | NAME = expr; |
;            NAME++; | NAME--; | NAME+=e; | NAME-=e; |
;            NAME[i] = expr; | NAME.m = e; | NAME->m = e; | *expr = expr; |
;            expr; | if(e) s [else s] | while(e) s | for([asg];[e];[asg]) s |
;            break; | continue; | { s* } | putchar(e); | return [e];
;     expr : cond ? expr : expr | land ('||' land)*   land : bor ('&&' bor)*
;     bor : bxor ('|' bxor)*   bxor : band ('^' band)*   band : rel ('&' rel)*
;     rel  : sh [relop sh]   sh : add (('<<'|'>>') add)*   add : term (('+'|'-') term)*
;     term : unary (('*'|'/'|'%') unary)*
;     unary : ('-'|'!'|'*'|'&'|'++'|'--') unary | factor
;     factor : NUM(dec/0xhex) | 'c' | "str" | NAME | NAME[i] | NAME(args) |
;              NAME.m | NAME->m | NAME++ | NAME-- |
;              builtins: putchar/puts/getchar/peek/poke/argstr/bios | '(' e ')'
;     //#use NAME       splices /lib/lib_NAME.c (once); //#define NAME value
; Codegen model (unchanged): a memory accumulator __ax and a temp __t0; every
; variable is a word slot in one array __V (slot n at __V+2n); each function's
; locals get STATIC slots from a global counter; arguments travel on the P3
; stack (PHW / LDW (P3+d) / ADDP3); a function saves its live slots around a
; call (re-entrancy); condition mode turns a top-level relational into one
; CMPW + one branch.
;
; Conventions: the source is the BIOS read stream (no cursor pointer); output
; is SYS_PUTC. P1/P2 are scratch everywhere. P3 is the stack. Word ops clobber A.
; =============================================================================

; ---- BIOS / OS ----
FSDIRBUF = $0145   ; repoint the directory-scan buffer (A = page) off SBUF
FRESOLVE = $0133   ; resolve a path -> dir extent + leaf FNAME (P1 = path)
SYS_GETCWD = $2003 ; OS: write the CWD path (NUL-terminated) to (P1)
FOPEN    = $0124   ; open the resolved file for reading (P1 = 512-byte buffer)
FGETB    = $0127   ; next source byte -> A; C=1 at EOF
SYS_PUTC = $2009   ; emit A to stdout (redirectable by the shell); preserves P1/P2
RDBUF    = $FC00   ; FOPEN read buffer for the main source
ROSTATE  = $605E   ; BIOS read-stream state (13 contiguous bytes)
ROSDRV   = $6085   ; BIOS read-stream drive (1 byte)

CR       = $0D
LF       = $0A
TAB      = $09
MAXFUNC  = 250     ; function-table capacity (the "too many functions" message)
MAXMAC   = 250     ; //#define capacity
USELEVELS= 5       ; //#use nesting depth

; keyword codes (CURKW after an identifier token; 0 = not a keyword)
K_INT   = 1
K_CHAR  = 2
K_STRUCT= 3
K_IF    = 4
K_WHILE = 5
K_PUTC  = 6
K_RET   = 7
K_FOR   = 8
K_BRK   = 9
K_CONT  = 10
K_ELSE  = 11
K_BIOS  = 12
K_PUTS  = 13
K_GETC  = 14
K_PEEK  = 15
K_POKE  = 16
K_ARGSTR= 17

; relational operator codes (RELOP): the emitted compare / branch depend on it
R_LT = 0
R_LE = 1
R_GT = 2
R_GE = 3
R_EQ = 4
R_NE = 5

; =============================================================================
; BSS: $A000-$DFFF is free TPA while the compiler runs (the binary ends near
; $9200; the OS captures a built-in's output into the TPA, but a RUN program's
; output streams through FPUTB; FSDIRBUF is moved to $E000 below; RDBUF is
; $FC00). Cleared at start.
; =============================================================================
BSS     = $A000
; -- word variables --
STK0    = BSS+$00   ; entry SP (a bail returns straight to the OS)
CURV    = BSS+$02   ; current token value (NUM value / PUNCT char)
NACC    = BSS+$04   ; lexer number accumulator
NTMP    = BSS+$06   ; scratch word (x10)
VN      = BSS+$08   ; number being emitted
SREL    = BSS+$0A   ; EMSLOT: 16-bit SLOTBASE-relative slot
SYMIDX  = BSS+$0C   ; SYMFIND/SYMADD result: slot relative to SLOTBASE (signed for globals)
LHSIDX  = BSS+$0E   ; assignment / declaration target slot
IDVARIDX= BSS+$10   ; gf_id: the variable's slot
SLOTCNT = BSS+$12   ; total variable slots so far (16-bit)
SLOTBASE= BSS+$14   ; the current function's first slot
CUR     = BSS+$16   ; table walk cursor
NTH     = BSS+$18   ; name tables: the head array in use
NTNAME  = BSS+$1A   ;   the name to find / add (NUL-terminated)
NTVAL   = BSS+$1C   ;   value field to store (NTADD)
ARENAP  = BSS+$1E   ;   global arena append pointer
LARENAP = BSS+$20   ;   local arena append pointer
MACVAL  = BSS+$22   ; MACLOOKUP result
BIOSAD  = BSS+$24   ; bios() intrinsic: the constant call address
TERM    = BSS+$26   ; scratch word
FENT    = BSS+$28   ; gfi_call: the callee's table entry
LASTENT = BSS+$2A   ; the variable entry most recently added (for an array mark)
; -- byte variables (cleared at start) --
PBF     = BSS+$30   ; pushback flag
PBC     = BSS+$31   ; pushback char
CURK    = BSS+$32   ; token kind: 0 EOF, 1 NUM, 2 ID, 3 PUNCT, 4 STRING
CUR2    = BSS+$33   ; second char of a two-char punct, else 0
CURKW   = BSS+$34   ; keyword code of an ID token (0 = plain identifier)
TIDLEN  = BSS+$35   ; length of TID
NTNLEN  = BSS+$36   ; length of the name at NTNAME
NTFLAG  = BSS+$37   ; flag byte to store (NTADD)
NTLOC   = BSS+$38   ; NTADD: 1 = append to the local arena
TMPB    = BSS+$39   ; byte scratch
TMPC    = BSS+$3A   ; byte scratch
TMPD    = BSS+$3B   ; byte scratch
SYMOK   = BSS+$3C   ; SYMFIND: found
SYMRCH  = BSS+$3D   ; SYMFIND result: char-typed
SYMRAR  = BSS+$3E   ; SYMFIND result: array
IDVAROK = BSS+$3F   ; gf_id: the id is a known variable
IDVARCH = BSS+$40
IDVARAR = BSS+$41
ELCHAR  = BSS+$42   ; ELEMADDR: char-typed base
ELARR   = BSS+$43   ; ELEMADDR: array (else pointer) base
LHSCH   = BSS+$44
LHSAR   = BSS+$45
EXPRCHAR= BSS+$46   ; the last factor loaded a char-typed value (for *p)
DCLCHAR = BSS+$47   ; the declaration being parsed is char-typed
NLSLOT  = BSS+$48   ; the current function's slot count
NPARAMS = BSS+$49   ; parameters of the function being defined
FCNT    = BSS+$4A   ; number of functions
MACCNT  = BSS+$4B   ; number of macros
RELOP   = BSS+$4D   ; relational operator code
RELF    = BSS+$4E   ; RELDET: it was a relational
CONDF   = BSS+$4F   ; the next GEXPR is a condition
CONDCUR = BSS+$50   ; GEXPR's copy of CONDF
CONDDONE= BSS+$52   ; GREL emitted the branch itself
USEMUL  = BSS+$55   ; runtime helpers needed
USEDIV  = BSS+$56
USENOT  = BSS+$57
USESHL  = BSS+$58
USESHR  = BSS+$59
USESP   = BSS+$5A   ; //#use nesting depth
STOFF   = BSS+$5B   ; struct being defined: running offset
TAGSIZE = BSS+$5C   ; STAGFIND result
STMEMOK = BSS+$5D   ; STMFIND result
STMEMOFF= BSS+$5E
STMEMCH = BSS+$5F
MEMTMP  = BSS+$60   ; member store width across an RHS
SAWADDRG= BSS+$61   ; an argument took an address
ARGI    = BSS+$62   ; call: argument count
VITER   = BSS+$63   ; slot loop counters
VITER2  = BSS+$64
ISCHARTYPE = BSS+$77
CURFNL  = BSS+$78   ; length of CURFN
IDNAMEL = BSS+$79   ; length of IDNAME
DQ      = BSS+$7A   ; decimal digit
HADH    = BSS+$7B   ; a digit was printed
USECNT  = BSS+$7C
; -- buffers --
TID     = BSS+$80   ; identifier text, NUL-terminated (24)
CURFN   = BSS+$A0   ; current function name (24)
IDNAME  = BSS+$C0   ; a factor's identifier (24)
NAMEBUF = BSS+$E0   ; //#use / //#define name (24)
PATH    = BSS+$100  ; raw source path argument (64)
APATHB  = BSS+$140  ; PATH made absolute (80)
LIBPATH = BSS+$190  ; "/lib/lib_<name>.c" (48)
STRBUF  = BSS+$1C0  ; current string literal (128)
; name-table heads: 32 words each (first char & 31), contiguous for the clear
HEADS   = BSS+$240
HLOC    = HEADS+$00  ; local variables of the current function
HGLOB   = HEADS+$40  ; globals
HFUNC   = HEADS+$80  ; functions
HMAC    = HEADS+$C0  ; //#define macros
HTAG    = HEADS+$100 ; struct tags
HMEM    = HEADS+$140 ; struct members
HUSED   = HEADS+$180 ; spliced libraries
HEADSEND= HEADS+$1C0
USESTATE= BSS+$400  ; saved read-stream state, 14 bytes x USELEVELS (70)
; label words -- 16-bit: a big program has more than 256 labels (grep has 600,
; the compiler's own C twin 900); a byte counter wrapped to duplicate labels
LBLW    = BSS+$460
CONDLBL = LBLW+$00  ; the false label of the condition
CURBRK  = LBLW+$02  ; innermost loop: break label
CURCONT = LBLW+$04  ;   continue label
JLBL    = LBLW+$06  ; EMITJ / EMITLBL: the label to print
NEWL    = LBLW+$08  ; NEWLBL's result
LBLCNT  = LBLW+$0A  ; next label number
LBLA    = LBLW+$0C
LBLB    = LBLW+$0E
IFTMP   = LBLW+$10
STRDL   = LBLW+$12
STRSL   = LBLW+$14
TERNF   = LBLW+$16
TERNE   = LBLW+$18
LORT    = LBLW+$1A
LORE    = LBLW+$1C
LANDF   = LBLW+$1E
LANDE   = LBLW+$20
LFT     = LBLW+$22
LFB     = LBLW+$24
LFP     = LBLW+$26
LFE     = LBLW+$28
WHT     = LBLW+$2A
WHE     = LBLW+$2C
USEBUF  = BSS+$500  ; per-level 512-byte read buffers (5 x 512 = $A00)
LARENA  = BSS+$F00  ; local-variable entries (reset per function) (768)
LARENAEND = BSS+$1200
ARENA   = BSS+$1200 ; global entries: globals, functions, macros, tags, members
ARENAEND= BSS+$4000 ; ($DFFF: 11.5 KB of names)
BSSEND  = BSS+$4000
; name-entry layout (relative to the entry pointer)
NT_NEXT = 0
NT_LEN  = 2
NT_FLAG = 3
NT_VAL  = 4
NT_CHARS= 6

        .org $6100               ; = TPABASE
START:  TPA3L
        STA  STK0
        TPA3H
        STA  STK0+1
        JSR  CLEARBSS            ; (keeps STK0)
        JSR  GETARG              ; PATH <- the first argument word
        LDA  PATH
        JZ   USAGE
        JSR  ABSPFX              ; APATHB <- PATH made absolute
        LDA  #$E0                ; move the directory-scan buffer to $E000 so
        JSR  FSDIRBUF            ;   FRESOLVE cannot clobber a redirected stream
        LDP1 #APATHB
        LDA  #0
        JSR  FRESOLVE
        LDP1 #RDBUF
        LDA  #0
        JSR  FOPEN
        JC   OPENERR
        LDW  ARENAP,#ARENA
        JSR  COMPILE
        RTS
USAGE:  LDP1 #MUSAGE
        JMP  EMIT
OPENERR:LDP1 #MNOSRC
        JMP  EMIT

; BAIL - P1 -> message: print it and return to the OS with the entry stack.
BAIL:   JSR  EMIT
        LPW3 STK0
        RTS

; CLEARBSS - zero everything after STK0 up to the //#use buffers: the head
;   arrays, the stream states and the label words (the arenas need no clearing:
;   the heads are the roots)
CLEARBSS:
        LDP1 #BSS+2
cb_l:   LDA  #0
        STA  (P1)+
        TPA1H
        LDB  #>USEBUF
        CMP
        JNZ  cb_l                ; until P1 reaches the //#use buffers
        RTS

; GETARG - copy the first blank-delimited word of the argument tail (P2 at
;   entry) into PATH, NUL-terminated (empty if there is no argument)
GETARG: LDP1 #PATH
ga_ss:  LDA  (P2)
        LDB  #' '
        CMP
        JNZ  ga_l
        INP2
        JMP  ga_ss
ga_l:   LDA  (P2)+
        JZ   ga_end
        LDB  #CR
        CMP
        JZ   ga_end
        LDB  #' '
        CMP
        JZ   ga_end
        STA  (P1)+
        JMP  ga_l
ga_end: LDA  #0
        STA  (P1)
        RTS

; ABSPFX - APATHB <- PATH made absolute: a leading '/' is copied as-is, a
;   relative path is prefixed with the CWD + '/' (FRESOLVE starts at root).
ABSPFX: LDP1 #APATHB
        LDA  PATH
        LDB  #'/'
        CMP
        JZ   ap_cat
        LDA  #0
        JSR  SYS_GETCWD          ; APATHB <- CWD
        LDP1 #APATHB
ap_en:  LDA  (P1)+
        JNZ  ap_en
        DEP1
        DEP1                     ; the last CWD character
        LDA  (P1)+
        LDB  #'/'
        CMP
        JZ   ap_cat              ; root "/" already ends in one
        LDA  #'/'
        STA  (P1)+
ap_cat: LDP2 #PATH
ap_cl:  LDA  (P2)+
        STA  (P1)+
        JNZ  ap_cl
        RTS

; =============================================================================
; Output: assembly text via SYS_PUTC
; =============================================================================
; EMIT - print the NUL-terminated string at P1 (SYS_PUTC preserves P1)
EMIT:   LDA  (P1)+
        JZ   em_d
        JSR  SYS_PUTC
        JMP  EMIT
em_d:   RTS

; EMITN - print A characters from P1
EMITN:  STA  TMPD
emn_l:  LDA  TMPD
        JZ   em_d
        DEC
        STA  TMPD
        LDA  (P1)+
        JSR  SYS_PUTC
        JMP  emn_l

; EMITNL - a newline
EMITNL: LDA  #LF
        JMP  SYS_PUTC

; EMITNUM - emit A (0..255) as decimal; EMITNUM16 - the word VN (no leading 0s)
EMITNUM:STA  VN
        LDA  #0
        STA  VN+1
EMITNUM16:
        LDA  #0
        STA  HADH
        LDW  NTMP,#10000
        JSR  EN_DIG
        LDW  NTMP,#1000
        JSR  EN_DIG
        LDW  NTMP,#100
        JSR  EN_DIG
        LDW  NTMP,#10
        JSR  EN_DIG
        LDA  VN                  ; the ones digit always prints
        LDB  #'0'
        ADD
        JMP  SYS_PUTC
; EN_DIG - one digit: how many times NTMP fits in VN; printed unless a leading 0
EN_DIG: LDA  #0
        STA  DQ
end_lp: CMPW VN,NTMP
        JNC  end_em
        SUBW VN,NTMP
        LDA  DQ
        INC
        STA  DQ
        JMP  end_lp
end_em: LDA  DQ
        JNZ  end_pr
        LDA  HADH
        JZ   end_ret
end_pr: LDA  DQ
        LDB  #'0'
        ADD
        JSR  SYS_PUTC
        LDA  #1
        STA  HADH
end_ret:RTS

; EMSLOT - emit the byte offset of the ABSOLUTE slot SLOTBASE + SREL (a 16-bit
;   two's-complement add: a global's SREL is negative) = 2 * slot.
EMSLOT: MOVW VN,SREL
        ADDW VN,SLOTBASE
        ADDW VN,VN
        JMP  EMITNUM16
EMSY:   MOVW SREL,SYMIDX         ; ... of slot SYMIDX
        JMP  EMSLOT
EMLH:   MOVW SREL,LHSIDX         ; ... of slot LHSIDX
        JMP  EMSLOT
EMSB:   STA  SREL                ; ... of slot A (0..255)
        LDA  #0
        STA  SREL+1
        JMP  EMSLOT

; EMHEX - emit A as two hex digits
EMHEX:  STA  TMPD
        SHR
        SHR
        SHR
        SHR
        JSR  EMNIB
        LDA  TMPD
        LDB  #$0F
        AND
EMNIB:  LDB  #10
        CMP
        JC   en_af
        LDB  #'0'
        ADD
        JMP  SYS_PUTC
en_af:  LDB  #$37                ; 'A' - 10
        ADD
        JMP  SYS_PUTC

; =============================================================================
; Name tables: [next:2][len:1][flag:1][val:2][chars] entries in an arena,
; chained from a 32-word head array by the name's first character (& 31).
;   NTH    = the head array          NTNAME / NTNLEN = the name
;   NTFIND -> C=1 and P1 = the entry, else C=0
;   NTADD  -> a new entry (flag NTFLAG, value NTVAL) in the global arena, or
;             the local one when NTLOC=1; P1 = the entry
; =============================================================================
; NTHEAD - P2 = &heads[first char & 31]
NTHEAD: LPW2 NTNAME
        LDA  (P2)
        LDB  #$1F
        AND
        SHL
        LDB  NTH
        ADD
        TAP2L
        LDA  #0
        ROL
        LDB  NTH+1
        ADD
        TAP2H
        RTS

NTFIND: JSR  NTHEAD
        LDW  CUR,(P2+0)          ; the chain's first entry
ntf_l:  LDA  CUR+1
        JZ   ntf_no              ; end of chain (entries live above $B000)
        LPW1 CUR
        LDA  (P1+2)              ; the length first
        LDB  NTNLEN
        CMP
        JNZ  ntf_nx
        LPW2 NTNAME
        INP1                     ; P1 -> the entry's characters
        INP1
        INP1
        INP1
        INP1
        INP1
        LDA  NTNLEN
        STA  TMPD
ntf_c:  LDA  TMPD
        JZ   ntf_yes
        DEC
        STA  TMPD
        LDA  (P1)+
        STA  TMPC
        LDA  (P2)+
        LDB  TMPC
        CMP
        JZ   ntf_c
        LPW1 CUR
ntf_nx: LDW  CUR,(P1+0)          ; next in chain
        JMP  ntf_l
ntf_yes:LPW1 CUR
        SEC
        RTS
ntf_no: CLC
        RTS

NTADD:  LDA  NTLOC
        JNZ  nta_loc
        MOVW CUR,ARENAP          ; the new entry
        LDA  NTNLEN
        STA  TMPD
        LDA  ARENAP+1            ; room? (entry <= 6+23 bytes; keep 32 spare)
        LDB  #>ARENAEND-32
        CMP
        JC   nta_full
        JMP  nta_go
nta_loc:MOVW CUR,LARENAP
        LDA  LARENAP+1
        LDB  #>LARENAEND-32
        CMP
        JNC  nta_go
        LDA  LARENAP
        LDB  #<LARENAEND-32
        CMP
        JC   nta_full
nta_go: JSR  NTHEAD              ; P2 = the head word
        LPW1 CUR
        LDW  TERM,(P2+0)         ; entry.next = old head
        STW  (P1+0),TERM
        STW  (P2+0),CUR          ; head = entry
        LDA  NTNLEN
        STA  (P1+2)
        LDA  NTFLAG
        STA  (P1+3)
        STW  (P1+4),NTVAL
        INP1
        INP1
        INP1
        INP1
        INP1
        INP1
        LPW2 NTNAME              ; the characters
        LDA  NTNLEN
        STA  TMPD
nta_c:  LDA  TMPD
        JZ   nta_e
        DEC
        STA  TMPD
        LDA  (P2)+
        STA  (P1)+
        JMP  nta_c
nta_e:  LDA  NTLOC
        JNZ  nta_le
        LEAW ARENAP,(P1+0)
        LPW1 CUR
        RTS
nta_le: LEAW LARENAP,(P1+0)
        LPW1 CUR
        RTS
nta_full:
        LDP1 #MTOOSYM
        JMP  BAIL

; NTSETTID - the name to look up / add is TID
NTSETTID:
        LDW  NTNAME,#TID
        LDA  TIDLEN
        STA  NTNLEN
        RTS

; =============================================================================
; Lexer (the BIOS read stream; one-char pushback)
; =============================================================================
; GC - the next source char -> A (C=0), or C=1 at the end of the source. At a
;   spliced library's end the parent stream resumes.
GC:     LDA  PBF
        JZ   gc_rd
        LDA  #0
        STA  PBF
        LDA  PBC
        CLC
        RTS
gc_rd:  JSR  FGETB
        JNC  gc_ok
        LDA  USESP
        JZ   gc_reof
        JSR  USEPOP
        JMP  gc_rd
gc_reof:SEC
        RTS
gc_ok:  CLC
        RTS
; UNGC - push A back
UNGC:   STA  PBC
        LDA  #1
        STA  PBF
        RTS

; ISDIG - C=1 if A is a digit; ISALP - C=1 if A is a letter or '_'. A kept.
ISDIG:  LDB  #'0'
        CMP
        JNC  isd_no
        LDB  #$3A
        CMP
        JC   isd_no
        SEC
        RTS
isd_no: CLC
        RTS
ISALP:  LDB  #'A'
        CMP
        JNC  isa_us
        LDB  #$5B                ; 'Z'+1
        CMP
        JNC  isa_yes
        LDB  #'a'
        CMP
        JNC  isa_us
        LDB  #$7B                ; 'z'+1
        CMP
        JNC  isa_yes
isa_us: LDB  #'_'
        CMP
        JZ   isa_yes
        CLC
        RTS
isa_yes:SEC
        RTS
; HEXVAL - A = char -> A = 0..15 with C=1, else C=0
HEXVAL: LDB  #'0'
        CMP
        JNC  hv_no
        LDB  #$3A
        CMP
        JNC  hv_dig
        LDB  #'a'
        CMP
        JNC  hv_up
        LDB  #$20
        SUB
hv_up:  LDB  #'A'
        CMP
        JNC  hv_no
        LDB  #'G'
        CMP
        JC   hv_no
        LDB  #$37                ; 'A'-10
        SUB
        RTS                      ; (SUB left C=1)
hv_dig: LDB  #'0'
        SUB
        RTS
hv_no:  CLC
        RTS

; SKIPLINE - consume the rest of the line (the LF included)
SKIPLINE:
        JSR  GC
        JC   skl_r
        LDB  #LF
        CMP
        JNZ  SKIPLINE
skl_r:  RTS

; ADVANCE - read the next token: CURK (0 EOF, 1 NUM, 2 ID, 3 PUNCT, 4 STRING),
;   CURV (value / punct char), CUR2 (second char of a two-char punct), TID +
;   TIDLEN + CURKW (an identifier and its keyword code), STRBUF (a string).
ADVANCE:
adv_ws: JSR  GC
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
        LDB  #TAB
        CMP
        JZ   adv_ws
        LDB  #'/'
        CMP
        JZ   adv_slash           ; a comment, a directive, or the divide
adv_cls:STA  TMPB
        JSR  ISDIG
        JC   adv_num
        LDA  TMPB
        JSR  ISALP
        JC   adv_id
        LDB  #$27                ; 'c'
        CMP
        JZ   adv_chl
        LDB  #$22                ; "string"
        CMP
        JZ   adv_stl
        LDA  #3                  ; punctuation
        STA  CURK
        LDA  TMPB
        STA  CURV
        LDA  #0
        STA  CUR2
        LDA  TMPB
        LDB  #'='
        CMP
        JZ   adv_2ck             ; ==
        LDB  #'!'
        CMP
        JZ   adv_2ck             ; !=
        LDB  #'<'
        CMP
        JZ   adv_ltgt            ; <= <<
        LDB  #'>'
        CMP
        JZ   adv_ltgt            ; >= >>
        LDB  #'&'
        CMP
        JZ   adv_2same           ; &&
        LDB  #'|'
        CMP
        JZ   adv_2same           ; ||
        LDB  #'+'
        CMP
        JZ   adv_pm              ; ++ +=
        LDB  #'-'
        CMP
        JZ   adv_pm              ; -- -= ->
        RTS
adv_pm: JSR  GC
        JC   adv_pd
        STA  TMPC
        LDB  #'='
        CMP
        JZ   adv_2set
        LDB  CURV
        CMP
        JZ   adv_2sset
        LDB  #'>'
        CMP
        JZ   adv_arrow
        JMP  UNGC
adv_arrow:
        LDA  #'>'                ; '->' : CURV='-', CUR2='>'
        STA  CUR2
        RTS
adv_ltgt:
        JSR  GC
        JC   adv_pd
        STA  TMPC
        LDB  #'='
        CMP
        JZ   adv_2set
        LDB  CURV
        CMP
        JZ   adv_2sset
        JMP  UNGC
adv_2same:
        JSR  GC
        JC   adv_pd
        STA  TMPC
        LDB  CURV
        CMP
        JZ   adv_2sset
        JMP  UNGC
adv_2sset:
        LDA  CURV                ; the doubled char
        STA  CUR2
        RTS
adv_2ck:JSR  GC
        JC   adv_pd
        STA  TMPC
        LDB  #'='
        CMP
        JZ   adv_2set
        JMP  UNGC
adv_2set:
        LDA  #'='
        STA  CUR2
adv_pd: RTS
adv_eof:LDA  #0
        STA  CURK
        RTS
; 'x' or '\x' -> a NUMBER token
adv_chl:JSR  GC
        STA  TMPB
        LDB  #$5C
        CMP
        JNZ  ach_v
        JSR  GC
        JSR  ESCMAP
        JMP  ach_set
ach_v:  LDA  TMPB
ach_set:STA  CURV
        LDA  #0
        STA  CURV+1
        LDA  #1
        STA  CURK
        JMP  GC                  ; the closing quote
; ESCMAP - the char after a backslash -> the byte it denotes
ESCMAP: LDB  #'n'
        CMP
        JNZ  esc1
        LDA  #10
        RTS
esc1:   LDB  #'t'
        CMP
        JNZ  esc2
        LDA  #9
        RTS
esc2:   LDB  #'r'
        CMP
        JNZ  esc3
        LDA  #13
        RTS
esc3:   LDB  #'0'
        CMP
        JNZ  esc_d
        LDA  #0
esc_d:  RTS                      ; \\ \' \" : the char itself
; "..." -> STRBUF (escapes kept raw: the assembler decodes them)
adv_stl:LDP2 #STRBUF
asl_l:  JSR  GC
        JC   asl_e
        LDB  #$22
        CMP
        JZ   asl_e
        STA  (P2)+
        LDB  #$5C
        CMP
        JNZ  asl_l
        JSR  GC                  ; the escaped char, raw
        JC   asl_e
        STA  (P2)+
        JMP  asl_l
asl_e:  LDA  #0
        STA  (P2)
        LDA  #4
        STA  CURK
        RTS
; '/' seen: // line comment (maybe a //# directive), /* block */, or divide
adv_slash:
        JSR  GC
        JC   adv_slp
        STA  TMPC
        LDB  #'/'
        CMP
        JZ   adv_linec
        LDB  #'*'
        CMP
        JZ   adv_blockc
        JSR  UNGC
adv_slp:LDA  #'/'
        JMP  adv_cls
adv_linec:
        JSR  GC
        JC   adv_eof
        LDB  #LF
        CMP
        JZ   adv_ws
        LDB  #'#'
        CMP
        JNZ  alc_skip
        JSR  GC                  ; //#d(efine) or //#u(se)
        JC   adv_ws
        LDB  #'d'
        CMP
        JZ   adv_def
        JSR  UNGC
        JSR  TRYUSE
        JMP  adv_ws
adv_def:JSR  TRYDEF
        JMP  adv_ws
alc_skip:
        JSR  SKIPLINE
        JMP  adv_ws
adv_blockc:
        JSR  GC
        JC   adv_eof
        LDB  #'*'
        CMP
        JNZ  adv_blockc
abc_st: JSR  GC
        JC   adv_eof
        LDB  #'/'
        CMP
        JZ   adv_ws
        LDB  #'*'
        CMP
        JZ   abc_st
        JMP  adv_blockc

; a number: decimal, or 0x hex. First char in TMPB.
adv_num:LDW  NACC,#0
        LDA  TMPB
        LDB  #'0'
        CMP
        JNZ  an_l
        JSR  GC                  ; after a '0': x/X -> hex
        JC   an_done
        STA  TMPC
        LDB  #'x'
        CMP
        JZ   an_hex
        LDB  #'X'
        CMP
        JZ   an_hex
        JSR  UNGC
        JMP  an_l
an_hex: JSR  GC
        JC   an_done
        STA  TMPB
        JSR  HEXVAL
        JNC  an_hx
        STA  DQ
        ADDW NACC,NACC
        ADDW NACC,NACC
        ADDW NACC,NACC
        ADDW NACC,NACC
        LDA  NACC
        LDB  DQ
        OR
        STA  NACC
        JMP  an_hex
an_hx:  LDA  TMPB
        JSR  UNGC
        JMP  an_done
an_l:   LDA  TMPB                ; NACC = NACC*10 + digit
        LDB  #'0'
        SUB
        STA  DQ
        ADDW NACC,NACC
        MOVW NTMP,NACC
        ADDW NACC,NACC
        ADDW NACC,NACC
        ADDW NACC,NTMP
        LDA  NACC
        LDB  DQ
        ADD
        STA  NACC
        JNC  an_c1
        LDA  NACC+1
        INC
        STA  NACC+1
an_c1:  JSR  GC
        JC   an_done
        STA  TMPB
        JSR  ISDIG
        JC   an_l
        JSR  UNGC
an_done:LDA  #1
        STA  CURK
        MOVW CURV,NACC
        RTS

; an identifier -> TID / TIDLEN; a keyword code or a macro substitution
adv_id: LDP2 #TID
        LDA  TMPB
        STA  (P2)+
        LDA  #1
        STA  TIDLEN
ai_l:   JSR  GC
        JC   ai_done
        STA  TMPB
        JSR  ISDIG
        JC   ai_put
        JSR  ISALP
        JC   ai_put
        JSR  UNGC
        JMP  ai_done
ai_put: LDA  TIDLEN
        LDB  #23
        CMP
        JC   ai_l                ; overlong: keep reading, stop storing
        INC
        STA  TIDLEN
        LDA  TMPB
        STA  (P2)+
        JMP  ai_l
ai_done:LDA  #0
        STA  (P2)
        LDA  MACCNT              ; a //#define macro? -> NUMBER token
        JZ   ai_kw
        JSR  NTSETTID
        LDW  NTH,#HMAC
        JSR  NTFIND
        JNC  ai_kw
        LDA  #1
        STA  CURK
        LDW  CURV,(P1+4)
        RTS
ai_kw:  JSR  KWFIND              ; CURKW = keyword code (0 = plain identifier)
        LDA  #2
        STA  CURK
        RTS

; KWFIND - CURKW = the keyword code of TID, 0 if none. KWTAB: [len][chars][code]
KWFIND: LDA  #0
        STA  CURKW
        LDP2 #KWTAB
kw_e:   LDA  (P2)+
        JZ   kw_d                ; table end
        STA  TMPD
        LDB  TIDLEN
        CMP
        JNZ  kw_sk
        LDP1 #TID
kw_c:   LDA  (P2)+
        STA  TMPC
        LDA  (P1)+
        LDB  TMPC
        CMP
        JNZ  kw_sk1
        LDA  TMPD
        DEC
        STA  TMPD
        JNZ  kw_c
        LDA  (P2)                ; the code
        STA  CURKW
kw_d:   RTS
kw_sk1: LDA  TMPD                ; skip the rest of the chars (TMPD-1 more) + the code
        DEC
        STA  TMPD
        JZ   kw_sk0
kw_sk:  LDA  TMPD                ; skip TMPD chars + the code
        JZ   kw_sk0
        DEC
        STA  TMPD
        INP2
        JMP  kw_sk
kw_sk0: INP2                     ; the code byte
        JMP  kw_e
KWTAB:  .byte 3
        .ascii "int"
        .byte K_INT
        .byte 4
        .ascii "char"
        .byte K_CHAR
        .byte 6
        .ascii "struct"
        .byte K_STRUCT
        .byte 2
        .ascii "if"
        .byte K_IF
        .byte 5
        .ascii "while"
        .byte K_WHILE
        .byte 7
        .ascii "putchar"
        .byte K_PUTC
        .byte 6
        .ascii "return"
        .byte K_RET
        .byte 3
        .ascii "for"
        .byte K_FOR
        .byte 5
        .ascii "break"
        .byte K_BRK
        .byte 8
        .ascii "continue"
        .byte K_CONT
        .byte 4
        .ascii "else"
        .byte K_ELSE
        .byte 4
        .ascii "bios"
        .byte K_BIOS
        .byte 4
        .ascii "puts"
        .byte K_PUTS
        .byte 7
        .ascii "getchar"
        .byte K_GETC
        .byte 4
        .ascii "peek"
        .byte K_PEEK
        .byte 4
        .ascii "poke"
        .byte K_POKE
        .byte 6
        .ascii "argstr"
        .byte K_ARGSTR
        .byte 0

; =============================================================================
; //#use NAME - splice /lib/lib_NAME.c (once); //#define NAME value
; =============================================================================
; RDNAME - skip blanks, read an identifier into NAMEBUF (NUL-terminated,
;   NTNLEN = its length); TMPB = the char after it (LF at EOF)
RDNAME: JSR  GC
        JC   rn_eof
        STA  TMPB
        LDB  #' '
        CMP
        JZ   RDNAME
        LDP2 #NAMEBUF
        LDA  #0
        STA  NTNLEN
rn_nm:  LDA  TMPB
        JSR  ISALP
        JC   rn_put
        JSR  ISDIG
        JC   rn_put
        JMP  rn_end
rn_put: STA  (P2)+
        LDA  NTNLEN
        INC
        STA  NTNLEN
        JSR  GC
        JC   rn_eof
        STA  TMPB
        JMP  rn_nm
rn_eof: LDA  #LF
        STA  TMPB
rn_end: LDA  #0
        STA  (P2)
        LDW  NTNAME,#NAMEBUF
        RTS

; TRYUSE - "//#" consumed: expect "use NAME" -> splice; else skip the line
TRYUSE: LDP2 #MUSEKW            ; "use"
        JSR  MATCHKW
        JNC  KWBAD
        JSR  RDNAME
        LDA  NTNLEN
        JZ   tu_eol
        LDA  TMPB                ; to the end of the line
        LDB  #LF
        CMP
        JZ   tu_do
        JSR  SKIPLINE
tu_do:  JMP  DOUSE
tu_eol: LDA  TMPB
        LDB  #LF
        CMP
        JZ   tu_r
        JMP  SKIPLINE
tu_r:   RTS

; MATCHKW - do the next source chars spell the string at P2? C=1 yes (consumed)
;   / C=0 no (the mismatching char is in A; the line is then skipped by callers)
MATCHKW:LDA  (P2)+
        JZ   mkw_yes
        STA  TMPC
        JSR  GC
        JC   mkw_no
        LDB  TMPC
        CMP
        JZ   MATCHKW
mkw_no: CLC
        RTS
mkw_yes:SEC
        RTS
; KWBAD - a directive that did not match: skip the rest of its line, unless
;   the mismatching char (A) already was the newline
KWBAD:  LDB  #LF
        CMP
        JZ   kwb_r
        JMP  SKIPLINE
kwb_r:  RTS
MUSEKW: .asciiz "use"
MDEFKW: .asciiz "efine"

; TRYDEF - "//#d" consumed: expect "efine NAME value"
TRYDEF: LDP2 #MDEFKW
        JSR  MATCHKW
        JNC  KWBAD
        JSR  RDNAME
td_vs:  LDA  TMPB                ; blanks between the name and the value
        LDB  #' '
        CMP
        JNZ  td_val
        JSR  GC
        JC   td_ret
        STA  TMPB
        JMP  td_vs
td_val: JSR  adv_num             ; the value (dec / 0x) -> CURV
        LDA  MACCNT
        LDB  #MAXMAC
        CMP
        JNC  td_add
        LDP1 #MTOOMAC
        JMP  BAIL
td_add: INC
        STA  MACCNT
        LDW  NTH,#HMAC
        MOVW NTVAL,CURV
        LDA  #0
        STA  NTFLAG
        STA  NTLOC
        JSR  NTADD
        JSR  SKIPLINE
td_ret: RTS

; DOUSE - NAMEBUF: once only; save the stream state, open /lib/lib_NAME.c
DOUSE:  LDW  NTH,#HUSED
        JSR  NTFIND
        JC   du_done             ; already spliced
        LDA  #0
        STA  NTFLAG
        STA  NTLOC
        JSR  NTADD
        LDA  USESP
        LDB  #USELEVELS
        CMP
        JC   du_done             ; nested too deep: ignore
        JSR  BUILDLIBPATH
        JSR  SAVESTATE
        LDP1 #LIBPATH
        LDA  #0
        JSR  FRESOLVE
        JSR  LIBBUFPTR           ; P1 = USEBUF + USESP*512
        LDA  #0
        JSR  FOPEN
        JC   du_fail
        LDA  USESP
        INC
        STA  USESP
        RTS
du_fail:JMP  RESTORESTATE        ; not found: the parent stream continues
du_done:RTS

; BUILDLIBPATH - LIBPATH = "/lib/lib_" + NAMEBUF + ".c"
BUILDLIBPATH:
        LDP2 #LIBPATH
        LDP1 #M_LIBPFX
        JSR  STRCAT
        LDP1 #NAMEBUF
        JSR  STRCAT
        LDP1 #M_DOTC
        JSR  STRCAT
        LDA  #0
        STA  (P2)
        RTS
; STRCAT - copy the string at P1 to P2 (without its NUL); P2 left after it
STRCAT: LDA  (P1)+
        JZ   sc_d
        STA  (P2)+
        JMP  STRCAT
sc_d:   RTS
M_LIBPFX: .asciiz "/lib/lib_"
M_DOTC:   .asciiz ".c"

; LIBBUFPTR - P1 = USEBUF + USESP*512
LIBBUFPTR:
        LDA  USESP
        SHL
        LDB  #>USEBUF
        ADD
        TAP1H
        LDA  #<USEBUF
        TAP1L
        RTS
; USESTP - P2 = USESTATE + USESP*14
USESTP: LDA  USESP
        SHL
        STA  TMPC                ; x2
        SHL
        SHL                      ; x8
        LDB  TMPC
        ADD                      ; x10
        LDB  TMPC
        ADD                      ; x12
        LDB  TMPC
        ADD                      ; x14
        LDB  #<USESTATE
        ADD
        TAP2L
        LDA  #>USESTATE
        TAP2H
        RTS
; SAVESTATE - USESTATE[USESP] <- the 13-byte read state + the drive
SAVESTATE:
        JSR  USESTP
        LDP1 #ROSTATE
        LDA  #13
        STA  USECNT
ss_l:   LDA  (P1)+
        STA  (P2)+
        LDA  USECNT
        DEC
        STA  USECNT
        JNZ  ss_l
        LDA  ROSDRV
        STA  (P2)
        RTS
; RESTORESTATE - the BIOS read state <- USESTATE[USESP]
RESTORESTATE:
        JSR  USESTP
        LDP1 #ROSTATE
        LDA  #13
        STA  USECNT
rs_l:   LDA  (P2)+
        STA  (P1)+
        LDA  USECNT
        DEC
        STA  USECNT
        JNZ  rs_l
        LDA  (P2)
        STA  ROSDRV
        RTS
; USEPOP - a spliced library ended: back to the parent stream
USEPOP: LDA  USESP
        DEC
        STA  USESP
        JMP  RESTORESTATE

; =============================================================================
; Symbols: locals (HLOC, per function), globals (HGLOB), functions (HFUNC),
; struct tags (HTAG) and members (HMEM). Entry flag: bit0 char, bit1 array
; (functions: the parameter count); value: the slot / size / offset / base.
; =============================================================================
; SYMFIND - the identifier TID: a local, else a global. SYMOK; SYMIDX = its slot
;   relative to SLOTBASE (a global's is negative, 16-bit); SYMRCH / SYMRAR.
SYMFIND:JSR  NTSETTID
        LDW  NTH,#HLOC
        JSR  NTFIND
        JNC  sf_glob
        LDA  (P1+4)              ; a local: the slot (< 256)
        STA  SYMIDX
        LDA  #0
        STA  SYMIDX+1
sf_fl:  LDA  (P1+3)              ; the flags
        STA  TMPC
        LDB  #1
        AND
        STA  SYMRCH
        LDA  TMPC
        SHR
        STA  SYMRAR
        LDA  #1
        STA  SYMOK
        RTS
sf_glob:LDW  NTH,#HGLOB
        JSR  NTFIND
        JNC  sf_no
        LDW  SYMIDX,(P1+4)       ; a global: absolute slot - SLOTBASE
        SUBW SYMIDX,SLOTBASE
        JMP  sf_fl
sf_no:  LDA  #0
        STA  SYMOK
        RTS

; SYMADD - a new local named TID (char-ness DCLCHAR) at slot NLSLOT; SYMIDX =
;   that slot; LASTENT = the entry (for an array mark)
SYMADD: JSR  NTSETTID
        LDW  NTH,#HLOC
        LDA  DCLCHAR
        STA  NTFLAG
        LDA  NLSLOT
        STA  NTVAL
        STA  SYMIDX
        LDA  #0
        STA  NTVAL+1
        STA  SYMIDX+1
        LDA  #1
        STA  NTLOC
        JSR  NTADD
        LEAW LASTENT,(P1+0)
        LDA  NLSLOT
        INC
        STA  NLSLOT
        RTS

; GSYMADD - a new global named CURFN (char-ness DCLCHAR) at slot SLOTCNT
GSYMADD:LDW  NTNAME,#CURFN
        LDA  CURFNL
        STA  NTNLEN
        LDW  NTH,#HGLOB
        LDA  DCLCHAR
        STA  NTFLAG
        MOVW NTVAL,SLOTCNT
        LDA  #0
        STA  NTLOC
        JSR  NTADD
        LEAW LASTENT,(P1+0)
        RTS

; MARKARR - the most recently added variable is an array
MARKARR:LPW1 LASTENT
        LDA  (P1+3)
        LDB  #2
        OR
        STA  (P1+3)
        RTS

; CPCURFN / CPIDNAME - copy TID (+ length) into CURFN / IDNAME
CPCURFN:LDP2 #CURFN
        LDA  TIDLEN
        STA  CURFNL
        JMP  cpn_go
CPIDNAME:
        LDP2 #IDNAME
        LDA  TIDLEN
        STA  IDNAMEL
cpn_go: LDP1 #TID
cpn_l:  LDA  (P1)+
        STA  (P2)+
        JNZ  cpn_l
        RTS

; FADD - record the function CURFN: NPARAMS params, base slot SLOTBASE
FADD:   LDA  FCNT
        LDB  #MAXFUNC
        CMP
        JNC  fa_ok
        LDP1 #MTOOFUN
        JMP  BAIL
fa_ok:  INC
        STA  FCNT
        LDW  NTNAME,#CURFN
        LDA  CURFNL
        STA  NTNLEN
        LDW  NTH,#HFUNC
        LDA  NPARAMS
        STA  NTFLAG
        MOVW NTVAL,SLOTBASE
        LDA  #0
        STA  NTLOC
        JMP  NTADD

; EMITFNAME - emit the callee's name: its table entry FENT, or the identifier
;   itself for a function not (yet) declared -- the assembler resolves the label
EMITFNAME:
        LDA  FENT+1
        JZ   efn_id
        LPW1 FENT
        LDA  (P1+2)
        STA  TMPD
        INP1
        INP1
        INP1
        INP1
        INP1
        INP1
        LDA  TMPD
        JMP  EMITN
efn_id: LDP1 #IDNAME
        JMP  EMIT

; STAGADD - the struct tag CURFN has size STOFF
STAGADD:LDW  NTNAME,#CURFN
        LDA  CURFNL
        STA  NTNLEN
        LDW  NTH,#HTAG
        LDA  STOFF
        STA  NTVAL
        LDA  #0
        STA  NTVAL+1
        STA  NTFLAG
        STA  NTLOC
        JMP  NTADD
; STAGFIND_CURFN / STAGFIND_CURTID - TAGSIZE = the size of that tag (0 if unknown)
STAGFIND_CURFN:
        LDW  NTNAME,#CURFN
        LDA  CURFNL
        STA  NTNLEN
        JMP  stf_go
STAGFIND_CURTID:
        JSR  NTSETTID
stf_go: LDA  #0
        STA  TAGSIZE
        LDW  NTH,#HTAG
        JSR  NTFIND
        JNC  stf_no
        LDA  (P1+4)
        STA  TAGSIZE
stf_no: RTS

; STMADD_M - the member TID at offset STOFF, char-ness DCLCHAR
STMADD_M:
        JSR  NTSETTID
        LDW  NTH,#HMEM
        LDA  DCLCHAR
        STA  NTFLAG
        LDA  STOFF
        STA  NTVAL
        LDA  #0
        STA  NTVAL+1
        STA  NTLOC
        JMP  NTADD
; STMFIND - the member TID -> STMEMOK, STMEMOFF, STMEMCH
STMFIND:LDA  #0
        STA  STMEMOK
        JSR  NTSETTID
        LDW  NTH,#HMEM
        JSR  NTFIND
        JNC  smf_no
        LDA  (P1+4)
        STA  STMEMOFF
        LDA  (P1+3)
        STA  STMEMCH
        LDA  #1
        STA  STMEMOK
smf_no: RTS

; =============================================================================
; Parser + codegen (single pass; emits as it parses)
; =============================================================================
COMPILE:LDP1 #MORG               ; .org $6100
        JSR  EMIT
        LDP1 #MBOOT              ; the startup: JSR _f_main on a fresh stack
        JSR  EMIT
        JSR  ADVANCE
co_s:   LDA  CURK
        JZ   co_end
        JSR  FUNCDEF
        JMP  co_s
co_end: LDP1 #MCMP_DEF           ; the 16-bit equality compare (always)
        JSR  EMIT
        LDA  USEMUL
        JZ   ce_nomul
        LDP1 #MMULDEF
        JSR  EMIT
ce_nomul:
        LDA  USEDIV
        JZ   ce_nodiv
        LDP1 #MDMDEF
        JSR  EMIT
ce_nodiv:
        LDA  USENOT
        JZ   ce_nonot
        LDP1 #MLNOT_DEF
        JSR  EMIT
ce_nonot:
        LDA  USESHL
        JZ   ce_noshl
        LDP1 #MSHLDEF
        JSR  EMIT
ce_noshl:
        LDA  USESHR
        JZ   ce_noshr
        LDP1 #MSHRDEF
        JSR  EMIT
ce_noshr:
        LDP1 #MTEMP              ; __t0 __sp0 __ax __c __sc
        JSR  EMIT
        LDP1 #MVBASE             ; __V: .fill 2*SLOTCNT
        JSR  EMIT
        MOVW VN,SLOTCNT
        ADDW VN,VN
        JSR  EMITNUM16
        JMP  EMITNL

; ISPUNCT - C=1 if the current token is the single-char punct A
ISPUNCT:STA  TMPD
        LDA  CURK
        LDB  #3
        CMP
        JNZ  isp_no
        LDA  CUR2
        JNZ  isp_no
        LDA  CURV
        LDB  TMPD
        CMP
        JNZ  isp_no
        SEC
        RTS
isp_no: CLC
        RTS

; EXPECTP - the current token must be the punct A, then ADVANCE
EXPECTP:JSR  ISPUNCT
        JNC  SYNTAXERR
        JMP  ADVANCE
SYNTAXERR:
        LDP1 #MSYNERR
        JMP  BAIL

; SKIPSTARS - skip pointer stars
SKIPSTARS:
        LDA  #'*'
        JSR  ISPUNCT
        JNC  sks_r
        JSR  ADVANCE
        JMP  SKIPSTARS
sks_r:  RTS

; EXPECTTYPE - int / char (ISCHARTYPE), advance past it
EXPECTTYPE:
        LDA  #0
        STA  ISCHARTYPE
        LDA  CURK
        LDB  #2
        CMP
        JNZ  SYNTAXERR
        LDA  CURKW
        LDB  #K_INT
        CMP
        JZ   ADVANCE
        LDB  #K_CHAR
        CMP
        JNZ  SYNTAXERR
        LDA  #1
        STA  ISCHARTYPE
        JMP  ADVANCE

; ---- structs: tag -> size, global member -> offset (member names unique) ----
; sdf_body - CURFN = the tag; current token '{'. Parse the members, record the tag.
sdf_body:
        LDA  #'{'
        JSR  EXPECTP
        LDA  #0
        STA  STOFF
sdf_l:  LDA  #'}'
        JSR  ISPUNCT
        JC   sdf_end
        JSR  EXPECTTYPE
        LDA  ISCHARTYPE
        STA  DCLCHAR
        LDA  #'*'                ; a pointer member is a word
        JSR  ISPUNCT
        JNC  sdf_ns
        LDA  #0
        STA  DCLCHAR
        JSR  SKIPSTARS
sdf_ns: JSR  STMADD_M
        JSR  ADVANCE             ; past the member name
        LDA  DCLCHAR             ; STOFF += 1 (char) or 2
        JNZ  sdf_c1
        LDA  STOFF
        INC
        STA  STOFF
sdf_c1: LDA  STOFF
        INC
        STA  STOFF
        LDA  #$3B
        JSR  EXPECTP
        JMP  sdf_l
sdf_end:LDA  #'}'
        JSR  EXPECTP
        JSR  STAGADD
        LDA  #$3B
        JMP  EXPECTP

; fd_struct - top level 'struct': a definition, or a global struct variable
fd_struct:
        JSR  ADVANCE             ; past 'struct'
        JSR  CPCURFN             ; the tag
        JSR  ADVANCE
        LDA  #'{'
        JSR  ISPUNCT
        JC   sdf_body
        JSR  STAGFIND_CURFN      ; a global: struct Tag [*]NAME ;
        LDA  #0
        STA  DCLCHAR
        STA  MEMTMP              ; pointer?
        LDA  #'*'
        JSR  ISPUNCT
        JNC  fdsv_nm
        JSR  SKIPSTARS
        LDA  #1
        STA  MEMTMP
fdsv_nm:JSR  CPCURFN             ; the variable name
        JSR  GSYMADD
        LDA  MEMTMP
        JNZ  fdsv_ptr
        LDA  TAGSIZE             ; a value: ceil(size/2) slots
        INC
        SHR
        STA  VN
        LDA  #0
        STA  VN+1
        ADDW SLOTCNT,VN
        JMP  fdsv_end
fdsv_ptr:
        INCW SLOTCNT
fdsv_end:
        JSR  ADVANCE             ; past NAME
        LDA  #$3B
        JMP  EXPECTP

; st_lstruct - local 'struct Tag [*]NAME ;'
st_lstruct:
        JSR  ADVANCE
        JSR  STAGFIND_CURTID
        JSR  ADVANCE             ; past the tag
        LDA  #0
        STA  DCLCHAR
        LDA  #'*'
        JSR  ISPUNCT
        JNC  sls_val
        JSR  SKIPSTARS
        JSR  SYMADD              ; a pointer: one slot
        JMP  sls_end
sls_val:JSR  SYMADD              ; a value: ceil(size/2) slots (one counted)
        LDA  TAGSIZE
        INC
        SHR
        DEC
        LDB  NLSLOT
        ADD
        STA  NLSLOT
sls_end:JSR  ADVANCE             ; past NAME
        LDA  #$3B
        JMP  EXPECTP

; EM_ADDOFF (A = offset) - emit __ax += offset (nothing for 0)
EM_ADDOFF:
        STA  MEMTMP
        LDB  #0
        CMP
        JZ   eao_d
        LDP1 #MADDWAXI
        JSR  EMIT
        LDA  MEMTMP
        JSR  EMITNUM
        JMP  EMITNL
eao_d:  RTS

; fd_glob - a global: type [*]NAME [ [N] ] ;  (CURFN = NAME, DCLCHAR set)
fd_glob:JSR  GSYMADD
        LDA  #'['
        JSR  ISPUNCT
        JC   fdg_arr
        INCW SLOTCNT
        JMP  fdg_end
fdg_arr:JSR  MARKARR
        JSR  ADVANCE             ; past '['
        MOVW VN,CURV
        LDA  DCLCHAR
        JZ   fdg_aint
        INCW VN                  ; char array: ceil(N/2) words
        LDA  VN+1
        SHR
        STA  VN+1
        LDA  VN
        ROR
        STA  VN
fdg_aint:
        ADDW SLOTCNT,VN
        JSR  ADVANCE             ; past the size
        LDA  #']'
        JSR  EXPECTP
fdg_end:LDA  #$3B
        JMP  EXPECTP

; FUNCDEF - one top-level item: a struct, a global, a prototype or a function
FUNCDEF:LDA  CURK
        LDB  #2
        CMP
        JNZ  SYNTAXERR
        LDA  CURKW
        LDB  #K_STRUCT
        CMP
        JZ   fd_struct
        JSR  EXPECTTYPE
        LDA  ISCHARTYPE
        STA  DCLCHAR
        JSR  SKIPSTARS           ; a pointer return type / global
        JSR  CPCURFN             ; NAME
        JSR  ADVANCE
        LDA  #'('
        JSR  ISPUNCT
        JNC  fd_glob
        MOVW SLOTBASE,SLOTCNT    ; a function: fresh slots, fresh local table
        LDA  #0
        STA  NLSLOT
        STA  NPARAMS
        JSR  CLEARLOC
        JSR  ADVANCE             ; past '('
        LDA  #')'
        JSR  ISPUNCT
        JC   fp_done
fp_loop:JSR  EXPECTTYPE
        LDA  ISCHARTYPE
        STA  DCLCHAR
        JSR  SKIPSTARS
        JSR  SYMADD              ; the parameter: slots 0..n-1
        JSR  ADVANCE
        LDA  NPARAMS
        INC
        STA  NPARAMS
        LDA  #','
        JSR  ISPUNCT
        JNC  fp_done
        JSR  ADVANCE
        JMP  fp_loop
fp_done:LDA  #')'
        JSR  EXPECTP
        LDA  #$3B                ; a prototype registers the name
        JSR  ISPUNCT
        JNC  fd_def
        JSR  FADD
        JMP  ADVANCE
fd_def: JSR  FADD
        LDP1 #MFPFX              ; _f_NAME:
        JSR  EMIT
        LDP1 #CURFN
        JSR  EMIT
        LDP1 #MCOLON
        JSR  EMIT
        JSR  EM_POPPARAMS
        LDA  #'{'
        JSR  EXPECTP
fd_s:   LDA  #'}'
        JSR  ISPUNCT
        JC   fd_end
        JSR  STMT
        JMP  fd_s
fd_end: LDA  #'}'
        JSR  EXPECTP
        LDP1 #MEPFX              ; _e_NAME: RTS
        JSR  EMIT
        LDP1 #CURFN
        JSR  EMIT
        LDP1 #MCOLON
        JSR  EMIT
        LDP1 #MRTS
        JSR  EMIT
        LDA  NLSLOT              ; SLOTCNT = SLOTBASE + NLSLOT
        STA  VN
        LDA  #0
        STA  VN+1
        MOVW SLOTCNT,SLOTBASE
        ADDW SLOTCNT,VN
        RTS

; CLEARLOC - empty the local table
CLEARLOC:
        LDW  LARENAP,#LARENA
        LDP1 #HLOC
        LDA  #32
        STA  TMPD
cl_l:   LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  TMPD
        DEC
        STA  TMPD
        JNZ  cl_l
        RTS

; EM_POPPARAMS - the prologue: LDW __V+2*slot(i),(P3+3+2*(NPARAMS-1-i))
EM_POPPARAMS:
        LDA  NPARAMS
        JZ   epp_d
        STA  VITER
epp_l:  LDA  VITER
        DEC
        STA  VITER
        LDP1 #MLDWV
        JSR  EMIT
        LDA  VITER
        JSR  EMSB
        LDP1 #MCP3
        JSR  EMIT
        LDA  NPARAMS
        LDB  VITER
        SUB
        DEC
        SHL
        LDB  #3
        ADD
        JSR  EMITNUM
        LDP1 #MCLNL
        JSR  EMIT
        LDA  VITER
        JNZ  epp_l
epp_d:  RTS

; ---- statements ----
STMT:   LDA  CURK
        LDB  #3
        CMP
        JZ   st_punct
        LDB  #2
        CMP
        JNZ  SYNTAXERR
        LDA  CURKW
        JZ   st_assign           ; an identifier: assignment / expression
        LDB  #K_BIOS
        CMP
        JC   st_assign           ; a builtin call: an expression statement
        SHL                      ; P1 = &STMTTAB[CURKW-1]
        LDB  #<STMTTAB-2
        ADD
        TAP1L
        LDA  #0
        ROL
        LDB  #>STMTTAB-2
        ADD
        TAP1H
        LDW  CUR,(P1+0)
        LPW1 CUR
        JSR  (P1)
        RTS
STMTTAB:.word st_decl,st_decl,st_lstruct,st_if       ; int char struct if
        .word st_while,st_putc,st_ret,st_for         ; while putchar return for
        .word st_break,st_continue,SYNTAXERR         ; break continue else
st_punct:
        LDA  CUR2
        JNZ  SYNTAXERR
        LDA  CURV
        LDB  #'{'
        CMP
        JZ   st_block
        LDB  #'*'
        CMP
        JZ   st_derefasg
        LDB  #$3B
        CMP
        JNZ  SYNTAXERR
        JMP  ADVANCE             ; an empty statement

; *ptr = expr ;
st_derefasg:
        JSR  ADVANCE
        JSR  GUNARY              ; the address -> __ax
        JSR  EM_PUSH
        LDA  #'='
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EM_POP
        JSR  EM_STOREW
        LDA  #$3B
        JMP  EXPECTP

; { stmt* }
st_block:
        LDA  #'{'
        JSR  EXPECTP
sb_l:   LDA  #'}'
        JSR  ISPUNCT
        JC   sb_end
        JSR  STMT
        JMP  sb_l
sb_end: LDA  #'}'
        JMP  EXPECTP

; COND - '(' condition ')' in condition mode: the false label is CONDLBL (set
;   by the caller). Emits the test-and-branch unless GREL already branched.
COND:   LDA  #'('
        JSR  EXPECTP
        LDA  #1
        STA  CONDF
        JSR  GEXPR
        LDA  #')'
        JSR  EXPECTP
        LDA  CONDDONE
        JNZ  cnd_d
        JSR  EM_TESTAX
        MOVW JLBL,CONDLBL
        LDP1 #MJZ
        JMP  EMITJ
cnd_d:  RTS

; if ( expr ) stmt [ else stmt ]
st_if:  JSR  ADVANCE
        JSR  NEWLBL              ; la = the false target
        MOVW CONDLBL,NEWL
        PHW  NEWL
        JSR  COND
        JSR  STMT                ; then
        LDA  CURK
        LDB  #2
        CMP
        JNZ  if_ne
        LDA  CURKW
        LDB  #K_ELSE
        CMP
        JNZ  if_ne
        JSR  ADVANCE
        PLW  IFTMP               ; la
        JSR  NEWLBL              ; lb = the end
        PHW  NEWL
        MOVW JLBL,NEWL
        LDP1 #MJMP
        JSR  EMITJ               ; JMP lb
        MOVW JLBL,IFTMP
        JSR  EMITLBL             ; la:
        JSR  STMT                ; else
        PLW  JLBL
        JMP  EMITLBL             ; lb:
if_ne:  PLW  JLBL
        JMP  EMITLBL             ; la:

; break ; / continue ;
st_break:
        JSR  ADVANCE
        MOVW JLBL,CURBRK
        LDP1 #MJMP
        JSR  EMITJ
        LDA  #$3B
        JMP  EXPECTP
st_continue:
        JSR  ADVANCE
        MOVW JLBL,CURCONT
        LDP1 #MJMP
        JSR  EMITJ
        LDA  #$3B
        JMP  EXPECTP

; for ( [init] ; [cond] ; [post] ) stmt
;   init ; Ltop: cond ? JZ Lend ; JMP Lbody ; Lpost: post ; JMP Ltop ;
;   Lbody: body ; JMP Lpost ; Lend:
st_for: JSR  ADVANCE
        LDA  #'('
        JSR  EXPECTP
        JSR  NEWLBL
        MOVW LFT,NEWL
        JSR  NEWLBL
        MOVW LFB,NEWL
        JSR  NEWLBL
        MOVW LFP,NEWL
        JSR  NEWLBL
        MOVW LFE,NEWL
        JSR  FORCLAUSE           ; init
        LDA  #$3B
        JSR  EXPECTP
        MOVW JLBL,LFT
        JSR  EMITLBL             ; Ltop:
        LDA  #$3B                ; an empty condition?
        JSR  ISPUNCT
        JC   sf_nocond
        MOVW CONDLBL,LFE
        LDA  #1
        STA  CONDF
        JSR  GEXPR
        LDA  CONDDONE
        JNZ  sf_nocond
        JSR  EM_TESTAX
        MOVW JLBL,LFE
        LDP1 #MJZ
        JSR  EMITJ               ; JZ Lend
sf_nocond:
        LDA  #$3B
        JSR  EXPECTP
        MOVW JLBL,LFB
        LDP1 #MJMP
        JSR  EMITJ               ; JMP Lbody
        MOVW JLBL,LFP
        JSR  EMITLBL             ; Lpost:
        JSR  FORCLAUSE           ; post
        LDA  #')'
        JSR  EXPECTP
        MOVW JLBL,LFT
        LDP1 #MJMP
        JSR  EMITJ               ; JMP Ltop
        MOVW JLBL,LFB
        JSR  EMITLBL             ; Lbody:
        PHW  CURBRK              ; save the enclosing targets and our labels
        PHW  CURCONT
        PHW  LFP
        PHW  LFE
        MOVW CURBRK,LFE          ; break -> Lend
        MOVW CURCONT,LFP         ; continue -> Lpost
        JSR  STMT
        PLW  LFE
        PLW  LFP
        PLW  CURCONT
        PLW  CURBRK
        MOVW JLBL,LFP
        LDP1 #MJMP
        JSR  EMITJ               ; JMP Lpost
        MOVW JLBL,LFE
        JMP  EMITLBL             ; Lend:

; FORCLAUSE - an optional NAME = expr
FORCLAUSE:
        LDA  CURK
        LDB  #2
        CMP
        JNZ  fc_ret
        JSR  SYMFIND
        LDA  SYMOK
        JZ   fc_ret
        MOVW LHSIDX,SYMIDX
        JSR  ADVANCE
        LDA  #'='
        JSR  EXPECTP
        JSR  GEXPR
        JMP  EM_STVAR
fc_ret: RTS

; while ( expr ) stmt
st_while:
        JSR  ADVANCE
        JSR  NEWLBL
        MOVW WHT,NEWL
        JSR  NEWLBL
        MOVW WHE,NEWL
        MOVW JLBL,WHT
        JSR  EMITLBL             ; Ltop:
        MOVW CONDLBL,WHE
        JSR  COND                ; JZ Lend unless branched
        PHW  CURBRK
        PHW  CURCONT
        PHW  WHT
        PHW  WHE
        MOVW CURBRK,WHE          ; break -> Lend
        MOVW CURCONT,WHT         ; continue -> Ltop
        JSR  STMT
        PLW  WHE
        PLW  WHT
        PLW  CURCONT
        PLW  CURBRK
        MOVW JLBL,WHT
        LDP1 #MJMP
        JSR  EMITJ               ; JMP Ltop
        MOVW JLBL,WHE
        JMP  EMITLBL             ; Lend:

; type [*]NAME [= expr] ;  |  type NAME[N] ;
st_decl:LDA  CURKW
        LDB  #K_CHAR
        CMP
        JNZ  sd_int
        LDA  #1
        STA  DCLCHAR
        JMP  sd_adv
sd_int: LDA  #0
        STA  DCLCHAR
sd_adv: JSR  ADVANCE
        JSR  SKIPSTARS
        JSR  SYMADD
        MOVW LHSIDX,SYMIDX
        JSR  ADVANCE             ; past NAME
        LDA  #'['
        JSR  ISPUNCT
        JC   sd_arr
        LDA  #'='
        JSR  ISPUNCT
        JNC  sd_semi
        JSR  ADVANCE
        JSR  GEXPR
        JSR  EM_STVAR
        JMP  sd_semi
sd_arr: JSR  ADVANCE             ; past '['
        MOVW VN,CURV             ; (16-bit: a local char[300] is 150 slots --
        LDA  DCLCHAR             ;   the byte arithmetic gave it 21)
        JZ   sd_arrm
        INCW VN                  ; char: (N+1)/2 words
        LDA  VN+1
        SHR
        STA  VN+1
        LDA  VN
        ROR
        STA  VN
sd_arrm:LDA  VN
        DEC                      ; the base slot is already counted
        LDB  NLSLOT
        ADD
        STA  NLSLOT
        JSR  MARKARR
        JSR  ADVANCE             ; past the size
        LDA  #']'
        JSR  EXPECTP
sd_semi:LDA  #$3B
        JMP  EXPECTP

; NAME = e; NAME[i] = e; NAME.m = e; NAME->m = e; NAME++; NAME--; NAME += e;
; NAME -= e;  or an expression statement (a call)
st_assign:
        JSR  SYMFIND
        LDA  SYMOK
        JNZ  st_asg2
        JSR  GEXPR               ; not a variable: evaluate for the side effects
        LDA  #$3B
        JMP  EXPECTP
st_asg2:MOVW LHSIDX,SYMIDX
        LDA  SYMRCH
        STA  LHSCH
        LDA  SYMRAR
        STA  LHSAR
        JSR  ADVANCE             ; past NAME
        LDA  CURK
        LDB  #3
        CMP
        JNZ  SYNTAXERR
        LDA  CUR2
        JNZ  sa_two
        LDA  CURV
        LDB  #'['
        CMP
        JZ   sa_arrstore
        LDB  #'.'
        CMP
        JZ   sa_memdot
sa_asg: LDA  #'='                ; NAME = expr
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EM_STVAR
sa_semi:LDA  #$3B
        JMP  EXPECTP
sa_two: LDA  CURV                ; a two-char op: -> ++ -- += -=
        LDB  #'-'
        CMP
        JNZ  sa_plus
        LDA  CUR2
        LDB  #'>'
        CMP
        JZ   sa_memarrow
        LDB  #'-'
        CMP
        JZ   sa_dec              ; NAME--
        JSR  SA_CLOAD            ; NAME -= e
        LDP1 #MSUB
        JMP  sa_cst
sa_plus:LDB  #'+'
        CMP
        JNZ  SYNTAXERR
        LDA  CUR2
        LDB  #'+'
        CMP
        JZ   sa_inc              ; NAME++
        JSR  SA_CLOAD            ; NAME += e
        LDP1 #MADD
sa_cst: JSR  EMIT
        JSR  EM_STVAR
        JMP  sa_semi
sa_inc: MOVW SYMIDX,LHSIDX       ; one INCW / DECW in place
        JSR  ADVANCE
        JSR  EM_INCVAR
        JMP  sa_semi
sa_dec: MOVW SYMIDX,LHSIDX
        JSR  ADVANCE
        JSR  EM_DECVAR
        JMP  sa_semi
; SA_CLOAD - push the old NAME, the rhs -> __ax, __t0 = old NAME
SA_CLOAD:
        MOVW SYMIDX,LHSIDX
        JSR  EM_LDVAR
        JSR  EM_PUSH
        JSR  ADVANCE             ; past += / -=
        JSR  GEXPR
        JMP  EM_POP
sa_memdot:
        MOVW SYMIDX,LHSIDX
        JSR  EM_ADDROF
        JMP  sa_memcommon
sa_memarrow:
        MOVW SYMIDX,LHSIDX
        JSR  EM_LDVAR
sa_memcommon:
        JSR  ADVANCE             ; past . / ->
        JSR  STMFIND
        LDA  STMEMOFF
        JSR  EM_ADDOFF
        JSR  ADVANCE             ; past the member
        LDA  STMEMCH
        STA  MEMTMP
        JSR  EM_PUSH
        LDA  #'='
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EM_POP
        LDA  MEMTMP
        JNZ  sa_memb
        JSR  EM_STOREW
        JMP  sa_semi
sa_memb:JSR  EM_STOREB
        JMP  sa_semi
sa_arrstore:
        MOVW SYMIDX,LHSIDX
        LDA  LHSCH
        STA  ELCHAR
        LDA  LHSAR
        STA  ELARR
        JSR  ELEMADDR            ; __ax = the element address
        LDA  ELCHAR
        PHA
        JSR  EM_PUSH
        LDA  #'='
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EM_POP
        PLA
        JNZ  sas_b
        JSR  EM_STOREW
        JMP  sa_semi
sas_b:  JSR  EM_STOREB
        JMP  sa_semi

; putchar ( expr ) ;
st_putc:JSR  ADVANCE
        LDA  #'('
        JSR  EXPECTP
        JSR  GEXPR
        LDA  #')'
        JSR  EXPECTP
        LDA  #$3B
        JSR  EXPECTP
        LDP1 #MPUTC
        JMP  EMIT

; return [expr] ;
st_ret: JSR  ADVANCE
        LDA  #$3B
        JSR  ISPUNCT
        JC   sr_semi
        JSR  GEXPR
sr_semi:LDA  #$3B
        JSR  EXPECTP
        LDP1 #MJMPE              ; JMP _e_NAME
        JSR  EMIT
        LDP1 #CURFN
        JSR  EMIT
        JMP  EMITNL

; =============================================================================
; Expressions -> __ax
; =============================================================================
; GEXPR - the top: condition mode is consumed here (a nested GEXPR sees 0), then
;   GLOR and an optional ternary
GEXPR:  LDA  CONDF
        STA  CONDCUR
        LDA  #0
        STA  CONDF
        STA  CONDDONE
        JSR  GLOR
        LDA  #'?'
        JSR  ISPUNCT
        JNC  ge_condd
        JSR  ADVANCE
        JSR  EM_TESTAX
        JSR  NEWLBL
        MOVW TERNF,NEWL
        JSR  NEWLBL
        MOVW TERNE,NEWL
        MOVW JLBL,TERNF
        LDP1 #MJZ
        JSR  EMITJ               ; JZ Lfalse
        PHW  TERNF
        PHW  TERNE
        JSR  GEXPR               ; the true value
        PLW  TERNE
        PLW  TERNF
        LDA  #':'
        JSR  EXPECTP
        MOVW JLBL,TERNE
        LDP1 #MJMP
        JSR  EMITJ               ; JMP Lend
        MOVW JLBL,TERNF
        JSR  EMITLBL             ; Lfalse:
        PHW  TERNE
        JSR  GEXPR               ; the false value
        PLW  JLBL
        JMP  EMITLBL             ; Lend:
ge_condd:
        RTS

; ISTWO - C=1 if the current token is the two-char punct A A (&& || << >>)
ISTWO:  STA  TMPD
        LDA  CURK
        LDB  #3
        CMP
        JNZ  it_no
        LDA  CURV
        LDB  TMPD
        CMP
        JNZ  it_no
        LDA  CUR2
        CMP
        JNZ  it_no
        SEC
        RTS
it_no:  CLC
        RTS

; land ( '||' land )*   short-circuit, 0/1
GLOR:   JSR  GLAND
ge_orl: LDA  #'|'
        JSR  ISTWO
        JNC  ge_ord
        JSR  NEWLBL
        MOVW LORT,NEWL
        JSR  NEWLBL
        MOVW LORE,NEWL
        JSR  EM_TESTAX
        MOVW JLBL,LORT
        LDP1 #MJNZ
        JSR  EMITJ               ; JNZ Ltrue
        JSR  ADVANCE
        PHW  LORT
        PHW  LORE
        JSR  GLAND
        PLW  LORE
        PLW  LORT
        JSR  EM_TESTAX
        MOVW JLBL,LORT
        LDP1 #MJNZ
        JSR  EMITJ               ; JNZ Ltrue
        JSR  EM_AX0
        MOVW JLBL,LORE
        LDP1 #MJMP
        JSR  EMITJ               ; JMP Lend
        MOVW JLBL,LORT
        JSR  EMITLBL             ; Ltrue:
        JSR  EM_AX1
        MOVW JLBL,LORE
        JSR  EMITLBL             ; Lend:
        JMP  ge_orl
ge_ord: RTS

; bor ( '&&' bor )*   -- the right operand is a VALUE (tested below), so a
;   trailing relational must not take the condition-mode branch: with it,
;   `if (a && b == c)` fell into the body when a was false
GLAND:  JSR  GBOR
ga_andl:LDA  #'&'
        JSR  ISTWO
        JNC  ga_andd
        LDA  #0
        STA  CONDCUR
        JSR  NEWLBL
        MOVW LANDF,NEWL
        JSR  NEWLBL
        MOVW LANDE,NEWL
        JSR  EM_TESTAX
        MOVW JLBL,LANDF
        LDP1 #MJZ
        JSR  EMITJ               ; JZ Lfalse
        JSR  ADVANCE
        PHW  LANDF
        PHW  LANDE
        JSR  GBOR
        PLW  LANDE
        PLW  LANDF
        JSR  EM_TESTAX
        MOVW JLBL,LANDF
        LDP1 #MJZ
        JSR  EMITJ               ; JZ Lfalse
        JSR  EM_AX1
        MOVW JLBL,LANDE
        LDP1 #MJMP
        JSR  EMITJ               ; JMP Lend
        MOVW JLBL,LANDF
        JSR  EMITLBL             ; Lfalse:
        JSR  EM_AX0
        MOVW JLBL,LANDE
        JSR  EMITLBL             ; Lend:
        JMP  ga_andl
ga_andd:RTS

; BINOP - the right operand by the routine at CUR, then the word op at P1:
;   push left, right -> __ax, pop left -> __t0, emit. (P1 is kept in TERM.)
; bxor ( '|' bxor )*
GBOR:   JSR  GBXOR
gbo_l:  LDA  #'|'
        JSR  ISPUNCT
        JNC  gbo_d
        JSR  ADVANCE
        JSR  EM_PUSH
        JSR  GBXOR
        JSR  EM_POP
        LDP1 #MJOR
        JSR  EMIT
        JMP  gbo_l
gbo_d:  RTS
; band ( '^' band )*
GBXOR:  JSR  GBAND
gbx_l:  LDA  #'^'
        JSR  ISPUNCT
        JNC  gbx_d
        JSR  ADVANCE
        JSR  EM_PUSH
        JSR  GBAND
        JSR  EM_POP
        LDP1 #MJXOR
        JSR  EMIT
        JMP  gbx_l
gbx_d:  RTS
; rel ( '&' rel )*
GBAND:  JSR  GREL
gba_l:  LDA  #'&'
        JSR  ISPUNCT
        JNC  gba_d
        JSR  ADVANCE
        JSR  EM_PUSH
        JSR  GREL
        JSR  EM_POP
        LDP1 #MJAND
        JSR  EMIT
        JMP  gba_l
gba_d:  RTS

; rel: sh [relop sh] -> 0/1, or in condition mode one branch to CONDLBL
GREL:   JSR  GSHIFT
        LDA  CURK
        LDB  #3
        CMP
        JNZ  grx
        JSR  RELDET
        LDA  RELF
        JZ   grx
        JSR  EM_PUSH             ; the left operand
        LDA  RELOP
        PHA
        JSR  ADVANCE
        JSR  GSHIFT              ; the right -> __ax
        PLA
        STA  RELOP
        JSR  EM_POP              ; left -> __t0
        LDA  RELOP
        LDB  #R_EQ
        CMP
        JC   grl_eq              ; == != : JSR __cmp (a 16-bit Z)
        LDB  #R_LE
        CMP
        JZ   grl_sw
        LDB  #R_GT
        CMP
        JZ   grl_sw
        LDP1 #MCMPWTA            ; < >= : CMPW __t0,__ax  (C = left >= right)
        JMP  grl_em
grl_sw: LDP1 #MCMPWAT            ; <= > : CMPW __ax,__t0  (C = right >= left)
        JMP  grl_em
grl_eq: LDP1 #MCMP
grl_em: JSR  EMIT
        LDA  CONDCUR             ; a condition, and this relational ends it?
        JZ   grl_val
        LDA  #')'
        JSR  ISPUNCT
        JC   grl_cond
        LDA  #$3B
        JSR  ISPUNCT
        JNC  grl_val
grl_cond:
        JSR  EMITCF              ; one branch to CONDLBL when FALSE
        LDA  #1
        STA  CONDDONE
        RTS
grl_val:JMP  EMITCMP             ; the 0/1 value
grx:    RTS

; EMITCF - after GREL's compare, jump to CONDLBL when the relation is FALSE:
;   <  C=1 (left>=right) -> JC      >= false when C=0 -> JNC
;   >  (swapped) true when C=0 -> JC     <= true when C=1 -> JNC
;   == false when Z=0 -> JNZ       != -> JZ
EMITCF: MOVW JLBL,CONDLBL
        LDA  RELOP
        JZ   ecf_jc
        LDB  #R_GT
        CMP
        JZ   ecf_jc
        LDB  #R_EQ
        CMP
        JZ   ecf_jnz
        LDB  #R_NE
        CMP
        JZ   ecf_jz
        LDP1 #MJNC
        JMP  EMITJ
ecf_jc: LDP1 #MJC
        JMP  EMITJ
ecf_jnz:LDP1 #MJNZ
        JMP  EMITJ
ecf_jz: LDP1 #MJZ
        JMP  EMITJ

; EMITCMP - the 0/1 value of the relation: one conditional jump to la (true),
;   the false path 0, la: 1, lb:
EMITCMP:JSR  NEWLBL
        MOVW LBLA,NEWL
        JSR  NEWLBL
        MOVW LBLB,NEWL
        MOVW JLBL,LBLA
        LDA  RELOP
        JZ   ec_jnc              ; <  : C=0
        LDB  #R_GE
        CMP
        JZ   ec_jc               ; >= : C=1
        LDB  #R_GT
        CMP
        JZ   ec_jnc              ; >  : (swapped) C=0
        LDB  #R_LE
        CMP
        JZ   ec_jc               ; <= : C=1
        LDB  #R_EQ
        CMP
        JZ   ec_jz
        LDP1 #MJNZ               ; !=
        JMP  ec_e
ec_jz:  LDP1 #MJZ
        JMP  ec_e
ec_jnc: LDP1 #MJNC
        JMP  ec_e
ec_jc:  LDP1 #MJC
ec_e:   JSR  EMITJ               ; (JLBL = la)
        JSR  EM_AX0
        MOVW JLBL,LBLB
        LDP1 #MJMP
        JSR  EMITJ
        MOVW JLBL,LBLA
        JSR  EMITLBL
        JSR  EM_AX1
        MOVW JLBL,LBLB
        JMP  EMITLBL

; RELDET - is the current punct a relational? RELF, RELOP
RELDET: LDA  #0
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
rd_l:   LDA  CUR2
        JNZ  rd_l2
        LDA  #R_LT
        JMP  rd_ok
rd_l2:  LDB  #'='
        CMP
        JNZ  rd_no               ; '<<' is a shift
        LDA  #R_LE
        JMP  rd_ok
rd_g:   LDA  CUR2
        JNZ  rd_g2
        LDA  #R_GT
        JMP  rd_ok
rd_g2:  LDB  #'='
        CMP
        JNZ  rd_no
        LDA  #R_GE
        JMP  rd_ok
rd_e:   LDA  CUR2
        LDB  #'='
        CMP
        JNZ  rd_no
        LDA  #R_EQ
        JMP  rd_ok
rd_x:   LDA  CUR2
        LDB  #'='
        CMP
        JNZ  rd_no
        LDA  #R_NE
rd_ok:  STA  RELOP
        LDA  #1
        STA  RELF
rd_no:  RTS

; sh: add ( ('<<'|'>>') add )*
GSHIFT: JSR  GADD
gsh_l:  LDA  #'<'
        JSR  ISTWO
        JC   gsh_ml
        LDA  #'>'
        JSR  ISTWO
        JNC  gsh_d
        LDA  #1
        STA  USESHR
        LDW  TERM,#MJSHR
        JMP  gsh_go
gsh_ml: LDA  #1
        STA  USESHL
        LDW  TERM,#MJSHL
gsh_go: JSR  ADVANCE
        JSR  EM_PUSH
        PHW  TERM                ; (the operand may nest another operator)
        JSR  GADD
        PLW  TERM
        JSR  EM_POP
        LPW1 TERM
        JSR  EMIT
        JMP  gsh_l
gsh_d:  RTS

; add: term ( ('+'|'-') term )*
GADD:   JSR  GTERM
ge_l:   LDA  #'+'
        JSR  ISPUNCT
        JC   ge_add
        LDA  #'-'
        JSR  ISPUNCT
        JNC  ge_d
        LDW  TERM,#MSUB
        JMP  ge_go
ge_add: LDW  TERM,#MADD
ge_go:  JSR  ADVANCE
        JSR  EM_PUSH
        PHW  TERM
        JSR  GTERM
        PLW  TERM
        JSR  EM_POP
        LPW1 TERM
        JSR  EMIT
        JMP  ge_l
ge_d:   RTS

; term: unary ( ('*'|'/'|'%') unary )*
GTERM:  JSR  GUNARY
gt_l:   LDA  #'*'
        JSR  ISPUNCT
        JC   gt_mul
        LDA  #'/'
        JSR  ISPUNCT
        JC   gt_div
        LDA  #'%'
        JSR  ISPUNCT
        JNC  gt_d
        LDW  TERM,#MMOD
        JMP  gt_dv
gt_div: LDW  TERM,#MDIV
gt_dv:  LDA  #1
        STA  USEDIV
        JMP  gt_go
gt_mul: LDA  #1
        STA  USEMUL
        LDW  TERM,#MMUL
gt_go:  JSR  ADVANCE
        JSR  EM_PUSH
        PHW  TERM
        JSR  GUNARY
        PLW  TERM
        JSR  EM_POP
        LPW1 TERM
        JSR  EMIT
        JMP  gt_l
gt_d:   RTS

; unary: ('-' | '!' | '&' | '*' | '++' | '--') unary | factor
GUNARY: LDA  CURK
        LDB  #3
        CMP
        JNZ  GFACT
        LDA  CUR2
        JNZ  gu_two
        LDA  CURV
        LDB  #'-'
        CMP
        JZ   gu_neg
        LDB  #'!'
        CMP
        JZ   gu_not
        LDB  #'&'
        CMP
        JZ   gu_addr
        LDB  #'*'
        CMP
        JZ   gu_deref
        JMP  GFACT
gu_two: LDA  #'+'                ; prefix ++ / --
        JSR  ISTWO
        JC   gu_pinc
        LDA  #'-'
        JSR  ISTWO
        JC   gu_pdec
        JMP  GFACT
gu_pinc:JSR  ADVANCE
        JSR  SYMFIND
        LDA  SYMOK
        JZ   GFACT
        JSR  EM_INCVAR
        JSR  EM_LDVAR
        JMP  ADVANCE
gu_pdec:JSR  ADVANCE
        JSR  SYMFIND
        LDA  SYMOK
        JZ   GFACT
        JSR  EM_DECVAR
        JSR  EM_LDVAR
        JMP  ADVANCE
gu_addr:LDA  #1
        STA  SAWADDRG            ; an argument took an address (pass by reference)
        JSR  ADVANCE
        JSR  SYMFIND
        LDA  SYMOK
        JZ   gu_ret
        MOVW IDVARIDX,SYMIDX
        LDA  SYMRCH
        STA  IDVARCH
        LDA  SYMRAR
        STA  IDVARAR
        JSR  ADVANCE             ; past NAME
        LDA  #'['
        JSR  ISPUNCT
        JC   gu_ad_ix
        MOVW SYMIDX,IDVARIDX
        JMP  EM_ADDROF
gu_ad_ix:
        MOVW SYMIDX,IDVARIDX
        LDA  IDVARCH
        STA  ELCHAR
        LDA  IDVARAR
        STA  ELARR
        JMP  ELEMADDR
gu_ret: RTS
gu_deref:
        JSR  ADVANCE
        JSR  GUNARY              ; the address -> __ax
        LDA  EXPRCHAR
        JNZ  EM_LOADB            ; char*: a byte
        JMP  EM_LOADW
gu_neg: JSR  ADVANCE
        JSR  GUNARY
        LDP1 #MNEG
        JMP  EMIT
gu_not: JSR  ADVANCE
        JSR  GUNARY
        LDA  #1
        STA  USENOT
        LDP1 #MLNOT
        JMP  EMIT

; factor: NUMBER | "string" | ( expr ) | NAME ...
GFACT:  LDA  CURK
        LDB  #1
        CMP
        JZ   gf_num
        LDB  #2
        CMP
        JZ   gf_id
        LDB  #4
        CMP
        JZ   gf_str
        LDA  #'('
        JSR  ISPUNCT
        JNC  gf_err
        JSR  ADVANCE
        JSR  GEXPR
        LDA  #')'
        JMP  EXPECTP
gf_err: RTS                      ; (an empty expression: nothing emitted)
gf_num: LDP1 #MLDWAXI            ; LDW __ax,#n
        JSR  EMIT
        MOVW VN,CURV
        JSR  EMITNUM16
        JSR  EMITNL
        LDA  #0
        STA  EXPRCHAR
        JMP  ADVANCE
; a string literal: its bytes inline (jumped over), __ax = its address
gf_str: LDA  #1
        STA  EXPRCHAR
        JSR  NEWLBL
        MOVW STRDL,NEWL
        JSR  NEWLBL
        MOVW STRSL,NEWL
        MOVW JLBL,STRSL
        LDP1 #MJMP
        JSR  EMITJ               ; JMP Lskip
        MOVW JLBL,STRDL
        JSR  EMITLBL             ; Ldata:
        LDP1 #MDQASC             ; .asciiz "
        JSR  EMIT
        LDP1 #STRBUF
        JSR  EMIT
        LDP1 #MDQCL              ; " LF
        JSR  EMIT
        LDP1 #MBYTE0             ; .byte 0 (a word load at the NUL reads 0)
        JSR  EMIT
        MOVW JLBL,STRSL
        JSR  EMITLBL             ; Lskip:
        LDP1 #MLDALL             ; LDA #<Ldata / STA __ax / LDA #>Ldata / STA __ax+1
        JSR  EMIT
        MOVW VN,STRDL
        JSR  EMITNUM16
        JSR  EMITNL
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDAHL
        JSR  EMIT
        MOVW VN,STRDL
        JSR  EMITNUM16
        JSR  EMITNL
        LDP1 #MSTAXH
        JSR  EMIT
        JMP  ADVANCE
; an identifier: a builtin, a call, a variable, an element, a member, a postfix
gf_id:  LDA  CURKW
        LDB  #K_BIOS
        CMP
        JC   gf_builtin
        JSR  CPIDNAME
        JSR  SYMFIND
        LDA  SYMOK
        STA  IDVAROK
        MOVW IDVARIDX,SYMIDX
        LDA  SYMRCH
        STA  IDVARCH
        LDA  SYMRAR
        STA  IDVARAR
        JSR  ADVANCE             ; past the id
        LDA  CURK
        LDB  #3
        CMP
        JNZ  gfi_var
        LDA  CUR2
        JNZ  gfi_two
        LDA  CURV
        LDB  #'('
        CMP
        JZ   gfi_call
        LDB  #'['
        CMP
        JZ   gfi_index
        LDB  #'.'
        CMP
        JZ   gfi_dot
gfi_var:LDA  IDVAROK
        JZ   gf_err
        MOVW SYMIDX,IDVARIDX
        LDA  IDVARCH
        STA  EXPRCHAR
        LDA  IDVARAR
        JZ   EM_LDVAR            ; the value
        LDA  #1                  ; a bare array name decays to its address
        STA  SAWADDRG
        JMP  EM_ADDROF
gfi_two:LDA  CURV
        LDB  #'-'
        CMP
        JNZ  gfi_pl
        LDA  CUR2
        LDB  #'>'
        CMP
        JZ   gfi_arrow
        LDB  #'-'
        CMP
        JNZ  gfi_var
        LDA  IDVAROK             ; NAME-- : the old value, then DECW
        JZ   gf_err
        MOVW SYMIDX,IDVARIDX
        JSR  EM_LDVAR
        JSR  EM_DECVAR
        JMP  ADVANCE
gfi_pl: LDB  #'+'
        CMP
        JNZ  gfi_var
        LDA  CUR2
        LDB  #'+'
        CMP
        JNZ  gfi_var
        LDA  IDVAROK             ; NAME++
        JZ   gf_err
        MOVW SYMIDX,IDVARIDX
        JSR  EM_LDVAR
        JSR  EM_INCVAR
        JMP  ADVANCE
gfi_dot:MOVW SYMIDX,IDVARIDX
        JSR  EM_ADDROF
        JMP  gfi_memld
gfi_arrow:
        MOVW SYMIDX,IDVARIDX
        JSR  EM_LDVAR
gfi_memld:
        JSR  ADVANCE             ; past . / ->
        JSR  STMFIND
        LDA  STMEMOFF
        JSR  EM_ADDOFF
        JSR  ADVANCE             ; past the member
        LDA  STMEMCH
        JNZ  EM_LOADB
        JMP  EM_LOADW
gfi_index:
        MOVW SYMIDX,IDVARIDX
        LDA  IDVARCH
        STA  ELCHAR
        LDA  IDVARAR
        STA  ELARR
        JSR  ELEMADDR
        LDA  ELCHAR
        JNZ  EM_LOADB
        JMP  EM_LOADW

; the builtins: bios / puts / getchar / peek / poke / argstr
gf_builtin:
        LDB  #K_PUTS
        CMP
        JZ   gc_puts
        LDB  #K_GETC
        CMP
        JZ   gc_getc
        LDB  #K_PEEK
        CMP
        JZ   gc_peek
        LDB  #K_POKE
        CMP
        JZ   gc_poke
        LDB  #K_ARGSTR
        CMP
        JZ   gc_argstr
        LDB  #K_BIOS
        CMP
        JNZ  SYNTAXERR
; bios(ADDR, p1, a) -> A | carry<<8 in __ax; ADDR is a constant
gc_bios:JSR  ADVANCE             ; past 'bios'
        LDA  #'('
        JSR  EXPECTP
        MOVW BIOSAD,CURV
        JSR  ADVANCE             ; past the address
        LDA  #','
        JSR  EXPECTP
        JSR  GEXPR               ; the P1 operand
        JSR  EM_PUSH
        LDA  #','
        JSR  EXPECTP
        JSR  GEXPR               ; the A operand
        LDA  #')'
        JSR  EXPECTP
        JSR  EM_POP
        LDP1 #MLPWT0
        JSR  EMIT
        LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MJSRHEX            ; JSR $hhhh
        JSR  EMIT
        LDA  BIOSAD+1
        JSR  EMHEX
        LDA  BIOSAD
        JSR  EMHEX
        JSR  EMITNL
        LDP1 #MSTAX              ; A -> __ax, the carry -> __ax+1
        JSR  EMIT
        JSR  NEWLBL
        MOVW JLBL,NEWL
        LDP1 #MLDA0
        JSR  EMIT
        LDP1 #MJNC
        JSR  EMITJ
        LDP1 #MLDA1
        JSR  EMIT
        JSR  EMITLBL             ; (JLBL kept by EMITJ)
        LDP1 #MSTAXH
        JMP  EMIT
; puts(s)
gc_puts:JSR  ADVANCE
        LDA  #'('
        JSR  EXPECTP
        JSR  GEXPR
        LDA  #')'
        JSR  EXPECTP
        LDP1 #MLPWAX
        JSR  EMIT
        LDP1 #MPUTS
        JMP  EMIT
; getchar() -> __ax, or 0xFFFF at EOF
gc_getc:JSR  ADVANCE
        LDA  #'('
        JSR  EXPECTP
        LDA  #')'
        JSR  EXPECTP
        LDP1 #MGETC
        JSR  EMIT
        JSR  NEWLBL
        MOVW JLBL,NEWL
        LDP1 #MJNC
        JSR  EMITJ
        LDP1 #MGETCEOF
        JSR  EMIT
        JMP  EMITLBL
; peek(addr)
gc_peek:JSR  ADVANCE
        LDA  #'('
        JSR  EXPECTP
        JSR  GEXPR
        LDA  #')'
        JSR  EXPECTP
        JMP  EM_LOADB
; poke(addr, val)
gc_poke:JSR  ADVANCE
        LDA  #'('
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EM_PUSH
        LDA  #','
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EM_POP
        JSR  EM_STOREB
        LDA  #')'
        JMP  EXPECTP
; argstr() -> the argument tail (P2)
gc_argstr:
        JSR  ADVANCE
        LDA  #'('
        JSR  EXPECTP
        LDA  #')'
        JSR  EXPECTP
        LDP1 #MARGSTR
        JMP  EMIT

; a call: NAME ( args )  -- IDNAME is the callee; the current token is '('
gfi_call:
        LDW  NTNAME,#IDNAME
        LDA  IDNAMEL
        STA  NTNLEN
        LDW  NTH,#HFUNC
        LDW  FENT,#0
        JSR  NTFIND
        JNC  gc_nf
        LEAW FENT,(P1+0)
gc_nf:  PHW  FENT                ; kept across the arguments (calls nest)
        LDA  #0
        STA  SAWADDRG
        JSR  ADVANCE             ; past '('
        JSR  EM_SAVESLOTS        ; the caller's live slots FIRST, then the args
        LDA  #0
        STA  ARGI
        LDA  #')'
        JSR  ISPUNCT
        JC   ga_done
ga_loop:LDA  ARGI
        PHA
        JSR  GEXPR
        PLA
        STA  ARGI
        LDP1 #MPHW               ; PHW __ax
        JSR  EMIT
        LDA  ARGI
        INC
        STA  ARGI
        LDA  #','
        JSR  ISPUNCT
        JNC  ga_done
        JSR  ADVANCE
        JMP  ga_loop
ga_done:LDA  #')'
        JSR  EXPECTP
        LDP1 #MJSRF              ; JSR _f_NAME
        JSR  EMIT
        PLW  FENT
        JSR  EMITFNAME
        JSR  EMITNL
        LDA  ARGI                ; drop the arguments: ADDP3 #2n
        JZ   gc_noargs
        SHL
        JSR  EM_ADDP3
gc_noargs:
        LDA  SAWADDRG            ; an address was passed: the callee wrote the
        JZ   EM_RESTSLOTS        ;   real slot -- discard the copies instead
        LDA  NLSLOT
        JZ   gc_norest
        SHL
        JMP  EM_ADDP3
gc_norest:
        RTS

; EM_SAVESLOTS / EM_RESTSLOTS - PHW / PLW the current function's slots
EM_SAVESLOTS:
        LDA  #0
        STA  VITER2
ess_l:  LDA  VITER2
        LDB  NLSLOT
        CMP
        JC   ess_d
        LDP1 #MPHWV
        JSR  EMIT
        LDA  VITER2
        JSR  EMSB
        JSR  EMITNL
        LDA  VITER2
        INC
        STA  VITER2
        JMP  ess_l
ess_d:  RTS
EM_RESTSLOTS:
        LDA  NLSLOT
        STA  VITER2
ers_l:  LDA  VITER2
        JZ   ers_d
        DEC
        STA  VITER2
        LDP1 #MPLWV
        JSR  EMIT
        LDA  VITER2
        JSR  EMSB
        JSR  EMITNL
        JMP  ers_l
ers_d:  RTS

; ELEMADDR - SYMIDX = an array / pointer; the current token '['. Emits the
;   element ADDRESS into __ax; consumes [ index ].
ELEMADDR:
        LDA  ELARR
        JZ   ela_ptr
        JSR  EM_ADDROF           ; an array: its base address
        JMP  ela_base
ela_ptr:JSR  EM_LDVAR            ; a pointer: its value
ela_base:
        JSR  EM_PUSH
        JSR  ADVANCE             ; past '['
        JSR  GEXPR               ; the index -> __ax
        LDA  #']'
        JSR  EXPECTP
        LDA  ELCHAR
        JNZ  ela_nos
        JSR  EM_SCALE2           ; int elements: index * 2
ela_nos:JSR  EM_POP
        LDP1 #MADD
        JMP  EMIT

; NEWLBL - NEWL = a fresh label number (16-bit)
NEWLBL: MOVW NEWL,LBLCNT
        INCW LBLCNT
        RTS
; EMITJ - the jump at P1 ("...L") to the label JLBL, newline (JLBL is kept)
EMITJ:  JSR  EMIT
        MOVW VN,JLBL
        JSR  EMITNUM16
        JMP  EMITNL
; EMITLBL - "L<JLBL>:" newline
EMITLBL:LDA  #'L'
        JSR  SYS_PUTC
        MOVW VN,JLBL
        JSR  EMITNUM16
        LDP1 #MLBC
        JMP  EMIT

; =============================================================================
; Emit helpers: the code shapes
; =============================================================================
EM_LDVAR:                        ; __ax = V<SYMIDX>
        LDP1 #MMVAXV
        JSR  EMIT
        JSR  EMSY
        JMP  EMITNL
EM_STVAR:                        ; V<LHSIDX> = __ax
        LDP1 #MMVV
        JSR  EMIT
        JSR  EMLH
        LDP1 #MCAX
        JMP  EMIT
EM_ADDROF:                       ; __ax = &V<SYMIDX>
        LDP1 #MLDALV
        JSR  EMIT
        JSR  EMSY
        JSR  EMITNL
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDAHV
        JSR  EMIT
        JSR  EMSY
        JSR  EMITNL
        LDP1 #MSTAXH
        JMP  EMIT
EM_INCVAR:                       ; INCW V<SYMIDX>
        LDP1 #MINCWV
        JSR  EMIT
        JSR  EMSY
        JMP  EMITNL
EM_DECVAR:
        LDP1 #MDECWV
        JSR  EMIT
        JSR  EMSY
        JMP  EMITNL
EM_PUSH:LDP1 #MPHW               ; PHW __ax
        JMP  EMIT
EM_POP: LDP1 #MPLW               ; PLW __t0
        JMP  EMIT
EM_AX0: LDP1 #MLDW0
        JMP  EMIT
EM_AX1: LDP1 #MLDW1
        JMP  EMIT
EM_TESTAX:
        LDP1 #MCMPAX0
        JMP  EMIT
EM_ADDP3:                        ; ADDP3 #A
        STA  MEMTMP
        LDP1 #MADDP3
        JSR  EMIT
        LDA  MEMTMP
        JSR  EMITNUM
        JMP  EMITNL
EM_LOADB:                        ; __ax = (byte) *__ax
        LDP1 #MLPWAX
        JSR  EMIT
        LDP1 #MLDP1
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDA0
        JSR  EMIT
        LDP1 #MSTAXH
        JMP  EMIT
EM_STOREB:                       ; *(__t0) = (byte) __ax
        LDP1 #MLPWT0
        JSR  EMIT
        LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MSTP1
        JMP  EMIT
EM_LOADW:                        ; __ax = *(__ax)
        LDP1 #MLPWAX
        JSR  EMIT
        LDP1 #MLDP1
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MINP1
        JSR  EMIT
        LDP1 #MLDP1
        JSR  EMIT
        LDP1 #MSTAXH
        JMP  EMIT
EM_STOREW:                       ; *(__t0) = __ax
        LDP1 #MLPWT0
        JSR  EMIT
        LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MSTP1
        JSR  EMIT
        LDP1 #MINP1
        JSR  EMIT
        LDP1 #MLDAXH
        JSR  EMIT
        LDP1 #MSTP1
        JMP  EMIT
EM_SCALE2:                       ; __ax <<= 1
        LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MSHL
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDAXH
        JSR  EMIT
        LDP1 #MROL
        JSR  EMIT
        LDP1 #MSTAXH
        JMP  EMIT

; =============================================================================
; Emitted text. A whole-line template ends with LF; a prefix ends at the point
; a number is appended. Every instruction line starts with one TAB.
; =============================================================================
MORG:   .byte TAB
        .ascii ".org $6100"
        .byte LF,0
MBOOT:  .byte TAB                ; the startup, as p8cc's: keep the caller's P3
        .ascii "TPA3L"           ;   in __sp0 and run on a stack below CSTACKTOP
        .byte LF,TAB             ;   unless the inherited P3 is already below it
        .ascii "STA __sp0"
        .byte LF,TAB
        .ascii "TPA3H"
        .byte LF,TAB
        .ascii "STA __sp0+1"
        .byte LF,TAB
        .ascii "LDB #248"
        .byte LF,TAB
        .ascii "CMP"
        .byte LF,TAB
        .ascii "JNC __sk0"
        .byte LF,TAB
        .ascii "LDP3 #63487"
        .byte LF
        .ascii "__sk0:"
        .byte TAB
        .ascii "JSR _f_main"
        .byte LF,TAB
        .ascii "LPW3 __sp0"
        .byte LF,TAB
        .ascii "RTS"
        .byte LF,0
MFPFX:  .asciiz "_f_"
MEPFX:  .asciiz "_e_"
MCOLON: .ascii ":"
        .byte LF,0
MJSRF:  .byte TAB
        .asciiz "JSR _f_"
MJMPE:  .byte TAB
        .asciiz "JMP _e_"
MVBASE: .asciiz "__V:   .fill "
MSTAX:  .byte TAB
        .ascii "STA __ax"
        .byte LF,0
MSTAXH: .byte TAB
        .ascii "STA __ax+1"
        .byte LF,0
MLDAX:  .byte TAB
        .ascii "LDA __ax"
        .byte LF,0
MLDAXH: .byte TAB
        .ascii "LDA __ax+1"
        .byte LF,0
MPHW:   .byte TAB
        .ascii "PHW __ax"
        .byte LF,0
MPLW:   .byte TAB
        .ascii "PLW __t0"
        .byte LF,0
MLPWAX: .byte TAB
        .ascii "LPW1 __ax"
        .byte LF,0
MLPWT0: .byte TAB
        .ascii "LPW1 __t0"
        .byte LF,0
MJSHL:  .byte TAB
        .ascii "JSR __shl"
        .byte LF,0
MJSHR:  .byte TAB
        .ascii "JSR __shr"
        .byte LF,0
MJAND:  .byte TAB
        .ascii "ANDW __ax,__t0"
        .byte LF,0
MJOR:   .byte TAB
        .ascii "ORW __ax,__t0"
        .byte LF,0
MJXOR:  .byte TAB
        .ascii "XORW __ax,__t0"
        .byte LF,0
MADD:   .byte TAB
        .ascii "ADDW __ax,__t0"
        .byte LF,0
MSUB:   .byte TAB                ; __ax = __t0 - __ax
        .ascii "SUBW __t0,__ax"
        .byte LF,TAB
        .ascii "MOVW __ax,__t0"
        .byte LF,0
MLDWAXI:.byte TAB
        .asciiz "LDW __ax,#"
MADDWAXI:
        .byte TAB
        .asciiz "ADDW __ax,#"
MCMPWTA:.byte TAB                ; C = left(__t0) >= right(__ax)
        .ascii "CMPW __t0,__ax"
        .byte LF,0
MCMPWAT:.byte TAB                ; C = right >= left  (for > and <=)
        .ascii "CMPW __ax,__t0"
        .byte LF,0
MINCWV: .byte TAB
        .asciiz "INCW __V+"
MDECWV: .byte TAB
        .asciiz "DECW __V+"
MLDWV:  .byte TAB
        .asciiz "LDW __V+"
MCP3:   .asciiz ",(P3+"
MCLNL:  .ascii ")"
        .byte LF,0
MADDP3: .byte TAB
        .asciiz "ADDP3 #"
MCMPAX0:.byte TAB
        .ascii "CMPW __ax,#0"
        .byte LF,0
MLDW0:  .byte TAB
        .ascii "LDW __ax,#0"
        .byte LF,0
MLDW1:  .byte TAB
        .ascii "LDW __ax,#1"
        .byte LF,0
MPUTC:  .byte TAB
        .ascii "LDA __ax"
        .byte LF,TAB
        .ascii "JSR $2009"
        .byte LF,0
MRTS:   .byte TAB
        .ascii "RTS"
        .byte LF,0
MCMP:   .byte TAB
        .ascii "JSR __cmp"
        .byte LF,0
MMUL:   .byte TAB
        .ascii "JSR __mul"
        .byte LF,0
MDIV:   .byte TAB
        .ascii "JSR __div"
        .byte LF,0
MMOD:   .byte TAB
        .ascii "JSR __mod"
        .byte LF,0
MLDA0:  .byte TAB
        .ascii "LDA #0"
        .byte LF,0
MLDA1:  .byte TAB
        .ascii "LDA #1"
        .byte LF,0
MJC:    .byte TAB
        .asciiz "JC L"
MJNC:   .byte TAB
        .asciiz "JNC L"
MJZ:    .byte TAB
        .asciiz "JZ L"
MJNZ:   .byte TAB
        .asciiz "JNZ L"
MJMP:   .byte TAB
        .asciiz "JMP L"
MLBC:   .ascii ":"
        .byte LF,0
MDQASC: .byte TAB
        .byte $2E,$61,$73,$63,$69,$69,$7A,$20,$22   ; .asciiz "
        .byte 0
MDQCL:  .byte $22,LF,0
MBYTE0: .byte TAB
        .ascii ".byte 0"
        .byte LF,0
MLDALL: .byte TAB
        .asciiz "LDA #<L"
MLDAHL: .byte TAB
        .asciiz "LDA #>L"
MSHL:   .byte TAB
        .ascii "SHL"
        .byte LF,0
MROL:   .byte TAB
        .ascii "ROL"
        .byte LF,0
MNEG:   .byte TAB                ; -__ax = ~__ax + 1
        .ascii "XORW __ax,#65535"
        .byte LF,TAB
        .ascii "INCW __ax"
        .byte LF,0
MLNOT:  .byte TAB
        .ascii "JSR __lnot"
        .byte LF,0
MINP1:  .byte TAB
        .ascii "INP1"
        .byte LF,0
MLDP1:  .byte TAB
        .ascii "LDA (P1)"
        .byte LF,0
MSTP1:  .byte TAB
        .ascii "STA (P1)"
        .byte LF,0
MLDALV: .byte TAB
        .asciiz "LDA #<__V+"
MLDAHV: .byte TAB
        .asciiz "LDA #>__V+"
MMVAXV: .byte TAB
        .asciiz "MOVW __ax,__V+"
MMVV:   .byte TAB
        .asciiz "MOVW __V+"
MCAX:   .ascii ",__ax"
        .byte LF,0
MPHWV:  .byte TAB
        .asciiz "PHW __V+"
MPLWV:  .byte TAB
        .asciiz "PLW __V+"
MPUTS:  .byte TAB                ; puts: the string at P1, then a newline
        .ascii "JSR $200F"
        .byte LF,TAB
        .ascii "LDA #10"
        .byte LF,TAB
        .ascii "JSR $2009"
        .byte LF,0
MGETC:  .byte TAB
        .ascii "JSR $200C"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "LDA #0"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,0
MGETCEOF:
        .byte TAB
        .ascii "LDA #255"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,0
MARGSTR:.byte TAB
        .ascii "TPA2L"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "TPA2H"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,0
MJSRHEX:.byte TAB
        .asciiz "JSR $"
MTEMP:  .ascii "__t0:   .fill 2"
        .byte LF
        .ascii "__sp0:  .fill 2"
        .byte LF
        .ascii "__ax:   .fill 2"
        .byte LF
        .ascii "__c:    .fill 1"
        .byte LF
        .ascii "__sc:   .fill 1"
        .byte LF,0
; the runtime helpers, emitted once each when the program needs them
MCMP_DEF:
        .ascii "__cmp:"
        .byte TAB
        .ascii "LDA __t0+1"
        .byte LF,TAB
        .ascii "LDB __ax+1"
        .byte LF,TAB
        .ascii "CMP"
        .byte LF,TAB
        .ascii "JNZ __cm0"
        .byte LF,TAB
        .ascii "LDA __t0"
        .byte LF,TAB
        .ascii "LDB __ax"
        .byte LF,TAB
        .ascii "CMP"
        .byte LF
        .ascii "__cm0:"
        .byte TAB
        .ascii "RTS"
        .byte LF,0
MMULDEF:.ascii "__mul:"          ; __ax = __ax * __t0 (repeated add)
        .byte TAB
        .ascii "LDA #0"
        .byte LF,TAB
        .ascii "STA __mr"
        .byte LF,TAB
        .ascii "STA __mr+1"
        .byte LF
        .ascii "__mu0:"
        .byte TAB
        .ascii "LDA __ax"
        .byte LF,TAB
        .ascii "LDB __ax+1"
        .byte LF,TAB
        .ascii "OR"
        .byte LF,TAB
        .ascii "JZ __mu2"
        .byte LF,TAB
        .ascii "LDA __mr"
        .byte LF,TAB
        .ascii "LDB __t0"
        .byte LF,TAB
        .ascii "ADD"
        .byte LF,TAB
        .ascii "STA __mr"
        .byte LF,TAB
        .ascii "LDA #0"
        .byte LF,TAB
        .ascii "JNC __mu1"
        .byte LF,TAB
        .ascii "LDA #1"
        .byte LF
        .ascii "__mu1:"
        .byte TAB
        .ascii "STA __c"
        .byte LF,TAB
        .ascii "LDA __mr+1"
        .byte LF,TAB
        .ascii "LDB __t0+1"
        .byte LF,TAB
        .ascii "ADD"
        .byte LF,TAB
        .ascii "LDB __c"
        .byte LF,TAB
        .ascii "ADD"
        .byte LF,TAB
        .ascii "STA __mr+1"
        .byte LF,TAB
        .ascii "LDA __ax"
        .byte LF,TAB
        .ascii "LDB #1"
        .byte LF,TAB
        .ascii "SUB"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "JC __mu0"
        .byte LF,TAB
        .ascii "LDA __ax+1"
        .byte LF,TAB
        .ascii "DEC"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,TAB
        .ascii "JMP __mu0"
        .byte LF
        .ascii "__mu2:"
        .byte TAB
        .ascii "LDA __mr"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "LDA __mr+1"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,TAB
        .ascii "RTS"
        .byte LF
        .ascii "__mr:   .fill 2"
        .byte LF,0
MDMDEF: .ascii "__div:"          ; __ax = __t0 / __ax ; __mod: the remainder
        .byte TAB
        .ascii "JSR __divmod"
        .byte LF,TAB
        .ascii "LDA __dq"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "LDA __dq+1"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,TAB
        .ascii "RTS"
        .byte LF
        .ascii "__mod:"
        .byte TAB
        .ascii "JSR __divmod"
        .byte LF,TAB
        .ascii "LDA __dr"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "LDA __dr+1"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,TAB
        .ascii "RTS"
        .byte LF
        .ascii "__divmod:"
        .byte TAB
        .ascii "LDA __t0"
        .byte LF,TAB
        .ascii "STA __dr"
        .byte LF,TAB
        .ascii "LDA __t0+1"
        .byte LF,TAB
        .ascii "STA __dr+1"
        .byte LF,TAB
        .ascii "LDA #0"
        .byte LF,TAB
        .ascii "STA __dq"
        .byte LF,TAB
        .ascii "STA __dq+1"
        .byte LF,TAB
        .ascii "LDA __ax"
        .byte LF,TAB
        .ascii "LDB __ax+1"
        .byte LF,TAB
        .ascii "OR"
        .byte LF,TAB
        .ascii "JZ __dm2"
        .byte LF
        .ascii "__dm0:"
        .byte TAB
        .ascii "LDA __dr+1"
        .byte LF,TAB
        .ascii "LDB __ax+1"
        .byte LF,TAB
        .ascii "CMP"
        .byte LF,TAB
        .ascii "JNZ __dm3"
        .byte LF,TAB
        .ascii "LDA __dr"
        .byte LF,TAB
        .ascii "LDB __ax"
        .byte LF,TAB
        .ascii "CMP"
        .byte LF
        .ascii "__dm3:"
        .byte TAB
        .ascii "JNC __dm2"
        .byte LF,TAB
        .ascii "LDA __dr"
        .byte LF,TAB
        .ascii "LDB __ax"
        .byte LF,TAB
        .ascii "SUB"
        .byte LF,TAB
        .ascii "STA __dr"
        .byte LF,TAB
        .ascii "LDA #0"
        .byte LF,TAB
        .ascii "JC __dm1"
        .byte LF,TAB
        .ascii "LDA #1"
        .byte LF
        .ascii "__dm1:"
        .byte TAB
        .ascii "STA __c"
        .byte LF,TAB
        .ascii "LDA __dr+1"
        .byte LF,TAB
        .ascii "LDB __ax+1"
        .byte LF,TAB
        .ascii "SUB"
        .byte LF,TAB
        .ascii "STA __dr+1"
        .byte LF,TAB
        .ascii "LDA __c"
        .byte LF,TAB
        .ascii "JZ __dm4"
        .byte LF,TAB
        .ascii "LDA __dr+1"
        .byte LF,TAB
        .ascii "DEC"
        .byte LF,TAB
        .ascii "STA __dr+1"
        .byte LF
        .ascii "__dm4:"
        .byte TAB
        .ascii "LDA __dq"
        .byte LF,TAB
        .ascii "LDB #1"
        .byte LF,TAB
        .ascii "ADD"
        .byte LF,TAB
        .ascii "STA __dq"
        .byte LF,TAB
        .ascii "JNC __dm0"
        .byte LF,TAB
        .ascii "LDA __dq+1"
        .byte LF,TAB
        .ascii "INC"
        .byte LF,TAB
        .ascii "STA __dq+1"
        .byte LF,TAB
        .ascii "JMP __dm0"
        .byte LF
        .ascii "__dm2:"
        .byte TAB
        .ascii "RTS"
        .byte LF
        .ascii "__dq:   .fill 2"
        .byte LF
        .ascii "__dr:   .fill 2"
        .byte LF,0
MSHLDEF:.ascii "__shl:"          ; __ax = __t0 << __ax
        .byte TAB
        .ascii "LDA __ax"
        .byte LF,TAB
        .ascii "STA __sc"
        .byte LF
        .ascii "__shl0:"
        .byte TAB
        .ascii "LDA __sc"
        .byte LF,TAB
        .ascii "JZ __shld"
        .byte LF,TAB
        .ascii "LDA __t0"
        .byte LF,TAB
        .ascii "SHL"
        .byte LF,TAB
        .ascii "STA __t0"
        .byte LF,TAB
        .ascii "LDA __t0+1"
        .byte LF,TAB
        .ascii "ROL"
        .byte LF,TAB
        .ascii "STA __t0+1"
        .byte LF,TAB
        .ascii "LDA __sc"
        .byte LF,TAB
        .ascii "DEC"
        .byte LF,TAB
        .ascii "STA __sc"
        .byte LF,TAB
        .ascii "JMP __shl0"
        .byte LF
        .ascii "__shld:"
        .byte TAB
        .ascii "LDA __t0"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "LDA __t0+1"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,TAB
        .ascii "RTS"
        .byte LF,0
MSHRDEF:.ascii "__shr:"          ; __ax = __t0 >> __ax
        .byte TAB
        .ascii "LDA __ax"
        .byte LF,TAB
        .ascii "STA __sc"
        .byte LF
        .ascii "__shr0:"
        .byte TAB
        .ascii "LDA __sc"
        .byte LF,TAB
        .ascii "JZ __shrd"
        .byte LF,TAB
        .ascii "LDA __t0+1"
        .byte LF,TAB
        .ascii "SHR"
        .byte LF,TAB
        .ascii "STA __t0+1"
        .byte LF,TAB
        .ascii "LDA __t0"
        .byte LF,TAB
        .ascii "ROR"
        .byte LF,TAB
        .ascii "STA __t0"
        .byte LF,TAB
        .ascii "LDA __sc"
        .byte LF,TAB
        .ascii "DEC"
        .byte LF,TAB
        .ascii "STA __sc"
        .byte LF,TAB
        .ascii "JMP __shr0"
        .byte LF
        .ascii "__shrd:"
        .byte TAB
        .ascii "LDA __t0"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "LDA __t0+1"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,TAB
        .ascii "RTS"
        .byte LF,0
MLNOT_DEF:
        .ascii "__lnot:"         ; __ax = !__ax
        .byte TAB
        .ascii "LDA __ax"
        .byte LF,TAB
        .ascii "LDB __ax+1"
        .byte LF,TAB
        .ascii "OR"
        .byte LF,TAB
        .ascii "JZ __ln1"
        .byte LF,TAB
        .ascii "LDA #0"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,TAB
        .ascii "RTS"
        .byte LF
        .ascii "__ln1:"
        .byte TAB
        .ascii "LDA #1"
        .byte LF,TAB
        .ascii "STA __ax"
        .byte LF,TAB
        .ascii "LDA #0"
        .byte LF,TAB
        .ascii "STA __ax+1"
        .byte LF,TAB
        .ascii "RTS"
        .byte LF,0
; messages
MUSAGE: .asciiz "usage: cc src.c >out.asm"
MNOSRC: .asciiz "cc: cannot open source"
MTOOFUN:.asciiz "cc: too many functions"
MTOOMAC:.asciiz "cc: too many //#define macros"
MTOOSYM:.asciiz "cc: symbol table full"
MSYNERR:.asciiz "cc: syntax error"
