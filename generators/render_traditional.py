#!/usr/bin/env python3
"""Traditional-style schematic PDF for the P8X memory card: drawn wires, bus
spines with angled entries, junction dots, power rail glyphs, NC marks.
The netlist and device library are imported from gen_eagle.py (the single
source of truth); only the hand-tuned drawing layout lives here.
Run from hardware/eagle/ — importing gen_eagle regenerates the board files
into the current directory (same as render_traditional_auto.py)."""
import sys, os as _os
_HERE=_os.path.dirname(_os.path.abspath(__file__))
sys.path.insert(0,_HERE)
import gen_eagle as GE          # aliased GE: local G is the 2.54 mm grid constant
_DOCS=_os.path.join(_os.path.dirname(_HERE),"docs","memory-card")
from reportlab.pdfgen import canvas as pdfc
from reportlab.lib.colors import Color
MM=2.83465; G=2.54; PIN=5.08; HALFW=12.7; PINX=17.78
BLK=Color(0,0,0); GRN=Color(0,0.42,0); RED=Color(0.72,0.08,0.08); BLU=Color(0,0,0.65)

# ---- canonical netlist + device library, imported from gen_eagle.py ---------
# gen_eagle.DEV carries pin maps and packages too; this drawing only reads the
# L/R pin-order lists, which match exactly.
DEV=GE.DEV
# GE.mcn is the memory-card netlist. Strip the J1 power/ground connector pins:
# this drawing renders +5V/GND via the consolidated J1 power rows and rail
# glyphs rather than per-pin connector entries, so those pins must not be routed.
mcn={net:[(r,p) for (r,p) in pins if not (r=="J1" and net in("VCC","GND"))]
     for net,pins in GE.mcn.items()}
PIN2NET={}
for n,ps in mcn.items():
    for rp in ps: PIN2NET[rp]=n

PARTS={  # ref:(dev,value,x,y) -- logical placement for the drawing
 "U3":("74245","74HCT245",185,95),
 "U1":("MEM28K8","28C256-15",185,20),
 "U2":("MEM28K8","62256-70",185,-55),
 "U4":("7430","74HCT30",185,-130),
 "U5":("74138","74HCT138 DOE",110,-125),
 "U6":("74138","74HCT138 DLD",110,-180),
 "U7":("GATES14","74HCT00",285,-28),
 "U8":("GATES14","74HCT32",285,-100),
 "U9":("GATES14","74HCT08",285,-140),
 "RP1":("RES","1K",360,55),"LED3":("LED","PWR GRN",398,55),
 "RS1":("RES","1K",360,33),"LED2":("LED","ROM YEL",398,33),
 "RS2":("RES","1K",360,11),"LED4":("LED","RAM YEL",398,11),
 "RS3":("RES","1K",360,-11),"LED5":("LED","RD GRN",398,-11),
 "RS4":("RES","1K",360,-33),"LED6":("LED","WR RED",398,-33),
}
# J1 drawn with connected pins on the right, grouped; power consolidated
J1ROWS=( [("D%d"%i,"A%d"%(3+i)) for i in range(8)]+[None]
        +[("A%d"%i,"C%d"%(3+i)) for i in range(16)]+[None]
        +[("DOE%d"%i,"A%d"%(12+i)) for i in range(4)]
        +[("DLD%d"%i,"A%d"%(16+i)) for i in range(4)]+[None]
        +[("CLK","A24")]+[None]
        +[("+5V (A1,B1,C1,A2,B2,C2)","VCCPWR"),("GND (B3-30 + 31/32 ALL ROWS)","GNDPWR")])
BUSES={ # name: (spine_x, ytop, ybot, member-prefix, index-range)
 "D[0..7]":(140,99,-20,"D",range(8)),
 "MD[0..7]":(212,95,-100,"MD",range(8)),
 "A[0..15]":(162,27,-160,"A",range(16)),
 "DOE[0..3]":(68,-58,-138,"DOE",range(4)),
 "DLD[0..3]":(76,-66,-195,"DLD",range(4)),
}
def busof(net):
    for bn,(sx,yt,yb,pre,rng) in BUSES.items():
        if net.startswith(pre) and net[len(pre):].isdigit() and int(net[len(pre):]) in rng:
            if pre=="A" and net.startswith("ALU"): continue
            if pre=="D" and (net.startswith("DOE") or net.startswith("DLD")): continue
            return bn
    return None
