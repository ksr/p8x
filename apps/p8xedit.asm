; =============================================================================
; P8X EDIT - line-oriented text editor (standalone TPA program)
; =============================================================================
; Built for the transient program area ($B000), launched from P8X/OS:
;     RUN EDIT NAME.EXT
; On entry P2 -> the argument tail (the OS program-arg ABI); EDIT copies it to
; FNAME and, if that file exists, loads it. Commands operate on a flat text
; buffer of LF-separated lines.
;
;   L      list all lines with 1-based numbers
;   A      append: type lines, end with a single "."
;   I n    insert before line n (n past the end = append); end with "."
;   D n    delete line n
;   W      write the buffer back to the file (FDELETE + FCREATE)
;   Q      quit back to the OS shell (RTS)
;   ?      help
;
; Built entirely on the BIOS jump table ($0100..) — no OS internals. Line
; numbers are 8-bit (max 255 lines). Text buffer is $C000..$F000 (12 KB).
; =============================================================================

; ---- BIOS entry points -------------------------------------------------------
CONIN   = $0100         ; wait for key -> A
CONOUT  = $0103         ; A -> console
PUTS    = $0112         ; print (P1)+ until $00
FLOADAT = $013F         ; bulk-read FLEN bytes from LBA into (P1)
FFIND   = $0118         ; root file FNAME -> LBA+FLEN; C=1 not found
FCREATE = $011B         ; create root file FNAME from FSRC/FLEN; C=1 err
FDELETE = $011E         ; tombstone root file FNAME; C=1 not found

; ---- BIOS shared FS parameter block -----------------------------------------
LBA     = $9D47         ; 24-bit LBA (lo/mid/hi)
LBA1    = $9D48
LBA2    = $9D49
FNAME   = $9D4A         ; 12-byte space-padded name
FSRC    = $9D56         ; FCREATE source address
FLEN    = $9D58         ; length (FCREATE in / FFIND out)

CR      = $0D
LF      = $0A
BS      = $08
DEL     = $7F

; ---- buffer geometry ---------------------------------------------------------
TBUF    = $C000         ; text buffer start
TMAXL   = $00           ; text ceiling = $F000 (12 KB)
TMAXH   = $F0
LBUF    = $BE00         ; line input buffer (page-aligned for cheap "at start?")

; ---- variables ($BF00 page) --------------------------------------------------
TENDL   = $BF00         ; end-of-text pointer
TENDH   = $BF01
ARGN    = $BF02         ; parsed decimal command argument (8-bit)
TMP     = $BF03
TMP2    = $BF04
CNTL    = $BF05         ; 16-bit scratch counter
CNTH    = $BF06
SRCL    = $BF07         ; 16-bit scratch pointer (insertion point / line start)
SRCH    = $BF08
PTRL    = $BF09         ; 16-bit line cursor
PTRH    = $BF0A
HASNAME = $BF0B         ; 1 if a filename was supplied
LINENO  = $BF0C         ; current line number while listing
KLEN    = $BF0D         ; bytes to insert (line length + 1 for LF)
DIGIT   = $BF0E         ; DECOUT tens scratch
CMDCH   = $BF0F         ; current command letter

        .org $A700
; =============================================================================
; Entry
; =============================================================================
START:  JSR  SETNAME            ; arg (P2) -> FNAME; HASNAME set
        LDA  #<TBUF             ; empty buffer: TEND = TBUF
        STA  TENDL
        LDA  #>TBUF
        STA  TENDH
        LDA  HASNAME
        JZ   BANNER             ; no name -> empty new buffer
        JSR  FFIND              ; existing file? loads LBA + FLEN
        JC   BANNER             ; not found -> new file
        JSR  LOADFILE
BANNER: LDP1 #MBANNER
        JSR  PUTS

