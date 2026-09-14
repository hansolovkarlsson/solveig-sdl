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
; **Nothing was added to sdl.c for this**, and nothing was lifted out of
; pong.sol either, on purpose. The rule for the engine is that it is what is
; left after the second game, and the way to see what is left is to write
; the second game whole and read the two side by side. So the frame loop,
; the drained queue, the held keys, the 3x5 font, the beep and the line
; between float physics and integer drawing are all here again, the same
; shape as in Pong. What is here for the first time is a hundred and twelve
; things of one kind: the bricks are objects delegating to one prototype,
; and drawing them and colliding with them is one `do` each. No game with
; one ball and two paddles needed that.
;
; The tones are pitches chosen for this file. Pong's were the 1972
; machine's; Breakout's were not recorded anywhere this could read.

sdl:start.

width  := #640.
height := #480.
screen := sdl:window("breakout", width, height).

; -- the paddle, as the x of its left edge
paddleFull   := #64.
paddleWidth  := paddleFull.
paddleHeight := #8.
paddleY      := #444.
paddleSpeed  := #7.
paddleX      := @expr((width - paddleWidth) / #2).

; -- the ball. Position and velocity are floats; `bx`, `by` are the integer
; copy every comparison and every draw uses.
ballSize := #8.
x := 0.0. y := 0.0. vx := 0.0. vy := 0.0.
bx := #0. by := #0.
speed := 4.0.
baseSpeed := 4.0.
scale := 1.0.

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

; -- the three sounds: pitch in hertz, length in milliseconds
brickTone  := #520. brickLength  := #40.
paddleTone := #330. paddleLength := #60.
wallTone   := #220. wallLength   := #24.
lostTone   := #110. lostLength   := #300.

; -- the game
score := #0.
balls := #3.                         ; left to play, counting the one in play
walls := #1.                         ; walls set up so far, of two
bricksLeft := #0.
hits := #0.                          ; this ball's brick hits, for the speed-ups
spedOrange := false. spedRed := false.
halved := false.
state := 'waiting.                   ; 'waiting  'playing  'over

; -- keys held, from events
leftHeld := false. rightHeld := false.

event := nil.
running := true.
frames := #0.
offset := 0.0.
digit := nil. row := nil. i := #0. j := #0.
cell := #6.                          ; one cell of a digit, in pixels
n := #0.
hit := nil.
colour := nil.

; ---------------------------------------------------------------------------
; A brick. Its position, its row, and whether it is still there; the row
; says what it is worth and what colour it is. `paint` draws it, `points`
; answers its value, and `make` is the constructor, so the wall below is
; a hundred and twelve sends to one prototype.

brick := object:new.
brick:x := #0. brick:y := #0. brick:row := #1. brick:alive := true.
brick:make := { left, top, r | | b |
    b := self:new. b:x := left. b:y := top. b:row := r. b }.
brick:points := { rowPoints:at(self:row) }.
brick:paint := {
    colour := rowColours:at(self:row).
    sdl:colour(screen, colour:at(#1), colour:at(#2), colour:at(#3)).
    sdl:fill(screen, self:x, self:y, brickWidth, brickHeight) }.
brick:touches := {
    @expr(bx < self:x + brickWidth & bx + ballSize > self:x &
          by < self:y + brickHeight & by + ballSize > self:y) }.

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
    halved := false. paddleWidth := paddleFull }.

; ---------------------------------------------------------------------------
; The digits, 3 wide and 5 high, as rows of text. `#` is a cell and `.` is a
; gap. Ten of them, in order, so `digits:at(d:inc)` is the digit d.

digits := [
    ["###", "#.#", "#.#", "#.#", "###"],
    [".#.", "##.", ".#.", ".#.", "###"],
    ["###", "..#", "###", "#..", "###"],
    ["###", "..#", "###", "..#", "###"],
    ["#.#", "#.#", "###", "..#", "..#"],
    ["###", "#..", "###", "..#", "###"],
    ["###", "#..", "###", "#.#", "###"],
    ["###", "..#", "..#", "..#", "..#"],
    ["###", "#.#", "###", "#.#", "###"],
    ["###", "#.#", "###", "..#", "###"]].

; One digit with its top-left cell at (dx, dy).
dx := #0. dy := #0.
drawDigit := {
    digit := digits:at(n:inc).
    j := #1.
    { j:lessOrEqual(#5) }:whileTrue({
        row := digit:at(j).
        i := #1.
        { i:lessOrEqual(#3) }:whileTrue({
            row:at(i):equals("#"):ifTrue({
                sdl:fill(screen, @expr(dx + (i - #1) * cell),
                                 @expr(dy + (j - #1) * cell), cell, cell) }).
            i := i:inc }).
        j := j:inc }) }.

; A number, right-aligned so that its last digit ends at `sx`. As many
; digits as it has, since the score reaches three.
sx := #0. number := #0.
drawNumber := {
    dy := #20.
    dx := @expr(sx - #3 * cell).
    n := number:mod(#10). drawDigit:value.
    number := number:div(#10).
    { number:greaterThan(#0) }:whileTrue({
        dx := @expr(dx - #4 * cell).
        n := number:mod(#10). drawDigit:value.
        number := number:div(#10) }) }.

; ---------------------------------------------------------------------------
; Serving. The ball sits on the paddle until Space, then goes up at a
; shallow angle, at the base speed, with this ball's speed-ups still to come.

placeBall := {
    x := @expr(paddleX + (paddleWidth - ballSize) / #2):asFloat.
    y := @expr(paddleY - ballSize):asFloat.
    vx := 0.0. vy := 0.0.
    bx := x:truncated. by := y:truncated }.

serve := {
    speed := baseSpeed.
    hits := #0.
    spedOrange := false. spedRed := false.
    vx := @expr(speed * 0.5).
    frames:mod(#2):equals(#1):ifTrue({ vx := vx:negated }).
    vy := @expr(-sqrt(speed * speed - vx * vx)).
    state := 'playing }.

; A speed-up keeps the direction and lengthens the velocity to match.
faster := {
    scale := @expr((speed + 1.0) / speed).
    speed := @expr(speed + 1.0).
    vx := @expr(vx * scale). vy := @expr(vy * scale) }.

; A ball lost. The score stays; the next serve is from the paddle.
lost := {
    sdl:beep(lostTone, lostLength).
    balls := balls:dec.
    placeBall:value.
    balls:equals(#0):ifElse({ state := 'over }, { state := 'waiting }) }.

; ---------------------------------------------------------------------------
; The paddle bounce, as Pong's: where the ball meets the paddle sets the
; angle, dead centre straight up and an edge off at about sixty degrees.
; The speed is this ball's, not raised by the hit; Breakout's speed-ups are
; counted in bricks. The ball is moved flush to the paddle so that one hit
; cannot register twice.

bounce := {
    offset := @expr((bx + ballSize / #2) - (paddleX + paddleWidth / #2)):asFloat.
    offset := @expr(offset / (paddleWidth / #2):asFloat).
    offset:greaterThan(1.0):ifTrue({ offset := 1.0 }).
    offset:lessThan(-1.0):ifTrue({ offset := -1.0 }).
    vx := @expr(offset * speed * 0.85).
    vy := @expr(-sqrt(speed * speed - vx * vx)).
    y := @expr(paddleY - ballSize):asFloat. by := y:truncated.
    sdl:beep(paddleTone, paddleLength) }.

; A brick hit. Which side the ball came from decides which component turns:
; if it was wholly above or below the brick a frame ago it came vertically,
; otherwise from the side. Then the brick goes, the score and the hit count
; move, and the speed-ups fire: the fourth and twelfth hits by count, the
; orange and red rows by a flag each, since a row is reached many times.
px := 0.0. py := 0.0.                ; where the ball was a frame ago
strike := {
    @expr(py + ballSize:asFloat <= hit:y:asFloat | py >= (hit:y + brickHeight):asFloat):ifElse(
        { vy := vy:negated },
        { vx := vx:negated }).
    hit:alive := false.
    bricksLeft := bricksLeft:dec.
    score := @expr(score + hit:points).
    hits := hits:inc.
    hits:equals(#4):or({ hits:equals(#12) }):ifTrue({ faster:value }).
    hit:row:lessOrEqual(#4):and({ spedOrange:not }):ifTrue({
        spedOrange := true. faster:value }).
    hit:row:lessOrEqual(#2):and({ spedRed:not }):ifTrue({
        spedRed := true. faster:value }).
    sdl:beep(brickTone, brickLength) }.

; ---------------------------------------------------------------------------

buildWall:value.
placeBall:value.

{ running }:whileTrue({
    ; -- drain the queue
    { event := sdl:poll. event:notNil }:whileTrue({
        event:kind:equals('quit):ifTrue({ running := false }).
        event:kind:equals('keyDown):ifTrue({
            event:key:equals("Escape"):ifTrue({ running := false }).
            event:key:equals("Left"):or({ event:key:equals("A") }):ifTrue({ leftHeld := true }).
            event:key:equals("Right"):or({ event:key:equals("D") }):ifTrue({ rightHeld := true }).
            event:key:equals("Space"):ifTrue({
                state:equals('waiting):ifTrue({ serve:value }).
                state:equals('over):ifTrue({
                    score := #0. balls := #3. walls := #1.
                    buildWall:value. placeBall:value. serve:value }) }) }).
        event:kind:equals('keyUp):ifTrue({
            event:key:equals("Left"):or({ event:key:equals("A") }):ifTrue({ leftHeld := false }).
            event:key:equals("Right"):or({ event:key:equals("D") }):ifTrue({ rightHeld := false }) }).
        event:kind:equals('mouseMove):ifTrue({
            paddleX := @expr(event:x - paddleWidth / #2) }) }).

    ; -- the paddle
    leftHeld:ifTrue({ paddleX := @expr(paddleX - paddleSpeed) }).
    rightHeld:ifTrue({ paddleX := @expr(paddleX + paddleSpeed) }).
    paddleX:lessThan(#0):ifTrue({ paddleX := #0 }).
    @expr(paddleX > width - paddleWidth):ifTrue({ paddleX := @expr(width - paddleWidth) }).

    ; -- a ball waiting rides the paddle
    state:equals('playing):ifFalse({ placeBall:value }).

    ; -- the ball
    state:equals('playing):ifTrue({
        px := x. py := y.
        x := @expr(x + vx). y := @expr(y + vy).
        bx := x:truncated. by := y:truncated.

        ; the side walls
        bx:lessThan(#0):ifTrue({
            x := 0.0. vx := vx:negated. sdl:beep(wallTone, wallLength) }).
        @expr(bx > width - ballSize):ifTrue({
            x := @expr(width - ballSize):asFloat. vx := vx:negated.
            sdl:beep(wallTone, wallLength) }).
        bx := x:truncated.

        ; the top wall, which halves the paddle the first time it is reached
        by:lessThan(#0):ifTrue({
            y := 0.0. by := #0. vy := vy:negated. sdl:beep(wallTone, wallLength).
            halved:ifFalse({
                halved := true.
                paddleWidth := @expr(paddleFull / #2).
                paddleX := @expr(paddleX + paddleWidth / #2) }) }).

        ; the bricks: the first one the ball is in, if any
        hit := nil.
        bricks:do({ b |
            hit:isNil:and({ b:alive }):and({ b:touches }):ifTrue({ hit := b }) }).
        hit:notNil:ifTrue({ strike:value }).

        ; the paddle, only while the ball is falling
        vy:greaterThan(0.0):and({ @expr(by + ballSize >= paddleY) }):and({
            @expr(by <= paddleY + paddleHeight) }):and({
            @expr(bx + ballSize >= paddleX & bx <= paddleX + paddleWidth) }):ifTrue({
                bounce:value }).

        ; past the paddle is a ball lost
        by:greaterThan(height):ifTrue({ lost:value }).

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
    sdl:fill(screen, paddleX, paddleY, paddleWidth, paddleHeight).
    state:equals('over):ifFalse({ sdl:fill(screen, bx, by, ballSize, ballSize) }).

    number := score. sx := @expr(fieldLeft + #11 * cell). drawNumber:value.
    number := balls. sx := @expr(width - fieldLeft). drawNumber:value.

    sdl:present(screen).
    frames := frames:inc.
    sdl:wait(#16) }).

"final score {}":fill([score]):display.
