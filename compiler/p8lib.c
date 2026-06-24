/* p8lib.c — a tiny C library for the P8X, written in the p8cc subset over the
 * BIOS via the getchar/putchar/puts/peek/poke/bios builtins.
 *
 * This toolchain has no #include and no linker (p8cc compiles one translation
 * unit), so use this library by PREPENDING it to your program:
 *
 *     cat compiler/p8lib.c prog.c > all.c
 *     python3 compiler/p8cc.py all.c -o all.asm      # or: compiler/p8cc-host all.c -o all.asm
 *
 * Caveats (the BIOS reports errors via the carry flag, which bios() does not
 * surface): loadfile/savefile do NOT detect a missing file or a full disk.
 * loadfile reads WHOLE SECTORS, so its destination must be sector-sized
 * (at least ceil(len/512)*512 bytes; a 512-byte buffer covers any file <= 512).
 */

/* ---- strings ----------------------------------------------------------- */
int strlen(char *s) {
    int n;
    n = 0;
    while (*s != 0) { n = n + 1; s = s + 1; }
    return n;
}

int strcpy(char *d, char *s) {
    while (*s != 0) { *d = *s; d = d + 1; s = s + 1; }
    *d = 0;
    return 0;
}

int strcmp(char *a, char *b) {           /* 0 if equal, 1 otherwise */
    while (*a != 0) {
        if (*a != *b) return 1;
        a = a + 1; b = b + 1;
    }
    if (*b != 0) return 1;
    return 0;
}

/* ---- console ----------------------------------------------------------- */
int getline(char *buf, int max) {        /* read a line (until CR/LF); return length */
    int n;
    int c;
    n = 0;
    c = getchar();
    while (c != 13 && c != 10 && c != 0 && n < max - 1) {
        buf[n] = c;
        n = n + 1;
        c = getchar();
    }
    buf[n] = 0;
    return n;
}

int putdec(int v) {                      /* print an unsigned decimal number */
    char tmp[6];
    int n;
    if (v == 0) { putchar(48); return 0; }
    n = 0;
    while (v != 0) { tmp[n] = 48 + (v % 10); n = n + 1; v = v / 10; }
    while (n != 0) { n = n - 1; putchar(tmp[n]); }
    return 0;
}

/* ---- OS syscalls (the OS jump table at $4000; the OS owns CWD) ---------- */
int getcwd(char *buf) { bios(0x4003, buf, 0); return 0; }   /* SYS_GETCWD -> buf */
int cwdlba() { return bios(0x4006, 0, 0) & 255; }           /* SYS_CWDLBA -> LBA */

/* ---- files (over the monitor BIOS jump table) -------------------------- */
/* FNAME=$9D4A, FLEN=$9D58; FNORM=$0136, FFIND=$0118, FLOADAT=$013F,
   FWOPEN=$012A, FPUTB=$012D, FCLOSE=$0130. */

int loadfile(char *name, char *dest) {   /* read a file into dest; return its byte length */
    int len;
    bios(0x0136, name, 0);               /* FNORM:   name -> FNAME            */
    bios(0x0118, 0, 0);                  /* FFIND:   FNAME -> LBA + FLEN      */
    len = peek(0x9D58) + peek(0x9D59) * 256;          /* FLEN (little-endian) */
    bios(0x013F, dest, 0);               /* FLOADAT: FLEN bytes (whole sectors) -> dest */
    return len;
}

int savefile(char *name, char *data, int len) {   /* write data[0..len) as a file */
    int i;
    bios(0x0136, name, 0);               /* FNORM:  name -> FNAME (for FCLOSE) */
    bios(0x012A, 0, 0);                  /* FWOPEN: open the write stream      */
    i = 0;
    while (i < len) {
        bios(0x012D, 0, data[i]);        /* FPUTB:  append one byte            */
        i = i + 1;
    }
    bios(0x0130, 0, 0);                  /* FCLOSE: flush + register FNAME     */
    return len;
}