; =============================================================================
; Command loop
; =============================================================================
MAIN:   LDP1 #MPROMPT
        JSR  PUTS
        JSR  GETLINE
        LDP1 #LBUF              ; parse: skip spaces, grab command letter
        JSR  SKIPSP1
        LDA  (P1)
        JZ   MAIN               ; blank line
        JSR  UPCASE
        STA  CMDCH
        INP1
        JSR  PARSEARG           ; ARGN <- trailing decimal (0 if none)
        LDA  CMDCH
        LDB  #'L'
        CMP
        JZ   CMD_L
        LDB  #'A'
        CMP
        JZ   CMD_A
        LDB  #'I'
        CMP
        JZ   CMD_I
        LDB  #'D'
        CMP
        JZ   CMD_D
        LDB  #'W'
        CMP
        JZ   CMD_W
        LDB  #'Q'
        CMP
        JZ   CMD_Q
        LDB  #'?'
        CMP
        JZ   CMD_H
        LDP1 #MERR
        JSR  PUTS
        JMP  MAIN

CMD_Q:  RTS                     ; back to the OS shell

CMD_H:  LDP1 #MHELP
        JSR  PUTS
        JMP  MAIN

; ---- L: list -----------------------------------------------------------------
CMD_L:  LDA  #<TBUF
        STA  PTRL
        LDA  #>TBUF
        STA  PTRH
        LDA  #1
        STA  LINENO
CL_LP:  JSR  PTR_AT_END
        JZ   CL_DONE
        LDA  LINENO
        JSR  DECOUT
        LDA  #' '
        JSR  CONOUT
        LDA  PTRL
        TAP1L
        LDA  PTRH
        TAP1H
CL_CH:  TPA1L
        LDB  TENDL
        CMP
        JNZ  CL_PR
        TPA1H
        LDB  TENDH
        CMP
        JZ   CL_EOL
CL_PR:  LDA  (P1)+
        STA  TMP
        LDB  #LF
        CMP
        JZ   CL_EOL
        LDA  TMP
        JSR  CONOUT
        JMP  CL_CH
CL_EOL: TPA1L
        STA  PTRL
        TPA1H
        STA  PTRH
        LDA  #CR
        JSR  CONOUT
        LDA  #LF
        JSR  CONOUT
        LDA  LINENO
        INC
        STA  LINENO
        JMP  CL_LP
CL_DONE:JMP  MAIN

; ---- A: append ---------------------------------------------------------------
; The append cursor lives in SRC, not P2 — GETLINE clobbers P2 each line, so we
; reload P2 from SRC before copying and save it back after.
CMD_A:  LDA  TENDL
        STA  SRCL
        LDA  TENDH
        STA  SRCH
CA_LP:  JSR  GETLINE
        LDA  LBUF               ; "." alone ends input
        LDB  #'.'
        CMP
        JNZ  CA_ST
        LDA  LBUF+1
        JZ   CA_FIN
CA_ST:  LDA  SRCL               ; P2 = append cursor
        TAP2L
        LDA  SRCH
        TAP2H
        LDP1 #LBUF
CA_CP:  LDA  (P1)+
        JZ   CA_EOL
        STA  TMP
        JSR  ROOMQ
        JZ   CA_FULL
        LDA  TMP
        STA  (P2)+
        JMP  CA_CP
CA_EOL: JSR  ROOMQ
        JZ   CA_FULL
        LDA  #LF
        STA  (P2)+
        TPA2L                   ; save cursor for the next line
        STA  SRCL
        TPA2H
        STA  SRCH
        JMP  CA_LP
CA_FIN: LDA  SRCL               ; commit TEND = cursor
        STA  TENDL
        LDA  SRCH
        STA  TENDH
        JMP  MAIN
CA_FULL:TPA2L                   ; commit the partial line we managed to store
        STA  TENDL
        TPA2H
        STA  TENDH
        LDP1 #MFULL
        JSR  PUTS
        JMP  MAIN

