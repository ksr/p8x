/* sort.c — sort lines (Unix `sort`, ASCII ascending).
 *
 *     SORT file            file's lines in ascending order
 *     cmd | SORT           sort a pipe
 *
 * Reads a named file (opened like cat) or stdin into memory, sorts the lines
 * ascending by byte value, and prints them. Holds up to 96 lines of up to 63
 * chars (longer lines truncated, extra lines dropped with a note on stderr-ish
 * console). Insertion sort over an index array.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() */
char lines[6144];                            /* 96 slots x 64 bytes */
int nline;

/* lless: 1 if line x sorts before line y (ascending, unsigned bytes). Returns a
 * boolean rather than -1/0/1 because p8cc's `<` is an UNSIGNED compare, so a
 * negative sentinel tested with `< 0` would never be true. The `a < b` here is
 * safe — both are masked byte values (0..255). */
int lless(int x, int y) {
    int i;
    int a;
    int b;
    i = 0;
    while (1) {
        a = lines[x * 64 + i] & 255;
        b = lines[y * 64 + i] & 255;
        if (a != b) { if (a < b) { return 1; } return 0; }
        if (a == 0) { return 0; }             /* equal -> not "less" */
        i = i + 1;
    }
}

int main() {
    char *arg;
    int r;
    int c;
    int col;
    int i;
    int j;
    int k;
    int min;
    int t;

    arg = argstr();
    while (*arg == 32) { arg = arg + 1; }
    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: SORT [file]   sort lines ascending (file or stdin)");
        return 0;
    }
    fromfile = 0;
    r = openarg(arg);
    if (r == 2) { puts("sort: not found"); return 1; }
    if (r == 1) { fromfile = 1; }

    nline = 0;                                /* read lines into the flat buffer */
    col = 0;
    c = nextc();
    while (c != 65535 && nline < 96) {        /* stop at buffer full (96 lines) */
        if (c == 10) {
            lines[nline * 64 + col] = 0;
            nline = nline + 1;
            col = 0;
        } else {
            if (c != 13 && col < 63) { lines[nline * 64 + col] = c; col = col + 1; }
        }
        c = nextc();
    }
    if (col > 0 && nline < 96) {              /* a final line with no trailing LF */
        lines[nline * 64 + col] = 0;
        nline = nline + 1;
    }

    i = 0;                                     /* in-place selection sort of slots */
    while (i < nline - 1) {                    /* (avoids an int index array) */
        min = i;
        j = i + 1;
        while (j < nline) {
            if (lless(j, min)) { min = j; }
            j = j + 1;
        }
        if (min != i) {                        /* swap the two 64-byte slots */
            k = 0;
            while (k < 64) {
                t = lines[i * 64 + k];
                lines[i * 64 + k] = lines[min * 64 + k];
                lines[min * 64 + k] = t;
                k = k + 1;
            }
        }
        i = i + 1;
    }

    i = 0;                                      /* print slots in order */
    while (i < nline) {
        col = i * 64;
        j = 0;
        while (lines[col + j] != 0) { putchar(lines[col + j]); j = j + 1; }
        putchar(10);
        i = i + 1;
    }
    return 0;
}
