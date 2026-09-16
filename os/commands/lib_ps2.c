/* lib_ps2.c -- decode the PS/2 keyboard + mouse window ($FF58-$FF5F).
 *
 * Spliced with `//#use ps2`. The hardware (the planned TTL card, or PS/2
 * receivers in the graphics FPGA-card fabric) is two DUMB receivers: it shifts
 * in the 11-bit frames and latches each byte with a ready flag, nothing more.
 * Everything that turns those bytes into meaning -- Set-2 make/break -> ASCII
 * with shift/caps, 3-byte mouse packets -> (dx,dy,buttons) -- lives HERE, the
 * P8X way (hardware receives, software understands). The emulator models the
 * same window (p8xemu -ps2/-ps2a/-ps2b), so this decodes identically on silicon
 * and against the golden model.
 *
 *   ps2_init()                 zero the decoder state (call once, like ptr_init)
 *   ps2_present()              1 if a PS/2 card is fitted (PSID reads 'K')
 *   kb_raw()                   next raw Set-2 scan code, or -1 if none ready
 *   kb_getc()                  next decoded ASCII key on a PRESS, or 0
 *   ms_poll()                  1 when a packet completes (into ms_dx/ms_dy/ms_btn)
 *
 * ms_poll leaves its result in the globals ms_dx, ms_dy, ms_btn (the lib_ptr
 * idiom -- ptr_ev sets ptr_x/ptr_y), so no address-of-local is needed.
 *
 * Coordinate/sign convention (PS/2 device): dx > 0 = right, dy > 0 = UP (the
 * device's own axis). The pointer-integration layer maps that onto the panel.
 *
 * NOT YET: the host->device TRANSMIT dance (bit-banged CLK/DATA, the $F4
 * mouse-enable / $FF reset handshake). ms_enable() is a stub -- the emulator's
 * transmit path and device responses are not modelled, and the scripted mouse
 * stream arrives as if already enabled. See the PS/2 backlog item.
 */

//#define PSADAT 0xFF58   /* r: port A (keyboard) byte, ready cleared on read   */
//#define PSAST  0xFF59   /* r: bit0 ready / bit1 overrun / bit2 parity          */
//#define PSBDAT 0xFF5A   /* r: port B (mouse) byte                              */
//#define PSBST  0xFF5B   /* r: as PSAST                                         */
//#define PSLINE 0xFF5C   /* r: bit0 Aclk/bit1 Adat/bit2 Bclk/bit3 Bdat          */
//#define PSID   0xFF5E   /* r: $4B 'K' when the card is fitted                  */

/* Set-2 scan code -> unshifted ASCII, as (code, char) pairs; a scan code of 0
 * terminates. Searched, not indexed, so no 128-byte table to zero-init. */
char _kbp[] = {
    0x1C,'a', 0x32,'b', 0x21,'c', 0x23,'d', 0x24,'e', 0x2B,'f', 0x34,'g', 0x33,'h',
    0x43,'i', 0x3B,'j', 0x42,'k', 0x4B,'l', 0x3A,'m', 0x31,'n', 0x44,'o', 0x4D,'p',
    0x15,'q', 0x2D,'r', 0x1B,'s', 0x2C,'t', 0x3C,'u', 0x2A,'v', 0x1D,'w', 0x22,'x',
    0x35,'y', 0x1A,'z',
    0x45,'0', 0x16,'1', 0x1E,'2', 0x26,'3', 0x25,'4', 0x2E,'5', 0x36,'6', 0x3D,'7',
    0x3E,'8', 0x46,'9',
    0x29,' ', 0x5A,13, 0x66,8, 0x0D,9, 0x76,27,
    0x4E,'-', 0x55,'=', 0x54,'[', 0x5B,']', 0x5D,92, 0x4C,';', 0x52,39, 0x41,',',
    0x49,'.', 0x4A,'/', 0x0E,'`',
    0, 0
};
/* The SHIFTED symbol for each non-letter key (letters shift by case, computed). */
char _symp[] = {
    0x45,')', 0x16,'!', 0x1E,'@', 0x26,'#', 0x25,'$', 0x2E,'%', 0x36,'^', 0x3D,'&',
    0x3E,'*', 0x46,'(',
    0x4E,'_', 0x55,'+', 0x54,'{', 0x5B,'}', 0x5D,'|', 0x4C,':', 0x52,'"', 0x41,'<',
    0x49,'>', 0x4A,'?', 0x0E,'~',
    0, 0
};

