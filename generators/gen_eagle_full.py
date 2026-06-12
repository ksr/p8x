#!/usr/bin/env python3
# P8X Eagle generator for Fusion 360 import.
# Emits consistent schematic+board pairs (shared netlists, shared library):
#   p8x-backplane.sch / .brd      (rev C, 10 slots, FULLY ROUTED 4-layer)
#   p8x-memory-card.sch / .brd    (rev C, placed + planes, signals unrouted)
# Board stack: Top(1) signals / Route2(2) GND plane / Route15(15) +5V plane / Bottom(16) signals
G=2.54; PIN_X=17.78; STUB=5.08

def busnet(pin):
    r,n=pin[0],int(pin[1:])
    if n in (1,2): return "VCC"
    if n in (31,32): return "GND"
    if r=="B": return "GND"
    if r=="A":
        if 3<=n<=10: return "D%d"%(n-3)
        if n==11: return "-RES"
        if 12<=n<=15: return "DOE%d"%(n-12)
        if 16<=n<=19: return "DLD%d"%(n-16)
        return {20:"PSEL0",21:"PSEL1",22:"PINC",23:"PDEC",24:"CLK",25:"CLKB",26:"LDF"}.get(n,"SPARE%d"%(n-27))
    if 3<=int(pin[1:])<=18: return "A%d"%(n-3)
    if 19<=n<=22: return "ALUS%d"%(n-19)
    return {23:"ALUM",24:"CIN",25:"SH0",26:"SH1"}.get(n,"SPARE%d"%(n-27+4))
ALLPINS=["%s%d"%(r,n) for r in "ABC" for n in range(1,33)]

# ---------------- packages (shared by sch devices and brd elements) -----------
def dip_pads(n,rowsep):
    half=n//2; p=[]
    for k in range(1,n+1):
        if k<=half: x,y=0,-G*(k-1)
        else: x,y=rowsep,-G*(n-k)
        p.append((str(k),x,y,0.8128,1.6))
    return p
PKG={
 "DIP14": dip_pads(14,7.62), "DIP16": dip_pads(16,7.62),
 "DIP20": dip_pads(20,7.62), "DIP28W": dip_pads(28,15.24),
 "DIN96": [ (pin, {"A":5.08,"B":2.54,"C":0}[pin[0]], -G*(int(pin[1:])-1), 1.0, 1.7) for pin in ALLPINS ],
 "SIP9": [ (str(k),0,-G*(k-1),0.8,1.6) for k in range(1,10) ],
 "R_AXIAL": [("1",0,0,0.8,1.6),("2",10.16,0,0.8,1.6)],
 "C_DISC": [("1",0,0,0.9,1.8),("2",0,-5.08,0.9,1.8)],
 "CP_RADIAL": [("1",0,0,0.9,1.8),("2",0,-5.08,0.9,1.8)],
 "TB4": [(str(k+1),0,-5.08*k,1.3,3.0) for k in range(4)],
 "LED5": [("2",0,0,0.9,1.8),("1",2.54,0,0.9,1.8)],
}
# ---------------- devices: symbol pins + pin->pad map -------------------------
def gates14(): 
    return dict(L=["1A","1B","2A","2B","3A","3B","4A","4B"],R=["1Y","2Y","3Y","4Y","VCC","GND"],
      pm={"1A":"1","1B":"2","1Y":"3","2A":"4","2B":"5","2Y":"6","GND":"7","3Y":"8","3A":"9","3B":"10","4Y":"11","4A":"12","4B":"13","VCC":"14"},pkg="DIP14")
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
   R=["C%d"%i for i in range(1,33)],
   pm={p:p for p in ALLPINS}, pkg="DIN96"),
 "CAP": dict(L=["1"],R=["2"],pm={"1":"1","2":"2"},pkg="C_DISC"),
 "CAPP": dict(L=["+"],R=["-"],pm={"+":"1","-":"2"},pkg="CP_RADIAL"),
 "RES": dict(L=["1"],R=["2"],pm={"1":"1","2":"2"},pkg="R_AXIAL"),
 "SIP9": dict(L=["COM"],R=["R%d"%i for i in range(1,9)],
   pm=dict([("COM","1")]+[("R%d"%i,str(i+1)) for i in range(1,9)]),pkg="SIP9"),
 "TB4": dict(L=["1","2"],R=["3","4"],pm={str(k):str(k) for k in range(1,5)},pkg="TB4"),
 "LED": dict(L=["A"],R=["K"],pm={"A":"2","K":"1"},pkg="LED5"),
}
SCH_LAYERS=[(91,"Nets",2),(92,"Busses",1),(93,"Pins",2),(94,"Symbols",4),(95,"Names",7),
 (96,"Values",7),(97,"Info",7),(98,"Guide",6)]
