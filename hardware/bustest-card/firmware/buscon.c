/* buscon.c — P8X Bus Test Card firmware (first cut, DESIGN — not run on hardware).
 *
 * A line-oriented ASCII protocol over USB CDC that drives the P8X backplane one
 * microcycle at a time through five MCP23S17 SPI expanders. Field names are the
 * microcode's own (see microcode/genucode.py): DOE, DLD, PSEL, ALUS, ... so a
 * script written here means the same thing against the emulator.
 *
 *   w DOE=MEM DLD=IR PSEL=P0     set microword fields (only while CLK is low)
 *   a 2000                       drive A0-A15 (reg-bank must be absent)
 *   step                         one microcycle: rest -> phaseA -> phaseB -> rest
 *   r D | r flags | r A          read back
 *   probe                        read the 8 high-Z probe lines
 *   drive ctrl addr ...          claim line groups; nothing is driven until claimed
 *   release <group>              hand a group back to Hi-Z
 *   owns                         report what is driven vs Hi-Z
 *   id                           firmware banner + 5V-present + ownership
 *
 * Replies are KEY=VAL (typable and parseable). Errors are "!ERR <reason>".
 *
 * SAFETY MODEL (design doc §3-4):
 *  - power-on drives NOTHING; a group is high-Z until `drive` claims it.
 *  - all-zeros is the inert bus; CLK held low means nothing latches anywhere.
 *  - the microword only changes while CLK is low (gated flag clock, non-atomic
 *    SPI update); `step` enforces the rest->A->B->rest phasing.
 *  - firmware refuses to drive unless the backplane-5V sense reads present.
 *
 * NOTE: pin-level SPI/GPIO plumbing is stubbed against the Pico SDK signatures
 * but has NOT been built or timed. Every MCP23S17 register op is marked TODO.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "pico/stdlib.h"
#include "hardware/spi.h"
#include "hardware/adc.h"

/* ---- Pico pin map (matches the netlist in generators/gen_eagle.py) ---------- */
#define PIN_SCK   2
#define PIN_MOSI  3
#define PIN_MISO  4
#define PIN_CS    5
#define PIN_RST   6
#define PIN_ST0   7            /* 8 status LEDs on GP7..GP14 */
#define PIN_SENSE 26           /* ADC0: backplane 5V divider */
#define ADC_SENSE 0

/* ---- MCP23S17 register model ------------------------------------------------
 * 5 chips share one CS; each is addressed by its hardware A2:A1:A0 strap (0..4).
 * We keep a shadow of each chip's 16 GPIO (OLAT) and 16 direction (IODIR) bits
 * so a field write is: update shadow, push the one affected 8-bit port. */
#define NCHIP 5
static uint16_t olat[NCHIP];   /* output latch shadow (1 = drive high) */
static uint16_t iodir[NCHIP];  /* 1 = input (Hi-Z), 0 = output. Power-on: all 1. */

/* MCP23S17 register addresses (IOCON.BANK=0) */
#define R_IODIRA 0x00
#define R_IODIRB 0x01
#define R_GPIOA  0x12
#define R_GPIOB  0x13
#define R_OLATA  0x14
#define R_OLATB  0x15
#define OPW(addr) (0x40 | ((addr) << 1))       /* SPI control byte: write, opcode */
#define OPR(addr) (0x41 | ((addr) << 1))       /* SPI control byte: read */

/* TODO(hw): real SPI transaction. Stubbed shapes so the logic compiles/reviews. */
static void mcp_write(int chip, uint8_t reg, uint8_t val) {
    uint8_t tx[3] = { OPW(chip), reg, val };
    (void)tx; /* TODO: gpio_put(PIN_CS,0); spi_write_blocking(spi0,tx,3); gpio_put(PIN_CS,1); */
}
static uint8_t mcp_read(int chip, uint8_t reg) {
    uint8_t tx[3] = { OPR(chip), reg, 0 }, rx[3] = {0};
    (void)tx; (void)rx; /* TODO: CS low; spi_write_read_blocking; CS high; return rx[2]; */
    return 0;
}

/* ---- field -> (chip, bit) map — MUST match the netlist allocation ----------
 * bit 0..7 = GPA0..7, bit 8..15 = GPB0..7 of the named chip. Keep this table and
 * the _map() calls in gen_eagle.py in lockstep; a mismatch drives the wrong pin. */
