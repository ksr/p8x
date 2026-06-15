#!/usr/bin/env python3
"""P8X remaining five cards: control, register bank, ALU, I/O, CF-IDE.
Imports the base generator (which regenerates backplane + memory card with
the FC/FZ/FN/FV flag allocation), extends the device library, then emits
sch+brd pairs for each card. NOTE: new device pin numbers require a
datasheet verification pass before fab (tracked in BACKLOG)."""
from gen_eagle_full import *

# ---------------- new packages ------------------------------------------------
PKG["DIP24W"]=dip_pads(24,15.24)
PKG["OSC4"]=[("1",0,0,0.8,1.6),("7",0,-15.24,0.8,1.6),("8",7.62,-15.24,0.8,1.6),("14",7.62,0,0.8,1.6)]
PKG["HDR4"]=[(str(k+1),0,-2.54*k,0.9,1.8) for k in range(4)]
PKG["HDR3"]=[(str(k+1),0,-2.54*k,0.9,1.8) for k in range(3)]
PKG["SW2P"]=[("1",0,0,1.0,1.9),("2",5.08,0,1.0,1.9)]
PKG["SIP16"]=[(str(k+1),0,-2.54*k,0.8,1.6) for k in range(16)]
PKG["HDR40"]=[(str(k+1),2.54*(k%2),-2.54*(k//2),0.9,1.7) for k in range(40)]

# ---------------- new devices (L/R pin lists + pin->pad maps) -------------------
def D(name,L,R,pm,pkg): DEV[name]=dict(L=L,R=R,pm=pm,pkg=pkg)
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
  {"A1":"1","B1":"2","C1":"3","A2":"4","B2":"5","Y1":"6","GND":"7","Y2":"8","C2":"9",
   "D2":"10","E2":"11","D1":"12","E1":"13","VCC":"14"},"DIP14")
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

# ---------------- helpers -------------------------------------------------------
CARDS={}   # name -> (title, parts, nets) for downstream renderers
def card(name,title,parts_ic,parts_small,nets,used_bus):
    """Build sch+brd for one card. parts_*: ref:(dev,val). nets: dict."""
    # J1 bus pins
    for pin in ALLPINS:
        net=busnet(pin)
        if net in ("VCC","GND") or net in used_bus:
            nets.setdefault(net,[]).append(("J1",pin))
    parts={"J1":("DIN96","DIN41612-96M")}
    parts.update(parts_ic); parts.update(parts_small)
    # schematic placement: J1 left, others in grid
    sch={}; order=[r for r in parts if r!="J1"]
    sch["J1"]=("DIN96",parts["J1"][1],0,38.10)
    for i,ref in enumerate(order):
        dev,val=parts[ref]
        sch[ref]=(dev,val,140+ (i%4)*101.6, 38.10-(i//4)*139.7)
    # board placement: J1 right edge, ICs grid, small parts top strip
    brd={}; brd["J1"]=("DIN96",parts["J1"][1],147.32,88.90)
    ics=[r for r in parts_ic]
    for i,ref in enumerate(ics):
        dev,val=parts_ic[ref]
        brd[ref]=(dev,val, 7.62+13.97*(i%10), 88.90-25.40*(i//10))
    sm=[r for r in parts_small]
    for i,ref in enumerate(sm):
        dev,val=parts_small[ref]
        brd[ref]=(dev,val, 5.08+10.16*(i%14), 96.52-7.62*(i//14)*0 - (0 if i<14 else 0) - (5.08 if i>=14 else 0))
    allp=dict(parts_ic); allp.update(parts_small)
    CARDS[name]=(title,allp,nets)
    write_sch("p8x-%s.sch"%name,title,sch,nets)
    validate("p8x-%s.sch"%name,sch,nets)
    write_brd("p8x-%s.brd"%name,title,brd,nets,{},{"GND":[(2,)],"VCC":[(15,)]},160,100)
    validate("p8x-%s.brd"%name,brd,nets)

def N(nets,n,*p): nets.setdefault(n,[]).extend(p)

#==================== CONTROL / MICROCODE CARD ==================================
n={}
ic={"U1":("74161","CLK DIV"),"U2":("HEX14","74HCT14"),"U3":("7474","74HCT74"),
 "U4":("GATES14","74HCT00"),"U5":("GATES14","74HCT08"),"U6":("GATES14","74HCT32"),
 "U7":("74377V2","IR 74HCT377"),"U8":("74138","DLD DEC"),"U9":("74151","COND MUX"),
 "U10":("28C64","UCODE ROM0"),"U11":("28C64","UCODE ROM1"),
 "U12":("28C64","UCODE ROM2"),"U13":("28C64","UCODE ROM3"),
 "U14":("74374","PIPE0"),"U15":("74374","PIPE1"),"U16":("74374","PIPE2"),
 "U17":("74374","PIPE3"),"U18":("74161","STEP CNT")}
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
  ("U18","C"),("U18","D"),("U9","D0"),("U9","D6"),("U9","D7"),("U9","!G"),
  ("U8","!G2B"),("X1","GND"),("SWR","1"),("SWS","1"),("SWT","1"),("C1","2"),
  ("LED3","K"),("U5","3A"),("U5","3B"),("U5","4A"),("U5","4B"),
  ("U6","2A"),("U6","2B"),("U6","3A"),("U6","3B"),("U6","4A"),("U6","4B"),
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
PIPE={14:["DOE0","DOE1","DOE2","DOE3","DLD0","DLD1","DLD2","DLD3"],
 15:["PSEL0","PSEL1","PINC","PDEC","ALUS0","ALUS1","ALUS2","ALUS3"],
 16:["ALUM","CIN","SH0","SH1","LDF","FCOND0","FCOND1","FCOND2"],
 17:["URST","HALT"]}
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
card("control-card","P8X CONTROL/MICROCODE CARD REV A",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"DOE%d"%i for i in range(4)}|{"DLD%d"%i for i in range(4)}|
 {"PSEL0","PSEL1","PINC","PDEC","ALUS0","ALUS1","ALUS2","ALUS3","ALUM","CIN","SH0","SH1",
  "LDF","CLK","CLKB","-RES","FC","FZ","FN","FV"})

#==================== REGISTER BANK CARD =========================================
n={}
ic={}
for p in range(4):
    for s,nm in enumerate(("L0","L1","H0","H1")):
        ic["U%d"%(1+p*4+s)]=("74169","P%d %s"%(p,nm))
for k in range(8): ic["U%d"%(17+k)]=("74244","PTR SEL %d"%k)
ic.update({"U25":("74244","ADDR LO"),"U26":("74244","ADDR HI"),
 "U27":("74257","RDBK LO"),"U28":("74257","RDBK HI"),"U29":("74244","RDBK OUT"),
 "U30":("74138","DLD DEC"),"U31":("74138","DOE DEC"),"U32":("74139","LOAD DEC"),
 "U33":("74139","SEL+CNT DEC"),"U34":("7402","74HCT02"),"U35":("HEX14","74HCT14"),
 "U36":("74244","ZERO P0"),"U37":("GATES14","74HCT08"),"U38":("GATES14","74HCT08")})
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
            N(n,"PB%d"%(s*4+bit),)  # placeholder ensures net exists
        for bit,q in enumerate(("QA","QB","QC","QD")):
            N(n,"PQ%d_%d"%(p,s*4+bit),(u,q))
# selection buffers: pointer Q -> PB via 2x244 per pointer
for p in range(4):
    for half in range(2):  # half0: PB0-7 (L), half1: PB8-15 (H)
        u="U%d"%(17+p*2+half)
        N(n,"-SEL%d"%p,(u,"!G1"),(u,"!G2"))
        for b in range(8):
            N(n,"PQ%d_%d"%(p,half*8+b),(u,"A%d"%(b+1)))
            N(n,"PB%d"%(half*8+b),(u,"Y%d"%(b+1)))
# address drivers
for half,u in ((0,"U25"),(1,"U26")):
    N(n,"GND",(u,"!G1"),(u,"!G2"))
    for b in range(8):
        N(n,"PB%d"%(half*8+b),(u,"A%d"%(b+1)))
        N(n,"A%d"%(half*8+b),(u,"Y%d"%(b+1)))
# readback
for k,(u,lo) in enumerate((("U27",0),("U28",4))):
    N(n,"POEHP",(u,"S")); N(n,"GND",(u,"!OE"))
    for b in range(4):
        N(n,"PB%d"%(lo+b),(u,"A%d"%(b+1)))
        N(n,"PB%d"%(8+lo+b),(u,"B%d"%(b+1)))
        N(n,"RB%d"%(lo+b),(u,"Y%d"%(b+1)))
N(n,"-POE",("U29","!G1"),("U29","!G2"))
for b in range(8):
    N(n,"RB%d"%b,("U29","A%d"%(b+1))); N(n,"D%d"%b,("U29","Y%d"%(b+1)))
# decodes
for u,f in (("U30","DLD"),("U31","DOE")):
    for i,pn in enumerate(("A","B","C")): N(n,"%s%d"%(f,i),(u,pn))
    N(n,"%s3"%f,(u,"G1")); N(n,"GND",(u,"!G2A"),(u,"!G2B"))
N(n,"-LDL",("U30","Y0"),("U32","!G1")); N(n,"-LDH",("U30","Y1"),("U32","!G2"))
N(n,"-POEL",("U31","Y0"),("U37","3A")); N(n,"-POEH",("U31","Y1"),("U37","3B"),("U35","2A"))
N(n,"POEHP",("U35","2Y"))
N(n,"-POE",("U37","3Y"),("U38","1A"),("U38","1B"))
for i,pn in enumerate(("A1","B1")): N(n,"PSEL%d"%i,("U32",pn),("U33",pn))
for i,pn in enumerate(("A2","B2")): N(n,"PSEL%d"%i,("U32",pn),("U33",pn))
for p in range(4):
    N(n,"-LDL%d"%p,("U32","1Y%d"%p)); N(n,"-LDH%d"%p,("U32","2Y%d"%p))
    N(n,"-SEL%d"%p,("U33","1Y%d"%p)); N(n,"-CNT%d"%p,("U33","2Y%d"%p))
N(n,"GND",("U33","!G1"))
N(n,"CNTN",("U34","1Y"),("U33","!G2"))
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
n={k:v for k,v in n.items() if v}  # drop placeholder-only empties
card("regbank-card","P8X REGISTER BANK CARD REV A (P0=PC P3=SP)",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"A%d"%i for i in range(16)}|
 {"DLD%d"%i for i in range(4)}|{"DOE%d"%i for i in range(4)}|
 {"PSEL0","PSEL1","PINC","PDEC","CLK","-RES"})

#==================== ALU CARD ====================================================
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
 "U24":("GATES14","74HCT32"),"U25":("GATES14","74HCT00")}
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
for b in range(4):
    N(n,"AQ%d"%b,("U9","A%d"%b)); N(n,"BQ%d"%b,("U9","B%d"%b))
    N(n,"AQ%d"%(4+b),("U10","A%d"%b)); N(n,"BQ%d"%(4+b),("U10","B%d"%b))
for u in ("U9","U10"):
    for s in range(4): N(n,"ALUS%d"%s,(u,"S%d"%s))
    N(n,"ALUM",(u,"M"))
N(n,"CIN",("U9","CN"),("U11","CN"),("U12","B1"),("U15","B4"))
N(n,"CP0",("U9","!P"),("U11","!P0")); N(n,"CG0",("U9","!G"),("U11","!G0"))
N(n,"CP1",("U10","!P"),("U11","!P1")); N(n,"CG1",("U10","!G"),("U11","!G1"))
N(n,"CNX",("U11","CNX"),("U10","CN"))
N(n,"VCC",("U11","!P2"),("U11","!G2"),("U11","!P3"),("U11","!G3"))
N(n,"CFLG",("U10","CN4"),("U22","A1"))
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
N(n,"ZFLG",("U19","1Y"),("U22","A2"))
N(n,"R7",("U22","A3"))
N(n,"GND",("U22","A4"))            # V flag: unimplemented rev A (backlog)
for b in range(4): N(n,"D%d"%b,("U22","B%d"%(b+1)))
N(n,"-FREST",("U21","Y5"),("U25","1A"),("U25","1B"))
N(n,"FRESP",("U25","1Y"),("U22","S"),("U24","1B"))
N(n,"GND",("U22","!G"))
N(n,"LDF",("U24","1A"),("U25","3A"),("U25","3B"))
N(n,"FEN",("U24","1Y"),("U19","2B")); N(n,"CLK",("U19","2A"))
N(n,"CLKF",("U19","2Y"),("U17","CLK"))
N(n,"-RES",("U17","!CLR"))
for i in range(4): N(n,"FM%d"%i,("U22","Y%d"%(i+1)),("U17","D%d"%(i+1)))
for i,f in enumerate(("FQC","FQZ","FQN","FQV")):
    N(n,f,("U17","Q%d"%(i+1)),("U23","A%d"%(i+1)),("U23","A%d"%(i+5)))
for i in range(4): N(n,"D%d"%i,("U23","Y%d"%(i+1)))
for i,f in enumerate(("FC","FZ","FN","FV")): N(n,f,("U23","Y%d"%(i+5)))
N(n,"-DOEFLG",("U20","Y6"),("U23","!G1"))
N(n,"GND",("U23","!G2"))
for u,fld in (("U20","DOE"),("U21","DLD")):
    for i,pn in enumerate(("A","B","C")): N(n,"%s%d"%(fld,i),(u,pn))
    N(n,"%s3"%fld,(u,"!G2A")); N(n,"VCC",(u,"G1")); N(n,"GND",(u,"!G2B"))
N(n,"ALUK",("U19","3Y"),("LED4","K"))
N(n,"LDFK",("U25","3Y"),("LED5","K"))
N(n,"GND",("U19","4A"),("U19","4B"),("U24","2A"),("U24","2B"),("U24","3A"),
  ("U24","3B"),("U24","4A"),("U24","4B"),("U25","2A"),("U25","2B"),
  ("U25","4A"),("U25","4B"),("LED3","K"))
N(n,"VCC",("RP1","1"),("R4","1"),("R5","1"))
N(n,"LEDP",("RP1","2"),("LED3","A"))
N(n,"LEDAL",("R4","2"),("LED4","A")); N(n,"LEDLF",("R5","2"),("LED5","A"))
card("alu-card","P8X ALU CARD REV A (V FLAG UNIMPLEMENTED - SEE BACKLOG)",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"DOE%d"%i for i in range(4)}|{"DLD%d"%i for i in range(4)}|
 {"ALUS0","ALUS1","ALUS2","ALUS3","ALUM","CIN","SH0","SH1","LDF","CLK","-RES",
  "FC","FZ","FN","FV"})

#==================== I/O CARD ====================================================
n={}
ic={"U1":("7430","IO PAGE"),"U2":("74138","PORT DEC"),"U3":("74138","DOE DEC"),
 "U4":("74138","DLD DEC"),"U5":("GATES14","74HCT32"),"U6":("GATES14","74HCT08"),
 "U7":("74161","BAUD DIV"),"U8":("MAX232","RS232"),"U9":("74244","SW IN"),
 "U10":("74374","LED PORT"),"U11":("74244","MON A-LO"),"U12":("74244","MON A-HI"),
 "U13":("74244","MON D"),"U14":("6850","ACIA"),"U15":("GATES14","74HCT00")}
sm={"X2":("OSC","2.4576MHZ"),"SW1":("DIP8SW","INPUT"),"RNP":("SIP9","8X10K"),
 "RL1":("RNISO8","8X330R"),"LA1":("LEDARR8","PORT LEDS"),
 "RM1":("RNISO8","8X330R"),"LM1":("LEDARR8","A0-7"),
 "RM2":("RNISO8","8X330R"),"LM2":("LEDARR8","A8-15"),
 "RM3":("RNISO8","8X330R"),"LM3":("LEDARR8","D0-7"),
 "J2":("HDR3","SERIAL"),"C2":("CAP","1U"),"C3":("CAP","1U"),"C4":("CAP","1U"),
 "C5":("CAP","1U"),"RP1":("RES","1K"),"LED3":("LED","PWR-GRN"),
 "R4":("RES","1K"),"LED4":("LED","IOSEL-YEL")}
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
N(n,"SELP",("U6","3Y"),("R4","2"))      # NOTE: source-drive deviation, LED to GND
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
card("io-card","P8X I/O CARD REV A - ACIA + SWITCHES + LEDS + BUS MONITOR",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"A%d"%i for i in range(16)}|
 {"DOE%d"%i for i in range(4)}|{"DLD%d"%i for i in range(4)}|{"CLKB","-RES"})

#==================== CF-IDE CARD =================================================
n={}
ic={"U1":("74245","DATA BUF"),"U2":("7430","IO PAGE"),"U3":("74138","DOE DEC"),
 "U4":("74138","DLD DEC"),"U5":("HEX14","74HCT14"),"U6":("7410","74HCT10"),
 "U7":("7410","74HCT10"),"U8":("GATES14","74HCT08")}
sm={"J2":("IDE40","CF/IDE 40P"),"RN1":("SIP9","8X10K"),
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
card("cf-card","P8X CF-IDE CARD REV A - 8-BIT TRUE IDE AT 0xFF10",ic,sm,n,
 {"D%d"%i for i in range(8)}|{"A0","A1","A2","A3","A4"}|{"A%d"%i for i in range(8,16)}|
 {"DOE%d"%i for i in range(4)}|{"DLD%d"%i for i in range(4)}|{"CLKB","-RES"})
print("ALL FIVE CARDS GENERATED")
