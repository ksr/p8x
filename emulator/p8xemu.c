/* p8xemu - cycle-level emulator for the P8X 8-bit TTL computer.
 *
 * Interprets the SAME microcode ROM images (u0-u3.bin) that are burned to
 * the control card 28C64s, so emulator and hardware cannot drift.
 *
 * Fidelity notes:
 *  - 74181 modelled with active-high data. The CIN pin is active-low at the
 *    silicon pin, but the C FLAG is CONVENTIONAL (rev B): C=1 means carry-out
 *    (ADD) / no-borrow i.e. A>=B (SUB/CMP).
 *  - Carry chain computed regardless of M (as in silicon), so LDF during
 *    logic ops latches the same C the hardware would.
 *  - V flag (rev C): signed overflow by the sign-bit method (see nV below);
 *    valid after ADD/SUB/CMP. FCOND 6/7 expose N^V and (N^V)|Z for the signed
 *    branches BLT/BGE/BLE/BGT.
 *  - Shifter: stage1 SH0 = left, stage2 SH1 = right; the shifted-out bit is
 *    latched into C, and with SHCIN the shifted-in bit is the current C
 *    (rotate through carry). SETC/CLRC force C only (SEC/CLC).
 *  - Pipeline/condition timing per control card: the FCOND field of the word
 *    in the pipeline selects ROM A12 for the NEXT lookup.
 *
 * Memory map: 0000-1FFF ROM (8K) | 2000-FEFF RAM (56K) | FF00-FFFF I/O
 *   (ROM = 8K low; RAM = 2x 62256 covering 2000-FEFF; OS loads at 2000)
 *   FF00 switches(r, set with -s)  FF02 LEDs(w, trace with -L)
 *   FF04 ACIA status(r)  FF05 ACIA data(rw)
 *   FF10-FF17 CF-IDE task file (8-bit True IDE), modelled when -c <img> given:
 *     FF10 data  FF11 feature  FF12 sector-count  FF13-15 LBA0-2
 *     FF16 head/dev  FF17 command(w)/status(r)  [BSY7 DRQ3 ERR0]
 *   Backs a flat sector-image file (LBA*512); SET FEATURES/IDENTIFY/READ/WRITE.
 *   FF20-FF2F graphics display: 480x272 RGB565 direct colour (a pixel IS its
 *     colour; no palette, no modes -- stage 6) with a drawing engine. Same
 *     device inside the FPGA P8X or on a bus card, so one command set and one
 *     golden model serve both.
 *     FF20-23 X0/Y0/X1/Y1 low  FF29-2C their high bytes  FF24/2D pen low/high
 *     FF28 x-radius  FF2F y-radius (ellipse)  FF25 command  FF26 status
 *     FF27 data  FF2D/2E "PG" presence signature
 *     Commands: 01 PIXELW 02 LINE 04 BOXFILL 09 PIXELR (read)
 *               08 CIRCLEFILL 09 POINT 0A ELLIPSE 0B ELLIPSEFILL
 *               | F0 SELFTEST (emulator only) F1 RESET F2 IDENT
 *     Always present; -g writes the DISPLAY page as a PPM, -G as text.
 *   FF30-FF3F MDU: hardware muldiv, bit-exact to lib_g3d's contract (stage 8a).
 *   FF40-FF4F geometry engine: TYPED, COLOURED records in SDRAM (LINE and
 *     filled/outline TRI -- stage 9), matrix transform, clip, project, draw
 *     + page-flip double buffering (stage 8b) + parameter readback (9c: the
 *     list is a persistent scene). Both pages power on holding a fixed
 *     garbage pattern, like real DRAM.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <signal.h>
#include <time.h>
#include "../generators/memmap.h"   /* RAMBASE/IOBASE/ROMSIZE/RAMSIZE — single-source memory map */
#include "../generators/trigtab.h"  /* SIN8/TANH8 — stage-10b GL trig, shared with the RTL */
#include "../generators/glkwtab.h"  /* GL ASCII keywords — stage 10d, shared with the RTL */

static int interactive=0;             /* stdin is a TTY: raw + blocking console */
static int norx=0;                    /* -N: console RX always empty (see rx_ready) */
static uint8_t *scr=0;                /* -i FILE: scripted console input (co-sim) */
static long scrlen=0, scrpos=0;
static int peeked=-1;                 /* one-char lookahead for ACIA status/data */
static struct termios g_orig;
static int g_raw=0;

static uint8_t rom[4][8192], eeprom[ROMSIZE], ram[RAMSIZE];  /* ROM 8K $0000..$1FFF; RAM $2000..$FEFF (56K) */
static uint16_t P[6];                 /* P0=PC P1 P2 P3=SP P4=PT P5=PT2 (2 hidden scratch) */
static uint8_t A,B,T,T2,IR;
static int stp, fC,fZ,fN,fV;          /* fC = conventional carry (1 = carry / A>=B) */
static int prev_fcond=0, halted=0, trace=0, mtrace=0;
static int IE=0, irq_pending=0;   /* rev C: interrupt-enable latch + pending IRQ */
static unsigned long long cycles=0;
static uint8_t leds=0;
static uint8_t switches=0;             /* $FF00 input byte, set with -s */
static int led_trace=0;                /* -L: print $FF02 writes as they change */

/* ---- CF-IDE model (active only when a disk image is attached with -c) ----
   The monitor's driver (firmware/p8xmon.asm) drives a CompactFlash in 8-bit
   True IDE mode: it writes LBA0-2/head/sector-count, issues a command to FF17,
   spins on BSY/DRQ in the status register, then streams 512 bytes through the
   data port FF10. We model exactly that handshake. BSY is never asserted (the
   transfer is instantaneous here); DRQ is raised while a 512-byte buffer is
   being streamed and dropped when it drains. */
/* Two CF devices on the shared $FF10 task-file port, selected by the ATA device
   bit (CFHEAD/$FF16 bit 0): device 0 = drive 0 (boot), device 1 = drive 1.
   `-c <img>` attaches drive 0, `-c2 <img>` drive 1. An absent device reads back
   $FF (a floating bus) — the firmware's bounded CF waits time out on it, so a
   missing drive 1 is detected, not a hang. */
struct cf_state {
    FILE   *img;
    uint8_t buf[512];
    int     idx, drq, err, write;
    uint8_t feat, lba0, lba1, lba2;
};
static struct cf_state cf[2];
static int cf_active=0;                 /* device selected by CFHEAD bit 0 */
static long cf_lbaof(struct cf_state*c){ return ((long)c->lba2<<16)|((long)c->lba1<<8)|c->lba0; }
static void cf_seek(struct cf_state*c){ if(c->img) fseek(c->img, cf_lbaof(c)*512L, SEEK_SET); }
/* ATA IDENTIFY: words 27-46 (bytes 54..) hold a byte-swapped model string,
   which is what the monitor's I command prints. */
static void cf_identify(struct cf_state*c){
    const char *m="P8X-CF EMULATOR                         "; /* 40 chars */
    memset(c->buf,0,512);
    for(int i=0;i<40;i+=2){ c->buf[54+i]=m[i+1]; c->buf[54+i+1]=m[i]; }
    c->idx=0; c->drq=1; c->err=0; c->write=0;
}
static void cf_readsec(struct cf_state*c){
    memset(c->buf,0,512);
    cf_seek(c); if(c->img) fread(c->buf,1,512,c->img);
    c->idx=0; c->drq=1; c->err=0; c->write=0;
}
static void cf_cmd(struct cf_state*c, uint8_t v){
    switch(v){
    case 0xEF: c->err=0; c->drq=0; break;                    /* SET FEATURES   */
    case 0xEC: cf_identify(c); break;                        /* IDENTIFY       */
    case 0x20: cf_readsec(c); break;                         /* READ SECTORS   */
    case 0x30: c->idx=0; c->drq=1; c->err=0; c->write=1; break; /* WRITE SECTORS */
    default:   c->err=1; c->drq=0; break;
    }
}
static uint8_t cf_data_rd(struct cf_state*c){
    uint8_t v=c->buf[c->idx++];
    if(c->idx>=512){ c->idx=0; c->drq=0; }
    return v;
}
static void cf_data_wr(struct cf_state*c, uint8_t v){
    c->buf[c->idx++]=v;
    if(c->idx>=512){
        if(c->write && c->img){ cf_seek(c); fwrite(c->buf,1,512,c->img); fflush(c->img); }
        c->idx=0; c->drq=0; c->write=0;
    }
}

/* ---- Graphics display model (always present; -g writes the image out) ------
   480x272 RGB565: the framebuffer lives in the board's in-package SDRAM behind
   the streaming controller (fpga/tang-nano-20k/sdram/), so the old block-RAM
   size arguments are history -- see STAGE2/5/6-DESIGN.md for how 240x136/2bpp
   and 480x272/8bpp-palettized each lived and died on the way here.

   The drawing engine belongs to the DEVICE, here and in the RTL -- not to the
   software. BASIC loads GX0/GY0/GX1/GY1/GCOL and writes GCMD, so a filled box
   costs a handful of port writes instead of 32640 read-modify-write cycles
   through a data port (2bpp packs four pixels to a byte, so software plotting
   would have to mask every single one). GSTAT bit 7 is the busy flag; drawing
   is instantaneous here, the same way CF never asserts BSY, so it reads 0.

   This is the GOLDEN MODEL. The Verilog engine has to reproduce gpu_line step
   for step or the co-sim diverges, so the Bresenham below is written in the
   plainest integer form there is and must not be "improved". */
/* 480x272 at 16 bpp, RGB565 direct colour. */
#define GW_MAX  480
#define GH_MAX  272
/* TWO framebuffer pages (stage 8b): gfb is the DRAW page -- every engine
   and CPU pixel, and POINT's read-back, all unchanged below -- and gfbd is
   the DISPLAY page the PPM/ASCII dumps show. Both start on page 0, so
   nothing that never flips can tell the second page exists. The geometry
   engine's FLIP swaps the pointers (on the board the display half is
   latched at the scanout frame boundary; here there are no frames -- the
   same instant-completion licence as GPU BUSY). */
static uint16_t gfbmem[2][GW_MAX*GH_MAX];  /* a pixel IS an RGB565 word */
static uint16_t *gfb  = gfbmem[0];         /* draw page */
static uint16_t *gfbd = gfbmem[0];         /* display page */
/* Power-on framebuffer contents are UNDEFINED on the board -- raw SDRAM,
   the cold-boot stripes. Model that with a fixed (deterministic: PPM
   diffs between runs must stay meaningful) garbage pattern on BOTH pages,
   so software that forgets to clear a page it shows fails HERE, not just
   on the panel. The boot splash clears page 0; page 1 is software's job
   (see man cube / STAGE8B-DESIGN on flipping). */
static void gfb_poweron(void){
    for(size_t i=0;i<2*(size_t)GW_MAX*GH_MAX;i++)
        gfbmem[0][i]=(uint16_t)(0x2104u*((i&7)+1));   /* stripey, fixed */
}
/* SINGLE MODE. 240x136 at 2 bpp was retired once nothing needed it: four pixels
   to a byte forced a read-modify-write on every plot, and carrying both depths
   cost enough logic in the RTL that the design would not place. One depth means
   a pixel IS a byte -- no read, no masking, no mode muxing anywhere. */
static const int gw=480, gh=272, gstride=480;
static const size_t gfpix=(size_t)480*272;      /* PIXELS, not bytes */
/* No palette. RGB565 direct colour: the pixel's own bits are its colour,
   exactly the panel's wiring (r[4:0] g[5:0] b[4:0]). The palette (and SETPAL,
   and BASIC's PALETTE) died with stage 6 -- see STAGE6-DESIGN.md for what was
   given up (recolour-without-redraw) and why 565 is the machine's natural
   ceiling: panel depth, word size, two pixels per bus word, a line per row. */
/* Coordinates are 16-bit register PAIRS. Writing the low byte clears the high
   byte, so software that only ever writes lows (everything at 240x136) can
   never be broken by a stale high byte left behind by something else. Write the
   high byte AFTER the low one when you need a coordinate past 255. The pairs
   exist because 480x272 -- this same panel at its native resolution, which is
   where an SDRAM framebuffer would go -- needs 9 bits for X. */
static uint16_t gx0,gy0,gx1,gy1;
/* The pen is a whole RGB565 colour. GCOL is its low byte and follows the same
   rule as the coordinate pairs: a low write CLEARS the high byte, so 8-bit
   software can never inherit a stale one. GCOLH is the WRITE side of $FF2D --
   the register page is full, and GID0's read-only signature leaves its write
   decode free (see STAGE6-DESIGN.md). */
static uint16_t gcol;
static uint8_t  gmode;                 /* 10f LINFUN pixel-write mode */
static uint8_t  gparm, gparm2, gerr;
/* GDATA ($FF27) is the one read-back port: it streams the IDENT record after an
   IDENT command, and otherwise holds the result of the last POINT. gidx is the
   stream cursor; POINT parks it at the end so a pixel read is not mistaken for
   another IDENT byte. */
#define GIDLEN 14
static uint8_t  gident[GIDLEN];
static int      gidx=GIDLEN;

/* Stage 8a MDU ($FF30-$FF3F): hardware muldiv, bit-exact to lib_g3d's
   software contract (STAGE8-DESIGN.md). Operands follow the gfx pair rules
   (low write clears high). Computation is INSTANT here -- MDSTAT never shows
   busy -- the same licence the GPU takes with BUSY: the RTL divider IS busy
   ~20 cycles, so software must poll even though it never spins here. */
static uint16_t mda, mdb, mdc, mdq;
static uint16_t mdu_exec(uint16_t a, uint16_t b, uint16_t c){
    int sa=a>>15, sb=b>>15, sc=c>>15;
    uint32_t ua = sa ? (uint16_t)(0-a) : a;   /* $8000 negates to 32768, */
    uint32_t ub = sb ? (uint16_t)(0-b) : b;   /*   the same 16-bit wrap  */
    uint32_t uc = sc ? (uint16_t)(0-c) : c;   /*   the software relies on */
    uint32_t uq;
    if(ua==0 || ub==0) return 0;              /* 0 even when c==0 */
    if(uc==0) uq=32767;                       /* /0 saturates */
    else { uq=(ua*ub)/uc; if(uq>32767) uq=32767; }
    return (uint16_t)((sa^sb^sc) ? 0-uq : uq);
}

/* Stage 8b geometry engine ($FF40-$FF4F): the GOLDEN MODEL, and the third
   implementation of the ONE pipeline -- lib_g3d's software walk is the
   specification, this must match it pixel for pixel, and the RTL must match
   both (c_g3d_test and tb_geom pin all three to the same reference).
   Every variable that is 16 bits on the machine is int16_t here, so C's
   assignment truncation reproduces the wrap; the transform accumulates in
   int32 and arithmetic-shifts (FLOOR), muldiv truncates toward zero --
   both per the contract. Rendering is instant (the GPU-BUSY licence). */
static void gpu_line(int x0,int y0,int x1,int y1,uint16_t c);
static uint16_t gpu_pixel(int x,int y);
static void gpu_hline(int xa,int xb,int y,uint16_t c);
static void gpu_ellipse(int cx,int cy,int rx,int ry,uint16_t c,int fill);
/* stage 10j: LINPAT lives in the DEVICE (like GMODE) -- every line from
   every door consults it, MSB first, restarting each primitive. AREAPT
   (patterned fill spans) was REMOVED 2026-08-30 to buy placement
   headroom on the full card; opcode E7 is err1 again, a candidate for
   the successor board. */
static uint16_t gpat = 0xFFFF;         /* device line pattern */
static void gpu_box(int x0,int y0,int x1,int y1,uint16_t c,int fill);
/* RETIRED (stage 10b): the $FF40 record-engine interface -- GEUP list
   upload, GECMD RENDER, the GESEL/GEVAL register file, GEID. The GL
   command port is the one hardware 3D interface now; gep[] lives on as
   the INTERNAL parameter file the GL verbs compose into. lib_g3d's GEID
   probe finds a floating bus and falls back to its software walk. */
