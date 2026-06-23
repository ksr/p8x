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
;   F          Format CF as P8XFS v2 (boot block + root extent '.'/'..'). Asks Y/N.
;   B          Boot: load OS image from CF to $4000 and jump. Falls back
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
; RAM USE (below the OS area; TPA $B000+ is never touched):
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
LBA     = $9D47          ; current LBA, byte 0 (bits 7:0)
LBA1    = $9D48          ; LBA byte 1 (bits 15:8)  — 0 after CFINIT unless set
LBA2    = $9D49          ; LBA byte 2 (bits 23:16) — 0 after CFINIT unless set
; ---- filesystem-call ABI (FFIND/FCREATE operate on the P8XFS v2 root, LBA 33) -
FNAME   = $9D4A          ; 12-byte filename (space-padded) — in for both calls
FSRC    = $9D56          ; FCREATE: source address of the file data (2 bytes)
FLEN    = $9D58          ; file length in bytes (2 bytes): FCREATE in, FFIND out
FSAV    = $9D5A          ; FCREATE scratch: requested length saved across FFIND
; --- read-stream state (FOPEN/FGETB): a sequential byte reader over a file,
;     using a caller-supplied 512-byte sector buffer (ROBUF) ---
ROLBA   = $9D5C          ; next sector LBA to read (3)
ROREM   = $9D5F          ; bytes remaining in the file (2)
ROBUF   = $9D61          ; caller's 512-byte sector buffer address (2)
ROPTR   = $9D63          ; read cursor within ROBUF (2)
ROCNT   = $9D65          ; bytes left in ROBUF; 0 -> refill (2)
; --- write-stream state (FWOPEN/FPUTB/FCLOSE): a sequential byte writer that
;     streams to disk at the volume free pointer, using SBUF as its buffer ---
WOLBA   = $9D67          ; current output sector LBA (3)
WOPOS   = $9D6A          ; byte offset within SBUF; 512 -> flush (2)
WOTOT   = $9D6C          ; total bytes written (-> FLEN at close) (2)
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
; Shared ABI state: 24-bit LBA at $9D47..$9D49 (LBA0/LBA1/LBA2, little-endian;
; LBA1/LBA2 default 0 after CFINIT — set them for sectors >255), and the
; 512-byte sector buffer SBUF at $9E00.
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
        JMP  FFIND          ; $0118 FFIND   root file FNAME -> LBA+FLEN; C=0 found
        JMP  FCREATE        ; $011B FCREATE root file FNAME from FSRC/FLEN; C=1 err
        JMP  FDELETE        ; $011E FDELETE tombstone root file FNAME; C=1 not found
        JMP  FCOMMIT        ; $0121 FCOMMIT register streamed file (entry+free); C=1 full
        JMP  FOPEN          ; $0124 FOPEN   open root file FNAME for reading (P1=buf); C=1 missing
        JMP  FGETB          ; $0127 FGETB   next byte -> A; C=1 at end of file
        JMP  FWOPEN         ; $012A FWOPEN  open a write stream at the free pointer (uses SBUF)
        JMP  FPUTB          ; $012D FPUTB   append byte A to the write stream
        JMP  FCLOSE         ; $0130 FCLOSE  flush + register file FNAME (len=bytes written); C=1 full

;==============================================================================
; Monitor body (relocated above the BIOS table; reset vectors here).
; The BIOS jump table now runs to $0132 (FCLOSE), so the body starts at $0160
; to leave headroom for further BIOS entries. RESET ($0000) jumps here by label.
;==============================================================================
        .org $0160
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
        LDA  #2             ; version 2 (hierarchical) — the only P8XFS format
        STA  SBUF+2
        LDA  #0             ; OSCNT = 0 (no OS image yet)
        STA  SBUF+3
        LDA  #37            ; free pointer = LBA 37 (first v2 data sector)
        STA  SBUF+4
        LDA  #0
        STA  SBUF+5
        LDA  #0
        STA  LBA
        JSR  CFWRSEC        ; write boot block (LBA 0)
        ; root directory extent at LBA 33 (4 sectors): '.' and '..', both -> root
        JSR  ZSBUF
        LDP1 #SBUF
        LDA  #'.'           ; entry 0 "." + 11 spaces
        STA  (P1)+
        LDA  #11
        STA  TMP
