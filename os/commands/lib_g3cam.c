/* lib_g3cam.c -- the look-at camera (stage 9d). Spliced with `//#use
 * g3cam`, AFTER `//#use gfx` and `//#use g3d` (it builds on g3probe/
 * the muldiv/m3mul machinery). Split from lib_g3d so the
 * ~6K of square-root and basis math is paid for ONLY by camera-using
 * programs -- folding it into the shared lib pushed every g3d client
 * past the 64K address space. */

/* ---- 32-bit square root + the look-at camera (stage 9d) -----------------
 * isqrt of a 32-bit value (hi:lo, unsigned) -> 16-bit root, by the classic
 * try-a-bit method: each candidate is squared with m3mul and compared
 * against N in 32 bits. ~15 slow multiplies -- tenths of a second on
 * target -- fine for a per-COMMAND tool, not for per-frame work. */
int q3hi; int q3lo;                   /* isqrt's N (hi:lo), consumed */

/* accumulate a*a into q3hi:q3lo (unsigned 32-bit add). m3mul is
 * UNSIGNED, so square the MAGNITUDE -- a negative component squared as
 * its two's-complement bit pattern wrecked every off-axis length (the
 * identity view passed only because its vectors had no negatives). */
int s3acc(int a) {
    int t;
    if (a & 32768) { a = 0 - a; }
    m3mul(a, a);
    t = q3lo + m3lo;
    if (t < q3lo) { q3hi = q3hi + 1; }
    q3lo = t;
    q3hi = q3hi + m3hi;
    return 0;
}

/* isqrt(q3hi:q3lo) -> the largest r with r*r <= N. Coordinate budget
 * (+/-16383 per component) keeps every root under 28378, so bit 14 down
 * to bit 0 covers the range. */
int i3sqrt() {
    int r; int b; int t;
    r = 0;
    b = 16384;
    while (b) {
        t = r + b;
        m3mul(t, t);
        if (m3hi < q3hi) { r = t; }
        else { if (m3hi == q3hi) { if ((m3lo > q3lo) == 0) { r = t; } } }
        b = b >> 1;
    }
    return r;
}

/* normalize v[3] (any scale) to 8.8 length 256, in place. Zero vectors
 * are left zero and reported. */
int n3orm(int *v) {
    int m;
    q3hi = 0; q3lo = 0;
    s3acc(v[0]); s3acc(v[1]); s3acc(v[2]);
    m = i3sqrt();
    if (m == 0) { return 0; }
    v[0] = muldiv(v[0], 256, m);
    v[1] = muldiv(v[1], 256, m);
    v[2] = muldiv(v[2], 256, m);
    return 1;
}

int c3f[3]; int c3r[3]; int c3u[3];   /* the look-at basis (8.8) */

/* cross of two 8.8 vectors -> 8.8 (terms via muldiv's 32-bit product) */
int c3ross(int *a, int *b, int *o) {
    o[0] = muldiv(a[1], b[2], 256) - muldiv(a[2], b[1], 256);
    o[1] = muldiv(a[2], b[0], 256) - muldiv(a[0], b[2], 256);
    o[2] = muldiv(a[0], b[1], 256) - muldiv(a[1], b[0], 256);
    return 0;
}

/* g3cam(p): p = int[6] = eye x,y,z then aim x,y,z (world units, each
 * within +/-16383). Look-at view: forward = aim-eye, right = worldUp x
 * forward, up = forward x right, all normalized to 8.8; matrix rows
 * [right; up; forward] -> params 0-8, T = -M*eye -> 9-11, so
 * v' = M*(v - eye): the camera sits at the eye looking at the aim,
 * world +y up. Aiming straight up/down degenerates the basis: the right
 * vector falls back to world +x. Engine-only; 0 when absent or when
 * aim == eye. */
int g3bas(int *p, int *m) {
    int i;
    c3f[0] = p[3] - p[0];
    c3f[1] = p[4] - p[1];
    c3f[2] = p[5] - p[2];
    if (n3orm(c3f) == 0) { return 0; }
    c3u[0] = 0; c3u[1] = 256; c3u[2] = 0;
    c3ross(c3u, c3f, c3r);
    if (n3orm(c3r) == 0) {
        c3r[0] = 256; c3r[1] = 0; c3r[2] = 0;
    }
    c3ross(c3f, c3r, c3u);
    n3orm(c3u);
    i = 0;
    while (i < 3) {
        m[i] = c3r[i];
        m[3 + i] = c3u[i];
        m[6 + i] = c3f[i];
        i = i + 1;
    }
    return 1;
}