TRACKS=["-RD","-MEMW","CLK","-WE","-BOE","-IOPG","-RAMCE","ROMK","RAMK","RDK","WRK"]
TRACKY0=-218

def pinxy(ref,pin):
    if ref=="J1":
        for i,row in enumerate(J1ROWS):
            if row and row[1]==pin: return (PINX, -G*i, "R")
        # map bus/named pins: J1 pins keyed by pad name
        raise KeyError(pin)
    dev,val,x,y=PARTS[ref]; d=DEV[dev]
    if pin in d["L"]: return (x-PINX, y-G*d["L"].index(pin),"L")
    return (x+PINX, y-G*d["R"].index(pin),"R")

def disp(p): return p.replace("!","-")

c=pdfc.Canvas(_os.path.join(_DOCS,"p8x-memory-card-schematic.pdf"),pagesize=(1683,1190))
minx,maxx,miny,maxy=-25,440,-252,108
s=min((1683-40)/((maxx-minx)*MM),(1190-70)/((maxy-miny)*MM))*MM
def X(x): return 20+(x-minx)*s
def Y(y): return 30+(y-miny)*s
def line(x1,y1,x2,y2,w=0.7,col=GRN):
    c.setStrokeColor(col); c.setLineWidth(w); c.line(X(x1),Y(y1),X(x2),Y(y2))
def dot(x,y,col=GRN):
    c.setFillColor(col); c.circle(X(x),Y(y),1.6,stroke=0,fill=1)
def txt(x,y,t,size=1.9,col=BLK,bold=False,right=False):
    c.setFillColor(col); c.setFont("Helvetica-Bold" if bold else "Helvetica",size*s)
    (c.drawRightString if right else c.drawString)(X(x),Y(y),t)
def vcc_glyph(x,y,side,label="+5V"):
    d=1 if side=="R" else -1
    line(x,y,x+d*1.8,y,0.7,RED); line(x+d*1.8,y,x+d*1.8,y+1.6,0.7,RED)
    line(x+d*1.8-1.1,y+1.6,x+d*1.8+1.1,y+1.6,1.0,RED)
    txt(x+d*3.2,y-0.5,label,1.4,RED,right=(side=="L"))
def gnd_glyph(x,y,side,label=""):
    d=1 if side=="R" else -1
    line(x,y,x+d*1.8,y,0.7,BLU); line(x+d*1.8,y,x+d*1.8,y-1.0,0.7,BLU)
    for i,w in enumerate((1.3,0.8,0.3)):
        line(x+d*1.8-w,y-1.0-i*0.6,x+d*1.8+w,y-1.0-i*0.6,0.9,BLU)
    if label: txt(x+d*3.4,y-0.5,label,1.4,BLU,right=(side=="L"))
def nc_mark(x,y,side):
    d=1 if side=="R" else -1; e=x+d*1.6
    line(e-1.2,y-1.2,e+1.2,y+1.2,0.8,BLK); line(e-1.2,y+1.2,e+1.2,y-1.2,0.8,BLK)

# title
c.setFont("Helvetica-Bold",18); c.setFillColor(BLK)
c.drawString(20,1190-26,"P8X MEMORY CARD REV C - SCHEMATIC (traditional wiring)")
c.setFont("Helvetica",9)
c.drawString(20,1190-40,"Buses drawn as spines with angled entries; junction dot = connection, plain crossing = no connection; rail glyphs = +5V/GND planes.")

# part boxes & pins
def draw_part(ref,dev,val,x,y,Lrows,Rrows):
    n=max(len(Lrows),len(Rrows)); ybot=y-G*(n-1)-G
    c.setStrokeColor(BLK); c.setLineWidth(1.0)
    c.rect(X(x-HALFW),Y(ybot),(2*HALFW)*s,(y+G-ybot)*s,stroke=1,fill=0)
    txt(x-HALFW,y+G+1.2,ref,2.4,RED,bold=True)
    txt(x-HALFW,ybot-3.4,val,1.9,BLU)
    for i,p in enumerate(Lrows):
        if p is None: continue
        py=y-G*i; line(x-PINX,py,x-HALFW,py,0.8,BLK)
        txt(x-HALFW+0.8,py-0.7,disp(p[0]),1.8)
    for i,p in enumerate(Rrows):
        if p is None: continue
        py=y-G*i; line(x+HALFW,py,x+PINX,py,0.8,BLK)
        txt(x+HALFW-0.8,py-0.7,disp(p[0]),1.8,right=True)