; ---- D: delete line ARGN -----------------------------------------------------
CMD_D:  JSR  LINESTART          ; PTR = start of line ARGN; TMP2 = found?
        LDA  TMP2
        JZ   CD_NONE
        LDA  PTRL               ; S (destination) saved in SRC
        STA  SRCL
        LDA  PTRH
        STA  SRCH
        JSR  ADVLINE            ; PTR = E (start of next line / TEND)
        LDA  PTRL               ; P1 = E (source)
        TAP1L
        LDA  PTRH
        TAP1H
        LDA  SRCL               ; P2 = S (destination)
        TAP2L
        LDA  SRCH
        TAP2H
CD_CP:  TPA1L
        LDB  TENDL
        CMP
        JNZ  CD_GO
        TPA1H
        LDB  TENDH
        CMP
        JZ   CD_END
CD_GO:  LDA  (P1)+
        STA  (P2)+
        JMP  CD_CP
CD_END: TPA2L
        STA  TENDL
        TPA2H
        STA  TENDH
        JMP  MAIN
CD_NONE:LDP1 #MNOLINE
        JSR  PUTS
        JMP  MAIN

; ---- I: insert before line ARGN ----------------------------------------------
CMD_I:  JSR  LINESTART          ; PTR = start of line ARGN (or TEND if past)
        LDA  PTRL               ; S = insertion point
        STA  SRCL
        LDA  PTRH
        STA  SRCH
CI_LP:  JSR  GETLINE
        LDA  LBUF
        LDB  #'.'
        CMP
        JNZ  CI_INS
        LDA  LBUF+1
        JZ   MAIN               ; "." -> done
CI_INS: JSR  STRLEN             ; A = line length
        LDB  #1                 ; K = length + 1 (for the LF)
        ADD
        JSR  CHKINS             ; sets KLEN; Z=1 if no room
        JZ   CI_FULL
        JSR  GAPOPEN            ; open KLEN-byte gap at S; TEND += KLEN
        LDA  SRCL               ; write line + LF at S
        TAP2L
        LDA  SRCH
        TAP2H
        LDP1 #LBUF
CIW:    LDA  (P1)+
        JZ   CIW_LF
        STA  (P2)+
        JMP  CIW
CIW_LF: LDA  #LF
        STA  (P2)+
        TPA2L                   ; advance S past the inserted line
        STA  SRCL
        TPA2H
        STA  SRCH
        JMP  CI_LP
CI_FULL:LDP1 #MFULL
        JSR  PUTS
        JMP  MAIN

; ---- W: write file -----------------------------------------------------------
CMD_W:  LDA  HASNAME
        JZ   CW_NON
        LDA  #<TBUF             ; FSRC = TBUF
        STA  FSRC
        LDA  #>TBUF
        STA  FSRC+1
        LDA  TENDL              ; FLEN = TEND - TBUF (TBUF low byte = 0)
        STA  FLEN
        LDA  TENDH
        LDB  #>TBUF
        SUB
        STA  FLEN+1
        JSR  FDELETE            ; remove old version (ignore "not found")
        JSR  FCREATE
        JC   CW_ERR
        LDP1 #MSAVED
        JSR  PUTS
        JMP  MAIN
CW_ERR: LDP1 #MWERR
        JSR  PUTS
        JMP  MAIN
CW_NON: LDP1 #MNONAME
        JSR  PUTS
        JMP  MAIN

; =============================================================================
; Helpers
; =============================================================================

; ---- LOADFILE: read FLEN bytes (FFIND result) from LBA into TBUF -------------
; LOADFILE - slurp the FFIND'd file (LBA + FLEN) into TBUF via the BIOS bulk
; reader, then set TEND = TBUF + FLEN.
LOADFILE:
        LDP1 #TBUF
        JSR  FLOADAT            ; read FLEN bytes from LBA into TBUF
        LDA  #<TBUF             ; TEND = TBUF + FLEN
        LDB  FLEN
        ADD
        STA  TENDL
        LDA  #>TBUF
        JNC  LD_TH
        INC
