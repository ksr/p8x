#!/usr/bin/env python3
# P8X board generator -- emits KiCad 7-format schematics (opens in 7/8/9):
#   1) p8x-backplane.kicad_sch    10-slot DIN41612 96-pin backplane, rev C pinout
#   2) p8x-memory-card.kicad_sch  memory card REV C (matches new power pinout)
# Rev C power: A1,B1,C1,A2,B2,C2 = +5V ; A31,B31,C31,A32,B32,C32 = GND
# Row B3-B30 = GND guard row between the two signal rows.
import uuid as U
def uid(): return str(U.uuid4())
PIN_X=17.78; STUB=5.08; PITCH=2.54
F="(effects (font (size 1.27 1.27)))"
FH="(effects (font (size 1.27 1.27)) hide)"

# ---------------- rev C backplane pin -> net map -----------------------------
def busnet(pin):
    r,n = pin[0], int(pin[1:])
    if n in (1,2): return "VCC"
    if n in (31,32): return "GND"
    if r=="B": return "GND"                       # guard row
    if r=="A":
        if 3<=n<=10:  return "D%d"%(n-3)
        if n==11: return "RES_N"
        if 12<=n<=15: return "DOE%d"%(n-12)
        if 16<=n<=19: return "DLD%d"%(n-16)
        if n==20: return "PSEL0"
        if n==21: return "PSEL1"
        if n==22: return "PINC"
        if n==23: return "PDEC"
        if n==24: return "CLK"
        if n==25: return "CLKB"
        if n==26: return "LDF"
        return "SPARE%d"%(n-27)                   # A27-A30 -> SPARE0-3
    if r=="C":
        if 3<=n<=18:  return "A%d"%(n-3)
        if 19<=n<=22: return "ALUS%d"%(n-19)
        if n==23: return "ALUM"
        if n==24: return "CIN"
        if n==25: return "SH0"
        if n==26: return "SH1"
        return "SPARE%d"%(n-27+4)                 # C27-C30 -> SPARE4-7
    raise KeyError(pin)
ALLPINS=[ "%s%d"%(r,n) for r in "ABC" for n in range(1,33)]

# ---------------- shared device library --------------------------------------
def din(fp):
    return dict(fp=fp,
      L=[("A%d"%i,"A%d"%i,"passive") for i in range(1,33)]+
        [("B%d"%i,"B%d"%i,"passive") for i in range(1,33)],
      R=[("C%d"%i,"C%d"%i,"passive") for i in range(1,33)])
