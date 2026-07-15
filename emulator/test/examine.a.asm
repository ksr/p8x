; examine.asm — hand-coded EXAMINE command (asm counterpart of os/commands/examine.c).
;   EXAMINE addr   view/modify memory from hex address addr. Per byte:
;     Enter        keep the byte, advance to the next
;     two hex      write that byte, then advance
;     .            quit to the shell
; Mirrors the ROM monitor's `E`. Memory-only. Entry: P2 = arg tail.
; SYS_GETC ($200C) echoes the key (and CRLF + a queued LF on Enter), so we echo
; nothing and swallow the queued LF after an Enter. SYS_PUTC=$2009, SYS_PUTS=$200F.
;#use abi

        .org $6A00
e_sk:   LDA (P2)                     ; skip leading spaces
        LDB #32
        CMP
        JNZ e_c0
        INP2
        JMP e_sk
e_c0:   LDA (P2)                     ; empty / CR -> usage
        LDB #0
        CMP
        JZ e_use
        LDB #13
        CMP
        JZ e_use
        LDB #'-'                     ; leading '-': only "-h"/"-H" is valid (usage)
        CMP
        JNZ e_addr
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ e_use
        LDB #'H'
        CMP
        JZ e_use
        JMP e_bad                     ; any other "-x" flag is an error
e_addr: JSR GETHEX                   ; address -> HXLO/HXHI, MATCH
        LDA MATCH
        JZ e_bad
        LDA HXLO
        STA ADLO
        LDA HXHI
        STA ADHI
; ---- interactive examine/modify loop ----
e_loop: LDA ADHI                     ; "AAAA: "
        JSR OPH8
        LDA ADLO
        JSR OPH8
        LDA #':'
        JSR SYS_PUTC
        LDA #32
        JSR SYS_PUTC
        LDA ADLO                     ; P1 = addr; show the current byte
        TAP1L
        LDA ADHI
        TAP1H
        LDA (P1)
        JSR OPH8
        LDA #32
        JSR SYS_PUTC
        JSR SYS_GETC                 ; key -> A, C=1 at EOF (SYS_GETC echoes it)
        JC e_end
        STA ECHR
        LDB #'.'                     ; '.' -> quit
        CMP
        JZ e_dot
        LDA ECHR
        LDB #13                      ; Enter -> advance (swallow the queued LF)
        CMP
        JZ e_cr
        LDA ECHR                     ; first hex digit
        JSR HEXVAL
        LDA MATCH
        JZ e_nl                      ; not hex -> newline, stay on this address
        LDA DIGIT
        STA HIN
        JSR SYS_GETC                 ; second hex digit
        JC e_end
        JSR HEXVAL
        LDA MATCH
        JZ e_nl
        LDA DIGIT
        STA LON
        LDA HIN                      ; value = HIN*16 + LON (four SHLs = <<4)
        SHL
        SHL
        SHL
        SHL
        LDB LON
        ADD
        STA VAL
        LDA ADLO                     ; write it
        TAP1L
        LDA ADHI
        TAP1H
        LDA VAL
        STA (P1)
        JSR e_crlf
        JMP e_next
e_cr:   JSR SYS_GETC                 ; consume the queued LF, then advance
        JMP e_next
e_dot:  JSR e_crlf
e_end:  RTS
e_nl:   JSR e_crlf
        JMP e_loop
e_next: LDA ADLO                     ; addr += 1 (16-bit, carry into ADHI)
        LDB #1
        ADD
        STA ADLO
        LDA ADHI                     ; ADD set C on low-byte overflow ($FF->$00)
        JNC e_nc
        INC
        STA ADHI
e_nc:   JMP e_loop
e_crlf: LDA #13
        JSR SYS_PUTC
        LDA #10
        JSR SYS_PUTC
        RTS
e_bad:  LDA #<m_bad
        TAP1L
        LDA #>m_bad
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
e_use:  LDA #<m_use
        TAP1L
        LDA #>m_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; OPH8: print A as two hex digits (to SYS_PUTC).
