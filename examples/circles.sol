; circles.sol -- bounce.sol with a shape the binding does not have.
;
;     solvm --extension=build/sdl.so examples/circles.sob
;
;   click        add a ball where you clicked
;   space        clear them all but one
;   Escape       quit
;
; **There is no `sdl:circle`, and that is the point of this example.** The
; eleven messages draw rectangles and lines, so a disc is something the program
; works out: for each row of it, half the width is the square root of
; `r^2 - dy^2`, and that row is one `sdl:line`. About sixty lines for a ball of
; thirty, which is nothing.
;
; It stays that way on purpose. A `circle` message would be a few dozen lines of
; C, and no program had asked for one until this file -- one customer, drawn in
; six lines of Solveig, is not a reason to grow a surface that every later back
; end would then have to match.
;
; **And a frame is still all or nothing.** `sdl:present` does not keep what was
; drawn, so every frame here clears, draws every ball, and presents once. An
; animation gets that right without trying; a slow render is where it is easy to
; get wrong, which is what examples/mandelbrot.sol is about.

sdl:start.

width  := #640.
height := #480.
screen := sdl:window("circles", width, height).

; -- the balls, as parallel arrays. Solveig indexes from one.
xs := array:new.  ys := array:new.
dxs := array:new. dys := array:new.
rs := array:new.
reds := array:new. greens := array:new. blues := array:new.

palette := [[#240, #180, #60], [#90, #200, #160], [#220, #90, #120],
            [#120, #150, #240], [#200, #200, #90]].

count := #0.
i := #0.
cx := #0. cy := #0. cr := #0. dy := #0. hw := #0.
nx := #0. ny := #0.
speedX := #0. speedY := #0.
event := nil.
running := true.
colour := nil.

; A ball at a point. Its direction is derived from how many there are, with the
; sign alternating -- without that they all set off the same way and spend the
; first few seconds in one corner, which is what the first version did.
addBall := {
    count := count:inc.
    xs:add(nx). ys:add(ny).
    speedX := @expr(#2 + count:mod(#4)).
    speedY := @expr(#2 + count:mod(#3)).
    count:mod(#2):equals(#0):ifTrue({ speedX := speedX:negated }).
    count:mod(#3):equals(#0):ifTrue({ speedY := speedY:negated }).
    dxs:add(speedX). dys:add(speedY).
    rs:add(@expr(#14 + count:mod(#5) * #6)).
    colour := palette:at(@expr(count:mod(#5) + #1)).
    reds:add(colour:at(#1)). greens:add(colour:at(#2)). blues:add(colour:at(#3)) }.

; ---------------------------------------------------------------------------
; A filled disc, out of the two shapes there are.
;
; One horizontal line per row. `cr * cr - dy * dy` is never negative over the
; range walked, so the square root is always real.

drawDisc := {
    dy := cr:negated.
    { @expr(dy <= cr) }:whileTrue({
        hw := @expr(cr * cr - dy * dy):asFloat:sqrt:truncated.
        sdl:line(screen, @expr(cx - hw), @expr(cy + dy),
                         @expr(cx + hw), @expr(cy + dy)).
        dy := dy:inc }) }.

; ---------------------------------------------------------------------------

nx := #320. ny := #240. addBall:value.

{ running }:whileTrue({
    ; -- drain the queue
    { event := sdl:poll. event:notNil }:whileTrue({
        event:kind:equals('quit):ifTrue({ running := false }).
        event:kind:equals('keyDown):ifTrue({
            event:key:equals("Escape"):ifTrue({ running := false }).
            event:key:equals("Space"):ifTrue({
                { count:greaterThan(#1) }:whileTrue({
                    xs:removeLast. ys:removeLast.
                    dxs:removeLast. dys:removeLast. rs:removeLast.
                    reds:removeLast. greens:removeLast. blues:removeLast.
                    count := @expr(count - #1) }) }) }).
        event:kind:equals('mouseDown):ifTrue({
            count:lessThan(#40):ifTrue({
                nx := event:x. ny := event:y. addBall:value }) }) }).

    ; -- move, and turn round at the edges
    i := #1.
    { i:lessOrEqual(count) }:whileTrue({
        cr := rs:at(i).
        nx := @expr(xs:at(i) + dxs:at(i)).
        ny := @expr(ys:at(i) + dys:at(i)).
        @expr(nx < cr):or({ @expr(nx > width - cr) }):ifTrue({
            dxs:atPut(i, dxs:at(i):negated).
            nx := @expr(xs:at(i) + dxs:at(i)) }).
        @expr(ny < cr):or({ @expr(ny > height - cr) }):ifTrue({
            dys:atPut(i, dys:at(i):negated).
            ny := @expr(ys:at(i) + dys:at(i)) }).
        xs:atPut(i, nx). ys:atPut(i, ny).
        i := i:inc }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #12, #12, #24).
    i := #1.
    { i:lessOrEqual(count) }:whileTrue({
        sdl:colour(screen, reds:at(i), greens:at(i), blues:at(i)).
        cx := xs:at(i). cy := ys:at(i). cr := rs:at(i).
        drawDisc:value.
        i := i:inc }).
    sdl:present(screen).

    sdl:wait(#16) }).

"balls at the end: ":display. count:print.
