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
 *     Commands: 01 PLOT 02 LINE 03 BOX 04 BOXFILL 05 CLS 07 CIRCLE
 *               08 CIRCLEFILL 09 POINT 0A ELLIPSE 0B ELLIPSEFILL
 *               | F0 SELFTEST (emulator only) F1 RESET F2 IDENT
 *     Always present; -g writes the DISPLAY page as a PPM, -G as text.
 *   FF30-FF3F MDU: hardware muldiv, bit-exact to lib_g3d's contract (stage 8a).
 *   FF40-FF4F geometry engine: SDRAM edge list, matrix transform, clip,
 *     project, draw + page-flip double buffering (stage 8b). Both pages power
 *     on holding a fixed garbage pattern, like real DRAM.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <signal.h>
#include "../generators/memmap.h"   /* RAMBASE/IOBASE/ROMSIZE/RAMSIZE — single-source memory map */

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
static void gpu_box(int x0,int y0,int x1,int y1,uint16_t c,int fill);
#define GEMAXE 4096                    /* list cap: count reg sanity bound */
static uint8_t  gemem[GEMAXE*12];      /* the edge list ($100000 on the board) */
static uint32_t gecur;                 /* upload cursor */
static uint8_t  gesel, gevlo, geerr;   /* param index, GEVAL low latch, err */
static int16_t  gep[23];               /* the parameter file */