OPH8:   STA RHX                      ; save byte; emit high nibble first
        SHR
        SHR
        SHR
        SHR
        JSR ONIB
        LDA RHX                      ; then low nibble
        LDB #$0F
        AND
        JMP ONIB                     ; tail call: ONIB's RTS returns to OPH8's caller
; ONIB: print low nibble of A (0..15) as one hex char. Clobbers A,B.
ONIB:   LDB #10                      ; CMP sets C=1 when A>=B, i.e. nibble>=10
        CMP
        JC on_hex
        LDB #'0'                     ; 0..9 -> '0'..'9'
        ADD
        JSR SYS_PUTC
        RTS
on_hex: LDB #$37                     ; 10..15 -> 'A'..'F' (10+$37=$41='A')
        ADD
        JSR SYS_PUTC
        RTS

; GETHEX: skip spaces at (P2), parse hex digits -> HXLO/HXHI, advance P2.
; MATCH=1 if at least one digit was read, else 0.
GETHEX: LDA #0
        STA HXLO
        STA HXHI
        STA GCNT
gh_sk:  LDA (P2)
        LDB #32
        CMP
        JNZ gh_lp
        INP2
        JMP gh_sk
gh_lp:  LDA (P2)
        JSR HEXVAL
        LDA MATCH
        JZ gh_end
        LDA #4                       ; shift 16-bit accum left 4 (one hex digit)
        STA SHC
gh_shl: LDA HXLO                     ; SHL low: bit7 -> C
        SHL
        STA HXLO
        LDA HXHI                     ; ROL high: pulls C into bit0
        ROL
        STA HXHI
        LDA SHC
        DEC
        STA SHC
        JNZ gh_shl
        LDA HXLO                     ; OR in new digit (low nibble now clear)
        LDB DIGIT
        ADD
        STA HXLO
        LDA HXHI                     ; propagate any carry into high byte
        JNC gh_nc
        INC
gh_nc:  STA HXHI
        INP2
        LDA GCNT
        INC
        STA GCNT
        JMP gh_lp
gh_end: LDA GCNT
        JZ gh_no
        LDA #1
        STA MATCH
        RTS
gh_no:  LDA #0
        STA MATCH
        RTS

; HEXVAL: A = char -> DIGIT (0..15), MATCH=1 if a hex digit, else MATCH=0.
; Lower-case 'a'..'f' are folded to upper case (subtract $20) so only the
; '0'..'9' and 'A'..'F' ranges need testing below.
HEXVAL: STA HVT
        LDB #'a'                     ; below 'a'? (C=0) leave as-is
        CMP
        JNC hv_u
        LDB #'g'                     ; at/above 'g'? (C=1) leave as-is
        CMP
        JC hv_u
        LDA HVT                      ; in 'a'..'f': fold to 'A'..'F'
        LDB #$20
        SUB
        STA HVT
hv_u:   LDA HVT                      ; reject chars below '0'
        LDB #'0'
        CMP
        JNC hv_no
        LDB #$3A                     ; '9'+1: below $3A means '0'..'9' digit
        CMP
        JC hv_af
        LDA HVT
        LDB #'0'
        SUB
        STA DIGIT
        LDA #1
        STA MATCH
        RTS
hv_af:  LDA HVT                      ; not a digit: test 'A'..'F' range
        LDB #'A'
        CMP
        JNC hv_no
        LDB #$47                     ; 'F'+1: at/above means past 'F', reject
        CMP
        JC hv_no
        LDA HVT                      ; 'A'..'F' -> 10..15
        LDB #'A'
        SUB
        LDB #10
        ADD
        STA DIGIT
        LDA #1
        STA MATCH
        RTS
hv_no:  LDA #0
        STA MATCH
        RTS

m_bad:  .asciiz "examine: bad address"
m_use:  .asciiz "usage: EXAMINE addr   view/modify memory (Enter=next, 2 hex=write, .=quit)"
HXLO:   .fill 1
HXHI:   .fill 1
GCNT:   .fill 1
SHC:    .fill 1
DIGIT:  .fill 1
MATCH:  .fill 1
HVT:    .fill 1
RHX:    .fill 1
ADLO:   .fill 1
ADHI:   .fill 1
ECHR:   .fill 1
HIN:    .fill 1
LON:    .fill 1
VAL:    .fill 1

