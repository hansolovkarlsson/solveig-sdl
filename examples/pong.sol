; pong.sol -- the game the README says this binding can write.
;
;     solvm --extension=build/sdl.so examples/pong.sob
;
;   W / S        left paddle
;   Up / Down    right paddle, when a person has it
;   C            hand the right paddle to the machine, or take it back
;   Space        serve the first ball; after a game, start another
;   Escape       quit
;
; First to eleven. The machine has the right paddle until someone presses C.
;
; **One message was added to sdl.c for this.** The README's reference ended
; with "You can write Pong. You cannot write anything that needs to draw a
; sprite", and a claim like that is checked by writing the program, not by
; reading the list. Three things Pong wants were missing from the eleven
; messages; two were written here in a few lines, and the third is the
; twelfth:
;
;   the score     there is no text. The digits are a 3x5 cell font drawn out
;                 of `sdl:fill`, which is how the 1972 machine drew them too;
;   held keys     there is no keyboard state, only events. A key held across
;                 a frame is a fact the program keeps, not one the binding
;                 remembers for it;
;   the beep      there was no audio, and the first version of this file was
;                 silent. It is the one thing a program cannot supply for
;                 itself, and the first thing a program here asked the binding
;                 for: `sdl:beep` is a square wave, and the three tones are
;                 the original's pitches and lengths.
;
; **This file was first written whole**, 290 lines with nothing shared, and
; Breakout after it the same way. The engine is what the two had in common
; when they were read side by side, and this is Pong rewritten over it: the
; font, the held keys and the float-to-integer line are in engine.sol now,
; the wall bounce and the paddle angle in kit.sol, and what is left here is
; Pong: two paddles, a machine to play one of them, and a rally that ends.

@include "kit.sol".

