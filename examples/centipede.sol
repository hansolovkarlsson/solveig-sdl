; centipede.sol -- the ninth game, the second drawn from a grid, and the
; second to move by the mouse or the keys, whichever moved last.
;
;     solvm --extension=build/sdl.so examples/centipede.sob
;
;   arrows / WASD  the shooter, in the bottom rows; the mouse moves it too
;   Space / click  fire; held, keeps firing, one shot on the screen
;   Space          when no game is on, start one
;   Escape         quit
;
; The 1981 rules. A field of mushrooms forty wide, each four shots to
; clear for a point. A centipede of a head and eleven segments comes in at
; the top, runs sideways, and drops a row and turns at a mushroom or an
; edge; in your rows it bounces up and down and stays. A segment shot
; becomes a mushroom, a head is 100 and a segment 10, and what was behind
; the shot grows a head of its own, so a centipede shot in the middle is
; two. A spider bounces about your rows eating mushrooms and is 300, 600
; or 900 by how close it was; a flea drops down a column when your rows
; run short of mushrooms, leaving more, and takes two shots for 200; a
; scorpion crosses higher up and poisons what it passes, and a head that
; touches a poisoned mushroom dives straight for your rows; 1,000 for the
; scorpion. Touching any of them costs a shooter, and every mushroom you
; had damaged is restored for 5 each before the next one; a shooter more
; every 12,000, three to start. Each wave the centipede comes in with a
; segment fewer and a loose head more, and faster. Two things the cabinet
; had that this does not: the mirrored field on the second player's turn,
; and the attract's demo.
;
; **What was predicted before this was written.** That the field is a grid
; of counts as Tetris's well was a grid of colours, and the second game
; drawn from a table rather than from things, with the centipede reading
; the table as its walls (it was, and the reading of ten made `grid` the
; engine's, with the two games' tables on it); that a segment is a cell and a direction and not
; a mover, since it moves a cell at a time on a tick, and the chain moves
; by each segment taking the cell of the one ahead; that the spider, the
; flea and the scorpion are `mover`s bare as Missile's were, since they
; move by pixels and wrap nowhere; that `sprite` carries its third game
; with ten pictures; that `keys` is back, with the shooter held by four
; keys and the mouse under Breakout's rule, whichever moved last, which
; gives that rule its second game; that `font:number` draws the score
; and `font:word` nothing, the first game since Lander with no word; and
; that the binding would be asked for nothing.
;
; The tones are pitches chosen for this file.

@include "engine.sol".

