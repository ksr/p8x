; lib_abi.inc — the BIOS/OS entry-point address book for hand-asm /BIN commands.
; A twin declares `;#use abi` and mkasm.sh appends this file, after which it can
; `JSR FOPEN` / `JSR SYS_PUTC` instead of hand-coding `JSR $0124` / `JSR $2009`.
;
; These are pure equates: they emit NO bytes, so a twin that switches its raw
; `JSR $NNNN` calls to symbolic ones assembles to the byte-identical binary — the
; magic numbers just get names, and the firmware jump table / syscall vector can
; be renumbered by editing this one file. (The C side splits the same names across
; lib_fsread/fswrite/fsdir/con.c because there each wrapper costs code space; on
; the asm side an equate is free, so one address book is simplest.)
;
; Unused equates are harmless, so a twin can blanket `;#use abi` even if it only
; needs a couple — which also lets a shared include, e.g. lib_stdin.inc, use these
; names as long as its host command pulls in this file too.

; --- OS syscalls ($20xx) — the redirectable stream + FS/CWD calls ---
SYS_GETCWD   = $2003    ; copy CWD path string -> (P1), incl. NUL
SYS_CWDLBA   = $2006    ; CWD directory start LBA -> A
SYS_PUTC     = $2009    ; A -> current stdout (console or redirected file)
SYS_GETC     = $200C    ; next stdin byte -> A (carry/EOF per ABI)
SYS_PUTS     = $200F    ; write (P1) string to stdout
SYS_OPENCWD  = $2012    ; begin iterating the CWD (16-bit LBA)
SYS_DIRENTRY = $201B    ; snapshot the current dir entry -> (P1) 18 bytes
SYS_OPENDIR  = $201E    ; P1 = 16-bit dir start LBA -> open for FNEXT
SYS_MKDIR    = $2021    ; P1 = path -> create a directory; C=1 on real failure

; --- BIOS jump table ($01xx) ---
CONIN      = $0100      ; wait for key, char -> A (raw console, not stdin)
CONOUT     = $0103      ; A -> serial (raw console, not stdout)
PUTS       = $0112      ; print (P1)+ until $00 (raw console)
PHEX8      = $0115      ; print A as two hex digits
FFIND      = $0118      ; root file FNAME -> LBA+FLEN; C=0 found
FCREATE    = $011B      ; create root file FNAME from FSRC/FLEN; C=1 err
FDELETE    = $011E      ; tombstone root file FNAME; C=1 not found
FCOMMIT    = $0121      ; register streamed file (entry+free); C=1 full
FOPEN      = $0124      ; open file FNAME for reading (P1=buffer); C=1 missing
FGETB      = $0127      ; next byte -> A; C=1 at end of file
FWOPEN     = $012A      ; open a write stream at the free pointer (uses SBUF)
FPUTB      = $012D      ; append byte A to the write stream
FCLOSE     = $0130      ; flush + register file FNAME; C=1 full
FRESOLVE   = $0133      ; resolve path (P1) -> dir extent + leaf FNAME; C=1 bad path
FNORM      = $0136      ; copy string (P1) -> FNAME, case-preserved, padded to 12
FOPENDIR   = $0139      ; begin iterating directory at path (P1); C=1 bad path
FNEXT      = $013C      ; next live entry -> FNAME/FFLAG/LBA/FLEN; C=1 at end
FLOADAT    = $013F      ; read FLEN bytes from LBA into (P1) (whole sectors)
FOPENDIRAT = $0142      ; iterate the 4-sector directory at LBA = A (low)+LBA1 (high)
FSDIRBUF   = $0145      ; point FNEXT's sector buffer at page A (call after FOPENDIR)
