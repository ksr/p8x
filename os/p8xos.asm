; p8xos.asm - P8X/OS v0.1, a RAM-resident disk operating system.
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
; v0.1 shell: HELP and DIR (lists the flat P8XFS v1 directory). Command
; dispatch is first-letter for now; richer parsing (LOAD/RUN/SAVE/DEL/CD...)
; comes as the kernel grows. See hardware/cf-card/p8x-cf-os-design.md sec 2.5.

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
F_FILE  = $01            ; entry flag: regular file
                         ; ($00 = end marker, $02 = dir, $FF = deleted)

; ---- OS RAM variables (below the kernel, clear of BIOS $9D44+ and SBUF) -----
LINEBUF = $9000          ; shell input line (64 bytes)
TMP     = $9040
ECNT    = $9041          ; entries-left-in-sector counter
FLAGS   = $9042          ; current entry flag byte
LENLO   = $9043          ; current entry length, low 16 bits
LENHI   = $9044
DLBA    = $9045          ; directory sector being scanned
NAMEBUF = $9050          ; 12-byte filename scratch

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
        JSR  GETLN          ; line -> LINEBUF (null-terminated)
        LDP2 #LINEBUF
SKIP:   LDA  (P2)+          ; skip leading spaces
        STA  TMP
        LDB  #' '
        CMP
        JZ   SKIP
        LDA  TMP            ; first non-space char (0 if line empty)
        JZ   SHELL
        STA  TMP
        LDB  #'D'           ; D -> DIR
        CMP
        JZ   DODIR
        LDA  TMP
        LDB  #'H'           ; H -> HELP
        CMP
        JZ   DOHELP
        LDA  TMP
        LDB  #'?'           ; ? -> HELP
        CMP
        JZ   DOHELP
        LDP1 #MUNK          ; unknown command
        JSR  PUTS
        JMP  SHELL

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
DSEC:   LDP1 #SBUF          ; read one directory sector -> SBUF
        LDA  DLBA
        STA  LBA
        JSR  CFREAD
        LDP2 #SBUF
        LDA  #16            ; 16 entries per 512-byte sector
        STA  ECNT
DENT:   JSR  RDENT          ; pull one 32-byte entry: name->NAMEBUF, len, FLAGS
        LDA  FLAGS
        JZ   DDONE          ; $00 = end of directory
        LDB  #F_FILE
        CMP
        JNZ  DNEXT          ; skip non-file entries (deleted / dir)
        LDP1 #NAMEBUF       ; print "NAME........  hhhh"
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
        LDA  DLBA           ; next directory sector
        INC
        STA  DLBA
        LDB  #DATALBA
        CMP                 ; DLBA >= 65 (C=1) -> ran past directory
        JC   DDONE
        JMP  DSEC
DDONE:  JMP  SHELL

; RDENT - read the 32-byte directory entry at (P2)+, leaving:
;   NAMEBUF = 12 name bytes, LENLO/LENHI = low 16 bits of length, FLAGS = flag.
; Walks the entry purely with (P2)+ (no offset addressing on this ISA).
RDENT:  LDP1 #NAMEBUF       ; bytes 0..11  name
        LDA  #12
        STA  TMP
RE_NM:  LDA  (P2)+
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  RE_NM
        LDA  (P2)+          ; bytes 12..15  start LBA (discard)
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+          ; bytes 16..17  length low 16
        STA  LENLO
        LDA  (P2)+
        STA  LENHI
        LDA  (P2)+          ; bytes 18..19  length high 16 (discard)
        LDA  (P2)+
        LDA  (P2)+          ; bytes 20..23  load+exec (discard)
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+          ; byte 24  flags
        STA  FLAGS
        LDA  (P2)+          ; bytes 25..31  spare (discard)
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
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
        JSR  CONOUT         ; echo (CONOUT preserves A)
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
         .asciiz "P8X/OS v0.1"
MPROMPT: .byte CR,LF
         .asciiz "> "
MHELP:   .byte CR,LF
         .asciiz "commands: DIR  HELP"
MDIRHDR: .byte CR,LF
         .asciiz "NAME            SIZE"
MUNK:    .byte CR,LF
         .asciiz "?"
