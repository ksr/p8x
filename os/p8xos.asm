; p8xos.asm - P8X/OS v0.2, a RAM-resident disk operating system.
;
; Loaded from CompactFlash to $8000 and entered by the ROM monitor's B command
; (which reads OSCNT sectors from LBA 1 and JMPs to $8000). The OS does NOT
; carry its own drivers: it calls the BIOS jump table the monitor publishes at
; $0100 (see firmware/p8xmon.asm), so console + CF access stay in one place.
;
; Build (RAM image, assembled to run at $8000):
;   python3 assembler/p8xasm.py os/p8xos.asm -o p8xos.bin --base 0x8000
; then install on a P8XFS image with:  tools/p8xfs.py boot disk.img p8xos.bin
;
; v0.2 shell:
;   DIR            list the flat P8XFS v1 directory
;   LOAD name      read a file into its stored load address
;   RUN  name      LOAD it, then JSR its exec address (program RTS -> shell)
;   DEL  name      mark the directory entry deleted ($FF) and write it back
;   HELP
; Commands are matched as whole words; a filename argument is parsed, upcased
; and space-padded to 12 chars. SAVE (create a file) is the next step and needs
; hex-argument parsing + a free-space allocator. See p8x-cf-os-design.md sec 2.5.

; ---- BIOS jump table (stable ABI, in ROM) ----------------------------------
CONIN   = $0100          ; wait for key, char -> A
CONOUT  = $0103          ; A -> serial
CONST   = $0106          ; A = RDRF bit; Z=1 when no key waiting
CFINIT  = $0109          ; reset + 8-bit mode; C=1 on error
CFREAD  = $010C          ; sector LBA -> (P1); P1 += 512
CFWRITE = $010F          ; SBUF -> sector LBA
PUTS    = $0112          ; print (P1)+ until $00
PHEX8   = $0115          ; print A as two hex digits

; ---- Shared ABI state (set by/for the BIOS) --------------------------------
LBA     = $9D47          ; CFREAD/CFWRITE target LBA (low byte)
SBUF    = $9E00          ; 512-byte sector buffer

; ---- P8XFS v1 on-disk layout -----------------------------------------------
DIRLBA  = 33             ; directory: LBA 33..64, 32-byte entries
DATALBA = 65             ; first data LBA (directory scan stops here)
F_FILE  = $01            ; entry flag: regular file ($00 end, $02 dir, $FF del)
F_DEL   = $FF

; ---- OS RAM variables (below the kernel, clear of BIOS $9D44+ and SBUF) -----
LINEBUF = $9000          ; shell input line (64 bytes)
CMDBUF  = $9040          ; parsed command word (16 bytes)
NAMEBUF = $9050          ; 12-byte filename (search key / DIR scratch)
TMP     = $9060
TMP2    = $9061
CNT     = $9062
ECNT    = $9063          ; entries-left-in-sector counter
FLAGS   = $9064          ; current entry flag byte
MATCH   = $9065          ; 1 = name matched / strings equal
LENLO   = $9066          ; entry length, low 16 bits
LENHI   = $9067
STARTLO = $9068          ; entry start LBA (low byte)
LOADLO  = $9069          ; entry load address
LOADHI  = $906A
EXECLO  = $906B          ; entry exec address
EXECHI  = $906C
DLBA    = $906D          ; directory sector being scanned
SECCNT  = $906E          ; sectors left to transfer
CURLBA  = $906F          ; current data LBA
ENTPL   = $9070          ; pointer to a directory entry (in SBUF):
ENTPH   = $9071          ;   flag byte for DEL, entry start for SAVE
ARGPL   = $9072          ; saved arg position in LINEBUF
ARGPH   = $9073
; ---- SAVE working set ----
HXLO    = $9074          ; GETHEX result
HXHI    = $9075
DIGIT   = $9076          ; HEXVAL digit value
SHCNT   = $9077          ; shift counter
SVSTLO  = $9078          ; SAVE source start address
SVSTHI  = $9079
FREELO  = $907A          ; boot-block free pointer (next data LBA)
FREEHI  = $907B
SRCLO   = $907C          ; running source pointer during the copy
SRCHI   = $907D
REM     = $907E          ; sectors remaining in the SAVE write loop