static void ge_reset(void){            /* power-on parameter state */
    memset(gep,0,sizeof gep);
    gep[0]=gep[4]=gep[8]=256;          /* identity matrix, S7.8 */
    gep[12]=256;                       /* focal d */
    gep[21]=3;                         /* flags: erase + flip */
    gesel=0; gevlo=0; gecur=0; geerr=0;
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
static void ge_tri(const uint8_t *e, int fill){
    int16_t v[3][3], w[3];
    int16_t pz[8][3]; int np = 0;             /* near-clipped polygon */
    int16_t sx[8], sy[8];
    for(int p=0;p<3;p++){
        int16_t in[3];
        for(int k=0;k<3;k++) in[k]=(int16_t)(e[p*6+k*2] | (e[p*6+k*2+1]<<8));
        ge_xform(in, v[p]);
    }
    if(gep[12] == 0){                         /* ortho: no near clip */
        for(int p=0;p<3;p++){ pz[np][0]=v[p][0]; pz[np][1]=v[p][1]; pz[np][2]=v[p][2]; np++; }
    } else {
        for(int p=0;p<3;p++){                 /* clip the polygon vs z=16 */
            int16_t *a=v[p], *b=v[(p+1)%3];
            int ain = a[2] >= 16, bin = b[2] >= 16;
            if(ain){ pz[np][0]=a[0]; pz[np][1]=a[1]; pz[np][2]=a[2]; np++; }
            if(ain != bin){
                pz[np][0]=(int16_t)(a[0]+ge_md((int16_t)(b[0]-a[0]),
                            (int16_t)(16-a[2]),(int16_t)(b[2]-a[2])));
                pz[np][1]=(int16_t)(a[1]+ge_md((int16_t)(b[1]-a[1]),
                            (int16_t)(16-a[2]),(int16_t)(b[2]-a[2])));
                pz[np][2]=16; np++;
            }
        }
        if(np < 3) return;                    /* wholly behind */
    }
    w[2]=0;
    for(int p=0;p<np;p++){ w[0]=pz[p][0]; w[1]=pz[p][1]; w[2]=pz[p][2];
                           ge_map(w, &sx[p], &sy[p]); }
    if(fill){                                 /* fan: (0,1,2) [,(0,2,3)] */
        for(int t=1;t+1<np;t++)
            ge_filltri(sx[0],sy[0],sx[t],sy[t],sx[t+1],sy[t+1]);
    } else {
        for(int p=0;p<np;p++)
            ge_sline(sx[p],sy[p],sx[(p+1)%np],sy[(p+1)%np]);
    }
}

static void ge_render(void){
    int n = gep[22];
    size_t off = 0;
    if(n<0 || n>GEMAXE){ geerr=1; return; }
    geerr=0;
    /* erase = a pen-0 BOXF of the viewport. Stage 9: records are TYPED and
       carry their own colour (STAGE9-DESIGN.md) -- the engine sets the pen
       per record and leaves it holding the LAST record's colour. */
    if(gep[21]&1) gpu_box(gep[17],gep[18],gep[19],gep[20],0,1);
    for(int i=0;i<n;i++){
        const uint8_t *e = gemem + off;
        int16_t v[6], w[6];
        int16_t x0,y0,z0,x1,y1,z1,d;
        uint8_t rtype, rflags;
        if(off + 16 > sizeof gemem){ geerr=1; return; }
        rtype = e[0]; rflags = e[1];
        gcol = (uint16_t)(e[2] | (e[3]<<8));      /* the record's colour */
        if(rtype == 2){                           /* TRI (stage 9b) */
            if(off + 22 > sizeof gemem){ geerr=1; return; }
            ge_tri(e + 4, rflags & 1);
            off += 22;
            continue;
        }
        if(rtype != 1){ geerr=1; return; }        /* else: LINE */
        off += 16;
        for(int k=0;k<6;k++) v[k]=(int16_t)(e[4+k*2] | (e[5+k*2]<<8));
        for(int p=0;p<2;p++)                    /* v' = (M*v >>> 8) + T */
            for(int r=0;r<3;r++){
                int32_t acc = (int32_t)gep[r*3+0]*v[p*3+0]
                            + (int32_t)gep[r*3+1]*v[p*3+1]
                            + (int32_t)gep[r*3+2]*v[p*3+2];
                w[p*3+r] = (int16_t)((acc>>8) + gep[9+r]);
            }
        x0=w[0]; y0=w[1]; z0=w[2]; x1=w[3]; y1=w[4]; z1=w[5];
        d = gep[12];
        if(d){                                  /* near clip BEFORE the divide */
            if(z0<16 && z1<16) continue;
            if(z0<16){
                x0=(int16_t)(x0+ge_md((int16_t)(x1-x0),(int16_t)(16-z0),(int16_t)(z1-z0)));
                y0=(int16_t)(y0+ge_md((int16_t)(y1-y0),(int16_t)(16-z0),(int16_t)(z1-z0)));
                z0=16;
            }
            if(z1<16){
                x1=(int16_t)(x1+ge_md((int16_t)(x0-x1),(int16_t)(16-z1),(int16_t)(z0-z1)));
                y1=(int16_t)(y1+ge_md((int16_t)(y0-y1),(int16_t)(16-z1),(int16_t)(z0-z1)));
                z1=16;
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
        if(!vis) continue;
        {   /* viewport map, constant denominators, y flips */
            int16_t px0=(int16_t)(gep[17]+ge_md((int16_t)(x0-gep[13]),(int16_t)(gep[19]-gep[17]),(int16_t)(gep[15]-gep[13])));
            int16_t py0=(int16_t)(gep[20]-ge_md((int16_t)(y0-gep[14]),(int16_t)(gep[20]-gep[18]),(int16_t)(gep[16]-gep[14])));
            int16_t px1=(int16_t)(gep[17]+ge_md((int16_t)(x1-gep[13]),(int16_t)(gep[19]-gep[17]),(int16_t)(gep[15]-gep[13])));
            int16_t py1=(int16_t)(gep[20]-ge_md((int16_t)(y1-gep[14]),(int16_t)(gep[20]-gep[18]),(int16_t)(gep[16]-gep[14])));
            gpu_line(px0,py0,px1,py1,gcol);
        }
    }
    if(gep[21]&2) ge_flip();
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
static void gpu_px(int x,int y,uint16_t c){
    if((unsigned)x>=(unsigned)gw || (unsigned)y>=(unsigned)gh) return;
    gfb[y*gstride+x]=c;                      /* one pixel, one 565 word */
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
    for(;;){
        gpu_px(x0,y0,c);
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
        for(int y=y0;y<=y1;y++) for(int x=x0;x<=x1;x++) gpu_px(x,y,c);
        return;
    }
    for(int x=x0;x<=x1;x++){ gpu_px(x,y0,c); gpu_px(x,y1,c); }
    for(int y=y0;y<=y1;y++){ gpu_px(x0,y,c); gpu_px(x1,y,c); }
}
static void gpu_hline(int xa,int xb,int y,uint16_t c){
    for(int x=xa;x<=xb;x++) gpu_px(x,y,c);
}
/* Midpoint circle, integer, eight-way symmetric. Same rule as gpu_line: this is
   the golden model and the RTL transliterates it, so it stays in this form. */
static void gpu_circle(int cx,int cy,int r,uint16_t c,int fill){
    int x=r, y=0, err=1-r;
    while(x>=y){
        if(fill){
            gpu_hline(cx-x,cx+x,cy+y,c);  gpu_hline(cx-x,cx+x,cy-y,c);
            gpu_hline(cx-y,cx+y,cy+x,c);  gpu_hline(cx-y,cx+y,cy-x,c);
        }else{
            gpu_px(cx+x,cy+y,c); gpu_px(cx-x,cy+y,c);
            gpu_px(cx+x,cy-y,c); gpu_px(cx-x,cy-y,c);
            gpu_px(cx+y,cy+x,c); gpu_px(cx-y,cy+x,c);
            gpu_px(cx+y,cy-x,c); gpu_px(cx-y,cy-x,c);
        }
        y++;
        if(err<0) err += 2*y+1;
        else { x--; err += 2*(y-x)+1; }
    }
}
/* Midpoint ellipse, integer, four-way symmetric. Chosen over a per-row "widest
   x that still satisfies the equation" search because this inner loop is adds
   and shifts only -- the RTL transliteration then needs no multiplier beyond the
   three at setup.

   The two regions meet where the curve's slope passes -1: region 1 steps x and
   sometimes y, region 2 steps y and sometimes x. Both decision variables are
   scaled by 4 so the classic rx^2/4 term is exact rather than rounded. A
   rounding choice is precisely what two implementations quietly disagree about,
   and this one has to stay bit-identical to the Verilog. */
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
    gpu_circle(gw/2,gh/2,gh/3,0x07FF,0);
}
/* SETMODE. Changing mode reinterprets every byte of the framebuffer, so the old
   contents are meaningless -- it clears, and loads the palette that belongs to
   the mode. Loading the palette here rather than sharing one across both is
   what keeps mode 0 exactly as it was: its four pens are the classic
   black/white/red/green, while mode 1 comes up with a 3-3-2 ramp so that a
   program which never touches PALETTE still sees sensible colour.
   Returns 0 on an unknown mode, which the caller turns into GSTAT's ERR bit. */
static void gpu_reset(void){
    memset(gfb,0,gfpix*sizeof *gfb);   /* gfb is a page POINTER now */
    /* The reset pen is WHITE (0xFFFF), because the historical default "pen 1"
       meant white back when there were four pens, and a visible default is the
       one that costs nobody a debugging round. The RTL must match. */
    gx0=gy0=gx1=gy1=0; gcol=0xFFFF; gparm=0; gparm2=0; gerr=0; gidx=GIDLEN;
    gpt[0]=gpt[1]=0; gpidx=2;
}
static void gpu_cmd(uint8_t v){
    switch(v){
    case 0x01: gpu_px(gx0,gy0,gcol);                break;   /* PLOT       */
    case 0x02: gpu_line(gx0,gy0,gx1,gy1,gcol);      break;   /* LINE       */
    case 0x03: gpu_box(gx0,gy0,gx1,gy1,gcol,0);     break;   /* BOX        */
    case 0x04: gpu_box(gx0,gy0,gx1,gy1,gcol,1);     break;   /* BOXFILL    */
    /* CLS: every byte is 4 pixels of the same pen, so 0x00/0x55/0xAA/0xFF. */
    case 0x05: for(size_t i=0;i<gfpix;i++) gfb[i]=gcol; break;  /* CLS     */
/* 0x06 was SETPAL. No palette, no command: an unknown code sets ERR, which
       is exactly what old software probing for it should see. */
    case 0x07: gpu_circle(gx0,gy0,gparm,gcol,0);    break;   /* CIRCLE     */
    case 0x08: gpu_circle(gx0,gy0,gparm,gcol,1);    break;   /* CIRCLEFILL */
    case 0x0A: gpu_ellipse(gx0,gy0,gparm,gparm2,gcol,0); break; /* ELLIPSE     */
    case 0x0B: gpu_ellipse(gx0,gy0,gparm,gparm2,gcol,1); break; /* ELLIPSEFILL */
    /* POINT reads a pixel back into GDATA, which is what a BASIC POINT()
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
static uint8_t memrd(uint16_t ad){
    if(ad<RAMBASE) return eeprom[ad];
    if(ad<IOBASE) return ram[ad-RAMBASE];
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
    /* Geometry engine reads. Instant too: GESTAT never shows busy here. */
    case GESTAT: return (uint8_t)(geerr ? 0x01 : 0x00);
    case GEID:   return 0x45;                      /* 'E' -- presence probe */
    default: return 0xFF;
    }
}
static void memwr(uint16_t ad,uint8_t v){
    if(ad<RAMBASE){ fprintf(stderr,"[warn] write to EEPROM %04X\n",ad); return; }
    if(ad<IOBASE){ ram[ad-RAMBASE]=v; return; }
    if(ad==0xFF02){                                          /* LEDs */
        if(led_trace && v!=leds)
            fprintf(stderr,"[LED $FF02] $%02X  %c%c%c%c%c%c%c%c\n", v,
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
      case GESEL:  gesel=v; return;
      case GEVAL:  gevlo=v; return;
      case GEVALH: if(gesel<23) gep[gesel]=(int16_t)((v<<8)|gevlo);
                   gesel++; return;
      case GEUP:   if(gecur<sizeof gemem) gemem[gecur++]=v; return;
      case GECMD:
        if(v==1) gecur=0;
        else if(v==2) ge_render();
        else if(v==3) ge_flip();
        else if(v==4) gfb=gfbd;          /* PGSYNC: back to single-buffer */
        else geerr=1;
        return;
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