FNM0:   LDA  #' '
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FNM0
        JSR  FENT           ; start=33, len=2048, load/exec=0, flag=dir, 7 spare=0
        LDA  #'.'           ; entry 1 ".." + 10 spaces
        STA  (P1)+
        LDA  #'.'
        STA  (P1)+
        LDA  #10
        STA  TMP
FNM1:   LDA  #' '
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FNM1
        JSR  FENT
        LDA  #33            ; write the root's first sector -> LBA 33
        STA  LBA
        JSR  CFWRSEC
        JSR  ZSBUF          ; zero the rest of the extent, LBA 34..36
        LDA  #34
FDIR:   STA  LBA
        JSR  CFWRSEC
        LDA  LBA
        INC
        LDB  #37
        CMP
        JNC  FDIR
        LDP1 #MFMTOK
        JSR  PUTS
        JMP  PROMPT
; FENT - emit the 20 non-name bytes of a v2 root dir entry through (P1)+:
;   start LBA 33, length 2048 (=4*512), load/exec 0, flag=directory, 7 spare 0.
FENT:   LDA  #33            ; start LBA (33,0,0,0)
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        STA  (P1)+
        LDA  #0             ; length 2048 = $0800 (lo,hi,0,0)
        STA  (P1)+
        LDA  #8
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  #0             ; load (2) + exec (2) = 0
        STA  (P1)+
        STA  (P1)+
        STA  (P1)+
        STA  (P1)+
        LDA  #2             ; flag = directory
        STA  (P1)+
        LDA  #7             ; 7 spare bytes = 0
        STA  TMP
FENS:   LDA  #0
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FENS
        RTS

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
        LDP1 #$4000         ; OS load address (rev D: RAM starts at $4000)
BLOOP:  JSR  CFRDSEC        ; reads 512 bytes, advances P1
        LDA  LBA
        INC
        STA  LBA
        LDA  CNT
        DEC
        STA  CNT
        JNZ  BLOOP
        JMP  $4000          ; hand off to the OS
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

CFINIT: LDA  #0             ; default the high LBA bytes to 0 (legacy 1-byte
        STA  LBA1           ; callers set only LBA0; CFSETL now reads LBA1/LBA2,
        STA  LBA2           ; so init them here — set them only for sectors >255)
        JSR  CFWAIT
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

CFSETL: LDA  LBA            ; 24-bit LBA -> task file (LBA0/LBA1/LBA2)
        STA  CFLBA0
        LDA  LBA1
        STA  CFLBA1
        LDA  LBA2
        STA  CFLBA2
        LDA  #$E0           ; LBA mode, drive 0, LBA[27:24]=0
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
        LDP1 #SBUF
CFWRP1:                     ; write 512 bytes from (P1) -> sector LBA (P1 += 512)
        JSR  CFWAIT
        JSR  CFSETL
        LDA  #$30           ; WRITE SECTORS
        STA  CFCMD
        JSR  CFDRQ
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

;==============================================================================
; FILESYSTEM CALLS — flat (root-only) file access on the P8XFS v2 root directory
; (LBA 33..36), shared by BASIC SAVE/LOAD and any RAM program; the full
; hierarchical path layer lives in P8X/OS. 32-byte entry: name 12 | start LBA 4 |
; length 4 | load 2 | exec 2 | flag 1 ($00 end, $01 file, $02 dir, $FF del) |
; spare 7. Free pointer = the 2-byte boot-block field at offset 4.
;==============================================================================
; FFIND - find regular file FNAME in the root.  C=0 + LBA(0..2)=start +
;   FLEN=length when found; C=1 if not.  Clobbers A,B,P1,P2,TMP,TMP2,CNT,ADDRL,HEXL,HEXH.
FFIND:  LDA  #4
        STA  CNT            ; 4 root sectors
        LDA  #33
        STA  ADDRL          ; current root LBA
