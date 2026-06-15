#!/usr/bin/env python3
# Generates KiCad 7-format .kicad_pcb files (open in 7/8/9):
#  1) p8x-backplane.kicad_pcb   -- FULLY ROUTED 4-layer 10-slot backplane
#  2) p8x-memory-card.kicad_pcb -- placed + netted Eurocard, planes done, signals to route
# Stackup both: F.Cu (signals) / In1.Cu (GND plane) / In2.Cu (+5V plane) / B.Cu (signals)
import uuid as U
def uid(): return str(U.uuid4())
G=2.54

def busnet(pin):
    r,n=pin[0],int(pin[1:])
    if n in (1,2): return "VCC"
    if n in (31,32): return "GND"
    if r=="B": return "GND"
    if r=="A":
        if 3<=n<=10: return "D%d"%(n-3)
        if n==11: return "RES_N"
        if 12<=n<=15: return "DOE%d"%(n-12)
        if 16<=n<=19: return "DLD%d"%(n-16)
        return {20:"PSEL0",21:"PSEL1",22:"PINC",23:"PDEC",24:"CLK",25:"CLKB",26:"LDF"}.get(n,"SPARE%d"%(n-27))
    if r=="C":
        if 3<=n<=18: return "A%d"%(n-3)
        if 19<=n<=22: return "ALUS%d"%(n-19)
        return {23:"ALUM",24:"CIN",25:"SH0",26:"SH1"}.get(n,"SPARE%d"%(n-27+4))
ALLPINS=["%s%d"%(r,n) for r in "ABC" for n in range(1,33)]

class PCB:
    def __init__(self,title):
        self.nets={"":0}; self.netorder=[""]
        self.fps=[]; self.segs=[]; self.zones=[]; self.gr=[]; self.title=title
    def net(self,name):
        if name not in self.nets:
            self.nets[name]=len(self.netorder); self.netorder.append(name)
        return self.nets[name]
    def pad(self,name,x,y,size,drill,netname=None):
        n=f'(net {self.net(netname)} "{netname}")' if netname else ""
        return (f'    (pad "{name}" thru_hole circle (at {x:.2f} {y:.2f}) (size {size} {size}) '
                f'(drill {drill}) (layers "*.Cu" "*.Mask") {n} (tstamp {uid()}))')
    def footprint(self,ref,fpname,X,Y,pads,silk=None):
        f=[f'  (footprint "p8x:{fpname}" (layer "F.Cu") (tstamp {uid()}) (at {X:.2f} {Y:.2f})']
        f.append(f'    (attr through_hole)')
        f.append(f'    (fp_text reference "{ref}" (at 0 -3.5) (layer "F.SilkS") (tstamp {uid()}) (effects (font (size 1 1) (thickness 0.15))))')
        f.append(f'    (fp_text value "{fpname}" (at 0 -5.5) (layer "F.Fab") (tstamp {uid()}) (effects (font (size 1 1) (thickness 0.15))))')
        if silk:
            x1,y1,x2,y2=silk
            for (a,b,c,d) in [(x1,y1,x2,y1),(x2,y1,x2,y2),(x2,y2,x1,y2),(x1,y2,x1,y1)]:
                f.append(f'    (fp_line (start {a:.2f} {b:.2f}) (end {c:.2f} {d:.2f}) (stroke (width 0.12) (type solid)) (layer "F.SilkS") (tstamp {uid()}))')
        f+=pads
        f.append('  )')
        self.fps.append("\n".join(f))
    def seg(self,x1,y1,x2,y2,layer,netname,width=0.4):
        self.segs.append(f'  (segment (start {x1:.2f} {y1:.2f}) (end {x2:.2f} {y2:.2f}) (width {width}) (layer "{layer}") (net {self.net(netname)}) (tstamp {uid()}))')
    def zone(self,netname,layer,x1,y1,x2,y2):
        self.zones.append(
f'''  (zone (net {self.net(netname)}) (net_name "{netname}") (layer "{layer}") (tstamp {uid()}) (hatch edge 0.508)
    (connect_pads (clearance 0.3)) (min_thickness 0.25) (filled_areas_thickness no)
    (fill yes (thermal_gap 0.5) (thermal_bridge_width 0.5))
    (polygon (pts (xy {x1} {y1}) (xy {x2} {y1}) (xy {x2} {y2}) (xy {x1} {y2}))))''')
    def outline(self,x1,y1,x2,y2):
        for (a,b,c,d) in [(x1,y1,x2,y1),(x2,y1,x2,y2),(x2,y2,x1,y2),(x1,y2,x1,y1)]:
            self.gr.append(f'  (gr_line (start {a} {b}) (end {c} {d}) (stroke (width 0.1) (type solid)) (layer "Edge.Cuts") (tstamp {uid()}))')
        self.gr.append(f'  (gr_text "{self.title}" (at {x1+4} {y2-3}) (layer "F.SilkS") (tstamp {uid()}) (effects (font (size 2 2) (thickness 0.3)) (justify left)))')
    def write(self,fn):
        o=[f'(kicad_pcb (version 20221018) (generator p8xgen)']
        o.append('  (general (thickness 1.6))')
        o.append('  (paper "A3")')
        o.append('''  (layers
    (0 "F.Cu" signal) (1 "In1.Cu" power) (2 "In2.Cu" power) (31 "B.Cu" signal)
    (34 "B.Paste" user) (35 "F.Paste" user) (36 "B.SilkS" user) (37 "F.SilkS" user)
    (38 "B.Mask" user) (39 "F.Mask" user) (40 "Dwgs.User" user) (41 "Cmts.User" user)
    (44 "Edge.Cuts" user) (46 "B.CrtYd" user) (47 "F.CrtYd" user) (48 "B.Fab" user) (49 "F.Fab" user))''')
        o.append('  (setup (pad_to_mask_clearance 0))')
        for i,n in enumerate(self.netorder):
            o.append(f'  (net {i} "{n}")')
        o+=self.fps+self.segs+self.zones+self.gr
        o.append(')')
        txt="\n".join(o)+"\n"
        open(fn,"w").write(txt)
        bal=0;instr=False;prev=''
        for ch in txt:
            if ch=='"' and prev!='\\': instr=not instr
            if not instr:
                if ch=='(':bal+=1
                elif ch==')':bal-=1
                assert bal>=0
            prev=ch
        assert bal==0
        import re
        toks=re.findall(r'"(?:[^"\\]|\\.)*"|\(|\)|[^\s()"]+',txt)
        def parse(ts,i=0):
            assert ts[i]=='(';i+=1
            while ts[i]!=')':
                if ts[i]=='(':_,i=parse(ts,i)
                else:i+=1
            return None,i+1
        _,end=parse(toks);assert end==len(toks)
        print(f"{fn}: {len(txt)} bytes, {len(self.netorder)-1} nets, {len(self.fps)} footprints, {len(self.segs)} segments -- parse OK")

