; cmp.asm — hand-coded CMP command (asm counterpart of os/commands/cmp.c).
;   CMP file1 file2   report the first differing byte (silent if equal).
; Reads file1 into b1 (<= 8 KB), then streams file2 comparing byte for byte,
; tracking a 16-bit offset + line. abspath + openf inline (from diff.asm); the
; 16-bit decimal printer + compares mirror awk.asm. BIOS: FRESOLVE $0133,
; FOPEN $0124, FGETB $0127. OS: SYS_GETCWD $2003, SYS_PUTC $2009, SYS_PUTS $200F.
;#use abi

        .org $6A00
        TPA2L
        STA carg
        TPA2H
        STA carg+1
c_sk:   LDA carg                     ; skip leading spaces
        TAP2L
        LDA carg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ c_chk
        JSR carg_inc
        JMP c_sk
c_chk:  LDA (P2)                     ; empty / CR / -h -> usage
        LDB #0
        CMP
        JZ c_use
        LDB #13
        CMP
        JZ c_use
        LDB #'-'
        CMP
        JNZ c_f1
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ c_use
        LDB #'H'
        CMP
        JZ c_use
c_f1:   JSR set_ap                   ; abspath(path, carg) — file 1
        JSR abspath
        LDA carg                     ; carg += ap_n (past file-1 word)
        LDB ap_n
        ADD
        STA carg
        JNC c_f1s
        LDA carg+1
        INC
        STA carg+1
c_f1s:  LDA carg                     ; skip spaces before file 2
        TAP2L
        LDA carg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ c_op1
        JSR carg_inc
        JMP c_f1s
c_op1:  JSR openf
        LDB #0
        CMP
        JZ c_nf1
        ; ---- slurp file 1 into b1 (cap 8192) ----
        LDA #0
        STA n1                       ; n1 = 16-bit count of bytes read from file1
        STA n1+1
        LDA #<b1                     ; sp = write cursor, starts at buffer b1
        STA sp
        LDA #>b1
        STA sp+1
c_rd1:  LDA #0
        JSR FGETB
        JC c_rd1e
        STA rb
        LDA n1+1                     ; n1 < 8192 ($2000)? store
        LDB #$20
        CMP
        JC c_rd1n                    ; n1.hi >= $20 -> at cap, skip store
        LDA sp
        TAP1L
        LDA sp+1
        TAP1H
        LDA rb
        STA (P1)
        LDA sp                       ; sp++
        LDB #1
        ADD
        STA sp
        JNC c_rd1n
        LDA sp+1
        INC
        STA sp+1
c_rd1n: LDA n1                       ; n1++
        LDB #1
        ADD
        STA n1
        JNC c_rd1
        LDA n1+1
        INC
        STA n1+1
        JMP c_rd1
c_rd1e: LDA n1+1                     ; n1 > 8192 -> too large
        LDB #$20
        CMP
        JNC c_f2                     ; hi < $20 -> ok
        JNZ c_big                   ; hi > $20 -> too large
        LDA n1                       ; hi == $20: any low -> too large
        LDB #0
        CMP
        JNZ c_big
c_f2:   LDA carg                     ; file 2 must be present
        TAP2L
        LDA carg+1
        TAP2H
        LDA (P2)
        LDB #0
        CMP
        JZ c_use2
        LDB #13
        CMP
        JZ c_use2
        JSR set_ap                   ; abspath(path, carg) — file 2
        JSR abspath
        JSR openf
        LDB #0
        CMP
        JZ c_nf2
        ; ---- stream file 2, compare against b1 ----
        LDA #0
        STA off
        STA off+1
        LDA #1
        STA line
        LDA #0
        STA line+1
c_rd2:  LDA #0
        JSR FGETB
        JC c_rd2e
        STA rb                       ; file-2 byte
        ; off >= n1 ? -> file 2 longer -> EOF on file 1
        LDA off+1
        LDB n1+1
        CMP
        JZ c2_lo                     ; hi equal -> compare lo
        JC c_eof1                    ; off.hi > n1.hi
        JMP c_cmp                    ; off.hi < n1.hi -> within
c2_lo:  LDA off
        LDB n1
        CMP
        JC c_eof1                    ; off.lo >= n1.lo (hi equal) -> off >= n1
