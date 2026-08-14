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
 *   FF20-FF2E graphics display: a 240x136 4-colour framebuffer with a drawing
 *     engine, pixel-doubled to a 480x272 panel. Same device whether it is inside
 *     the FPGA P8X or on a bus card (a Tang Nano 20K + the same panel), so one
 *     command set and one golden model serve both.
 *     FF20-23 X0/Y0/X1/Y1 low  FF29-2C their high bytes  FF24 pen  FF28 scalar
 *     FF25 command  FF26 status  FF27 data  FF2D/2E "PG" presence signature
 *     Commands: 01 PLOT 02 LINE 03 BOX 04 BOXFILL 05 CLS 06 SETPAL 07 CIRCLE
 *               08 CIRCLEFILL 09 POINT | F0 SELFTEST F1 RESET F2 IDENT
 *     Always present; -g writes it out as a PPM, -G as text.
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
   The FPGA drives a 4.3" 480x272 RGB panel, but 480x272 does not fit in the
   Tang Nano's spare block RAM at ANY depth: 6 free blocks are 12288 bytes and
   even one bit per pixel needs 16320. So the framebuffer is 240x136 at 2 bits
   per pixel (8160 bytes, 4 blocks) and each logical pixel is drawn as a 2x2
   block, which fills the panel exactly and keeps pixels square. Four pens index
   a palette of 12-bit RGB, so the 4 colours on screen are chosen from 4096.

   The drawing engine belongs to the DEVICE, here and in the RTL -- not to the
   software. BASIC loads GX0/GY0/GX1/GY1/GCOL and writes GCMD, so a filled box
   costs a handful of port writes instead of 32640 read-modify-write cycles
   through a data port (2bpp packs four pixels to a byte, so software plotting
   would have to mask every single one). GSTAT bit 7 is the busy flag; drawing
   is instantaneous here, the same way CF never asserts BSY, so it reads 0.

   This is the GOLDEN MODEL. The Verilog engine has to reproduce gpu_line step
   for step or the co-sim diverges, so the Bresenham below is written in the
   plainest integer form there is and must not be "improved". */
#define GW      240                    /* logical framebuffer; pixel-doubled */
#define GH      136                    /* to 480x272 on the panel            */
#define GSTRIDE (GW/4)                 /* 60 bytes/row: 4 pixels per byte    */
static uint8_t  gfb[GSTRIDE*GH];
static const uint16_t gpal_reset[4]={0x000,0xFFF,0xF00,0x0F0}; /* black white red green */
static uint16_t gpal[4]={0x000,0xFFF,0xF00,0x0F0};             /* RGB444 */
/* Coordinates are 16-bit register PAIRS. Writing the low byte clears the high
   byte, so software that only ever writes lows (everything at 240x136) can
   never be broken by a stale high byte left behind by something else. Write the
   high byte AFTER the low one when you need a coordinate past 255. The pairs
   exist because 480x272 -- this same panel at its native resolution, which is
   where an SDRAM framebuffer would go -- needs 9 bits for X. */
static uint16_t gx0,gy0,gx1,gy1;
static uint8_t  gcol, gparm, gerr;
/* GDATA ($FF27) is the one read-back port: it streams the IDENT record after an
   IDENT command, and otherwise holds the result of the last POINT. gidx is the
   stream cursor; POINT parks it at the end so a pixel read is not mistaken for
   another IDENT byte. */
#define GIDLEN 14
static uint8_t  gident[GIDLEN], gdata=0;
static int      gidx=GIDLEN;
static const char *gdump=0;            /* -g FILE: write a PPM when the run ends */
static int      gascii=0;              /* -G: also render as text to stderr      */

/* One pixel. Off-screen writes are DISCARDED, not clipped: the coordinate
   registers are 16-bit, so coordinates far past the screen are reachable, and
   "drop the
   pixel" is the one rule that is trivially identical in C and in Verilog. A
   real clipper would have to match exactly, which is a bug waiting to happen. */
static void gpu_px(int x,int y,uint8_t c){
    if((unsigned)x>=GW || (unsigned)y>=GH) return;
    int off=y*GSTRIDE+(x>>2), sh=(3-(x&3))*2;   /* leftmost pixel in the high bits */
    gfb[off]=(gfb[off]&~(3<<sh))|((c&3)<<sh);
}
static uint8_t gpu_pixel(int x,int y){      /* pen at (x,y), for the dumps */
    return (gfb[y*GSTRIDE+(x>>2)] >> ((3-(x&3))*2)) & 3;
}
/* Integer Bresenham, all eight octants, endpoints inclusive. dy is held
   NEGATIVE, which is what lets one error term cover every direction. */