DEV={
 "DIN96M": din("Connector_DIN:DIN41612_C_3x32_Male_Horizontal"),
 "DIN96F": din("Connector_DIN:DIN41612_C_3x32_Female_Vertical"),
 "CAP": dict(fp="Capacitor_THT:C_Disc_D7.5mm_W5.0mm_P5.00mm",
   L=[("1","1","passive")], R=[("2","2","passive")]),
 "CAPP": dict(fp="Capacitor_THT:CP_Radial_D10.0mm_P5.00mm",
   L=[("+","1","passive")], R=[("-","2","passive")]),
 "RES": dict(fp="Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",
   L=[("1","1","passive")], R=[("2","2","passive")]),
 "SIP9": dict(fp="Resistor_THT:R_Array_SIP9",
   L=[("COM","1","passive")],
   R=[("R%d"%i,str(i+1),"passive") for i in range(1,9)]),
 "TB4": dict(fp="TerminalBlock:TerminalBlock_bornier-4_P5.08mm",
   L=[("1","1","passive"),("2","2","passive")],
   R=[("3","3","passive"),("4","4","passive")]),
 "LED": dict(fp="LED_THT:LED_D5.0mm",
   L=[("A","2","passive")], R=[("K","1","passive")]),
 # memory card devices
 "MEM28K8": dict(fp="Package_DIP:DIP-28_W15.24mm",
   L=[("A0","10","input"),("A1","9","input"),("A2","8","input"),("A3","7","input"),
      ("A4","6","input"),("A5","5","input"),("A6","4","input"),("A7","3","input"),
      ("A8","25","input"),("A9","24","input"),("A10","21","input"),("A11","23","input"),
      ("A12","2","input"),("A13","26","input"),("A14","1","input")],
   R=[("IO0","11","bidirectional"),("IO1","12","bidirectional"),("IO2","13","bidirectional"),
      ("IO3","15","bidirectional"),("IO4","16","bidirectional"),("IO5","17","bidirectional"),
      ("IO6","18","bidirectional"),("IO7","19","bidirectional"),
      ("~{CE}","20","input"),("~{OE}","22","input"),("~{WE}","27","input"),
      ("VCC","28","power_in"),("GND","14","power_in")]),
 "74245": dict(fp="Package_DIP:DIP-20_W7.62mm",
   L=[("DIR","1","input")]+[("A%d"%i,str(i+2),"bidirectional") for i in range(8)]+[("~{OE}","19","input")],
   R=[("B%d"%i,str(18-i),"bidirectional") for i in range(8)]+[("VCC","20","power_in"),("GND","10","power_in")]),
 "7430": dict(fp="Package_DIP:DIP-14_W7.62mm",
   L=[("A","1","input"),("B","2","input"),("C","3","input"),("D","4","input"),
      ("E","5","input"),("F","6","input"),("G","11","input"),("H","12","input")],
   R=[("Y","8","output"),("VCC","14","power_in"),("GND","7","power_in")]),
 "74138": dict(fp="Package_DIP:DIP-16_W7.62mm",
   L=[("A","1","input"),("B","2","input"),("C","3","input"),
      ("G1","6","input"),("~{G2A}","4","input"),("~{G2B}","5","input")],
   R=[("Y0","15","output"),("Y1","14","output"),("Y2","13","output"),("Y3","12","output"),
      ("Y4","11","output"),("Y5","10","output"),("Y6","9","output"),("Y7","7","output"),
      ("VCC","16","power_in"),("GND","8","power_in")]),
 "GATES14": dict(fp="Package_DIP:DIP-14_W7.62mm",
   L=[("1A","1","input"),("1B","2","input"),("2A","4","input"),("2B","5","input"),
      ("3A","9","input"),("3B","10","input"),("4A","12","input"),("4B","13","input")],
   R=[("1Y","3","output"),("2Y","6","output"),("3Y","8","output"),("4Y","11","output"),
      ("VCC","14","power_in"),("GND","7","power_in")]),
}
def pininfo(dev,name):
    d=DEV[dev]
    for i,(n,num,et) in enumerate(d["L"]):
        if n==name: return ("L",i,num)
    for i,(n,num,et) in enumerate(d["R"]):
        if n==name: return ("R",i,num)
    raise KeyError((dev,name))

