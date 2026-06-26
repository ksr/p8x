/* grep.c — print stdin lines matching a basic regular expression. Unix `grep`
 * with a small regex dialect:
 *     .   any single character
 *     *   zero or more of the preceding character (or '.')
 *     ^   anchor to the start of the line   (only special as the first char)
 *     $   anchor to the end of the line     (only special as the last char)
 * everything else is a literal. (No character classes, +, ?, or alternation.)
 *
 *     GREP "^al" FILE        -> lines of FILE starting with "al"
 *     GREP "be.a" <FILE      -> from stdin (a redirect): be<any>a
 *     cmd | GREP "x.*y"      -> filter a pipe
 *
 * Like cat, grep reads a **named file** if a second argument is given, otherwise
 * **stdin** (so `<`/`|` still work). The file is opened the same way cat does:
 * an absolute path (CWD via SYS_GETCWD unless already absolute), FRESOLVE +
 * FOPEN, with the read buffer at $FC00. Reads a line at a time (CR, LF, or CRLF
 * all end a line). The regex is the first argument word (no spaces); lines are
 * capped at 127 characters.
 *
 * The basic-regex matcher (`match`/`matchhere`, the `. * ^ $` dialect) lives in
 * the shared os/commands/lib_regex.c and is spliced in by `//#use regex` below;
 * sed uses the same library. grep filters lines with match() (matches anywhere).
 */
char line[128];                              /* the current input line */

//#use regex   /* match(re,t)/matchhere(re,t): the basic-regex matcher . * ^ $ */
//#use stdin   /* path[80], fromfile, nextc(), openarg() */

int main() {
    char *a;
    char pbuf[64];
    int i;
    int j;
    int n;
    int c;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: GREP regex [file]   match regex (. * ^ $) in file or stdin");
        return 0;
    }
    i = 0;                                    /* the regex = the first arg word */
    while (a[i] != 0 && a[i] != 32 && a[i] != 13 && i < 63) {
        pbuf[i] = a[i];
        i = i + 1;
    }
    pbuf[i] = 0;
    a = a + i;                                /* skip to a possible second word: a file */
    while (*a == 32) { a = a + 1; }

    fromfile = 0;
    j = openarg(a);                           /* open the optional file arg, else stdin */
    if (j == 2) { puts("grep: not found"); return 1; }
    if (j == 1) { fromfile = 1; }

    n = 0;
    c = nextc();
    while (c != 65535) {
        if (c == 10 || c == 13) {             /* end of line */
            line[n] = 0;
            if (n > 0 && match(pbuf, line)) { puts(line); }
            n = 0;
        } else {
            if (n < 127) { line[n] = c; n = n + 1; }
        }
        c = nextc();
    }
    if (n > 0) {                              /* a final line with no trailing newline */
        line[n] = 0;
        if (match(pbuf, line)) { puts(line); }
    }
    return 0;
}