static int16_t  gep[25];               /* the parameter file (stage 10b: 23
                                          near plane, 24 far plane) */

static void ge_reset(void){            /* power-on parameter state */
    memset(gep,0,sizeof gep);
    gep[0]=gep[4]=gep[8]=256;          /* identity matrix, S7.8 */
    gep[12]=256;                       /* focal d */
    gep[21]=3;                         /* flags: erase + flip */
    gep[23]=16;                        /* near plane (the stage-7..9 z>=16) */
    gep[24]=32767;                     /* far plane: int16 max = no far clip */
}

static int16_t ge_md(int16_t a,int16_t b,int16_t c){
    return (int16_t)mdu_exec((uint16_t)a,(uint16_t)b,(uint16_t)c);
}
static int ge_oc(int16_t x,int16_t y){          /* window outcode L,R,B,T */
    int c=0;
    if(x<gep[13]) c|=1;
    if(x>gep[15]) c|=2;
    if(y<gep[14]) c|=4;
    if(y>gep[16]) c|=8;
    return c;
}

static void ge_flip(void){
    /* display <- the page just drawn; draw toggles to the OTHER bank. This
       exact rule (not a pointer swap, which from the shared power-on page
       would be a no-op forever) is what makes the FIRST flip split the
       pages: boot is single-buffered on page 0 until someone flips. */
    gfbd = gfb;
    gfb  = (gfb == gfbmem[0]) ? gfbmem[1] : gfbmem[0];
}

/* transform one vertex (M*v >>> 8 + T) -- shared by both record types */
static void ge_xform(const int16_t *v, int16_t *w){
    for(int r=0;r<3;r++){
        int32_t acc = (int32_t)gep[r*3+0]*v[0]
                    + (int32_t)gep[r*3+1]*v[1]
                    + (int32_t)gep[r*3+2]*v[2];
        w[r] = (int16_t)((acc>>8) + gep[9+r]);
    }
}
/* project + viewport-map one transformed vertex to screen space */
static void ge_map(const int16_t *w, int16_t *sx, int16_t *sy){
    int16_t x=w[0], y=w[1];
    if(gep[12]){
        x = ge_md(x, gep[12], w[2]);
        y = ge_md(y, gep[12], w[2]);
    }
    *sx = (int16_t)(gep[17] + ge_md((int16_t)(x - gep[13]),
                    (int16_t)(gep[19]-gep[17]), (int16_t)(gep[15]-gep[13])));
    *sy = (int16_t)(gep[20] - ge_md((int16_t)(y - gep[14]),
                    (int16_t)(gep[20]-gep[18]), (int16_t)(gep[16]-gep[14])));
}
/* the TRI record (STAGE9-DESIGN.md): near clip the polygon to <=4 verts,
   fan, project+map each vertex, then outline (3 LINEs through the normal
   tail is approximated here by direct screen-space lines between the
   mapped vertices, clamped by the device's own discard) or scanline-fill
   clamped to the viewport, each span the device's height-1 BOXFILL. */
/* screen-space Cohen-Sutherland against the VIEWPORT box, for TRI outlines
   (LINE records keep their window-space clip; both are exact) */
static int ge_soc(int16_t x, int16_t y){
    int c=0;
    if(x<gep[17]) c|=1;
    if(x>gep[19]) c|=2;
    if(y<gep[18]) c|=4;
    if(y>gep[20]) c|=8;
    return c;
}
static void ge_sline(int16_t x0,int16_t y0,int16_t x1,int16_t y1){
    int n=0;
    while(n<8){
        int a=ge_soc(x0,y0), b=ge_soc(x1,y1);
        if(!(a|b)){ gpu_line(x0,y0,x1,y1,gcol); return; }
        if(a&b) return;
        if(!a){ int16_t t; t=x0;x0=x1;x1=t; t=y0;y0=y1;y1=t; a=b; }
        if(a&1){ y0=(int16_t)(y0+ge_md((int16_t)(y1-y0),(int16_t)(gep[17]-x0),(int16_t)(x1-x0))); x0=gep[17]; }
        else if(a&2){ y0=(int16_t)(y0+ge_md((int16_t)(y1-y0),(int16_t)(gep[19]-x0),(int16_t)(x1-x0))); x0=gep[19]; }
        else if(a&4){ x0=(int16_t)(x0+ge_md((int16_t)(x1-x0),(int16_t)(gep[18]-y0),(int16_t)(y1-y0))); y0=gep[18]; }
        else        { x0=(int16_t)(x0+ge_md((int16_t)(x1-x0),(int16_t)(gep[20]-y0),(int16_t)(y1-y0))); y0=gep[20]; }
        n++;
    }
}
static void ge_span(int16_t y, int16_t xl, int16_t xr){
    if(xl > xr){ int16_t t=xl; xl=xr; xr=t; }
    if(xl < gep[17]) xl = gep[17];
    if(xr > gep[19]) xr = gep[19];
    if(xl > xr) return;
    gpu_box(xl, y, xr, y, gcol, 1);           /* the height-1 BOXFILL */
}
static void ge_filltri(int16_t x0,int16_t y0,int16_t x1,int16_t y1,
                       int16_t x2,int16_t y2){
    int16_t tx, ty;
    /* sort ascending by y (stable comparison-swap network) */
    if(y1 < y0){ tx=x0;x0=x1;x1=tx; ty=y0;y0=y1;y1=ty; }
    if(y2 < y1){ tx=x1;x1=x2;x2=tx; ty=y1;y1=y2;y2=ty; }
    if(y1 < y0){ tx=x0;x0=x1;x1=tx; ty=y0;y0=y1;y1=ty; }
    if(y2 == y0){                             /* degenerate: one scanline */
        int16_t lo=x0, hi=x0;
        if(x1<lo)lo=x1; if(x2<lo)lo=x2;
        if(x1>hi)hi=x1; if(x2>hi)hi=x2;
        if(y0 >= gep[18] && y0 <= gep[20]) ge_span(y0, lo, hi);
        return;
    }
    for(int16_t y=y0; ; y++){
        if(y >= gep[18] && y <= gep[20]){
            int16_t xa = (int16_t)(x0 + ge_md((int16_t)(y-y0),
                              (int16_t)(x2-x0), (int16_t)(y2-y0)));
            int16_t xb;
            if(y < y1 || y1 == y0)
                xb = (y1==y0) ? x1
                   : (int16_t)(x0 + ge_md((int16_t)(y-y0),
                              (int16_t)(x1-x0), (int16_t)(y1-y0)));
            else
                xb = (y2==y1) ? x1
                   : (int16_t)(x1 + ge_md((int16_t)(y-y1),
                              (int16_t)(x2-x1), (int16_t)(y2-y1)));
            ge_span(y, xa, xb);
        }
        if(y == y2) break;
    }
}
/* one triangle from WORLD-space int16 vertices (vv[9] = three x,y,z).
   Shared by the record walk (via the byte-decoding ge_tri wrapper) and the
   stage-10 GL interpreter (POLY3's fill fans through here). */
static void ge_tri3(const int16_t *vv, int fill){
    int16_t v[3][3], w[3];
    int16_t pz[8][3]; int np = 0;             /* near-clipped polygon */
    int16_t pq[8][3]; int nq = 0;             /* ...then far-clipped (10b) */
    int16_t sx[8], sy[8];
    int16_t zn=gep[23], zf=gep[24];
    for(int p=0;p<3;p++){
        int16_t in[3];
        for(int k=0;k<3;k++) in[k]=vv[p*3+k];
        ge_xform(in, v[p]);
    }
    if(gep[12] == 0){                         /* ortho: no z clipping */
        for(int p=0;p<3;p++){ pq[nq][0]=v[p][0]; pq[nq][1]=v[p][1]; pq[nq][2]=v[p][2]; nq++; }
    } else {
        for(int p=0;p<3;p++){                 /* clip the polygon vs z=near */
            int16_t *a=v[p], *b=v[(p+1)%3];
            int ain = a[2] >= zn, bin = b[2] >= zn;
            if(ain){ pz[np][0]=a[0]; pz[np][1]=a[1]; pz[np][2]=a[2]; np++; }
            if(ain != bin){
                pz[np][0]=(int16_t)(a[0]+ge_md((int16_t)(b[0]-a[0]),
                            (int16_t)(zn-a[2]),(int16_t)(b[2]-a[2])));
                pz[np][1]=(int16_t)(a[1]+ge_md((int16_t)(b[1]-a[1]),
                            (int16_t)(zn-a[2]),(int16_t)(b[2]-a[2])));
                pz[np][2]=zn; np++;
            }
        }
        if(np < 3) return;                    /* wholly behind */
        for(int p=0;p<np;p++){                /* ...and vs z=far (yon) */
            int16_t *a=pz[p], *b=pz[(p+1)%np];
            int ain = a[2] <= zf, bin = b[2] <= zf;
            if(ain){ pq[nq][0]=a[0]; pq[nq][1]=a[1]; pq[nq][2]=a[2]; nq++; }
            if(ain != bin){
                pq[nq][0]=(int16_t)(a[0]+ge_md((int16_t)(b[0]-a[0]),
                            (int16_t)(zf-a[2]),(int16_t)(b[2]-a[2])));
                pq[nq][1]=(int16_t)(a[1]+ge_md((int16_t)(b[1]-a[1]),
                            (int16_t)(zf-a[2]),(int16_t)(b[2]-a[2])));
                pq[nq][2]=zf; nq++;
            }
        }
        if(nq < 3) return;                    /* wholly beyond */
    }
    w[2]=0;
    for(int p=0;p<nq;p++){ w[0]=pq[p][0]; w[1]=pq[p][1]; w[2]=pq[p][2];
                           ge_map(w, &sx[p], &sy[p]); }
    if(fill){                                 /* fan: (0,1,2) [,(0,2,3)...] */
        for(int t=1;t+1<nq;t++)
            ge_filltri(sx[0],sy[0],sx[t],sy[t],sx[t+1],sy[t+1]);
    } else {
        for(int p=0;p<nq;p++)
            ge_sline(sx[p],sy[p],sx[(p+1)%nq],sy[(p+1)%nq]);
    }
}
/* the transformed-LINE tail: near clip -> perspective divide -> window
   Cohen-Sutherland -> viewport map -> device LINE. w = the two vertices
   AFTER ge_xform. Shared verbatim by the record walk and the stage-10 GL
   interpreter's DRAW3 -- one tail, so the pixels cannot disagree. */
static void ge_line3t(const int16_t *w){
    int16_t x0,y0,z0,x1,y1,z1,d,zn,zf;
    x0=w[0]; y0=w[1]; z0=w[2]; x1=w[3]; y1=w[4]; z1=w[5];
    d = gep[12];
    zn = gep[23]; zf = gep[24];             /* near/far planes (10b: DISTH/
                                               DISTY; defaults 16 / 32767) */
    if(d){                                  /* near clip BEFORE the divide */
        if(z0<zn && z1<zn) return;
        if(z0<zn){
            x0=(int16_t)(x0+ge_md((int16_t)(x1-x0),(int16_t)(zn-z0),(int16_t)(z1-z0)));
            y0=(int16_t)(y0+ge_md((int16_t)(y1-y0),(int16_t)(zn-z0),(int16_t)(z1-z0)));
            z0=zn;
        }
        if(z1<zn){
            x1=(int16_t)(x1+ge_md((int16_t)(x0-x1),(int16_t)(zn-z1),(int16_t)(z0-z1)));
            y1=(int16_t)(y1+ge_md((int16_t)(y0-y1),(int16_t)(zn-z1),(int16_t)(z0-z1)));
            z1=zn;
        }
        if(z0>zf && z1>zf) return;          /* yon clip, same shape */
        if(z0>zf){
            x0=(int16_t)(x0+ge_md((int16_t)(x1-x0),(int16_t)(zf-z0),(int16_t)(z1-z0)));
            y0=(int16_t)(y0+ge_md((int16_t)(y1-y0),(int16_t)(zf-z0),(int16_t)(z1-z0)));
            z0=zf;
        }
        if(z1>zf){
            x1=(int16_t)(x1+ge_md((int16_t)(x0-x1),(int16_t)(zf-z1),(int16_t)(z0-z1)));
            y1=(int16_t)(y1+ge_md((int16_t)(y0-y1),(int16_t)(zf-z1),(int16_t)(z0-z1)));
            z1=zf;
        }
        x0=ge_md(x0,d,z0); y0=ge_md(y0,d,z0);
        x1=ge_md(x1,d,z1); y1=ge_md(y1,d,z1);
    }
    int vis=1, nit=0;                       /* Cohen-Sutherland, lib order */
    while(nit<8){
        int a=ge_oc(x0,y0), b=ge_oc(x1,y1);
        if(!(a|b)) break;
        if(a&b){ vis=0; break; }
        if(!a){ int16_t t; t=x0;x0=x1;x1=t; t=y0;y0=y1;y1=t; a=b; }
        if(a&1){ y0=(int16_t)(y0+ge_md((int16_t)(y1-y0),(int16_t)(gep[13]-x0),(int16_t)(x1-x0))); x0=gep[13]; }
        else if(a&2){ y0=(int16_t)(y0+ge_md((int16_t)(y1-y0),(int16_t)(gep[15]-x0),(int16_t)(x1-x0))); x0=gep[15]; }
        else if(a&4){ x0=(int16_t)(x0+ge_md((int16_t)(x1-x0),(int16_t)(gep[14]-y0),(int16_t)(y1-y0))); y0=gep[14]; }
        else        { x0=(int16_t)(x0+ge_md((int16_t)(x1-x0),(int16_t)(gep[16]-y0),(int16_t)(y1-y0))); y0=gep[16]; }
        nit++;
    }
    if(nit>=8) vis=0;
    if(!vis) return;
    {   /* viewport map, constant denominators, y flips */
        int16_t px0=(int16_t)(gep[17]+ge_md((int16_t)(x0-gep[13]),(int16_t)(gep[19]-gep[17]),(int16_t)(gep[15]-gep[13])));
        int16_t py0=(int16_t)(gep[20]-ge_md((int16_t)(y0-gep[14]),(int16_t)(gep[20]-gep[18]),(int16_t)(gep[16]-gep[14])));
        int16_t px1=(int16_t)(gep[17]+ge_md((int16_t)(x1-gep[13]),(int16_t)(gep[19]-gep[17]),(int16_t)(gep[15]-gep[13])));
        int16_t py1=(int16_t)(gep[20]-ge_md((int16_t)(y1-gep[14]),(int16_t)(gep[20]-gep[18]),(int16_t)(gep[16]-gep[14])));
        gpu_line(px0,py0,px1,py1,gcol);
    }
}

/* ---- Stage 10: the GRAPHICS LANGUAGE ($FF50-$FF57, STAGE10-DESIGN.md) ----
   A PGC-style command STREAM (Matrox PG-640A, docs/reference/pg640a.pdf):
   bytes poked at GLDATA queue in a FIFO; the interpreter executes one
   opcode + parameters (hex mode -- ASCII mode is stage 10d) and draws
   IMMEDIATELY through the exact stage-8b/9 datapath (ge_xform, ge_line3t,
   ge_tri3, and the shared window/viewport/matrix parameter file gep[]),
   so GL pixels and record-engine pixels cannot disagree. PGC opcodes are
   kept verbatim where a verb is adopted (appendix K of the manual stays
   the reference card); P8X-only verbs (FLIP 02, PGSYNC 03) take unused
   opcodes. Parameters are P8X-flavoured: int16 LE wherever the PGC has
   16.16 Reals, and COLOR/CLEARS/FLOOD take r g b bytes -> RGB565 (no
   LUT). The PGC's 2D space has NO matrix: 2D primitives clip to the
   window and map to the viewport, nothing else. Execution is instant
   (the GPU-BUSY licence): GLSTAT busy never reads 1 here, and the FIFO
   drains as far as complete commands allow -- a partial command waits. */