LD_TH:  LDB  FLEN+1
        ADD
        STA  TENDH
        RTS

; ---- SETNAME: arg at P2 -> FNAME (12 bytes, upcased, space-padded) -----------
SETNAME:LDP1 #FNAME             ; pad with spaces first
        LDA  #12
        STA  TMP
SN_PAD: LDA  #' '
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  SN_PAD
SN_SK:  LDA  (P2)               ; skip leading spaces in the arg
        JZ   SN_EMPTY
        LDB  #' '
        CMP
        JNZ  SN_GO
        INP2
        JMP  SN_SK
SN_GO:  LDP1 #FNAME
        LDA  #12
        STA  TMP
SN_CP:  LDA  (P2)
        JZ   SN_SET
        LDB  #' '
        CMP
        JZ   SN_SET
        LDA  (P2)
        JSR  UPCASE
        STA  (P1)+
        INP2
        LDA  TMP
        DEC
        STA  TMP
        JNZ  SN_CP
SN_SET: LDA  #1
        STA  HASNAME
        RTS
SN_EMPTY:LDA #0
        STA  HASNAME
        RTS

; ---- GETLINE: read a line into LBUF (echo, backspace), null-terminate --------
GETLINE:LDP2 #LBUF
GL_LP:  JSR  CONIN
        STA  TMP
        LDB  #CR
        CMP
        JZ   GL_END
        LDA  TMP                ; backspace?
        LDB  #BS
        CMP
        JZ   GL_BS
        LDA  TMP
        LDB  #DEL
        CMP
        JZ   GL_BS
        LDA  TMP                ; ordinary char: echo + store
        JSR  CONOUT
        STA  (P2)+
        JMP  GL_LP
GL_BS:  TPA2L                   ; at start of LBUF? (page-aligned)
        LDB  #<LBUF
        CMP
        JNZ  GL_BSDO
        TPA2H
        LDB  #>LBUF
        CMP
        JZ   GL_LP              ; nothing to erase
GL_BSDO:DEP2
        LDA  #BS
        JSR  CONOUT
        LDA  #' '
        JSR  CONOUT
        LDA  #BS
        JSR  CONOUT
        JMP  GL_LP
GL_END: LDA  #CR
        JSR  CONOUT
        LDA  #LF
        JSR  CONOUT
        LDA  #0
        STA  (P2)
        RTS

; ---- SKIPSP1: advance P1 past spaces -----------------------------------------
SKIPSP1:LDA  (P1)
        LDB  #' '
        CMP
        JNZ  SS_D
        INP1
        JMP  SKIPSP1
SS_D:   RTS

; ---- PARSEARG: P1 -> trailing decimal digits -> ARGN (8-bit) -----------------
PARSEARG:LDA #0
        STA  ARGN
        JSR  SKIPSP1
PA_LP:  LDA  (P1)
        STA  TMP2
        LDB  #'0'
        CMP                     ; C = c >= '0'
        JNC  PA_D
        LDA  #'9'
        LDB  TMP2
        CMP                     ; C = '9' >= c
        JNC  PA_D
        LDA  ARGN               ; ARGN = ARGN*10 + (c - '0')
        SHL
        STA  TMP                ; ARGN*2
        SHL
        SHL                     ; ARGN*8
        LDB  TMP
        ADD                     ; ARGN*10
        STA  TMP
        LDA  TMP2
        LDB  #'0'
        SUB                     ; c - '0'
        LDB  TMP
        ADD
        STA  ARGN
        INP1
        JMP  PA_LP
PA_D:   RTS

; ---- UPCASE: A -> uppercase if 'a'..'z' --------------------------------------
UPCASE: STA  TMP2
        LDB  #'a'
        CMP                     ; C = A >= 'a'
        JNC  UC_NO
        LDA  #'z'
        LDB  TMP2
        CMP                     ; C = 'z' >= A
        JNC  UC_NO
        LDA  TMP2
        LDB  #$20
        SUB
        RTS