CR      = $0D
LF      = $0A
STKTOP  = $FEFF

        .org $8000
; ---------------- Cold start -------------------------------------------------
COLD:   LDP3 #STKTOP
        LDP1 #MBANNER
        JSR  PUTS

; ---------------- Shell main loop --------------------------------------------
SHELL:  LDP1 #MPROMPT
        JSR  PUTS
        JSR  GETLN              ; line -> LINEBUF (null-terminated)
        LDP2 #LINEBUF
        LDP1 #CMDBUF
        JSR  PARSEW             ; CMDBUF = upcased command word; P2 -> args
        TPA2L                   ; remember where arguments start
        STA  ARGPL
        TPA2H
        STA  ARGPH
        LDA  CMDBUF
        JZ   SHELL              ; blank line
        LDP1 #KW_DIR
        JSR  CMPCMD
        JNZ  DODIR
        LDP1 #KW_HELP
        JSR  CMPCMD
        JNZ  DOHELP
        LDP1 #KW_LOAD
        JSR  CMPCMD
        JNZ  DOLOAD
        LDP1 #KW_RUN
        JSR  CMPCMD
        JNZ  DORUN
        LDP1 #KW_DEL
        JSR  CMPCMD
        JNZ  DODEL
        LDP1 #KW_SAVE
        JSR  CMPCMD
        JNZ  DOSAVE
        LDP1 #MUNK              ; unknown command
        JSR  PUTS
        JMP  SHELL

; CMPCMD - compare CMDBUF to the keyword at (P1); returns A!=0 (and Z clear)
; when they match. Leaves the keyword pointer consumed.
CMPCMD: LDP2 #CMDBUF
        JSR  STREQ
        LDA  MATCH
        RTS

; ---------------- HELP -------------------------------------------------------
DOHELP: LDP1 #MHELP
        JSR  PUTS
        JMP  SHELL

; ---------------- DIR : list the P8XFS directory -----------------------------
DODIR:  LDP1 #MDIRHDR
        JSR  PUTS
        JSR  CRLF
        LDA  #DIRLBA
        STA  DLBA
DSEC:   LDP1 #SBUF              ; read one directory sector -> SBUF
        LDA  DLBA
        STA  LBA
        JSR  CFREAD
        LDP2 #SBUF
        LDA  #16                ; 16 entries per 512-byte sector
        STA  ECNT
DENT:   JSR  RDENT              ; name->NAMEBUF, length->LENLO/HI, flag->FLAGS
        LDA  FLAGS
        JZ   DDONE              ; $00 = end of directory
        LDB  #F_FILE
        CMP
        JNZ  DNEXT              ; skip non-file entries (deleted / dir)
        LDP1 #NAMEBUF           ; print "NAME........  hhhh"
        LDA  #12
        STA  TMP
DPRN:   LDA  (P1)+
        JSR  CONOUT
        LDA  TMP
        DEC
        STA  TMP
        JNZ  DPRN
        LDA  #' '
        JSR  CONOUT
        LDA  #' '
        JSR  CONOUT
        LDA  LENHI
        JSR  PHEX8
        LDA  LENLO
        JSR  PHEX8
        JSR  CRLF
DNEXT:  LDA  ECNT
        DEC
        STA  ECNT
        JNZ  DENT
        LDA  DLBA               ; next directory sector
        INC
        STA  DLBA
        LDB  #DATALBA
        CMP                     ; DLBA >= 65 (C=1) -> ran past directory
        JC   DDONE
        JMP  DSEC
DDONE:  JMP  SHELL

; ---------------- LOAD name --------------------------------------------------
DOLOAD: JSR  FINDARG            ; parse name, scan directory
        JZ   NOFILE
        JSR  LOADF              ; read the file into its load address
        LDP1 #MLOADED
        JSR  PUTS
        JMP  SHELL

