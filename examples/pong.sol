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
; messages; two are handled here in a few lines, and the third is the twelfth:
;
;   the score     there is no text. The digits are a 3x5 cell font drawn out
;                 of `sdl:fill`, which is how the 1972 machine drew them too;
;   held keys     there is no keyboard state, only events. Four booleans are
;                 set on 'keyDown and cleared on 'keyUp, and the paddles read
;                 the booleans. A key held across a frame is a fact the program
;                 keeps, not one the binding remembers for it;
;   the beep      there was no audio, and the first version of this file was
;                 silent. It is the one thing a program cannot supply for
;                 itself, and the first thing a program here asked the binding
;                 for: `sdl:beep` is a square wave, and the three tones are
;                 the original's pitches and lengths.
;
; **The physics is in floats and the drawing is in integers**, and the line
; between them is drawn once per frame: `bx := x:truncated`, and everything
; that compares, collides or draws uses `bx`. No arithmetic message crosses
; the two types, so keeping one integer copy of the ball's position is what
; stops `#` and `asFloat` from appearing in every other line.

sdl:start.

width  := #640.
height := #480.
screen := sdl:window("pong", width, height).

; -- the court
paddleWidth  := #10.
paddleHeight := #60.
paddleSpeed  := #6.
halfPaddle   := 30.0.                ; paddleHeight / 2, as the float the angle wants
ballSize     := #10.
margin       := #24.                 ; paddle inset from the side wall
winningScore := #11.

; -- the three sounds, as the 1972 machine had them: pitch in hertz, length
; in milliseconds
hitTone  := #459. hitLength  := #96.
wallTone := #226. wallLength := #16.
scoreTone := #490. scoreLength := #257.

