; BIOS path-aware write exerciser — planted as the "OS" at LBA 1, booted to $4000.
; Resolves "/SUB/W", writes "HI" into it via the write stream, then resolves and
; reads it back via the read stream, echoing the bytes. Clean output is "HI";
; 'E' on any error. (/SUB must already exist on the disk.)
CONOUT  = $0103
FOPEN   = $0124
FGETB   = $0127
FWOPEN  = $012A
FPUTB   = $012D
FCLOSE  = $0130
FRESOLVE= $0133
        .org $4000
        LDP1 #PATHSTR       ; resolve target -> DIRLBA=/SUB, FNAME="W"
        JSR  FRESOLVE
        JC   ERR
        JSR  FWOPEN
        LDA  #'H'
        JSR  FPUTB
        LDA  #'I'
        JSR  FPUTB
        JSR  FCLOSE         ; writes /SUB/W
        JC   ERR
        LDP1 #PATHSTR       ; resolve again for the read
        JSR  FRESOLVE
        JC   ERR
        LDP1 #$6000
        JSR  FOPEN
        JC   ERR
LP:     JSR  FGETB
        JC   DONE
        JSR  CONOUT
        JMP  LP
DONE:   HLT
ERR:    LDA  #'E'
        JSR  CONOUT
        HLT
PATHSTR: .ascii "/SUB/W"
        .byte 0
