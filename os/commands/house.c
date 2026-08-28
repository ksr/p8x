/* house.c -- the PG-640A manual's house, animated (the graphics card's
 * demo reel, stage CARD-EDGE).
 *
 *     HOUSE           one slow turn, then zoom out and back in
 *     HOUSE 36        the turn in 36 frames (10 degrees a step)
 *
 * The house is the manual's own worked example (docs/reference/
 * pg640a.pdf ch.3; docs' HOUSE.GL is the ASCII form), embedded here as
 * the raw hex GL bytes and recorded into command list 1 with its erase,
 * FLIP and frame WAIT inside -- so every CLRUN is one complete paced
 * frame. The animation is CPU-driven, eight bytes a frame: a matrix
 * delta then CLRUN. Matrix verbs COMPOSE, so each MDROTY adds 360/nf
 * degrees and each MDSCAL multiplies -- zoom-out is 24 frames of x0.94,
 * zoom-in 24 of x1.066, and a final MDIDEN squares away the ~2% of
 * compounded rounding.
 *
 * The model is pre-translated to put its centre (50,75,0) at the
 * origin, so rotation and scale pivot through the middle of the house.
 * Runs identically on the all-in-one build and across the bridge
 * (runcard.sh) -- the same bytes, the same bus contract. */

//#use gfx

//#define GLID   0xFF54  /* GL presence probe: 'G' when fitted            */
//#define GLDATA 0xFF50  /* the command FIFO, one byte at a time          */
//#define GLSTAT 0xFF51  /* bit7 FIFO full, bit6 busy                     */

char hdat[604] = {
    224, 0, 50, 4, 156, 255, 0, 0, 100, 0, 100, 0,
    0, 0, 100, 0, 100, 0, 0, 0, 156, 255, 156, 255,
    0, 0, 156, 255, 50, 4, 156, 255, 100, 0, 100, 0,
    100, 0, 100, 0, 100, 0, 100, 0, 100, 0, 156, 255,
    156, 255, 100, 0, 156, 255, 18, 156, 255, 100, 0, 100,
    0, 42, 156, 255, 0, 0, 100, 0, 18, 100, 0, 100,
    0, 100, 0, 42, 100, 0, 0, 0, 100, 0, 18, 100,
    0, 100, 0, 156, 255, 42, 100, 0, 0, 0, 156, 255,
    18, 156, 255, 100, 0, 156, 255, 42, 156, 255, 0, 0,
    156, 255, 18, 156, 255, 100, 0, 100, 0, 42, 0, 0,
    150, 0, 100, 0, 42, 100, 0, 100, 0, 100, 0, 18,
    100, 0, 100, 0, 156, 255, 42, 0, 0, 150, 0, 156,
    255, 42, 156, 255, 100, 0, 156, 255, 18, 0, 0, 150,
    0, 156, 255, 42, 0, 0, 150, 0, 100, 0, 18, 241,
    255, 0, 0, 100, 0, 42, 241, 255, 66, 0, 100, 0,
    42, 15, 0, 66, 0, 100, 0, 42, 15, 0, 0, 0,
    100, 0, 50, 4, 251, 255, 33, 0, 100, 0, 5, 0,
    33, 0, 100, 0, 5, 0, 55, 0, 100, 0, 251, 255,
    55, 0, 100, 0, 50, 4, 181, 255, 33, 0, 100, 0,
    216, 255, 33, 0, 100, 0, 216, 255, 66, 0, 100, 0,
    181, 255, 66, 0, 100, 0, 50, 4, 40, 0, 33, 0,
    100, 0, 75, 0, 33, 0, 100, 0, 75, 0, 66, 0,
    100, 0, 40, 0, 66, 0, 100, 0, 50, 4, 40, 0,
    33, 0, 156, 255, 75, 0, 33, 0, 156, 255, 75, 0,
    66, 0, 156, 255, 40, 0, 66, 0, 156, 255, 50, 4,
    181, 255, 33, 0, 156, 255, 216, 255, 33, 0, 156, 255,
    216, 255, 66, 0, 156, 255, 181, 255, 66, 0, 156, 255,
    50, 4, 156, 255, 33, 0, 186, 255, 156, 255, 33, 0,
    221, 255, 156, 255, 66, 0, 221, 255, 156, 255, 66, 0,
    186, 255, 50, 4, 156, 255, 33, 0, 35, 0, 156, 255,
    33, 0, 70, 0, 156, 255, 66, 0, 70, 0, 156, 255,
    66, 0, 35, 0, 50, 4, 8, 0, 25, 0, 100, 0,
    13, 0, 25, 0, 100, 0, 13, 0, 30, 0, 100, 0,
    8, 0, 30, 0, 100, 0, 50, 4, 100, 0, 0, 0,
    100, 0, 200, 0, 0, 0, 100, 0, 200, 0, 0, 0,
    0, 0, 100, 0, 0, 0, 0, 0, 50, 4, 100, 0,
    75, 0, 100, 0, 200, 0, 75, 0, 100, 0, 200, 0,
    75, 0, 0, 0, 100, 0, 75, 0, 0, 0, 18, 100,
    0, 75, 0, 0, 0, 42, 100, 0, 0, 0, 0, 0,
    18, 200, 0, 75, 0, 0, 0, 42, 200, 0, 0, 0,
    0, 0, 18, 200, 0, 75, 0, 100, 0, 42, 200, 0,
    0, 0, 100, 0, 18, 105, 0, 0, 0, 100, 0, 42,
    105, 0, 66, 0, 100, 0, 42, 195, 0, 66, 0, 100,
    0, 42, 195, 0, 0, 0, 100, 0, 18, 105, 0, 22,
    0, 100, 0, 42, 195, 0, 22, 0, 100, 0, 18, 105,
    0, 44, 0, 100, 0, 42, 195, 0, 44, 0, 100, 0,
    50, 4, 120, 0, 50, 0, 100, 0, 130, 0, 50, 0,
    100, 0, 130, 0, 60, 0, 100, 0, 120, 0, 60, 0,
    100, 0, 50, 4, 170, 0, 50, 0, 100, 0, 180, 0,
    50, 0, 100, 0, 180, 0, 60, 0, 100, 0, 170, 0,
    60, 0, 100, 0
};

