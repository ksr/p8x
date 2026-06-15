; JSR/RTS round trip: expect A=$43, SP=$FEFF at halt
        .org 0
        LDP1 #sub
        LDA  #'A'
        JSR  (P1)
        HLT
        .org $20
sub:    INC
        INC
        RTS
