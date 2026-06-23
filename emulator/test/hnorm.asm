; BIOS FNORM exerciser — planted as the "OS" at LBA 1, booted to $4000.
; Formats the lowercase string "hi.c" into FNAME with FNORM, then FCREATEs a
; 1-byte file by that name. Prints 'Y' on success ('E' on error). The host then
; checks the directory holds the upper-cased, padded name "HI.C".
CONOUT  = $0103
FCREATE = $011B
FNORM   = $0136
FSRC    = $9D56
FLEN    = $9D58
        .org $4000
        LDA  #'X'           ; 1 byte of file data at $5000
        STA  $5000
        LDA  #$00
        STA  FSRC
        LDA  #$50
        STA  FSRC+1
        LDA  #1
        STA  FLEN
        LDA  #0
        STA  FLEN+1
        LDP1 #NAMESTR
        JSR  FNORM          ; FNAME <- "HI.C" upper-cased, space-padded
        JSR  FCREATE
        JC   ERR
        LDA  #'Y'
        JSR  CONOUT
        HLT
ERR:    LDA  #'E'
        JSR  CONOUT
        HLT
NAMESTR: .ascii "hi.c"
        .byte 0