#define GLFMAX 2048          /* holds the largest command: POLY3 255 verts */
static uint8_t glf[GLFMAX];  static int glflen;         /* command FIFO */
static uint8_t glef[16];     static int gleflen;        /* error FIFO */
static uint8_t glrbf[4352];  static int glrblen, glrbrd; /* read-back (10e):
        sized for a full CLRD burst -- the RTL streams through a small
        FIFO with backpressure; instant interpretation is the licence */
static uint8_t glmode;       /* 0 = hex (10a default; 1 = ASCII, stage 10d) */
static char awb[8];  static int awn;      /* keyword accumulator */
static int  axv, axneg, axhas;            /* number accumulator */
static int  a_op, a_bcnt, a_left, a_var, a_vw, a_act, a_pi, a_skip;
static int  a_str;                        /* 10h: 1 = await quote, 2 = in string */
static uint8_t a_sop;                     /* the string verb's opcode */
static uint8_t a_sb[64]; static int a_sn; /* 10k: counted-string buffer --
                                             TJUST needs the length FIRST,
                                             so the per-char emission died */
static uint8_t glfill;       /* PRMFIL: closed primitives fill when 1 */
static int16_t glc2[2], glc3[3];   /* the 2D and 3D current points */
static int16_t glproj, gldist;     /* PROJCT angle / DISTAN viewer distance */
/* stage 10b: the card-side matrices (STAGE10-DESIGN.md). Vertices go
   through ONE combined matrix in the parameter file, recomposed at COMMAND
   time from two masters: v_screen <- project((VR*((M*v>>8)+Tm-r))>>8
   + (0,0,dist)). MD* verbs compose submatrices into M (in command order,
   about the MDORG origin); VW* verbs compose into VR about the VWRPT
   reference point; DISTAN slides the viewer back along z. PROJCT switches
   the focal K from the native 256 to WW*128/tan(angle/2) (TANH8). */
static int16_t glmm[12];     /* modeling: 3x3 8.8 rows 0-8, T 9-11 */
static int16_t glvm[9];      /* viewing rotation VR, 3x3 8.8 */
static int16_t glvrp[3];     /* VWRPT: the viewing reference point */
static int16_t glorg[3];     /* MDORG: rotation/scale pivot */
static int16_t glh, gly;     /* DISTH / DISTY plane distances (from VRP) */
static uint8_t glch, glcy;   /* CLIPH / CLIPY enables */
static uint8_t glpmode;      /* 0 = native focal (par12 as-is); 1 = PROJCT */

/* error codes: 1 unknown opcode, 2 bad parameter, 3 mode not fitted
   (ASCII before stage 10d), 4 command-FIFO overflow */
static void gl_err(uint8_t code){ if(gleflen<(int)sizeof glef) glef[gleflen++]=code; }
/* stage 10e read-back: bytes for the CPU to pop at GLRB (GLSTAT bit 0) */
static void gl_rbb(uint8_t b){ if(glrblen<(int)sizeof glrbf) glrbf[glrblen++]=b; }
static void gl_rbw(int16_t v){ gl_rbb((uint8_t)(v&255)); gl_rbb((uint8_t)((v>>8)&255)); }

static void gl_mat_reset(void){            /* 10b matrix state to power-up */
    memset(glmm,0,sizeof glmm); glmm[0]=glmm[4]=glmm[8]=256;
    memset(glvm,0,sizeof glvm); glvm[0]=glvm[4]=glvm[8]=256;
    memset(glvrp,0,sizeof glvrp); memset(glorg,0,sizeof glorg);
    glh=0; gly=0; glch=0; glcy=0; glpmode=0;
    glproj=60; gldist=0;                   /* dist 0 = the stage-9 camera */
}
static void gl_state_reset(void){          /* RESETF: state, NOT the FIFOs */
    ge_reset();                            /* matrix/window/viewport/flags */
    glfill=0; glc2[0]=glc2[1]=0; glc3[0]=glc3[1]=glc3[2]=0;
    gl_mat_reset();
    gcol=0xFFFF;                           /* pen back to white */
}
static void gl_reset(void){                /* power-on */
    glflen=0; gleflen=0; glrblen=glrbrd=0; glmode=0;
    awn=0; axv=0; axneg=0; axhas=0; a_act=0; a_skip=0; a_str=0;
    glfill=0; glc2[0]=glc2[1]=0; glc3[0]=glc3[1]=glc3[2]=0;
    gl_mat_reset();
}

/* ---- 10b: composition, all in ge_md (the muldiv contract, /256) --------- */
/* out = sub o m: apply m FIRST, then sub -- commands compose on the left
   (MDSCAL then MDTRAN = scale first), the manual's order rule. m12 form:
   rows 0-8 are the 3x3 in 8.8, 9-11 the translation in world units. */
static void gl_mcomp(const int16_t *s, int16_t *m){
    int16_t r[12];
    for(int i=0;i<3;i++){
        for(int j=0;j<3;j++)
            r[i*3+j]=(int16_t)(ge_md(s[i*3+0],m[0*3+j],256)
                              +ge_md(s[i*3+1],m[1*3+j],256)
                              +ge_md(s[i*3+2],m[2*3+j],256));
        r[9+i]=(int16_t)(ge_md(s[i*3+0],m[9],256)
                        +ge_md(s[i*3+1],m[10],256)
                        +ge_md(s[i*3+2],m[11],256)+s[9+i]);
    }
    memcpy(m,r,sizeof r);
}
static void gl_mcomp9(const int16_t *s, int16_t *m){   /* 3x3 only (VR) */
    int16_t r[9];
    for(int i=0;i<3;i++)
        for(int j=0;j<3;j++)
            r[i*3+j]=(int16_t)(ge_md(s[i*3+0],m[0*3+j],256)
                              +ge_md(s[i*3+1],m[1*3+j],256)
                              +ge_md(s[i*3+2],m[2*3+j],256));
    memcpy(m,r,sizeof r);
}
static int16_t gl_sin(int16_t deg){ return SIN8[((deg%360)+360)%360]; }
static int16_t gl_cos(int16_t deg){ return SIN8[((deg%360)+450)%360]; }
/* rotation submatrices, rotate.c's exact row conventions */
static void gl_rsub(int axis, int16_t deg, int16_t *s){
    int16_t c=gl_cos(deg), n=gl_sin(deg);
    memset(s,0,12*sizeof(int16_t));
    if(axis==0){ s[0]=256; s[4]=c; s[5]=(int16_t)-n; s[7]=n; s[8]=c; }
    else if(axis==1){ s[0]=c; s[2]=n; s[4]=256; s[6]=(int16_t)-n; s[8]=c; }
    else { s[0]=c; s[1]=(int16_t)-n; s[3]=n; s[4]=c; s[8]=256; }
}
/* MDROT/MDSCAL pivot about the MDORG origin: T = o - (S*o)>>8 */
static void gl_orgt(int16_t *s){
    for(int i=0;i<3;i++)
        s[9+i]=(int16_t)(glorg[i]-(int16_t)(ge_md(s[i*3+0],glorg[0],256)
                                           +ge_md(s[i*3+1],glorg[1],256)
                                           +ge_md(s[i*3+2],glorg[2],256)));
}
/* rebuild the parameter file from the two masters + projection state */
static void gl_recompose(void){
    int16_t tmr[3];
    for(int i=0;i<3;i++){
        for(int j=0;j<3;j++)
            gep[i*3+j]=(int16_t)(ge_md(glvm[i*3+0],glmm[0*3+j],256)
                                +ge_md(glvm[i*3+1],glmm[1*3+j],256)
                                +ge_md(glvm[i*3+2],glmm[2*3+j],256));
        tmr[i]=(int16_t)(glmm[9+i]-glvrp[i]);
    }
    for(int i=0;i<3;i++)
        gep[9+i]=(int16_t)(ge_md(glvm[i*3+0],tmr[0],256)
                          +ge_md(glvm[i*3+1],tmr[1],256)
                          +ge_md(glvm[i*3+2],tmr[2],256));
    gep[11]=(int16_t)(gep[11]+gldist);      /* viewer slides back on z */
    if(glpmode)                             /* PROJCT: K from angle+window */
        gep[12]=(glproj==0)?0
               :ge_md((int16_t)(gep[15]-gep[13]),128,TANH8[glproj%180]);
    /* hither/yon planes in eye z (plane distances are from the VRP) */
    gep[23]=glch?(int16_t)((gldist+glh)<16?16:(gldist+glh)):16;
    gep[24]=glcy?(int16_t)(gldist+gly):32767;
}

static uint16_t gl_rgb(uint8_t r,uint8_t g,uint8_t b){
    return (uint16_t)(((r&31)<<11)|((g&63)<<5)|(b&31));
}
/* map one WINDOW-space point to the screen -- the ge_line3t formulas */
static void gl_map2(int16_t x,int16_t y,int16_t *px,int16_t *py){
    *px=(int16_t)(gep[17]+ge_md((int16_t)(x-gep[13]),(int16_t)(gep[19]-gep[17]),(int16_t)(gep[15]-gep[13])));
    *py=(int16_t)(gep[20]-ge_md((int16_t)(y-gep[14]),(int16_t)(gep[20]-gep[18]),(int16_t)(gep[16]-gep[14])));
}
/* a 2D line: window-space Cohen-Sutherland (the ge_line3t idiom, minus
   transform and divide), then viewport map, then the device LINE */
static void gl_line2(int16_t x0,int16_t y0,int16_t x1,int16_t y1){
    int vis=1, nit=0;
    while(nit<8){
        int a=ge_oc(x0,y0), b=ge_oc(x1,y1);
        if(!(a|b)) break;
        if(a&b){ vis=0; break; }
        if(!a){ int16_t t; t=x0;x0=x1;x1=t; t=y0;y0=y1;y1=t; a=b; }
        if(a&1){ y0=(int16_t)(y0+ge_md((int16_t)(y1-y0),(int16_t)(gep[13]-x0),(int16_t)(x1-x0))); x0=gep[13]; }
        else if(a&2){ y0=(int16_t)(y0+ge_md((int16_t)(y1-y0),(int16_t)(gep[15]-x0),(int16_t)(x1-x0))); x0=gep[15]; }
        else if(a&4){ x0=(int16_t)(x0+ge_md((int16_t)(x1-x0),(int16_t)(gep[14]-y0),(int16_t)(y1-y0))); y0=gep[14]; }
        else        { x0=(int16_t)(x0+ge_md((int16_t)(x1-x0),(int16_t)(gep[16]-y0),(int16_t)(y1-y0))); y0=gep[16]; }
        nit++;
    }
    if(nit>=8 || !vis) return;
    {   int16_t px0,py0,px1,py1;
        gl_map2(x0,y0,&px0,&py0); gl_map2(x1,y1,&px1,&py1);
        gpu_line(px0,py0,px1,py1,gcol);
    }
}
static void gl_point2(int16_t x,int16_t y){
    int16_t px,py;
    if(ge_oc(x,y)) return;                 /* outside the window */
    gl_map2(x,y,&px,&py);
    gpu_box(px,py,px,py,gcol,1);           /* one pixel: the device PLOT */
}
/* ---- stage 10g: AREA / AREABC -- scanline boundary seed fill --------------
   Fills from the mapped 2D current point with the pen, bounded by `bc`
   (AREABC's colour, or the pen itself for AREA -- the classic boundary
   fill: anything that is neither boundary nor already-pen is interior).
   The EXACT algorithm below -- span probe left then right, paint the
   span, seed one push per interior run on the rows above and below,
   explicit stack, overflow = error 8 with a deterministic partial fill
   -- is the contract: the RTL walker must reproduce it step for step,
   and the SDRAM stack cap (16384 entries) is part of the semantics. */
#define AFCAP 16384
static uint16_t afsx[AFCAP], afsy[AFCAP];
static int gl_af_in(int x,int y,uint16_t bc){
    uint16_t v;
    if(x<0||x>=480||y<0||y>=272) return 0;
    v = gfb[y*gstride+x];
    return v != bc && v != gcol;
}
static void gl_afill(uint16_t bc){
    int sp=0, x, y, L, R, row, i;
    int16_t px, py;
    gmode = 0;                     /* a fill under XOR/AND/... would break
                                      the fill's own invariant (painted ==
                                      pen is the visited mark), so AREA
                                      forces replace mode -- documented */
    gpat = 0xFFFF;                 /* 10j: and the line pattern solid, for
                                      the same reason (spans paint as
                                      device LINEs on the card) */
    if(ge_oc(glc2[0],glc2[1])){ gl_err(2); return; }   /* seed off-window */
    gl_map2(glc2[0],glc2[1],&px,&py);
    if(!gl_af_in(px,py,bc)) return;                    /* seeded on bound */
    afsx[0]=(uint16_t)px; afsy[0]=(uint16_t)py; sp=1;
    while(sp){
        sp--; x=afsx[sp]; y=afsy[sp];
        if(!gl_af_in(x,y,bc)) continue;
        L=x; while(gl_af_in(L-1,y,bc)) L--;
        R=x; while(gl_af_in(R+1,y,bc)) R++;
        gpu_hline(L,R,y,gcol);                         /* paint the span */
        for(row=y-1; row<=y+1; row+=2){
            if(row<0||row>=272) continue;
            i=L;
            while(i<=R){
                if(gl_af_in(i,row,bc)){
                    if(sp>=AFCAP){ gl_err(8); return; }  /* fill overflow */
                    afsx[sp]=(uint16_t)i; afsy[sp]=(uint16_t)row; sp++;
                    while(i<=R && gl_af_in(i,row,bc)) i++;
                } else i++;
            }
        }
    }
}

static void gl_point3(void){
    int16_t w[3]; int16_t x,y;
    ge_xform(glc3,w);
    x=w[0]; y=w[1];
    if(gep[12]){
        if(w[2]<gep[23]) return;           /* behind the near plane */
        if(w[2]>gep[24]) return;           /* beyond the far plane */
        x=ge_md(x,gep[12],w[2]); y=ge_md(y,gep[12],w[2]);
    }
    gl_point2(x,y);
}
static void gl_line3(const int16_t *a,const int16_t *b){
    int16_t w[6];
    ge_xform(a,w); ge_xform(b,w+3);
    ge_line3t(w);
}
/* ---- stage 10c: COMMAND LISTS (STAGE10-DESIGN.md) ---------------------
   256 lists in 4KB slots ($100000 on the board; here a plain array), byte
   length in the slot's first halfword. Recording flows bytes through the
   NORMAL decoder (it must track command boundaries, or a parameter byte
   equal to CLEND's opcode would end a list early) with execution
   suppressed; replay feeds the stored stream back through the same
   interpreter. Nesting is refused (error 5); running an undefined list
   is error 6; outgrowing a slot is error 7 and the recording aborts. */
#define CLSLOT 4096
#define CLNUM  64                      /* 64 lists (P8X cap; PGC had 256) */
static uint8_t clmem[CLNUM][CLSLOT];
static uint8_t cldef[CLNUM];           /* the DEFINED bitmap */
/* stage 10h: the GLYPH bank -- a second 64-slot list bank ($140000 on
   the card). A glyph IS a command list (relative MOVER3/DRAWR3 strokes
   ending in a pen-up advance); TDEFIN records into it through the SAME
   machinery, chars 32..95 (lowercase folds), slot = char - 32. RESETF
   deliberately does NOT clear it: a font is an installed resource. */
static uint8_t glgmem[CLNUM][CLSLOT];
static uint8_t glgdef[CLNUM];
static int     glrec;                  /* recording into slot glrec-1 */
static int     glrbank;                /* recording target: 0 lists, 1 glyphs */
static int     glrlen;                 /* bytes recorded so far */
static int     glreplay;               /* inside a replay (no nesting) */
static int     glgrun;                 /* inside a GLYPH replay (10k) */
static int     tjh = 1, tjv = 1;       /* TJUST: 1 left/bottom 2 centre
                                          3 right/top (10k) */