FF_SEC: LDA  ADDRL
        STA  LBA
        LDA  #0
        STA  LBA1
        STA  LBA2
        LDP1 #SBUF
        JSR  CFRDSEC        ; root sector -> SBUF
        LDP2 #SBUF
        LDA  #16
        STA  TMP            ; 16 entries / sector
FF_ENT: LDP1 #FNAME         ; compare 12-byte name: (P2)=entry vs (P1)=FNAME
        LDA  #1
        STA  HEXH           ; match flag (1 until a byte differs)
        LDA  #12
        STA  HEXL           ; name byte counter
FF_NM:  LDA  (P2)+
        STA  TMP2
        LDA  (P1)+
        LDB  TMP2
        CMP
        JZ   FF_NE
        LDA  #0
        STA  HEXH
FF_NE:  LDA  HEXL
        DEC
        STA  HEXL
        JNZ  FF_NM
        LDA  (P2)+          ; 12..15 start LBA (keep low 3)
        STA  LBA
        LDA  (P2)+
        STA  LBA1
        LDA  (P2)+
        STA  LBA2
        LDA  (P2)+
        LDA  (P2)+          ; 16..19 length (keep low 2)
        STA  FLEN
        LDA  (P2)+
        STA  FLEN+1
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+          ; 20..23 load + exec
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+          ; 24 flag
        STA  TMP2
        LDA  #7             ; skip 25..31 spare -> next entry
        STA  HEXL
FF_SP:  LDA  (P2)+
        LDA  HEXL
        DEC
        STA  HEXL
        JNZ  FF_SP
        LDA  TMP2           ; flag
        JZ   FF_NO          ; $00 end-of-directory
        LDB  #$01
        CMP
        JNZ  FF_NXT         ; not a file
        LDA  HEXH
        JNZ  FF_HIT         ; file + name matched
FF_NXT: LDA  TMP
        DEC
        STA  TMP
        JNZ  FF_ENT
        LDA  ADDRL
        INC
        STA  ADDRL
        LDA  CNT
        DEC
        STA  CNT
        JNZ  FF_SEC
FF_NO:  SEC
        RTS
FF_HIT: CLC
        RTS

; FCREATE - create regular file FNAME in the root from FSRC (FLEN bytes).
;   C=1 if the name already exists or the root is full; else writes the data +
;   directory entry, bumps the free pointer, C=0.
FCREATE:LDA  FLEN           ; FFIND clobbers FLEN while scanning — save the
        STA  FSAV           ; caller's requested length and restore it after
        LDA  FLEN+1
        STA  FSAV+1
        JSR  FFIND
        JNC  FC_ERR         ; already exists
        LDA  FSAV
        STA  FLEN
        LDA  FSAV+1
        STA  FLEN+1
        LDA  #0             ; read boot block -> SBUF (free pointer at +4/+5)
        STA  LBA
        STA  LBA1
        STA  LBA2
        LDP1 #SBUF
        JSR  CFRDSEC
        LDA  SBUF+4         ; ADDRL/ADDRH = file start LBA = free pointer
        STA  ADDRL
        STA  LBA            ; LBA(0..2) = free pointer for the data write
        LDA  SBUF+5
        STA  ADDRH
        STA  LBA1
        LDA  #0
        STA  LBA2
        LDA  FSRC           ; P1 = data source
        TAP1L
        LDA  FSRC+1
        TAP1H
        LDA  #0
        STA  CNT            ; sectors written
        LDA  FLEN
        STA  TMP            ; remaining bytes (lo)
        LDA  FLEN+1
        STA  TMP2           ; remaining bytes (hi)
