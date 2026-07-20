#!/usr/bin/env python3
"""Breadboard-Arduino test board (ATmega328P from scratch) — a Cowork<->Fusion
workflow probe, NOT part of the P8X machine.

Minimal standalone AVR board after the classic "Arduino from scratch" recipe:
ATmega328P-PU + 16 MHz crystal + reset pull-up + a 7805 5 V regulator (with in/out
caps) + a 6-pin FTDI programming/serial header (with the DTR auto-reset cap) + a
pin-13 LED and a power LED. Through-hole only.

Reuses gen_eagle's low-level emitters (write_sch / write_brd / validate) and its
device library, but NOT card() — card() forces a P8X DIN96 edge connector, and
this board has none. Emits Eagle .sch/.brd into hardware/arduino-scratch/, parts
parked off-board (unplaced) with the ratsnest, ready to place + route in Fusion.

    python3 generators/gen_arduino.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_eagle as G

OUTDIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "hardware", "arduino-scratch")

# ---- new footprints (through-hole; (pad, x, y, drill, dia) in mm) --------------
G.PKG["HC49"]  = [("1",0,0,0.8,1.6), ("2",4.88,0,0.8,1.6)]                  # HC-49/U crystal
G.PKG["TO220"] = [("1",0,0,1.0,2.0), ("2",2.54,0,1.0,2.0), ("3",5.08,0,1.0,2.0)]
G.PKG["HDR6"]  = [(str(k+1),0,-2.54*k,0.9,1.8) for k in range(6)]           # 1x6 FTDI
G.PKG["HDR2"]  = [(str(k+1),0,-2.54*k,0.9,1.8) for k in range(2)]           # 1x2 power in

# ---- new devices (pin-name -> pad map) -----------------------------------------
# ATmega328P-PU, 28-pin narrow DIP. Pins named by primary function; pm maps each
# to its physical pad (1..28). L = pads 1..14, R = pads 15..28.
_L = ["RESET","RXD","TXD","PD2","PD3","PD4","VCC","GND1","XTAL1","XTAL2","PD5","PD6","PD7","PB0"]
_R = ["PB1","PB2","MOSI","MISO","SCK","AVCC","AREF","GND2","PC0","PC1","PC2","PC3","SDA","SCL"]
_pm = {n:str(i+1)  for i,n in enumerate(_L)}
_pm.update({n:str(i+15) for i,n in enumerate(_R)})
G.D("ATMEGA328", _L, _R, _pm, "DIP28N")
G.D("XTAL16", ["1","2"], [], {"1":"1","2":"2"}, "HC49")
G.D("L7805",  ["IN","GND","OUT"], [], {"IN":"1","GND":"2","OUT":"3"}, "TO220")
G.D("HDR6",   [str(k) for k in range(1,7)], [], {str(k):str(k) for k in range(1,7)}, "HDR6")
G.D("HDR2",   ["1","2"], [], {"1":"1","2":"2"}, "HDR2")

# ---- parts: ref -> (device, value) ---------------------------------------------
parts = {
    "U1":("ATMEGA328","ATMEGA328P-PU"), "U2":("L7805","7805"),
    "Y1":("XTAL16","16MHZ"),
    "C1":("CAP","22P"), "C2":("CAP","22P"),            # crystal load caps
    "C3":("CAP","100N"), "C4":("CAP","100N"),          # VCC / AVCC decoupling
    "C5":("CAP","100N"),                               # DTR auto-reset cap
    "C6":("CAPP","10U"), "C7":("CAPP","10U"),          # 7805 in / out
    "R1":("RES","10K"),                                # RESET pull-up
    "R2":("RES","330R"), "R3":("RES","1K"),            # pin-13 LED / power LED
    "LED1":("LED","YEL"), "LED2":("LED","GRN"),        # pin-13 / power
    "J1":("HDR6","FTDI"), "J2":("HDR2","7-12V DC"),
}

# ---- nets: name -> [(ref, pin), ...] -------------------------------------------
n = {}
def net(name, *pins): n.setdefault(name, []).extend(pins)

net("VCC", ("U1","VCC"),("U1","AVCC"),("U2","OUT"),("J1","3"),
           ("C3","1"),("C4","1"),("C7","+"),("R1","1"),("R3","1"))
net("GND", ("U1","GND1"),("U1","GND2"),("U2","GND"),("J1","1"),("J1","2"),("J2","2"),
           ("C1","2"),("C2","2"),("C3","2"),("C4","2"),("C6","-"),("C7","-"),
           ("LED1","K"),("LED2","K"))            # C5 low side is RESET, not GND (auto-reset pulse)
net("VIN", ("J2","1"),("U2","IN"),("C6","+"))              # raw 7-12 V in -> 7805
net("RESET", ("U1","RESET"),("R1","2"),("C5","2"))         # pull-up + DTR cap
net("DTR",  ("J1","6"),("C5","1"))                         # FTDI DTR -> cap -> RESET (auto-reset)
net("RXD",  ("U1","RXD"),("J1","4"))                       # FTDI TXD -> MCU RXD
net("TXD",  ("U1","TXD"),("J1","5"))                       # MCU TXD -> FTDI RXD
net("XTAL1",("U1","XTAL1"),("Y1","1"),("C1","1"))
net("XTAL2",("U1","XTAL2"),("Y1","2"),("C2","1"))
net("D13",  ("U1","SCK"),("R2","1"))                       # PB5 = Arduino pin 13
net("LED13",("R2","2"),("LED1","A"))
net("PWRLED",("R3","2"),("LED2","A"))

# ---- simple schematic layout (grid) + emit -------------------------------------
order = list(parts)
sch = {}
for i, ref in enumerate(order):
    dev, val = parts[ref]
    sch[ref] = (dev, val, 20 + (i % 5) * 45.0, 80 - (i // 5) * 45.0)

W, H = 76.2, 50.8   # 3.0" x 2.0"
os.makedirs(OUTDIR, exist_ok=True)
base = os.path.join(OUTDIR, "arduino-scratch")
title = "BREADBOARD ARDUINO (ATmega328P) - Cowork/Fusion workflow test"
G.write_sch(base + ".sch", title, sch, n)
G.validate(base + ".sch", sch, n)
G.write_brd(base + ".brd", title, sch, n, {}, {}, W, H, unplaced=True)
G.validate(base + ".brd", sch, n)
print("wrote", base + ".sch", "and", base + ".brd")
print("parts:", len(parts), " nets:", len(n))
