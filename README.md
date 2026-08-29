# solveig-sdl

An SDL2 surface for [Solum](https://github.com/hansolovkarlsson/Solveig), loaded
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

Needs SDL2 and a checkout of Solveig 0.36.0 or later.

```sh
brew install sdl2                 # macOS
apt install libsdl2-dev           # Debian, Ubuntu

make                              # -> build/sdl.so
make SOLVEIG=/path/to/Solveig     # if it is not ../Solveig
make run                          # build and bounce a ball
```

A bundle is per-platform and per-build: `SOL_EXTENSION_ABI` is compared for
equality and refused rather than guessed, so rebuild this whenever `solvm` is
rebuilt from a newer Solveig. You never rebuild `solvm` to add an extension.

## Reference

Eleven messages, ten of them distinct. Everything that draws answers the screen,
so calls chain.

### Opening

| | |
| --- | --- |
| `sdl:start` | Opens SDL's video subsystem. Answers `true`, or fails with SDL's own message. Calling it twice is harmless; `poll`, `ticks` and `window` fail until it has been called. |
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
| `event:key` | `'keyDown` `'keyUp` — `"Escape"`, `"a"`, `"Left"` |
| `event:repeat` | `'keyDown` `'keyUp` — `#1` when the key is repeating |
| `event:x` `event:y` | the three mouse kinds |
| `event:button` | `'mouseDown` `'mouseUp` |

### Time

| | |
| --- | --- |
| `sdl:wait(#milliseconds)` | Answers `nil`. |
| `sdl:ticks` | Milliseconds since `sdl:start`, as an integer. |

### Failures

Every message checks its own arity and argument types, and names the message:

```
'fill' expects integers, got float -- a coordinate is written with '#',
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
event:key         ; -- "Escape", "a", "Left"      (keyDown, keyUp)
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
| distinct ones this extension calls | **15** |
| messages it publishes | **11**, ten distinct |

**What is missing.** No textures and no images, so nothing but solid rectangles
and lines. No text rendering, no audio, no gamepads, no fullscreen, and no
immediate keyboard state — only events. You can write Pong. You cannot write
anything that needs to draw a sprite.

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
does not have.

## Licence

MIT, the same as Solveig.
