; High-LBA BIOS exerciser — planted as the "OS" at LBA 1 and booted to $4000.
; Proves the multi-byte LBA ABI: CFSETL must honour LBA1 ($9D48), so a sector
; number >255 reaches the right place instead of wrapping mod 256.
;   1. read sector 300 ($012C) — host seeds it with "LBAHI!" — and echo 6 bytes.
;      (if LBA1 were ignored it would read sector 44 = zeros, printing nothing.)
;   2. write "WR301" to sector 301 ($012D); the harness then checks the image
;      landed it at sector 301, NOT sector 45 (301 mod 256).
; Position-independent (no internal labels — all addresses are fixed BIOS
; entries / ABI RAM), so it assembles at org 0 and runs wherever booted.
CFINIT  = $0109
CFREAD  = $010C
CFWRITE = $010F
CONOUT  = $0103
LBA     = $9D47
LBA1    = $9D48
SBUF    = $9E00
RBUF    = $8400

        JSR  CFINIT          ; resets LBA1/LBA2 to 0
        ; --- read sector 300 -> RBUF ---
        LDA  #$2C
        STA  LBA             ; LBA0
        LDA  #$01
        STA  LBA1            ; LBA1 -> sector $012C = 300
        LDP1 #RBUF
        JSR  CFREAD
        ; --- echo the 6-byte signature read back ---
        LDP1 #RBUF
        LDA  (P1)+
        JSR  CONOUT
        LDA  (P1)+
        JSR  CONOUT
        LDA  (P1)+
        JSR  CONOUT
        LDA  (P1)+
        JSR  CONOUT
        LDA  (P1)+
        JSR  CONOUT
        LDA  (P1)+
        JSR  CONOUT
        ; --- write "WR301" to sector 301 (LBA1 still 1) ---
        LDA  #'W'
        STA  SBUF
        LDA  #'R'
        STA  SBUF+1
        LDA  #'3'
        STA  SBUF+2
        LDA  #'0'
        STA  SBUF+3
        LDA  #'1'
        STA  SBUF+4
        LDA  #$2D
        STA  LBA             ; LBA0 -> sector $012D = 301
        JSR  CFWRITE
        HLT
