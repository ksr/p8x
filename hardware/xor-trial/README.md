# XOR Trial Board

A tiny standalone circuit to trial the workflow (and the parts): one **TTL XOR
gate**, two **push-button** inputs, and an **LED** on the output. Not part of the
P8X backplane — a breadboard-first "does this light up like the truth table says"
test. The LED is on when **exactly one** button is pressed (that is what XOR
means).

```
         +5V ─────────────┬───────────────┬───────────────┐
                          SW1             SW2              │
                        (press)         (press)           │ pin14 VCC
                           │               │              │
              1A ──────────┤               │              ┌┴┐ U1  74HC86
                           │        1B ────┤              │ │ (quad 2-in XOR;
              R1 10k       │        R2 10k │              │ │  use gate 1)
                           │               │              │ │
              GND ─[R1]────┤        GND ─[R2]────┐         └┬┘ pin7 GND
                           │                     │          │
                        (node 1A)            (node 1B)      │
                           │                     │          │
                    U1 pin1 (1A)          U1 pin2 (1B)      │
                           └──────►┌───────┐◄────┘          │
                                   │ XOR 1 │                │
                                   └───┬───┘                │
                                 U1 pin3 (1Y)               │
                                     │                      │
                                     ├──[ R3 330 ]──►|──────┘
                                     │              LED1   GND
                                   1Y output      (anode►|cathode)
```

## How it works

- **Buttons are active-high with pull-downs.** Each push-button connects its gate
  input to **+5 V when pressed**. A **10 kΩ resistor from the input to GND** (R1,
  R2) holds that input at a solid **0** when the button is released — so a floating
  input never reads as a random 1. Press = logic 1, release = logic 0.
- **The XOR gate** (U1 gate 1: inputs pin 1 & pin 2, output pin 3) drives its
  output **HIGH only when the two inputs differ** — i.e. exactly one button down.
- **The LED** hangs off the output through a **330 Ω** current-limiting resistor
  (R3): output HIGH → LED lights; output LOW → LED dark.

## Truth table (what you should see)

| SW1 | SW2 | 1Y (LED) |
|-----|-----|----------|
| off | off | **off**  |
| on  | off | **ON**   |
| off | on  | **ON**   |
| on  | on  | **off**  |

## Bill of materials

| Ref | Part | Value / notes |
|-----|------|---------------|
| U1 | 74HC86 | quad 2-input XOR (7486 is the classic bipolar-TTL equivalent; 74HC/HCT is the P8X house family and lower power) |
| SW1, SW2 | momentary push-button | SPST normally-open |
| R1, R2 | resistor | 10 kΩ — input pull-downs |
| R3 | resistor | 330 Ω — LED current limit (≈9 mA at 5 V) |
| LED1 | LED | any 3 mm / 5 mm; observe polarity (flat = cathode → GND) |
| C1 | ceramic capacitor | 100 nF — VCC↔GND decoupling across U1 (house rule; through-hole) |

## Wiring notes

- **Power** U1: pin 14 = +5 V, pin 7 = GND. Put **C1 (100 nF)** right across pins
  14↔7 — the P8X decoupling convention, and it keeps the gate from double-triggering
  on a noisy breadboard 5 V rail.
- **Tie off the three unused gates** so their CMOS inputs do not float: ground
  pins 4, 5 (gate 2), 9, 10 (gate 3), 12, 13 (gate 4). Their outputs (6, 8, 11)
  are left open. (On a 7486 bipolar part this matters less, but grounding unused
  inputs is good practice either way.)
- **Debounce, if it matters.** For a "watch the LED" trial, raw buttons are fine.
  If you later clock this into a flip-flop, add a small cap (e.g. 100 nF) across
  each button or an RC/Schmitt debounce — a bare button bounces for a few ms.

## If you want it as a real board

This is written for a breadboard. To turn it into a PCB in the P8X flow, say the
word and I'll add a `gen_eagle.py` entry (a small 1-IC board) so it generates a
`.sch`/`.brd` like the other cards — same generators-are-canon rule applies.

See `hardware/arduino-scratch/` for the existing scratch/experimental board and
the ECAD round-trip notes.
