; asteroids.sol -- the third game, and the first to test the engine's
; boundary rather than the binding's.
;
;     solvm --extension=build/sdl.so examples/asteroids.sob
;
;   Left / Right   turn; A / D do the same
;   Up             thrust; W does the same
;   Space          fire; when no game is on, start one
;   H              hyperspace
;   Escape         quit
;
; The 1979 rules. A large rock is 20, a medium 50, a small 100, and each
; splits in two down to small. Four rocks on the first wave and two more
; each wave to a ceiling of eleven. Three ships, and one more at every
; 10,000. Four shots on the screen at once. Hyperspace takes the ship off
; the screen for a moment and puts it back somewhere else, or does not.
; A large saucer is 200 and fires where it likes; the small one is 1,000
; and fires at you, and takes over once the score passes 10,000. A saucer's
; shots break rocks too, and a rock breaks a saucer.
;
; **What was predicted before this was written**, so that the file can be
; scored against it. Of the engine's six names, four would carry over
; unchanged: `engine`, `keys`, `font`, `tone`. Two would not fit at all:
; `rect`, because nothing here is a rectangle, and `ball`, because a rock's
; integer shadow is not a box but a radius, and Asteroids wraps where Pong
; bounced. So this file would define its own moving thing, and whether
; `ball` is that thing's special case is a question for the reading after,
; not for this file. (The reading of three found neither is the other's
; case: both are a `mover`. The reading of five, after Spacewar! wanted the
; same `thing`, `draw` and `mote`, moved all three into the engine, with
; `craft` for what the two games' ships shared; this file keeps the rock,
; the shot, the saucer and the rules.) Of the binding's twelve messages it would ask for
; nothing: `sdl:line` is the whole of the vector display, the trigonometry
; is the machine's, and the continuous sounds, thrust and siren and the
; heartbeat, would be `sdl:beep` re-issued from the frame, since a beep
; that is about now can be asked for again now. (The re-issuing became
; `tone:hum` in the engine at the reading of four, when Invaders wanted it
; the same way.)
;
; **What is here that neither game had**: a shape is a list of unit points
; drawn as lines after one rotation and one scale, so a rock is nine
; `sdl:line`s and never a `fill`; everything that moves wraps; collisions
; are a distance against two radii; and the things on the screen are lists
; that are rebuilt with `select` when something dies. The sound is one
; channel with the latest beep winning, so the continuous sounds yield to
; anything that just happened.
;
; The tones are pitches chosen for this file.

@include "engine.sol".