; ---------------- RUN name ---------------------------------------------------
DORUN:  JSR  FINDARG
        JZ   NOFILE
        JSR  LOADF
        LDA  EXECLO             ; P1 <- exec address
        TAP1L
        LDA  EXECHI
        TAP1H
        JSR  (P1)               ; execute; program RTS returns here
        JMP  SHELL

; ---------------- DEL name ---------------------------------------------------
DODEL:  JSR  FINDARG
        JZ   NOFILE
        LDA  ENTPL              ; P1 <- &flags of the matched entry (in SBUF)
        TAP1L
        LDA  ENTPH
        TAP1H
        LDA  #F_DEL
        STA  (P1)               ; mark deleted in the buffered sector
        LDA  DLBA               ; persist that directory sector
        STA  LBA
        JSR  CFWRITE
        LDP1 #MDELETED
        JSR  PUTS
        JMP  SHELL

NOFILE: LDP1 #MNOFILE
        JSR  PUTS
        JMP  SHELL

; FINDARG - parse a filename argument and locate it. Returns Z set (A=0) when
; no file was found, Z clear when FINDENT filled the entry fields.
FINDARG:JSR  ARG2P2             ; P2 -> argument text
        JSR  PARSEN             ; NAMEBUF <- upcased, space-padded name
        JSR  FINDENT            ; sets MATCH + fields + ENTPL/H + DLBA
        LDA  MATCH
        RTS

; ARG2P2 - point P2 at the saved argument position in LINEBUF.
ARG2P2: LDA  ARGPL
        TAP2L
        LDA  ARGPH
        TAP2H
        RTS

; SECCOUNT - SECCNT = ceil(LENLO:LENHI / 512) = (LENHI>>1) rounded up when any
; low bits remain. Used by LOAD and SAVE.
SECCOUNT:LDA LENHI
        SHR
        STA  SECCNT
        LDA  LENHI
        LDB  #1
        AND                     ; high byte odd -> 256-byte tail -> round up
        JNZ  SC_RND
        LDA  LENLO
        JZ   SC_GO              ; exact multiple of 512
SC_RND: LDA  SECCNT
        INC
        STA  SECCNT
SC_GO:  RTS

; LOADF - read the located file (STARTLO / LENLO:LENHI / LOADLO:LOADHI) into
; memory at its load address.
LOADF:  JSR  SECCOUNT
        LDA  LOADLO             ; P1 <- load address
        TAP1L
        LDA  LOADHI
        TAP1H
        LDA  STARTLO
        STA  CURLBA
LF_LP:  LDA  SECCNT
        JZ   LF_END
        LDA  CURLBA
        STA  LBA
        JSR  CFREAD             ; sector -> (P1); P1 += 512
        LDA  CURLBA
        INC
        STA  CURLBA
        LDA  SECCNT
        DEC
        STA  SECCNT
        JMP  LF_LP
LF_END: RTS

; ---------------- SAVE name start end ----------------------------------------
; Write the memory range [start,end) to a new file: length = end - start,
; allocate at the boot-block free pointer, copy memory into successive sectors,
; add a directory entry, and advance the free pointer.
DOSAVE: JSR  ARG2P2             ; P2 -> argument text
        JSR  PARSEN             ; NAMEBUF <- filename (P2 left after the name)
        JSR  GETHEX             ; start address
        LDA  MATCH
        JZ   SV_ERR
        LDA  HXLO
        STA  SVSTLO
        LDA  HXHI
        STA  SVSTHI
        JSR  GETHEX             ; end address
        LDA  MATCH
        JZ   SV_ERR
        ; length = end - start (16-bit), into LENLO:LENHI
        LDA  HXLO
        LDB  SVSTLO
        SUB                     ; C=1 when no borrow (end_lo >= start_lo)
        STA  LENLO
        JC   SV_HI
        LDA  HXHI               ; borrow: high = end_hi - start_hi - 1
        LDB  SVSTHI
        SUB
        STA  LENHI
        LDA  LENHI
        LDB  #1
        SUB
        STA  LENHI
        JMP  SV_LEN
SV_HI:  LDA  HXHI
        LDB  SVSTHI
        SUB
        STA  LENHI
