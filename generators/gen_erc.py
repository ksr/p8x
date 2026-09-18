#!/usr/bin/env python3
"""gen_erc.py -- netlist-level Electrical Rules Check for the P8X cards.

    python3 generators/gen_erc.py            # check every card in gen_eagle.CARDS
    python3 generators/gen_erc.py io-card    # check one card

This validates the AS-DRAWN board wiring electrically, WITHOUT needing a KiCad
schematic: it works straight off the gen_eagle netlists + a per-device pin-role
table. It catches the electrical mistakes ERC exists to catch:

  * output contention  -- two push-pull outputs shorted on one net
  * undriven net       -- a net with only inputs, nothing drives it
  * floating pin       -- a device pin that is in no net (or a 1-pin net)
  * unpowered IC       -- a logic chip whose VCC/GND pins are not on the rails

Pins are classified from ROLE below: 'O' push-pull output, 'T' tri-state /
open-collector output, 'B' bidirectional (bus / MCU GPIO / RAM I/O -- may drive
OR listen), 'P' passive/connector/external (a wire to the outside world or an
R/C/LED -- never flagged), 'C' power (VCC/GND). Everything not listed is an
INPUT. GENERATORS ARE CANON -- fix the generator, not the board.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_eagle as GE
DEV = GE.DEV

# --- per-device OUTPUT pins (everything else non-power is an input) ----------
# value 'O' = push-pull output, 'T' = tri-state/open-collector output.
OUT = {
 "7430":   {"Y":"O"},
 "74138":  {**{f"Y{i}":"O" for i in range(8)}},
 "74139":  {**{f"1Y{i}":"O" for i in range(4)}, **{f"2Y{i}":"O" for i in range(4)}},
 "GATES14":{f"{g}Y":"O" for g in "1234"},              # 7400/7408/7432/7486 (function varies by value)
 "HEX14":  {f"{g}Y":"O" for g in "123456"},            # 74x14 inverters
 "7402":   {f"{g}Y":"O" for g in "1234"},
 "7410":   {f"{g}Y":"O" for g in "123"},
 "7474":   {"1Q":"O","!1Q":"O","2Q":"O","!2Q":"O"},
 "74161":  {"QA":"O","QB":"O","QC":"O","QD":"O","RCO":"O"},
 "74169":  {"QA":"O","QB":"O","QC":"O","QD":"O","!RCO":"O"},
 "74151":  {"Y":"O","!W":"O"},
 "74157":  {f"Y{i}":"O" for i in range(1,5)},
 "74257":  {f"Y{i}":"T" for i in range(1,5)},          # tri-state mux
 "74175":  {**{f"Q{i}":"O" for i in range(1,5)}, **{f"!Q{i}":"O" for i in range(1,5)}},
 "74260":  {"Y1":"O","Y2":"O"},
 "74181":  {"F0":"O","F1":"O","F2":"O","F3":"O","CN4":"O","!P":"O","!G":"O","AEB":"O"},
 "74182":  {"CNX":"O","CNY":"O","CNZ":"O","!P":"O","!G":"O"},
 "74244":  {f"Y{i}":"T" for i in range(1,9)},          # tri-state buffer
 "74374":  {f"Q{i}":"T" for i in range(1,9)},          # tri-state FF
 "74377V2":{f"Q{i}":"O" for i in range(1,9)},
 "74688":  {"!PEQ":"O"},
 "6850":   {"TXD":"O","!IRQ":"T","!RTS":"O"},          # !IRQ open-drain; D0-7 handled as bus below
 "MAX232": {"T1OUT":"O","T2OUT":"O","R1OUT":"O","R2OUT":"O","VP":"O","VM":"O"},
 "OSC":    {"OUT":"O"},
}
# whole devices whose signal pins are all bidirectional buses (may drive or listen)
BUS_DEV = {"74245","28C64","MEM28K8","MCP23S17","DS1302","ATMEGA328"}
# 6850 D0-D7 are a bidirectional data bus
BUS_PINS = {"6850": {f"D{i}" for i in range(8)}}
# whole devices that are passive / external connectors / discretes -> never flagged
PASSIVE_DEV = {"CAP","CAP1","COIN","XTAL32","RES","LED","SIP9","RNISO8","RNISO8D",
 "LEDARR8","DIP8SW","SW2","DIN96C","IDE40","DSUB9F","MINIDIN6","JMP2X3",
 "HDR3","HDR4","HDR10","PICO"}
POWER_PINS = {"VCC","GND","VDD","VSS","VCC1","VCC2","AVCC","GND2"}

def role(dev, pin):
    if dev in PASSIVE_DEV: return "P"
    if pin in POWER_PINS:  return "C"
    if dev in BUS_DEV:     return "B"
    if pin in BUS_PINS.get(dev, ()): return "B"
    o = OUT.get(dev, {})
    if pin in o: return o[pin]     # 'O' or 'T'
    return "I"                      # default: input

def check(name):
    """Return (errors, warns). ERRORS are real electrical faults; WARNS are
    floating INPUTS worth an eyeball (usually intentional spare-gate inputs)."""
    title, parts, nets = GE.CARDS[name]
    errors, warns = [], []
    pinnet = {}
    for net, mem in nets.items():
        for (ref, pin) in mem: pinnet[(ref, pin)] = net
    # 1. contention + undriven, per net (the real faults)
    for net, mem in nets.items():
        if net in ("VCC","GND"): continue
        mm = [(r,p) for (r,p) in mem if r in parts]
        roles = [role(parts[r][0], p) for (r,p) in mm]
        pp = [(r,p) for (r,p) in mm if role(parts[r][0],p)=="O"]
        drivers = [x for x in roles if x in ("O","T","B","P")]
        loads   = [x for x in roles if x == "I"]
        if len(pp) >= 2:
            errors.append(("contention", "%s: %d push-pull outputs shorted (%s)" % (net,
                len(pp), ", ".join("%s.%s"%(r,p) for r,p in pp))))
        if loads and not drivers:
            errors.append(("undriven", "%s: %d input(s) but no driver" % (net, len(loads))))
    # 2. unpowered ICs
    vcc = {r for (r,p) in nets.get("VCC",[])}; gnd = {r for (r,p) in nets.get("GND",[])}
    for ref,(dev,val) in parts.items():
        d = DEV.get(dev)
        if not d or dev in PASSIVE_DEV: continue
        pins = d["L"]+d["R"]
        if "VCC" in pins and ref not in vcc: errors.append(("unpowered","%s VCC floating"%ref))
        if "GND" in pins and ref not in gnd: errors.append(("unpowered","%s GND floating"%ref))
    # 3. floating INPUT pins only (unconnected outputs are normal spares -> ignored)
    for ref,(dev,val) in parts.items():
        if dev in PASSIVE_DEV or dev in BUS_DEV: continue
        d = DEV.get(dev)
        if not d: continue
        for pin in d["L"]+d["R"]:
            if pin.upper().startswith("NC"): continue    # no-connect-by-design pins
            if role(dev,pin)=="I" and (ref,pin) not in pinnet:
                warns.append("%s.%s (%s) input floating"%(ref,pin,dev))
    return errors, warns

def main():
    which = sys.argv[1:] or sorted(GE.CARDS)
    te = tw = 0
    for name in which:
        if name not in GE.CARDS: print("?? no such card:", name); continue
        errors, warns = check(name); te += len(errors); tw += len(warns)
        status = "CLEAN" if not errors else "%d ERROR(S)" % len(errors)
        print("%-16s %-12s (%d input-floating warnings)" % (name, status, len(warns)))
        for kind, msg in errors:
            print("   ERROR [%-11s] %s" % (kind, msg))
        for w in warns[:6]:
            print("   warn  [floating-in ] %s" % w)
        if len(warns) > 6: print("   warn  ... +%d more floating inputs (usually spare gates)" % (len(warns)-6))
    print("\n== ERC: %d ERROR(s), %d input-floating warning(s) across %d card(s) ==" % (te, tw, len(which)))
    print("Errors are real faults (output contention / undriven net / unpowered IC).")
    print("Warnings are unconnected INPUTs -- review for intent (most are spare-gate inputs).")
    return 1 if te else 0

if __name__ == "__main__":
    sys.exit(main())
