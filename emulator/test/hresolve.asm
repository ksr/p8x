; BIOS path-resolution exerciser — planted as the "OS" at LBA 1, booted to $4000.
; Resolves "/SUB/T" with FRESOLVE (descending into the subdirectory), opens it
; with FOPEN, and echoes its bytes via FGETB. Clean output is the file contents
; ("DEEP"); 'E' on any error.
CONOUT  = $0103
FOPEN   = $0124
FGETB   = $0127
FRESOLVE= $0133
        .org $4000
        LDP1 #PATHSTR
        JSR  FRESOLVE       ; DIRLBA/DIRN -> /SUB, FNAME -> "T"
        JC   ERR
        LDP1 #$6000         ; 512-byte read buffer
        JSR  FOPEN          ; opens /SUB/T (FFIND runs in /SUB)
        JC   ERR
LP:     JSR  FGETB
        JC   DONE
        JSR  CONOUT
        JMP  LP
DONE:   HLT
ERR:    LDA  #'E'
        JSR  CONOUT
        HLT
PATHSTR: .ascii "/SUB/T"
        .byte 0
