; invaders.sol -- the fourth game, and the one the first reading said would
; push on the binding, because an invader is a picture and nothing here
; draws a picture.
;
;     solvm --extension=build/sdl.so examples/invaders.sob
;
;   Left / Right   the cannon; A / D do the same
;   Space          fire; when no game is on, start one
;   Escape         quit
;
; The 1978 rules. Fifty-five invaders in five rows of eleven, three kinds
; worth 30, 20 and 10, two frames each. They step sideways as a block, one
; invader a frame, so the block ripples and quickens as it thins; at an
; edge the next pass drops a row and turns round. One shot in the air at a
; time for you, three bombs at a time from them, dropped by the lowest
; invader of a column. Four bunkers that lose a bite where a shot or a
; bomb lands and are trampled where the invaders reach them. A mystery
; ship across the top now and then, worth 50, 100 or 150, or 300 on the
; twenty-third shot and every fifteenth after. Three cannons and one more
; at 1,500. They win if they reach the ground. The next wave starts a row
; lower. Two things the original had that this does not: the three bombs
; are one drawing here, and the mystery ship's siren is a beep.
;
; **What was predicted before this was written.** That the file would not
; ask the binding for anything, even here, because a picture at this scale
; is rows of text compiled once to horizontal runs and a run is one
; `sdl:fill`: fifty-five invaders are about six hundred fills a frame and
; not three thousand, and a bunker that erodes is a grid of cells whose
; runs are recomputed only when it is bitten. If that turned out to be over
; the frame, the trigger would be met by a measurement and the message
; asked for would be *a bitmap in one call*, not a texture. And that of the
; engine's seven names, `rect` would carry its third game (everything here
; is an integer rectangle that steps), `mover` and `ball` would not (nothing
; here is a float), and the font would turn out to be the special case of
; the sprite: a digit is a 3x5 picture drawn the slow way.
;
; **What was here that no game had**: a sprite, which is what `font:digit`
; did, done once at start rather than every frame, and which the reading of
; four moved into the engine with the font over it; a picture that changes,
; the bunker, which is cells and a sprite rebuilt from them; and a block of
; things that moves one thing a frame, which is the original's whole feel
; and costs nothing to write.
;
; The tones are pitches chosen for this file; the four notes of the march
; are the original's descending four.

@include "engine.sol".

