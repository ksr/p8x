/* lib_dirent.c — read the current directory entry through syscalls instead of
 * poking BIOS scratch addresses. Spliced in with `//#use dirent`.
 *
 * A BIOS FNEXT leaves the matched entry's metadata in fixed BIOS scratch RAM
 * (FNAME/$704A, FFLAG/$7070, FLEN/$7058, the start LBA/$7047). Commands used to
 * read those absolute addresses with peek()/poke(), which coupled every command
 * to the firmware's scratch layout — a memory remap had to move ~30 hardcoded
 * sites in lockstep. These helpers go through two OS syscalls instead:
 *
 *   SYS_DIRENTRY ($401B): copy the current entry into a caller buffer.
 *   SYS_OPENDIR  ($401E): begin iterating a subdirectory by its 16-bit LBA.
 *
 * so the firmware can relocate its scratch freely without touching a command.
 *
 * Usage: after each `bios(0x013C, 0, 0)` (FNEXT that returned "not end"), call
 * de_read() once, then query the snapshot:
 *   de_isfile()/de_isdir()/de_isdot(), de_len(), de_lba(), and de[0..11] = name.
 * To descend into a subdirectory found this way: de_opendir(de_lba()), then the
 * usual FSDIRBUF if the command iterates in its own page.
 *
 * de[] layout (17 bytes): [0..11] name (space-padded), [12] flag (1=file 2=dir),
 * [13..14] length lo/hi, [15..16] start-LBA lo/hi.  Within the p8cc subset
 * (no ++/--, decls at top); only the bios() builtin is used.
 */
char de[17];

int de_read() {                       /* snapshot the current entry into de[] */
    bios(0x401B, de, 0);              /* SYS_DIRENTRY -> (P1)=de */
    return 0;
}
int de_isfile() { return (de[12] & 255) == 1; }
int de_isdir()  { return (de[12] & 255) == 2; }
int de_isdot()  { return (de[0]  & 255) == '.'; }   /* '.' or '..' */
int de_len()    { return (de[13] & 255) + (de[14] & 255) * 256; }
int de_lba()    { return (de[15] & 255) + (de[16] & 255) * 256; }

int de_opendir(int lba) {             /* open subdirectory `lba` for FNEXT */
    bios(0x401E, lba, 0);            /* SYS_OPENDIR: P1 = 16-bit start LBA */
    return 0;
}
