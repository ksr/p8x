#!/usr/bin/env python3
"""Render P8X Eagle .sch files to vector PDF (zoomable; text stays crisp)."""
import sys, xml.etree.ElementTree as ET
from reportlab.pdfgen import canvas as pdfcanvas
from reportlab.lib.colors import Color
MM=2.83465
def render(schfile, pdffile, title):
    root=ET.parse(schfile).getroot()
    symbols={}
    for s in root.findall(".//symbol"):
        prim=dict(wires=[],pins=[],texts=[])
        for w in s.findall("wire"):
            prim["wires"].append(tuple(float(w.get(k)) for k in("x1","y1","x2","y2")))
        for p in s.findall("pin"):
            prim["pins"].append((p.get("name"),float(p.get("x")),float(p.get("y")),p.get("rot") or "R0"))
        for t in s.findall("text"):
            prim["texts"].append((t.text,float(t.get("x")),float(t.get("y"))))
        symbols[s.get("name")]=prim
    ds2sym={d.get("name"):d.find(".//gate").get("symbol") for d in root.findall(".//deviceset")}
    parts={p.get("name"):(p.get("deviceset"),p.get("value") or "") for p in root.findall(".//parts/part")}
    insts=[(i.get("part"),float(i.get("x")),float(i.get("y"))) for i in root.findall(".//instance")]
    nets=[]
    for n in root.findall(".//net"):
        for seg in n.findall("segment"):
            for w in seg.findall("wire"):
                nets.append(("w",tuple(float(w.get(k)) for k in("x1","y1","x2","y2")),n.get("name")))
            for l in seg.findall("label"):
                nets.append(("l",(float(l.get("x")),float(l.get("y"))),n.get("name")))
    # bounds
    xs=[];ys=[]
    for ref,ix,iy in insts:
        sym=symbols[ds2sym[parts[ref][0]]]
        for (x1,y1,x2,y2) in sym["wires"]: xs+=[ix+x1,ix+x2]; ys+=[iy+y1,iy+y2]
        for (_,px,py,_) in sym["pins"]: xs.append(ix+px); ys.append(iy+py)
    for kind,geo,name in nets:
        if kind=="w": xs+=[geo[0],geo[2]]; ys+=[geo[1],geo[3]]
        else: xs.append(geo[0]); ys.append(geo[1])
    minx,maxx,miny,maxy=min(xs)-15,max(xs)+25,min(ys)-10,max(ys)+15
    W,H=maxx-minx,maxy-miny
    if W>=H: pw,ph=1683,1190     # A2 landscape pt
    else:    pw,ph=1190,1683
    s=min((pw-40)/(W*MM),(ph-60)/(H*MM))*MM
    def X(x): return 20+(x-minx)*s
    def Y(y): return 40+(y-miny)*s
    c=pdfcanvas.Canvas(pdffile,pagesize=(pw,ph))
    c.setFont("Helvetica-Bold",16); c.drawString(20,ph-25,title)
    c.setFont("Helvetica",9)
    c.drawString(20,ph-38,"Generated from %s - vector PDF, zoom for detail. Connections are by net label (same name = same net)."%schfile)
    GREEN=Color(0,0.45,0); RED=Color(0.7,0.1,0.1); BLK=Color(0,0,0)
    for ref,ix,iy in insts:
        dsname,val=parts[ref]; sym=symbols[ds2sym[dsname]]
        c.setStrokeColor(BLK); c.setLineWidth(0.7)
        for (x1,y1,x2,y2) in sym["wires"]:
            c.line(X(ix+x1),Y(iy+y1),X(ix+x2),Y(iy+y2))
        c.setLineWidth(0.5)
        fs=max(1.778*s,1.0)
        for (pn,px,py,rot) in sym["pins"]:
            gx,gy=ix+px,iy+py
            d=5.08 if rot=="R0" else -5.08
            c.line(X(gx),Y(gy),X(gx+d),Y(gy))
            c.setFont("Helvetica",fs*0.85); c.setFillColor(BLK)
            if rot=="R0": c.drawString(X(gx+d+0.7),Y(gy)-fs*0.3,pn)
            else: c.drawRightString(X(gx+d-0.7),Y(gy)-fs*0.3,pn)
        for (txt,tx,ty) in sym["texts"]:
            label=ref if txt==">NAME" else (val if txt==">VALUE" else txt)
            c.setFont("Helvetica-Bold",fs); c.setFillColor(RED)
            c.drawString(X(ix+tx),Y(iy+ty),label)
    c.setStrokeColor(GREEN); c.setLineWidth(0.6)
    for kind,geo,name in nets:
        if kind=="w": c.line(X(geo[0]),Y(geo[1]),X(geo[2]),Y(geo[3]))
    c.setFillColor(GREEN)
    for kind,geo,name in nets:
        if kind=="l":
            c.setFont("Helvetica",max(1.778*s,1.0))
            c.drawString(X(geo[0]),Y(geo[1]),name)
    c.save()
    print(pdffile,"written, scale %.2f, %d parts, %d net elements"%(s/MM,len(insts),len(nets)))
render("/home/claude/eagle2/p8x-memory-card.sch","/mnt/user-data/outputs/p8x-memory-card-schematic.pdf","P8X MEMORY CARD REV C - SCHEMATIC")
render("/home/claude/eagle2/p8x-backplane.sch","/mnt/user-data/outputs/p8x-backplane-schematic.pdf","P8X 10-SLOT BACKPLANE REV C - SCHEMATIC")
