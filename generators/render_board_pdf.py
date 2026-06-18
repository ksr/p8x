#!/usr/bin/env python3
"""Placement-view PDF for each P8X board (.brd).

Draws the board outline, every component footprint (pads + drill holes from the
canonical PKG table), reference designators, values, pin-1 markers, and a title
block. DNP (Do-Not-Populate) parts are drawn greyed/dashed.

NOT a routed layout: the generator only PLACES parts + emits the netlist, so
there is no copper here. This is a pre-route sanity check (placement, spacing,
overlap). Routed copper / Gerbers come from Fusion after routing.

Data sources: the .brd files (real board x/y + package + outline) and gen_eagle's
PKG pad geometry — so it cannot drift from the boards."""
import sys, os as _os, glob, xml.etree.ElementTree as ET
_HERE=_os.path.dirname(_os.path.abspath(__file__))
_HW=_os.path.join(_os.path.dirname(_HERE),"hardware")
sys.path.insert(0,_HERE)
# gen_eagle regenerates the boards relative to the CWD on import, so run it from
# hardware/ no matter where this script is launched (avoids stray board dirs).
_os.makedirs(_HW,exist_ok=True); _os.chdir(_HW)
import gen_eagle as G                 # regenerates boards; provides PKG
from reportlab.pdfgen import canvas as pdfc
from reportlab.lib.colors import Color

MM=2.83465                            # mm -> PDF points
COPPER=Color(0.55,0.33,0.10); PAD=Color(0.72,0.45,0.12); HOLE=Color(1,1,1)
BODY=Color(0.15,0.15,0.15); OUTLINE=Color(0,0,0); TXT=Color(0,0,0)
DNPC=Color(0.62,0.62,0.62); ACCENT=Color(0,0,0.65)

def parse_brd(path):
    root=ET.parse(path).getroot()
    # board outline: rectangle wires on layer 20 -> W,H from max coords
    W=H=0.0
    for w in root.findall(".//plain/wire"):
        if w.get("layer")=="20":
            W=max(W,float(w.get("x1")),float(w.get("x2")))
            H=max(H,float(w.get("y1")),float(w.get("y2")))
    title=""
    for t in root.findall(".//plain/text"):
        title=t.text or title
    els=[]
    for e in root.findall(".//elements/element"):
        els.append(dict(ref=e.get("name"),pkg=e.get("package"),val=e.get("value") or "",
                        x=float(e.get("x")),y=float(e.get("y")),rot=e.get("rot") or "R0"))
    return title,W,H,els

def rot_xy(px,py,rot):
    if rot=="R90":  return (-py,px)
    if rot=="R180": return (-px,-py)
    if rot=="R270": return (py,-px)
    return (px,py)

