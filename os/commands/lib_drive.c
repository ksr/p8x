/* lib_drive.c — inline "N:" drive-prefix support for /BIN commands.
 *
 * Spliced in with `//#use drive`. A path argument may carry a leading drive
 * prefix `0:` / `1:` (dual-CF: drive 0 = boot/default, drive 1). These helpers
 * detect it and route the filesystem's sector I/O to that card via the BIOS
 * CFSEL call ($0148); the rest of the path then resolves on that drive (an
 * absolute `N:/dir` walks from that card's root, which lives at the same LBA on
 * both cards). The shell re-asserts the current drive (SYNCDRV) at the start of
 * every command, so a command that routes I/O to the other card does NOT leak
 * the change — the next prompt is back on the current drive.
 *
 * Two BIOS/OS calls: CFSEL=$0148 (A=drive -> route + lazy-init that card),
 * CFCURDRV=$014B (-> A = current drive). Within the p8cc subset (no ++/--).
 */

int hasdrive(char *a) {                  /* 1 if `a` begins with an "N:" prefix */
    return (a[0] == '0' || a[0] == '1') && a[1] == ':';
}

int seldrive(int d) {                    /* route FS sector I/O to drive d (0/1) */
    bios(0x0148, 0, d);                  /* CFSEL */
    return 0;
}

int pdrive(char *a) {                    /* drive named by an "N:" prefix, else current */
    if (hasdrive(a)) { return a[0] - '0'; }
    return bios(0x014B, 0, 0) & 255;     /* CFCURDRV */
}
