# solveig-sdl -- an SDL2 surface for Solum, loaded at run time.
#
#   make                build build/sdl.so
#   make run            build it and run examples/bounce.sol
#   make bounce         the same, said by name
#   make circles        build it and run examples/circles.sol
#   make mandelbrot     build it and run examples/mandelbrot.sol
#   make pong           build it and play
#   make breakout       build it and play the second game
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

# The Solveig this is being built against, read from the same header the
# binaries report their version out of.
#
# Checked rather than assumed because the failure it prevents is unhelpful: an
# older checkout has no solum/extend.h at all, so the compiler says a header is
# missing and says nothing about why. The version says why.
#
# The run-time half is separate and stays separate: SOL_EXTENSION_ABI is
# compared when the bundle loads, and catches a Solveig whose structs moved
# under a bundle that was built earlier. This check is only "does this Solveig
# have an extension interface at all".
SOLVEIG_MINIMUM = 0.36.0
SOLVEIG_VERSION = $(shell grep SOLUM_VERSION \
                    $(SOLVEIG)/solum/include/solum/common.h 2>/dev/null \
                    | tr -d '"' | awk '{print $$3}')

INCLUDES = -I$(SOLVEIG)/solum/include

TARGET = $(BUILD)/sdl.so

.PHONY: all run bounce circles mandelbrot pong breakout clean check

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
	@test -n "$(SOLVEIG_VERSION)" || \
	    { echo "solveig-sdl: $(SOLVEIG) is not a Solveig checkout."; \
	      echo "      make SOLVEIG=/path/to/Solveig"; exit 1; }
	@echo "$(SOLVEIG_VERSION) $(SOLVEIG_MINIMUM)" \
	    | awk '{ split($$1, a, "."); split($$2, b, "."); \
	             exit !(a[1] > b[1] || (a[1] == b[1] && a[2] >= b[2])) }' || \
	    { echo "solveig-sdl: found Solveig $(SOLVEIG_VERSION) under $(SOLVEIG),"; \
	      echo "  and this needs $(SOLVEIG_MINIMUM) or later."; \
	      echo "  Update that checkout, or point SOLVEIG at a newer one."; exit 1; }

# `run` is the habit; `bounce` is what the example is called, and reaching for
# the name rather than the habit should not be an error.
run bounce: all
	$(SOLVEIG)/bin/solis --extension=$(TARGET) examples/bounce.sol

# Bouncing discs, drawn out of lines because there is no circle message.
circles: all
	$(SOLVEIG)/bin/solis --extension=$(TARGET) examples/circles.sol

# The other example. It wants an optimised Solveig -- see the note in the file.
mandelbrot: all
	$(SOLVEIG)/bin/solis --extension=$(TARGET) examples/mandelbrot.sol

# The game the reference says this binding can write, written to check it.
pong: all
	$(SOLVEIG)/bin/solis --extension=$(TARGET) examples/pong.sol

# The second game, written whole rather than over Pong's parts, so that what
# the two share can be read off rather than guessed at.
breakout: all
	$(SOLVEIG)/bin/solis --extension=$(TARGET) examples/breakout.sol

clean:
	rm -rf $(BUILD)