; -- the paddles, as the y of their top edge
leftY  := @expr((height - paddleHeight) / #2).
rightY := leftY.
leftX  := margin.
rightX := @expr(width - margin - paddleWidth).

; -- the ball. Position and velocity are floats; `bx`, `by` are the integer
; copy every comparison and every draw uses.
x := 0.0. y := 0.0. vx := 0.0. vy := 0.0.
bx := #0. by := #0.
speed := 5.0.                        ; along the direction of travel
serveSpeed := 5.0.
maxSpeed := 12.0.

; -- who has the ball, and the game
leftScore := #0. rightScore := #0.
state := 'waiting.                   ; 'waiting  'serving  'playing  'over
serveAt := #0.                       ; ticks at which a pending serve goes
serveDirection := 1.0.               ; toward the player who conceded
machine := true.                     ; the right paddle plays itself

; -- keys held, from events
leftUp := false.  leftDown := false.
rightUp := false. rightDown := false.

event := nil.
running := true.
frames := #0.
offset := 0.0.
target := #0.
digit := nil. row := nil. i := #0. j := #0.
cell := #6.                          ; one cell of a score digit, in pixels
n := #0.

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

; A score, right-aligned so that its last digit ends at `sx`. Two digits at
; most, since the game ends at eleven.
sx := #0. score := #0.
drawScore := {
    dy := #20.
    dx := @expr(sx - #3 * cell).
    n := score:mod(#10). drawDigit:value.
    score:greaterOrEqual(#10):ifTrue({
        dx := @expr(dx - #4 * cell).
        n := score:div(#10). drawDigit:value }) }.

; ---------------------------------------------------------------------------
; Serving. The ball sits on the centre line and goes a moment later, toward
; whoever conceded the last point, at the serve speed and a shallow angle.

placeBall := {
    x := @expr((width - ballSize) / #2):asFloat.
    y := @expr((height - ballSize) / #2):asFloat.
    vx := 0.0. vy := 0.0.
    bx := x:truncated. by := y:truncated }.

serve := {
    speed := serveSpeed.
    vx := @expr(speed * serveDirection * 0.9).
    vy := @expr(speed * 0.45).
    frames:mod(#2):equals(#1):ifTrue({ vy := vy:negated }).
    state := 'playing }.

; A point. The ball is placed, and the serve is timed from the clock rather
; than counted in frames, so a slow frame does not shorten the pause.
point := {
    sdl:beep(scoreTone, scoreLength).
    placeBall:value.
    leftScore:greaterOrEqual(winningScore):or({
        rightScore:greaterOrEqual(winningScore) }):ifElse(
        { state := 'over },
        { state := 'serving. serveAt := @expr(sdl:ticks + #900) }) }.

; ---------------------------------------------------------------------------
; The paddle bounce. Where the ball meets the paddle sets the angle: dead
; centre sends it straight back, an edge sends it off at about sixty degrees.
; Every hit is a little faster, up to a ceiling, which is what makes a rally
; end. `py` is the paddle's top edge; the ball is moved flush to the paddle so
; that one hit cannot register twice.

py := #0.
bounce := {
    offset := @expr((by + ballSize / #2) - (py + paddleHeight / #2)):asFloat.
    offset := @expr(offset / halfPaddle).
    offset:greaterThan(1.0):ifTrue({ offset := 1.0 }).
    offset:lessThan(-1.0):ifTrue({ offset := -1.0 }).
    speed := @expr(speed * 1.06).
    speed:greaterThan(maxSpeed):ifTrue({ speed := maxSpeed }).
    vy := @expr(offset * speed * 0.85).
    vx := @expr(sqrt(speed * speed - vy * vy)).
    sdl:beep(hitTone, hitLength) }.

; The machine's paddle follows the ball while the ball is coming, and drifts
; back to the middle while it is going away. Its speed is below the ball's
; ceiling, so a fast, steep return beats it, which is the whole game.
machineSpeed := #4.
machineMove := {
    vx:greaterThan(0.0):ifElse(
        { target := @expr(by + ballSize / #2 - paddleHeight / #2) },
        { target := @expr((height - paddleHeight) / #2) }).
    @expr(target > rightY + #4):ifTrue({ rightY := @expr(rightY + machineSpeed) }).
    @expr(target < rightY - #4):ifTrue({ rightY := @expr(rightY - machineSpeed) }) }.

; ---------------------------------------------------------------------------

placeBall:value.

{ running }:whileTrue({
    ; -- drain the queue
    { event := sdl:poll. event:notNil }:whileTrue({
        event:kind:equals('quit):ifTrue({ running := false }).
        event:kind:equals('keyDown):ifTrue({
            event:key:equals("Escape"):ifTrue({ running := false }).
            event:key:equals("W"):ifTrue({ leftUp := true }).
            event:key:equals("S"):ifTrue({ leftDown := true }).
            event:key:equals("Up"):ifTrue({ rightUp := true }).
            event:key:equals("Down"):ifTrue({ rightDown := true }).
            event:key:equals("C"):ifTrue({ machine := machine:not }).
            event:key:equals("Space"):ifTrue({
                state:equals('waiting):ifTrue({ serve:value }).
                state:equals('over):ifTrue({
                    leftScore := #0. rightScore := #0.
                    placeBall:value. serve:value }) }) }).
        event:kind:equals('keyUp):ifTrue({
            event:key:equals("W"):ifTrue({ leftUp := false }).
            event:key:equals("S"):ifTrue({ leftDown := false }).
            event:key:equals("Up"):ifTrue({ rightUp := false }).
            event:key:equals("Down"):ifTrue({ rightDown := false }) }) }).

    ; -- the paddles
    leftUp:ifTrue({ leftY := @expr(leftY - paddleSpeed) }).
    leftDown:ifTrue({ leftY := @expr(leftY + paddleSpeed) }).
    machine:ifElse(
        { machineMove:value },
        { rightUp:ifTrue({ rightY := @expr(rightY - paddleSpeed) }).
          rightDown:ifTrue({ rightY := @expr(rightY + paddleSpeed) }) }).
    leftY:lessThan(#0):ifTrue({ leftY := #0 }).
    rightY:lessThan(#0):ifTrue({ rightY := #0 }).
    @expr(leftY > height - paddleHeight):ifTrue({ leftY := @expr(height - paddleHeight) }).
    @expr(rightY > height - paddleHeight):ifTrue({ rightY := @expr(height - paddleHeight) }).

    ; -- a pending serve
    state:equals('serving):ifTrue({
        sdl:ticks:greaterOrEqual(serveAt):ifTrue({ serve:value }) }).

    ; -- the ball
    state:equals('playing):ifTrue({
        x := @expr(x + vx). y := @expr(y + vy).
        bx := x:truncated. by := y:truncated.

        ; the top and bottom walls
        by:lessThan(#0):ifTrue({
            y := 0.0. vy := vy:negated. sdl:beep(wallTone, wallLength) }).
        @expr(by > height - ballSize):ifTrue({
            y := @expr(height - ballSize):asFloat. vy := vy:negated.
            sdl:beep(wallTone, wallLength) }).
        by := y:truncated.

        ; the left paddle, only while the ball is coming toward it
        vx:lessThan(0.0):and({ @expr(bx <= leftX + paddleWidth) }):and({
            @expr(bx + ballSize >= leftX) }):and({
            @expr(by + ballSize >= leftY & by <= leftY + paddleHeight) }):ifTrue({
                py := leftY. bounce:value.
                x := @expr(leftX + paddleWidth):asFloat. bx := x:truncated }).

        ; the right paddle
        vx:greaterThan(0.0):and({ @expr(bx + ballSize >= rightX) }):and({
            @expr(bx <= rightX + paddleWidth) }):and({
            @expr(by + ballSize >= rightY & by <= rightY + paddleHeight) }):ifTrue({
                py := rightY. bounce:value. vx := vx:negated.
                x := @expr(rightX - ballSize):asFloat. bx := x:truncated }).

        ; past a paddle is a point
        @expr(bx + ballSize < #0):ifTrue({
            rightScore := rightScore:inc. serveDirection := -1.0. point:value }).
        @expr(bx > width):ifTrue({
            leftScore := leftScore:inc. serveDirection := 1.0. point:value }) }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #10, #10, #14).

    sdl:colour(screen, #70, #70, #80).
    j := #8.
    { j:lessThan(height) }:whileTrue({
        sdl:fill(screen, @expr(width / #2 - #2), j, #4, #12).
        j := @expr(j + #24) }).

    sdl:colour(screen, #220, #220, #220).
    sdl:fill(screen, leftX, leftY, paddleWidth, paddleHeight).
    machine:ifTrue({ sdl:colour(screen, #160, #180, #220) }).
    sdl:fill(screen, rightX, rightY, paddleWidth, paddleHeight).

    sdl:colour(screen, #220, #220, #220).
    state:equals('over):ifFalse({ sdl:fill(screen, bx, by, ballSize, ballSize) }).

    score := leftScore.  sx := @expr(width / #2 - #40). drawScore:value.
    score := rightScore. sx := @expr(width / #2 + #40 + #3 * cell). drawScore:value.

    sdl:present(screen).
    frames := frames:inc.
    sdl:wait(#16) }).

"final score {} - {}":fill([leftScore, rightScore]):display.