char *ap;

int glb(int v) {
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}

int glw(int v) { glb(v & 255); glb((v / 256) & 255); return 0; }

int setup() {                     /* frame + camera + centred model */
    glb(179); glw(0 - 180); glw(180); glw(0 - 180); glw(180);  /* WINDOW */
    glb(178); glw(104); glw(375); glw(0); glw(271);            /* VWPORT */
    glb(160);                                                  /* VWIDEN */
    glb(161); glw(0); glw(0); glw(0);                          /* VWRPT  */
    glb(177); glw(400);                                        /* DISTAN */
    glb(144);                                                  /* MDIDEN */
    glb(145); glw(0); glw(0); glw(0);                          /* MDORG  */
    glb(150); glw(0 - 50); glw(0 - 75); glw(0);                /* MDTRAN */
    return 0;
}

int frame(int op, int v) {        /* one delta + one replayed frame */
    glb(op); glw(v);
    if (op == 146) { glw(v); glw(v); }         /* MDSCAL takes three */
    glb(114); glb(1);                          /* CLRUN 1 */
    return 0;
}

int main() {
    int nf; int i; int step;
    ap = argstr();
    while (*ap == 32) { ap = ap + 1; }
    nf = 0;
    while (*ap >= '0' && *ap <= '9') { nf = nf * 10 + (*ap - '0'); ap = ap + 1; }
    if (nf < 4) { nf = 72; }
    step = 360 / nf;
    if (step < 1) { step = 1; }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    if (peek(GLID) != 71) { puts("?No GL engine"); return 1; }

    setup();
    glb(15); glb(0); glb(0); glb(0);           /* CLEARS both pages */
    glb(112); glb(1);                          /* CLBEG 1: one frame */
    glb(7); glb(0); glb(0); glb(0);            /*   FLOOD: erase     */
    glb(6); glb(31); glb(63); glb(31);         /*   COLOR white      */
    i = 0;
    while (i < 604) { glb(hdat[i] & 255); i = i + 1; }
    glb(2);                                    /*   FLIP             */
    glb(5); glw(1);                            /*   WAIT 1           */
    glb(113);                                  /* CLEND              */

    i = 0;                                     /* one full turn      */
    while (i < nf) { frame(148, step); i = i + 1; }
    i = 0;                                     /* zoom out...        */
    while (i < 24) { frame(146, 240); i = i + 1; }
    i = 0;                                     /* ...and back in     */
    while (i < 24) { frame(146, 273); i = i + 1; }

    glb(144);                                  /* MDIDEN: exact home */
    glb(150); glw(0 - 50); glw(0 - 75); glw(0);
    glb(114); glb(1);                          /* the resting frame  */
    glb(3);                                    /* PGSYNC on the way out */
    while (peek(GLSTAT) & 64) { }
    puts("DONE");
    return 0;
}
