; engine.sol -- what was left after the second game.
;
;     @include "engine.sol".
;
; Two games were written whole over the twelve messages, pong.sol and
; breakout.sol, sharing nothing on purpose, and this file is what the two
; had in common when they were read side by side. Five things and a tone,
; none of them C, about a hundred lines. Nothing here draws a sprite, mixes a
; sample or owns a scene; neither game asked. The rule at the end of the
; README applies at this boundary too: a third game that wants something the
; two did not is the reason to add it, and not before. The third game was
; Asteroids, and it asked for nothing; what the reading of three found was
; a seam inside the fifth thing, which is `mover` now. The fourth was
; Invaders, which asked for nothing either, and the reading of four moved
; three things in: the sprite, which the font had been all along; `alive`
; on a rect; and `hum`, which two games had written the same way.
;
;   engine    opens the window and binds `screen`, `width`, `height`,
;             `running` and `frames`; drains the queue, and shows a frame
;   keys      which keys are held, kept from the events, asked by name
;   sprite    rows of text compiled once to runs, painted with `fill`
;   font      the 3x5 cell digits every score was drawn with, ten sprites
;   rect      an integer rectangle: overlap, edges, clamping, a fill, `alive`
;   mover     a float position and velocity, one move a frame, `alive`
;   ball      a mover with an integer shadow, `box`, which is a rect,
;             crossed once a frame by `settle`
;   tone      a pitch and a length, played by `sdl:beep`; `hum` for a sound
;             that is continuous, since the channel is one
;
; **The game keeps its loop.** `engine:drain` empties the queue and hands each
; event on; the `whileTrue` around it is the program's own, as it was in both
; games and as the README argues it should be. Nothing here calls back.
;
; **What an included file binds are ordinary globals**, so the eight names
; above and the five the engine binds when it opens are the whole of what
; this file takes from the namespace.

; ---------------------------------------------------------------------------
; The frame

engine := object:new.

; The five globals every frame reads, bound here at the top level because a
; first assignment inside a block does not bind a global, and `open` is one.
screen := nil. width := #0. height := #0.
running := false. frames := #0.

