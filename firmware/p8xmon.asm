;==============================================================================
; P8XMON — ROM Monitor for the P8X TTL Computer
;
; Resides at $0000 (EEPROM). Runs at reset (P0 cleared to $0000 by hardware).
; Serial console: 6850 ACIA at $FF04/05, 9600 8N1.
;
; COMMANDS (single letter, hex args, case-insensitive intent — use caps):
;   E aaaa     Examine/modify. Shows "aaaa: vv ". Type two hex digits to
;              replace and advance, plain CR to advance, '.' to exit.
;   D aaaa     Dump 256 bytes from aaaa, hex + ASCII, 16 per line.
;   I          Init CF: SET FEATURES 8-bit mode, IDENTIFY, print model.
;   F          Format CF as P8XFS (boot block + zeroed directory). Asks Y/N.
;   B          Boot: load OS image from CF to $8000 and jump. Falls back
;              to the monitor prompt if no card / no signature / OSCNT=0.
;   G aaaa     Go: JSR to aaaa. Program returns to monitor via RTS.
;   X          Run ROM BASIC (JMP $2000, overlaid by tools/build_basic_rom.py).
;              BASIC's BYE command jumps to reset ($0000) to return here.
;   ?          Help.
;
; Also publishes a BIOS jump table at $0100 (CONIN/CONOUT/CONST/CFINIT/CFREAD/
; CFWRITE/PUTS/PHEX8) — a stable ABI for RAM-resident programs (P8X/OS).
;
; REGISTER/ISA NOTES
;   Uses the P8X set as defined in the design docs. Conventions:
;     CMP  = A - B, C=1 when A >= B (no borrow), Z=1 when equal
;     SHL/ROL shift through carry
;   TWO NEW OPCODES REQUIRED (add to microcode):
;     JMP (P1)  ; P1 -> P0 via T/T2          (5 microcycles)
;     JSR (P1)  ; push P0, then P1 -> P0     (9 microcycles)
;   Microcode for JMP (P1):
;     0: fetch
;     1: PSEL=P1, DOE=PTRL, DLD=T
;     2: PSEL=P1, DOE=PTRH, DLD=T2
;     3: PSEL=P0, DOE=T2,  DLD=PTRH
;     4: PSEL=P0, DOE=T,   DLD=PTRL, uRESET
;   (JSR (P1) prepends the 4-cycle return-address push from JSR abs.)
;
; RAM USE (below the OS area; TPA $A000+ is never touched):
;   $9D00-$9D3F  line buffer
;   $9D40-       variables (see equates)
;   $9E00-$9FFF  512-byte sector buffer (shared with OS when it loads)
;   $FE00-$FEFF  stack (P3), grows down from $FEFF
;==============================================================================

; ---------------- Equates ----------------------------------------------------
ACIAS   = $FF04          ; ACIA status (rd) / control (wr)
ACIAD   = $FF05          ; ACIA data
CFDATA  = $FF10          ; CF task file
CFFEAT  = $FF11
CFSCNT  = $FF12
CFLBA0  = $FF13
CFLBA1  = $FF14
CFLBA2  = $FF15
CFHEAD  = $FF16          ; $E0 = LBA mode, drive 0
CFCMD   = $FF17          ; command (wr) / status (rd)
CFSTAT  = $FF17

LBUF    = $9D00          ; input line buffer
ADDRL   = $9D40          ; parsed address
ADDRH   = $9D41
HEXL    = $9D42          ; hex accumulator
HEXH    = $9D43
TMP     = $9D44
TMP2    = $9D45
CNT     = $9D46          ; loop counter
LBA     = $9D47          ; current LBA (low byte; LBA1-3 written as 0)
SBUF    = $9E00          ; sector buffer
STKTOP  = $FEFF
BASIC   = $2000          ; ROM BASIC cold-start (overlaid by the ROM build)

CR      = $0D
LF      = $0A
BS      = $08

        .org $0000
