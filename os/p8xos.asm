; p8xos.asm - P8X/OS v1.0, a RAM-resident disk operating system.
;
; Loaded from CompactFlash to $4000 and entered by the ROM monitor's B command
; (which reads OSCNT sectors from LBA 1 and JMPs to $4000). The OS does NOT
; carry its own drivers: it calls the BIOS jump table the monitor publishes at
; $0100 (see firmware/p8xmon.asm), so console + CF access stay in one place.
;
; rev D memory map (16K ROM / 48K RAM) put RAM at $4000, so the OS loads there
; instead of $8000 — the code can now span $4000..$9D46 (~23.8K) before the BIOS
; LBA pointer at $9D47, vs ~7K at $8000. The on-disk OS region (LBA 1..32) caps
; it at 32 sectors / 16K. Data ($A000 vars, $9E00 SBUF, $9D47 LBA) is unchanged.
;
; Build (RAM image, assembled to run at $4000):
;   python3 assembler/p8xasm.py os/p8xos.asm -o p8xos.bin --base 0x4000
; then install on a P8XFS image with:  tools/p8xfs.py boot disk.img p8xos.bin
;
; shell over a P8XFS v2 (hierarchical) volume:
;   DIR [path]         list the current directory, or a given one
;   CD  path           change directory (absolute /a/b, relative, '.'/'..')
;   PWD                print the working-directory path
;   CAT  name          print a file's contents to the console
;   MKDIR path         create a subdirectory (v2; allocates a SUBSECS extent)
;   RMDIR path         remove an empty subdirectory (v2)
;   TREE               depth-first indented listing of the whole tree (v2)
;   LOAD name          read a file into its stored load address
;   RUN  name          LOAD it, then JSR its exec address (program RTS -> shell)
;   SAVE name start end write memory [start,end) to a new file (hex addresses)
;   DEL  name          mark the directory entry deleted ($FF) and write it back
;   DUMP addr          show 256 bytes from addr (hex + ASCII)
;   DEP  addr b b ...  deposit hex byte values starting at addr
;   PACK               compact the data area, reclaiming deleted extents
;   FORMAT             erase the card and lay a fresh P8XFS v2 volume (asks Y/N;
;                      OSCNT preserved so the card stays bootable)
;   HELP
; A file/dir argument may be a path; directory scanning works on any extent
; (start LBA + sector count), so CWD and resolved paths share one code path.
; The prompt shows the current path. Verify a volume with p8xfs.py fsck.
; RAM layout: code $4000..(<=$9D46) | CF LBA $9D47, SBUF $9E00 (both fixed by the
; BIOS) | OS variables $A000.. | user programs / RUN / ">" capture (the TPA)
; $7A00.. | TPA (programs); stack (P3) grows down from $FEFF.

; ---- BIOS jump table (stable ABI, in ROM) ----------------------------------
CONIN   = $0100          ; wait for key, char -> A
CONOUT  = $0103          ; A -> serial
CONST   = $0106          ; A = RDRF bit; Z=1 when no key waiting
CFINIT  = $0109          ; reset + 8-bit mode (current drive); C=1 on error
CFSEL   = $0148          ; A = drive (0/1) -> route CF/FS sector I/O to that card
CFCURDRV= $014B          ; -> A = current CF drive
FFIND   = $0118          ; find file FNAME in current dir -> LBA+FLEN; C=1 absent
CFREAD  = $010C          ; sector LBA -> (P1); P1 += 512
CFWRITE = $010F          ; SBUF -> sector LBA
CFIMASK = $7081          ; firmware "drive N CFINIT'd this session" bitmask (UMOUNT clears bit 1)
PUTS    = $0112          ; print (P1)+ until $00
PHEX8   = $0115          ; print A as two hex digits
FLOADAT = $013F          ; bulk-read FLEN bytes from LBA into (P1)
FNEXT     = $013C        ; next directory entry -> BFNAME/BFFLAG/FLEN; C=1 at end
FOPENDIRAT= $0142        ; begin iterating the 4-sector directory at LBA in A
FSDIRBUF= $0145          ; point the FNEXT/FSCAN sector buffer at page A (high byte)
FWOPEN  = $012A          ; open a write stream at the volume free pointer
FPUTB   = $012D          ; append byte A to the write stream
FCLOSE  = $0130          ; flush + register the streamed file as FNAME
FNORM   = $0136          ; copy string (P1) -> FNAME, case-preserved + space-padded
FOPEN   = $0124          ; open file FNAME for reading (P1 = 512-byte buffer)
FGETB   = $0127          ; next byte -> A; C=1 at end of file
FDELETE = $011E          ; tombstone file FNAME (for the pipe temp)
BDIRLBA = $706E          ; BIOS "current directory" start LBA (default root); the
BDIRN   = $706F          ; FS calls register/find in here. We point it at the CWD
                         ; so a redirect / pipe file lands in the working dir.
BDIRLBA1= $707A          ; BIOS current-directory start LBA high byte (16-bit dirs)
BFNAME  = $704A          ; FNEXT entry-name output (BIOS FNAME)
BFFLAG  = $7070          ; FNEXT entry-flag output (BIOS FFLAG)

; ---- Shared ABI state (set by/for the BIOS) --------------------------------
LBA     = $7047          ; CFREAD/CFWRITE target LBA, byte 0 (bits 7:0)
LBA1    = $7048          ; LBA byte 1 (bits 15:8)  — 0 after CFINIT unless set
LBA2    = $7049          ; LBA byte 2 (bits 23:16) — 0 after CFINIT unless set
FLEN    = $7058          ; BIOS file length param (used to drive FLOADAT)
; BIOS read-stream state — `sh` points a stream at the script's extent (over IBUF)
; and saves/restores this block around each dispatched command.
ROSTAT  = $705C          ; read-stream state base (ROLBA..ROCNT, 11 bytes)
ROLBA   = $705C          ; next sector LBA (3)
ROREM   = $705F          ; bytes remaining in the file (2)
ROBUF   = $7061          ; caller's 512-byte sector buffer address (2)
ROCNT   = $7065          ; bytes left in ROBUF; 0 -> refill (2)
DRVSEL  = $707C          ; current CF drive
ROSDRV  = $707F          ; read-stream drive
SBUF    = $7100          ; 512-byte sector buffer

; ---- P8XFS v2 on-disk layout (root @ LBA 33, 4 secs; data @ 37) -------------
F_FILE  = $01            ; entry flag: regular file ($00 end marker)
F_DIR   = $02            ; subdirectory (its extent holds entries)
F_DEL   = $FF            ; deleted
SUBSECS = 4              ; sectors allocated for a new subdirectory (64 entries)

; ---- OS RAM variables (below the kernel, clear of BIOS $9D44+ and SBUF) -----
LINEBUF = $7300          ; shell input line (64 bytes)
CMDBUF  = $7340          ; parsed command word (16 bytes)
NAMEBUF = $7350          ; 12-byte filename (search key / DIR scratch)
TMP     = $7360
TMP2    = $7361
CNT     = $7362
ECNT    = $7363          ; entries-left-in-sector counter
FLAGS   = $7364          ; current entry flag byte
MATCH   = $7365          ; 1 = name matched / strings equal
LENLO   = $7366          ; entry length, low 16 bits
LENHI   = $7367
STARTLO = $7368          ; entry start LBA (low byte)
LOADLO  = $7369          ; entry load address
LOADHI  = $736A
EXECLO  = $736B          ; entry exec address
EXECHI  = $736C
DLBA    = $736D          ; directory sector being scanned
SECCNT  = $736E          ; sectors left to transfer
CURLBA  = $736F          ; current data LBA
ENTPL   = $7370          ; pointer to a directory entry (in SBUF):
ENTPH   = $7371          ;   flag byte for DEL, entry start for SAVE
ARGPL   = $7372          ; saved arg position in LINEBUF
ARGPH   = $7373
; ---- SAVE working set ----
HXLO    = $7374          ; GETHEX result
HXHI    = $7375
DIGIT   = $7376          ; HEXVAL digit value
SHCNT   = $7377          ; shift counter
SVSTLO  = $7378          ; SAVE source start address
SVSTHI  = $7379
FREELO  = $737A          ; boot-block free pointer (next data LBA)
FREEHI  = $737B
SRCLO   = $737C          ; running source pointer during the copy
SRCHI   = $737D
REM     = $737E          ; sectors remaining in the SAVE write loop
; ---- PACK working set ----
NF      = $7380          ; running next-free LBA
PFOUND  = $7381          ; 1 if this pass found an unpacked extent
MINSTRT = $7382          ; smallest start LBA >= NF this pass
MINSEC  = $7383          ; that extent's sector count
MINPL   = $7384          ; pointer to that entry's start-LBA field (in SBUF)
MINPH   = $7385
MINDL   = $7386          ; that entry's directory sector LBA
ESTART  = $7387          ; current entry start LBA (low byte)
SRCL    = $7388          ; copy source LBA
DSTL    = $7389          ; copy dest LBA
CPYN    = $738A          ; sectors left to copy
CANDL   = $738B          ; current entry's start-field pointer
CANDH   = $738C
; ---- directory / path working set ----
ROOTN   = $738D          ; root directory sector count (4)
DATABASE= $738E          ; first data LBA (37)
CWDL    = $738F          ; current directory: start LBA
CWDN    = $7390          ;                    sector count
SDIRL   = $7391          ; directory being scanned this op (start LBA)
SDIRN   = $7392          ;                                 sector count
SCNT    = $7393          ; sectors-left counter while scanning a directory
LSL     = $7394          ; SETPATH: pointer to the last '/' in CWDPATH
LSH     = $7395
PATHL   = $7396          ; saved path cursor across DESCEND (FINDENT clobbers P2)
PATHH   = $7397
NEWLBA  = $7398          ; MKDIR: LBA of the new directory extent
PSL     = $7399          ; MKDIR: parent dir start LBA / sector count
PSN     = $739A
EFLAG   = $739B          ; flag byte WRENT stamps (F_FILE for SAVE, F_DIR for MKDIR)
RMDL    = $739C          ; RMDIR: parent directory sector holding the entry
; ---- directory-walk working set (FSCK/PACK; was TREE) ----
CDST    = $739D          ; current directory: start LBA / sectors / entry index
CDSC    = $739E
CIDX    = $739F
; ---- output redirection ("> file") ----
REDIRF  = $73A0          ; 0 = console, 1 = capturing to RBUF
RCH     = $73A1          ; OUTCH: byte being emitted
RS2L    = $73A2          ; OUTCH: saved caller P2
RS2H    = $73A3
RPTRL   = $73A4          ; OUTCH: next free byte in the capture buffer
RPTRH   = $73A5
RHX     = $73A6          ; OPHEX8 scratch
REDNAME = $73A7          ; redirect target filename (null-terminated, <=48): $73A7..$73D6
; FSCK counters/scratch ($A0D7..$A0DE) - safely above REDNAME, below the tree stack
FNDIR   = $73D7          ; directories counted
FNFIL   = $73D8          ; files counted
FNDEL   = $73D9          ; deleted slots counted
FMAXE   = $73DA          ; highest extent end LBA seen (data area only)
FUSED   = $73DB          ; data sectors occupied by live extents
FERR    = $73DC          ; problems found (0 = clean)
FCHILD  = $73DD          ; CHKDD: directory whose '..' is being checked
FEXP    = $73DE          ; CHKDD: expected parent LBA
RBUF    = $7A00          ; capture buffer = the TPA (free during a built-in cmd)
TSP     = $73E0          ; tree stack depth (0 = at root level)
TI      = $73E1          ; scratch loop counter for the frame stack
TFRAME  = $74B7          ; 8 frames x 4 bytes (dst_lo,dst_hi,dsc,idx): $74B7..$74D6
                         ;   (16-bit CDST; the old 3-byte $A0E2 region is now free)
