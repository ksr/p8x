; BIOS read-stream exerciser — planted as the "OS" at LBA 1, booted to $2000.
; Creates root file "T" holding "FSOK" (FCREATE), then opens it with FOPEN and
; reads it back a byte at a time with FGETB, echoing each byte. Clean output is
; "FSOK"; 'E' on any error.
CONOUT  = $0103
FCREATE = $011B
FOPEN   = $0124
FGETB   = $0127
HEXL    = $1F42
FNAME   = $1F4A
FSRC    = $1F56
FLEN    = $1F58
        .org $2000
        LDP1 #FNAME         ; FNAME = "T" + 11 spaces
        LDA  #'T'
        STA  (P1)+
        LDA  #11
        STA  HEXL
PAD:    LDA  #' '
        STA  (P1)+
        LDA  HEXL
        DEC
        STA  HEXL
        JNZ  PAD
        LDA  #'F'           ; source data "FSOK" at $5000
        STA  $5000
        LDA  #'S'
        STA  $5001
        LDA  #'O'
        STA  $5002
        LDA  #'K'
        STA  $5003
        LDA  #$00           ; FSRC = $5000
        STA  FSRC
        LDA  #$50
        STA  FSRC+1
        LDA  #4             ; FLEN = 4
        STA  FLEN
        LDA  #0
        STA  FLEN+1
        JSR  FCREATE
        JC   ERR
        LDP1 #$8000         ; FOPEN with a 512-byte buffer at $8000
        JSR  FOPEN
        JC   ERR
LP:     JSR  FGETB
        JC   DONE           ; C=1 -> end of file
        JSR  CONOUT
        JMP  LP
DONE:   HLT
ERR:    LDA  #'E'
        JSR  CONOUT
        HLT
