#!/usr/bin/env python3
"""gen_memmap_pdf.py -- render docs/p8x-memory-map.pdf, a one-look reference of the
whole $0000-$FFFF address space.

The load-bearing numbers (TPABASE, ROM size, the I/O-page port addresses) are pulled
from generators/memmap.inc -- the file gen_memmap.py generates -- so this PDF can never
drift from the single source. Layout and prose live in memmap_pdf.html.in; the {{TOKENS}}
there are the only things this script substitutes.

    python3 generators/gen_memmap_pdf.py           # regenerate the PDF

Rendering is headless Chrome (set $CHROME to override the binary). If memmap.inc is
stale, run gen_memmap.py first. GENERATORS ARE CANON -- do not hand-edit the PDF.
"""
import os, re, sys, subprocess, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
INC = os.path.join(HERE, "memmap.inc")
TEMPLATE = os.path.join(HERE, "memmap_pdf.html.in")
OUT_PDF = os.path.join(ROOT, "docs", "p8x-memory-map.pdf")

CHROME = os.environ.get("CHROME") or \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# --- 1. read the canonical address map ---------------------------------------
if not os.path.exists(INC):
    sys.exit("error: %s missing -- run gen_memmap.py first" % INC)
SYM = {}
for line in open(INC):
    m = re.match(r"\s*([A-Za-z_]\w*)\s*=\s*\$([0-9A-Fa-f]+)", line)
    if m:
        SYM[m.group(1)] = int(m.group(2), 16)

def need(name):
    if name not in SYM:
        sys.exit("error: symbol %s not in memmap.inc (renamed in gen_memmap.py?)" % name)
    return SYM[name]

def a4(v):    return "$%04X" % v            # full 16-bit address
def lo2(v):   return "%02X" % (v & 0xFF)    # trailing byte, for a range end

# --- 2. the I/O-page table (addresses from source, labels curated here) ------
# each row: (start-symbol, end-symbol-or-None, label, small-note, pending?)
IO_SPEC = [
    ("SWITCHES", None,     "Switches",       "rd",         False),
    ("LEDS",     None,     "LED latch",      "wr",         False),
    ("ACIAS",    "ACIAD",  "ACIA 1",         "console",    False),
    ("IRQGEN",   None,     "IRQ assert",     "wr",         False),
    ("ACIA2S",   "ACIA2D", "ACIA 2",         "serial",     False),
    ("CFDATA",   "CFCMD",  "CF-IDE",         "drive 0",    False),
    (0xFF18,     0xFF1F,   "CF-IDE",         "drive 1 &#9871;", True),   # not in memmap yet
    ("MDA",      "MDQH",   "MDU",            "mul/div",    False),
    ("GLDATA",   "GLID",   "GL graphics",    "",           False),
    ("PSADAT",   "PSID",   "PS/2 kbd+mouse", "",           False),
]

def resolve(x):
    return x if isinstance(x, int) else need(x)

def addr_text(start, end):
    s = resolve(start)
    if end is None:
        return a4(s)
    return "%s&#8211;%s" % (a4(s), lo2(resolve(end)))

io_rows = []
for start, end, label, small, pending in IO_SPEC:
    cls = "iorow pending" if pending else "iorow"
    sm = ' <small>%s</small>' % small if small else ''
    io_rows.append('          <div class="%s"><span class="p">%s%s</span>'
                   '<span class="a">%s</span></div>'
                   % (cls, label, sm, addr_text(start, end)))
IO_ROWS = "\n".join(io_rows)

# compact one-line summary shown inside the map's I/O band
IO_SUMMARY = ("One decoded page. Switches %s &#183; LEDs %s &#183; dual ACIA %s/%s "
              "&#183; CF-IDE %s &#183; MDU %s &#183; GL graphics %s &#183; "
              "PS/2 keyboard+mouse %s.") % (
    a4(need("SWITCHES")), a4(need("LEDS")), a4(need("ACIAS")), a4(need("ACIA2S")),
    a4(need("CFDATA")), a4(need("MDA")), a4(need("GLDATA")), a4(need("PSADAT")))

# --- 3. headline facts, computed from source ---------------------------------
romsize = need("ROMSIZE")                       # 6K -> ROM is $0000..ROMSIZE-1
tpabase = need("TPABASE")
cstack  = need("CSTACKTOP")                      # TPA runs up to CSTACKTOP-1
iobase  = need("IOBASE")
tpa_kb  = (cstack - tpabase) / 1024.0

FACT_ROM      = "%d&nbsp;KB <span class=\"u\">$0000&#8211;%s</span>" % (romsize // 1024, a4(romsize - 1))
FACT_TPA_SIZE = "%.1f&nbsp;KB" % tpa_kb

# --- 4. sanity-check the static band labels still match the source -----------
# (these addresses appear as fixed text in the template; warn if the map moved)
for name, want in [("RAMBASE", 0x1800), ("SBUF", 0x1D00), ("TPABASE", 0x5900),
                   ("CSTACKTOP", 0xF800), ("IOBASE", 0xFF00), ("ROMSIZE", 0x1800)]:
    if SYM.get(name) != want:
        print("  WARNING: %s is %s in memmap.inc but the template's static bands "
              "assume $%04X -- edit memmap_pdf.html.in" % (name, a4(SYM.get(name, 0)), want))

# --- 5. fill the template ----------------------------------------------------
html = open(TEMPLATE).read()
subs = {
    "STAMP": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "TPABASE": a4(tpabase),
    "IOBASE": a4(iobase),
    "FACT_ROM": FACT_ROM,
    "FACT_TPA_SIZE": FACT_TPA_SIZE,
    "IO_SUMMARY": IO_SUMMARY,
    "IO_ROWS": IO_ROWS,
    "ACIA2S": a4(need("ACIA2S")),
    "GLDATA": a4(need("GLDATA")),
    "PSADAT": a4(need("PSADAT")),
}
for k, v in subs.items():
    html = html.replace("{{%s}}" % k, v)
left = re.findall(r"\{\{(\w+)\}\}", html)
if left:
    sys.exit("error: unfilled template tokens: %s" % sorted(set(left)))

tmp_html = os.path.join(HERE, "memmap_pdf.gen.html")
open(tmp_html, "w").write(html)

# --- 6. render with headless Chrome ------------------------------------------
if not os.path.exists(CHROME):
    sys.exit("error: Chrome not found at %s (set $CHROME)\n  intermediate HTML: %s"
             % (CHROME, tmp_html))
subprocess.run([CHROME, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                "--no-margins", "--print-to-pdf=%s" % OUT_PDF,
                "file://%s" % tmp_html],
               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
os.remove(tmp_html)
print("wrote", os.path.relpath(OUT_PDF, ROOT),
      "(%.1f KB)" % (os.path.getsize(OUT_PDF) / 1024.0))
