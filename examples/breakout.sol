; breakout.sol -- the second game, written to find out what the first one
; left behind.
;
;     solvm --extension=build/sdl.so examples/breakout.sob
;
;   Left / Right   the paddle, held; A / D do the same
;   the mouse      the paddle follows the pointer, the way the 1976 knob did
;   Space          serve a ball; after a game, start another
;   Escape         quit
;
; The 1976 rules. Eight rows of fourteen bricks: red, orange, green, yellow,
; two rows each, worth 7, 5, 3 and 1. Three balls. The ball speeds up four
; times: on its fourth hit, on its twelfth, and the first time it reaches
; the orange rows and the red ones. Once it has broken through and touched
; the top wall, the paddle is half its width. Clearing the wall brings a
; second one, once; 896 is the most a game can score.
;
; **Nothing was added to sdl.c for this**, and the first version shared
; nothing with pong.sol either, on purpose: 339 lines with the loop, the
; drained queue, the held keys, the font, the beep and the float-to-integer
; line all written again in Pong's shape, so that the engine could be read
; off two whole games side by side. It was, and it is engine.sol and
; kit.sol; this is the game rewritten over them. What was here for the first
; time, and is still the whole of what is Breakout's own, is a hundred and
; twelve things of one kind: a brick is a rect with a row, the wall is one
; `do` that paints and one `do` that collides, and the rules are the speed-
; ups, the halved paddle and the second wall.
;
; The tones are pitches chosen for this file. Pong's were the 1972
; machine's; Breakout's were not recorded anywhere this could read.

@include "kit.sol".

