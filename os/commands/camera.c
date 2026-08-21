/* camera.c -- place the camera and redraw the scene (stage 9d).
 *
 *     CAMERA                       back to the origin, looking down +z
 *     CAMERA ex ey ez ax ay az     camera AT the eye point, LOOKING AT
 *                                  the aim point (world units, +/-16383)
 *
 * The g3cam look-at (man g3d): the view matrix and translation land in
 * the geometry engine's parameters and the PERSISTED scene redraws from
 * the new viewpoint -- so tri-built worlds and cube's aftermath can be
 * walked around: same scene, any eye. World +y is up; aiming straight
 * up or down keeps a sane (fallback) horizon. The focal length is
 * whatever the scene set (256 by default). Needs the engine. */
char path[2];

//#use gfx
//#use g3d
//#use g3cam

char *ap;
int anum_ok;
int cp[6];

int skipsp() {
    while (*ap == 32) { ap = ap + 1; }
    return 0;
}

int anum() {
    int v; int neg;
    skipsp();
    neg = 0; anum_ok = 0;
    if (*ap == '-') { neg = 1; ap = ap + 1; }
    v = 0;
    while (*ap >= '0' && *ap <= '9') {
        v = v * 10 + (*ap - '0');
        ap = ap + 1;
        anum_ok = 1;
    }
    if (neg) { return 0 - v; }
    return v;
}

int main() {
    int i;
    ap = argstr();
    skipsp();
    if (*ap == '-' && (*(ap + 1) == 'h' || *(ap + 1) == 'H')) {
        puts("usage: CAMERA [ex ey ez ax ay az]   eye point, aim point; none = origin");
        return 0;
    }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    if (g3probe() == 0) { puts("?No engine"); return 1; }
    i = anum();
    if (anum_ok) {
        cp[0] = i;
        i = 1;
        while (i < 6) {
            cp[i] = anum();
            if (anum_ok == 0) {
                puts("usage: CAMERA [ex ey ez ax ay az]   eye point, aim point");
                return 1;
            }
            i = i + 1;
        }
        if (g3cam(cp) == 0) { puts("?Bad camera (aim = eye)"); return 1; }
    } else {
        i = 0;                        /* identity view: origin, +z */
        while (i < 12) {
            skipsp();                 /* (no args to consume) */
            if (i == 0 || i == 4 || i == 8) { g3par(i, 256); }
            else { g3par(i, 0); }
            i = i + 1;
        }
    }
    g3par(21, 1);                     /* erase, no flip */
    poke(GECMD, 2);                   /* RENDER the persisted scene */
    while (peek(GESTAT) & 128) { }
    return 0;
}