RESET:  JMP  COLD

;==============================================================================
; BIOS JUMP TABLE  — stable entry points for RAM-resident programs (P8X/OS).
; These addresses are an ABI: never reorder or insert, or every OS image on
; every card breaks. See hardware/cf-card/p8x-cf-os-design.md sec 2.2.
; Shared ABI state: LBA byte at $9D47, 512-byte sector buffer SBUF at $9E00.
;==============================================================================
        .org $0100
        JMP  GETC           ; $0100 CONIN   wait for key, char -> A
        JMP  PUTC           ; $0103 CONOUT  A -> serial
        JMP  CONST          ; $0106 CONST   A=RDRF bit; Z=1 when no key waiting
        JMP  CFINIT         ; $0109 CFINIT  reset + 8-bit mode; C=1 on error
        JMP  CFRDSEC        ; $010C CFREAD  sector LBA -> (P1); P1 += 512
        JMP  CFWRSEC        ; $010F CFWRITE SBUF -> sector LBA
        JMP  PUTS           ; $0112 PUTS    print (P1)+ until $00
        JMP  PRBYTE         ; $0115 PHEX8   print A as two hex digits

;==============================================================================
; Monitor body (relocated above the BIOS table; reset vectors here).
;==============================================================================
        .org $0130
; ---------------- Cold start -------------------------------------------------
COLD:   LDP3 #STKTOP        ; stack
        LDA  #$03           ; ACIA master reset
        STA  ACIAS
        LDA  #$15           ; /16 clock, 8N1, no IRQ
        STA  ACIAS
        LDP1 #MBANNER
        JSR  PUTS

; ---------------- Main loop --------------------------------------------------
PROMPT: LDP1 #MPROMPT
        JSR  PUTS
        JSR  GETLINE        ; line -> LBUF, P2 left at LBUF
        LDP2 #LBUF
        JSR  SKIPSP
        LDA  (P2)+          ; command char
        JZ   PROMPT         ; empty line
        STA  TMP2
        LDB  #'E'
        CMP
        JZ   CMD_E
        LDA  TMP2
        LDB  #'D'
        CMP
        JZ   CMD_D
        LDA  TMP2
        LDB  #'I'
        CMP
        JZ   CMD_I
        LDA  TMP2
        LDB  #'F'
        CMP
        JZ   CMD_F
        LDA  TMP2
        LDB  #'B'
        CMP
        JZ   CMD_B
        LDA  TMP2
        LDB  #'G'
        CMP
        JZ   CMD_G
        LDA  TMP2
        LDB  #'X'
        CMP
        JZ   CMD_X
        LDA  TMP2
        LDB  #'?'
        CMP
        JZ   CMD_H
        LDA  TMP2
        LDB  #'H'           ; H = ? = help
        CMP
        JZ   CMD_H
ERR:    LDP1 #MWHAT
        JSR  PUTS
        JMP  PROMPT

; ---------------- E aaaa : examine / modify ----------------------------------
CMD_E:  JSR  GETADDR        ; ADDR <- hex arg (errors -> ERR)
        JC   ERR
        JSR  A2P1           ; P1 <- ADDR
EXLOOP: JSR  PRADDR         ; "aaaa: vv "
        LDA  #':'
        JSR  PUTC
        JSR  SPACE
        LDA  (P1)
        JSR  PRBYTE
        JSR  SPACE
        JSR  GETC           ; first key
        LDB  #CR
        CMP
        JZ   EXNEXT         ; CR = keep, advance
        LDA  TMP            ; (GETC leaves char in TMP too)
        LDB  #'.'
        CMP
        JZ   EXDONE
        JSR  PUTC           ; echo first hex digit
        JSR  NIBBLE         ; -> low 4 of A, C=1 invalid
        JC   EXBAD
        STA  TMP2           ; high nibble (so far)
        JSR  GETC
        JSR  PUTC
        JSR  NIBBLE
        JC   EXBAD
        STA  TMP            ; low nibble
        LDA  TMP2
        SHL
        SHL
        SHL
        SHL
        LDB  TMP
        OR
        STA  (P1)           ; write new value
