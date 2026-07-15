/* uniq.c — collapse adjacent duplicate lines (Unix `uniq`).
 *
 *     UNIQ file            file with adjacent dup lines collapsed
 *     SORT f | UNIQ        the usual pairing (uniq only sees *adjacent* dups)
 *
 * Reads a named file (opened like cat) or stdin. Prints a line only when it
 * differs from the previous printed line. Lines capped at 128 chars.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() */
/* Two 260-byte line buffers: `cur` holds the line just read, `prev` holds the
 * previous line read (updated every iteration). rdline caps a line at 128 chars, so 260 bytes is
 * comfortable headroom (data + NUL). Kept as file-scope globals rather than
 * locals to avoid large stack frames on this 8-bit target. */
char cur[260];
char prev[260];

//#use rdline
//#use streq


/* main — read from a named file or stdin, printing each line only when it
 * differs from the previously printed line (adjacent-duplicate collapse).
 * Returns 0 on success, 1 if the named file could not be opened.
 * a=arg pointer, r=openarg result, first=have-we-printed-yet flag, i=copy idx. */
int main() {
    char *a;
    int r;
    int first;
    int i;

    a = argstr();
    /* Skip leading spaces (32 = ASCII space) to reach the first argument. */
    while (*a == 32) { a = a + 1; }
    /* -h / -H prints usage and exits without touching any input. */
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: UNIQ [file]   collapse adjacent duplicate lines");
        return 0;
    }
    /* openarg (from stdin lib) decides the input source:
     *   r==0  empty arg  -> read stdin (fromfile stays 0)
     *   r==1  file opened -> set fromfile so nextc()/readline() pull from it
     *   r==2  named file not found -> error out. */
    fromfile = 0;
    r = openarg(a);
    if (r == 2) { puts("uniq: not found"); return 1; }
    if (r == 1) { fromfile = 1; }

    /* first==1 forces the very first line to print (prev is not yet valid). */
    first = 1;
    while (readline(cur)) {
        /* Print only when this is the first line or it differs from the last
         * line read. streq returns nonzero on equal, so ==0 means differ. */
        if (first || streq(cur, prev) == 0) { puts(cur); }
        /* Copy cur into prev (manual strcpy — remember the line we just saw). */
        i = 0;                                /* prev = cur */
        while (cur[i] != 0) { prev[i] = cur[i]; i = i + 1; }
        prev[i] = 0;
        first = 0;
    }
    return 0;
}
