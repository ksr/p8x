#!/usr/bin/env python3
"""Traditional-style backplane schematic: one representative connector
(all 10 slots are wired pin-for-pin in parallel) + support circuitry
drawn with real wires."""
import os as _os, sys as _sys; _DOCS=_os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),"hardware","backplane")
_sys.path.insert(0,_os.path.dirname(_os.path.abspath(__file__)))
import gen_eagle as GE   # EMIT is False on import, so this writes nothing — we only borrow PASSIVE_ART
from reportlab.pdfgen import canvas as pdfc
from reportlab.lib.colors import Color
MM=2.83465; G=2.54; HALFW=12.7; PINX=17.78
BLK=Color(0,0,0); GRN=Color(0,0.42,0); RED=Color(0.72,0.08,0.08); BLU=Color(0,0,0.65)
c=pdfc.Canvas(_os.path.join(_DOCS,"p8x-backplane-schematic.pdf"),pagesize=(842,1190))
minx,maxx,miny,maxy=-25,235,-284,42
s=min((842-40)/((maxx-minx)*MM),(1190-90)/((maxy-miny)*MM))*MM
def X(x): return 20+(x-minx)*s
def Y(y): return 40+(y-miny)*s
def line(x1,y1,x2,y2,w=0.8,col=GRN):
    c.setStrokeColor(col); c.setLineWidth(w); c.line(X(x1),Y(y1),X(x2),Y(y2))
def txt(x,y,t,size=2.0,col=BLK,bold=False,right=False):
    c.setFillColor(col); c.setFont("Helvetica-Bold" if bold else "Helvetica",size*s)
    (c.drawRightString if right else c.drawString)(X(x),Y(y),t)
def vcc(x,y,d=1,label="+5V"):
    line(x,y,x+d*1.8,y,0.8,RED); line(x+d*1.8,y,x+d*1.8,y+1.6,0.8,RED)
    line(x+d*1.8-1.1,y+1.6,x+d*1.8+1.1,y+1.6,1.0,RED)
    txt(x+d*3.4,y-0.6,label,1.6,RED,right=(d<0))
def gnd(x,y,d=1):
    line(x,y,x+d*1.8,y,0.8,BLU); line(x+d*1.8,y,x+d*1.8,y-1.0,0.8,BLU)
    for i,w in enumerate((1.3,0.8,0.3)):
        line(x+d*1.8-w,y-1.0-i*0.6,x+d*1.8+w,y-1.0-i*0.6,0.9,BLU)
def box(ref,val,x,y,nrows,wide=HALFW):
    ybot=y-G*(nrows-1)-G
    c.setStrokeColor(BLK); c.setLineWidth(1.1)
    c.rect(X(x-wide),Y(ybot),(2*wide)*s,(y+G-ybot)*s,stroke=1,fill=0)
    txt(x-wide,y+G+1.3,ref,2.6,RED,bold=True); txt(x-wide,ybot-3.6,val,2.0,BLU)
    return ybot
# title
c.setFont("Helvetica-Bold",18); c.setFillColor(BLK)
c.drawString(20,1190-26,"P8X 10-SLOT BACKPLANE REV C - SCHEMATIC (traditional wiring)")
c.setFont("Helvetica",9.5)
c.drawString(20,1190-42,"J1-J10: ALL TEN SLOTS ARE WIRED PIN-FOR-PIN IN PARALLEL - drawn once below. Decoupling C1-C10: one per slot.")
c.drawString(20,1190-55,"Rail glyphs = +5V / GND planes (inner layers). RT/CT clock terminators ship DNP. FC/FZ/FN/FV = ALU flags (ex SPARE0-3). rev C3: C27-30=PSEL2/LDZN/SHCIN/SETC, B27=CLRC; B28=BSEL, B29=IRQ, SPARE11 on B30.")
# representative connector rows
ROWS=( [("D%d"%i,"D") for i in range(8)]+[None]
      +[("A%d"%i,"S") for i in range(16)]+[None]
      +[("DOE%d"%i,"S") for i in range(4)]+[("DLD%d"%i,"S") for i in range(4)]+[None]
      +[("PSEL0","S"),("PSEL1","S"),("PINC","S"),("PDEC","S"),("LDF","S"),
        ("ALUS0","S"),("ALUS1","S"),("ALUS2","S"),("ALUS3","S"),("ALUM","S"),
        ("CIN","S"),("SH0","S"),("SH1","S"),("-RES","S")]+[None]
      +[("CLK","CLK"),("CLKB","CLKB")]+[None]
      +[("FC","S"),("FZ","S"),("FN","S"),("FV","S")]+[None]
      +[("SPARE%d"%i,"S") for i in range(4,12)]+[None]
      +[("+5V (A1,B1,C1,A2,B2,C2)","V"),("GND (B3-B26)","G"),("GND (31/32 ALL ROWS)","G")])
JX=0; JY=0
box("J1..J10","DIN41612 96P x10 SLOTS",JX,JY,len(ROWS),wide=15)
rowy={}
for i,row in enumerate(ROWS):
    if row is None: continue
    name,kind=row; py=JY-G*i; rowy[name]=py
    line(JX+15,py,JX+15+5.08,py,0.9,BLK)
    txt(JX+15-0.9,py-0.7,name,1.9,right=True)
