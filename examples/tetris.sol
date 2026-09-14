; tetris.sol -- the seventh game, the first drawn from a grid, and the
; second that wanted words.
;
;     solvm --extension=build/sdl.so examples/tetris.sob
;
;   Left / Right   move; A / D do the same
;   Up / X         turn clockwise; Z turns the other way
;   Down / S       drop faster
;   Space          when no game is on, start one
;   Escape         quit
;
; The 1989 rules, the cartridge's. A well ten wide and twenty deep, seven
; pieces, the next one shown. A piece falls a row every so many frames by
; level, 48 at level 0 down to 1 at 29; Down drops it a row every second
; frame and each row dropped that way is a point when it lands. It lands the
; moment it cannot fall, with no delay; a turn that does not fit does not
; happen, and a wall does not push the piece back. Lines score 40, 100, 300
; or 1,200 times the level after them, the level is the lines by ten, and a
; cleared line goes from the middle outward over twenty frames, then ten
; frames pass before the next piece enters. A held Left or Right moves once,
; waits sixteen frames, and then moves every sixth. The next piece is drawn
; from eight and drawn again from seven when it is the eighth or the same as
; the last. The game is over when a piece cannot enter, and the well fills
; from the top with a curtain. Three things the cartridge had that this does
; not: the statistics down the left, the start-level menu, and the second
; and third tunes.
;
; **What was predicted before this was written.** That of the engine's
; thirteen names, `engine`, `keys`, `font` and `tone` would carry a seventh
; game and nothing else would carry this one: nothing here has a float
; position, a radius, a heading or a box, because a piece is four cells in a
; grid and the grid is the state, which is the first time the screen is
; drawn from a table rather than from things. That `sprite` would not be
; wanted either, since a cell is two fills and there is no picture. That
; `keys` would take its first rule from a game, the sixteen-then-six repeat
; of a held key, written over the booleans it keeps rather than over the
; event stream, which has a repeat of the keyboard's own. That this is the
; second game to name a number, so `letters`, `glyphs` and `label` are
; copied from lander.sol as Spacewar copied Asteroids' `thing`, with this
; game's twelve letters, and the trigger the reading of six wrote down is
; met: the second word in a second game. That the tune is a sequence of
; tones stepped by the frame through the one-channel policy, the way
; Invaders' four-note march is, and is one game's. And that the binding
; would be asked for nothing.
;
; The tune is Korobeiniki, which is a folk song; the tones are pitches
; chosen for this file.

@include "engine.sol".