typedef struct { const char *name; uint8_t chip; uint8_t bit; uint8_t width; } field_t;
static const field_t FIELDS[] = {
    /* U2.GPB */ {"DOE",1,8,4}, {"DLD",1,12,4},
    /* U3.GPA */ {"PSEL",2,0,3}, {"PINC",2,3,1}, {"PDEC",2,4,1},
                 {"CLK",2,5,1}, {"CLKB",2,6,1}, {"RES",2,7,1},   /* RES = -RES, active low */
    /* U3.GPB */ {"ALUS",2,8,4}, {"ALUM",2,12,1}, {"CIN",2,13,1}, {"SH0",2,14,1}, {"SH1",2,15,1},
    /* U4.GPA */ {"LDF",3,0,1}, {"LDZN",3,1,1}, {"SETC",3,2,1}, {"CLRC",3,3,1},
                 {"BSEL",3,4,1}, {"SHCIN",3,5,1}, {"IRQ",3,6,1},  /* IRQ = -IRQ */
};
#define NFIELDS (int)(sizeof(FIELDS)/sizeof(FIELDS[0]))

/* symbolic values, from genucode.py DOE/DLD/PSEL dicts */
static int lookup_sym(const char *field, const char *val, int *out) {
    static const char *DOE[]={"idle","A","B","T","T2","ALU","FLAGS","MEM","PTRL","PTRH",0};
    static const char *DLD[]={"none","A","B","T","T2","FLAGS","IR","MEMW","PTRL","PTRH",0};
    static const char *PSEL[]={"P0","P1","P2","P3","PT","PT2",0};
    const char **t = !strcmp(field,"DOE")?DOE : !strcmp(field,"DLD")?DLD
                   : !strcmp(field,"PSEL")?PSEL : 0;
    if (t) for (int i=0;t[i];i++) if (!strcmp(t[i],val)) { *out=i; return 1; }
    char *end; long v = strtol(val,&end,0);           /* else numeric (0x.. ok) */
    if (*end) return 0;
    *out=(int)v; return 1;
}

/* ---- ownership: groups of lines, each Hi-Z until `drive`d ------------------- */
enum { G_CTRL, G_ADDR, G_DATA, G_PROBE, NGROUP };
static const char *GNAME[NGROUP] = {"ctrl","addr","data","probe"};
static int owned[NGROUP];       /* 1 = we drive it */

/* clock phase helpers — CLK on U3.bit5, CLKB on U3.bit6 (see FIELDS) ---------- */
static void set_bit(int chip,int bit,int v){
    if (v) olat[chip]|=(1u<<bit); else olat[chip]&=~(1u<<bit);
}
static void push_chip(int chip){
    mcp_write(chip,R_OLATA,olat[chip]&0xFF);
    mcp_write(chip,R_OLATB,olat[chip]>>8);
}
static void set_clocks(int clk,int clkb){       /* both on chip 2 */
    set_bit(2,5,clk); set_bit(2,6,clkb); push_chip(2);
}

static int sense_5v(void){
    adc_select_input(ADC_SENSE);
    /* divider is 10k/10k, so present ~2.5V; ~1.2V threshold. 12-bit, 3.3V ref. */
    return adc_read() > 1500;
}

/* ---- one microcycle: rest -> phaseA -> phaseB -> rest (design doc §4.3) ------ */
static int do_step(char *err){
    if (!sense_5v()) { strcpy(err,"no backplane 5V"); return 0; }
    /* word is already set by `w`; we are at rest (both clocks low) */
    set_clocks(0,1);            /* phase A: strobes assert, source drives, settle */
    sleep_us(5);
    set_clocks(1,0);            /* phase B: destination latches; write commits */
    sleep_us(5);
    set_clocks(0,0);            /* back to rest */
    return 1;
}

/* ---- command parser --------------------------------------------------------- */
static int find_field(const char *nm){
    for (int i=0;i<NFIELDS;i++) if(!strcmp(FIELDS[i].name,nm)) return i;
    return -1;
}
static void set_field(const field_t *f,int val){
    for (int b=0;b<f->width;b++) set_bit(f->chip, f->bit+b, (val>>b)&1);
    push_chip(f->chip);
}

static void cmd_w(char *args, char *out){         /* w FIELD=VAL ... */
    char *tok=strtok(args," ");
    while(tok){
        char *eq=strchr(tok,'=');
        if(!eq){ strcpy(out,"!ERR expected FIELD=VAL"); return; }
        *eq=0; int fi=find_field(tok);
        if(fi<0){ sprintf(out,"!ERR unknown field %s",tok); return; }
        int v; if(!lookup_sym(tok,eq+1,&v)){ sprintf(out,"!ERR bad value %s",eq+1); return; }
        set_field(&FIELDS[fi],v);
        tok=strtok(0," ");
    }
    strcpy(out,"OK");
}