BRD_LAYERS=[(1,"Top",4),(2,"Route2",1),(15,"Route15",4),(16,"Bottom",1),(17,"Pads",2),
 (18,"Vias",2),(19,"Unrouted",6),(20,"Dimension",24),(21,"tPlace",7),(22,"bPlace",7),
 (23,"tOrigins",15),(24,"bOrigins",15),(25,"tNames",7),(26,"bNames",7),(27,"tValues",7),
 (28,"bValues",7),(39,"tKeepout",4),(40,"bKeepout",1),(41,"tRestrict",4),(42,"bRestrict",1),
 (43,"vRestrict",2),(44,"Drills",7),(45,"Holes",7),(46,"Milling",3),(47,"Measures",7),
 (48,"Document",7),(49,"Reference",7),(51,"tDocu",7),(52,"bDocu",7)]
def hdr(layers):
    o=['<?xml version="1.0" encoding="utf-8"?>','<!DOCTYPE eagle SYSTEM "eagle.dtd">',
       '<eagle version="9.6.2">','<drawing>',
       '<settings><setting alwaysvectorfont="no"/><setting verticaltext="up"/></settings>',
       '<grid distance="0.1" unitdist="inch" unit="inch" style="lines" multiple="1" display="no" altdistance="0.01" altunitdist="inch" altunit="inch"/>',
       '<layers>']
    for n,nm,c in layers+ [l for l in BRD_LAYERS if layers is SCH_LAYERS and False]:
        o.append(f'<layer number="{n}" name="{nm}" color="{c}" fill="1" visible="yes" active="yes"/>')
    o.append('</layers>')
    return o
def lib_xml(devnames, for_board):
    o=['<libraries><library name="p8x">','<packages>']
    pkgs=sorted({DEV[d]["pkg"] for d in devnames})
    for pk in pkgs:
        o.append(f'<package name="{pk}">')
        for (nm,x,y,dr,sz) in PKG[pk]:
            o.append(f'<pad name="{nm}" x="{x:.2f}" y="{y:.2f}" drill="{dr}" diameter="{sz}"/>')
        o.append('<text x="0" y="2.54" size="1.27" layer="25">&gt;NAME</text>')
        o.append('</package>')
    o.append('</packages>')
    if not for_board:
        o.append('<symbols>')
        for dn in sorted(set(devnames)):
            d=DEV[dn]; L,R=d["L"],d["R"]; n=max(len(L),len(R)); y1=-G*(n-1)-G
            o.append(f'<symbol name="{dn}">')
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
            o.append(f'<deviceset name="{dn}" prefix="U"><gates><gate name="G$1" symbol="{dn}" x="0" y="0"/></gates>')
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
def write_sch(fn,title,parts,nets):
    o=hdr(SCH_LAYERS)
    o.append('<schematic xreflabel="%F%N/%S.%C%R" xrefpart="/%S.%C%R">')
    o+=lib_xml([p[0] for p in parts.values()],False)
    o.append('<classes><class number="0" name="default" width="0" drill="0"/></classes>')
    o.append('<parts>')
    for ref,(dev,val,x,y) in parts.items():
        o.append(f'<part name="{ref}" library="p8x" deviceset="{dev}" device="" value="{val}"/>')
    o.append('</parts><sheets><sheet><plain>')
    o.append(f'<text x="0" y="40" size="3.81" layer="97">{title}</text>')
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
    open(fn,"w").write("\n".join(o)+"\n")
def write_brd(fn,title,parts,nets,wires,polys,W,H,vias=None):
    vias=vias or {}
    o=hdr(BRD_LAYERS)
    o.append('<board><plain>')
    for (a,b,c,d) in [(0,0,W,0),(W,0,W,H),(W,H,0,H),(0,H,0,0)]:
        o.append(f'<wire x1="{a}" y1="{b}" x2="{c}" y2="{d}" width="0" layer="20"/>')
    o.append(f'<text x="4" y="{H-6}" size="2.54" layer="21">{title}</text>')
    o.append('</plain>')
    o+=lib_xml([p[0] for p in parts.values()],True)
    o.append('<classes><class number="0" name="default" width="0" drill="0"/></classes>')
    o.append('<designrules name="default"><param name="layerSetup" value="(1*2*15*16)"/></designrules>')
    o.append('<elements>')
    for ref,pv in parts.items():
        dev,val,x,y=pv[:4]; rot=f' rot="{pv[4]}"' if len(pv)>4 else ""
        o.append(f'<element name="{ref}" library="p8x" package="{DEV[dev]["pkg"]}" value="{val}" x="{x:.2f}" y="{y:.2f}"{rot}/>')
    o.append('</elements><signals>')
    allnets=set(nets)|set(wires)|set(polys)
    for nn in sorted(allnets):
        o.append(f'<signal name="{nn}">')
        for ref,pin in nets.get(nn,[]):
            pad=DEV[parts[ref][0]]["pm"][pin]
            o.append(f'<contactref element="{ref}" pad="{pad}"/>')
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
    open(fn,"w").write("\n".join(o)+"\n")