engine:open("tetris", #640, #480).

rng := random:new.

; -- the well
cols := #10. rows := #20.
cell := #20.                         ; one cell, in pixels
wellLeft := #220. wellTop := #40.

leftKeys := ["Left", "A"]. rightKeys := ["Right", "D"]. downKeys := ["Down", "S"].

; -- the rules
dasDelay := #16. dasRate := #6.      ; a held key repeats after 16 frames, then every 6
entryDelay := #10.                   ; frames between a landing and the next piece
clearDelay := #20.                   ; frames a line takes to go
curtainRate := #4.                   ; frames a curtain row takes to fall
lineScores := [#40, #100, #300, #1200].
speeds := [#48, #43, #38, #33, #28, #23, #18, #13, #8, #6,
           #5, #5, #5, #4, #4, #4, #3, #3, #3,
           #2, #2, #2, #2, #2, #2, #2, #2, #2, #2, #1].   ; frames a row, by level

; -- the sounds
turnTone   := tone:make(#300, #30).
landTone   := tone:make(#150, #50).
lineTone   := tone:make(#500, #150).
tetrisTone := tone:make(#800, #300).
levelTone  := tone:make(#1000, #150).
overTone   := tone:make(#80, #600).

; -- the game
state := 'attract.                   ; 'attract  'playing  'clearing  'entry  'curtain  'over
score := #0. best := #0. lines := #0. level := #0.
well := [].                          ; rows of cells, row 1 at the top; 0 is empty, else a colour class
current := nil. next := nil. lastKind := #0.
dropIn := #0. softRows := #0.
das := #0. lastDir := #0.
waitIn := #0. full := []. curtainRow := #0.
i := #0. j := #0.

; ---------------------------------------------------------------------------
; The pieces. Each is its turns, clockwise from the way it enters, and each
; turn is four cells about a pivot, columns right and rows down; the entry
; turn of every piece sits in the top two rows. The three colour classes
; are the cartridge's: T, O and I are white, J and S are the level's first
; colour, Z and L its second.

piece := object:new.
piece:turns := nil. piece:hue := #1.
piece:make := { turns, hue | | p | p := self:new. p:turns := turns. p:hue := hue. p }.

kinds := [
    piece:make([[[#-1, #0], [#0, #0], [#1, #0], [#0, #1]],     ; T
                [[#0, #-1], [#-1, #0], [#0, #0], [#0, #1]],
                [[#0, #-1], [#-1, #0], [#0, #0], [#1, #0]],
                [[#0, #-1], [#0, #0], [#1, #0], [#0, #1]]], #1),
    piece:make([[[#-1, #0], [#0, #0], [#1, #0], [#1, #1]],     ; J
                [[#0, #-1], [#0, #0], [#0, #1], [#-1, #1]],
                [[#-1, #-1], [#-1, #0], [#0, #0], [#1, #0]],
                [[#0, #-1], [#1, #-1], [#0, #0], [#0, #1]]], #2),
    piece:make([[[#-1, #0], [#0, #0], [#0, #1], [#1, #1]],     ; Z
                [[#1, #-1], [#0, #0], [#1, #0], [#0, #1]]], #3),
    piece:make([[[#-1, #0], [#0, #0], [#-1, #1], [#0, #1]]], #1),   ; O
    piece:make([[[#0, #0], [#1, #0], [#-1, #1], [#0, #1]],     ; S
                [[#0, #-1], [#0, #0], [#1, #0], [#1, #1]]], #2),
    piece:make([[[#-1, #0], [#0, #0], [#1, #0], [#-1, #1]],    ; L
                [[#0, #-1], [#0, #0], [#0, #1], [#-1, #-1]],
                [[#1, #-1], [#-1, #0], [#0, #0], [#1, #0]],
                [[#0, #-1], [#0, #0], [#0, #1], [#1, #1]]], #3),
    piece:make([[[#-2, #0], [#-1, #0], [#0, #0], [#1, #0]],    ; I
                [[#0, #-2], [#0, #-1], [#0, #0], [#0, #1]]], #1)].

; The one falling: which kind, which turn, and where the pivot is.
falling := object:new.
falling:kind := #1. falling:turn := #1. falling:col := #6. falling:row := #1.
falling:make := { kind | | f |
    f := self:new. f:kind := kind. f:turn := #1. f:col := #6. f:row := #1. f }.
falling:cells := { kinds:at(self:kind):turns:at(self:turn) }.
falling:hue := { kinds:at(self:kind):hue }.

; Would the piece fit at a turn and a place: every cell between the walls,
; above the floor and on nothing. A cell may stand above the well, which
; is how a piece turns in the top row; it is not drawn there.
falling:fits := { turn, col, row |
    kinds:at(self:kind):turns:at(turn):inject(true, { ok, c | | ci, cj |
        ci := @expr(col + c:at(#1)). cj := @expr(row + c:at(#2)).
        ok:and({ @expr(ci >= #1 & ci <= cols & cj <= rows) })
          :and({ cj:lessThan(#1):or({ well:at(cj):at(ci):equals(#0) }) }) }) }.

; Moved, if it fits; answers whether it did.
falling:shift := { by |
    self:fits(self:turn, @expr(self:col + by), self:row):ifElse(
        { self:col := @expr(self:col + by). true }, { false }) }.
falling:fall := {
    self:fits(self:turn, self:col, self:row:inc):ifElse(
        { self:row := self:row:inc. true }, { false }) }.
falling:rotate := { by | | n, t |
    n := kinds:at(self:kind):turns:size.
    t := @expr((self:turn - #1 + by + n):mod(n) + #1).
    self:fits(t, self:col, self:row):ifElse({ self:turn := t. true }, { false }) }.

; ---------------------------------------------------------------------------
; The well

emptyRow := { | r | r := []. cols:repeat({ r:add(#0) }). r }.
emptyWell := { | w | w := []. rows:repeat({ w:add(emptyRow:value) }). w }.

; The piece written in, where it lies; a cell above the well is lost.
land := {
    current:cells:do({ c | | cj |
        cj := @expr(current:row + c:at(#2)).
        cj:greaterOrEqual(#1):ifTrue({
            well:at(cj):atPut(@expr(current:col + c:at(#1)), current:hue) }) }) }.

; The rows with no gap, top first.
fullRows := { | found |
    found := [].
    [#1, rows]:loop({ cj |
        well:at(cj):inject(true, { ok, v | ok:and({ v:greaterThan(#0) }) }):ifTrue({ found:add(cj) }) }).
    found }.

; The full rows taken out and as many empty ones put in at the top.
collapse := { | kept, w |
    kept := [].
    [#1, rows]:loop({ cj | full:indexOf(cj):isNil:ifTrue({ kept:add(well:at(cj)) }) }).
    w := [].
    full:size:repeat({ w:add(emptyRow:value) }).
    kept:do({ r | w:add(r) }).
    well := w }.

; ---------------------------------------------------------------------------
; Words, in the same cells as the digits. Only the letters the five words
; use; a sixth word would add its letters here.

letters := #[
    "C" = ["###", "#..", "#..", "#..", "###"],
    "E" = ["###", "#..", "##.", "#..", "###"],
    "I" = ["###", ".#.", ".#.", ".#.", "###"],
    "L" = ["#..", "#..", "#..", "#..", "###"],
    "N" = ["##.", "#.#", "#.#", "#.#", "#.#"],
    "O" = ["###", "#.#", "#.#", "#.#", "###"],
    "P" = ["###", "#.#", "###", "#..", "#.."],
    "R" = ["###", "#.#", "##.", "#.#", "#.#"],
    "S" = ["###", "#..", "###", "..#", "###"],
    "T" = ["###", ".#.", ".#.", ".#.", ".#."],
    "V" = ["#.#", "#.#", "#.#", "#.#", ".#."],
    "X" = ["#.#", "#.#", ".#.", "#.#", "#.#"]].
glyphs := dictionary:new.
["C", "E", "I", "L", "N", "O", "P", "R", "S", "T", "V", "X"]:do({ ch |
    glyphs:atPut(ch, sprite:make(letters:at(ch), font:cell)) }).

; A word with its top-left at (left, top).
label := { text, left, top | | k |
    k := #1.
    { k:lessOrEqual(text:size) }:whileTrue({
        glyphs:at(text:at(k)):paint(@expr(left + (k - #1) * #4 * font:cell), top).
        k := k:inc }) }.

; ---------------------------------------------------------------------------
; The tune: notes as a pitch and a length in eighths, twelve frames each,
; stepped by the frame. A note asks for the channel with `hum`, so a sound
; of the game's cuts it off and the tune comes back at its next note.

eighth := #12.                       ; frames
tune := object:new.
tune:notes := [
    [#659, #2], [#494, #1], [#523, #1], [#587, #2], [#523, #1], [#494, #1],
    [#440, #2], [#440, #1], [#523, #1], [#659, #2], [#587, #1], [#523, #1],
    [#494, #3], [#523, #1], [#587, #2], [#659, #2],
    [#523, #2], [#440, #2], [#440, #2], [#0, #2],
    [#0, #1], [#587, #2], [#698, #1], [#880, #2], [#784, #1], [#698, #1],
    [#659, #3], [#523, #1], [#659, #2], [#587, #1], [#523, #1],
    [#494, #2], [#494, #1], [#523, #1], [#587, #2], [#659, #2],
    [#523, #2], [#440, #2], [#440, #2], [#0, #2],
    [#330, #4], [#262, #4], [#294, #4], [#247, #4],
    [#262, #4], [#220, #4], [#208, #4], [#247, #4],
    [#330, #4], [#262, #4], [#294, #4], [#247, #4],
    [#262, #2], [#330, #2], [#440, #4], [#440, #4], [#415, #8], [#0, #2]]:collect({ n |
        [n:at(#1):equals(#0):ifElse({ nil }, { tone:make(n:at(#1), @expr(n:at(#2) * eighth * #16 - #16)) }),
         @expr(n:at(#2) * eighth)] }).
tune:index := #0. tune:left := #0.
tune:restart := { self:index := #0. self:left := #0 }.
tune:step := { | note |
    self:left := self:left:dec.
    self:left:lessOrEqual(#0):ifTrue({
        self:index := @expr(self:index:mod(self:notes:size) + #1).
        note := self:notes:at(self:index).
        self:left := note:at(#2).
        note:at(#1):notNil:ifTrue({ note:at(#1):hum }) }) }.

; ---------------------------------------------------------------------------
; What happens

; Frames a row at this level; 29 and past are the same.
speed := { | l | l := level. l:greaterThan(#29):ifTrue({ l := #29 }). speeds:at(l:inc) }.

; The next piece: one of eight, and one of seven again when that was the
; eighth or the same as the last.
deal := { | k |
    k := rng:upTo(#8).
    k:equals(#8):or({ k:equals(lastKind) }):ifTrue({ k := rng:upTo(#7) }).
    lastKind := k.
    k }.

; A piece enters, or cannot, and that is the game.
enter := {
    current := falling:make(next).
    next := deal:value.
    dropIn := speed:value.
    softRows := #0.
    current:fits(current:turn, current:col, current:row):ifElse(
        { state := 'playing },
        { land:value. current := nil.
          state := 'curtain. curtainRow := #0. waitIn := curtainRate.
          overTone:play }) }.

newGame := {
    score := #0. lines := #0. level := #0.
    well := emptyWell:value.
    lastKind := #0. next := deal:value.
    das := #0. lastDir := #0.
    tune:restart.
    enter:value }.

; Landed: written in, the drop paid, and the full rows found.
settle := {
    land:value.
    score := @expr(score + softRows).
    current := nil.
    full := fullRows:value.
    full:size:greaterThan(#0):ifElse(
        { state := 'clearing. waitIn := clearDelay.
          full:size:equals(#4):ifElse({ tetrisTone:play }, { lineTone:play }) },
        { state := 'entry. waitIn := entryDelay. landTone:play }) }.

; The full rows gone: the score, the count, and the level.
scoreLines := { | before |
    collapse:value.
    lines := @expr(lines + full:size).
    before := level.
    level := lines:div(#10).
    score := @expr(score + lineScores:at(full:size) * (level + #1)).
    level:greaterThan(before):ifTrue({ levelTone:play }).
    full := [] }.

; Left and Right: a move on the frame the key goes down, and the repeat.
shift := { | dir |
    dir := #0.
    keys:any(leftKeys):ifTrue({ dir := #-1 }).
    keys:any(rightKeys):ifTrue({ dir := #1 }).
    dir:equals(#0):ifElse(
        { das := #0. lastDir := #0 },
        { dir:equals(lastDir):ifElse(
            { das := das:inc.
              das:greaterOrEqual(dasDelay):ifTrue({ current:shift(dir). das := @expr(dasDelay - dasRate) }) },
            { current:shift(dir). das := #0. lastDir := dir }) }) }.

; Gravity, and the soft drop over it.
fall := {
    keys:any(downKeys):ifElse(
        { frames:mod(#2):equals(#0):ifTrue({
              current:fall:ifElse({ softRows := softRows:inc }, { settle:value }) }) },
        { dropIn := dropIn:dec.
          dropIn:lessOrEqual(#0):ifTrue({
              dropIn := speed:value.
              current:fall:ifFalse({ settle:value }) }) }) }.

; ---------------------------------------------------------------------------
; Drawing. The level's two colours are the cartridge's, cycling by ten;
; a white cell has the first for its rim, a coloured one a white corner.

palette := [[[#0, #88, #248], [#60, #188, #252]],
            [[#0, #168, #0], [#184, #248, #24]],
            [[#216, #0, #204], [#248, #120, #248]],
            [[#0, #88, #248], [#88, #216, #84]],
            [[#228, #0, #88], [#88, #248, #152]],
            [[#88, #248, #152], [#104, #136, #252]],
            [[#248, #56, #0], [#124, #124, #124]],
            [[#104, #68, #252], [#168, #0, #32]],
            [[#0, #88, #248], [#248, #56, #0]],
            [[#248, #56, #0], [#252, #160, #68]]].
colourOf := { which | | pair |
    pair := palette:at(level:mod(#10):inc).
    which:equals(#2):ifElse({ pair:at(#1) }, { pair:at(#2) }) }.
paintCell := { px, py, hue | | c |
    hue:equals(#1):ifElse(
        { c := colourOf:value(#2).
          sdl:colour(screen, c:at(#1), c:at(#2), c:at(#3)).
          sdl:fill(screen, px:inc, py:inc, @expr(cell - #2), @expr(cell - #2)).
          sdl:colour(screen, #252, #252, #252).
          sdl:fill(screen, @expr(px + #4), @expr(py + #4), @expr(cell - #8), @expr(cell - #8)) },
        { c := colourOf:value(hue).
          sdl:colour(screen, c:at(#1), c:at(#2), c:at(#3)).
          sdl:fill(screen, px:inc, py:inc, @expr(cell - #2), @expr(cell - #2)).
          sdl:colour(screen, #252, #252, #252).
          sdl:fill(screen, @expr(px + #3), @expr(py + #3), #4, #4) }) }.
cellAt := { ci, cj, hue |
    paintCell:value(@expr(wellLeft + (ci - #1) * cell), @expr(wellTop + (cj - #1) * cell), hue) }.

; ---------------------------------------------------------------------------

well := emptyWell:value.             ; the empty well, to look at before a game

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):and({ event:repeat:equals(#0) }):ifTrue({
            state:equals('playing):ifTrue({
                event:key:equals("Up"):or({ event:key:equals("X") }):ifTrue({
                    current:rotate(#1):ifTrue({ turnTone:play }) }).
                event:key:equals("Z"):ifTrue({
                    current:rotate(#-1):ifTrue({ turnTone:play }) }) }).
            state:equals('attract):or({ state:equals('over) }):and({ event:key:equals("Space") }):ifTrue({
                newGame:value }) }) }).

    ; -- the player
    state:equals('playing):ifTrue({
        shift:value.
        state:equals('playing):ifTrue({ fall:value }) }).

    ; -- a line going, from the middle out, then the next piece
    state:equals('clearing):ifTrue({
        waitIn := waitIn:dec.
        waitIn:mod(#4):equals(#0):ifTrue({
            i := @expr(waitIn / #4 + #1).
            full:do({ cj | well:at(cj):atPut(i, #0). well:at(cj):atPut(@expr(cols + #1 - i), #0) }) }).
        waitIn:equals(#0):ifTrue({ scoreLines:value. state := 'entry. waitIn := entryDelay }) }).
    state:equals('entry):ifTrue({
        waitIn := waitIn:dec.
        waitIn:equals(#0):ifTrue({ enter:value }) }).
    state:equals('playing):or({ state:equals('clearing) }):or({ state:equals('entry) }):ifTrue({
        tune:step }).

    ; -- the curtain
    state:equals('curtain):ifTrue({
        waitIn := waitIn:dec.
        waitIn:equals(#0):ifTrue({
            curtainRow := curtainRow:inc. waitIn := curtainRate.
            [#1, cols]:loop({ ci | well:at(curtainRow):atPut(ci, #4) }).
            curtainRow:equals(rows):ifTrue({
                state := 'over.
                score:greaterThan(best):ifTrue({ best := score }) }) }) }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #0, #0, #0).
    sdl:colour(screen, #124, #124, #124).
    sdl:fill(screen, @expr(wellLeft - #4), @expr(wellTop - #4), @expr(cols * cell + #8), #4).
    sdl:fill(screen, @expr(wellLeft - #4), @expr(wellTop + rows * cell), @expr(cols * cell + #8), #4).
    sdl:fill(screen, @expr(wellLeft - #4), wellTop, #4, @expr(rows * cell)).
    sdl:fill(screen, @expr(wellLeft + cols * cell), wellTop, #4, @expr(rows * cell)).
    [#1, rows]:loop({ cj |
        [#1, cols]:loop({ ci | | v |
            v := well:at(cj):at(ci).
            v:greaterThan(#0):ifTrue({
                v:equals(#4):ifElse(
                    { sdl:colour(screen, #124, #124, #124).
                      sdl:fill(screen, @expr(wellLeft + (ci - #1) * cell + #1),
                                       @expr(wellTop + (cj - #1) * cell + #1),
                                       @expr(cell - #2), @expr(cell - #2)) },
                    { cellAt:value(ci, cj, v) }) }) }) }).
    current:notNil:ifTrue({
        current:cells:do({ c | | cj |
            cj := @expr(current:row + c:at(#2)).
            cj:greaterOrEqual(#1):ifTrue({
                cellAt:value(@expr(current:col + c:at(#1)), cj, current:hue) }) }) }).
    sdl:colour(screen, #252, #252, #252).
    label:value("LINES", #16, #48).  font:number(lines, #200, #78).
    label:value("SCORE", #16, #130). font:number(score, #200, #160).
    label:value("TOP", #16, #212).   font:number(best, #200, #242).
    label:value("NEXT", #440, #48).
    label:value("LEVEL", #440, #180). font:number(level, #600, #210).
    next:notNil:and({ state:equals('attract):not }):ifTrue({
        kinds:at(next):turns:at(#1):do({ c |
            paintCell:value(@expr(#480 + c:at(#1) * cell), @expr(#90 + c:at(#2) * cell),
                            kinds:at(next):hue) }) }).

    engine:show }).

"final score {}":fill([score]):display.