/* length of the complete command at p (opcode included); 0 = incomplete,
   -1 = unknown opcode. The recorder's command-boundary oracle. */
static int gl_cmdlen(const uint8_t *p, int n){
    int k;
    if(n < 1) return 0;
    switch(p[0]){
    case 0x01: case 0x02: case 0x03: case 0x04: case 0x08: case 0x09:
    case 0x90: case 0xA0: case 0xAF: case 0x71: return 1;
    case 0xE0: case 0xAA: case 0xAB: case 0x70: case 0x72: case 0x74:
    case 0x79: case 0xEB: case 0x61: case 0x62: case 0x76: return 2;
    case 0x63: return 5;                   /* PIXRD x y -> RB */
    case 0xC0: return 1;
    case 0xC1: return 4;                   /* AREABC r g b */
    case 0xEA: return 3;                   /* LINPAT p (10j) */
    case 0x38: return 3;                   /* CIRCLE r (10i) */
    case 0x39: return 5;                   /* ELIPSE rx ry */
    case 0x80: case 0x83:                  /* TEXT / TEXTP: count + chars */
        if(n < 2) return 0;
        return 2 + p[1];
    case 0x81: case 0x82: return 3;        /* TSIZE / TANGLE */
    case 0x84: return 2;                   /* TDEFIN c */
    case 0x85: return 3;                   /* TJUST h v (10k) */
    case 0x78: return 5;                   /* CLMOD n b off */
    case 0x05: case 0x43: case 0x93: case 0x94: case 0x95:
    case 0xA3: case 0xA4: case 0xA5: case 0xA8: case 0xA9:
    case 0xB0: case 0xB1: return 3;
    case 0x06: case 0x07: case 0x0F: case 0x73: return 4;
    case 0x10: case 0x11: case 0x28: case 0x29: case 0x34: case 0x35:
        return 5;
    case 0x12: case 0x13: case 0x2A: case 0x2B:
    case 0x91: case 0x92: case 0x96: case 0xA1:
        return 7;
    case 0xB2: case 0xB3: return 9;
    case 0xA7: return 19;
    case 0x97: return 25;
    case 0x30: case 0x31: case 0x32: case 0x33:
        if(n < 2) return 0;
        k = p[1];
        return 2 + k * ((p[0] & 2) ? 6 : 4);
    default: return -1;
    }
}

static int gl_exec2(const uint8_t *p, int n);

/* replay list `slot` cnt times: the same interpreter, a different byte
   source. WAIT paces on real frames in RTL; instant here (the licence). */
static void gl_replay(int slot, int cnt){
    const uint8_t *base = clmem[slot] + 2;
    int len = clmem[slot][0] | (clmem[slot][1] << 8);
    int pass, off, c;
    glreplay = 1;
    for(pass = 0; pass < cnt; pass++){
        off = 0;
        while(off < len){
            c = gl_exec2(base + off, len - off);
            if(c <= 0) break;
            off += c;
        }
    }
    glreplay = 0;
}

/* one complete command at p[0..]: returns bytes consumed, 0 = incomplete.
   NEED(n) waits for n bytes total (opcode included) before touching state. */
