/* p8xemu - cycle-level emulator for the P8X 8-bit TTL computer.
 *
 * Interprets the SAME microcode ROM images (u0-u3.bin) that are burned to
 * the control card 28C64s, so emulator and hardware cannot drift.
 *
 * Fidelity notes (deliberate, matches rev A hardware):
 *  - 74181 modelled with active-high data: CIN pin and Cn+4 are ACTIVE-LOW
 *    carries. The C flag latches the RAW Cn+4 pin (1 = no carry out).
 *  - Carry chain computed regardless of M (as in silicon), so LDF during
 *    logic ops latches the same C the hardware would.
 *  - V flag is hardwired 0 (rev A ALU card drives FV low).
 *  - Shifter: stage1 SH0 = left (CIN pin is the shift-in bit),
 *    stage2 SH1 = right. Pipeline/condition timing per control card:
 *    the FCOND field of the word in the pipeline selects ROM A12 for the
 *    NEXT lookup.
 *
 * Memory map: 0000-7FFF EEPROM | 8000-FEFF RAM | FF00-FFFF I/O
 *   FF00 switches(r)  FF02 LEDs(w)  FF04 ACIA status(r)  FF05 ACIA data(rw)
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

static uint8_t rom[4][8192], eeprom[0x8000], ram[0x7F00];
static uint16_t P[4];                 /* P0=PC P1 P2 P3=SP */
static uint8_t A,B,T,T2,IR;
static int stp, fC=1,fZ,fN,fV;        /* fC = raw Cn+4 pin (1 = no carry) */
static int prev_fcond=0, halted=0, trace=0;
static unsigned long long cycles=0;
static uint8_t leds=0;

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
    *cn4 = !((r>>8)&1);                    /* pin: low = carry generated */
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
static uint8_t memrd(uint16_t ad){
    if(ad<0x8000) return eeprom[ad];
    if(ad<0xFF00) return ram[ad-0x8000];
    switch(ad){
    case 0xFF00: return 0x00;                                 /* switches */
    case 0xFF04: return 0x02 | (stdin_pending()?0x01:0x00);   /* TDRE|RDRF */
    case 0xFF05: { int ch=getchar(); return ch<0?0:ch; }
    default: return 0xFF;
    }
}
static void memwr(uint16_t ad,uint8_t v){
    if(ad<0x8000){ fprintf(stderr,"[warn] write to EEPROM %04X\n",ad); return; }
    if(ad<0xFF00){ ram[ad-0x8000]=v; return; }
    if(ad==0xFF02){ leds=v; return; }
    if(ad==0xFF05){ putchar(v); fflush(stdout); return; }
}
static void load(const char*fn,uint8_t*buf,size_t n){
    FILE*f=fopen(fn,"rb");
    if(!f){perror(fn);exit(1);}
    fread(buf,1,n,f); fclose(f);
}
int main(int argc,char**argv){
    const char*ee="eeprom.bin"; unsigned long long lim=200000000ULL;
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"-t")) trace=1;
        else if(!strcmp(argv[i],"-l")) lim=strtoull(argv[++i],0,0);
        else ee=argv[i];
    }
    char fn[64];
    for(int k=0;k<4;k++){ sprintf(fn,"u%d.bin",k); load(fn,rom[k],8192); }
    load(ee,eeprom,0x8000);
    P[0]=0; P[1]=P[2]=0; P[3]=0xFEFF; stp=0; IR=0;   /* reset: P0 forced 0 */
    while(!halted && cycles<lim){
        /* condition mux: FCOND of the word currently in the pipeline */
        int cond;
        switch(prev_fcond){
        case 1: cond=1; break;       case 2: cond=fC; break;
        case 3: cond=fZ; break;      case 4: cond=fN; break;
        case 5: cond=fV; break;      default: cond=0;
        }
        int ad = IR | stp<<8 | cond<<12;
        uint32_t cw = rom[0][ad] | rom[1][ad]<<8 | rom[2][ad]<<16
                    | ((uint32_t)rom[3][ad])<<24;
        int doe=cw&15, dld=(cw>>4)&15, psel=(cw>>8)&3;
        int pinc=(cw>>10)&1, pdec=(cw>>11)&1, alus=(cw>>12)&15;
        int m=(cw>>16)&1, cinp=(cw>>17)&1, sh0=(cw>>18)&1, sh1=(cw>>19)&1;
        int ldf=(cw>>20)&1, fcond=(cw>>21)&7, urst=(cw>>24)&1, halt=(cw>>25)&1;
        /* combinational ALU + shifter from CURRENT register state */
        int cn4; uint8_t f=alu181(A,B,alus,m,cinp,&cn4);
        uint8_t g = sh0 ? (uint8_t)((f<<1)|(cinp&1)) : f;     /* stage 1: left  */
        uint8_t r = sh1 ? (uint8_t)((g>>1)|((cinp&1)<<7)) : g;/* stage 2: right */
        int nC=cn4, nZ=(r==0), nN=(r>>7)&1, nV=0;
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
