/* cp.c — copy a file: CP SRC DST  (Unix `cp`).
 *
 *     RUN /BIN/CP.BIN OLD.TXT NEW.TXT
 *  (and, via implicit RUN + PATH, simply `CP OLD.TXT NEW.TXT`).
 *
 * Reads SRC through the BIOS read stream (FOPEN/FGETB, its own 512-byte buffer
 * ROBUF) and writes DST through the write stream (FWOPEN/FPUTB/FCLOSE). The two
 * streams use independent buffers, so the byte-copy loop interleaves them
 * freely. Both paths are made absolute (CWD via SYS_GETCWD unless already
 * absolute) and resolved with FRESOLVE so they land relative to the shell's CWD.
 *
 * SBUF ordering matters: FRESOLVE and FOPEN both transit the BIOS sector buffer
 * SBUF, and so does the write stream. So we (1) open SRC, then (2) FRESOLVE DST
 * to set the directory + leaf name for FCLOSE, then (3) FWOPEN — which reads the
 * boot block and *zeroes* SBUF last — so nothing reads into SBUF again until the
 * FPUTB loop owns it. FCLOSE then commits DST in the resolved directory.
 *
 * BIOS: FRESOLVE=$0133 (P1=path -> DIRLBA+FNAME), FOPEN=$0124 (P1=buffer; C=1
 * not found), FGETB=$0127 (->A, C=1 EOF), FWOPEN=$012A, FPUTB=$012D (A=byte),
 * FCLOSE=$0130 (registers FNAME in DIRLBA).  OS: SYS_GETCWD=$4003.
 *
 * Read-stream buffer: the fixed page-aligned scratch at $E000 (clear of our
 * code/globals at $B000 and the stack at $FEFF). p8cc has no preprocessor.
 */
char src[80];
char dst[80];

/* abspath(out, arg): copy the next whitespace-delimited word of *argp into out
 * as an absolute path (prefixing the CWD when it isn't already absolute), and
 * advance *argp past it. Returns 1 if a word was present, 0 if none. */
int abspath(char *out, char *a) {
    int i;
    int j;
    i = 0;
    if (*a != '/') {                          /* relative -> prefix the CWD */
        bios(0x4003, out, 0);                 /* SYS_GETCWD -> out */
        while (out[i] != 0) { i = i + 1; }
        if (i > 0 && out[i - 1] != '/') { out[i] = '/'; i = i + 1; }
    }
    j = 0;
    while (a[j] != 0 && a[j] != 13 && a[j] != 32) {
        out[i] = a[j]; i = i + 1; j = j + 1;
    }
    out[i] = 0;
    return j;                                 /* number of chars consumed */
}

int main() {
    char *a;
    int n;
    int c;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: CP src dst   copy a file");
        return 0;
    }
    n = abspath(src, a);                      /* SRC word */
    if (n == 0) { puts("usage: CP src dst"); return 1; }
    a = a + n;
    while (*a == 32) { a = a + 1; }            /* DST word */
    if (*a == 0 || *a == 13) { puts("usage: CP src dst"); return 1; }
    abspath(dst, a);

    bios(0x0133, src, 0);                      /* FRESOLVE SRC */
    if (bios(0x0124, 0xE000, 0) & 256) {       /* FOPEN SRC; C=1 -> not found */
        puts("cp: source not found");
        return 1;
    }
    bios(0x0133, dst, 0);                      /* FRESOLVE DST (sets DIRLBA+FNAME) */
    bios(0x012A, 0, 0);                        /* FWOPEN (zeroes SBUF last) */
    c = bios(0x0127, 0, 0);                    /* FGETB */
    while ((c & 256) == 0) {                   /* until EOF */
        bios(0x012D, 0, c & 255);              /* FPUTB */
        c = bios(0x0127, 0, 0);
    }
    bios(0x0130, 0, 0);                        /* FCLOSE -> commit DST */
    return 0;
}