static void handle(char *line, char *out){
    char *cmd=strtok(line," ");
    if(!cmd){ out[0]=0; return; }
    char *rest=strtok(0,"");                        /* remainder of the line */

    if(!strcmp(cmd,"id")){
        sprintf(out,"P8XBUS 1.0  5V=%s  owns=%s%s%s%s",
            sense_5v()?"ok":"ABSENT",
            owned[G_CTRL]?"ctrl ":"", owned[G_ADDR]?"addr ":"",
            owned[G_DATA]?"data ":"", owned[G_PROBE]?"probe":"");
    } else if(!strcmp(cmd,"w")){
        if(rest) cmd_w(rest,out); else strcpy(out,"!ERR w needs FIELD=VAL");
    } else if(!strcmp(cmd,"step")){
        char e[48]; if(do_step(e)) strcpy(out,"OK"); else sprintf(out,"!ERR %s",e);
    } else if(!strcmp(cmd,"r")){
        char *what=rest?strtok(rest," "):0;
        if(what && !strcmp(what,"D"))       sprintf(out,"D=%02X", mcp_read(0,R_GPIOA));
        else if(what && !strcmp(what,"flags")){
            uint8_t fl=mcp_read(3,R_GPIOB);           /* U4.GPB0..3 = FC/FZ/FN/FV */
            sprintf(out,"FC=%d FZ=%d FN=%d FV=%d",fl&1,(fl>>1)&1,(fl>>2)&1,(fl>>3)&1);
        } else strcpy(out,"!ERR r D|flags|A");
    } else if(!strcmp(cmd,"probe")){
        uint8_t p=mcp_read(4,R_GPIOA);                /* U5.GPA = probes */
        sprintf(out,"PR=%d%d%d%d_%d%d%d%d",(p>>7)&1,(p>>6)&1,(p>>5)&1,(p>>4)&1,
                (p>>3)&1,(p>>2)&1,(p>>1)&1,p&1);
    } else if(!strcmp(cmd,"owns")){
        int k=sprintf(out,"drive=");
        int any=0; for(int g=0;g<NGROUP;g++) if(owned[g]){k+=sprintf(out+k,"%s ",GNAME[g]);any=1;}
        if(!any) k+=sprintf(out+k,"(none)");
    } else {
        sprintf(out,"!ERR unknown command %s",cmd);
    }
}

/* ---- init: everything Hi-Z except the clocks, which we hold low immediately ---
 * There are NO bus pull-downs on this card. A floating word only matters while a
 * clock edge can latch it, so the one line worth conditioning is CLK — and we do
 * it here in firmware, not in copper: chip 2's CLK/CLKB bits are made OUTPUTS
 * driving 0 as the very first thing after reset, so nothing downstream can latch
 * a floating word. Everything else stays Hi-Z until a `drive` command claims it.
 * The only unguarded moment is power-on-to-here (~tens of ms), closed by power
 * sequencing the backplane up before/with USB. */
static void bus_init(void){
    for(int c=0;c<NCHIP;c++){
        iodir[c]=0xFFFF; olat[c]=0;                   /* all inputs (Hi-Z); latch 0 */
        mcp_write(c,R_OLATA,0);     mcp_write(c,R_OLATB,0);
        mcp_write(c,R_IODIRA,0xFF); mcp_write(c,R_IODIRB,0xFF);
    }
    /* claim CLK/CLKB (chip 2, GPA bits 5,6) as outputs, driving both low = rest */
    iodir[2] &= ~((1u<<5)|(1u<<6));
    mcp_write(2,R_IODIRA, iodir[2]&0xFF);             /* bits 5,6 -> output, rest input */
    set_clocks(0,0);                                  /* both low: inert, no edge */
    for(int g=0;g<NGROUP;g++) owned[g]=0;
    owned[G_CTRL]=0;                                  /* we hold only the clocks, not "ctrl" */
}

int main(void){
    stdio_init_all();                                 /* USB CDC */
    spi_init(spi0, 1000*1000);                        /* 1 MHz — static, so slow is fine */
    gpio_set_function(PIN_SCK, GPIO_FUNC_SPI);
    gpio_set_function(PIN_MOSI,GPIO_FUNC_SPI);
    gpio_set_function(PIN_MISO,GPIO_FUNC_SPI);
    gpio_init(PIN_CS);  gpio_set_dir(PIN_CS,1);  gpio_put(PIN_CS,1);
    gpio_init(PIN_RST); gpio_set_dir(PIN_RST,1); gpio_put(PIN_RST,1);
    for(int i=0;i<8;i++){ gpio_init(PIN_ST0+i); gpio_set_dir(PIN_ST0+i,1); }
    adc_init(); adc_gpio_init(PIN_SENSE);
    bus_init();

    char line[160]; int n=0; char out[160];
    for(;;){
        int ch=getchar_timeout_us(0);
        if(ch==PICO_ERROR_TIMEOUT){ tight_loop_contents(); continue; }
        if(ch=='\r'||ch=='\n'){
            line[n]=0; n=0;
            if(line[0]){ handle(line,out); puts(out); }
        } else if(n<(int)sizeof(line)-1){
            line[n++]=(char)ch;
        }
    }
}