PX=JX+15+5.08
# D0-7 -> RN1 pull-up array (drawn vertically, pin rows aligned)
RNX=70
ytop=rowy["D0"]+G
ybot=rowy["D7"]-G
c.setStrokeColor(BLK); c.setLineWidth(1.1)
c.rect(X(RNX-7),Y(ybot),(14)*s,(ytop-ybot)*s,stroke=1,fill=0)
txt(RNX-7,ytop+1.3,"RN1",2.6,RED,bold=True); txt(RNX-7,ybot-3.6,"8 x 10K (COM TO +5V)",2.0,BLU)
for i in range(8):
    py=rowy["D%d"%i]
    line(RNX-7-5.08,py,RNX-7,py,0.9,BLK)
    line(PX,py,RNX-7-5.08,py)        # wire from connector pin to RN pad
    txt(RNX-6,py-0.7,"R%d"%(i+1),1.7)
vcc(RNX,ytop+0.0,d=1,label="+5V (COM)")
line(RNX,ytop,RNX+1.0,ytop,0)  # anchor
# simple labeled stubs for the S rows (bused to all slots; no on-board circuitry)
for name,kind in [r for r in ROWS if r]:
    if kind=="S":
        py=rowy[name]; line(PX,py,PX+6,py); txt(PX+6.8,py-0.7,"TO ALL SLOTS",1.3,GRN)
    elif kind=="V":
        vcc(PX,rowy[name],d=1)
    elif kind=="G":
        gnd(PX,rowy[name],d=1)
# clock terminators: CLK -> RT1 -> CT1 -> GND   (DNP)
def twopart(ref,val,x,y,p1,p2,w=10):
    c.setStrokeColor(BLK); c.setLineWidth(1.0)
    c.rect(X(x),Y(y-2.2),w*s,4.4*s,stroke=1,fill=0)
    txt(x,y+3.0,ref,2.2,RED,bold=True); txt(x,y-5.6,val,1.8,BLU)
    line(x-5.08,y,x,y,0.9,BLK); line(x+w,y,x+w+5.08,y,0.9,BLK)
    return (x-5.08,y),(x+w+5.08,y)
def disc(kind,ref,val,x,y,w=10):
    # Same footprint/pin geometry as twopart() so callers and wiring math are
    # unchanged, but draws a US/ANSI symbol (G.PASSIVE_ART) instead of a box.
    # PASSIVE_ART spans +/-12.7 in x (the pin ends); scale x so those ends land
    # exactly on this part's pin stubs. y is true size (no vertical scaling).
    a=x-5.08; b=x+w+5.08; cx=(a+b)/2.0; xs=((b-a)/2.0)/12.7
    c.setStrokeColor(BLK); c.setLineWidth(0.9)
    for (x1,y1,x2,y2) in GE.PASSIVE_ART[kind]:
        line(cx+x1*xs,y+y1,cx+x2*xs,y+y2,0.9,BLK)
    txt(x,y+4.4,ref,2.2,RED,bold=True); txt(x,y-5.6,val,1.8,BLU)
    return (a,y),(b,y)
for sig,rref,cref,drop in (("CLK","RT1","CT1",0),("CLKB","RT2","CT2",13)):
    py0=rowy[sig]; py=py0-drop
    if drop:
        line(PX,py0,PX+4,py0); line(PX+4,py0,PX+4,py); line(PX+4,py,55-5.08,py)
    (a,_),(b,_)=disc("RES",rref,"100R (DNP)",55,py)
    if not drop: line(PX,py,a,py)
    (c1,_),(c2,_)=disc("CAP",cref,"150P (DNP)",92,py)
    line(b,py,c1,py)
    gnd(c2,py,d=1)
    txt(122,py-0.7,"AC TERM - FIT ONLY IF %s RINGS AT FAR SLOT"%sig,1.5,BLU)
# power entry + bulk + per-slot decoupling + LED, drawn in a power section
PYY=-225
txt(0,PYY+10,"POWER SECTION",2.6,BLK,bold=True)
(a,_),(b,_)=twopart("J11","SCREW TERM 4P: 1,2=+5V IN / 3,4=GND IN",10,PYY,"","",w=46)
vcc(b,PYY,d=1,label="+5V"); gnd(a,PYY,d=-1)
for i,(ref,val,kind) in enumerate((("CB1","470uF","CAPP"),("CB2","470uF","CAPP"),("C1-C10","100nF x10, ONE PER SLOT","CAP"))):
    py=PYY-14-13*i
    (a,_),(b,_)=disc(kind,ref,val,30,py,w=16)
    vcc(a,py,d=-1); gnd(b,py,d=1)
py=PYY-53
(a,_),(b,_)=disc("RES","RL1","1K",30,py,w=14)
vcc(a,py,d=-1)
(l1,_),(l2,_)=disc("LED","LED1","PWR GRN",70,py,w=10)
line(b,py,l1,py); gnd(l2,py,d=1)
c.save()
print("backplane traditional PDF written")