/* decoder state (zeroed by ps2_init, never trusted uninitialised -- lib_ptr's
 * rule; p8cc globals are not reliably zero-filled) */
int _kb_shift;   /* a shift key is held        */
int _kb_caps;    /* caps lock latched          */
int _kb_brk;     /* F0 seen: next code is a release */
int _kb_ext;     /* E0 seen: extended key      */
int _ms_n;       /* mouse bytes collected 0..2 */
int _ms_b0;      /* mouse packet byte 0 (flags)*/
int _ms_b1;      /* mouse packet byte 1 (dx)   */
int ms_dx;       /* last packet: X delta (>0 right)          */
int ms_dy;       /* last packet: Y delta (>0 up, device axis)*/
int ms_btn;      /* last packet: bit0 left/bit1 right/bit2 mid */

int ps2_init() {
    _kb_shift = 0; _kb_caps = 0; _kb_brk = 0; _kb_ext = 0;
    _ms_n = 0; _ms_b0 = 0; _ms_b1 = 0;
    ms_dx = 0; ms_dy = 0; ms_btn = 0;
    return 0;
}

int ps2_present() { return peek(PSID) == 0x4B; }   /* 'K' */

/* search a (code,char) pair list for sc; 0 if not found */
int _ps2look(char *pairs, int sc) {
    int i;
    i = 0;
    while (pairs[i]) {
        if ((pairs[i] & 127) == sc) { return pairs[i + 1] & 127; }
        i = i + 2;
    }
    return 0;
}

int kb_raw() {
    if (peek(PSAST) & 1) { return peek(PSADAT); }
    return -1;
}

/* Decode one scan code into an ASCII key on PRESS. Returns 0 for the codes that
 * carry no character yet (prefixes, releases, modifier keys, unmapped keys). */
int kb_getc() {
    int c; int b; int s; int up;
    c = kb_raw();
    if (c < 0) { return 0; }
    if (c == 0xF0) { _kb_brk = 1; return 0; }          /* break prefix */
    if (c == 0xE0) { _kb_ext = 1; return 0; }          /* extended prefix */
    if (_kb_brk) {                                     /* a release completes */
        _kb_brk = 0;
        if (c == 0x12 || c == 0x59) { _kb_shift = 0; } /* shift up */
        _kb_ext = 0;
        return 0;
    }
    if (c == 0x12 || c == 0x59) { _kb_shift = 1; return 0; }  /* shift down */
    if (c == 0x58) { _kb_caps = _kb_caps ^ 1; return 0; }     /* caps toggles on press */
    if (_kb_ext) { _kb_ext = 0; return 0; }            /* extended (arrows/…): unmapped here */
    b = _ps2look(_kbp, c);
    if (b == 0) { return 0; }
    if ((b >= 'a') && (b <= 'z')) {                    /* a letter: case = shift XOR caps */
        up = _kb_shift ^ _kb_caps;
        if (up) { return b - 32; }
        return b;
    }
    if (_kb_shift) { s = _ps2look(_symp, c); if (s) { return s; } }
    return b;
}

/* Assemble the standard 3-byte PS/2 mouse packet from port B. Returns 1 when a
 * packet completes (leaving it in ms_dx/ms_dy/ms_btn), else 0. Resyncs on
 * byte0's always-1 bit (bit3). btn: bit0 left, bit1 right, bit2 middle. */
int ms_poll() {
    int b; int x; int y;
    if ((peek(PSBST) & 1) == 0) { return 0; }
    b = peek(PSBDAT);
    if (_ms_n == 0) {
        if ((b & 8) == 0) { return 0; }                /* sync: byte0 bit3 must be 1 */
        _ms_b0 = b; _ms_n = 1;
        return 0;
    }
    if (_ms_n == 1) { _ms_b1 = b; _ms_n = 2; return 0; }
    _ms_n = 0;                                         /* byte 2 completes the packet */
    x = _ms_b1;
    y = b;
    if (_ms_b0 & 16) { x = x - 256; }                  /* X sign (byte0 bit4) */
    if (_ms_b0 & 32) { y = y - 256; }                  /* Y sign (byte0 bit5) */
    ms_dx = x;
    ms_dy = y;
    ms_btn = _ms_b0 & 7;
    return 1;
}

/* STUB: enable mouse data reporting ($F4). The host->device transmit is
 * bit-banged over PSxST/PSLINE and not modelled in the emulator yet, so this is
 * a placeholder -- the scripted mouse stream arrives already enabled. */
int ms_enable() { return 0; }
