; BIOS FDELETE exerciser — planted as the "OS" at LBA 1, booted to $4000.
; Creates root file "TEST", deletes it via FDELETE (expects C=0), then FFIND
; must report not-found (C=1). Prints 'Y' on success; 'E' create error,
; 'D' delete-not-found, 'N' file still found after delete.
CONOUT  = $0103
FFIND   = $0118
FCREATE = $011B
FDELETE = $011E
FNAME   = $9D4A
FSRC    = $9D56
FLEN    = $9D58
        .org $4000
        LDA  #'T'           ; FNAME = "TEST" + 8 spaces
        STA  FNAME
        LDA  #'E'
        STA  FNAME+1
        LDA  #'S'
        STA  FNAME+2
        LDA  #'T'
        STA  FNAME+3
        LDA  #' '
        STA  FNAME+4
        STA  FNAME+5
        STA  FNAME+6
        STA  FNAME+7
        STA  FNAME+8
        STA  FNAME+9
        STA  FNAME+10
        STA  FNAME+11
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
        JNC  FC_OK
        LDA  #'E'
        JSR  CONOUT
        HLT
FC_OK:  JSR  FDELETE        ; FNAME still "TEST" -> tombstone it
        JNC  FD_OK
        LDA  #'D'
        JSR  CONOUT
        HLT
FD_OK:  JSR  FFIND          ; must now be not found (C=1)
        JC   GONE
        LDA  #'N'
        JSR  CONOUT
        HLT
GONE:   LDA  #'Y'
        JSR  CONOUT
        HLT