def render(path,outpdf):
    title,W,H,els=parse_brd(path)
    if W<=0 or H<=0: W,H=160.0,100.0
    # extent over the board rectangle AND every pad (the auto-placer can push the
    # densest cards' parts past the board edge — show them, don't clip).
    minx=miny=0.0; maxx,maxy=W,H; spill=False
    for e in els:
        pads=G.PKG.get(e["pkg"]) or []
        for (_pn,px,py,_dr,_di) in pads:
            rx,ry=rot_xy(px,py,e["rot"]); X0=e["x"]+rx; Y0=e["y"]+ry
            minx=min(minx,X0); maxx=max(maxx,X0); miny=min(miny,Y0); maxy=max(maxy,Y0)
            if X0<-0.5 or X0>W+0.5 or Y0<-0.5 or Y0>H+0.5: spill=True
    margin=22.0; strip=30.0
    pw=(maxx-minx)*MM+2*margin; ph=(maxy-miny)*MM+2*margin+strip
    c=pdfc.Canvas(outpdf,pagesize=(pw,ph))
    ox,oy=margin-minx*MM,margin-miny*MM
    def X(mm): return ox+mm*MM
    def Y(mm): return oy+mm*MM
    # board outline
    c.setLineWidth(1.2); c.setStrokeColor(OUTLINE)
    c.rect(X(0),Y(0),W*MM,H*MM,stroke=1,fill=0)
    # parts
    dnp_n=0
    for e in els:
        pads=G.PKG.get(e["pkg"])
        if pads is None: continue
        is_dnp="DNP" in e["val"].upper()
        if is_dnp: dnp_n+=1
        # footprint pad bounding box (for the body outline + label placement)
        pxs=[]; pys=[]
        for (_pn,px,py,_dr,_di) in pads:
            rx,ry=rot_xy(px,py,e["rot"]); pxs.append(rx); pys.append(ry)
        x0,x1=min(pxs),max(pxs); y0,y1=min(pys),max(pys)
        bm=1.6   # body margin around pads (mm)
        bx,by=X(e["x"]+x0-bm),Y(e["y"]+y0-bm)
        bw,bh=(x1-x0+2*bm)*MM,(y1-y0+2*bm)*MM
        # body outline (dashed grey if DNP)
        c.setLineWidth(0.7)
        if is_dnp: c.setStrokeColor(DNPC); c.setDash(3,2)
        else:      c.setStrokeColor(BODY); c.setDash()
        c.rect(bx,by,bw,bh,stroke=1,fill=0); c.setDash()
        # pads + holes
        for i,(pn,px,py,dr,di) in enumerate(pads):
            rx,ry=rot_xy(px,py,e["rot"])
            cx,cy=X(e["x"]+rx),Y(e["y"]+ry)
            rpad=max(di,1.0)/2*MM; rhole=max(dr,0.3)/2*MM
            c.setFillColor(DNPC if is_dnp else PAD); c.setStrokeColor(DNPC if is_dnp else COPPER)
            c.setLineWidth(0.4)
            # pad 1 / first pad: square; others round
            if pn=="1" or i==0:
                c.rect(cx-rpad,cy-rpad,2*rpad,2*rpad,stroke=1,fill=1)
            else:
                c.circle(cx,cy,rpad,stroke=1,fill=1)
            c.setFillColor(HOLE); c.circle(cx,cy,rhole,stroke=0,fill=1)
        # ref designator (bold-ish) + value, centred on the body
        c.setFillColor(DNPC if is_dnp else TXT)
        cxb,cyb=bx+bw/2,by+bh/2
        c.setFont("Helvetica-Bold",6.2); c.drawCentredString(cxb,cyb+1.0,e["ref"])
        c.setFont("Helvetica",4.6)
        v=e["val"][:22]
        c.drawCentredString(cxb,cyb-5.0,v)
    # title strip (above the topmost content)
    ts=Y(max(H,maxy))+10
    c.setFillColor(ACCENT); c.setFont("Helvetica-Bold",11)
    c.drawString(margin,ts+8,title or _os.path.basename(path))
    c.setFillColor(TXT); c.setFont("Helvetica",7.5)
    note=("PLACEMENT VIEW (component side, top) — board %g x %g mm, %d parts%s. "
          "Pin 1 = square pad. NOT routed: no copper; route + DRC in Fusion."
          % (W,H,len(els),(" (%d DNP, greyed/dashed)"%dnp_n if dnp_n else "")))
    c.drawString(margin,ts-2,note)
    if spill:
        c.setFillColor(RED:=Color(0.72,0.08,0.08)); c.setFont("Helvetica-Oblique",7)
        c.drawString(margin,ts-12,"NOTE: some auto-placed parts fall outside the board outline "
                     "— placement is a rough grid; arrange properly when routing.")
    # board dimension labels (anchored to the board rect, not the page)
    c.setFont("Helvetica",6); c.setFillColor(BODY)
    c.drawCentredString(X(W/2),Y(0)-12,"%g mm"%W)
    c.saveState(); c.translate(X(0)-12,Y(H/2)); c.rotate(90)
    c.drawCentredString(0,0,"%g mm"%H); c.restoreState()
    c.save()
    return _os.path.basename(outpdf),len(els),dnp_n

if __name__=="__main__":
    brds=sorted(glob.glob(_os.path.join(_HW,"*","p8x-*.brd")))
    for b in brds:
        out=b[:-4]+"-placement.pdf"
        name,nparts,ndnp=render(b,out)
        print("wrote %-34s (%d parts%s)"%(name,nparts," , %d DNP"%ndnp if ndnp else ""))