UC_NO:  LDA  TMP2
        RTS

; ---- DECOUT: print A (0..255) as decimal, no leading zeros -------------------
DECOUT: STA  TMP
        LDA  #0
        STA  TMP2               ; hundreds
DO_H:   LDA  TMP
        LDB  #100
        CMP
        JNC  DO_T
        LDB  #100
        SUB
        STA  TMP
        LDA  TMP2
        INC
        STA  TMP2
        JMP  DO_H
DO_T:   LDA  #0
        STA  DIGIT              ; tens
DO_TL:  LDA  TMP
        LDB  #10
        CMP
        JNC  DO_P
        LDB  #10
        SUB
        STA  TMP
        LDA  DIGIT
        INC
        STA  DIGIT
        JMP  DO_TL
DO_P:   LDA  TMP2               ; print hundreds if nonzero
        JZ   DO_NOH
        LDB  #'0'
        ADD
        JSR  CONOUT
        LDA  #1                 ; force tens to print too
        STA  TMP2
        JMP  DO_TENS
DO_NOH: LDA  #0
        STA  TMP2
DO_TENS:LDA  DIGIT
        JNZ  DO_PT
        LDA  TMP2
        JZ   DO_ONES
DO_PT:  LDA  DIGIT
        LDB  #'0'
        ADD
        JSR  CONOUT
DO_ONES:LDA  TMP
        LDB  #'0'
        ADD
        JSR  CONOUT
        RTS

; ---- STRLEN: A = length of null-terminated LBUF ------------------------------
STRLEN: LDP1 #LBUF
        LDA  #0
        STA  TMP
SL_LP:  LDA  (P1)+
        JZ   SL_D
        LDA  TMP
        INC
        STA  TMP
        JMP  SL_LP
SL_D:   LDA  TMP
        RTS

; ---- PTR_AT_END: Z=1 if PTR == TEND ------------------------------------------
PTR_AT_END:
        LDA  PTRL
        LDB  TENDL
        CMP
        JNZ  PAE_NO
        LDA  PTRH
        LDB  TENDH
        CMP
        JNZ  PAE_NO
        LDA  #0                 ; equal -> Z=1
        RTS
PAE_NO: LDA  #1                 ; not equal -> Z=0
        RTS

; ---- ROOMQ: Z=1 if P2 == text ceiling (buffer full) --------------------------
ROOMQ:  TPA2L
        LDB  #TMAXL
        CMP
        JNZ  RQ_NO
        TPA2H
        LDB  #TMAXH
        CMP
        JZ   RQ_YES
RQ_NO:  LDA  #1                 ; room -> Z=0
        RTS
RQ_YES: LDA  #0                 ; full -> Z=1
        RTS

; ---- ADVLINE: advance PTR to the start of the next line ----------------------
ADVLINE:LDA  PTRL
        TAP1L
        LDA  PTRH
        TAP1H
AL_LP:  TPA1L
        LDB  TENDL
        CMP
        JNZ  AL_NE
        TPA1H
        LDB  TENDH
        CMP
        JZ   AL_END
AL_NE:  LDA  (P1)+
        LDB  #LF
        CMP
        JZ   AL_END
        JMP  AL_LP
AL_END: TPA1L
        STA  PTRL
        TPA1H
        STA  PTRH
        RTS

; ---- LINESTART: PTR = start of line ARGN; TMP2 = 1 found / 0 past end ---------
LINESTART:
        LDA  #<TBUF
        STA  PTRL
        LDA  #>TBUF
        STA  PTRH
        LDA  ARGN               ; lines to skip = ARGN - 1 (line N is 1-based)
        JZ   LS_Z0              ; ARGN 0 -> treat as line 1 (skip none)
        LDB  #1
        SUB
        STA  TMP
        JMP  LS_CHK