; lib_abi.inc — the BIOS/OS entry-point address book for hand-asm /BIN commands.
; A twin declares `;#use abi` and mkasm.sh appends this file, after which it can
; `JSR FOPEN` / `JSR SYS_PUTC` instead of hand-coding `JSR $0124` / `JSR $2009`.
;
; These are pure equates: they emit NO bytes, so a twin that switches its raw
; `JSR $NNNN` calls to symbolic ones assembles to the byte-identical binary — the
; magic numbers just get names, and the firmware jump table / syscall vector can
; be renumbered by editing this one file. (The C side splits the same names across
; lib_fsread/fswrite/fsdir/con.c because there each wrapper costs code space; on
; the asm side an equate is free, so one address book is simplest.)
;
; Unused equates are harmless, so a twin can blanket `;#use abi` even if it only
; needs a couple — which also lets a shared include, e.g. lib_stdin.inc, use these
; names as long as its host command pulls in this file too.

; --- OS syscalls ($20xx) — the redirectable stream + FS/CWD calls ---
SYS_GETCWD   = $2003    ; copy CWD path string -> (P1), incl. NUL
SYS_CWDLBA   = $2006    ; CWD directory start LBA -> A
SYS_PUTC     = $2009    ; A -> current stdout (console or redirected file)
SYS_GETC     = $200C    ; next stdin byte -> A (carry/EOF per ABI)
SYS_PUTS     = $200F    ; write (P1) string to stdout
SYS_OPENCWD  = $2012    ; begin iterating the CWD (16-bit LBA)
; Note the gap: $2015/$2018 are reserved/unused vectors, so the numbering
; jumps from $2012 straight to $201B — keep new syscalls at the +3 stride.
SYS_DIRENTRY = $201B    ; snapshot the current dir entry -> (P1) 18 bytes
SYS_OPENDIR  = $201E    ; P1 = 16-bit dir start LBA -> open for FNEXT
SYS_MKDIR    = $2021    ; P1 = path -> create a directory; C=1 on real failure

; --- BIOS jump table ($01xx) ---
CONIN      = $0100      ; wait for key, char -> A (raw console, not stdin)
CONOUT     = $0103      ; A -> serial (raw console, not stdout)
PUTS       = $0112      ; print (P1)+ until $00 (raw console)
PHEX8      = $0115      ; print A as two hex digits
FFIND      = $0118      ; root file FNAME -> LBA+FLEN; C=0 found
FCREATE    = $011B      ; create root file FNAME from FSRC/FLEN; C=1 err
FDELETE    = $011E      ; tombstone root file FNAME; C=1 not found
FCOMMIT    = $0121      ; register streamed file (entry+free); C=1 full
FOPEN      = $0124      ; open file FNAME for reading (P1=buffer); C=1 missing
; FGETB/FPUTB stream one byte at a time and clobber P1/P2 (they walk the
; sector buffer), so save any live pointer regs around the call.
FGETB      = $0127      ; next byte -> A; C=1 at end of file
FWOPEN     = $012A      ; open a write stream at the free pointer (uses SBUF)
FPUTB      = $012D      ; append byte A to the write stream
FCLOSE     = $0130      ; flush + register file FNAME; C=1 full
FRESOLVE   = $0133      ; resolve path (P1) -> dir extent + leaf FNAME; C=1 bad path
FNORM      = $0136      ; copy string (P1) -> FNAME, case-preserved, padded to 12
FOPENDIR   = $0139      ; begin iterating directory at path (P1); C=1 bad path
FNEXT      = $013C      ; next live entry -> FNAME/FFLAG/LBA/FLEN; C=1 at end
FLOADAT    = $013F      ; read FLEN bytes from LBA into (P1) (whole sectors)
FOPENDIRAT = $0142      ; iterate the 4-sector directory at LBA = A (low)+LBA1 (high)
FSDIRBUF   = $0145      ; point FNEXT's sector buffer at page A (call after FOPENDIR)