def emit(filename, title, paper, parts, nets, project):
    used=set()
    for p in nets.values(): used.update(p)
    NC=[]
    for ref,(dev,_,_,_) in parts.items():
        for (nm,num,et) in DEV[dev]["L"]+DEV[dev]["R"]:
            if (ref,nm) not in used: NC.append((ref,nm))
    def pinpos(ref,name):
        dev,val,X,Y=parts[ref]
        side,i,num=pininfo(dev,name)
        return (X-PIN_X,Y+PITCH*i,"L",num) if side=="L" else (X+PIN_X,Y+PITCH*i,"R",num)
    ROOT=uid(); o=[]
    o.append(f'(kicad_sch (version 20230121) (generator p8xgen)\n  (uuid {ROOT})\n  (paper "{paper}")')
    o.append('  (lib_symbols')
    useddevs=sorted({d[0] for d in parts.values()})
    for dn in useddevs:
        d=DEV[dn]; n=max(len(d["L"]),len(d["R"])); ybot=-(PITCH*(n-1)+PITCH)
        o.append(f'    (symbol "p8x:{dn}" (pin_names (offset 1.016)) (in_bom yes) (on_board yes)')
        o.append(f'      (property "Reference" "U" (at 0 5.08 0) {F})')
        o.append(f'      (property "Value" "{dn}" (at 0 7.62 0) {F})')
        o.append(f'      (property "Footprint" "{d["fp"]}" (at 0 0 0) {FH})')
        o.append(f'      (property "Datasheet" "" (at 0 0 0) {FH})')
        o.append(f'      (symbol "{dn}_0_1"')
        o.append(f'        (rectangle (start -12.7 2.54) (end 12.7 {ybot}) (stroke (width 0.254) (type default)) (fill (type background))))')
        o.append(f'      (symbol "{dn}_1_1"')
        for i,(nm,num,et) in enumerate(d["L"]):
            o.append(f'        (pin {et} line (at {-PIN_X} {-PITCH*i} 0) (length {STUB}) (name "{nm}" {F}) (number "{num}" {F}))')
        for i,(nm,num,et) in enumerate(d["R"]):
            o.append(f'        (pin {et} line (at {PIN_X} {-PITCH*i} 180) (length {STUB}) (name "{nm}" {F}) (number "{num}" {F}))')
        o.append('      ))')
    o.append('  )')
    o.append(f'  (text "{title}" (at 35.56 17.78 0) (effects (font (size 3 3)) (justify left bottom)) (uuid {uid()}))')
    for ref,(dev,val,X,Y) in parts.items():
        o.append(f'  (symbol (lib_id "p8x:{dev}") (at {X} {Y} 0) (unit 1) (in_bom yes) (on_board yes) (dnp no)')
        o.append(f'    (uuid {uid()})')
        o.append(f'    (property "Reference" "{ref}" (at {X} {Y-7.62} 0) {F})')
        o.append(f'    (property "Value" "{val}" (at {X} {Y-5.08} 0) {F})')
        o.append(f'    (property "Footprint" "{DEV[dev]["fp"]}" (at {X} {Y} 0) {FH})')
        o.append(f'    (property "Datasheet" "" (at {X} {Y} 0) {FH})')
        for (nm,num,et) in DEV[dev]["L"]+DEV[dev]["R"]:
            o.append(f'    (pin "{num}" (uuid {uid()}))')
        o.append(f'    (instances (project "{project}" (path "/{ROOT}" (reference "{ref}") (unit 1)))))')
    for nname,pins in nets.items():
        for (ref,pname) in pins:
            x,y,side,num=pinpos(ref,pname)
            x2 = x-STUB if side=="L" else x+STUB
            jst = "right bottom" if side=="L" else "left bottom"
            o.append(f'  (wire (pts (xy {x:.2f} {y:.2f}) (xy {x2:.2f} {y:.2f})) (stroke (width 0) (type default)) (uuid {uid()}))')
            o.append(f'  (label "{nname}" (at {x2:.2f} {y:.2f} 0) (effects (font (size 1.27 1.27)) (justify {jst})) (uuid {uid()}))')
    for (ref,pname) in NC:
        x,y,_,_=pinpos(ref,pname)
        o.append(f'  (no_connect (at {x:.2f} {y:.2f}) (uuid {uid()}))')
    o.append('  (sheet_instances (path "/" (page "1")))\n)')
    txt="\n".join(o)+"\n"
    open(filename,"w").write(txt)
    # validation
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
        assert ts[i]=='('
        i+=1
        while ts[i]!=')':
            if ts[i]=='(' : _,i=parse(ts,i)
            else: i+=1
        return None,i+1
    _,end=parse(toks); assert end==len(toks)
    seen=set()
    for pins in nets.values():
        for rp in pins:
            x,y,_,_=pinpos(*rp)
            assert abs((x/1.27)-round(x/1.27))<1e-6 and abs((y/1.27)-round(y/1.27))<1e-6
            assert rp not in seen, rp
            seen.add(rp)
    tot=sum(len(DEV[d[0]]["L"])+len(DEV[d[0]]["R"]) for d in parts.values())
    assert len(seen)+len(NC)==tot
    print(f"{filename}: {len(txt)} bytes, {len(seen)} netted pins, {len(NC)} NC, coverage OK")

# =================== BOARD 1: BACKPLANE =======================================
bp_parts={}
for i in range(10):
    col=i%5; row=i//5
    bp_parts["J%d"%(i+1)]=("DIN96F","SLOT %d"%(i+1), 35.56+101.6*col, 38.10+220.98*row)
y3=502.92  # small parts row (198*2.54)
small=[("J11","TB4","PWR IN 5V",35.56),("CB1","CAPP","470u",86.36),("CB2","CAPP","470u",137.16),
       ("RN1","SIP9","8x10K PULLUP",187.96),
       ("RT1","RES","100R CLK TERM",238.76),("CT1","CAP","150p",289.56),
       ("RT2","RES","100R CLKB TERM",340.36),("CT2","CAP","150p",391.16),
       ("RL1","RES","1K",441.96),("LED1","LED","PWR",492.76)]
for ref,dev,val,x in small: bp_parts[ref]=(dev,val,x,y3)
for i in range(10):
    bp_parts["C%d"%(i+1)]=("CAP","100n", 35.56+50.8*i, 553.72)  # per-slot decoupling
bp_nets={}
def bnet(n,*p): bp_nets.setdefault(n,[]).extend(p)
for i in range(10):
    ref="J%d"%(i+1)
    for pin in ALLPINS: bnet(busnet(pin),(ref,pin))
bnet("VCC",("J11","1"),("J11","2"),("CB1","+"),("CB2","+"),("RN1","COM"),
     ("RL1","1"),*[("C%d"%(i+1),"1") for i in range(10)])
bnet("GND",("J11","3"),("J11","4"),("CB1","-"),("CB2","-"),("LED1","K"),
     ("CT1","2"),("CT2","2"),*[("C%d"%(i+1),"2") for i in range(10)])
