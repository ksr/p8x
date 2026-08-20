/* rotate.c -- set the scene's rotation and redraw (stage 9c).
 *
 *     ROTATE                     identity rotation, translation kept; redraw
 *     ROTATE x y z               rotate the MODEL about its own origin
 *                                (translation kept -- cube-style scenes)
 *     ROTATE x y z px py pz      rotate the SCENE about the PIVOT point
 *                                (translation rewritten: T = P - R*P --
 *                                tri-style scenes with z in the vertices)
 *
 * Angles are BRADS (256 = a full turn, 64 = 90 degrees), applied as Ry
 * (yaw), then Rx (pitch), then Rz (roll). The geometry engine's record
 * list survives in SDRAM between commands -- it IS the scene (build one
 * with tri/tri k, or run cube and rotate its aftermath). The pivot is
 * what makes rotation feel right: scenes live at z of a few hundred, and
 * spinning them about the ORIGIN swings them out of the window -- give
 * the scene's own centre (e.g. 0 0 400) and it turns in place. This is
 * the whole transform: matrix = R, translation = P - R*P (both written;
 * a prior translation is replaced). Composed with muldiv; the sine table
 * is cube's. Needs the engine. */
char path[2];

//#use gfx
//#use g3d

char s3tab[256] = {
    128, 131, 134, 137, 140, 143, 146, 149, 151, 154, 157, 160, 163, 166, 168, 171,
    174, 177, 179, 182, 185, 187, 190, 192, 195, 197, 199, 202, 204, 206, 209, 211,
    213, 215, 217, 219, 221, 223, 224, 226, 228, 229, 231, 232, 234, 235, 236, 238,
    239, 240, 241, 242, 243, 244, 244, 245, 246, 246, 247, 247, 247, 248, 248, 248,
    248, 248, 248, 248, 247, 247, 247, 246, 246, 245, 244, 244, 243, 242, 241, 240,
    239, 238, 236, 235, 234, 232, 231, 229, 228, 226, 224, 223, 221, 219, 217, 215,
    213, 211, 209, 206, 204, 202, 199, 197, 195, 192, 190, 187, 185, 182, 179, 177,
    174, 171, 168, 166, 163, 160, 157, 154, 151, 149, 146, 143, 140, 137, 134, 131,
    128, 125, 122, 119, 116, 113, 110, 107, 105, 102, 99, 96, 93, 90, 88, 85,
    82, 79, 77, 74, 71, 69, 66, 64, 61, 59, 57, 54, 52, 50, 47, 45,
    43, 41, 39, 37, 35, 33, 32, 30, 28, 27, 25, 24, 22, 21, 20, 18,
    17, 16, 15, 14, 13, 12, 12, 11, 10, 10, 9, 9, 9, 8, 8, 8,
    8, 8, 8, 8, 9, 9, 9, 10, 10, 11, 12, 12, 13, 14, 15, 16,
    17, 18, 20, 21, 22, 24, 25, 27, 28, 30, 32, 33, 35, 37, 39, 41,
    43, 45, 47, 50, 52, 54, 57, 59, 61, 64, 66, 69, 71, 74, 77, 79,
    82, 85, 88, 90, 93, 96, 99, 102, 105, 107, 110, 113, 116, 119, 122, 125};

char *ap;
int anum_ok;
int ma[9]; int mb[9]; int mc[9];

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

/* sin(a) in 8.8 (doubled 7-bit table), brads; cos(a) = rsin(a+64) */
int rsin(int a) { return (s3tab[a & 255] - 128) * 2; }

/* mc = ma * mb, all 8.8 3x3 row-major (muldiv gives the 32-bit product) */
int matmul() {
    int r; int c; int k; int v;
    r = 0;
    while (r < 3) {
        c = 0;
        while (c < 3) {
            v = 0;
            k = 0;
            while (k < 3) {
                v = v + muldiv(ma[r * 3 + k], mb[k * 3 + c], 256);
                k = k + 1;
            }
            mc[r * 3 + c] = v;
            c = c + 1;
        }
        r = r + 1;
    }
    return 0;
}

int pv[3];
int haspv;

int main() {
    int x; int y; int z; int i; int c; int s;
    ap = argstr();
    skipsp();
    if (*ap == '-' && (*(ap + 1) == 'h' || *(ap + 1) == 'H')) {
        puts("usage: ROTATE [x y z [px py pz]]  brads (64 = 90 deg); pivot point");
        return 0;
    }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    if (g3probe() == 0) { puts("?No engine"); return 1; }
    x = 0; y = 0; z = 0;
    pv[0] = 0; pv[1] = 0; pv[2] = 0;
    haspv = 0;
    i = anum(); if (anum_ok) { x = i;
        y = anum();
        z = anum();
        i = anum(); if (anum_ok) { pv[0] = i;
            pv[1] = anum();
            pv[2] = anum();
            haspv = 1;
        }
    }
    /* ma = Ry(y): rows [c 0 -s / 0 1 0 / s 0 c] */
    c = rsin(y + 64); s = rsin(y);
    ma[0] = c;   ma[1] = 0;   ma[2] = 0 - s;
    ma[3] = 0;   ma[4] = 256; ma[5] = 0;
    ma[6] = s;   ma[7] = 0;   ma[8] = c;
    /* mb = Rx(x): rows [1 0 0 / 0 c -s / 0 s c]; mc = Rx * Ry */
    c = rsin(x + 64); s = rsin(x);
    mb[0] = 256; mb[1] = 0;   mb[2] = 0;
    mb[3] = 0;   mb[4] = c;   mb[5] = 0 - s;
    mb[6] = 0;   mb[7] = s;   mb[8] = c;
    i = 0;
    while (i < 9) { int t; t = ma[i]; ma[i] = mb[i]; mb[i] = t; i = i + 1; }
    matmul();
    /* ma = Rz(z): rows [c -s 0 / s c 0 / 0 0 1]; result = Rz * (Rx * Ry) */
    c = rsin(z + 64); s = rsin(z);
    ma[0] = c;   ma[1] = 0 - s; ma[2] = 0;
    ma[3] = s;   ma[4] = c;     ma[5] = 0;
    ma[6] = 0;   ma[7] = 0;     ma[8] = 256;
    i = 0;
    while (i < 9) { mb[i] = mc[i]; i = i + 1; }
    matmul();
    i = 0;
    while (i < 9) { g3par(i, mc[i]); i = i + 1; }
    /* WITH a pivot: translation = P - R*P so the pivot maps to itself
     * (scene-style: tri-built worlds with z baked into the vertices).
     * WITHOUT one: translation is left UNTOUCHED -- the model rotates
     * about its own origin and keeps its push-out, which is what
     * origin-centred models like cube's need (cube uploads +/-90 verts
     * and lives at T z=400; overwriting T dropped it into the near
     * plane and it vanished). */
    if (haspv) {
        i = 0;
        while (i < 3) {
            c = 0;
            s = 0;
            while (s < 3) {
                c = c + muldiv(mc[i * 3 + s], pv[s], 256);
                s = s + 1;
            }
            g3par(9 + i, pv[i] - c);
            i = i + 1;
        }
    }
    g3par(21, 1);                    /* erase, no flip */
    poke(GECMD, 2);                  /* RENDER the persisted scene */
    while (peek(GESTAT) & 128) { }
    return 0;
}
