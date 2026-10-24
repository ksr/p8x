#!/usr/bin/env python3
"""P8X schematic symbol library: pin TYPES and left/right LAYOUT for every
device in generators/gen_eagle.py, so the canonical netlists can be rendered as
KiCad schematics (ported from the P32X schematic toolchain).

gen_eagle.DEV already carries each device's pin -> pad-number map (datasheet-
verified). This module adds, per device, the electrical TYPE of each pin
(in/out/tri/bidir/oc/pwr/gnd/pas) and the order pins sit on the left and right of
the drawn symbol (inputs left, outputs right, by convention). From those three
things p8x_kicad_sch.py draws a symbol with correctly-typed pins -- no external
KiCad symbol library needed -- and the ELK wiring and ERC both use the types.

SYM[dev] = dict(pkg, value, footprint, pins={name:(number, type)}, layout=(L,R))
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import gen_eagle as GE          # pin->number maps, CARDS, busnet, ALLPINS (pure python, no pcbnew)

# KiCad library footprint per package / per device (mirrors gen_kicad.FPMAP +
# DEV_FP; kept here so the schematic toolchain needs no pcbnew). The footprint is
# the board link + BOM field; "" is acceptable for the schematic itself.
_D = "Package_DIP:"
FP_PKG = {
    "DIP8": _D + "DIP-8_W7.62mm", "DIP14": _D + "DIP-14_W7.62mm",
    "DIP16": _D + "DIP-16_W7.62mm", "DIP20": _D + "DIP-20_W7.62mm",
    "DIP24N": _D + "DIP-24_W7.62mm", "DIP24W": _D + "DIP-24_W15.24mm",
    "DIP28N": _D + "DIP-28_W7.62mm", "DIP28W": _D + "DIP-28_W15.24mm",
    "DIP40": _D + "DIP-40_W15.24mm",
    "C_DISC1": "Capacitor_THT:C_Disc_D5.0mm_W2.5mm_P5.00mm",
    "C_DISC": "Capacitor_THT:C_Disc_D5.0mm_W2.5mm_P5.00mm",
    "LED5": "LED_THT:LED_D5.0mm",
    "R_AXIAL": "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",
    "HDR3": "Connector_PinHeader_2.54mm:PinHeader_1x03_P2.54mm_Vertical",
    "HDR4": "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical",
    "HDR10": "Connector_PinHeader_2.54mm:PinHeader_1x10_P2.54mm_Vertical",
    "MABC96R": "Connector_DIN:DIN41612_C_3x32_Male_Horizontal_THT",
    "DSUB9": "Connector_Dsub:DSUB-9_Socket_Horizontal_P2.77x2.54mm_EdgePinOffset9.40mm",
    "HDR2X3": "Connector_PinHeader_2.54mm:PinHeader_2x03_P2.54mm_Vertical",
    "MINIDIN6": "",     # local custom footprint on the board; omitted from the schematic link
    "HDR40": "Connector_PinHeader_2.54mm:PinHeader_2x20_P2.54mm_Vertical",
    "OSC4": "Oscillator:Oscillator_DIP-14",
    "SIP9": "Resistor_THT:R_Array_SIP9",
    "SIP16": "Connector_PinHeader_2.54mm:PinHeader_1x16_P2.54mm_Vertical",
    "CP_RADIAL": "Capacitor_THT:CP_Radial_D8.0mm_P3.50mm",
    "SW2P": "Button_Switch_THT:SW_PUSH_6mm",
    "PICO40": "Module:RaspberryPi_Pico_Common_THT",
    "FABC96S": "Connector_DIN:DIN41612_C_3x32_Female_Vertical_THT",   # backplane slot (female)
    "TB4": "Connector_Phoenix_MSTB:PhoenixContact_MSTBA_2,5_4-G-5,08_1x04_P5.08mm_Horizontal",
}
FP_DEV = {
    "DIP8SW": "Button_Switch_THT:SW_DIP_SPSTx08_Slide_9.78x22.5mm_W7.62mm_P2.54mm",
    "IDE40": "Connector_IDC:IDC-Header_2x20_P2.54mm_Vertical",
    "XTAL32": "Crystal:Crystal_Round_D3.0mm_Vertical",
    "LEDARR8": _D + "DIP-16_W7.62mm", "RNISO8D": _D + "DIP-16_W7.62mm",
    "RNISO8": "Connector_PinHeader_2.54mm:PinHeader_1x16_P2.54mm_Vertical",
    "COIN": "Battery:BatteryHolder_Keystone_103_1x20mm",
}

# ---------------------------------------------------------------- pin types
# in  input            out totem-pole output     tri 3-state output
# bidir bidirectional  oc  open-drain/collector   pwr +5V   gnd 0V   pas passive
def _seq(prefix, lo, hi):
    return ["%s%d" % (prefix, i) for i in range(lo, hi + 1)]

# helper: assign one type to a list of pins
def _T(pins, t):
    return {p: t for p in pins}

# Each entry: dev -> (types dict {pin:type}, (left_pins, right_pins)).
# Pins not named in the types dict default by heuristic in build(): VCC/AVCC/VP->pwr,
# GND*/VSS/VM->gnd, everything else->pas. Power/ground pins are never in L/R (they
# are drawn top/bottom), so L/R lists only the signal pins, in display order.
TYPES = {}
LAYOUT = {}

def dev(name, types, left, right):
    TYPES[name] = types
    LAYOUT[name] = (left, right)

# ---- logic gates ------------------------------------------------------------
# GATES14 = quad 2-input (74HCT08/32/86); 7402 = quad 2-input NOR
_G4_in = ["1A", "1B", "2A", "2B", "3A", "3B", "4A", "4B"]
_G4_out = ["1Y", "2Y", "3Y", "4Y"]
dev("GATES14", {**_T(_G4_in, "in"), **_T(_G4_out, "out")},
    _G4_in, ["1Y", None, "2Y", None, "3Y", None, "4Y", None])
dev("7402", {**_T(_G4_in, "in"), **_T(_G4_out, "out")},
    _G4_in, ["1Y", None, "2Y", None, "3Y", None, "4Y", None])
# 7410 = triple 3-input NAND
_G3_in = ["1A", "1B", "1C", "2A", "2B", "2C", "3A", "3B", "3C"]
dev("7410", {**_T(_G3_in, "in"), **_T(["1Y", "2Y", "3Y"], "out")},
    _G3_in, ["1Y", None, None, "2Y", None, None, "3Y", None, None])
# 7430 = 8-input NAND
dev("7430", {**_T(list("ABCDEFGH"), "in"), "Y": "out"},
    list("ABCDEFGH"), ["Y"])
# HEX14 = hex inverter (74HC14)
_HEXin = ["1A", "2A", "3A", "4A", "5A", "6A"]
_HEXout = ["1Y", "2Y", "3Y", "4Y", "5Y", "6Y"]
dev("HEX14", {**_T(_HEXin, "in"), **_T(_HEXout, "out")}, _HEXin, _HEXout)
# 74260 = dual 5-input NOR
_260in = ["A1", "B1", "C1", "D1", "E1", "A2", "B2", "C2", "D2", "E2"]
dev("74260", {**_T(_260in, "in"), **_T(["Y1", "Y2"], "out")},
    _260in, ["Y1", None, None, None, None, "Y2", None, None, None, None])

# ---- decoders ---------------------------------------------------------------
dev("74138", {**_T(["A", "B", "C", "G1", "!G2A", "!G2B"], "in"), **_T(_seq("Y", 0, 7), "out")},
    ["A", "B", "C", "G1", "!G2A", "!G2B"], _seq("Y", 0, 7))
dev("74139", {**_T(["!G1", "A1", "B1", "!G2", "A2", "B2"], "in"),
              **_T(["1Y0", "1Y1", "1Y2", "1Y3", "2Y0", "2Y1", "2Y2", "2Y3"], "out")},
    ["!G1", "A1", "B1", "!G2", "A2", "B2"],
    ["1Y0", "1Y1", "1Y2", "1Y3", "2Y0", "2Y1", "2Y2", "2Y3"])

# ---- counters ---------------------------------------------------------------
dev("74161", {**_T(["!CLR", "CLK", "A", "B", "C", "D", "ENP", "!LOAD", "ENT"], "in"),
              **_T(["QA", "QB", "QC", "QD", "RCO"], "out")},
    ["!CLR", "CLK", "!LOAD", "ENP", "ENT", "A", "B", "C", "D"],
    ["QA", "QB", "QC", "QD", "RCO"])
dev("74169", {**_T(["UD", "CLK", "A", "B", "C", "D", "!ENP", "!LOAD", "!ENT"], "in"),
              **_T(["QA", "QB", "QC", "QD", "!RCO"], "out")},
    ["UD", "CLK", "!LOAD", "!ENP", "!ENT", "A", "B", "C", "D"],
    ["QA", "QB", "QC", "QD", "!RCO"])

# ---- latches / flip-flops ---------------------------------------------------
dev("74374", {**_T(["!OC", "CLK"] + _seq("D", 1, 8), "in"), **_T(_seq("Q", 1, 8), "tri")},
    ["!OC", "CLK"] + _seq("D", 1, 8), [None, None] + _seq("Q", 1, 8))
dev("74377V2", {**_T(["!E", "CLK"] + _seq("D", 1, 8), "in"), **_T(_seq("Q", 1, 8), "out")},
    ["!E", "CLK"] + _seq("D", 1, 8), [None, None] + _seq("Q", 1, 8))
dev("74175", {**_T(["!CLR", "CLK"] + _seq("D", 1, 4), "in"),
              **_T(_seq("Q", 1, 4) + ["!Q1", "!Q2", "!Q3", "!Q4"], "out")},
    ["!CLR", "CLK", "D1", "D2", "D3", "D4"],
    ["Q1", "!Q1", "Q2", "!Q2", "Q3", "!Q3", "Q4", "!Q4"])
dev("7474", {**_T(["!1CLR", "1D", "1CLK", "!1PRE", "!2CLR", "2D", "2CLK", "!2PRE"], "in"),
             **_T(["1Q", "!1Q", "2Q", "!2Q"], "out")},
    ["!1CLR", "1D", "1CLK", "!1PRE", "!2CLR", "2D", "2CLK", "!2PRE"],
    ["1Q", "!1Q", None, None, "2Q", "!2Q", None, None])

# ---- buffers / transceivers / muxes ----------------------------------------
dev("74244", {**_T(["!G1", "!G2"] + _seq("A", 1, 8), "in"), **_T(_seq("Y", 1, 8), "tri")},
    ["!G1", "A1", "A2", "A3", "A4", "!G2", "A5", "A6", "A7", "A8"],
    [None, "Y1", "Y2", "Y3", "Y4", None, "Y5", "Y6", "Y7", "Y8"])
dev("74245", {**_T(["DIR", "!OE"], "in"), **_T(_seq("A", 0, 7) + _seq("B", 0, 7), "bidir")},
    ["DIR", "!OE"] + _seq("B", 0, 7), [None, None] + _seq("A", 0, 7))
dev("74151", {**_T(["A", "B", "C", "!G"] + _seq("D", 0, 7), "in"), **_T(["Y", "!W"], "out")},
    ["A", "B", "C", "!G"] + _seq("D", 0, 7),
    ["Y", "!W"] + [None] * 10)
dev("74157", {**_T(["S", "!G"] + _seq("A", 1, 4) + _seq("B", 1, 4), "in"), **_T(_seq("Y", 1, 4), "out")},
    ["S", "!G", "A1", "B1", "A2", "B2", "A3", "B3", "A4", "B4"],
    [None, None, "Y1", None, "Y2", None, "Y3", None, "Y4", None])
dev("74257", {**_T(["S", "!OE"] + _seq("A", 1, 4) + _seq("B", 1, 4), "in"), **_T(_seq("Y", 1, 4), "tri")},
    ["S", "!OE", "A1", "B1", "A2", "B2", "A3", "B3", "A4", "B4"],
    [None, None, "Y1", None, "Y2", None, "Y3", None, "Y4", None])

# ---- ALU --------------------------------------------------------------------
dev("74181", {**_T(_seq("A", 0, 3) + _seq("B", 0, 3) + _seq("S", 0, 3) + ["M", "CN"], "in"),
              **_T(["F0", "F1", "F2", "F3", "CN4", "!P", "!G"], "out"), "AEB": "oc"},
    ["A0", "B0", "A1", "B1", "A2", "B2", "A3", "B3", "S0", "S1", "S2", "S3", "M", "CN"],
    ["F0", "F1", "F2", "F3", "CN4", "!P", "!G", "AEB"])
dev("74182", {**_T(["!G0", "!G1", "!G2", "!G3", "!P0", "!P1", "!P2", "!P3", "CN"], "in"),
              **_T(["!P", "!G", "CNX", "CNY", "CNZ"], "out")},
    ["!G0", "!P0", "!G1", "!P1", "!G2", "!P2", "!G3", "!P3", "CN"],
    ["!G", "!P", "CNX", "CNY", "CNZ"])

# ---- comparator -------------------------------------------------------------
dev("74688", {**_T(["!G"] + _seq("P", 0, 7) + _seq("Q", 0, 7), "in"), "!PEQ": "out"},   # 74HCT688: totem-pole P=Q output
    ["!G", "P0", "Q0", "P1", "Q1", "P2", "Q2", "P3", "Q3", "P4", "Q4", "P5", "Q5", "P6", "Q6", "P7", "Q7"],
    ["!PEQ"])

# ---- memory -----------------------------------------------------------------
dev("28C64", {**_T(_seq("A", 0, 12) + ["!CE", "!OE", "!WE"], "in"), **_T(_seq("IO", 0, 7), "bidir"),
              "RDY": "oc", "NC26": "pas"},
    _seq("A", 0, 12) + ["!CE", "!OE", "!WE", "RDY", "NC26"], _seq("IO", 0, 7))
dev("MEM28K8", {**_T(_seq("A", 0, 14) + ["!CE", "!OE", "!WE"], "in"), **_T(_seq("IO", 0, 7), "bidir")},
    _seq("A", 0, 14) + ["!CE", "!OE", "!WE"], _seq("IO", 0, 7))

# ---- ACIA / serial ----------------------------------------------------------
dev("6850", {**_T(["RXD", "RXCLK", "TXCLK", "!CTS", "!DCD", "CS0", "CS1", "!CS2", "RS", "RW", "E"], "in"),
             **_T(["TXD", "!RTS"], "out"), "!IRQ": "oc", **_T(_seq("D", 0, 7), "bidir")},
    # bus side left, serial side right, so a schematic reads bus -> ACIA -> line driver
    _seq("D", 0, 7) + ["CS0", "CS1", "!CS2", "RS", "RW", "E", "!IRQ", "RXCLK", "TXCLK"],
    ["TXD", "RXD", "!RTS", "!CTS", "!DCD"])
dev("MAX232", {**_T(["T1IN", "T2IN", "R1IN", "R2IN"], "in"), **_T(["R1OUT", "R2OUT", "T1OUT", "T2OUT"], "out"),
               **_T(["C1P", "C1M", "C2P", "C2M", "VP", "VM"], "pas")},
    # TTL side left (paired per channel, as the 6850 presents TXD/RXD); RS-232 side
    # right, the charge-pump pins below it so the pump caps sit beside the outputs
    ["T1IN", "R1OUT", "T2IN", "R2OUT"],
    ["T1OUT", "R1IN", "T2OUT", "R2IN", None, "C1P", "C1M", "C2P", "C2M", "VP", "VM"])

# ---- MCUs / programmable ----------------------------------------------------
_AVRio = _seq("PA", 0, 7) + _seq("PB", 0, 7) + _seq("PC", 0, 7) + _seq("PD", 0, 7)
dev("ATMEGA1284", {**_T(_AVRio, "bidir"), **_T(["!RESET", "XTAL1"], "in"), "XTAL2": "out", "AREF": "pas"},
    ["!RESET", "XTAL1", "XTAL2", "AREF"] + _seq("PB", 0, 7) + _seq("PD", 0, 7),
    _seq("PA", 0, 7) + _seq("PC", 0, 7))
dev("MCP23S17", {**_T(_seq("GPA", 0, 7) + _seq("GPB", 0, 7), "bidir"),
                 **_T(["!CS", "SCK", "SI", "!RESET", "A0", "A1", "A2"], "in"),
                 "SO": "tri",                        # SPI MISO: high-Z when the chip is not selected
                 **_T(["!INTA", "!INTB"], "pas")},    # unused interrupt outputs, tied off to GND on
                                                      # the bustest fixture (only board using this part)
    ["!CS", "SCK", "SI", "SO", "!RESET", "A0", "A1", "A2", "!INTA", "!INTB"],
    _seq("GPA", 0, 7) + _seq("GPB", 0, 7))
_PICOio = _seq("GP", 0, 22) + ["GP26", "GP27", "GP28"]
dev("PICO", {**_T(_PICOio, "bidir"), "!RUN": "in",
             **_T(["3V3OUT", "ADCVREF"], "pas"), "3V3EN": "in", "AGND": "gnd",
             **_T(["VSYS", "VBUS"], "pwr")},
    ["!RUN", "3V3EN", "VSYS", "VBUS", "3V3OUT", "ADCVREF"] + _seq("GP", 0, 10),
    _seq("GP", 11, 22) + ["GP26", "GP27", "GP28"])

# ---- clock / RTC ------------------------------------------------------------
dev("OSC", {"OUT": "out", "NC1": "pas"}, ["NC1"], ["OUT"])
dev("DS1302", {**_T(["X1", "CE", "SCLK"], "in"), "X2": "out", "IO": "bidir"},
    ["X1", "X2", "CE", "SCLK"], ["IO"])

# ---- connectors (all passive) ----------------------------------------------
def _passive(name, pins, left=None, right=None):
    dev(name, _T(pins, "pas"), left if left is not None else pins, right if right is not None else [])

_passive("DSUB9F", [str(i) for i in range(1, 10)])
_passive("IDE40", [str(i) for i in range(1, 41)],
         [str(i) for i in range(1, 41, 2)], [str(i) for i in range(2, 41, 2)])  # odd left, even right
_passive("HDR3", ["1", "2", "3"])
_passive("HDR4", ["1", "2", "3", "4"])
_passive("HDR10", [str(i) for i in range(1, 11)])
_passive("JMP2X3", ["1", "3", "5"] + ["2", "4", "6"], ["1", "3", "5"], ["2", "4", "6"])
_passive("MINIDIN6", ["1", "2", "3", "4", "5", "6", "SH"])
_passive("SW2", ["1", "2"], ["1"], ["2"])
_passive("DIP8SW", _seq("A", 1, 8) + _seq("B", 1, 8), _seq("A", 1, 8), ["B%d" % i for i in range(8, 0, -1)])
# DIN96C (card male) and DIN96 (backplane female): 64 pins left, 32 right
for _din in ("DIN96C", "DIN96"):
    _passive(_din, ["%s%d" % (r, n) for r in "ABC" for n in range(1, 33)],
             ["A%d" % n for n in range(1, 33)] + ["B%d" % n for n in range(1, 33)],
             ["C%d" % n for n in range(1, 33)])
_passive("TB4", ["1", "2", "3", "4"], ["1", "2"], ["3", "4"])   # 4-pos power terminal block

# ---- passives ---------------------------------------------------------------
_passive("CAP", ["1", "2"], ["1"], ["2"])
_passive("CAP1", ["1", "2"], ["1"], ["2"])
_passive("CAPP", ["+", "-"], ["+"], ["-"])   # polarized bulk electrolytic
_passive("RES", ["1", "2"], ["1"], ["2"])
_passive("XTAL32", ["1", "2"], ["1"], ["2"])
_passive("COIN", ["+", "-"], ["+"], ["-"])
_passive("LED", ["A", "K"], ["A"], ["K"])
_passive("SIP9", ["COM"] + _seq("R", 1, 8), ["COM"], _seq("R", 1, 8))
# RNISO8 / RNISO8D = 8 independent isolated resistors (A/B pairs); LEDARR8 = 8 LEDs
_passive("RNISO8", [p for i in range(1, 9) for p in ("A%d" % i, "B%d" % i)],
         _seq("A", 1, 8), _seq("B", 1, 8))
_passive("RNISO8D", _seq("A", 1, 8) + _seq("B", 1, 8), _seq("A", 1, 8), ["B%d" % i for i in range(8, 0, -1)])
_passive("LEDARR8", _seq("A", 1, 8) + _seq("K", 1, 8), _seq("A", 1, 8), ["K%d" % i for i in range(8, 0, -1)])

# ---------------------------------------------------------------- build SYM
PWR = {"VCC", "AVCC", "VCC1", "VCC2", "VDD", "VP", "VSYS", "VBUS", "3V3OUT"}
GND = {"GND", "GND2", "VSS", "VM", "AGND", "GND8", "GND13", "GND18", "GND23", "GND28", "GND38"}

def build():
    """Merge gen_eagle.DEV pin numbers with the TYPES/LAYOUT overlays above."""
    sym = {}
    for name, d in GE.DEV.items():
        if name not in TYPES:
            continue                                   # e.g. DIN96 (female) is backplane-only
        tover = TYPES.get(name, {})
        pins = {}
        for pin, num in d["pm"].items():
            if pin in tover:
                t = tover[pin]
            elif pin in PWR:
                t = "pwr"
            elif pin in GND:
                t = "gnd"
            else:
                t = "pas"
            pins[pin] = (str(num), t)
        pkg = d["pkg"]
        fp = FP_DEV.get(name) or FP_PKG.get(pkg, "")
        sym[name] = dict(pkg=pkg, value=name, footprint=fp,
                         pins=pins, layout=LAYOUT.get(name, (list(pins), [])))
    return sym

SYM = build()

# Schematic-only drawings of a device: same pins, numbers and footprint, a layout
# that shows what the part does on one card. A card adapter maps a ref to one
# (p8x_card.VARIANTS); the board and netlist never see the name.
#   JMP2X3SWAP -- the io-card RX/TX swap block: driver side (3, 4) left, connector
#   side right with each straight/crossed pair together (2+5 one DB9 pin, 1+6 the
#   other). The ps2-card's ICSP header keeps the plain 2x3 drawing.
SYM["JMP2X3SWAP"] = dict(SYM["JMP2X3"], value="JMP2X3SWAP",
                         layout=(["3", "4"], ["2", "5", "1", "6"]))
#   RNISO8DSTR -- an 8x isolated resistor DIP drawn B1..B8 top to bottom (the plain
#   RNISO8D runs B8..B1, matching a DIP's far side) for a network that feeds a
#   pin header in order: the bustest probe series resistors into J2.
SYM["RNISO8DSTR"] = dict(SYM["RNISO8D"], value="RNISO8DSTR",
                         layout=(_seq("A", 1, 8), _seq("B", 1, 8)))

if __name__ == "__main__":
    # self-check: every pin of every used device has a type and is placed
    miss = []
    for name, s in sorted(SYM.items()):
        L, R = s["layout"]
        placed = {p for p in (L + R) if p}
        sigpins = {p for p, (n, t) in s["pins"].items() if t not in ("pwr", "gnd")}
        gap = sigpins - placed
        extra = placed - set(s["pins"])
        if gap or extra:
            miss.append((name, sorted(gap), sorted(extra)))
    if miss:
        for n, g, e in miss:
            print("  %-12s missing-from-layout=%s  not-a-pin=%s" % (n, g, e))
        sys.exit("symlib: %d device(s) with layout gaps" % len(miss))
    print("p8x_symlib: %d devices OK (types + layout complete)" % len(SYM))
