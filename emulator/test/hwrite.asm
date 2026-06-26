; BIOS write-stream exerciser — planted as the "OS" at LBA 1, booted to $4000.
; Writes "HELLO" to a new file "W" with FWOPEN/FPUTB/FCLOSE, then reads it back
; with FOPEN/FGETB and echoes it. Clean output is "HELLO"; 'E' on any error.
CONOUT  = $0103
FOPEN   = $0124
FGETB   = $0127
FWOPEN  = $012A
FPUTB   = $012D
FCLOSE  = $0130
HEXL    = $7042
FNAME   = $704A
        .org $4000
        JSR  FWOPEN
        LDA  #'H'
        JSR  FPUTB
        LDA  #'E'
        JSR  FPUTB
        LDA  #'L'
        JSR  FPUTB
        LDA  #'L'
        JSR  FPUTB
        LDA  #'O'
        JSR  FPUTB
        LDP1 #FNAME         ; FNAME = "W" + 11 spaces
        LDA  #'W'
        STA  (P1)+
        LDA  #11
        STA  HEXL
PAD:    LDA  #' '
        STA  (P1)+
        LDA  HEXL
        DEC
        STA  HEXL
        JNZ  PAD
        JSR  FCLOSE
        JC   ERR
        LDP1 #$6000         ; read it back through the read stream
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