static void gpu_line(int x0,int y0,int x1,int y1,uint8_t c){
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
static void gpu_box(int x0,int y0,int x1,int y1,uint8_t c,int fill){
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
static void gpu_hline(int xa,int xb,int y,uint8_t c){
    for(int x=xa;x<=xb;x++) gpu_px(x,y,c);
}
/* Midpoint circle, integer, eight-way symmetric. Same rule as gpu_line: this is
   the golden model and the RTL transliterates it, so it stays in this form. */
static void gpu_circle(int cx,int cy,int r,uint8_t c,int fill){
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
/* IDENT builds a fixed 14-byte record that GDATA then streams out, the same
   shape as the CF card's IDENTIFY -> data-port idiom the firmware already
   knows. It carries the GEOMETRY, so software can ask the card how big it is
   instead of assuming: that is what lets one BASIC binary drive both this
   240x136 device and a wider one later. */
static void gpu_ident(void){
    memcpy(gident,"P8X-GFX",7);
    gident[7]=1;                        /* protocol version */
    gident[8]=GW&0xFF; gident[9]=GW>>8;
    gident[10]=GH&0xFF; gident[11]=GH>>8;
    gident[12]=4;                       /* colours (pens) */
    gidx=0;                             /* GDATA now streams the record */
}
/* SELFTEST: a fixed pattern drawn entirely from the card's own state, so a
   display with no software behind it can still be proven end to end -- power it
   up, poke one register, and every pen, both drawing primitives and all four
   edges are on screen. Deterministic, so a test can assert on it. */
static void gpu_selftest(void){
    memset(gfb,0,sizeof gfb);
    for(int i=0;i<4;i++)                                  /* pen bars */
        gpu_box(i*(GW/4), 0, i*(GW/4)+(GW/4)-1, GH/4, (uint8_t)i, 1);
    gpu_box(0,0,GW-1,GH-1,1,0);                           /* extreme edges */
    gpu_line(0,0,GW-1,GH-1,2); gpu_line(GW-1,0,0,GH-1,2); /* both diagonals */
    gpu_circle(GW/2,GH/2,GH/3,3,0);
}
static void gpu_reset(void){
    memset(gfb,0,sizeof gfb);
    memcpy(gpal,gpal_reset,sizeof gpal);
    gx0=gy0=gx1=gy1=0; gcol=1; gparm=0; gerr=0; gidx=GIDLEN; gdata=0;
}
static void gpu_cmd(uint8_t v){
    switch(v){
    case 0x01: gpu_px(gx0,gy0,gcol);                break;   /* PLOT       */
    case 0x02: gpu_line(gx0,gy0,gx1,gy1,gcol);      break;   /* LINE       */
    case 0x03: gpu_box(gx0,gy0,gx1,gy1,gcol,0);     break;   /* BOX        */
    case 0x04: gpu_box(gx0,gy0,gx1,gy1,gcol,1);     break;   /* BOXFILL    */
    /* CLS: every byte is 4 pixels of the same pen, so 0x00/0x55/0xAA/0xFF. */
    case 0x05: memset(gfb,(gcol&3)*0x55,sizeof gfb); break;  /* CLS        */
    /* SETPAL reuses the coordinate registers as R,G,B (0-15 each) and recolours
       the pen in GCOL -- no extra port, and no two-write latch to keep in step. */
    case 0x06: gpal[gcol&3]=((gx0&15)<<8)|((gy0&15)<<4)|(gx1&15); break;
    case 0x07: gpu_circle(gx0,gy0,gparm,gcol,0);    break;   /* CIRCLE     */
    case 0x08: gpu_circle(gx0,gy0,gparm,gcol,1);    break;   /* CIRCLEFILL */
    /* POINT reads a pixel back into GDATA, which is what a BASIC POINT()
       function needs. Off-screen reads as pen 0, matching the write side's
       "off-screen simply is not there" rule. */
    case 0x09: gdata = ((unsigned)gx0<GW && (unsigned)gy0<GH) ? gpu_pixel(gx0,gy0) : 0;
               gidx = GIDLEN;         /* not an IDENT stream: GDATA holds the pixel */
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
    fprintf(f,"P6\n%d %d\n255\n",GW*2,GH*2);
    for(int y=0;y<GH;y++)
      for(int r=0;r<2;r++)                                  /* doubled down   */
        for(int x=0;x<GW;x++){
            uint16_t p=gpal[gpu_pixel(x,y)];
            uint8_t rgb[3]={ (uint8_t)(((p>>8)&15)*17),     /* 0-15 -> 0-255  */
                             (uint8_t)(((p>>4)&15)*17),
                             (uint8_t)(( p     &15)*17) };
            fwrite(rgb,1,3,f); fwrite(rgb,1,3,f);           /* doubled across */
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
    static const char pen[4]={' ','1','2','3'};
    fputc('+',stderr); for(int i=0;i<GW/2;i++) fputc('-',stderr); fputs("+\n",stderr);
    for(int y=0;y<GH;y+=4){
        fputc('|',stderr);
        for(int x=0;x<GW;x+=2){
            int best=0;
            for(int dy=0;dy<4;dy++) for(int dx=0;dx<2;dx++)
                if(x+dx<GW && y+dy<GH){
                    int p=gpu_pixel(x+dx,y+dy);
                    if(p>best) best=p;
                }
            fputc(pen[best],stderr);
        }
        fputs("|\n",stderr);
    }
    fputc('+',stderr); for(int i=0;i<GW/2;i++) fputc('-',stderr); fputs("+\n",stderr);
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
    case GDATA:  return (gidx<GIDLEN) ? gident[gidx++] : gdata;
    case GID0:   return 0x50;                      /* 'P' */
    case GID1:   return 0x47;                      /* 'G' -- "PG", not a floating $FF */
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
      case GCOL: gcol=v; return;
      case GPARM:gparm=v; return;
      case GCMD: gerr=0; gpu_cmd(v); return;
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
