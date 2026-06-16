;==============================================================================
; P8X BASIC — interpreter for the P8X TTL computer  (SKELETON)
;
; Boots at $0000 (EEPROM), 6850 ACIA console at $FF04/05.
; Current scope: banner + read-line REPL (line input with echo + backspace).
; Tokenizing / storage / execution are TODO — see basic/README.md milestones.
;==============================================================================

; ---------------- Equates ----------------------------------------------------
ACIAS  = $FF04          ; ACIA status (rd) / control (wr)
ACIAD  = $FF05          ; ACIA data
CR     = $0D
LF     = $0A
BS     = $08
LBUF   = $8000          ; input line buffer
STKTOP = $FEFF          ; P3 stack top

        .org $0000
        LDP3 #STKTOP
        LDA  #$03            ; ACIA master reset
        STA  ACIAS
        LDA  #$15            ; /16 clock, 8N1, no IRQ
        STA  ACIAS
        LDP1 #BANNER
        JSR  PUTS

; ---------------- REPL -------------------------------------------------------
REPL:   LDP1 #MREADY
        JSR  PUTS
        JSR  GETLINE         ; line -> LBUF (0-terminated)
        ; TODO milestone 2+: parse line number / immediate, store or execute.
        JMP  REPL

;==============================================================================
; CONSOLE
;==============================================================================
PUTC:   PHA
PUTC1:  LDA  ACIAS
        LDB  #$02            ; TDRE
        AND
        JZ   PUTC1
        PLA
        STA  ACIAD
        RTS

GETC:   LDA  ACIAS
        LDB  #$01            ; RDRF
        AND
        JZ   GETC
        LDA  ACIAD
        RTS

PUTS:   LDA  (P1)+           ; print zero-terminated string at (P1)
        JZ   PUTSX
        JSR  PUTC
        JMP  PUTS
PUTSX:  RTS

CRLF:   LDA  #CR
        JSR  PUTC
        LDA  #LF
        JSR  PUTC
        RTS

GETLINE:                     ; read a line (echo + backspace) -> LBUF, 0-term
        LDP2 #LBUF
GL1:    JSR  GETC
        LDB  #CR
        CMP
        JZ   GLDONE
        LDB  #BS
        CMP
        JZ   GLBS
        LDB  #$7F
        CMP
        JZ   GLBS
        JSR  PUTC            ; echo (PUTC preserves A)
        STA  (P2)+
        JMP  GL1
GLBS:   TPA2L               ; non-empty? (low byte past LBUF start)
        LDB  #<LBUF
        CMP
        JZ   GL1
        DEP2
        LDA  #BS
        JSR  PUTC
        LDA  #' '
        JSR  PUTC
        LDA  #BS
        JSR  PUTC
        JMP  GL1
GLDONE: LDA  #0
        STA  (P2)
        JSR  CRLF
        RTS

;==============================================================================
; MESSAGES
;==============================================================================
BANNER: .byte CR,LF
        .ascii "P8X BASIC V0 (skeleton)"
        .byte CR,LF,0
MREADY: .ascii "READY"
        .byte CR,LF,0
