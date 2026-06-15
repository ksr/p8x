; countdown: prints 9876543210 using CMP/BZ/DEC
ACIA_D = $FF05
        .org 0
        LDP2 #ACIA_D
        LDA  #'9'
        LDB  #'0'
loop:   STA  (P2)
        CMP             ; A-B -> flags only
        BZ   done
        DEC
        JMP  loop
done:   HLT