# ====================== BACKPLANE (fully routed) ==============================
bp=PCB("P8X 10-SLOT BACKPLANE REV C")
X0=15.24; PITCH=20.32; Y0=15.24
def slotx(i): return X0+PITCH*i
def piny(n): return Y0+G*(n-1)
for s in range(10):
    pads=[]
    for pin in ALLPINS:
        r,n=pin[0],int(pin[1:])
        dx={"A":0,"B":G,"C":2*G}[r]
        pads.append(bp.pad(pin,dx,G*(n-1),1.7,1.0,busnet(pin)))
    bp.footprint("J%d"%(s+1),"DIN96F",slotx(s),Y0,pads,silk=(-2.5,-2.5,2*G+2.5,G*31+2.5))
# bus traces: row A on F.Cu, row C on B.Cu
EXTD=208.28; EXTCLK=205.74
for n in range(3,31):
    netA=busnet("A%d"%n); y=piny(n)
    xend = EXTD if 3<=n<=10 else (EXTCLK if n in (24,25) else slotx(9))
    bp.seg(slotx(0),y,xend,y,"F.Cu",netA)
    netC=busnet("C%d"%n)
    bp.seg(slotx(0)+2*G,y,slotx(9)+2*G,y,"B.Cu",netC)
# pull-up SIP9 on D0-D7 (vertical, pads align with D-line y)
sip=[bp.pad("1",0,0,1.6,0.8,"VCC")]
for k in range(8):
    sip.append(bp.pad(str(k+2),0,G*(k+1),1.6,0.8,"D%d"%k))
bp.footprint("RN1","SIP9",EXTD,piny(3)-G,sip)
# clock RC terminators
bp.footprint("RT1","R_AXIAL",EXTCLK,piny(24),
    [bp.pad("1",0,0,1.6,0.8,"CLK"),bp.pad("2",10.16,0,1.6,0.8,"CLK_T")])
