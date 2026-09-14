; mario.sol -- the twelfth game, the first console game, the first with a
; jump, and the first whose map is a grid the player collides with.
;
;     solvm --extension=build/sdl.so examples/mario.sob
;
;   Left / Right   walk; A / D do the same
;   Z / Space      jump, higher the longer it is held
;   X / Shift      run
;   Space          when no game is on, start one
;   Escape         quit
;
; The 1985 rules, for World 1-1. A level two hundred tiles long laid out
; as rows of text, the way a sprite is, and read into a grid: ground,
; bricks, question blocks, pipes, stairs, the flagpole and the castle.
; Mario walks with a little slide, runs with a button, jumps higher the
; longer the button is held, and falls faster than he rises. A question
; block bumped from below gives a coin for 200 or a mushroom, and the
; mushroom makes him big; big, he breaks bricks from below for 50 and
; takes one hit to be small again. Goombas walk and are stomped for 100;
; a Koopa stomped is a shell that stands until kicked, and a kicked shell
; takes what it hits. Touching either any other way costs a Mario when
; small, three to start and one more at a hundred coins. The clock starts
; at 400 and counts in fifths of a second; at nought he is lost. The
; flagpole is 100 to 5,000 by how high he takes it, the clock left is 50 a
; count, and then it is 1-1 again, with the goombas a little quicker.
; Things the cartridge had that this does not: the other thirty-one
; levels, the midway point, the fire flower, the star, the hidden blocks,
; the warp pipes, and the tune, which is Nintendo's.
;
; **What was predicted before this was written.** That the jump is the
; first thing in twelve games to leave the ground under a key and come
; back down, with the gravity itself under the key, and that it is a
; dozen lines of the game with nothing under it in the engine but
; `mover`. That the level is the grid's fourth game and its first as a
; map a moving body collides with, resolved on each axis in turn against
; the tiles it overlaps, a block of the game and not of the engine, since
; what a solid tile is and what a bumped one does are this game's. That
; the camera is here a third time, one way only with a floor at the left
; edge, a third shape for the reading of twelve to read against the two
; it has. That the enemies, the shell and the mushroom are `mover`s bare
; under the same tile rule. That `sprite` carries a sixth game, `font:word`
; a sixth, `tint` a sixth, `keys` its eleventh. And that the binding would
; be asked for nothing.
;
; The sounds are pitches chosen for this file.

@include "engine.sol".

