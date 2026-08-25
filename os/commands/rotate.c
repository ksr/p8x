/* rotate.c -- set the scene's rotation and redraw (stage 9c; a GRAPHICS-
 * LANGUAGE emitter since stage 10c, STAGE10-DESIGN.md).
 *
 *     ROTATE [x y z [px py pz]]
 *
 * Angles are DEGREES now (the card's native unit -- brads died with the
 * sine table): 360 is a full turn, 90 a quarter, negative allowed. They
 * apply as yaw (y), then pitch (x), then roll (z), about the pivot
 * point (px py pz; the origin without one). Bare ROTATE resets the
 * rotation. The scene is GL command list 0 -- whatever tri built --
 * and this command just rewrites the card's modeling matrix (MDIDEN,
 * MDORG, MDROT*) and replays the list (CLRUN 0): five small commands,
 * the fabric does everything else. Model scenes near the origin, or
 * hand the pivot their centre, and they turn in place. */
char path[2];

//#use gfx

//#define GLID   0xFF54  /* GL presence probe: 'G' when fitted            */
//#define GLDATA 0xFF50  /* the command FIFO, one byte at a time          */
//#define GLSTAT 0xFF51  /* bit7 FIFO full, bit6 busy                     */
//#define GLERR  0xFF53  /* pop one error byte; 6 = list undefined        */

char *ap;
int anum_ok;

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
    int rx; int ry; int rz; int px; int py; int pz;
    ap = argstr();
    skipsp();
    if (*ap == '-' && (*(ap + 1) == 'h' || *(ap + 1) == 'H')) {
        puts("usage: ROTATE [x y z [px py pz]]  degrees; pivot point");
        return 0;
    }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    if (peek(GLID) != 71) { puts("?No GL engine"); return 1; }
    rx = anum(); ry = anum(); rz = anum();
    px = anum(); py = anum(); pz = anum();
    while (peek(GLERR)) { }              /* drain stale errors */
    glb(144);                            /* MDIDEN */
    glb(145); glw(px); glw(py); glw(pz); /* MDORG (0 0 0 when omitted) */
    glb(148); glw(ry);                   /* MDROTY: yaw...   */
    glb(147); glw(rx);                   /* MDROTX: pitch... */
    glb(149); glw(rz);                   /* MDROTZ: roll     */
    glb(114); glb(0);                    /* CLRUN 0: redraw the scene */
    while (peek(GLSTAT) & 64) { }
    if (peek(GLERR) == 6) { puts("?No scene (tri builds one)"); return 1; }
    return 0;
}
