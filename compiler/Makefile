# Build the native P8X C cross-compiler from the small-C codebase.
#
# p8cc.c is the compiler written in p8cc's own subset; built with the host cc it
# becomes a fast native cross-compiler (host -> P8X asm).  Its asm differs from
# p8cc.py's in incidental ways (label names, arg-push order) but is BEHAVIOURALLY
# equivalent — programs run to identical output (emulator/test/c_selfhost_test.sh
# proves this differentially).
# The raw binary is a stdin->stdout filter (the in-subset source can only use
# getchar/putchar); the `p8cc-host` wrapper gives it p8cc.py's file interface.

CC      ?= cc
CFLAGS  ?= -O2 -w
BIN      = p8cc-host.bin

all: $(BIN)

$(BIN): p8cc.c
	$(CC) $(CFLAGS) p8cc.c -o $(BIN)

clean:
	rm -f $(BIN)

.PHONY: all clean