SV_LEN: JSR  SECCOUNT           ; SECCNT = sectors needed
        JSR  SAVECORE
        LDA  MATCH
        JZ   SV_FULL
        LDP1 #MSAVED
        JSR  PUTS
        JMP  SHELL
SV_ERR: LDP1 #MSVERR
        JSR  PUTS
        JMP  SHELL
SV_FULL:LDP1 #MDIRFUL
        JSR  PUTS
        JMP  SHELL

; SAVECORE - allocate + write data + directory entry. Returns MATCH=0 if the
; directory is full (data already written, but no entry made).
SAVECORE:LDP1 #SBUF             ; read boot block -> free pointer
        LDA  #0
        STA  LBA
        JSR  CFREAD
        LDA  SBUF+4
        STA  FREELO
        LDA  SBUF+5
        STA  FREEHI
        LDA  SVSTLO             ; source pointer = start address
        STA  SRCLO
        LDA  SVSTHI
        STA  SRCHI
        LDA  FREELO             ; data LBA starts at the free pointer
        STA  CURLBA
        LDA  SECCNT
        STA  REM
SV_WL:  LDA  REM
        JZ   SV_WD
        JSR  CPYSEC             ; copy 512 bytes SRC -> SBUF, advance SRC
        LDA  CURLBA
        STA  LBA
        JSR  CFWRITE            ; SBUF -> data sector
        LDA  CURLBA
        INC
        STA  CURLBA
        LDA  REM
        DEC
        STA  REM
        JMP  SV_WL
SV_WD:  JSR  FINDSLOT           ; locate a free directory slot (sector in SBUF)
        LDA  MATCH
        JZ   SVC_RET            ; directory full -> MATCH=0, bail
        JSR  WRENT              ; build the 32-byte entry in SBUF
        LDA  DLBA
        STA  LBA
        JSR  CFWRITE            ; persist the directory sector
        LDP1 #SBUF              ; reload boot block, bump free pointer
        LDA  #0
        STA  LBA
        JSR  CFREAD
        LDA  FREELO
        LDB  SECCNT
        ADD                     ; new free = old free + sectors written
        STA  SBUF+4
        LDA  FREEHI
        JNC  SVC_NC
        INC
SVC_NC: STA  SBUF+5
        LDA  #0
        STA  LBA
        JSR  CFWRITE
        LDA  #1
        STA  MATCH
SVC_RET:RTS

; CPYSEC - copy 512 bytes from SRCLO:SRCHI into SBUF, then save the advanced
; source pointer back (CFWRITE will clobber P1).
CPYSEC: LDA  SRCLO
        TAP1L
        LDA  SRCHI
        TAP1H
        LDP2 #SBUF
        LDA  #0
        STA  TMP
CS1:    LDA  (P1)+
        STA  (P2)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  CS1
        LDA  #0
        STA  TMP
CS2:    LDA  (P1)+
        STA  (P2)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  CS2
        TPA1L
        STA  SRCLO
        TPA1H
        STA  SRCHI
        RTS

; FINDSLOT - scan the directory for a free entry ($00 end or $FF deleted).
; On success MATCH=1, ENTPL/H -> entry start in SBUF, DLBA = that sector,
; sector left in SBUF. Directory full -> MATCH=0.
FINDSLOT:LDA #DIRLBA
        STA  DLBA
FS_SEC: LDP1 #SBUF
        LDA  DLBA
        STA  LBA
        JSR  CFREAD
        LDP2 #SBUF
        LDA  #16
        STA  ECNT
FS_ENT: TPA2L                   ; remember entry start
        STA  ENTPL
        TPA2H
        STA  ENTPH
        LDA  #24                ; skip name+start+len+load+exec to the flag byte
        STA  TMP
FS_SK:  LDA  (P2)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FS_SK
        LDA  (P2)+              ; flag byte (offset 24)
        STA  FLAGS
        LDA  #7                 ; skip spare -> next entry
        STA  TMP