; A window, and the five globals filled in.
engine:open := { title, w, h |
    sdl:start.
    width := w. height := h.
    screen := sdl:window(title, w, h).
    running := true. frames := #0 }.

; Empty the queue. `'quit` and Escape end the program, the keys are noted,
; and every event is handed to the block for whatever the game wants of it.
engine:drain := { each | | event |
    { event := sdl:poll. event:notNil }:whileTrue({
        event:kind:equals('quit):ifTrue({ self:stop }).
        event:kind:equals('keyDown):and({ event:key:equals("Escape") }):ifTrue({
            self:stop }).
        keys:note(event).
        each:value(event) }) }.

; The loop's end, from inside the program. `running := false` in the game
; would do the same and draw the compiler's rebinding warning, since a bare
; assignment of a constant reads as a claim on the name.
engine:stop := { running := false }.

; The frame just drawn, then about a sixtieth of a second.
engine:show := {
    sdl:present(screen).
    frames := frames:inc.
    sdl:wait(#16) }.

; ---------------------------------------------------------------------------
; Held keys. The binding has events and no keyboard state, so a key held
; across a frame is a fact the program keeps: true from its 'keyDown until
; its 'keyUp. Both games kept it as booleans; this is the booleans by name.

keys := object:new.
keys:held := dictionary:new.
keys:note := { event |
    event:kind:equals('keyDown):ifTrue({ self:held:atPut(event:key, true) }).
    event:kind:equals('keyUp):ifTrue({ self:held:atPut(event:key, false) }) }.
keys:down := { name | self:held:at(name, false) }.
keys:any := { names |
    names:inject(false, { seen, name | seen:or({ self:down(name) }) }) }.

; ---------------------------------------------------------------------------
; A sprite: rows of text, `#` a cell and `.` a gap, compiled once to
; horizontal runs, so that painting it is one `sdl:fill` per run rather
; than one per cell. `fromCells` is the same over rows of booleans, which
; is what a picture that changes keeps. Written for Invaders, and found at
; the reading of four to be what the font had been doing slowly since the
; first game: a digit is a 3x5 sprite.

sprite := object:new.
sprite:w := #0. sprite:h := #0. sprite:cell := #1. sprite:runs := nil.
sprite:fromCells := { cells, cell | | s, row, start, ci, cj |
    s := self:new.
    s:h := cells:size. s:w := cells:at(#1):size. s:cell := cell. s:runs := [].
    cj := #1.
    { cj:lessOrEqual(s:h) }:whileTrue({
        row := cells:at(cj). start := #0. ci := #1.
        { ci:lessOrEqual(s:w) }:whileTrue({
            row:at(ci):ifElse(
                { start:equals(#0):ifTrue({ start := ci }) },
                { start:greaterThan(#0):ifTrue({
                    s:runs:add([cj, start, @expr(ci - start)]). start := #0 }) }).
            ci := ci:inc }).
        start:greaterThan(#0):ifTrue({ s:runs:add([cj, start, @expr(s:w + #1 - start)]) }).
        cj := cj:inc }).
    s }.
sprite:make := { rows, cell |
    self:fromCells(rows:collect({ row | | out, ci |
        out := []. ci := #1.
        { ci:lessOrEqual(row:size) }:whileTrue({
            out:add(row:at(ci):equals("#")). ci := ci:inc }).
        out }), cell) }.
; At (px, py), its top-left, in the current colour.
sprite:paint := { px, py | | c |
    c := self:cell.
    self:runs:do({ r |
        sdl:fill(screen, @expr(px + (r:at(#2) - #1) * c),
                         @expr(py + (r:at(#1) - #1) * c),
                         @expr(r:at(#3) * c), c) }) }.

; ---------------------------------------------------------------------------
; The digits, 3 wide and 5 high, ten sprites in order so that
; `digits:at(d:inc)` is the digit d. This is how the 1972 machine drew its
; score, and four games have found it text enough. The cell is fixed when
; the file is compiled in.

font := object:new.
font:cell := #6.                     ; one cell, in pixels
font:digits := [
    ["###", "#.#", "#.#", "#.#", "###"],
    [".#.", "##.", ".#.", ".#.", "###"],
    ["###", "..#", "###", "#..", "###"],
    ["###", "..#", "###", "..#", "###"],
    ["#.#", "#.#", "###", "..#", "..#"],
    ["###", "#..", "###", "..#", "###"],
    ["###", "#..", "###", "#.#", "###"],
    ["###", "..#", "..#", "..#", "..#"],
    ["###", "#.#", "###", "#.#", "###"],
    ["###", "#.#", "###", "..#", "###"]]:collect({ rows | sprite:make(rows, font:cell) }).

; One digit with its top-left cell at (left, top), in the current colour.
font:digit := { d, left, top | self:digits:at(d:inc):paint(left, top) }.

; A number, right-aligned so that its last digit ends at `right`, with as
; many digits as it has.
font:number := { value, right, top | | n, left, c |
    c := self:cell.
    n := value.
    left := @expr(right - #3 * c).
    self:digit(n:mod(#10), left, top).
    n := n:div(#10).
    { n:greaterThan(#0) }:whileTrue({
        left := @expr(left - #4 * c).
        self:digit(n:mod(#10), left, top).
        n := n:div(#10) }) }.

; ---------------------------------------------------------------------------
; A rectangle, in pixels. Paddles and bricks are rects; a ball's shadow is
; one. The overlap test was written four times across the two games and is
; written once here.

rect := object:new.
rect:x := #0. rect:y := #0. rect:w := #0. rect:h := #0.
rect:alive := true.
rect:make := { left, top, w, h | | r |
    r := self:new. r:x := left. r:y := top. r:w := w. r:h := h. r }.
rect:right  := { @expr(self:x + self:w) }.
rect:bottom := { @expr(self:y + self:h) }.
rect:touches := { other |
    @expr(self:x < other:right & self:right > other:x &
          self:y < other:bottom & self:bottom > other:y) }.
rect:paint := { sdl:fill(screen, self:x, self:y, self:w, self:h) }.

; Kept on the screen along one axis.
rect:clampX := {
    self:x:lessThan(#0):ifTrue({ self:x := #0 }).
    @expr(self:x > width - self:w):ifTrue({ self:x := @expr(width - self:w) }) }.
rect:clampY := {
    self:y:lessThan(#0):ifTrue({ self:y := #0 }).
    @expr(self:y > height - self:h):ifTrue({ self:y := @expr(height - self:h) }) }.

; ---------------------------------------------------------------------------
; A mover: a float position and velocity, one move a frame, and whether it
; is still there. It is what a ball and Asteroids' `thing` had in common
; when the three games were read together: four slots and two lines, with
; the shape of motion, a box that bounces or a radius that wraps, left to
; whatever delegates to it.

mover := object:new.
mover:x := 0.0. mover:y := 0.0. mover:vx := 0.0. mover:vy := 0.0.
mover:alive := true.
mover:move := {
    self:x := @expr(self:x + self:vx).
    self:y := @expr(self:y + self:vy) }.
mover:aim := { angle, speed |
    self:vx := @expr(angle:cos * speed). self:vy := @expr(angle:sin * speed) }.
mover:speed := { @expr(sqrt(self:vx * self:vx + self:vy * self:vy)) }.

; ---------------------------------------------------------------------------
; A ball: a mover with a box. The physics is in floats and the drawing is
; in integers, and the line between them is crossed in one place: `settle`
; copies the position into `box`, and everything that compares, collides
; or draws uses the box. Both games kept that as a rule in a comment; here
; it is a slot.

ball := mover:new.
ball:box := nil.
ball:make := { size | | b |
    b := self:new. b:box := rect:make(#0, #0, size, size). b }.
ball:settle := {
    self:box:x := self:x:truncated.
    self:box:y := self:y:truncated }.

; At rest at an integer position.
ball:place := { left, top |
    self:x := left:asFloat. self:y := top:asFloat.
    self:vx := 0.0. self:vy := 0.0.
    self:settle }.

; One frame of travel.
ball:step := { self:move. self:settle }.

; Moved flush to an edge along one axis, which is how a hit is kept from
; registering twice.
ball:putX := { at | self:x := at:asFloat. self:settle }.
ball:putY := { at | self:y := at:asFloat. self:settle }.

ball:paint := { self:box:paint }.

; ---------------------------------------------------------------------------
; A sound: pitch in hertz, length in milliseconds, so a game names its tones
; once and plays them by name. Two games wanted the channel policy below.

tone := object:new.
tone:hz := #440. tone:ms := #50.
tone:lastAt := #0.                   ; the frame the channel last played
tone:make := { hz, ms | | t | t := self:new. t:hz := hz. t:ms := ms. t }.
tone:play := { sdl:beep(self:hz, self:ms). tone:lastAt := frames }.

; The channel is one and the latest beep wins, so a sound that is
; continuous, a thrust, a siren, a march, is asked for again from the
; frame with `hum`, and yields to anything that just happened.
tone:hum := { @expr(frames - tone:lastAt >= #3):ifTrue({ self:play }) }.
