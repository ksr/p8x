#!/usr/bin/env python3
"""Consolidated, orderable bill of materials for the whole P8X.

Reads the canonical in-memory device data from gen_eagle (CARDS + the backplane
parts) — so it uses the real chip type, not the schematic label — maps each
device to an orderable part, aggregates across all 7 boards, and writes a CSV +
prints a summary, a DIP-socket count, and sourcing notes.

NO live DigiKey part numbers are invented. The 'Part' column gives the standard
generic device; verify exact orderable parts, package, logic family and stock
on DigiKey yourself. Hard-to-source parts are flagged in 'Notes'."""
import os, sys, csv, re, collections
_HERE=os.path.dirname(os.path.abspath(__file__))
_HW=os.path.join(os.path.dirname(_HERE),"hardware")
sys.path.insert(0,_HERE)
os.chdir(_HW)                      # gen_eagle writes boards relative to CWD
import gen_eagle as G

# device -> orderable part (generic). HCT assumed throughout (5V TTL-compatible).
LOGIC={"74377V2":"74HCT377","74244":"74HCT244","74245":"74HCT245","74181":"74HCT181",
 "74182":"74HCT182","74157":"74HCT157","74151":"74HCT151","74138":"74HCT138",
 "74139":"74HCT139","74161":"74HCT161","74169":"74HCT169","74374":"74HCT374",
 "74175":"74HCT175","74260":"74HCT260","74257":"74HCT257","7430":"74HCT30",
 "7410":"74HCT10","7402":"74HCT02","7474":"74HCT74","HEX14":"74HCT14"}
NOTE={"74HCT181":"ALU slice — HCT uncommon; may need 74F181/NOS","74HCT182":"look-ahead carry — uncommon; 74F182/NOS",
 "74HCT260":"dual 5-in NOR — uncommon; verify HCT avail or NOS",
 "MC6850":"ACIA — OBSOLETE, source NOS (eBay/specialist)","AT28C256":"parallel EEPROM 32Kx8, 150ns",
 "62256 SRAM":"32Kx8 SRAM (e.g. AS6C62256-55)","AT28C64":"parallel EEPROM 8Kx8 (microcode ROMs)",
 "MAX232":"RS-232 level shifter (+ its 1uF caps)","DS1302":"RTC (DNP option)"}

def part(dev,val):
    """-> (orderable part, category, package)."""
    pkg=G.DEV[dev]["pkg"]; v=val.upper()
    if dev in LOGIC: return LOGIC[dev],"Logic IC",pkg
    if dev=="GATES14":
        m=re.search(r"74HCT(00|08|32|86)",v); return ("74HCT"+m.group(1)) if m else "74HCT??","Logic IC",pkg
    if dev=="28C64":   return "AT28C64","Memory IC",pkg
    if dev=="MEM28K8": return ("AT28C256" if "28C256" in v else "62256 SRAM"),"Memory IC",pkg
    if dev=="6850":    return "MC6850","Peripheral IC",pkg
    if dev=="MAX232":  return "MAX232","Peripheral IC",pkg
    if dev=="DS1302":  return "DS1302","Peripheral IC",pkg
    if dev=="OSC":     return "%s full-can oscillator"%val,"Oscillator",pkg
    if dev=="XTAL32":  return "32.768kHz crystal","Crystal",pkg
    if dev=="COIN":    return "CR2032 coin-cell holder","Battery",pkg
    if dev=="RES":     return "Resistor %s"%val,"Resistor",pkg
    if dev=="CAP":     return "Ceramic cap %s"%val,"Capacitor",pkg
    if dev=="CAPP":    return "Electrolytic cap %s"%val,"Capacitor",pkg
    if dev=="SIP9":    return "Resistor network %s (bussed, 9-pin SIP)"%val,"Resistor network",pkg
    if dev=="RNISO8":  return "Resistor network %s (isolated, SIP)"%val,"Resistor network",pkg
    if dev=="LED":
        col={"GRN":"green","YEL":"yellow","RED":"red"}.get((re.search(r"(GRN|YEL|RED)$",v) or [None,""])[0] if re.search(r"(GRN|YEL|RED)$",v) else "","")
        col=next((c for k,c in (("GRN","green"),("YEL","yellow"),("RED","red")) if v.endswith(k)),"green")
        return "LED 3mm %s"%col,"LED",pkg
    if dev=="LEDARR8": return "LED bar array, 8-segment (DIP)","LED",pkg
    if dev=="DIP8SW":  return "DIP switch, 8-position","Switch",pkg
    if dev=="SW2":     return "Switch SPST (momentary/toggle)","Switch",pkg
    if dev=="DIN96":   return ("DIN41612 96-pin male R/A (card)" if "96M" in v else
                               "DIN41612 96-pin female R/A (backplane)"),"Connector",pkg
    if dev=="IDE40":   return "40-pin boxed header (IDC, CF/IDE)","Connector",pkg
    if dev in ("HDR3","HDR4","HDR40"): return "Pin header %s-pin 0.1in"%dev[3:],"Connector",pkg
    if dev=="TB4":     return "Terminal block, 4-pos 5mm","Connector",pkg
    return val or dev,"Other",pkg

SOCK={"DIP8":"8","DIP14":"14","DIP16":"16","DIP20":"20","DIP24W":"24 (0.6in wide)","DIP28W":"28 (0.6in wide)"}

def main():
    agg=collections.defaultdict(lambda:{"qty":0,"refs":[]})
    socks=collections.Counter(); socks_dnp=collections.Counter()
    boards=[(n,G.CARDS[n][1]) for n in G.CARDS]+[("backplane",G.bpb)]
    for bname,parts in boards:
        bn=bname.split("-")[0]
        for ref,pv in parts.items():
            dev,val=pv[0],pv[1]; dnp="DNP" in val.upper()
            p,cat,pkg=part(dev,val)
            k=(cat,p,pkg,dnp)                       # DNP in the key: never merge populate+DNP
            a=agg[k]; a["qty"]+=1; a["refs"].append("%s:%s"%(bn,ref))
            if pkg in SOCK: (socks_dnp if dnp else socks)[pkg]+=1
    out=os.path.join(_HW,"p8x-bom.csv")
    with open(out,"w",newline="") as f:
        w=csv.writer(f); w.writerow(["Qty","Part (generic — verify on DigiKey)","Package","Category","Populate","Notes","RefDes"])
        for (cat,p,pkg,dnp),a in sorted(agg.items(),key=lambda kv:(kv[0][3],kv[0][0],kv[0][1])):
            w.writerow([a["qty"],p,pkg,cat,"DNP" if dnp else "yes",NOTE.get(p,""),
                        " ".join(sorted(a["refs"]))])
    pop=sum(a["qty"] for (c,p,pk,d),a in agg.items() if not d)
    print("P8X BOM ->",out)
    print("  %d line items, %d parts to populate + %d DNP-option parts"
          %(len(agg),pop,sum(a["qty"] for (c,p,pk,d),a in agg.items() if d)))
    print("  DIP sockets to populate (1 per IC, recommended):")
    for pkg,q in sorted(socks.items()): print("    %-7s x %d   (%s-pin socket)"%(pkg,q,SOCK[pkg]))
    if socks_dnp: print("    + DNP-option:", dict(socks_dnp))

if __name__=="__main__": main()
