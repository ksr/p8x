; P8X smoke test: print message via ACIA, halt
ACIA_D = $FF05

        .org 0
        LDP2 #ACIA_D
        LDP1 #msg
        LDB  #0
loop:   LDA  (P1)+
        OR              ; A|=0 -> sets Z on terminator
        BZ   done
        STA  (P2)
        JMP  loop
done:   HLT

msg:    .asciiz "P8X lives! same ucode as the EPROMs\r\n"