FS_SP:  LDA  (P2)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FS_SP
        LDA  FLAGS
        JZ   FS_OK              ; $00 end marker -> free
        LDB  #F_DEL
        CMP
        JZ   FS_OK              ; $FF deleted -> free
        LDA  ECNT
        DEC
        STA  ECNT
        JNZ  FS_ENT
        LDA  DLBA
        INC
        STA  DLBA
        LDB  #DATALBA
        CMP
        JC   FS_FULL
        JMP  FS_SEC
FS_OK:  LDA  #1
        STA  MATCH
        RTS
FS_FULL:LDA  #0
        STA  MATCH
        RTS

; WRENT - write a 32-byte file entry at ENTPL/H (in SBUF): NAMEBUF, start LBA =
; FREELO (4 bytes), length (4), load=exec=SVST (2+2), flag=file, spare zeros.
WRENT:  LDA  ENTPL
        TAP1L
        LDA  ENTPH
        TAP1H
        LDP2 #NAMEBUF           ; name (12)
        LDA  #12
        STA  TMP
WE_NM:  LDA  (P2)+
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  WE_NM
        LDA  FREELO             ; start LBA (4)
        STA  (P1)+
        LDA  FREEHI
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  LENLO              ; length (4)
        STA  (P1)+
        LDA  LENHI
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  SVSTLO             ; load (2)
        STA  (P1)+
        LDA  SVSTHI
        STA  (P1)+
        LDA  SVSTLO             ; exec (2) = load
        STA  (P1)+
        LDA  SVSTHI
        STA  (P1)+
        LDA  #F_FILE            ; flag
        STA  (P1)+
        LDA  #7                 ; spare (7)
        STA  TMP
WE_SP:  LDA  #0
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  WE_SP
        RTS

; GETHEX - parse a hex number from (P2) into HXLO:HXHI. Skips leading spaces,
; consumes hex digits (0-9 A-F, upcased), stops at the first non-hex char.
; MATCH=1 if at least one digit was read, else MATCH=0.
GETHEX: LDA  #0
        STA  HXLO
        STA  HXHI
        STA  CNT                ; digit count
GH_SK:  LDA  (P2)
        LDB  #' '
        CMP
        JNZ  GH_LP
        INP2
        JMP  GH_SK
GH_LP:  LDA  (P2)
        JSR  HEXVAL             ; -> DIGIT, MATCH
        LDA  MATCH
        JZ   GH_END
        LDA  #4                 ; accumulator <<= 4 (16-bit)
        STA  SHCNT
GH_SHL: LDA  HXLO
        SHL                     ; C = bit7
        STA  HXLO
        LDA  HXHI
        ROL                     ; shift carry in
        STA  HXHI
        LDA  SHCNT
        DEC
        STA  SHCNT
        JNZ  GH_SHL
        LDA  HXLO               ; accumulator |= digit (add, carry to high)
        LDB  DIGIT
        ADD
        STA  HXLO
        LDA  HXHI
        JNC  GH_NC
        INC
GH_NC:  STA  HXHI
        INP2
        LDA  CNT
        INC
        STA  CNT
        JMP  GH_LP
GH_END: LDA  CNT
        JZ   GH_ERR
        LDA  #1
        STA  MATCH
        RTS
GH_ERR: LDA  #0
        STA  MATCH
        RTS

; HEXVAL - A holds a candidate hex char. If valid, DIGIT = 0..15 and MATCH=1;
; else MATCH=0. Upcases first.
HEXVAL: JSR  UPCASE
        STA  TMP
        LDB  #'0'
        CMP                     ; A >= '0' ?
        JNC  HV_BAD
        LDB  #$3A               ; '9' + 1
        CMP                     ; A > '9' ?
        JC   HV_AF
        LDA  TMP                ; digit 0-9
        LDB  #'0'
        SUB
        STA  DIGIT
        LDA  #1
        STA  MATCH
        RTS
HV_AF:  LDA  TMP
        LDB  #'A'
        CMP                     ; A >= 'A' ?
        JNC  HV_BAD
        LDB  #$47               ; 'F' + 1
        CMP                     ; A > 'F' ?
        JC   HV_BAD
        LDA  TMP                ; digit A-F = char - 'A' + 10
        LDB  #'A'
        SUB
        LDB  #10
        ADD
        STA  DIGIT
        LDA  #1
        STA  MATCH
        RTS
