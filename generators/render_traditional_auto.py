#!/usr/bin/env python3
"""Auto-drafted traditional-style schematics for the P8X cards.
Style: bus rails across the top with taps dropping into column gaps;
discrete nets on bottom track channels; rail glyphs for power; junction
dots; NC marks. Net data comes from the generator netlists (canonical)."""
import sys, re, os as _os
_HERE=_os.path.dirname(_os.path.abspath(__file__))
sys.path.insert(0,_HERE)
import gen_eagle as G              # regenerates all boards, provides DEV, busnet, ALLPINS, CARDS
_HW=_os.path.join(_os.path.dirname(_HERE),"hardware")  # per-board dirs hold CAD + docs + PDFs
from reportlab.pdfgen import canvas as pdfc
from reportlab.lib.colors import Color
MM=2.83465; GR=2.54; HALFW=12.7; PINX=17.78
BLK=Color(0,0,0); GRN=Color(0,0.42,0); RED=Color(0.72,0.08,0.08); BLU=Color(0,0,0.65)

def disp(p): return p.replace("!","-")

def draw_card(name,title,parts,nets,outpdf):
    parts={r:v for r,v in parts.items() if r!="J1"}
    # ---- J1 rows: used pins in bus order, power consolidated
    j1rows=[]; vccpins=[]; gndpins=[]
    pin2net={}
    for nn,prs in nets.items():
        for rp in prs: pin2net[rp]=nn
    lastgrp=None
    for pin in G.ALLPINS:
        nn=pin2net.get(("J1",pin))
        if nn is None: continue
        if nn=="VCC": vccpins.append(pin); continue
        if nn=="GND": gndpins.append(pin); continue
        grp=re.sub(r"\d+$","",nn)
        if lastgrp is not None and grp!=lastgrp: j1rows.append(None)
        j1rows.append((nn,pin)); lastgrp=grp
    j1rows+=[None,("+5V (%d PINS)"%len(vccpins),"#VCC"),("GND (%d PINS)"%len(gndpins),"#GND")]
    # ---- column placement
    order=list(parts)
    ncol=min(7,max(3,(len(order)+7)//8))
    percol=(len(order)+ncol-1)//ncol
    cols=[order[k*percol:(k+1)*percol] for k in range(ncol)]
    def pheight(ref):
        d=G.DEV[parts[ref][0]]
        return (max(len(d["L"]),len(d["R"]))+1)*GR
    pos={}
    # bus detection first (drop-zone width depends on bus count)
    groups={}
    for nn in nets:
        if nn in ("VCC","GND"): continue
        m=re.match(r"^(.*?)(\d+)$",nn)
        key=m.group(1) if m else None
        if key: groups.setdefault(key,[]).append(nn)
    buses=[k for k,v in sorted(groups.items()) if len(v)>=4]
    busidx={k:i for i,k in enumerate(buses)}
    busnets={nn:re.match(r"^(.*?)(\d+)$",nn).group(1) for k in buses for nn in groups[k]}
    nb=len(buses)
    STUBZ=16; DROPZ=nb*2.2+4; GAP=STUBZ*2+DROPZ
    colx=[]; x=70   # J1 occupies x<36; gap0 starts after it
    for k in range(ncol):
        colx.append(x+HALFW); x+=2*HALFW+GAP
    for k,col in enumerate(cols):
        y=0
        for ref in col:
            pos[ref]=(colx[k],y); y-=pheight(ref)+22
    ybot=min([pos[r][1]-pheight(r) for r in order]+[ -GR*len(j1rows) ])
    # ---- discrete (track) nets
    tracks=[nn for nn in nets if nn not in ("VCC","GND") and nn not in busnets]
    tracks.sort()
    tidx={nn:i for i,nn in enumerate(tracks)}
    TRACK0=ybot-22
    yfloor=TRACK0-GR*len(tracks)-12
    # ---- canvas scaled to content
    minx,maxx=-30,colx[-1]+HALFW+STUBZ+DROPZ+12
    miny,maxy=yfloor,30+nb*6+14
    W=(maxx-minx)*MM*0.95; H=(maxy-miny)*MM*0.95
    c=pdfc.Canvas(outpdf,pagesize=(W+30,H+44))
    s=0.95*MM
    def X(x): return 15+(x-minx)*s
    def Y(y): return 15+(y-miny)*s
    def line(x1,y1,x2,y2,w=0.7,col=GRN):
        c.setStrokeColor(col); c.setLineWidth(w); c.line(X(x1),Y(y1),X(x2),Y(y2))
    def dot(x,y):
        c.setFillColor(GRN); c.circle(X(x),Y(y),1.5,stroke=0,fill=1)
    def txt(x,y,t,size=1.8,col=BLK,bold=False,right=False):
        c.setFillColor(col); c.setFont("Helvetica-Bold" if bold else "Helvetica",size*s)
        (c.drawRightString if right else c.drawString)(X(x),Y(y),t)
    def vcc(x,y,d):
        line(x,y,x+d*1.8,y,0.7,RED); line(x+d*1.8,y,x+d*1.8,y+1.5,0.7,RED)
        line(x+d*1.8-1.0,y+1.5,x+d*1.8+1.0,y+1.5,1.0,RED)
    def gnd(x,y,d):
        line(x,y,x+d*1.8,y,0.7,BLU); line(x+d*1.8,y,x+d*1.8,y-1.0,0.7,BLU)
        for i,w in enumerate((1.2,0.7,0.25)):
            line(x+d*1.8-w,y-1.0-i*0.55,x+d*1.8+w,y-1.0-i*0.55,0.85,BLU)
    c.setFont("Helvetica-Bold",15); c.setFillColor(BLK)
    c.drawString(15,H+44-18,title+"  -  traditional wiring (auto-drafted)")
    c.setFont("Helvetica",8)
    c.drawString(15,H+44-30,"Bus rails top with taps in column gaps; dot = junction, plain crossing = no connection; rail glyphs = +5V/GND; X = no connect.")
    # ---- geometry helpers
    drawn=set()
    def pinxy(ref,pin):
        if ref=="J1":
            for i,row in enumerate(j1rows):
                if row and row[1]==pin: return (PINX+18-HALFW+0 if False else 18+5.08, -GR*i, "R")
            raise KeyError(pin)
        d=G.DEV[parts[ref][0]]; x,y=pos[ref]
        if pin in d["L"]: return (x-PINX,y-GR*d["L"].index(pin),"L")
        return (x+PINX,y-GR*d["R"].index(pin),"R")
    # ---- part boxes
    def box(ref):
        d=G.DEV[parts[ref][0]]; x,y=pos[ref]; n=max(len(d["L"]),len(d["R"]))
        yb=y-GR*(n-1)-GR
        c.setStrokeColor(BLK); c.setLineWidth(0.9)
        c.rect(X(x-HALFW),Y(yb),2*HALFW*s,(y+GR-yb)*s,stroke=1,fill=0)
        txt(x-HALFW,y+GR+1.0,ref,2.1,RED,bold=True)
        txt(x-HALFW,yb-3.0,parts[ref][1],1.6,BLU)
        for i,p in enumerate(d["L"]):
            line(x-PINX,y-GR*i,x-HALFW,y-GR*i,0.7,BLK); txt(x-HALFW+0.7,y-GR*i-0.6,disp(p),1.5)
        for i,p in enumerate(d["R"]):
            line(x+HALFW,y-GR*i,x+PINX,y-GR*i,0.7,BLK); txt(x+HALFW-0.7,y-GR*i-0.6,disp(p),1.5,right=True)
    for ref in order: box(ref)
    # J1 box
    c.setStrokeColor(BLK); c.setLineWidth(1.0)
    c.rect(X(-12),Y(-GR*len(j1rows)),30*s,(GR*len(j1rows)+GR)*s,stroke=1,fill=0)
    txt(-12,GR+1.2,"J1",2.3,RED,bold=True)
    txt(-12,-GR*len(j1rows)-3.4,"DIN41612 96P BUS",1.7,BLU)
    for i,row in enumerate(j1rows):
        if row is None: continue
        nm,pad=row; py=-GR*i
        line(18,py,18+5.08,py,0.7,BLK)
        txt(17,py-0.6,nm if pad.startswith("#") else "%s  %s"%(pad,nm),1.5,right=True)
    # ---- gap x lookup
    def gaps_for(colk):  # (left_gap_dropbase, right_gap_dropbase)
        right=colx[colk]+HALFW+STUBZ
        left=(colx[colk-1]+HALFW+STUBZ) if colk>0 else 36
        return left,right
    def colof(ref):
        for k,col in enumerate(cols):
            if ref in col: return k
        return -1
    # ---- bus rails + taps
    raily={k:18+6*(nb-1-busidx[k]) for k in buses}
    drops={}   # (buskey,gapbase) -> (x, [ys])
    pend_entries=[]
    for nn,prs in nets.items():
        bk=busnets.get(nn)
        if not bk: continue
        for ref,pin in prs:
            x,y,side=pinxy(ref,pin)
            k=colof(ref)
            if ref=="J1": base=36
            else:
                l,r=gaps_for(k); base=r if side=="R" else l
            dx=base+busidx[bk]*2.2
            key=(bk,base)
            drops.setdefault(key,(dx,[]))[1].append(y)
            line(x,y,dx-1.0 if x<dx else dx+1.0,y)
            line(dx-1.0 if x<dx else dx+1.0,y,dx,y-1.0,0.65,GRN)
            pname=disp(pin if ref!="J1" else "")
            if ref!="J1" and pname!=nn:
                txt(x+(1.0 if side=="R" else -1.0),y+0.5,nn,1.3,GRN,right=(side=="L"))
            drawn.add((ref,pin))
    for (bk,base),(dx,ys) in drops.items():
        line(dx,raily[bk],dx,min(ys),1.9,GRN)
        dot(dx,raily[bk])
    for bk in buses:
        xs=[v[0] for (b2,_),v in drops.items() if b2==bk]
        if not xs: continue
        line(min(xs)-4,raily[bk],max(xs)+4,raily[bk],1.9,GRN)
        lo=min(int(re.match(r"^(.*?)(\d+)$",nn).group(2)) for nn in groups[bk])
        hi=max(int(re.match(r"^(.*?)(\d+)$",nn).group(2)) for nn in groups[bk])
        txt(min(xs)-5,raily[bk]+0.8,"%s[%d..%d]"%(disp(bk),lo,hi),1.9,GRN,bold=True,right=True)
    # ---- power + tracks
    # local elbow for 2-pin nets whose drops share a gap (avoids tall loops)
    elbow=set()
    for nn,prs in nets.items():
        if nn in busnets or nn in ("VCC","GND") or len(prs)!=2: continue
        (r1,p1),(r2,p2)=prs
        if r1=="J1" or r2=="J1": continue
        x1,y1,s1=pinxy(r1,p1); x2,y2,s2=pinxy(r2,p2)
        e1=x1+(1 if s1=="R" else -1)*4.5; e2=x2+(1 if s2=="R" else -1)*4.5
        if abs(e1-e2)<26:
            mx=(max(e1,e2) if (s1=="R" and s2=="R") else min(e1,e2) if (s1=="L" and s2=="L") else (e1+e2)/2)
            line(x1,y1,mx,y1); line(mx,y1,mx,y2); line(mx,y2,x2,y2)
            drawn.add((r1,p1)); drawn.add((r2,p2)); elbow.add(nn)
    tdrop={}
    for nn,prs in nets.items():
        if nn in busnets or nn in elbow: continue
        for ref,pin in prs:
            if ref=="J1" and nn in ("VCC","GND"):
                drawn.add((ref,pin)); continue   # consolidated rows below
            x,y,side=pinxy(ref,pin); d=1 if side=="R" else -1
            if nn=="VCC": vcc(x,y,d); drawn.add((ref,pin)); continue
            if nn=="GND": gnd(x,y,d); drawn.add((ref,pin)); continue
            ext=3.5+ (tidx[nn]%9)*1.27
            ty=TRACK0-GR*tidx[nn]
            line(x,y,x+d*ext,y); line(x+d*ext,y,x+d*ext,ty)
            tdrop.setdefault(nn,[]).append(x+d*ext)
            drawn.add((ref,pin))
    for nn,xs in tdrop.items():
        ty=TRACK0-GR*tidx[nn]; xs=sorted(xs)
        line(xs[0],ty,xs[-1],ty)
        txt(xs[0]-1.5,ty+0.5,nn,1.6,GRN,bold=True,right=True)
        for xx in xs[1:-1]: dot(xx,ty)
    # consolidated J1 power glyphs
    for i,row in enumerate(j1rows):
        if row and row[1]=="#VCC": vcc(18+5.08,-GR*i,1)
        if row and row[1]=="#GND": gnd(18+5.08,-GR*i,1)
    # ---- NC marks
    for ref in order:
        d=G.DEV[parts[ref][0]]
        for p in d["L"]+d["R"]:
            if (ref,p) not in pin2net:
                x,y,side=pinxy(ref,p); dd=1 if side=="R" else -1; e=x+dd*1.4
                line(e-1.0,y-1.0,e+1.0,y+1.0,0.7,BLK); line(e-1.0,y+1.0,e+1.0,y-1.0,0.7,BLK)
    # ---- coverage check
    want={rp for nn,prs in nets.items() for rp in prs}
    missing=want-drawn
    assert not missing, ("undrawn pins",sorted(missing)[:8])
    c.save()

if __name__=="__main__":
    # each card's PDF goes in its own hardware/<board>/ dir (name matches the board)
    for name,(title,parts,nets) in G.CARDS.items():
        outpdf=_os.path.join(_HW,name,"p8x-%s-schematic.pdf"%name)
        draw_card(name,title,parts,nets,outpdf)
        print("wrote",_os.path.basename(outpdf))