EXNEXT: INP1
        JSR  CRLF
        JMP  EXLOOP
EXBAD:  LDA  #'?'
        JSR  PUTC
        JSR  CRLF
        JMP  EXLOOP
EXDONE: JSR  CRLF
        JMP  PROMPT

; ---------------- D aaaa : dump 256 bytes ------------------------------------
CMD_D:  JSR  GETADDR
        JC   ERR
        JSR  A2P1
DPAGE:  LDA  #16            ; 16 lines = one 256-byte block
        STA  CNT
DLINE:  JSR  PRADDR
        JSR  SPACE
        JSR  P1TOP2         ; save line start for ASCII pass
        LDA  #16
        STA  TMP2
DHEX:   LDA  (P1)+
        JSR  PRBYTE
        JSR  SPACE
        LDA  TMP2
        DEC
        STA  TMP2
        JNZ  DHEX
        JSR  SPACE
        LDA  #16
        STA  TMP2
DASC:   LDA  (P2)+
        LDB  #$20           ; below space -> '.'
        CMP
        JNC  DDOT
        LDB  #$7F           ; DEL and above -> '.'
        CMP
        JC   DDOT
        JMP  DPUT
DDOT:   LDA  #'.'
DPUT:   JSR  PUTC
        LDA  TMP2
        DEC
        STA  TMP2
        JNZ  DASC
        JSR  CRLF
        LDA  CNT
        DEC
        STA  CNT
        JNZ  DLINE
        JSR  GETC           ; page: '.' = exit to prompt, CR/any = next block
        LDB  #'.'
        CMP
        JZ   PROMPT
        JMP  DPAGE          ; P1 already points at the next 256 bytes

; ---------------- I : init CF + identify -------------------------------------
CMD_I:  JSR  CFINIT
        JC   CFFAIL
        JSR  CFWAIT
        LDA  #$EC           ; IDENTIFY DEVICE
        STA  CFCMD
        JSR  CFDRQ
        LDP1 #SBUF
        JSR  CFRD512
        LDP1 #MCFOK
        JSR  PUTS
        LDP1 #SBUF+54       ; model string: words 27-46, byte-swapped
        LDA  #20            ; 20 word pairs
        STA  CNT
IDLOOP: LDA  (P1)+          ; byte 0 of pair prints second
        STA  TMP2
        LDA  (P1)+
        JSR  PUTC
        LDA  TMP2
        JSR  PUTC
        LDA  CNT
        DEC
        STA  CNT
        JNZ  IDLOOP
        JSR  CRLF
        JMP  PROMPT
CFFAIL: LDP1 #MCFERR
        JSR  PUTS
        JMP  PROMPT