LS_Z0:  LDA  #0
        STA  TMP
LS_CHK: LDA  TMP
        LDB  #1
        CMP                     ; C = TMP >= 1
        JNC  LS_HERE            ; TMP == 0 -> at target line start
        JSR  PTR_AT_END
        JZ   LS_PAST            ; ran off the end first
        JSR  ADVLINE
        LDA  TMP
        DEC
        STA  TMP
        JMP  LS_CHK
LS_HERE:JSR  PTR_AT_END
        JZ   LS_PAST
        LDA  #1
        STA  TMP2
        RTS
LS_PAST:LDA  #0
        STA  TMP2
        RTS

; ---- CHKINS: A = K; sets KLEN; Z=1 if TEND+K would exceed the ceiling --------
CHKINS: STA  KLEN
        LDA  TENDL
        LDB  KLEN
        ADD
        STA  CNTL
        LDA  TENDH
        JNC  CI_1
        INC
CI_1:   STA  CNTH               ; CNT = TEND + K
        LDA  #TMAXH
        LDB  CNTH
        CMP
        JNZ  CI_HI
        LDA  #TMAXL             ; hi equal -> compare lo
        LDB  CNTL
        CMP
        JC   CI_OK
        JMP  CI_NO
CI_HI:  JC   CI_OK              ; TMAXH != CNTH: room iff TMAXH > CNTH
        JMP  CI_NO
CI_OK:  LDA  #1                 ; room -> Z=0
        RTS
CI_NO:  LDA  #0                 ; no room -> Z=1
        RTS

; ---- GAPOPEN: shift [S..TEND) up by KLEN; TEND += KLEN (backward copy) --------
GAPOPEN:LDA  TENDL              ; CNT = TEND - S
        LDB  SRCL
        SUB
        STA  CNTL
        LDA  #0
        JC   GO_NB
        LDA  #1
GO_NB:  STA  TMP2               ; borrow
        LDA  TENDH
        LDB  SRCH
        SUB
        STA  CNTH
        LDA  TMP2
        JZ   GO_HOK
        LDA  CNTH
        LDB  #1
        SUB
        STA  CNTH
GO_HOK: LDA  TENDL              ; P1 = TEND (src top, DEP before read)
        TAP1L
        LDA  TENDH
        TAP1H
        LDA  TENDL              ; P2 = TEND + K (dst top)
        LDB  KLEN
        ADD
        TAP2L
        LDA  TENDH
        JNC  GO_DH
        INC
GO_DH:  TAP2H
GO_LP:  LDA  CNTL
        LDB  CNTH
        OR
        JZ   GO_END
        DEP1
        DEP2
        LDA  (P1)
        STA  (P2)
        LDA  CNTL
        LDB  #1
        SUB
        STA  CNTL
        JC   GO_LP
        LDA  CNTH
        LDB  #1
        SUB
        STA  CNTH
        JMP  GO_LP
GO_END: LDA  TENDL              ; TEND += K
        LDB  KLEN
        ADD
        STA  TENDL
        LDA  TENDH
        JNC  GO_X
        INC
GO_X:   STA  TENDH
        RTS

; =============================================================================
; Messages
; =============================================================================
MBANNER:.byte CR,LF
        .ascii "P8X EDIT  ? for help"
        .byte CR,LF,0
MPROMPT:.ascii ": "
        .byte 0
MHELP:  .ascii "L list  A append  I n insert  D n delete  W write  Q quit"
        .byte CR,LF,0
MERR:   .ascii "?"
        .byte CR,LF,0
MFULL:  .ascii "BUFFER FULL"
        .byte CR,LF,0
MNOLINE:.ascii "NO SUCH LINE"
        .byte CR,LF,0
MSAVED: .ascii "SAVED"
        .byte CR,LF,0
MWERR:  .ascii "WRITE ERROR"
        .byte CR,LF,0
MNONAME:.ascii "NO FILENAME"
        .byte CR,LF,0