HV_BAD: LDA  #0
        STA  MATCH
        RTS

; FINDENT - search the directory for the file named in NAMEBUF.
; On a match: MATCH=1, fields filled, ENTPL/H -> the entry's flag byte in SBUF
; (the matching sector is left in SBUF), DLBA = that sector's LBA.
; On miss / end-of-directory: MATCH=0.
FINDENT:LDA  #DIRLBA
        STA  DLBA
FE_SEC: LDP1 #SBUF
        LDA  DLBA
        STA  LBA
        JSR  CFREAD
        LDP2 #SBUF
        LDA  #16
        STA  ECNT
FE_ENT: LDP1 #NAMEBUF           ; compare 12-byte name
        LDA  #12
        STA  TMP
        LDA  #1
        STA  MATCH
FE_CMP: LDA  (P2)+              ; entry name char (advances P2 through the name)
        STA  TMP2
        LDA  (P1)+              ; search-key char
        LDB  TMP2
        CMP
        JZ   FE_C1
        LDA  #0
        STA  MATCH
FE_C1:  LDA  TMP
        DEC
        STA  TMP
        JNZ  FE_CMP
        LDA  (P2)+              ; bytes 12..15  start LBA
        STA  STARTLO
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; bytes 16..19  length (low 16 kept)
        STA  LENLO
        LDA  (P2)+
        STA  LENHI
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; bytes 20..23  load + exec
        STA  LOADLO
        LDA  (P2)+
        STA  LOADHI
        LDA  (P2)+
        STA  EXECLO
        LDA  (P2)+
        STA  EXECHI
        TPA2L                   ; capture &flags (current P2) before reading it
        STA  ENTPL
        TPA2H
        STA  ENTPH
        LDA  (P2)+              ; byte 24  flags
        STA  FLAGS
        LDA  (P2)+              ; bytes 25..31  spare
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  FLAGS
        JZ   FE_NF              ; $00 end marker -> stop, not found
        LDA  MATCH
        JZ   FE_NEXT            ; name mismatch
        LDA  FLAGS              ; matched name; require it be a live file
        LDB  #F_FILE
        CMP
        JNZ  FE_NEXT
        LDA  #1
        STA  MATCH
        RTS
FE_NEXT:LDA  ECNT
        DEC
        STA  ECNT
        JNZ  FE_ENT
        LDA  DLBA
        INC
        STA  DLBA
        LDB  #DATALBA
        CMP
        JC   FE_NF
        JMP  FE_SEC
FE_NF:  LDA  #0
        STA  MATCH
        RTS

; RDENT - read the 32-byte directory entry at (P2)+ for DIR: name -> NAMEBUF,
; low 16 bits of length -> LENLO/HI, flag byte -> FLAGS. (P2)+ only.
RDENT:  LDP1 #NAMEBUF
        LDA  #12
        STA  TMP
RE_NM:  LDA  (P2)+
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  RE_NM
        LDA  (P2)+              ; start LBA (discard 4)
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; length low 16
        STA  LENLO
        LDA  (P2)+
        STA  LENHI
        LDA  (P2)+              ; length high 16 (discard)
        LDA  (P2)+
        LDA  (P2)+              ; load + exec (discard 4)
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; flags
        STA  FLAGS
        LDA  (P2)+              ; spare (discard 7)
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        RTS

; ---------------- parsing helpers --------------------------------------------
; PARSEW - copy a word from (P2) into the buffer at (P1), upcased and
; null-terminated. Skips leading spaces; stops at space/null WITHOUT consuming
; the terminator (peek with LDA (P2), advance with INP2).
PARSEW: LDA  (P2)               ; skip leading spaces
        LDB  #' '
        CMP
        JNZ  PW_LP
        INP2
        JMP  PARSEW
PW_LP:  LDA  (P2)
        JZ   PW_END             ; end of line
        LDB  #' '
        CMP
        JZ   PW_END             ; space ends the word
        JSR  UPCASE             ; A holds the char (CMP preserves A)
        STA  (P1)
        INP1
        INP2
        JMP  PW_LP