FC_WR:  LDA  TMP
        LDB  TMP2
        OR
        JZ   FC_WROK        ; remaining == 0
        JSR  CFWRP1         ; 512 from (P1) -> sector LBA; P1 += 512
        LDA  LBA
        INC
        STA  LBA
        JNZ  FC_WNC
        LDA  LBA1
        INC
        STA  LBA1
FC_WNC: LDA  CNT
        INC
        STA  CNT
        LDA  TMP2           ; remaining -= 512 (floor 0)
        LDB  #2
        SUB
        JNC  FC_WLST        ; hi < 2 -> this was the last (partial) sector
        STA  TMP2
        JMP  FC_WR
FC_WLST:LDA  #0
        STA  TMP
        STA  TMP2
        JMP  FC_WR
FC_WROK:LDA  SBUF+4         ; bump free pointer by the sectors written
        LDB  CNT
        ADD
        STA  SBUF+4
        LDA  SBUF+5
        JNC  FC_FNC
        INC
FC_FNC: STA  SBUF+5
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFWRSEC        ; write boot block back
        LDA  #4             ; find a free slot in the root and write the entry
        STA  CNT
        LDA  #33
        STA  HEXL           ; current root LBA
FC_DSEC:LDA  HEXL
        STA  LBA
        LDA  #0
        STA  LBA1
        STA  LBA2
        LDP1 #SBUF
        JSR  CFRDSEC
        LDP2 #SBUF
        LDA  #16
        STA  TMP
FC_DENT:TPA2L               ; save entry-start pointer in FSRC (data ptr is done)
        STA  FSRC
        TPA2H
        STA  FSRC+1
        LDA  #24            ; peek the flag at offset 24
        STA  HEXH
FC_SK:  LDA  (P2)+
        LDA  HEXH
        DEC
        STA  HEXH
        JNZ  FC_SK
        LDA  (P2)           ; flag
        JZ   FC_SLOT        ; $00 end -> free slot
        LDB  #$FF
        CMP
        JZ   FC_SLOT        ; $FF deleted -> reusable
        LDA  #8             ; occupied: P2 at +24, advance to next entry (+32)
        STA  HEXH
FC_NXE: LDA  (P2)+
        LDA  HEXH
        DEC
        STA  HEXH
        JNZ  FC_NXE
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FC_DENT
        LDA  HEXL
        INC
        STA  HEXL
        LDA  CNT
        DEC
        STA  CNT
        JNZ  FC_DSEC
        SEC                 ; root directory full
        RTS
FC_SLOT:LDA  FSRC           ; re-point P2 at the slot start
        TAP2L
        LDA  FSRC+1
        TAP2H
        LDP1 #FNAME         ; name (12)
        LDA  #12
        STA  HEXH
FC_WNM: LDA  (P1)+
        STA  (P2)+
        LDA  HEXH
        DEC
        STA  HEXH
        JNZ  FC_WNM
        LDA  ADDRL          ; start LBA (lo, hi, 0, 0)
        STA  (P2)+
        LDA  ADDRH
        STA  (P2)+
        LDA  #0
        STA  (P2)+
        STA  (P2)+
        LDA  FLEN           ; length (lo, hi, 0, 0)
        STA  (P2)+
        LDA  FLEN+1
        STA  (P2)+
        LDA  #0
        STA  (P2)+
        STA  (P2)+
        LDA  #0             ; load (2) + exec (2) = 0
        STA  (P2)+
        STA  (P2)+
        STA  (P2)+
        STA  (P2)+
        LDA  #$01           ; flag = file
        STA  (P2)+
        LDA  #7             ; spare (7) = 0
        STA  HEXH