#define NEED(k) do{ if(n<(k)) return 0; }while(0)
static int16_t gl_i16(const uint8_t *p){ return (int16_t)(p[0]|(p[1]<<8)); }
static int gl_exec1(void){ return gl_exec2(glf, glflen); }
static int gl_exec2(const uint8_t *p, int n){
    if(n < 1) return 0;
    if(glrec){                             /* recording: store, don't run */
        int L;
        if(p[0] != 0x71 && p[0] != 0x43){  /* CLEND ends it; the CA/CX mode
                                              switch is TRANSPORT, never
                                              content -- it executes even
                                              mid-recording (a multi-line
                                              gl session re-enters ASCII
                                              between lines) */
            L = gl_cmdlen(p, n);
            if(L == -1){ gl_err(1); return 1; }   /* skipped, not stored */
            if(L == 0 || L > n) return 0;         /* wait for the rest */
            if(p[0]==0x70 || p[0]==0x79 || p[0]==0x72 || p[0]==0x73 ||
               p[0]==0x84){
                gl_err(5); return L;       /* no nesting (TEXT records fine
                                              since 10k -- glyph replay is
                                              its own context) */
            }
            if(glrlen + L > CLSLOT - 2){   /* slot overflow: abort */
                gl_err(7);
                if(glrbank) glgdef[glrec-1]=0; else cldef[glrec-1]=0;
                glrec=0; glrbank=0; return L;
            }
            memcpy((glrbank?glgmem:clmem)[glrec-1] + 2 + glrlen, p, L);
            glrlen += L;
            return L;
        }
    }
    switch(p[0]){
    case 0x70: case 0x79: NEED(2);         /* CLBEG / CLAPP (P8X append) */
        if(glrec || glreplay){ gl_err(5); return 2; }
        if(p[1] >= CLNUM){ gl_err(2); return 2; }
        if(p[0] == 0x79 && !cldef[p[1]]){ gl_err(6); return 2; }
        glrec = p[1] + 1;
        glrlen = (p[0] == 0x79)
               ? (clmem[p[1]][0] | (clmem[p[1]][1] << 8)) : 0;
        cldef[p[1]] = 0;                   /* undefined until CLEND */
        return 2;
    case 0x71:                             /* CLEND (either bank) */
        if(!glrec){ gl_err(5); return 1; }
        (glrbank?glgmem:clmem)[glrec-1][0] = (uint8_t)(glrlen & 255);
        (glrbank?glgmem:clmem)[glrec-1][1] = (uint8_t)(glrlen >> 8);
        (glrbank?glgdef:cldef)[glrec-1] = 1; glrec = 0; glrbank = 0;
        return 1;
    case 0x72: NEED(2);                    /* CLRUN */
        if(glreplay){ gl_err(5); return 2; }
        if(p[1] >= CLNUM){ gl_err(2); return 2; }
        if(!cldef[p[1]]){ gl_err(6); return 2; }
        gl_replay(p[1], 1);
        return 2;
    case 0x73: NEED(4);                    /* CLOOP n count */
        if(glreplay){ gl_err(5); return 4; }
        if(p[1] >= CLNUM){ gl_err(2); return 4; }
        if(!cldef[p[1]]){ gl_err(6); return 4; }
        gl_replay(p[1], (int)(uint16_t)(p[2] | (p[3] << 8)));
        return 4;
    case 0x74: NEED(2);                    /* CLDEL */
        if(p[1] >= CLNUM){ gl_err(2); return 2; }
        cldef[p[1]] = 0; return 2;
    /* ---- stage 10e: read-back ---- */
    case 0x61: NEED(2);                    /* FLAGRD n -> RB (man gl table) */
        switch(p[1]){
        case 1: gl_rbw((int16_t)glfill); break;
        case 2: gl_rbw((int16_t)gcol); break;
        case 3: gl_rbw(glpmode ? glproj : (int16_t)-1); break;
        case 4: gl_rbw(gldist); break;
        case 5: gl_rbw(gep[13]); gl_rbw(gep[15]);       /* WINDOW x1 x2 y1 y2 */
                gl_rbw(gep[14]); gl_rbw(gep[16]); break;
        case 6: gl_rbw(gep[17]); gl_rbw(gep[19]);       /* VWPORT x1 x2 y1 y2 */
                gl_rbw(gep[18]); gl_rbw(gep[20]); break;
        case 9: gl_rbw(gep[23]); gl_rbw(gep[24]); break; /* near, far */
        default: gl_err(2); break;
        }
        return 2;
    case 0x63: NEED(5);                    /* PIXRD x y -> RB: ONE colour.
        The single-interface migration's first verb (2026-08-31): window
        coordinates through the same gl_map2 as every 2D verb, the pixel
        read with the DEVICE's exact rule (unsigned coords, off-screen
        reads 0), the RGB565 colour pushed low-then-high like every
        read-back. The PGC never had a pixel read -- this is P8X's. */
        { int16_t px, py;
          gl_map2(gl_i16(p+1), gl_i16(p+3), &px, &py);
          gl_rbw((int16_t)(((unsigned)(uint16_t)px<(unsigned)gw &&
                            (unsigned)(uint16_t)py<(unsigned)gh)
                           ? gpu_pixel((uint16_t)px,(uint16_t)py) : 0));
        }
        return 5;
    case 0x62: NEED(2);                    /* MATXRD 1|2 -> RB */
        if(p[1] == 1){ int i; for(i=0;i<12;i++) gl_rbw(glmm[i]); }
        else if(p[1] == 2){ int i; for(i=0;i<9;i++) gl_rbw(glvm[i]); }
        else gl_err(2);
        return 2;
    case 0x76: NEED(2);                    /* CLRD n: length then the bytes */
        if(p[1] >= CLNUM){ gl_err(2); return 2; }
        if(!cldef[p[1]]){ gl_err(6); return 2; }
        { int L = clmem[p[1]][0] | (clmem[p[1]][1] << 8); int i;
          gl_rbb(clmem[p[1]][0]); gl_rbb(clmem[p[1]][1]);
          for(i = 0; i < L; i++) gl_rbb(clmem[p[1]][2 + i]); }
        return 2;
    case 0x78: NEED(5);                    /* CLMOD n b off: one-byte patch */
        if(glrec || glreplay){ gl_err(5); return 5; }
        if(p[1] >= CLNUM){ gl_err(2); return 5; }
        if(!cldef[p[1]]){ gl_err(6); return 5; }
        { int off = (uint16_t)(p[3] | (p[4] << 8));
          int L = clmem[p[1]][0] | (clmem[p[1]][1] << 8);
          if(off >= L){ gl_err(2); return 5; }
          clmem[p[1]][2 + off] = p[2]; }
        return 5;
    /* ---- stage 10h/10k: TEXT (glyphs are lists in the second bank).
       TEXTP (83) is the same engine: on the PGC, TEXT was the fixed
       character generator and TEXTP the programmable stroke text --
       P8X text IS stroke text, so both opcodes draw identically.
       TJUST offsets the start point in MODEL units before drawing
       (h: 0/-3n/-6n of the 6-unit advance; v: 0/-3/-7 of the 7-unit
       cap), so the matrix scales and rotates the justification with
       everything else. TEXT runs inside command lists since 10k (the
       glyph replay is its own context); glyph CONTENT may not TEXT. */
    case 0x80: case 0x83:                  /* TEXT / TEXTP count chars */
        if(n < 2) return 0;
        { int L = 2 + p[1]; int i;
          NEED(L);
          if(glgrun){ gl_err(5); return L; }   /* no text inside a glyph */
          if(tjh == 2) glc3[0] = (int16_t)(glc3[0] - 3*p[1]);
          else if(tjh == 3) glc3[0] = (int16_t)(glc3[0] - 6*p[1]);
          if(tjv == 2) glc3[1] = (int16_t)(glc3[1] - 3);
          else if(tjv == 3) glc3[1] = (int16_t)(glc3[1] - 7);
          for(i = 0; i < p[1]; i++){
              int c = p[2+i];
              if(c >= 'a' && c <= 'z') c -= 32;
              c -= 32;
              if(c < 0 || c >= CLNUM || !glgdef[c]) continue; /* no glyph:
                                                    silent skip (a font is
                                                    optional per char) */
              { const uint8_t *b = glgmem[c] + 2;
                int len = glgmem[c][0] | (glgmem[c][1] << 8);
                int off = 0, k, sav = glreplay;
                glreplay = 1; glgrun = 1;  /* glyph content may not nest */
                while(off < len){
                    k = gl_exec2(b + off, len - off);
                    if(k <= 0) break;
                    off += k;
                }
                glreplay = sav; glgrun = 0; }
          }
          return L; }
    case 0x85: NEED(3);                    /* TJUST h v */
        if(p[1] < 1 || p[1] > 3 || p[2] < 1 || p[2] > 3){ gl_err(2); return 3; }
        tjh = p[1]; tjv = p[2];
        return 3;
    case 0x81: NEED(3);                    /* TSIZE s == MDSCAL s s s (8.8) */
        { int16_t sc[12]; memset(sc,0,sizeof sc);
          sc[0]=sc[4]=sc[8]=gl_i16(p+1);
          gl_orgt(sc); gl_mcomp(sc,glmm); gl_recompose(); }
        return 3;
    case 0x82: NEED(3);                    /* TANGLE d == MDROTZ d */
        { int16_t sc[12];
          gl_rsub(2, gl_i16(p+1), sc);
          gl_orgt(sc); gl_mcomp(sc,glmm); gl_recompose(); }
        return 3;
    case 0x84: NEED(2);                    /* TDEFIN c: record a glyph */
        if(glrec || glreplay){ gl_err(5); return 2; }
        { int c = p[1];
          if(c >= 'a' && c <= 'z') c -= 32;
          c -= 32;
          if(c < 0 || c >= CLNUM){ gl_err(2); return 2; }
          glrec = c + 1; glrbank = 1; glrlen = 0; glgdef[c] = 0;
 }
        return 2;
    case 0x01: return 1;                                  /* NOOP */
    case 0x02: ge_flip(); return 1;                       /* FLIP   (P8X) */
    case 0x03: gfb=gfbd; return 1;                        /* PGSYNC (P8X) */
    case 0x04:                                            /* RESETF */
        gl_state_reset();
        memset(cldef, 0, sizeof cldef); glrec = 0; glrbank = 0;
        gpat = 0xFFFF;                 /* 10j: patterns back to solid */
        tjh = 1; tjv = 1;              /* 10k: justification home */
        gmode = 0;                     /* 10f: drawing mode back to replace */
        glrblen = glrbrd = 0;              /* 10e: read-back FIFO clears */
        return 1;
    case 0x05: NEED(3); return 3;      /* WAIT frames: paces on real frame
                                          ticks in RTL; instant here */
    case 0x06: NEED(4); gcol=gl_rgb(p[1],p[2],p[3]); return 4;   /* COLOR */
    case 0x07: NEED(4);                                   /* FLOOD: viewport */
        gpu_box(gep[17],gep[18],gep[19],gep[20],gl_rgb(p[1],p[2],p[3]),1);
        return 4;
    case 0x08: gl_point2(glc2[0],glc2[1]); return 1;      /* POINT */
    case 0xC0: gl_afill(gcol); return 1;                  /* AREA (10g) */
    case 0xC1: NEED(4);                                   /* AREABC r g b */
        gl_afill(gl_rgb(p[1],p[2],p[3])); return 4;
    case 0x09: gl_point3(); return 1;                     /* POINT3 */
    case 0x0F: NEED(4);                    /* CLEARS: BOTH pages, the whole
                                              screen (the sideband lesson) */
        { uint16_t c=gl_rgb(p[1],p[2],p[3]);
          for(size_t i=0;i<gfpix;i++){ gfbmem[0][i]=c; gfbmem[1][i]=c; } }
        return 4;
    case 0x10: NEED(5); glc2[0]=gl_i16(p+1); glc2[1]=gl_i16(p+3); return 5;
    case 0x11: NEED(5);                                   /* MOVER */
        glc2[0]=(int16_t)(glc2[0]+gl_i16(p+1));
        glc2[1]=(int16_t)(glc2[1]+gl_i16(p+3)); return 5;
    case 0x12: NEED(7);                                   /* MOVE3 */
        glc3[0]=gl_i16(p+1); glc3[1]=gl_i16(p+3); glc3[2]=gl_i16(p+5);
        return 7;
    case 0x13: NEED(7);                                   /* MOVER3 */
        glc3[0]=(int16_t)(glc3[0]+gl_i16(p+1));
        glc3[1]=(int16_t)(glc3[1]+gl_i16(p+3));
        glc3[2]=(int16_t)(glc3[2]+gl_i16(p+5)); return 7;
    case 0x28: case 0x29: NEED(5);                        /* DRAW / DRAWR */
        { int16_t x=gl_i16(p+1), y=gl_i16(p+3);
          if(p[0]==0x29){ x=(int16_t)(x+glc2[0]); y=(int16_t)(y+glc2[1]); }
          gl_line2(glc2[0],glc2[1],x,y);
          glc2[0]=x; glc2[1]=y; }
        return 5;
    case 0x2A: case 0x2B: NEED(7);                        /* DRAW3 / DRAWR3 */
        { int16_t b[3];
          b[0]=gl_i16(p+1); b[1]=gl_i16(p+3); b[2]=gl_i16(p+5);
          if(p[0]==0x2B){ b[0]=(int16_t)(b[0]+glc3[0]);
                          b[1]=(int16_t)(b[1]+glc3[1]);
                          b[2]=(int16_t)(b[2]+glc3[2]); }
          gl_line3(glc3,b);
          glc3[0]=b[0]; glc3[1]=b[1]; glc3[2]=b[2]; }
        return 7;
    case 0x30: case 0x31: NEED(2);                        /* POLY / POLYR */
        { int k=p[1];
          NEED(2+4*k);
          if(k==0){ gl_err(2); return 2; }
          { int16_t vx[255], vy[255];
            for(int i=0;i<k;i++){
                vx[i]=gl_i16(p+2+4*i); vy[i]=gl_i16(p+4+4*i);
                if(p[0]==0x31){ vx[i]=(int16_t)(vx[i]+glc2[0]);
                                vy[i]=(int16_t)(vy[i]+glc2[1]); }
            }
            if(glfill && k>=3){        /* fan of viewport-clamped fills */
                int16_t sx[255], sy[255];
                for(int i=0;i<k;i++) gl_map2(vx[i],vy[i],&sx[i],&sy[i]);
                for(int t=1;t+1<k;t++)
                    ge_filltri(sx[0],sy[0],sx[t],sy[t],sx[t+1],sy[t+1]);
            } else {
                for(int i=0;i<k;i++)
                    gl_line2(vx[i],vy[i],vx[(i+1)%k],vy[(i+1)%k]);
            } }
          return 2+4*k; }
    case 0x32: case 0x33: NEED(2);                        /* POLY3 / POLYR3 */
        { int k=p[1];
          NEED(2+6*k);
          if(k==0){ gl_err(2); return 2; }
          { int16_t v[255][3];
            for(int i=0;i<k;i++){
                v[i][0]=gl_i16(p+2+6*i); v[i][1]=gl_i16(p+4+6*i);
                v[i][2]=gl_i16(p+6+6*i);
                if(p[0]==0x33){ v[i][0]=(int16_t)(v[i][0]+glc3[0]);
                                v[i][1]=(int16_t)(v[i][1]+glc3[1]);
                                v[i][2]=(int16_t)(v[i][2]+glc3[2]); }
            }
            if(glfill && k>=3){        /* fan of stage-9 TRIs */
                int16_t vv[9];
                for(int t=1;t+1<k;t++){
                    vv[0]=v[0][0]; vv[1]=v[0][1]; vv[2]=v[0][2];
                    vv[3]=v[t][0]; vv[4]=v[t][1]; vv[5]=v[t][2];
                    vv[6]=v[t+1][0]; vv[7]=v[t+1][1]; vv[8]=v[t+1][2];
                    ge_tri3(vv,1);
                }
            } else {
                for(int i=0;i<k;i++) gl_line3(v[i],v[(i+1)%k]);
            } }
          return 2+6*k; }
    case 0x34: case 0x35: NEED(5);                        /* RECT / RECTR */
        { int16_t x=gl_i16(p+1), y=gl_i16(p+3);
          if(p[0]==0x35){ x=(int16_t)(x+glc2[0]); y=(int16_t)(y+glc2[1]); }
          if(glfill){                  /* map corners, clamp to the viewport */
              int16_t px0,py0,px1,py1,t;
              gl_map2(glc2[0],glc2[1],&px0,&py0); gl_map2(x,y,&px1,&py1);
              if(px0>px1){ t=px0;px0=px1;px1=t; }
              if(py0>py1){ t=py0;py0=py1;py1=t; }
              if(px0<gep[17]) px0=gep[17];
              if(px1>gep[19]) px1=gep[19];
              if(py0<gep[18]) py0=gep[18];
              if(py1>gep[20]) py1=gep[20];
              if(px0<=px1 && py0<=py1)
                  gpu_box(px0,py0,px1,py1,gcol,1);
          } else {
              gl_line2(glc2[0],glc2[1],x,glc2[1]);
              gl_line2(x,glc2[1],x,y);
              gl_line2(x,y,glc2[0],y);
              gl_line2(glc2[0],y,glc2[0],glc2[1]);
          } }
        return 5;
    /* ---- stage 10j: patterns -------------------------------------------
       LINPAT p: the device line pattern (every line from every door --
       glyph strokes included; LINPAT -1 restores solid). AREA forces it
       solid like it forces replace mode (its visited-mark invariant).
       RESETF restores it. AREAPT (E7, patterned fill spans) was REMOVED
       2026-08-30 for placement headroom -- unknown opcode, err1. */
    case 0xEA: NEED(3);                                   /* LINPAT */
        gpat = (uint16_t)(p[1] | (p[2] << 8));
        return 3;
    /* ---- stage 10i: curves (PG-640A ch.4) ------------------------------
       CIRCLE/ELIPSE draw in 2D window space at the current point, like
       RECT, without moving it: radii map through the window->viewport
       scale and draw as the DEVICE ellipse (clipped to the screen, not
       the window -- documented divergence); PRMFIL fills. ARC/SECTOR
       (3C/3D, trig polylines + the SECTOR fan) were REMOVED 2026-08-30
       for placement headroom -- unknown opcodes, err1; software draws
       arcs as short line chains through this same port. */
    case 0x38: case 0x39:                                 /* CIRCLE/ELIPSE */
        { int16_t rx, ry, cxs, cys, rxs, rys;
          if(p[0]==0x38){ NEED(3); rx=ry=gl_i16(p+1); }
          else          { NEED(5); rx=gl_i16(p+1); ry=gl_i16(p+3); }
          if(rx<0 || ry<0){ gl_err(2); return p[0]==0x38?3:5; }
          gl_map2(glc2[0],glc2[1],&cxs,&cys);
          rxs=ge_md(rx,(int16_t)(gep[19]-gep[17]),(int16_t)(gep[15]-gep[13]));
          rys=ge_md(ry,(int16_t)(gep[20]-gep[18]),(int16_t)(gep[16]-gep[14]));
          if(rxs<0) rxs=(int16_t)-rxs;
          if(rys<0) rys=(int16_t)-rys;
          /* the DEVICE is the drawing contract: its radius registers are
             8-bit (clamp at 255 -- still over half the screen), and its
             coordinate registers are unsigned, so an off-window centre
             wraps to a large positive and clips to nothing, exactly as
             the walker writing the same 16 bits would */
          if(rxs>255) rxs=255;
          if(rys>255) rys=255;
          gpu_ellipse((int)(uint16_t)cxs,(int)(uint16_t)cys,rxs,rys,gcol,glfill);
          return p[0]==0x38?3:5; }
    case 0x43: NEED(3);                /* "CA " / "CX ": the mode switches
                                          are their own ASCII bytes in BOTH
                                          modes (the PGC's little joke) */
        if(p[1]=='X' && p[2]==' ') return 3;         /* already hex */
        if(p[1]=='A' && p[2]==' '){ glmode = 1; return 3; } /* -> ASCII */
        gl_err(2); return 3;
    /* ---- stage 10b: the matrix verbs ---------------------------------- */
    case 0x90:                                            /* MDIDEN */
        memset(glmm,0,sizeof glmm); glmm[0]=glmm[4]=glmm[8]=256;
        gl_recompose(); return 1;
    case 0x91: NEED(7);                                   /* MDORG */
        glorg[0]=gl_i16(p+1); glorg[1]=gl_i16(p+3); glorg[2]=gl_i16(p+5);
        return 7;
    case 0x92: NEED(7);                                   /* MDSCAL (8.8) */
        { int16_t s[12]; memset(s,0,sizeof s);
          s[0]=gl_i16(p+1); s[4]=gl_i16(p+3); s[8]=gl_i16(p+5);
          gl_orgt(s); gl_mcomp(s,glmm); gl_recompose(); }
        return 7;
    case 0x93: case 0x94: case 0x95: NEED(3);             /* MDROTX/Y/Z */
        { int16_t s[12];
          gl_rsub(p[0]-0x93, gl_i16(p+1), s);
          gl_orgt(s); gl_mcomp(s,glmm); gl_recompose(); }
        return 3;
    case 0x96: NEED(7);                                   /* MDTRAN */
        { int16_t s[12]; memset(s,0,sizeof s);
          s[0]=s[4]=s[8]=256;
          s[9]=gl_i16(p+1); s[10]=gl_i16(p+3); s[11]=gl_i16(p+5);
          gl_mcomp(s,glmm); gl_recompose(); }
        return 7;
    case 0x97: NEED(25);                                  /* MDMATX: 12 int16 */
        for(int k=0;k<12;k++) glmm[k]=gl_i16(p+1+2*k);
        gl_recompose(); return 25;
    case 0xA0:                                            /* VWIDEN */
        memset(glvm,0,sizeof glvm); glvm[0]=glvm[4]=glvm[8]=256;
        gl_recompose(); return 1;
    case 0xA1: NEED(7);                                   /* VWRPT */
        glvrp[0]=gl_i16(p+1); glvrp[1]=gl_i16(p+3); glvrp[2]=gl_i16(p+5);
        gl_recompose(); return 7;
    case 0xA3: case 0xA4: case 0xA5: NEED(3);             /* VWROTX/Y/Z */
        { int16_t s[12];                     /* the viewer orbits: -angle */
          gl_rsub(p[0]-0xA3, (int16_t)(0-gl_i16(p+1)), s);
          gl_mcomp9(s,glvm); gl_recompose(); }
        return 3;
    case 0xA7: NEED(19);                                  /* VWMATX: 9 int16 */
        for(int k=0;k<9;k++) glvm[k]=gl_i16(p+1+2*k);
        gl_recompose(); return 19;
    case 0xA8: NEED(3); glh=gl_i16(p+1); gl_recompose(); return 3;  /* DISTH */
    case 0xA9: NEED(3); gly=gl_i16(p+1); gl_recompose(); return 3;  /* DISTY */
    case 0xAA: NEED(2); glch=(uint8_t)(p[1]&1); gl_recompose(); return 2;
    case 0xAB: NEED(2); glcy=(uint8_t)(p[1]&1); gl_recompose(); return 2;
    case 0xAF:                                            /* CONVRT */
        { int16_t w3[3]; ge_xform(glc3,w3);
          if(gep[12]){
              int16_t z=w3[2];
              if(z<gep[23]) z=gep[23];       /* clamp, deterministically */
              if(z>gep[24]) z=gep[24];
              glc2[0]=ge_md(w3[0],gep[12],z);
              glc2[1]=ge_md(w3[1],gep[12],z);
          } else { glc2[0]=w3[0]; glc2[1]=w3[1]; } }
        return 1;
    case 0xB0: NEED(3);                                   /* PROJCT */
        { int16_t ang=gl_i16(p+1);
          if(ang<0 || ang>179) gl_err(2);
          else { glproj=ang; glpmode=1; gl_recompose(); } }
        return 3;
    case 0xB1: NEED(3); gldist=gl_i16(p+1); gl_recompose(); return 3;
    case 0xB2: NEED(9);                /* VWPORT x1 x2 y1 y2 -- PGC order */
        gep[17]=gl_i16(p+1); gep[19]=gl_i16(p+3);
        gep[18]=gl_i16(p+5); gep[20]=gl_i16(p+7); return 9;
    case 0xB3: NEED(9);                /* WINDOW x1 x2 y1 y2 -- PGC order */
        gep[13]=gl_i16(p+1); gep[15]=gl_i16(p+3);
        gep[14]=gl_i16(p+5); gep[16]=gl_i16(p+7);
        if(glpmode) gl_recompose();    /* PROJCT's K tracks window width */
        return 9;
    case 0xE0: NEED(2); glfill=(uint8_t)(p[1]&1); return 2;   /* PRMFIL */
    case 0xEB: NEED(2);                                       /* LINFUN */
        if(p[1] > 4){ gl_err(2); return 2; }
        gmode = p[1]; return 2;
    default: gl_err(1); return 1;      /* unknown opcode: log, skip a byte */
    }
}
static void gl_hexb(uint8_t b){
    if(glflen>=GLFMAX){ gl_err(4); return; }
    glf[glflen++]=b;
    for(;;){
        int c=gl_exec1();
        if(c<=0) break;
        memmove(glf,glf+c,(size_t)(glflen-c));
        glflen-=c;
        if(glflen==0) break;
    }
}

/* ---- stage 10d: the ASCII front-end -----------------------------------
   A pure TRANSLATOR: keywords (long or short form, any case) become the
   hex opcode, decimal numbers become parameters at the right width, and
   the result flows into the unchanged hex machinery -- so recording
   stores hex and replay is mode-independent. Grammar: delimiters are
   space/tab/comma/semicolon/CR/LF, '-' negates, no reals (int16 only).
   Recovery is deterministic: a keyword arriving before the previous
   verb's parameters are complete logs error 2 and ZERO-FILLS the rest;
   an excess or orphaned number logs error 2 and is dropped; an unknown
   keyword logs error 1 and swallows its numbers. CA/CX switch modes in
   the translator itself and emit nothing. */

static void gl_aemit(int v){              /* one parameter, right width */
    if(a_pi < a_bcnt) gl_hexb((uint8_t)(v & 255));
    else { gl_hexb((uint8_t)(v & 255)); gl_hexb((uint8_t)((v >> 8) & 255)); }
    if(a_var && a_pi == 0) a_left = (v & 255) * a_vw + 1;
    a_pi++; a_left--;
    if(a_left <= 0) a_act = 0;
}
static void gl_azfill(void){              /* early keyword: complete with 0s */
    gl_err(2);
    while(a_act) gl_aemit(0);
}
static void gl_akw(void){
    int i;
    awb[awn] = 0; awn = 0;
    for(i = 0; i < GLKWN; i++)
        if(strcmp(awb, GLKW[i].kw) == 0) break;
    if(i == GLKWN){                        /* unknown keyword */
        gl_err(1);
        if(a_act) gl_azfill();
        a_skip = 1;
        return;
    }
    if(GLKW[i].op == 0xFE){ glmode = 1; return; }   /* CA */
    if(GLKW[i].op == 0xFF){ glmode = 0; return; }   /* CX */
    if(a_act) gl_azfill();
    if(GLKW[i].arity == 14){               /* string verb (TEXT/TEXTP):
                                              buffered and emitted COUNTED
                                              (TJUST justifies by length,
                                              so the count must lead) */
        a_sop = GLKW[i].op; a_str = 1; a_sn = 0; a_skip = 0;
        return;
    }
    a_skip = 0;
    gl_hexb(GLKW[i].op);
    a_op = GLKW[i].op; a_bcnt = GLKW[i].bcnt; a_pi = 0;
    a_var = (GLKW[i].arity == 15);
    a_vw  = a_var ? ((GLKW[i].op & 2) ? 3 : 2) : 0;
    a_left = a_var ? 1 : GLKW[i].arity;
    a_act = (a_left > 0);
}
static void gl_anum(void){
    int v = axneg ? -axv : axv;
    axv = 0; axneg = 0; axhas = 0;
    if(!a_act){ if(!a_skip) gl_err(2); return; }
    gl_aemit(v);
}
static void gl_ascii(uint8_t b){
    if(a_str == 2){                        /* inside "..." -- verbatim, no
                                              folding, no delimiters */
        int i;
        if(b == '"' || b == 13 || b == 10){
            if(b != '"') gl_err(2);        /* the line ended the string:
                                              emit what arrived, log it */
            gl_hexb(a_sop); gl_hexb((uint8_t)a_sn);
            for(i = 0; i < a_sn; i++) gl_hexb(a_sb[i]);
            a_str = 0; return;
        }
        if(a_sn < 63) a_sb[a_sn++] = b;
        else gl_err(2);                    /* over the 63-char cap: dropped */
        return;
    }
    if(a_str == 1){                        /* awaiting the opening quote */
        if(b == '"'){ a_str = 2; return; }
        if(b == ' ' || b == 9 || b == ',' || b == ';') return;
        gl_err(2); a_str = 0;              /* no string came: verb dropped */
        if(b == 13 || b == 10) return;     /* fall through to process b */
    }
    if(b >= 'a' && b <= 'z') b -= 32;
    if(b == ' ' || b == 9 || b == ',' || b == ';' || b == 13 || b == 10){
        if(awn) gl_akw();
        else if(axhas) gl_anum();
        return;
    }
    if(awn){                               /* inside a keyword */
        if(awn < 7) awb[awn++] = (char)b;
        return;
    }
    if(axhas || b == '-' || (b >= '0' && b <= '9')){
        if(b == '-' && !axhas){ axneg = 1; axhas = 1; return; }
        if(b >= '0' && b <= '9'){ axv = axv * 10 + (b - '0'); axhas = 1; return; }
        gl_err(2); axv = 0; axneg = 0; axhas = 0;    /* junk in a number */
        return;
    }
    if(b >= 'A' && b <= 'Z'){ awb[0] = (char)b; awn = 1; return; }
    gl_err(2);                             /* stray byte */
}

