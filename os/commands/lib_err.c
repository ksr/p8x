/* lib_err.c — eputs(): write an error message to the CONSOLE, never to stdout.
 * Spliced with `//#use err`. The asm twins do the same thing inline: `JSR PUTS`
 * + `JSR CONOUT` instead of `JSR SYS_PUTS` + `JSR SYS_PUTC`.
 *
 * WHY THIS EXISTS. The puts() builtin compiles to SYS_PUTS ($200F) + SYS_PUTC
 * ($2009) — both go to *stdout*, which the shell may have pointed at a file or a
 * pipe. So `cat missing >F` used to put "cat: not found" INSIDE F, and
 * `cat missing | wc` fed the error text to wc as DATA, which counted it and
 * reported a plausible wrong number instead of failing. The OS already avoids
 * this for its own `?...` errors by printing them through the BIOS PUTS (always
 * console) rather than the redirectable sink; this gives /bin commands the same
 * escape hatch, so a diagnostic can never be mistaken for output.
 *
 * The newline goes to CONOUT ($0103), not SYS_PUTC — sending the text to the
 * console but its terminator to a redirect would split the message across two
 * sinks.
 *
 * Convention: use eputs() for anything on a `return 1` (failure) path, including
 * a usage message printed *because the arguments were wrong*. Keep plain puts()
 * for usage that the user explicitly asked for with -h — that is requested
 * output, and `cmd -h >notes.txt` should capture it.
 */
//#use abi     /* PUTS, CONOUT */

int eputs(char *s) {
    bios(PUTS, s, 0);                        /* message -> console, bypassing stdout */
    bios(CONOUT, 0, 10);                     /* its newline must go the same way */
    return 0;
}