c_cmp:  JSR b1_ptr                   ; P1 = b1 + off  (carry-correct)
        LDA (P1)
        LDB rb
        CMP
        JNZ c_diff
        LDA (P1)                     ; newline? line++
        LDB #10
        CMP
        JNZ c_noln
        JSR line_inc
c_noln: JSR off_inc
        JMP c_rd2
c_rd2e: ; file 2 ended: off < n1 -> file 1 longer -> EOF on file 2
        LDA off+1
        LDB n1+1
        CMP
        JZ ce_lo
        JC c_eq                      ; off.hi > n1.hi -> off >= n1 -> silent
        JMP c_eof2                   ; off.hi < n1.hi -> off < n1
ce_lo:  LDA off
        LDB n1
        CMP
        JNC c_eof2                   ; off.lo < n1.lo -> off < n1
c_eq:   RTS                          ; identical -> silent
; ---- outcomes ----
c_diff: LDA #<m_diff
        TAP1L
        LDA #>m_diff
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA off                      ; byte = off + 1
        LDB #1
        ADD
        STA dv
        LDA off+1
        JNC c_d1
        INC
c_d1:   STA dv+1
        JSR pnum
        LDA #<m_line
        TAP1L
        LDA #>m_line
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA line
        STA dv
        LDA line+1
        STA dv+1
        JSR pnum
        LDA #10
        JSR SYS_PUTC
        RTS
c_eof1: LDA #<m_eof1
        TAP1L
        LDA #>m_eof1
        TAP1H
        JMP c_pln
c_eof2: LDA #<m_eof2
        TAP1L
        LDA #>m_eof2
        TAP1H
        JMP c_pln
c_nf1:  LDA #<m_nf1
        TAP1L
        LDA #>m_nf1
        TAP1H
        JMP c_pln
c_nf2:  LDA #<m_nf2
        TAP1L
        LDA #>m_nf2
        TAP1H
        JMP c_pln
c_big:  LDA #<m_big
        TAP1L
        LDA #>m_big
        TAP1H
        JMP c_pln
c_use:  LDA #<m_use
        TAP1L
        LDA #>m_use
        TAP1H
        JMP c_pln
c_use2: LDA #<m_use2
        TAP1L
        LDA #>m_use2
        TAP1H
c_pln:  LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; b1_ptr: P1 = b1 + off  (16-bit, carry-correct)
b1_ptr: LDA off
        LDB #<b1
        ADD
        TAP1L
        LDA #0
        JNC bp_nc
        LDA #1
bp_nc:  STA bcar
        LDA off+1
        LDB #>b1
        ADD
        LDB bcar
        ADD
        TAP1H
        RTS

; carg_inc / off_inc / line_inc: 16-bit ++ of the named var, low byte first,
;   carry into the high byte only when the low byte wraps 255->0. No outputs;
;   clobbers A/B. (P8X has no INC-with-carry, hence the JNC/INC hi pattern.)
carg_inc: LDA carg
        LDB #1
        ADD
        STA carg
        JNC ci_r
        LDA carg+1
        INC
        STA carg+1
ci_r:   RTS
off_inc: LDA off
        LDB #1
        ADD
        STA off
        JNC oi_r
        LDA off+1
        INC
        STA off+1
oi_r:   RTS
line_inc: LDA line
        LDB #1
        ADD
        STA line
        JNC li_r
        LDA line+1
        INC
        STA line+1
li_r:   RTS
; set_ap: point abspath at its buffers before each JSR abspath — dest ap_out =
;   the shared 'path' buffer, source ap_a = current carg word. Clobbers A.
set_ap: LDA #<path
        STA ap_out
        LDA #>path
        STA ap_out+1
        LDA carg
        STA ap_a
        LDA carg+1
        STA ap_a+1
        RTS

; openf: FRESOLVE(path)+FOPEN($FC00) -> A = 1 ok / 0 not found
openf:  LDA #<path
        TAP1L
        LDA #>path
        TAP1H
        LDA #0
        JSR FRESOLVE
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR FOPEN
        JC of_no
        LDA #1
        RTS
of_no:  LDA #0
        RTS

