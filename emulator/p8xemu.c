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
 * Memory map: 0000-7FFF EEPROM | 8000-FEFF RAM | FF00-FFFF I/O
 *   FF00 switches(r)  FF02 LEDs(w)  FF04 ACIA status(r)  FF05 ACIA data(rw)
 *   FF10-FF17 CF-IDE task file (8-bit True IDE), modelled when -c <img> given:
 *     FF10 data  FF11 feature  FF12 sector-count  FF13-15 LBA0-2
 *     FF16 head/dev  FF17 command(w)/status(r)  [BSY7 DRQ3 ERR0]
 *   Backs a flat sector-image file (LBA*512); SET FEATURES/IDENTIFY/READ/WRITE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <signal.h>

static int interactive=0;             /* stdin is a TTY: raw + blocking console */
static int peeked=-1;                 /* one-char lookahead for ACIA status/data */
static struct termios g_orig;
static int g_raw=0;

static uint8_t rom[4][8192], eeprom[0x8000], ram[0x7F00];
static uint16_t P[5];                 /* P0=PC P1 P2 P3=SP P4=PT (hidden scratch) */
static uint8_t A,B,T,T2,IR;
static int stp, fC,fZ,fN,fV;          /* fC = conventional carry (1 = carry / A>=B) */
static int prev_fcond=0, halted=0, trace=0;
static unsigned long long cycles=0;
static uint8_t leds=0;

/* ---- CF-IDE model (active only when a disk image is attached with -c) ----
   The monitor's driver (firmware/p8xmon.asm) drives a CompactFlash in 8-bit
   True IDE mode: it writes LBA0-2/head/sector-count, issues a command to FF17,
   spins on BSY/DRQ in the status register, then streams 512 bytes through the
   data port FF10. We model exactly that handshake. BSY is never asserted (the
   transfer is instantaneous here); DRQ is raised while a 512-byte buffer is
   being streamed and dropped when it drains. */
static FILE *cf_img=NULL;
static uint8_t cf_buf[512];
static int cf_idx=0, cf_drq=0, cf_err=0, cf_write=0;
static uint8_t cf_feat=0, cf_lba0=0, cf_lba1=0, cf_lba2=0;
static long cf_lba(void){ return ((long)cf_lba2<<16)|((long)cf_lba1<<8)|cf_lba0; }
static void cf_seek(void){ if(cf_img) fseek(cf_img, cf_lba()*512L, SEEK_SET); }
/* ATA IDENTIFY: words 27-46 (bytes 54..) hold a byte-swapped model string,
   which is what the monitor's I command prints. */
