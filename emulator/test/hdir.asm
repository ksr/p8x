; BIOS directory-iteration exerciser — planted as the "OS" at LBA 1, booted to
; $4000. Iterates the root directory with FOPENDIR/FNEXT and prints the first
; character of each live entry's name. With files A and B present the output is
; "AB"; 'E' on a FOPENDIR error.
CONOUT  = $0103
FOPENDIR= $0139
FNEXT   = $013C
FNAME   = $704A
        .org $4000
        LDP1 #ROOTSTR
        JSR  FOPENDIR       ; iterate the root
        JC   ERR
LP:     JSR  FNEXT
        JC   DONE           ; C=1 -> no more entries
        LDA  FNAME          ; first char of this entry's name
        JSR  CONOUT
        JMP  LP
DONE:   HLT
ERR:    LDA  #'E'
        JSR  CONOUT
        HLT
ROOTSTR: .ascii "/"
        .byte 0
