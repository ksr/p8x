; rev E memory-map check: $2000-$FEFF is RAM (OS loads at $2000); spot-check $5000.
; Write a sentinel into the new bank, read it back; print 'Y' on match, 'N' if
; the write was swallowed (i.e. still decoded as ROM).
ACIA_D = $FF05
        .org 0
        LDA  #$A5
        STA  $5000          ; RAM ($2000-$FEFF)
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
