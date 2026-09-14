; defender.sol -- the eleventh game, the second whose world is wider than
; the screen, and the first with two views of it.
;
;     solvm --extension=build/sdl.so examples/defender.sob
;
;   Up / Down      fly; W / S do the same
;   Left / Right   face that way and thrust; A / D do the same
;   Space          the laser
;   X              a smart bomb: everything on the screen, three a ship
;   Z              hyperspace: somewhere else, usually
;   Space          when no game is on, start one
;   Escape         quit
;
; The 1981 rules, most of them. A planet six screens round, with ten
; humanoids standing on it. Landers come down to carry one off, and a
; lander that gets one to the top becomes a mutant, which hunts you. Shoot
; a lander on its way up and the humanoid falls: catch it for 500 and set
; it down for 500 more, or let it fall from too high and lose it. Baiters
; come when a wave takes too long, and are fast; bombers drift and leave
; mines; pods burst into swarmers when shot. A lander, a mutant or a
; swarmer is 150, a baiter 200, a bomber 250, a pod 1,000; every humanoid
; alive at the end of a wave is 100 times the wave. Lose the last
; humanoid and the planet goes: every lander is a mutant from then on,
; until the fifth wave after gives the planet back. A ship and a smart
; bomb more every 10,000, three of each to start. Two things the cabinet
; had that this does not: the second player, and the attract's roll of
; scores.
;
; **What was predicted before this was written.** That the camera is here
; a second time and harder: the world wraps, the view moves both ways at
; the ship's own speed and leads it in the direction it faces, and the
; scanner along the top is a second camera on the same world at another
; scale, so `toScreen` and `toScanner` are the two blocks every paint
; goes through and the reading of eleven has its second customer for the
; first of them. (The reading of twelve made the camera the engine's;
; `toScreen` is its `camera:screenX`, overridden here with the wrap.) That the ship is the first thing in eleven games with
; inertia under a key rather than a heading, so `craft` does not fit and
; `mover` bare does, with thrust as a line of the game. That the
; humanoids are the first things a game has attached to other things, a
; humanoid to the lander carrying it or to the ship, which is a slot and
; not an engine question. That `sprite` carries a fifth game, `font:word`
; a fifth, `tint` a fifth with the planet's colours, and `keys` its tenth.
; And that the binding would be asked for nothing.
;
; The tones are pitches chosen for this file.

@include "engine.sol".

