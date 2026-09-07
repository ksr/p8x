/* p8mouse.c -- seize a USB mouse and feed it to the P8X as xterm SGR.
 *
 * A macOS host helper for os/runcard.sh. It grabs ONE mouse exclusively
 * (IOHIDManager, seize) so macOS stops processing that device -- the Mac
 * cursor never moves and nothing on the desktop reacts -- reads its raw
 * HID motion/buttons, tracks a terminal-cell cursor, and writes xterm SGR
 * mouse sequences (ESC[<b;x;yM / ...m) to stdout. The P8X's resident WM
 * (and paint/desk via lib_ptr) already understand those, so NOTHING on the
 * P8X side changes -- the seized mouse looks exactly like a terminal click.
 *
 * The keyboard typed in the terminal passes straight through, so one pipe
 * carries both:
 *
 *   cc -O2 -o p8mouse tools/p8mouse.c -framework IOKit -framework CoreFoundation
 *   ./p8mouse -l                 # list mice; note the USB one's VID:PID
 *   ./p8mouse 046d:c52b | ./os/runcard.sh    # seize THAT mouse
 *
 * ONLY the seized USB mouse reaches the P8X. The touchpad still drives the
 * Mac normally -- and although the terminal (with xterm mouse mode on, as
 * paint/desk turn it on) also reports the TOUCHPAD as SGR on our stdin,
 * kbd_thread FILTERS those out: it forwards the keyboard but drops any
 * ESC[<...M/m the terminal sends, so the touchpad cannot leak into the
 * P8X. The only mouse SGR that flow are the ones this helper emits from
 * the seized device.
 *
 * CAVEATS (this is a starting sketch, not a shipped tool):
 *   - Needs Input Monitoring permission (System Settings > Privacy).
 *     Seizing an HID device may require a signed/entitled binary or
 *     elevated privileges; IOHIDManagerOpen returns non-zero otherwise.
 *   - With no VID:PID it seizes the FIRST mouse -- which on a laptop may be
 *     the TRACKPAD. Use `-l` to find the USB mouse and pass its VID:PID.
 *   - The pipe makes the emulator's stdin non-interactive; a cleaner design
 *     is a dedicated pointer channel (an emulator register or a bridge
 *     packet) instead of piggybacking the console -- see docs/p8x-wm-design
 *     and the PS/2-card backlog for the no-Mac path.
 *
 * The P8X panel is 480x272; its WM/lib_ptr map terminal CELLS to pixels as
 * px=(col-1)*6, py=271-(row-1)*11 on an 80x24 grid, so we track a CELL
 * cursor and accumulate raw counts into cell steps.
 */
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <CoreFoundation/CoreFoundation.h>
#include <termios.h>
#include <unistd.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define COLS 80
#define ROWS 24
#define CNT_PER_COL 6          /* raw mouse counts to advance one cell */
#define CNT_PER_ROW 11

static int col = 40, row = 12;         /* current cell cursor (1-based) */
static int accx = 0, accy = 0;         /* sub-cell count accumulators */
static int lbtn = 0;                   /* left button held? */
static pthread_mutex_t out_mx = PTHREAD_MUTEX_INITIALIZER;

static void put(const char *s, int n) {
    pthread_mutex_lock(&out_mx);
    (void)!write(1, s, n);
    pthread_mutex_unlock(&out_mx);
}

/* one SGR mouse report: b = button+flags, final 'M' (press/drag) or 'm' */
static void sgr(int b, char final) {
    char buf[32];
    int n = snprintf(buf, sizeof buf, "\033[<%d;%d;%d%c", b, col, row, final);
    put(buf, n);
}

static void clampcell(void) {
    if (col < 1) col = 1;
    if (col > COLS) col = COLS;
    if (row < 1) row = 1;
    if (row > ROWS) row = ROWS;
}

