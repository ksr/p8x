# P8X QA entry points: the same three targets as in YACC1-D, elf and P32W (2026-11-20).
# None of them changes a tracked file; a skipped test is reported, never counted as a pass.
# tools/qa.py says what each runs.
#
#   make qa-quick   ~3-7 min before every commit (emulator test-quick, the three co-sims, netlist ERC)
#   make qa         ~40 min  the whole suite, before an order (emulator make test, co-sims, ERC)
#   make qa-fresh   ~1.5 min every committed generated file against a fresh build (in a temp copy)
#
# The builds themselves stay where they are: emulator/Makefile, fpga/, generators/build.sh.

.PHONY: qa-quick qa qa-fresh

qa-quick:
	python3 tools/qa.py quick

qa:
	python3 tools/qa.py full

qa-fresh:
	python3 tools/qa.py fresh