engine:open("centipede", #640, #480).

; -- the field
cols := #40. rows := #30.
cell := #16.                         ; one cell, in pixels
fieldTop := #3.                      ; rows 1 and 2 are the score's
zoneTop := #24.                      ; your rows, to the bottom
upKeys := ["Up", "W"]. downKeys := ["Down", "S"].

; -- the rules
shooterSpeed := #3.
shotSpeed := #8.
segmentsAtStart := #11.
mushroomsAtStart := #30.
fleaWhen := #5.                      ; mushrooms in your rows below which the flea comes
lifeEvery := #12000.

; -- the sounds
shotTone   := tone:make(#900, #20).
hitTone    := tone:make(#200, #20).
segTone    := tone:make(#400, #40).
headTone   := tone:make(#600, #60).
spiderTone := tone:make(#150, #40).
fleaTone   := tone:make(#300, #40).
scorpTone  := tone:make(#80, #40).
deathTone  := tone:make(#60, #500).
tickTone   := tone:make(#1000, #20).
lifeTone   := tone:make(#1200, #200).

; -- the game
state := 'attract.                   ; 'attract  'playing  'restoring  'over
score := #0. lives := #0. wave := #0. nextLife := lifeEvery.
field := nil.                        ; a grid of counts: 0 none, 1 to 4 a mushroom, 11 to 14 poisoned
chains := [].                        ; each a list of segments, head first
shooter := nil. shot := nil.
spider := nil. flea := nil. scorpion := nil.
spiderIn := #0. scorpionIn := #0. headIn := #0.

fireHeld := false.
pace := #8.                          ; frames a cell, the centipede's
restoreRow := #0. restoreCol := #0. restoreIn := #0.
shown := #0. shownAt := #0. shownIn := #0.
i := #0.

; ---------------------------------------------------------------------------
; The pictures, eight cells square at two pixels a cell.

pic := #2.
mushroomSprites := [
    sprite:make([".....#..", "....###.", "....##..", "...##...", "...##...", "...##...", "...##...", "...##..."], pic),
    sprite:make(["...###..", "....###.", "...####.", "...####.", "...##...", "...##...", "...##...", "...##..."], pic),
    sprite:make(["..####..", ".######.", ".#######", "...####.", "...##...", "...##...", "...##...", "...##..."], pic),
    sprite:make(["..####..", ".######.", "########", "########", "...##...", "...##...", "...##...", "...##..."], pic)].
headSprite := sprite:make(["..####..", ".#.##.#.", "########", "#.####.#", "########", ".######.", "..#..#..", ".#....#."], pic).
bodySprite := sprite:make(["..####..", ".######.", "########", "########", "########", ".######.", "..#..#..", ".#....#."], pic).
shooterSprite := sprite:make(["...##...", "..####..", "..####..", "...##...", ".######.", "########", "########", "..#..#.."], pic).
spiderSprite := sprite:make(["#......#", ".#.##.#.", "..####..", ".##..##.", "########", "#.####.#", "#.#..#.#", "#......#"], pic).
fleaSprite := sprite:make(["..####..", ".##.###.", "########", ".######.", "..#.#.#.", ".#..#..#", "#......#", "........"], pic).
scorpionSprite := sprite:make([".....#..", "....##..", "....#...", "###.#..#", "########", ".######.", "#.#..#.#", "#......#"], pic).

; The wave's colours, five sets: mushrooms, the centipede, the shooter and
; the shot, the spider and the rest. (The reading of ten moved `tint` into
; the engine; the table stays here.)
tint:sets := [[[#0, #200, #0],    [#248, #80, #80],  [#248, #248, #80], [#180, #120, #248]],
             [[#248, #120, #0],  [#80, #200, #248], [#248, #248, #248], [#80, #248, #80]],
             [[#200, #0, #200],  [#248, #200, #0],  [#80, #248, #200], [#248, #120, #80]],
             [[#80, #120, #248], [#248, #80, #200], [#248, #248, #80], [#80, #248, #248]],
             [[#248, #200, #80], [#80, #248, #80],  [#248, #80, #80],  [#200, #200, #248]]].

; ---------------------------------------------------------------------------
; The field: a grid of counts, and the questions asked of it. (The grid
; itself is the engine's since the reading of ten; the questions are this
; game's.)

leftOf := { col | @expr((col - #1) * cell) }.  ; a column's left edge
topOf := { row | @expr((row - #1) * cell) }.   ; a row's top edge
colOf := { x | @expr(x / cell + #1) }.         ; the column a pixel is in
rowOf := { y | @expr(y / cell + #1) }.

inField := { col, row | @expr(col >= #1 & col <= cols & row >= fieldTop & row <= rows) }.
hasMushroom := { col, row | inField:value(col, row):and({ field:at(col, row):greaterThan(#0) }) }.
isPoisoned := { col, row | inField:value(col, row):and({ field:at(col, row):greaterThan(#10) }) }.

; Some mushrooms, above your rows, to begin with.
seedField := {
    field := grid:make(cols, rows).
    mushroomsAtStart:repeat({
        field:atPut(rng:upTo(cols), rng:between(fieldTop, @expr(zoneTop - #1)), #4) }) }.

; Mushrooms in your rows, which is what the flea watches.
zoneMushrooms := { | n |
    n := #0.
    [zoneTop, rows]:loop({ r | [#1, cols]:loop({ c | hasMushroom:value(c, r):ifTrue({ n := n:inc }) }) }).
    n }.

; ---------------------------------------------------------------------------
; The centipede: segments in chains, head first. A segment is a cell, a
; sideways direction and an up-or-down one; a body segment takes the cell
; of the one ahead on each tick, and keeps its directions so that it can
; become a head.

segment := object:new.
segment:col := #1. segment:row := #1. segment:dir := #1. segment:vdir := #1.
segment:head := false. segment:diving := false.
segment:make := { col, row, dir, head | | s |
    s := self:new. s:col := col. s:row := row. s:dir := dir. s:vdir := #1. s:head := head. s }.

; A whole centipede at the top, or a loose head, from one side.
newChain := { length, fromLeft | | c, k |
    c := [].
    k := #0.
    length:repeat({
        c:add(segment:make(fromLeft:ifElse({ @expr(#1 - k) }, { @expr(cols + k) }), fieldTop,
                           fromLeft:ifElse({ #1 }, { #-1 }), k:equals(#0))).
        k := k:inc }).
    c }.

; The head's next cell: sideways if it can, else down (or up, in your
; rows) and turned; straight down while diving.
headStep := { h | | nc, nr |
    h:diving:ifElse(
        { h:row := h:row:inc.
          h:row:greaterOrEqual(rows):ifTrue({ h:row := rows. h:diving := false. h:vdir := #-1 }) },
        { nc := @expr(h:col + h:dir).
          @expr(nc < #1 | nc > cols):or({ hasMushroom:value(nc, h:row) }):ifElse(
              { isPoisoned:value(nc, h:row):ifTrue({ h:diving := true }).
                nr := @expr(h:row + h:vdir).
                nr:greaterThan(rows):ifTrue({ h:vdir := #-1. nr := @expr(rows - #1) }).
                nr:lessThan(zoneTop):and({ h:vdir:equals(#-1) }):ifTrue({ h:vdir := #1. nr := @expr(zoneTop + #1) }).
                nr:lessThan(fieldTop):ifTrue({ nr := fieldTop }).
                h:row := nr. h:dir := h:dir:negated },
              { h:col := nc }) }) }.

; One tick of a chain: the body follows, then the head moves.
chainStep := { c | | k, ahead, s |
    k := c:size.
    { k:greaterThan(#1) }:whileTrue({
        s := c:at(k). ahead := c:at(k:dec).
        s:col := ahead:col. s:row := ahead:row. s:dir := ahead:dir. s:vdir := ahead:vdir.
        k := k:dec }).
    headStep:value(c:at(#1)) }.

; A segment shot: a mushroom where it was, and the chain in two.
shootSegment := { c, k | | s, before, after |
    s := c:at(k).
    s:head:ifElse({ score := @expr(score + #100). headTone:play },
                  { score := @expr(score + #10). segTone:play }).
    inField:value(s:col, s:row):ifTrue({ field:atPut(s:col, s:row, #4) }).
    before := k:equals(#1):ifElse({ [] }, { c:copyFrom(#1, k:dec) }).
    after := k:equals(c:size):ifElse({ [] }, { c:copyFrom(k:inc, c:size) }).
    after:size:greaterThan(#0):ifTrue({ after:at(#1):head := true }).
    chains := chains:select({ x | x:equals(c):not }).
    before:size:greaterThan(#0):ifTrue({ chains:add(before) }).
    after:size:greaterThan(#0):ifTrue({ chains:add(after) }) }.

segmentsLeft := { chains:inject(#0, { n, c | @expr(n + c:size) }) }.
anyInZone := { chains:inject(false, { seen, c | seen:or({ c:at(#1):row:greaterOrEqual(zoneTop) }) }) }.

; ---------------------------------------------------------------------------
; The shooter, and the shot. The shooter is a box in your rows that a
; mushroom stops; the shot is a line that goes up until it hits something.

shooter := rect:make(#312, #448, cell, cell).
shooter:tryX := { nx | | c, r |
    c := colOf:value(@expr(nx + cell / #2)). r := rowOf:value(@expr(self:y + cell / #2)).
    @expr(nx >= #0 & nx <= width - cell):and({ hasMushroom:value(c, r):not }):ifTrue({ self:x := nx }) }.
shooter:tryY := { ny | | c, r |
    c := colOf:value(@expr(self:x + cell / #2)). r := rowOf:value(@expr(ny + cell / #2)).
    @expr(ny >= (zoneTop - #1) * cell & ny <= height - cell):and({ hasMushroom:value(c, r):not }):ifTrue({ self:y := ny }) }.
shooter:col := { colOf:value(@expr(self:x + cell / #2)) }.
shooter:row := { rowOf:value(@expr(self:y + cell / #2)) }.

fire := {
    shot:isNil:ifTrue({
        shot := rect:make(@expr(shooter:x + cell / #2 - #1), @expr(shooter:y - #8), #2, #8).
        shotTone:play }) }.

; ---------------------------------------------------------------------------
; The three visitors, movers by the pixel.

; The spider: in and about your rows, eating what it crosses.
spiderThing := mover:new.
spiderThing:turnIn := #0.
spiderThing:make := { | s |
    s := self:new.
    s:y := @expr(((zoneTop - #3) + rng:upTo(#6)) * cell):asFloat.
    rng:upTo(#2):equals(#1):ifElse({ s:x := -16.0. s:vx := 1.5 }, { s:x := fw. s:vx := -1.5 }).
    s:vy := 1.5. s:turnIn := #20.
    s }.
spiderThing:step := { | top, bottom |
    self:move.
    top := @expr((zoneTop - #4) * cell):asFloat. bottom := @expr(height - cell):asFloat.
    self:y:lessThan(top):ifTrue({ self:y := top. self:vy := self:vy:abs }).
    self:y:greaterThan(bottom):ifTrue({ self:y := bottom. self:vy := self:vy:abs:negated }).
    self:turnIn := self:turnIn:dec.
    self:turnIn:equals(#0):ifTrue({
        self:turnIn := @expr(#10 + rng:upTo(#30)).
        self:vy := [1.5, -1.5, 0.0]:at(rng:upTo(#3)).
        rng:upTo(#4):equals(#1):ifTrue({ self:vx := self:vx:negated }) }).
    hasMushroom:value(self:col, self:row):ifTrue({ field:atPut(self:col, self:row, #0) }).
    @expr(self:x < -20.0 | self:x > fw + 20.0):ifTrue({ self:alive := false }) }.
spiderThing:col := { colOf:value(@expr(self:x:truncated + cell / #2)) }.
spiderThing:row := { rowOf:value(@expr(self:y:truncated + cell / #2)) }.

; The flea: straight down a column, leaving mushrooms; two shots.
fleaThing := mover:new.
fleaThing:hits := #0. fleaThing:lastRow := #0.
fleaThing:make := { | f |
    f := self:new. f:x := @expr((rng:upTo(cols) - #1) * cell):asFloat. f:y := @expr((fieldTop - #1) * cell):asFloat.
    f:vy := 3.0. f:hits := #0. f:lastRow := #0. f }.
fleaThing:step := { | r |
    self:move.
    r := self:row.
    r:equals(self:lastRow):ifFalse({
        self:lastRow := r.
        r:lessThan(rows):and({ rng:upTo(#3):equals(#1) }):and({ hasMushroom:value(self:col, r):not }):ifTrue({
            field:atPut(self:col, r, #4) }) }).
    self:y:greaterThan(fh):ifTrue({ self:alive := false }) }.
fleaThing:col := { colOf:value(@expr(self:x:truncated + cell / #2)) }.
fleaThing:row := { rowOf:value(@expr(self:y:truncated + cell / #2)) }.

; The scorpion: across a row above your rows, poisoning what it passes.
scorpionThing := mover:new.
scorpionThing:make := { | s |
    s := self:new.
    s:y := @expr((rng:between(fieldTop, @expr(zoneTop - #4)) - #1) * cell):asFloat.
    rng:upTo(#2):equals(#1):ifElse({ s:x := -16.0. s:vx := 2.0 }, { s:x := fw. s:vx := -2.0 }).
    s }.
scorpionThing:step := {
    self:move.
    hasMushroom:value(self:col, self:row):and({ isPoisoned:value(self:col, self:row):not }):ifTrue({
        field:atPut(self:col, self:row, @expr(field:at(self:col, self:row) + #10)) }).
    @expr(self:x < -20.0 | self:x > fw + 20.0):ifTrue({ self:alive := false }) }.
scorpionThing:col := { colOf:value(@expr(self:x:truncated + cell / #2)) }.
scorpionThing:row := { rowOf:value(@expr(self:y:truncated + cell / #2)) }.

; A visitor's box, for the shot and the shooter to touch.
boxOf := { m | rect:make(@expr(m:x:truncated + #2), @expr(m:y:truncated + #2), @expr(cell - #4), @expr(cell - #4)) }.

; ---------------------------------------------------------------------------
; What happens

startWave := { | loose |
    wave := wave:inc.
    tint:set := @expr((wave - #1):mod(#5) + #1).
    pace := @expr(#8 - (wave - #1) / #2). pace:lessThan(#3):ifTrue({ pace := #3 }).
    chains := [].
    loose := @expr((wave - #1):mod(#12)).
    chains:add(newChain:value(@expr(segmentsAtStart + #1 - loose), rng:upTo(#2):equals(#1))).
    loose:repeat({ chains:add(newChain:value(#1, rng:upTo(#2):equals(#1))) }).
    spider := nil. flea := nil. scorpion := nil. shot := nil.
    spiderIn := @expr(#300 + rng:upTo(#300)). scorpionIn := @expr(#900 + rng:upTo(#600)). headIn := #420 }.

newGame := {
    score := #0. lives := #3. wave := #0. nextLife := lifeEvery.
    seedField:value.
    shooter:x := #312. shooter:y := #448.
    startWave:value.
    state := 'playing }.

earn := { points |
    score := @expr(score + points).
    score:greaterOrEqual(nextLife):ifTrue({ lives := lives:inc. nextLife := @expr(nextLife + lifeEvery). lifeTone:play }) }.

; The shooter lost: the visitors leave, and the field is restored one
; mushroom at a time before the next shooter, or the game is over.
die := {
    lives := lives:dec. deathTone:play.
    spider := nil. flea := nil. scorpion := nil. shot := nil.
    state := 'restoring. restoreRow := fieldTop. restoreCol := #1. restoreIn := #60 }.
restore := { | v |
    restoreIn := restoreIn:dec.
    restoreIn:lessOrEqual(#0):ifTrue({
        { restoreRow:lessOrEqual(rows):and({ field:at(restoreCol, restoreRow):equals(#0):or({ field:at(restoreCol, restoreRow):equals(#4) }) }) }:whileTrue({
            restoreCol := restoreCol:inc.
            restoreCol:greaterThan(cols):ifTrue({ restoreCol := #1. restoreRow := restoreRow:inc }) }).
        restoreRow:lessOrEqual(rows):ifElse(
            { field:atPut(restoreCol, restoreRow, #4). earn:value(#5). tickTone:play. restoreIn := #3 },
            { lives:equals(#0):ifElse(
                { state := 'over },
                { wave := wave:dec. startWave:value. shooter:x := #312. shooter:y := #448. state := 'playing }) }) }) }.

; The shot against everything above it, nearest first: the cell it is in
; for mushrooms and segments, the box for the visitors.
shotHits := { | c, r, hit |
    c := colOf:value(shot:x). r := rowOf:value(shot:y).
    hit := false.
    hasMushroom:value(c, r):ifTrue({
        hit := true. hitTone:play.
        isPoisoned:value(c, r):ifElse(
            { field:atPut(c, r, @expr(field:at(c, r) - #1)). field:at(c, r):equals(#10):ifTrue({ field:atPut(c, r, #0). earn:value(#1) }) },
            { field:atPut(c, r, @expr(field:at(c, r) - #1)). field:at(c, r):equals(#0):ifTrue({ earn:value(#1) }) }) }).
    hit:ifFalse({
        chains:select({ x | true }):do({ ch | | k |
            k := #1.
            { hit:not:and({ k:lessOrEqual(ch:size) }) }:whileTrue({
                ch:at(k):col:equals(c):and({ ch:at(k):row:equals(r) }):ifTrue({ hit := true. shootSegment:value(ch, k) }).
                k := k:inc }) }) }).
    hit:not:and({ spider:notNil }):and({ shot:touches(boxOf:value(spider)) }):ifTrue({ | d |
        hit := true.
        d := @expr(spider:row - shooter:row):abs.
        shown := d:lessThan(#2):ifElse({ #900 }, { d:lessThan(#4):ifElse({ #600 }, { #300 }) }).
        shownAt := spider:x:truncated. shownIn := #60.
        earn:value(shown). spider := nil. headTone:play }).
    hit:not:and({ flea:notNil }):and({ shot:touches(boxOf:value(flea)) }):ifTrue({
        hit := true. flea:hits := flea:hits:inc. flea:vy := 6.0. hitTone:play.
        flea:hits:equals(#2):ifTrue({ earn:value(#200). flea := nil. headTone:play }) }).
    hit:not:and({ scorpion:notNil }):and({ shot:touches(boxOf:value(scorpion)) }):ifTrue({
        hit := true. earn:value(#1000). scorpion := nil. headTone:play }).
    hit }.

; Anything touching the shooter kills it.
touched := { | c, r, dead |
    c := shooter:col. r := shooter:row. dead := false.
    chains:do({ ch | ch:do({ s | s:col:equals(c):and({ s:row:equals(r) }):ifTrue({ dead := true }) }) }).
    spider:notNil:and({ shooter:touches(boxOf:value(spider)) }):ifTrue({ dead := true }).
    flea:notNil:and({ shooter:touches(boxOf:value(flea)) }):ifTrue({ dead := true }).
    dead }.

; ---------------------------------------------------------------------------

seedField:value.                     ; a field, to look at before a game

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('mouseMove):ifTrue({
            shooter:tryX(@expr(event:x - cell / #2)). shooter:tryY(@expr(event:y - cell / #2)) }).
        event:kind:equals('mouseDown):and({ event:button:equals(#1) }):ifTrue({ fireHeld := true }).
        event:kind:equals('mouseUp):and({ event:button:equals(#1) }):ifTrue({ fireHeld := false }).
        event:kind:equals('keyDown):and({ event:key:equals("Space") }):and({ event:repeat:equals(#0) }):ifTrue({
            state:equals('attract):or({ state:equals('over) }):ifTrue({ newGame:value }) }) }).

    ; -- the player
    state:equals('playing):ifTrue({
        keys:any(leftKeys):ifTrue({ shooter:tryX(@expr(shooter:x - shooterSpeed)) }).
        keys:any(rightKeys):ifTrue({ shooter:tryX(@expr(shooter:x + shooterSpeed)) }).
        keys:any(upKeys):ifTrue({ shooter:tryY(@expr(shooter:y - shooterSpeed)) }).
        keys:any(downKeys):ifTrue({ shooter:tryY(@expr(shooter:y + shooterSpeed)) }).
        fireHeld:or({ keys:down("Space") }):ifTrue({ fire:value }).

        ; -- the shot
        shot:notNil:ifTrue({
            shot:y := @expr(shot:y - shotSpeed).
            shot:y:lessThan(@expr((fieldTop - #1) * cell)):ifTrue({ shot := nil }) }).
        shot:notNil:ifTrue({ shotHits:value:ifTrue({ shot := nil }) }).

        ; -- the centipede, on its tick
        frames:mod(pace):equals(#0):ifTrue({ chains:do({ ch | chainStep:value(ch) }) }).
        anyInZone:value:ifTrue({
            headIn := headIn:dec.
            headIn:lessOrEqual(#0):ifTrue({
                chains:add([segment:make(rng:upTo(#2):equals(#1):ifElse({ #1 }, { cols }),
                                         rng:between(zoneTop, rows), #1, true)]).
                headIn := @expr(#420 + rng:upTo(#300)) }) }).

        ; -- the visitors
        spider:notNil:ifTrue({ spider:step. spiderTone:hum. spider:alive:ifFalse({ spider := nil }) }).
        spider:isNil:ifTrue({
            spiderIn := spiderIn:dec.
            spiderIn:lessOrEqual(#0):ifTrue({ spider := spiderThing:make. spiderIn := @expr(#400 + rng:upTo(#400)) }) }).
        flea:notNil:ifTrue({ flea:step. fleaTone:hum. flea:alive:ifFalse({ flea := nil }) }).
        flea:isNil:and({ frames:mod(#60):equals(#0) }):and({ zoneMushrooms:value:lessThan(fleaWhen) }):ifTrue({
            flea := fleaThing:make }).
        scorpion:notNil:ifTrue({ scorpion:step. scorpTone:hum. scorpion:alive:ifFalse({ scorpion := nil }) }).
        scorpion:isNil:and({ wave:greaterThan(#1) }):ifTrue({
            scorpionIn := scorpionIn:dec.
            scorpionIn:lessOrEqual(#0):ifTrue({ scorpion := scorpionThing:make. scorpionIn := @expr(#900 + rng:upTo(#900)) }) }).

        ; -- the wave, and the shooter
        segmentsLeft:value:equals(#0):ifTrue({ startWave:value }).
        touched:value:ifTrue({ die:value }) }).
    state:equals('restoring):ifTrue({ restore:value }).
    shownIn:greaterThan(#0):ifTrue({ shownIn := shownIn:dec }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #0, #0, #0).
    tint:value(#1).
    [fieldTop, rows]:loop({ r | | line |
        line := field:row(r).
        [#1, cols]:loop({ c | | v |
        v := line:at(c).
        v:greaterThan(#0):ifTrue({
            v:greaterThan(#10):ifElse({ tint:value(#4). v := @expr(v - #10) }, { tint:value(#1) }).
            mushroomSprites:at(v):paint(leftOf:value(c), topOf:value(r)) }) }) }).
    tint:value(#2).
    chains:do({ ch | ch:do({ s |
        s:head:ifElse({ headSprite:paint(leftOf:value(s:col), topOf:value(s:row)) },
                      { bodySprite:paint(leftOf:value(s:col), topOf:value(s:row)) }) }) }).
    tint:value(#4).
    spider:notNil:ifTrue({ spiderSprite:paint(spider:x:truncated, spider:y:truncated) }).
    flea:notNil:ifTrue({ fleaSprite:paint(flea:x:truncated, flea:y:truncated) }).
    scorpion:notNil:ifTrue({ scorpionSprite:paint(scorpion:x:truncated, scorpion:y:truncated) }).
    tint:value(#3).
    state:equals('over):ifFalse({ shooterSprite:paint(shooter:x, shooter:y) }).
    shot:notNil:ifTrue({ shot:paint }).
    sdl:colour(screen, #248, #248, #248).
    state:equals('attract):ifFalse({
        font:number(score, #400, #1).
        i := #0.
        { i:lessThan(lives) }:whileTrue({ shooterSprite:paint(@expr(#8 + i * #20), #8). i := i:inc }) }).
    shownIn:greaterThan(#0):ifTrue({ font:number(shown, @expr(shownAt + #40), @expr((zoneTop - #5) * cell)) }).

    engine:show }).

"final score {}":fill([score]):display.