/* IOHID value callback: one changed element (relative X/Y, or a button) */
static void on_value(void *ctx, IOReturn res, void *sender, IOHIDValueRef v) {
    IOHIDElementRef e = IOHIDValueGetElement(v);
    uint32_t page = IOHIDElementGetUsagePage(e);
    uint32_t use  = IOHIDElementGetUsage(e);
    CFIndex   val = IOHIDValueGetIntegerValue(v);
    int moved = 0;

    if (page == kHIDPage_GenericDesktop && use == kHIDUsage_GD_X) {
        accx += (int)val;
        while (accx >=  CNT_PER_COL) { col++; accx -= CNT_PER_COL; moved = 1; }
        while (accx <= -CNT_PER_COL) { col--; accx += CNT_PER_COL; moved = 1; }
    } else if (page == kHIDPage_GenericDesktop && use == kHIDUsage_GD_Y) {
        accy += (int)val;                    /* HID Y grows down = row down */
        while (accy >=  CNT_PER_ROW) { row++; accy -= CNT_PER_ROW; moved = 1; }
        while (accy <= -CNT_PER_ROW) { row--; accy += CNT_PER_ROW; moved = 1; }
    } else if (page == kHIDPage_Button) {
        int pressed = (val != 0);
        clampcell();
        if (use == 1) {                      /* left button */
            if (pressed && !lbtn)  { lbtn = 1; sgr(0, 'M'); }   /* press  */
            else if (!pressed && lbtn) { lbtn = 0; sgr(0, 'm'); } /* release */
        } else if (use == 2) {               /* right button -> SGR button 2 */
            sgr(2, pressed ? 'M' : 'm');
        }
        return;
    }

    if (moved) {
        clampcell();
        if (lbtn) sgr(0 | 32, 'M');           /* motion while held = drag */
        /* hover (no button) sends nothing: the P8X acts on press/drag/release */
    }
}

static struct termios saved_tio;
static int have_tio = 0;
static void restore_tio(void) { if (have_tio) tcsetattr(0, TCSANOW, &saved_tio); }

/* Forward the terminal keyboard to the P8X, but DROP the terminal's own
 * mouse reports. With xterm mouse mode on (paint/desk enable it), the
 * terminal sends ESC[<b;x;yM/m for ANY pointer over its window -- the
 * TOUCHPAD included -- on our stdin. We filter those out so the touchpad
 * cannot leak in; the only mouse SGR reaching the P8X are the ones this
 * helper emits from the SEIZED USB mouse (via on_value). Arrow keys and
 * other CSI sequences pass through untouched.
 *
 * State: 0 normal, 1 saw ESC, 2 saw ESC[, 3 dropping a mouse SGR body. */
static void *kbd_thread(void *arg) {
    unsigned char c;
    int st = 0;
    const unsigned char ESC = 27, LB = '[';
    while (read(0, &c, 1) == 1) {
        switch (st) {
        case 0:
            if (c == ESC) st = 1;                 /* hold ESC, decide later */
            else put((const char *)&c, 1);
            break;
        case 1:
            if (c == LB) st = 2;                  /* hold ESC[ */
            else { put((const char *)&ESC, 1); put((const char *)&c, 1); st = 0; }
            break;
        case 2:
            if (c == '<') st = 3;                 /* ESC[< = mouse SGR -> drop */
            else {                                /* other CSI (arrows etc.) */
                put((const char *)&ESC, 1);
                put((const char *)&LB, 1);
                put((const char *)&c, 1);
                st = 0;
            }
            break;
        case 3:
            if (c == 'M' || c == 'm') st = 0;     /* end of the mouse report */
            break;                                /* body dropped */
        }
    }
    return NULL;
}

/* read an int property (VendorID/ProductID) off a device */
static int dev_int(IOHIDDeviceRef d, CFStringRef key) {
    int v = 0;
    CFTypeRef r = IOHIDDeviceGetProperty(d, key);
    if (r && CFGetTypeID(r) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)r, kCFNumberIntType, &v);
    return v;
}

/* list every matched mouse: "VID:PID  Product name" */
static int list_mice(IOHIDManagerRef mgr) {
    CFSetRef set = IOHIDManagerCopyDevices(mgr);
    if (!set) { fprintf(stderr, "p8mouse: no mice matched.\n"); return 1; }
    CFIndex n = CFSetGetCount(set);
    IOHIDDeviceRef *devs = calloc(n, sizeof *devs);
    CFSetGetValues(set, (const void **)devs);
    for (CFIndex i = 0; i < n; i++) {
        int vid = dev_int(devs[i], CFSTR(kIOHIDVendorIDKey));
        int pid = dev_int(devs[i], CFSTR(kIOHIDProductIDKey));
        char name[128] = "(unnamed)";
        CFTypeRef p = IOHIDDeviceGetProperty(devs[i], CFSTR(kIOHIDProductKey));
        if (p && CFGetTypeID(p) == CFStringGetTypeID())
            CFStringGetCString((CFStringRef)p, name, sizeof name, kCFStringEncodingUTF8);
        printf("%04x:%04x  %s\n", vid, pid, name);
    }
    free(devs);
    CFRelease(set);
    return 0;
}