; ---------------- F : format P8XFS -------------------------------------------
CMD_F:  LDP1 #MSURE
        JSR  PUTS
        JSR  GETC
        JSR  PUTC
        JSR  CRLF
        LDA  TMP            ; CRLF clobbered A; reload the key (GETC's TMP copy)
        LDB  #'Y'
        CMP
        JNZ  PROMPT
        JSR  CFINIT
        JC   CFFAIL
        JSR  ZSBUF          ; zero the sector buffer
        LDA  #'P'           ; boot block: signature, ver, oscnt, free ptr
        STA  SBUF+0
        LDA  #'8'
        STA  SBUF+1
        LDA  #1             ; version
        STA  SBUF+2
        LDA  #0             ; OSCNT = 0 (no OS image yet)
        STA  SBUF+3
        LDA  #65            ; free pointer = LBA 65 (lo)
        STA  SBUF+4
        LDA  #0
        STA  SBUF+5
        LDA  #0
        STA  LBA
        JSR  CFWRSEC        ; write LBA 0
        JSR  ZSBUF
        LDA  #33            ; zero directory, LBA 33..64
FDIR:   STA  LBA
        JSR  CFWRSEC
        LDA  LBA
        INC
        LDB  #65
        CMP
        JNC  FDIR
        LDP1 #MFMTOK
        JSR  PUTS
        JMP  PROMPT

; ---------------- B : boot from CF -------------------------------------------
CMD_B:  JSR  CFINIT
        JC   CFFAIL
        LDA  #0
        STA  LBA
        LDP1 #SBUF
        JSR  CFRDSEC        ; boot block -> SBUF
        LDA  SBUF+0
        LDB  #'P'
        CMP
        JNZ  NOBOOT
        LDA  SBUF+1
        LDB  #'8'
        CMP
        JNZ  NOBOOT
        LDA  SBUF+3         ; OSCNT
        JZ   NOBOOT
        STA  CNT
        LDA  #1
        STA  LBA
        LDP1 #$8000         ; OS load address
BLOOP:  JSR  CFRDSEC        ; reads 512 bytes, advances P1
        LDA  LBA
        INC
        STA  LBA
        LDA  CNT
        DEC
        STA  CNT
        JNZ  BLOOP
        JMP  $8000          ; hand off to the OS
NOBOOT: LDP1 #MNOOS
        JSR  PUTS
        JMP  PROMPT

; ---------------- G aaaa : run program ---------------------------------------
CMD_G:  JSR  GETADDR
        JC   ERR
        JSR  A2P1
        JSR  CRLF
        JSR  (P1)           ; program RTS -> here
        JSR  CRLF
        JMP  PROMPT

; ---------------- X : launch ROM BASIC ---------------------------------------
; BASIC is assembled to $2000 (its cold start) and overlaid into this EEPROM
; image by the ROM build (see basic/README.md). BASIC's BYE command jumps back
; to the reset vector ($0000), returning here.
CMD_X:  JMP  BASIC

; ---------------- ? : help ----------------------------------------------------
CMD_H:  LDP1 #MHELP
        JSR  PUTS
        JMP  PROMPT

;==============================================================================
; CF DRIVER
;==============================================================================
CFWAIT: LDA  CFSTAT         ; spin while BSY
        LDB  #$80
        AND
        JNZ  CFWAIT
        RTS

CFDRQ:  LDA  CFSTAT         ; spin until DRQ
        LDB  #$08
        AND
        JZ   CFDRQ
        RTS

CFINIT: JSR  CFWAIT
        LDA  #$E0           ; LBA mode, drive 0
        STA  CFHEAD
        LDA  #$01           ; feature: enable 8-bit transfers
        STA  CFFEAT
        LDA  #$EF           ; SET FEATURES
        STA  CFCMD
        JSR  CFWAIT
        LDA  CFSTAT         ; C=1 on ERR
        LDB  #$01
        AND
        JZ   CFI_OK
        SEC                 ; (SEC/CLC = set/clear carry; 1-byte micro-ops)
        RTS
CFI_OK: CLC
        RTS

CFSETL: LDA  LBA            ; LBA -> task file (sectors 0..255 used by mon)
        STA  CFLBA0
        LDA  #0
        STA  CFLBA1
        STA  CFLBA2
        LDA  #$E0
        STA  CFHEAD
        LDA  #1
        STA  CFSCNT
        RTS

CFRDSEC:                    ; read sector LBA -> (P1), P1 advances 512
        JSR  CFWAIT
        JSR  CFSETL
        LDA  #$20           ; READ SECTORS
        STA  CFCMD
        JSR  CFDRQ
CFRD512:                    ; (entry used by IDENTIFY too)
        LDA  #0
        STA  TMP
RD1:    LDA  CFDATA
        STA  (P1)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  RD1            ; 256 bytes
        LDA  #0
        STA  TMP
RD2:    LDA  CFDATA
        STA  (P1)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  RD2            ; 512 total
        RTS

CFWRSEC:                    ; write SBUF -> sector LBA
        JSR  CFWAIT
        JSR  CFSETL
        LDA  #$30           ; WRITE SECTORS
        STA  CFCMD
        JSR  CFDRQ
        LDP1 #SBUF
        LDA  #0
        STA  TMP
WR1:    LDA  (P1)+
        STA  CFDATA
        LDA  TMP
        INC
        STA  TMP
        JNZ  WR1
        LDA  #0
        STA  TMP
WR2:    LDA  (P1)+
        STA  CFDATA
        LDA  TMP
        INC
        STA  TMP
        JNZ  WR2
        JSR  CFWAIT
        RTS

ZSBUF:  LDP1 #SBUF          ; zero 512-byte buffer
        LDA  #0
        STA  TMP
ZS1:    LDA  #0
        STA  (P1)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  ZS1
        LDA  #0
        STA  TMP
ZS2:    LDA  #0
        STA  (P1)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  ZS2
        RTS

;==============================================================================
; CONSOLE & PARSING SUPPORT
;==============================================================================
PUTC:   PHA
PUTC1:  LDA  ACIAS
        LDB  #$02           ; TDRE
        AND
        JZ   PUTC1
        PLA
        STA  ACIAD
        RTS

GETC:   LDA  ACIAS
        LDB  #$01           ; RDRF
        AND
        JZ   GETC
        LDA  ACIAD
        STA  TMP            ; convenience copy
        RTS

CONST:  LDA  ACIAS          ; console status: A = RDRF bit, Z=1 when no key
        LDB  #$01
        AND
        RTS

PUTS:   LDA  (P1)+          ; print zero-terminated string at (P1)
        JZ   PUTSX
        JSR  PUTC
        JMP  PUTS
PUTSX:  RTS

CRLF:   LDA  #CR
        JSR  PUTC
        LDA  #LF
        JSR  PUTC
        RTS

SPACE:  LDA  #' '
        JSR  PUTC
        RTS

GETLINE:                    ; line w/ echo + backspace -> LBUF, 0-terminated
        LDP2 #LBUF
GL1:    JSR  GETC
        LDB  #CR
        CMP
        JZ   GLDONE
        LDA  TMP
        LDB  #BS
        CMP
        JZ   GLBS
        LDA  TMP
        LDB  #$7F
        CMP
        JZ   GLBS
        LDA  TMP
        JSR  PUTC           ; echo
        STA  (P2)+
        JMP  GL1
GLBS:   TPA2L               ; backspace if buffer non-empty (check low byte)
        LDB  #<LBUF      ; assembler: low byte of LBUF
        CMP
        JZ   GL1
        DEP2
        LDA  #BS
        JSR  PUTC
        JSR  SPACE
        LDA  #BS
        JSR  PUTC
        JMP  GL1
GLDONE: LDA  #0
        STA  (P2)
        JSR  CRLF
        RTS

SKIPSP: LDA  (P2)           ; advance P2 past spaces
        LDB  #' '
        CMP
        JNZ  SKX
        INP2
        JMP  SKIPSP
SKX:    RTS

NIBBLE: LDB  #'0'           ; ASCII in A -> value 0-15; C=1 if invalid
        SUB
        JNC  NBAD           ; below '0'
        LDB  #10
        CMP
        JNC  NOK            ; 0-9
        LDB  #7             ; 'A'-'F' -> 10-15
        SUB
        LDB  #10
        CMP
        JNC  NBAD           ; gap between '9' and 'A'
        LDB  #16
        CMP
        JC   NBAD
NOK:    CLC
        RTS
NBAD:   SEC
        RTS

GETADDR:                    ; parse 4 hex digits at (P2) -> ADDRH/L; C=1 err
        JSR  SKIPSP
        LDA  #0
        STA  HEXL
        STA  HEXH
        STA  TMP2           ; digit count
GH1:    LDA  (P2)
        JZ   GHEND          ; end of line
        LDB  #' '
        CMP
        JZ   GHEND
        INP2
        JSR  NIBBLE
        JC   GHERR
        STA  CNT            ; nibble value
        LDA  HEXL           ; 16-bit left shift by 4
        SHL
        STA  HEXL
        LDA  HEXH
        ROL
        STA  HEXH
        LDA  HEXL
        SHL
        STA  HEXL
        LDA  HEXH
        ROL
        STA  HEXH
        LDA  HEXL
        SHL
        STA  HEXL
        LDA  HEXH
        ROL
        STA  HEXH
        LDA  HEXL
        SHL
        STA  HEXL
        LDA  HEXH
        ROL
        STA  HEXH
        LDA  HEXL
        LDB  CNT
        OR
        STA  HEXL
        LDA  TMP2
        INC
        STA  TMP2
        JMP  GH1
GHEND:  LDA  TMP2
        JZ   GHERR          ; no digits at all
        LDA  HEXL
        STA  ADDRL
        LDA  HEXH
        STA  ADDRH
        CLC
        RTS
GHERR:  SEC
        RTS

A2P1:   LDA  ADDRL          ; ADDR -> P1
        TAP1L
        LDA  ADDRH
        TAP1H
        RTS

P1TOP2: TPA1L               ; P1 -> P2
        TAP2L
        TPA1H
        TAP2H
        RTS

PRADDR: TPA1H               ; print P1 as 4 hex digits
        JSR  PRBYTE
        TPA1L
        JSR  PRBYTE
        RTS

PRBYTE: PHA
        SHR
        SHR
        SHR
        SHR
        JSR  PRNIB
        PLA
PRNIB:  LDB  #$0F
        AND
        LDB  #10
        CMP
        JC   PRA
        LDB  #'0'
        ADD
        JMP  PRP
PRA:    LDB  #'7'           ; 'A'-10
        ADD
PRP:    JSR  PUTC
        RTS

;==============================================================================
; MESSAGES
;==============================================================================
MBANNER: .byte CR,LF
        .ascii "P8X MONITOR V1.0"
        .byte CR,LF
         .ascii "? FOR HELP"
         .byte CR,LF,0
MPROMPT: .ascii "* "
        .byte 0
MWHAT:  .ascii "?"
        .byte CR,LF,0
MCFOK:  .ascii "CF OK: "
        .byte 0
MCFERR: .ascii "CF ERROR"
        .byte CR,LF,0
MSURE:  .ascii "FORMAT CF - SURE? (Y/N) "
        .byte 0
MFMTOK: .ascii "FORMATTED"
        .byte CR,LF,0
MNOOS:  .ascii "NO OS ON CARD"
        .byte CR,LF,0
MHELP:  .ascii "P8XMON COMMANDS  (AAAA = 4 HEX DIGITS):"
        .byte CR,LF
         .ascii "E AAAA  EXAMINE/MODIFY FROM AAAA (TYPE HEX=SET, CR=NEXT, .=EXIT)"
         .byte CR,LF
         .ascii "D AAAA  DUMP 256 BYTES FROM AAAA (CR=NEXT BLOCK, .=EXIT)"
         .byte CR,LF
         .ascii "I       INIT CF: SET 8-BIT, IDENTIFY, PRINT MODEL"
         .byte CR,LF
         .ascii "F       FORMAT CF AS P8XFS (ASKS Y/N)"
         .byte CR,LF
         .ascii "B       BOOT OS IMAGE FROM CF TO $8000"
         .byte CR,LF
         .ascii "G AAAA  CALL AAAA (JSR, RTS RETURNS HERE)"
         .byte CR,LF
         .ascii "X       RUN ROM BASIC (BASIC 'BYE' RETURNS HERE)"
         .byte CR,LF
         .ascii "? / H   THIS HELP"
         .byte CR,LF,0