static void cf_identify(void){
    const char *m="P8X-CF EMULATOR                         "; /* 40 chars */
    memset(cf_buf,0,512);
    for(int i=0;i<40;i+=2){ cf_buf[54+i]=m[i+1]; cf_buf[54+i+1]=m[i]; }
    cf_idx=0; cf_drq=1; cf_err=0; cf_write=0;
}
static void cf_readsec(void){
    memset(cf_buf,0,512);
    cf_seek(); if(cf_img) fread(cf_buf,1,512,cf_img);
    cf_idx=0; cf_drq=1; cf_err=0; cf_write=0;
}
static void cf_cmd(uint8_t c){
    switch(c){
    case 0xEF: cf_err=0; cf_drq=0; break;                    /* SET FEATURES   */
    case 0xEC: cf_identify(); break;                         /* IDENTIFY       */
    case 0x20: cf_readsec(); break;                          /* READ SECTORS   */
    case 0x30: cf_idx=0; cf_drq=1; cf_err=0; cf_write=1; break; /* WRITE SECTORS */
    default:   cf_err=1; cf_drq=0; break;
    }
}
static uint8_t cf_data_rd(void){
    uint8_t v=cf_buf[cf_idx++];
    if(cf_idx>=512){ cf_idx=0; cf_drq=0; }
    return v;
}
static void cf_data_wr(uint8_t v){
    cf_buf[cf_idx++]=v;
    if(cf_idx>=512){
        if(cf_write && cf_img){ cf_seek(); fwrite(cf_buf,1,512,cf_img); fflush(cf_img); }
        cf_idx=0; cf_drq=0; cf_write=0;
    }
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
static void on_sig(int s){ (void)s; term_restore(); _exit(0); }
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
    if(peeked>=0){ int c=peeked; peeked=-1; return c; }
    if(!interactive){ int ch=getchar(); return ch<0?0:ch; }
    unsigned char c;
    if(read(0,&c,1)==1) return c;
    term_restore(); exit(0);
}
static uint8_t memrd(uint16_t ad){
    if(ad<0x8000) return eeprom[ad];
    if(ad<0xFF00) return ram[ad-0x8000];
    switch(ad){
    case 0xFF00: return 0x00;                                 /* switches */
    case 0xFF04: return 0x02 | (rx_ready()?0x01:0x00);        /* TDRE|RDRF */
    case 0xFF05: return rx_char();
    case 0xFF10: return cf_img? cf_data_rd() : 0xFF;          /* CF data    */
    case 0xFF17: return cf_img? (0x40|(cf_drq?0x08:0)|(cf_err?0x01:0)) : 0xFF; /* CF status: RDY, !BSY */
    default: return 0xFF;
    }
}
static void memwr(uint16_t ad,uint8_t v){
    if(ad<0x8000){ fprintf(stderr,"[warn] write to EEPROM %04X\n",ad); return; }
    if(ad<0xFF00){ ram[ad-0x8000]=v; return; }
    if(ad==0xFF02){ leds=v; return; }
    if(ad==0xFF05){ putchar(v); fflush(stdout); rx_misses=0; return; }
    if(cf_img) switch(ad){                                   /* CF task file */
    case 0xFF10: cf_data_wr(v); return;
    case 0xFF11: cf_feat=v; return;
    case 0xFF13: cf_lba0=v; return;
    case 0xFF14: cf_lba1=v; return;
    case 0xFF15: cf_lba2=v; return;
    case 0xFF17: cf_cmd(v); return;
    /* FF12 sector-count, FF16 head/dev: accepted, single-sector model */
    }
}
static void load(const char*fn,uint8_t*buf,size_t n){
    FILE*f=fopen(fn,"rb");
    if(!f){perror(fn);exit(1);}
    fread(buf,1,n,f); fclose(f);
}
int main(int argc,char**argv){
    const char*ee="eeprom.bin"; const char*cfn=0; unsigned long long lim=200000000ULL;
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"-t")) trace=1;
        else if(!strcmp(argv[i],"-l")) lim=strtoull(argv[++i],0,0);
        else if(!strcmp(argv[i],"-c")) cfn=argv[++i];
        else ee=argv[i];
    }
    char fn[64];
    for(int k=0;k<4;k++){ sprintf(fn,"u%d.bin",k); load(fn,rom[k],8192); }
    load(ee,eeprom,0x8000);
    if(cfn){                                        /* attach CF disk image */
        cf_img=fopen(cfn,"r+b");
        if(!cf_img){                                /* create + zero-fill 256 sectors */
            cf_img=fopen(cfn,"w+b");
            if(!cf_img){ perror(cfn); exit(1); }
            static uint8_t z[512]={0};
            for(int s=0;s<256;s++) fwrite(z,1,512,cf_img);
            fflush(cf_img);
        }
    }
    if(isatty(0) && tcgetattr(0,&g_orig)==0){       /* interactive console */
        interactive=1;
        struct termios t=g_orig;
        t.c_lflag &= ~(ICANON|ECHO);                /* char-at-a-time, BASIC echoes */
        t.c_iflag &= ~(ICRNL);                      /* Enter -> CR (not NL) */
        t.c_cc[VMIN]=1; t.c_cc[VTIME]=0;
        tcsetattr(0,TCSANOW,&t); g_raw=1;
        atexit(term_restore);
        signal(SIGINT,on_sig); signal(SIGTERM,on_sig);
        lim=~0ULL;                                  /* no cycle cap while typing */
    }
    P[0]=0; P[1]=P[2]=0; P[3]=0xFEFF; P[4]=0; stp=0; IR=0;   /* reset: P0 forced 0 */
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
        prev_fcond=fcond;
        stp = urst ? 0 : (stp+1)&15;
        if(halt) halted=1;
        cycles++;
    }
    fprintf(stderr,"\n[%s after %llu cycles] PC=%04X A=%02X B=%02X "
            "P1=%04X P2=%04X SP=%04X F=%c%c%c%c LED=%02X\n",
            halted?"HALT":"cycle limit",cycles,P[0],A,B,P[1],P[2],P[3],
            fC?'C':'.',fZ?'Z':'.',fN?'N':'.',fV?'V':'.',leds);
    return 0;
}