; ---- v2 PACK working set ----
PPSEC   = $73FA          ; chosen extent's parent-entry: dir sector LBA / slot
PPSLOT  = $73FB
CANDSEC = $73FC          ; candidate entry's location during the find walk
CANDSLOT= $73FD
PARST   = $73FE          ; PK2FIX: parent directory start LBA (for '..')
CWDPATH = $7400          ; textual CWD path for the prompt (up to 48 bytes)
; ---- stdin redirection ("< file") ----
INMODE  = $7430          ; SYS_GETC source: 0 = console, 1 = the read stream
INARM   = $7431          ; shell armed a "< file" for the next RUN
INNAME  = $7432          ; "< file" name (null-terminated, <=48): $7432..$7461
PIPEF   = $7462          ; pipe stage: 0 none, 1 left ran, 2 right ran
PIPEBUF = $7463          ; saved right-hand command of a "cmd | cmd" ($7463..$74A2)
; --- 16-bit directory-LBA high bytes (P8XFS directories may live at LBA >=256;
;     the volume free pointer is 16-bit, so one extra byte per cursor suffices.
;     Each pairs with an existing low-byte cursor of the same root name). ---
CWDLH   = $74A3          ; CWDL high byte (current working directory start LBA)
SDIRLH  = $74A4          ; SDIRL high byte (directory being scanned this op)
STARTHI = $74A5          ; STARTLO high byte (entry start LBA from FINDENT)
DLBAH   = $74A6          ; DLBA high byte (directory-sector scan cursor)
NEWLBAH = $74A7          ; NEWLBA high byte (MKDIR new extent)
PSLH    = $74A8          ; PSL high byte (MKDIR parent extent)
PARSTH  = $74A9          ; PARST high byte (PACK '..' parent fix)
RMDLH   = $74AA          ; RMDL high byte (RMDIR parent sector)
CURLBAH = $74AB          ; CURLBA high byte (SAVE data-write LBA, 16-bit)
; --- PACK/FSCK 16-bit tree-walk high bytes (pair with the 8-bit cursors above) -
NFH     = $74AC          ; NF high byte (PACK next-free target)
MINSTRTH= $74AD          ; MINSTRT high byte (smallest start LBA this pass)
CDSTH   = $74AE          ; CDST high byte (current directory in the walk)
CANDSECH= $74AF          ; CANDSEC high byte (candidate entry's dir sector)
PPSECH  = $74B0          ; PPSEC high byte (chosen extent's parent-entry sector)
SRCH    = $74B1          ; SRCL high byte (PK2MOVE copy source)
DSTH    = $74B2          ; DSTL high byte (PK2MOVE copy dest)
FCHILDH = $74B3          ; FCHILD high byte (CHKDD child dir)
FEXPH   = $74B4          ; FEXP high byte (CHKDD expected parent)
FMAXEH  = $74B5          ; FMAXE high byte (FSCK highest extent end)
FUSEDH  = $74B6          ; FUSED high byte (FSCK live data sectors)
REDAPP  = $74D7          ; >> append redirect: 1 = prepend the existing file
APHAVE  = $74D8          ; >> : 1 = an existing file to prepend was found
APLBA   = $74D9          ; >> : old file's start LBA (2 bytes)
APREM   = $74DB          ; >> : old file bytes left to copy (2 bytes)
APCHK   = $74DD          ; >> : bytes to emit from the current sector (2 bytes)
; ---- sh: run shell commands from a script file (slurped into APBUF) ----
SCRIPTM = $74E0          ; 1 = the shell is running lines from a `sh` script
SCRSAVE = $74E1          ; saved script read-stream state (ROSTATE 11 + ROSDRV = 12)
SCRCNT  = $74ED          ; byte counter for SAVESCR/RESTSCR (1)
APBUF   = $7800          ; >> prepend sector buffer (512B, below the TPA); also the
                         ;   `sh` script buffer (a script line can't use >>, which is
                         ;   fine — build scripts use >)
IBUF    = $7500          ; 512-byte buffer for the stdin read stream
; ---- program search path (implicit RUN of a bare command name) ----
PATHBUF = $7700          ; search path, ';'-separated dirs; default "/BIN" ($7700..$773F)
RUNPATH = $7740          ; scratch: candidate program path built during a lookup ($7740..$779F)
RUNSKIP = $77A0          ; DORUN: 1 = skip the program-name word for the arg pointer
PSCANL  = $77A1          ; PATH search cursor into PATHBUF (low)
PSCANH  = $77A2          ; PATH search cursor into PATHBUF (high)
GPLF    = $77A3          ; SYS_GETC console: 1 = a LF is pending after a CR keypress
; ---- mount model (drive 1 mounted at /d1) state ----
CURDRIVE= $77A4          ; derived: 1 if the CWD is under /d1 (drive 1), else 0
DRVINIT = $77A5          ; bitmask: bit N set = drive N has been CFINIT'd this session
MPSAV   = $77A6          ; MNTPFX: saved P2 (2 bytes) while sniffing a "d1" prefix
; $77A8..$77D9 free (was the DOS-model drive-1 CWD backing, removed with the
; mount migration).
; ($77DA..$77E4 free — was IMPORT bulk-copy state; IMPORT removed, superseded by
;  the userland `cp -r`, which recurses and works across the /d1 mount.)

CR      = $0D
LF      = $0A
STKTOP  = $FEFF

        .org $4000          ; rev D: OS loads at $4000 (match the monitor's CMD_B + --base)
; ---------------- OS syscall table (stable ABI for TPA programs) -------------
; A jump table at the front of the OS image, like the BIOS table at $0100 but
; for OS-level services (CWD etc.) that the BIOS deliberately doesn't own. The
; OS stays resident at $4000 while a RUN program executes, so a program reaches
; these with a plain JSR (or the C compiler's bios()).  Append-only.
        JMP  COLD               ; $4000 boot entry (monitor's CMD_B jumps here)
        JMP  SYS_GETCWD         ; $4003 copy CWD path string -> (P1), incl. NUL
        JMP  SYS_CWDLBA         ; $4006 CWD directory start LBA -> A
        JMP  OUTCH              ; $4009 SYS_PUTC: A -> current stdout (console/file)
        JMP  SYS_GETC           ; $400C SYS_GETC: next stdin byte -> A
        JMP  SYS_PUTS           ; $400F SYS_PUTS: write (P1) string to stdout
        JMP  SYS_OPENCWD        ; $4012 SYS_OPENCWD: begin iterating the CWD (16-bit LBA)
        JMP  SYS_SETDRV         ; $4015 SYS_SETDRIVE: deprecated (mount model) — no-op stub, ABI slot kept
        JMP  SYS_GETDRIVE       ; $4018 SYS_GETDRIVE: -> A = 1 if CWD is under /d1 (drive 1), else 0
        JMP  SYS_DIRENTRY       ; $401B SYS_DIRENTRY: snapshot the current dir entry -> (P1) 17 bytes
        JMP  SYS_OPENDIR        ; $401E SYS_OPENDIR: P1 = 16-bit dir start LBA -> open for FNEXT
        JMP  SYS_MKDIR          ; $4021 SYS_MKDIR: P1 = path -> create a directory; C=1 on real failure
; Reached only via the table above (COLD jumps past them).
SYS_GETDRIVE:                   ; derived: 1 if the CWD is under the /d1 mount
        LDA  CURDRIVE
        RTS
SYS_SETDRV:                     ; deprecated: the drive follows the CWD path now
        CLC
        RTS
; SYS_DIRENTRY — copy the entry FNEXT just matched into a caller buffer, so
; /BIN commands read directory metadata without hardcoding BIOS scratch
; addresses (FNAME/FFLAG/FLEN/entry-LBA). Layout of the 17-byte snapshot:
;   [0..11] name (space-padded)  [12] flag (file $01/dir $02)
;   [13..14] length lo/hi        [15..16] start-LBA lo/hi
; Call it right after a BIOS FNEXT (before any other FS call reuses the scratch).
SYS_DIRENTRY:                   ; P1 = dest (17 bytes); clobbers A, P2, TMP
        LDP2 #BFNAME
        LDA  #12
        STA  TMP
SDE_NM: LDA  (P2)+              ; [0..11] name
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  SDE_NM
        LDA  BFFLAG             ; [12] flag
        STA  (P1)+
        LDA  FLEN               ; [13] length lo
        STA  (P1)+
        LDA  FLEN+1             ; [14] length hi
        STA  (P1)+
        LDA  LBA                ; [15] start-LBA lo
        STA  (P1)+
        LDA  LBA1               ; [16] start-LBA hi
        STA  (P1)
        RTS
; SYS_OPENDIR — begin iterating an arbitrary directory whose 16-bit start LBA is
; passed in P1 (so a command can descend into a subdirectory it found via
; SYS_DIRENTRY without poking the LBA scratch). Pairs with FNEXT; a caller that
; redirects iteration to its own page calls FSDIRBUF afterwards.
SYS_OPENDIR:                    ; P1 = dir start LBA (16-bit)
        TPA1H                   ; P1 high -> LBA1
        STA  LBA1
        LDA  #0
        STA  LBA2
        TPA1L                   ; P1 low -> A
        JMP  FOPENDIRAT         ; A=low, LBA1=high, DICNT=4 -> ready; RTS to caller
SYS_MKDIR:                      ; P1 = path -> create a directory (via MKDIRCORE).
        TPA1L                   ; P2 = P1 (MKDIRCORE resolves the path at P2)
        TAP2L
        TPA1H
        TAP2H
        JSR  MKDIRCORE          ; A = status, C=1 on error
        JNC  smk_ok             ; 0 created -> ok
        LDB  #2                 ; 2 already-exists -> also ok (idempotent for cp -r)
        CMP
        JZ   smk_ok
        SEC                     ; 1 bad path / 3 full -> real failure
        RTS
smk_ok: CLC
        RTS
SYS_GETCWD:                     ; copy CWDPATH -> (P1); clobbers P2
        LDP2 #CWDPATH
SGC_LP: LDA  (P2)+
        STA  (P1)+
        JNZ  SGC_LP             ; copy through the terminating NUL
        RTS
SYS_CWDLBA:
        LDA  CWDL               ; current directory start LBA (low byte) -> A
        RTS                     ; (8-bit; use SYS_OPENCWD for dirs at LBA >=256)
SYS_OPENCWD:                    ; begin iterating the CWD directory (full 16-bit
        JSR  SYNCDRV           ; route to the CWD's drive first: a /BIN program was
                              ;   just loaded from drive 0, leaving DRVSEL=0, but the
                              ;   CWD may be under the /d1 mount (drive 1).
        LDA  CWDLH              ; LBA), so a /BIN program can list the CWD even
        STA  LBA1               ; when it lives at LBA >=256. Pairs with FNEXT.
        LDA  #0
        STA  LBA2
        LDA  CWDL
        JMP  FOPENDIRAT         ; A=low, LBA1=high -> set up iteration; RTS to caller
SYS_GETC:                       ; next stdin byte -> A; C=1 at EOF
        LDA  INMODE
        JNZ  SGC_FILE
        LDA  GPLF               ; a LF queued from a prior CR keypress? deliver it
        JZ   SGC_KEY            ;   (no echo: the CRLF was already echoed)
        LDA  #0
        STA  GPLF
        LDA  #$0A
        CLC
        RTS
SGC_KEY:JSR  CONIN              ; console: a key
        LDB  #$04               ; Ctrl-D ends console input (C=1, like file EOF)
        CMP
        JZ   SGC_EOF
        LDB  #CR                ; Enter -> echo CRLF, return CR now, queue the LF
        CMP
        JZ   SGC_CR             ;   so a typed line lands in the file as CR+LF
        JSR  CONOUT             ; normal key: echo to the screen via CONOUT, NOT
        CLC                     ;   OUTCH (stdout may be a redirect/pipe)
        RTS
SGC_CR: JSR  CONOUT             ; echo CR ...
        LDA  #LF
        JSR  CONOUT             ; ... and LF
        LDA  #1
        STA  GPLF               ; next SYS_GETC returns the LF
        LDA  #CR                ; return the CR now
        CLC
        RTS
SGC_EOF: SEC                    ; Ctrl-D -> end of input (not echoed)
        RTS
SGC_FILE:
        JSR  FGETB              ; read stream: next byte -> A, C=1 at end of file
        RTS
SYS_PUTS:                       ; write the (P1) string to stdout via OUTCH
SPS_LP: LDA  (P1)+
        JZ   SPS_DN
        JSR  OUTCH              ; OUTCH preserves P1 (see OUTFILE)
        JMP  SPS_LP
SPS_DN: RTS
SETCWDDIR:                      ; point the BIOS FS at the CWD (so redirect/pipe
        LDA  CWDL               ; files land in the working dir, not root). The
        STA  BDIRLBA            ; FS calls revert to root after, so set per-op.
        LDA  CWDLH              ; 16-bit: carry the high byte too
        STA  BDIRLBA1
        LDA  CWDN
        STA  BDIRN
        RTS
; ---------------- Cold start -------------------------------------------------
COLD:   LDP3 #STKTOP
        LDA  #0                 ; output goes to the console until a "> file" redirect
        STA  REDIRF
        STA  INMODE             ; input from the console until a "< file" redirect
        STA  INARM
        STA  PIPEF              ; no pipe in progress
        LDP1 #MBANNER
        JSR  OPUTS
        ; P8XFS v2 layout (the only format): root LBA 33..36 (4 secs), data @ 37
        LDA  #4
        STA  ROOTN
        LDA  #37
        STA  DATABASE
        LDA  #33                ; CWD = root
        STA  CWDL
        LDA  #0
        STA  CWDLH
        LDA  #4
        STA  CWDN
        JSR  PATHROOT           ; CWDPATH = "/"
        ; mount model: boot at the root on drive 0 (already CFINIT'd by the boot
        ; loader). CURDRIVE is derived from the CWD path (0 = not under /d1).
        LDA  #0
        STA  CURDRIVE
        LDA  #1                 ; drive 0 inited by CMD_B; mark it
        STA  DRVINIT
        JSR  PATHINIT           ; PATH = "/BIN" (search dir for bare command names)

; ---------------- Shell main loop --------------------------------------------
SHELL:  JSR  FLUSHRED           ; if the previous command was redirected, write its file
        ; pipe state machine: 1 = the left command just ran (now run the right
        ; from the temp file); 2 = the right just ran (delete the temp). A pipe
        ; "cmd1 | cmd2" runs as cmd1 >PIPE.TMP then cmd2 <PIPE.TMP then del.
        LDA  PIPEF
        JZ   SH_PROMPT
        LDB  #1
        CMP
        JZ   PIPE_RHS
        JSR  SETCWDDIR          ; PIPE.TMP lives in the CWD (where it was written)
        LDP1 #MPIPE             ; PIPEF=2: right command done -> remove the temp
        JSR  FNORM
        JSR  FDELETE
        LDA  #0
        STA  PIPEF
SH_PROMPT:
        LDA  SCRIPTM            ; running a script: no prompt (GETLN pulls + echoes)
        JNZ  SH_GL
        JSR  CRLF
        LDP1 #CWDPATH           ; prompt = "<path>> " (drive 1 shows as /d1/...)
        JSR  OPUTS
        LDP1 #MPROMPT
        JSR  OPUTS
SH_GL:  JSR  GETLN              ; line -> LINEBUF (null-terminated)
        JSR  PIPESCAN          ; split "cmd | cmd": save the right, arm left's >PIPE
        JSR  INSCAN            ; split off a "< name" stdin redirect (before REDSCAN)
        JSR  REDSCAN            ; split off a trailing "> name" and arm capture
DISPATCH:
        LDP2 #LINEBUF
        LDP1 #CMDBUF
        JSR  PARSEW             ; CMDBUF = upcased command word; P2 -> args
        TPA2L                   ; remember where arguments start
        STA  ARGPL
        TPA2H
        STA  ARGPH
        LDA  CMDBUF
        JZ   SHELL              ; blank line
        JSR  SYNCDRV            ; baseline CF routing = the current drive (CWD's card)
        LDP1 #KW_HELP
        JSR  CMPCMD
        JNZ  DOHELP
        LDP1 #KW_LOAD
        JSR  CMPCMD
        JNZ  DOLOAD
        LDP1 #KW_RUN
        JSR  CMPCMD
        JNZ  DORUN
        LDP1 #KW_DEL
        JSR  CMPCMD
        JNZ  DODEL
        LDP1 #KW_SAVE
        JSR  CMPCMD
        JNZ  DOSAVE
        LDP1 #KW_PACK
        JSR  CMPCMD
        JNZ  DOPACK
        LDP1 #KW_CD
        JSR  CMPCMD
        JNZ  DOCD
        LDP1 #KW_MKDIR
        JSR  CMPCMD
        JNZ  DOMKDIR
        LDP1 #KW_RMDIR
        JSR  CMPCMD
        JNZ  DORMDIR
        LDP1 #KW_FSCK
        JSR  CMPCMD
        JNZ  DOFSCK
        LDP1 #KW_PATH
        JSR  CMPCMD
        JNZ  DOPATH
        LDP1 #KW_EXIT
        JSR  CMPCMD
        JNZ  DOEXIT
        LDP1 #KW_MON
        JSR  CMPCMD
        JNZ  DOEXIT
        LDP1 #KW_FORMAT
        JSR  CMPCMD
        JNZ  DOFORMAT
        LDP1 #KW_UMOUNT
        JSR  CMPCMD
        JNZ  DOUMOUNT
        LDP1 #KW_MOUNT
        JSR  CMPCMD
        JNZ  DOMOUNT
        LDP1 #KW_SH
        JSR  CMPCMD
        JNZ  DOSH
        JMP  IMPRUN             ; not a built-in: try to run it as a program (PATH)

; CMPCMD - compare CMDBUF to the keyword at (P1); returns A!=0 (and Z clear)
; when they match. Leaves the keyword pointer consumed.
CMPCMD: LDP2 #CMDBUF
        JSR  STREQ
        LDA  MATCH
        RTS

; ---------------- HELP -------------------------------------------------------
DOHELP: LDP1 #MHELP
        JSR  OPUTS
        JMP  SHELL

; PWD is no longer a built-in — bare `PWD` falls through DISPATCH to /BIN/PWD.BIN
; (os/commands/pwd.c). DIR and TREE likewise moved to /BIN. DUMP stays native.

; ---------------- PATH [dirs] : view or set the program search path ----------
; No argument prints the current PATH (PATHBUF, where implicit RUN looks up bare
; command names; ';'-separated, default "/BIN"). An argument replaces it (copied
; upcased + NUL-terminated, like a path component). Resets to "/BIN" each boot.
DOPATH: JSR  ARG2P2
        JSR  SKIPSPC
        LDA  (P2)
        JNZ  DPA_SET            ; an argument -> set PATH
        LDP1 #PATHBUF           ; no argument -> print the current PATH
        JSR  OPUTS
        JSR  CRLF
        JMP  SHELL
DPA_SET:LDP1 #PATHBUF           ; copy the argument word into PATHBUF (upcased)
        JSR  PARSEW
        JMP  SHELL

; ---------------- MOUNT / UMOUNT : hot-swap the /d1 card ---------------------
; The filesystem caches no state for drive 1 (free pointer, root LBA, and the
; CWD are all re-derived on demand), so a CF in the /d1 slot can be swapped at
; the prompt. Two things must be reset across a swap: the firmware's
; "already initialized" cache (CFIMASK) so the new card gets its 8-bit-mode +
; IDENTIFY handshake, and the CWD if it currently sits under /d1 (its LBAs
; belong to the OLD card). Swap sequence:  UMOUNT -> pull card -> insert card
; -> MOUNT.  (Swap only at the prompt with no I/O in flight — the True-IDE bus
; has no card-detect.)
DOUMOUNT:
        LDA  CURDRIVE           ; if the CWD is under /d1, drop back to the root
        JZ   um_forget          ;   (its start LBA belongs to the old card)
        LDA  #33
        STA  CWDL
        LDA  #0
        STA  CWDLH
        LDA  ROOTN
        STA  CWDN
        LDA  #0
        STA  CURDRIVE
        JSR  PATHROOT           ; CWDPATH = "/"
um_forget:
        LDA  CFIMASK            ; forget drive 1's init: the next /d1 access will
        LDB  #$FD               ;   re-run CFINIT on whatever card is now inserted
        AND
        STA  CFIMASK
        LDP1 #MUMOK
        JSR  OPUTS
        JMP  SHELL

DOMOUNT:
        LDA  CFIMASK            ; force a fresh init: clear drive 1's cached flag so
        LDB  #$FD               ;   CFSEL re-runs the CFINIT handshake on the card
        AND
        STA  CFIMASK
        LDA  #1                 ; route to drive 1 (CFSEL does the CFINIT handshake)
        JSR  CFSEL
        LDP1 #SBUF              ; read the boot block (LBA 0) and judge by its data:
        LDA  #0                 ;   "P8" = mounted, $FF = floating bus (no card),
        STA  LBA                ;   else = unformatted. (Bounded CF waits -> no hang.)
        STA  LBA1
        STA  LBA2
        JSR  CFREAD
        LDA  SBUF+0
        LDB  #'P'
        CMP
        JNZ  mnt_notp
        LDA  SBUF+1
        LDB  #'8'
        CMP
        JNZ  mnt_notp
        LDP1 #MMNTOK           ; "P8" signature -> mounted
        JSR  OPUTS
        JMP  mnt_done
mnt_notp:LDA SBUF+0
        LDB  #$FF
        CMP
        JZ   mnt_no            ; all-ones -> nothing driving the bus -> no card
        LDP1 #MMNTBAD         ; else -> a card, but not P8XFS
        JSR  OPUTS
        JMP  mnt_done
mnt_no: LDP1 #MMNTNO
        JSR  OPUTS
mnt_done:
        JSR  SYNCDRV            ; restore routing to the current drive
        JMP  SHELL

; EXIT / MON - leave the OS and cold-restart into the ROM monitor (reset vector
; $0000), mirroring BASIC's BYE. The monitor re-inits the ACIA and prompts.
DOEXIT: JMP  $0000

; CAT is no longer a built-in: a bare `CAT file` falls through DISPATCH to the
; implicit-RUN of /BIN/CAT.BIN (os/commands/cat.c), which is a strict superset
; (it also filters stdin and pipes). See the backlog for DIR/PWD.

; DIR is no longer a built-in — `DIR [-R] [path]` falls through DISPATCH to
; /BIN/DIR.BIN (os/commands/dir.c). DENT2OS/DPRENT/MDIRHDR/MDIRTAG went with it.

; ---------------- LOAD name --------------------------------------------------
DOLOAD: JSR  FINDARG            ; parse name, scan directory
        JZ   NOFILE
        JSR  LOADF              ; read the file into its load address
        LDP1 #MLOADED
        JSR  OPUTS
        JMP  SHELL

; ---------------- RUN name ---------------------------------------------------
DORUN:  JSR  FINDARG
        JZ   NOFILE
        LDA  #1                 ; explicit RUN: program name is arg[0]; skip it so
        STA  RUNSKIP            ;   the program sees the tail after its own name
RUNGO:  LDA  #0                 ; clear any pending console LF from a prior program
        STA  GPLF
        JSR  DEFADDR            ; load/exec 0 -> TPA base $7A00 (on-target-built
        JSR  LOADF              ; programs, e.g. ASM output, carry 0 from FCREATE)
        ; Redirection for programs. KEY CONSTRAINT: FFIND scans through SBUF, but
        ; FWOPEN then keeps the write stream's partial (unflushed) sector in SBUF —
        ; so any FFIND AFTER FWOPEN corrupts pending output. Therefore do every
        ; FFIND first: (1) ">>" resolves the existing file's extent (FFIND, saved);
        ; (2) "< name" stdin is bound (its FOPEN FFINDs); THEN (3) FWOPEN; THEN
        ; (4) the ">>" prepend copies the old extent in with RAW sector reads
        ; (CFREAD, not the read stream — stdin owns that), so the program's output
        ; appends after it. RBUF capture isn't usable (RBUF is the TPA, where the
        ; program lives); stdout streams to the file (REDIRF=2): putchar->OUTCH->
        ; FPUTB. FNAME is (re)set at FCLOSE (the program clobbers the BIOS FNAME).
        LDA  #0
        STA  APHAVE
        LDA  REDIRF             ; ">>" prepend resolve (needs output redirect)
        JZ   DR_BIND
        LDA  REDAPP
        JZ   DR_BIND
        JSR  SETCWDDIR          ; resolve REDNAME in the CWD, not root
        LDP1 #REDNAME
        JSR  FNORM              ; FNAME = the append target
        JSR  FFIND              ; -> LBA(0..2)+FLEN; C=1 if the file is absent
        JC   DR_BIND            ; new file -> nothing to prepend (acts like '>')
        LDA  LBA                ; remember the old extent for the raw copy below
        STA  APLBA
        LDA  LBA1
        STA  APLBA+1
        LDA  FLEN
        STA  APREM
        LDA  FLEN+1
        STA  APREM+1
        LDA  #1
        STA  APHAVE
DR_BIND:LDA  INARM              ; stdin "< name": bind it (its FFIND runs BEFORE any
        JZ   DR_OUT             ;   FWOPEN below, so it can't corrupt the output)
        JSR  SETCWDDIR
        LDP1 #INNAME            ; FNAME = the input file
        JSR  FNORM
        LDP1 #IBUF              ; read-stream buffer (separate page from APBUF)
        JSR  FOPEN
        LDA  #1
        STA  INMODE             ; SYS_GETC now reads the file
DR_OUT: LDA  REDIRF             ; open the write stream if redirecting output
        JZ   DR_NOIN
        JSR  FWOPEN             ; claims SBUF — NO FFIND past this point
        LDA  #2
        STA  REDIRF
        LDA  APHAVE             ; ">>": copy the old extent (APLBA/APREM) into the
        JZ   DR_NOIN            ;   open write stream with raw sector reads
        JSR  APCOPY
        ; program-arg ABI: enter with P2 -> the command tail after the program
        ; name (null-terminated), so `RUN EDIT FOO.ASM` hands "FOO.ASM" to it.
DR_NOIN:JSR  ARG2P2             ; P2 -> RUN args ("EDIT FOO.ASM")
        LDA  RUNSKIP            ; explicit RUN: skip the program-name word; implicit
        JZ   DR_ARGS            ;   run already points at the tail (after the cmd word)
        JSR  SKIPWORD           ; skip the program name + spaces -> P2 at the tail
DR_ARGS:LDA  EXECLO             ; P1 <- exec address
        TAP1L
        LDA  EXECHI
        TAP1H
        JSR  (P1)               ; execute; program RTS returns here, P2 = arg tail
        LDA  REDIRF             ; if streaming to a file, name it + flush + register
        LDB  #2
        CMP
        JNC  DR_NOOUT
        JSR  SETCWDDIR          ; register the file in the CWD, not root
        LDP1 #REDNAME           ; FNAME = redirect target (set now: the program may
        JSR  FNORM              ; have clobbered the BIOS FNAME via its own FS calls)
        JSR  FCLOSE
        LDA  #0
        STA  REDIRF
DR_NOOUT:LDA #0                 ; restore console stdin for the next command
        STA  INMODE
        STA  INARM
DR_DONE:JMP  SHELL
; DEFADDR - a directory entry with load/exec == 0 (the value FCREATE writes for
; files built on-target) is taken to mean "load at the TPA base $7A00". Programs
; installed from the host set explicit non-zero load/exec, so they are untouched.
DEFADDR:LDA  LOADLO
        LDB  LOADHI
        OR
        JNZ  DA_EX
        LDA  #$00
        STA  LOADLO
        LDA  #$7A
        STA  LOADHI
DA_EX:  LDA  EXECLO
        LDB  EXECHI
        OR
        JNZ  DA_RT
        LDA  #$00
        STA  EXECLO
        LDA  #$7A
        STA  EXECHI
DA_RT:  RTS
; SKIPWORD - advance P2 past leading spaces, then one word, then trailing
; spaces, leaving P2 at the next argument (ARGP has a leading space).
SKIPWORD:LDA  (P2)              ; skip leading spaces
        JZ   SW_DONE
        LDB  #' '
        CMP
        JNZ  SW_W
        INP2
        JMP  SKIPWORD
SW_W:   LDA  (P2)              ; skip the word (non-spaces)
        JZ   SW_DONE
        LDB  #' '
        CMP
        JZ   SW_SP
        INP2
        JMP  SW_W
SW_SP:  LDA  (P2)              ; skip trailing spaces
        JZ   SW_DONE
        LDB  #' '
        CMP
        JNZ  SW_DONE
        INP2
        JMP  SW_SP
SW_DONE:RTS

; ---------------- implicit RUN (bare command name -> a program) --------------
; The command word in CMDBUF matched no built-in. Treat it as a program:
;   * if CMDBUF contains '/', it's a path (CWD-relative or absolute) -> run it
;     as typed, then with a ".BIN" suffix;
;   * otherwise search PATHBUF (';'-separated directories, default "/BIN"),
;     trying "<dir>/<cmd>" then "<dir>/<cmd>.BIN" in each.
; On the first hit: RUNSKIP=0 (the args already follow the command word) and run
; it via the shared RUNGO tail. No hit -> "unknown command". The whole-line
; redirects/pipes ( < > | ) were stripped before DISPATCH, so they apply here too.
IMPRUN: LDP1 #CMDBUF            ; does the command word contain a '/'?
IM_SL:  LDA  (P1)+
        JZ   IM_PATH            ; no '/': search PATHBUF
        LDB  #'/'
        CMP
        JNZ  IM_SL
        LDP1 #CMDBUF            ; literal path: RUNPATH = CMDBUF verbatim
        LDP2 #RUNPATH
IM_LCP: LDA  (P1)+
        STA  (P2)+
        JNZ  IM_LCP            ; copy through the terminating NUL
        JSR  TRYCAND
        LDA  MATCH
        JNZ  IM_RUN
        JSR  APPENDBIN         ; try "<path>.BIN"
        JSR  TRYCAND
        LDA  MATCH
        JNZ  IM_RUN
        JMP  IM_UNK
IM_PATH:LDP1 #PATHBUF          ; PSCAN = start of the search path
        TPA1L
        STA  PSCANL
        TPA1H
        STA  PSCANH
IM_LOOP:LDA  PSCANL            ; any path entries left?
        TAP1L
        LDA  PSCANH
        TAP1H
        LDA  (P1)
        JZ   IM_UNK            ; end of PATH, nothing matched
        JSR  BUILDCAND         ; RUNPATH = entry + "/" + CMDBUF; PSCAN -> next entry
        JSR  TRYCAND
        LDA  MATCH
        JNZ  IM_RUN
        JSR  APPENDBIN         ; entry + "/" + CMDBUF + ".BIN"
        JSR  TRYCAND
        LDA  MATCH
        JNZ  IM_RUN
        JMP  IM_LOOP
IM_RUN: LDA  #0                ; args already follow the command word -> no skip
        STA  RUNSKIP
        JMP  RUNGO
IM_UNK: LDP1 #MUNK
        JSR  PUTS
        JMP  SHELL

; BUILDCAND - RUNPATH = (PATH entry at PSCAN) + "/" + CMDBUF; advance PSCAN past
;   the entry (and its ';' separator). Entry ends at ';' or NUL.
BUILDCAND:
        LDA  PSCANL            ; P1 = PSCAN (source in PATHBUF)
        TAP1L
        LDA  PSCANH
        TAP1H
        LDP2 #RUNPATH          ; P2 = destination cursor
BC_CP:  LDA  (P1)
        JZ   BC_END            ; entry ends at NUL (last entry)
        LDB  #$3B              ; ';' (char literal would start a comment) -> separator
        CMP
        JZ   BC_SEP            ; entry ends at ';'
        STA  (P2)+
        INP1
        JMP  BC_CP
BC_SEP: INP1                   ; consume the ';' -> PSCAN at the next entry
BC_END: TPA1L                  ; save the advanced cursor back to PSCAN
        STA  PSCANL
        TPA1H
        STA  PSCANH
        LDA  #'/'              ; append "/"
        STA  (P2)+
        LDP1 #CMDBUF           ; append the command word
BC_CMD: LDA  (P1)+
        JZ   BC_TERM
        STA  (P2)+
        JMP  BC_CMD
BC_TERM:LDA  #0                ; NUL-terminate (leave P2 on it for APPENDBIN)
        STA  (P2)
        RTS

; APPENDBIN - append ".bin" to the NUL-terminated string in RUNPATH.
APPENDBIN:
        LDP2 #RUNPATH
AB_F:   LDA  (P2)
        JZ   AB_AP
        INP2
        JMP  AB_F
AB_AP:  LDA  #'.'
        STA  (P2)+
        LDA  #'b'
        STA  (P2)+
        LDA  #'i'
        STA  (P2)+
        LDA  #'n'
        STA  (P2)+
        LDA  #0
        STA  (P2)
        RTS

; TRYCAND - resolve RUNPATH to a regular file (-> entry fields + MATCH).
TRYCAND:LDP2 #RUNPATH
        JSR  FINDP2
        RTS

; PATHINIT - seed the program search path with the default "/bin".
PATHINIT:
        LDP1 #DEFPATH
        LDP2 #PATHBUF
PI_LP:  LDA  (P1)+
        STA  (P2)+
        JNZ  PI_LP
        RTS
DEFPATH:.asciiz "/bin"

; ---------------- DEL name ---------------------------------------------------
DODEL:  JSR  FINDARG
        JZ   NOFILE
        LDA  ENTPL              ; P1 <- &flags of the matched entry (in SBUF)
        TAP1L
        LDA  ENTPH
        TAP1H
        LDA  #F_DEL
        STA  (P1)               ; mark deleted in the buffered sector
        LDA  DLBA               ; persist that directory sector (16-bit)
        STA  LBA
        LDA  DLBAH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFWRITE
        LDA  #0                 ; restore LBA1=0 at rest
        STA  LBA1
        LDP1 #MDELETED
        JSR  OPUTS
        JMP  SHELL

NOFILE: LDP1 #MNOFILE
        JSR  PUTS
        JMP  SHELL

; ---------------- sh name : run shell commands from a script file ------------
; `sh FILE` — run shell commands from FILE. The script's read stream is kept open
; over IBUF and its state is saved/restored (SCRSAVE) around every dispatched
; command — each command (cc/asm/...) uses the BIOS read stream itself — so a
; script of any length streams a line at a time. GL_SCRIPT does the reading.
; Caveat: a script line can't use `< redirect` (it shares IBUF). Build a command
; from source, e.g.:  cc /src/commands/c/pwd.c >T.ASM   then   asm T.ASM /bin/pwd.bin
DOSH:   JSR  FINDARG            ; locate the script -> STARTLO/STARTHI + LENLO/LENHI
        JZ   NOFILE
        LDA  STARTLO            ; point a read stream at the script's extent (IBUF)
        STA  ROLBA
        LDA  STARTHI
        STA  ROLBA+1
        LDA  #0
        STA  ROLBA+2
        LDA  LENLO
        STA  ROREM
        LDA  LENHI
        STA  ROREM+1
        LDA  #<IBUF
        STA  ROBUF
        LDA  #>IBUF
        STA  ROBUF+1
        LDA  #0                 ; ROCNT=0 -> the first FGETB refills IBUF
        STA  ROCNT
        STA  ROCNT+1
        LDA  DRVSEL
        STA  ROSDRV
        JSR  SAVESCR            ; SCRSAVE <- this fresh stream state
        LDA  #1
        STA  SCRIPTM
        JMP  SHELL

; FINDARG - resolve a path argument to a regular file. Returns A=0 (Z set) on
; failure (bad directory path, not found, or it's a directory), A=1 with the
; entry fields filled on success.
FINDARG:JSR  ARG2P2             ; P2 -> argument text
FINDP2: JSR  RESOLVE            ; resolve the path at P2: SDIR = parent, NAMEBUF = leaf
        LDA  MATCH
        JZ   FA_NO
        JSR  FINDENT            ; scan SDIR for NAMEBUF
        LDA  MATCH
        JZ   FA_NO
        LDA  FLAGS              ; must be a regular file (not a directory)
        LDB  #F_FILE
        CMP
        JNZ  FA_NO
        LDA  #1
        STA  MATCH
        RTS
FA_NO:  LDA  #0
        STA  MATCH
        RTS

; ARG2P2 - point P2 at the saved argument position in LINEBUF.
ARG2P2: LDA  ARGPL
        TAP2L
        LDA  ARGPH
        TAP2H
        RTS

; ---------------- path resolution --------------------------------------------
; SKIPSPC - advance P2 past spaces.
SKIPSPC:LDA  (P2)
        LDB  #' '
        CMP
        JNZ  sks_d
        INP2
        JMP  SKIPSPC
sks_d:  RTS

; RV_START - begin a walk: skip spaces, then set SDIR to the root directory and
; consume a leading '/' (absolute path) or to the current directory (relative).
RV_START:JSR SKIPSPC
        LDA  (P2)
        LDB  #'/'
        CMP
        JZ   rvs_abs            ; absolute path
        ; relative: a bare "d1" is the mount only when the CWD is the drive-0
        ; root (so `CD D1` from / == `CD /d1`, but a real D1 subdir elsewhere,
        ; or D1 while already under /d1, stays an ordinary component).
        LDA  CURDRIVE
        JNZ  rvs_cwd            ; already under /d1 -> normal relative
        LDA  CWDLH
        JNZ  rvs_cwd            ; CWD not at the root (LBA 33) -> normal relative
        LDA  CWDL
        LDB  #33
        CMP
        JNZ  rvs_cwd
        JSR  MNTPFX             ; at root: bare "d1" -> mount (C=1), else C=0
        JC   rvs_root
        JMP  rvs_cwd            ; other name -> normal relative from root
rvs_abs:INP2                    ; consume leading '/'
        JSR  MNTPFX             ; "/d1[/]" -> drive 1 + strip (C=1); else C=0
        JC   rvs_root
        LDA  #0                 ; absolute, not the mount -> drive 0 root
        JSR  CFSEL
        JMP  rvs_root
rvs_cwd:LDA  CURDRIVE           ; relative path resolves on the CWD's drive
        JSR  CFSEL
        LDA  CWDL
        STA  SDIRL
        LDA  CWDLH
        STA  SDIRLH
        LDA  CWDN
        STA  SDIRN
        RTS
rvs_root:LDA #33
        STA  SDIRL
        LDA  #0
        STA  SDIRLH
        LDA  ROOTN
        STA  SDIRN
        RTS

; MNTPFX - at (P2), just past a leading '/', apply the mount redirect: if the
; component is "d1" (delimited by '/' or NUL) route I/O to drive 1 and advance
; P2 past it; otherwise route to drive 0 and leave P2 unchanged. Mirrors the
; firmware FRESOLVE redirect for the OS's own directory walker.
MNTPFX: TPA2L                   ; save P2 to restore on a non-match
        STA  MPSAV
        TPA2H
        STA  MPSAV+1
        LDA  (P2)
        LDB  #'d'
        CMP
        JNZ  mp_no
        INP2
        LDA  (P2)
        LDB  #'1'
        CMP
        JNZ  mp_no
        INP2
        LDA  (P2)               ; after "d1": NUL or '/' => the mount point
        JZ   mp_yes
        LDB  #'/'
        CMP
        JNZ  mp_no
        INP2                    ; consume the '/'
mp_yes: LDA  #1                 ; it is the mount: route to drive 1, C=1
        JSR  CFSEL
        SEC
        RTS
mp_no:  LDA  MPSAV              ; restore P2 (first component wasn't "d1"); C=0,
        TAP2L                   ;   leave the drive to the caller
        LDA  MPSAV+1
        TAP2H
        LDA  #0
        JSR  CFSEL
        RTS

; DERIVEDRV - CURDRIVE = 1 if CWDPATH begins "/d1" (the mount), else 0. Called
; after CD commits a new CWD so SYNCDRV routes current-drive ops to the right card.
DERIVEDRV:
        LDP2 #CWDPATH
        LDA  (P2)
        LDB  #'/'
        CMP
        JNZ  dd_0
        INP2
        LDA  (P2)
        LDB  #'d'
        CMP
        JNZ  dd_0
        INP2
        LDA  (P2)
        LDB  #'1'
        CMP
        JNZ  dd_0
        INP2
        LDA  (P2)               ; "/d1" then NUL or '/' => under the mount
        JZ   dd_1
        LDB  #'/'
        CMP
        JNZ  dd_0
dd_1:   LDA  #1
        STA  CURDRIVE
        RTS
dd_0:   LDA  #0
        STA  CURDRIVE
        RTS

; SYNCDRV - baseline routing = the current drive (call at each command).
SYNCDRV:LDA  CURDRIVE
        JSR  CFSEL
        RTS


; PARSECOMP - copy one path component from (P2) into NAMEBUF (case-preserved, 12,
; space-padded), stopping at '/', space, or null WITHOUT consuming it.
PARSECOMP:LDP1 #NAMEBUF
        LDA  #12
        STA  TMP
pc_fz:  LDA  #' '
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  pc_fz
        LDP1 #NAMEBUF
        LDA  #12
        STA  CNT
pc_lp:  LDA  (P2)
        JZ   pc_end
        LDB  #' '
        CMP
        JZ   pc_end
        LDB  #'/'
        CMP
        JZ   pc_end
        LDA  CNT
        JZ   pc_end
        LDA  (P2)               ; case preserved (filenames are case-sensitive;
        STA  (P1)               ; the command word is still upcased in PARSEW)
        INP1
        INP2
        LDA  CNT
        DEC
        STA  CNT
        JMP  pc_lp
pc_end: RTS

; DESCEND - find the directory named in NAMEBUF inside SDIR; on success set
; SDIR to its extent (start LBA + sector count) and MATCH=1, else MATCH=0.
; Preserves P2 (the caller's path cursor) — FINDENT walks SBUF with P2.
DESCEND:TPA2L
        STA  PATHL
        TPA2H
        STA  PATHH
        JSR  FINDENT
        LDA  PATHL
        TAP2L
        LDA  PATHH
        TAP2H
        LDA  MATCH
        JZ   dsc_no
        LDA  FLAGS
        LDB  #F_DIR
        CMP
        JNZ  dsc_no
        LDA  STARTLO
        STA  SDIRL
        LDA  STARTHI            ; 16-bit subdirectory start LBA
        STA  SDIRLH
        JSR  SECCOUNT           ; sectors from the dir's length field
        LDA  SECCNT
        STA  SDIRN
        LDA  #1
        STA  MATCH
        RTS
dsc_no: LDA  #0
        STA  MATCH
        RTS

; RESOLVE - walk a path leaving SDIR = the containing directory and NAMEBUF =
; the final (leaf) component. MATCH=0 if an intermediate component is missing
; or not a directory.
RESOLVE:JSR  RV_START
rv_lp:  JSR  PARSECOMP
        LDA  (P2)               ; delimiter after the component
        LDB  #'/'
        CMP
        JNZ  rv_done            ; not '/': NAMEBUF is the leaf
        INP2                    ; consume '/'; NAMEBUF is an intermediate dir
        JSR  DESCEND
        LDA  MATCH
        JZ   rv_bad
        JMP  rv_lp
rv_done:LDA  #1
        STA  MATCH
        RTS
rv_bad: LDA  #0
        STA  MATCH
        RTS

; CDPATH - walk a path treating every component as a directory; on success
; SDIR = the target directory and MATCH=1.
CDPATH: JSR  RV_START
cd_lp:  JSR  PARSECOMP
        LDA  NAMEBUF            ; empty component (e.g. "/" alone) -> SDIR is it
        LDB  #' '
        CMP
        JZ   cd_done
        JSR  DESCEND
        LDA  MATCH
        JZ   cd_bad
        LDA  (P2)
        LDB  #'/'
        CMP
        JNZ  cd_done            ; no more components
        INP2
        JMP  cd_lp
cd_done:LDA  #1
        STA  MATCH
        RTS
cd_bad: LDA  #0
        STA  MATCH
        RTS

; ---------------- CD path ----------------------------------------------------
DOCD:   JSR  ARG2P2
        JSR  CDPATH             ; resolve to a directory -> SDIR (RV_START does /d1)
        LDA  MATCH
        JZ   NODIR
        LDA  SDIRL              ; commit it as the working directory
        STA  CWDL
        LDA  SDIRLH
        STA  CWDLH
        LDA  SDIRN
        STA  CWDN
        JSR  SETPATH            ; update the displayed CWD path
        JSR  DERIVEDRV          ; CURDRIVE = is the new CWD under /d1?
        JMP  SHELL
NODIR:  LDP1 #MNODIR
        JSR  PUTS
        JMP  SHELL

; PATHROOT - CWDPATH = "/".
PATHROOT:LDP1 #CWDPATH
        LDA  #'/'
        STA  (P1)+
        LDA  #0
        STA  (P1)
        RTS

; SETPATH - best-effort update of the displayed CWD path from the CD argument:
;   absolute  -> copy it;  ".." -> pop a component;  else -> append "/arg".
; (CWDL/CWDN are always exact; this only affects the prompt text.)
SETPATH:JSR  ARG2P2
        JSR  SKIPSPC
        LDA  (P2)
        LDB  #'/'
        CMP
        JZ   sp_abs
        LDA  (P2)
        LDB  #'.'
        CMP
        JNZ  sp_app
        INP2                    ; maybe ".."
        LDA  (P2)
        LDB  #'.'
        CMP
        JNZ  sp_app
        INP2
        LDA  (P2)               ; ".." must be the whole component
        JZ   sp_pop
        LDB  #' '
        CMP
        JZ   sp_pop
        JMP  sp_app             ; "../..." compound -> just append (approximate)
sp_pop: JSR  PATHPOP
        RTS
sp_abs: JSR  ARG2P2             ; copy the absolute path verbatim (upcased)
        JSR  SKIPSPC
        LDP1 #CWDPATH
sa_lp:  LDA  (P2)
        JZ   sa_end
        LDB  #' '
        CMP
        JZ   sa_end
        STA  (P1)               ; case preserved (case-sensitive CWD path)
        INP1
        INP2
        JMP  sa_lp
sa_end: LDA  #0
        STA  (P1)
        RTS
sp_app: JSR  ARG2P2
        JSR  SKIPSPC
        LDA  CWDPATH+1          ; at root ("/")? then write name after the '/'
        JNZ  sap_walk
        LDP1 #CWDPATH
        INP1
        JMP  sap_copy
sap_walk:LDP1 #CWDPATH          ; else walk to end and add a '/'
sap_e:  LDA  (P1)
        JZ   sap_sl
        INP1
        JMP  sap_e
sap_sl: LDA  #'/'
        STA  (P1)
        INP1
sap_copy:LDA (P2)
        JZ   sap_end
        LDB  #' '
        CMP
        JZ   sap_end
        STA  (P1)               ; case preserved (case-sensitive CWD path)
        INP1
        INP2
        JMP  sap_copy
sap_end:LDA  #0
        STA  (P1)
        RTS

; PATHPOP - drop the last component of CWDPATH (truncate at the last '/',
; leaving at least "/").
PATHPOP:LDA  #<CWDPATH
        STA  LSL
        LDA  #>CWDPATH
        STA  LSH
        LDP1 #CWDPATH
pp_lp:  LDA  (P1)
        JZ   pp_done
        LDB  #'/'
        CMP
        JNZ  pp_adv
        TPA1L
        STA  LSL
        TPA1H
        STA  LSH
pp_adv: INP1
        JMP  pp_lp
pp_done:LDA  LSL                ; last '/' at the very start -> keep "/"
        LDB  #<CWDPATH
        CMP
        JNZ  pp_cut
        LDA  LSH
        LDB  #>CWDPATH
        CMP
        JNZ  pp_cut
        LDP1 #CWDPATH
        INP1
        LDA  #0
        STA  (P1)
        RTS
pp_cut: LDA  LSL
        TAP1L
        LDA  LSH
        TAP1H
        LDA  #0
        STA  (P1)
        RTS

; SECCOUNT - SECCNT = ceil(LENLO:LENHI / 512) = (LENHI>>1) rounded up when any
; low bits remain. Used by LOAD and SAVE.
SECCOUNT:LDA LENHI
        SHR
        STA  SECCNT
        LDA  LENHI
        LDB  #1
        AND                     ; high byte odd -> 256-byte tail -> round up
        JNZ  SC_RND
        LDA  LENLO
        JZ   SC_GO              ; exact multiple of 512
SC_RND: LDA  SECCNT
        INC
        STA  SECCNT
SC_GO:  RTS

; ---------------- MKDIR path -------------------------------------------------
; Create a subdirectory: allocate a SUBSECS-sector extent at the free pointer,
; lay down its '.' / '..', and add an entry to the parent directory.
DOMKDIR:JSR  ARG2P2             ; P2 -> the path argument
        JSR  MKDIRCORE          ; create it; A = status, C=1 on error
        JNC  mk_ok
        LDB  #1
        CMP
        JZ   NODIR              ; A=1: bad parent path
        LDB  #2
        CMP
        JZ   MK_EXIST           ; A=2: already exists
        JMP  SV_FULL            ; A=3: parent directory full
mk_ok:  LDP1 #MMKOK
        JSR  OPUTS
        JMP  SHELL
MK_EXIST:LDP1 #MEXIST
        JSR  PUTS
        JMP  SHELL

; MKDIRCORE - create the directory named by the NUL-terminated path at (P2).
; Returns A = status (0 created / 1 bad parent path / 2 already exists / 3 parent
; directory full) and C=1 on any error (A != 0). Shared by DOMKDIR and the
; SYS_MKDIR syscall (so a /BIN program like `cp -r` can make directories).
MKDIRCORE:
        JSR  RESOLVE            ; SDIR = parent, NAMEBUF = new dir name
        LDA  MATCH
        JNZ  mkc_p
        LDA  #1                 ; bad parent path
        SEC
        RTS
mkc_p:  LDA  SDIRL              ; remember the parent extent (16-bit)
        STA  PSL
        LDA  SDIRLH
        STA  PSLH
        LDA  SDIRN
        STA  PSN
        JSR  FINDENT            ; already present?
        LDA  MATCH
        JZ   mkc_new
        LDA  #2                 ; already exists
        SEC
        RTS
mkc_new:LDP1 #SBUF              ; allocate: read free pointer, bump it by SUBSECS
        LDA  #0                 ; boot block is LBA 0 (FINDENT left LBA1 nonzero
        STA  LBA                ;   for a parent dir >=256, so zero it explicitly)
        STA  LBA1
        STA  LBA2
        JSR  CFREAD
        LDA  SBUF+4             ; new extent LBA = free pointer (16-bit)
        STA  NEWLBA
        LDA  SBUF+5
        STA  NEWLBAH
        LDA  SBUF+4
        LDB  #SUBSECS
        ADD
        STA  SBUF+4
        LDA  SBUF+5
        JNC  mkc_nc
        INC
mkc_nc: STA  SBUF+5
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFWRITE
        JSR  MKEXT              ; write the new extent's '.' and '..'
        LDA  PSL                ; add the entry into the parent (16-bit)
        STA  SDIRL
        LDA  PSLH
        STA  SDIRLH
        LDA  PSN
        STA  SDIRN
        JSR  FINDSLOT
        LDA  MATCH
        JNZ  mkc_slot
        LDA  #3                 ; parent directory full
        SEC
        RTS
mkc_slot:LDA #F_DIR
        STA  EFLAG
        LDA  NEWLBA             ; entry: start=NEWLBA (16-bit), len=SUBSECS*512
        STA  FREELO
        LDA  NEWLBAH
        STA  FREEHI
        LDA  #0
        STA  SVSTLO
        STA  SVSTHI
        STA  LENLO
        LDA  #SUBSECS
        SHL                     ; SUBSECS*512 -> high byte = SUBSECS*2
        STA  LENHI
        JSR  WRENT
        LDA  DLBA               ; write the parent directory sector back (16-bit)
        STA  LBA
        LDA  DLBAH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFWRITE
        LDA  #0                 ; success (A=0), restore LBA1=0 at rest
        STA  LBA1
        CLC
        RTS

; MKEXT - initialize the directory extent at NEWLBA: entry 0 = '.', entry 1 =
; '..' (parent = PSL/PSN); remaining sectors zeroed.
MKEXT:  JSR  ZSB                ; SBUF = 512 zeros
        LDP1 #SBUF
        LDA  #'.'               ; entry 0 ".", 11 trailing spaces
        STA  (P1)+
        LDA  #11
        STA  TMP
mx_d0:  LDA  #' '
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  mx_d0
        LDA  NEWLBA             ; start LBA (4) = this dir (16-bit)
        STA  (P1)+
        LDA  NEWLBAH
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  #0                 ; length = SUBSECS*512 (4)
        STA  (P1)+
        LDA  #SUBSECS
        SHL
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  #0                 ; load + exec (4) = 0
        STA  (P1)+
        STA  (P1)+
        STA  (P1)+
        STA  (P1)+
        LDA  #F_DIR             ; flag
        STA  (P1)+
        LDA  #7                 ; spare (7)
        STA  TMP
mx_s0:  LDA  #0
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  mx_s0
        LDA  #'.'               ; entry 1 "..", 10 trailing spaces
        STA  (P1)+
        LDA  #'.'
        STA  (P1)+
        LDA  #10
        STA  TMP
mx_d1:  LDA  #' '
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  mx_d1
        LDA  PSL                ; start LBA = parent (4), 16-bit
        STA  (P1)+
        LDA  PSLH
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  #0                 ; length = PSN*512 (4)
        STA  (P1)+
        LDA  PSN
        SHL
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  #0                 ; load + exec (4)
        STA  (P1)+
        STA  (P1)+
        STA  (P1)+
        STA  (P1)+
        LDA  #F_DIR             ; flag (spare left zero by ZSB)
        STA  (P1)+
        LDA  NEWLBA             ; write the first sector (16-bit LBA)
        STA  LBA
        LDA  NEWLBAH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFWRITE
        LDA  LBA                ; advance to the second sector (16-bit)
        INC
        STA  LBA
        JNZ  mx_zi
        LDA  LBA1
        INC
        STA  LBA1
mx_zi:  LDA  #SUBSECS-1         ; CNT (not TMP) — ZSB clobbers TMP each pass
        STA  CNT
mx_z:   JSR  ZSB
        JSR  CFWRITE
        LDA  LBA                ; 16-bit advance
        INC
        STA  LBA
        JNZ  mx_zc
        LDA  LBA1
        INC
        STA  LBA1
mx_zc:  LDA  CNT
        DEC
        STA  CNT
        JNZ  mx_z
        RTS

; ---------------- FORMAT (on-target P8XFS v2) --------------------------------
; Rewrite the volume as a fresh P8XFS v2: boot block ('P8', version 2, OSCNT
; preserved so the card stays bootable, free pointer = 37) + a clean root extent
; at LBA 33 (4 sectors) with '.'/'..' (reusing MKEXT). Asks Y/N first; on success
; leaves RAM exactly as a freshly-booted v2 card (root = CWD). The OS image at
; LBA 1..32 is untouched, so EXIT+B re-boots the same OS onto the clean volume.
DOFORMAT:LDP1 #MFMTQ            ; "FORMAT: erase card as v2? (Y/N) "
        JSR  OPUTS
        JSR  CONIN              ; one key
        STA  TMP2               ; save before the echo clobbers A
        JSR  CONOUT             ; echo it
        JSR  CRLF
        LDA  TMP2
        LDB  #'Y'
        CMP
        JZ   FMT_GO
        LDB  #'y'
        CMP
        JNZ  FMT_AB
FMT_GO: LDP1 #SBUF              ; read current boot block to keep OSCNT
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFREAD
        LDA  SBUF+3             ; OSCNT (sectors of OS image at LBA 1..)
        STA  TMP2               ; stash across ZSB
        JSR  ZSB                ; clean boot sector
        LDA  #'P'
        STA  SBUF+0
        LDA  #'8'
        STA  SBUF+1
        LDA  #2                 ; version 2 (hierarchical)
        STA  SBUF+2
        LDA  TMP2               ; OSCNT preserved (card stays bootable)
        STA  SBUF+3
        LDA  #37                ; free pointer = first v2 data LBA
        STA  SBUF+4
        LDA  #0
        STA  SBUF+5
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFWRITE            ; write boot block (LBA 0)
        LDA  #33                ; fresh root extent at LBA 33, parent = itself
        STA  NEWLBA
        STA  PSL
        LDA  #0                 ; root LBA < 256, so high bytes are 0 (MKEXT reads
        STA  NEWLBAH            ;   NEWLBAH/PSLH for the 16-bit start LBAs)
        STA  PSLH
        LDA  #SUBSECS           ; 4 sectors (= root size)
        STA  PSN
        JSR  MKEXT              ; write root '.'/'..' + zero LBAs 34..36
        LDA  #4                 ; adopt the v2 layout in RAM (as COLD does)
        STA  ROOTN
        LDA  #37
        STA  DATABASE
        LDA  #33
        STA  CWDL
        LDA  #0
        STA  CWDLH
        LDA  #4
        STA  CWDN
        JSR  PATHROOT           ; CWDPATH = "/"
        LDP1 #MFMTOK
        JSR  OPUTS
        JMP  SHELL
FMT_AB: LDP1 #MFMTAB
        JSR  OPUTS
        JMP  SHELL

; ZSB - fill the 512-byte sector buffer with zeros.
ZSB:    LDP1 #SBUF
        LDA  #0
        STA  TMP
zsb1:   LDA  #0
        STA  (P1)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  zsb1
        LDA  #0
        STA  TMP
zsb2:   LDA  #0
        STA  (P1)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  zsb2
        RTS

; ---------------- RMDIR path -------------------------------------------------
; Remove an empty subdirectory: resolve it, confirm it's a directory and empty
; (nothing past '.'/'..'), then tombstone its entry in the parent.
DORMDIR:JSR  ARG2P2
        JSR  RESOLVE
        LDA  MATCH
        JZ   NODIR
        JSR  FINDENT            ; locate the entry in the parent
        LDA  MATCH
        JZ   NODIR
        LDA  FLAGS
        LDB  #F_DIR
        CMP
        JNZ  RM_NOTDIR
        LDA  DLBA               ; save parent sector + entry pointer (FINDENT set
        STA  RMDL               ;   ENTPL/H; DIREMPTY will reuse SBUF/DLBA)
        LDA  DLBAH
        STA  RMDLH
        LDA  STARTLO            ; scan the child extent for non-./.. entries
        STA  SDIRL
        LDA  STARTHI
        STA  SDIRLH
        JSR  SECCOUNT           ; child sector count from its length
        LDA  SECCNT
        STA  SDIRN
        JSR  DIREMPTY
        LDA  MATCH
        JZ   RM_NOTMT
        LDP1 #SBUF              ; empty: tombstone the parent entry (16-bit LBA)
        LDA  RMDL
        STA  LBA
        LDA  RMDLH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFREAD
        LDA  ENTPL
        TAP1L
        LDA  ENTPH
        TAP1H
        LDA  #F_DEL
        STA  (P1)
        LDA  RMDL
        STA  LBA
        LDA  RMDLH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFWRITE
        LDA  #0                 ; restore LBA1=0 at rest
        STA  LBA1
        LDP1 #MRMOK
        JSR  OPUTS
        JMP  SHELL
RM_NOTDIR:LDP1 #MNOTDIR
        JSR  PUTS
        JMP  SHELL
RM_NOTMT:LDP1 #MNOTMT
        JSR  PUTS
        JMP  SHELL

; DIREMPTY - MATCH=1 if directory (SDIRL,SDIRN) holds only '.'/'..' (and the end
; marker); MATCH=0 if any other live entry exists.
DIREMPTY:LDA SDIRL
        STA  DLBA
        LDA  SDIRLH             ; 16-bit child-directory scan cursor
        STA  DLBAH
        LDA  SDIRN
        STA  SCNT
de_sec: LDP1 #SBUF
        LDA  DLBA
        STA  LBA
        LDA  DLBAH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFREAD
        LDP2 #SBUF
        LDA  #16
        STA  ECNT
de_ent: JSR  RDENT              ; NAMEBUF + FLAGS
        LDA  FLAGS
        JZ   de_mt              ; end marker -> empty
        LDB  #F_DEL
        CMP
        JZ   de_nx              ; deleted -> skip
        LDA  NAMEBUF            ; '.' / '..' both start with '.'
        LDB  #'.'
        CMP
        JNZ  de_no              ; a real entry -> not empty
de_nx:  LDA  ECNT
        DEC
        STA  ECNT
        JNZ  de_ent
        LDA  DLBA               ; advance the 16-bit scan cursor
        INC
        STA  DLBA
        JNZ  de_snc
        LDA  DLBAH
        INC
        STA  DLBAH
de_snc: LDA  SCNT
        DEC
        STA  SCNT
        JNZ  de_sec
de_mt:  LDA  #1
        STA  MATCH
        JMP  de_rst
de_no:  LDA  #0
        STA  MATCH
de_rst: LDA  #0                 ; restore LBA1=0 at rest
        STA  LBA1
        STA  LBA2
        RTS

; (TR_PUSH/TR_POP/READCUR below stay — shared with FSCK and PACK.)

; ---------------- FSCK (read-only consistency check) ------------------------
; Walks the directory tree WITHOUT modifying the
; disk, and verifies: the boot signature 'P8'; every live extent starts in the
; data area and ends at/below the free pointer; and (v2) every directory's
; '..' points at its real parent. Prints counts and a verdict. Exhaustive
; cross-extent overlap and volume-end checks remain in the host tool
; (p8xfs.py fsck) - this is a quick on-target integrity check.
DOFSCK: LDA  #0
        STA  FNDIR
        STA  FNFIL
        STA  FNDEL
        STA  FMAXE
        STA  FUSED
        STA  FERR
        ; --- boot block: signature + free pointer ---
        LDP1 #SBUF
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFREAD
        LDA  SBUF+4             ; free pointer (16-bit)
        STA  FREELO
        LDA  SBUF+5
        STA  FREEHI
        LDA  #0                 ; FMAXE/FUSED are 16-bit accumulators
        STA  FMAXEH
        STA  FUSEDH
        LDA  SBUF
        LDB  #'P'
        CMP
        JNZ  FK_SIG
        LDA  SBUF+1
        LDB  #'8'
        CMP
        JZ   FK_RDD            ; signature OK
FK_SIG: LDP1 #MFKSIG
        JSR  OPUTS
        JSR  CRLF
        JSR  FK_BUMP
FK_RDD: ; root's '..' must point at the root (LBA 33)
        LDA  #33
        STA  FCHILD
        LDA  #33
        STA  FEXP
        LDA  #0
        STA  FCHILDH
        STA  FEXPH
        JSR  CHKDD
        ; --- walk from the root ---
        LDA  #33
        STA  CDST
        LDA  #0
        STA  CDSTH
        LDA  ROOTN
        STA  CDSC
        LDA  #0
        STA  CIDX
        STA  TSP
FK_ENT: LDA  CDSC              ; max entries in this directory = CDSC * 16
        SHL
        SHL
        SHL
        SHL
        STA  TMP
        LDA  CIDX
        LDB  TMP
        CMP
        JC   FK_ASC            ; CIDX >= max -> ascend
        JSR  READCUR
        LDA  FLAGS
        JZ   FK_ASC            ; $00 end marker
        LDA  CIDX              ; advance for our eventual return
        INC
        STA  CIDX
        LDA  FLAGS
        LDB  #F_DEL
        CMP
        JZ   FK_DEL
        LDA  NAMEBUF           ; '.' and '..' both start with '.'
        LDB  #'.'
        CMP
        JZ   FK_ENT
        ; --- live file or directory: per-extent checks ---
        JSR  SECCOUNT          ; SECCNT = sectors for this extent
        LDA  STARTHI           ; start must be in the data area (16-bit)
        JNZ  FK_INB            ; high byte set -> start >=256 > DATABASE, in bounds
        LDA  STARTLO
        LDB  DATABASE
        CMP                    ; C=1 when start >= DATABASE
        JC   FK_INB
        LDP1 #MFKLOW
        JSR  OPUTS
        LDA  STARTLO
        JSR  OPHEX8
        JSR  CRLF
        JSR  FK_BUMP
FK_INB: LDA  STARTLO           ; end = start + sectors (16-bit); track max + used
        LDB  SECCNT
        ADD
        STA  TMP               ; end low
        LDA  STARTHI
        JNC  fk_enc
        INC
fk_enc: STA  TMP2              ; end high
        LDA  TMP2              ; max(end, FMAXE), 16-bit
        LDB  FMAXEH
        CMP
        JNZ  fk_mxc            ; high bytes differ -> their carry decides
        LDA  TMP
        LDB  FMAXE
        CMP
fk_mxc: JNC  FK_NMX            ; end < FMAXE -> keep current max
        LDA  TMP
        STA  FMAXE
        LDA  TMP2
        STA  FMAXEH
FK_NMX: LDA  FUSED             ; FUSED += SECCNT (16-bit)
        LDB  SECCNT
        ADD
        STA  FUSED
        JNC  fk_unc
        LDA  FUSEDH
        INC
        STA  FUSEDH
fk_unc: LDA  FLAGS
        LDB  #F_DIR
        CMP
        JNZ  FK_FIL
        ; --- directory: count, check '..', descend ---
        LDA  FNDIR
        INC
        STA  FNDIR
        LDA  STARTLO
        STA  FCHILD
        LDA  STARTHI
        STA  FCHILDH
        LDA  CDST              ; this directory is the child's parent (16-bit)
        STA  FEXP
        LDA  CDSTH
        STA  FEXPH
        JSR  CHKDD
        LDA  TSP               ; depth limit (8 frames) -> don't descend deeper
        LDB  #7
        CMP
        JC   FK_ENT
        JSR  TR_PUSH
        LDA  STARTLO
        STA  CDST
        LDA  STARTHI
        STA  CDSTH
        JSR  SECCOUNT
        LDA  SECCNT
        STA  CDSC
        LDA  #0
        STA  CIDX
        JMP  FK_ENT
FK_FIL: LDA  FNFIL
        INC
        STA  FNFIL
        JMP  FK_ENT
FK_DEL: LDA  FNDEL
        INC
        STA  FNDEL
        JMP  FK_ENT
FK_ASC: LDA  TSP
        JZ   FK_REP
        JSR  TR_POP
        JMP  FK_ENT
; --- report ---
FK_REP: LDA  FMAXEH            ; free pointer must cover the highest extent (16-bit)
        LDB  FREEHI
        CMP
        JNZ  fk_frc            ; high bytes differ -> their carry/zero decide
        LDA  FMAXE
        LDB  FREELO
        CMP
fk_frc: JNC  FK_FOK            ; FMAXE < FREE -> fine
        JZ   FK_FOK            ; FMAXE == FREE -> fine (free just past it)
        LDP1 #MFKFRE
        JSR  OPUTS
        JSR  CRLF
        JSR  FK_BUMP
FK_FOK: LDP1 #MFKD             ; "DIRS="
        JSR  OPUTS
        LDA  FNDIR
        JSR  OPHEX8
        LDP1 #MFKF             ; " FILES="
        JSR  OPUTS
        LDA  FNFIL
        JSR  OPHEX8
        LDP1 #MFKX             ; " DEL="
        JSR  OPUTS
        LDA  FNDEL
        JSR  OPHEX8
        LDP1 #MFKR             ; " FREE=" (16-bit: high then low)
        JSR  OPUTS
        LDA  FREEHI
        JSR  OPHEX8
        LDA  FREELO
        JSR  OPHEX8
        LDP1 #MFKU             ; " USED=" (16-bit)
        JSR  OPUTS
        LDA  FUSEDH
        JSR  OPHEX8
        LDA  FUSED
        JSR  OPHEX8
        JSR  CRLF
        LDA  FERR
        JZ   FK_GOOD
        LDP1 #MFKBAD           ; "FSCK: PROBLEMS="
        JSR  OPUTS
        LDA  FERR
        JSR  OPHEX8
        JSR  CRLF
        JMP  SHELL
FK_GOOD:LDP1 #MFKOK
        JSR  OPUTS
        JSR  CRLF
        JMP  SHELL

; FK_BUMP - count one problem (saturates at 255).
FK_BUMP:LDA  FERR
        LDB  #$FF
        CMP
        JZ   fkb_r
        LDA  FERR
        INC
        STA  FERR
fkb_r:  RTS

; CHKDD - verify the '..' entry (slot 1) of directory FCHILD/FCHILDH points at
; FEXP/FEXPH (16-bit). Reads FCHILD's first sector; slot 1's start-LBA bytes are
; at SBUF + 32 + 12 = 44 (low) and 45 (high).
CHKDD:  LDA  FCHILD
        STA  LBA
        LDA  FCHILDH
        STA  LBA1
        LDA  #0
        STA  LBA2
        LDP1 #SBUF
        JSR  CFREAD
        LDA  SBUF+44           ; '..' start LBA low
        LDB  FEXP
        CMP
        JNZ  ck_bad
        LDA  SBUF+45           ; '..' start LBA high
        LDB  FEXPH
        CMP
        JZ   cd_ok
ck_bad: LDP1 #MFKPAR
        JSR  OPUTS
        LDA  FCHILD
        JSR  OPHEX8
        JSR  CRLF
        JSR  FK_BUMP
cd_ok:  LDA  #0               ; restore LBA1=0 at rest (CHKDD read a dir sector)
        STA  LBA1
        RTS

; READCUR - read entry CIDX of the current directory (CDST) into NAMEBUF /
; STARTLO / LENLO:LENHI / FLAGS. Reads the containing sector into SBUF.
READCUR:LDA  CIDX               ; sector = CDST/CDSTH + CIDX/16 (16-bit)
        SHR
        SHR
        SHR
        SHR
        LDB  CDST
        ADD
        STA  LBA
        LDA  CDSTH              ; high byte + carry from the low-byte ADD
        JNC  rc_nc
        INC
rc_nc:  STA  LBA1
        LDA  #0
        STA  LBA2
        LDP1 #SBUF
        JSR  CFREAD
        LDP2 #SBUF              ; advance P2 to slot (CIDX & 15) * 32 bytes
        LDA  CIDX
        LDB  #15
        AND
        STA  TI
rc_pos: LDA  TI
        JZ   rc_rd
        LDA  #32
        STA  TMP
rc_p2:  INP2
        LDA  TMP
        DEC
        STA  TMP
        JNZ  rc_p2
        LDA  TI
        DEC
        STA  TI
        JMP  rc_pos
rc_rd:  LDP1 #NAMEBUF           ; read the 32-byte entry at (P2)
        LDA  #12
        STA  TMP
rf_nm:  LDA  (P2)+
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  rf_nm
        LDA  (P2)+              ; start LBA (low 16 kept)
        STA  STARTLO
        LDA  (P2)+
        STA  STARTHI
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; length low 16
        STA  LENLO
        LDA  (P2)+
        STA  LENHI
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; load + exec
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; flag
        STA  FLAGS
        LDA  #0                 ; restore LBA1=0 at rest (read a dir sector with a
        STA  LBA1               ; 16-bit LBA; the next READCUR/CHKDD re-sets it, and
        STA  LBA2               ; boot-block reads after the walk stay correct)
        RTS

; TR_PUSH / TR_POP - save/restore the current (CDST/CDSTH,CDSC,CIDX) frame in the
; depth stack at TFRAME + TSP*4 (4 bytes/frame: dst_lo, dst_hi, dsc, idx).
TR_PUSH:LDP1 #TFRAME
        LDA  TSP
        STA  TI
tp_a:   LDA  TI
        JZ   tp_w
        INP1
        INP1
        INP1
        INP1
        LDA  TI
        DEC
        STA  TI
        JMP  tp_a
tp_w:   LDA  CDST
        STA  (P1)+
        LDA  CDSTH
        STA  (P1)+
        LDA  CDSC
        STA  (P1)+
        LDA  CIDX
        STA  (P1)
        LDA  TSP
        INC
        STA  TSP
        RTS
TR_POP: LDA  TSP
        DEC
        STA  TSP
        LDP1 #TFRAME
        LDA  TSP
        STA  TI
to_a:   LDA  TI
        JZ   to_r
        INP1
        INP1
        INP1
        INP1
        LDA  TI
        DEC
        STA  TI
        JMP  to_a
to_r:   LDA  (P1)+
        STA  CDST
        LDA  (P1)+
        STA  CDSTH
        LDA  (P1)+
        STA  CDSC
        LDA  (P1)
        STA  CIDX
        RTS

; LOADF - read the located file (STARTLO / LENLO:LENHI / LOADLO:LOADHI) into
; memory at its load address.
LOADF:  LDA  STARTLO            ; set up the BIOS bulk read: LBA = start (16-bit)
        STA  LBA
        LDA  STARTHI
        STA  LBA1
        LDA  #0
        STA  LBA2
        LDA  LENLO              ; FLEN = length
        STA  FLEN
        LDA  LENHI
        STA  FLEN+1
        LDA  LOADLO             ; P1 = load address
        TAP1L
        LDA  LOADHI
        TAP1H
        JMP  FLOADAT            ; reads the whole file into (P1); RTSes to caller

; ---------------- SAVE name start end ----------------------------------------
; Write the memory range [start,end) to a new file: length = end - start,
; allocate at the boot-block free pointer, copy memory into successive sectors,
; add a directory entry, and advance the free pointer.
DOSAVE: JSR  ARG2P2             ; P2 -> argument text
        JSR  RESOLVE            ; SDIR = parent dir, NAMEBUF = leaf name
        LDA  MATCH
        JZ   SV_ERR
        TPA2L                   ; reject a duplicate name. FINDENT clobbers P2 and
        STA  RS2L               ; LENLO/HI, so do it now (before the length calc)
        TPA2H                   ; and save/restore the arg cursor for GETHEX.
        STA  RS2H
        JSR  FINDENT
        LDA  MATCH
        JNZ  SV_EXIST
        LDA  RS2L
        TAP2L
        LDA  RS2H
        TAP2H
        JSR  GETHEX             ; start address
        LDA  MATCH
        JZ   SV_ERR
        LDA  HXLO
        STA  SVSTLO
        LDA  HXHI
        STA  SVSTHI
        JSR  GETHEX             ; end address
        LDA  MATCH
        JZ   SV_ERR
        ; length = end - start (16-bit), into LENLO:LENHI
        LDA  HXLO
        LDB  SVSTLO
        SUB                     ; C=1 when no borrow (end_lo >= start_lo)
        STA  LENLO
        JC   SV_HI
        LDA  HXHI               ; borrow: high = end_hi - start_hi - 1
        LDB  SVSTHI
        SUB
        STA  LENHI
        LDA  LENHI
        LDB  #1
        SUB
        STA  LENHI
        JMP  SV_LEN
SV_HI:  LDA  HXHI
        LDB  SVSTHI
        SUB
        STA  LENHI
SV_LEN: JSR  SECCOUNT           ; SECCNT = sectors needed
        JSR  SAVECORE
        LDA  MATCH
        JZ   SV_FULL
        LDP1 #MSAVED
        JSR  OPUTS
        JMP  SHELL
SV_ERR: LDP1 #MSVERR
        JSR  PUTS
        JMP  SHELL
SV_EXIST:LDP1 #MEXIST
        JSR  PUTS
        JMP  SHELL
SV_FULL:LDP1 #MDIRFUL
        JSR  PUTS
        JMP  SHELL


; ---------------- PACK : compact the data area -------------------------------
; SAVE allocates at the free pointer and DEL/RMDIR only tombstone, so deleted
; extents leak; PACK reclaims them. Two phases. PHASE 1 compacts every extent
; (files AND directory extents) down
; to a running free pointer, ascending by start LBA, updating ONLY the one
; parent directory entry that points to each (the find-walk reaches each extent
; via that entry, so it has the location in hand; re-walking each pass reflects
; prior moves). Moving a directory carries its child *listing* verbatim, so
; child pointers stay valid; navigation during the walk uses parent listings,
; not '.'/'..', so stale './..' don't matter here. PHASE 2 then re-walks the
; (now compacted) tree and rewrites every directory's '.' (=self) and '..'
; (=parent) from final positions. Root (LBA 33..36) never moves.
DOPACK: LDA  DATABASE           ; first data LBA (37); NF is 16-bit
        STA  NF
        LDA  #0
        STA  NFH
P2_PASS:JSR  PK2FIND            ; PFOUND + MINSTRT/MINSEC + PPSEC/PPSLOT
        LDA  PFOUND
        JZ   P2_FIX
        LDA  MINSTRT            ; already at NF (16-bit)? just advance
        LDB  NF
        CMP
        JNZ  P2_MOVE
        LDA  MINSTRTH
        LDB  NFH
        CMP
        JZ   P2_ADV
P2_MOVE:JSR  PK2MOVE            ; copy extent down, repoint the parent entry
P2_ADV: LDA  NF                 ; NF += MINSEC (16-bit)
        LDB  MINSEC
        ADD
        STA  NF
        JNC  P2_PNC
        LDA  NFH
        INC
        STA  NFH
P2_PNC: JMP  P2_PASS
P2_FIX: JSR  PK2FIX             ; phase 2: repair every dir's '.' and '..'
        LDP1 #SBUF              ; write the new free pointer (16-bit)
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFREAD
        LDA  NF
        STA  SBUF+4
        LDA  NFH
        STA  SBUF+5
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFWRITE
        LDP1 #MPACKED
        JSR  OPUTS
        JMP  SHELL

; PK2FIND - tree-walk; find the live file/dir extent with the smallest start
; LBA >= NF. Sets PFOUND, MINSTRT, MINSEC, and PPSEC/PPSLOT = the dir sector +
; slot of the entry that points to it (its parent reference).
PK2FIND:LDA  #0
        STA  PFOUND
        LDA  #33
        STA  CDST
        LDA  #0
        STA  CDSTH
        LDA  ROOTN
        STA  CDSC
        LDA  #0
        STA  CIDX
        STA  TSP
pf_ent: LDA  CDSC               ; end of this directory?
        SHL
        SHL
        SHL
        SHL
        STA  TMP
        LDA  CIDX
        LDB  TMP
        CMP
        JC   pf_asc
        LDA  CIDX               ; record this entry's location before reading
        SHR
        SHR
        SHR
        SHR
        LDB  CDST
        ADD
        STA  CANDSEC
        LDA  CDSTH              ; 16-bit: high byte + carry from the low-byte ADD
        JNC  pf_cnc
        INC
pf_cnc: STA  CANDSECH
        LDA  CIDX
        LDB  #15
        AND
        STA  CANDSLOT
        JSR  READCUR            ; NAMEBUF / STARTLO / LEN / FLAGS
        LDA  FLAGS
        JZ   pf_asc             ; $00 end marker
        LDA  CIDX
        INC
        STA  CIDX
        LDA  FLAGS
        LDB  #F_DEL
        CMP
        JZ   pf_ent             ; deleted
        LDA  NAMEBUF            ; skip '.' / '..'
        LDB  #'.'
        CMP
        JZ   pf_ent
        LDA  STARTHI            ; candidate only if start >= NF (16-bit)
        LDB  NFH
        CMP
        JNZ  pf_gnf             ; high bytes differ -> their carry decides
        LDA  STARTLO
        LDB  NF
        CMP
pf_gnf: JNC  pf_dir             ; start < NF (already packed) — still descend dirs
        LDA  PFOUND
        JZ   pf_take
        LDA  STARTHI            ; smaller than the current min? (16-bit)
        LDB  MINSTRTH
        CMP
        JNZ  pf_gmn             ; high bytes differ -> their carry decides
        LDA  STARTLO
        LDB  MINSTRT
        CMP
pf_gmn: JC   pf_dir             ; start >= min -> not smaller, skip
pf_take:LDA  #1
        STA  PFOUND
        LDA  STARTLO
        STA  MINSTRT
        LDA  STARTHI
        STA  MINSTRTH
        JSR  SECCOUNT
        LDA  SECCNT
        STA  MINSEC
        LDA  CANDSEC
        STA  PPSEC
        LDA  CANDSECH
        STA  PPSECH
        LDA  CANDSLOT
        STA  PPSLOT
pf_dir: LDA  FLAGS              ; descend into subdirectories regardless
        LDB  #F_DIR
        CMP
        JNZ  pf_ent
        LDA  TSP
        LDB  #7
        CMP
        JC   pf_ent             ; depth limit
        JSR  TR_PUSH
        LDA  STARTLO
        STA  CDST
        LDA  STARTHI
        STA  CDSTH
        JSR  SECCOUNT
        LDA  SECCNT
        STA  CDSC
        LDA  #0
        STA  CIDX
        JMP  pf_ent
pf_asc: LDA  TSP
        JZ   pf_done
        JSR  TR_POP
        JMP  pf_ent
pf_done:RTS

; PK2MOVE - copy MINSEC sectors from MINSTRT down to NF, then set the parent
; entry (sector PPSEC, slot PPSLOT) start LBA = NF.
PK2MOVE:LDA  MINSTRT            ; src/dst are 16-bit
        STA  SRCL
        LDA  MINSTRTH
        STA  SRCH
        LDA  NF
        STA  DSTL
        LDA  NFH
        STA  DSTH
        LDA  MINSEC
        STA  CPYN
pm2_cp: LDP1 #SBUF
        LDA  SRCL
        STA  LBA
        LDA  SRCH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFREAD
        LDA  DSTL
        STA  LBA
        LDA  DSTH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFWRITE
        LDA  SRCL              ; 16-bit advance source
        INC
        STA  SRCL
        JNZ  pm2_snc
        LDA  SRCH
        INC
        STA  SRCH
pm2_snc:LDA  DSTL              ; 16-bit advance dest
        INC
        STA  DSTL
        JNZ  pm2_dnc
        LDA  DSTH
        INC
        STA  DSTH
pm2_dnc:LDA  CPYN
        DEC
        STA  CPYN
        JNZ  pm2_cp
        LDP1 #SBUF              ; repoint the parent entry's start LBA to NF (16-bit)
        LDA  PPSEC
        STA  LBA
        LDA  PPSECH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFREAD
        LDA  PPSLOT             ; P1 -> entry start field (slot*32 + 12)
        STA  TMP
        LDP1 #SBUF
pm2_sl: LDA  TMP
        JZ   pm2_f
        LDA  #32
        STA  TMP2
pm2_a:  INP1
        LDA  TMP2
        DEC
        STA  TMP2
        JNZ  pm2_a
        LDA  TMP
        DEC
        STA  TMP
        JMP  pm2_sl
pm2_f:  LDA  #12                ; skip name(12) to the start-LBA field
        STA  TMP
pm2_a2: INP1
        LDA  TMP
        DEC
        STA  TMP
        JNZ  pm2_a2
        LDA  NF
        STA  (P1)+
        LDA  NFH
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)
        LDA  PPSEC
        STA  LBA
        LDA  PPSECH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFWRITE
        LDA  #0                 ; restore LBA1=0 at rest
        STA  LBA1
        RTS

; PK2FIX - phase 2: tree-walk; rewrite every directory's '.' (=its own start)
; and '..' (=parent start) from the compacted positions. Fixes root first,
; then each child directory as it is descended into.
PK2FIX: LDA  #33                ; root: '.' and '..' both = 33
        STA  CDST
        STA  PARST
        LDA  #0                 ; root LBA < 256
        STA  CDSTH
        STA  PARSTH
        JSR  PK2DD              ; write CDST's '.'=CDST, '..'=PARST
        LDA  #33
        STA  CDST
        LDA  #0
        STA  CDSTH
        LDA  ROOTN
        STA  CDSC
        LDA  #0
        STA  CIDX
        STA  TSP
fx_ent: LDA  CDSC
        SHL
        SHL
        SHL
        SHL
        STA  TMP
        LDA  CIDX
        LDB  TMP
        CMP
        JC   fx_asc
        JSR  READCUR
        LDA  FLAGS
        JZ   fx_asc
        LDA  CIDX
        INC
        STA  CIDX
        LDA  FLAGS
        LDB  #F_DEL
        CMP
        JZ   fx_ent
        LDA  NAMEBUF
        LDB  #'.'
        CMP
        JZ   fx_ent
        LDA  FLAGS              ; only directories need fixing/descending
        LDB  #F_DIR
        CMP
        JNZ  fx_ent
        LDA  TSP                ; depth limit
        LDB  #7
        CMP
        JC   fx_ent
        ; child dir at STARTLO, parent = CDST. Write its '.'=STARTLO, '..'=CDST.
        LDA  CDST
        STA  PARST              ; parent start (for PK2DD '..'), 16-bit
        LDA  CDSTH
        STA  PARSTH
        JSR  TR_PUSH
        LDA  STARTLO
        STA  CDST
        LDA  STARTHI
        STA  CDSTH
        JSR  SECCOUNT
        LDA  SECCNT
        STA  CDSC
        LDA  #0
        STA  CIDX
        JSR  PK2DD              ; write this dir's '.' = CDST, '..' = PARST
        JMP  fx_ent
fx_asc: LDA  TSP
        JZ   fx_done
        JSR  TR_POP
        JMP  fx_ent
fx_done:RTS

; PK2DD - in the directory whose extent starts at CDST, set entry 0 ('.') start
; = CDST and entry 1 ('..') start = PARST. Reads/writes the first sector.
PK2DD:  LDP1 #SBUF
        LDA  CDST
        STA  LBA
        LDA  CDSTH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFREAD
        LDP1 #SBUF              ; entry 0 start field at offset 12
        LDA  #12
        STA  TMP
dd_a0:  INP1
        LDA  TMP
        DEC
        STA  TMP
        JNZ  dd_a0
        LDA  CDST               ; '.' start = this dir (16-bit)
        STA  (P1)+
        LDA  CDSTH
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)
        LDP1 #SBUF              ; entry 1 start field at offset 32+12 = 44
        LDA  #44
        STA  TMP
dd_a1:  INP1
        LDA  TMP
        DEC
        STA  TMP
        JNZ  dd_a1
        LDA  PARST              ; '..' start = parent (16-bit)
        STA  (P1)+
        LDA  PARSTH
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)
        LDA  CDST
        STA  LBA
        LDA  CDSTH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFWRITE
        LDA  #0                 ; restore LBA1=0 at rest
        STA  LBA1
        RTS

; SAVECORE - allocate + write data + directory entry. Returns MATCH=0 if the
; directory is full (data already written, but no entry made).
SAVECORE:LDP1 #SBUF             ; read boot block -> free pointer
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFREAD
        LDA  SBUF+4
        STA  FREELO
        LDA  SBUF+5
        STA  FREEHI
        LDA  SVSTLO             ; source pointer = start address
        STA  SRCLO
        LDA  SVSTHI
        STA  SRCHI
        LDA  FREELO             ; data LBA starts at the free pointer (16-bit)
        STA  CURLBA
        LDA  FREEHI
        STA  CURLBAH
        LDA  SECCNT
        STA  REM
SV_WL:  LDA  REM
        JZ   SV_WD
        JSR  CPYSEC             ; copy 512 bytes SRC -> SBUF, advance SRC
        LDA  CURLBA
        STA  LBA
        LDA  CURLBAH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFWRITE            ; SBUF -> data sector (16-bit LBA)
        LDA  CURLBA             ; 16-bit advance
        INC
        STA  CURLBA
        JNZ  SV_WNC
        LDA  CURLBAH
        INC
        STA  CURLBAH
SV_WNC: LDA  REM
        DEC
        STA  REM
        JMP  SV_WL
SV_WD:  JSR  FINDSLOT           ; locate a free directory slot (sector in SBUF)
        LDA  MATCH
        JZ   SVC_RET            ; directory full -> MATCH=0, bail
        LDA  #F_FILE            ; SAVE writes a regular-file entry
        STA  EFLAG
        JSR  WRENT              ; build the 32-byte entry in SBUF
        LDA  DLBA               ; persist the directory sector (16-bit)
        STA  LBA
        LDA  DLBAH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFWRITE
        LDP1 #SBUF              ; reload boot block, bump free pointer
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFREAD
        LDA  FREELO
        LDB  SECCNT
        ADD                     ; new free = old free + sectors written
        STA  SBUF+4
        LDA  FREEHI
        JNC  SVC_NC
        INC
SVC_NC: STA  SBUF+5
        LDA  #0
        STA  LBA
        STA  LBA1
        STA  LBA2
        JSR  CFWRITE
        LDA  #1
        STA  MATCH
SVC_RET:RTS

; CPYSEC - copy 512 bytes from SRCLO:SRCHI into SBUF, then save the advanced
; source pointer back (CFWRITE will clobber P1).
CPYSEC: LDA  SRCLO
        TAP1L
        LDA  SRCHI
        TAP1H
        LDP2 #SBUF
        LDA  #0
        STA  TMP
CS1:    LDA  (P1)+
        STA  (P2)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  CS1
        LDA  #0
        STA  TMP
CS2:    LDA  (P1)+
        STA  (P2)+
        LDA  TMP
        INC
        STA  TMP
        JNZ  CS2
        TPA1L
        STA  SRCLO
        TPA1H
        STA  SRCHI
        RTS

; FINDSLOT - scan the directory (SDIRL, SDIRN) for a free entry ($00 end or
; $FF deleted). On success MATCH=1, ENTPL/H -> entry start in SBUF, DLBA = that
; sector, sector left in SBUF. Directory full -> MATCH=0.
FINDSLOT:LDA SDIRL
        STA  DLBA
        LDA  SDIRLH             ; 16-bit directory-sector scan cursor
        STA  DLBAH
        LDA  SDIRN
        STA  SCNT
FS_SEC: LDP1 #SBUF
        LDA  DLBA
        STA  LBA
        LDA  DLBAH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFREAD
        LDP2 #SBUF
        LDA  #16
        STA  ECNT
FS_ENT: TPA2L                   ; remember entry start
        STA  ENTPL
        TPA2H
        STA  ENTPH
        LDA  #24                ; skip name+start+len+load+exec to the flag byte
        STA  TMP
FS_SK:  LDA  (P2)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FS_SK
        LDA  (P2)+              ; flag byte (offset 24)
        STA  FLAGS
        LDA  #7                 ; skip spare -> next entry
        STA  TMP
FS_SP:  LDA  (P2)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  FS_SP
        LDA  FLAGS
        JZ   FS_OK              ; $00 end marker -> free
        LDB  #F_DEL
        CMP
        JZ   FS_OK              ; $FF deleted -> free
        LDA  ECNT
        DEC
        STA  ECNT
        JNZ  FS_ENT
        LDA  DLBA               ; advance the 16-bit scan cursor
        INC
        STA  DLBA
        JNZ  FS_SNC
        LDA  DLBAH
        INC
        STA  DLBAH
FS_SNC: LDA  SCNT
        DEC
        STA  SCNT
        JNZ  FS_SEC
FS_FULL:LDA  #0
        STA  MATCH
        JMP  FS_RST
FS_OK:  LDA  #1
        STA  MATCH
FS_RST: LDA  #0                 ; restore LBA1=0 at rest (see FINDENT/FE_RST);
        STA  LBA1               ; the write-back caller uses DLBAH for the sector
        STA  LBA2
        RTS

; WRENT - write a 32-byte file entry at ENTPL/H (in SBUF): NAMEBUF, start LBA =
; FREELO (4 bytes), length (4), load=exec=SVST (2+2), flag=file, spare zeros.
WRENT:  LDA  ENTPL
        TAP1L
        LDA  ENTPH
        TAP1H
        LDP2 #NAMEBUF           ; name (12)
        LDA  #12
        STA  TMP
WE_NM:  LDA  (P2)+
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  WE_NM
        LDA  FREELO             ; start LBA (4)
        STA  (P1)+
        LDA  FREEHI
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  LENLO              ; length (4)
        STA  (P1)+
        LDA  LENHI
        STA  (P1)+
        LDA  #0
        STA  (P1)+
        STA  (P1)+
        LDA  SVSTLO             ; load (2)
        STA  (P1)+
        LDA  SVSTHI
        STA  (P1)+
        LDA  SVSTLO             ; exec (2) = load
        STA  (P1)+
        LDA  SVSTHI
        STA  (P1)+
        LDA  EFLAG              ; flag (F_FILE for SAVE, F_DIR for MKDIR)
        STA  (P1)+
        LDA  #7                 ; spare (7)
        STA  TMP
WE_SP:  LDA  #0
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  WE_SP
        RTS

; GETHEX - parse a hex number from (P2) into HXLO:HXHI. Skips leading spaces,
; consumes hex digits (0-9 A-F, upcased), stops at the first non-hex char.
; MATCH=1 if at least one digit was read, else MATCH=0.
GETHEX: LDA  #0
        STA  HXLO
        STA  HXHI
        STA  CNT                ; digit count
GH_SK:  LDA  (P2)
        LDB  #' '
        CMP
        JNZ  GH_LP
        INP2
        JMP  GH_SK
GH_LP:  LDA  (P2)
        JSR  HEXVAL             ; -> DIGIT, MATCH
        LDA  MATCH
        JZ   GH_END
        LDA  #4                 ; accumulator <<= 4 (16-bit)
        STA  SHCNT
GH_SHL: LDA  HXLO
        SHL                     ; C = bit7
        STA  HXLO
        LDA  HXHI
        ROL                     ; shift carry in
        STA  HXHI
        LDA  SHCNT
        DEC
        STA  SHCNT
        JNZ  GH_SHL
        LDA  HXLO               ; accumulator |= digit (add, carry to high)
        LDB  DIGIT
        ADD
        STA  HXLO
        LDA  HXHI
        JNC  GH_NC
        INC
GH_NC:  STA  HXHI
        INP2
        LDA  CNT
        INC
        STA  CNT
        JMP  GH_LP
GH_END: LDA  CNT
        JZ   GH_ERR
        LDA  #1
        STA  MATCH
        RTS
GH_ERR: LDA  #0
        STA  MATCH
        RTS

; HEXVAL - A holds a candidate hex char. If valid, DIGIT = 0..15 and MATCH=1;
; else MATCH=0. Upcases first.
HEXVAL: JSR  UPCASE
        STA  TMP
        LDB  #'0'
        CMP                     ; A >= '0' ?
        JNC  HV_BAD
        LDB  #$3A               ; '9' + 1
        CMP                     ; A > '9' ?
        JC   HV_AF
        LDA  TMP                ; digit 0-9
        LDB  #'0'
        SUB
        STA  DIGIT
        LDA  #1
        STA  MATCH
        RTS
HV_AF:  LDA  TMP
        LDB  #'A'
        CMP                     ; A >= 'A' ?
        JNC  HV_BAD
        LDB  #$47               ; 'F' + 1
        CMP                     ; A > 'F' ?
        JC   HV_BAD
        LDA  TMP                ; digit A-F = char - 'A' + 10
        LDB  #'A'
        SUB
        LDB  #10
        ADD
        STA  DIGIT
        LDA  #1
        STA  MATCH
        RTS
HV_BAD: LDA  #0
        STA  MATCH
        RTS

; FINDENT - search the directory (SDIRL, SDIRN) for the entry named in NAMEBUF.
; On a match: MATCH=1, fields filled (incl. FLAGS so the caller knows file vs
; directory), ENTPL/H -> the entry's flag byte in SBUF (sector left in SBUF),
; DLBA = that sector's LBA. Skips deleted slots; stops at the $00 end marker.
; On miss / end-of-directory: MATCH=0.
FINDENT:LDA  SDIRL
        STA  DLBA
        LDA  SDIRLH             ; 16-bit directory-sector scan cursor
        STA  DLBAH
        LDA  SDIRN
        STA  SCNT
FE_SEC: LDP1 #SBUF
        LDA  DLBA
        STA  LBA
        LDA  DLBAH
        STA  LBA1
        LDA  #0
        STA  LBA2
        JSR  CFREAD
        LDP2 #SBUF
        LDA  #16
        STA  ECNT
FE_ENT: LDP1 #NAMEBUF           ; compare 12-byte name
        LDA  #12
        STA  TMP
        LDA  #1
        STA  MATCH
FE_CMP: LDA  (P2)+              ; entry name char (advances P2 through the name)
        STA  TMP2
        LDA  (P1)+              ; search-key char
        LDB  TMP2
        CMP
        JZ   FE_C1
        LDA  #0
        STA  MATCH
FE_C1:  LDA  TMP
        DEC
        STA  TMP
        JNZ  FE_CMP
        LDA  (P2)+              ; bytes 12..15  start LBA (low 16 kept)
        STA  STARTLO
        LDA  (P2)+
        STA  STARTHI
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; bytes 16..19  length (low 16 kept)
        STA  LENLO
        LDA  (P2)+
        STA  LENHI
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; bytes 20..23  load + exec
        STA  LOADLO
        LDA  (P2)+
        STA  LOADHI
        LDA  (P2)+
        STA  EXECLO
        LDA  (P2)+
        STA  EXECHI
        TPA2L                   ; capture &flags (current P2) before reading it
        STA  ENTPL
        TPA2H
        STA  ENTPH
        LDA  (P2)+              ; byte 24  flags
        STA  FLAGS
        LDA  (P2)+              ; bytes 25..31  spare
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  FLAGS
        JZ   FE_NF              ; $00 end marker -> stop, not found
        LDA  MATCH
        JZ   FE_NEXT            ; name mismatch
        LDA  FLAGS              ; matched name; ignore deleted slots
        LDB  #F_DEL
        CMP
        JZ   FE_NEXT
        LDA  #1
        STA  MATCH              ; found (FLAGS = file or dir)
        JMP  FE_RST
FE_NEXT:LDA  ECNT
        DEC
        STA  ECNT
        JNZ  FE_ENT
        LDA  DLBA               ; advance the 16-bit scan cursor
        INC
        STA  DLBA
        JNZ  FE_SNC
        LDA  DLBAH
        INC
        STA  DLBAH
FE_SNC: LDA  SCNT               ; sectors left in this directory extent
        DEC
        STA  SCNT
        JNZ  FE_SEC
FE_NF:  LDA  #0
        STA  MATCH
FE_RST: LDA  #0                 ; restore the "LBA1=0 at rest" invariant for the
        STA  LBA1               ; OS's boot-block/absolute-LBA reads (the scan set
        STA  LBA2               ; LBA1 high; write-back callers use DLBAH instead)
        RTS

; RDENT - read the 32-byte directory entry at (P2)+ for DIR: name -> NAMEBUF,
; low 16 bits of length -> LENLO/HI, flag byte -> FLAGS. (P2)+ only.
RDENT:  LDP1 #NAMEBUF
        LDA  #12
        STA  TMP
RE_NM:  LDA  (P2)+
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  RE_NM
        LDA  (P2)+              ; start LBA (discard 4)
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; length low 16
        STA  LENLO
        LDA  (P2)+
        STA  LENHI
        LDA  (P2)+              ; length high 16 (discard)
        LDA  (P2)+
        LDA  (P2)+              ; load + exec (discard 4)
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+              ; flags
        STA  FLAGS
        LDA  (P2)+              ; spare (discard 7)
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        LDA  (P2)+
        RTS

; ---------------- parsing helpers --------------------------------------------
; PARSEW - copy a word from (P2) into the buffer at (P1), upcased and
; null-terminated. Skips leading spaces; stops at space/null WITHOUT consuming
; the terminator (peek with LDA (P2), advance with INP2).
PARSEW: LDA  (P2)               ; skip leading spaces
        LDB  #' '
        CMP
        JNZ  PW_LP
        INP2
        JMP  PARSEW
PW_LP:  LDA  (P2)
        JZ   PW_END             ; end of line
        LDB  #' '
        CMP
        JZ   PW_END             ; space ends the word
        STA  (P1)               ; case preserved: commands are lowercase and
        INP1                    ; matched case-sensitively (type them lowercase)
        INP2
        JMP  PW_LP
PW_END: LDA  #0
        STA  (P1)
        RTS

; PARSEN - fill NAMEBUF with 12 spaces, then copy up to 12 upcased name chars
; from (P2) (after skipping leading spaces), stopping at space/null.
PARSEN: LDP1 #NAMEBUF
        LDA  #12
        STA  TMP
PN_FZ:  LDA  #' '
        STA  (P1)+
        LDA  TMP
        DEC
        STA  TMP
        JNZ  PN_FZ
        LDP1 #NAMEBUF
PN_SK:  LDA  (P2)               ; skip leading spaces
        LDB  #' '
        CMP
        JNZ  PN_CP
        INP2
        JMP  PN_SK
PN_CP:  LDA  #12                ; copy up to 12 name chars
        STA  CNT
PN_LP:  LDA  (P2)
        JZ   PN_END
        LDB  #' '
        CMP
        JZ   PN_END
        LDA  CNT
        JZ   PN_END             ; 12 chars taken
        LDA  (P2)
        JSR  UPCASE
        STA  (P1)
        INP1
        INP2
        LDA  CNT
        DEC
        STA  CNT
        JMP  PN_LP
PN_END: RTS

; UPCASE - if A is 'a'..'z', clear bit 5 to uppercase it; else leave A.
UPCASE: STA  TMP2
        LDB  #'a'
        CMP                     ; C=1 when A >= 'a'
        JNC  UC_RAW
        LDB  #$7B               ; 'z' + 1
        CMP                     ; C=1 when A > 'z'
        JC   UC_RAW
        LDB  #$DF
        AND
        RTS
UC_RAW: LDA  TMP2
        RTS

; STREQ - compare the null-terminated strings at (P1) and (P2). Sets MATCH=1
; when equal, else 0. Consumes P1/P2.
STREQ:  LDA  (P1)
        STA  TMP2
        LDA  (P2)
        LDB  TMP2
        CMP                     ; A(P2 char) - B(P1 char); Z if equal
        JNZ  SR_NE
        LDA  (P2)               ; chars equal; if both 0 -> strings equal
        JZ   SR_EQ
        INP1
        INP2
        JMP  STREQ
SR_EQ:  LDA  #1
        STA  MATCH
        RTS
SR_NE:  LDA  #0
        STA  MATCH
        RTS

; ---------------- console helpers (built on the BIOS) ------------------------
; GETLN - read a line into LINEBUF until CR, echoing; null-terminate.
GETLN:  LDP2 #LINEBUF
        LDA  SCRIPTM            ; sh: read the next line from the script buffer
        JNZ  GL_SCRIPT
GL1:    JSR  CONIN
        STA  TMP
        LDB  #CR
        CMP
        JZ   GLEND
        LDA  TMP               ; backspace ($08) or DEL ($7F) -> erase last char
        LDB  #$08
        CMP
        JZ   GLBS
        LDA  TMP
        LDB  #$7F
        CMP
        JZ   GLBS
        TPA2L                  ; full? LINEBUF is 64 bytes; cap at 63 (keep a NUL
        LDB  #63               ; slot, and stay clear of CMDBUF at $A040). The line
        CMP                    ; never spans a page, so the low byte is the length.
        JC   GL1               ; C = (len >= 63) -> drop the char, keep reading
        LDA  TMP
        JSR  OUTCH             ; echo (CONOUT preserves A)
        STA  (P2)+
        JMP  GL1
GLBS:   TPA2L                  ; at the start of the line? nothing to erase
        JZ   GL1
        DEP2                   ; drop the last stored char
        LDA  #$08              ; erase it on the terminal: BS, space, BS
        JSR  OUTCH
        LDA  #' '
        JSR  OUTCH
        LDA  #$08
        JSR  OUTCH
        JMP  GL1
GLEND:  JSR  CRLF
        LDA  #0
        STA  (P2)
        RTS

; GL_SCRIPT - GETLN in `sh` mode: read the next line from the OPEN script stream
;   (RESTSCR brings its ROSTATE back, since the previous command clobbered it) into
;   LINEBUF (P2), echoing it; LF ends the line, CR is dropped. Save the stream
;   position for the next line. At EOF, clear SCRIPTM so GETLN reads the console.
GL_SCRIPT:
        JSR  RESTSCR            ; ROSTATE <- script stream (a command clobbered it)
        LDP2 #LINEBUF           ; RESTSCR used P2 — restore the LINEBUF write cursor
GS_LP:  JSR  FGETB
        JC   GS_EOF             ; end of script
        STA  TMP
        LDB  #LF                ; CR or LF ends the line (an editor writes CR; a
        CMP                     ;   CRLF's trailing LF just makes a blank line that
        JZ   GS_DONE            ;   DISPATCH ignores)
        LDB  #CR
        CMP
        JZ   GS_DONE
        TPA2L                  ; cap at 63 like the console reader (LINEBUF is page-
        LDB  #63               ;   aligned, so P2 low = length); full -> drop the char
        CMP                    ;   but keep scanning to end of line
        JC   GS_LP
        LDA  TMP                ; store + echo
        STA  (P2)+
        JSR  OUTCH
        JMP  GS_LP
GS_DONE:LDA  #0
        STA  (P2)               ; NUL-terminate the line
        JSR  CRLF               ; echo the newline after the command
        JSR  SAVESCR            ; remember the position for the next line
        RTS
GS_EOF: LDA  #0                 ; script exhausted -> console next time
        STA  SCRIPTM
        STA  (P2)
        JSR  CRLF
        RTS

; SAVESCR / RESTSCR - copy the BIOS read-stream state (ROSTATE 11 + ROSDRV) to /
;   from SCRSAVE, so a `sh` script survives each command's own read-stream use.
SAVESCR:LDP1 #ROSTAT
        LDP2 #SCRSAVE
        LDA  #11
        STA  SCRCNT
SVS_LP: LDA  (P1)+
        STA  (P2)+
        LDA  SCRCNT
        DEC
        STA  SCRCNT
        JNZ  SVS_LP
        LDA  ROSDRV
        STA  (P2)
        RTS
RESTSCR:LDP1 #SCRSAVE
        LDP2 #ROSTAT
        LDA  #11
        STA  SCRCNT
RSS_LP: LDA  (P1)+
        STA  (P2)+
        LDA  SCRCNT
        DEC
        STA  SCRCNT
        JNZ  RSS_LP
        LDA  (P1)
        STA  ROSDRV
        RTS

CRLF:   LDA  #CR
        JSR  OUTCH
        LDA  #LF
        JSR  OUTCH
        RTS

; ---- output sink -----------------------------------------------------------
; OUTCH: emit A. REDIRF=0 -> console (BIOS CONOUT); REDIRF=1 -> append to the
; capture buffer at RPTR (built-in commands); REDIRF=2 -> stream to the open
; write stream via FPUTB (a redirected RUN program, whose putchar/SYS_PUTC come
; here). Preserves the caller's P1 and P2, clobbers A like CONOUT does.
OUTCH:  STA  RCH
        LDA  REDIRF
        JZ   OUTTTY             ; 0 = console
        LDB  #2
        CMP                     ; C = REDIRF >= 2
        JC   OUTFILE            ; 2 = stream to file
        TPA2L                   ; 1 = capture buffer: save caller P2
        STA  RS2L
        TPA2H
        STA  RS2H
        LDA  RPTRL              ; P2 = capture pointer
        TAP2L
        LDA  RPTRH
        TAP2H
        LDA  RCH
        STA  (P2)+              ; append byte, advance
        TPA2L                   ; write the pointer back
        STA  RPTRL
        TPA2H
        STA  RPTRH
        LDA  RS2L               ; restore caller P2
        TAP2L
        LDA  RS2H
        TAP2H
        RTS
OUTFILE:                        ; REDIRF=2: append RCH to the write stream (FPUTB),
        TPA1L                   ; preserving P1 across the BIOS call (it uses P1)
        PHA
        TPA1H
        PHA
        LDA  RCH
        JSR  FPUTB
        PLA
        TAP1H
        PLA
        TAP1L
        RTS
OUTTTY: LDA  RCH
        JMP  CONOUT             ; tail call: CONOUT RTSs to OUTCH's caller

; OPUTS: print the null-terminated string at (P1) through OUTCH. Uses P1 only
; (OUTCH preserves it), so redirection works for every string the OS prints.
OPUTS:  LDA  (P1)+
        JZ   OPRET
        JSR  OUTCH
        JMP  OPUTS
OPRET:  RTS

; OPHEX8: print A as two uppercase hex digits through OUTCH.
OPHEX8: STA  RHX
        SHR
        SHR
        SHR
        SHR
        JSR  ONIB              ; high nibble
        LDA  RHX
        LDB  #$0F
        AND
        JMP  ONIB             ; low nibble (tail call)
ONIB:   LDB  #10
        CMP                   ; nibble - 10; C=1 when nibble >= 10
        JC   ONHEX
        LDB  #'0'
        ADD
        JMP  OUTCH
ONHEX:  LDB  #$37             ; 'A' - 10
        ADD
        JMP  OUTCH

; ---- "> file" output redirection -------------------------------------------
; REDSCAN: if LINEBUF holds a '>', cut the command there, copy the target name
; to REDNAME, and arm capture (REDIRF=1, RPTR=RBUF). No '>' -> leaves REDIRF 0.
REDSCAN:LDA  #0
        STA  REDAPP            ; default: '>' overwrite (not append)
        LDP1 #LINEBUF
RDS_LP: LDA  (P1)
        JZ   RDS_NO
        LDB  #'>'
        CMP
        JZ   RDS_HIT
        INP1
        JMP  RDS_LP
RDS_HIT:LDA  #0
        STA  (P1)              ; command text ends at the '>'
        INP1
        LDA  (P1)              ; a second '>' -> append mode (>>)
        LDB  #'>'
        CMP
        JNZ  RDS_SK
        LDA  #1
        STA  REDAPP
        INP1                   ; consume the second '>'
RDS_SK: LDA  (P1)              ; skip spaces before the filename
        LDB  #' '
        CMP
        JNZ  RDS_CP
        INP1
        JMP  RDS_SK
RDS_CP: LDP2 #REDNAME
RDS_CL: LDA  (P1)+
        STA  (P2)+
        JNZ  RDS_CL
        LDA  #1
        STA  REDIRF
        LDA  #<RBUF            ; capture pointer = RBUF ($7A00)
        STA  RPTRL
        LDA  #>RBUF
        STA  RPTRH
RDS_NO: RTS

; INSCAN: split off a "< name" stdin redirect. Copies the name to INNAME and
; blanks the '<' + name in LINEBUF (to spaces) so REDSCAN and the command parser
; don't see it. Run BEFORE REDSCAN. No '<' -> INARM stays 0.
INSCAN: LDA  #0
        STA  INARM
        LDP1 #LINEBUF
INS_LP: LDA  (P1)
        JZ   INS_NO
        LDB  #'<'
        CMP
        JZ   INS_HIT
        INP1
        JMP  INS_LP
INS_HIT:LDA  #' '              ; blank the '<'
        STA  (P1)
        INP1
INS_SK: LDA  (P1)              ; skip spaces before the filename
        LDB  #' '
        CMP
        JNZ  INS_CP
        INP1
        JMP  INS_SK
INS_CP: LDP2 #INNAME
INS_CL: LDA  (P1)              ; copy the filename, stopping at a space or NUL
        JZ   INS_END
        LDB  #' '
        CMP
        JZ   INS_END
        STA  (P2)+             ; append to INNAME
        LDA  #' '              ; blank the source byte
        STA  (P1)
        INP1
        JMP  INS_CL
INS_END:LDA  #0
        STA  (P2)              ; NUL-terminate INNAME
        LDA  #1
        STA  INARM
INS_NO: RTS

; CPYPIPE: copy the pipe temp-file name -> (P1) (incl. the NUL).
CPYPIPE:LDP2 #MPIPE
CPP_LP: LDA  (P2)+
        STA  (P1)+
        JNZ  CPP_LP
        RTS

; PIPESCAN: split "cmd1 | cmd2". Save cmd2 to PIPEBUF, truncate LINEBUF at '|',
; and arm cmd1's stdout to PIPE.TMP (REDIRF=1 + REDNAME, like REDSCAN's '>').
; No '|' -> PIPEF stays 0.
PIPESCAN:LDA #0
        STA  PIPEF
        LDP1 #LINEBUF
PPS_LP: LDA  (P1)
        JZ   PPS_NO
        LDB  #'|'
        CMP
        JZ   PPS_HIT
        INP1
        JMP  PPS_LP
PPS_HIT:LDA  #0
        STA  (P1)              ; left command ends at '|'
        INP1
PPS_SK: LDA  (P1)              ; skip spaces before the right command
        LDB  #' '
        CMP
        JNZ  PPS_CP
        INP1
        JMP  PPS_SK
PPS_CP: LDP2 #PIPEBUF          ; save the right command
PPS_CL: LDA  (P1)+
        STA  (P2)+
        JNZ  PPS_CL
        LDP1 #REDNAME          ; arm cmd1's stdout -> PIPE.TMP
        JSR  CPYPIPE
        LDA  #1
        STA  REDIRF
        LDA  #0
        STA  REDAPP            ; cmd1 -> PIPE.TMP is always a fresh overwrite
        LDA  #<RBUF
        STA  RPTRL
        LDA  #>RBUF
        STA  RPTRH
        LDA  #1
        STA  PIPEF
PPS_NO: RTS

; PIPE_RHS: stage 2 — copy the saved right command into LINEBUF, parse a ">out"
; on it, bind its stdin to PIPE.TMP, and re-enter the dispatcher.
PIPE_RHS:LDP1 #PIPEBUF
        LDP2 #LINEBUF
PRH_CP: LDA  (P1)+
        STA  (P2)+
        JNZ  PRH_CP
        JSR  REDSCAN           ; a ">out" on the right command still works
        LDP1 #INNAME           ; stdin <- PIPE.TMP
        JSR  CPYPIPE
        LDA  #1
        STA  INARM
        LDA  #2
        STA  PIPEF
        JMP  DISPATCH

MPIPE:   .asciiz "PIPE.TMP"

; APCOPY - ">>" helper: copy APREM bytes of an existing file (extent starting at
; the 16-bit APLBA) into the currently-open write stream, using RAW sector reads
; (CFREAD into APBUF, then FPUTB) — NOT the BIOS read stream, so a "< name" stdin
; stream can stay open. No FFIND here (the caller resolved the extent before
; FWOPEN; an FFIND now would corrupt the write stream's unflushed SBUF).
APCOPY: LDA  APREM              ; bytes left to copy?
        LDB  APREM+1
        OR
        JZ   APC_RET
        LDA  APLBA              ; read one old sector into APBUF
        STA  LBA
        LDA  APLBA+1
        STA  LBA1
        LDA  #0
        STA  LBA2
        LDP1 #APBUF
        JSR  CFREAD
        LDA  APREM+1            ; chunk = min(512, APREM)
        LDB  #2
        CMP                     ; C=1 when APREM hi >= 2 (i.e. APREM >= 512)
        JNC  APC_PART
        LDA  #0
        STA  APCHK
        LDA  #2
        STA  APCHK+1            ; chunk = 512
        JMP  APC_BYT
APC_PART:LDA APREM
        STA  APCHK
        LDA  APREM+1
        STA  APCHK+1            ; chunk = APREM (< 512)
APC_BYT:LDP2 #APBUF
APC_B1: LDA  APCHK              ; sector chunk emitted?
        LDB  APCHK+1
        OR
        JZ   APC_NXT
        LDA  (P2)+
        JSR  FPUTB
        LDA  APCHK              ; APCHK-- (16-bit)
        JNZ  APC_C1
        LDA  APCHK+1
        DEC
        STA  APCHK+1
APC_C1: LDA  APCHK
        DEC
        STA  APCHK
        LDA  APREM              ; APREM-- (16-bit)
        JNZ  APC_R1
        LDA  APREM+1
        DEC
        STA  APREM+1
APC_R1: LDA  APREM
        DEC
        STA  APREM
        JMP  APC_B1
APC_NXT:LDA  APLBA              ; APLBA++ (16-bit), next sector
        INC
        STA  APLBA
        JNZ  APCOPY
        LDA  APLBA+1
        INC
        STA  APLBA+1
        JMP  APCOPY
APC_RET:RTS

; FLUSHRED: called at the shell prompt. If a redirect was armed, write the
; captured bytes [RBUF, RPTR) to the file REDNAME (via SAVECORE), then disarm.
FLUSHRED:LDA REDIRF
        JZ   FR_RET
        LDA  #0
        STA  REDIRF            ; console again (flush errors print normally)
        LDA  RPTRH             ; nothing captured (RPTR still at RBUF)? -> no file
        LDB  #>RBUF
        CMP
        JNZ  FR_GO
        LDA  RPTRL
        JZ   FR_RET
FR_GO:  LDP2 #REDNAME
        JSR  RESOLVE
        LDA  MATCH
        JZ   FR_ERR
        JSR  FINDENT            ; MATCH=1 if the target already exists
        LDA  REDAPP
        JNZ  FR_APP             ; ">>": append (prepend existing, then captured)
        LDA  MATCH              ; ">": refuse to clobber an existing file
        JNZ  FR_EXIST
        LDA  #<RBUF
        STA  SVSTLO
        LDA  #>RBUF
        STA  SVSTHI
        LDA  RPTRL             ; length = RPTR - RBUF
        STA  LENLO
        LDA  RPTRH
        LDB  #>RBUF
        SUB
        STA  LENHI
        JSR  SECCOUNT
        JSR  SAVECORE
        LDA  MATCH
        JZ   FR_ERR
FR_RET: RTS
; ">>" capture-append: stream the existing file's bytes (if any) then the
; captured [RBUF,RPTR) into a fresh file, registered over the old one by FCLOSE.
FR_APP: LDA  #0
        STA  APHAVE
        LDA  MATCH              ; existing file -> remember its extent to prepend
        JZ   FR_APOP
        LDA  STARTLO
        STA  APLBA
        LDA  STARTHI
        STA  APLBA+1
        LDA  LENLO
        STA  APREM
        LDA  LENHI
        STA  APREM+1
        LDA  #1
        STA  APHAVE
FR_APOP:JSR  SETCWDDIR          ; FCLOSE registers in the CWD
        LDP1 #REDNAME
        JSR  FNORM              ; FNAME = the target (for FCLOSE)
        JSR  FWOPEN
        LDA  APHAVE
        JZ   FR_APC
        JSR  APCOPY             ; prepend the old bytes
FR_APC: LDP2 #RBUF              ; append the captured bytes [RBUF, RPTR)
FR_APL: TPA2H
        LDB  RPTRH
        CMP
        JNZ  FR_APE
        TPA2L
        LDB  RPTRL
        CMP
        JZ   FR_APD             ; reached RPTR -> done
FR_APE: LDA  (P2)+
        JSR  FPUTB
        JMP  FR_APL
FR_APD: JSR  FCLOSE
        JC   FR_ERR
        RTS
FR_ERR: LDP1 #MREDERR
        JSR  PUTS
        JSR  CRLF
        RTS
FR_EXIST:LDP1 #MEXIST
        JSR  PUTS
        JSR  CRLF
        RTS
MREDERR:.asciiz "?REDIRECT"

; ---------------- strings ----------------------------------------------------
MBANNER: .byte CR,LF
         .asciiz "P8X/OS v1.0"
MPROMPT: .asciiz "> "
MNODRV:  .byte CR,LF
         .asciiz "?NO DRIVE"
MHELP:   .byte CR,LF
         .ascii "P8X/OS COMMANDS:"
         .byte CR,LF
         .ascii "cd path       change directory (/abs, rel, .., .)"
         .byte CR,LF
         .ascii "path [dirs]   show/set the program search path (default /bin)"
         .byte CR,LF
         .ascii "mkdir path    create a subdirectory"
         .byte CR,LF
         .ascii "rmdir path    remove an empty subdirectory"
         .byte CR,LF
         .ascii "load path     read a file to its load address"
         .byte CR,LF
         .ascii "run path args load+run a program (args in P2, RTS to exit)"
         .byte CR,LF
         .ascii "name args     run a program by bare name, found on PATH (/bin)"
         .byte CR,LF
         .ascii "save path s e save memory [s,e) to a new file"
         .byte CR,LF
         .ascii "del path      delete a file"
         .byte CR,LF
         .ascii "pack          reclaim deleted space"
         .byte CR,LF
         .ascii "/d1           drive 1 is mounted here (cd /d1, cat /d1/FILE)"
         .byte CR,LF
         .ascii "umount/mount  swap the /d1 card: umount, swap, mount"
         .byte CR,LF
         .ascii "fsck          check filesystem integrity (read-only)"
         .byte CR,LF
         .ascii "format        erase card, make a fresh v2 volume (asks Y/N)"
         .byte CR,LF
         .ascii "help          this help"
         .byte CR,LF
         .ascii "man name      show a command's manual page (/man)"
         .byte CR,LF
         .ascii "sh file       run shell commands from a script file (<=512B)"
         .byte CR,LF
         .ascii "exit / mon    return to the ROM monitor"
         .byte CR,LF
         .ascii "cmd >FILE     send output to FILE instead of the screen"
         .byte CR,LF
         .ascii "cmd <FILE     take input from FILE instead of the keyboard"
         .byte CR,LF
         .ascii "a | b         pipe a's output into b's input"
         .byte CR,LF
         .ascii "programs:     run /bin/basic.bin | edit.bin f | asm.bin s o"
         .byte CR,LF
         .ascii "  path=file/dir (drive 1 at /d1), s e a=hex, b=byte"
         .byte CR,LF,0
MUNK:    .byte CR,LF
         .asciiz "?"
MNOFILE: .byte CR,LF
         .asciiz "?NO FILE"
MLOADED: .byte CR,LF
         .asciiz "LOADED"
MDELETED: .byte CR,LF
         .asciiz "DELETED"
MSAVED:  .byte CR,LF
         .asciiz "SAVED"
MSVERR:  .byte CR,LF
         .asciiz "?SAVE f start end"
MDIRFUL: .byte CR,LF
         .asciiz "?DIR FULL"
MPACKED: .byte CR,LF
         .asciiz "PACKED"
MNODIR:  .byte CR,LF
         .asciiz "?NO DIR"
MMKOK:   .byte CR,LF
         .asciiz "DIR CREATED"
MRMOK:   .byte CR,LF
         .asciiz "DIR REMOVED"
MFMTQ:   .byte CR,LF
         .asciiz "FORMAT: erase card as v2? (Y/N) "
MFMTOK:  .byte CR,LF
         .asciiz "FORMATTED"
MFMTAB:  .byte CR,LF
         .asciiz "ABORTED"
MUMOK:   .byte CR,LF
         .asciiz "DRIVE 1 UNMOUNTED - SWAP THE CARD, THEN MOUNT"
MMNTOK:  .byte CR,LF
         .asciiz "DRIVE 1 MOUNTED AT /d1"
MMNTNO:  .byte CR,LF
         .asciiz "?NO CARD IN DRIVE 1"
MMNTBAD: .byte CR,LF
         .asciiz "?DRIVE 1 NOT P8XFS - FORMAT IT"
MEXIST:  .byte CR,LF
         .asciiz "?EXISTS"
MNOTDIR: .byte CR,LF
         .asciiz "?NOT A DIR"
MNOTMT:  .byte CR,LF
         .asciiz "?DIR NOT EMPTY"
MFKSIG:  .byte CR,LF
         .asciiz "?BAD SIGNATURE"
MFKLOW:  .byte CR,LF
         .asciiz "?EXTENT BELOW DATA LBA "
MFKFRE:  .byte CR,LF
         .asciiz "?FREE PTR BELOW LAST EXTENT"
MFKPAR:  .byte CR,LF
         .asciiz "?BAD PARENT IN DIR LBA "
MFKD:    .byte CR,LF
         .asciiz "DIRS="
MFKF:    .asciiz " FILES="
MFKX:    .asciiz " DEL="
MFKR:    .asciiz " FREE="
MFKU:    .asciiz " USED="
MFKBAD:  .byte CR,LF
         .asciiz "FSCK: PROBLEMS="
MFKOK:   .byte CR,LF
         .asciiz "FSCK OK"

KW_HELP: .asciiz "help"
KW_LOAD: .asciiz "load"
KW_RUN:  .asciiz "run"
KW_DEL:  .asciiz "del"
KW_SAVE: .asciiz "save"
KW_PACK: .asciiz "pack"
KW_CD:   .asciiz "cd"
KW_MKDIR:.asciiz "mkdir"
KW_RMDIR:.asciiz "rmdir"
KW_FSCK: .asciiz "fsck"
KW_PATH: .asciiz "path"
KW_EXIT: .asciiz "exit"
KW_MON:  .asciiz "mon"
KW_FORMAT:.asciiz "format"
KW_MOUNT: .asciiz "mount"
KW_UMOUNT:.asciiz "umount"
KW_SH:   .asciiz "sh"
