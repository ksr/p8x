/* cube.c -- spinning wireframe cube: the stage-7 3D pipeline's first client
 * (STAGE7-DESIGN.md) and the measured demo of lib_g3d.
 *
 *     CUBE            spin for 64 frames (one full turn) and exit
 *     CUBE 500        spin for 500 frames
 *
 * Per frame: rotate the 8 corner vertices of a +/-90 cube about Y (angle a)
 * and X (a/2), push the result 400 into the scene, pour the 12 edges into
 * the g3d pool, render. The vertices are rebuilt from constants every frame
 * -- rotation by ACCUMULATED angle, not incrementally -- so rounding never
 * accumulates and frame N is bit-identical on every run and every machine
 * (which is what the spot-pixel test relies on).
 *
 * The rotation is the demo's own, not the library's (STAGE7: measure the
 * base pipeline before deciding a library transform is affordable): a
 * 256-step binary-angle sine table, amplitude 120, so a rotation term is
 * (x*c - z*s)/128 -- products stay inside 16 bits for coordinates <= ~136,
 * which +/-90 corners (|corner| <= 90*sqrt(3) = 156 only AFTER both
 * rotations, when no further multiply touches them) respect. sdiv7 is the
 * signed >>7 (p8cc's >> is unsigned).
 *
 * Frame 0 has angle 0: cos=120, sin=0, so the cube appears axis-aligned at
 * 120/128 scale -- the geometry the test computes by hand. */

//#use gfx
//#use g3d

//#define GLID   0xFF54  /* GL presence probe: 'G' when fitted            */
//#define GLDATA 0xFF50  /* the command FIFO, one byte at a time          */
//#define GLSTAT 0xFF51  /* bit7 FIFO full, bit6 busy                     */

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

int c3ea[12] = {0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3};   /* edge: vertex a */
int c3eb[12] = {1, 2, 3, 0, 5, 6, 7, 4, 4, 5, 6, 7};   /* edge: vertex b */
int cvx[8]; int cvy[8]; int cvz[8];                     /* the model      */
int rx[8]; int ry[8]; int rz[8];                        /* this frame     */

/* sin(a) scaled to +/-120, binary angles (256 = a full turn). The table
 * stores value+128 so it initializes as unsigned chars; the subtract's
 * 16-bit wrap IS the sign. cos(a) = rsin(a+64). */
int rsin(int a) { return s3tab[a & 255] - 128; }

/* signed v >> 7 (p8cc's >> is a logical shift) */
int sdiv7(int v) {
    if (v & 32768) { return 0 - ((0 - v) >> 7); }
    return v >> 7;
}


int glb(int v) {
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}
int glw(int v) { glb(v & 255); glb(v >> 8); return 0; }