def validate(fn,parts,nets):
    import xml.etree.ElementTree as ET
    t=ET.parse(fn);root=t.getroot()
    errs=0
    if root.find(".//schematic") is not None:
        for pr in root.findall(".//pinref"):
            dev=parts[pr.get("part")][0]
            if pr.get("pin") not in DEV[dev]["L"]+DEV[dev]["R"]: errs+=1;print("bad pin",pr.get("part"),pr.get("pin"))
    else:
        for cr in root.findall(".//contactref"):
            dev=parts[cr.get("element")][0]
            pads={p[0] for p in PKG[DEV[dev]["pkg"]]}
            if cr.get("pad") not in pads: errs+=1;print("bad pad",cr.get("element"),cr.get("pad"))
    seen=set()
    for nn,pins in nets.items():
        for rp in pins:
            assert rp not in seen,(rp,nn); seen.add(rp)
    print(fn,"validated, errors:",errs); assert errs==0

# ======================= MEMORY CARD rev C ====================================
mc_parts={
 "J1":("DIN96","DIN41612-96M",35.56,38.10),
 "U1":("MEM28K8","28C256-15",132.08,38.10),"U2":("MEM28K8","62256-70",220.98,38.10),
 "U3":("74245","74HCT245",309.88,38.10),"U4":("7430","74HCT30",398.78,38.10),
 "U9":("GATES14","74HCT08",487.68,38.10),"U5":("74138","74HCT138-DOE",132.08,-76.20),
 "U6":("74138","74HCT138-DLD",220.98,-76.20),"U7":("GATES14","74HCT00",309.88,-76.20),
 "U8":("GATES14","74HCT32",398.78,-76.20)}
# Eagle sch is y-up; rows: top row y=38.10, second row y=-76.20
mcn={}
def mnet(n,*p): mcn.setdefault(n,[]).extend(p)
for i in range(8):
    mnet("D%d"%i,("J1","A%d"%(3+i)),("U3","A%d"%i))
    mnet("MD%d"%i,("U3","B%d"%i),("U1","IO%d"%i),("U2","IO%d"%i))
for i in range(16):
    pins=[("J1","C%d"%(3+i))]
    if i<15: pins+=[("U1","A%d"%i),("U2","A%d"%i)]
    if 8<=i<=14: pins.append(("U4","ABCDEFG"[i-8]))
    if i==15: pins+=[("U4","H"),("U1","!CE"),("U7","1A")]
    mnet("A%d"%i,*pins)
mnet("-IOPG",("U4","Y"),("U7","1B"))
mnet("-RAMCE",("U7","1Y"),("U2","!CE"))
for i in range(4):
    mnet("DOE%d"%i,("J1","A%d"%(12+i)),("U5",["A","B","C","!G2A"][i]))
    mnet("DLD%d"%i,("J1","A%d"%(16+i)),("U6",["A","B","C","!G2A"][i]))
mnet("-RD",("U5","Y7"),("U1","!OE"),("U2","!OE"),("U3","DIR"),("U9","1A"))
mnet("-MEMW",("U6","Y7"),("U8","1A"),("U9","1B"))
mnet("CLK",("J1","A24"),("U8","1B"))
mnet("-WE",("U8","1Y"),("U1","!WE"),("U2","!WE"))
mnet("-BOE",("U9","1Y"),("U3","!OE"))
mnet("VCC",*[("J1",p) for p in("A1","B1","C1","A2","B2","C2")],
  ("U1","VCC"),("U2","VCC"),("U3","VCC"),("U4","VCC"),("U5","VCC"),("U5","G1"),
  ("U6","VCC"),("U6","G1"),("U7","VCC"),("U8","VCC"),("U9","VCC"))
mnet("GND",*[("J1",p) for p in("A31","B31","C31","A32","B32","C32")],
  *[("J1","B%d"%i) for i in range(3,31)],
  ("U1","GND"),("U2","GND"),("U3","GND"),("U4","GND"),("U5","GND"),("U5","!G2B"),
  ("U6","GND"),("U6","!G2B"),("U7","GND"),("U8","GND"),("U9","GND"),
  *[(u,p) for u in("U7","U8","U9") for p in("2A","2B","3A","3B","4A","4B")])