; pnum: print the 16-bit value in dv as decimal (no leading zeros). (from awk.asm)
pnum:   LDA #0
        STA pd_any
        LDA #$10
        STA pv
        LDA #$27
        STA pv+1
        JSR pd_dig
        LDA #$E8
        STA pv
        LDA #$03
        STA pv+1
        JSR pd_dig
        LDA #100
        STA pv
        LDA #0
        STA pv+1
        JSR pd_dig
        LDA #10
        STA pv
        LDA #0
        STA pv+1
        JSR pd_dig
        LDA #1
        STA pv
        LDA #0
        STA pv+1
        LDA #1
        STA pd_any
        JSR pd_dig
        RTS
; pd_dig: emit one decimal digit for place value pv by repeated 16-bit subtract
;   of pv from dv (pd_n = quotient). Leading zeros suppressed until pd_any set;
;   the ones place forces pd_any so a value of 0 still prints "0".
pd_dig: LDA #0
        STA pd_n
pd_l:   LDA dv+1
        LDB pv+1
        CMP
        JZ pd_lo
        JC pd_ge
        JMP pd_d
pd_lo:  LDA dv
        LDB pv
        CMP
        JNC pd_d
pd_ge:  LDA dv
        LDB pv
        SUB
        STA dv
        JC pd_nb
        LDA dv+1
        DEC
        STA dv+1
pd_nb:  LDA dv+1
        LDB pv+1
        SUB
        STA dv+1
        LDA pd_n
        INC
        STA pd_n
        JMP pd_l
pd_d:   LDA pd_n
        LDB #0
        CMP
        JNZ pd_pr
        LDA pd_any
        LDB #0
        CMP
        JZ pd_r
pd_pr:  LDA pd_n
        LDB #'0'
        ADD
        JSR SYS_PUTC
        LDA #1
        STA pd_any
pd_r:   RTS

; abspath (ap_a source, ap_out dest); ap_n = chars copied. (from diff.asm)
abspath:LDA #0
        STA ap_n
        LDA ap_a
        TAP2L
        LDA ap_a+1
        TAP2H
        LDA (P2)
        LDB #'/'
        CMP
        JZ ab_abs
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
        LDA #0
        JSR SYS_GETCWD
        LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
ab_sl:  LDA (P1)
        LDB #0
        CMP
        JZ ab_sld
        INP1
        JMP ab_sl
ab_sld: DEP1
        LDA (P1)
        INP1
        LDB #'/'
        CMP
        JZ ab_setp
        LDA #'/'
        STA (P1)+
        JMP ab_setp
ab_abs: LDA ap_out
        TAP1L
        LDA ap_out+1
        TAP1H
ab_setp:LDA ap_a
        TAP2L
        LDA ap_a+1
        TAP2H
ab_cp:  LDA (P2)
        LDB #0
        CMP
        JZ ab_dn
        LDB #13
        CMP
        JZ ab_dn
        LDB #32
        CMP
        JZ ab_dn
        STA (P1)+
        INP2
        LDA ap_n
        INC
        STA ap_n
        JMP ab_cp
ab_dn:  LDA #0
        STA (P1)
        RTS

m_diff: .asciiz "cmp: files differ: byte "
m_line: .asciiz ", line "
m_eof1: .asciiz "cmp: EOF on file1"
m_eof2: .asciiz "cmp: EOF on file2"
m_nf1:  .asciiz "cmp: file1 not found"
m_nf2:  .asciiz "cmp: file2 not found"
m_big:  .asciiz "cmp: file1 too large (max 8K)"
m_use:  .asciiz "usage: CMP file1 file2   report the first differing byte (silent if equal)"
m_use2: .asciiz "usage: CMP file1 file2"

carg:   .fill 2
n1:     .fill 2
off:    .fill 2
line:   .fill 2
sp:     .fill 2
rb:     .fill 1
bcar:   .fill 1
dv:     .fill 2
pv:     .fill 2
pd_n:   .fill 1
pd_any: .fill 1
ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
path:   .fill 80
b1:     .fill 8192

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
; Note the gap: $2015/$2018 are reserved/unused vectors, so the numbering
; jumps from $2012 straight to $201B — keep new syscalls at the +3 stride.
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
; FGETB/FPUTB stream one byte at a time and clobber P1/P2 (they walk the
; sector buffer), so save any live pointer regs around the call.
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
