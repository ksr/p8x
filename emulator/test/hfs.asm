; BIOS filesystem-API exerciser — planted as the "OS" at LBA 1, booted to $4000.
; Creates a root file "TEST" holding "FSOK" via FCREATE, finds it via FFIND,
; reads its sector back, and prints 'Y' on a clean round-trip ('E' = FCREATE
; error, 'N' = not found / data mismatch).
CONOUT  = $0103
CFREAD  = $010C
FFIND   = $0118
FCREATE = $011B
FNAME   = $704A
FSRC    = $7056
FLEN    = $7058
        .org $4000          ; booted to $4000 (has internal labels -> not PIC)
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
FC_OK:  JSR  FFIND          ; FNAME still "TEST" -> sets LBA + FLEN
        JNC  FN_OK
        LDA  #'N'
        JSR  CONOUT
        HLT
FN_OK:  LDP1 #$6000         ; read the file's first sector into $6000
        JSR  CFREAD
        LDA  $6000
        LDB  #'F'
        CMP
        JNZ  BAD
        LDA  $6001
        LDB  #'S'
        CMP
        JNZ  BAD
        LDA  $6002
        LDB  #'O'
        CMP
        JNZ  BAD
        LDA  $6003
        LDB  #'K'
        CMP
        JNZ  BAD
        LDA  #'Y'
        JSR  CONOUT
        HLT
BAD:    LDA  #'N'
        JSR  CONOUT
        HLT