int main(int argc, char **argv) {
    int want_list = 0, no_seize = 0, vid = 0, pid = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-l")) want_list = 1;
        else if (!strcmp(argv[i], "-n")) no_seize = 1;
        else if (sscanf(argv[i], "%x:%x", &vid, &pid) != 2) {
            fprintf(stderr, "usage: %s [-l] [-n] [VID:PID]   (VID:PID hex, e.g. 046d:c52b)\n"
                            "  -l  list mice and exit\n"
                            "  -n  no seize: READ the mouse without grabbing it (needs no\n"
                            "      root, only Input Monitoring). The mouse still moves the\n"
                            "      Mac cursor, but only IT -- not the trackpad -- reaches\n"
                            "      the P8X. Keep the P8X terminal focused.\n",
                    argv[0]);
            return 2;
        }
    }

    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault,
                                             kIOHIDOptionsTypeNone);
    CFMutableDictionaryRef match = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int page = kHIDPage_GenericDesktop, usage = kHIDUsage_GD_Mouse;
    CFNumberRef pn = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef un = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    CFDictionarySetValue(match, CFSTR(kIOHIDDeviceUsagePageKey), pn);
    CFDictionarySetValue(match, CFSTR(kIOHIDDeviceUsageKey), un);
    if (vid || pid) {                          /* target one specific mouse */
        CFNumberRef vn = CFNumberCreate(NULL, kCFNumberIntType, &vid);
        CFNumberRef pdn = CFNumberCreate(NULL, kCFNumberIntType, &pid);
        CFDictionarySetValue(match, CFSTR(kIOHIDVendorIDKey), vn);
        CFDictionarySetValue(match, CFSTR(kIOHIDProductIDKey), pdn);
    }
    IOHIDManagerSetDeviceMatching(mgr, match);

    if (want_list) {                           /* enumerate, don't seize */
        IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
        return list_mice(mgr);
    }

    if (tcgetattr(0, &saved_tio) == 0) {       /* raw so keys pass unbuffered */
        struct termios t = saved_tio;
        cfmakeraw(&t);
        tcsetattr(0, TCSANOW, &t);
        have_tio = 1;
        atexit(restore_tio);
    }

    IOHIDManagerRegisterInputValueCallback(mgr, on_value, NULL);
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(),
                                    kCFRunLoopDefaultMode);

    /* SEIZE (default): exclusive grab so macOS stops moving the cursor for
     * this mouse. Needs root/entitlement on modern macOS. With -n we open
     * NON-exclusively: we still READ the mouse (Input Monitoring is enough,
     * no root), but it keeps driving the Mac cursor -- only this device, not
     * the trackpad, is forwarded to the P8X, and kbd_thread filters the
     * terminal's own reports so nothing double-counts. */
    IOOptionBits opt = no_seize ? kIOHIDOptionsTypeNone
                                : kIOHIDOptionsTypeSeizeDevice;
    IOReturn r = IOHIDManagerOpen(mgr, opt);
    if (r != kIOReturnSuccess) {
        fprintf(stderr, "p8mouse: could not open the mouse (0x%x).\n"
                        "  Grant Input Monitoring (System Settings > Privacy)"
                        " to your terminal app,\n"
                        "  then fully quit and reopen it.%s\n", r,
                no_seize ? "" : "  For the exclusive seize you also need"
                               " root (sudo) or a signed/entitled binary;\n"
                               "  if you cannot use sudo, run with -n.");
        return 1;
    }
    if (no_seize)
        fprintf(stderr, "p8mouse: reading %s WITHOUT seizing -- it still moves the "
                        "Mac cursor, but\n  only it (not the trackpad) reaches the "
                        "P8X. Keep the P8X terminal focused. Ctrl-C to stop.\n",
                (vid || pid) ? "that mouse" : "the first mouse");
    else
        fprintf(stderr, "p8mouse: %s seized -- it drives the P8X only now. "
                        "Ctrl-C to release.\n",
                (vid || pid) ? "that mouse" : "the first mouse");

    pthread_t kt;
    pthread_create(&kt, NULL, kbd_thread, NULL);
    CFRunLoopRun();
    return 0;
}
