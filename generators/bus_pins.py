#!/usr/bin/env python3
"""bus_pins.py -- the P8X bus pinout, one line per connector pin: CONNECTOR PIN SIGNAL.

    python3 generators/bus_pins.py              # a card's plug: J1, all 96 pins
    python3 generators/bus_pins.py --backplane  # the backplane's sockets J1..J8

It is the `bus_pins` command in each board's pcb-check.ini (~/Developer/pcb-check, the
check before any order): pcb-check compares every pin of the board's bus connector with
this list, so a card wired to the wrong bus line fails before it is made. The pinout is
gen_eagle.busnet(), the one definition the boards themselves are generated from; this
only prints it (importing gen_eagle writes nothing).
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_eagle  # noqa: E402

def main(argv):
    conns = ["J%d" % (i + 1) for i in range(gen_eagle.NSLOT)] if "--backplane" in argv else ["J1"]
    for c in conns:
        for pin in gen_eagle.ALLPINS:
            print("%s %s %s" % (c, pin, gen_eagle.busnet(pin)))

if __name__ == "__main__":
    main(sys.argv[1:])
