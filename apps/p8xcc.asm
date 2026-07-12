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
; EARLY (v0.28). Supported so far:  (type = int (16-bit) | char (1-byte elem))
;     program : (func | global | struct-def)*   global : type [*]NAME [[N]] ;
;     struct-def : struct TAG { (type [*]member;)* } ;   access: v.m  p->m
;     func : type NAME([type [*]P,...]) { <stmt>* }
;     stmt : type [*]NAME [= expr]; | type NAME[N]; | NAME = expr; |
;            NAME++; | NAME--; | NAME+=e; | NAME-=e; |
;            NAME[i] = expr; | *expr = expr; | expr; | if(e) s [else s] |
;            while(e) s | for([asg];[e];[asg]) s | break; | continue; |
;            { s* } | putchar(e); | return [e];
;     expr : land ('||' land)*   land : bor ('&&' bor)*   (short-circuit)
;     bor : bxor ('|' bxor)*   bxor : band ('^' band)*   band : rel ('&' rel)*
;     rel  : sh [relop sh]   sh : add (('<<'|'>>') add)*   add : term(...)
;     term : unary (('*'|'/'|'%') unary)*   unary : ('-'|'!'|'*'|'&') unary | factor
;     factor : NUM(dec/0xhex) | 'c' | "str" | NAME | NAME[i] | NAME(args) |
;              builtins: putchar/puts/getchar/peek/poke/argstr/bios | '(' e ')'
;     (a bare array NAME decays to &NAME[0])
; Values are 16-bit int. Codegen uses a MEMORY accumulator __ax (every
; expression's value) + a temp __t0; binary ops route through runtime helpers
; (__add/__sub/__mul/__cmp/__div) emitted at the end of the program. putchar
; takes __ax's low byte. FUNCTIONS: each is _f_NAME (call = JSR, return value in
; __ax); params/locals use STATIC per-function slots (a global slot counter);
; args are passed on a runtime ARG STACK (__sp): the caller pushes them
; (EM_PUSHARG), the callee's prologue pops them into its own static slots
; (EM_POPPARAMS) -- so a callee's storage is never needed at the call site and
; FORWARD calls / MUTUAL RECURSION work (a prototype just registers the name).
; Re-entrancy: before a call a function pushes its own live slots (EM_SAVESLOTS)
; and restores them after -- SKIPPED when an argument took an address (SAWADDRG)
; so pass-by-reference still works. POINTERS: & (EM_ADDROF), * deref (EM_LOADW),
; *p = e (EM_STOREW) via P1. Ver.
; behavioural (compile on-target, run, diff output vs p8cc.py). Grows one tested
; feature at a time (char/pointers, ...) toward the p8cc subset.
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
ROSTATE  = $705E   ; BIOS read-stream state (ROLBA..ROCNT, 13 contiguous bytes)
ROSDRV   = $7085   ; BIOS read-stream drive (1 byte)

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
        LDA  #0                      ; reset the lexer + symbol table + labels
        STA  PBF
        STA  SYMCNT
        STA  LBLCNT
        STA  USEMUL
        STA  USEDIV
        STA  SLOTCNT
        STA  FCNT
        STA  USENEG
        STA  USENOT
        STA  CURBRK
        STA  CURCONT
        STA  GSYMCNT
        STA  USESP
        STA  USEDN
        STA  USEAND
        STA  USEOR
        STA  USEXOR
        STA  USESHL
        STA  USESHR
        STA  STAGCNT
        STA  STMCNT
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

; ---- 16-bit accumulator emit helpers ----
EM_LDIMM: LDP1 #MLDAI                ; __ax = CURV (16-bit literal)
        JSR  EMIT
        LDA  CURV
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDAI
        JSR  EMIT
        LDA  CURV+1
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MSTAXH
        JSR  EMIT
        RTS
EM_LDVAR: LDP1 #MLDAV                ; __ax = V<SYMIDX>
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDAV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        LDP1 #MSTAXH
        JSR  EMIT
        RTS
; GSYMCHAR (A = slot) -> A = 1 if that slot is char-typed
GSYMCHAR: STA TMPC
        LDA  #<SYMCHAR
        LDB  TMPC
        ADD
        TAP1L
        LDA  #>SYMCHAR
        JNC  gsc1
        INC
gsc1:   TAP1H
        LDA  (P1)
        RTS

; SETSYMCHAR: SYMCHAR[SYMIDX] = DCLCHAR
SETSYMCHAR: LDA #<SYMCHAR
        LDB  SYMIDX
        ADD
        TAP1L
        LDA  #>SYMCHAR
        JNC  ssc1
        INC
ssc1:   TAP1H
        LDA  DCLCHAR
        STA  (P1)
        RTS

; EM_LOADB: __ax = (byte)*(__ax)   (byte deref; high byte 0)
EM_LOADB: LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MTAP1L
        JSR  EMIT
        LDP1 #MLDAXH
        JSR  EMIT
        LDP1 #MTAP1H
        JSR  EMIT
        LDP1 #MLDP1
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDA0
        JSR  EMIT
        LDP1 #MSTAXH
        JSR  EMIT
        RTS

; EM_STOREB: *(__t0) = (byte)__ax   (store the low byte)
EM_STOREB: LDP1 #MLDT0
        JSR  EMIT
        LDP1 #MTAP1L
        JSR  EMIT
        LDP1 #MLDT0H
        JSR  EMIT
        LDP1 #MTAP1H
        JSR  EMIT
        LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MSTP1
        JSR  EMIT
        RTS

; EM_SCALE2: __ax <<= 1  (scale an int index to a byte offset)
EM_SCALE2: LDP1 #MLDAX
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
        JSR  EMIT
        RTS