static void gl_push(uint8_t b){
    if(glmode) gl_ascii(b);
    else gl_hexb(b);
}

/* POINT's answer is 16 bits and GDATA is a byte port, so it STREAMS: low byte
   then high, the same idiom as the IDENT record. Reads past the second byte
   return the high byte again (parked), so a sloppy extra read is harmless and
   deterministic. The RTL must match byte order and parking. */
static uint8_t  gpt[2];
static int      gpidx=2;
static const char *gdump=0;            /* -g FILE: write a PPM when the run ends */
static int      gascii=0;              /* -G: also render as text to stderr      */

/* One pixel. Off-screen writes are DISCARDED, not clipped: the coordinate
   registers are 16-bit, so coordinates far past the screen are reachable, and
   "drop the
   pixel" is the one rule that is trivially identical in C and in Verilog. A
   real clipper would have to match exactly, which is a bug waiting to happen. */
/* gmode (declared with the engine state above): stage 10f LINFUN --
   0 replace, 1 complement, 2 OR, 3 AND, 4 XOR. Lines/points/outlines
   only; the raw writer below serves every fill and span. */
static void gpu_pxr(int x,int y,uint16_t c){       /* raw: fills, spans */
    if((unsigned)x>=(unsigned)gw || (unsigned)y>=(unsigned)gh) return;
    gfb[y*gstride+x]=c;
}
static void gpu_px(int x,int y,uint16_t c){
    uint16_t *p;
    if((unsigned)x>=(unsigned)gw || (unsigned)y>=(unsigned)gh) return;
    p = &gfb[y*gstride+x];
    switch(gmode){
    case 1:  *p = (uint16_t)~*p;   break;    /* complement: pen ignored */
    case 2:  *p |= c;              break;
    case 3:  *p &= c;              break;
    case 4:  *p ^= c;              break;
    default: *p = c;               break;    /* replace (5-7 act as 0) */
    }
}
static uint16_t gpu_pixel(int x,int y){     /* colour at (x,y), for the dumps */
    return gfb[y*gstride+x];
}
/* Integer Bresenham, all eight octants, endpoints inclusive. dy is held
   NEGATIVE, which is what lets one error term cover every direction. */
static void gpu_line(int x0,int y0,int x1,int y1,uint16_t c){
    int dx = x1>x0 ? x1-x0 : x0-x1,  sx = x0<x1 ? 1 : -1;
    int dy = y1>y0 ? y0-y1 : y1-y0,  sy = y0<y1 ? 1 : -1;
    int err = dx+dy;
    int pi = 0;
    for(;;){
        if(gpat & (0x8000 >> (pi & 15))) gpu_px(x0,y0,c);
        pi++;
        if(x0==x1 && y0==y1) break;
        int e2 = 2*err;
        if(e2>=dy){ err+=dy; x0+=sx; }
        if(e2<=dx){ err+=dx; y0+=sy; }
    }
}
static void gpu_box(int x0,int y0,int x1,int y1,uint16_t c,int fill){
    int t;
    if(x0>x1){ t=x0; x0=x1; x1=t; }             /* normalise: any two corners */
    if(y0>y1){ t=y0; y0=y1; y1=t; }
    if(fill){
        for(int y=y0;y<=y1;y++) for(int x=x0;x<=x1;x++) gpu_pxr(x,y,c);
        return;
    }
    for(int x=x0;x<=x1;x++){ gpu_px(x,y0,c); gpu_px(x,y1,c); }
    for(int y=y0;y<=y1;y++){ gpu_px(x0,y,c); gpu_px(x1,y,c); }
}
static void gpu_hline(int xa,int xb,int y,uint16_t c){
    for(int x=xa;x<=xb;x++) gpu_pxr(x,y,c);   /* spans always replace */
}
static void gpu_ellipse(int cx,int cy,int rx,int ry,uint16_t c,int fill){
    long rx2 = (long)rx*rx, ry2 = (long)ry*ry;
    long x = 0, y = ry;
    long dx = 0, dy = 2*rx2*(long)ry;
    long err;

    if (rx <= 0 || ry <= 0) return;

    err = 4*ry2 - 4*rx2*(long)ry + rx2;              /* region 1, x4 */
    while (dx < dy) {
        if (fill) {
            gpu_hline(cx-(int)x, cx+(int)x, cy+(int)y, c);
            gpu_hline(cx-(int)x, cx+(int)x, cy-(int)y, c);
        } else {
            gpu_px(cx+(int)x, cy+(int)y, c);  gpu_px(cx-(int)x, cy+(int)y, c);
            gpu_px(cx+(int)x, cy-(int)y, c);  gpu_px(cx-(int)x, cy-(int)y, c);
        }
        x++;  dx += 2*ry2;
        if (err < 0) err += 4*ry2 + 4*dx;
        else { y--; dy -= 2*rx2; err += 4*ry2 + 4*dx - 4*dy; }
    }
    err = ry2*(2*x+1)*(2*x+1) + 4*rx2*(y-1)*(y-1) - 4*rx2*ry2;   /* region 2 */
    while (y >= 0) {
        if (fill) {
            gpu_hline(cx-(int)x, cx+(int)x, cy+(int)y, c);
            gpu_hline(cx-(int)x, cx+(int)x, cy-(int)y, c);
        } else {
            gpu_px(cx+(int)x, cy+(int)y, c);  gpu_px(cx-(int)x, cy+(int)y, c);
            gpu_px(cx+(int)x, cy-(int)y, c);  gpu_px(cx-(int)x, cy-(int)y, c);
        }
        y--;  dy -= 2*rx2;
        if (err > 0) err += 4*rx2 - 4*dy;
        else { x++; dx += 2*ry2; err += 4*dx + 4*rx2 - 4*dy; }
    }
}

/* IDENT builds a fixed 14-byte record that GDATA then streams out, the same
   shape as the CF card's IDENTIFY -> data-port idiom the firmware already
   knows. It carries the GEOMETRY, so software can ask the card how big it is
   instead of assuming: that is what lets one BASIC binary drive both this
   240x136 device and a wider one later. */
static void gpu_ident(void){
    memcpy(gident,"P8X-GFX",7);
    gident[7]=2;                        /* protocol 2: direct colour */
    gident[8]=gw&0xFF; gident[9]=gw>>8;     /* 480 */
    gident[10]=gh&0xFF; gident[11]=gh>>8;   /* 272 */
    gident[12]=0;                       /* pens: 0 = no palette, direct colour */
    gident[13]=16;                      /* bits per pixel -- ask, don't assume */
    gidx=0;                             /* GDATA now streams the record */
}
/* SELFTEST: a fixed pattern drawn entirely from the card's own state, so a
   display with no software behind it can still be proven end to end -- power it
   up, poke one register, and every pen, both drawing primitives and all four
   edges are on screen. Deterministic, so a test can assert on it. */
static void gpu_selftest(void){
    static const uint16_t bar[4]={0x0000,0xF800,0x07E0,0x001F}; /* K R G B */
    memset(gfb,0,gfpix*sizeof *gfb);   /* gfb is a page POINTER now */
    for(int i=0;i<4;i++)                                  /* colour bars */
        gpu_box(i*(gw/4), 0, i*(gw/4)+(gw/4)-1, gh/4, bar[i], 1);
    gpu_box(0,0,gw-1,gh-1,0xFFFF,0);                      /* extreme edges */
    gpu_line(0,0,gw-1,gh-1,0xFFE0);                       /* both diagonals */
    gpu_line(gw-1,0,0,gh-1,0xFFE0);
    gpu_ellipse(gw/2,gh/2,gh/3,gh/3,0x07FF,0);
}
/* SETMODE. Changing mode reinterprets every byte of the framebuffer, so the old
   contents are meaningless -- it clears, and loads the palette that belongs to
   the mode. Loading the palette here rather than sharing one across both is
   what keeps mode 0 exactly as it was: its four pens are the classic
   black/white/red/green, while mode 1 comes up with a 3-3-2 ramp so that a
   program which never touches PALETTE still sees sensible colour.
   Returns 0 on an unknown mode, which the caller turns into GSTAT's ERR bit. */
static void gpu_reset(void){
    gpat = 0xFFFF;                 /* 10j: line pattern to solid */
    memset(gfb,0,gfpix*sizeof *gfb);   /* gfb is a page POINTER now */
    /* The reset pen is WHITE (0xFFFF), because the historical default "pen 1"
       meant white back when there were four pens, and a visible default is the
       one that costs nobody a debugging round. The RTL must match. */
    gx0=gy0=gx1=gy1=0; gcol=0xFFFF; gparm=0; gparm2=0; gerr=0; gidx=GIDLEN;
    gmode=0;
    gpt[0]=gpt[1]=0; gpidx=2;
}
static void gpu_cmd(uint8_t v){
    switch(v){
    case 0x01: gpu_px(gx0,gy0,gcol);                break;   /* PIXELW     */
    case 0x02: gpu_line(gx0,gy0,gx1,gy1,gcol);      break;   /* LINE       */
    case 0x04: gpu_box(gx0,gy0,gx1,gy1,gcol,1);     break;   /* BOXFILL    */
    /* 0x03 (BOX outline), 0x05 (CLS) and 0x07/0x08 (CIRCLE) are RETIRED
       (stage-10 diet): four LINEs, BOXFILL 0,0,479,271 and ELLIPSE rx=ry
       cover them, and the fabric they paid for bought the PGC's curves,
       patterns and text. 0x06 was SETPAL (retired with the palette).
       All of them read as unknown -> ERR now. */
    case 0x0A: gpu_ellipse(gx0,gy0,gparm,gparm2,gcol,0); break; /* ELLIPSE     */
    case 0x0B: gpu_ellipse(gx0,gy0,gparm,gparm2,gcol,1); break; /* ELLIPSEFILL */
    case 0x0C: gpat = (uint16_t)(gparm | (gparm2 << 8)); break;  /* LINPAT (10j):
                                      latch {GPARM2,GPARM} -- the register
                                      map is full, so the pattern rides a
                                      command, like the GL walker writes it */
    /* PIXELR reads a pixel back into GDATA, which is what BASIC's PIXELR()
       function needs. Off-screen reads as pen 0, matching the write side's
       "off-screen simply is not there" rule. */
    case 0x09: { uint16_t p = ((unsigned)gx0<(unsigned)gw && (unsigned)gy0<(unsigned)gh)
                                ? gpu_pixel(gx0,gy0) : 0;
                 gpt[0]=(uint8_t)(p&0xFF); gpt[1]=(uint8_t)(p>>8);
                 gpidx = 0;           /* GDATA now streams low, then high */
                 gidx  = GIDLEN; }    /* and is NOT an IDENT stream */
               break;                                        /* POINT      */
    case 0xF0: gpu_selftest();                      break;   /* SELFTEST   */
    case 0xF1: gpu_reset();                         break;   /* RESET      */
    case 0xF2: gpu_ident();                         break;   /* IDENT      */
    default:   gerr=1; break;         /* unknown command: flagged in GSTAT */
    }
}
/* P6 PPM at PANEL resolution: each framebuffer pixel becomes a 2x2 block, so
   the file shows what the panel shows, not what the framebuffer holds. */
static void gpu_writeppm(const char*fn){
    FILE*f=fopen(fn,"wb");
    if(!f){ perror(fn); return; }
    /* 1:1 -- the framebuffer IS the panel now, no pixel doubling. */
    fprintf(f,"P6\n%d %d\n255\n",gw,gh);
    for(int y=0;y<gh;y++)
        for(int x=0;x<gw;x++){
            /* the DISPLAY page: the dump shows what the panel shows, which
               matters once the geometry engine has flipped */
            uint16_t p=gfbd[y*gstride+x];
            uint8_t r5=(p>>11)&31, g6=(p>>5)&63, b5=p&31;
            /* 565 -> 888 by bit replication, so full scale really is 255 */
            uint8_t rgb[3]={ (uint8_t)((r5<<3)|(r5>>2)),
                             (uint8_t)((g6<<2)|(g6>>4)),
                             (uint8_t)((b5<<3)|(b5>>2)) };
            fwrite(rgb,1,3,f);
        }
    fclose(f);
}
/* Quick eyeball with no image viewer in the loop. Each character covers a 2x4
   block of pixels, which comes out about square once a character cell's own 1:2
   aspect is allowed for, and shows the HIGHEST pen in that block.
   Deliberately not a point sample: sampling every 2nd column and 4th row never
   visits x=239 or y=135 at all, so it silently hid the right and bottom edges
   of a full-screen box -- precisely where an off-by-one would be -- and lost
   isolated pixels like a bare PLOT. A max is the honest reduction here: it can
   make a feature look fatter than it is, but it can never make one vanish.
   Pen 0 prints as blank so the drawing stands out from the background. */
static void gpu_writeascii(void){
    /* Brightness, not pen number: there are no pens. Four levels by a rough
       luminance; the max over the block keeps single pixels from vanishing,
       the same honesty argument as before. */
    static const char lum[5]={' ','.','*','#','@'};
    fputc('+',stderr); for(int i=0;i<gw/2;i++) fputc('-',stderr); fputs("+\n",stderr);
    for(int y=0;y<gh;y+=4){
        fputc('|',stderr);
        for(int x=0;x<gw;x+=2){
            int best=0;
            for(int dy=0;dy<4;dy++) for(int dx=0;dx<2;dx++)
                if(x+dx<gw && y+dy<gh){
                    uint16_t p=gfbd[(y+dy)*gstride+(x+dx)];  /* display page */
                    int v=2*((p>>11)&31)+3*((p>>5)&63)/2+((p)&31);  /* ~0..218 */
                    if(v>best) best=v;
                }
            fputc(lum[best==0?0: best<40?1: best<100?2: best<170?3:4],stderr);
        }
        fputs("|\n",stderr);
    }
    fputc('+',stderr); for(int i=0;i<gw/2;i++) fputc('-',stderr); fputs("+\n",stderr);
}