FC_WSP: LDA  #0
        STA  (P2)+
        LDA  HEXH
        DEC
        STA  HEXH
        JNZ  FC_WSP
        LDA  HEXL           ; write the updated root sector back
        STA  LBA
        LDA  #0
        STA  LBA1
        STA  LBA2
        JSR  CFWRSEC
        CLC
        RTS
FC_ERR: SEC
        RTS

; FCOMMIT - register a file whose data the caller already streamed to disk at
;   the current free pointer. Writes its root directory entry (FNAME, start =
;   free pointer, length FLEN, load/exec 0, flag = file) and bumps the free
;   pointer by ceil(FLEN/512) sectors. Inputs are just the FS ABI vars FNAME +
;   FLEN. C=1 if the root is full. Reuses FCREATE's tail (FC_WROK: bump free +
;   write boot + find slot + write entry).
FCOMMIT:LDA  #0             ; CNT = ceil(FLEN / 512)
        STA  CNT
        LDA  FLEN
        STA  TMP
        LDA  FLEN+1
        STA  TMP2
FCM_CL: LDA  TMP
        LDB  TMP2
        OR
        JZ   FCM_DN
        LDA  CNT
        INC
        STA  CNT
        LDA  TMP2          ; remaining -= 512 (floor 0)
        LDB  #2
        SUB
        JNC  FCM_LST
        STA  TMP2
        JMP  FCM_CL
FCM_LST:LDA  #0
        STA  TMP
        STA  TMP2
        JMP  FCM_CL
FCM_DN: LDA  #0            ; read boot block -> SBUF
        STA  LBA
        STA  LBA1
        STA  LBA2
        LDP1 #SBUF
        JSR  CFRDSEC
        LDA  SBUF+4         ; start LBA = current free pointer
        STA  ADDRL
        LDA  SBUF+5
        STA  ADDRH
        JMP  FC_WROK

; FOPEN - open root file FNAME for sequential byte reading. P1 = a caller-owned
;   512-byte sector buffer the stream will use. C=1 if the file is not found.
;   Pairs with FGETB. (One read stream at a time.)
FOPEN:  TPA1L
        STA  ROBUF
        TPA1H
        STA  ROBUF+1
        JSR  FFIND          ; sets LBA + FLEN if found
        JC   FOP_NF
        LDA  LBA
        STA  ROLBA
        LDA  LBA1
        STA  ROLBA+1
        LDA  LBA2
        STA  ROLBA+2
        LDA  FLEN
        STA  ROREM
        LDA  FLEN+1
        STA  ROREM+1
        LDA  #0            ; force a refill on the first FGETB
        STA  ROCNT
        STA  ROCNT+1
        CLC
        RTS
FOP_NF: SEC
        RTS

; FGETB - return the next byte of the open read stream in A (C=0). C=1 at EOF.
;   Refills the sector buffer from disk as needed. Clobbers P1 + TMP.
FGETB:  LDA  ROREM
        LDB  ROREM+1
        OR
        JNZ  FG_GO
        SEC                ; no bytes left -> EOF
        RTS
FG_GO:  LDA  ROCNT
        LDB  ROCNT+1
        OR
        JNZ  FG_RD
        JSR  FG_FILL       ; buffer empty -> read next sector
FG_RD:  LDA  ROPTR
        TAP1L
        LDA  ROPTR+1
        TAP1H
        LDA  (P1)+
        STA  TMP
        TPA1L
        STA  ROPTR
        TPA1H
        STA  ROPTR+1
        LDA  ROCNT         ; ROCNT--
        LDB  #1
        SUB
        STA  ROCNT
        JC   FG_R1
        LDA  ROCNT+1
        LDB  #1
        SUB
        STA  ROCNT+1
FG_R1:  LDA  ROREM         ; ROREM--
        LDB  #1
        SUB
        STA  ROREM
        JC   FG_R2
        LDA  ROREM+1
        LDB  #1
        SUB
        STA  ROREM+1
FG_R2:  LDA  TMP
        CLC
        RTS
