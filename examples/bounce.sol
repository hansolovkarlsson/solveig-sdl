; bounce.sol -- a ball, a wall, and a loop this program owns.
;
;     solvm --extension=build/sdl.so examples/bounce.sob
;
; SDL hands you a frame and gets out of the way, so there is no callback here
; and nothing is registered with anything. The loop is an ordinary whileTrue.

sdl:start.
screen := sdl:window("bounce", #640, #480).

x  := #40.  y  := #40.
dx := #4.   dy := #3.
size := #40.
running := true.
event := nil.
frames := #0.

{ running }:whileTrue({
    ; -- drain everything that has happened since the last frame
    { event := sdl:poll. event:notNil }:whileTrue({
        event:kind:equals('quit):ifTrue({ running := false }).
        event:kind:equals('keyDown):ifTrue({
            event:key:equals("Escape"):ifTrue({ running := false }) }).
        event:kind:equals('mouseDown):ifTrue({
            x := event:x. y := event:y }) }).

    ; -- move, and turn round at the edges
    x := @expr(x + dx).
    y := @expr(y + dy).
    @expr(x < #0 | x > @expr(#640 - size)):ifTrue({ dx := dx:negated }).
    @expr(y < #0 | y > @expr(#480 - size)):ifTrue({ dy := dy:negated }).

    ; -- draw
    sdl:clear(screen, #20, #20, #30).
    sdl:colour(screen, #240, #180, #60).
    sdl:fill(screen, x, y, size, size).
    sdl:colour(screen, #60, #90, #140).
    sdl:line(screen, #0, #240, #640, #240).
    sdl:present(screen).

    frames := @expr(frames + #1).
    sdl:wait(#16) }).

"frames drawn: ":display. frames:print.
