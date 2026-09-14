; scramble.sol -- the tenth game, and the first whose world is wider than
; the screen.
;
;     solvm --extension=build/sdl.so examples/scramble.sob
;
;   arrows / WASD  the ship, anywhere on the left of the screen
;   Space / Z      the laser, forward; three in the air
;   X / C          a bomb, forward and down; two in the air
;   Space          when no game is on, start one
;   Escape         quit
;
; The 1981 rules. The world scrolls left under the ship at a steady pace
; and the ship flies where it likes on the screen, but the ground and the
; roof are where they are and touching either is the end of it. Fuel
; drains all the while and is refilled by bombing or shooting a tank; dry,
; the ship falls. Rockets stand on the ground and launch when the ship is
; near, 50 standing and 80 in the air; a tank is 150; a mystery base is
; 100, 200 or 300, whichever it turns out to be; a UFO 100; a fireball
; cannot be destroyed and only avoided. Six stages: open ground with
; rockets, a cave with UFOs, a cave with fireballs, a city of towers, a
; winding tunnel, and the base, which bombed is 800 and the start of the
; next round, faster and thirstier. Ten points for every stretch of
; ground flown over, a ship more at 10,000, three to start; a ship lost
; starts its stage again. Two things the cabinet had that this does not:
; the second player's turn, and the flag-count of rounds beside the score.
;
; **What was predicted before this was written.** That the world being
; wider than the screen means a camera, one number that every paint goes
; through and that nothing in the engine has a notion of: a sprite paints
; at a screen position and a mover moves in whatever space it is given,
; so the movers live in the world and the subtraction happens at the
; paint, in one block, and whether that block is one game's or the
; engine's is the reading's question. (The reading of twelve answered
; it, after Defender and Mario: `camera` is the engine's, and so is the
; box at a mover's position that all three had written.) That the ground is a table again,
; but a one-dimensional one and generated ahead of the camera rather than
; laid out at the start, which no game has done. That `rect` carries its
; fourth game in screen space and nothing in world space, since the
; overlap test does not care what space it is in as long as both sides
; agree; that the rockets in flight, the bombs, the fireballs and the
; UFOs are `mover`s bare; that `sprite` carries a fourth game; that
; `font:word` has a fourth customer in FUEL; and that the binding would
; be asked for nothing.
;
; The tones are pitches chosen for this file.

@include "engine.sol".

engine:open("scramble", #640, #480).

; -- the world
colW := #8.                          ; a ground column, in pixels
skyTop := #0. hudTop := #440.        ; the ground lives between these
shipLeftMost := #0. shipRightMost := #380.
stageCols := #400.                   ; columns a stage is long
upKeys := ["Up", "W"]. downKeys := ["Down", "S"].
fireKeys := ["Space", "Z"]. bombKeys := ["X", "C"].

; -- the rules
shipSpeed := #3.
shotSpeed := 8.0. shotsMost := #3.
bombsMost := #2. bombGravity := 0.12.
fuelFull := #100. tankFuel := #16.
lifeEvery := #10000.

; -- the sounds
shotTone   := tone:make(#800, #20).
bombTone   := tone:make(#200, #40).
boomTone   := tone:make(#100, #80).
tankTone   := tone:make(#1000, #80).
launchTone := tone:make(#300, #60).
crashTone  := tone:make(#50, #600).
lowTone    := tone:make(#900, #40).
baseTone   := tone:make(#150, #500).
lifeTone   := tone:make(#1200, #200).

; -- the game
state := 'attract.                   ; 'attract  'flying  'crashing  'over
score := #0. lives := #0. round := #1. stage := #1. nextLife := lifeEvery.
pace := 1.5.                         ; pixels a frame the world moves
fuel := #0. fuelIn := #0. fuelRate := #28.
ground := [].                        ; per world column: [floor y, roof y]
foes := [].                          ; everything in the world but the ground
shots := []. bombs := []. booms := [].
ship := nil.
stageStart := #0. stageRng := nil.
crashIn := #0. distance := #0.
i := #0.

; ---------------------------------------------------------------------------
; The pictures.

pic := #2.
shipSprite := sprite:make(["#####.......", "#.#####.....", "############", "..#####..###", "#####.......", "#..........."], pic).
rocketSprite := sprite:make([".#.", "###", "###", "###", "###", "###", "#.#", "#.#"], pic).
flameSprite := sprite:make([".#.", "###", "#.#"], pic).
tankSprite := sprite:make(["..####..", ".#....#.", "#.####.#", "#.#..#.#", "#.####.#", "#......#", ".#....#.", "..####.."], pic).
mysterySprite := sprite:make(["########", "#..##..#", "#.#..#.#", "#..##..#", "#...#..#", "#..#...#", "#......#", "########"], pic).
ufoSprite := sprite:make(["...##...", ".######.", "########", ".#.##.#."], pic).
fireSprite := sprite:make(["..##..", ".####.", "######", "######", ".####.", "..##.."], pic).
baseSprite := sprite:make(["....####....", "...######...", "..##.##.##..", ".##..##..##.", "############", "#.#.#..#.#.#", "############", "##.##..##.##"], pic).
boomSprite := sprite:make(["#..#..#.", ".#.#.#..", "..###.#.", "##.#.###", "..###.#.", ".#.#.#..", "#..#..#.", "........"], pic).

; The stage's colours: the ground, the roof, and the sky; the set in use is
; the stage. (The reading of ten moved `tint` into the engine; the table
; stays here.)
tint:sets := [[[#200, #120, #40],  [#200, #120, #40],  [#0, #0, #40]],
             [[#60, #160, #60],   [#60, #160, #60],   [#0, #0, #0]],
             [[#160, #60, #60],   [#160, #60, #60],   [#20, #0, #0]],
             [[#120, #120, #200], [#120, #120, #200], [#0, #0, #30]],
             [[#200, #200, #60],  [#200, #200, #60],  [#0, #0, #0]],
             [[#180, #180, #180], [#180, #180, #180], [#0, #20, #0]]].

; ---------------------------------------------------------------------------
; The ground: a floor and a roof per column, made up as the camera comes
; to it, by the stage's own rules and from the stage's own seeded
; generator, so that a stage begun again is the same stage.

colAt := { wx | @expr(wx:truncated / colW + #1) }.       ; the column a world x is in
floorAt := { col | col:lessOrEqual(ground:size):ifElse({ ground:at(col):at(#1) }, { hudTop }) }.
roofAt := { col | col:lessOrEqual(ground:size):ifElse({ ground:at(col):at(#2) }, { skyTop }) }.

; The stage a column is in, and where that stage began.
stageOf := { col | @expr(((col - #1) / stageCols):mod(#6) + #1) }.
startOf := { col | @expr(((col - #1) / stageCols) * stageCols + #1) }.

; One more column on the end, by the stage's rules.
growGround := { | col, st, floor, roof, last, k |
    col := @expr(ground:size + #1).
    st := stageOf:value(col).
    last := ground:size:greaterThan(#0):ifElse({ ground:at(ground:size) }, { [#400, skyTop] }).
    floor := last:at(#1). roof := last:at(#2).
    k := @expr(col - startOf:value(col)).
    k:equals(#0):ifTrue({ stageRng := random:new(@expr(round * #100 + st)) }).
    st:equals(#1):ifTrue({                          ; rolling ground, no roof
        floor := @expr(floor + stageRng:between(#-8, #8)).
        roof := skyTop }).
    st:equals(#2):or({ st:equals(#3) }):ifTrue({    ; a cave
        floor := @expr(floor + stageRng:between(#-8, #8)).
        roof := @expr(roof + stageRng:between(#-8, #8)).
        roof:lessThan(#40):ifTrue({ roof := #40 }). roof:greaterThan(#180):ifTrue({ roof := #180 }) }).
    st:equals(#4):ifTrue({                          ; the city: a flat street and towers
        roof := #40.
        k:mod(#10):lessThan(#3):ifElse({ floor := @expr(#180 + stageRng:upTo(#3) * #60) }, { floor := #420 }) }).
    st:equals(#5):ifTrue({                          ; the tunnel: floor and roof together
        k:mod(#4):equals(#0):ifTrue({ floor := @expr(floor + stageRng:between(#-16, #16)) }).
        floor:lessThan(#180):ifTrue({ floor := #180 }).
        roof := @expr(floor - #110 - stageRng:upTo(#20)) }).
    st:equals(#6):ifTrue({                          ; the base: a flat approach
        floor := #400. roof := skyTop }).
    floor:greaterThan(#420):ifTrue({ floor := #420 }). floor:lessThan(#260):and({ st:equals(#4):not }):ifTrue({ floor := #260 }).
    roof:lessThan(skyTop):ifTrue({ roof := skyTop }).
    ground:add([floor, roof]).
    placeAt:value(col, st, k, floor) }.

; Enough ground to draw a screen and a little more.
groundTo := { wx | | need |
    need := @expr(colAt:value(wx) + #2).
    { ground:size:lessThan(need) }:whileTrue({ growGround:value }) }.

; ---------------------------------------------------------------------------
; The foes: everything in the world but the ground, every one a mover in world coordinates with a
; kind, a box the size of its picture, and what it is worth.

foe := mover:new.
foe:kind := 'rocket. foe:w := #16. foe:h := #16. foe:launched := false. foe:phase := 0.0.
foe:make := { kind, wx, wy, w, h | | t |
    t := self:new. t:kind := kind. t:x := wx. t:y := wy. t:w := w. t:h := h. t }.
; Its box, on the screen.
foe:box := { self:via(mover):box(self:w, self:h) }.
foe:step := {
    self:kind:equals('rocket):ifTrue({
        self:launched:not:and({ @expr(self:x - camera:x < 260.0) }):ifTrue({
            self:launched := true. self:vy := -0.5. launchTone:play }).
        self:launched:ifTrue({ self:vy := @expr(self:vy - 0.04). self:move }) }).
    self:kind:equals('ufo):ifTrue({
        self:phase := @expr(self:phase + 0.05).
        self:x := @expr(self:x + pace * 0.3).
        self:y := @expr(self:y + self:phase:sin * 1.2) }).
    self:kind:equals('fire):ifTrue({ self:move }).
    @expr(self:x - camera:x < -40.0 | self:y < -40.0):ifTrue({ self:alive := false }) }.
foe:paint := { | sx, sy |
    sx := camera:screenX(self:x). sy := self:y:truncated.
    self:kind:equals('rocket):ifTrue({
        rocketSprite:paint(@expr(sx + #5), sy).
        self:launched:and({ frames:mod(#2):equals(#0) }):ifTrue({ flameSprite:paint(@expr(sx + #5), @expr(sy + #16)) }) }).
    self:kind:equals('tank):ifTrue({ tankSprite:paint(sx, sy) }).
    self:kind:equals('mystery):ifTrue({ mysterySprite:paint(sx, sy) }).
    self:kind:equals('ufo):ifTrue({ ufoSprite:paint(sx, sy) }).
    self:kind:equals('fire):ifTrue({ fireSprite:paint(sx, sy) }).
    self:kind:equals('base):ifTrue({ baseSprite:paint(sx, sy) }) }.

; What stands on the ground at a column, by the stage: rockets, tanks and
; mysteries on the floor, and the base at the end of the sixth.
placeAt := { col, st, k, floor | | wx, r |
    wx := @expr((col - #1) * colW):asFloat.
    r := stageRng:upTo(#100).
    st:equals(#6):and({ k:equals(@expr(stageCols - #40)) }):ifTrue({
        foes:add(foe:make('base, wx, @expr(floor - #16):asFloat, #24, #16)) }).
    k:mod(#12):equals(#6):and({ k:greaterThan(#20) }):and({ k:lessThan(@expr(stageCols - #60)) }):ifTrue({
        st:equals(#1):ifTrue({
            r:lessThan(#60):ifElse({ foes:add(foe:make('rocket, wx, @expr(floor - #16):asFloat, #14, #16)) },
                { r:lessThan(#85):ifElse({ foes:add(foe:make('tank, wx, @expr(floor - #16):asFloat, #16, #16)) },
                                        { foes:add(foe:make('mystery, wx, @expr(floor - #16):asFloat, #16, #16)) }) }) }).
        st:equals(#2):or({ st:equals(#3) }):ifTrue({
            r:lessThan(#35):ifElse({ foes:add(foe:make('rocket, wx, @expr(floor - #16):asFloat, #14, #16)) },
                { r:lessThan(#75):ifElse({ foes:add(foe:make('tank, wx, @expr(floor - #16):asFloat, #16, #16)) },
                                        { foes:add(foe:make('mystery, wx, @expr(floor - #16):asFloat, #16, #16)) }) }) }).
        st:equals(#4):and({ floor:equals(#420) }):ifTrue({
            r:lessThan(#60):ifElse({ foes:add(foe:make('rocket, wx, @expr(floor - #16):asFloat, #14, #16)) },
                                   { foes:add(foe:make('tank, wx, @expr(floor - #16):asFloat, #16, #16)) }) }).
        st:equals(#5):ifTrue({
            r:lessThan(#60):ifElse({ foes:add(foe:make('tank, wx, @expr(floor - #16):asFloat, #16, #16)) },
                                   { foes:add(foe:make('mystery, wx, @expr(floor - #16):asFloat, #16, #16)) }) }).
        st:equals(#6):ifTrue({
            r:lessThan(#50):ifElse({ foes:add(foe:make('rocket, wx, @expr(floor - #16):asFloat, #14, #16)) },
                                   { foes:add(foe:make('tank, wx, @expr(floor - #16):asFloat, #16, #16)) }) }) }).
    st:equals(#2):and({ k:mod(#30):equals(#15) }):ifTrue({
        foes:add(foe:make('ufo, wx, @expr(#80 + stageRng:upTo(#120)):asFloat, #16, #8)) }) }.

; A fireball, from the right, in the third stage.
fireIn := #0.
throwFire := { | f |
    f := foe:make('fire, @expr(camera:x + fw + 20.0), @expr(60.0 + rng:fraction * 300.0), #12, #12).
    f:vx := @expr(-(2.0 + rng:fraction * 2.0)). f:vy := @expr(rng:fraction * 1.0 - 0.5).
    foes:add(f) }.

; ---------------------------------------------------------------------------
; The ship, its shots and its bombs, on the screen and in the world.

ship := rect:make(#60, #200, #24, #12).

; A shot: a mover in the world, a short line.
shot := mover:new.
shot:make := { | s | s := self:new. s:x := @expr(camera:x + ship:right:asFloat). s:y := @expr(ship:y:asFloat + 5.0). s:vx := shotSpeed. s }.
shot:box := { self:via(mover):box(#8, #2) }.
shot:step := { | col |
    self:move.
    col := colAt:value(self:x).
    @expr(self:x - camera:x > fw):or({ self:y:truncated:greaterThan(floorAt:value(col)) }):or({ self:y:truncated:lessThan(roofAt:value(col)) }):ifTrue({
        self:alive := false }) }.

; A bomb: forward with the ship, then down, and a burst where it lands.
bomb := mover:new.
bomb:make := { | b | b := self:new. b:x := @expr(camera:x + ship:x:asFloat + 8.0). b:y := @expr(ship:bottom:asFloat). b:vx := @expr(pace + 2.5). b:vy := 0.0. b }.
bomb:box := { self:via(mover):box(#6, #6) }.
bomb:step := { | col |
    self:vy := @expr(self:vy + bombGravity).
    self:move.
    col := colAt:value(self:x).
    @expr(self:y:truncated + #6 >= floorAt:value(col)):ifTrue({
        self:alive := false. burst:value(self:x, @expr(floorAt:value(col) - #16):asFloat) }) }.

burst := { wx, wy | booms:add([wx, wy, #14]). boomTone:play }.

; ---------------------------------------------------------------------------
; What happens

earn := { points |
    score := @expr(score + points).
    score:greaterOrEqual(nextLife):ifTrue({ lives := lives:inc. nextLife := @expr(nextLife + lifeEvery). lifeTone:play }) }.

; A foe hit by a shot or a bomb.
destroy := { t |
    t:alive := false.
    t:kind:equals('rocket):ifTrue({ earn:value(t:launched:ifElse({ #80 }, { #50 })) }).
    t:kind:equals('tank):ifTrue({ earn:value(#150). fuel := @expr(fuel + tankFuel). fuel:greaterThan(fuelFull):ifTrue({ fuel := fuelFull }). tankTone:play }).
    t:kind:equals('mystery):ifTrue({ earn:value([#100, #200, #300]:at(rng:upTo(#3))) }).
    t:kind:equals('ufo):ifTrue({ earn:value(#100) }).
    t:kind:equals('base):ifTrue({ earn:value(#800). baseTone:play. nextRound:value }).
    burst:value(t:x, t:y) }.

; The stage's beginning, or the same one again after a crash: the ground
; from its first column, the foes gone, the ship placed.
startStage := {
    stageStart := startOf:value(colAt:value(camera:x)).
    ground := ground:first(@expr(stageStart - #1)).
    foes := []. shots := []. bombs := []. booms := [].
    camera:x := @expr((stageStart - #1) * colW):asFloat.
    stage := stageOf:value(stageStart). tint:set := stage.
    ship:x := #60. ship:y := #200.
    fuel := fuelFull. fuelIn := fuelRate. fireIn := #90.
    groundTo:value(@expr(camera:x + fw)).
    state := 'flying }.

nextRound := {
    round := round:inc.
    pace := @expr(1.5 + (round - #1):asFloat * 0.25).
    fuelRate := @expr(#28 - (round - #1) * #3). fuelRate:lessThan(#12):ifTrue({ fuelRate := #12 }) }.

newGame := {
    score := #0. lives := #3. round := #1. nextLife := lifeEvery. distance := #0.
    pace := 1.5. fuelRate := #28.
    camera:x := 0.0. ground := [].
    startStage:value }.

crash := { state := 'crashing. crashIn := #90. crashTone:play. burst:value(@expr(camera:x + ship:x:asFloat), ship:y:asFloat) }.

; The ship against the ground under it and the roof over it.
shipHitsGround := { | hit |
    hit := false.
    [colAt:value(@expr(camera:x + ship:x:asFloat)), colAt:value(@expr(camera:x + ship:right:asFloat - 1.0))]:loop({ col |
        ship:bottom:greaterThan(floorAt:value(col)):or({ ship:y:lessThan(roofAt:value(col)) }):ifTrue({ hit := true }) }).
    hit }.

; ---------------------------------------------------------------------------

groundTo:value(fw).                  ; some ground, to look at before a game

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):and({ event:repeat:equals(#0) }):ifTrue({
            state:equals('flying):ifTrue({
                fireKeys:indexOf(event:key):notNil:and({ shots:size:lessThan(shotsMost) }):ifTrue({
                    shots:add(shot:make). shotTone:play }).
                bombKeys:indexOf(event:key):notNil:and({ bombs:size:lessThan(bombsMost) }):ifTrue({
                    bombs:add(bomb:make). bombTone:play }) }).
            event:key:equals("Space"):and({ state:equals('attract):or({ state:equals('over) }) }):ifTrue({
                newGame:value }) }) }).

    ; -- the pilot
    state:equals('flying):ifTrue({
        ; -- the ship, which answers the keys while it has fuel
        fuel:greaterThan(#0):ifTrue({
            keys:any(leftKeys):ifTrue({ ship:x := @expr(ship:x - shipSpeed) }).
            keys:any(rightKeys):ifTrue({ ship:x := @expr(ship:x + shipSpeed) }).
            keys:any(upKeys):ifTrue({ ship:y := @expr(ship:y - shipSpeed) }).
            keys:any(downKeys):ifTrue({ ship:y := @expr(ship:y + shipSpeed) }) }).
        ship:x:lessThan(shipLeftMost):ifTrue({ ship:x := shipLeftMost }).
        ship:x:greaterThan(shipRightMost):ifTrue({ ship:x := shipRightMost }).
        ship:y:lessThan(skyTop):ifTrue({ ship:y := skyTop }).
        @expr(ship:bottom > hudTop):ifTrue({ ship:y := @expr(hudTop - ship:h) }).

        ; -- the world moves, and the ground is made to meet it
        camera:x := @expr(camera:x + pace).
        groundTo:value(@expr(camera:x + fw)).
        distance := distance:inc.
        distance:mod(#16):equals(#0):ifTrue({ earn:value(#10) }).
        stageOf:value(colAt:value(camera:x)):equals(stage):ifFalse({
            stage := stageOf:value(colAt:value(camera:x)). tint:set := stage. fireIn := #90 }).
        stage:equals(#3):ifTrue({
            fireIn := fireIn:dec.
            fireIn:lessOrEqual(#0):ifTrue({ throwFire:value. fireIn := @expr(#40 + rng:upTo(#50)) }) }).

        ; -- fuel
        fuelIn := fuelIn:dec.
        fuelIn:lessOrEqual(#0):ifTrue({
            fuelIn := fuelRate. fuel := fuel:dec.
            fuel:lessOrEqual(#20):and({ fuel:mod(#4):equals(#0) }):ifTrue({ lowTone:play }) }).
        fuel:lessOrEqual(#0):ifTrue({ fuel := #0. ship:y := @expr(ship:y + #2) }).

        ; -- everything in the world
        foes:do({ t | t:alive:ifTrue({ t:step }) }).
        shots:do({ s | s:step }).
        bombs:do({ b | b:step }).
        booms:do({ bm | bm:atPut(#3, bm:at(#3):dec) }).

        ; -- what hits what
        shots:do({ s | foes:do({ t |
            s:alive:and({ t:alive }):and({ t:kind:equals('fire):not }):and({ s:box:touches(t:box) }):ifTrue({
                s:alive := false. destroy:value(t) }) }) }).
        bombs:do({ b | foes:do({ t |
            b:alive:and({ t:alive }):and({ t:kind:equals('fire):not }):and({ b:box:touches(t:box) }):ifTrue({
                b:alive := false. destroy:value(t) }) }) }).
        foes:do({ t | t:alive:and({ ship:touches(t:box) }):ifTrue({ crash:value }) }).
        shipHitsGround:value:ifTrue({ crash:value }).

        foes := foes:select({ t | t:alive }).
        shots := shots:select({ s | s:alive }).
        bombs := bombs:select({ b | b:alive }).
        booms := booms:select({ bm | bm:at(#3):greaterThan(#0) }) }).

    ; -- a crash: the world stands still, then the stage again or the end
    state:equals('crashing):ifTrue({
        booms:do({ bm | bm:atPut(#3, bm:at(#3):dec) }).
        booms := booms:select({ bm | bm:at(#3):greaterThan(#0) }).
        crashIn := crashIn:dec.
        crashIn:equals(#0):ifTrue({
            lives := lives:dec.
            lives:equals(#0):ifElse({ state := 'over }, { startStage:value }) }) }).

    ; -- one whole frame, then show it
    tint:value(#3).
    sdl:fill(screen, #0, #0, width, height).
    i := #0.
    { i:lessThan(@expr(width / colW + #1)) }:whileTrue({ | col, sx |
        col := colAt:value(@expr(camera:x + (i * colW):asFloat)).
        sx := @expr(i * colW - (camera:x:truncated:mod(colW))).
        tint:value(#1).
        sdl:fill(screen, sx, floorAt:value(col), colW, @expr(hudTop - floorAt:value(col))).
        tint:value(#2).
        roofAt:value(col):greaterThan(skyTop):ifTrue({ sdl:fill(screen, sx, skyTop, colW, roofAt:value(col)) }).
        i := i:inc }).
    sdl:colour(screen, #230, #230, #230).
    foes:do({ t | t:paint }).
    sdl:colour(screen, #248, #248, #80).
    shots:do({ s | s:box:paint }).
    sdl:colour(screen, #248, #248, #248).
    bombs:do({ b | b:box:paint }).
    sdl:colour(screen, #248, #160, #40).
    booms:do({ bm | boomSprite:paint(camera:screenX(bm:at(#1)), bm:at(#2):truncated) }).
    state:equals('flying):ifTrue({ sdl:colour(screen, #80, #200, #248). shipSprite:paint(ship:x, ship:y) }).

    ; -- the panel: the score, the fuel, the stage
    sdl:colour(screen, #0, #0, #0).
    sdl:fill(screen, #0, hudTop, width, @expr(height - hudTop)).
    sdl:colour(screen, #248, #248, #248).
    state:equals('attract):ifFalse({
        font:number(score, #150, #446).
        font:word("FUEL", #200, #446).
        sdl:colour(screen, fuel:lessOrEqual(#20):ifElse({ #248 }, { #80 }), fuel:lessOrEqual(#20):ifElse({ #80 }, { #200 }), #80).
        sdl:fill(screen, #310, #450, @expr(fuel * #2), #12).
        sdl:colour(screen, #248, #248, #248).
        i := #0.
        { i:lessThan(lives) }:whileTrue({ shipSprite:paint(@expr(#8 + i * #28), #448). i := i:inc }).
        [#1, #6]:loop({ st |
            st:equals(stage):ifElse({ sdl:colour(screen, #248, #200, #40) }, { sdl:colour(screen, #100, #100, #100) }).
            sdl:fill(screen, @expr(#530 + (st - #1) * #18), #452, #14, #10) }) }).

    engine:show }).

"final score {}":fill([score]):display.