; FG_FILL - read the next sector into ROBUF; reset ROPTR; ROCNT = min(512,ROREM).
FG_FILL:LDA  ROLBA
        STA  LBA
        LDA  ROLBA+1
        STA  LBA1
        LDA  ROLBA+2
        STA  LBA2
        LDA  ROBUF
        TAP1L
        LDA  ROBUF+1
        TAP1H
        JSR  CFRDSEC
        LDA  ROLBA         ; ROLBA++ (24-bit)
        INC
        STA  ROLBA
        JNZ  FF_1
        LDA  ROLBA+1
        INC
        STA  ROLBA+1
        JNZ  FF_1
        LDA  ROLBA+2
        INC
        STA  ROLBA+2
FF_1:   LDA  ROBUF
        STA  ROPTR
        LDA  ROBUF+1
        STA  ROPTR+1
        LDA  ROREM+1       ; ROCNT = min(512, ROREM)
        LDB  #2
        CMP
        JC   FF_FULL       ; ROREM hi >= 2 -> >= 512
        LDA  ROREM
        STA  ROCNT
        LDA  ROREM+1
        STA  ROCNT+1
        RTS
FF_FULL:LDA  #0
        STA  ROCNT
        LDA  #2
        STA  ROCNT+1       ; 512
        RTS

; FWOPEN - open a sequential write stream. Data streams to disk starting at the
;   volume free pointer; SBUF is the sector buffer. Pair with FPUTB + FCLOSE.
;   (One write stream at a time.)
FWOPEN: LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        LDP1 #SBUF
        JSR  CFRDSEC       ; boot block -> SBUF
        LDA  SBUF+4        ; output starts at the free pointer
        STA  WOLBA
        LDA  SBUF+5
        STA  WOLBA+1
        LDA  #0
        STA  WOLBA+2
        STA  WOPOS
        STA  WOPOS+1
        STA  WOTOT
        STA  WOTOT+1
        JSR  FW_ZBUF       ; clear the first sector
        RTS
; FPUTB - append byte A to the write stream; flush a full sector at 512.
;   Clobbers P1 + TMP.
FPUTB:  STA  TMP
        LDA  WOPOS         ; P1 = SBUF + WOPOS (SBUF low byte = 0)
        TAP1L
        LDA  #$9E
        LDB  WOPOS+1
        ADD
        TAP1H
        LDA  TMP
        STA  (P1)
        LDA  WOPOS         ; WOPOS++
        LDB  #1
        ADD
        STA  WOPOS
        LDA  WOPOS+1
        JNC  FP_1
        INC
        STA  WOPOS+1
FP_1:   LDA  WOTOT         ; WOTOT++
        LDB  #1
        ADD
        STA  WOTOT
        LDA  WOTOT+1
        JNC  FP_2
        INC
        STA  WOTOT+1
FP_2:   LDA  WOPOS+1       ; WOPOS == 512 -> flush
        LDB  #2
        CMP
        JNZ  FP_R
        JSR  FW_FLUSH
FP_R:   RTS
; FCLOSE - flush a partial sector, then register file FNAME (length = bytes
;   written). C=1 if the root directory is full.
FCLOSE: LDA  WOPOS
        LDB  WOPOS+1
        OR
        JZ   FCL_R
        JSR  FW_FLUSH
FCL_R:  LDA  WOTOT
        STA  FLEN
        LDA  WOTOT+1
        STA  FLEN+1
        JSR  FDELETE       ; drop any old version (ignore not-found)
        JMP  FCOMMIT       ; write dir entry + bump free; returns C
; FW_FLUSH - write SBUF to WOLBA, advance, clear the buffer.
FW_FLUSH:
        LDA  WOLBA
        STA  LBA
        LDA  WOLBA+1
        STA  LBA1
        LDA  WOLBA+2
        STA  LBA2
        JSR  CFWRSEC
        LDA  WOLBA         ; WOLBA++ (24-bit)
        INC
        STA  WOLBA
        JNZ  FWF_1
        LDA  WOLBA+1
        INC
        STA  WOLBA+1
        JNZ  FWF_1
        LDA  WOLBA+2
        INC
        STA  WOLBA+2
