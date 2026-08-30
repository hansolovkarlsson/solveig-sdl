; mandelbrot.sol -- an explorer, and a loop this program owns.
;
;     solvm --extension=build/sdl.so examples/mandelbrot.sob
;
;   click        zoom in, centred where you clicked
;   right-click  zoom out
;   r            back to the whole set
;   Escape       quit
;
; Two things here are worth reading for reasons that are not the fractal.
;
; **It presents on a clock, not on a row.** `sdl:present` waits for the
; display -- about 8ms -- so presenting each of 480 rows would spend four
; seconds a frame doing nothing. Showing the buffer at most every 16ms costs
; one `sdl:ticks` per row and is the difference between a demo and a slideshow.
;
; **It draws the picture four times, coarse to fine.** A pass of 8x8 blocks
; costs a 64th of the full one and puts a recognisable picture up immediately;
; each finer pass replaces it. The whole sequence costs about a third more than
; going straight to single pixels, and it means a click never waits for a
; finished render -- the passes check for events between rows and abandon.
;
; **Build Solveig with the optimiser for this one.** The default `make` is
; `-g` with none, and the four passes take 13 seconds against 2.9 -- which is
; a demo you wait for against one you play with:
;
;     make clean && make CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -O2"

sdl:start.

width  := #640.
height := #480.
screen := sdl:window("mandelbrot", width, height).

; -- the view. `scale` is how much of the complex plane the width covers, so
;    the height follows the window's shape and nothing is stretched.
centreX := -0.5.
centreY := 0.0.
scale   := 3.2.

; **The iteration cap follows the zoom.** A detail that is one pixel wide at
; this scale is a thousand at the next, and the cap that drew the whole set
; cleanly turns a deep view into a flat disc. So it grows as you go in.
depth    := #0.
baseIter := #120.
maxIter  := baseIter.

; -- scratch, all at the top level: a block that reads a global reads a global,
;    where one reading its home frame could not outlive it.
px := #0.      py := #0.
cr := 0.0.     ci := 0.0.
zr := 0.0.     zi := 0.0.
zr2 := 0.0.    zi2 := 0.0.
it := #0.
t := #0.       r := #0.     g := #0.     b := #0.
step := #8.
lastPresent := #0.
abandon := false.
running := true.
event := nil.
halfW := @expr(width:asFloat / 2.0).
halfH := @expr(height:asFloat / 2.0).
pixelSize := 0.0.

; ---------------------------------------------------------------------------
; The colour of an escape count: black inside the set, a hue cycle outside it.

paint := {
    it:equals(maxIter):ifElse(
        { r := #0. g := #0. b := #0 },
        { t := @expr(it * #9):mod(#768).
          @expr(t < #256):ifTrue({
              r := t. g := #0. b := @expr(#255 - t) }).
          @expr(t >= #256):and({ @expr(t < #512) }):ifTrue({
              r := @expr(#511 - t). g := @expr(t - #256). b := #0 }).
          @expr(t >= #512):ifTrue({
              r := #0. g := @expr(#767 - t). b := @expr(t - #512) }) }) }.

; ---------------------------------------------------------------------------
; Events, drained between rows so a click does not wait for the render.

pump := {
    { event := sdl:poll. event:notNil }:whileTrue({
        event:kind:equals('quit):ifTrue({ running := false. abandon := true }).
        event:kind:equals('keyDown):ifTrue({
            event:key:equals("Escape"):ifTrue({ running := false. abandon := true }).
            event:key:equals("R"):ifTrue({
                centreX := -0.5. centreY := 0.0. scale := 3.2.
                depth := #0. abandon := true }) }).
        event:kind:equals('mouseDown):ifTrue({
            ; the clicked pixel, as a point on the plane, becomes the centre
            centreX := @expr(centreX + (event:x:asFloat - halfW) * pixelSize).
            centreY := @expr(centreY + (event:y:asFloat - halfH) * pixelSize).
            event:button:equals(#1):ifElse(
                { scale := @expr(scale / 4.0). depth := depth:inc },
                { scale := @expr(scale * 4.0).
                  @expr(depth > #0):ifTrue({ depth := @expr(depth - #1) }) }).
            abandon := true }) }) }.

; ---------------------------------------------------------------------------
; One pass over the picture at the current block size.

renderPass := {
    pixelSize := @expr(scale / width:asFloat).
    maxIter := @expr(baseIter + depth * #30).
    py := #0.
    { @expr(py < height):and({ abandon:equals(false) }) }:whileTrue({
        px := #0.
        { @expr(px < width) }:whileTrue({
            cr := @expr(centreX + (px:asFloat - halfW) * pixelSize).
            ci := @expr(centreY + (py:asFloat - halfH) * pixelSize).
            zr := 0.0. zi := 0.0. zr2 := 0.0. zi2 := 0.0. it := #0.
            { @expr(it < maxIter):and({ @expr(zr2 + zi2 < 4.0) }) }:whileTrue({
                zi := @expr(2.0 * zr * zi + ci).
                zr := @expr(zr2 - zi2 + cr).
                zr2 := @expr(zr * zr).
                zi2 := @expr(zi * zi).
                it := it:inc }).
            paint:value.
            sdl:colour(screen, r, g, b).
            sdl:fill(screen, px, py, step, step).
            px := @expr(px + step) }).

        ; the row being worked on, so a slow pass looks like progress
        sdl:colour(screen, #255, #255, #255).
        sdl:line(screen, #0, @expr(py + step), width, @expr(py + step)).

        @expr(sdl:ticks - lastPresent > #16):ifTrue({
            sdl:present(screen).
            lastPresent := sdl:ticks }).
        pump:value.
        py := @expr(py + step) }).
    sdl:present(screen) }.

; ---------------------------------------------------------------------------
; Coarse to fine, and start again whenever the view moves.

"click to zoom in, right-click out, r to reset, Escape to quit":display.

{ running }:whileTrue({
    abandon := false.
    step := #8.
    { @expr(step > #0):and({ abandon:equals(false) }) }:whileTrue({
        renderPass:value.
        step := @expr(step / #2) }).

    ; The picture is finished and nothing is being computed, so wait for an
    ; event rather than spinning through the loop above at full speed. This is
    ; the one place the program is idle, and it is idle on purpose.
    { running:and({ abandon:equals(false) }) }:whileTrue({
        pump:value.
        sdl:wait(#16) }) }).

"done":display.