engine:open("pong", #640, #480).

; -- the court
paddleSpeed  := #6.
margin       := #24.                 ; paddle inset from the side wall
winningScore := #11.
left  := rect:make(margin, #210, #10, #60).
right := rect:make(@expr(width - margin - #10), #210, #10, #60).
puck  := ball:make(#10).

speed := 5.0.                        ; along the direction of travel
serveSpeed := 5.0.
maxSpeed := 12.0.

; -- the three sounds, as the 1972 machine had them
hitTone   := tone:make(#459, #96).
wallTone  := tone:make(#226, #16).
scoreTone := tone:make(#490, #257).

; -- who has the ball, and the game
leftScore := #0. rightScore := #0.
state := 'waiting.                   ; 'waiting  'serving  'playing  'over
serveAt := #0.                       ; ticks at which a pending serve goes
serveDirection := 1.0.               ; toward the player who conceded
machine := true.                     ; the right paddle plays itself
target := #0.
j := #0.

; ---------------------------------------------------------------------------
; Serving. The ball sits on the centre line and goes a moment later, toward
; whoever conceded the last point, at the serve speed and a shallow angle.

placeBall := {
    puck:place(@expr((width - puck:box:w) / #2), @expr((height - puck:box:h) / #2)) }.

serve := {
    speed := serveSpeed.
    frames:mod(#2):equals(#1):ifElse(
        { puck:aimX(0.5, speed, serveDirection) },
        { puck:aimX(-0.5, speed, serveDirection) }).
    state := 'playing }.

; A point. The ball is placed, and the serve is timed from the clock rather
; than counted in frames, so a slow frame does not shorten the pause.
point := {
    scoreTone:play.
    placeBall:value.
    leftScore:greaterOrEqual(winningScore):or({
        rightScore:greaterOrEqual(winningScore) }):ifElse(
        { state := 'over },
        { state := 'serving. serveAt := @expr(sdl:ticks + #900) }) }.

; ---------------------------------------------------------------------------
; The paddle bounce. Where the ball meets the paddle sets the angle, and
; every hit is a little faster, up to a ceiling, which is what makes a rally
; end. The ball is moved flush to the paddle so that one hit cannot register
; twice.

bounce := { paddle, direction |
    speed := @expr(speed * 1.06).
    speed:greaterThan(maxSpeed):ifTrue({ speed := maxSpeed }).
    puck:aimX(paddle:offsetY(puck:box), speed, direction).
    hitTone:play }.

; The machine's paddle follows the ball while the ball is coming, and drifts
; back to the middle while it is going away. Its speed is below the ball's
; ceiling, so a fast, steep return beats it, which is the whole game.
machineSpeed := #4.
machineMove := {
    puck:vx:greaterThan(0.0):ifElse(
        { target := @expr(puck:box:y + puck:box:h / #2 - right:h / #2) },
        { target := @expr((height - right:h) / #2) }).
    @expr(target > right:y + #4):ifTrue({ right:y := @expr(right:y + machineSpeed) }).
    @expr(target < right:y - #4):ifTrue({ right:y := @expr(right:y - machineSpeed) }) }.

; ---------------------------------------------------------------------------

placeBall:value.

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):ifTrue({
            event:key:equals("C"):ifTrue({ machine := machine:not }).
            event:key:equals("Space"):ifTrue({
                state:equals('waiting):ifTrue({ serve:value }).
                state:equals('over):ifTrue({
                    leftScore := #0. rightScore := #0.
                    placeBall:value. serve:value }) }) }) }).

    ; -- the paddles
    keys:down("W"):ifTrue({ left:y := @expr(left:y - paddleSpeed) }).
    keys:down("S"):ifTrue({ left:y := @expr(left:y + paddleSpeed) }).
    machine:ifElse(
        { machineMove:value },
        { keys:down("Up"):ifTrue({ right:y := @expr(right:y - paddleSpeed) }).
          keys:down("Down"):ifTrue({ right:y := @expr(right:y + paddleSpeed) }) }).
    left:clampY. right:clampY.

    ; -- a pending serve
    state:equals('serving):ifTrue({
        sdl:ticks:greaterOrEqual(serveAt):ifTrue({ serve:value }) }).

    ; -- the ball
    state:equals('playing):ifTrue({
        puck:step.

        ; the top and bottom walls
        puck:box:y:lessThan(#0):ifTrue({ puck:bounceY(#0). wallTone:play }).
        @expr(puck:box:bottom > height):ifTrue({
            puck:bounceY(@expr(height - puck:box:h)). wallTone:play }).

        ; the paddles, each only while the ball is coming toward it
        puck:vx:lessThan(0.0):and({ puck:box:touches(left) }):ifTrue({
            bounce:value(left, 1.0). puck:putX(left:right) }).
        puck:vx:greaterThan(0.0):and({ puck:box:touches(right) }):ifTrue({
            bounce:value(right, -1.0). puck:putX(@expr(right:x - puck:box:w)) }).

        ; past a paddle is a point
        puck:box:right:lessThan(#0):ifTrue({
            rightScore := rightScore:inc. serveDirection := -1.0. point:value }).
        puck:box:x:greaterThan(width):ifTrue({
            leftScore := leftScore:inc. serveDirection := 1.0. point:value }) }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #10, #10, #14).

    sdl:colour(screen, #70, #70, #80).
    j := #8.
    { j:lessThan(height) }:whileTrue({
        sdl:fill(screen, @expr(width / #2 - #2), j, #4, #12).
        j := @expr(j + #24) }).

    sdl:colour(screen, #220, #220, #220).
    left:paint.
    machine:ifTrue({ sdl:colour(screen, #160, #180, #220) }).
    right:paint.

    sdl:colour(screen, #220, #220, #220).
    state:equals('over):ifFalse({ puck:paint }).
    font:number(leftScore, @expr(width / #2 - #40), #20).
    font:number(rightScore, @expr(width / #2 + #40 + #3 * font:cell), #20).

    engine:show }).

"final score {} - {}":fill([leftScore, rightScore]):display.