bp.footprint("CT1","C_DISC",218.44,piny(24),
    [bp.pad("1",0,0,1.8,0.9,"CLK_T"),bp.pad("2",0,5.08,1.8,0.9,"GND")])
bp.seg(EXTCLK+10.16,piny(24),218.44,piny(24),"F.Cu","CLK_T")
bp.footprint("RT2","R_AXIAL",EXTCLK,piny(25),
    [bp.pad("1",0,0,1.6,0.8,"CLKB"),bp.pad("2",10.16,0,1.6,0.8,"CLKB_T")])
bp.footprint("CT2","C_DISC",220.98,piny(25),
    [bp.pad("1",0,0,1.8,0.9,"CLKB_T"),bp.pad("2",0,5.08,1.8,0.9,"GND")])
bp.seg(EXTCLK+10.16,piny(25),220.98,piny(25),"F.Cu","CLKB_T")
# power entry + bulk + per-slot decoupling + LED
bp.footprint("J11","TB4",5.08,30.48,
    [bp.pad(str(k+1),0,5.08*k,3.0,1.3,"VCC" if k<2 else "GND") for k in range(4)])
for i,ref in enumerate(("CB1","CB2")):
    bp.footprint(ref,"CP_RADIAL",5.08,55.88+10.16*i,
        [bp.pad("1",0,0,1.8,0.9,"VCC"),bp.pad("2",0,5.08,1.8,0.9,"GND")])
for s in range(10):
    bp.footprint("C%d"%(s+1),"C_DISC",slotx(s)+G,5.08,
        [bp.pad("1",0,0,1.8,0.9,"VCC"),bp.pad("2",0,5.08,1.8,0.9,"GND")])
bp.footprint("RL1","R_AXIAL",15.24,99.06,
    [bp.pad("1",0,0,1.6,0.8,"VCC"),bp.pad("2",10.16,0,1.6,0.8,"LED_A")])
bp.footprint("LED1","LED5MM",30.48,99.06,
    [bp.pad("2",0,0,1.8,0.9,"LED_A"),bp.pad("1",2.54,0,1.8,0.9,"GND")])
bp.seg(25.40,99.06,30.48,99.06,"F.Cu","LED_A")
bp.zone("GND","In1.Cu",0,0,228.6,110)
bp.zone("VCC","In2.Cu",0,0,228.6,110)
bp.outline(0,0,228.6,110)
bp.write("p8x-backplane.kicad_pcb")

# ====================== MEMORY CARD (placed + planes) =========================
mc=PCB("P8X MEMORY CARD REV C")
# nets identical to the rev C schematic
MNETS={}
def mnet(n,*p): MNETS.setdefault(n,[]).extend(p)
for i in range(8):
    mnet("D%d"%i,("J1","A%d"%(3+i)),("U3","A%d"%i))
    mnet("MD%d"%i,("U3","B%d"%i),("U1","IO%d"%i),("U2","IO%d"%i))
for i in range(16):
    pins=[("J1","C%d"%(3+i))]
    if i<15: pins+=[("U1","A%d"%i),("U2","A%d"%i)]
    if 8<=i<=14: pins.append(("U4","ABCDEFG"[i-8]))
    if i==15: pins+=[("U4","H"),("U1","CE"),("U7","1A")]
    mnet("A%d"%i,*pins)
mnet("IOPG_N",("U4","Y"),("U7","1B"))
mnet("RAMCE_N",("U7","1Y"),("U2","CE"))
for i in range(4):
    mnet("DOE%d"%i,("J1","A%d"%(12+i)),("U5",["A","B","C","G2A"][i]))
    mnet("DLD%d"%i,("J1","A%d"%(16+i)),("U6",["A","B","C","G2A"][i]))
mnet("RD_N",("U5","Y7"),("U1","OE"),("U2","OE"),("U3","DIR"),("U9","1A"))
mnet("MEMW_N",("U6","Y7"),("U8","1A"),("U9","1B"))
mnet("CLK",("J1","A24"),("U8","1B"))
mnet("WE_N",("U8","1Y"),("U1","WE"),("U2","WE"))
mnet("BOE_N",("U9","1Y"),("U3","OE"))
mnet("VCC",*[("J1",p) for p in("A1","B1","C1","A2","B2","C2")],
  ("U1","VCC"),("U2","VCC"),("U3","VCC"),("U4","VCC"),("U5","VCC"),("U5","G1"),
  ("U6","VCC"),("U6","G1"),("U7","VCC"),("U8","VCC"),("U9","VCC"))