FWF_1:  LDA  #0
        STA  WOPOS
        STA  WOPOS+1
        JSR  FW_ZBUF
        RTS
; FW_ZBUF - zero the 512-byte SBUF write buffer.
FW_ZBUF:LDP1 #SBUF
        LDA  #2
        STA  CNT
FWZ_P:  LDA  #0
        STA  TMP
FWZ_I:  LDA  #0
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FWZ_I
        LDA  CNT
        DEC
        STA  CNT
        JNZ  FWZ_P
        RTS

; FDELETE - tombstone regular file FNAME in the root (entry flag -> $FF).
;   C=0 if found and deleted; C=1 if not found. The file's data sectors are
;   orphaned (reclaimed by the next PACK). Used to overwrite an existing file:
;   FDELETE then FCREATE. Scan mirrors FFIND; flag-peek mirrors FCREATE.
FDELETE:LDA  #4
        STA  CNT
        LDA  #33
        STA  ADDRL          ; current root LBA
FDD_SEC:LDA  ADDRL
        STA  LBA
        LDA  #0
        STA  LBA1
        STA  LBA2
        LDP1 #SBUF
        JSR  CFRDSEC        ; root sector -> SBUF
        LDP2 #SBUF
        LDA  #16
        STA  TMP            ; 16 entries / sector
FDD_ENT:LDP1 #FNAME         ; compare 12-byte name: (P2)=entry vs (P1)=FNAME
        LDA  #1
        STA  HEXH           ; match flag (1 until a byte differs)
        LDA  #12
        STA  HEXL
FDD_NM: LDA  (P2)+
        STA  TMP2
        LDA  (P1)+
        LDB  TMP2
        CMP
        JZ   FDD_NE
        LDA  #0
        STA  HEXH
FDD_NE: LDA  HEXL
        DEC
        STA  HEXL
        JNZ  FDD_NM
        LDA  #12            ; skip 12..23 (start+len+load+exec) to flag at +24
        STA  HEXL
FDD_SK: LDA  (P2)+
        LDA  HEXL
        DEC
        STA  HEXL
        JNZ  FDD_SK
        LDA  (P2)           ; flag (no advance — may overwrite it below)
        JZ   FDD_NO         ; $00 end-of-directory -> not found
        LDB  #$01
        CMP
        JNZ  FDD_NXT        ; not a regular file -> skip
        LDA  HEXH
        JZ   FDD_NXT        ; name mismatch -> skip
        LDA  #$FF           ; hit: tombstone the flag in SBUF
        STA  (P2)
        LDA  ADDRL          ; write the updated root sector back
        STA  LBA
        LDA  #0
        STA  LBA1
        STA  LBA2
        JSR  CFWRSEC
        CLC
        RTS
FDD_NXT:LDA  #8             ; P2 at +24 -> advance to next entry (+32)
        STA  HEXL
FDD_NXE:LDA  (P2)+
        LDA  HEXL
        DEC
        STA  HEXL
        JNZ  FDD_NXE
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FDD_ENT
        LDA  ADDRL
        INC
        STA  ADDRL
        LDA  CNT
        DEC
        STA  CNT
        JNZ  FDD_SEC
FDD_NO: SEC
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
         .ascii "B       BOOT OS IMAGE FROM CF TO $4000"
         .byte CR,LF
         .ascii "G AAAA  CALL AAAA (JSR, RTS RETURNS HERE)"
         .byte CR,LF
         .ascii "X       RUN ROM BASIC (BASIC 'BYE' RETURNS HERE)"
         .byte CR,LF
         .ascii "? / H   THIS HELP"
         .byte CR,LF,0