engine:open("mario", #640, #480).

; -- the world
tile := #32.                         ; a tile, in pixels; the cartridge's sixteen, twice
rows := #15.
runKeys := ["X", "Left Shift", "Right Shift"]. jumpKeys := ["Z", "Space"].

; -- the rules
walkTop := 3.0. runTop := 5.0. accel := 0.15. friction := 0.2.
jumpSpeed := -10.0. jumpRun := 0.2. gravityHeld := 0.35. gravity := 0.9. fallTop := 8.0.   ; a running jump is higher
clockStart := #400. clockTick := #24.
lifeAtCoins := #100.

; -- the sounds
jumpTone  := tone:make(#600, #60).
coinTone  := tone:make(#1300, #80).
stompTone := tone:make(#300, #50).
bumpTone  := tone:make(#150, #40).
breakTone := tone:make(#200, #80).
growTone  := tone:make(#900, #150).
hurtTone  := tone:make(#250, #200).
deathTone := tone:make(#80, #700).
kickTone  := tone:make(#500, #40).
flagTone  := tone:make(#1000, #300).
clearTone := tone:make(#1200, #400).
oneUpTone := tone:make(#1500, #200).

; -- the game
state := 'attract.                   ; 'attract  'playing  'dying  'flag  'walking  'over
score := #0. coins := #0. lives := #0. round := #1. clock := #0. clockIn := #0.
cam := 0.0.
map := nil. cols := #0.
mario := nil. enemies := []. items := []. pops := []. debris := [].
dyingIn := #0. pauseIn := #0. countIn := #0.
i := #0.

; ---------------------------------------------------------------------------
; The pictures, at four pixels a cell: a cartridge sprite of eight is a
; tile of thirty-two.

pic := #4.
smallRight := sprite:make([
    "...####.", "..######", "..##..#.", ".#.####.", "..###...", "..####..", ".##.##..", ".#...#.."], pic).
smallLeft := sprite:make([
    ".####...", "######..", ".#..##..", ".####.#.", "...###..", "..####..", "..##.##.", "..#...#."], pic).
bigRight := sprite:make([
    "...####.", "..######", "..##..#.", ".#.####.", "..###...", "..#####.", ".#######", "#.#####.",
    "#.#####.", "#.#####.", "..#####.", "..#####.", "..#...#.", ".##...##", ".##...##", "###...##"], pic).
bigLeft := sprite:make([
    ".####...", "######..", ".#..##..", ".####.#.", "...###..", ".#####..", "#######.", ".#####.#",
    ".#####.#", ".#####.#", ".#####..", ".#####..", ".#...#..", "##...##.", "##...##.", "##...###"], pic).
goombaSprite := sprite:make([
    "..####..", ".######.", "##.##.##", "########", ".######.", "..####..", ".##..##.", "###..###"], pic).
squashedSprite := sprite:make(["........", "........", "........", "........", "........", ".######.", "########", "#.####.#"], pic).
koopaSprite := sprite:make([
    "...##...", "..####..", "..#.##..", "..####..", ".######.", "#.####.#", "########", ".######.",
    "..####..", ".##..##.", "##....##", "........"], pic).
shellSprite := sprite:make(["..####..", ".######.", "##.##.##", "########", ".#.##.#.", "..####..", "........", "........"], pic).
mushroomSprite := sprite:make(["..####..", ".#.##.#.", "##.##.##", "########", "..#..#..", "..####..", "..####..", "...##..."], pic).
coinSprite := sprite:make([".##.", "#..#", "#..#", "#..#", "#..#", "#..#", "#..#", ".##."], pic).

tint:sets := [[[#92, #148, #252], [#200, #76, #12], [#252, #152, #56], [#0, #168, #0], [#252, #216, #168]]].

; ---------------------------------------------------------------------------
; The level: rows of text, one character a tile, read into a grid of
; codes. What a tile is and what it does when bumped are this game's.

air := #0. ground := #1. brick := #2. question := #3. mushroomBlock := #4. used := #5.
pipe := #6. stair := #7. pole := #8. poleTop := #9. castle := #10. poleBase := #11.
codes := #[ "." = #0, "#" = #1, "B" = #2, "?" = #3, "M" = #4, "U" = #5, "p" = #6, "S" = #7,
            "F" = #8, "T" = #9, "C" = #10, "X" = #11 ].

level := [
    "....................................................................................................................................................................................................................",
    "....................................................................................................................................................................................................................",
    "......................................................................................................................................................................................................T.............",
    "......................................................................................................................................................................................................F.............",
    "......................................................................................................................................................................................................F.............",
    "......................?.........................................................BBBBBBBB...BBB?..........................BBB....B??B........................................................SS........F.............",
    "...........................................................................................................................................................................................SSS........F.....C.......",
    "..........................................................................................................................................................................................SSSS........F....CCC......",
    "........................................................................................................................................................S................................SSSSS........F....CCC......",
    "................?...BMB?B.....................pp.........pp..................BMB..............B.....?.....?..M..?.....B..........BB......S..S..........SS..S............B?B.............SSSSSS........F...CCCCC.....",
    "......................................pp......pp.........pp.............................................................................SS..SS........SSS..SS..........................SSSSSSS........F...CCCCC.....",
    "............................pp........pp......pp.........pp............................................................................SSS..SSS......SSSS..SSS........................SSSSSSSS........F...CCCCC.....",
    "............................pp........pp......pp.........pp...........................................................................SSSS..SSSS....SSSSS..SSSS......................SSSSSSSSS........X...CCCCC.....",
    "#####################################################################..###############...################################################################..#########################################################",
    "#####################################################################..###############...################################################################..#########################################################"
].

; Where the enemies stand at the start, a column and a kind each.
starts := [[#22, 'goomba], [#40, 'goomba], [#51, 'goomba], [#53, 'goomba], [#80, 'goomba], [#82, 'goomba],
           [#97, 'goomba], [#99, 'goomba], [#107, 'koopa], [#114, 'goomba], [#116, 'goomba],
           [#124, 'goomba], [#126, 'goomba], [#128, 'goomba], [#130, 'goomba], [#174, 'goomba], [#176, 'goomba]].

readLevel := { | line |
    cols := level:at(#1):size.
    map := grid:make(cols, rows).
    [#1, rows]:loop({ r |
        line := level:at(r).
        [#1, cols]:loop({ c | map:atPut(c, r, codes:at(line:at(c))) }) }) }.

; The tile at a column and row, and air beyond the level.
tileAt := { c, r | @expr(c < #1 | c > cols | r < #1 | r > rows):ifElse({ air }, { map:at(c, r) }) }.
solidAt := { c, r | | v |
    v := tileAt:value(c, r).
    @expr(v = ground | v = brick | v = question | v = mushroomBlock | v = used | v = pipe | v = stair | v = castle | v = poleBase) }.

colOf := { x | @expr(x:truncated / tile + #1) }.
rowOf := { y | @expr(y:truncated / tile + #1) }.

; ---------------------------------------------------------------------------
; A body: a mover with a box, moved on each axis in turn and pushed out
; of the tiles it overlaps. What is solid is asked of the level; what a
; bump does is done by the body that bumped, since only Mario bumps.

body := mover:new.
body:w := #24. body:h := #30. body:onGround := false. body:bumped := nil.
body:box := { rect:make(@expr(self:x - cam):truncated, self:y:truncated, self:w, self:h) }.
body:touches := { other |
    @expr(self:x < other:x + other:w:asFloat & self:x + self:w:asFloat > other:x &
          self:y < other:y + other:h:asFloat & self:y + self:h:asFloat > other:y) }.

; Sideways, then out of any tile the left or right edge is in.
body:moveX := { | c, r0, r1 |
    self:x := @expr(self:x + self:vx).
    r0 := rowOf:value(self:y). r1 := rowOf:value(@expr(self:y + self:h:asFloat - 1.0)).
    self:vx:greaterThan(0.0):ifTrue({
        c := colOf:value(@expr(self:x + self:w:asFloat - 1.0)).
        [r0, r1]:loop({ r | solidAt:value(c, r):ifTrue({ self:x := @expr(((c - #1) * tile - self:w):asFloat). self:vx := 0.0 }) }) }).
    self:vx:lessThan(0.0):ifTrue({
        c := colOf:value(self:x).
        [r0, r1]:loop({ r | solidAt:value(c, r):ifTrue({ self:x := @expr((c * tile):asFloat). self:vx := 0.0 }) }) }).
    self:x:lessThan(0.0):ifTrue({ self:x := 0.0. self:vx := 0.0 }) }.

; Up or down, then out of any tile the top or bottom edge is in; landing
; and bumping are told here.
body:moveY := { | r, c0, c1, hit, best, mx |
    self:y := @expr(self:y + self:vy).
    self:onGround := false. self:bumped := nil.
    c0 := colOf:value(@expr(self:x + 2.0)). c1 := colOf:value(@expr(self:x + self:w:asFloat - 3.0)).
    self:vy:greaterOrEqual(0.0):ifTrue({
        r := rowOf:value(@expr(self:y + self:h:asFloat)).      ; the pixel under the feet, so that standing counts every frame
        hit := false.
        [c0, c1]:loop({ c | solidAt:value(c, r):ifTrue({ hit := true }) }).
        hit:ifTrue({ self:y := @expr(((r - #1) * tile - self:h):asFloat). self:vy := 0.0. self:onGround := true }) }).
    self:vy:lessThan(0.0):ifTrue({
        r := rowOf:value(self:y).
        hit := nil. best := 10000.0. mx := @expr(self:x + self:w:asFloat / 2.0).
        [c0, c1]:loop({ c | | d |
            solidAt:value(c, r):ifTrue({
                d := @expr(((c - #1) * tile + tile / #2):asFloat - mx):abs.
                d:lessThan(best):ifTrue({ best := d. hit := c }) }) }).
        hit:notNil:ifTrue({ self:y := @expr((r * tile):asFloat). self:vy := 0.0. self:bumped := [hit, r] }) }) }.

; ---------------------------------------------------------------------------
; Mario

marioBody := body:new.
marioBody:big := false. marioBody:facing := #1. marioBody:safeIn := #0. marioBody:jumping := false.
marioBody:paint := { | sy |
    self:safeIn:greaterThan(#0):and({ frames:mod(#4):lessThan(#2) }):ifFalse({
        sy := self:y:truncated:sub(#2).
        self:big:ifElse(
            { self:facing:greaterThan(#0):ifElse({ bigRight:paint(@expr(self:x - cam):truncated:sub(#4), sy) }, { bigLeft:paint(@expr(self:x - cam):truncated:sub(#4), sy) }) },
            { self:facing:greaterThan(#0):ifElse({ smallRight:paint(@expr(self:x - cam):truncated:sub(#4), sy) }, { smallLeft:paint(@expr(self:x - cam):truncated:sub(#4), sy) }) }) }) }.

grow := { mario:big:ifFalse({ mario:big := true. mario:h := #62. mario:y := @expr(mario:y - 32.0) }). earn:value(#1000). growTone:play }.
shrink := { mario:big := false. mario:h := #30. mario:y := @expr(mario:y + 32.0). mario:safeIn := #120. hurtTone:play }.

; The block over his head: a coin, a mushroom, a brick broken or bumped.
bump := { c, r | | v |
    v := map:at(c, r).
    v:equals(question):ifTrue({ map:atPut(c, r, used). coins := coins:inc. earn:value(#200). pops:add([c, r, #30]). coinTone:play.
        coins:equals(lifeAtCoins):ifTrue({ lives := lives:inc. coins := #0. oneUpTone:play }) }).
    v:equals(mushroomBlock):ifTrue({ map:atPut(c, r, used). items:add(mushroom:make(c, r)). bumpTone:play }).
    v:equals(brick):ifTrue({
        mario:big:ifElse(
            { map:atPut(c, r, air). earn:value(#50). breakTone:play.
              [[-2.0, -8.0], [2.0, -8.0], [-2.0, -5.0], [2.0, -5.0]]:do({ d |
                  debris:add([@expr(((c - #1) * tile + tile / #2):asFloat), @expr(((r - #1) * tile):asFloat), d:at(#1), d:at(#2), #40]) }) },
            { bumpTone:play }) }).
    v:equals(used):or({ v:equals(ground) }):or({ v:equals(stair) }):or({ v:equals(pipe) }):ifTrue({ bumpTone:play }) }.

; ---------------------------------------------------------------------------
; The others: goombas, koopas and shells, and the mushroom, all bodies
; under the same tiles, walking until a wall and falling off edges.

foe := body:new.
foe:kind := 'goomba. foe:squashedIn := #0. foe:awake := false.
foe:make := { c, kind | | f |
    f := self:new. f:kind := kind. f:x := @expr(((c - #1) * tile):asFloat + 4.0).
    f:h := kind:equals('koopa):ifElse({ #44 }, { #30 }). f:y := @expr((#13 * tile - f:h):asFloat).
    f:vx := @expr(-1.0 - (round - #1):asFloat * 0.3).
    f }.
foe:step := { | was |
    self:kind:equals('shell):and({ self:vx:equals(0.0) }):ifFalse({
        was := self:vx.
        self:moveX.
        self:vx:equals(0.0):and({ was:equals(0.0):not }):ifTrue({ self:vx := was:negated }) }).
    self:vy := @expr(self:vy + gravity). self:vy:greaterThan(fallTop):ifTrue({ self:vy := fallTop }).
    self:moveY.
    self:y:greaterThan(fh):ifTrue({ self:alive := false }) }.
foe:paint := { | sx |
    sx := @expr(self:x - cam):truncated:sub(#4).
    self:kind:equals('goomba):ifTrue({
        self:squashedIn:greaterThan(#0):ifElse({ squashedSprite:paint(sx, self:y:truncated) }, { goombaSprite:paint(sx, self:y:truncated) }) }).
    self:kind:equals('koopa):ifTrue({ koopaSprite:paint(sx, @expr(self:y:truncated - #4)) }).
    self:kind:equals('shell):ifTrue({ shellSprite:paint(sx, self:y:truncated) }) }.

mushroom := body:new.
mushroom:rising := #0.
mushroom:make := { c, r | | m |
    m := self:new. m:x := @expr(((c - #1) * tile):asFloat + 4.0). m:y := @expr(((r - #1) * tile):asFloat). m:rising := #32. m:vx := 1.5. m }.
mushroom:step := { | was |
    self:rising:greaterThan(#0):ifElse(
        { self:y := @expr(self:y - 1.0). self:rising := self:rising:dec },
        { was := self:vx. self:moveX.
          self:vx:equals(0.0):ifTrue({ self:vx := was:negated }).
          self:vy := @expr(self:vy + gravity). self:vy:greaterThan(fallTop):ifTrue({ self:vy := fallTop }).
          self:moveY }).
    self:y:greaterThan(fh):ifTrue({ self:alive := false }) }.
mushroom:paint := { mushroomSprite:paint(@expr(self:x - cam):truncated:sub(#4), self:y:truncated) }.

; ---------------------------------------------------------------------------
; What happens

earn := { points | score := @expr(score + points) }.

; Enemies come to life a screen ahead of the camera, and are placed when
; the level is.
placeEnemies := {
    enemies := [].
    starts:do({ s | enemies:add(foe:make(s:at(#1), s:at(#2))) }) }.

startLevel := {
    readLevel:value.
    mario := marioBody:new. mario:x := 96.0. mario:y := @expr((#13 * tile - #30):asFloat). mario:h := #30. mario:big := false.
    cam := 0.0. items := []. pops := []. debris := [].
    placeEnemies:value.
    clock := clockStart. clockIn := clockTick.
    state := 'playing }.

newGame := {
    score := #0. coins := #0. lives := #3. round := #1.
    startLevel:value }.

jump := { mario:vy := @expr(jumpSpeed - mario:vx:abs * jumpRun). mario:jumping := true. mario:onGround := false }.

die := { state := 'dying. dyingIn := #120. mario:vy := -10.0. deathTone:play }.

; Hit from the side or below: hurt if big, lost if small.
hurt := {
    mario:safeIn:equals(#0):ifTrue({ mario:big:ifElse({ shrink:value }, { die:value }) }) }.

; The flagpole: the height taken is the score, and the walk to the castle.
takeFlag := { | r |
    state := 'flag. mario:vx := 0.0. mario:vy := 0.0. flagTone:play.
    r := rowOf:value(mario:y).
    earn:value([#5000, #5000, #2000, #2000, #800, #800, #400, #400, #100, #100, #100, #100, #100, #100, #100]:at(r)) }.

; The clock, counting down, and paid out at the end.
tickClock := {
    clockIn := clockIn:dec.
    clockIn:equals(#0):ifTrue({
        clockIn := clockTick. clock := clock:dec.
        clock:equals(#0):ifTrue({ die:value }) }) }.

; ---------------------------------------------------------------------------

readLevel:value.                     ; the level, to look at before a game
mario := marioBody:new. mario:x := 96.0. mario:y := @expr((#13 * tile - #30):asFloat).

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):and({ event:repeat:equals(#0) }):ifTrue({
            state:equals('playing):and({ jumpKeys:indexOf(event:key):notNil }):and({ mario:onGround }):ifTrue({
                jump:value. jumpTone:play }).
            event:key:equals("Space"):and({ state:equals('attract):or({ state:equals('over) }) }):ifTrue({ newGame:value }) }) }).

    ; -- the player
    state:equals('playing):ifTrue({ | top, g |
        top := keys:any(runKeys):ifElse({ runTop }, { walkTop }).
        keys:any(leftKeys):ifTrue({ mario:vx := @expr(mario:vx - accel * 2.0). mario:facing := #-1 }).
        keys:any(rightKeys):ifTrue({ mario:vx := @expr(mario:vx + accel * 2.0). mario:facing := #1 }).
        keys:any(leftKeys):or({ keys:any(rightKeys) }):ifFalse({
            mario:vx:greaterThan(friction):ifElse({ mario:vx := @expr(mario:vx - friction) },
                { mario:vx:lessThan(friction:negated):ifElse({ mario:vx := @expr(mario:vx + friction) }, { mario:vx := 0.0 }) }) }).
        mario:vx:greaterThan(top):ifTrue({ mario:vx := top }).
        mario:vx:lessThan(top:negated):ifTrue({ mario:vx := top:negated }).
        keys:any(jumpKeys):ifFalse({ mario:jumping := false }).
        g := mario:jumping:and({ mario:vy:lessThan(0.0) }):ifElse({ gravityHeld }, { gravity }).
        mario:vy := @expr(mario:vy + g).
        mario:vy:greaterThan(fallTop):ifTrue({ mario:vy := fallTop }).
        mario:moveX. mario:moveY.
        mario:bumped:notNil:ifTrue({ bump:value(mario:bumped:at(#1), mario:bumped:at(#2)) }).
        mario:safeIn:greaterThan(#0):ifTrue({ mario:safeIn := mario:safeIn:dec }).
        mario:y:greaterThan(fh):ifTrue({ die:value }).
        tileAt:value(colOf:value(@expr(mario:x + 12.0)), rowOf:value(@expr(mario:y + 10.0))):equals(pole):ifTrue({ takeFlag:value }).

        ; -- the camera: forward only
        @expr(mario:x - cam > 220.0):ifTrue({ cam := @expr(mario:x - 220.0) }).
        cam:greaterThan(@expr((cols * tile - width):asFloat)):ifTrue({ cam := @expr((cols * tile - width):asFloat) }).

        ; -- the others, awake once they are near the screen
        enemies:do({ f |
            f:alive:ifTrue({
                f:awake:not:and({ @expr(f:x - cam < fw + 64.0) }):ifTrue({ f:awake := true }).
                f:awake:and({ f:squashedIn:equals(#0) }):ifTrue({ f:step }).
                f:squashedIn:greaterThan(#0):ifTrue({ f:squashedIn := f:squashedIn:dec. f:squashedIn:equals(#0):ifTrue({ f:alive := false }) }) }) }).
        items:do({ m | m:step }).

        ; -- Mario against them: from above is a stomp, otherwise a hurt
        enemies:do({ f |
            f:alive:and({ f:awake }):and({ f:squashedIn:equals(#0) }):and({ mario:touches(f) }):ifTrue({
                mario:vy:greaterThan(0.0):and({ @expr(mario:y + mario:h:asFloat - f:y < 20.0) }):ifElse(
                    { mario:vy := -6.0.
                      f:kind:equals('goomba):ifTrue({ f:squashedIn := #30. f:vx := 0.0. earn:value(#100). stompTone:play }).
                      f:kind:equals('koopa):ifTrue({ f:kind := 'shell. f:h := #30. f:y := @expr(f:y + 14.0). f:vx := 0.0. earn:value(#100). stompTone:play }).
                      f:kind:equals('shell):ifTrue({
                          f:vx:equals(0.0):ifElse(
                              { f:vx := @expr(mario:x + 12.0):lessThan(@expr(f:x + 12.0)):ifElse({ 6.0 }, { -6.0 }). kickTone:play },
                              { f:vx := 0.0. earn:value(#100). stompTone:play }) }) },
                    { f:kind:equals('shell):and({ f:vx:equals(0.0) }):ifElse(
                        { f:vx := @expr(mario:x + 12.0):lessThan(@expr(f:x + 12.0)):ifElse({ 6.0 }, { -6.0 }). kickTone:play },
                        { hurt:value }) }) }) }).
        ; a moving shell against the rest
        enemies:do({ s | s:alive:and({ s:kind:equals('shell) }):and({ s:vx:equals(0.0):not }):ifTrue({
            enemies:do({ f | f:alive:and({ f:equals(s):not }):and({ f:awake }):and({ s:touches(f) }):ifTrue({
                f:alive := false. earn:value(#100). kickTone:play }) }) }) }).
        items:do({ m | m:alive:and({ mario:touches(m) }):ifTrue({ m:alive := false. grow:value }) }).

        pops:do({ p | p:atPut(#3, p:at(#3):dec) }).
        debris:do({ d | d:atPut(#1, @expr(d:at(#1) + d:at(#3))). d:atPut(#2, @expr(d:at(#2) + d:at(#4))). d:atPut(#4, @expr(d:at(#4) + 0.5)). d:atPut(#5, d:at(#5):dec) }).
        enemies := enemies:select({ f | f:alive }).
        items := items:select({ m | m:alive }).
        pops := pops:select({ p | p:at(#3):greaterThan(#0) }).
        debris := debris:select({ d | d:at(#5):greaterThan(#0) }).
        tickClock:value }).

    ; -- the flag: down the pole, then the walk in, then the clock paid
    state:equals('flag):ifTrue({
        mario:y := @expr(mario:y + 4.0).
        mario:y:greaterOrEqual(@expr((#12 * tile - mario:h):asFloat)):ifTrue({
            mario:y := @expr((#12 * tile - mario:h):asFloat). state := 'walking. mario:vx := 2.0 }) }).
    state:equals('walking):ifTrue({
        mario:facing := #1. mario:moveX.
        mario:vy := @expr(mario:vy + gravity). mario:moveY.
        tileAt:value(colOf:value(@expr(mario:x + 12.0)), rowOf:value(@expr(mario:y + 10.0))):equals(castle):or({ mario:vx:equals(0.0) }):ifTrue({
            state := 'counting. countIn := #2 }) }).
    state:equals('counting):ifTrue({
        countIn := countIn:dec.
        countIn:equals(#0):ifTrue({
            clock:greaterThan(#0):ifElse(
                { clock := clock:dec. earn:value(#50). countIn := #2. frames:mod(#4):equals(#0):ifTrue({ coinTone:play }) },
                { clearTone:play. round := round:inc. pauseIn := #120. state := 'cleared }) }) }).
    state:equals('cleared):ifTrue({ pauseIn := pauseIn:dec. pauseIn:equals(#0):ifTrue({ startLevel:value }) }).

    ; -- a Mario lost: he leaps and falls, then the level again or the end
    state:equals('dying):ifTrue({
        mario:vy := @expr(mario:vy + 0.5). mario:y := @expr(mario:y + mario:vy).
        dyingIn := dyingIn:dec.
        dyingIn:equals(#0):ifTrue({
            lives := lives:dec.
            lives:equals(#0):ifElse({ state := 'over }, { startLevel:value }) }) }).

    ; -- one whole frame, then show it
    tint:value(#1).
    sdl:fill(screen, #0, #0, width, height).
    i := #0.
    { i:lessThan(#21) }:whileTrue({ | c, sx |
        c := @expr(cam:truncated / tile + i + #1).
        sx := @expr(i * tile - cam:truncated:mod(tile)).
        c:lessOrEqual(cols):ifTrue({
            [#1, rows]:loop({ r | | v, sy |
                v := map:at(c, r). sy := @expr((r - #1) * tile).
                v:equals(ground):ifTrue({ tint:value(#2). sdl:fill(screen, sx, sy, tile, tile). tint:value(#3).
                    sdl:fill(screen, @expr(sx + #2), @expr(sy + #2), #12, #12). sdl:fill(screen, @expr(sx + #18), @expr(sy + #18), #12, #12) }).
                v:equals(brick):ifTrue({ tint:value(#2). sdl:fill(screen, sx, sy, tile, tile). tint:value(#1).
                    sdl:fill(screen, sx, @expr(sy + #15), tile, #2). sdl:fill(screen, @expr(sx + #15), sy, #2, #15). sdl:fill(screen, @expr(sx + #7), @expr(sy + #17), #2, #15). sdl:fill(screen, @expr(sx + #23), @expr(sy + #17), #2, #15) }).
                v:equals(question):or({ v:equals(mushroomBlock) }):ifTrue({ tint:value(#3). sdl:fill(screen, sx, sy, tile, tile).
                    tint:value(#2). sdl:fill(screen, @expr(sx + #10), @expr(sy + #6), #12, #4). sdl:fill(screen, @expr(sx + #18), @expr(sy + #10), #4, #6). sdl:fill(screen, @expr(sx + #14), @expr(sy + #16), #4, #6). sdl:fill(screen, @expr(sx + #14), @expr(sy + #24), #4, #4) }).
                v:equals(used):ifTrue({ tint:value(#2). sdl:fill(screen, sx, sy, tile, tile). sdl:colour(screen, #0, #0, #0). sdl:fill(screen, @expr(sx + #2), @expr(sy + #2), @expr(tile - #4), @expr(tile - #4)). tint:value(#2). sdl:fill(screen, @expr(sx + #4), @expr(sy + #4), @expr(tile - #8), @expr(tile - #8)) }).
                v:equals(pipe):ifTrue({ tint:value(#4). sdl:fill(screen, sx, sy, tile, tile). sdl:colour(screen, #0, #0, #0).
                    tileAt:value(c, @expr(r - #1)):equals(pipe):ifFalse({ sdl:fill(screen, sx, @expr(sy + #6), tile, #2) }).
                    sdl:fill(screen, @expr(sx + #4), sy, #2, tile) }).
                v:equals(stair):ifTrue({ tint:value(#2). sdl:fill(screen, sx, sy, tile, tile). sdl:colour(screen, #0, #0, #0). sdl:fill(screen, @expr(sx + #4), @expr(sy + #4), @expr(tile - #8), #2). sdl:fill(screen, @expr(sx + #4), @expr(sy + #4), #2, @expr(tile - #8)) }).
                v:equals(pole):ifTrue({ tint:value(#4). sdl:fill(screen, @expr(sx + #15), sy, #3, tile) }).
                v:equals(poleTop):ifTrue({ tint:value(#4). sdl:fill(screen, @expr(sx + #11), @expr(sy + #10), #10, #10). sdl:fill(screen, @expr(sx + #15), @expr(sy + #20), #3, #12).
                    tint:value(#3). sdl:fill(screen, @expr(sx - #10), @expr(sy + #24), #24, #16) }).
                v:equals(poleBase):ifTrue({ tint:value(#2). sdl:fill(screen, sx, sy, tile, tile) }).
                v:equals(castle):ifTrue({ tint:value(#2). sdl:fill(screen, sx, sy, tile, tile). sdl:colour(screen, #0, #0, #0).
                    tileAt:value(c, @expr(r - #1)):equals(castle):ifFalse({ sdl:fill(screen, @expr(sx + #4), sy, #8, #8). sdl:fill(screen, @expr(sx + #20), sy, #8, #8) }).
                    tileAt:value(c, @expr(r + #1)):equals(castle):ifFalse({ sdl:fill(screen, @expr(sx + #10), @expr(sy + #12), #12, #20) }) }) }) }).
        i := i:inc }).
    tint:value(#3).
    pops:do({ p | coinSprite:paint(@expr(((p:at(#1) - #1) * tile) - cam:truncated + #8), @expr((p:at(#2) - #2) * tile + p:at(#3) - #30)) }).
    tint:value(#2).
    debris:do({ d | sdl:fill(screen, @expr(d:at(#1) - cam):truncated, d:at(#2):truncated, #8, #8) }).
    items:do({ m | tint:value(#3). m:paint }).
    tint:value(#2).
    enemies:do({ f | f:alive:and({ f:awake }):and({ @expr(f:x - cam > -40.0 & f:x - cam < fw) }):ifTrue({ f:paint }) }).
    state:equals('attract):or({ state:equals('over) }):ifFalse({ tint:value(#5). sdl:colour(screen, #252, #56, #56). mario:paint }).

    ; -- the top: MARIO and the score, the coins, WORLD 1-1, TIME
    sdl:colour(screen, #252, #252, #252).
    state:equals('attract):ifFalse({
        font:word("MARIO", #16, #8). font:number(score, #150, #40).
        coinSprite:paint(#220, #40). font:number(coins, #290, #40).
        font:word("WORLD", #340, #8). font:number(#1, #388, #40). sdl:fill(screen, #396, #54, #10, #4). font:number(#1, #430, #40).
        font:word("TIME", #500, #8). font:number(clock, #600, #40) }).
    state:equals('over):ifTrue({ font:word("GAME OVER", #212, #220) }).

    engine:show }).

"final score {}":fill([score]):display.
