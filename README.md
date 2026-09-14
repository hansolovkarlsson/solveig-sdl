# solveig-sdl

An SDL2 surface for [Solveig](https://github.com/hansolovkarlsson/Solveig), loaded
at run time.

```sh
make
../Solveig/bin/solvm --extension=build/sdl.so examples/bounce.sob
```

```
sdl:start.
screen := sdl:window("bounce", #640, #480).

{ running }:whileTrue({
    { event := sdl:poll. event:notNil }:whileTrue({
        event:kind:equals('quit):ifTrue({ running := false }) }).

    x := @expr(x + dx).
    @expr(x < #0 | x > #600):ifTrue({ dx := dx:negated }).

    sdl:clear(screen, #20, #20, #30).
    sdl:colour(screen, #240, #180, #60).
    sdl:fill(screen, x, y, #40, #40).
    sdl:present(screen).
    sdl:wait(#16) }).
```

## It is not shaped like solveig-gtk, on purpose

[solveig-gtk](https://github.com/hansolovkarlsson/solveig-gtk) is the sister
bundle, and the two look nothing alike because the toolkits do not.

**GTK owns the loop and calls into your program.** So it has `gtk:run`, and
`gtk:onClick(button, block)`, and every block it holds has to be kept alive
across collections.

**SDL hands your program a frame and gets out of the way.** So there is no
`sdl:run`, no callback, and nothing registered with anything. The loop is an
ordinary `whileTrue` and `sdl:poll` answers the next event or `nil`.

The temptation was to give SDL a `run(block)` so the two would match. Solveig's
own notes argue against it: a back end that borrows another's vocabulary makes
every later back end emulate a toolkit it has nothing to do with. A Plan 9
`draw` binding would be shaped like this one, not like the GTK one.

**And this is the check on a decision made in the VM.** Solveig's retain
registry was built as *a service an extension may use, not the shape an
extension takes*. This extension uses none of it. Had callbacks been the shape,
every file here would be working around it.

## Building

Needs SDL2 and **[Solveig 0.36.0](https://github.com/hansolovkarlsson/Solveig/releases/tag/v0.36.0)
or later** — the release the extension interface arrived in.

Either a clone or the release tarball will do. The build reads headers straight
out of the tree, so an unpacked `solveig-0.36.0/` works as `SOLVEIG` with
nothing else done to it:

```sh
curl -LO https://github.com/hansolovkarlsson/Solveig/releases/download/v0.36.0/solveig-0.36.0.tar.gz
tar xzf solveig-0.36.0.tar.gz && make -C solveig-0.36.0

brew install sdl2                 # macOS
apt install libsdl2-dev          # Debian, Ubuntu

make SOLVEIG=solveig-0.36.0       # -> build/sdl.so;  default is ../Solveig
make run SOLVEIG=solveig-0.36.0   # build and bounce a ball
```

**The version is checked rather than taken on trust**, because the failure it
prevents is unhelpful: an older checkout has no `solum/extend.h` at all, so the
compiler says a header is missing and says nothing about why.

```
solveig-sdl: found Solveig 0.35.0 under ../Solveig,
  and this needs 0.36.0 or later.
  Update that checkout, or point SOLVEIG at a newer one.
```

A missing SDL2 is named the same way rather than left to the compiler.

**That is a build-time check for one thing only** — *is there an extension
interface at all*. The run-time half is separate and stays separate: a bundle is
per-platform and per-build, and `SOL_EXTENSION_ABI` is compared for equality
when it loads, never guessed, since `SolValue` is passed by value and
`SolObject`'s layout is exposed. So rebuild this whenever `solvm` is rebuilt
from a newer Solveig:

```
solvm: cannot load extension build/sdl.so: refused ABI 1 --
built against a different SolVM, rebuild it against this one
```

You never rebuild `solvm` to add an extension. You do rebuild extensions when
`solvm` changes.

## The seven examples, and the engine under four of them

| | |
| --- | --- |
| [`examples/bounce.sol`](examples/bounce.sol) | a ball, a wall, and the smallest loop that owns itself |
| [`examples/circles.sol`](examples/circles.sol) | bouncing discs — click to add one, space to clear, Escape to quit |
| [`examples/mandelbrot.sol`](examples/mandelbrot.sol) | an explorer — click to zoom in, right-click out, `r` to reset, Escape to quit |
| [`examples/pong.sol`](examples/pong.sol) | the game: `W`/`S` and `Up`/`Down`, `C` hands a paddle to the machine, Space serves, first to eleven |
| [`examples/breakout.sol`](examples/breakout.sol) | the second game: `Left`/`Right` or the mouse, Space serves, three balls, the 1976 rules |
| [`examples/asteroids.sol`](examples/asteroids.sol) | the third game: turn, thrust, fire, hyperspace; rocks that split, both saucers, the 1979 rules |
| [`examples/invaders.sol`](examples/invaders.sol) | the fourth game: fifty-five invaders, four bunkers that erode, the mystery ship, the 1978 rules |
| [`examples/engine.sol`](examples/engine.sol) | what the games have in common: the frame, held keys, a sprite and the font, a rect, a mover and a ball, a tone and its channel |
| [`examples/kit.sol`](examples/kit.sol) | what they share that a third game might not: the wall bounce and the paddle angle |

```sh
../Solveig/bin/solas examples/mandelbrot.sol -o examples/mandelbrot.sob
../Solveig/bin/solvm --extension=build/sdl.so examples/mandelbrot.sob
```

**`circles.sol` draws a shape this binding does not have.** There is no
`sdl:circle`: the drawing messages are rectangles and lines, so a disc is
something the program works out — for each of its rows, half the width is the
square root of `r² - dy²`, and that row is one `sdl:line`. Six lines of Solveig,
about sixty calls for a ball of thirty.

It stays that way deliberately. A `circle` message would be a few dozen lines of
C and no program had asked for one until that file. **One customer, satisfied in
six lines of the language, is not a reason to grow a surface** — every later back
end would then have to match it, and a `draw`-style binding has no circle to
match with.

**The Mandelbrot is the one that says something about this binding**, and two
things in it are worth reading for reasons that are not the fractal.

**A frame is all or nothing.** `sdl:present` waits for the display — about 8ms
here — but the thing worth knowing is that it does not *keep* what was drawn:
the buffer handed back for the next frame holds undefined memory, not the
picture just shown. So a half-drawn picture cannot be shown at all. The first
version of this example presented every 16ms to show progress and drew bands of
stale video memory with fractal in between, which is what the noise was.
**Nothing is presented until a pass has covered every pixel.**

**So it draws the whole picture five times, coarse to fine** — 16×16 blocks,
then 8, 4, 2, 1. Each pass is a complete frame and can therefore be shown; the
first costs a 256th of the last and is up in about ten milliseconds. That is how
it feels progressive without ever presenting a partial frame.

A click still never waits for a finished render, because each pass drains the
queue between rows and an abandoned pass is dropped rather than shown. That is
`sdl:poll` answering `nil` doing the job it exists for: the program decides when
to look, and nothing calls back into it.

Both want an optimised Solveig. The default `make` there is `-g` with no
optimiser, and the five passes take 10.2 seconds against 2.2.

**`pong.sol` is the sentence at the end of this file, checked.** The reference
said *you can write Pong*, and the way to find out whether eleven messages are
enough for a game is to write one over them and add nothing. Two of the three
things the game wanted and the binding lacked took a few lines of the program:
the score is a 3×5 cell font out of `sdl:fill`, which is how the original drew
its digits, and a held key is four booleans kept from `'keyDown` and `'keyUp`,
since there is no keyboard state to ask for. The third could not be written in
the language at all, and it is the twelfth message: `sdl:beep` is the square
wave the original made, and the game's three tones are its pitches and
lengths. That is the trigger this file's last section names, met for the
first time. The machine plays the right paddle until `C` hands it over, and it
follows the ball a little slower than the ball can be made to go, which is
what makes it beatable.

**`breakout.sol` is the second game, and it added nothing to `sdl.c`.** The
1976 rules over the same twelve messages: four speed-ups, a paddle halved by
the top wall, a second wall once. It was first written whole, sharing nothing
with Pong on purpose, because the engine was defined as *what is left after the
second game* and the way to read that off is two whole games side by side
rather than one game and a library extracted from a sample of one. Nothing
plays it for you; a self-playing copy was used to check the physics and thrown
away.

**`engine.sol` and `kit.sol` are what was left.** Read against each other, the
two games shared five things and a tone, none of them C: the frame (open a
window, drain the queue, show a frame, and the loop stays the program's own),
held keys as a fact the program keeps, the 3×5 cell font both scores were drawn
with, a rectangle with the overlap test that had been written four times, and a
ball whose float position has an integer shadow crossed in one place. That is
`engine.sol`, about a hundred lines of code. What Pong and Breakout share that
Asteroids would not want, a wall bounce and the paddle-angle formula, is
`kit.sol` beside it and not the bottom of it. Both games were then rewritten
over the two files and lost a hundred lines each, 290 to 184 and 339 to 232;
the engine and kit are 238 lines with their headers, so the whole is a few
lines longer than the two games were and every line of it is written once.
Nothing here draws a sprite, mixes a sample or owns a scene, because neither
game asked, and the rule at the end of this file applies at the engine's
boundary too.

**`asteroids.sol` is the third game, and the first to test the engine's
boundary rather than the binding's.** It was written over `engine.sol` from
the start, with a prediction in its header of what would carry over: four of
the six names (`engine`, `keys`, `font`, `tone`), and neither `rect` nor
`ball`, since nothing in Asteroids is a box and everything wraps. The
prediction held. The file defines its own moving `thing`, a float position
with a radius rather than a box, and everything on the screen delegates to it;
a shape is a list of unit points drawn as `sdl:line`s after one rotation and
one scale, so a rock is nine lines and never a `fill`. The binding was asked
for nothing: the trigonometry is the machine's, and the continuous sounds, the
thrust, the siren and the heartbeat, are `sdl:beep` asked for again from the
frame, yielding to anything that just happened. The reading of three files
that followed found the seam: neither `ball` nor `thing` is the other's special
case, but both are a `mover`, four slots and two lines, which is in `engine.sol`
now with both delegating to it. `thing`, the line drawing and the one-channel
sound policy stay in `asteroids.sol` until a second game wants them.

**`invaders.sol` is the fourth game, and the one the first reading said
would push on the binding**, because an invader is a picture and nothing here
draws a picture. It did not. The header predicted, before the body was
written, that a picture at this scale is rows of text compiled once to
horizontal runs, that a run is one `sdl:fill`, and that fifty-five invaders
and four eroding bunkers would fit the frame that way; and named what would be
asked for if they did not, *a bitmap in one call*, not a texture. Measured:
26,913 frames of a self-playing game in 14.6 seconds on the `-g` build with
SDL's dummy renderer, about half a millisecond a frame against the sixteen
available. So the trigger was not met, by a number rather than a guess, and
the twelve messages stand after four games. The block moves one invader a
frame, which is where the original's ripple and its quickening both come from
and costs nothing to write; a bunker is cells and a sprite rebuilt from them
when bitten. The reading of four that followed moved three things into the
engine: the sprite, because the font had been one drawn the slow way since the
first game and is ten sprites now; `alive` on a rect, which three games had
written for themselves; and `tone:hum`, the one-channel policy Asteroids and
Invaders had written the same way. Everything else in this file stays its own.

## Reference

Twelve messages, eleven of them distinct. Everything that draws answers the
screen, so calls chain.

### Opening

| | |
| --- | --- |
| `sdl:start` | Opens SDL's video subsystem, and turns SDL's text-input mode off, since nothing here answers a text-input event and on macOS the mode is what makes a held key raise the accent popup instead of repeating. Answers `true`, or fails with SDL's own message. Calling it twice is harmless; `poll`, `ticks` and `window` fail until it has been called. |
| `sdl:window(title, #width, #height)` | A window and the renderer that draws into it, as one **screen** — `<sdl screen>` when printed. Falls back to software rendering where there is no acceleration, which is what a headless run gets. |

### Drawing

A frame is: clear it, choose a colour, draw, present it.

| | |
| --- | --- |
| `sdl:clear(screen, #r, #g, #b)` | Fills the whole screen and sets the draw colour. |
| `sdl:colour(screen, #r, #g, #b)` | What the next `fill` or `line` uses. `sdl:color` is the same message. |
| `sdl:fill(screen, #x, #y, #width, #height)` | A solid rectangle. |
| `sdl:line(screen, #x1, #y1, #x2, #y2)` | |
| `sdl:present(screen)` | Shows the frame just drawn. Nothing appears until this. |

Components are 0–255; coordinates are pixels from the top left.

### Events

| | |
| --- | --- |
| `sdl:poll` | The next event as an object, or `nil` when the queue is empty. |

Answering `nil` rather than blocking is what lets the program own its loop:
drain what has happened, draw a frame, come back.

| slot | on which kinds |
| --- | --- |
| `event:kind` | always — `'quit` `'keyDown` `'keyUp` `'mouseDown` `'mouseUp` `'mouseMove` `'other` |
| `event:key` | `'keyDown` `'keyUp` — `"Escape"`, `"A"`, `"Left"`. SDL names a letter key in upper case whichever way it was typed |
| `event:repeat` | `'keyDown` `'keyUp` — `#1` when the key is repeating |
| `event:x` `event:y` | the three mouse kinds |
| `event:button` | `'mouseDown` `'mouseUp` |

### Time

| | |
| --- | --- |
| `sdl:wait(#milliseconds)` | Answers `nil`. |
| `sdl:ticks` | Milliseconds since `sdl:start`, as an integer. |

### Sound

| | |
| --- | --- |
| `sdl:beep(#hertz, #milliseconds)` | A square wave, from `#20` to `#20000` hertz and up to ten seconds. Answers `true`, or `false` on a machine with nothing to play it on, which is silence rather than an error for the same reason a machine with no acceleration gets software rendering. |

The samples are written by the extension and queued, so there is no audio
callback: the one place SDL offers to call into a program is declined here for
the reason the top of this file gives. The device is opened by the first beep,
not by `sdl:start`, so a program that never beeps holds no sound device. A beep
drops whatever was still queued, because a beep is about now and a tone that
waits its turn is a tone about a moment ago. It ends on a whole period, so it
does not click.

### Failures

Every message checks its own arity and argument types, and names the message:

```
'fill' expects integers, got float -- an integer is written with '#',
and a float becomes one with 'truncated'
'clear' expects a screen, got nil
'poll' before sdl:start
```

The float message is there because it is the mistake a program actually makes:
`x` out of a physics step is a float, and `#` is what makes it a coordinate.

## Events are objects, not dictionaries

`sdl:poll` answers an ordinary object, so a program asks it questions the way it
asks anything else:

```
event:kind        ; -- 'quit 'keyDown 'keyUp 'mouseDown 'mouseUp 'mouseMove 'other
event:key         ; -- "Escape", "A", "Left"      (keyDown, keyUp)
event:x  event:y  ; -- (mouseDown, mouseUp, mouseMove)
event:button      ; -- (mouseDown, mouseUp)
```

`event:kind` rather than `event:at('kind)`, because *everything is a message
send* is the language's whole premise and a dictionary lookup would be one
wearing a send's clothes. The kind is a **symbol**, which compares by identity
and is therefore cheap enough to test every frame.

This is also the one thing writing this extension found missing from Solveig's
promised interface: `sol_symbol_intern` was reachable and not promised. It is
promised now, which is what a second customer is for.

`'other` is answered for an event this binding does not name yet — a program
draining the queue has to see *something*, or `nil` would mean both "nothing
happened" and "something I don't recognise happened", and the loop would spin.

## A screen is a foreign handle

`<sdl screen>` when printed, compared by identity, answering
`isKindOf(foreign)`. **Nothing closes it by hand.** The collector destroys the
renderer and the window when the program lets go, and the machine does it for
whatever is still held when it goes down — including for a program a limit took
away mid-frame, which is exactly when a window left on the screen would be most
annoying.

## Limits still apply

```sh
$ solvm --steps=3000 --extension=build/sdl.so bounce.sob
$ echo $?
124
```

and, less obviously:

```sh
$ solvm --memory=2M --extension=build/sdl.so two-big-windows.sob
solvm: stopped: the memory limit of 2097152 bytes was reached, with 3179480 live
```

A 1024×768 window is about 3MB of pixels, and the foreign cell declares that as
its footprint — so `--memory` measures the window rather than the pointer to it.
An extension that declared nothing would let a program open a thousand.

## How much of SDL2 this is

**Under two percent**, deliberately. With numbers, since "a subset" could mean
anything:

| | |
| --- | --- |
| `SDL_*` functions exported by libSDL2 | **837** |
| distinct ones this extension calls | **20** |
| messages it publishes | **12**, eleven distinct |

**What is missing.** No textures and no images, so nothing but solid rectangles
and lines. No text rendering, no samples or music, no gamepads, no fullscreen,
and no immediate keyboard state — only events. You can write Pong, and
[`examples/pong.sol`](examples/pong.sol) is that sentence checked: it wanted
one thing the eleven messages could not give, and `beep` is that thing. You
cannot write anything that needs to draw a sprite.

**It is a demonstration that a second back end needs nothing the first one did
not**, which was the question it was written to answer. It does not.

### Adding more is mechanical

The per-toolkit work is done: the screen's lifetime against the collector, the
event objects, the argument checking. A new message is a primitive, an arity
check, a `sol_foreign_handle` call and a line in `sol_extension_init`.

Unlike GTK — 4,299 functions and machine-readable introspection data — SDL2 is
small enough and regular enough that hand-writing is the right answer all the
way up. Eight hundred functions, of which a game wants perhaps two hundred.

**Nothing is waiting on it.** The trigger is a program that wants something this
does not have, and `beep` is the one time it has fired: Pong could draw its
score and hold its keys in the language, and could not make a sound.

## Licence

MIT, the same as Solveig.