; ELEMADDR: SYMIDX = an array/pointer variable's slot; current token '['.
;   Emits code leaving the element ADDRESS in __ax.  Consumes  [ index ] .
ELEMADDR: LDA ELARR                 ; caller pre-set ELCHAR + ELARR
        JZ   ela_ptr
        JSR  EM_ADDROF               ; array: base = &V<slot>
        JMP  ela_base
ela_ptr: JSR EM_LDVAR                ; pointer: base = its value
ela_base: JSR EM_PUSH                ; push base
        JSR  ADVANCE                 ; past '['
        JSR  GEXPR                   ; index -> __ax
        LDA  #']'
        JSR  EXPECTP
        LDA  ELCHAR                  ; char: scale 1 (no shift); int: scale 2
        JNZ  ela_nos
        JSR  EM_SCALE2
ela_nos: JSR EM_POP                  ; base -> __t0
        LDP1 #MADD                   ; JSR __add -> __ax = index*(1|2) + base
        JSR  EMIT
        RTS

; --- pointer helpers (v0.13) ---
; EM_ADDROF: __ax = &V<SLOTBASE+SYMIDX>   (address-of a scalar variable)
EM_ADDROF: LDP1 #MLDALV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDAHV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MSTAXH
        JSR  EMIT
        RTS

; EM_LOADW: __ax = *(__ax)   (deref: load a word from the address in __ax)
EM_LOADW: LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MTAP1L
        JSR  EMIT
        LDP1 #MLDAXH
        JSR  EMIT
        LDP1 #MTAP1H
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
        JSR  EMIT
        RTS

; EM_STOREW: *(__t0) = __ax   (store the word in __ax to the address in __t0)
EM_STOREW: LDP1 #MLDT0
        JSR  EMIT
        LDP1 #MTAP1L
        JSR  EMIT
        LDP1 #MLDT0H
        JSR  EMIT
        LDP1 #MTAP1H
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
        JSR  EMIT
        RTS

EM_STVAR: LDP1 #MLDAX                ; V<LHSIDX> = __ax
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  LHSIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MLDAXH
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  LHSIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        RTS
EM_PUSH: LDP1 #MLDAX                 ; push __ax (16-bit)
        JSR  EMIT
        LDP1 #MPHA
        JSR  EMIT
        LDP1 #MLDAXH
        JSR  EMIT
        LDP1 #MPHA
        JSR  EMIT
        RTS
EM_POP: LDP1 #MPLA                   ; pop -> __t0 (16-bit)
        JSR  EMIT
        LDP1 #MSTT0H
        JSR  EMIT
        LDP1 #MPLA
        JSR  EMIT
        LDP1 #MSTAT
        JSR  EMIT
        RTS
; EM_INCVAR / EM_DECVAR: V<SLOTBASE+SYMIDX> += / -= 1 (16-bit, in place; __ax kept)
EM_VADDR: LDP1 #MSTAV                 ; helper: emit "STA V<slot>" (slot in A? no) -- unused
        RTS
EM_INCVAR: JSR NEWLBL
        STA  INCLBL
        LDP1 #MLDAV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MLDB1
        JSR  EMIT
        LDP1 #MADDOP
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MJNC
        LDA  INCLBL
        JSR  EMITJ
        LDP1 #MLDAV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        LDP1 #MINCOP
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        LDA  INCLBL
        JSR  EMITLBL
        RTS
EM_DECVAR: JSR NEWLBL
        STA  INCLBL
        LDP1 #MLDAV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MLDB1
        JSR  EMIT
        LDP1 #MSUBOP
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MJC
        LDA  INCLBL
        JSR  EMITJ
        LDP1 #MLDAV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        LDP1 #MDECOP
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  SYMIDX
        LDB  SLOTBASE
        ADD
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        LDA  INCLBL
        JSR  EMITLBL
        RTS

; EM_PUSHARG: emit "JSR __pusharg" (push __ax onto the runtime arg stack)
EM_PUSHARG: LDP1 #MPUSHARG
        JSR  EMIT
        RTS

; EM_POPPARAMS: prologue - pop NPARAMS args (pushed left-to-right by the caller)
;   into this function's param slots V<SLOTBASE+i>, i = NPARAMS-1 .. 0.
EM_POPPARAMS: LDA NPARAMS
        JZ   epp_d
        STA  VITER
epp_l:  LDA  VITER
        DEC
        STA  VITER
        LDP1 #MPOP                    ; JSR __pop  (-> __ax)
        JSR  EMIT
        LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  SLOTBASE
        LDB  VITER
        ADD
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MLDAXH
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  SLOTBASE
        LDB  VITER
        ADD
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        LDA  VITER
        JZ   epp_d
        JMP  epp_l
epp_d:  RTS

EM_AX0: LDP1 #MLDA0                  ; __ax = 0
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MSTAXH
        JSR  EMIT
        RTS
EM_AX1: LDP1 #MLDA1                  ; __ax = 1
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDA0
        JSR  EMIT
        LDP1 #MSTAXH
        JSR  EMIT
        RTS
EM_TESTAX: LDP1 #MLDAX                ; set Z=1 iff __ax==0  (LDA __ax; LDB __ax+1; OR)
        JSR  EMIT
        LDP1 #MLDBXH
        JSR  EMIT
        LDP1 #MOR
        JSR  EMIT
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
        JNC  gc_ok                   ; got a byte
        LDA  USESP                   ; EOF: inside a spliced lib? pop and continue
        JZ   gc_reof
        JSR  USEPOP
        JMP  gc_rd
gc_reof: SEC
        RTS
gc_ok:  CLC
        RTS

; =============================================================================
; //#use NAME  -- recursive source splicer (native counterpart of clib.py).
;   On "//#use NAME" the current read stream is saved, /lib/lib_NAME.c is opened
;   into a fresh buffer, and lexing continues from it; at its EOF (GC) the parent
;   stream is restored. Nesting is a stack (USESTATE + USEBUF per level); each
;   library is spliced at most once (USED dedup).
; =============================================================================
; TRYUSE: we have consumed "//#". Expect "use NAME" -> splice; else skip the line.
TRYUSE: JSR GC
        JC   tu_ret
        LDB  #'u'
        CMP
        JNZ  tu_skipl
        JSR  GC
        JC   tu_ret
        LDB  #'s'
        CMP
        JNZ  tu_skipl
        JSR  GC
        JC   tu_ret
        LDB  #'e'
        CMP
        JNZ  tu_skipl
tu_sp:  JSR  GC                       ; skip spaces before the name
        JC   tu_ret
        STA  TMPB
        LDB  #' '
        CMP
        JZ   tu_sp
        LDA  #<NAMEBUF                ; read the library name into NAMEBUF (via P2)
        TAP2L
        LDA  #>NAMEBUF
        TAP2H
tu_nm:  LDA  TMPB
        JSR  ISALP
        JC   tu_put
        LDA  TMPB
        JSR  ISDIG
        JC   tu_put
        JMP  tu_nend
tu_put: LDA  TMPB
        STA  (P2)
        INP2
        JSR  GC
        JC   tu_nend0
        STA  TMPB
        JMP  tu_nm
tu_nend0: LDA #LF
        STA  TMPB
tu_nend: LDA #0
        STA  (P2)                     ; NUL-terminate the name
        LDA  TMPB                     ; skip to end of line
        LDB  #LF
        CMP
        JZ   tu_do
tu_es:  JSR  GC
        JC   tu_do
        LDB  #LF
        CMP
        JNZ  tu_es
tu_do:  JSR  DOUSE
        RTS
tu_skipl: LDB #LF                     ; not "use": skip the rest of the line
        CMP
        JZ   tu_ret
tu_sl:  JSR  GC
        JC   tu_ret
        LDB  #LF
        CMP
        JNZ  tu_sl
tu_ret: RTS

; DOUSE: dedup NAMEBUF, then save state + open /lib/lib_NAME.c into a new buffer.
DOUSE:  JSR USED_HAS
        LDA  USEDF
        JNZ  du_done                  ; already spliced -> skip
        JSR  USED_ADD
        JSR  BUILDLIBPATH
        JSR  SAVESTATE
        LDA  #<LIBPATH
        TAP1L
        LDA  #>LIBPATH
        TAP1H
        LDA  #0
        JSR  FRESOLVE
        JSR  LIBBUFPTR                ; P1 = USEBUF + USESP*512
        LDA  #0
        JSR  FOPEN
        JC   du_fail
        LDA  USESP                    ; success: descend one level
        INC
        STA  USESP
        RTS
du_fail: JSR RESTORESTATE             ; not found -> restore parent, continue
du_done: RTS

; USED_HAS: USEDF = 1 if NAMEBUF is already in the USED pool.
USED_HAS: LDA #<USED
        TAP1L
        LDA  #>USED
        TAP1H
        LDA  #0
        STA  TMPB
        STA  USEDF
uh_e:   LDA  TMPB
        LDB  USEDN
        CMP
        JC   uh_ret
        LDA  #<NAMEBUF
        TAP2L
        LDA  #>NAMEBUF
        TAP2H
uh_c:   LDA  (P1)
        STA  TMPC
        LDA  (P2)
        LDB  TMPC
        CMP
        JNZ  uh_nx
        LDA  (P1)
        JZ   uh_yes
        INP1
        INP2
        JMP  uh_c
uh_nx:  LDA  (P1)
        JZ   uh_np
        INP1
        JMP  uh_nx
uh_np:  INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  uh_e
uh_yes: LDA #1
        STA  USEDF
uh_ret: RTS

; USED_ADD: append NAMEBUF to the USED pool.
USED_ADD: LDA #<USED
        TAP1L
        LDA  #>USED
        TAP1H
        LDA  #0
        STA  TMPB
ua_e:   LDA  TMPB
        LDB  USEDN
        CMP
        JC   ua_ap
ua_sk:  LDA  (P1)
        JZ   ua_np
        INP1
        JMP  ua_sk
ua_np:  INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  ua_e
ua_ap:  LDA #<NAMEBUF
        TAP2L
        LDA  #>NAMEBUF
        TAP2H
ua_cp:  LDA  (P2)
        STA  (P1)
        JZ   ua_dn
        INP1
        INP2
        JMP  ua_cp
ua_dn:  LDA USEDN
        INC
        STA  USEDN
        RTS

; BUILDLIBPATH: LIBPATH = "/lib/lib_" + NAMEBUF + ".c"
BUILDLIBPATH: LDA #<LIBPATH
        TAP2L
        LDA  #>LIBPATH
        TAP2H
        LDA  #<M_LIBPFX
        TAP1L
        LDA  #>M_LIBPFX
        TAP1H
blp_p:  LDA  (P1)
        JZ   blp_nm
        STA  (P2)
        INP1
        INP2
        JMP  blp_p
blp_nm: LDA  #<NAMEBUF
        TAP1L
        LDA  #>NAMEBUF
        TAP1H
blp_n:  LDA  (P1)
        JZ   blp_x
        STA  (P2)
        INP1
        INP2
        JMP  blp_n
blp_x:  LDA  #<M_DOTC
        TAP1L
        LDA  #>M_DOTC
        TAP1H
blp_e:  LDA  (P1)
        STA  (P2)
        JZ   blp_d
        INP1
        INP2
        JMP  blp_e
blp_d:  RTS

; LIBBUFPTR: P1 = USEBUF + USESP*512
LIBBUFPTR: LDA #<USEBUF
        TAP1L
        LDA  USESP
        SHL
        STA  TMPC
        LDA  #>USEBUF
        LDB  TMPC
        ADD
        TAP1H
        RTS

; USEOFF -> A = USESP*14  (index into USESTATE)
USEOFF: LDA USESP
        SHL             ; x*2
        STA  TMPC       ; TMPC = x*2
        SHL             ; x*4
        LDB  TMPC
        ADD             ; x*6
        STA  TMPC       ; TMPC = x*6
        LDA  USESP
        SHL
        SHL
        SHL             ; x*8
        LDB  TMPC
        ADD             ; x*8 + x*6 = x*14
        RTS

; SAVESTATE: USESTATE[USESP] = the 13-byte read state + ROSDRV
SAVESTATE: JSR USEOFF
        STA  TMPC
        LDA  #<USESTATE
        LDB  TMPC
        ADD
        TAP2L
        LDA  #>USESTATE
        JNC  ss0
        INC
ss0:    TAP2H
        LDA  #<ROSTATE
        TAP1L
        LDA  #>ROSTATE
        TAP1H
        LDA  #13
        STA  USECNT
ss_l:   LDA  (P1)
        STA  (P2)
        INP1
        INP2
        LDA  USECNT
        DEC
        STA  USECNT
        JNZ  ss_l
        LDA  ROSDRV
        STA  (P2)
        RTS

; RESTORESTATE: BIOS read state <- USESTATE[USESP]
RESTORESTATE: JSR USEOFF
        STA  TMPC
        LDA  #<USESTATE
        LDB  TMPC
        ADD
        TAP1L
        LDA  #>USESTATE
        JNC  rs0
        INC
rs0:    TAP1H
        LDA  #<ROSTATE
        TAP2L
        LDA  #>ROSTATE
        TAP2H
        LDA  #13
        STA  USECNT
rs_l:   LDA  (P1)
        STA  (P2)
        INP1
        INP2
        LDA  USECNT
        DEC
        STA  USECNT
        JNZ  rs_l
        LDA  (P1)
        STA  ROSDRV
        RTS

; USEPOP: a spliced library reached EOF -> restore the parent stream
USEPOP: LDA USESP
        DEC
        STA  USESP
        JSR  RESTORESTATE
        RTS

M_LIBPFX: .asciiz "/lib/lib_"
M_DOTC:   .asciiz ".c"


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
        LDB  #'/'                     ; '/' may start a comment
        CMP
        JZ   adv_slash
        STA  TMPB
adv_cls: JSR ISDIG                    ; classify the first non-ws char
        JC   adv_num
        LDA  TMPB
        JSR  ISALP
        JC   adv_id
        LDA  TMPB                     ; char literal  'x'
        LDB  #$27
        CMP
        JZ   adv_chl
        LDA  TMPB                     ; string literal  "..."
        LDB  #$22
        CMP
        JZ   adv_stl
        LDA  #3                      ; punctuation
        STA  CURK
        LDA  TMPB
        STA  CURV
        LDA  #0
        STA  CUR2                    ; default: single-char op
        LDA  TMPB                    ; a two-char op?  == != <= >=  (c2 is '=')
        LDB  #'='
        CMP
        JZ   adv_2ck
        LDB  #'!'
        CMP
        JZ   adv_2ck
        LDB  #'<'
        CMP
        JZ   adv_ltgt
        LDB  #'>'
        CMP
        JZ   adv_ltgt
        LDB  #'&'                    ; '&&' and '||' : combine only if doubled
        CMP
        JZ   adv_2same
        LDB  #'|'
        CMP
        JZ   adv_2same
        LDB  #'+'
        CMP
        JZ   adv_pm
        LDB  #'-'
        CMP
        JZ   adv_pm
        RTS
adv_pm: JSR GC                       ; '+'/'-' : += -= ++ -- or -> or single
        JC   adv_pd
        STA  TMPC
        LDB  #'='
        CMP
        JZ   adv_2set
        LDA  TMPC
        LDB  CURV
        CMP
        JZ   adv_2sset
        LDA  TMPC
        LDB  #'>'
        CMP
        JZ   adv_arrow
        LDA  TMPC
        JSR  UNGC
        RTS
adv_arrow: LDA #'>'                   ; '->' : CURV='-', CUR2='>'
        STA  CUR2
        RTS
adv_ltgt: JSR GC                     ; '<'/'>' : peek for '=' (<=,>=) or doubling (<<,>>)
        JC   adv_pd
        STA  TMPC
        LDB  #'='
        CMP
        JZ   adv_2set
        LDA  TMPC
        LDB  CURV
        CMP
        JZ   adv_2sset
        LDA  TMPC
        JSR  UNGC
        RTS
adv_2same: JSR GC                    ; peek c2
        JC   adv_pd
        STA  TMPC
        LDB  CURV                    ; c1
        CMP                          ; c2 == c1 ?
        JZ   adv_2sset
        LDA  TMPC                    ; not doubled -> push back, stay single
        JSR  UNGC
        RTS
adv_2sset: LDA CURV                  ; CUR2 = the doubled char ('&' or '|')
        STA  CUR2
        RTS
adv_2ck: JSR GC                      ; peek the next char
        JC   adv_pd                  ; EOF -> single
        STA  TMPC
        LDB  #'='
        CMP
        JZ   adv_2set
        LDA  TMPC                    ; not '=' -> push back, stay single
        JSR  UNGC
        RTS
adv_2set: LDA #'='
        STA  CUR2
        RTS
adv_pd: RTS
adv_eof: LDA #0
        STA  CURK
        RTS
adv_chl: JSR GC                       ; 'x' or '\x' -> NUMBER token
        STA  TMPB
        LDB  #$5C
        CMP
        JNZ  ach_v
        JSR  GC                       ; the escaped char
        JSR  ESCMAP                   ; -> byte value
        JMP  ach_set
ach_v:  LDA  TMPB
ach_set: STA CURV
        LDA  #0
        STA  CURV+1
        LDA  #1
        STA  CURK
        JSR  GC                       ; closing quote
        RTS

; ESCMAP: A = char after a backslash -> A = the byte it denotes.
ESCMAP: STA TMPB
        LDB  #'n'
        CMP
        JNZ  esc1
        LDA  #10
        RTS
esc1:   LDA TMPB
        LDB  #'t'
        CMP
        JNZ  esc2
        LDA  #9
        RTS
esc2:   LDA TMPB
        LDB  #'r'
        CMP
        JNZ  esc3
        LDA  #13
        RTS
esc3:   LDA TMPB
        LDB  #'0'
        CMP
        JNZ  esc_d
        LDA  #0
        RTS
esc_d:  LDA TMPB                       ; default (\\ \' \") : the char itself
        RTS
adv_stl: LDA #<STRBUF                  ; "..." -> STRING (kind 4); built via P2
        TAP2L                         ;   (GC/FGETB clobbers P1, preserves P2)
        LDA  #>STRBUF
        TAP2H
asl_l:  JSR  GC
        JC   asl_e                    ; EOF ends it
        STA  TMPB
        LDB  #$22
        CMP
        JZ   asl_e                    ; closing quote
        LDA  TMPB
        LDB  #$5C                     ; backslash: keep it + the next char raw
        CMP
        JNZ  asl_st                   ; (the assembler decodes the escape)
        LDA  #$5C
        STA  (P2)
        INP2
        JSR  GC
        JC   asl_e
        STA  (P2)
        INP2
        JMP  asl_l
asl_st: LDA  TMPB
        STA  (P2)
        INP2
        JMP  asl_l
asl_e:  LDA  #0
        STA  (P2)                     ; NUL-terminate
        LDA  #4
        STA  CURK
        RTS
; '/' seen: peek next -> // line comment, /* block comment, or lone '/' (divide)
adv_slash: JSR GC
        JC   adv_slp                  ; EOF after '/' -> lone '/'
        STA  TMPC
        LDB  #'/'
        CMP
        JZ   adv_linec
        LDA  TMPC
        LDB  #'*'
        CMP
        JZ   adv_blockc
        LDA  TMPC                     ; lone '/' : push back the peeked char
        JSR  UNGC
adv_slp: LDA #'/'
        STA  TMPB
        JMP  adv_cls                  ; classify as the '/' punct
adv_linec: JSR GC                     ; first char after '//'
        JC   adv_eof
        LDB  #LF
        CMP
        JZ   alc_end
        LDB  #'#'
        CMP
        JNZ  alc_skip                 ; ordinary comment
        JSR  TRYUSE                   ; "#use NAME" ? -> splice the library
        JMP  adv_ws
alc_skip: JSR GC                       ; skip the rest of an ordinary comment line
        JC   adv_eof
        LDB  #LF
        CMP
        JNZ  alc_skip
alc_end: JMP  adv_ws
adv_blockc: JSR GC                    ; skip to '*/'
        JC   adv_eof
        LDB  #'*'
        CMP
        JNZ  adv_blockc
abc_st: JSR  GC
        JC   adv_eof
        LDB  #'/'
        CMP
        JZ   adv_ws                   ; '*/' -> comment ends
        LDB  #'*'
        CMP
        JZ   abc_st                   ; another '*' -> re-check
        JMP  adv_blockc

; HEXVAL: A = char -> A = 0..15, C=1 if a hex digit, else C=0
HEXVAL: STA TMPC
        LDB  #'0'
        CMP
        JNC  hv_no
        LDA  TMPC
        LDB  #':'
        CMP
        JC   hv_hi
        LDA  TMPC
        LDB  #'0'
        SUB
        SEC
        RTS
hv_hi:  LDA TMPC
        LDB  #'A'
        CMP
        JNC  hv_no
        LDA  TMPC
        LDB  #'G'
        CMP
        JC   hv_lo
        LDA  TMPC
        LDB  #'A'
        SUB
        LDB  #10
        ADD
        SEC
        RTS
hv_lo:  LDA TMPC
        LDB  #'a'
        CMP
        JNC  hv_no
        LDA  TMPC
        LDB  #'g'
        CMP
        JC   hv_no
        LDA  TMPC
        LDB  #'a'
        SUB
        LDB  #10
        ADD
        SEC
        RTS
hv_no:  CLC
        RTS

adv_num: LDA #0                      ; number -> CURV (decimal, or 0x.. hex)
        STA  NACC
        STA  NACC+1
        LDA  TMPB
        LDB  #'0'
        CMP
        JNZ  an_l                    ; not '0' -> decimal
        JSR  GC                      ; peek after '0'
        JC   an_done
        STA  TMPC
        LDB  #'x'
        CMP
        JZ   an_hex
        LDA  TMPC
        LDB  #'X'
        CMP
        JZ   an_hex
        LDA  TMPC                    ; "0" not followed by x -> decimal
        JSR  UNGC
        JMP  an_l
an_hex: JSR GC                       ; hex digits after 0x
        JC   an_done
        STA  TMPB
        JSR  HEXVAL
        JC   ah_put
        LDA  TMPB
        JSR  UNGC
        JMP  an_done
ah_put: STA DQ                       ; NACC = NACC*16 + digit
        LDA  NACC
        SHL
        STA  NACC
        LDA  NACC+1
        ROL
        STA  NACC+1
        LDA  NACC
        SHL
        STA  NACC
        LDA  NACC+1
        ROL
        STA  NACC+1
        LDA  NACC
        SHL
        STA  NACC
        LDA  NACC+1
        ROL
        STA  NACC+1
        LDA  NACC
        SHL
        STA  NACC
        LDA  NACC+1
        ROL
        STA  NACC+1
        LDA  NACC
        LDB  DQ
        ADD
        STA  NACC
        JNC  ah_nc
        LDA  NACC+1
        INC
        STA  NACC+1
ah_nc:  JMP an_hex
an_l:   LDA  TMPB                    ; digit -> DQ; NACC = NACC*10 + digit (16-bit)
        LDB  #'0'
        SUB
        STA  DQ
        LDA  NACC                    ; MULT2 = NACC << 1
        SHL
        STA  MULT2
        LDA  NACC+1
        ROL
        STA  MULT2+1
        LDA  MULT2                   ; NACC = MULT2 << 2  (= NACC*8)
        SHL
        STA  NACC
        LDA  MULT2+1
        ROL
        STA  NACC+1
        LDA  NACC
        SHL
        STA  NACC
        LDA  NACC+1
        ROL
        STA  NACC+1
        LDA  NACC                    ; NACC = NACC + MULT2  (= NACC*10)
        LDB  MULT2
        ADD
        STA  NACC
        LDA  #0
        JNC  an_c0
        LDA  #1
an_c0:  STA  CARRY
        LDA  NACC+1
        LDB  MULT2+1
        ADD
        LDB  CARRY
        ADD
        STA  NACC+1
        LDA  NACC                    ; NACC += digit
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
        LDA  TMPB
        JSR  UNGC
an_done: LDA #1
        STA  CURK
        LDA  NACC
        STA  CURV
        LDA  NACC+1
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
        LDP1 #MBOOT                  ; JSR _f_main ; RTS
        JSR  EMIT
        JSR  ADVANCE
co_s:   LDA  CURK                    ; a sequence of function definitions
        JZ   co_end
        JSR  FUNCDEF
        JMP  co_s
co_end: LDP1 #MADD_DEF                ; 16-bit runtime helpers (always emitted)
        JSR  EMIT
        LDP1 #MSUB_DEF
        JSR  EMIT
        LDP1 #MCMP_DEF
        JSR  EMIT
        LDA  USEMUL                  ; the multiply helper, if the program used '*'
        JZ   ce_nomul
        LDP1 #MMULDEF
        JSR  EMIT
ce_nomul: LDA USEDIV                 ; the divide/modulo helper, if '/' or '%' used
        JZ   ce_nodiv
        LDP1 #MDMDEF
        JSR  EMIT
ce_nodiv: LDA USENEG                 ; unary-minus helper, if '-' used as a prefix
        JZ   ce_noneg
        LDP1 #MNEG_DEF
        JSR  EMIT
ce_noneg: LDA USENOT                 ; logical-not helper, if '!' used
        JZ   ce_nonot
        LDP1 #MLNOT_DEF
        JSR  EMIT
ce_nonot: LDA USEAND
        JZ   ce_noand
        LDP1 #MANDDEF
        JSR  EMIT
ce_noand: LDA USEOR
        JZ   ce_noor
        LDP1 #MORDEF
        JSR  EMIT
ce_noor: LDA USEXOR
        JZ   ce_noxor
        LDP1 #MXORDEF
        JSR  EMIT
ce_noxor: LDA USESHL
        JZ   ce_noshl
        LDP1 #MSHLDEF
        JSR  EMIT
ce_noshl: LDA USESHR
        JZ   ce_noshr
        LDP1 #MSHRDEF
        JSR  EMIT
ce_noshr: LDP1 #MTEMP                ; the codegen temp
        JSR  EMIT
        LDP1 #MFRAMEDEF              ; arg-stack runtime: __pusharg/__pop/__sp/__cstack
        JSR  EMIT
        LDA  #0                      ; storage for each declared variable:
        STA  VITER                   ;   V0:  .fill 1  /  V1:  .fill 1  / ...
ce_vl:  LDA  VITER
        LDB  SLOTCNT
        CMP
        JC   ce_vd                   ; VITER >= SLOTCNT -> done
        LDP1 #MVL                    ; "V"
        JSR  EMIT
        LDA  VITER
        JSR  EMITNUM
        LDP1 #MVF                    ; ":   .fill 1" + LF
        JSR  EMIT
        LDA  VITER
        INC
        STA  VITER
        JMP  ce_vl
ce_vd:  RTS

; FUNCDEF: int NAME ( ) { <stmt>* }   (Stage A: no parameters yet)

; =============================================================================
; structs (minimal): a tag -> size table, and a GLOBAL member -> offset table
;   (member names are assumed unique across structs). `.`/`->` add the member
;   offset to the base (&var for '.', value(var) for '->') and load/store a
;   word (int/ptr member) or byte (char member).
; =============================================================================
; STRUCTDEF: current = tag name; parse  { type [*]m ; ... } ;  and record it.
STRUCTDEF: JSR CPCURFN                ; CURFN = tag name
        JSR  ADVANCE                  ; past tag
        LDA  #'{'
        JSR  EXPECTP
        LDA  #0
        STA  STOFF
sdf_l:  LDA  CURK                     ; '}' ends the member list
        LDB  #3
        CMP
        JNZ  sdf_m
        LDA  CURV
        LDB  #'}'
        CMP
        JZ   sdf_end
sdf_m:  JSR  EXPECTTYPE               ; member type (int/char)
        LDA  ISCHARTYPE
        STA  DCLCHAR
sdf_st: LDA  CURK                     ; pointer member -> word (DCLCHAR=0)
        LDB  #3
        CMP
        JNZ  sdf_ns
        LDA  CURV
        LDB  #'*'
        CMP
        JNZ  sdf_ns
        LDA  #0
        STA  DCLCHAR
        JSR  ADVANCE
        JMP  sdf_st
sdf_ns: JSR  STMADD_M                 ; member name (TID) @ STOFF, char DCLCHAR
        JSR  ADVANCE                  ; past member name
        LDA  DCLCHAR                  ; STOFF += (char ? 1 : 2)
        JNZ  sdf_c1
        LDA  STOFF
        LDB  #2
        ADD
        STA  STOFF
        JMP  sdf_semi
sdf_c1: LDA STOFF
        INC
        STA  STOFF
sdf_semi: LDA #$3B
        JSR  EXPECTP
        JMP  sdf_l
sdf_end: LDA #'}'
        JSR  EXPECTP
        JSR  STAGADD                  ; record tag CURFN with size STOFF
        LDA  #$3B
        JSR  EXPECTP
        RTS

; fd_struct: top-level 'struct' -> a definition (Tag {...}) or a global var.
fd_struct: JSR ADVANCE                ; past 'struct'
        JSR  CPCURFN                  ; CURFN = tag name (for a possible def)
        JSR  ADVANCE                  ; past tag; peek
        LDA  CURK
        LDB  #3
        CMP
        JNZ  fds_var
        LDA  CURV
        LDB  #'{'
        CMP
        JNZ  fds_var
        ; a definition: CURFN=tag, current='{'.  Re-enter STRUCTDEF's body.
        LDA  #'{'
        JSR  EXPECTP
        LDA  #0
        STA  STOFF
        JMP  sdf_l                    ; (CURFN already = tag)
fds_var: ; global 'struct Tag [*]NAME ;'  -> reserve storage
        JSR  STAGFIND_CURFN           ; TAGSIZE from the tag (still in CURFN)
        LDA  #0
        STA  DCLCHAR
        LDA  #0
        STA  MEMTMP2                  ; is-pointer flag
        LDA  CURK
        LDB  #3
        CMP
        JNZ  fdsv_nm
        LDA  CURV
        LDB  #'*'
        CMP
        JNZ  fdsv_nm
        JSR  ADVANCE                  ; past '*'
        LDA  #1
        STA  MEMTMP2
fdsv_nm: JSR CPCURFN                  ; CURFN = the VARIABLE name (not the tag)
        JSR  GSYMADD
        LDA  MEMTMP2
        JNZ  fdsv_ptr
        LDA  TAGSIZE                  ; struct value: ceil(size/2) slots
        INC
        SHR
        LDB  SLOTCNT
        ADD
        STA  SLOTCNT
        JMP  fdsv_end
fdsv_ptr: LDA SLOTCNT                 ; pointer: 1 slot
        INC
        STA  SLOTCNT
fdsv_end: JSR ADVANCE                 ; past NAME
        LDA  #$3B
        JSR  EXPECTP
        RTS

; st_lstruct: local 'struct Tag [*]NAME ;'
st_lstruct: JSR ADVANCE               ; past 'struct'
        JSR  STAGFIND_CURTID          ; TAGSIZE = size (tag = current TID)
        JSR  ADVANCE                  ; past tag
        LDA  #0
        STA  DCLCHAR
        LDA  CURK                     ; pointer?
        LDB  #3
        CMP
        JNZ  sls_val
        LDA  CURV
        LDB  #'*'
        CMP
        JNZ  sls_val
        JSR  ADVANCE                  ; '*' -> pointer (1 slot)
        JSR  SYMADD
        JSR  SETSYMCHAR
        JMP  sls_end
sls_val: JSR SYMADD                   ; struct value: ceil(size/2) slots
        JSR  SETSYMCHAR
        LDA  TAGSIZE                  ; NLSLOT += ceil(size/2) - 1  (base already 1)
        INC
        SHR
        STA  TMPC
        LDA  NLSLOT
        LDB  TMPC
        ADD
        STA  NLSLOT
        LDA  NLSLOT
        LDB  #1
        SUB
        STA  NLSLOT
sls_end: JSR ADVANCE                  ; past NAME
        LDA  #$3B
        JSR  EXPECTP
        RTS

; STAGADD: record tag CURFN with size STOFF
STAGADD: LDA #<STAGPOOL
        TAP1L
        LDA  #>STAGPOOL
        TAP1H
        LDA  #0
        STA  TMPB
sga_e:  LDA  TMPB
        LDB  STAGCNT
        CMP
        JC   sga_ap
sga_sk: LDA  (P1)
        JZ   sga_np
        INP1
        JMP  sga_sk
sga_np: INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  sga_e
sga_ap: LDA #<CURFN
        TAP2L
        LDA  #>CURFN
        TAP2H
sga_cp: LDA  (P2)
        STA  (P1)
        JZ   sga_dn
        INP1
        INP2
        JMP  sga_cp
sga_dn: LDA #<STAGSIZE
        LDB  STAGCNT
        ADD
        TAP1L
        LDA  #>STAGSIZE
        JNC  sga1
        INC
sga1:   TAP1H
        LDA  STOFF
        STA  (P1)
        LDA  STAGCNT
        INC
        STA  STAGCNT
        RTS

; STAGFIND_CURFN / STAGFIND_CURTID: tag name -> TAGSIZE (by name in CURFN or TID)
STAGFIND_CURFN: LDA #<CURFN
        STA  STFNP
        LDA  #>CURFN
        STA  STFNP+1
        JMP  stf_go
STAGFIND_CURTID: LDA #<TID
        STA  STFNP
        LDA  #>TID
        STA  STFNP+1
stf_go: LDA #<STAGPOOL
        TAP1L
        LDA  #>STAGPOOL
        TAP1H
        LDA  #0
        STA  TMPB
        STA  TAGSIZE
stf_e:  LDA  TMPB
        LDB  STAGCNT
        CMP
        JC   stf_no
        LDA  STFNP
        TAP2L
        LDA  STFNP+1
        TAP2H
stf_c:  LDA  (P1)
        STA  TMPC
        LDA  (P2)
        LDB  TMPC
        CMP
        JNZ  stf_nx
        LDA  (P1)
        JZ   stf_yes
        INP1
        INP2
        JMP  stf_c
stf_nx: LDA  (P1)
        JZ   stf_np
        INP1
        JMP  stf_nx
stf_np: INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  stf_e
stf_yes: LDA #<STAGSIZE
        LDB  TMPB
        ADD
        TAP1L
        LDA  #>STAGSIZE
        JNC  sty1
        INC
sty1:   TAP1H
        LDA  (P1)
        STA  TAGSIZE
stf_no: RTS

; STMADD_M: add member TID @ STOFF (char DCLCHAR) to the global member table
STMADD_M: LDA #<STMPOOL
        TAP1L
        LDA  #>STMPOOL
        TAP1H
        LDA  #0
        STA  TMPB
smm_e:  LDA  TMPB
        LDB  STMCNT
        CMP
        JC   smm_ap
smm_sk: LDA  (P1)
        JZ   smm_np
        INP1
        JMP  smm_sk
smm_np: INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  smm_e
smm_ap: LDA #<TID
        TAP2L
        LDA  #>TID
        TAP2H
smm_cp: LDA  (P2)
        STA  (P1)
        JZ   smm_dn
        INP1
        INP2
        JMP  smm_cp
smm_dn: LDA #<STMOFF
        LDB  STMCNT
        ADD
        TAP1L
        LDA  #>STMOFF
        JNC  smm1
        INC
smm1:   TAP1H
        LDA  STOFF
        STA  (P1)
        LDA  #<STMCH
        LDB  STMCNT
        ADD
        TAP1L
        LDA  #>STMCH
        JNC  smm2
        INC
smm2:   TAP1H
        LDA  DCLCHAR
        STA  (P1)
        LDA  STMCNT
        INC
        STA  STMCNT
        RTS

; STMFIND: member name TID -> STMEMOFF, STMEMCH (STMEMOK=1 if found)
STMFIND: LDA #<STMPOOL
        TAP1L
        LDA  #>STMPOOL
        TAP1H
        LDA  #0
        STA  TMPB
        STA  STMEMOK
smf_e:  LDA  TMPB
        LDB  STMCNT
        CMP
        JC   smf_no
        LDA  #<TID
        TAP2L
        LDA  #>TID
        TAP2H
smf_c:  LDA  (P1)
        STA  TMPC
        LDA  (P2)
        LDB  TMPC
        CMP
        JNZ  smf_nx
        LDA  (P1)
        JZ   smf_yes
        INP1
        INP2
        JMP  smf_c
smf_nx: LDA  (P1)
        JZ   smf_np
        INP1
        JMP  smf_nx
smf_np: INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  smf_e
smf_yes: LDA #1
        STA  STMEMOK
        LDA  #<STMOFF
        LDB  TMPB
        ADD
        TAP1L
        LDA  #>STMOFF
        JNC  smy1
        INC
smy1:   TAP1H
        LDA  (P1)
        STA  STMEMOFF
        LDA  #<STMCH
        LDB  TMPB
        ADD
        TAP1L
        LDA  #>STMCH
        JNC  smy2
        INC
smy2:   TAP1H
        LDA  (P1)
        STA  STMEMCH
smf_no: RTS

; EM_ADDOFF (A = offset): emit __ax += offset  (via __t0 + __add)
EM_ADDOFF: STA MEMTMP
        LDP1 #MLDAI
        JSR  EMIT
        LDA  MEMTMP
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MSTAT
        JSR  EMIT
        LDP1 #MLDA0
        JSR  EMIT
        LDP1 #MSTT0H
        JSR  EMIT
        LDP1 #MADD
        JSR  EMIT
        RTS

; fd_glob: a top-level global declaration  type [*]NAME [ [N] ] ;
fd_glob: JSR GSYMADD                 ; record CURFN @ slot SLOTCNT (char = DCLCHAR)
        LDA  CURK
        LDB  #3
        CMP
        JNZ  fdg_scal
        LDA  CURV
        LDB  #'['
        CMP
        JZ   fdg_arr
fdg_scal: LDA SLOTCNT                ; scalar global: one word slot
        INC
        STA  SLOTCNT
        JMP  fdg_end
fdg_arr: JSR GSYMMARKARR             ; mark it an array
        JSR  ADVANCE                 ; past '['
        LDA  DCLCHAR
        JZ   fdg_aint
        LDA  CURV                    ; char array: ceil(N/2) word slots
        INC
        SHR
        LDB  SLOTCNT
        ADD
        STA  SLOTCNT
        JMP  fdg_asz
fdg_aint: LDA SLOTCNT                ; int array: N word slots
        LDB  CURV
        ADD
        STA  SLOTCNT
fdg_asz: JSR ADVANCE                 ; past size
        LDA  #']'
        JSR  EXPECTP
fdg_end: LDA #$3B
        JSR  EXPECTP
        RTS

FUNCDEF: LDP1 #KW_STRUCT
        JSR  IDEQ
        LDA  TMPB
        JNZ  fd_struct
        JSR  EXPECTTYPE
        LDA  ISCHARTYPE              ; remember char-ness for a possible global
        STA  DCLCHAR
fdt_star: LDA CURK                   ; skip pointer stars (ret-type / global ptr)
        LDB  #3
        CMP
        JNZ  fdt_ns
        LDA  CURV
        LDB  #'*'
        CMP
        JNZ  fdt_ns
        JSR  ADVANCE
        JMP  fdt_star
fdt_ns: JSR  CPCURFN                 ; CURFN <- NAME (function or global)
        JSR  ADVANCE                 ; past NAME; peek what follows
        LDA  CURK
        LDB  #3
        CMP
        JNZ  fd_glob                 ; not '(' -> a global declaration
        LDA  CURV
        LDB  #'('
        CMP
        JNZ  fd_glob
        LDA  SLOTCNT                 ; ---- function definition ----
        STA  SLOTBASE
        LDA  #0
        STA  SYMCNT
        STA  NLSLOT
        LDA  #'('
        JSR  EXPECTP                 ; consume '(' (current)
        LDA  #0
        STA  NPARAMS                 ; parameters: int P, int P, ...
        LDA  CURK
        LDB  #3
        CMP
        JNZ  fp_loop
        LDA  CURV
        LDB  #')'
        CMP
        JZ   fp_done
fp_loop: JSR EXPECTTYPE
        LDA  ISCHARTYPE
        STA  DCLCHAR
fp_star: LDA CURK                    ; skip pointer stars on the param
        LDB  #3
        CMP
        JNZ  fp_nostar
        LDA  CURV
        LDB  #'*'
        CMP
        JNZ  fp_nostar
        JSR  ADVANCE
        JMP  fp_star
fp_nostar: JSR SYMADD                ; the param is a local variable (slots 0..n-1)
        JSR  SETSYMCHAR              ; record a char-typed parameter
        JSR  ADVANCE                 ; past the param name
        LDA  NPARAMS
        INC
        STA  NPARAMS
        LDA  CURK
        LDB  #3
        CMP
        JNZ  fp_done
        LDA  CURV
        LDB  #','
        CMP
        JNZ  fp_done
        JSR  ADVANCE                 ; past ','
        JMP  fp_loop
fp_done: LDA #')'
        JSR  EXPECTP
        LDA  CURK                    ; prototype?  int NAME(params) ;
        LDB  #3
        CMP
        JNZ  fd_def
        LDA  CURV
        LDB  #$3B
        CMP
        JNZ  fd_def
        JSR  FADD                    ; a prototype still registers the name
        JSR  ADVANCE                 ; consume ';' (forward calls can now resolve it)
        RTS
fd_def: JSR  FADD                    ; record CURFN -> NPARAMS, SLOTBASE
        LDP1 #MFPFX                  ; "_f_" NAME ":"
        JSR  EMIT
        LDP1 #CURFN
        JSR  EMIT
        LDP1 #MCOLON
        JSR  EMIT
        JSR  EM_POPPARAMS            ; prologue: pop args into param slots
        LDA  #'{'
        JSR  EXPECTP
fd_s:   LDA  CURK
        LDB  #3
        CMP
        JNZ  fd_st
        LDA  CURV
        LDB  #'}'
        CMP
        JZ   fd_end
fd_st:  JSR  STMT
        JMP  fd_s
fd_end: LDA  #'}'
        JSR  EXPECTP
        LDP1 #MEPFX                  ; "_e_" NAME ":"  (return target)
        JSR  EMIT
        LDP1 #CURFN
        JSR  EMIT
        LDP1 #MCOLON
        JSR  EMIT
        LDP1 #MRTS
        JSR  EMIT
        LDA  SLOTBASE                ; advance the global slot counter
        LDB  NLSLOT
        ADD
        STA  SLOTCNT
        RTS
; CPCURFN / CPIDNAME: copy the current id (TID) into CURFN / IDNAME.
CPCURFN: LDA #<CURFN
        TAP2L
        LDA  #>CURFN
        TAP2H
        JMP  cpn_go
CPIDNAME: LDA #<IDNAME
        TAP2L
        LDA  #>IDNAME
        TAP2H
cpn_go: LDA #<TID
        TAP1L
        LDA  #>TID
        TAP1H
cpn_l:  LDA  (P1)
        STA  (P2)
        JZ   cpn_d
        INP1
        INP2
        JMP  cpn_l
cpn_d:  RTS

; FADD: record the current function -> FPOOL name, FNPAR[], FSLOT[].
FADD:   LDA #<FPOOL
        TAP1L
        LDA  #>FPOOL
        TAP1H
        LDA  #0
        STA  TMPC
fa_e:   LDA  TMPC
        LDB  FCNT
        CMP
        JC   fa_ap
fa_sk:  LDA  (P1)
        JZ   fa_np
        INP1
        JMP  fa_sk
fa_np:  INP1
        LDA  TMPC
        INC
        STA  TMPC
        JMP  fa_e
fa_ap:  LDA #<CURFN
        TAP2L
        LDA  #>CURFN
        TAP2H
fa_cp:  LDA  (P2)
        STA  (P1)
        JZ   fa_dn
        INP1
        INP2
        JMP  fa_cp
fa_dn:  LDA #<FNPAR
        LDB  FCNT
        ADD
        TAP1L
        LDA  #>FNPAR
        JNC  fad1
        INC
fad1:   TAP1H
        LDA  NPARAMS
        STA  (P1)
        LDA  #<FSLOT
        LDB  FCNT
        ADD
        TAP1L
        LDA  #>FSLOT
        JNC  fad2
        INC
fad2:   TAP1H
        LDA  SLOTBASE
        STA  (P1)
        LDA  FCNT
        INC
        STA  FCNT
        RTS
; FFIND_ID: look up IDNAME in the function table -> FFB (base slot), FOK.
FFIND_ID: LDA #0
        STA  FOK
        LDA  #<FPOOL
        TAP1L
        LDA  #>FPOOL
        TAP1H
        LDA  #0
        STA  FI
ff_e:   LDA  FI
        LDB  FCNT
        CMP
        JC   ff_no
        LDA  #<IDNAME
        TAP2L
        LDA  #>IDNAME
        TAP2H
ff_c:   LDA  (P1)
        STA  TMPC
        LDA  (P2)
        LDB  TMPC
        CMP
        JNZ  ff_nx
        LDA  (P1)
        JZ   ff_yes
        INP1
        INP2
        JMP  ff_c
ff_nx:  LDA  (P1)
        JZ   ff_np
        INP1
        JMP  ff_nx
ff_np:  INP1
        LDA  FI
        INC
        STA  FI
        JMP  ff_e
ff_yes: LDA #<FSLOT
        LDB  FI
        ADD
        TAP1L
        LDA  #>FSLOT
        JNC  ffy1
        INC
ffy1:   TAP1H
        LDA  (P1)
        STA  FFB
        LDA  #1
        STA  FOK
        RTS
ff_no:  LDA #0
        STA  FOK
        RTS
; EM_STSLOT: store __ax into the absolute variable slot in ARGSLOT.
EM_STSLOT: LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  ARGSLOT
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MLDAXH
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  ARGSLOT
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        RTS

; one statement
STMT:   LDA  CURK
        LDB  #3
        CMP
        JZ   st_punct                ; '{' -> block
        LDB  #2
        CMP
        JNZ  st_err
        LDP1 #KW_INT
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_decl
        LDP1 #KW_CHAR
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_decl
        LDP1 #KW_STRUCT
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_lstruct
        LDP1 #KW_IF
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_if
        LDP1 #KW_WHILE
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_while
        LDP1 #KW_PUTC
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_putc
        LDP1 #KW_RET
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_ret
        LDP1 #KW_FOR
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_for
        LDP1 #KW_BRK
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_break
        LDP1 #KW_CONT
        JSR  IDEQ
        LDA  TMPB
        JNZ  st_continue
        JMP  st_assign               ; an identifier LHS -> assignment
st_punct: LDA CURV
        LDB  #'{'
        CMP
        JZ   st_block
        LDA  CURV
        LDB  #'*'
        CMP
        JZ   st_derefasg
st_err: RTS                          ; (unknown statement -> stop quietly)
; *ptr = expr ;   -> store a word through a pointer
st_derefasg: JSR ADVANCE             ; past '*'
        JSR  GUNARY                  ; address -> __ax
        JSR  EM_PUSH                 ; save address
        LDA  #'='
        JSR  EXPECTP
        JSR  GEXPR                   ; RHS -> __ax
        JSR  EM_POP                  ; address -> __t0
        JSR  EM_STOREW               ; *(__t0) = __ax
        LDA  #$3B
        JSR  EXPECTP
        RTS

; { <stmt>* }
st_block: LDA #'{'
        JSR  EXPECTP
sb_l:   LDA  CURK
        LDB  #3
        CMP
        JNZ  sb_st
        LDA  CURV
        LDB  #'}'
        CMP
        JZ   sb_end
sb_st:  JSR  STMT
        JMP  sb_l
sb_end: LDA  #'}'
        JSR  EXPECTP
        RTS

; if ( <expr> ) <stmt> [ else <stmt> ]
st_if:  JSR  ADVANCE                 ; past "if"
        LDA  #'('
        JSR  EXPECTP
        JSR  GEXPR                   ; condition -> __ax
        LDA  #')'
        JSR  EXPECTP
        JSR  EM_TESTAX               ; set Z from __ax for the branch
        JSR  NEWLBL                  ; la = false-branch target
        PHA
        LDP1 #MJZ
        PLA
        PHA
        JSR  EMITJ                   ; JZ L<la>
        JSR  STMT                    ; then-branch
        LDA  CURK                    ; an "else"?
        LDB  #2
        CMP
        JNZ  if_ne
        LDP1 #KW_ELSE
        JSR  IDEQ
        LDA  TMPB
        JZ   if_ne
        JSR  ADVANCE                 ; past "else"
        PLA                          ; la
        STA  IFTMP
        JSR  NEWLBL                  ; lb = end target
        PHA
        LDP1 #MJMP
        PLA
        PHA
        JSR  EMITJ                   ; JMP L<lb>
        LDA  IFTMP
        JSR  EMITLBL                 ; L<la>:
        JSR  STMT                    ; else-branch
        PLA
        JSR  EMITLBL                 ; L<lb>:
        RTS
if_ne:  PLA                          ; la
        JSR  EMITLBL                 ; L<la>:
        RTS

; while ( <expr> ) <stmt>
; break ;   -> jump to the innermost loop's end label
st_break: JSR ADVANCE
        LDP1 #MJMP
        LDA  CURBRK
        JSR  EMITJ
        LDA  #$3B
        JSR  EXPECTP
        RTS

; continue ;   -> jump to the innermost loop's continue label
st_continue: JSR ADVANCE
        LDP1 #MJMP
        LDA  CURCONT
        JSR  EMITJ
        LDA  #$3B
        JSR  EXPECTP
        RTS

; for ( [init] ; [cond] ; [post] ) <stmt>
; single-pass jump threading:  init ; Ltop: cond?JZ Lend ; JMP Lbody ;
;   Lpost: post ; JMP Ltop ; Lbody: <body> ; JMP Lpost ; Lend:
st_for: JSR  ADVANCE                  ; past "for"
        LDA  #'('
        JSR  EXPECTP
        JSR  NEWLBL                   ; Ltop (cond)
        STA  LFT
        JSR  NEWLBL                   ; Lbody
        STA  LFB
        JSR  NEWLBL                   ; Lpost
        STA  LFP
        JSR  NEWLBL                   ; Lend
        STA  LFE
        JSR  FORCLAUSE                 ; init (optional assignment)
        LDA  #$3B                      ; ';'
        JSR  EXPECTP
        LDA  LFT                       ; Ltop:
        JSR  EMITLBL
        LDA  CURK                      ; empty condition?  (next token is ';')
        LDB  #3
        CMP
        JNZ  sf_cond
        LDA  CURV
        LDB  #$3B
        CMP
        JZ   sf_nocond
sf_cond: JSR  GEXPR                    ; cond -> __ax
        JSR  EM_TESTAX
        LDP1 #MJZ
        LDA  LFE
        JSR  EMITJ                     ; JZ Lend
sf_nocond: LDA #$3B
        JSR  EXPECTP
        LDP1 #MJMP                     ; JMP Lbody
        LDA  LFB
        JSR  EMITJ
        LDA  LFP                       ; Lpost:
        JSR  EMITLBL
        JSR  FORCLAUSE                  ; post (optional assignment)
        LDA  #')'
        JSR  EXPECTP
        LDP1 #MJMP                     ; JMP Ltop
        LDA  LFT
        JSR  EMITJ
        LDA  LFB                       ; Lbody:
        JSR  EMITLBL
        LDA  CURBRK                    ; save enclosing break/continue
        PHA
        LDA  CURCONT
        PHA
        LDA  LFP                       ; save Lpost/Lend across the body (may nest)
        PHA
        LDA  LFE
        PHA
        LDA  LFE
        STA  CURBRK                    ; break -> Lend
        LDA  LFP
        STA  CURCONT                   ; continue -> Lpost (run post, re-test)
        JSR  STMT                      ; body
        PLA
        STA  LFE
        PLA
        STA  LFP
        PLA
        STA  CURCONT
        PLA
        STA  CURBRK
        LDP1 #MJMP                     ; JMP Lpost
        LDA  LFP
        JSR  EMITJ
        LDA  LFE                       ; Lend:
        JSR  EMITLBL
        RTS

; FORCLAUSE: optional  NAME = expr  (for-loop init/post; consumes no terminator)
FORCLAUSE: LDA CURK
        LDB  #2                        ; an identifier LHS?
        CMP
        JNZ  fc_ret                    ; else empty clause
        JSR  SYMFIND
        LDA  SYMOK
        JZ   fc_ret                    ; undeclared -> stop quietly
        LDA  SYMIDX
        STA  LHSIDX
        JSR  ADVANCE                   ; past NAME
        LDA  #'='
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EMITSTV                   ; STA V<LHSIDX>
fc_ret: RTS

st_while: JSR ADVANCE                ; past "while"
        JSR  NEWLBL                  ; ltop
        STA  WHT
        JSR  NEWLBL                  ; lend
        STA  WHE
        LDA  WHT
        JSR  EMITLBL                 ; L<ltop>:
        LDA  #'('
        JSR  EXPECTP
        JSR  GEXPR                   ; condition -> __ax
        LDA  #')'
        JSR  EXPECTP
        JSR  EM_TESTAX               ; set Z from __ax for the branch
        LDP1 #MJZ
        LDA  WHE
        JSR  EMITJ                   ; JZ L<lend>
        LDA  CURBRK                  ; enter loop: save enclosing break/continue
        PHA
        LDA  CURCONT
        PHA
        LDA  WHT                     ; and this loop's labels (nesting)
        PHA
        LDA  WHE
        PHA
        LDA  WHE
        STA  CURBRK                  ; break -> lend
        LDA  WHT
        STA  CURCONT                 ; continue -> ltop (re-test)
        JSR  STMT                    ; body
        PLA
        STA  WHE
        PLA
        STA  WHT
        PLA
        STA  CURCONT
        PLA
        STA  CURBRK
        LDP1 #MJMP
        LDA  WHT
        JSR  EMITJ                   ; JMP L<ltop>
        LDA  WHE
        JSR  EMITLBL                 ; L<lend>:
        RTS

; int NAME [ = expr ] ;   -> reserve a variable, optionally initialise it
st_decl: LDP1 #KW_CHAR              ; int or char ?
        JSR  IDEQ
        LDA  TMPB
        STA  DCLCHAR
        JSR  ADVANCE                 ; past the type keyword
sd_star: LDA CURK                    ; skip pointer stars: int *p, int **p
        LDB  #3
        CMP
        JNZ  sd_nostar
        LDA  CURV
        LDB  #'*'
        CMP
        JNZ  sd_nostar
        JSR  ADVANCE
        JMP  sd_star
sd_nostar: JSR SYMADD                ; add NAME (current id) -> SYMIDX
        LDA  SYMIDX
        STA  LHSIDX
        JSR  SETSYMCHAR              ; SYMCHAR[slot] = DCLCHAR
        JSR  ADVANCE                 ; past NAME
        LDA  CURK                    ; array?  int NAME [ N ]
        LDB  #3
        CMP
        JNZ  sd_chkeq
        LDA  CURV
        LDB  #'['
        CMP
        JZ   sd_arr
sd_chkeq: LDA CURK                   ; optional  = expr
        LDB  #3
        CMP
        JNZ  sd_semi
        LDA  CURV
        LDB  #'='
        CMP
        JNZ  sd_semi
        JSR  ADVANCE                 ; past '='
        JSR  GEXPR
        JSR  EMITSTV                 ; STA V<LHSIDX>
sd_arr: JSR ADVANCE                  ; past '['
        LDA  DCLCHAR                  ; char array: ceil(N/2) words; int array: N
        JNZ  sd_arrc
        LDA  NLSLOT
        LDB  CURV
        ADD
        STA  NLSLOT
        JMP  sd_arrm
sd_arrc: LDA CURV                     ; (N + 1) / 2
        INC
        SHR
        LDB  NLSLOT
        ADD
        STA  NLSLOT
sd_arrm: LDA NLSLOT                   ; the base slot was already counted -> -1
        LDB  #1
        SUB
        STA  NLSLOT
        LDA  #<SYMARR                 ; SYMARR[base slot] = 1
        LDB  LHSIDX
        ADD
        TAP1L
        LDA  #>SYMARR
        JNC  sd_a1
        INC
sd_a1:  TAP1H
        LDA  #1
        STA  (P1)
        JSR  ADVANCE                  ; past size
        LDA  #']'
        JSR  EXPECTP
sd_semi: LDA #$3B
        JSR  EXPECTP
        RTS

; NAME = expr ;   -> assignment to an existing variable
st_assign: JSR SYMFIND              ; look up NAME (current id) -> SYMIDX/SYMOK
        LDA  SYMOK
        JZ   st_exprstmt             ; not a variable (a function call etc.)
        JMP  st_asg2
; expression statement:  foo(args) ;   (evaluate for side effects, discard result)
st_exprstmt: JSR GEXPR
        LDA  #$3B
        JSR  EXPECTP
        RTS
st_asg2:
        LDA  SYMIDX
        STA  LHSIDX
        LDA  SYMRCH
        STA  LHSCH
        LDA  SYMRAR
        STA  LHSAR
        JSR  ADVANCE                 ; past NAME
        LDA  CURK                    ; NAME[index] = e ?
        LDB  #3
        CMP
        JNZ  sa_scalar
        LDA  CURV
        LDB  #'['
        CMP
        JZ   sa_arrstore
        LDA  CUR2                 ; NAME.m = e  or  NAME->m = e ?
        JNZ  sa_ck_arrow
        LDA  CURV
        LDB  #'.'
        CMP
        JZ   sa_memdot
        JMP  sa_scalar
sa_ck_arrow: LDA CURV
        LDB  #'-'
        CMP
        JNZ  sa_scalar
        LDA  CUR2
        LDB  #'>'
        CMP
        JZ   sa_memarrow
        JMP  sa_scalar
sa_memdot: LDA LHSIDX             ; &NAME + offset
        STA  SYMIDX
        JSR  EM_ADDROF
        JMP  sa_memcommon
sa_memarrow: LDA LHSIDX           ; value(NAME) + offset
        STA  SYMIDX
        JSR  EM_LDVAR
sa_memcommon: JSR ADVANCE         ; past '.' or '->'
        JSR  STMFIND
        LDA  STMEMOFF
        JSR  EM_ADDOFF
        JSR  ADVANCE              ; past member name
        LDA  STMEMCH
        STA  MEMTMP2              ; remember member width across the RHS
        JSR  EM_PUSH              ; save address
        LDA  #'='
        JSR  EXPECTP
        JSR  GEXPR                ; RHS -> __ax
        JSR  EM_POP               ; address -> __t0
        LDA  MEMTMP2
        JNZ  sa_memb
        JSR  EM_STOREW
        JMP  sa_memsemi
sa_memb: JSR EM_STOREB
sa_memsemi: LDA #$3B
        JSR  EXPECTP
        RTS
sa_scalar: LDA CUR2               ; ++ / -- / += / -= ?
        JZ   sa_asg
        LDA  CURV
        LDB  #'+'
        CMP
        JZ   sa_cadd
        LDA  CURV
        LDB  #'-'
        CMP
        JZ   sa_csub
sa_asg: LDA #'='
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EMITSTV                 ; STA V<LHSIDX>
        LDA  #$3B
        JSR  EXPECTP
        RTS
sa_cadd: JSR SA_CLOAD               ; NAME += rhs
        LDP1 #MADD
        JSR  EMIT
        JMP  sa_cst
sa_csub: JSR SA_CLOAD               ; NAME -= rhs
        LDP1 #MSUB
        JSR  EMIT
sa_cst: JSR EMITSTV
        LDA  #$3B
        JSR  EXPECTP
        RTS
; SA_CLOAD: __ax = old NAME (pushed), then RHS -> __ax, then __t0 = old NAME.
;   rhs = 1 for ++/-- (CUR2 == CURV), or an expression for += / -= (CUR2 == '=').
SA_CLOAD: LDA LHSIDX
        STA  SYMIDX
        JSR  EM_LDVAR
        JSR  EM_PUSH
        LDA  CUR2
        LDB  #'='
        CMP
        JZ   scl_e
        JSR  ADVANCE                 ; past ++ / --
        JSR  EM_AX1                  ; rhs = 1
        JMP  scl_p
scl_e:  JSR ADVANCE                  ; past += / -=
        JSR  GEXPR
scl_p:  JSR EM_POP                   ; __t0 = old NAME
        RTS
sa_arrstore: LDA LHSIDX
        STA  SYMIDX
        LDA  LHSCH
        STA  ELCHAR
        LDA  LHSAR
        STA  ELARR
        JSR  ELEMADDR                ; __ax = element address (consumes [i])
        LDA  ELCHAR                  ; save char-ness across the RHS parse
        PHA
        JSR  EM_PUSH                 ; save address
        LDA  #'='
        JSR  EXPECTP
        JSR  GEXPR                   ; RHS -> __ax
        JSR  EM_POP                  ; address -> __t0
        PLA
        STA  ELCHAR
        LDA  ELCHAR
        JNZ  sas_b
        JSR  EM_STOREW
        JMP  sas_semi
sas_b:  JSR  EM_STOREB
sas_semi: LDA #$3B
        JSR  EXPECTP
        RTS
; EMITSTV: emit  "        STA V<LHSIDX>" + newline
EMITSTV: JSR EM_STVAR                 ; V<LHSIDX> = __ax
        RTS
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
        LDP1 #MJMPE                  ; JMP _e_<CURFN>  (function epilogue)
        JSR  EMIT
        LDP1 #CURFN
        JSR  EMIT
        LDP1 #MNL
        JSR  EMIT
        RTS

; expression: GADD [ relop GADD ]  -> result in the runtime A register.
; A relational compares two additive expressions, yielding 0/1 (single, non-
; associative). Assignment/putchar/return/conditions all call GEXPR.
GREL:   JSR  GSHIFT
        LDA  CURK
        LDB  #3
        CMP
        JNZ  grx
        JSR  RELDET                  ; is the current punct a relop? -> RELOP/RELF
        LDA  RELF
        JZ   grx
        JSR  EM_PUSH                 ; push the left operand
        LDA  RELOP                   ; save RELOP across GADD (parens may recurse)
        PHA
        JSR  ADVANCE                 ; past the operator
        JSR  GSHIFT                  ; right operand -> __ax
        PLA
        STA  RELOP
        JSR  EM_POP                  ; pop left -> __t0
        LDP1 #MCMP                   ; JSR __cmp  (C=left>=right, Z=eq)
        JSR  EMIT
        JSR  EMITCMP                 ; emit the 0/1 sequence for RELOP
grx:    RTS

; expr: logical-or  ->  land ('||' land)*   (short-circuit, yields 0/1)
; expr : cond  ->  a ? b : c   (ternary; wraps the || level GLOR)
GEXPR:  JSR  GLOR
        LDA  CURK
        LDB  #3
        CMP
        JNZ  ge_condd
        LDA  CURV
        LDB  #'?'
        CMP
        JNZ  ge_condd
        JSR  ADVANCE                 ; past '?'
        JSR  EM_TESTAX
        JSR  NEWLBL
        STA  TERNF
        JSR  NEWLBL
        STA  TERNE
        LDP1 #MJZ
        LDA  TERNF
        JSR  EMITJ                   ; JZ Lfalse
        LDA  TERNF                   ; save labels across the true branch (may nest)
        PHA
        LDA  TERNE
        PHA
        JSR  GEXPR                   ; b (true branch)
        PLA
        STA  TERNE
        PLA
        STA  TERNF
        LDA  #':'
        JSR  EXPECTP
        LDP1 #MJMP
        LDA  TERNE
        JSR  EMITJ                   ; JMP Lend
        LDA  TERNF
        JSR  EMITLBL                 ; Lfalse:
        LDA  TERNE
        PHA
        JSR  GEXPR                   ; c (false branch)
        PLA
        STA  TERNE
        LDA  TERNE
        JSR  EMITLBL                 ; Lend:
ge_condd: RTS

GLOR:   JSR  GLAND
ge_orl: LDA  CURK
        LDB  #3
        CMP
        JNZ  ge_ord
        LDA  CURV
        LDB  #'|'
        CMP
        JNZ  ge_ord
        LDA  CUR2
        LDB  #'|'
        CMP
        JNZ  ge_ord
        JSR  NEWLBL                  ; Ltrue
        STA  LORT
        JSR  NEWLBL                  ; Lend
        STA  LORE
        JSR  EM_TESTAX               ; left in __ax
        LDP1 #MJNZ
        LDA  LORT
        JSR  EMITJ                   ; JNZ Ltrue  (left true -> whole true)
        JSR  ADVANCE                 ; past '||'
        LDA  LORT
        PHA
        LDA  LORE
        PHA
        JSR  GLAND                   ; right -> __ax  (labels saved on stack)
        PLA
        STA  LORE
        PLA
        STA  LORT
        JSR  EM_TESTAX
        LDP1 #MJNZ
        LDA  LORT
        JSR  EMITJ                   ; JNZ Ltrue
        JSR  EM_AX0                  ; both false -> 0
        LDP1 #MJMP
        LDA  LORE
        JSR  EMITJ                   ; JMP Lend
        LDA  LORT
        JSR  EMITLBL                 ; Ltrue:
        JSR  EM_AX1                  ; -> 1
        LDA  LORE
        JSR  EMITLBL                 ; Lend:
        JMP  ge_orl                  ; chained '||'
ge_ord: RTS

; logical-and  ->  rel ('&&' rel)*   (short-circuit, yields 0/1)
GLAND:  JSR  GBOR
ga_andl: LDA CURK
        LDB  #3
        CMP
        JNZ  ga_andd
        LDA  CURV
        LDB  #'&'
        CMP
        JNZ  ga_andd
        LDA  CUR2
        LDB  #'&'
        CMP
        JNZ  ga_andd
        JSR  NEWLBL                  ; Lfalse
        STA  LANDF
        JSR  NEWLBL                  ; Lend
        STA  LANDE
        JSR  EM_TESTAX
        LDP1 #MJZ
        LDA  LANDF
        JSR  EMITJ                   ; JZ Lfalse  (left false -> whole false)
        JSR  ADVANCE                 ; past '&&'
        LDA  LANDF
        PHA
        LDA  LANDE
        PHA
        JSR  GBOR                    ; right -> __ax
        PLA
        STA  LANDE
        PLA
        STA  LANDF
        JSR  EM_TESTAX
        LDP1 #MJZ
        LDA  LANDF
        JSR  EMITJ                   ; JZ Lfalse
        JSR  EM_AX1                  ; both true -> 1
        LDP1 #MJMP
        LDA  LANDE
        JSR  EMITJ                   ; JMP Lend
        LDA  LANDF
        JSR  EMITLBL                 ; Lfalse:
        JSR  EM_AX0                  ; -> 0
        LDA  LANDE
        JSR  EMITLBL                 ; Lend:
        JMP  ga_andl                 ; chained '&&'
ga_andd: RTS

; term: factor (('*'|'/'|'%') factor)*   (8-bit, via __mul8/__divmod8 helpers)
GTERM:  JSR  GUNARY
gt_l:   LDA  CURK
        LDB  #3
        CMP
        JNZ  gt_d
        LDA  CURV
        LDB  #'*'
        CMP
        JZ   gt_mul
        LDA  CURV
        LDB  #'/'
        CMP
        JZ   gt_div
        LDA  CURV
        LDB  #'%'
        CMP
        JZ   gt_mod
        JMP  gt_d
gt_mul: JSR  ADVANCE
        LDA  #1
        STA  USEMUL
        JSR  GT_COMB
        LDP1 #MMUL                   ; JSR __mul8 -> A = left * right
        JSR  EMIT
        JMP  gt_l
gt_div: JSR  ADVANCE
        LDA  #1
        STA  USEDIV
        JSR  GT_COMB
        LDP1 #MDIV                   ; JSR __divmod8 ; LDA __d1  (quotient)
        JSR  EMIT
        JMP  gt_l
gt_mod: JSR  ADVANCE
        LDA  #1
        STA  USEDIV
        JSR  GT_COMB
        LDP1 #MMOD                   ; JSR __divmod8 ; LDA __d0  (remainder)
        JSR  EMIT
        JMP  gt_l
gt_d:   RTS
; GT_COMB: emit  push-left ; <right factor> ; STA __t0 ; PLA  (left in A, right in __t0)
GT_COMB: JSR EM_PUSH                  ; left
        JSR  GUNARY                   ; right -> __ax
        JSR  EM_POP                   ; left -> __t0
        RTS

; additive: term (('+'|'-') term)*
; bitwise: GBOR (|) -> GBXOR (^) -> GBAND (&) -> GREL   (C precedence)
GBOR:   JSR  GBXOR
gbo_l:  LDA  CURK
        LDB  #3
        CMP
        JNZ  gbo_d
        LDA  CUR2
        JNZ  gbo_d
        LDA  CURV
        LDB  #'|'
        CMP
        JNZ  gbo_d
        JSR  ADVANCE
        JSR  EM_PUSH
        JSR  GBXOR
        JSR  EM_POP
        LDA  #1
        STA  USEOR
        LDP1 #MJOR
        JSR  EMIT
        JMP  gbo_l
gbo_d:  RTS

GBXOR:  JSR  GBAND
gbx_l:  LDA  CURK
        LDB  #3
        CMP
        JNZ  gbx_d
        LDA  CUR2
        JNZ  gbx_d
        LDA  CURV
        LDB  #'^'
        CMP
        JNZ  gbx_d
        JSR  ADVANCE
        JSR  EM_PUSH
        JSR  GBAND
        JSR  EM_POP
        LDA  #1
        STA  USEXOR
        LDP1 #MJXOR
        JSR  EMIT
        JMP  gbx_l
gbx_d:  RTS

GBAND:  JSR  GREL
gba_l:  LDA  CURK
        LDB  #3
        CMP
        JNZ  gba_d
        LDA  CUR2                    ; single '&' (binary AND), not '&&'
        JNZ  gba_d
        LDA  CURV
        LDB  #'&'
        CMP
        JNZ  gba_d
        JSR  ADVANCE
        JSR  EM_PUSH
        JSR  GREL
        JSR  EM_POP
        LDA  #1
        STA  USEAND
        LDP1 #MJAND
        JSR  EMIT
        JMP  gba_l
gba_d:  RTS

; shift: GSHIFT (<< >>) between relational and additive
GSHIFT: JSR  GADD
gsh_l:  LDA  CURK
        LDB  #3
        CMP
        JNZ  gsh_d
        LDA  CURV
        LDB  #'<'
        CMP
        JZ   gsh_ml
        LDA  CURV
        LDB  #'>'
        CMP
        JZ   gsh_mr
        JMP  gsh_d
gsh_ml: LDA CUR2
        LDB  #'<'
        CMP
        JNZ  gsh_d
        JSR  ADVANCE
        JSR  EM_PUSH
        JSR  GADD
        JSR  EM_POP
        LDA  #1
        STA  USESHL
        LDP1 #MJSHL
        JSR  EMIT
        JMP  gsh_l
gsh_mr: LDA CUR2
        LDB  #'>'
        CMP
        JNZ  gsh_d
        JSR  ADVANCE
        JSR  EM_PUSH
        JSR  GADD
        JSR  EM_POP
        LDA  #1
        STA  USESHR
        LDP1 #MJSHR
        JSR  EMIT
        JMP  gsh_l
gsh_d:  RTS

GADD:   JSR  GTERM
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
        JSR  EM_PUSH                  ; left
        JSR  GTERM                    ; right -> __ax
        JSR  EM_POP                   ; left -> __t0
        LDP1 #MADD                    ; JSR __add  (__ax = __t0 + __ax)
        JSR  EMIT
        JMP  ge_l
ge_sub: JSR  ADVANCE
        JSR  EM_PUSH                  ; left
        JSR  GTERM                    ; right -> __ax
        JSR  EM_POP                   ; left -> __t0
        LDP1 #MSUB                    ; JSR __sub  (__ax = __t0 - __ax)
        JSR  EMIT
        JMP  ge_l
ge_d:   RTS

; unary: ('-' | '!') unary | factor
GUNARY: LDA  CURK
        LDB  #3
        CMP
        JNZ  gu_fact
        LDA  CUR2                    ; prefix ++ / -- (CUR2 == CURV)
        LDB  #'+'
        CMP
        JNZ  gu_np1
        LDA  CURV
        LDB  #'+'
        CMP
        JZ   gu_pinc
gu_np1: LDA  CUR2
        LDB  #'-'
        CMP
        JNZ  gu_np2
        LDA  CURV
        LDB  #'-'
        CMP
        JZ   gu_pdec
gu_np2: LDA  CUR2                    ; other two-char op -> factor
        JNZ  gu_fact
        LDA  CURV
        LDB  #'-'
        CMP
        JZ   gu_neg
        LDA  CURV
        LDB  #'!'
        CMP
        JZ   gu_not
        LDA  CURV
        LDB  #'&'
        CMP
        JZ   gu_addr
        LDA  CURV
        LDB  #'*'
        CMP
        JZ   gu_deref
gu_fact: JMP  GFACT
gu_pinc: JSR ADVANCE
        JSR  SYMFIND
        LDA  SYMOK
        JZ   gu_fact
        JSR  EM_INCVAR
        JSR  EM_LDVAR
        JSR  ADVANCE
        RTS
gu_pdec: JSR ADVANCE
        JSR  SYMFIND
        LDA  SYMOK
        JZ   gu_fact
        JSR  EM_DECVAR
        JSR  EM_LDVAR
        JSR  ADVANCE
        RTS
gu_addr: LDA #1
        STA  SAWADDRG                 ; an argument took an address (pass-by-ref)
        JSR  ADVANCE                 ; past '&'
        JSR  SYMFIND                  ; the NAME (TID) -> SYMIDX (slot)
        LDA  SYMOK
        JZ   gu_ad_e
        LDA  SYMIDX
        STA  IDVARIDX                 ; save the slot across ADVANCE
        LDA  SYMRCH
        STA  IDVARCH
        LDA  SYMRAR
        STA  IDVARAR
        JSR  ADVANCE                  ; past NAME
        LDA  CURK                     ; &NAME[i] ?
        LDB  #3
        CMP
        JNZ  gu_ad_pl
        LDA  CURV
        LDB  #'['
        CMP
        JZ   gu_ad_ix
gu_ad_pl: LDA IDVARIDX                ; &NAME  -> address of the variable
        STA  SYMIDX
        JSR  EM_ADDROF
        RTS
gu_ad_ix: LDA IDVARIDX                ; &NAME[i] -> address of the element
        STA  SYMIDX
        LDA  IDVARCH
        STA  ELCHAR
        LDA  IDVARAR
        STA  ELARR
        JSR  ELEMADDR
        RTS
gu_ad_e: RTS
gu_deref: JSR ADVANCE                 ; past '*'
        JSR  GUNARY                   ; the address expression -> __ax
        LDA  EXPRCHAR                 ; char* -> byte load, else word
        JNZ  gud_b
        JSR  EM_LOADW
        RTS
gud_b:  JSR  EM_LOADB
        RTS
gu_neg: JSR  ADVANCE
        JSR  GUNARY
        LDA  #1
        STA  USENEG
        LDP1 #MNEG                   ; JSR __neg  (__ax = -__ax)
        JSR  EMIT
        RTS
gu_not: JSR  ADVANCE
        JSR  GUNARY
        LDA  #1
        STA  USENOT
        LDP1 #MLNOT                  ; JSR __lnot (__ax = !__ax -> 0/1)
        JSR  EMIT
        RTS

; factor: NUMBER | IDENT | '(' expr ')'
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
gf_num: JSR  EM_LDIMM                ; __ax = the 16-bit literal
        LDA  #0
        STA  EXPRCHAR
        JSR  ADVANCE
        RTS
; a string literal: emit its bytes inline (jumped over), __ax = its address.
; Padded with an extra 0 so a WORD load at the terminating NUL reads 0.
gf_str: LDA #1                       ; a string literal is a char*
        STA  EXPRCHAR
        JSR  NEWLBL
        STA  STRDL                    ; data label
        JSR  NEWLBL
        STA  STRSL                    ; skip label
        LDP1 #MJMP                    ; JMP L<skip>
        LDA  STRSL
        JSR  EMITJ
        LDA  STRDL                    ; L<data>:
        JSR  EMITLBL
        LDP1 #MDQASC                  ; "        .asciiz \""
        JSR  EMIT
        LDP1 #STRBUF                  ; the text
        JSR  EMIT
        LDP1 #MDQCL                   ; closing quote + LF
        JSR  EMIT
        LDP1 #MBYTE0                  ; extra pad 0
        JSR  EMIT
        LDA  STRSL                    ; L<skip>:
        JSR  EMITLBL
        LDP1 #MLDALL                  ; __ax = &L<data>
        JSR  EMIT
        LDA  STRDL
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MSTAX
        JSR  EMIT
        LDP1 #MLDAHL
        JSR  EMIT
        LDA  STRDL
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MSTAXH
        JSR  EMIT
        JSR  ADVANCE
        RTS
gf_id:  JSR  CPIDNAME                ; save the id; it may be a call or a variable
        JSR  SYMFIND                 ; variable candidate (from TID)
        LDA  SYMOK
        STA  IDVAROK
        LDA  SYMIDX
        STA  IDVARIDX
        LDA  SYMRCH
        STA  IDVARCH
        LDA  SYMRAR
        STA  IDVARAR
        JSR  ADVANCE                 ; past the id
        LDA  CURK
        LDB  #3
        CMP
        JNZ  gfi_var
        LDA  CURV
        LDB  #'('
        CMP
        JZ   gfi_call
        LDA  CURV
        LDB  #'['
        CMP
        JZ   gfi_index
        LDA  CUR2                    ; NAME.m ?
        JNZ  gfi_ck_arrow
        LDA  CURV
        LDB  #'.'
        CMP
        JZ   gfi_dot
        JMP  gfi_ckpp
gfi_ck_arrow: LDA CURV               ; NAME->m ?  (CURV='-', CUR2='>')
        LDB  #'-'
        CMP
        JNZ  gfi_ckpp
        LDA  CUR2
        LDB  #'>'
        CMP
        JZ   gfi_arrow
gfi_ckpp: LDA CUR2                   ; NAME++ / NAME-- (postfix, simple var)
        JZ   gfi_var
        LDA  CURV
        LDB  #'+'
        CMP
        JZ   gfi_pinc
        LDA  CURV
        LDB  #'-'
        CMP
        JZ   gfi_pdec
gfi_var: LDA IDVAROK
        JZ   gf_err
        LDA  IDVARIDX
        STA  SYMIDX
        LDA  IDVARCH
        STA  EXPRCHAR
        LDA  IDVARAR                 ; a bare array name decays to &name[0]
        JNZ  gfv_arr
        JSR  EM_LDVAR
        RTS
gfv_arr: LDA #1
        STA  SAWADDRG                 ; array decay passes an address (pass-by-ref)
        JSR  EM_ADDROF
        RTS
gfi_dot: LDA IDVARIDX               ; NAME.member : &NAME + offset
        STA  SYMIDX
        JSR  EM_ADDROF
        JMP  gfi_memld
gfi_arrow: LDA IDVARIDX              ; NAME->member : value(NAME) + offset
        STA  SYMIDX
        JSR  EM_LDVAR
gfi_memld: JSR ADVANCE               ; past '.' or '->'
        JSR  STMFIND
        LDA  STMEMOFF
        JSR  EM_ADDOFF
        JSR  ADVANCE                 ; past member name
        LDA  STMEMCH
        JNZ  gfi_memb
        JSR  EM_LOADW
        RTS
gfi_memb: JSR EM_LOADB
        RTS
gfi_pinc: LDA IDVAROK               ; NAME++ : value = old NAME, then NAME += 1
        JZ   gf_err
        LDA  IDVARIDX
        STA  SYMIDX
        JSR  EM_LDVAR                 ; __ax = old NAME
        JSR  EM_INCVAR                ; NAME += 1 (in place, __ax kept)
        JSR  ADVANCE
        RTS
gfi_pdec: LDA IDVAROK
        JZ   gf_err
        LDA  IDVARIDX
        STA  SYMIDX
        JSR  EM_LDVAR
        JSR  EM_DECVAR
        JSR  ADVANCE
        RTS
gfi_index: LDA IDVARIDX               ; NAME[index] rvalue
        STA  SYMIDX
        LDA  IDVARCH
        STA  ELCHAR
        LDA  IDVARAR
        STA  ELARR
        JSR  ELEMADDR                 ; __ax = element address
        LDA  ELCHAR
        JNZ  gfx_b
        JSR  EM_LOADW
        RTS
gfx_b:  JSR  EM_LOADB
        RTS
; puts(s): print the string + a newline
gc_puts: JSR ADVANCE
        JSR  GEXPR
        LDA  #')'
        JSR  EXPECTP
        LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MTAP1L
        JSR  EMIT
        LDP1 #MLDAXH
        JSR  EMIT
        LDP1 #MTAP1H
        JSR  EMIT
        LDP1 #MPUTS
        JSR  EMIT
        LDP1 #MPUTNL
        JSR  EMIT
        RTS

; getchar(): next stdin byte -> __ax, or 0xFFFF at EOF
gc_getc: JSR ADVANCE
        LDA  #')'
        JSR  EXPECTP
        LDP1 #MGETC
        JSR  EMIT
        JSR  NEWLBL
        STA  JLBL
        LDP1 #MJNC
        LDA  JLBL
        JSR  EMITJ
        LDP1 #MGETCEOF
        JSR  EMIT
        LDA  JLBL
        JSR  EMITLBL
        RTS

; peek(addr): byte at addr -> __ax
gc_peek: JSR ADVANCE
        JSR  GEXPR
        LDA  #')'
        JSR  EXPECTP
        JSR  EM_LOADB
        RTS

; poke(addr, val): store val's low byte at addr
gc_poke: JSR ADVANCE
        JSR  GEXPR
        JSR  EM_PUSH
        LDA  #','
        JSR  EXPECTP
        JSR  GEXPR
        JSR  EM_POP
        JSR  EM_STOREB
        LDA  #')'
        JSR  EXPECTP
        RTS

; argstr(): the program's argument tail (P2) -> __ax  (a char*)
gc_argstr: JSR ADVANCE
        LDA  #')'
        JSR  EXPECTP
        LDP1 #MARGSTR
        JSR  EMIT
        RTS

; gc_bios: bios(ADDR, p1, a) -> A | carry<<8 in __ax.  ADDR is a constant.
gc_bios: JSR ADVANCE                 ; past '('
        LDA  CURV                    ; arg0 = the constant BIOS/OS address
        STA  BIOSAD
        LDA  CURV+1
        STA  BIOSAD+1
        JSR  ADVANCE                 ; past the address number
        LDA  #','
        JSR  EXPECTP
        JSR  GEXPR                   ; arg1 (P1 operand) -> __ax
        JSR  EM_PUSH
        LDA  #','
        JSR  EXPECTP
        JSR  GEXPR                   ; arg2 (A operand) -> __ax
        LDA  #')'
        JSR  EXPECTP
        JSR  EM_POP                  ; __t0 = the P1 operand
        LDP1 #MLDT0
        JSR  EMIT
        LDP1 #MTAP1L
        JSR  EMIT
        LDP1 #MLDT0H
        JSR  EMIT
        LDP1 #MTAP1H
        JSR  EMIT
        LDP1 #MLDAX
        JSR  EMIT
        LDP1 #MJSRHEX                ; "        JSR $"
        JSR  EMIT
        LDA  BIOSAD+1
        JSR  EMHEX
        LDA  BIOSAD
        JSR  EMHEX
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MSTAX                  ; returned A -> __ax low
        JSR  EMIT
        JSR  NEWLBL
        STA  JLBL
        LDP1 #MLDA0                  ; carry -> __ax high  (LDA keeps C)
        JSR  EMIT
        LDP1 #MJNC
        LDA  JLBL
        JSR  EMITJ
        LDP1 #MLDA1
        JSR  EMIT
        LDA  JLBL
        JSR  EMITLBL
        LDP1 #MSTAXH
        JSR  EMIT
        RTS

; IDNAMEEQ: P1 = a NUL-terminated string -> TMPB = 1 if it equals IDNAME.
IDNAMEEQ: LDA #<IDNAME
        TAP2L
        LDA  #>IDNAME
        TAP2H
ine_l:  LDA  (P1)
        STA  TMPC
        LDA  (P2)
        LDB  TMPC
        CMP
        JNZ  ine_no
        LDA  (P1)
        JZ   ine_yes
        INP1
        INP2
        JMP  ine_l
ine_no: LDA #0
        STA  TMPB
        RTS
ine_yes: LDA #1
        STA  TMPB
        RTS

; EMNIB / EMHEX: emit a nibble / byte as hex digit(s)
EMNIB:  LDB #10
        CMP
        JC   en_af
        LDB  #'0'
        ADD
        JSR  SYS_PUTC
        RTS
en_af:  LDB #10
        SUB
        LDB  #'A'
        ADD
        JSR  SYS_PUTC
        RTS
EMHEX:  STA TMPC
        SHR
        SHR
        SHR
        SHR
        JSR  EMNIB
        LDA  TMPC
        LDB  #$0F
        AND
        JSR  EMNIB
        RTS

M_BIOS:  .asciiz "bios"
M_PUTS:  .asciiz "puts"
M_GETC:  .asciiz "getchar"
M_PEEK:  .asciiz "peek"
M_POKE:  .asciiz "poke"
M_ARGSTR: .asciiz "argstr"
MPUTS:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR $400F"
        .byte LF,0
MPUTNL:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA #10"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR $4009"
        .byte LF,0
MGETC:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR $400C"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __ax"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA #0"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __ax+1"
        .byte LF,0
MGETCEOF:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA #255"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __ax"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __ax+1"
        .byte LF,0
MARGSTR:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "TPA2L"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __ax"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "TPA2H"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __ax+1"
        .byte LF,0
MJSRHEX: .byte $20,$20,$20,$20,$20,$20,$20,$20
         .asciiz "JSR $"

gfi_call: LDP1 #M_BIOS             ; builtins: bios / puts / getchar / peek /
        JSR  IDNAMEEQ                ;   poke / argstr
        LDA  TMPB
        JNZ  gc_bios
        LDP1 #M_PUTS
        JSR  IDNAMEEQ
        LDA  TMPB
        JNZ  gc_puts
        LDP1 #M_GETC
        JSR  IDNAMEEQ
        LDA  TMPB
        JNZ  gc_getc
        LDP1 #M_PEEK
        JSR  IDNAMEEQ
        LDA  TMPB
        JNZ  gc_peek
        LDP1 #M_POKE
        JSR  IDNAMEEQ
        LDA  TMPB
        JNZ  gc_poke
        LDP1 #M_ARGSTR
        JSR  IDNAMEEQ
        LDA  TMPB
        JNZ  gc_argstr
        JSR  FFIND_ID              ; FI = callee index (name for the JSR)
        LDA  FI                      ; save across arg parsing (FI/IDNAME get reused)
        PHA
        LDA  #0
        STA  SAWADDRG                ; did any argument take an address? (pass-by-ref)
        JSR  ADVANCE                 ; past '('
        LDA  #0
        STA  ARGI
        LDA  CURK
        LDB  #3
        CMP
        JNZ  ga_loop
        LDA  CURV
        LDB  #')'
        CMP
        JZ   ga_done
ga_loop: LDA ARGI                    ; save ARGI across GEXPR (nested calls reuse it)
        PHA
        JSR  GEXPR                   ; arg value -> __ax
        PLA
        STA  ARGI
        JSR  EM_PUSHARG              ; push __ax onto the runtime arg stack
        LDA  ARGI
        INC
        STA  ARGI
        LDA  CURK
        LDB  #3
        CMP
        JNZ  ga_done
        LDA  CURV
        LDB  #','
        CMP
        JNZ  ga_done
        JSR  ADVANCE                 ; past ','
        JMP  ga_loop
ga_done: LDA #')'
        JSR  EXPECTP
        LDA  SAWADDRG                ; caller-save the live slots (re-entrancy) unless
        JNZ  gc_nosave               ; a &local was passed (then the callee writes it)
        JSR  EM_SAVESLOTS
gc_nosave: LDP1 #MJSRF               ; JSR _f_NAME   (result -> __ax)
        JSR  EMIT
        PLA                          ; restore callee index
        STA  FI
        JSR  EMITFNAME               ; emit the callee's name from FPOOL[FI]
        LDP1 #MNL
        JSR  EMIT
        LDA  SAWADDRG
        JNZ  gc_norest
        JSR  EM_RESTSLOTS            ; restore caller's slots (result stays in __ax)
gc_norest: RTS
gf_err: RTS

; CHKSELFREC: SELFREC = 1 if IDNAME (callee) equals CURFN (current function).
CHKSELFREC: LDA #<IDNAME
        TAP1L
        LDA  #>IDNAME
        TAP1H
        LDA  #<CURFN
        TAP2L
        LDA  #>CURFN
        TAP2H
        LDA  #1
        STA  SELFREC
csr_l:  LDA  (P1)
        STA  TMPC
        LDA  (P2)
        LDB  TMPC
        CMP
        JNZ  csr_no
        LDA  (P1)
        JZ   csr_d
        INP1
        INP2
        JMP  csr_l
csr_no: LDA  #0
        STA  SELFREC
csr_d:  RTS

; EMITFNAME: emit the FI-th NUL-terminated name from the packed FPOOL.
EMITFNAME: LDA #<FPOOL
        TAP1L
        LDA  #>FPOOL
        TAP1H
        LDA  FI
        STA  VITER2                  ; names to skip
efn_sk: LDA  VITER2
        JZ   efn_go
efn_s1: LDA  (P1)                    ; walk past one name + its NUL
        INP1
        JNZ  efn_s1
        LDA  VITER2
        DEC
        STA  VITER2
        JMP  efn_sk
efn_go: JSR  EMIT                    ; P1 -> the FI-th name; emit it
        RTS

; --- caller-saved slots: make static local storage re-entrant (recursion) ---
; EM_SAVESLOTS: emit runtime pushes of the current function's live slots
;   V<SLOTBASE .. SLOTBASE+SYMCNT-1>, low then high, in ascending order.
EM_SAVESLOTS: LDA #0
        STA  VITER3
ess_l:  LDA  VITER3
        LDB  NLSLOT
        CMP
        JC   ess_d                   ; VITER3 >= SYMCNT -> done
        LDA  SLOTBASE
        LDB  VITER3
        ADD
        JSR  EM_PUSHSLOT
        LDA  VITER3
        INC
        STA  VITER3
        JMP  ess_l
ess_d:  RTS

; EM_RESTSLOTS: emit runtime pops in reverse (slot SYMCNT-1 .. 0).
EM_RESTSLOTS: LDA NLSLOT
        JZ   ers_d
        STA  VITER3
ers_l:  LDA  VITER3
        DEC
        STA  VITER3
        LDA  SLOTBASE
        LDB  VITER3
        ADD
        JSR  EM_POPSLOT
        LDA  VITER3
        JZ   ers_d                   ; just handled slot 0
        JMP  ers_l
ers_d:  RTS

; EM_PUSHSLOT (A = slot number): emit  LDA V<n> / PHA / LDA V<n>+1 / PHA
EM_PUSHSLOT: STA VITER2
        LDP1 #MLDAV
        JSR  EMIT
        LDA  VITER2
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        LDP1 #MPHA
        JSR  EMIT
        LDP1 #MLDAV
        JSR  EMIT
        LDA  VITER2
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        LDP1 #MPHA
        JSR  EMIT
        RTS

; EM_POPSLOT (A = slot number): emit  PLA / STA V<n>+1 / PLA / STA V<n>
EM_POPSLOT: STA VITER2
        LDP1 #MPLA
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  VITER2
        JSR  EMITNUM
        LDP1 #MP1
        JSR  EMIT
        LDP1 #MPLA
        JSR  EMIT
        LDP1 #MSTAV
        JSR  EMIT
        LDA  VITER2
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        RTS

; =============================================================================
; Symbol table - each declared variable maps to an index (emitted as V<index>).
; Names are packed NUL-terminated in SYMPOOL; SYMCNT counts them.
; =============================================================================
; SYMFIND: search SYMPOOL for the current id (TID). SYMOK=1 & SYMIDX=index if
;          found, else SYMOK=0.
SYMFIND: LDA #0
        STA  SYMIDX
        STA  SYMOK
        LDA  #<SYMPOOL
        TAP1L
        LDA  #>SYMPOOL
        TAP1H
sf_e:   LDA  SYMIDX
        LDB  SYMCNT
        CMP
        JC   sf_no                   ; SYMIDX >= SYMCNT -> not found
        LDA  #<TID
        TAP2L
        LDA  #>TID
        TAP2H
sf_c:   LDA  (P1)                    ; pool char vs TID char
        STA  TMPC
        LDA  (P2)
        LDB  TMPC
        CMP
        JNZ  sf_nx
        LDA  (P1)
        JZ   sf_yes                  ; equal and both at NUL -> match
        INP1
        INP2
        JMP  sf_c
sf_nx:  LDA  (P1)                    ; skip the rest of this pool name + its NUL
        JZ   sf_np
        INP1
        JMP  sf_nx
sf_np:  INP1
        LDA  SYMIDX
        INC
        STA  SYMIDX
        JMP  sf_e
sf_yes: LDA  #1
        STA  SYMOK
        LDA  SYMIDX                   ; SYMIDX walked as the name index; map -> slot
        JSR  GSYMSLOT
        STA  SYMIDX
        JSR  GSYMCHAR                 ; resolve the char/array flags for the caller
        STA  SYMRCH
        LDA  SYMIDX
        JSR  GSYMARR
        STA  SYMRAR
        RTS
sf_no:  JMP  GSYMFIND                 ; not a local -> try the globals

; SYMADD: append the current id (TID) to SYMPOOL; SYMIDX = its (new) index.
SYMADD: LDA #<SYMPOOL
        TAP1L
        LDA  #>SYMPOOL
        TAP1H
        LDA  #0
        STA  TMPB                    ; names skipped
sa_e:   LDA  TMPB
        LDB  SYMCNT
        CMP
        JC   sa_ap                   ; skipped SYMCNT names -> at the append point
sa_sk:  LDA  (P1)
        JZ   sa_np
        INP1
        JMP  sa_sk
sa_np:  INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  sa_e
sa_ap:  LDA  #<TID                   ; copy TID (+ its NUL) into the pool
        TAP2L
        LDA  #>TID
        TAP2H
sa_cp:  LDA  (P2)
        STA  (P1)
        JZ   sa_dn
        INP1
        INP2
        JMP  sa_cp
sa_dn:  LDA  #<SYMSLOT                ; SYMSLOT[SYMCNT] = NLSLOT (name -> slot)
        LDB  SYMCNT
        ADD
        TAP1L
        LDA  #>SYMSLOT
        JNC  sad1
        INC
sad1:   TAP1H
        LDA  NLSLOT
        STA  (P1)
        LDA  #<SYMARR                 ; SYMARR[NLSLOT] = 0 (scalar by default)
        LDB  NLSLOT
        ADD
        TAP1L
        LDA  #>SYMARR
        JNC  sad2
        INC
sad2:   TAP1H
        LDA  #0
        STA  (P1)
        LDA  NLSLOT                   ; SYMIDX = the slot; bump slot + name counts
        STA  SYMIDX
        INC
        STA  NLSLOT
        LDA  SYMCNT
        INC
        STA  SYMCNT
        RTS

; GSYMFIND: search the GLOBAL table for TID. Sets SYMOK; on a hit, SYMIDX =
;   (global slot - SLOTBASE) so V<SLOTBASE+SYMIDX> lands on the fixed slot, and
;   SYMRCH/SYMRAR carry its char/array flags.
GSYMFIND: LDA #<GSYMPOOL
        TAP1L
        LDA  #>GSYMPOOL
        TAP1H
        LDA  #0
        STA  TMPB
gsf_e:  LDA  TMPB
        LDB  GSYMCNT
        CMP
        JC   gsf_no
        LDA  #<TID
        TAP2L
        LDA  #>TID
        TAP2H
gsf_c:  LDA  (P1)
        STA  TMPC
        LDA  (P2)
        LDB  TMPC
        CMP
        JNZ  gsf_nx
        LDA  (P1)
        JZ   gsf_yes
        INP1
        INP2
        JMP  gsf_c
gsf_nx: LDA  (P1)
        JZ   gsf_np
        INP1
        JMP  gsf_nx
gsf_np: INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  gsf_e
gsf_yes: LDA #1
        STA  SYMOK
        LDA  #<GVSLOT
        LDB  TMPB
        ADD
        TAP1L
        LDA  #>GVSLOT
        JNC  gsy1
        INC
gsy1:   TAP1H
        LDA  (P1)
        LDB  SLOTBASE
        SUB
        STA  SYMIDX
        LDA  #<GSYMCH
        LDB  TMPB
        ADD
        TAP1L
        LDA  #>GSYMCH
        JNC  gsy2
        INC
gsy2:   TAP1H
        LDA  (P1)
        STA  SYMRCH
        LDA  #<GSYMAR
        LDB  TMPB
        ADD
        TAP1L
        LDA  #>GSYMAR
        JNC  gsy3
        INC
gsy3:   TAP1H
        LDA  (P1)
        STA  SYMRAR
        RTS
gsf_no: LDA #0
        STA  SYMOK
        RTS

; GSYMADD: append CURFN to the global table at slot SLOTCNT (char = DCLCHAR).
GSYMADD: LDA #<GSYMPOOL
        TAP1L
        LDA  #>GSYMPOOL
        TAP1H
        LDA  #0
        STA  TMPB
gA_e:   LDA  TMPB
        LDB  GSYMCNT
        CMP
        JC   gA_ap
gA_sk:  LDA  (P1)
        JZ   gA_np
        INP1
        JMP  gA_sk
gA_np:  INP1
        LDA  TMPB
        INC
        STA  TMPB
        JMP  gA_e
gA_ap:  LDA #<CURFN
        TAP2L
        LDA  #>CURFN
        TAP2H
gA_cp:  LDA  (P2)
        STA  (P1)
        JZ   gA_dn
        INP1
        INP2
        JMP  gA_cp
gA_dn:  LDA #<GVSLOT
        LDB  GSYMCNT
        ADD
        TAP1L
        LDA  #>GVSLOT
        JNC  gAd1
        INC
gAd1:   TAP1H
        LDA  SLOTCNT
        STA  (P1)
        LDA  #<GSYMCH
        LDB  GSYMCNT
        ADD
        TAP1L
        LDA  #>GSYMCH
        JNC  gAd2
        INC
gAd2:   TAP1H
        LDA  DCLCHAR
        STA  (P1)
        LDA  #<GSYMAR
        LDB  GSYMCNT
        ADD
        TAP1L
        LDA  #>GSYMAR
        JNC  gAd3
        INC
gAd3:   TAP1H
        LDA  #0
        STA  (P1)
        LDA  GSYMCNT
        INC
        STA  GSYMCNT
        RTS

; GSYMMARKARR: mark the most-recently-added global (GSYMCNT-1) as an array.
GSYMMARKARR: LDA #<GSYMAR
        LDB  GSYMCNT
        ADD
        TAP1L
        LDA  #>GSYMAR
        JNC  gma1
        INC
gma1:   TAP1H
        DEP1
        LDA  #1
        STA  (P1)
        RTS

; GSYMSLOT (A = name index) -> A = that name's slot (SYMSLOT[A])
GSYMSLOT: STA TMPC
        LDA  #<SYMSLOT
        LDB  TMPC
        ADD
        TAP1L
        LDA  #>SYMSLOT
        JNC  gss1
        INC
gss1:   TAP1H
        LDA  (P1)
        RTS

; GSYMARR (A = slot) -> A = 1 if that slot is an array base, else 0
GSYMARR: STA TMPC
        LDA  #<SYMARR
        LDB  TMPC
        ADD
        TAP1L
        LDA  #>SYMARR
        JNC  gsa1
        INC
gsa1:   TAP1H
        LDA  (P1)
        RTS

; =============================================================================
; Comparisons + labels (for relational operators and if/while)
; =============================================================================
; RELDET: is the current punct token a relational operator? RELF=1 and RELOP set
;         (0 LT, 1 LE, 2 GT, 3 GE, 4 EQ, 5 NE), else RELF=0. Does not advance.
RELDET: LDA #0
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
rd_l:   LDA  CUR2                    ; '<' or '<='
        LDB  #'='
        CMP
        JZ   rd_le
        LDA  #0
        STA  RELOP
        JMP  rd_ok
rd_le:  LDA  #1
        STA  RELOP
        JMP  rd_ok
rd_g:   LDA  CUR2                    ; '>' or '>='
        LDB  #'='
        CMP
        JZ   rd_ge
        LDA  #2
        STA  RELOP
        JMP  rd_ok
rd_ge:  LDA  #3
        STA  RELOP
        JMP  rd_ok
rd_e:   LDA  CUR2                    ; only '==' is relational ('=' is assignment)
        LDB  #'='
        CMP
        JNZ  rd_no
        LDA  #4
        STA  RELOP
        JMP  rd_ok
rd_x:   LDA  CUR2                    ; '!='
        LDB  #'='
        CMP
        JNZ  rd_no
        LDA  #5
        STA  RELOP
rd_ok:  LDA  #1
        STA  RELF
rd_no:  RTS

; EMITCMP: given a preceding CMP (left-right, setting C=left>=right and Z=equal),
;          emit code leaving 0/1 in A per RELOP.  The conditional branch must come
;          BEFORE any LDA — an LDA clobbers Z (though not C), which would destroy
;          the comparison result.  Two fresh labels: la (branch target), lb (end).
EMITCMP: JSR NEWLBL
        STA  LBLA
        JSR  NEWLBL
        STA  LBLB
        LDA  RELOP
        LDB  #0
        CMP
        JZ   ec_lt
        LDB  #1
        CMP
        JZ   ec_le
        LDB  #2
        CMP
        JZ   ec_gt
        LDB  #3
        CMP
        JZ   ec_ge
        LDB  #4
        CMP
        JZ   ec_eq
        JMP  ec_ne
; simple ops: one conditional jump (on the CMP flags) to la=TRUE, else fall to 0.
ec_lt:  LDP1 #MJNC                   ; a<b : true when C=0
        LDA  LBLA
        JSR  EMITJ
        JMP  ec_t
ec_ge:  LDP1 #MJC                    ; a>=b : true when C=1
        LDA  LBLA
        JSR  EMITJ
        JMP  ec_t
ec_eq:  LDP1 #MJZ                    ; a==b : true when Z=1
        LDA  LBLA
        JSR  EMITJ
        JMP  ec_t
ec_ne:  LDP1 #MJNZ                   ; a!=b : true when Z=0
        LDA  LBLA
        JSR  EMITJ
        JMP  ec_t
ec_t:   JSR  EM_AX0                  ; false path, then jump over the true value
        LDP1 #MJMP
        LDA  LBLB
        JSR  EMITJ
        LDA  LBLA                    ; la: (true)
        JSR  EMITLBL
        JSR  EM_AX1
        JMP  ec_end
ec_gt:  LDP1 #MJZ                    ; a>b : false when Z=1 (eq) or C=0 (a<b)
        LDA  LBLA
        JSR  EMITJ
        LDP1 #MJNC
        LDA  LBLA
        JSR  EMITJ
        JSR  EM_AX1                  ; a>b -> true
        LDP1 #MJMP
        LDA  LBLB
        JSR  EMITJ
        LDA  LBLA                    ; la: (false)
        JSR  EMITLBL
        JSR  EM_AX0
        JMP  ec_end
ec_le:  LDP1 #MJZ                    ; a<=b : true when Z=1 (eq) or C=0 (a<b)
        LDA  LBLA
        JSR  EMITJ
        LDP1 #MJNC
        LDA  LBLA
        JSR  EMITJ
        JSR  EM_AX0                  ; a>b -> false
        LDP1 #MJMP
        LDA  LBLB
        JSR  EMITJ
        LDA  LBLA                    ; la: (true)
        JSR  EMITLBL
        JSR  EM_AX1
ec_end: LDA  LBLB                    ; lb: (end)
        JSR  EMITLBL
        RTS

; NEWLBL: A = a fresh label number; bump the counter.
NEWLBL: LDA LBLCNT
        STA  TMPC
        INC
        STA  LBLCNT
        LDA  TMPC
        RTS
; EMITJ: emit a jump (P1 = "... L" prefix) to the label number in A + newline.
EMITJ:  STA JLBL
        JSR  EMIT
        LDA  JLBL
        JSR  EMITNUM
        LDP1 #MNL
        JSR  EMIT
        RTS
; EMITLBL: emit  "L<A>:"  + newline (a label definition at column 0).
EMITLBL: STA JLBL
        LDP1 #MLBP
        JSR  EMIT
        LDA  JLBL
        JSR  EMITNUM
        LDP1 #MLBC
        JSR  EMIT
        RTS

; EXPECTP: current token must be punct char A, else quietly stop; then ADVANCE.
EXPECTP: STA TMPB
        LDA  CURK
        LDB  #3
        CMP
        JNZ  ep_ret
        LDA  CUR2                    ; a single-char punct only (not ==, <=, ...)
        JNZ  ep_ret
        LDA  CURV
        LDB  TMPB
        CMP
        JNZ  ep_ret
        JSR  ADVANCE
ep_ret: RTS

; EXPECTID: current token must be the identifier at P1, then ADVANCE.
; EXPECTTYPE: accept the type keyword 'int' or 'char' (advance past it).
EXPECTTYPE: LDP1 #KW_INT
        JSR  IDEQ
        LDA  TMPB
        JZ   ett_c
        LDA  #0
        STA  ISCHARTYPE
        JMP  ett_ok
ett_c:  LDP1 #KW_CHAR
        JSR  IDEQ
        LDA  TMPB
        JZ   ett_no
        LDA  #1
        STA  ISCHARTYPE
ett_ok: JSR  ADVANCE
        LDA  #1
        STA  TMPB
        RTS
ett_no: LDA  #0
        STA  TMPB
        RTS

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
KW_CHAR: .asciiz "char"
KW_MAIN: .asciiz "main"
KW_PUTC: .asciiz "putchar"
KW_RET:  .asciiz "return"
KW_IF:   .asciiz "if"
KW_WHILE: .asciiz "while"
KW_ELSE: .asciiz "else"
KW_FOR:  .asciiz "for"
KW_STRUCT: .asciiz "struct"
KW_BRK:  .asciiz "break"
KW_CONT: .asciiz "continue"

; whole-line mnemonics end with LF (8-space indent + text + newline)
MORG:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii ".org $7A00"
        .byte LF,0
MLDAI:  .byte $20,$20,$20,$20,$20,$20,$20,$20   ; prefix: a number + MNL follow
        .asciiz "LDA #"
MLDAV:  .byte $20,$20,$20,$20,$20,$20,$20,$20   ; prefix: "LDA V" + index + MNL
        .asciiz "LDA V"
MSTAV:  .byte $20,$20,$20,$20,$20,$20,$20,$20   ; prefix: "STA V" + index + MNL
        .asciiz "STA V"
MBOOT:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA #<__cstktop"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __sp"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA #>__cstktop"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __sp+1"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR _f_main"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "RTS"
        .byte LF,0
MPUSHARG: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __pusharg"
        .byte LF,0
MPOP:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __pop"
        .byte LF,0
MFPFX:  .asciiz "_f_"
MEPFX:  .asciiz "_e_"
MJSRF:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JSR _f_"
MJMPE:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JMP _e_"
MCOLON: .ascii ":"
        .byte LF,0
MVL:    .asciiz "V"                             ; a variable's storage label prefix
MVF:    .ascii ":   .word 0"
        .byte LF,0
MNL:    .byte LF,0
MSTAX:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __ax"
        .byte LF,0
MSTAXH: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __ax+1"
        .byte LF,0
MLDAX:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA __ax"
        .byte LF,0
MLDAXH: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA __ax+1"
        .byte LF,0
MLDBXH: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDB __ax+1"
        .byte LF,0
MOR:    .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "OR"
        .byte LF,0
MSTT0H: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA __t0+1"
        .byte LF,0
MP1:    .ascii "+1"
        .byte LF,0
MVWORD: .ascii ":   .word 0"
        .byte LF,0
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
MLDB1:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDB #1"
        .byte LF,0
MADDOP:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "ADD"
        .byte LF,0
MSUBOP:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "SUB"
        .byte LF,0
MINCOP:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "INC"
        .byte LF,0
MDECOP:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "DEC"
        .byte LF,0
MJSHL:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __shl"
        .byte LF,0
MJSHR:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __shr"
        .byte LF,0
MJAND:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __and"
        .byte LF,0
MJOR:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __or"
        .byte LF,0
MJXOR:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __xor"
        .byte LF,0
MADD:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __add"
        .byte LF,0
MSUB:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __sub"
        .byte LF,0
MPUTC:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA __ax"
        .byte LF
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR $4009"
        .byte LF,0
MRTS:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "RTS"
        .byte LF,0
MCMP:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __cmp"
        .byte LF,0
MMUL:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __mul"
        .byte LF,0
; the 8-bit multiply runtime helper (A * __t0 -> A), emitted once if '*' is used
MMULDEF:
        .ascii "__mul:  LDA #0"
        .byte LF
        .ascii "        STA __mr"
        .byte LF
        .ascii "        STA __mr+1"
        .byte LF
        .ascii "__mu0:  LDA __ax"
        .byte LF
        .ascii "        LDB __ax+1"
        .byte LF
        .ascii "        OR"
        .byte LF
        .ascii "        JZ __mu2"
        .byte LF
        .ascii "        LDA __mr"
        .byte LF
        .ascii "        LDB __t0"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        STA __mr"
        .byte LF
        .ascii "        LDA #0"
        .byte LF
        .ascii "        JNC __mu1"
        .byte LF
        .ascii "        LDA #1"
        .byte LF
        .ascii "__mu1:  STA __c"
        .byte LF
        .ascii "        LDA __mr+1"
        .byte LF
        .ascii "        LDB __t0+1"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        LDB __c"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        STA __mr+1"
        .byte LF
        .ascii "        LDA __ax"
        .byte LF
        .ascii "        LDB #1"
        .byte LF
        .ascii "        SUB"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        JC __mu0"
        .byte LF
        .ascii "        LDA __ax+1"
        .byte LF
        .ascii "        DEC"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        JMP __mu0"
        .byte LF
        .ascii "__mu2:  LDA __mr"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA __mr+1"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF
        .ascii "__mr:   .fill 2"
        .byte LF,0
MDIV:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __div"
        .byte LF,0
MMOD:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __mod"
        .byte LF,0
; the 8-bit divide/modulo helper (A / __t0 -> __d1 quotient, __d0 remainder)
MDMDEF:
        .ascii "__div:  JSR __divmod"
        .byte LF
        .ascii "        LDA __dq"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA __dq+1"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF
        .ascii "__mod:  JSR __divmod"
        .byte LF
        .ascii "        LDA __dr"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA __dr+1"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF
        .ascii "__divmod: LDA __t0"
        .byte LF
        .ascii "        STA __dr"
        .byte LF
        .ascii "        LDA __t0+1"
        .byte LF
        .ascii "        STA __dr+1"
        .byte LF
        .ascii "        LDA #0"
        .byte LF
        .ascii "        STA __dq"
        .byte LF
        .ascii "        STA __dq+1"
        .byte LF
        .ascii "        LDA __ax"
        .byte LF
        .ascii "        LDB __ax+1"
        .byte LF
        .ascii "        OR"
        .byte LF
        .ascii "        JZ __dm2"
        .byte LF
        .ascii "__dm0:  LDA __dr+1"
        .byte LF
        .ascii "        LDB __ax+1"
        .byte LF
        .ascii "        CMP"
        .byte LF
        .ascii "        JNZ __dm3"
        .byte LF
        .ascii "        LDA __dr"
        .byte LF
        .ascii "        LDB __ax"
        .byte LF
        .ascii "        CMP"
        .byte LF
        .ascii "__dm3:  JNC __dm2"
        .byte LF
        .ascii "        LDA __dr"
        .byte LF
        .ascii "        LDB __ax"
        .byte LF
        .ascii "        SUB"
        .byte LF
        .ascii "        STA __dr"
        .byte LF
        .ascii "        LDA #0"
        .byte LF
        .ascii "        JC __dm1"
        .byte LF
        .ascii "        LDA #1"
        .byte LF
        .ascii "__dm1:  STA __c"
        .byte LF
        .ascii "        LDA __dr+1"
        .byte LF
        .ascii "        LDB __ax+1"
        .byte LF
        .ascii "        SUB"
        .byte LF
        .ascii "        STA __dr+1"
        .byte LF
        .ascii "        LDA __c"
        .byte LF
        .ascii "        JZ __dm4"
        .byte LF
        .ascii "        LDA __dr+1"
        .byte LF
        .ascii "        DEC"
        .byte LF
        .ascii "        STA __dr+1"
        .byte LF
        .ascii "__dm4:  LDA __dq"
        .byte LF
        .ascii "        LDB #1"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        STA __dq"
        .byte LF
        .ascii "        JNC __dm0"
        .byte LF
        .ascii "        LDA __dq+1"
        .byte LF
        .ascii "        INC"
        .byte LF
        .ascii "        STA __dq+1"
        .byte LF
        .ascii "        JMP __dm0"
        .byte LF
        .ascii "__dm2:  RTS"
        .byte LF
        .ascii "__dq:   .fill 2"
        .byte LF
        .ascii "__dr:   .fill 2"
        .byte LF,0
MLDA0:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA #0"
        .byte LF,0
MLDA1:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA #1"
        .byte LF,0
MJC:    .byte $20,$20,$20,$20,$20,$20,$20,$20     ; jump prefixes: "JXX L" + num
        .asciiz "JC L"
MJNC:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JNC L"
MJZ:    .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JZ L"
MJNZ:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JNZ L"
MJMP:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "JMP L"
MLBP:   .asciiz "L"                              ; a label def: "L" + num + MLBC
MLBC:   .ascii ":"
        .byte LF,0
MTEMP:  .ascii "__t0:   .fill 2"
        .byte LF
        .ascii "__ax:   .fill 2"
        .byte LF
        .ascii "__c:    .fill 1"
        .byte LF
        .ascii "__sc:   .fill 1"
        .byte LF,0
MANDDEF:
        .ascii "__and:  LDA __ax"
        .byte LF
        .ascii "        LDB __t0"
        .byte LF
        .ascii "        AND"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA __ax+1"
        .byte LF
        .ascii "        LDB __t0+1"
        .byte LF
        .ascii "        AND"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF,0
MORDEF:
        .ascii "__or:  LDA __ax"
        .byte LF
        .ascii "        LDB __t0"
        .byte LF
        .ascii "        OR"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA __ax+1"
        .byte LF
        .ascii "        LDB __t0+1"
        .byte LF
        .ascii "        OR"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF,0
MXORDEF:
        .ascii "__xor:  LDA __ax"
        .byte LF
        .ascii "        LDB __t0"
        .byte LF
        .ascii "        XOR"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA __ax+1"
        .byte LF
        .ascii "        LDB __t0+1"
        .byte LF
        .ascii "        XOR"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF,0
MSHLDEF:
        .ascii "__shl:  LDA __ax"
        .byte LF
        .ascii "        STA __sc"
        .byte LF
        .ascii "__shl0:  LDA __sc"
        .byte LF
        .ascii "        JZ __shld"
        .byte LF
        .ascii "        LDA __t0"
        .byte LF
        .ascii "        SHL"
        .byte LF
        .ascii "        STA __t0"
        .byte LF
        .ascii "        LDA __t0+1"
        .byte LF
        .ascii "        ROL"
        .byte LF
        .ascii "        STA __t0+1"
        .byte LF
        .ascii "        LDA __sc"
        .byte LF
        .ascii "        DEC"
        .byte LF
        .ascii "        STA __sc"
        .byte LF
        .ascii "        JMP __shl0"
        .byte LF
        .ascii "__shld:  LDA __t0"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA __t0+1"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF,0
MSHRDEF:
        .ascii "__shr:  LDA __ax"
        .byte LF
        .ascii "        STA __sc"
        .byte LF
        .ascii "__shr0:  LDA __sc"
        .byte LF
        .ascii "        JZ __shrd"
        .byte LF
        .ascii "        LDA __t0+1"
        .byte LF
        .ascii "        SHR"
        .byte LF
        .ascii "        STA __t0+1"
        .byte LF
        .ascii "        LDA __t0"
        .byte LF
        .ascii "        ROR"
        .byte LF
        .ascii "        STA __t0"
        .byte LF
        .ascii "        LDA __sc"
        .byte LF
        .ascii "        DEC"
        .byte LF
        .ascii "        STA __sc"
        .byte LF
        .ascii "        JMP __shr0"
        .byte LF
        .ascii "__shrd:  LDA __t0"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA __t0+1"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF,0
MADD_DEF:
        .ascii "__add:  LDA __ax"
        .byte LF
        .ascii "        LDB __t0"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA #0"
        .byte LF
        .ascii "        JNC __ad0"
        .byte LF
        .ascii "        LDA #1"
        .byte LF
        .ascii "__ad0:  STA __c"
        .byte LF
        .ascii "        LDA __ax+1"
        .byte LF
        .ascii "        LDB __t0+1"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        LDB __c"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF,0
MSUB_DEF:
        .ascii "__sub:  LDA __t0"
        .byte LF
        .ascii "        LDB __ax"
        .byte LF
        .ascii "        SUB"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA #0"
        .byte LF
        .ascii "        JC __sb0"
        .byte LF
        .ascii "        LDA #1"
        .byte LF
        .ascii "__sb0:  STA __c"
        .byte LF
        .ascii "        LDA __t0+1"
        .byte LF
        .ascii "        LDB __ax+1"
        .byte LF
        .ascii "        SUB"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        LDA __c"
        .byte LF
        .ascii "        JZ __sb1"
        .byte LF
        .ascii "        LDA __ax+1"
        .byte LF
        .ascii "        DEC"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "__sb1:  RTS"
        .byte LF,0
MCMP_DEF:
        .ascii "__cmp:  LDA __t0+1"
        .byte LF
        .ascii "        LDB __ax+1"
        .byte LF
        .ascii "        CMP"
        .byte LF
        .ascii "        JNZ __cm0"
        .byte LF
        .ascii "        LDA __t0"
        .byte LF
        .ascii "        LDB __ax"
        .byte LF
        .ascii "        CMP"
        .byte LF
        .ascii "__cm0:  RTS"
        .byte LF,0
MDQASC: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .byte $2E,$61,$73,$63,$69,$69,$7A,$20,$22   ; .asciiz (space) "
        .byte 0
MDQCL:  .byte $22,LF,0                              ; closing quote + newline
MBYTE0: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii ".byte 0"
        .byte LF,0
MLDALL: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "LDA #<L"
MLDAHL: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "LDA #>L"
MSHL:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "SHL"
        .byte LF,0
MROL:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "ROL"
        .byte LF,0
MNEG:   .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __neg"
        .byte LF,0
MLNOT:  .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "JSR __lnot"
        .byte LF,0
MNEG_DEF:
        .ascii "__neg:  LDA __ax"
        .byte LF
        .ascii "        LDB #$FF"
        .byte LF
        .ascii "        XOR"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA __ax+1"
        .byte LF
        .ascii "        LDB #$FF"
        .byte LF
        .ascii "        XOR"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        LDA __ax"
        .byte LF
        .ascii "        LDB #1"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        JNC __ng0"
        .byte LF
        .ascii "        LDA __ax+1"
        .byte LF
        .ascii "        INC"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "__ng0:  RTS"
        .byte LF,0
MLNOT_DEF:
        .ascii "__lnot: LDA __ax"
        .byte LF
        .ascii "        LDB __ax+1"
        .byte LF
        .ascii "        OR"
        .byte LF
        .ascii "        JZ __ln1"
        .byte LF
        .ascii "        LDA #0"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF
        .ascii "__ln1:  LDA #1"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        LDA #0"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        RTS"
        .byte LF,0
MTAP1L:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "TAP1L"
        .byte LF,0
MTAP1H:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "TAP1H"
        .byte LF,0
MINP1:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "INP1"
        .byte LF,0
MLDP1:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA (P1)"
        .byte LF,0
MSTP1:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "STA (P1)"
        .byte LF,0
MLDT0:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA __t0"
        .byte LF,0
MLDT0H:
        .byte $20,$20,$20,$20,$20,$20,$20,$20
        .ascii "LDA __t0+1"
        .byte LF,0
MLDALV: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "LDA #<V"
MLDAHV: .byte $20,$20,$20,$20,$20,$20,$20,$20
        .asciiz "LDA #>V"
MFRAMEDEF:
        .ascii "__pusharg: LDA __sp"
        .byte LF
        .ascii "        LDB #2"
        .byte LF
        .ascii "        SUB"
        .byte LF
        .ascii "        STA __sp"
        .byte LF
        .ascii "        JC __pa1"
        .byte LF
        .ascii "        LDA __sp+1"
        .byte LF
        .ascii "        DEC"
        .byte LF
        .ascii "        STA __sp+1"
        .byte LF
        .ascii "__pa1:  LDA __sp"
        .byte LF
        .ascii "        TAP1L"
        .byte LF
        .ascii "        LDA __sp+1"
        .byte LF
        .ascii "        TAP1H"
        .byte LF
        .ascii "        LDA __ax"
        .byte LF
        .ascii "        STA (P1)"
        .byte LF
        .ascii "        INP1"
        .byte LF
        .ascii "        LDA __ax+1"
        .byte LF
        .ascii "        STA (P1)"
        .byte LF
        .ascii "        RTS"
        .byte LF
        .ascii "__pop:  LDA __sp"
        .byte LF
        .ascii "        TAP1L"
        .byte LF
        .ascii "        LDA __sp+1"
        .byte LF
        .ascii "        TAP1H"
        .byte LF
        .ascii "        LDA (P1)"
        .byte LF
        .ascii "        STA __ax"
        .byte LF
        .ascii "        INP1"
        .byte LF
        .ascii "        LDA (P1)"
        .byte LF
        .ascii "        STA __ax+1"
        .byte LF
        .ascii "        LDA __sp"
        .byte LF
        .ascii "        LDB #2"
        .byte LF
        .ascii "        ADD"
        .byte LF
        .ascii "        STA __sp"
        .byte LF
        .ascii "        JNC __pp1"
        .byte LF
        .ascii "        LDA __sp+1"
        .byte LF
        .ascii "        INC"
        .byte LF
        .ascii "        STA __sp+1"
        .byte LF
        .ascii "__pp1:  RTS"
        .byte LF
        .ascii "__sp:   .word 0"
        .byte LF
        .ascii "__cstack: .fill 2048"
        .byte LF
        .ascii "__cstktop:"
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
SYMCNT: .fill 1    ; number of declared variables
SYMIDX: .fill 1    ; SYMFIND/SYMADD result index
SYMOK:  .fill 1    ; SYMFIND: 1 if found
LHSIDX: .fill 1    ; index of an assignment/decl target variable
VITER:  .fill 1    ; loop counter emitting variable storage
VITER2: .fill 1    ; EM_PUSHSLOT/EM_POPSLOT: slot number being emitted
VITER3: .fill 1    ; EM_SAVESLOTS/EM_RESTSLOTS: slot loop counter
SELFREC: .fill 1   ; (unused since frames) was: direct self-recursion flag
SAWADDRG: .fill 1   ; 1 if an argument in the current call took an address
GSYMPOOL: .fill 256 ; packed global variable names
GVSLOT: .fill 48   ; per-global: its (absolute) storage slot
GSYMCH: .fill 48    ; per-global: char-typed flag
GSYMAR: .fill 48    ; per-global: array flag
GSYMCNT: .fill 1    ; number of globals
SYMRCH: .fill 1     ; SYMFIND/GSYMFIND result: char flag
SYMRAR: .fill 1     ; SYMFIND/GSYMFIND result: array flag
IDVARCH: .fill 1    ; gf_id: the variable's char flag
IDVARAR: .fill 1    ; gf_id: the variable's array flag
ELARR: .fill 1      ; ELEMADDR: 1 if the indexed base is an array (else pointer)
LHSCH: .fill 1      ; assignment target char flag
LHSAR: .fill 1      ; assignment target array flag
USESP:  .fill 1     ; //#use nesting depth (0 = main source)
USEDF:  .fill 1     ; USED_HAS result
USEDN:  .fill 1     ; number of spliced library names (dedup)
USECNT: .fill 1     ; save/restore byte counter
NAMEBUF: .fill 24   ; the current //#use library name
LIBPATH: .fill 40   ; "/lib/lib_<name>.c"
USED:   .fill 128   ; packed names of already-spliced libraries
USESTATE: .fill 70  ; saved read-stream state, 14 bytes x 5 levels
USEBUF: .fill 2560  ; per-level 512-byte read buffers (5 levels)
BIOSAD: .fill 2    ; bios() intrinsic: the constant call address
USEAND: .fill 1    ; 1 if binary & used
USEOR:  .fill 1    ; 1 if binary | used
USEXOR: .fill 1    ; 1 if binary ^ used
USESHL: .fill 1    ; 1 if << used
USESHR: .fill 1    ; 1 if >> used
TERNF:  .fill 1    ; ternary ?: false label
TERNE:  .fill 1    ; ternary ?: end label
INCLBL: .fill 1    ; ++/-- carry-skip label
STAGPOOL: .fill 128 ; struct tag names
STAGSIZE: .fill 16  ; per-tag size in bytes
STAGCNT: .fill 1
STMPOOL: .fill 256  ; struct member names (global, unique)
STMOFF: .fill 64    ; per-member byte offset
STMCH:  .fill 64    ; per-member char flag
STMCNT: .fill 1
STOFF:  .fill 1     ; running offset while defining a struct
TAGSIZE: .fill 1    ; STAGFIND result: tag size
STFNP:  .fill 2     ; STAGFIND name pointer
STMEMOK: .fill 1    ; STMFIND: found
STMEMOFF: .fill 1   ; STMFIND: member offset
STMEMCH: .fill 1    ; STMFIND: member char flag
MEMTMP: .fill 1     ; EM_ADDOFF scratch
MEMTMP2: .fill 1    ; member-store width across RHS
NLSLOT: .fill 1    ; current function's slot count (>= name count, arrays add N)
SYMSLOT: .fill 48  ; per-name -> first slot (relative to SLOTBASE)
SYMARR: .fill 256  ; per-slot: 1 if this slot is an array base
STRBUF: .fill 128  ; current string-literal text
STRDL:  .fill 1    ; string literal: data label
STRSL:  .fill 1    ; string literal: skip label
SYMCHAR: .fill 256 ; per-slot: 1 if the variable is char-typed (byte elements)
DCLCHAR: .fill 1   ; current declaration is char-typed
ISCHARTYPE: .fill 1 ; EXPECTTYPE: 1 if the type just parsed was 'char'
EXPRCHAR: .fill 1  ; last factor loaded a char-typed value (for *p byte deref)
ELCHAR: .fill 1    ; ELEMADDR: 1 if the indexed base is char-typed
CUR2:   .fill 1    ; second char of a two-char punct (== != <= >=), else 0
RELOP:  .fill 1    ; relational op code: 0 LT 1 LE 2 GT 3 GE 4 EQ 5 NE
RELF:   .fill 1    ; RELDET: 1 if the current token is a relational op
LBLCNT: .fill 1    ; next codegen label number
LBLA:   .fill 1    ; comparison branch-target label (EMITCMP)
LBLB:   .fill 1    ; comparison end label (EMITCMP)
JLBL:   .fill 1    ; label number scratch for EMITJ/EMITLBL
IFTMP:  .fill 1    ; a label held briefly (non-recursively) in if/while
USEMUL: .fill 1    ; 1 if the program uses '*' (emit the __mul8 helper)
USEDIV: .fill 1    ; 1 if the program uses '/' or '%'
MULT2:  .fill 2    ; lexer: NACC<<1 scratch for *10
CARRY:  .fill 1    ; lexer: 16-bit add carry
SLOTCNT: .fill 1   ; total variable slots across all functions (global)
SLOTBASE: .fill 1  ; the current function's first slot
CURFN:  .fill 16   ; current function name
IDNAME: .fill 16   ; a factor's identifier (call name / var name)
IDVAROK: .fill 1   ; gf_id: the id is a known variable
IDVARIDX: .fill 1  ; gf_id: that variable's local index
FCNT:   .fill 1    ; number of defined functions
FI:     .fill 1    ; FFIND function index
FFB:    .fill 1    ; FFIND result: the function's param base slot
FOK:    .fill 1    ; FFIND: 1 if found
NPARAMS: .fill 1   ; FUNCDEF: parameter count being parsed
ARGI:   .fill 1    ; call: current argument index
ARGSLOT: .fill 1   ; call: absolute slot for the current argument
FNPAR:  .fill 16   ; per-function parameter count
FSLOT:  .fill 16   ; per-function param base slot
FPOOL:  .fill 128  ; packed function names
USENEG: .fill 1    ; 1 if unary '-' is used (emit __neg)
USENOT: .fill 1    ; 1 if '!' is used (emit __lnot)
LORT:   .fill 1    ; '||' short-circuit: Ltrue label
LORE:   .fill 1    ; '||' end label
LANDF:  .fill 1    ; '&&' short-circuit: Lfalse label
LANDE:  .fill 1    ; '&&' end label
LFT:    .fill 1    ; for-loop: cond (top) label
LFB:    .fill 1    ; for-loop: body label
LFP:    .fill 1    ; for-loop: post label
LFE:    .fill 1    ; for-loop: end label
WHT:    .fill 1    ; while-loop: top (cond) label
WHE:    .fill 1    ; while-loop: end label
CURBRK: .fill 1    ; innermost loop's break target (0 outside any loop)
CURCONT: .fill 1   ; innermost loop's continue target
SYMPOOL: .fill 256 ; packed NUL-terminated variable names