engine:open("asteroids", #640, #480).

up := -1.5707963267948966.          ; a heading, since y runs down the screen

thrustKeys := ["Up", "W"].

; -- the ship
turnRate  := 0.085.                  ; radians a frame
thrustAt  := 0.14.                   ; pixels a frame a frame
drag      := 0.985.
topSpeed  := 7.0.
shotSpeed := 9.0.
shotLife  := #48.                    ; frames
shotsMost := #4.

; -- the rocks, by size: 1 small, 2 medium, 3 large
rockRadius := [8.0, 16.0, 32.0].
rockSpeed  := [2.2, 1.5, 0.9].
rockScore  := [#100, #50, #20].

; -- the saucers
saucerLarge := #200. saucerSmall := #1000.
saucerAfter := #600.                 ; frames between saucers, at least
saucerAim   := 0.3.                  ; the small one's error, in radians

; -- the sounds
fireTone   := tone:make(#700, #40).
bangTones  := [tone:make(#220, #110), tone:make(#140, #160), tone:make(#90, #220)].
thrustTone := tone:make(#55, #40).
sirenTones := [[tone:make(#180, #80), tone:make(#220, #80)],
               [tone:make(#360, #80), tone:make(#440, #80)]].
heartTones := [tone:make(#50, #60), tone:make(#40, #60)].
bonusTone  := tone:make(#1000, #80).
hyperTone  := tone:make(#300, #60).

; -- the game
score := #0. lives := #0. wave := #0. nextBonus := #10000.
state := 'attract.                   ; 'attract  'playing  'over
rocks := []. shots := []. saucerShots := []. debris := [].
saucer := nil. saucerIn := saucerAfter.
respawnIn := #0. waveIn := #0. hyperIn := #0.
heartIn := #0. heartBeat := #1. sirenBeat := #1.
born := []. i := #0. k := nil.

; ---------------------------------------------------------------------------
; The shapes, as unit points drawn in order and closed.

shipShape  := [[1.0, 0.0], [-0.7, 0.6], [-0.4, 0.0], [-0.7, -0.6]].
hullShape  := [[1.0, 0.0], [0.5, 0.4], [-0.5, 0.4], [-1.0, 0.0], [-0.5, -0.4], [0.5, -0.4]].
domeShape  := [[0.3, -0.4], [0.2, -0.8], [-0.2, -0.8], [-0.3, -0.4]].
rockShapes := [
    [[1.0, 0.2], [0.6, 0.9], [-0.1, 1.0], [-0.7, 0.6], [-1.0, 0.0],
     [-0.6, -0.6], [-0.2, -1.0], [0.5, -0.8], [0.9, -0.4]],
    [[0.9, 0.4], [0.3, 0.7], [0.0, 1.0], [-0.6, 0.8], [-1.0, 0.2],
     [-0.8, -0.5], [-0.3, -0.9], [0.4, -1.0], [1.0, -0.3]],
    [[1.0, 0.0], [0.5, 0.5], [0.7, 1.0], [0.0, 0.8], [-0.7, 0.9], [-1.0, 0.2],
     [-0.6, -0.4], [-0.9, -0.8], [-0.2, -1.0], [0.5, -0.6]],
    [[0.8, 0.6], [0.2, 0.9], [-0.4, 1.0], [-0.9, 0.5], [-0.7, -0.1],
     [-1.0, -0.6], [-0.3, -1.0], [0.4, -0.7], [1.0, -0.3]]].

; -- a rock
rock := thing:new.
rock:size := #3. rock:shape := nil.
rock:make := { size, px, py | | k |
    k := self:new.
    k:size := size. k:x := px. k:y := py.
    k:r := rockRadius:at(size).
    k:shape := rockShapes:at(rng:upTo(#4)).
    k:aim(@expr(rng:fraction * tau), @expr(rockSpeed:at(size) * (0.6 + rng:fraction * 0.8))).
    k }.
rock:paint := { draw:value(self:shape, self:x, self:y, 0.0, self:r) }.

; -- a shot, from the ship or a saucer
shot := thing:new.
shot:life := #0.
shot:make := { px, py, angle, speed | | s |
    s := self:new. s:x := px. s:y := py. s:life := shotLife.
    s:aim(angle, speed). s }.
shot:step := { self:via(thing):step. self:life := self:life:dec.
    self:life:equals(#0):ifTrue({ self:alive := false }) }.
shot:paint := { sdl:fill(screen, self:x:truncated, self:y:truncated, #2, #2) }.

; -- the ship: a craft with drag. One of them; it is reset rather than remade.
ship := craft:new.
ship:r := 10.0. ship:heading := up. ship:mode := 'dead.      ; 'alive 'dead 'hyper
ship:reset := {
    self:x := @expr(fw / 2.0). self:y := @expr(fh / 2.0).
    self:vx := 0.0. self:vy := 0.0. self:heading := up.
    self:mode := 'alive }.
ship:thrust := { self:burn(thrustAt, topSpeed) }.
ship:coast := { self:vx := @expr(self:vx * drag). self:vy := @expr(self:vy * drag) }.

; -- a saucer, a thing and not a craft, since it has no heading. Crosses the
; screen, wrapping in y only, and leaves at the far side; changes its mind
; about up and down now and then; fires.
ufo := thing:new.
ufo:small := false. ufo:fireIn := #0. ufo:turnIn := #0. ufo:dir := 1.0.
ufo:make := { small | | c |
    c := self:new.
    c:small := small.
    c:r := small:ifElse({ 6.0 }, { 12.0 }).
    rng:upTo(#2):equals(#1):ifElse({ c:dir := 1.0 }, { c:dir := -1.0 }).
    c:x := c:dir:lessThan(0.0):ifElse({ @expr(fw + c:r) }, { @expr(-c:r) }).
    c:y := @expr(rng:fraction * fh).
    c:vx := @expr(c:dir * 1.5). c:vy := 0.0.
    c:fireIn := #60. c:turnIn := #90.
    c }.
ufo:wrap := {
    self:y:lessThan(@expr(-self:r)):ifTrue({ self:y := @expr(self:y + fh + 2.0 * self:r) }).
    self:y:greaterThan(@expr(fh + self:r)):ifTrue({ self:y := @expr(self:y - fh - 2.0 * self:r) }).
    self:dir:greaterThan(0.0):and({ self:x:greaterThan(@expr(fw + self:r)) }):ifTrue({ self:alive := false }).
    self:dir:lessThan(0.0):and({ self:x:lessThan(@expr(-self:r)) }):ifTrue({ self:alive := false }) }.
ufo:step := {
    self:via(thing):step.
    self:turnIn := self:turnIn:dec.
    self:turnIn:equals(#0):ifTrue({
        self:turnIn := #90.
        self:vy := [-1.0, 0.0, 1.0]:at(rng:upTo(#3)) }).
    self:fireIn := self:fireIn:dec.
    self:fireIn:equals(#0):ifTrue({ self:fireIn := #60. self:fire }) }.
ufo:fire := { | angle |
    self:small:and({ ship:mode:equals('alive) }):ifElse(
        { angle := @expr(float:atan2(ship:y - self:y, ship:x - self:x)
                         + (rng:fraction - 0.5) * 2.0 * saucerAim) },
        { angle := @expr(rng:fraction * tau) }).
    saucerShots:add(shot:make(self:x, self:y, angle, 6.0)).
    fireTone:play }.
ufo:paint := { | s |
    s := self:r.
    draw:value(hullShape, self:x, self:y, 0.0, s).
    draw:value(domeShape, self:x, self:y, 0.0, s).
    sdl:line(screen, @expr(self:x - s):truncated, self:y:truncated,
                     @expr(self:x + s):truncated, self:y:truncated) }.

; ---------------------------------------------------------------------------
; What happens to things

; A rock breaks: dots, two smaller rocks or none, and the bang for its size.
; `worth` says whether the ship gets the points.
burst := { k, worth |
    k:alive := false.
    i := #0.
    { i:lessThan(#6) }:whileTrue({
        debris:add(mote:make(k:x, k:y, false, #30)). i := i:inc }).
    k:size:greaterThan(#1):ifTrue({
        born:add(rock:make(k:size:dec, k:x, k:y)).
        born:add(rock:make(k:size:dec, k:x, k:y)) }).
    worth:ifTrue({ score := @expr(score + rockScore:at(k:size)) }).
    bangTones:at(k:size):play }.

; The saucer goes, with or without the points.
downSaucer := { worth |
    saucer:alive := false.
    i := #0.
    { i:lessThan(#8) }:whileTrue({
        debris:add(mote:make(saucer:x, saucer:y, false, #30)). i := i:inc }).
    worth:ifTrue({
        score := @expr(score + saucer:small:ifElse({ saucerSmall }, { saucerLarge })) }).
    bangTones:at(#2):play.
    saucer := nil. saucerIn := @expr(saucerAfter + rng:upTo(#600)) }.

; The ship goes: four lines of it fly apart, and the next one comes when
; the middle of the screen is clear, or the game is over.
killShip := {
    ship:mode := 'dead.
    i := #0.
    { i:lessThan(#4) }:whileTrue({
        debris:add(mote:make(ship:x, ship:y, true, #70)). i := i:inc }).
    bangTones:at(#3):play.
    lives := lives:dec.
    lives:equals(#0):ifElse({ state := 'over }, { respawnIn := #120 }) }.

; The middle is clear when no rock is near it and there is no saucer.
centreClear := { | clear |
    clear := saucer:isNil.
    rocks:do({ k | k:within(ship, 100.0):ifTrue({ clear := false }) }).
    clear }.

; A wave: rocks along the edges, away from the ship at the centre.
spawnWave := { | count, px, py |
    wave := wave:inc.
    count := @expr(#4 + (wave - #1) * #2).
    count:greaterThan(#11):ifTrue({ count := #11 }).
    i := #0.
    { i:lessThan(count) }:whileTrue({
        rng:upTo(#2):equals(#1):ifElse(
            { px := @expr(rng:fraction * fw). py := 0.0 },
            { px := 0.0. py := @expr(rng:fraction * fh) }).
        rocks:add(rock:make(#3, px, py)).
        i := i:inc }) }.

fire := {
    shots:size:lessThan(shotsMost):ifTrue({
        k := shot:make(@expr(ship:x + ship:heading:cos * 12.0),
                       @expr(ship:y + ship:heading:sin * 12.0),
                       ship:heading, shotSpeed).
        k:vx := @expr(k:vx + ship:vx). k:vy := @expr(k:vy + ship:vy).
        shots:add(k).
        fireTone:play }) }.

hyperspace := {
    ship:mode := 'hyper. hyperIn := #60. hyperTone:play }.

newGame := {
    score := #0. lives := #3. wave := #0. nextBonus := #10000.
    rocks := []. shots := []. saucerShots := []. debris := [].
    saucer := nil. saucerIn := saucerAfter.
    ship:reset. spawnWave:value. heartIn := #60.
    state := 'playing }.

; ---------------------------------------------------------------------------

spawnWave:value.                     ; something to look at before a game

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):ifTrue({
            event:key:equals("Space"):ifTrue({
                state:equals('playing):ifElse(
                    { ship:mode:equals('alive):ifTrue({ fire:value }) },
                    { newGame:value }) }).
            event:key:equals("H"):and({ ship:mode:equals('alive) }):ifTrue({
                hyperspace:value }) }) }).

    ; -- the ship
    ship:mode:equals('alive):ifTrue({
        keys:any(leftKeys):ifTrue({ ship:turn(turnRate:negated) }).
        keys:any(rightKeys):ifTrue({ ship:turn(turnRate) }).
        keys:any(thrustKeys):ifTrue({ ship:thrust. thrustTone:hum }).
        ship:coast.
        ship:step }).
    ship:mode:equals('hyper):ifTrue({
        hyperIn := hyperIn:dec.
        hyperIn:equals(#0):ifTrue({
            ship:x := @expr(rng:fraction * fw). ship:y := @expr(rng:fraction * fh).
            ship:vx := 0.0. ship:vy := 0.0.
            ship:mode := 'alive.
            rng:upTo(#8):equals(#1):ifTrue({ killShip:value }) }) }).
    ship:mode:equals('dead):and({ state:equals('playing) }):ifTrue({
        respawnIn:greaterThan(#0):ifTrue({ respawnIn := respawnIn:dec }).
        respawnIn:equals(#0):and({ centreClear:value }):ifTrue({ ship:reset }) }).

    ; -- everything else moves
    rocks:do({ k | k:step }).
    shots:do({ s | s:step }).
    saucerShots:do({ s | s:step }).
    debris:do({ m | m:step }).
    saucer:notNil:ifTrue({ saucer:step. saucer:alive:ifFalse({ saucer := nil. saucerIn := saucerAfter }) }).

    ; -- what hits what
    born := [].
    shots:do({ s |
        rocks:do({ k |
            s:alive:and({ k:alive }):and({ s:touches(k) }):ifTrue({
                s:alive := false. burst:value(k, true) }) }).
        saucer:notNil:and({ s:alive }):and({ s:touches(saucer) }):ifTrue({
            s:alive := false. downSaucer:value(true) }) }).
    saucerShots:do({ s |
        rocks:do({ k |
            s:alive:and({ k:alive }):and({ s:touches(k) }):ifTrue({
                s:alive := false. burst:value(k, false) }) }).
        ship:mode:equals('alive):and({ s:alive }):and({ s:touches(ship) }):ifTrue({
            s:alive := false. killShip:value }) }).
    rocks:do({ k |
        ship:mode:equals('alive):and({ k:alive }):and({ k:touches(ship) }):ifTrue({
            burst:value(k, true). killShip:value }).
        saucer:notNil:and({ k:alive }):and({ k:touches(saucer) }):ifTrue({
            burst:value(k, false). downSaucer:value(false) }) }).
    saucer:notNil:and({ ship:mode:equals('alive) }):and({ saucer:touches(ship) }):ifTrue({
        downSaucer:value(true). killShip:value }).

    rocks := rocks:select({ k | k:alive }).
    born:do({ k | rocks:add(k) }).
    shots := shots:select({ s | s:alive }).
    saucerShots := saucerShots:select({ s | s:alive }).
    debris := debris:select({ m | m:alive }).

    ; -- what comes next
    state:equals('playing):ifTrue({
        score:greaterOrEqual(nextBonus):ifTrue({
            lives := lives:inc. nextBonus := @expr(nextBonus + #10000). bonusTone:play }).
        rocks:size:equals(#0):ifTrue({
            waveIn:equals(#0):ifTrue({ waveIn := #120 }).
            waveIn := waveIn:dec.
            waveIn:equals(#0):ifTrue({ spawnWave:value }) }).
        saucer:isNil:ifTrue({
            saucerIn := saucerIn:dec.
            saucerIn:equals(#0):ifTrue({
                saucer := ufo:make(score:greaterOrEqual(#10000):and({ rng:upTo(#5):greaterThan(#1) })) }) }).

        ; the heartbeat, quicker as the rocks go
        heartIn := heartIn:dec.
        heartIn:lessOrEqual(#0):ifTrue({
            heartTones:at(heartBeat):hum.
            heartBeat := @expr(#3 - heartBeat).
            heartIn := @expr(#12 + rocks:size * #4) }) }).
    saucer:notNil:and({ frames:mod(#10):equals(#0) }):ifTrue({
        sirenTones:at(saucer:small:ifElse({ #2 }, { #1 })):at(sirenBeat):hum.
        sirenBeat := @expr(#3 - sirenBeat) }).
    state:equals('over):and({ debris:size:equals(#0) }):ifTrue({ state := 'attract }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #0, #0, #0).
    sdl:colour(screen, #230, #230, #230).
    rocks:do({ k | k:paint }).
    shots:do({ s | s:paint }).
    saucerShots:do({ s | s:paint }).
    debris:do({ m | m:paint }).
    saucer:notNil:ifTrue({ saucer:paint }).
    ship:mode:equals('alive):ifTrue({ ship:paint(shipShape, 12.0, keys:any(thrustKeys)) }).
    state:equals('attract):ifFalse({
        font:number(score, #100, #14).
        i := #0.
        { i:lessThan(lives) }:whileTrue({
            draw:value(shipShape, @expr(30.0 + i:asFloat * 16.0), 52.0, up, 6.0).
            i := i:inc }) }).

    engine:show }).

"final score {}":fill([score]):display.