/* ---- 74181, active-high data. Returns F; *cn4 gets the RAW pin level. */
static uint8_t alu181(uint8_t a,uint8_t b,int s,int m,int cinpin,int*cn4){
    int c = !cinpin;                       /* logical carry-in */
    unsigned r;                            /* arithmetic interpretation of S */
    switch(s){
    case 0x0: r=a; break;                       case 0x1: r=a|b; break;
    case 0x2: r=a|(~b&0xFF); break;             case 0x3: r=0xFF; break;
    case 0x4: r=a+(a&~b&0xFF); break;           case 0x5: r=(a|b)+(a&~b&0xFF); break;
    case 0x6: r=a+(~b&0xFF); break;             case 0x7: r=(a&~b&0xFF)+0xFF; break;
    case 0x8: r=a+(a&b); break;                 case 0x9: r=a+b; break;
    case 0xA: r=(a|(~b&0xFF))+(a&b); break;     case 0xB: r=(a&b)+0xFF; break;
    case 0xC: r=a+a; break;                     case 0xD: r=(a|b)+a; break;
    case 0xE: r=(a|(~b&0xFF))+a; break;         default: r=a+0xFF; break;
    }
    r+=c;
    *cn4 = (r>>8)&1;                       /* rev B: conventional carry-out (1 = carry / A>=B) */
    if(!m) return r&0xFF;
    switch(s){                             /* M=1: logic, carries inhibited */
    case 0x0: return ~a;        case 0x1: return ~(a|b);
    case 0x2: return ~a&b;      case 0x3: return 0;
    case 0x4: return ~(a&b);    case 0x5: return ~b;
    case 0x6: return a^b;       case 0x7: return a&~b;
    case 0x8: return ~a|b;      case 0x9: return ~(a^b);
    case 0xA: return b;         case 0xB: return a&b;
    case 0xC: return 0xFF;      case 0xD: return a|~b;
    case 0xE: return a|b;       default:  return a;
    }
}
static int stdin_pending(void){
    fd_set s; struct timeval tv={0,0}; FD_ZERO(&s); FD_SET(0,&s);
    return select(1,&s,0,0,&tv)>0;
}
static void term_restore(void){ if(g_raw){ tcsetattr(0,TCSANOW,&g_orig); g_raw=0; } }
/* SIGQUIT (Ctrl-\) shows the display WITHOUT ending the run. Dumping only on
   exit makes the graphics almost unusable interactively -- you would have to
   quit and restart to look at every change. With this you draw, peek, and carry
   on in the same session.
   If neither -g nor -G was given, print the text view anyway: someone pressing
   this key wants to SEE something, and doing nothing is a useless answer. */
static void on_show(int s){
    (void)s;
    if(gdump) gpu_writeppm(gdump);
    if(gascii || !gdump) gpu_writeascii();
    signal(SIGQUIT,on_show);          /* stay installed for the next peek */
}
/* Ctrl-C must still produce the display, or -g/-G would be useless for anything
   INTERACTIVE: you drive BASIC by hand, then quit, and quitting is a signal.
   fopen/fwrite in a handler is not strictly async-signal-safe, but this is a
   debug emulator that is already calling tcsetattr here, and the alternative is
   a feature that only works on scripted runs. */
static void on_sig(int s){
    (void)s;
    term_restore();
    if(gdump) gpu_writeppm(gdump);
    if(gascii) gpu_writeascii();
    _exit(0);
}
/* console RX status (RDRF). Must NOT block: the ACIA status register also
   carries TDRE, which PUTC polls before every transmitted byte, so a blocking
   status read would stall all output until a key is pressed. It is therefore
   non-blocking; but to keep an idle prompt from spinning the host CPU at 100%,
   after RX_SPIN consecutive "no key, no output" polls we block for one key.
   Any console output (memwr $FF05) resets the counter, so transmit and bulk
   output never block. */
#define RX_SPIN 4000
static long rx_misses=0;
static int rx_ready(void){
    /* -N: report "no key, ever". The FPGA co-sim needs this: p8x_soc.v models
       $FF04 as a constant 0x02 (TDRE set, RDRF clear), and without -N the golden
       trace depends on what stdin happens to be. A TTY with no keystrokes reports
       not-ready, but a redirected/closed stdin (/dev/null, a script, CI) is at EOF,
       which select() calls readable — so RDRF reads back set and the RTL "diverges"
       at the first ACIA status poll. Same run, different shell, different trace. */
    /* -i: RDRF is exactly "the script still has a byte" -- no host timing in it,
       so the FPGA co-sim can mirror the rule in RTL and step identically. */
    if(scr) return scrpos<scrlen;
    if(norx) return 0;
    if(!interactive) return stdin_pending();
    if(peeked>=0) return 1;
    if(stdin_pending()){
        unsigned char c;
        if(read(0,&c,1)==1){ peeked=c; rx_misses=0; return 1; }
        term_restore(); exit(0);        /* EOF / error */
    }
    if(++rx_misses < RX_SPIN) return 0;  /* report "no key" and keep polling */
    rx_misses=0;                         /* idle: block for a key (no spin) */
    unsigned char c;
    if(read(0,&c,1)==1){ peeked=c; return 1; }
    term_restore(); exit(0);
}
static int rx_char(void){
    if(scr) return scrpos<scrlen ? scr[scrpos++] : 0;   /* -i: consume one byte */
    if(norx) return 0;                  /* -N: never any data behind RDRF */
    if(peeked>=0){ int c=peeked; peeked=-1; return c; }
    if(!interactive){ int ch=getchar(); return ch<0?0:ch; }
    unsigned char c;
    if(read(0,&c,1)==1) return c;
    term_restore(); exit(0);
}
/* ---- stage CARD-EDGE: the -B bridge client ------------------------------
   With -B <tty>, every access to the CARD WINDOWS -- the 2D device
   ($FF20-$FF2F) and the GL port ($FF50-$FF57) -- is forwarded over the
   serial card-edge protocol (CARD-EDGE-DESIGN.md; the C twin of
   glbridge.py) to a REAL graphics card. Everything else (CPU, RAM,
   storage, console, MDU) stays local. The local framebuffer is never
   painted in this mode: pixels exist on the card's panel, POINT reads
   come back over the wire, and -g dumps stay black by design.
   GLDATA writes go as single WRITEs -- the running P8X software already
   polls GLSTAT bit7, exactly as it would on the real bus. */
static int bridge_fd = -1;
/* GLDATA write batching: the running software polls GLSTAT bit7 before
   every byte (correct against the real bus, ruinous over serial -- two
   round trips per payload byte). The client buffers GLDATA writes and
   ships them as the protocol's ack'd 64-byte BURSTs, whose ack IS the
   flow control; while bytes are pending, a GLSTAT read is answered
   LOCALLY as busy-not-full ($40) -- truthful (the card owes us work,
   the buffer accepts more) and poll-free. The buffer flushes on 64
   bytes, on ANY other card access (an ordering barrier), or when a
   GLSTAT poll finds it aged past BRIDGE_FLUSH_AGE cycles (the drain
   loop after a stream spins polls without writes -- age is what turns
   its synthetic busy into a flush and real answers). Same bytes, same
   order, same semantics; the wire cost drops from ~4x to ~1.03x. */
static uint8_t bridge_buf[64];
static int     bridge_bn = 0;
static unsigned long long bridge_bage = 0;
#define BRIDGE_FLUSH_AGE 20000
#define cycles_now() (cycles)
static uint8_t bridge_recv1(void);
static void bridge_flush(void){
    uint8_t hdr[2];
    if(bridge_bn == 0) return;
    hdr[0]=0x01; hdr[1]=(uint8_t)bridge_bn;
    if(write(bridge_fd,hdr,2)!=2 ||
       write(bridge_fd,bridge_buf,bridge_bn)!=bridge_bn){
        perror("bridge burst"); exit(1);
    }
    bridge_bn = 0;
    if(bridge_recv1()!=0x06){
        fprintf(stderr,"p8xemu: bridge burst not acked\n"); exit(1);
    }
}
static int bridge_card(uint16_t ad){
    return (ad>=0xFF20&&ad<=0xFF2F) || (ad>=0xFF50&&ad<=0xFF57);
}
static uint8_t bridge_recv1(void){
    uint8_t b; int n; int spins=0;
    for(;;){
        n=read(bridge_fd,&b,1);
        if(n==1) return b;
        if(++spins>2000000){
            fprintf(stderr,"p8xemu: bridge silent -- card detached?\n");
            exit(1);
        }
    }
}
static void bridge_wr(uint16_t ad,uint8_t v){
    uint8_t m[2];
    if(ad==0xFF50){                        /* GLDATA: batch into bursts */
        if(bridge_bn==0) bridge_bage=cycles_now();
        bridge_buf[bridge_bn++]=v;
        if(bridge_bn==64) bridge_flush();
        return;
    }
    bridge_flush();                        /* ordering barrier */
    m[0]=(uint8_t)(0x80|((ad-0xFF20)&0x3F)); m[1]=v;
    if(write(bridge_fd,m,2)!=2){ perror("bridge write"); exit(1); }
}
static uint8_t bridge_rd(uint16_t ad){
    uint8_t m;
    if(ad==0xFF51 && bridge_bn){           /* GLSTAT with bytes pending */
        if(cycles_now()-bridge_bage < BRIDGE_FLUSH_AGE)
            return 0x40;                   /* busy, not full: keep pushing */
        bridge_flush();                    /* aged out: drain wants truth */
    } else bridge_flush();                 /* ordering barrier */
    m=(uint8_t)(0x40|((ad-0xFF20)&0x3F));
    if(write(bridge_fd,&m,1)!=1){ perror("bridge write"); exit(1); }
    return bridge_recv1();
}