mnet("GND",*[("J1",p) for p in("A31","B31","C31","A32","B32","C32")],
  *[("J1","B%d"%i) for i in range(3,31)],
  ("U1","GND"),("U2","GND"),("U3","GND"),("U4","GND"),("U5","GND"),("U5","G2B"),
  ("U6","GND"),("U6","G2B"),("U7","GND"),("U8","GND"),("U9","GND"),
  *[(u,p) for u in ("U7","U8","U9") for p in ("2A","2B","3A","3B","4A","4B")])
PIN2NET={}
for n,pins in MNETS.items():
    for rp in pins: PIN2NET[rp]=n
# DIP pin->pad-position maps (pad names = pin NUMBERS; map via schematic pin names)
DIPMAP={
 "U1":("DIP28W",28,{"A14":1,"A12":2,"A7":3,"A6":4,"A5":5,"A4":6,"A3":7,"A2":8,"A1":9,"A0":10,
   "IO0":11,"IO1":12,"IO2":13,"GND":14,"IO3":15,"IO4":16,"IO5":17,"IO6":18,"IO7":19,
   "CE":20,"A10":21,"OE":22,"A11":23,"A9":24,"A8":25,"A13":26,"WE":27,"VCC":28}),
 "U3":("DIP20",20,{"DIR":1,"A0":2,"A1":3,"A2":4,"A3":5,"A4":6,"A5":7,"A6":8,"A7":9,"GND":10,
   "B7":11,"B6":12,"B5":13,"B4":14,"B3":15,"B2":16,"B1":17,"B0":18,"OE":19,"VCC":20}),
 "U4":("DIP14",14,{"A":1,"B":2,"C":3,"D":4,"E":5,"F":6,"GND":7,"Y":8,"G":11,"H":12,"VCC":14}),
 "U5":("DIP16",16,{"A":1,"B":2,"C":3,"G2A":4,"G2B":5,"G1":6,"Y7":7,"GND":8,"Y6":9,"Y5":10,
   "Y4":11,"Y3":12,"Y2":13,"Y1":14,"Y0":15,"VCC":16}),
 "U7":("DIP14",14,{"1A":1,"1B":2,"1Y":3,"2A":4,"2B":5,"2Y":6,"GND":7,"3Y":8,"3A":9,"3B":10,
   "4Y":11,"4A":12,"4B":13,"VCC":14}),
}
DIPMAP["U2"]=DIPMAP["U1"]; DIPMAP["U6"]=DIPMAP["U5"]
DIPMAP["U8"]=DIPMAP["U7"]; DIPMAP["U9"]=DIPMAP["U7"]
ROWSEP={"DIP14":7.62,"DIP16":7.62,"DIP20":7.62,"DIP28W":15.24}
PLACE={"U1":(17.78,15.24),"U2":(43.18,15.24),"U3":(68.58,15.24),"U4":(88.90,15.24),
       "U5":(109.22,15.24),"U6":(17.78,63.50),"U7":(43.18,63.50),"U8":(68.58,63.50),
       "U9":(88.90,63.50)}
for ref,(X,Y) in PLACE.items():
    fp,npins,pmap=DIPMAP[ref]; rs=ROWSEP[fp]; half=npins//2
    pads=[]
    inv={v:k for k,v in pmap.items()}
    for k in range(1,npins+1):
        if k<=half: x,y=0,G*(k-1)
        else: x,y=rs,G*(npins-k)
        pname=inv.get(k)
        netn=PIN2NET.get((ref,pname)) if pname else None
        pads.append(mc.pad(str(k),x,y,1.6,0.8,netn))
    mc.footprint(ref,fp,X,Y,pads,silk=(-1.3,-1.3,rs+1.3,G*(half-1)+1.3))
# DIN 41612 male right-angle at right board edge; rows A/B/C in 3 hole columns
jp=[]
for pin in ALLPINS:
    r,n=pin[0],int(pin[1:])
    dx={"A":2*G,"B":G,"C":0}[r]      # row A nearest edge for horizontal male
    jp.append(mc.pad(pin,dx,G*(n-1),1.7,1.0,PIN2NET.get(("J1",pin))))
mc.footprint("J1","DIN96M_RA",147.32,10.16,jp,silk=(-2.5,-2.5,2*G+2.5,G*31+2.5))
mc.zone("GND","In1.Cu",0,0,160,100)
mc.zone("VCC","In2.Cu",0,0,160,100)
mc.outline(0,0,160,100)
mc.write("p8x-memory-card.kicad_pcb")
