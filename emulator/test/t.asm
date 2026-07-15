        .include "../inc/eq.inc"
        .org $6A00
        LDA #FOO
        JSR $0103
        LDA #$0D
        JSR $0103
        LDA #$0A
        JSR $0103
        RTS
