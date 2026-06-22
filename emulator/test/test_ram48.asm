; rev D memory-map check: $4000-$7FFF must now be RAM (it was ROM in rev C).
; Write a sentinel into the new bank, read it back; print 'Y' on match, 'N' if
; the write was swallowed (i.e. still decoded as ROM).
ACIA_D = $FF05
        .org 0
        LDA  #$A5
        STA  $5000          ; new RAM bank ($4000-$7FFF)
        LDA  #$00           ; clobber A so the readback proves the store stuck
        LDA  $5000
        LDB  #$A5
        CMP
        BZ   good
        LDA  #'N'
        STA  ACIA_D
        HLT
good:   LDA  #'Y'
        STA  ACIA_D
        HLT
