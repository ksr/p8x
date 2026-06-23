CR = $0D
LF = $0A
        .org $B000
        LDP1 #msg
lp:     LDA (P1)+
        JZ   done
        JSR  $0103
        JMP  lp
done:   LDA  #<msg
        LDB  #>msg
        ADD
        RTS
msg:    .asciiz "HELLO-ASM"
        .byte CR,LF
