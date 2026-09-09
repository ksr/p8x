/* help.c — the shell command reference. Moved OUT of the OS shell into /bin
 * (2026-09-09): it was ~1.4 KB of static text plus a one-line print routine, all
 * of it in the resident OS image for no reason -- it touches no shell state, it
 * just prints. As a /bin program the text lives in the TPA, freeing that ~1.4 KB
 * back to the OS (which had run out of room for the window-manager work).
 *
 * A bare `help` falls through DISPATCH to the implicit-RUN of /BIN/HELP.BIN, so
 * it works exactly as the built-in did. Keep this list in step with the commands
 * the shell and /bin actually provide.
 */
int main() {
    puts("P8X/OS COMMANDS:");
    puts("/d1           drive 1 is mounted here (cd /d1, cat /d1/FILE)");
    puts("bootload file install file as the boot OS, then exit + B to run");
    puts("cd path       change directory (/abs, rel, .., .)");
    puts("del name      delete file(s)");
    puts("exit / mon    return to the ROM monitor");
    puts("format        erase card, make a fresh v2 volume (asks Y/N)");
    puts("fsck          check filesystem integrity (read-only)");
    puts("help          this help");
    puts("load path     read a file to its load address");
    puts("make [target] build a target from the Makefile in the CWD");
    puts("man name      show a command's manual page (/man)");
    puts("graphics      tri/rotate/camera/cube/gl in /bin -- man gl, man basic");
    puts("desk / wdesk  the windowed GUI -- man wdesk");
    puts("mkdir path    create a subdirectory");
    puts("name args     run a program by bare name, found on PATH (/bin)");
    puts("pack          reclaim deleted space");
    puts("path [dirs]   show/set the program search path (default /bin)");
    puts("rmdir path    remove an empty subdirectory");
    puts("run path args load+run a program (args in P2, RTS to exit)");
    puts("save path s e save memory [s,e) to a new file");
    puts("sh file       run shell commands from a script file (streamed)");
    puts("umount/mount  swap the /d1 card: umount, swap, mount");
    puts("cmd >FILE     send output to FILE instead of the screen");
    puts("cmd <FILE     take input from FILE instead of the keyboard");
    puts("a | b         pipe a's output into b's input");
    puts("programs:     run /bin/basic.bin | edit.bin f | asm.bin s o");
    puts("  path=file/dir (drive 1 at /d1), s e a=hex, b=byte");
    return 0;
}