engine:open("breakout", #640, #480).

; -- the paddle
paddleFull  := #64.
paddleSpeed := #7.
paddle := rect:make(#288, #444, paddleFull, #8).
puck   := ball:make(#8).
speed := 4.0.
baseSpeed := 4.0.

; -- the wall. Fourteen across, eight down, top row first.
columns     := #14.
rows        := #8.
brickWidth  := #42.
brickHeight := #14.
brickGap    := #2.
fieldLeft   := #13.                  ; centres 14 bricks and 13 gaps in 640
fieldTop    := #64.
rowPoints   := [#7, #7, #5, #5, #3, #3, #1, #1].
rowColours  := [[#200, #40, #40], [#200, #40, #40],
                [#220, #120, #30], [#220, #120, #30],
                [#40, #170, #60], [#40, #170, #60],
                [#220, #200, #40], [#220, #200, #40]].

; -- the four sounds
brickTone  := tone:make(#520, #40).
paddleTone := tone:make(#330, #60).
wallTone   := tone:make(#220, #24).
lostTone   := tone:make(#110, #300).

; -- the game
score := #0.
balls := #3.                         ; left to play, counting the one in play
walls := #1.                         ; walls set up so far, of two
bricksLeft := #0.
hits := #0.                          ; this ball's brick hits, for the speed-ups
spedOrange := false. spedRed := false.
halved := false.
state := 'waiting.                   ; 'waiting  'playing  'over
hit := nil.
scale := 1.0.
wasAt := 0.0.                        ; the ball's y a frame ago
i := #0. j := #0.

; ---------------------------------------------------------------------------
; A brick is a rect with a row, and whether it is still there; the row says
; what it is worth and what colour it is.

brick := rect:new.
brick:row := #1. brick:alive := true.
brick:make := { left, top, r | | b |
    b := self:via(rect):make(left, top, brickWidth, brickHeight).
    b:row := r. b }.
brick:points := { rowPoints:at(self:row) }.
brick:paint := { | c |
    c := rowColours:at(self:row).
    sdl:colour(screen, c:at(#1), c:at(#2), c:at(#3)).
    self:via(rect):paint }.

bricks := [].
buildWall := {
    bricks := [].
    j := #1.
    { j:lessOrEqual(rows) }:whileTrue({
        i := #1.
        { i:lessOrEqual(columns) }:whileTrue({
            bricks:add(brick:make(
                @expr(fieldLeft + (i - #1) * (brickWidth + brickGap)),
                @expr(fieldTop + (j - #1) * (brickHeight + brickGap)), j)).
            i := i:inc }).
        j := j:inc }).
    bricksLeft := @expr(rows * columns).
    halved := false. paddle:w := paddleFull }.

; ---------------------------------------------------------------------------
; Serving. The ball sits on the paddle until Space, then goes up at a
; shallow angle, at the base speed, with this ball's speed-ups still to come.

placeBall := {
    puck:place(@expr(paddle:x + (paddle:w - puck:box:w) / #2),
               @expr(paddle:y - puck:box:h)) }.

serve := {
    speed := baseSpeed.
    hits := #0.
    spedOrange := false. spedRed := false.
    frames:mod(#2):equals(#1):ifElse(
        { puck:aimY(0.6, speed, -1.0) },
        { puck:aimY(-0.6, speed, -1.0) }).
    state := 'playing }.

; A speed-up keeps the direction and lengthens the velocity to match.
faster := {
    scale := @expr((speed + 1.0) / speed).
    speed := @expr(speed + 1.0).
    puck:vx := @expr(puck:vx * scale). puck:vy := @expr(puck:vy * scale) }.

; A ball lost. The score stays; the next serve is from the paddle.
lost := {
    lostTone:play.
    balls := balls:dec.
    placeBall:value.
    balls:equals(#0):ifElse({ state := 'over }, { state := 'waiting }) }.

; A brick hit. Which side the ball came from decides which component turns:
; if it was wholly above or below the brick a frame ago it came vertically,
; otherwise from the side. Then the brick goes, the score and the hit count
; move, and the speed-ups fire: the fourth and twelfth hits by count, the
; orange and red rows by a flag each, since a row is reached many times.
strike := {
    @expr(wasAt + puck:box:h:asFloat <= hit:y:asFloat | wasAt >= hit:bottom:asFloat):ifElse(
        { puck:vy := puck:vy:negated },
        { puck:vx := puck:vx:negated }).
    hit:alive := false.
    bricksLeft := bricksLeft:dec.
    score := @expr(score + hit:points).
    hits := hits:inc.
    hits:equals(#4):or({ hits:equals(#12) }):ifTrue({ faster:value }).
    hit:row:lessOrEqual(#4):and({ spedOrange:not }):ifTrue({
        spedOrange := true. faster:value }).
    hit:row:lessOrEqual(#2):and({ spedRed:not }):ifTrue({
        spedRed := true. faster:value }).
    brickTone:play }.

; ---------------------------------------------------------------------------

buildWall:value.
placeBall:value.

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):and({ event:key:equals("Space") }):ifTrue({
            state:equals('waiting):ifTrue({ serve:value }).
            state:equals('over):ifTrue({
                score := #0. balls := #3. walls := #1.
                buildWall:value. placeBall:value. serve:value }) }).
        event:kind:equals('mouseMove):ifTrue({
            paddle:x := @expr(event:x - paddle:w / #2) }) }).

    ; -- the paddle, by the keys or the mouse, whichever moved last
    keys:any(["Left", "A"]):ifTrue({ paddle:x := @expr(paddle:x - paddleSpeed) }).
    keys:any(["Right", "D"]):ifTrue({ paddle:x := @expr(paddle:x + paddleSpeed) }).
    paddle:clampX.

    ; -- a ball waiting rides the paddle
    state:equals('playing):ifFalse({ placeBall:value }).

    ; -- the ball
    state:equals('playing):ifTrue({
        wasAt := puck:y.
        puck:step.

        ; the side walls
        puck:box:x:lessThan(#0):ifTrue({ puck:bounceX(#0). wallTone:play }).
        @expr(puck:box:right > width):ifTrue({
            puck:bounceX(@expr(width - puck:box:w)). wallTone:play }).

        ; the top wall, which halves the paddle the first time it is reached
        puck:box:y:lessThan(#0):ifTrue({
            puck:bounceY(#0). wallTone:play.
            halved:ifFalse({
                halved := true.
                paddle:w := @expr(paddleFull / #2).
                paddle:x := @expr(paddle:x + paddle:w / #2) }) }).

        ; the bricks: the first one the ball is in, if any
        hit := nil.
        bricks:do({ b |
            hit:isNil:and({ b:alive }):and({ puck:box:touches(b) }):ifTrue({ hit := b }) }).
        hit:notNil:ifTrue({ strike:value }).

        ; the paddle, only while the ball is falling
        puck:vy:greaterThan(0.0):and({ puck:box:touches(paddle) }):ifTrue({
            puck:aimY(paddle:offsetX(puck:box), speed, -1.0).
            puck:putY(@expr(paddle:y - puck:box:h)).
            paddleTone:play }).

        ; past the paddle is a ball lost
        puck:box:y:greaterThan(height):ifTrue({ lost:value }).

        ; the wall cleared: a second one, once
        bricksLeft:equals(#0):ifTrue({
            walls:lessThan(#2):ifElse(
                { walls := walls:inc. buildWall:value. placeBall:value.
                  state := 'waiting },
                { state := 'over }) }) }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #10, #10, #14).
    bricks:do({ b | b:alive:ifTrue({ b:paint }) }).
    sdl:colour(screen, #220, #220, #220).
    paddle:paint.
    state:equals('over):ifFalse({ puck:paint }).
    font:number(score, @expr(fieldLeft + #11 * font:cell), #20).
    font:number(balls, @expr(width - fieldLeft), #20).

    engine:show }).

"final score {}":fill([score]):display.
