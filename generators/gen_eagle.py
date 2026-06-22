#!/usr/bin/env python3
"""P8X Eagle generator. Emits schematic+board pairs for all 7 boards, each in its
own subdirectory:
  backplane/p8x-backplane.sch/.brd      (rev C, 10 slots, fully routed 4-layer)
  memory-card/p8x-memory-card.sch/.brd  (rev C, placed + planes, signals unrouted)
  control-card/p8x-control-card.sch/.brd
  regbank-card/p8x-regbank-card.sch/.brd
  alu-card/p8x-alu-card.sch/.brd
  io-card/p8x-io-card.sch/.brd
  cf-card/p8x-cf-card.sch/.brd
Board stack: Top(1) signals / Route2(2) GND plane / Route15(15) +5V plane / Bottom(16) signals.
Output: each board's .sch/.brd pair goes in its own subdirectory of the current
working directory (e.g. control-card/p8x-control-card.sch), so run from hardware/.
NOTE: new device pin numbers require a datasheet verification pass before fab (tracked in BACKLOG)."""

import os
G=2.54; PIN_X=17.78; STUB=5.08

# ===================== BUS =====================================================
def busnet(pin):
    r,n=pin[0],int(pin[1:])
    if n in (1,2): return "VCC"
    if n in (31,32): return "GND"
    if r=="B":
        if n in (27,28,29,30): return {27:"CLRC",28:"BSEL",29:"IRQ",30:"SPARE11"}[n]
        # B3-26: alternate ground guard (odd pins) / spare line (even pins). The
        # odd-pin grounds still shield between the data bus (row A) and address
        # bus (row C); the 12 even pins are SPARE12..23 — usable later with no
        # backplane respin.
        if 3<=n<=26 and n%2==0: return "SPARE%d"%(12+(n-4)//2)
        return "GND"
    if r=="A":
        if 3<=n<=10: return "D%d"%(n-3)
        if n==11: return "-RES"
        if 12<=n<=15: return "DOE%d"%(n-12)
        if 16<=n<=19: return "DLD%d"%(n-16)
        return {20:"PSEL0",21:"PSEL1",22:"PINC",23:"PDEC",24:"CLK",25:"CLKB",26:"LDF",
                27:"FC",28:"FZ",29:"FN",30:"FV"}.get(n)
    if 3<=n<=18: return "A%d"%(n-3)
    if 19<=n<=22: return "ALUS%d"%(n-19)
    # rev C3: C27-30 + B27 carry the rev-B control signals. B28=BSEL (rev C: ALU
    # B-input mux select); B29=IRQ (rev C, reserved for the interrupt controller);
    # SPARE11 remains on B30
    return {23:"ALUM",24:"CIN",25:"SH0",26:"SH1",
            27:"PSEL2",28:"LDZN",29:"SHCIN",30:"SETC"}.get(n,"SPARE%d"%(n-27+4))

ALLPINS=["%s%d"%(r,n) for r in "ABC" for n in range(1,33)]

# Only write/validate the .sch/.brd files when this module is RUN directly.
# Importing it (renderers use busnet/DEV/CARDS) must have NO filesystem side
# effects — otherwise an `import gen_eagle` from any CWD scatters board files.
# The net/CARDS data is still built on import; only the file emission is gated.
EMIT = (__name__ == "__main__")

# ===================== PACKAGES ================================================
def dip_pads(n,rowsep):
    half=n//2; p=[]
    for k in range(1,n+1):
        if k<=half: x,y=0,-G*(k-1)
        else: x,y=rowsep,-G*(n-k)
        p.append((str(k),x,y,0.8128,1.6))
    return p

PKG={
 "DIP8":  dip_pads(8,7.62),
 "DIP14": dip_pads(14,7.62), "DIP16": dip_pads(16,7.62),
 "DIP20": dip_pads(20,7.62), "DIP24W": dip_pads(24,15.24),
 "DIP28W": dip_pads(28,15.24),
 # DIN 41612 96-pin footprints from Eagle's con-vg library (geometry baked in so
 # the generator stays self-contained). Rows A/B/C at x=-2.54/0/+2.54, 32 positions
 # from y=+39.37 at 2.54mm pitch; octagon pads drill 0.9144 (round here — cosmetic);
 # two mounting holes at x=-0.3048, y=±45.0, drill 2.794. Backplane = FABC96S
 # (female vertical), card = MABC96R (male right-angle); both share this pad map.
 "FABC96S": [(pin,{"A":-2.54,"B":0.0,"C":2.54}[pin[0]],39.37-G*(int(pin[1:])-1),0.9144,1.524) for pin in ALLPINS]
            + [("MH1",-0.3048,45.0,2.794,2.794),("MH2",-0.3048,-45.0,2.794,2.794)],
 "MABC96R": [(pin,{"A":-2.54,"B":0.0,"C":2.54}[pin[0]],39.37-G*(int(pin[1:])-1),0.9144,1.524) for pin in ALLPINS]
            + [("MH1",-0.3048,45.0,2.794,2.794),("MH2",-0.3048,-45.0,2.794,2.794)],
 "SIP9":  [(str(k),0,-G*(k-1),0.8,1.6) for k in range(1,10)],
 "SIP16": [(str(k),0,-2.54*k,0.8,1.6) for k in range(1,17)],
 "R_AXIAL": [("1",0,0,0.8,1.6),("2",10.16,0,0.8,1.6)],
 "C_DISC":  [("1",0,0,0.9,1.8),("2",0,-5.08,0.9,1.8)],   # 0.2" (5.08mm) lead pitch
 "C_DISC1": [("1",0,0,0.9,1.8),("2",0,-2.54,0.9,1.8)],   # 0.1" (2.54mm) lead pitch — 100nF bypass caps
 "CP_RADIAL":[("1",0,0,0.9,1.8),("2",0,-5.08,0.9,1.8)],
 "TB4":  [(str(k+1),0,-5.08*k,1.3,3.0) for k in range(4)],
 "LED5": [("2",0,0,0.9,1.8),("1",2.54,0,0.9,1.8)],
 "OSC4": [("1",0,0,0.8,1.6),("7",0,-15.24,0.8,1.6),("8",7.62,-15.24,0.8,1.6),("14",7.62,0,0.8,1.6)],
 "HDR4": [(str(k+1),0,-2.54*k,0.9,1.8) for k in range(4)],
 "HDR3": [(str(k+1),0,-2.54*k,0.9,1.8) for k in range(3)],
 "SW2P": [("1",0,0,1.0,1.9),("2",5.08,0,1.0,1.9)],
 "HDR40": [(str(k+1),2.54*(k%2),-2.54*(k//2),0.9,1.7) for k in range(40)],
}

# ===================== DEVICES =================================================
def gates14():
    return dict(L=["1A","1B","2A","2B","3A","3B","4A","4B"],
                R=["1Y","2Y","3Y","4Y","VCC","GND"],
                pm={"1A":"1","1B":"2","1Y":"3","2A":"4","2B":"5","2Y":"6","GND":"7",
                    "3Y":"8","3A":"9","3B":"10","4Y":"11","4A":"12","4B":"13","VCC":"14"},pkg="DIP14")

DEV={
 "MEM28K8": dict(L=["A%d"%i for i in range(15)],
   R=["IO%d"%i for i in range(8)]+["!CE","!OE","!WE","VCC","GND"],
   pm={"A14":"1","A12":"2","A7":"3","A6":"4","A5":"5","A4":"6","A3":"7","A2":"8","A1":"9","A0":"10",
       "IO0":"11","IO1":"12","IO2":"13","GND":"14","IO3":"15","IO4":"16","IO5":"17","IO6":"18","IO7":"19",
       "!CE":"20","A10":"21","!OE":"22","A11":"23","A9":"24","A8":"25","A13":"26","!WE":"27","VCC":"28"},
   pkg="DIP28W"),
 "74245": dict(L=["DIR"]+["A%d"%i for i in range(8)]+["!OE"],
   R=["B%d"%i for i in range(8)]+["VCC","GND"],
   pm={"DIR":"1","A0":"2","A1":"3","A2":"4","A3":"5","A4":"6","A5":"7","A6":"8","A7":"9","GND":"10",
       "B7":"11","B6":"12","B5":"13","B4":"14","B3":"15","B2":"16","B1":"17","B0":"18","!OE":"19","VCC":"20"},
   pkg="DIP20"),
 "7430": dict(L=list("ABCDEFGH"),R=["Y","VCC","GND"],
   pm={"A":"1","B":"2","C":"3","D":"4","E":"5","F":"6","GND":"7","Y":"8","G":"11","H":"12","VCC":"14"},pkg="DIP14"),
 "74138": dict(L=["A","B","C","G1","!G2A","!G2B"],
   R=["Y%d"%i for i in range(8)]+["VCC","GND"],
   pm={"A":"1","B":"2","C":"3","!G2A":"4","!G2B":"5","G1":"6","Y7":"7","GND":"8","Y6":"9","Y5":"10",
       "Y4":"11","Y3":"12","Y2":"13","Y1":"14","Y0":"15","VCC":"16"},pkg="DIP16"),
 "GATES14": gates14(),
 "DIN96": dict(L=["A%d"%i for i in range(1,33)]+["B%d"%i for i in range(1,33)],
   R=["C%d"%i for i in range(1,33)],pm={p:p for p in ALLPINS},pkg="FABC96S"),
 "CAP":  dict(L=["1"],R=["2"],pm={"1":"1","2":"2"},pkg="C_DISC"),
 # 100nF bypass/decoupling caps: identical symbol to CAP, but 0.1" lead pitch.
 "CAP1": dict(L=["1"],R=["2"],pm={"1":"1","2":"2"},pkg="C_DISC1"),
 "CAPP": dict(L=["+"],R=["-"],pm={"+":"1","-":"2"},pkg="CP_RADIAL"),
 # rev C RTC (DS1302, DIP8) + its 32.768kHz tuning-fork crystal and backup coin
 # cell. XTAL32/COIN reuse generic 2-pin THT footprints as placeholders — VERIFY
 # the physical land pattern against the parts you buy before fab.
 "DS1302": dict(L=["X1","X2","CE","IO","SCLK"],R=["VCC2","GND","VCC1"],
   pm={"VCC2":"1","X1":"2","X2":"3","GND":"4","CE":"5","IO":"6","SCLK":"7","VCC1":"8"},pkg="DIP8"),
 "XTAL32": dict(L=["1"],R=["2"],pm={"1":"1","2":"2"},pkg="C_DISC"),
 "COIN":   dict(L=["+"],R=["-"],pm={"+":"1","-":"2"},pkg="CP_RADIAL"),
 "RES":  dict(L=["1"],R=["2"],pm={"1":"1","2":"2"},pkg="R_AXIAL"),
 "SIP9": dict(L=["COM"],R=["R%d"%i for i in range(1,9)],
   pm=dict([("COM","1")]+[("R%d"%i,str(i+1)) for i in range(1,9)]),pkg="SIP9"),
 "TB4":  dict(L=["1","2"],R=["3","4"],pm={str(k):str(k) for k in range(1,5)},pkg="TB4"),
 "LED":  dict(L=["A"],R=["K"],pm={"A":"2","K":"1"},pkg="LED5"),
}

def D(name,L,R,pm,pkg): DEV[name]=dict(L=L,R=R,pm=pm,pkg=pkg)

# Card edge connector: same electrical part as the backplane DIN96, but the
# MABC96R (male right-angle) footprint instead of FABC96S (female vertical).
DEV["DIN96C"]={**DEV["DIN96"],"pkg":"MABC96R"}

D("74161",["!CLR","CLK","A","B","C","D","ENP","!LOAD","ENT"],
  ["QA","QB","QC","QD","RCO","VCC","GND"],
  {"!CLR":"1","CLK":"2","A":"3","B":"4","C":"5","D":"6","ENP":"7","GND":"8","!LOAD":"9",
   "ENT":"10","QD":"11","QC":"12","QB":"13","QA":"14","RCO":"15","VCC":"16"},"DIP16")
D("74169",["UD","CLK","A","B","C","D","!ENP","!LOAD","!ENT"],
  ["QA","QB","QC","QD","!RCO","VCC","GND"],
  {"UD":"1","CLK":"2","A":"3","B":"4","C":"5","D":"6","!ENP":"7","GND":"8","!LOAD":"9",
   "!ENT":"10","QD":"11","QC":"12","QB":"13","QA":"14","!RCO":"15","VCC":"16"},"DIP16")
PM374={"!OC":"1","Q1":"2","D1":"3","D2":"4","Q2":"5","Q3":"6","D3":"7","D4":"8","Q4":"9",
 "GND":"10","CLK":"11","Q5":"12","D5":"13","D6":"14","Q6":"15","Q7":"16","D7":"17","D8":"18",
 "Q8":"19","VCC":"20"}
D("74374",["!OC","CLK"]+["D%d"%i for i in range(1,9)],
  ["Q%d"%i for i in range(1,9)]+["VCC","GND"],PM374,"DIP20")
PM377=dict(PM374); PM377["!E"]=PM377.pop("!OC")
D("74377V2",["!E","CLK"]+["D%d"%i for i in range(1,9)],
  ["Q%d"%i for i in range(1,9)]+["VCC","GND"],PM377,"DIP20")
D("74151",["A","B","C"]+["D%d"%i for i in range(8)]+["!G"],
  ["Y","!W","VCC","GND"],
  {"D3":"1","D2":"2","D1":"3","D0":"4","Y":"5","!W":"6","!G":"7","GND":"8","C":"9","B":"10",
   "A":"11","D7":"12","D6":"13","D5":"14","D4":"15","VCC":"16"},"DIP16")
D("HEX14",["1A","2A","3A","4A","5A","6A"],["1Y","2Y","3Y","4Y","5Y","6Y","VCC","GND"],
  {"1A":"1","1Y":"2","2A":"3","2Y":"4","3A":"5","3Y":"6","GND":"7","4Y":"8","4A":"9",
   "5Y":"10","5A":"11","6Y":"12","6A":"13","VCC":"14"},"DIP14")
D("7474",["!1CLR","1D","1CLK","!1PRE","!2CLR","2D","2CLK","!2PRE"],
  ["1Q","!1Q","2Q","!2Q","VCC","GND"],
  {"!1CLR":"1","1D":"2","1CLK":"3","!1PRE":"4","1Q":"5","!1Q":"6","GND":"7","!2Q":"8",
   "2Q":"9","!2PRE":"10","2CLK":"11","2D":"12","!2CLR":"13","VCC":"14"},"DIP14")
D("7402",["1A","1B","2A","2B","3A","3B","4A","4B"],["1Y","2Y","3Y","4Y","VCC","GND"],
  {"1Y":"1","1A":"2","1B":"3","2Y":"4","2A":"5","2B":"6","GND":"7","3A":"8","3B":"9",
   "3Y":"10","4A":"11","4B":"12","4Y":"13","VCC":"14"},"DIP14")
D("7410",["1A","1B","1C","2A","2B","2C","3A","3B","3C"],["1Y","2Y","3Y","VCC","GND"],
  {"1A":"1","1B":"2","2A":"3","2B":"4","2C":"5","2Y":"6","GND":"7","3Y":"8","3A":"9",
   "3B":"10","3C":"11","1Y":"12","1C":"13","VCC":"14"},"DIP14")
D("28C64",["A%d"%i for i in range(13)],
  ["IO%d"%i for i in range(8)]+["!CE","!OE","!WE","RDY","NC26","VCC","GND"],
  {"RDY":"1","A12":"2","A7":"3","A6":"4","A5":"5","A4":"6","A3":"7","A2":"8","A1":"9",
   "A0":"10","IO0":"11","IO1":"12","IO2":"13","GND":"14","IO3":"15","IO4":"16","IO5":"17",
   "IO6":"18","IO7":"19","!CE":"20","A10":"21","!OE":"22","A11":"23","A9":"24","A8":"25",
   "NC26":"26","!WE":"27","VCC":"28"},"DIP28W")
D("74139",["!G1","A1","B1","!G2","A2","B2"],
  ["1Y0","1Y1","1Y2","1Y3","2Y0","2Y1","2Y2","2Y3","VCC","GND"],
  {"!G1":"1","A1":"2","B1":"3","1Y0":"4","1Y1":"5","1Y2":"6","1Y3":"7","GND":"8",
   "2Y3":"9","2Y2":"10","2Y1":"11","2Y0":"12","B2":"13","A2":"14","!G2":"15","VCC":"16"},"DIP16")
D("74257",["S","A1","B1","A2","B2","A3","B3","A4","B4","!OE"],
  ["Y1","Y2","Y3","Y4","VCC","GND"],
  {"S":"1","A1":"2","B1":"3","Y1":"4","A2":"5","B2":"6","Y2":"7","GND":"8","Y3":"9",
   "B3":"10","A3":"11","Y4":"12","B4":"13","A4":"14","!OE":"15","VCC":"16"},"DIP16")
D("74244",["!G1","A1","A2","A3","A4","!G2","A5","A6","A7","A8"],
  ["Y1","Y2","Y3","Y4","Y5","Y6","Y7","Y8","VCC","GND"],
  {"!G1":"1","A1":"2","Y8":"3","A2":"4","Y7":"5","A3":"6","Y6":"7","A4":"8","Y5":"9",
   "GND":"10","A5":"11","Y4":"12","A6":"13","Y3":"14","A7":"15","Y2":"16","A8":"17",
   "Y1":"18","!G2":"19","VCC":"20"},"DIP20")
D("74157",["S","A1","B1","A2","B2","A3","B3","A4","B4","!G"],
  ["Y1","Y2","Y3","Y4","VCC","GND"],
  {"S":"1","A1":"2","B1":"3","Y1":"4","A2":"5","B2":"6","Y2":"7","GND":"8","Y3":"9",
   "B3":"10","A3":"11","Y4":"12","B4":"13","A4":"14","!G":"15","VCC":"16"},"DIP16")
D("74175",["!CLR","CLK","D1","D2","D3","D4"],
  ["Q1","!Q1","Q2","!Q2","Q3","!Q3","Q4","!Q4","VCC","GND"],
  {"!CLR":"1","Q1":"2","!Q1":"3","D1":"4","D2":"5","!Q2":"6","Q2":"7","GND":"8","CLK":"9",
   "Q3":"10","!Q3":"11","D3":"12","D4":"13","!Q4":"14","Q4":"15","VCC":"16"},"DIP16")
D("74260",["A1","B1","C1","D1","E1","A2","B2","C2","D2","E2"],["Y1","Y2","VCC","GND"],
  # SN74x260 datasheet pinout (the input/output split is non-obvious):
  #   1=1A 2=1B 3=2A 4=2B 5=2C 6=2Y 7=GND 8=1Y 9=2D 10=2E 11=1C 12=1D 13=1E 14=VCC
  {"A1":"1","B1":"2","A2":"3","B2":"4","C2":"5","Y2":"6","GND":"7","Y1":"8","D2":"9",
   "E2":"10","C1":"11","D1":"12","E1":"13","VCC":"14"},"DIP14")
D("74181",["A0","B0","A1","B1","A2","B2","A3","B3","S0","S1","S2","S3","M","CN"],
  ["F0","F1","F2","F3","CN4","!P","!G","AEB","VCC","GND"],
  {"B0":"1","A0":"2","S3":"3","S2":"4","S1":"5","S0":"6","CN":"7","M":"8","F0":"9",
   "F1":"10","F2":"11","GND":"12","F3":"13","AEB":"14","!P":"15","CN4":"16","!G":"17",
   "B3":"18","A3":"19","B2":"20","A2":"21","B1":"22","A1":"23","VCC":"24"},"DIP24W")
D("74182",["!P0","!G0","!P1","!G1","!P2","!G2","!P3","!G3","CN"],
  ["CNX","CNY","CNZ","!P","!G","VCC","GND"],
  {"!G1":"1","!P1":"2","!G0":"3","!P0":"4","!G3":"5","!P3":"6","!P":"7","GND":"8",
   "CNZ":"9","!G":"10","CNY":"11","CNX":"12","CN":"13","!P2":"14","!G2":"15","VCC":"16"},"DIP16")
D("6850",["D%d"%i for i in range(8)]+["CS0","CS1","!CS2","RS","RW","E"],
  ["TXD","RXD","TXCLK","RXCLK","!RTS","!CTS","!DCD","!IRQ","VCC","GND"],
  {"GND":"1","RXD":"2","RXCLK":"3","TXCLK":"4","!RTS":"5","TXD":"6","!IRQ":"7","CS0":"8",
   "!CS2":"9","CS1":"10","RS":"11","VCC":"12","RW":"13","E":"14","D7":"15","D6":"16",
   "D5":"17","D4":"18","D3":"19","D2":"20","D1":"21","D0":"22","!DCD":"23","!CTS":"24"},"DIP24W")
D("MAX232",["C1P","C1M","C2P","C2M","T1IN","T2IN","R1OUT","R2OUT"],
  ["VP","VM","T1OUT","T2OUT","R1IN","R2IN","VCC","GND"],
  {"C1P":"1","VP":"2","C1M":"3","C2P":"4","C2M":"5","VM":"6","T2OUT":"7","R2IN":"8",
   "R2OUT":"9","T2IN":"10","T1IN":"11","R1OUT":"12","R1IN":"13","T1OUT":"14","GND":"15",
   "VCC":"16"},"DIP16")
D("OSC",["NC1"],["OUT","VCC","GND"],{"NC1":"1","GND":"7","OUT":"8","VCC":"14"},"OSC4")
D("HDR4",["1","2","3","4"],[],{str(k):str(k) for k in range(1,5)},"HDR4")
D("HDR3",["1","2","3"],[],{str(k):str(k) for k in range(1,4)},"HDR3")
D("SW2",["1"],["2"],{"1":"1","2":"2"},"SW2P")
D("DIP8SW",["A%d"%i for i in range(1,9)],["B%d"%i for i in range(1,9)],
  dict([("A%d"%i,str(i)) for i in range(1,9)]+[("B%d"%i,str(17-i)) for i in range(1,9)]),"DIP16")
D("RNISO8",["A%d"%i for i in range(1,9)],["B%d"%i for i in range(1,9)],
  dict([("A%d"%i,str(2*i-1)) for i in range(1,9)]+[("B%d"%i,str(2*i)) for i in range(1,9)]),"SIP16")
D("LEDARR8",["A%d"%i for i in range(1,9)],["K%d"%i for i in range(1,9)],
  dict([("A%d"%i,str(i)) for i in range(1,9)]+[("K%d"%i,str(17-i)) for i in range(1,9)]),"DIP16")
D("IDE40",[str(k) for k in range(1,41,2)],[str(k) for k in range(2,41,2)],
  {str(k):str(k) for k in range(1,41)},"HDR40")

# ===================== XML HELPERS =============================================
# The COMPLETE standard EAGLE layer table (number, name, color, fill). Real
# Eagle .sch/.brd files carry the full set in every drawing; emitting only a
# subset makes Fusion remap on import (text lands on auto-named layers). Use the
# same full table for both schematic and board so nothing is remapped.
LAYERS=[(1,"Top",4,1),(2,"Route2",1,1),(3,"Route3",4,1),(4,"Route4",1,1),(5,"Route5",4,1),
 (6,"Route6",1,1),(7,"Route7",4,1),(8,"Route8",1,1),(9,"Route9",4,1),(10,"Route10",1,1),
 (11,"Route11",4,1),(12,"Route12",1,1),(13,"Route13",4,1),(14,"Route14",1,1),(15,"Route15",4,1),
 (16,"Bottom",1,1),(17,"Pads",2,1),(18,"Vias",2,1),(19,"Unrouted",6,1),(20,"Dimension",24,1),
 (21,"tPlace",7,1),(22,"bPlace",7,1),(23,"tOrigins",15,1),(24,"bOrigins",15,1),
 (25,"tNames",7,1),(26,"bNames",7,1),(27,"tValues",7,1),(28,"bValues",7,1),
 (29,"tStop",7,3),(30,"bStop",7,6),(31,"tCream",7,4),(32,"bCream",7,5),
 (33,"tFinish",6,3),(34,"bFinish",6,6),(35,"tGlue",7,4),(36,"bGlue",7,5),
 (37,"tTest",7,1),(38,"bTest",7,1),(39,"tKeepout",4,11),(40,"bKeepout",1,11),
 (41,"tRestrict",4,10),(42,"bRestrict",1,10),(43,"vRestrict",2,10),(44,"Drills",7,1),
 (45,"Holes",7,1),(46,"Milling",3,1),(47,"Measures",7,1),(48,"Document",7,1),
 (49,"Reference",7,1),(51,"tDocu",7,1),(52,"bDocu",7,1),
 (88,"SimResults",9,1),(89,"SimProbes",9,1),(90,"Modules",5,1),(91,"Nets",2,1),
 (92,"Busses",1,1),(93,"Pins",2,1),(94,"Symbols",4,1),(95,"Names",7,1),(96,"Values",7,1),
 (97,"Info",7,1),(98,"Guide",6,1)]
SCH_LAYERS=BRD_LAYERS=LAYERS

def hdr(layers):
    o=['<?xml version="1.0" encoding="utf-8"?>','<!DOCTYPE eagle SYSTEM "eagle.dtd">',
       '<eagle version="9.6.2">','<drawing>',
       '<settings><setting alwaysvectorfont="no"/><setting verticaltext="up"/></settings>',
       '<grid distance="0.1" unitdist="inch" unit="inch" style="lines" multiple="1" display="no" altdistance="0.01" altunitdist="inch" altunit="inch"/>',
       '<layers>']
    for n,nm,c,f in layers:
        o.append(f'<layer number="{n}" name="{nm}" color="{c}" fill="{f}" visible="yes" active="yes"/>')
    o.append('</layers>')
    return o

def _w(x1,y1,x2,y2): return f'<wire x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" width="0.254" layer="94"/>'
def _passive_art():
    """ANSI/US 2-pin discrete symbol art as (x1,y1,x2,y2) segments, drawn
    horizontally between the pin inner-ends at x=-12.7 / +12.7. Shared by the
    Eagle library (lib_xml) and the schematic-PDF renderer."""
    zz=[(-7.62,0),(-6.35,1.78),(-3.81,-1.78),(-1.27,1.78),(1.27,-1.78),(3.81,1.78),(6.35,-1.78),(7.62,0)]
    res=[(-12.7,0,-7.62,0),(7.62,0,12.7,0)]+[zz[i]+zz[i+1] for i in range(len(zz)-1)]   # US zig-zag
    cap=[(-12.7,0,-1.27,0),(1.27,0,12.7,0),(-1.27,-3.81,-1.27,3.81),(1.27,-3.81,1.27,3.81)]
    plus=[(-5.59,3.81,-3.56,3.81),(-4.57,2.79,-4.57,4.83)]                              # "+" mark
    capp=[(-12.7,0,-1.27,0),(1.78,0,12.7,0),(-1.27,-3.81,-1.27,3.81),(1.78,-3.81,1.78,3.81)]+plus
    led=[(-12.7,0,-2.54,0),(2.54,0,12.7,0),
         (-2.54,2.54,-2.54,-2.54),(-2.54,2.54,2.54,0),(-2.54,-2.54,2.54,0),   # anode triangle ->
         (2.54,-2.54,2.54,2.54),                                              # cathode bar
         (1.02,3.05,3.05,5.08),(3.05,5.08,2.03,4.83),(3.05,5.08,2.79,4.06),   # light arrow 1
         (3.56,2.54,5.59,4.57),(5.59,4.57,4.57,4.32),(5.59,4.57,5.33,3.56)]   # light arrow 2
    xtal=[(-12.7,0,-3.81,0),(3.81,0,12.7,0),(-3.81,-3.81,-3.81,3.81),(3.81,-3.81,3.81,3.81),
          (-1.27,-2.54,1.27,-2.54),(1.27,-2.54,1.27,2.54),(1.27,2.54,-1.27,2.54),(-1.27,2.54,-1.27,-2.54)]
    coin=[(-12.7,0,-1.27,0),(1.27,0,12.7,0),(-1.27,-3.81,-1.27,3.81),(1.27,-1.91,1.27,1.91)]+plus
    return {"RES":res,"CAP":cap,"CAP1":cap,"CAPP":capp,"LED":led,"XTAL32":xtal,"COIN":coin}
PASSIVE_ART=_passive_art()
PASSIVE_SYM={dn:[_w(*seg) for seg in segs] for dn,segs in PASSIVE_ART.items()}

def lib_xml(devnames, for_board):
    o=['<libraries><library name="p8x">','<packages>']
    pkgs=sorted({DEV[d]["pkg"] for d in devnames})
    for pk in pkgs:
        o.append(f'<package name="{pk}">')
        for (nm,x,y,dr,sz) in PKG[pk]:
            if nm.startswith("MH"):      # mounting hole: non-plated mechanical hole, not a pad
                o.append(f'<hole x="{x:.2f}" y="{y:.2f}" drill="{dr}"/>')
            else:
                o.append(f'<pad name="{nm}" x="{x:.2f}" y="{y:.2f}" drill="{dr}" diameter="{sz}"/>')
        o.append('<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>')    # silkscreen refdes
        o.append('<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>')   # silkscreen value
        o.append('</package>')
    o.append('</packages>')
    if not for_board:
        o.append('<symbols>')
        for dn in sorted(set(devnames)):
            d=DEV[dn]; L,R=d["L"],d["R"]
            o.append(f'<symbol name="{dn}">')
            if dn in PASSIVE_SYM:                       # ANSI 2-pin discrete (R/C/LED/...)
                o+=PASSIVE_SYM[dn]
                o.append('<text x="-2.54" y="4.32" size="1.778" layer="95">&gt;NAME</text>')
                o.append('<text x="-2.54" y="-6.6" size="1.778" layer="96">&gt;VALUE</text>')
                o.append(f'<pin name="{L[0]}" x="{-PIN_X}" y="0" length="middle"/>')
                o.append(f'<pin name="{R[0]}" x="{PIN_X}" y="0" length="middle" rot="R180"/>')
            else:                                       # generic box for ICs / connectors / arrays
                n=max(len(L),len(R)); y1=-G*(n-1)-G
                for (a,b,c,e) in [(-12.7,G,12.7,G),(12.7,G,12.7,y1),(12.7,y1,-12.7,y1),(-12.7,y1,-12.7,G)]:
                    o.append(f'<wire x1="{a}" y1="{b}" x2="{c}" y2="{e:.2f}" width="0.254" layer="94"/>')
                o.append(f'<text x="-12.7" y="{G+1.27:.2f}" size="1.778" layer="95">&gt;NAME</text>')
                o.append(f'<text x="-12.7" y="{y1-3.81:.2f}" size="1.778" layer="96">&gt;VALUE</text>')
                for i,p in enumerate(L):
                    o.append(f'<pin name="{p}" x="{-PIN_X}" y="{-G*i:.2f}" length="middle"/>')
                for i,p in enumerate(R):
                    o.append(f'<pin name="{p}" x="{PIN_X}" y="{-G*i:.2f}" length="middle" rot="R180"/>')
            o.append('</symbol>')
        o.append('</symbols>')
        o.append('<devicesets>')
        for dn in sorted(set(devnames)):
            d=DEV[dn]
            o.append(f'<deviceset name="{dn}" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="{dn}" x="0" y="0"/></gates>')
            o.append(f'<devices><device name="" package="{d["pkg"]}"><connects>')
            for pin,pad in d["pm"].items():
                o.append(f'<connect gate="G$1" pin="{pin}" pad="{pad}"/>')
            o.append('</connects><technologies><technology name=""/></technologies></device></devices></deviceset>')
        o.append('</devicesets>')
    o.append('</library></libraries>')
    return o

def pinpos(dev,pin):
    d=DEV[dev]
    if pin in d["L"]: return (-PIN_X,-G*d["L"].index(pin),"L")
    return (PIN_X,-G*d["R"].index(pin),"R")

def write_sch(fn,title,parts,nets,labels=None):
    o=hdr(SCH_LAYERS)
    o.append('<schematic xreflabel="%F%N/%S.%C%R" xrefpart="/%S.%C%R">')
    o+=lib_xml([p[0] for p in parts.values()],False)
    o.append('<classes><class number="0" name="default" width="0" drill="0"/></classes>')
    o.append('<parts>')
    for ref,(dev,val,x,y) in parts.items():
        o.append(f'<part name="{ref}" library="p8x" deviceset="{dev}" device="" value="{val}"/>')
    o.append('</parts><sheets><sheet><plain>')
    o.append(f'<text x="0" y="40" size="3.81" layer="97">{title}</text>')
    # Per-part annotations placed above each chip: the part NUMBER (= the Eagle
    # 'value', also in the BOM) on the Values layer, and the logical FUNCTION on
    # the Info layer. Placed explicitly so they're visible regardless of layer
    # display settings (the symbol still carries >VALUE too).
    for ref,fn_txt in (labels or {}).items():
        if ref in parts:
            _,val,x,y=parts[ref]
            o.append(f'<text x="{x-12.7:.2f}" y="{y+G+7.0:.2f}" size="1.778" layer="97">{fn_txt}</text>')
            o.append(f'<text x="{x-12.7:.2f}" y="{y+G+4.0:.2f}" size="2.032" layer="96">{val}</text>')
    o.append('</plain><instances>')
    for ref,(dev,val,x,y) in parts.items():
        o.append(f'<instance part="{ref}" gate="G$1" x="{x}" y="{y}"/>')
    o.append('</instances><busses/><nets>')
    for nn,pins in nets.items():
        o.append(f'<net name="{nn}" class="0">')
        for ref,pin in pins:
            dev=parts[ref][0]; px,py,side=pinpos(dev,pin)
            gx,gy=parts[ref][2]+px,parts[ref][3]+py
            x2=gx-STUB if side=="L" else gx+STUB
            o.append(f'<segment><pinref part="{ref}" gate="G$1" pin="{pin}"/>')
            o.append(f'<wire x1="{gx:.2f}" y1="{gy:.2f}" x2="{x2:.2f}" y2="{gy:.2f}" width="0.1524" layer="91"/>')
            o.append(f'<label x="{x2:.2f}" y="{gy+0.508:.2f}" size="1.778" layer="95"/></segment>')
        o.append('</net>')
    o.append('</nets></sheet></sheets></schematic></drawing></eagle>')
    os.makedirs(os.path.dirname(fn) or ".",exist_ok=True)
    open(fn,"w").write("\n".join(o)+"\n")

def write_brd(fn,title,parts,nets,wires,polys,W,H,vias=None,outline_only=False,unplaced=False,holes=None):
    # unplaced: emit all parts (names+values) + the ratsnest (connectivity), but
    # parked OFF the board outline with no routing/pours — ready to place by hand.
    vias=vias or {}
    o=hdr(BRD_LAYERS)
    o.append('<board><plain>')
    for (a,b,c,d) in [(0,0,W,0),(W,0,W,H),(W,H,0,H),(0,H,0,0)]:
        o.append(f'<wire x1="{a}" y1="{b}" x2="{c}" y2="{d}" width="0" layer="20"/>')
    if outline_only:
        # board dimensions only — no parts, copper, silk, pours, or signals.
        # (The <layers> defs in the header stay; they're required for a valid file.)
        o.append('</plain><libraries/>')
        o.append('<classes><class number="0" name="default" width="0" drill="0"/></classes>')
        o.append('<designrules name="default"><param name="layerSetup" value="(1*2*15*16)"/></designrules>')
        o.append('<elements/><signals/></board></drawing></eagle>')
        os.makedirs(os.path.dirname(fn) or ".",exist_ok=True)
        open(fn,"w").write("\n".join(o)+"\n")
        return
    o.append(f'<text x="4" y="{H-6}" size="2.54" layer="21">{title}</text>')
    for (hx,hy,hd) in (holes or []):                      # board mounting holes (mechanical, non-plated)
        o.append(f'<hole x="{hx:.2f}" y="{hy:.2f}" drill="{hd}"/>')
    o.append('</plain>')
    o+=lib_xml([p[0] for p in parts.values()],True)
    o.append('<attributes></attributes><variantdefs></variantdefs>')   # std Eagle board sections
    o.append('<classes><class number="0" name="default" width="0" drill="0"/></classes>')
    o.append('<designrules name="default"><param name="layerSetup" value="(1*2*15*16)"/></designrules>')
    o.append('<elements>')
    # unplaced: park every part in a tidy column to the RIGHT of the board so
    # nothing sits on the outline; the ratsnest then guides manual placement.
    offx = W+25.4 if unplaced else 0.0
    for ref,pv in parts.items():
        dev,val,x,y=pv[:4]; rot=f' rot="{pv[4]}"' if len(pv)>4 else ""
        ex,ey=x+offx,y
        # Smashed element with explicit NAME (tNames/25) + VALUE (tValues/27)
        # attributes — exactly how Eagle writes boards, so Fusion reliably shows
        # the refdes + part number instead of remapping them to scratch layers.
        o.append(f'<element name="{ref}" library="p8x" package="{DEV[dev]["pkg"]}" value="{val}" x="{ex:.2f}" y="{ey:.2f}"{rot} smashed="yes">')
        o.append(f'<attribute name="NAME" x="{ex:.2f}" y="{ey+2.54:.2f}" size="1.778" layer="25" ratio="10"/>')
        o.append(f'<attribute name="VALUE" x="{ex:.2f}" y="{ey-2.54:.2f}" size="1.778" layer="27" ratio="10"/>')
        o.append('</element>')
    o.append('</elements><signals>')
    allnets=set(nets)|set(wires)|set(polys)
    for nn in sorted(allnets):
        o.append(f'<signal name="{nn}">')
        for ref,pin in nets.get(nn,[]):
            pad=DEV[parts[ref][0]]["pm"][pin]
            o.append(f'<contactref element="{ref}" pad="{pad}"/>')
        if unplaced: o.append('</signal>'); continue   # ratsnest only — no copper/pours
        for (x1,y1,x2,y2,ly,wd) in wires.get(nn,[]):
            o.append(f'<wire x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" width="{wd}" layer="{ly}"/>')
        for (vx,vy) in vias.get(nn,[]):
            o.append(f'<via x="{vx:.2f}" y="{vy:.2f}" extent="1-16" drill="0.4" diameter="0.8"/>')
        for (ly,) in polys.get(nn,[]):
            o.append(f'<polygon width="0.254" layer="{ly}" isolate="0.3" rank="1">')
            for (vx,vy) in [(0,0),(W,0),(W,H),(0,H)]:
                o.append(f'<vertex x="{vx}" y="{vy}"/>')
            o.append('</polygon>')
        o.append('</signal>')
    o.append('</signals></board></drawing></eagle>')
    os.makedirs(os.path.dirname(fn) or ".",exist_ok=True)
    open(fn,"w").write("\n".join(o)+"\n")

def validate(fn,parts,nets):
    import xml.etree.ElementTree as ET
    t=ET.parse(fn); root=t.getroot(); errs=0
    if root.find(".//schematic") is not None:
        for pr in root.findall(".//pinref"):
            dev=parts[pr.get("part")][0]
            if pr.get("pin") not in DEV[dev]["L"]+DEV[dev]["R"]: errs+=1; print("bad pin",pr.get("part"),pr.get("pin"))
    else:
        for cr in root.findall(".//contactref"):
            dev=parts[cr.get("element")][0]
            pads={p[0] for p in PKG[DEV[dev]["pkg"]]}
            if cr.get("pad") not in pads: errs+=1; print("bad pad",cr.get("element"),cr.get("pad"))
        # footprint overlap guard (board only): rotation-aware AABBs over the pads
        def _rot(px,py,r): return {"R90":(-py,px),"R180":(-px,-py),"R270":(py,-px)}.get(r,(px,py))
        bxs=[]
        for ref,pv in parts.items():
            ps=PKG[DEV[pv[0]]["pkg"]]; d=max(p[4] for p in ps); rt=pv[4] if len(pv)>4 else "R0"
            xs=[];ys=[]
            for (_n,px,py,_dr,_di) in ps:
                rx,ry=_rot(px,py,rt); xs.append(pv[2]+rx); ys.append(pv[3]+ry)
            bxs.append((ref,min(xs)-d/2,min(ys)-d/2,max(xs)+d/2,max(ys)+d/2))
        ov=0
        for i in range(len(bxs)):
            for j in range(i+1,len(bxs)):
                a,b=bxs[i],bxs[j]
                if a[1]<b[3]-0.05 and b[1]<a[3]-0.05 and a[2]<b[4]-0.05 and b[2]<a[4]-0.05:
                    ov+=1
                    if ov<=3: print("  overlap:",a[0],"<->",b[0])
        if ov: print("  WARNING: %d footprint overlap(s) in %s — fix placement"%(ov,fn))
    seen=set()
    for nn,pins in nets.items():
        for rp in pins:
            assert rp not in seen,(rp,nn); seen.add(rp)
    print(fn,"validated, errors:",errs); assert errs==0

# ===================== CARD BUILDER ============================================
CARDS={}  # name -> (title, parts, nets) — used by render_traditional_auto.py

# device -> orderable generic part number (the Eagle `value`). For these
# deterministic devices card() sets the value automatically and turns the part's
# original tuple text into its function label. Devices NOT listed (gate arrays,
# memory size variants, oscillators, passives, connectors) keep their tuple value.
PN={"74161":"74HCT161","74169":"74HCT169","74374":"74HCT374","74377V2":"74HCT377",
 "74151":"74HCT151","74139":"74HCT139","74138":"74HCT138","74157":"74HCT157",
 "74257":"74HCT257","74244":"74HCT244","74245":"74HCT245","7402":"74HCT02",
 "7410":"74HCT10","7430":"74HCT30","7474":"74HCT74","74181":"74HCT181",
 "74182":"74HCT182","74260":"74HCT260","28C64":"28C64","6850":"6850",
 "MAX232":"MAX232","DS1302":"DS1302"}

def fp_box(pkg):
    """Footprint bounding box from the pad geometry: (w,h,ox,oy) where ox,oy is
    the bbox bottom-left relative to the part origin (pad dia included)."""
    pads=PKG[pkg]; xs=[p[1] for p in pads]; ys=[p[2] for p in pads]; d=max(p[4] for p in pads)
    return (max(xs)-min(xs)+d, max(ys)-min(ys)+d, min(xs)-d/2, min(ys)-d/2)

def card(name,title,parts_ic,parts_small,nets,used_bus,labels=None,
         brd_outline_only=False,brd_unplaced=True):
    """Build sch+brd for one plug-in card. `labels` maps ref -> logical-function
    text placed near the part on the schematic (the part's `value` is its part
    number). `brd_outline_only` emits a .brd with just the board dimensions;
    `brd_unplaced` emits all parts + ratsnest parked off the board (no routing)."""
    for pin in ALLPINS:
        net=busnet(pin)
        if net in ("VCC","GND") or net in used_bus:
            nets.setdefault(net,[]).append(("J1",pin))
    # one 100nF decoupling cap per IC (card standards sec.5), each across
    # VCC<->GND and placed next to its IC. Named CDn to avoid clashing with any
    # functional caps a card already declares (C1, C2, ...).
    decap={}
    icrefs=list(parts_ic)
    for i,ref in enumerate(icrefs):
        c="CD%d"%(i+1)
        decap[c]=("CAP1","100N")
        nets.setdefault("VCC",[]).append((c,"1"))
        nets.setdefault("GND",[]).append((c,"2"))
    # Every IC's dedicated supply pins must be members of the VCC/GND nets — a
    # copper pour only connects pads that belong to the net, so without this the
    # chips sit unpowered next to the rails. (The hand-built memory card does this
    # explicitly; this loop gives the card()-built boards the same.)
    for ref,(dev,_val) in parts_ic.items():
        pins=DEV[dev]["L"]+DEV[dev]["R"]
        for rail in ("VCC","GND"):
            if rail in pins and (ref,rail) not in nets.get(rail,[]):
                nets.setdefault(rail,[]).append((ref,rail))   # skip if already wired by hand
    parts={"J1":("DIN96C","MABC96R")}
    parts.update(parts_ic); parts.update(parts_small); parts.update(decap)
    # Resolve the value field to the orderable part number (PN map wins for the
    # deterministic devices), and turn the original per-part text into a function
    # label for those; an explicit `labels` entry always overrides.
    lab=dict(labels or {})
    for ref,(dev,raw) in list(parts.items()):
        if dev in PN:                                  # deterministic logic/memory
            val,fn = PN[dev], (raw if raw and raw!=PN[dev] else None)
        elif dev=="LED" and "-" in raw:                # "FUNC-COLOR" -> value=color, label=FUNC
            fn,val = raw.rsplit("-",1)
        elif dev=="HDR3": val,fn = "1x3", (raw if raw not in ("1x3","") else None)
        elif dev=="HDR4": val,fn = "1x4", (raw if raw not in ("1x4","") else None)
        elif dev=="SW2":  val,fn = "SPST", (raw or None)
        else:             val,fn = raw, None           # gates/passives/connectors keep their value
        parts[ref]=(dev,val)
        if fn and ref not in lab: lab[ref]=fn          # explicit labels always win
    sch={}; order=[r for r in parts if r!="J1"]
    sch["J1"]=("DIN96",parts["J1"][1],0,38.10)
    for i,ref in enumerate(order):
        dev,val=parts[ref]
        sch[ref]=(dev,val,140+(i%4)*101.6,38.10-(i//4)*139.7)
    # Footprint-aware placement: J1 (the DIN96 edge connector) hugs the left
    # edge; everything else flows left-to-right in rows sized to each part's real
    # pad-extent + clearance, wrapping at the board width and stacking downward.
    # This guarantees NO OVERLAPS. Dense cards may run past the board outline
    # (they genuinely don't fit 160x100 at safe pitch) — arrange by hand when
    # routing; the placement-view PDF flags the overflow.
    BW,BH,EDGE,GAP=160.0,100.0,4.0,2.6
    brd={}
    j1dev=parts["J1"][0]                       # DIN96C (card edge connector, has mounting holes)
    j1pkg=DEV[j1dev]["pkg"]
    j1w,j1h,j1ox,j1oy=fp_box(j1pkg)
    brd["J1"]=(j1dev,parts["J1"][1],EDGE-j1ox,BH-EDGE-j1h-j1oy)
    flow=[]                                   # (ref,dev,val,pkg) in placement order
    for i,ref in enumerate(icrefs):           # each IC immediately followed by its cap
        dev,val=parts[ref]; flow.append((ref,dev,val,DEV[dev]["pkg"]))
        flow.append(("CD%d"%(i+1),"CAP1","100N",DEV["CAP1"]["pkg"]))
    for ref in parts_small:
        dev,val=parts[ref]; flow.append((ref,dev,val,DEV[dev]["pkg"]))
    x0=EDGE+j1w+GAP*2; cx=x0; cyt=BH-EDGE; rowh=0.0
    for ref,dev,val,pkg in flow:
        w,h,ox,oy=fp_box(pkg)
        if cx+w>BW-EDGE and cx>x0:            # wrap to next row
            cx=x0; cyt-=rowh+GAP; rowh=0.0
        brd[ref]=(dev,val,cx-ox,cyt-h-oy)     # top-left of this part at (cx,cyt)
        cx+=w+GAP; rowh=max(rowh,h)
    # include J1 so CARDS is the full board (the BOM counts it; the schematic
    # renderer filters J1 by name). Without it the card edge connectors were
    # missing from the BOM.
    allp=dict(parts)   # resolved values (part numbers) for the BOM / renderer
    CARDS[name]=(title,allp,nets)
    base="%s/p8x-%s"%(name,name)   # each board in its own subdirectory
    if EMIT:
        write_sch(base+".sch",title,sch,nets,lab)
        validate(base+".sch",sch,nets)
        write_brd(base+".brd",title,brd,nets,{},{"GND":[(2,)],"VCC":[(15,)]},160,100,
                  outline_only=brd_outline_only,unplaced=brd_unplaced)
        if not brd_outline_only:
            validate(base+".brd",brd,nets)
            # companion "-full" board: same parts but with auto-placement attempted
            # (footprint flow on-board + GND/VCC pours + ratsnest) as a starting layout.
            write_brd(base+"-full.brd",title+" (FULL)",brd,nets,{},{"GND":[(2,)],"VCC":[(15,)]},160,100)
            validate(base+"-full.brd",brd,nets)

def N(nets,n,*p): nets.setdefault(n,[]).extend(p)

# ===================== CONTROL / MICROCODE CARD ================================
n={}
ic={"U1":("74161","CLK DIV"),"U2":("HEX14","74HCT14"),"U3":("7474","74HCT74"),
 "U4":("GATES14","74HCT00"),"U5":("GATES14","74HCT08"),"U6":("GATES14","74HCT32"),
 "U7":("74377V2","INSTR REG"),"U8":("74138","DLD DEC"),"U9":("74151","COND MUX"),
 "U10":("28C64","UCODE ROM0"),"U11":("28C64","UCODE ROM1"),
 "U12":("28C64","UCODE ROM2"),"U13":("28C64","UCODE ROM3"),
 "U14":("74374","PIPE0"),"U15":("74374","PIPE1"),"U16":("74374","PIPE2"),
 "U17":("74374","PIPE3"),"U18":("74161","STEP CNT"),
 "U19":("GATES14","74HCT86"),   # rev C: N^V for signed-compare cond mux
 # rev C: interrupt-controller footprints, provisioned DNP (Do Not Populate).
 # Pads + the IRQ bus line exist so the controller can be built post-fab WITHOUT
 # a respin, but the bus-critical bits (the forcing-buffer OUTPUTS onto the data
 # bus, the service/enable sequencer, and the memory -RD suppression) are
 # deliberately NOT wired here — they must be designed with DRC/breadboard first.
 "U20":("74244","IRQ-FORCE DNP"),"U21":("7474","IRQ/IE FF DNP")}
sm={"X1":("OSC","4MHZ"),"JP1":("HDR4","CLKSEL"),
 "SWR":("SW2","RUN/HALT"),"SWS":("SW2","STEP"),"SWT":("SW2","RESET"),
 "R1":("RES","10K"),"R2":("RES","10K"),"R3":("RES","10K"),"C1":("CAP","1U"),
 "RP1":("RES","1K"),"LED3":("LED","PWR-GRN"),
 "R4":("RES","1K"),"LED4":("LED","RUN-GRN"),
 "R5":("RES","1K"),"LED5":("LED","HALT-RED")}
N(n,"OSCO",("X1","OUT"),("JP1","1"),("U1","CLK"))
N(n,"DIVQA",("U1","QA"),("JP1","3")); N(n,"DIVQB",("U1","QB"),("JP1","4"))
N(n,"CLKRAW",("JP1","2"),("U3","1CLK"),("U3","2CLK"),("U5","1A"))
N(n,"VCC",("U1","ENP"),("U1","ENT"),("U1","!LOAD"),("U3","!1PRE"),("U3","!2PRE"),
  ("U18","ENP"),("U18","ENT"),("R1","1"),("R2","1"),("R3","1"),("X1","VCC"),
  ("U8","G1"),("RP1","1"),("R4","1"),("R5","1"),
  *[("U%d"%k,"!WE") for k in (10,11,12,13)])
N(n,"GND",("U1","A"),("U1","B"),("U1","C"),("U1","D"),("U18","A"),("U18","B"),
  ("U18","C"),("U18","D"),("U9","D0"),("U9","!G"),
  ("U8","!G2B"),("X1","GND"),("SWR","1"),("SWS","1"),("SWT","1"),("C1","2"),
  ("LED3","K"),("U5","3A"),("U5","3B"),("U5","4A"),("U5","4B"),
  ("U6","2A"),("U6","2B"),("U6","3A"),("U6","3B"),
  *[("U%d"%k,"!CE") for k in (10,11,12,13)],*[("U%d"%k,"!OE") for k in (10,11,12,13)],
  *[("U%d"%k,"!OC") for k in (14,15,16,17)])
N(n,"VCC",("U9","D1"))
N(n,"RUNSW",("SWR","2"),("R3","2"),("U5","2A"))
N(n,"HALT",("U2","1A"))
N(n,"HALTN",("U2","1Y"),("U5","2B"))
N(n,"RUND",("U5","2Y"),("U3","1D"))
N(n,"STEPRAW",("SWS","2"),("R2","2"),("U2","2A"))
N(n,"STEPN",("U2","2Y"),("U2","3A"))
N(n,"STEPP",("U2","3Y"),("U3","2D"),("U4","1B"))
N(n,"STEPQ",("U3","2Q"),("U4","1A"),("U6","1B"))
N(n,"STEPCLR",("U4","1Y"),("U3","!2CLR"))
N(n,"RUNQ",("U3","1Q"),("U6","1A"),("U4","3A"),("U4","3B"))
N(n,"RUNLK",("U4","3Y"),("LED4","K"),("U4","4A"),("U4","4B"))
N(n,"HALTK",("U4","4Y"),("LED5","K"))
N(n,"CLKEN",("U6","1Y"),("U5","1B"))
N(n,"CLK",("U5","1Y"),("U2","6A"),("U7","CLK"),("U18","CLK"))
N(n,"CLKB",("U2","6Y"),*[("U%d"%k,"CLK") for k in (14,15,16,17)])
N(n,"RSTRAW",("SWT","2"),("R1","2"),("C1","1"),("U2","4A"))
N(n,"RSTP",("U2","4Y"),("U2","5A"))
N(n,"-RES",("U2","5Y"),("U1","!CLR"),("U3","!1CLR"),("U18","!CLR"))
for i in range(8):
    N(n,"D%d"%i,("U7","D%d"%(i+1)))
    N(n,"IRQ%d"%i,("U7","Q%d"%(i+1)),*[("U%d"%k,"A%d"%i) for k in (10,11,12,13)])
for i,dn in enumerate(("DLD0","DLD1","DLD2")):
    N(n,dn,("U8",["A","B","C"][i]))
N(n,"DLD3",("U8","!G2A"))
N(n,"-IRLD",("U8","Y6"),("U7","!E"))
for i in range(4):
    N(n,"SQ%d"%i,("U18",["QA","QB","QC","QD"][i]),*[("U%d"%k,"A%d"%(8+i)) for k in (10,11,12,13)])
N(n,"CONDY",("U9","Y"),*[("U%d"%k,"A12") for k in (10,11,12,13)])
for f,d in (("FC","D2"),("FZ","D3"),("FN","D4"),("FV","D5")):
    N(n,f,("U9",d))
# rev C signed-compare conditions: NV = FN^FV (U19, 74HCT86) -> mux D6 (FCOND 6,
# signed LT); NVZ = NV | FZ (spare U6 OR gate 4) -> mux D7 (FCOND 7, signed LE).
N(n,"FN",("U19","1A")); N(n,"FV",("U19","1B")); N(n,"NV",("U19","1Y"))
N(n,"NV",("U9","D6"))
N(n,"NV",("U6","4A")); N(n,"FZ",("U6","4B")); N(n,"NVZ",("U6","4Y"))
N(n,"NVZ",("U9","D7"))
N(n,"GND",("U19","2A"),("U19","2B"),("U19","3A"),("U19","3B"),("U19","4A"),("U19","4B"))
# rev C interrupt-controller footprints (DNP): only the SAFE, populate-ready
# connections. The forcing buffer holds its outputs DISABLED (high-Z) and carries
# the fixed $08 pattern on its inputs; the IRQ bus line reaches the FF. The buffer
# OUTPUTS (Y1-8 onto the data bus), the service/enable sequencer, the EI/DI/RTI
# opcode decode, and the memory -RD suppression are intentionally NOT wired here.
N(n,"VCC",("U20","!G1"),("U20","!G2"))                 # outputs forced high-Z
N(n,"VCC",("U20","A4"))                                # $08 input pattern: bit3 high
N(n,"GND",("U20","A1"),("U20","A2"),("U20","A3"),
          ("U20","A5"),("U20","A6"),("U20","A7"),("U20","A8"))
N(n,"IRQ",("U21","1D"))                                # reserved IRQ line (B29) -> pending FF
N(n,"-RES",("U21","!1CLR"),("U21","!2CLR"))            # power-up reset (safe if populated)
N(n,"VCC",("U21","!1PRE"),("U21","!2PRE"))
N(n,"GND",("U21","1CLK"),("U21","2D"),("U21","2CLK"))  # inactive defaults
# rev B 32-bit control word -> pipeline latches U14..U17 (8 bits each).
# Word bit b is latch U[14 + b//8], output Q[(b%8)+1].
PIPE={14:["DOE0","DOE1","DOE2","DOE3","DLD0","DLD1","DLD2","DLD3"],
 15:["PSEL0","PSEL1","PSEL2","PINC","PDEC","ALUS0","ALUS1","ALUS2"],
 16:["ALUS3","ALUM","CIN","SH0","SH1","LDF","FCOND0","FCOND1"],
 17:["FCOND2","URST","HALT","LDZN","SHCIN","SETC","CLRC","BSEL"]}
for k,sigs in PIPE.items():
    for b,sig in enumerate(sigs):
        N(n,"P%dB%d"%(k,b),("U%d"%k,"D%d"%(b+1)),("U%d"%(k-4),"IO%d"%b))
        N(n,sig,("U%d"%k,"Q%d"%(b+1)))
for i,f in enumerate(("FCOND0","FCOND1","FCOND2")):
    N(n,f,("U9",["A","B","C"][i]))
N(n,"URST",("U4","2A"),("U4","2B"))
N(n,"-USTL",("U4","2Y"),("U18","!LOAD"))
N(n,"LEDP",("RP1","2"),("LED3","A"))
N(n,"LEDRN",("R4","2"),("LED4","A")); N(n,"LEDHL",("R5","2"),("LED5","A"))
card("control-card","P8X CONTROL/MICROCODE CARD REV B",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"DOE%d"%i for i in range(4)}|{"DLD%d"%i for i in range(4)}|
 {"PSEL0","PSEL1","PSEL2","PINC","PDEC","ALUS0","ALUS1","ALUS2","ALUS3","ALUM","CIN","SH0","SH1",
  "LDF","CLK","CLKB","-RES","FC","FZ","FN","FV","LDZN","SHCIN","SETC","CLRC","BSEL","IRQ"},
 labels={"U19":"N^V XOR"})

# ===================== REGISTER BANK CARD =====================================
n={}; ic={}
for p in range(4):
    for s,nm in enumerate(("L0","L1","H0","H1")):
        ic["U%d"%(1+p*4+s)]=("74169","P%d %s"%(p,nm))
for k in range(8): ic["U%d"%(17+k)]=("74244","PTR SEL %d"%k)
ic.update({"U25":("74244","ADDR LO"),"U26":("74244","ADDR HI"),
 "U27":("74257","RDBK LO"),"U28":("74257","RDBK HI"),"U29":("74244","RDBK OUT"),
 "U30":("74138","DLD DEC"),"U31":("74138","DOE DEC"),"U32":("74139","LOAD DEC"),
 "U33":("74138","SEL DEC"),"U34":("7402","74HCT02"),"U35":("HEX14","74HCT14"),
 "U36":("74244","ZERO P0"),"U37":("GATES14","74HCT08"),"U38":("GATES14","74HCT08"),
 # rev B: PT (5th pointer, PSEL=4) + 3-bit decode support
 "U39":("74139","CNT DEC"),"U40":("GATES14","74HCT32"),
 "U41":("74377V2","PT LO"),"U42":("74377V2","PT HI"),
 "U43":("74244","PT SEL LO"),"U44":("74244","PT SEL HI")})
sm={"RP1":("RES","1K"),"LED3":("LED","PWR-GRN"),
 "R4":("RES","1K"),"LED4":("LED","RD-GRN"),"R5":("RES","1K"),"LED5":("LED","LD-YEL")}
for p in range(4):
    base=1+p*4
    for s in range(4):
        u="U%d"%(base+s)
        N(n,"CLK",(u,"CLK")); N(n,"UDB",(u,"UD")); N(n,"-CNT%d"%p,(u,"!ENP"))
        for bit in range(4):
            N(n,"D%d"%((s%2)*4+bit),(u,"ABCD"[bit]))
        N(n,("-LDL0E" if (p==0 and s<2) else "-LDH0E" if p==0 else
             "-LDL%d"%p if s<2 else "-LDH%d"%p),(u,"!LOAD"))
        if s==0: N(n,"-CNT%d"%p,(u,"!ENT"))
        else: N(n,"RC%d_%d"%(p,s-1),(u,"!ENT"))
        if s<3: N(n,"RC%d_%d"%(p,s),(u,"!RCO"))
        for bit in range(4):
            N(n,"PB%d"%(s*4+bit),)
        for bit,q in enumerate(("QA","QB","QC","QD")):
            N(n,"PQ%d_%d"%(p,s*4+bit),(u,q))
for p in range(4):
    for half in range(2):
        u="U%d"%(17+p*2+half)
        N(n,"-SEL%d"%p,(u,"!G1"),(u,"!G2"))
        for b in range(8):
            N(n,"PQ%d_%d"%(p,half*8+b),(u,"A%d"%(b+1)))
            N(n,"PB%d"%(half*8+b),(u,"Y%d"%(b+1)))
for half,u in ((0,"U25"),(1,"U26")):
    N(n,"GND",(u,"!G1"),(u,"!G2"))
    for b in range(8):
        N(n,"PB%d"%(half*8+b),(u,"A%d"%(b+1)))
        N(n,"A%d"%(half*8+b),(u,"Y%d"%(b+1)))
for k,(u,lo) in enumerate((("U27",0),("U28",4))):
    N(n,"POEHP",(u,"S")); N(n,"GND",(u,"!OE"))
    for b in range(4):
        N(n,"PB%d"%(lo+b),(u,"A%d"%(b+1)))
        N(n,"PB%d"%(8+lo+b),(u,"B%d"%(b+1)))
        N(n,"RB%d"%(lo+b),(u,"Y%d"%(b+1)))
N(n,"-POE",("U29","!G1"),("U29","!G2"))
for b in range(8):
    N(n,"RB%d"%b,("U29","A%d"%(b+1))); N(n,"D%d"%b,("U29","Y%d"%(b+1)))
for u,f in (("U30","DLD"),("U31","DOE")):
    for i,pn in enumerate(("A","B","C")): N(n,"%s%d"%(f,i),(u,pn))
    N(n,"%s3"%f,(u,"G1")); N(n,"GND",(u,"!G2A"),(u,"!G2B"))
# load-decode enables are gated with PSEL2 (off for PT); U40 also derives the
# PT load strobes. -LDLG/-LDHG = -LDL|PSEL2 / -LDH|PSEL2 ; -LDL4/-LDH4 = -LDL|-SEL4 etc.
N(n,"-LDL",("U30","Y0"),("U40","1A"),("U40","3A"))
N(n,"-LDH",("U30","Y1"),("U40","2A"),("U40","4A"))
N(n,"PSEL2",("U40","1B"),("U40","2B"))
N(n,"-SEL4",("U40","3B"),("U40","4B"))
N(n,"-LDLG",("U40","1Y"),("U32","!G1")); N(n,"-LDHG",("U40","2Y"),("U32","!G2"))
N(n,"-LDL4",("U40","3Y")); N(n,"-LDH4",("U40","4Y"))
N(n,"-POEL",("U31","Y0"),("U37","3A")); N(n,"-POEH",("U31","Y1"),("U37","3B"),("U35","2A"))
N(n,"POEHP",("U35","2Y"))
N(n,"-POE",("U37","3Y"),("U38","1A"),("U38","1B"))
# U32 load decoder (74139): PSEL0/1 on both gates -> -LDL0..3 / -LDH0..3
for i,pn in enumerate(("A1","B1","A2","B2")): N(n,"PSEL%d"%(i%2),("U32",pn))
for p in range(4):
    N(n,"-LDL%d"%p,("U32","1Y%d"%p)); N(n,"-LDH%d"%p,("U32","2Y%d"%p))
# U33 select decoder (74138, 3-bit PSEL): -SEL0..4 (P0-P3 + PT)
N(n,"PSEL0",("U33","A")); N(n,"PSEL1",("U33","B")); N(n,"PSEL2",("U33","C"))
N(n,"VCC",("U33","G1")); N(n,"GND",("U33","!G2A"),("U33","!G2B"))
for p in range(4): N(n,"-SEL%d"%p,("U33","Y%d"%p))
N(n,"-SEL4",("U33","Y4"))
# U39 count decoder (74139 gate1): PSEL0/1, enabled by CNTN (P0-P3 only)
N(n,"PSEL0",("U39","A1")); N(n,"PSEL1",("U39","B1"))
for p in range(4): N(n,"-CNT%d"%p,("U39","1Y%d"%p))
N(n,"VCC",("U39","!G2")); N(n,"GND",("U39","A2"),("U39","B2"))
N(n,"CNTN",("U34","1Y"),("U39","!G1"))
N(n,"PINC",("U34","1A")); N(n,"PDEC",("U34","1B"),("U35","1A"))
N(n,"UDB",("U35","1Y"))
N(n,"GND",*[("U34",p) for p in ("2A","2B","3A","3B","4A","4B")],
  *[("U35",p) for p in ("3A","4A","5A","6A")],
  ("U38","3A"),("U38","3B"),("U38","4A"),("U38","4B"),("LED3","K"),
  *[("U36","A%d"%k) for k in range(1,9)])
N(n,"-RES",("U36","!G1"),("U36","!G2"),("U37","1B"),("U37","2B"))
for b in range(8): N(n,"D%d"%b,("U36","Y%d"%(b+1)))
N(n,"-LDL0",("U37","1A")); N(n,"-LDL0E",("U37","1Y"))
N(n,"-LDH0",("U37","2A")); N(n,"-LDH0E",("U37","2Y"))
N(n,"-LDL",("U37","4A")); N(n,"-LDH",("U37","4B"))
N(n,"-LDP",("U37","4Y"),("U38","2A"),("U38","2B"))
N(n,"RDK",("U38","1Y"),("LED4","K")); N(n,"LDK",("U38","2Y"),("LED5","K"))
N(n,"VCC",("RP1","1"),("R4","1"),("R5","1"))
N(n,"LEDP",("RP1","2"),("LED3","A"))
N(n,"LEDRD",("R4","2"),("LED4","A")); N(n,"LEDLD",("R5","2"),("LED5","A"))
# PT scratch pointer (PSEL=4): 74377 latches loaded from D0-7 on -LDL4/-LDH4,
# driven onto the pointer bus PB via 74244 buffers when -SEL4.
for half,ureg,ubuf,lds in ((0,"U41","U43","-LDL4"),(1,"U42","U44","-LDH4")):
    N(n,"CLK",(ureg,"CLK"))
    N(n,lds,(ureg,"!E"))
    for b in range(8):
        N(n,"D%d"%b,(ureg,"D%d"%(b+1)))
        N(n,"PTQ%d_%d"%(half,b),(ureg,"Q%d"%(b+1)),(ubuf,"A%d"%(b+1)))
    N(n,"-SEL4",(ubuf,"!G1"),(ubuf,"!G2"))
    for b in range(8):
        N(n,"PB%d"%(half*8+b),(ubuf,"Y%d"%(b+1)))
n={k:v for k,v in n.items() if v}
card("regbank-card","P8X REGISTER BANK CARD REV B (P0=PC P3=SP, PT scratch)",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"A%d"%i for i in range(16)}|
 {"DLD%d"%i for i in range(4)}|{"DOE%d"%i for i in range(4)}|
 {"PSEL0","PSEL1","PSEL2","PINC","PDEC","CLK","-RES"})

# ===================== ALU CARD ===============================================
n={}
ic={"U1":("74377V2","A REG"),"U2":("74244","A OUT"),"U3":("74377V2","B REG"),
 "U4":("74244","B OUT"),"U5":("74377V2","T REG"),"U6":("74244","T OUT"),
 "U7":("74377V2","T2 REG"),"U8":("74244","T2 OUT"),
 "U9":("74181","ALU LO"),"U10":("74181","ALU HI"),"U11":("74182","CLA"),
 "U12":("74157","SH1 LO"),"U13":("74157","SH1 HI"),
 "U14":("74157","SH2 LO"),"U15":("74157","SH2 HI"),
 "U16":("74244","ALU OUT"),"U17":("74175","FLAGS"),"U18":("74260","Z DET"),
 "U19":("GATES14","74HCT08"),"U20":("74138","DOE DEC"),"U21":("74138","DLD DEC"),
 "U22":("74157","FLAG MUX"),"U23":("74244","FLAG OUT"),
 "U24":("GATES14","74HCT32"),"U25":("GATES14","74HCT00"),
 # rev B flag-register redesign (split C; LDZN Z/N; SETC/CLRC; carry-coupled shifter)
 "U26":("7474","C FLAG FF"),"U27":("74260","BUS Z-DET"),
 "U28":("74157","SHIFT-OUT MUX"),"U29":("74157","C-SRC MUX"),
 "U30":("74157","SHIN MUX"),"U31":("GATES14","74HCT08"),
 # rev C: 2nd ALU-input mux. B-side operand = B register (BSEL=0) or T (BSEL=1).
 "U32":("74157","B-MUX LO"),"U33":("74157","B-MUX HI"),
 # rev C: V (signed overflow) derivation — sign-bit method, ungated by M
 # (valid after ADD/SUB/CMP). U34 XORs, U35 ANDs.
 "U34":("GATES14","74HCT86"),"U35":("GATES14","74HCT08")}
sm={"RP1":("RES","1K"),"LED3":("LED","PWR-GRN"),
 "R4":("RES","1K"),"LED4":("LED","ALU-GRN"),"R5":("RES","1K"),"LED5":("LED","LDF-YEL")}
REGS=(("U1","U2","A","Y1"),("U3","U4","B","Y2"),("U5","U6","T","Y3"),("U7","U8","T2","Y4"))
for i,(ur,ub,nm,doey) in enumerate(REGS):
    N(n,"CLK",(ur,"CLK"))
    N(n,"-LD%s"%nm,(ur,"!E"),("U21","Y%d"%(i+1)))
    for b in range(8):
        N(n,"D%d"%b,(ur,"D%d"%(b+1)),(ub,"Y%d"%(b+1)))
        N(n,"%sQ%d"%(nm,b),(ur,"Q%d"%(b+1)),(ub,"A%d"%(b+1)))
    N(n,"-DOE%s"%nm,(ub,"!G1"),(ub,"!G2"),("U20",doey))
# A operand: A register straight to 74181 A inputs. B operand: routed through
# the rev-C B-mux (U32/U33, 74157) which selects B register (BSEL=0, on the A
# legs) or T register (BSEL=1, on the B legs); muxed result BMX -> 74181 B.
for b in range(4):
    N(n,"AQ%d"%b,("U9","A%d"%b)); N(n,"BMX%d"%b,("U9","B%d"%b))
    N(n,"AQ%d"%(4+b),("U10","A%d"%b)); N(n,"BMX%d"%(4+b),("U10","B%d"%b))
for mux,base in (("U32",0),("U33",4)):
    N(n,"BSEL",(mux,"S")); N(n,"GND",(mux,"!G"))
    for k in range(4):
        N(n,"BQ%d"%(base+k),(mux,"A%d"%(k+1)))   # BSEL=0 -> B register
        N(n,"TQ%d"%(base+k),(mux,"B%d"%(k+1)))   # BSEL=1 -> T register
        N(n,"BMX%d"%(base+k),(mux,"Y%d"%(k+1)))  # muxed operand -> 74181 B
for u in ("U9","U10"):
    for s in range(4): N(n,"ALUS%d"%s,(u,"S%d"%s))
    N(n,"ALUM",(u,"M"))
N(n,"CIN",("U9","CN"),("U11","CN"),("U30","A1"))   # ALU carry-in + shifter shift-in mux (A)
N(n,"CP0",("U9","!P"),("U11","!P0")); N(n,"CG0",("U9","!G"),("U11","!G0"))
N(n,"CP1",("U10","!P"),("U11","!P1")); N(n,"CG1",("U10","!G"),("U11","!G1"))
N(n,"CNX",("U11","CNX"),("U10","CN"))
N(n,"VCC",("U11","!P2"),("U11","!G2"),("U11","!P3"),("U11","!G3"))
# rev B: C flag is conventional active-high -> invert the raw 74181 Cn+4
# (active-low) with a spare U25 NAND gate before the flag mux.
N(n,"CFLG",("U10","CN4"),("U25","2A"),("U25","2B"))
N(n,"CFLGI",("U25","2Y"),("U29","A1"))   # inverted Cn+4 -> C-source mux (non-shift input)
for b in range(8):
    u="U12" if b<4 else "U13"; i=b%4+1
    N(n,"F%d"%b,("U9" if b<4 else "U10","F%d"%(b%4)),(u,"A%d"%i))
    if b>0: N(n,"F%d"%(b-1),(u,"B%d"%i))
for b in range(8):
    u="U14" if b<4 else "U15"; i=b%4+1
    N(n,"G%d"%b,("U12" if b<4 else "U13","Y%d"%(b%4+1)),(u,"A%d"%i))
    if b<7: N(n,"G%d"%(b+1),(u,"B%d"%i))
for b in range(8):
    N(n,"R%d"%b,("U14" if b<4 else "U15","Y%d"%(b%4+1)),("U16","A%d"%(b+1)))
    N(n,"D%d"%b,("U16","Y%d"%(b+1)))
for u in ("U12","U13"): N(n,"SH0",(u,"S")); N(n,"GND",(u,"!G"))
for u in ("U14","U15"): N(n,"SH1",(u,"S")); N(n,"GND",(u,"!G"))
N(n,"-DOEALU",("U16","!G1"),("U16","!G2"),("U20","Y5"),("U19","3A"),("U19","3B"))
for b in range(5): N(n,"R%d"%b,("U18",["A1","B1","C1","D1","E1"][b]))
for b in range(3): N(n,"R%d"%(5+b),("U18",["A2","B2","C2"][b]))
N(n,"GND",("U18","D2"),("U18","E2"))
N(n,"ZL",("U18","Y1"),("U19","1A")); N(n,"ZH",("U18","Y2"),("U19","1B"))
# ---- rev B flag register ----------------------------------------------------
# Z/N source mux U22 (74157, S=LDZN): A=ALU result flags, B=bus-derived (loads)
N(n,"ZFLG",("U19","1Y"),("U22","A1"))            # ALU zero (U18 -> U19 gate1)
N(n,"R7",("U22","A2"))                            # ALU result bit 7
N(n,"ZBUS",("U22","B1")); N(n,"D7",("U22","B2"))  # bus all-zero / bus bit 7
N(n,"LDZN",("U22","S")); N(n,"GND",("U22","!G"))
N(n,"ZSRC",("U22","Y1")); N(n,"NSRC",("U22","Y2"))
# bus zero-detect U27 (74260 dual 5-in NOR): ZBUS = NOR(D0-4) & NOR(D5-7)
for b in range(5): N(n,"D%d"%b,("U27",["A1","B1","C1","D1","E1"][b]))
for b in range(3): N(n,"D%d"%(5+b),("U27",["A2","B2","C2"][b]))
N(n,"GND",("U27","D2"),("U27","E2"))
N(n,"ZBL",("U27","Y1"),("U19","2A")); N(n,"ZBH",("U27","Y2"),("U19","2B"))
N(n,"ZBUS",("U19","2Y"))
# Z,N,V flip-flops in U17 (74175), clocked on (LDF|LDZN); V hardwired 0
N(n,"ZSRC",("U17","D1")); N(n,"NSRC",("U17","D2")); N(n,"VSRC",("U17","D3"))
# rev C: V (signed overflow). V = (A7^F7) & (A7^B7^~ALUS2). A7=AQ7, B7=BMX7
# (muxed B operand), F7=raw ALU result sign. U34 (74HCT86) XORs, U35 (74HCT08) AND.
N(n,"AQ7",("U34","1A"));   N(n,"F7",("U34","1B"));    N(n,"VX1",("U34","1Y"))   # A7^F7
N(n,"AQ7",("U34","2A"));   N(n,"BMX7",("U34","2B"));  N(n,"VX2",("U34","2Y"))   # A7^B7
N(n,"ALUS2",("U34","3A")); N(n,"VCC",("U34","3B"));   N(n,"NS2",("U34","3Y"))   # ~S2 = S2^1
N(n,"VX2",("U34","4A"));   N(n,"NS2",("U34","4B"));   N(n,"VX4",("U34","4Y"))   # A7^B7^~S2
N(n,"VX1",("U35","1A"));   N(n,"VX4",("U35","1B"));   N(n,"VSRC",("U35","1Y"))  # V = VX1 & VX4
N(n,"GND",("U35","2A"),("U35","2B"),("U35","3A"),("U35","3B"),("U35","4A"),("U35","4B"))
N(n,"-RES",("U17","!CLR"))
# C-flag source: shift-out when shifting else inverted Cn+4
N(n,"SH0",("U28","S")); N(n,"F0",("U28","A1")); N(n,"F7",("U28","B1"))
N(n,"SHOUT",("U28","Y1")); N(n,"GND",("U28","!G"))
N(n,"SH0",("U24","2A")); N(n,"SH1",("U24","2B")); N(n,"SHANY",("U24","2Y"))
N(n,"SHANY",("U29","S")); N(n,"SHOUT",("U29","B1"))   # CFLGI on A1 (wired above)
N(n,"NC",("U29","Y1")); N(n,"GND",("U29","!G"))
# C flag in its own 7474 (U26): clocked on LDF; SETC/CLRC force via preset/clear
N(n,"NC",("U26","1D")); N(n,"CLKFC",("U26","1CLK"))
N(n,"-SETCb",("U26","!1PRE")); N(n,"-CCLR",("U26","!1CLR"))
N(n,"VCC",("U26","!2PRE"),("U26","!2CLR")); N(n,"GND",("U26","2D"),("U26","2CLK"))
# shifter shift-in mux U30 (74157, S=SHCIN): CIN (A1) else current C (B1)
N(n,"SHCIN",("U30","S")); N(n,"FQC",("U30","B1"))
N(n,"SHIN",("U30","Y1"),("U12","B1"),("U15","B4")); N(n,"GND",("U30","!G"))
# clock gates (U31 AND) and flag forces (U24 OR / U25 NAND inverters)
N(n,"LDF",("U24","1A"),("U31","1B"),("U25","3A"),("U25","3B")); N(n,"LDZN",("U24","1B"))
N(n,"FENZN",("U24","1Y"),("U31","2A"))            # LDF | LDZN
N(n,"SETC",("U25","1A"),("U25","1B")); N(n,"-SETCb",("U25","1Y"))
N(n,"CLRC",("U25","4A"),("U25","4B")); N(n,"-CLRCb",("U25","4Y"))
N(n,"CLK",("U31","1A"),("U31","2B")); N(n,"CLKFC",("U31","1Y"))   # CLK & LDF
N(n,"CLKFZN",("U31","2Y"),("U17","CLK"))          # CLK & (LDF|LDZN)
N(n,"-RES",("U31","3A")); N(n,"-CLRCb",("U31","3B")); N(n,"-CCLR",("U31","3Y"))
N(n,"GND",("U31","4A"),("U31","4B"))
# flag outputs -> U23 buffer: FQC from U26, FQZ/FQN/FQV from U17
N(n,"FQC",("U26","1Q"),("U23","A1"),("U23","A5"))
N(n,"FQZ",("U17","Q1"),("U23","A2"),("U23","A6"))
N(n,"FQN",("U17","Q2"),("U23","A3"),("U23","A7"))
N(n,"FQV",("U17","Q3"),("U23","A4"),("U23","A8"))
for i in range(4): N(n,"D%d"%i,("U23","Y%d"%(i+1)))
for i,f in enumerate(("FC","FZ","FN","FV")): N(n,f,("U23","Y%d"%(i+5)))
N(n,"-DOEFLG",("U20","Y6"),("U23","!G1"))
N(n,"GND",("U23","!G2"))
for u,fld in (("U20","DOE"),("U21","DLD")):
    for i,pn in enumerate(("A","B","C")): N(n,"%s%d"%(fld,i),(u,pn))
    N(n,"%s3"%fld,(u,"!G2A")); N(n,"VCC",(u,"G1")); N(n,"GND",(u,"!G2B"))
N(n,"ALUK",("U19","3Y"),("LED4","K"))
N(n,"LDFK",("U25","3Y"),("LED5","K"))
N(n,"GND",("U19","4A"),("U19","4B"),("U24","3A"),
  ("U24","3B"),("U24","4A"),("U24","4B"),("LED3","K"))
N(n,"VCC",("RP1","1"),("R4","1"),("R5","1"))
N(n,"LEDP",("RP1","2"),("LED3","A"))
N(n,"LEDAL",("R4","2"),("LED4","A")); N(n,"LEDLF",("R5","2"),("LED5","A"))
card("alu-card","P8X ALU CARD REV B (conventional carry, LDZN, SETC/CLRC, carry-coupled shifter)",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"DOE%d"%i for i in range(4)}|{"DLD%d"%i for i in range(4)}|
 {"ALUS0","ALUS1","ALUS2","ALUS3","ALUM","CIN","SH0","SH1","LDF","CLK","-RES",
  "FC","FZ","FN","FV","LDZN","SHCIN","SETC","CLRC","BSEL"},
 labels={"U31":"CLK/FORCE GATES","U34":"V XOR","U35":"V AND"})

# ===================== I/O CARD ===============================================
n={}
ic={"U1":("7430","IO PAGE"),"U2":("74138","PORT DEC"),"U3":("74138","DOE DEC"),
 "U4":("74138","DLD DEC"),"U5":("GATES14","74HCT32"),"U6":("GATES14","74HCT08"),
 "U7":("74161","BAUD DIV"),"U8":("MAX232","RS232"),"U9":("74244","SW IN"),
 "U10":("74374","LED PORT"),"U11":("74244","MON A-LO"),"U12":("74244","MON A-HI"),
 "U13":("74244","MON D"),"U14":("6850","ACIA"),"U15":("GATES14","74HCT00"),
 "U16":("DS1302","RTC DNP")}   # rev C: real-time clock, provisioned DNP
sm={"X2":("OSC","2.4576MHZ"),"SW1":("DIP8SW","INPUT"),"RNP":("SIP9","8X10K"),
 "RL1":("RNISO8","8X330R"),"LA1":("LEDARR8","8-LED BAR"),
 "RM1":("RNISO8","8X330R"),"LM1":("LEDARR8","A0-7"),
 "RM2":("RNISO8","8X330R"),"LM2":("LEDARR8","A8-15"),
 "RM3":("RNISO8","8X330R"),"LM3":("LEDARR8","D0-7"),
 "J2":("HDR3","SERIAL"),"C2":("CAP","1U"),"C3":("CAP","1U"),"C4":("CAP","1U"),
 "C5":("CAP","1U"),"RP1":("RES","1K"),"LED3":("LED","PWR-GRN"),
 "R4":("RES","1K"),"LED4":("LED","IOSEL-YEL"),
 # rev C RTC support parts (DNP): 32.768kHz crystal, backup coin cell, and a
 # 3-pin header breaking out the DS1302 3-wire (CE/SCLK/IO) so it can be jumpered
 # to a port during bring-up. Reserved I/O address: $FF08 (PORT DEC U2 Y3).
 "X3":("XTAL32","32.768KHZ"),"BT1":("COIN","CR2032"),"J3":("HDR3","RTC 3-WIRE")}
for i in range(8): N(n,"A%d"%(8+i),("U1","ABCDEFGH"[i]))
N(n,"IOPG",("U1","Y"),("U2","!G2A"),("U15","3A"),("U15","3B"))
for i,pn in enumerate(("A","B","C")): N(n,"A%d"%(i+1),("U2",pn))
N(n,"VCC",("U2","G1")); N(n,"GND",("U2","!G2B"))
N(n,"-P0",("U2","Y0"),("U5","1A")); N(n,"-P1",("U2","Y1"),("U5","2A"))
N(n,"-P2",("U2","Y2"),("U15","2A"),("U15","2B"))
for u,fld,y in (("U3","DOE","-RD"),("U4","DLD","-MEMW")):
    for i,pn in enumerate(("A","B","C")): N(n,"%s%d"%(fld,i),(u,pn))
    N(n,"%s3"%fld,(u,"!G2A")); N(n,"VCC",(u,"G1")); N(n,"GND",(u,"!G2B"))
N(n,"-RD",("U3","Y7"),("U5","1B"),("U5","4A"))
N(n,"-MEMW",("U4","Y7"),("U5","2B"),("U5","4B"),("U14","RW"))
N(n,"-SWOE",("U5","1Y"),("U9","!G1"),("U9","!G2"))
N(n,"LW1",("U5","2Y"),("U5","3A"))
N(n,"CLKB",("U15","1A"),("U15","1B"),("U6","2B"))
N(n,"CLKBN",("U15","1Y"),("U5","3B"))
N(n,"LCK",("U5","3Y"),("U10","CLK"))
N(n,"BOEISH",("U5","4Y"),("U15","4A"),("U15","4B"))
N(n,"ACCP",("U15","4Y"),("U6","3B"))
N(n,"IOPGN",("U15","3Y"),("U6","3A"))
N(n,"SELP",("U6","3Y"),("R4","2"))
N(n,"LED4A",("R4","1"))
N(n,"LED4A",("LED4","A")); N(n,"GND",("LED4","K"))
N(n,"P2P",("U15","2Y"),("U6","2A"))
N(n,"EEN",("U6","2Y"),("U14","E"))
for b in range(8):
    N(n,"SWN%d"%b,("SW1","A%d"%(b+1)),("RNP","R%d"%(b+1)),("U9","A%d"%(b+1)))
    N(n,"GND",("SW1","B%d"%(b+1)))
    N(n,"D%d"%b,("U9","Y%d"%(b+1)),("U10","D%d"%(b+1)),("U13","A%d"%(b+1)),("U14","D%d"%b))
    N(n,"LP%d"%b,("U10","Q%d"%(b+1)),("RL1","A%d"%(b+1)))
    N(n,"LR%d"%b,("RL1","B%d"%(b+1)),("LA1","A%d"%(b+1)))
    N(n,"GND",("LA1","K%d"%(b+1)))
N(n,"VCC",("RNP","COM"),("U14","CS0"),("U14","CS1"))
N(n,"GND",("U10","!OC"),("U14","!CTS"),("U14","!DCD"))
N(n,"-P2",("U14","!CS2"))
N(n,"A0",("U14","RS"))
N(n,"BOSC",("X2","OUT"),("U7","CLK"))
N(n,"VCC",("X2","VCC"),("U7","ENP"),("U7","ENT"),("U7","!LOAD"),("U7","!CLR"))
N(n,"GND",("X2","GND"),("U7","A"),("U7","B"),("U7","C"),("U7","D"))
N(n,"BCLK",("U7","QD"),("U14","TXCLK"),("U14","RXCLK"))
N(n,"TXD",("U14","TXD"),("U8","T1IN"))
N(n,"RXD",("U14","RXD"),("U8","R1OUT"))
N(n,"SOUT",("U8","T1OUT"),("J2","1")); N(n,"SIN",("U8","R1IN"),("J2","2"))
N(n,"GND",("J2","3"),("LED3","K"))
N(n,"C1PN",("U8","C1P"),("C2","1")); N(n,"C1MN",("U8","C1M"),("C2","2"))
N(n,"C2PN",("U8","C2P"),("C3","1")); N(n,"C2MN",("U8","C2M"),("C3","2"))
N(n,"VPN",("U8","VP"),("C4","1")); N(n,"GND",("C4","2"))
N(n,"VMN",("U8","VM"),("C5","1")); N(n,"GND",("C5","2"))
for half,u in ((0,"U11"),(1,"U12")):
    N(n,"GND",(u,"!G1"),(u,"!G2"))
    for b in range(8):
        N(n,"A%d"%(half*8+b),(u,"A%d"%(b+1)))
        N(n,"MA%d"%(half*8+b),(u,"Y%d"%(b+1)))
N(n,"GND",("U13","!G1"),("U13","!G2"))
for b in range(8): N(n,"MD%d"%b,("U13","Y%d"%(b+1)))
for arr,(rm,lm,pre) in enumerate((("RM1","LM1","MA"),("RM2","LM2","MA"),("RM3","LM3","MD"))):
    off=8 if arr==1 else 0
    for b in range(8):
        sig="%s%d"%(pre,off+b)
        N(n,sig,(rm,"A%d"%(b+1)))
        N(n,"ML%d_%d"%(arr,b),(rm,"B%d"%(b+1)),(lm,"A%d"%(b+1)))
        N(n,"GND",(lm,"K%d"%(b+1)))
N(n,"VCC",("RP1","1"))
N(n,"LEDP",("RP1","2"),("LED3","A"))
N(n,"GND",("U6","1A"),("U6","1B"))
# rev C RTC (DS1302) — fully isolated 3-wire peripheral, safe to wire (no bus
# contention possible). Crystal across X1/X2, VCC1 from +5, VCC2 from the coin
# cell, and the 3-wire (CE/SCLK/IO) brought to header J3. Connecting the 3-wire
# to a CPU port (reserved $FF08) is left for bring-up — jumper J3 to spare port
# bits, or add a small DNP latch/buffer once the protocol is validated.
N(n,"RTCX1",("U16","X1"),("X3","1")); N(n,"RTCX2",("U16","X2"),("X3","2"))
N(n,"VCC",("U16","VCC1")); N(n,"VBAT",("U16","VCC2"),("BT1","+"))
N(n,"GND",("U16","GND"),("BT1","-"))
N(n,"RTCCE",("U16","CE"),("J3","1")); N(n,"RTCSCLK",("U16","SCLK"),("J3","2"))
N(n,"RTCIO",("U16","IO"),("J3","3"))
card("io-card","P8X I/O CARD REV A - ACIA + SWITCHES + LEDS + BUS MONITOR",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"A%d"%i for i in range(16)}|
 {"DOE%d"%i for i in range(4)}|{"DLD%d"%i for i in range(4)}|{"CLKB","-RES"})

# ===================== CF-IDE CARD ============================================
n={}
ic={"U1":("74245","DATA BUF"),"U2":("7430","IO PAGE"),"U3":("74138","DOE DEC"),
 "U4":("74138","DLD DEC"),"U5":("HEX14","74HCT14"),"U6":("7410","74HCT10"),
 "U7":("7410","74HCT10"),"U8":("GATES14","74HCT08"),
 # rev C: 8-bit-mode fallback latch (DNP). Only needed if a CF card refuses True
 # IDE 8-bit mode; it captures the CF high data byte (D8-15) so it can be read
 # back separately. Provisioned DNP — inputs wired, outputs/clock/decode deferred.
 "U9":("74374","CF HI-BYTE DNP")}
sm={"J2":("IDE40","IDE-40"),"RN1":("SIP9","8X10K"),
 "RP1":("RES","1K"),"LED3":("LED","PWR-GRN"),
 "R4":("RES","1K"),"LED4":("LED","ACT-YEL"),
 "R5":("RES","330R"),"LED5":("LED","DASP-GRN")}
for i in range(8): N(n,"A%d"%(8+i),("U2","ABCDEFGH"[i]))
N(n,"IOPG",("U2","Y"),("U5","1A"))
N(n,"IOPGP",("U5","1Y"),("U6","1A"),("U6","2A"))
for u,fld,y in (("U3","DOE","-RD"),("U4","DLD","-MEMW")):
    for i,pn in enumerate(("A","B","C")): N(n,"%s%d"%(fld,i),(u,pn))
    N(n,"%s3"%fld,(u,"!G2A")); N(n,"VCC",(u,"G1")); N(n,"GND",(u,"!G2B"))
N(n,"-RD",("U3","Y7"),("U5","2A")); N(n,"-MEMW",("U4","Y7"),("U5","3A"))
N(n,"RDP",("U5","2Y"),("U7","1B")); N(n,"WRP",("U5","3Y"),("U7","2B"))
N(n,"A3",("U6","2C"),("U5","4A")); N(n,"A3N",("U5","4Y"),("U6","1C"))
N(n,"A4",("U6","1B"),("U6","2B"))
N(n,"-CS0",("U6","1Y"),("J2","37"),("U8","1A"))
N(n,"-CS1",("U6","2Y"),("J2","38"),("U8","1B"))
N(n,"-CFSEL",("U8","1Y"),("U5","5A"))
N(n,"SELP",("U5","5Y"),("U7","1A"),("U7","2A"))
N(n,"CLKB",("U7","1C"),("U7","2C"))
N(n,"-IOR",("U7","1Y"),("J2","25"),("U1","DIR"),("U8","2A"))
N(n,"-IOW",("U7","2Y"),("J2","23"),("U8","2B"))
N(n,"-CFOE",("U8","2Y"),("U1","!OE"),("U8","3A"),("U8","3B"))
N(n,"ACTK",("U8","3Y"),("LED4","K"))
for b in range(8):
    N(n,"D%d"%b,("U1","A%d"%b))
    N(n,"CFD%d"%b,("U1","B%d"%b),("J2",str(17-2*b)))
for i,pin in enumerate(("35","33","36")): N(n,"A%d"%i,("J2",pin))
N(n,"-RES",("J2","1"))
N(n,"VCC",("RN1","COM"),("J2","29"))
N(n,"IORDY",("RN1","R1"),("J2","27"))
N(n,"-PDIAG",("RN1","R2"),("J2","34"))
N(n,"-DASP",("RN1","R3"),("J2","39"),("LED5","K"))
N(n,"GND",("J2","28"),*[("J2",p) for p in ("2","19","22","24","26","30","40")],
  ("LED3","K"),("U8","4A"),("U8","4B"),
  ("U6","3A"),("U6","3B"),("U6","3C"),("U7","3A"),("U7","3B"),("U7","3C"),
  ("U5","6A"))
N(n,"VCC",("RP1","1"),("R4","1"),("R5","1"))
N(n,"LEDP",("RP1","2"),("LED3","A"))
N(n,"LEDAC",("R4","2"),("LED4","A")); N(n,"LEDDA",("R5","2"),("LED5","A"))
# rev C 8-bit fallback latch (DNP). Capture the CF high data byte D8-15 (J2 even
# data pins) into U9; safe wiring only: inputs from the CF connector, output
# enable held high (high-Z) and clock grounded (never latches). The bus-critical
# parts — Q outputs onto D0-7 and a decoded read/clock — are deferred (design
# with DRC). Only populate if 8-bit-mode testing shows a card needs it.
for b,pin in enumerate(("4","6","8","10","12","14","16","18")):
    N(n,"CFD%d"%(8+b),("U9","D%d"%(b+1)),("J2",pin))
N(n,"VCC",("U9","!OC")); N(n,"GND",("U9","CLK"))   # outputs high-Z, no clocking (safe)
card("cf-card","P8X CF-IDE CARD REV A - 8-BIT TRUE IDE AT 0xFF10",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"A0","A1","A2","A3","A4"}|{"A%d"%i for i in range(8,16)}|
 {"DOE%d"%i for i in range(4)}|{"DLD%d"%i for i in range(4)}|{"CLKB","-RES"})

# ===================== MEMORY CARD rev C ======================================
# Built through the shared card() helper like every other logic card (placement
# is auto — final layout is done in Fusion/Eagle). card() supplies J1, the per-IC
# decoupling caps, the IC power pins, and the J1 bus/power wiring derived from
# used_bus + busnet(). So this only declares the functional netlist — and routing
# J1 via busnet() means the rev-D even-pin spares are no longer tied to GND.
ic={"U1":("MEM28K8","28C256"),"U2":("MEM28K8","62256"),
 "U3":("74245","74HCT245"),"U4":("7430","74HCT30"),
 "U5":("74138","DOE DEC"),"U6":("74138","DLD DEC"),
 "U7":("GATES14","74HCT00"),"U8":("GATES14","74HCT32"),"U9":("GATES14","74HCT08")}
sm={"RP1":("RES","1K"),"LED3":("LED","PWR-GRN"),
 "RS1":("RES","1K"),"LED2":("LED","ROM-YEL"),
 "RS2":("RES","1K"),"LED4":("LED","RAM-YEL"),
 "RS3":("RES","1K"),"LED5":("LED","RD-GRN"),
 "RS4":("RES","1K"),"LED6":("LED","WR-RED"),
 # ROM write-protect jumper (3-pin select on the 28C256 !WE: 1-2 = -WE writable
 # [default], 2-3 = VCC write-protected; RAM stays on -WE).
 "JWP":("HDR3","ROM-WP")}
mcn={}
def mnet(n,*p): mcn.setdefault(n,[]).extend(p)
for i in range(8):
    mnet("D%d"%i,("U3","A%d"%i))
    mnet("MD%d"%i,("U3","B%d"%i),("U1","IO%d"%i),("U2","IO%d"%i))
for i in range(16):
    pins=[]
    if i<15: pins+=[("U1","A%d"%i),("U2","A%d"%i)]
    if 8<=i<=14: pins.append(("U4","ABCDEFG"[i-8]))
    if i==15: pins+=[("U4","H"),("U1","!CE"),("U7","1A")]
    mnet("A%d"%i,*pins)
mnet("-IOPG",("U4","Y"),("U7","1B"))
mnet("-RAMCE",("U7","1Y"),("U2","!CE"))
for i in range(4):
    mnet("DOE%d"%i,("U5",["A","B","C","!G2A"][i]))
    mnet("DLD%d"%i,("U6",["A","B","C","!G2A"][i]))
mnet("-RD",("U5","Y7"),("U1","!OE"),("U2","!OE"),("U3","DIR"),("U9","1A"))
mnet("-MEMW",("U6","Y7"),("U8","1A"),("U9","1B"))
mnet("CLK",("U8","1B"))
# RAM !WE is always on -WE; ROM !WE routes through the JWP select header so it
# can be write-protected (jumper 2-3 -> VCC) without affecting RAM writes.
mnet("-WE",("U8","1Y"),("U2","!WE"),("JWP","1"))
mnet("ROMWE",("JWP","2"),("U1","!WE"))   # header centre -> 28C256 !WE
mnet("VCC",("JWP","3"))                   # protect position: !WE held high
mnet("-BOE",("U9","1Y"),("U3","!OE"))
# functional ties only; card() adds the J1 power/bus pins (via busnet, so the
# even-pin spares stay OFF GND) plus every IC's own VCC/GND supply pin.
mnet("VCC",("U5","G1"),("U6","G1"))
mnet("GND",("U5","!G2B"),("U6","!G2B"),
  *[("U7",p) for p in("2A","2B","3A","3B","4A","4B")],
  ("U8","4A"),("U8","4B"),("U9","4A"),("U9","4B"),("LED3","K"))
mnet("-BOE",("U8","2B"),("U8","3B"))
mnet("-RAMCE",("U8","2A"))
mnet("A15",("U8","3A"))
mnet("-RD",("U9","2A"),("U9","2B"))
mnet("-MEMW",("U9","3A"),("U9","3B"))
mnet("LEDP",("RP1","2"),("LED3","A"))
mnet("LEDRO",("RS1","2"),("LED2","A")); mnet("ROMK",("U8","3Y"),("LED2","K"))
mnet("LEDRA",("RS2","2"),("LED4","A")); mnet("RAMK",("U8","2Y"),("LED4","K"))
mnet("LEDRD",("RS3","2"),("LED5","A")); mnet("RDK",("U9","2Y"),("LED5","K"))
mnet("LEDWR",("RS4","2"),("LED6","A")); mnet("WRK",("U9","3Y"),("LED6","K"))
mnet("VCC",("RP1","1"),("RS1","1"),("RS2","1"),("RS3","1"),("RS4","1"))
card("memory-card","P8X MEMORY CARD REV C",ic,sm,mcn,
 {"D%d"%i for i in range(8)}|{"A%d"%i for i in range(16)}|
 {"DOE%d"%i for i in range(4)}|{"DLD%d"%i for i in range(4)}|{"CLK"})

# ===================== BACKPLANE rev C ========================================
bps={}
for i in range(10):
    bps["J%d"%(i+1)]=("DIN96","SLOT%d"%(i+1),35.56+101.6*(i%5),38.10-281.94*(i//5))
small=[("J11","TB4","PWR-5V",35.56),("CB1","CAPP","470U",86.36),("CB2","CAPP","470U",137.16),
 ("RN1","SIP9","8X10K",187.96),("RT1","RES","100R",238.76),("CT1","CAP","150P",289.56),
 ("RT2","RES","100R",340.36),("CT2","CAP","150P",391.16),("RL1","RES","1K",441.96),("LED1","LED","PWR",492.76)]
for ref,dev,val,x in small: bps[ref]=(dev,val,x,-635.0)
bpn={}
def bnet(n,*p): bpn.setdefault(n,[]).extend(p)
for i in range(10):
    for pin in ALLPINS: bnet(busnet(pin),("J%d"%(i+1),pin))
bnet("VCC",("J11","1"),("J11","2"),("CB1","+"),("CB2","+"),("RN1","COM"),("RL1","1"),
     *[("C%d"%(i+1),"1") for i in range(10)])
bnet("GND",("J11","3"),("J11","4"),("CB1","-"),("CB2","-"),("LED1","K"),("CT1","2"),("CT2","2"),
     *[("C%d"%(i+1),"2") for i in range(10)])
for i in range(10): bps["C%d"%(i+1)]=("CAP1","100N",35.56+50.8*i,-723.9)
for b in range(8): bnet("D%d"%b,("RN1","R%d"%(b+1)))
bnet("CLK",("RT1","1")); bnet("CLK_T",("RT1","2"),("CT1","1"))
bnet("CLKB",("RT2","1")); bnet("CLKB_T",("RT2","2"),("CT2","1"))
bnet("LED_A",("RL1","2"),("LED1","A"))
if EMIT:
    write_sch("backplane/p8x-backplane.sch","P8X 10-SLOT BACKPLANE REV C",bps,bpn)
    validate("backplane/p8x-backplane.sch",bps,bpn)
X0=15.24; P=25.4
def sx(i): return X0+P*i
def py(n): return G*(38-n)
# FABC96S footprint centres its pad field on the element origin (pads y=+/-39.37,
# rows A/B/C at x=-2.54/0/+2.54). Place each slot element at (sx(i)-2.54, EY) so
# the pin field sits on the 109mm board and the A/B/C pads land at the columns
# below; py(n) (the old pin-y) still matches because EY+39.37 = 93.98.
EY=54.61
def padx(i,row): return sx(i)+{"A":-5.08,"B":-2.54,"C":0.0}[row]   # FABC96S pad x for slot i
bpb={}
for i in range(10): bpb["J%d"%(i+1)]=("DIN96","SLOT%d"%(i+1),sx(i)-2.54,EY)
# RN1 pulled off the slot-10 connector into the end zone (was 246.38, hard up
# against the C column at 243.84). Its R1..R8 pads still land on the row-3..10
# A-row D-bus traces, which are extended to follow it (see xe below).
bpb["RN1"]=("SIP9","8X10K",252.0,91.44)
# Ring-reduction (clock AC termination) parked in the lengthened end zone, right
# of RN1 and clear of every slot/bus column (x>=263). Each chain runs left->right:
# clock in -> RTn (R0, pad1=CLK side, pad2=node) -> CTn (node -> GND via pour).
bpb["RT1"]=("RES","100R",264.0,96.0)
bpb["CT1"]=("CAP","150P",279.24,96.0)
bpb["RT2"]=("RES","100R",264.0,80.0)
bpb["CT2"]=("CAP","150P",279.24,80.0)
# Power-entry cluster, pinned to the front (left) edge in the front bay opened by
# the XOFF shift below. CB1/CB2 spread to 23mm apart (was ~10). RL1/LED1 brought
# forward toward the front edge. These five are excluded from the X/Y shifts.
bpb["J11"]=("TB4","PWR-5V",5.08,95.0)
bpb["CB1"]=("CAPP","470U",5.08,68.0); bpb["CB2"]=("CAPP","470U",5.08,45.0)
for s in range(10): bpb["C%d"%(s+1)]=("CAP1","100N",sx(s)+G,104.14)
bpb["RL1"]=("RES","1K",5.08,3.0); bpb["LED1"]=("LED","PWR",18.0,3.0)
wires={}; viad={}
def wadd(n,*w): wires.setdefault(n,[]).extend(w)
def vadd(n,*v): viad.setdefault(n,[]).extend(v)
for n in range(3,31):
    y=py(n)
    nA=busnet("A%d"%n); xe=252.0 if 3<=n<=10 else padx(9,"A")   # rows 3..10 reach RN1
    wadd(nA,(padx(0,"A"),y,xe,y,1,0.4))
    nC=busnet("C%d"%n)
    wadd(nC,(padx(0,"C"),y,padx(9,"C"),y,16,0.4))
# Clock taps to the end-zone terminators. Routed entirely on layer 1 in the free
# channel right of the bus columns (A-row copper ends at 246.38, so x=250/253
# risers cross no other net), straight to RTn pad1; no layer change/via needed.
wadd("CLK",(padx(9,"A"),py(24),256.0,py(24),1,0.4),
           (256.0,py(24),256.0,96.0,1,0.4),
           (256.0,96.0,264.0,96.0,1,0.4))
wadd("CLK_T",(274.16,96.0,279.24,96.0,1,0.4))
wadd("CLKB",(padx(9,"A"),py(25),259.0,py(25),1,0.4),
            (259.0,py(25),259.0,80.0,1,0.4),
            (259.0,80.0,264.0,80.0,1,0.4))
wadd("CLKB_T",(274.16,80.0,279.24,80.0,1,0.4))
wadd("LED_A",(15.24,3.0,18.0,3.0,1,0.4))   # RL1 pad2 -> LED1 anode (both at front)
# Route the non-ground B-row signals slot-to-slot: B27=CLRC, B28=BSEL, B29=IRQ,
# B30=SPARE11, plus the rev-D even-pin spares B4..B26 (SPARE12..23). Odd B pins
# stay ground guards (handled by the GND pour).
for nn in range(3,31):
    net=busnet("B%d"%nn)
    if net in ("GND","VCC"): continue
    y=py(nn)
    wadd(net,(sx(0)-2.54,y-1.27,sx(9)-2.54,y-1.27,1,0.4))
    for i in range(10):
        wadd(net,(sx(i)-2.54,y,sx(i)-2.54,y-1.27,1,0.4))
# Shift the slot field + its routing right by XOFF (opens a front bay at the left
# for the power connector and bulk caps) and up by YOFF (opens a bottom margin so
# the bottom mounting holes clear the bus connectors). The power-entry cluster
# (J11/CB1/CB2/RL1/LED1) and the LED_A net stay pinned to the front edge.
YOFF=7.0; XOFF=16.0
FRONT={"J11","CB1","CB2","RL1","LED1"}
bpb={r:(pv if r in FRONT else pv[:2]+(pv[2]+XOFF,pv[3]+YOFF)+pv[4:]) for r,pv in bpb.items()}
wires={n:(segs if n=="LED_A" else [(a+XOFF,b+YOFF,c+XOFF,d+YOFF,ly,wd) for (a,b,c,d,ly,wd) in segs])
       for n,segs in wires.items()}
viad={n:[(vx+XOFF,vy+YOFF) for (vx,vy) in vs] for n,vs in viad.items()}
if EMIT:
    # M3 mounting holes: 3 along each long (306mm) edge at 100mm pitch (shifted
    # with the slot field by XOFF). Drill 3.2mm = M3 clearance. Board is 306 x 123:
    # XOFF front bay + end-zone cluster on the width, the YOFF lift gives the bottom
    # holes (y=5) room below the connectors; top holes (y=118) clear the cap row.
    bpholes=[(x+XOFF,y,3.2) for y in (5.0,118.0) for x in (40.0,140.0,240.0)]
    write_brd("backplane/p8x-backplane.brd","P8X 10-SLOT BACKPLANE REV C COMPACT",bpb,bpn,wires,
              {"GND":[(2,)],"VCC":[(15,)]},306.0,123.0,viad,holes=bpholes)
    validate("backplane/p8x-backplane.brd",bpb,bpn)

# ===================== LED OUTPUT CARD (test / CAD-workflow trial) ============
# A minimal memory-mapped output card: write a byte to $FF0C and its 8 bits
# appear on 8 LEDs (write-only; no readback). Built with the shared card()
# helper so it gets the standard DIN96C edge connector, per-IC decoupling, and
# IC power-pin wiring automatically. Decode: I/O page (A8-15 all high) + A4=0
# region, port select A1-3 -> Y6 = $FF0C; latched on a write (DLD=7 -> -MEMW)
# phased by CLKB. NOTE: like the other I/O cards it does not decode A5-7, so the
# port aliases every 32 bytes within the page (fine for a scratch test card).
n={}
# value = orderable part number; logical function is in `labels` (placed text).
ic={"U1":("7430","74HCT30"),"U2":("74138","74HCT138"),"U3":("74138","74HCT138"),
 "U4":("GATES14","74HCT32"),"U5":("HEX14","74HCT14"),"U6":("74374","74HCT374")}
sm={"RL1":("RNISO8","8x330R"),"LA1":("LEDARR8","8-LED BAR"),
 "RP1":("RES","1K"),"LED3":("LED","GRN"),
 "R4":("RES","1K"),"LED4":("LED","YEL")}
led_labels={"U1":"I/O PAGE DEC","U2":"PORT DEC $FF0C","U3":"DLD DEC",
 "U4":"WRITE/CLK GATES","U5":"CLKB INVERT","U6":"LED LATCH",
 "RL1":"LED Rs","LA1":"OUTPUT LEDS","LED3":"POWER","LED4":"WRITE ACT"}
for i in range(8): N(n,"A%d"%(8+i),("U1","ABCDEFGH"[i]))   # I/O page: A8-15 -> IOPG
N(n,"IOPG",("U1","Y"),("U2","!G2A"))
for i,pn in enumerate(("A","B","C")): N(n,"A%d"%(i+1),("U2",pn))  # port select A1-3
N(n,"VCC",("U2","G1")); N(n,"A4",("U2","!G2B"))            # require A4=0 ($FF00-0F region)
N(n,"-SEL",("U2","Y6"))                                    # Y6 -> $FF0C
for i,pn in enumerate(("A","B","C")): N(n,"DLD%d"%i,("U3",pn))    # DLD decode -> -MEMW
N(n,"DLD3",("U3","!G2A")); N(n,"VCC",("U3","G1")); N(n,"GND",("U3","!G2B"))
N(n,"-MEMW",("U3","Y7"))
# latch clock: WRSEL low only on a write to our port; LCK = WRSEL OR ~CLKB so a
# clean rising edge captures D0-7 into the 74374 as the write cycle completes.
N(n,"-SEL",("U4","1A")); N(n,"-MEMW",("U4","1B"))
N(n,"WRSEL",("U4","1Y"),("U4","2A"),("LED4","K"))          # WR LED on while WRSEL low
N(n,"CLKB",("U5","1A")); N(n,"CLKBN",("U5","1Y"),("U4","2B"))
N(n,"LCK",("U4","2Y"),("U6","CLK"))
N(n,"GND",("U6","!OC"))                                    # latch outputs always enabled
for b in range(8):
    N(n,"D%d"%b,("U6","D%d"%(b+1)))
    N(n,"LP%d"%b,("U6","Q%d"%(b+1)),("RL1","A%d"%(b+1)))
    N(n,"LR%d"%b,("RL1","B%d"%(b+1)),("LA1","A%d"%(b+1)))
    N(n,"GND",("LA1","K%d"%(b+1)))
# spare gates tied off (U4 OR gates 3,4; U5 unused inverters 2-6)
N(n,"GND",("U4","3A"),("U4","3B"),("U4","4A"),("U4","4B"),
  ("U5","2A"),("U5","3A"),("U5","4A"),("U5","5A"),("U5","6A"))
N(n,"VCC",("RP1","1"),("R4","1"))
N(n,"LEDP",("RP1","2"),("LED3","A")); N(n,"GND",("LED3","K"))
N(n,"LEDWR",("R4","2"),("LED4","A"))
card("led-card","P8X LED OUTPUT CARD (test - write-only 8 LEDs at $FF0C)",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"A1","A2","A3","A4"}|{"A%d"%i for i in range(8,16)}|
 {"DLD%d"%i for i in range(4)}|{"CLKB"},labels=led_labels)   # brd_unplaced is now the default

if EMIT: print("ALL 8 BOARDS GENERATED")