for ref,(dev,val,x,y) in PARTS.items():
    d=DEV[dev]
    Lr=[(p,) for p in d["L"]]; Rr=[(p,) for p in d["R"]]
    draw_part(ref,dev,val,x,y,Lr,Rr)
draw_part("J1","DIN96","BUS CONNECTOR J1 (DIN41612 96P)",0,0,[],J1ROWS)

# buses: spines
for bn,(sx,yt,yb,pre,rng) in BUSES.items():
    line(sx,yt,sx,yb,2.6,GRN); txt(sx-2,yt+1.5,bn,2.2,GRN,bold=True)

drops={}  # tracknet -> list of x
ext_of={n:2.54+1.27*(i%4) for i,n in enumerate(TRACKS)}
STUBPINS={("U1","!CE")}   # faces away from its bus; use a reference label
def route_pin(ref,pin,net):
    x,y,side=pinxy(ref,pin); d=1 if side=="R" else -1
    if (ref,pin) in STUBPINS:
        line(x,y,x+d*5.08,y)
        txt(x+d*5.6,y-0.7,net,1.9,GRN,bold=True,right=(side=="L"))
        return
    if net in ("VCC","VCCPWR"): vcc_glyph(x,y,side,"+5V"); return
    if net in ("GND","GNDPWR"): gnd_glyph(x,y,side); return
    b=busof(net)
    if b:
        sx=BUSES[b][0]
        endx = sx-1.27 if x<sx else sx+1.27
        line(x,y,endx,y)
        line(endx,y,sx,y-1.27,0.7,GRN)
        return
    if net in TRACKS:
        ext=ext_of[net]; ex=x+d*ext; ty=TRACKY0-G*TRACKS.index(net)
        line(x,y,ex,y); line(ex,y,ex,ty)
        drops.setdefault(net,[]).append(ex); return
    # direct nets handled separately
def direct(net):
    ps=mcn[net]
    (r1,p1),(r2,p2)=ps
    x1,y1,s1=pinxy(r1,p1); x2,y2,s2=pinxy(r2,p2)
    if abs(y1-y2)<0.01 and s1=="R" and s2=="L" and x1<x2:
        line(x1,y1,x2,y2); return True
    return False
DIRECT=["LEDP","LEDRO","LEDRA","LEDRD","LEDWR"]
handled=set()
for net,pins in mcn.items():
    if net in DIRECT and direct(net): handled.add(net); continue
for net,pins in mcn.items():
    if net in handled: continue
    for ref,pin in pins:
        nm=net
        route_pin(ref,pin,net if net not in("VCC","GND") else net)
# SELK as track? not in TRACKS list -> add manually as short track
TRACKS2=TRACKS
# J1 consolidated power glyph pins
route_pin("J1","VCCPWRPAD","VCCPWR") if False else None
# (J1 power rows route via their stored pad keys)
# draw track horizontals + dots + labels
for net,xs in drops.items():
    ty=TRACKY0-G*TRACKS.index(net)
    xs=sorted(xs); line(xs[0],ty,xs[-1],ty)
    txt(xs[0]-2,ty+0.7,net,1.9,GRN,bold=True,right=True)
    for x in xs[1:-1]: dot(x,ty)
# bus-entry labels where the pin name differs from the net name
for net,pins in mcn.items():
    if not busof(net): continue
    for ref,pin in pins:
        if disp(pin)!=net and ref!="J1":
            x,y,side=pinxy(ref,pin)
            txt(x+(1.2 if side=="R" else -1.2), y+0.6, net, 1.5, GRN, right=(side=="L"))
# J1 consolidated power rows
for i,row in enumerate(J1ROWS):
    if row and row[1]=="VCCPWR": vcc_glyph(PINX,-G*i,"R")
    if row and row[1]=="GNDPWR": gnd_glyph(PINX,-G*i,"R")
# NC pins (every pin not in netlist)
for ref,(dev,val,x,y) in PARTS.items():
    d=DEV[dev]
    for p in d["L"]+d["R"]:
        if (ref,p) not in PIN2NET:
            px,py,side=pinxy(ref,p); nc_mark(px,py,side)
c.save()
print("memory card traditional PDF written")