engine:open("invaders", #640, #480).

cell := #2.                          ; one picture cell, in pixels
ground := #456.
rng := random:new.

leftKeys := ["Left", "A"]. rightKeys := ["Right", "D"].

; -- the cannon
cannonSpeed := #3.
cannonY := #424.
shotSpeed := #8.
bombSpeed := #3.
bombsMost := #3.

; -- the invaders
columns := #11. rows := #5.
pitch := #32.                        ; between columns and between rows
stepX := #4.                         ; a sideways step
stepY := #16.                        ; a drop
kindPoints := [#30, #20, #10].       ; squid, crab, octopus
rowKinds := [#1, #2, #2, #3, #3].    ; top row first
edgeLeft := #16. edgeRight := #624.

; -- the sounds
fireTone  := tone:make(#500, #30).
hitTone   := tone:make(#120, #60).
deathTone := tone:make(#80, #400).
mysteryTones := [tone:make(#600, #60), tone:make(#700, #60)].
mysteryHit := tone:make(#900, #120).
bonusTone := tone:make(#1000, #80).
marchTones := [tone:make(#73, #60), tone:make(#69, #60), tone:make(#65, #60), tone:make(#62, #60)].

; -- the game
score := #0. lives := #0. wave := #0. nextBonus := #1500.
state := 'attract.                   ; 'attract  'playing  'over
shotsFired := #0.
shot := nil. bombs := []. booms := []. mystery := nil. mysteryDx := #0.
invaders := []. standing := #0.
cursor := #0.                        ; which invader moves this frame
direction := #1. edgeHit := false. dropping := false.
bombIn := #60. mysteryIn := #1500. marchNote := #1. waveIn := #0.
dying := #0.                         ; frames of the cannon's death left
mysteryWorth := #0. mysteryShownAt := #0. mysteryShownIn := #0.
i := #0. j := #0. k := nil. b := nil.

squid := [sprite:make(["...##...", "..####..", ".######.", "##.##.##",
                       "########", "..#..#..", ".#.##.#.", "#.#..#.#"], cell),
          sprite:make(["...##...", "..####..", ".######.", "##.##.##",
                       "########", ".#.##.#.", "#......#", ".#....#."], cell)].
crab  := [sprite:make(["..#.....#..", "...#...#...", "..#######..", ".##.###.##.",
                       "###########", "#.#######.#", "#.#.....#.#", "...##.##..."], cell),
          sprite:make(["..#.....#..", "#..#...#..#", "#.#######.#", "###.###.###",
                       "###########", ".#########.", "..#.....#..", ".#.......#."], cell)].
octopus := [sprite:make(["....####....", ".##########.", "############", "###..##..###",
                         "############", "...##..##...", "..##.##.##..", "##........##"], cell),
            sprite:make(["....####....", ".##########.", "############", "###..##..###",
                         "############", "..###..###..", ".##..##..##.", "..##....##.."], cell)].
kindSprites := [squid, crab, octopus].
cannonSprite := sprite:make(["......#......", ".....###.....", ".....###.....", ".############",
                             "#############", "#############", "#############", "#############"], cell).
deathSprites := [sprite:make(["....#....#...", ".#...#..#..#.", "..#.#.....#..", "...#....#....",
                              "#.......#...#", "..#..#.#..#..", ".#..#.#.#..#.", "#..#.....#..#"], cell),
                 sprite:make(["#...#.....#..", "..#....#....#", ".#..#.#..#...", "....#...#..#.",
                              "..#......#...", "#..#.#.#....#", ".#....#..#.#.", "#..#.#....#.."], cell)].
boomSprite := sprite:make(["....#...#....", ".#...#.#...#.", "..#.......#..", "...#.....#...",
                           "##.........##", "...#.....#...", "..#..#.#..#..", ".#..#...#..#."], cell).
mysterySprite := sprite:make([".....######.....", "...##########...", "..############..",
                              ".##.##.##.##.##.", "################", "..###..###..###.",
                              "...#.......#...."], cell).
bombSprites := [sprite:make(["#..", ".#.", "..#", ".#.", "#..", ".#.", "..#"], cell),
                sprite:make(["..#", ".#.", "#..", ".#.", "..#", ".#.", "#.."], cell)].
bunkerRows := ["....##############....", "...################...", "..##################..",
               ".####################.", "######################", "######################",
               "######################", "######################", "######################",
               "######################", "######################", "######################",
               "#######........#######", "######..........######", "#####............#####",
               "#####............#####"].

; ---------------------------------------------------------------------------
; The things on the screen. Everything is a rect that steps by whole
; pixels: there is not a float in the game.

invader := rect:new.
invader:kind := #1. invader:frame := #1. invader:col := #1.
invader:make := { kind, col, px, py | | v, s |
    v := self:new. s := kindSprites:at(kind):at(#1).
    v:kind := kind. v:col := col.
    v:w := @expr(s:w * cell). v:h := @expr(s:h * cell).
    v:x := @expr(px + (#24 - v:w) / #2). v:y := py.
    v }.
invader:paint := { kindSprites:at(self:kind):at(self:frame):paint(self:x, self:y) }.
invader:points := { kindPoints:at(self:kind) }.

cannon := rect:make(#40, cannonY, @expr(cannonSprite:w * cell), @expr(cannonSprite:h * cell)).

; A shot or a bomb: a rect with a vertical speed, gone off the screen.
missile := rect:new.
missile:vy := #0.
missile:make := { px, py, w, h, vy | | m |
    m := self:via(rect):make(px, py, w, h). m:vy := vy. m }.
missile:step := {
    self:y := @expr(self:y + self:vy).
    self:bottom:lessThan(#60):or({ self:y:greaterThan(ground) }):ifTrue({ self:alive := false }) }.

; A bunker: cells, and a sprite rebuilt from them when they change.
bunker := rect:new.
bunker:cells := nil. bunker:image := nil.
bunker:make := { px, py | | bk |
    bk := self:via(rect):make(px, py, @expr(#22 * cell), @expr(#16 * cell)).
    bk:cells := bunkerRows:collect({ row | | out, ci |
        out := []. ci := #1.
        { ci:lessOrEqual(row:size) }:whileTrue({
            out:add(row:at(ci):equals("#")). ci := ci:inc }).
        out }).
    bk:rebuild. bk }.
bunker:rebuild := { self:image := sprite:fromCells(self:cells, cell) }.
bunker:paint := { self:image:paint(self:x, self:y) }.
bunker:inside := { px, py |
    @expr(px >= self:x & px < self:right & py >= self:y & py < self:bottom) }.
bunker:solidAt := { px, py |
    self:inside(px, py):and({
        self:cells:at(@expr((py - self:y) / cell + #1)):at(@expr((px - self:x) / cell + #1)) }) }.
bunker:clear := { ci, cj |
    @expr(ci >= #1 & ci <= #22 & cj >= #1 & cj <= #16):ifTrue({
        self:cells:at(cj):atPut(ci, false) }) }.
; A bite at a pixel: the cells within two of it, and a few more at random.
bunker:bite := { px, py | | ci, cj, di, dj |
    ci := @expr((px - self:x) / cell + #1). cj := @expr((py - self:y) / cell + #1).
    dj := #-2.
    { dj:lessOrEqual(#2) }:whileTrue({
        di := #-2.
        { di:lessOrEqual(#2) }:whileTrue({
            @expr(di:abs + dj:abs <= #2):ifTrue({ self:clear(@expr(ci + di), @expr(cj + dj)) }).
            di := di:inc }).
        dj := dj:inc }).
    di := #0.
    { di:lessThan(#4) }:whileTrue({
        self:clear(@expr(ci + rng:between(#-3, #3)), @expr(cj + rng:between(#-3, #3))).
        di := di:inc }).
    self:rebuild }.
; Trampled: every cell under a rect goes.
bunker:trample := { r | | ci, cj |
    cj := @expr((r:y - self:y) / cell + #1).
    { cj:lessOrEqual(@expr((r:bottom - self:y) / cell)) }:whileTrue({
        ci := @expr((r:x - self:x) / cell + #1).
        { ci:lessOrEqual(@expr((r:right - self:x) / cell)) }:whileTrue({
            self:clear(ci, cj). ci := ci:inc }).
        cj := cj:inc }).
    self:rebuild }.

bunkers := [bunker:make(#96, #360), bunker:make(#232, #360),
            bunker:make(#368, #360), bunker:make(#504, #360)].

; ---------------------------------------------------------------------------
; What happens

; A wave: the block in place, a row lower each time up to four.
spawnWave := { | top, col, row |
    wave := wave:inc.
    invaders := []. bombs := []. shot := nil. booms := [].
    top := @expr(#96 + (wave - #1) * stepY).
    top:greaterThan(#160):ifTrue({ top := #160 }).
    row := #1.
    { row:lessOrEqual(rows) }:whileTrue({
        col := #1.
        { col:lessOrEqual(columns) }:whileTrue({
            invaders:add(invader:make(rowKinds:at(row), col,
                @expr(#144 + (col - #1) * pitch), @expr(top + (row - #1) * pitch))).
            col := col:inc }).
        row := row:inc }).
    standing := @expr(rows * columns).
    cursor := #0. direction := #1. edgeHit := false. dropping := false.
    bombIn := #60. mysteryIn := #1500. waveIn := #0 }.

; The block moves one invader a frame. When the cursor comes round, a pass
; is complete: if an edge was reached during it, the next pass drops and
; turns. That is where the ripple and the quickening both come from.
moveBlock := { | v, tries |
    tries := #0.
    { tries:lessThan(invaders:size) }:whileTrue({
        cursor := @expr(cursor:mod(invaders:size) + #1).
        invaders:at(cursor):alive:ifElse({ tries := invaders:size }, { tries := tries:inc }) }).
    v := invaders:at(cursor).
    v:alive:ifTrue({
        dropping:ifElse(
            { v:y := @expr(v:y + stepY) },
            { v:x := @expr(v:x + direction * stepX).
              v:x:lessOrEqual(edgeLeft):or({ v:right:greaterOrEqual(edgeRight) }):ifTrue({
                  edgeHit := true }) }).
        v:frame := @expr(#3 - v:frame).
        bunkers:do({ bk | v:touches(bk):ifTrue({ bk:trample(v) }) }).
        v:bottom:greaterOrEqual(cannonY):ifTrue({ state := 'over }) }) }.

; The pass is complete when the cursor has just passed the last live
; invader; the march plays a note there, and the turn is decided.
lastAlive := #0.
findLast := {
    lastAlive := #0. i := #1.
    { i:lessOrEqual(invaders:size) }:whileTrue({
        invaders:at(i):alive:ifTrue({ lastAlive := i }). i := i:inc }) }.
endPass := {
    dropping := false.
    edgeHit:ifTrue({ direction := direction:negated. dropping := true. edgeHit := false }).
    marchTones:at(marchNote):hum. marchNote := @expr(marchNote:mod(#4) + #1) }.

; An invader hit: the points, an explosion where it was, and the tempo.
kill := { v |
    v:alive := false. standing := standing:dec.
    score := @expr(score + v:points).
    booms:add([v:x, v:y, #16]).
    hitTone:play }.

; The lowest live invader in a column, or nil.
lowestIn := { col | | found |
    found := nil.
    invaders:do({ v | v:alive:and({ v:col:equals(col) }):ifTrue({ found := v }) }).
    found }.

dropBomb := { | v |
    v := lowestIn:value(rng:upTo(columns)).
    v:notNil:ifTrue({
        bombs:add(missile:make(@expr(v:x + v:w / #2 - #3), v:bottom, #6, #14, bombSpeed)) }) }.

fire := {
    shot:isNil:ifTrue({
        shot := missile:make(@expr(cannon:x + cannon:w / #2 - #1), @expr(cannon:y - #8), #2, #8, shotSpeed:negated).
        shotsFired := shotsFired:inc.
        fireTone:play }) }.

killCannon := { dying := #90. deathTone:play }.

newGame := {
    score := #0. lives := #3. wave := #0. nextBonus := #1500. shotsFired := #0.
    mystery := nil. dying := #0.
    bunkers := [bunker:make(#96, #360), bunker:make(#232, #360),
                bunker:make(#368, #360), bunker:make(#504, #360)].
    cannon:x := #40.
    spawnWave:value.
    state := 'playing }.

; A missile against the bunkers: where its tip is in solid, the bunker is
; bitten and the missile is spent. `tipY` is the leading edge.
bunkerHit := { m, tipY | | hit |
    hit := false.
    bunkers:do({ bk |
        hit:not:and({ bk:solidAt(@expr(m:x + m:w / #2), tipY) }):ifTrue({
            bk:bite(@expr(m:x + m:w / #2), tipY). hit := true }) }).
    hit }.

; ---------------------------------------------------------------------------

spawnWave:value.                     ; the block, to look at before a game

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):and({ event:key:equals("Space") }):ifTrue({
            state:equals('playing):ifElse(
                { dying:equals(#0):ifTrue({ fire:value }) },
                { newGame:value }) }) }).

    state:equals('playing):and({ dying:equals(#0) }):ifTrue({
        ; -- the cannon
        keys:any(leftKeys):ifTrue({ cannon:x := @expr(cannon:x - cannonSpeed) }).
        keys:any(rightKeys):ifTrue({ cannon:x := @expr(cannon:x + cannonSpeed) }).
        cannon:x:lessThan(edgeLeft):ifTrue({ cannon:x := edgeLeft }).
        @expr(cannon:right > edgeRight):ifTrue({ cannon:x := @expr(edgeRight - cannon:w) }).

        ; -- the block, one invader a frame
        standing:greaterThan(#0):ifTrue({
            findLast:value.
            moveBlock:value.
            cursor:equals(lastAlive):ifTrue({ endPass:value }) }).

        ; -- the shot
        shot:notNil:ifTrue({
            shot:step.
            invaders:do({ v |
                shot:alive:and({ v:alive }):and({ shot:touches(v) }):ifTrue({
                    kill:value(v). shot:alive := false }) }).
            mystery:notNil:and({ shot:alive }):and({ shot:touches(mystery) }):ifTrue({
                score := @expr(score + mysteryWorth).
                mysteryShownAt := mystery:x. mysteryShownIn := #40.
                mystery := nil. shot:alive := false. mysteryHit:play }).
            bombs:do({ m |
                shot:alive:and({ m:alive }):and({ shot:touches(m) }):ifTrue({
                    shot:alive := false. m:alive := false }) }).
            shot:alive:and({ bunkerHit:value(shot, shot:y):or({ bunkerHit:value(shot, @expr(shot:y + #4)) }) }):ifTrue({
                shot:alive := false }).
            shot:alive:ifFalse({ shot := nil }) }).

        ; -- the bombs
        bombs:do({ m |
            m:step.
            m:alive:and({ m:touches(cannon) }):ifTrue({ m:alive := false. killCannon:value }).
            m:alive:and({ bunkerHit:value(m, @expr(m:bottom - #1)) }):ifTrue({ m:alive := false }) }).
        bombs := bombs:select({ m | m:alive }).
        bombIn := bombIn:dec.
        bombIn:lessOrEqual(#0):and({ bombs:size:lessThan(bombsMost) }):ifTrue({
            dropBomb:value.
            bombIn := @expr(#30 + rng:upTo(#60) - (wave - #1) * #5) }).

        ; -- the mystery ship
        mystery:notNil:ifTrue({
            mystery:x := @expr(mystery:x + mysteryDx).
            mystery:right:lessThan(#0):or({ mystery:x:greaterThan(width) }):ifTrue({ mystery := nil }).
            frames:mod(#8):equals(#0):ifTrue({
                mysteryTones:at(@expr(frames / #8):mod(#2):inc):hum }) }).
        mystery:isNil:ifTrue({
            mysteryIn := mysteryIn:dec.
            mysteryIn:equals(#0):ifTrue({
                mysteryIn := @expr(#1200 + rng:upTo(#600)).
                rng:upTo(#2):equals(#1):ifElse(
                    { mystery := rect:make(#-32, #56, #32, #14). mysteryDx := #2 },
                    { mystery := rect:make(width, #56, #32, #14). mysteryDx := #-2 }).
                shotsFired:equals(#23):or({ @expr(shotsFired > #23 & (shotsFired - #23):mod(#15) = #0) }):ifElse(
                    { mysteryWorth := #300 },
                    { mysteryWorth := [#50, #100, #150]:at(rng:upTo(#3)) }) }) }).

        ; -- the explosions, and the points a mystery ship was worth
        booms:do({ bm | bm:atPut(#3, bm:at(#3):dec) }).
        booms := booms:select({ bm | bm:at(#3):greaterThan(#0) }).
        mysteryShownIn:greaterThan(#0):ifTrue({ mysteryShownIn := mysteryShownIn:dec }).

        ; -- the extra cannon, and the next wave
        score:greaterOrEqual(nextBonus):ifTrue({
            lives := lives:inc. nextBonus := @expr(nextBonus + #1500). bonusTone:play }).
        standing:equals(#0):ifTrue({
            waveIn := waveIn:inc.
            waveIn:greaterThan(#90):ifTrue({ spawnWave:value }) }) }).

    ; -- the cannon's death: everything else stands still
    dying:greaterThan(#0):ifTrue({
        dying := dying:dec.
        dying:equals(#0):ifTrue({
            lives := lives:dec.
            bombs := [].
            lives:equals(#0):ifElse({ state := 'over }, { cannon:x := #40 }) }) }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #0, #0, #0).
    sdl:colour(screen, #230, #230, #230).
    invaders:do({ v | v:alive:ifTrue({ v:paint }) }).
    booms:do({ bm | boomSprite:paint(bm:at(#1), bm:at(#2)) }).
    mystery:notNil:ifTrue({ sdl:colour(screen, #230, #60, #60). mysterySprite:paint(mystery:x, mystery:y) }).
    mysteryShownIn:greaterThan(#0):ifTrue({
        sdl:colour(screen, #230, #60, #60). font:number(mysteryWorth, @expr(mysteryShownAt + #32), #56) }).
    sdl:colour(screen, #60, #220, #60).
    bunkers:do({ bk | bk:paint }).
    state:equals('over):ifFalse({
        dying:greaterThan(#0):ifElse(
            { deathSprites:at(@expr(dying / #6):mod(#2):inc):paint(cannon:x, cannon:y) },
            { cannonSprite:paint(cannon:x, cannon:y) }) }).
    shot:notNil:ifTrue({ shot:paint }).
    sdl:colour(screen, #230, #230, #230).
    bombs:do({ m |
        bombSprites:at(@expr(frames / #4):mod(#2):inc):paint(m:x, m:y) }).
    sdl:colour(screen, #60, #220, #60).
    sdl:fill(screen, #0, ground, width, #2).
    state:equals('attract):ifFalse({
        sdl:colour(screen, #230, #230, #230).
        font:number(score, #100, #14).
        font:number(lives, #40, #462).
        i := #1.
        { i:lessThan(lives) }:whileTrue({
            cannonSprite:paint(@expr(#40 + i * #32), #460). i := i:inc }) }).

    engine:show }).

"final score {}":fill([score]):display.
