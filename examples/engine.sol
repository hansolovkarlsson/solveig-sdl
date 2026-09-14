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
; on a rect; and `hum`, which two games had written the same way. The fifth
; was Spacewar!, the second drawn with lines, and the reading of five moved
; the whole of that layer in: `thing`, `draw` and `mote` as Asteroids had
; written them and Spacewar copied them, and `craft`, the seam between the
; two games' ships. The sixth was Lunar Lander, which asked for nothing and
; was the first to want words; the seventh was Tetris, which wanted them
; again, and the reading of seven moved the alphabet in beside the digits,
; and bound the generator and the two key lists that five games and three
; had each written in a line of their own. The eighth, ninth and tenth
; were Missile Command, Centipede and Scramble, and the reading of ten
; moved two things in: `tint`, the four lines three games had written the
; same way over a table of colours, and `grid`, the table of counts two
; games had each made for themselves. The eleventh and twelfth were
; Defender and Super Mario Bros., and the reading of twelve moved the
; camera in, once three games had scrolled three ways and written the
; same box at a mover's position, and gave the grid its cell and the font
; a centred word.
;
;   engine    opens the window and binds `screen`, `width`, `height`,
;             `running` and `frames`; drains the queue, and shows a frame
;   keys      which keys are held, kept from the events, asked by name
;   sprite    rows of text compiled once to runs, painted with `fill`
;   font      the 3x5 cell digits every score was drawn with, ten sprites,
;             and the alphabet two games wrote their words with
;   tint      the colour in use, from a table of sets the game fills
;   rect      an integer rectangle: overlap, edges, clamping, a fill, `alive`
;   grid      a table of counts, rows by columns, `at(c, r)` and `atPut`,
;             and the column and row a pixel is in
;   camera    the world x at the screen's left edge, and a world x made a
;             screen one; a game that wraps overrides the making
;   mover     a float position and velocity, one move a frame, `alive`,
;             and its box on the screen through the camera
;   ball      a mover with an integer shadow, `box`, which is a rect,
;             crossed once a frame by `settle`
;   thing     a mover with a radius, that wraps; collision is a distance
;   draw      a shape, as unit points, drawn as lines turned and scaled
;   craft     a thing with a heading: turns, burns to a ceiling, a flame
;   mote      debris, a dot or a line, from a point for a while
;   tone      a pitch and a length, played by `sdl:beep`; `hum` for a sound
;             that is continuous, since the channel is one
;
; **The game keeps its loop.** `engine:drain` empties the queue and hands each
; event on; the `whileTrue` around it is the program's own, as it was in both
; games and as the README argues it should be. Nothing here calls back.
;
; **What an included file binds are ordinary globals**, so the fifteen
; names above, the seven the engine binds when it opens, `tau`, `rng` and
; the two key lists are the whole of what this file takes from the
; namespace.

; ---------------------------------------------------------------------------
; The frame

engine := object:new.

; The five globals every frame reads, bound here at the top level because a
; first assignment inside a block does not bind a global, and `open` is one.
screen := nil. width := #0. height := #0.
running := false. frames := #0.
fw := 0.0. fh := 0.0.                ; the width and height as floats
tau := 6.283185307179586.            ; a whole turn, for the games in radians
rng := random:new.                   ; the one generator; five games had made their own