static uint8_t memrd(uint16_t ad){
    if(ad<RAMBASE) return eeprom[ad];
    if(ad<IOBASE) return ram[ad-RAMBASE];
    if(bridge_fd>=0 && bridge_card(ad)) return bridge_rd(ad);
    switch(ad){
    case 0xFF00: return switches;                             /* switches (-s) */
    case 0xFF04: return 0x02 | (rx_ready()?0x01:0x00);        /* TDRE|RDRF */
    case 0xFF05: return rx_char();
    case 0xFF10: return cf[cf_active].img? cf_data_rd(&cf[cf_active]) : 0xFF;  /* CF data */
    case 0xFF17: return cf[cf_active].img?                                     /* CF status */
                        (0x40|(cf[cf_active].drq?0x08:0)|(cf[cf_active].err?0x01:0)) : 0xFF;
    /* GPU. BUSY is never set here: drawing is instantaneous, the same licence
       the CF model takes with BSY. The RTL engine does raise it, and software
       must poll -- so BASIC will spin on GSTAT even though it never spins here. */
    case GSTAT:  return (uint8_t)(gerr?0x01:0x00);
    case GDATA:  if (gidx<GIDLEN) return gident[gidx++];
                 if (gpidx<2)     return gpt[gpidx++];
                 return gpt[1];                /* parked on the high byte */
    case GID0:   return 0x50;                      /* 'P' */
    case GID1:   return 0x47;                      /* 'G' -- "PG", not a floating $FF */
    /* MDU reads. Instant, so MDSTAT is never busy (see the mdu_exec note). */
    case MDQ:    return (uint8_t)(mdq & 0xFF);
    case MDQH:   return (uint8_t)(mdq >> 8);
    case MDSTAT: return 0x00;
    case MDID:   return 0x4D;                      /* 'M' -- presence probe */
    /* The $FF40 record-engine window is RETIRED (stage 10b): reads float
       to $FF like any absent card, so lib_g3d's GEID probe falls back. */
    /* Stage 10 GL port. busy (bit6) never reads 1: interpretation is
       instant, the same licence as GPU BUSY / GESTAT above. */
    case GLSTAT: return (uint8_t)((glflen>=GLFMAX?0x80:0) |
                                  (gleflen?0x02:0) |
                                  (glrblen>glrbrd?0x01:0));
    case GLRB:   return (uint8_t)(glrblen>glrbrd ? glrbf[glrbrd++] : 0);
    case GLERR:  if(gleflen){ uint8_t e=glef[0];
                              memmove(glef,glef+1,(size_t)--gleflen);
                              return e; }
                 return 0;
    case GLID:   return 0x47;                      /* 'G' -- presence probe */
    default: return 0xFF;
    }
}
static void memwr(uint16_t ad,uint8_t v){
    if(ad<RAMBASE){ fprintf(stderr,"[warn] write to EEPROM %04X\n",ad); return; }
    if(ad<IOBASE){ ram[ad-RAMBASE]=v; return; }
    if(bridge_fd>=0 && bridge_card(ad)){ bridge_wr(ad,v); return; }
    if(ad==0xFF02){                                          /* LEDs */
        if(led_trace && v!=leds)                 /* cycle-stamped: POKE 65282,n
                                                    brackets time a code span */
            fprintf(stderr,"[LED $FF02 @%llu] $%02X  %c%c%c%c%c%c%c%c\n", cycles, v,
                (v&0x80)?'*':'.',(v&0x40)?'*':'.',(v&0x20)?'*':'.',(v&0x10)?'*':'.',
                (v&0x08)?'*':'.',(v&0x04)?'*':'.',(v&0x02)?'*':'.',(v&0x01)?'*':'.');
        leds=v; return;
    }
    if(ad==0xFF06){ irq_pending=1; return; }   /* rev C: raise a maskable IRQ (models a device) */
    if(ad==0xFF05){ putchar(v); fflush(stdout); rx_misses=0; return; }
    if(ad==0xFF16){ cf_active=v&1; return; }  /* CFHEAD: ATA device select (bit 0) */
    /* GPU: the coordinate/pen registers just latch; writing GCMD executes.
       A low-byte write CLEARS the matching high byte -- see the note by the
       register declarations -- so 8-bit software can never inherit a stale one. */
    switch(ad){
      case GX0:  gx0=v;  return;
      case GY0:  gy0=v;  return;
      case GX1:  gx1=v;  return;
      case GY1:  gy1=v;  return;
      case GX0H: gx0=(uint16_t)((gx0&0xFF)|(v<<8)); return;
      case GY0H: gy0=(uint16_t)((gy0&0xFF)|(v<<8)); return;
      case GX1H: gx1=(uint16_t)((gx1&0xFF)|(v<<8)); return;
      case GY1H: gy1=(uint16_t)((gy1&0xFF)|(v<<8)); return;
      case GCOL: gcol=v; return;             /* low write CLEARS the high byte */
      case GCOLH:gcol=(uint16_t)((gcol&0xFF)|(v<<8)); return;
      case GPARM: gparm=v;  return;
      case GPARM2:gparm2=v; return;
      case GMODE: gmode=(uint8_t)(v&7); return;   /* 10f: pixel-write mode */
      case GCMD: gerr=0; gpu_cmd(v); return;
    }
    /* MDU writes: pairs latch (low write clears high), MDGO computes. */
    switch(ad){
      case MDA:  mda=v; return;
      case MDB:  mdb=v; return;
      case MDC:  mdc=v; return;
      case MDAH: mda=(uint16_t)((mda&0xFF)|(v<<8)); return;
      case MDBH: mdb=(uint16_t)((mdb&0xFF)|(v<<8)); return;
      case MDCH: mdc=(uint16_t)((mdc&0xFF)|(v<<8)); return;
      case MDGO: mdq=mdu_exec(mda,mdb,mdc); return;
    }
    /* Geometry engine writes (stage 8b): the indexed parameter file, the
       list upload, and the three commands. GEVAL low latches; GEVALH
       commits reg[GESEL] and auto-increments, so a matrix uploads as one
       GESEL poke + 24 GEVAL pokes. */
    switch(ad){
      case GLDATA: gl_push(v); return;   /* stage 10: one command-stream byte */
    }
    /* The ATA task-file (feature + LBA) is a SHARED bus: both drives latch these
       writes; the CFHEAD DEV bit picks who executes the command. Mirror them to
       both devices so a drive switch after loading the LBA still sees it (the
       firmware writes CFLBAx before CFHEAD in CFSETL). Data/command route to the
       device selected at command time. */
    switch(ad){
      case 0xFF11: cf[0].feat=cf[1].feat=v; return;
      case 0xFF13: cf[0].lba0=cf[1].lba0=v; return;
      case 0xFF14: cf[0].lba1=cf[1].lba1=v; return;
      case 0xFF15: cf[0].lba2=cf[1].lba2=v; return;
      /* FF12 sector-count: accepted, single-sector model */
    }
    { struct cf_state *c=&cf[cf_active];
      if(c->img) switch(ad){
      case 0xFF10: cf_data_wr(c,v); return;
      case 0xFF17: cf_cmd(c,v); return;
      } }
}
static void load(const char*fn,uint8_t*buf,size_t n){
    FILE*f=fopen(fn,"rb");
    if(!f){perror(fn);exit(1);}
    fread(buf,1,n,f); fclose(f);
}
static void cf_attach(struct cf_state*c,const char*fn){   /* open/create a CF image */
    c->img=fopen(fn,"r+b");
    if(!c->img){                                /* create + zero-fill 256 sectors */
        c->img=fopen(fn,"w+b");
        if(!c->img){ perror(fn); exit(1); }
        static uint8_t z[512]={0};
        for(int s=0;s<256;s++) fwrite(z,1,512,c->img);
        fflush(c->img);
    }
}
int main(int argc,char**argv){
    const char*ee="eeprom.bin"; const char*cfn=0,*cfn2=0; unsigned long long lim=200000000ULL;
    ge_reset();                          /* geometry engine power-on state */
    gl_reset();                          /* stage 10 GL power-on state */
    gfb_poweron();                       /* both pages: undefined, like DRAM */
    int lim_set=0;                       /* -l given explicitly: always honour it */
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"-t")) trace=1;
        else if(!strcmp(argv[i],"-T")) mtrace=1;   /* canonical machine trace (co-sim) */
        else if(!strcmp(argv[i],"-l")){ lim=strtoull(argv[++i],0,0); lim_set=1; }
        else if(!strcmp(argv[i],"-c")) cfn=argv[++i];
        else if(!strcmp(argv[i],"-c2")) cfn2=argv[++i];   /* 2nd CF (drive 1) */
        else if(!strcmp(argv[i],"-s")) switches=(uint8_t)strtoul(argv[++i],0,0);  /* $FF00 input byte */
        else if(!strcmp(argv[i],"-L")) led_trace=1;                               /* trace $FF02 writes */
        else if(!strcmp(argv[i],"-N")) norx=1;     /* console RX always empty (FPGA co-sim) */
        else if(!strcmp(argv[i],"-B")){            /* card-edge bridge client */
            const char *bdev=argv[++i];
            struct termios bt;
            bridge_fd=open(bdev,O_RDWR|O_NOCTTY|O_NONBLOCK);
            if(bridge_fd<0){ perror(bdev); return 1; }
            if(tcgetattr(bridge_fd,&bt)==0){
                cfmakeraw(&bt);
                cfsetispeed(&bt,B115200); cfsetospeed(&bt,B115200);
                bt.c_cc[VMIN]=0; bt.c_cc[VTIME]=0;
                tcsetattr(bridge_fd,TCSANOW,&bt);
            }
            /* RESYNC: a previous host may have died mid-command, leaving
               the card's FSM expecting operands. 66 zero bytes complete
               any partial command (a dangling burst swallows them as
               GLDATA noise -- harmless, drained below), then everything
               is PINGs. Flush the reply junk, then do one clean PING. */
            { uint8_t z[66]={0}; struct timespec ts={0,100000000};
              write(bridge_fd,z,sizeof z);
              nanosleep(&ts,0);
              { uint8_t junk[256]; while(read(bridge_fd,junk,sizeof junk)>0){} }
            }
            /* PING: refuse to run against the wrong personality */
            { uint8_t p=0x00, r[5]; int got=0;
              if(write(bridge_fd,&p,1)!=1){ perror("bridge"); return 1; }
              while(got<5) r[got++]=bridge_recv1();
              if(memcmp(r,"P8XG",4)!=0){
                  fprintf(stderr,"p8xemu: -B device is not a graphics card "
                          "(PING got %02X %02X %02X %02X)\n",r[0],r[1],r[2],r[3]);
                  return 1;
              }
              fprintf(stderr,"[bridge: graphics card protocol v%d on %s]\n",r[4],bdev);
            }
            /* GL-WALKER RESYNC (2026-09-01, found the hard way): the
               zeros above resync the BRIDGE framing, but the WALKER
               keeps its own stream state across host sessions -- a
               session killed between an opcode and its parameters
               leaves the walker waiting, and the next session's first
               bytes get EATEN as the phantom command's operands (seen
               as GLSTAT busy stuck 1 + an error FIFO full of err1).
               One BURST of 64 zero GLDATA bytes completes any phantom
               (zeros are harmless: operands of the phantom, then err1
               skips), then the error FIFO is drained clean. */
            { uint8_t frame[66]; int k;
              frame[0]=0x01; frame[1]=64;
              memset(frame+2,0,64);
              if(write(bridge_fd,frame,66)==66 && bridge_recv1()==0x06){
                  for(k=0;k<24;k++){            /* drain GLERR (reg $33) */
                      uint8_t rd=0x40|0x33, e;
                      if(write(bridge_fd,&rd,1)!=1) break;
                      e=bridge_recv1();
                      if(e==0) break;
                  }
              } else fprintf(stderr,"p8xemu: bridge GL resync burst "
                                    "not acked -- card may be wedged\n");
            }
        }
        else if(!strcmp(argv[i],"-g")) gdump=argv[++i];   /* write the display as a PPM */
        else if(!strcmp(argv[i],"-G")) gascii=1;          /* ... and/or as text to stderr */
        else if(!strcmp(argv[i],"-i")){            /* scripted console input (FPGA co-sim) */
            FILE*sf=fopen(argv[++i],"rb");
            if(!sf){ fprintf(stderr,"p8xemu: cannot open input script %s\n",argv[i]); return 1; }
            fseek(sf,0,SEEK_END); scrlen=ftell(sf); fseek(sf,0,SEEK_SET);
            scr=malloc(scrlen?scrlen:1);
            if(scrlen && fread(scr,1,scrlen,sf)!=(size_t)scrlen){ fprintf(stderr,"p8xemu: short read on input script\n"); return 1; }
            fclose(sf);
        }
        else if(!strcmp(argv[i],"-h")||!strcmp(argv[i],"--help")){
            fprintf(stderr,"usage: p8xemu [-t] [-T] [-N] [-l cycles] [-c disk.img] [-c2 disk2.img] "
                "[-s switches] [-L] [-g out.ppm] [-G] [rom.bin]\n"
                "  -T     canonical per-cycle machine trace to stderr (FPGA co-sim)\n"
                "  -N     console RX always empty; makes -T traces independent of stdin\n"
                "  -i F   scripted console input from file F (RDRF = bytes remain)\n"
                "  -s NN  value read at $FF00 (e.g. -s 0xA5); default 0\n"
                "  -L     print $FF02 LED writes to stderr as they change\n"
                "  -g F   write the 240x136 display to F as a PPM when the run ends\n"
                "  -G     render the display as text to stderr when the run ends\n"
                "  -t trace  -l limit cycles  -c attach CF drive 0  -c2 attach CF drive 1\n");
            return 0;
        }
        else ee=argv[i];
    }
    char fn[64];
    for(int k=0;k<4;k++){ sprintf(fn,"u%d.bin",k); load(fn,rom[k],8192); }
    load(ee,eeprom,ROMSIZE);
    /* Installed for EVERY run, not just interactive ones: the default action for
       SIGQUIT is to kill the process, so a scripted run would die on a peek. */
    signal(SIGQUIT,on_show);            /* Ctrl-\ : show the display, keep going */
    if(cfn)  cf_attach(&cf[0],cfn);                 /* attach CF disk images */
    if(cfn2) cf_attach(&cf[1],cfn2);
    /* -N / -i mean the console is disabled or scripted, so this is a batch run
       (the FPGA co-sim): do not seize the terminal and do not lift the cycle cap,
       even when launched from a shell. Without this guard a `-T` run started from
       a TTY ignores -l and streams a trace line per cycle until the disk fills. */
    if(!norx && !scr && isatty(0) && tcgetattr(0,&g_orig)==0){   /* interactive console */
        interactive=1;
        struct termios t=g_orig;
        t.c_lflag &= ~(ICANON|ECHO);                /* char-at-a-time, BASIC echoes */
        t.c_iflag &= ~(ICRNL);                      /* Enter -> CR (not NL) */
        t.c_cc[VMIN]=1; t.c_cc[VTIME]=0;
        tcsetattr(0,TCSANOW,&t); g_raw=1;
        atexit(term_restore);
        signal(SIGINT,on_sig); signal(SIGTERM,on_sig);
        if(!lim_set) lim=~0ULL;   /* no cycle cap while typing -- unless -l was asked for */
    }
    P[0]=0; P[1]=P[2]=0; P[3]=0xFEFF; P[4]=P[5]=0; stp=0; IR=0;   /* reset: P0 forced 0 */
    while(!halted && cycles<lim){
        /* condition mux: FCOND of the word currently in the pipeline */
        int cond;
        switch(prev_fcond){
        case 1: cond=1; break;       case 2: cond=fC; break;
        case 3: cond=fZ; break;      case 4: cond=fN; break;
        case 5: cond=fV; break;
        case 6: cond=fN^fV; break;            /* signed less-than (BLT) */
        case 7: cond=(fN^fV)|fZ; break;       /* signed less-or-equal (BLE) */
        default: cond=0;
        }
        int ad = IR | stp<<8 | cond<<12;
        uint32_t cw = rom[0][ad] | rom[1][ad]<<8 | rom[2][ad]<<16
                    | ((uint32_t)rom[3][ad])<<24;
        int doe=cw&15, dld=(cw>>4)&15, psel=(cw>>8)&7;   /* PSEL now 3 bits (P0-P3 + PT=4) */
        int pinc=(cw>>11)&1, pdec=(cw>>12)&1, alus=(cw>>13)&15;
        int m=(cw>>17)&1, cinp=(cw>>18)&1, sh0=(cw>>19)&1, sh1=(cw>>20)&1;
        int ldf=(cw>>21)&1, fcond=(cw>>22)&7, urst=(cw>>25)&1, halt=(cw>>26)&1;
        int ldzn=(cw>>27)&1, shcin=(cw>>28)&1, setc=(cw>>29)&1, clrc=(cw>>30)&1;
        int bsel=(cw>>31)&1;                                 /* ALU B-input mux: 0=B reg, 1=T reg */
        /* combinational ALU + shifter from CURRENT register state */
        uint8_t bop = bsel ? T : B;                          /* B-side operand (2nd ALU-input mux) */
        int cout; uint8_t f=alu181(A,bop,alus,m,cinp,&cout); /* cout = conventional carry */
        int sin = shcin ? (fC&1) : 0;                        /* shift-in: C for rotate, else 0 */
        uint8_t g = sh0 ? (uint8_t)((f<<1)|sin) : f;         /* stage 1: left  */
        uint8_t r = sh1 ? (uint8_t)((g>>1)|(sin<<7)) : g;    /* stage 2: right */
        int shout = sh0 ? ((f>>7)&1) : (sh1 ? (f&1) : 0);    /* bit shifted out */
        int nC = (sh0||sh1) ? shout : cout;                  /* shift ops latch shifted-out bit */
        int nZ=(r==0), nN=(r>>7)&1;
        /* V (signed overflow), sign-bit method — matches the ALU-card net exactly
         * (U34 XOR + U35 AND): V = (A7 ^ F7) & (A7 ^ B7 ^ isADD), isADD = ~ALUS2
         * (add-like ops have S2=0: ADD=1001, INC=0000; sub-like S2=1: SUB=0110,
         * DEC=1111). F7 is the raw ALU result sign (pre-shifter). Ungated by M, so
         * defined for every op but only MEANINGFUL after ADD/SUB/CMP — the signed
         * branches are documented for use after CMP. */
        int a7=(A>>7)&1, b7=(bop>>7)&1, f7=(f>>7)&1, isadd=!((alus>>2)&1);
        int nV = (a7^f7) & (a7^b7^isadd);
        uint16_t addr=P[psel];
        /* bus source */
        uint8_t bus=0xFF;
        switch(doe){
        case 1: bus=A; break;   case 2: bus=B; break;
        case 3: bus=T; break;   case 4: bus=T2; break;
        case 5: bus=r; break;
        case 6: bus=fC|fZ<<1|fN<<2|fV<<3; break;
        case 7: bus=memrd(addr); break;
        case 8: bus=addr&0xFF; break;  case 9: bus=addr>>8; break;
        }
        /* rev C interrupt forcing buffer. At fetch (step 0) with IE set and an IRQ
         * pending, it injects opcode $08 (overriding the memory read) and the
         * interrupt is acknowledged (pending clear, IE masked). While the $08
         * micro-routine runs with DOE=idle it drives $08 again, so the two PTR
         * loads build P0 = $0808 (the ROM vector). */
        if(stp==0 && doe==7 && IE && irq_pending){ bus=0x08; irq_pending=0; IE=0; }
        else if(IR==0x08 && doe==0) bus=0x08;
        if(mtrace)   /* canonical per-cycle state line -> stderr; matches tb_p8x.v */
            fprintf(stderr,"%llu %02x %x %02x %02x %02x %02x "
                    "%04x %04x %04x %04x %04x %04x %d%d%d%d\n",
                    cycles,IR,stp,A,B,T,T2,P[0],P[1],P[2],P[3],P[4],P[5],
                    fC,fZ,fN,fV);
        if(trace)
            printf("%9llu IR=%02X st=%X cd=%d | DOE=%X DLD=%X P%d=%04X "
                   "bus=%02X A=%02X B=%02X T=%02X%02X F=%c%c%c%c%s%s\n",
                   cycles,IR,stp,cond,doe,dld,psel,addr,bus,A,B,T2,T,
                   fC?'C':'.',fZ?'Z':'.',fN?'N':'.',fV?'V':'.',
                   urst?" uRST":"",halt?" HALT":"");
        /* commits (CLK edge) */
        switch(dld){
        case 1: A=bus; break;   case 2: B=bus; break;
        case 3: T=bus; break;   case 4: T2=bus; break;
        case 5: fC=bus&1; fZ=(bus>>1)&1; fN=(bus>>2)&1; fV=(bus>>3)&1; break;
        case 6: IR=bus; break;
        case 7: memwr(addr,bus); break;
        case 8: P[psel]=(P[psel]&0xFF00)|bus; break;
        case 9: P[psel]=(P[psel]&0x00FF)|(bus<<8); break;
        }
        if(pinc) P[psel]++;
        if(pdec) P[psel]--;
        if(ldf){ fC=nC; fZ=nZ; fN=nN; fV=nV; }
        else if(ldzn){ fZ=(bus==0); fN=(bus>>7)&1; }   /* loads set Z,N from the byte */
        if(setc) fC=1;                                 /* SEC: force C, leave Z/N/V */
        if(clrc) fC=0;                                 /* CLC */
        /* rev C: EI/DI/RTI manage the interrupt-enable latch (an opcode decode on
         * the control card, not a microcode bit). Applied as the opcode retires. */
        if(urst){ if(IR==0x02||IR==0x04) IE=1; else if(IR==0x03) IE=0; }
        prev_fcond=fcond;
        stp = urst ? 0 : (stp+1)&15;
        if(halt) halted=1;
        cycles++;
    }
    if(gdump) gpu_writeppm(gdump);
    if(gascii) gpu_writeascii();
    fprintf(stderr,"\n[%s after %llu cycles] PC=%04X A=%02X B=%02X "
            "P1=%04X P2=%04X SP=%04X F=%c%c%c%c LED=%02X\n",
            halted?"HALT":"cycle limit",cycles,P[0],A,B,P[1],P[2],P[3],
            fC?'C':'.',fZ?'Z':'.',fN?'N':'.',fV?'V':'.',leds);
    return 0;
}
