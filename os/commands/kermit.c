/* kermit.c -- Kermit-style file transfer over the SECOND serial port (two-mode
 * P5, the port from P3 at $FF08/$FF09). Moves a file between the P8X and whatever
 * is on the other end of the 2nd ACIA (a host running a matching peer; in the
 * emulator the port is file-backed with -2i/-2o, which also makes a round-trip
 * testable).
 *
 *     kermit send /FILE     frame /FILE into packets and send them out port 2
 *     kermit recv /FILE     read packets from port 2 and write them to /FILE
 *
 * The framing is a minimal Kermit-style block protocol (not the full ACK/NAK
 * Kermit -- a fire-and-forward stream): each packet is
 *
 *     SEQ  LEN  data[LEN]  CHK        (CHK = sum of the data bytes, & 255)
 *
 * and a LEN=0 packet marks end of file. The 2nd ACIA is polled directly: status
 * $FF08 bit0 = RDRF (a byte waiting), bit1 = TDRE (ready to send); data $FF09.
 * This is the payoff for the 2nd serial port -- the Term app can launch it for a
 * transfer while the console stays on port 1.
 */

//#use abi     /* FOPEN/FGETB/FWOPEN/FPUTB/FCLOSE/FRESOLVE/FDELETE, RDBUF, argstr */

//#define A2S 0xFF08   /* 2nd ACIA status: bit0 RDRF, bit1 TDRE */
//#define A2D 0xFF09   /* 2nd ACIA data */

char path[64];
char blk[64];

int a2put(int c) { while ((peek(A2S) & 2) == 0) { } poke(A2D, c & 255); return 0; }
int a2get() { while ((peek(A2S) & 1) == 0) { } return peek(A2D); }

/* send: file -> framed packets out port 2 */
int ksend() {
    int seq; int eof; int n; int chk; int i; int r;
    bios(FRESOLVE, path, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { puts("?No file"); return 1; }
    seq = 0; eof = 0;
    while (eof == 0) {
        n = 0; chk = 0;
        while (n < 64 && eof == 0) {
            r = bios(FGETB, 0, 0);
            if (r & 256) { eof = 1; }
            else { blk[n] = r & 255; chk = (chk + (r & 255)) & 255; n = n + 1; }
        }
        if (n > 0) {
            a2put(seq); a2put(n);
            i = 0; while (i < n) { a2put(blk[i]); i = i + 1; }
            a2put(chk);
            seq = (seq + 1) & 255;
        }
    }
    a2put(seq); a2put(0); a2put(0);            /* EOF packet: LEN=0 */
    puts("kermit: sent");
    return 0;
}

/* recv: framed packets from port 2 -> file (stops at the LEN=0 packet) */
int krecv() {
    int done; int seq; int n; int chk; int i; int c; int rc; int bad;
    bios(FRESOLVE, path, 0);
    bios(FDELETE, path, 0);
    bios(FRESOLVE, path, 0);
    bios(FWOPEN, 0, 0);
    done = 0; bad = 0;
    while (done == 0) {
        seq = a2get();
        n = a2get();
        if (n == 0) { rc = a2get(); done = 1; }    /* EOF: consume its CHK */
        else {
            chk = 0; i = 0;
            while (i < n) { c = a2get(); bios(FPUTB, 0, c); chk = (chk + c) & 255; i = i + 1; }
            rc = a2get();
            if (rc != chk) { bad = 1; }
        }
    }
    bios(FCLOSE, 0, 0);
    if (bad) { puts("?checksum"); return 1; }
    puts("kermit: received");
    return 0;
}

int main() {
    char *a; int i; int verb;
    a = argstr();
    while (*a == 32) { a = a + 1; }
    verb = *a;
    if (verb != 's' && verb != 'S' && verb != 'r' && verb != 'R') {
        puts("usage: kermit send|recv /path"); return 1;
    }
    while (*a != 32 && *a != 0 && *a != 13) { a = a + 1; }   /* past the verb */
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13) { puts("usage: kermit send|recv /path"); return 1; }
    i = 0;
    while (a[i] != 0 && a[i] != 13 && a[i] != 32 && i < 60) { path[i] = a[i]; i = i + 1; }
    path[i] = 0;
    if (verb == 's' || verb == 'S') { return ksend(); }
    return krecv();
}
