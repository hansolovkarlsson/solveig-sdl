# solveig-sdl -- an SDL2 surface for Solum, loaded at run time.
#
#   make                build build/sdl.so
#   make run            build it and run examples/bounce.sol
#   make clean
#
# This is an *extension*, so it is not part of Solveig and does not build with
# it. That separation is the point rather than an inconvenience: Solveig's front
# page says "no dependencies beyond a C11 compiler and make", and it stays true
# because SDL lives here. Nothing in Solveig's CI needs SDL to be installed.

SOLVEIG ?= ../Solveig

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Wpedantic -g -fPIC
BUILD    = build

# `-std=c11` asks for ISO C and nothing besides, which hides `setenv` and
# friends on glibc. Solveig's Makefile carries the same two lines for the same
# reason; an extension is a C file like any other.
ifeq ($(shell uname -s),Darwin)
STANDARD = -D_DARWIN_C_SOURCE
# A bundle leaves `sol_*` unresolved for solvm to satisfy. ELF does that by
# default; Mach-O has to be told, and refuses to link otherwise.
BUNDLE_LD = -Wl,-undefined,dynamic_lookup
else
STANDARD = -D_XOPEN_SOURCE=700
BUNDLE_LD =
endif

# `-isystem` rather than `-I`, which is what pkg-config hands back: the compiler
# then knows the headers are not ours and stays quiet about anything they do
# that `-Wpedantic` dislikes, while still warning about everything in src/.
SDL_CFLAGS = $(shell pkg-config --cflags sdl2 | sed 's/-I/-isystem /g')
SDL_LIBS   = $(shell pkg-config --libs sdl2)

INCLUDES = -I$(SOLVEIG)/solum/include

TARGET = $(BUILD)/sdl.so

.PHONY: all run clean check

all: $(TARGET)

$(TARGET): src/sdl.c | check
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(STANDARD) $(INCLUDES) $(SDL_CFLAGS) -shared \
	    $< -o $@ $(SDL_LIBS) $(BUNDLE_LD)

# Said once, here, because the two ways this goes wrong both produce compiler
# errors that do not name the cause.
check:
	@pkg-config --exists sdl2 || \
	    { echo "solveig-sdl: sdl2 not found by pkg-config."; \
	      echo "  macOS:  brew install sdl2"; \
	      echo "  Debian: apt install libsdl2-dev"; exit 1; }
	@test -f $(SOLVEIG)/solum/include/solum/extend.h || \
	    { echo "solveig-sdl: no solum/extend.h under $(SOLVEIG)."; \
	      echo "  Set SOLVEIG to a checkout of Solveig 0.36.0 or later:"; \
	      echo "      make SOLVEIG=/path/to/Solveig"; exit 1; }

run: all
	$(SOLVEIG)/bin/solis --extension=$(TARGET) examples/bounce.sol

clean:
	rm -rf $(BUILD)
