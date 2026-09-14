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
; two did not is the reason to add it, and not before.
;
;   engine    opens the window and binds `screen`, `width`, `height`,
;             `running` and `frames`; drains the queue, and shows a frame
;   keys      which keys are held, kept from the events, asked by name
;   font      the 3x5 cell digits both scores were drawn with
;   rect      an integer rectangle: overlap, edges, clamping, a fill
;   ball      a float position and velocity with an integer shadow, `box`,
;             which is a rect, crossed once a frame by `settle`
;   tone      a pitch and a length, played by `sdl:beep`
;
; **The game keeps its loop.** `engine:drain` empties the queue and hands each
; event on; the `whileTrue` around it is the program's own, as it was in both
; games and as the README argues it should be. Nothing here calls back.
;
; **What an included file binds are ordinary globals**, so the six names
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
; The digits, 3 wide and 5 high, as rows of text. `#` is a cell and `.` is a
; gap. Ten of them, in order, so `digits:at(d:inc)` is the digit d. This is
; how the 1972 machine drew its score, and it is text enough for one.

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
    ["###", "#.#", "###", "..#", "###"]].

; One digit with its top-left cell at (left, top), in the current colour.
font:digit := { d, left, top | | glyph, row, i, j, c |
    c := self:cell.
    glyph := self:digits:at(d:inc).
    j := #1.
    { j:lessOrEqual(#5) }:whileTrue({
        row := glyph:at(j).
        i := #1.
        { i:lessOrEqual(#3) }:whileTrue({
            row:at(i):equals("#"):ifTrue({
                sdl:fill(screen, @expr(left + (i - #1) * c),
                                 @expr(top + (j - #1) * c), c, c) }).
            i := i:inc }).
        j := j:inc }) }.

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
; A ball. The physics is in floats and the drawing is in integers, and the
; line between them is crossed in one place: `settle` copies the position
; into `box`, and everything that compares, collides or draws uses the box.
; Both games kept that as a rule in a comment; here it is a slot.

ball := object:new.
ball:x := 0.0. ball:y := 0.0. ball:vx := 0.0. ball:vy := 0.0.
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
ball:step := {
    self:x := @expr(self:x + self:vx).
    self:y := @expr(self:y + self:vy).
    self:settle }.

; Moved flush to an edge along one axis, which is how a hit is kept from
; registering twice.
ball:putX := { at | self:x := at:asFloat. self:settle }.
ball:putY := { at | self:y := at:asFloat. self:settle }.

ball:speed := { @expr(sqrt(self:vx * self:vx + self:vy * self:vy)) }.
ball:paint := { self:box:paint }.

; ---------------------------------------------------------------------------
; A sound: pitch in hertz, length in milliseconds, so a game names its tones
; once and plays them by name.

tone := object:new.
tone:hz := #440. tone:ms := #50.
tone:make := { hz, ms | | t | t := self:new. t:hz := hz. t:ms := ms. t }.
tone:play := { sdl:beep(self:hz, self:ms) }.