PW_END: LDA  #0
        STA  (P1)
        RTS

; PARSEN - fill NAMEBUF with 12 spaces, then copy up to 12 upcased name chars
; from (P2) (after skipping leading spaces), stopping at space/null.
PARSEN: LDP1 #NAMEBUF
        LDA  #12
        STA  TMP
PN_FZ:  LDA  #' '
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  PN_FZ
        LDP1 #NAMEBUF
PN_SK:  LDA  (P2)               ; skip leading spaces
        LDB  #' '
        CMP
        JNZ  PN_CP
        INP2
        JMP  PN_SK
PN_CP:  LDA  #12                ; copy up to 12 name chars
        STA  CNT
PN_LP:  LDA  (P2)
        JZ   PN_END
        LDB  #' '
        CMP
        JZ   PN_END
        LDA  CNT
        JZ   PN_END             ; 12 chars taken
        LDA  (P2)
        JSR  UPCASE
        STA  (P1)
        INP1
        INP2
        LDA  CNT
        DEC
        STA  CNT
        JMP  PN_LP
PN_END: RTS

; UPCASE - if A is 'a'..'z', clear bit 5 to uppercase it; else leave A.
UPCASE: STA  TMP2
        LDB  #'a'
        CMP                     ; C=1 when A >= 'a'
        JNC  UC_RAW
        LDB  #$7B               ; 'z' + 1
        CMP                     ; C=1 when A > 'z'
        JC   UC_RAW
        LDB  #$DF
        AND
        RTS
UC_RAW: LDA  TMP2
        RTS

; STREQ - compare the null-terminated strings at (P1) and (P2). Sets MATCH=1
; when equal, else 0. Consumes P1/P2.
STREQ:  LDA  (P1)
        STA  TMP2
        LDA  (P2)
        LDB  TMP2
        CMP                     ; A(P2 char) - B(P1 char); Z if equal
        JNZ  SR_NE
        LDA  (P2)               ; chars equal; if both 0 -> strings equal
        JZ   SR_EQ
        INP1
        INP2
        JMP  STREQ
SR_EQ:  LDA  #1
        STA  MATCH
        RTS
SR_NE:  LDA  #0
        STA  MATCH
        RTS

; ---------------- console helpers (built on the BIOS) ------------------------
; GETLN - read a line into LINEBUF until CR, echoing; null-terminate.
GETLN:  LDP2 #LINEBUF
GL1:    JSR  CONIN
        STA  TMP
        LDB  #CR
        CMP
        JZ   GLEND
        LDA  TMP
        JSR  CONOUT             ; echo (CONOUT preserves A)
        STA  (P2)+
        JMP  GL1
GLEND:  JSR  CRLF
        LDA  #0
        STA  (P2)
        RTS

CRLF:   LDA  #CR
        JSR  CONOUT
        LDA  #LF
        JSR  CONOUT
        RTS

; ---------------- strings ----------------------------------------------------
MBANNER: .byte CR,LF
         .asciiz "P8X/OS v0.3"
MPROMPT: .byte CR,LF
         .asciiz "> "
MHELP:   .byte CR,LF
         .asciiz "commands: DIR  LOAD f  RUN f  SAVE f s e  DEL f  HELP"
MDIRHDR: .byte CR,LF
         .asciiz "NAME            SIZE"
MUNK:    .byte CR,LF
         .asciiz "?"
MNOFILE: .byte CR,LF
         .asciiz "?NO FILE"
MLOADED: .byte CR,LF
         .asciiz "LOADED"
MDELETED: .byte CR,LF
         .asciiz "DELETED"
MSAVED:  .byte CR,LF
         .asciiz "SAVED"
MSVERR:  .byte CR,LF
         .asciiz "?SAVE f start end"
MDIRFUL: .byte CR,LF
         .asciiz "?DIR FULL"

KW_DIR:  .asciiz "DIR"
KW_HELP: .asciiz "HELP"
KW_LOAD: .asciiz "LOAD"
KW_RUN:  .asciiz "RUN"
KW_DEL:  .asciiz "DEL"
KW_SAVE: .asciiz "SAVE"
