/* lib_abi.c — object-like #defines that name the BIOS jump table ($01xx) and the
 * OS syscall vector ($20xx), so a command writes bios(FOPEN, RDBUF, 0) instead of
 * bios(0x0124, 0xFC00, 0). Spliced with `//#use abi`.
 *
 * #define is a compile-time TEXTUAL substitution, so bios()'s "address must be a
 * literal" requirement is still met — and, unlike a wrapper function, it costs
 * ZERO code space. Each address lives here alone; the firmware can renumber its
 * jump table / syscall vector by editing this file (and the asm twin's
 * os/commands-asm/lib_abi.inc) alone.
 *
 * Return convention (unchanged): bios() returns the routine's A in the low byte
 * with the carry flag in bit 8, so callers keep their `& 256` tests:
 *     if (bios(FOPEN, RDBUF, 0) & 256) ...        // carry = not found
 *     c = bios(FGETB, 0, 0); while ((c & 256)==0) // carry = end of file
 */

/* OS syscalls ($20xx). Reached via bios(); several take a pointer arg in P1 and
 * clobber P1/P2 per the ISA syscall convention. Carry (bit 8 of bios()'s return)
 * signals failure where noted below. */
//#define SYS_GETCWD   0x2003    /* copy CWD path -> (P1), incl NUL */
//#define SYS_CWDLBA   0x2006    /* CWD dir start LBA -> A */
//#define SYS_OPENCWD  0x2012    /* begin iterating the CWD (16-bit LBA) */
//#define SYS_DIRENTRY 0x201B    /* snapshot current dir entry -> (P1) */
//#define SYS_OPENDIR  0x201E    /* P1 = 16-bit dir LBA -> open for FNEXT */
//#define SYS_MKDIR    0x2021    /* P1 = path -> mkdir; C=1 on real failure */

/* BIOS jump table ($01xx): low-level console + file-stream primitives. The read
 * (FOPEN/FGETB) and write (FWOPEN/FPUTB/FCLOSE) streams are separate single-file
 * pipes; FRESOLVE/FOPENDIR/FNEXT handle path lookup and directory walking. */
//#define CONIN        0x0100    /* wait for key -> A (raw console) */
//#define CONOUT       0x0103    /* A -> serial (raw console) */
//#define CONST        0x0106    /* console status: A = key-waiting (no wait) */
//#define FDELETE      0x011E    /* tombstone file FNAME; C=1 not found */
//#define FOPEN        0x0124    /* open file FNAME for read (P1=buf); C=1 missing */
//#define FGETB        0x0127    /* next byte -> A; C=1 at EOF */
//#define FWOPEN       0x012A    /* open write stream at the free pointer */
//#define FPUTB        0x012D    /* append byte A to the write stream */
//#define FCLOSE       0x0130    /* flush + register file; C=1 full */
//#define FRESOLVE     0x0133    /* resolve path (P1) -> dir + leaf FNAME; C=1 bad */
//#define FOPENDIR     0x0139    /* begin iterating directory at path (P1); C=1 bad */
//#define FNEXT        0x013C    /* next live entry; C=1 at end */
//#define FSDIRBUF     0x0145    /* point FNEXT's buffer at page A */
/* PUTS is the RAW CONSOLE string printer, and is NOT the puts() builtin: puts()
 * compiles to SYS_PUTS/SYS_PUTC, i.e. stdout, which the shell may have pointed at
 * a file or a pipe. PUTS always reaches the screen — it is what the OS's own
 * `?...` errors use, and what eputs() (//#use err) is built from. */
//#define PUTS         0x0112    /* print (P1)+ until NUL -> raw console */

/* the shared 512-byte page-aligned read buffer FOPEN/FGETB stream through */
//#define RDBUF        0xFC00
