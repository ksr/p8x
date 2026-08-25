/* camera.c -- place the camera and redraw the scene (stage 9d; a GRAPHICS-
 * LANGUAGE emitter since stage 10c, STAGE10-DESIGN.md).
 *
 *     CAMERA                       back to the origin, looking down +z
 *     CAMERA ex ey ez ax ay az     camera AT the eye point, LOOKING AT
 *                                  the aim point (world units, +/-16383)
 *
 * The look-at basis (lib_g3cam's g3bas: forward = aim-eye, right =
 * up x forward, true up = forward x right, all normalized 8.8) goes to
 * the card as its VIEWING matrix (VWMATX), the eye as the viewing
 * reference point (VWRPT) -- the card's own recompose then applies
 * exactly the old -M*eye translation -- and the scene (GL command
 * list 0, whatever tri built) replays from the new viewpoint: same
 * scene, any eye. World +y is up; aiming straight up or down keeps a
 * sane (fallback) horizon. The focal length is whatever the frame set
 * (256 native). Needs the GL engine. */
char path[2];

//#use gfx
//#use g3d
//#use g3cam

//#define GLID   0xFF54  /* GL presence probe: 'G' when fitted            */
//#define GLDATA 0xFF50  /* the command FIFO, one byte at a time          */
//#define GLSTAT 0xFF51  /* bit7 FIFO full, bit6 busy                     */
//#define GLERR  0xFF53  /* pop one error byte; 6 = list undefined        */

char *ap;
int anum_ok;
int cp[6];
int m9[9];

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

int glb(int v) {
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}
int glw(int v) { glb(v & 255); glb(v >> 8); return 0; }

int main() {
    int i;
    ap = argstr();
    skipsp();
    if (*ap == '-' && (*(ap + 1) == 'h' || *(ap + 1) == 'H')) {
        puts("usage: CAMERA [ex ey ez ax ay az]   eye point, aim point; none = origin");
        return 0;
    }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    if (peek(GLID) != 71) { puts("?No GL engine"); return 1; }
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
        if (g3bas(cp, m9) == 0) { puts("?Bad camera (aim = eye)"); return 1; }
        while (peek(GLERR)) { }          /* drain stale errors */
        glb(167);                        /* VWMATX: the look-at rows */
        i = 0;
        while (i < 9) { glw(m9[i]); i = i + 1; }
        glb(161); glw(cp[0]); glw(cp[1]); glw(cp[2]);   /* VWRPT = eye */
        glb(177); glw(0);                                /* DISTAN 0 */
    } else {
        while (peek(GLERR)) { }
        glb(160);                        /* VWIDEN: home */
        glb(161); glw(0); glw(0); glw(0);
        glb(177); glw(0);
    }
    glb(114); glb(0);                    /* CLRUN 0: redraw the scene */
    while (peek(GLSTAT) & 64) { }
    if (peek(GLERR) == 6) { puts("?No scene (tri builds one)"); return 1; }
    return 0;
}