int main() {
    char *a;
    int nf; int f; int ang; int ax;
    int i; int k; int c; int s; int t;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == '-') {
        puts("usage: CUBE [frames]   spinning wireframe cube (default 64)");
        return 0;
    }
    nf = 0;
    while (*a >= '0' && *a <= '9') { nf = nf * 10 + (*a - '0'); a = a + 1; }
    if (nf == 0) { nf = 64; }
    while (*a == 32) { a = a + 1; }
    if (*a == 's') { g3has = 2; }    /* CUBE n s: force the software path */

    if (gpresent() == 0) { puts("?No display"); return 1; }


    /* the 8 corners of a +/-90 cube: x -,+,+,- per face ring, y - then +
     * within a ring, z - front ring / + back ring */
    i = 0;
    while (i < 8) {
        k = i & 3;
        if (k == 1 || k == 2) { cvx[i] = 90; } else { cvx[i] = 0 - 90; }
        if (k & 2) { cvy[i] = 90; } else { cvy[i] = 0 - 90; }
        if (i & 4) { cvz[i] = 90; } else { cvz[i] = 0 - 90; }
        i = i + 1;
    }
    if (g3has != 2 && peek(GLID) == 71) {
        /* stage 10c: the cube is a stored GL command list that spins
         * ITSELF -- per pass the list nudges the modeling matrix
         * (MDROTY 6, MDROTX 3), erases, draws the 12 edges, flips and
         * waits a frame tick; CLOOP runs it nf times with the CPU
         * completely idle. CLEARS first: both framebuffer pages power
         * on as garbage (the stage-8b sideband lesson), and the exit
         * PGSYNC rejoins them, so drawing afterwards behaves. */
        glb(179); glw(0 - 120); glw(120); glw(0 - 120); glw(120);
        glb(178); glw(104); glw(375); glw(0); glw(271);
        glb(160);                        /* VWIDEN */
        glb(161); glw(0); glw(0); glw(0);
        glb(177); glw(400);              /* DISTAN: viewer backs off */
        glb(144);                        /* MDIDEN */
        glb(145); glw(0); glw(0); glw(0);
        glb(15); glb(0); glb(0); glb(0); /* CLEARS: BOTH pages */
        glb(112); glb(1);                /* CLBEG 1: one frame of spin */
        glb(148); glw(6);                /* MDROTY 6 (a delta per pass) */
        glb(147); glw(3);                /* MDROTX 3 */
        glb(7); glb(0); glb(0); glb(0);  /* FLOOD */
        glb(6); glb(0); glb(0); glb(31); /* connectors: blue */
        i = 0;
        while (i < 4) {
            glb(18); glw(cvx[i]); glw(cvy[i]); glw(0 - 90);
            glb(42); glw(cvx[i]); glw(cvy[i]); glw(90);
            i = i + 1;
        }
        glb(6); glb(31); glb(0); glb(0); /* front ring: red */
        i = 0;
        while (i < 4) {
            k = (i + 1) & 3;
            glb(18); glw(cvx[i]); glw(cvy[i]); glw(0 - 90);
            glb(42); glw(cvx[k]); glw(cvy[k]); glw(0 - 90);
            i = i + 1;
        }
        glb(6); glb(0); glb(63); glb(0); /* back ring: green */
        i = 0;
        while (i < 4) {
            k = (i + 1) & 3;
            glb(18); glw(cvx[i]); glw(cvy[i]); glw(90);
            glb(42); glw(cvx[k]); glw(cvy[k]); glw(90);
            i = i + 1;
        }
        glb(2);                          /* FLIP */
        glb(5); glw(1);                  /* WAIT 1: pace to the panel */
        glb(113);                        /* CLEND */
        glb(115); glb(1); glw(nf);       /* CLOOP 1 nf: spin, CPU idle */
        glb(3);                          /* PGSYNC on the way out */
        while (peek(GLSTAT) & 64) { }
        puts("DONE");
        return 0;
    }

    g3window(0 - 120, 0 - 120, 120, 120);
    g3view(104, 0, 375, 271);        /* centred square (272 wide) */
    g3persp(256);

    /* THE ENGINE PATH (stage 8b): upload the UNROTATED cube once, then a
     * frame is just a matrix (composed from the same sine table -- values
     * double from 7-bit to 8.8 scale; the cross terms need muldiv's 32-bit
     * product) and a render command. Rotation happens in fabric; the CPU's
     * per-frame work is ~60 pokes. Rounding differs microscopically from
     * the software path (one composed matrix vs two sequential shifts), so
     * this is a sibling of the software cube, not its twin -- the test
     * replica models each path with its own arithmetic.
     * `cube 1` renders without the page flip so POINT verification reads
     * the frame it drew; longer runs flip for a tear-free spin. */
    /* (the stage-8b record-engine path lived here until stage 10c --
     * retired with the $FF40 interface; the GL list path above is the
     * hardware cube now, and below is the stage-7 software original) */

    f = 0; ang = 0;
    while (f < nf) {
        /* rotate all 8 vertices: Y by ang, then X by ang/2, then +400 z */
        ax = (ang >> 1) & 255;
        i = 0;
        while (i < 8) {
            c = rsin(ang + 64); s = rsin(ang);
            t     = sdiv7(cvx[i] * c - cvz[i] * s);
            rz[i] = sdiv7(cvx[i] * s + cvz[i] * c);
            rx[i] = t;
            c = rsin(ax + 64); s = rsin(ax);
            t     = sdiv7(cvy[i] * c - rz[i] * s);
            rz[i] = sdiv7(cvy[i] * s + rz[i] * c) + 400;
            ry[i] = t;
            i = i + 1;
        }
        g3clear();
        i = 0;
        while (i < 12) {
            if (i == 0) { g3color(0xF800); }
            if (i == 4) { g3color(0x07E0); }
            if (i == 8) { g3color(0x001F); }
            k = c3ea[i]; t = c3eb[i];
            g3line(rx[k], ry[k], rz[k], rx[t], ry[t], rz[t]);
            i = i + 1;
        }
        g3render();
        ang = (ang + 4) & 255;
        f = f + 1;
    }
    puts("DONE");
    return 0;
}