engine:open("defender", #640, #480).

; -- the world
worldW := 3840.0.                    ; six screens round
skyTop := #60.                       ; the scanner is above this
groundY := #430.                     ; where a humanoid stands
scanLeft := #170. scanW := #300. scanTop := #4. scanH := #52.
upKeys := ["Up", "W"]. downKeys := ["Down", "S"].

; -- the rules
thrust := 0.25. topSpeed := 7.0. drag := 0.985.
climb := #4.
laserSpeed := 18.0. laserLength := #48. laserLife := #30.
humanoidsAWave := #10.
lifeEvery := #10000.
baiterAfter := #2400. baiterEvery := #700.

; -- the sounds
laserTone  := tone:make(#1400, #25).
hitTone    := tone:make(#120, #60).
catchTone  := tone:make(#900, #80).
dropTone   := tone:make(#500, #80).
mutantTone := tone:make(#200, #150).
bombTone   := tone:make(#60, #400).
hyperTone  := tone:make(#300, #200).
deathTone  := tone:make(#40, #700).
waveTone   := tone:make(#1000, #200).
planetTone := tone:make(#30, #1200).

; -- the game
state := 'attract.                   ; 'attract  'playing  'dying  'over
score := #0. lives := #0. bombs := #0. wave := #0. nextLife := lifeEvery.
ship := nil. facing := 1.0. held := nil.
humanoids := []. foes := []. bullets := []. mines := []. lasers := []. booms := [].
landersLeft := #0. bombersLeft := #0. podsLeft := #0. spawnIn := #0.
baiterIn := #0.
planetGone := false. planetBackAt := #0.
dyingIn := #0. flash := #0.
i := #0.

; ---------------------------------------------------------------------------
; The pictures.

pic := #2.
shipRight := sprite:make(["#####.......", "#..########.", "############", ".....######.", "......###..."], pic).
shipLeft  := sprite:make([".......#####", ".########..#", "############", ".######.....", "...###......"], pic).
landerSprite := sprite:make(["...##...", "..####..", ".#.##.#.", "########", "#.#..#.#", "#......#"], pic).
mutantSprite := sprite:make(["#.####.#", ".######.", "#.#..#.#", "########", ".#.##.#.", "#......#"], pic).
baiterSprite := sprite:make(["..####..", "########", "..####.."], pic).
bomberSprite := sprite:make([".######.", "#.#..#.#", "########", "#.#..#.#", ".######."], pic).
podSprite := sprite:make([".####.", "#.##.#", "######", "#.##.#", ".####."], pic).
swarmerSprite := sprite:make([".##.", "####", ".##."], pic).
humanoidSprite := sprite:make([".#.", "###", ".#.", ".#.", "#.#"], pic).
mineSprite := sprite:make([".#.", "###", ".#."], pic).
boomSprite := sprite:make(["#..#..#.", ".#.#.#..", "..###.#.", "##.#.###", "..###.#.", ".#.#.#..", "#..#..#."], pic).

; The planet's colours: the ground, the sky, the scanner's frame; and the
; same with the planet gone.
tint:sets := [[[#200, #120, #60], [#0, #0, #0], [#100, #100, #160]],
              [[#40, #40, #40],   [#0, #0, #0], [#160, #60, #60]]].

; ---------------------------------------------------------------------------
; The two cameras. A world x is between 0 and worldW; the difference from
; the camera is brought to the nearest, so that a thing just behind the
; wrap is just off the edge. The scanner is the same world at a twelfth,
; centred on the camera.

wrapX := { x | | w |
    w := x. w:lessThan(0.0):ifTrue({ w := @expr(w + worldW) }).
    w:greaterOrEqual(worldW):ifTrue({ w := @expr(w - worldW) }). w }.
nearest := { dx | | d |
    d := dx.
    d:lessThan(@expr(-worldW / 2.0)):ifTrue({ d := @expr(d + worldW) }).
    d:greaterOrEqual(@expr(worldW / 2.0)):ifTrue({ d := @expr(d - worldW) }). d }.
camera:screenX := { wx | nearest:value(@expr(wx - self:x)):truncated }.   ; the engine's, with the wrap
onScreen := { wx | | sx | sx := camera:screenX(wx). @expr(sx > #-40 & sx < width + #40) }.
toScanner := { wx | | d |
    d := nearest:value(@expr(wx - camera:x - fw / 2.0)).
    @expr(scanLeft + scanW / #2 + (d * scanW:asFloat / worldW):truncated) }.
scanY := { wy | @expr(scanTop + ((wy - skyTop) * scanH / (groundY - skyTop))) }.

; The mountains: a height per sixteen pixels of the world, drawn as lines.
mountain := [].
{ mountain:size:lessThan(#240) }:whileTrue({
    mountain:add(@expr(groundY - #10 - rng:upTo(#40))) }).
mountainAt := { k | mountain:at(@expr(k:mod(#240) + #1)) }.

; ---------------------------------------------------------------------------
; The things in the world. All movers in world coordinates.

; A humanoid: on the ground, carried by a lander, falling, or held by you.
humanoid := mover:new.
humanoid:mode := 'ground. humanoid:fellFrom := 0.0.
humanoid:make := { wx | | h | h := self:new. h:x := wx. h:y := @expr(groundY - #10):asFloat. h }.
humanoid:step := {
    self:mode:equals('falling):ifTrue({
        self:y := @expr(self:y + 1.5).
        self:y:greaterOrEqual(@expr(groundY - #10):asFloat):ifTrue({
            self:y := @expr(groundY - #10):asFloat.
            self:fellFrom:lessThan(250.0):ifElse({ self:alive := false. burst:value(self:x, self:y) }, { self:mode := 'ground }) }) }).
    self:mode:equals('held):ifTrue({
        self:x := @expr(ship:x + 8.0). self:y := @expr(ship:y + 12.0).
        ship:y:greaterOrEqual(@expr(groundY - #26):asFloat):ifTrue({
            self:mode := 'ground. self:y := @expr(groundY - #10):asFloat. held := nil. earn:value(#500). dropTone:play }) }) }.
humanoid:paint := { humanoidSprite:paint(camera:screenX(self:x), self:y:truncated) }.

; A foe: which kind, and what it carries.
foe := mover:new.
foe:kind := 'lander. foe:w := #16. foe:h := #12. foe:carrying := nil. foe:phase := 0.0. foe:fireIn := #0.
foe:make := { kind, wx, wy | | f |
    f := self:new. f:kind := kind. f:x := wx. f:y := wy.
    kind:equals('baiter):ifTrue({ f:h := #6 }).
    kind:equals('pod):ifTrue({ f:w := #12. f:h := #10. f:vx := @expr(rng:fraction * 2.0 - 1.0). f:vy := @expr(rng:fraction - 0.5) }).
    kind:equals('swarmer):ifTrue({ f:w := #8. f:h := #6 }).
    kind:equals('bomber):ifTrue({ f:w := #16. f:h := #10. f:vx := rng:upTo(#2):equals(#1):ifElse({ 1.2 }, { -1.2 }). f:fireIn := #40 }).
    kind:equals('lander):ifTrue({ f:vx := @expr(rng:fraction * 2.0 - 1.0). f:fireIn := @expr(#120 + rng:upTo(#120)) }).
    f:phase := @expr(rng:fraction * tau).
    f }.
foe:box := { self:via(mover):box(self:w, self:h) }.
worths := #[ "lander" = #150, "mutant" = #150, "swarmer" = #150, "baiter" = #200, "bomber" = #250, "pod" = #1000 ].
foe:worth := { worths:at(self:kind:asString) }.

; Plus or minus a magnitude, by the sign of a difference.
toward := { d, mag | d:greaterThan(0.0):ifElse({ mag }, { mag:negated }) }.

; Toward the ship, the near way round.
foe:dxToShip := { nearest:value(@expr(ship:x - self:x)) }.

foe:step := { | dx, dy, target |
    self:kind:equals('lander):ifTrue({
        self:carrying:isNil:ifElse(
            { ; the nearest humanoid on the ground, or a wander
              target := nil.
              humanoids:do({ h | h:alive:and({ h:mode:equals('ground) }):ifTrue({
                  target:isNil:or({ nearest:value(@expr(h:x - self:x)):abs:lessThan(nearest:value(@expr(target:x - self:x)):abs) }):ifTrue({ target := h }) }) }).
              target:notNil:ifElse(
                  { dx := nearest:value(@expr(target:x - self:x)).
                    dx:abs:greaterThan(4.0):ifElse({ self:vx := dx:greaterThan(0.0):ifElse({ 1.0 }, { -1.0 }). self:vy := 0.0 },
                                                   { self:vx := 0.0. self:vy := 0.8 }).
                    dx:abs:lessThan(6.0):and({ @expr(self:y + 22.0 >= target:y) }):ifTrue({
                        self:carrying := target. target:mode := 'carried. self:vy := -0.7. self:vx := 0.0 }) },
                  { self:vy := @expr(self:phase:sin * 0.5). self:phase := @expr(self:phase + 0.03) }) },
            { self:vy := -0.7. self:vx := 0.0.
              self:carrying:x := self:x. self:carrying:y := @expr(self:y + 14.0).
              self:y:lessThan(@expr(skyTop + #10):asFloat):ifTrue({
                  self:carrying:alive := false. self:carrying := nil. self:kind := 'mutant. mutantTone:play }) }).
        self:y:lessThan(@expr(skyTop + #10):asFloat):ifTrue({ self:vy := 0.5 }) }).
    self:kind:equals('mutant):ifTrue({
        dx := self:dxToShip. dy := @expr(ship:y - self:y).
        self:vx := @expr(self:vx * 0.9 + toward:value(dx, 0.35) + (rng:fraction - 0.5)).
        self:vy := @expr(self:vy * 0.9 + toward:value(dy, 0.3) + (rng:fraction - 0.5)) }).
    self:kind:equals('baiter):ifTrue({
        dx := self:dxToShip. dy := @expr(ship:y - self:y).
        self:vx := @expr(self:vx * 0.95 + toward:value(dx, 0.4)).
        self:vy := @expr(dy * 0.05) }).
    self:kind:equals('bomber):ifTrue({
        self:vy := @expr(self:phase:sin * 1.5). self:phase := @expr(self:phase + 0.05).
        self:fireIn := self:fireIn:dec.
        self:fireIn:equals(#0):ifTrue({ mines:add([self:x, self:y, #600]). self:fireIn := #50 }) }).
    self:kind:equals('swarmer):ifTrue({
        dx := self:dxToShip. dy := @expr(ship:y - self:y).
        self:vx := @expr(self:vx * 0.92 + toward:value(dx, 0.5) + (rng:fraction - 0.5) * 2.0).
        self:vy := @expr(self:vy * 0.92 + toward:value(dy, 0.4) + (rng:fraction - 0.5) * 2.0) }).
    self:move.
    self:x := wrapX:value(self:x).
    self:y:lessThan(skyTop:asFloat):ifTrue({ self:y := skyTop:asFloat }).
    self:y:greaterThan(@expr(groundY - #14):asFloat):ifTrue({ self:y := @expr(groundY - #14):asFloat }).
    ; a shot at you now and then, from anything that shoots
    self:kind:equals('lander):or({ self:kind:equals('mutant) }):or({ self:kind:equals('baiter) }):ifTrue({
        self:fireIn := self:fireIn:dec.
        self:fireIn:lessOrEqual(#0):and({ onScreen:value(self:x) }):ifTrue({
            shootAt:value(self). self:fireIn := @expr(#90 + rng:upTo(#150)) }) }) }.
foe:paint := { | sx, sy |
    sx := camera:screenX(self:x). sy := self:y:truncated.
    self:kind:equals('lander):ifTrue({ landerSprite:paint(sx, sy) }).
    self:kind:equals('mutant):ifTrue({ mutantSprite:paint(sx, sy) }).
    self:kind:equals('baiter):ifTrue({ baiterSprite:paint(sx, sy) }).
    self:kind:equals('bomber):ifTrue({ bomberSprite:paint(sx, sy) }).
    self:kind:equals('pod):ifTrue({ podSprite:paint(sx, sy) }).
    self:kind:equals('swarmer):ifTrue({ swarmerSprite:paint(sx, sy) }) }.

; A bullet of theirs: a dot, at where you were.
shootAt := { f | | b, dx, dy, d |
    b := mover:new. b:x := f:x. b:y := @expr(f:y + 6.0).
    dx := f:dxToShip. dy := @expr(ship:y - f:y). d := @expr(sqrt(dx * dx + dy * dy)).
    d:lessThan(1.0):ifTrue({ d := 1.0 }).
    b:vx := @expr(dx / d * 3.0). b:vy := @expr(dy / d * 3.0).
    b:life := #150.
    bullets:add(b) }.

; The laser: a line that races on, from the ship's nose, for a while.
laser := mover:new.
laser:life := #0.
laser:make := { | l, nose |
    nose := facing:greaterThan(0.0):ifElse({ 24.0 }, { 0.0 }).
    l := self:new. l:x := @expr(ship:x + nose). l:y := @expr(ship:y + 4.0).
    l:vx := @expr(facing * laserSpeed + ship:vx). l:life := laserLife. l }.
laser:box := { | b |
    b := self:via(mover):box(laserLength, #2).
    facing:greaterThan(0.0):ifTrue({ b:x := @expr(b:x - laserLength) }). b }.
laser:step := { self:move. self:x := wrapX:value(self:x). self:life := self:life:dec. self:life:equals(#0):ifTrue({ self:alive := false }) }.

; ---------------------------------------------------------------------------
; What happens

burst := { wx, wy | booms:add([wx, wy, #16]). hitTone:play }.

earn := { points |
    score := @expr(score + points).
    score:greaterOrEqual(nextLife):ifTrue({ lives := lives:inc. bombs := bombs:inc. nextLife := @expr(nextLife + lifeEvery). waveTone:play }) }.

; A foe destroyed: its worth, what it drops, what it bursts into.
destroy := { f |
    f:alive := false. earn:value(f:worth). burst:value(f:x, f:y).
    f:carrying:notNil:ifTrue({ f:carrying:mode := 'falling. f:carrying:fellFrom := f:carrying:y. f:carrying := nil }).
    f:kind:equals('pod):ifTrue({
        @expr(#3 + rng:upTo(#3)):repeat({ | s |
            s := foe:make('swarmer, f:x, f:y). s:vx := @expr(rng:fraction * 4.0 - 2.0). s:vy := @expr(rng:fraction * 4.0 - 2.0).
            foes:add(s) }) }) }.

; Somewhere in the world at least a screen from you.
spawnX := { wrapX:value(@expr(ship:x + 500.0 + rng:fraction * (worldW - 1000.0))) }.
spawnFoe := { kind | | f |
    f := foe:make(planetGone:and({ kind:equals('lander) }):ifElse({ 'mutant }, { kind }), spawnX:value, @expr(skyTop:asFloat + 20.0 + rng:fraction * 250.0)).
    foes:add(f) }.

startWave := {
    wave := wave:inc.
    landersLeft := wave:lessThan(#3):ifElse({ #15 }, { #20 }).
    bombersLeft := wave:lessThan(#2):ifElse({ #0 }, { wave:lessThan(#3):ifElse({ #3 }, { #4 }) }).
    podsLeft := wave:lessThan(#2):ifElse({ #0 }, { wave:lessThan(#3):ifElse({ #1 }, { #2 }) }).
    spawnIn := #30. baiterIn := baiterAfter.
    planetGone:and({ wave:greaterOrEqual(planetBackAt) }):ifTrue({
        planetGone := false. tint:set := #1.
        humanoids := []. humanoidsAWave:repeat({ humanoids:add(humanoid:make(@expr(rng:fraction * worldW))) }) }).
    foes := []. bullets := []. mines := []. lasers := []. booms := [] }.

newGame := {
    score := #0. lives := #3. bombs := #3. wave := #0. nextLife := lifeEvery.
    planetGone := false. tint:set := #1.
    humanoids := []. humanoidsAWave:repeat({ humanoids:add(humanoid:make(@expr(rng:fraction * worldW))) }).
    placeShip:value.
    startWave:value.
    state := 'playing }.

placeShip := {
    ship := mover:new. ship:x := 100.0. ship:y := 240.0. ship:vx := 0.0. ship:vy := 0.0.
    facing := 1.0. held := nil. camera:x := @expr(ship:x - 200.0) }.

; The planet lost: every lander a mutant, for four waves.
losePlanet := {
    planetGone := true. planetBackAt := @expr(wave + #5). tint:set := #2. planetTone:play.
    foes:do({ f | f:kind:equals('lander):ifTrue({ f:kind := 'mutant. f:carrying := nil }) }) }.

die := {
    state := 'dying. dyingIn := #90. deathTone:play. burst:value(ship:x, ship:y).
    held:notNil:ifTrue({ held:mode := 'falling. held:fellFrom := held:y. held := nil }) }.

smartBomb := {
    bombs:greaterThan(#0):ifTrue({
        bombs := bombs:dec. flash := #6. bombTone:play.
        foes:do({ f | f:alive:and({ onScreen:value(f:x) }):ifTrue({ destroy:value(f) }) }).
        bullets := []. mines := mines:select({ m | onScreen:value(m:at(#1)):not }) }) }.

hyperspace := {
    hyperTone:play.
    held:notNil:ifTrue({ held:mode := 'falling. held:fellFrom := held:y. held := nil }).
    ship:x := @expr(rng:fraction * worldW). ship:y := @expr(skyTop:asFloat + 30.0 + rng:fraction * 300.0).
    ship:vx := 0.0. camera:x := wrapX:value(@expr(ship:x - lead:value)).
    rng:upTo(#8):equals(#1):ifTrue({ die:value }) }.

shipBox := { ship:box(#24, #10) }.

; How far ahead of the ship the camera sits, by the way it faces.
lead := { facing:greaterThan(0.0):ifElse({ 200.0 }, { 440.0 }) }.

; ---------------------------------------------------------------------------

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):and({ event:repeat:equals(#0) }):ifTrue({
            state:equals('playing):ifTrue({
                event:key:equals("Space"):ifTrue({ lasers:add(laser:make). laserTone:play }).
                event:key:equals("X"):ifTrue({ smartBomb:value }).
                event:key:equals("Z"):ifTrue({ hyperspace:value }) }).
            event:key:equals("Space"):and({ state:equals('attract):or({ state:equals('over) }) }):ifTrue({
                newGame:value }) }) }).

    ; -- the pilot
    state:equals('playing):ifTrue({
        ; -- the ship: thrust the way it faces, drag otherwise, and the camera leads it
        keys:any(leftKeys):ifTrue({ facing := -1.0. ship:vx := @expr(ship:vx - thrust) }).
        keys:any(rightKeys):ifTrue({ facing := 1.0. ship:vx := @expr(ship:vx + thrust) }).
        keys:any(leftKeys):or({ keys:any(rightKeys) }):ifFalse({ ship:vx := @expr(ship:vx * drag) }).
        ship:vx:greaterThan(topSpeed):ifTrue({ ship:vx := topSpeed }).
        ship:vx:lessThan(topSpeed:negated):ifTrue({ ship:vx := topSpeed:negated }).
        keys:any(upKeys):ifTrue({ ship:y := @expr(ship:y - climb:asFloat) }).
        keys:any(downKeys):ifTrue({ ship:y := @expr(ship:y + climb:asFloat) }).
        ship:y:lessThan(skyTop:asFloat):ifTrue({ ship:y := skyTop:asFloat }).
        ship:y:greaterThan(@expr(groundY - #14):asFloat):ifTrue({ ship:y := @expr(groundY - #14):asFloat }).
        ship:x := wrapX:value(@expr(ship:x + ship:vx)).
        camera:x := wrapX:value(@expr(camera:x + nearest:value(@expr(ship:x - lead:value - camera:x)) * 0.08)).

        ; -- the wave: what is still to come, and the baiters when it drags
        spawnIn := spawnIn:dec.
        spawnIn:lessOrEqual(#0):ifTrue({
            spawnIn := #90.
            foes:select({ f | f:kind:equals('lander):or({ f:kind:equals('mutant) }) }):size:lessThan(#5):and({ landersLeft:greaterThan(#0) }):ifTrue({
                #2:repeat({ landersLeft:greaterThan(#0):ifTrue({ spawnFoe:value('lander). landersLeft := landersLeft:dec }) }) }).
            bombersLeft:greaterThan(#0):ifTrue({ spawnFoe:value('bomber). bombersLeft := bombersLeft:dec }).
            podsLeft:greaterThan(#0):ifTrue({ spawnFoe:value('pod). podsLeft := podsLeft:dec }) }).
        baiterIn := baiterIn:dec.
        baiterIn:lessOrEqual(#0):ifTrue({ spawnFoe:value('baiter). baiterIn := baiterEvery }).

        ; -- everything moves
        foes:do({ f | f:alive:ifTrue({ f:step }) }).
        humanoids:do({ h | h:alive:ifTrue({ h:step }) }).
        bullets:do({ b | b:move. b:x := wrapX:value(b:x). b:life := b:life:dec. b:life:equals(#0):ifTrue({ b:alive := false }) }).
        lasers:do({ l | l:step }).
        mines:do({ m | m:atPut(#3, m:at(#3):dec) }).
        booms:do({ bm | bm:atPut(#3, bm:at(#3):dec) }).

        ; -- the laser against the foes; the foes, bullets and mines against you
        lasers:do({ l | foes:do({ f |
            l:alive:and({ f:alive }):and({ onScreen:value(f:x) }):and({ l:box:touches(f:box) }):ifTrue({ l:alive := false. destroy:value(f) }) }) }).
        foes:do({ f | f:alive:and({ onScreen:value(f:x) }):and({ shipBox:value:touches(f:box) }):ifTrue({ destroy:value(f). die:value }) }).
        bullets:do({ b | b:alive:and({ onScreen:value(b:x) }):and({ shipBox:value:touches(rect:make(camera:screenX(b:x), b:y:truncated, #3, #3)) }):ifTrue({ b:alive := false. die:value }) }).
        mines:do({ m | onScreen:value(m:at(#1)):and({ shipBox:value:touches(rect:make(camera:screenX(m:at(#1)), m:at(#2):truncated, #6, #6)) }):ifTrue({ m:atPut(#3, #0). die:value }) }).

        ; -- a humanoid falling, caught
        held:isNil:ifTrue({
            humanoids:do({ h |
                h:alive:and({ h:mode:equals('falling) }):and({ onScreen:value(h:x) })
                 :and({ shipBox:value:touches(rect:make(camera:screenX(h:x), h:y:truncated, #6, #10)) }):ifTrue({
                    h:mode := 'held. held := h. earn:value(#500). catchTone:play }) }) }).

        foes := foes:select({ f | f:alive }).
        bullets := bullets:select({ b | b:alive }).
        lasers := lasers:select({ l | l:alive }).
        mines := mines:select({ m | m:at(#3):greaterThan(#0) }).
        booms := booms:select({ bm | bm:at(#3):greaterThan(#0) }).
        humanoids := humanoids:select({ h | h:alive }).

        ; -- the planet, and the wave
        humanoids:size:equals(#0):and({ planetGone:not }):ifTrue({ losePlanet:value }).
        landersLeft:equals(#0):and({ bombersLeft:equals(#0) }):and({ podsLeft:equals(#0) })
            :and({ foes:select({ f | f:kind:equals('baiter):not }):size:equals(#0) }):ifTrue({
                earn:value(@expr(humanoids:size * #100 * wave)). waveTone:play. startWave:value }) }).

    ; -- a death: the world holds, then a ship again or the end
    state:equals('dying):ifTrue({
        booms:do({ bm | bm:atPut(#3, bm:at(#3):dec) }).
        booms := booms:select({ bm | bm:at(#3):greaterThan(#0) }).
        dyingIn := dyingIn:dec.
        dyingIn:equals(#0):ifTrue({
            lives := lives:dec.
            lives:equals(#0):ifElse({ state := 'over }, {
                placeShip:value. foes := []. bullets := []. mines := []. lasers := [].
                spawnIn := #60. state := 'playing }) }) }).
    flash:greaterThan(#0):ifTrue({ flash := flash:dec }).

    ; -- one whole frame, then show it
    flash:greaterThan(#0):ifElse({ sdl:clear(screen, #248, #248, #248) }, { sdl:clear(screen, #0, #0, #0) }).
    planetGone:ifFalse({
        tint:value(#1).
        i := #0.
        { i:lessThan(#41) }:whileTrue({ | k, sx |
            k := @expr((camera:x:truncated + i * #16) / #16).
            sx := @expr(i * #16 - camera:x:truncated:mod(#16)).
            sdl:line(screen, sx, mountainAt:value(k), @expr(sx + #16), mountainAt:value(k:inc)).
            i := i:inc }) }).
    sdl:colour(screen, #248, #200, #80).
    humanoids:do({ h | onScreen:value(h:x):ifTrue({ h:paint }) }).
    sdl:colour(screen, #80, #248, #80).
    foes:do({ f | onScreen:value(f:x):ifTrue({ f:paint }) }).
    sdl:colour(screen, #248, #80, #80).
    bullets:do({ b | onScreen:value(b:x):ifTrue({ sdl:fill(screen, camera:screenX(b:x), b:y:truncated, #3, #3) }) }).
    mines:do({ m | onScreen:value(m:at(#1)):ifTrue({ mineSprite:paint(camera:screenX(m:at(#1)), m:at(#2):truncated) }) }).
    sdl:colour(screen, #248, #248, #248).
    lasers:do({ l | onScreen:value(l:x):ifTrue({ l:box:paint }) }).
    sdl:colour(screen, #248, #160, #40).
    booms:do({ bm | onScreen:value(bm:at(#1)):ifTrue({ boomSprite:paint(camera:screenX(bm:at(#1)), bm:at(#2):truncated) }) }).
    state:equals('playing):ifTrue({
        sdl:colour(screen, #80, #200, #248).
        facing:greaterThan(0.0):ifElse({ shipRight:paint(camera:screenX(ship:x), ship:y:truncated) },
                                       { shipLeft:paint(camera:screenX(ship:x), ship:y:truncated) }) }).

    ; -- the scanner: the whole world at a twelfth, and the screen's box
    sdl:colour(screen, #0, #0, #0).
    sdl:fill(screen, #0, #0, width, skyTop).
    tint:value(#3).
    sdl:line(screen, scanLeft, scanTop, @expr(scanLeft + scanW), scanTop).
    sdl:line(screen, scanLeft, @expr(scanTop + scanH), @expr(scanLeft + scanW), @expr(scanTop + scanH)).
    sdl:line(screen, scanLeft, scanTop, scanLeft, @expr(scanTop + scanH)).
    sdl:line(screen, @expr(scanLeft + scanW), scanTop, @expr(scanLeft + scanW), @expr(scanTop + scanH)).
    sdl:line(screen, toScanner:value(camera:x), scanTop, toScanner:value(camera:x), @expr(scanTop + scanH)).
    sdl:line(screen, toScanner:value(@expr(camera:x + fw)), scanTop, toScanner:value(@expr(camera:x + fw)), @expr(scanTop + scanH)).
    sdl:colour(screen, #248, #200, #80).
    humanoids:do({ h | sdl:fill(screen, toScanner:value(h:x), scanY:value(h:y:truncated), #2, #2) }).
    sdl:colour(screen, #80, #248, #80).
    foes:do({ f | sdl:fill(screen, toScanner:value(f:x), scanY:value(f:y:truncated), #3, #2) }).
    state:equals('playing):ifTrue({
        sdl:colour(screen, #248, #248, #248).
        sdl:fill(screen, toScanner:value(ship:x), scanY:value(ship:y:truncated), #3, #3) }).
    sdl:line(screen, #0, skyTop, width, skyTop).

    ; -- the score, the ships, the bombs, the wave
    sdl:colour(screen, #248, #248, #248).
    state:equals('attract):ifFalse({
        font:number(score, #150, #10).
        i := #0.
        { i:lessThan(lives) }:whileTrue({ shipRight:paint(@expr(#490 + i * #28), #8). i := i:inc }).
        i := #0.
        { i:lessThan(bombs) }:whileTrue({ sdl:fill(screen, @expr(#490 + i * #10), #30, #6, #12). i := i:inc }).
        font:number(wave, #620, #10) }).
    state:equals('over):ifTrue({ font:centred("GAME OVER", #220) }).

    engine:show }).

"final score {}":fill([score]):display.