; A window, and the globals filled in.
engine:open := { title, w, h |
    sdl:start.
    width := w. height := h. fw := w:asFloat. fh := h:asFloat.
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

; The frame just drawn, then the rest of a sixtieth of a second. `present`
; takes time of its own and a frame that drew a lot has spent some of the
; sixtieth already; waiting a whole one on top of both, as this did for
; twelve games, measured fifty-four frames a second on the twelfth here,
; and would be less on a display that `present` waits for.
engine:lastShown := #0.
engine:show := { | spent |
    sdl:present(screen).
    frames := frames:inc.
    spent := @expr(sdl:ticks - engine:lastShown).
    @expr(spent < #16):ifTrue({ sdl:wait(@expr(#16 - spent)) }).
    engine:lastShown := sdl:ticks }.

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

; The two lists three games wrote the same way: the arrows, and the letters
; a left hand rests on. A game with more keys names its own beside these.
leftKeys := ["Left", "A"]. rightKeys := ["Right", "D"].

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
; score, and five games found it text enough. The letters are in the same
; cells, and are the one place this file was designed ahead of the games:
; Lander and Tetris had used sixteen between them, and the alphabet is
; twenty-six, because the digits are all ten and a word with a letter the
; font lacks would fail an eighth game at run time. The cell is fixed when
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

; The letters, upper case, as sprites by name.
font:letters := #[
    "A" = ["###", "#.#", "###", "#.#", "#.#"],
    "B" = ["##.", "#.#", "##.", "#.#", "##."],
    "C" = ["###", "#..", "#..", "#..", "###"],
    "D" = ["##.", "#.#", "#.#", "#.#", "##."],
    "E" = ["###", "#..", "##.", "#..", "###"],
    "F" = ["###", "#..", "##.", "#..", "#.."],
    "G" = ["###", "#..", "#.#", "#.#", "###"],
    "H" = ["#.#", "#.#", "###", "#.#", "#.#"],
    "I" = ["###", ".#.", ".#.", ".#.", "###"],
    "J" = ["..#", "..#", "..#", "#.#", "###"],
    "K" = ["#.#", "#.#", "##.", "#.#", "#.#"],
    "L" = ["#..", "#..", "#..", "#..", "###"],
    "M" = ["#.#", "###", "###", "#.#", "#.#"],
    "N" = ["##.", "#.#", "#.#", "#.#", "#.#"],
    "O" = ["###", "#.#", "#.#", "#.#", "###"],
    "P" = ["###", "#.#", "###", "#..", "#.."],
    "Q" = ["###", "#.#", "#.#", "###", "..#"],
    "R" = ["###", "#.#", "##.", "#.#", "#.#"],
    "S" = ["###", "#..", "###", "..#", "###"],
    "T" = ["###", ".#.", ".#.", ".#.", ".#."],
    "U" = ["#.#", "#.#", "#.#", "#.#", "###"],
    "V" = ["#.#", "#.#", "#.#", "#.#", ".#."],
    "W" = ["#.#", "#.#", "###", "###", "#.#"],
    "X" = ["#.#", "#.#", ".#.", "#.#", "#.#"],
    "Y" = ["#.#", "#.#", ".#.", ".#.", ".#."],
    "Z" = ["###", "..#", ".#.", "#..", "###"]].
font:glyphs := dictionary:new.
font:letters:keysAndValuesDo({ ch, rows | font:glyphs:atPut(ch, sprite:make(rows, font:cell)) }).

; A word, upper case, with its top-left at (left, top), in the current
; colour; a space is a cell left empty, which the eighth game asked for
; with its first title, and a letter the font lacks is an error, since
; there are none.
font:word := { text, left, top | | k |
    k := #1.
    { k:lessOrEqual(text:size) }:whileTrue({
        text:at(k):equals(" "):ifFalse({
            self:glyphs:at(text:at(k)):paint(@expr(left + (k - #1) * #4 * self:cell), top) }).
        k := k:inc }) }.

; A word across the middle of the screen, which three games had placed by
; hand and two of them at the same number.
font:centred := { text, top |
    self:word(text, @expr((width - (text:size * #4 - #1) * self:cell) / #2), top) }.

; ---------------------------------------------------------------------------
; The colour in use: a table of sets the game fills, each a list of colour
; triples, and which set is in use, so that a game changes its colours by
; the wave with one assignment. Three games wrote these four lines the
; same way and a fourth wrote the two-colour case of them; the tables are
; theirs, since a game's colours are its own the way its tones are.
; `value` is a method here like any other, so a game asks `tint:value(n)`.

tint := object:new.
tint:sets := [[[#248, #248, #248]]].     ; one white, until a game says otherwise
tint:set := #1.
tint:value := { which | | c |
    c := self:sets:at(self:set):at(which).
    sdl:colour(screen, c:at(#1), c:at(#2), c:at(#3)) }.

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
; A table of counts, rows by columns, one-based both ways and asked with
; the column first, as a pixel is. Tetris's well and Centipede's field,
; which each made their own; a row is an array, which is what a game that
; clears or scans one wants.

grid := object:new.
grid:cols := #0. grid:rows := #0. grid:cells := nil.
grid:cell := #1.                     ; a cell's side in pixels, for the two below
grid:make := { cols, rows | | g, r |
    g := self:new. g:cols := cols. g:rows := rows. g:cells := [].
    rows:repeat({ r := []. cols:repeat({ r:add(#0) }). g:cells:add(r) }).
    g }.
grid:at := { c, r | self:cells:at(r):at(c) }.
grid:atPut := { c, r, v | self:cells:at(r):atPut(c, v) }.
grid:row := { r | self:cells:at(r) }.
; The column and row an integer pixel is in, which two games wrote.
grid:colOf := { x | @expr(x / self:cell + #1) }.
grid:rowOf := { y | @expr(y / self:cell + #1) }.

; ---------------------------------------------------------------------------
; The camera: the world x at the screen's left edge, nought for a game
; whose world is its screen, and the making of a screen x from a world
; one, which is where three scrolling games subtracted it. A world that
; wraps overrides `screenX` to bring the difference the near way round
; first, and everything in the engine that asks the camera gets the wrap.

camera := object:new.
camera:x := 0.0.
camera:screenX := { wx | @expr(wx - self:x):truncated }.

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
; Its box on the screen, w by h, through the camera; three games wrote it.
mover:box := { w, h | rect:make(camera:screenX(self:x), self:y:truncated, w, h) }.

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
; A thing: a mover with a radius, that wraps. The other shape of motion,
; Asteroids' and Spacewar's; collisions are a distance against two radii.

thing := mover:new.
thing:r := 1.0.
thing:step := { self:move. self:wrap }.
thing:wrap := {
    self:x:lessThan(@expr(-self:r)):ifTrue({ self:x := @expr(self:x + fw + 2.0 * self:r) }).
    self:x:greaterThan(@expr(fw + self:r)):ifTrue({ self:x := @expr(self:x - fw - 2.0 * self:r) }).
    self:y:lessThan(@expr(-self:r)):ifTrue({ self:y := @expr(self:y + fh + 2.0 * self:r) }).
    self:y:greaterThan(@expr(fh + self:r)):ifTrue({ self:y := @expr(self:y - fh - 2.0 * self:r) }) }.
thing:within := { other, reach | | dx, dy |
    dx := @expr(self:x - other:x). dy := @expr(self:y - other:y).
    @expr(dx * dx + dy * dy < reach * reach) }.
thing:touches := { other | self:within(other, @expr(self:r + other:r)) }.

; ---------------------------------------------------------------------------
; A shape at (ox, oy), turned by `angle` and scaled, as lines; the last
; point joins the first. A shape is a list of unit points, so a rock is a
; list and a ship is a list, and the vector display is this one block.

draw := { shape, ox, oy, angle, scale | | c, s, n, j, p, lx, ly, px, py |
    c := angle:cos. s := angle:sin.
    n := shape:size.
    p := shape:at(n).
    lx := @expr(ox + (p:at(#1) * c - p:at(#2) * s) * scale):truncated.
    ly := @expr(oy + (p:at(#1) * s + p:at(#2) * c) * scale):truncated.
    j := #1.
    { j:lessOrEqual(n) }:whileTrue({
        p := shape:at(j).
        px := @expr(ox + (p:at(#1) * c - p:at(#2) * s) * scale):truncated.
        py := @expr(oy + (p:at(#1) * s + p:at(#2) * c) * scale):truncated.
        sdl:line(screen, lx, ly, px, py).
        lx := px. ly := py.
        j := j:inc }) }.

; ---------------------------------------------------------------------------
; A craft: a thing with a heading, that turns, burns along its heading up
; to a ceiling, and is painted as a shape with a flame behind it on the
; frames it is burning. What Asteroids' ship and Spacewar's ships had in
; common; what they carry, drag or a tank, and what hyperspace costs them,
; is theirs.

craft := thing:new.
craft:heading := 0.0.
craft:flame := [[-0.4, 0.3], [-1.0, 0.0], [-0.4, -0.3]].
craft:turn := { by | self:heading := @expr(self:heading + by) }.
craft:burn := { accel, top |
    self:vx := @expr(self:vx + self:heading:cos * accel).
    self:vy := @expr(self:vy + self:heading:sin * accel).
    @expr(self:vx * self:vx + self:vy * self:vy > top * top):ifTrue({
        self:aim(float:atan2(self:vy, self:vx), top) }) }.
craft:paint := { shape, scale, burning |
    draw:value(shape, self:x, self:y, self:heading, scale).
    burning:and({ frames:mod(#2):equals(#0) }):ifTrue({
        draw:value(self:flame, self:x, self:y, self:heading, scale) }) }.

; ---------------------------------------------------------------------------
; Debris: a dot or a short line, from a point in a random direction, for a
; while. What an explosion is in a game drawn with lines.

mote := thing:new.
mote:life := #0. mote:angle := 0.0. mote:long := false.
mote:make := { px, py, long, life | | m |
    m := self:new. m:x := px. m:y := py. m:long := long. m:life := life.
    m:angle := @expr(rng:fraction * tau).
    m:aim(@expr(rng:fraction * tau), @expr(0.5 + rng:fraction * 1.5)).
    m }.
mote:step := { self:via(thing):step. self:life := self:life:dec.
    self:life:equals(#0):ifTrue({ self:alive := false }) }.
mote:paint := {
    self:long:ifElse(
        { sdl:line(screen, self:x:truncated, self:y:truncated,
                   @expr(self:x + self:angle:cos * 8.0):truncated,
                   @expr(self:y + self:angle:sin * 8.0):truncated) },
        { sdl:fill(screen, self:x:truncated, self:y:truncated, #2, #2) }) }.

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
