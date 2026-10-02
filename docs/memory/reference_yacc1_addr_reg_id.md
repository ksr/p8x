---
name: reference-yacc1-addr-reg-id
description: YACC1 bus pins C3-C6 - Bus V3.0/V3.1 (<=2020-08) called them -ADDR-REG-RD0/LD0/RD1/LD1 for the retired "Address and TMP" card; Bus V3.2 (2020-11) renamed them ADDR-REG-ID0..3 (index-register number) which is what the built machine, microcode and tester use; Blank V3.1 template still has the OLD names
metadata:
  type: reference
---

Two generations of bus naming for connector pins -C3..-C6:
- Bus Template V3.0/V3.1 (files dated 2020-08-23): -ADDR-REG-RD0 (C3), -ADDR-REG-LD0 (C4), -ADDR-REG-RD1 (C5),
  -ADDR-REG-LD1 (C6) = separate load/read strobes for two address registers on the "Address and TMP V1.0" card
  (fabricated, retired 2021-01, now hardware/cards/address-tmp/eagle/deprecated/).
- Bus Template V3.2 (2020-11-29): ADDR-REG-ID0..3, active-high 4-bit index-register number. Sequencer-logic
  drives them from microcode (uCode-Generator2 setRegBit("ADDR-REG-IDn", reg & 0xF)); Index Registers card
  IC38 (dual 2-to-4 decoder) uses bits 0-1 for R0..R3 on-card and bits 2-3 via jumper J3 for card select.
  Built ALU V3.2, Registers 1.1, IO 1.1 (Production, 2020-11-29), Seq-Logic 2.1, Arduino signal table,
  microcode all use this. This is the machine.
Stale old-name carriers: Blank V3.1 template (never updated to V3.2 naming!), so Mem Switch V1.1, Mem Register
V1.0, Video 1.0 (2026, Fusion) and the IO 1.1 draft of 2020-08 (hardware/cards/io/eagle/v1.1-draft-2020-08)
show RD/LD on C3-C6 without using them; ALU V3.3's bus ribbon label too. Memory v1.3 writes "-ADDR-REG-ID"
(spurious dash). NOT related to the 16-bit work: ALU V3.3-16 (2021-09) keeps ADDR-REG-ID0..3.
**How to apply:** canonical bus table = V3.2 names; fix Blank V3.1 (or make a Blank V3.2) before drawing new
cards; never read the RD/LD names as a newer scheme. See [[project-yacc1]], [[project-yacc1-kicad]].
