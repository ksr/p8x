/* grep.c — print stdin lines that contain a (literal) pattern. Unix `grep`,
 * minus regular expressions: the pattern is a plain substring.
 *
 *     RUN /BIN/GREP.BIN foo <FILE   -> lines of FILE containing "foo"
 *     cmd | RUN /BIN/GREP.BIN foo   -> filter a pipe
 *  (and, via implicit RUN + PATH, simply `GREP foo <FILE` or `… | GREP foo`).
 *
 * Reads stdin a line at a time (CR, LF, or CRLF all end a line — so it handles
 * both P8X and host-style text), and prints each line that contains the pattern.
 * The pattern is the first argument word (no spaces). Lines are capped at 127
 * characters; longer lines are truncated for the match.
 *
 * OS: getchar()/SYS_GETC, EOF = 65535. With no `<file`/pipe, stdin is the
 * console and Ctrl-D ends input.
 */
char line[128];                              /* the current input line */

int contains(char *hay, char *needle) {      /* 1 if needle is a substring of hay */
    int i;
    int j;
    i = 0;
    while (hay[i] != 0) {
        j = 0;
        while (needle[j] != 0 && hay[i + j] == needle[j]) { j = j + 1; }
        if (needle[j] == 0) { return 1; }    /* reached needle end -> matched */
        i = i + 1;
    }
    return 0;
}

int main() {
    char *pat;
    char pbuf[64];
    int i;
    int n;
    int c;

    pat = argstr();
    while (*pat == 32) { pat = pat + 1; }
    if (*pat == '-' && (*(pat + 1) == 'h' || *(pat + 1) == 'H')) {
        puts("usage: GREP pattern   print stdin lines containing pattern");
        return 0;
    }
    i = 0;                                    /* copy the first arg word as the pattern */
    while (pat[i] != 0 && pat[i] != 32 && pat[i] != 13 && i < 63) {
        pbuf[i] = pat[i];
        i = i + 1;
    }
    pbuf[i] = 0;

    n = 0;
    c = getchar();
    while (c != 65535) {
        if (c == 10 || c == 13) {             /* end of line */
            line[n] = 0;
            if (n > 0 && contains(line, pbuf)) { puts(line); }
            n = 0;
        } else {
            if (n < 127) { line[n] = c; n = n + 1; }
        }
        c = getchar();
    }
    if (n > 0) {                              /* a final line with no trailing newline */
        line[n] = 0;
        if (contains(line, pbuf)) { puts(line); }
    }
    return 0;
}
