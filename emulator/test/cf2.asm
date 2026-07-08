        ; Position-independent (fixed BIOS/ABI addresses only): assembles at org 0,
        ; planted at LBA 1, booted to $4000. drive 0 was CFINIT'd by the boot.
        ; Marker $B0 -> drive0 LBA 40.
        LDA  #40
        STA  $7047
        LDA  #0
        STA  $7048
        STA  $7049
        LDA  #$B0
        STA  $7100          ; SBUF[0]
        JSR  $010F          ; CFWRITE (drive 0)
        ; select + init drive 1, marker $A1 -> drive1 LBA 40 (same LBA)
        LDA  #1
        JSR  $0148          ; CFSEL(1)
        JSR  $0109          ; CFINIT drive 1 (bounded; C=1 if absent)
        LDA  #40
        STA  $7047
        LDA  #0
        STA  $7048
        STA  $7049
        LDA  #$A1
        STA  $7100
        JSR  $010F          ; CFWRITE (drive 1)
        ; read drive1 LBA 40 -> print byte
        LDA  #40
        STA  $7047
        LDP1 #$7100
        JSR  $010C          ; CFREAD (drive 1)
        LDA  $7100
        JSR  $0115          ; PHEX8 -> "A1" (or "FF" if drive 1 absent)
        ; select drive 0, read LBA 40 -> print byte (must still be $B0)
        LDA  #0
        JSR  $0148          ; CFSEL(0)
        LDA  #40
        STA  $7047
        LDP1 #$7100
        JSR  $010C          ; CFREAD (drive 0)
        LDA  $7100
        JSR  $0115          ; PHEX8 -> "B0"
        HLT