for b in range(8): bnet("D%d"%b,("RN1","R%d"%(b+1)))
bnet("CLK",("RT1","1"));  bnet("CLK_T",("RT1","2"),("CT1","1"))
bnet("CLKB",("RT2","1")); bnet("CLKB_T",("RT2","2"),("CT2","1"))
bnet("LED_A",("RL1","2"),("LED1","A"))
emit("p8x-backplane.kicad_sch",
     "P8X 10-SLOT BACKPLANE REV C - A1/B1/C1/A2/B2/C2=+5V, A31/B31/C31/A32/B32/C32=GND, ROW B GUARD",
     "A1", bp_parts, bp_nets, "p8x-backplane")

# =================== BOARD 2: MEMORY CARD REV C ================================
mc_parts={
 "J1": ("DIN96M","DIN41612-96", 35.56, 38.10),
 "U1": ("MEM28K8","28C256-15",  132.08, 38.10),
 "U2": ("MEM28K8","62256-70",   220.98, 38.10),
 "U3": ("74245","74HCT245",     309.88, 38.10),
 "U4": ("7430","74HCT30",       398.78, 38.10),
 "U9": ("GATES14","74HCT08",    487.68, 38.10),
 "U5": ("74138","74HCT138 DOE", 132.08, 152.40),
 "U6": ("74138","74HCT138 DLD", 220.98, 152.40),
 "U7": ("GATES14","74HCT00",    309.88, 152.40),
 "U8": ("GATES14","74HCT32",    398.78, 152.40),
}
mc_nets={}
def mnet(n,*p): mc_nets.setdefault(n,[]).extend(p)
for i in range(8):
    mnet("D%d"%i, ("J1","A%d"%(3+i)), ("U3","A%d"%i))
    mnet("MD%d"%i, ("U3","B%d"%i), ("U1","IO%d"%i), ("U2","IO%d"%i))
for i in range(16):
    pins=[("J1","C%d"%(3+i))]
    if i<15: pins+=[("U1","A%d"%i),("U2","A%d"%i)]
    if 8<=i<=14: pins.append(("U4","ABCDEFG"[i-8]))
    if i==15: pins+=[("U4","H"),("U1","~{CE}"),("U7","1A")]
    mnet("A%d"%i,*pins)
mnet("IOPG_N",("U4","Y"),("U7","1B"))
mnet("RAMCE_N",("U7","1Y"),("U2","~{CE}"))
for i in range(4):
    mnet("DOE%d"%i,("J1","A%d"%(12+i)),("U5",["A","B","C","~{G2A}"][i]))
    mnet("DLD%d"%i,("J1","A%d"%(16+i)),("U6",["A","B","C","~{G2A}"][i]))
mnet("RD_N",("U5","Y7"),("U1","~{OE}"),("U2","~{OE}"),("U3","DIR"),("U9","1A"))
mnet("MEMW_N",("U6","Y7"),("U8","1A"),("U9","1B"))
mnet("CLK",("J1","A24"),("U8","1B"))
mnet("WE_N",("U8","1Y"),("U1","~{WE}"),("U2","~{WE}"))
mnet("BOE_N",("U9","1Y"),("U3","~{OE}"))
# rev C power pins
mnet("VCC",*[("J1",p) for p in ("A1","B1","C1","A2","B2","C2")],
     ("U1","VCC"),("U2","VCC"),("U3","VCC"),("U4","VCC"),("U5","VCC"),("U5","G1"),
     ("U6","VCC"),("U6","G1"),("U7","VCC"),("U8","VCC"),("U9","VCC"))
mnet("GND",*[("J1",p) for p in ("A31","B31","C31","A32","B32","C32")],
     *[("J1","B%d"%i) for i in range(3,31)],
     ("U1","GND"),("U2","GND"),("U3","GND"),("U4","GND"),("U5","GND"),
     ("U5","~{G2B}"),("U6","GND"),("U6","~{G2B}"),("U7","GND"),("U8","GND"),("U9","GND"),
     ("U7","2A"),("U7","2B"),("U7","3A"),("U7","3B"),("U7","4A"),("U7","4B"),
     ("U8","2A"),("U8","2B"),("U8","3A"),("U8","3B"),("U8","4A"),("U8","4B"),
     ("U9","2A"),("U9","2B"),("U9","3A"),("U9","3B"),("U9","4A"),("U9","4B"))
emit("p8x-memory-card.kicad_sch",
     "P8X MEMORY CARD REV C - MATCHES REV C BACKPLANE POWER PINOUT",
     "A2", mc_parts, mc_nets, "p8x-memory-card")