write_sch("p8x-memory-card.sch","P8X MEMORY CARD REV C",mc_parts,mcn)
validate("p8x-memory-card.sch",mc_parts,mcn)
mcb_parts={
 "J1":("DIN96","DIN41612-96M",147.32,88.90),
 "U1":("MEM28K8","28C256-15",17.78,83.82),"U2":("MEM28K8","62256-70",43.18,83.82),
 "U3":("74245","74HCT245",68.58,83.82),"U4":("7430","74HCT30",88.90,83.82),
 "U5":("74138","74HCT138-DOE",109.22,83.82),"U6":("74138","74HCT138-DLD",17.78,35.56),
 "U7":("GATES14","74HCT00",43.18,35.56),"U8":("GATES14","74HCT32",68.58,35.56),
 "U9":("GATES14","74HCT08",88.90,35.56)}
write_brd("p8x-memory-card.brd","P8X MEMORY CARD REV C",mcb_parts,mcn,{},
          {"GND":[(2,)],"VCC":[(15,)]},160,100)
validate("p8x-memory-card.brd",mcb_parts,mcn)

# ======================= BACKPLANE rev C ======================================
bps={}
for i in range(10):
    bps["J%d"%(i+1)]=("DIN96","SLOT%d"%(i+1),35.56+101.6*(i%5), 38.10-281.94*(i//5))
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
for i in range(10): bps["C%d"%(i+1)]=("CAP","100N",35.56+50.8*i,-723.9)
for b in range(8): bnet("D%d"%b,("RN1","R%d"%(b+1)))
bnet("CLK",("RT1","1")); bnet("CLK_T",("RT1","2"),("CT1","1"))
bnet("CLKB",("RT2","1")); bnet("CLKB_T",("RT2","2"),("CT2","1"))
bnet("LED_A",("RL1","2"),("LED1","A"))
write_sch("p8x-backplane.sch","P8X 10-SLOT BACKPLANE REV C",bps,bpn)
validate("p8x-backplane.sch",bps,bpn)
# --- board: fully routed, y-up; compact variant, W under 250mm ---
X0=15.24;P=25.4
def sx(i):return X0+P*i
def py(n):return G*(38-n)        # pin1 y=93.98 ... pin32 y=15.24
bpb={}
for i in range(10): bpb["J%d"%(i+1)]=("DIN96","SLOT%d"%(i+1),sx(i)-5.08,93.98)
# service column tucked at right edge; clock RC moved to top strip
bpb["RN1"]=("SIP9","8X10K",246.38,91.44)
bpb["RT1"]=("RES","100R",238.76,101.60,"R180")   # pad1(CLK)@238.76, pad2@228.60
bpb["CT1"]=("CAP","150P",223.52,101.60)
bpb["RT2"]=("RES","100R",238.76,106.68,"R180")
bpb["CT2"]=("CAP","150P",213.36,106.68)
bpb["J11"]=("TB4","PWR-5V",5.08,78.74)
bpb["CB1"]=("CAPP","470U",5.08,55.88); bpb["CB2"]=("CAPP","470U",5.08,45.72)
for s in range(10): bpb["C%d"%(s+1)]=("CAP","100N",sx(s)+G,104.14)
bpb["RL1"]=("RES","1K",15.24,7.62); bpb["LED1"]=("LED","PWR",30.48,7.62)
wires={}; viad={}
def wadd(n,*w): wires.setdefault(n,[]).extend(w)
def vadd(n,*v): viad.setdefault(n,[]).extend(v)
RNX=246.38
for n in range(3,31):
    y=py(n)
    nA=busnet("A%d"%n)
    xe=RNX if 3<=n<=10 else sx(9)           # D lines extend to the pull-up column
    wadd(nA,(sx(0),y,xe,y,1,0.4))
    nC=busnet("C%d"%n)
    wadd(nC,(sx(0)-5.08,y,sx(9)-5.08,y,16,0.4))
# CLK: leave slot-10 pad on Bottom, ride the pad-free channel up, via to Top strip
wadd("CLK",(sx(9),py(24),242.10,py(24),16,0.4),
           (242.10,py(24),242.10,101.60,16,0.4),
           (242.10,101.60,238.76,101.60,1,0.4))
vadd("CLK",(242.10,101.60))
wadd("CLK_T",(228.60,101.60,223.52,101.60,1,0.4))
wadd("CLKB",(sx(9),py(25),240.50,py(25),16,0.4),
            (240.50,py(25),240.50,106.68,16,0.4),
            (240.50,106.68,238.76,106.68,1,0.4))
vadd("CLKB",(240.50,106.68))
wadd("CLKB_T",(228.60,106.68,213.36,106.68,1,0.4))
wadd("LED_A",(25.40,7.62,30.48,7.62,1,0.4))
write_brd("p8x-backplane.brd","P8X 10-SLOT BACKPLANE REV C COMPACT",bpb,bpn,wires,
          {"GND":[(2,)],"VCC":[(15,)]},248.92,109.22,viad)
validate("p8x-backplane.brd",bpb,bpn)
print("ALL FILES GENERATED")
