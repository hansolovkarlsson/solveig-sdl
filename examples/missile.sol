; missile.sol -- the eighth game, the first aimed with the mouse, and the
; first with a title.
;
;     solvm --extension=build/sdl.so examples/missile.sob
;
;   the mouse      the crosshair, the way the 1980 trackball did
;   left / middle / right button   fire from Alpha, Delta, Omega;
;                  Z / X / C do the same
;   Space          when no game is on, start one
;   Escape         quit
;
; The 1980 rules. Six cities and three bases along the ground, ten missiles
; a base a wave, the middle base's the faster. Missiles come down as lines
; from the top toward the cities and the bases, some splitting on the way;
; from the second wave a bomber or a satellite crosses and drops more, and
; from the fifth a smart bomb comes down that steers round an explosion
; unless it is boxed in. A missile of yours flies to the crosshair and
; explodes into a disc that grows and shrinks, and anything caught in a
; disc is destroyed and explodes in turn, so a good shot chains. A missile
; that arrives takes its city, or its base's missiles for the wave. A
; missile is 25, a bomber or satellite 100, a smart bomb 125, all times the
; wave's multiplier, 1 to 6 by pairs of waves. At the end of a wave every
; missile left is 5 and every city standing is 100, times the multiplier,
; counted one at a time with a tick; a bonus city is earned every 10,000
; and rebuilt at the count. The game ends at a count with no city standing,
; and says so: THE END. Two things the cabinet had that this does not: the
; demo in the attract, and the sixteen-colour changes, which are five here.
;
; **What was predicted before this was written.** That `keys` would carry
; nothing here for the first time in eight games, since every input is an
; event, a click or a press that fires once, and the crosshair is the
; pointer kept from `'mouseMove` as Breakout kept its paddle. That the
; incoming and outgoing missiles, the bombers and the smart bombs would all
; delegate to `mover` itself, the first game to want neither `ball` nor
; `thing` but the four slots and two lines under both: a missile is a head
; that moves and a trail from where it started, and nothing here bounces
; or wraps. That the cities and the bombers are pictures, so `sprite`
; carries its third game; that `font:word` gets its third customer and
; its first title, THE END in cells three times the size, built from the
; engine's own rows rather than drawn again; that the explosion is a disc
; out of lines as circles.sol drew one, copied rather than shared since
; that file is not a game; and that the binding would be asked for
; nothing.
;
; The tones are pitches chosen for this file.

@include "engine.sol".

engine:open("missile", #640, #480).

ground := #440.
fireKeys := ["Z", "X", "C"].         ; Alpha, Delta, Omega

; -- the rules
missilesABase := #10.
abmSpeed := [4.5, 8.0, 4.5].         ; the middle base is the fast one
boomMost := 28.0.                    ; a disc's largest radius, in pixels
boomRate := 0.9.                     ; radius a frame, growing and shrinking
lowAt := #3.                         ; when a base says LOW

; -- the sounds
fireTone  := tone:make(#700, #40).
boomTone  := tone:make(#90, #100).
cityTone  := tone:make(#55, #400).
tickTone  := tone:make(#900, #25).
bonusTone := tone:make(#1200, #150).
endTone   := tone:make(#45, #900).
dropTone  := tone:make(#300, #60).

; -- the game
state := 'attract.                   ; 'attract  'wave  'counting  'end
score := #0. wave := #0. mult := #1.
aimX := #320. aimY := #240.
icbms := []. abms := []. booms := []. flyers := []. smarts := [].
toLaunch := #0. launchIn := #0.
flyersLeft := #0. flyerIn := #0. smartsLeft := #0. smartIn := #0.
bonusCities := #0. nextBonus := #10000.
countStep := #0. countIn := #0. countBase := #1. countCity := #1.
countMissiles := #0. countCitiesUp := #0.
palette := #1.
i := #0. sky := nil.

; ---------------------------------------------------------------------------
; The pictures. A city is a skyline; a base is a hill with its missiles
; stacked on it; a bomber and a satellite are what they are.

pic := #2.                           ; a picture cell, in pixels
citySprite := sprite:make(["....#....#....", "..#.#..#.#....", "..###.####..#.", ".####.####.###",
                           "#####.#######.", "##############"], pic).
rubbleSprite := sprite:make(["..#........#..", "#####.##.#####"], pic).
bomberSprite := sprite:make(["......##......", "#############.", "###############", ".....###......"], pic).
satSprite := sprite:make(["#.#.....#.#", "###.###.###", "#.#.....#.#"], pic).

; The wave's colours, five sets by pairs of waves: sky, ground, the enemy's
; trail, yours.
palettes := [[[#0, #0, #0],     [#232, #200, #40], [#232, #40, #40],  [#40, #120, #248]],
             [[#0, #0, #0],     [#0, #160, #0],    [#248, #248, #0],  [#0, #200, #200]],
             [[#0, #40, #80],   [#248, #120, #0],  [#0, #248, #0],    [#248, #0, #248]],
             [[#40, #0, #40],   [#0, #200, #200],  [#248, #160, #0],  [#248, #248, #248]],
             [[#0, #0, #0],     [#200, #0, #0],    [#248, #248, #248], [#248, #248, #0]]].
tint := { which | | c |
    c := palettes:at(palette):at(which).
    sdl:colour(screen, c:at(#1), c:at(#2), c:at(#3)) }.

; A filled disc, one horizontal line a row, as circles.sol drew one.
disc := { cx, cy, r | | dy, hw |
    dy := r:negated.
    { @expr(dy <= r) }:whileTrue({
        hw := @expr(r * r - dy * dy):asFloat:sqrt:truncated.
        sdl:line(screen, @expr(cx - hw), @expr(cy + dy), @expr(cx + hw), @expr(cy + dy)).
        dy := dy:inc }) }.

; ---------------------------------------------------------------------------
; What stands on the ground: a city is alive or rubble, a base has missiles
; or has none. Both are targets, which is one list.

city := object:new.
city:x := #0. city:alive := true. city:kind := 'city.
city:make := { px | | c | c := self:new. c:x := px. c }.
city:paint := {
    self:alive:ifElse({ citySprite:paint(@expr(self:x - #14), @expr(ground - #12)) },
                      { rubbleSprite:paint(@expr(self:x - #14), @expr(ground - #4)) }) }.
cities := [#104, #168, #232, #408, #472, #536]:collect({ px | city:make(px) }).

base := object:new.
base:x := #0. base:missiles := #0. base:index := #1. base:kind := 'base.
base:make := { px, index | | b | b := self:new. b:x := px. b:index := index. b }.
base:paint := { | n, row, col, left |
    tint:value(#2).
    sdl:fill(screen, @expr(self:x - #24), @expr(ground - #6), #48, #6).
    tint:value(#4).
    n := self:missiles. row := #1. left := @expr(self:x - #9).
    { n:greaterThan(#0):and({ row:lessOrEqual(#4) }) }:whileTrue({
        col := #0.
        { col:lessThan(@expr(#5 - row)):and({ n:greaterThan(#0) }) }:whileTrue({
            sdl:fill(screen, @expr(left + (row - #1) * #3 + col * #6), @expr(ground - #6 - row * #4), #2, #3).
            n := n:dec. col := col:inc }).
        row := row:inc }).
    self:missiles:equals(#0):ifTrue({ font:word("OUT", @expr(self:x - #33), @expr(ground + #6)) }).
    @expr(self:missiles > #0 & self:missiles <= lowAt):ifTrue({
        font:word("LOW", @expr(self:x - #33), @expr(ground + #6)) }) }.
bases := [base:make(#40, #1), base:make(#320, #2), base:make(#600, #3)].

; Somewhere to aim at: any city, standing or not, or a base; the cabinet
; kept shooting at rubble, which is what makes a dead city still cost you.
targets := { | t | t := []. cities:do({ c | t:add(c) }). bases:do({ b | t:add(b) }). t }.
aTarget := { | t | t := targets:value. t:at(rng:upTo(t:size)) }.

; ---------------------------------------------------------------------------
; The things in the air. All of them are a `mover` with a target; a missile
; keeps where it started for its trail.

; An incoming missile: from a point, at a target on the ground, splitting
; once on the way if it was born to.
icbm := mover:new.
icbm:ox := 0.0. icbm:oy := 0.0. icbm:target := nil.
icbm:splitAt := 0.0. icbm:splitsInto := #0.
icbm:make := { px, py, target, speed | | m |
    m := self:new. m:x := px. m:y := py. m:ox := px. m:oy := py. m:target := target.
    m:aim(float:atan2(@expr(ground:asFloat - py), @expr(target:x:asFloat - px)), speed).
    m:splitAt := 0.0. m:splitsInto := #0.
    m }.
icbm:step := {
    self:move.
    self:splitsInto:greaterThan(#0):and({ self:y:greaterThan(self:splitAt) }):ifTrue({
        self:splitsInto:repeat({
            icbms:add(icbm:make(self:x, self:y, aTarget:value, self:speed)) }).
        self:splitsInto := #0 }).
    self:y:greaterOrEqual(ground:asFloat):ifTrue({ self:alive := false. arrive:value(self) }) }.
icbm:paint := {
    sdl:line(screen, self:ox:truncated, self:oy:truncated, self:x:truncated, self:y:truncated).
    sdl:fill(screen, @expr(self:x:truncated - #1), @expr(self:y:truncated - #1), #3, #3) }.

; One of yours: from a base to the crosshair, where it explodes.
abm := mover:new.
abm:ox := 0.0. abm:oy := 0.0. abm:tx := 0.0. abm:ty := 0.0.
abm:make := { b, tx, ty | | m |
    m := self:new.
    m:x := b:x:asFloat. m:y := @expr(ground:asFloat - 8.0). m:ox := m:x. m:oy := m:y.
    m:tx := tx. m:ty := ty.
    m:aim(float:atan2(@expr(ty - m:y), @expr(tx - m:x)), abmSpeed:at(b:index)).
    m }.
abm:step := { | dx, dy |
    self:move.
    dx := @expr(self:tx - self:x). dy := @expr(self:ty - self:y).
    @expr(dx * dx + dy * dy < self:speed * self:speed):ifTrue({
        self:alive := false. explode:value(self:tx, self:ty) }) }.
abm:paint := {
    sdl:line(screen, self:ox:truncated, self:oy:truncated, self:x:truncated, self:y:truncated).
    sdl:fill(screen, @expr(self:x:truncated - #1), @expr(self:y:truncated - #1), #3, #3) }.

; An explosion: a disc that grows to its largest and shrinks away, killing
; whatever its edge reaches while it is there.
boom := object:new.
boom:x := 0.0. boom:y := 0.0. boom:r := 0.0. boom:growing := true. boom:alive := true.
boom:make := { px, py | | b | b := self:new. b:x := px. b:y := py. b }.
boom:step := {
    self:growing:ifElse(
        { self:r := @expr(self:r + boomRate).
          self:r:greaterOrEqual(boomMost):ifTrue({ self:growing := false }) },
        { self:r := @expr(self:r - boomRate).
          self:r:lessOrEqual(0.0):ifTrue({ self:alive := false }) }) }.
boom:reaches := { px, py | | dx, dy |
    dx := @expr(px - self:x). dy := @expr(py - self:y).
    @expr(dx * dx + dy * dy < self:r * self:r) }.
boom:paint := {
    frames:mod(#4):lessThan(#2):ifElse({ tint:value(#4) }, { sdl:colour(screen, #248, #248, #248) }).
    disc:value(self:x:truncated, self:y:truncated, self:r:truncated) }.

; A bomber or a satellite: across the sky at its height, dropping a
; missile now and then.
flyer := mover:new.
flyer:sat := false. flyer:dropIn := #0.
flyer:make := { sat | | f |
    f := self:new. f:sat := sat.
    f:y := sat:ifElse({ 70.0 }, { 130.0 }).
    rng:upTo(#2):equals(#1):ifElse(
        { f:x := -20.0. f:vx := sat:ifElse({ 0.8 }, { 1.1 }) },
        { f:x := @expr(fw + 20.0). f:vx := sat:ifElse({ -0.8 }, { -1.1 }) }).
    f:dropIn := @expr(#90 + rng:upTo(#90)).
    f }.
flyer:step := {
    self:move.
    self:dropIn := self:dropIn:dec.
    self:dropIn:equals(#0):and({ @expr(self:x > 20.0 & self:x < fw - 20.0) }):ifTrue({
        icbms:add(icbm:make(self:x, self:y, aTarget:value, icbmSpeed:value)).
        self:dropIn := @expr(#120 + rng:upTo(#120)). dropTone:play }).
    @expr(self:x < -30.0 | self:x > fw + 30.0):ifTrue({ self:alive := false }) }.
flyer:paint := {
    self:sat:ifElse({ satSprite:paint(@expr(self:x:truncated - #11), @expr(self:y:truncated - #3)) },
                    { bomberSprite:paint(@expr(self:x:truncated - #15), @expr(self:y:truncated - #4)) }) }.

; A smart bomb: down toward its target, slower, with no trail, slipping
; sideways from any disc whose edge comes near; caught only when the edge
; reaches it anyway.
smart := mover:new.
smart:target := nil. smart:pace := 0.0.
smart:make := { target, speed | | s |
    s := self:new. s:x := @expr(20.0 + rng:fraction * (fw - 40.0)). s:y := 0.0.
    s:target := target. s:pace := speed. s }.
smart:step := { | dodged |
    dodged := false.
    booms:do({ b | | dx, dy, near |
        dx := @expr(self:x - b:x). dy := @expr(self:y - b:y).
        near := @expr(b:r + 16.0).
        dodged:not:and({ @expr(dx * dx + dy * dy < near * near) }):ifTrue({
            dodged := true.
            dx:lessThan(0.0):ifElse({ self:vx := self:pace:negated }, { self:vx := self:pace }).
            self:vy := 0.0 }) }).
    dodged:ifFalse({
        self:aim(float:atan2(@expr(ground:asFloat - self:y), @expr(self:target:x:asFloat - self:x)), self:pace) }).
    self:move.
    self:x:lessThan(4.0):ifTrue({ self:x := 4.0 }).
    self:x:greaterThan(@expr(fw - 4.0)):ifTrue({ self:x := @expr(fw - 4.0) }).
    self:y:greaterOrEqual(ground:asFloat):ifTrue({ self:alive := false. arrive:value(self) }) }.
smart:paint := {
    frames:mod(#2):equals(#0):ifTrue({
        sdl:fill(screen, @expr(self:x:truncated - #2), @expr(self:y:truncated - #2), #5, #5) }) }.

; ---------------------------------------------------------------------------
; What happens

icbmSpeed := { | s | s := @expr(0.8 + (wave - #1):asFloat * 0.12). s:greaterThan(2.6):ifTrue({ s := 2.6 }). s }.

explode := { px, py | booms:add(boom:make(px, py)). boomTone:play }.

; A missile that got through: its target, and a burst on the ground.
arrive := { m |
    m:target:kind:equals('city):and({ m:target:alive }):ifTrue({ m:target:alive := false. cityTone:play }).
    m:target:kind:equals('base):ifTrue({ m:target:missiles := #0 }).
    explode:value(m:x, m:y) }.

fire := { which | | b |
    b := bases:at(which).
    state:equals('wave):and({ b:missiles:greaterThan(#0) }):ifTrue({
        b:missiles := b:missiles:dec.
        abms:add(abm:make(b, aimX:asFloat, aimY:asFloat)).
        fireTone:play }) }.

earn := { points |
    score := @expr(score + points * mult).
    score:greaterOrEqual(nextBonus):ifTrue({
        bonusCities := bonusCities:inc. nextBonus := @expr(nextBonus + #10000). bonusTone:play }) }.

; A wave: the count of missiles, in flights; the flyers and smart bombs it
; brings; the bases filled; the multiplier and the colours.
startWave := {
    wave := wave:inc.
    mult := @expr((wave - #1) / #2 + #1). mult:greaterThan(#6):ifTrue({ mult := #6 }).
    palette := @expr((wave - #1) / #2):mod(#5):inc.
    toLaunch := @expr(#12 + (wave - #1):mod(#4) * #3 + (wave - #1) / #4 * #2).
    toLaunch:greaterThan(#30):ifTrue({ toLaunch := #30 }).
    launchIn := #30.
    flyersLeft := wave:greaterThan(#1):ifElse({ @expr(#1 + (wave - #2) / #3) }, { #0 }).
    flyersLeft:greaterThan(#3):ifTrue({ flyersLeft := #3 }).
    flyerIn := @expr(#300 + rng:upTo(#300)).
    smartsLeft := wave:greaterThan(#4):ifElse({ @expr((wave - #2) / #3) }, { #0 }).
    smartsLeft:greaterThan(#4):ifTrue({ smartsLeft := #4 }).
    smartIn := @expr(#200 + rng:upTo(#400)).
    bases:do({ b | b:missiles := missilesABase }).
    icbms := []. abms := []. booms := []. flyers := []. smarts := [].
    state := 'wave }.

; A flight: a few missiles from along the top, one in three born to split.
launchFlight := { | n, m |
    n := @expr(#2 + rng:upTo(#3)).
    n:greaterThan(toLaunch):ifTrue({ n := toLaunch }).
    n:repeat({
        m := icbm:make(@expr(10.0 + rng:fraction * (fw - 20.0)), 0.0, aTarget:value, icbmSpeed:value).
        rng:upTo(#3):equals(#1):ifTrue({
            m:splitAt := @expr(60.0 + rng:fraction * 180.0). m:splitsInto := rng:upTo(#2) }).
        icbms:add(m) }).
    toLaunch := @expr(toLaunch - n).
    launchIn := @expr(#150 - wave * #6 + rng:upTo(#60)).
    launchIn:lessThan(#40):ifTrue({ launchIn := #40 }) }.

; Everything a disc reaches dies, and a missile that dies explodes, which
; is the chain.
reap := {
    booms:select({ b | true }):do({ b |
        icbms:do({ m | m:alive:and({ b:reaches(m:x, m:y) }):ifTrue({
            m:alive := false. earn:value(#25). explode:value(m:x, m:y) }) }).
        flyers:do({ f | f:alive:and({ b:reaches(f:x, f:y) }):ifTrue({
            f:alive := false. earn:value(#100). explode:value(f:x, f:y) }) }).
        smarts:do({ s | s:alive:and({ b:reaches(s:x, s:y) }):ifTrue({
            s:alive := false. earn:value(#125). explode:value(s:x, s:y) }) }) }) }.

waveDone := {
    toLaunch:equals(#0):and({ flyersLeft:equals(#0) }):and({ smartsLeft:equals(#0) })
        :and({ icbms:size:equals(#0) }):and({ abms:size:equals(#0) })
        :and({ booms:size:equals(#0) }):and({ flyers:size:equals(#0) }):and({ smarts:size:equals(#0) }) }.

; The count at the end of a wave: the missiles left, five each; the cities
; standing, a hundred each; a city rebuilt if one was earned; then on, or
; THE END.
startCount := {
    state := 'counting. countStep := #1. countIn := #40.
    countBase := #1. countCity := #1. countMissiles := #0. countCitiesUp := #0 }.
count := {
    countIn := countIn:dec.
    countIn:lessOrEqual(#0):ifTrue({
        countStep:equals(#1):ifTrue({
            { countBase:lessOrEqual(#3):and({ bases:at(countBase):missiles:equals(#0) }) }:whileTrue({
                countBase := countBase:inc }).
            countBase:lessOrEqual(#3):ifElse(
                { bases:at(countBase):missiles := bases:at(countBase):missiles:dec.
                  countMissiles := countMissiles:inc. earn:value(#5). tickTone:play. countIn := #4 },
                { countStep := #2. countIn := #30 }) }).
        countStep:equals(#2):ifTrue({
            { countCity:lessOrEqual(#6):and({ cities:at(countCity):alive:not }) }:whileTrue({
                countCity := countCity:inc }).
            countCity:lessOrEqual(#6):ifElse(
                { countCity := countCity:inc. countCitiesUp := countCitiesUp:inc.
                  earn:value(#100). tickTone:play. countIn := #10 },
                { countStep := #3. countIn := #30 }) }).
        countStep:equals(#3):ifTrue({
            bonusCities:greaterThan(#0):and({ cities:select({ c | c:alive:not }):size:greaterThan(#0) }):ifTrue({
                cities:select({ c | c:alive:not }):at(rng:upTo(cities:select({ c | c:alive:not }):size)):alive := true.
                bonusCities := bonusCities:dec. countCitiesUp := countCitiesUp:inc. bonusTone:play }).
            countStep := #4. countIn := #90 }).
        countStep:equals(#4):ifTrue({
            cities:select({ c | c:alive }):size:equals(#0):ifElse(
                { state := 'end. countIn := #300. endTone:play },
                { startWave:value }) }) }) }.

newGame := {
    score := #0. wave := #0. bonusCities := #0. nextBonus := #10000.
    cities:do({ c | c:alive := true }).
    startWave:value }.

; THE END, in cells three times the font's, from the engine's own rows.
bigCell := @expr(font:cell * #3).
bigGlyphs := dictionary:new.
["T", "H", "E", "N", "D"]:do({ ch | bigGlyphs:atPut(ch, sprite:make(font:letters:at(ch), bigCell)) }).
theEnd := { | left |
    left := #77.
    ["T", "H", "E", " ", "E", "N", "D"]:do({ ch |
        ch:equals(" "):ifFalse({ bigGlyphs:at(ch):paint(left, #180) }).
        left := @expr(left + #4 * bigCell) }) }.

; ---------------------------------------------------------------------------

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('mouseMove):ifTrue({ aimX := event:x. aimY := event:y }).
        event:kind:equals('mouseDown):ifTrue({
            @expr(event:button >= #1 & event:button <= #3):ifTrue({ fire:value(event:button) }) }).
        event:kind:equals('keyDown):and({ event:repeat:equals(#0) }):ifTrue({
            i := fireKeys:indexOf(event:key).
            i:notNil:ifTrue({ fire:value(i) }).
            event:key:equals("Space"):and({ state:equals('attract):or({ state:equals('end) }) }):ifTrue({
                newGame:value }) }) }).
    aimY:greaterThan(@expr(ground - #40)):ifTrue({ aimY := @expr(ground - #40) }).
    aimY:lessThan(#10):ifTrue({ aimY := #10 }).

    ; -- the pilot

    state:equals('wave):ifTrue({
        ; -- what the wave sends
        toLaunch:greaterThan(#0):ifTrue({
            launchIn := launchIn:dec.
            launchIn:lessOrEqual(#0):ifTrue({ launchFlight:value }) }).
        flyersLeft:greaterThan(#0):ifTrue({
            flyerIn := flyerIn:dec.
            flyerIn:lessOrEqual(#0):ifTrue({
                flyers:add(flyer:make(rng:upTo(#2):equals(#1))).
                flyersLeft := flyersLeft:dec. flyerIn := @expr(#400 + rng:upTo(#400)) }) }).
        smartsLeft:greaterThan(#0):ifTrue({
            smartIn := smartIn:dec.
            smartIn:lessOrEqual(#0):ifTrue({
                smarts:add(smart:make(aTarget:value, @expr(icbmSpeed:value * 0.7))).
                smartsLeft := smartsLeft:dec. smartIn := @expr(#300 + rng:upTo(#400)) }) }).

        ; -- everything moves, then the discs take what they reach
        icbms:select({ m | true }):do({ m | m:alive:ifTrue({ m:step }) }).
        abms:do({ m | m:step }).
        flyers:do({ f | f:step }).
        smarts:do({ s | s:alive:ifTrue({ s:step }) }).
        booms:do({ b | b:step }).
        reap:value.
        icbms := icbms:select({ m | m:alive }).
        abms := abms:select({ m | m:alive }).
        flyers := flyers:select({ f | f:alive }).
        smarts := smarts:select({ s | s:alive }).
        booms := booms:select({ b | b:alive }).
        waveDone:value:ifTrue({ startCount:value }) }).
    state:equals('counting):ifTrue({ count:value }).
    state:equals('end):ifTrue({
        countIn := countIn:dec.
        countIn:equals(#0):ifTrue({ state := 'attract }) }).

    ; -- one whole frame, then show it
    sky := palettes:at(palette):at(#1).
    sdl:clear(screen, sky:at(#1), sky:at(#2), sky:at(#3)).
    tint:value(#2).
    sdl:fill(screen, #0, ground, width, @expr(height - ground)).
    cities:do({ c | c:paint }).
    bases:do({ b | b:paint }).
    tint:value(#3).
    icbms:do({ m | m:paint }).
    smarts:do({ s | s:paint }).
    sdl:colour(screen, #248, #248, #248).
    flyers:do({ f | f:paint }).
    tint:value(#4).
    abms:do({ m | m:paint }).
    booms:do({ b | b:paint }).
    state:equals('wave):ifTrue({
        tint:value(#4).
        sdl:line(screen, @expr(aimX - #6), aimY, @expr(aimX + #6), aimY).
        sdl:line(screen, aimX, @expr(aimY - #6), aimX, @expr(aimY + #6)) }).
    sdl:colour(screen, #248, #248, #248).
    state:equals('attract):ifFalse({ font:number(score, #400, #10) }).
    state:equals('counting):ifTrue({
        font:word("BONUS POINTS", #176, #120).
        font:number(mult, #300, #160). font:word("X", #316, #160).
        countStep:greaterOrEqual(#1):ifTrue({
            font:number(@expr(countMissiles * #5 * mult), #260, #210).
            i := #0.
            { i:lessThan(countMissiles) }:whileTrue({
                sdl:fill(screen, @expr(#280 + i * #7), #212, #3, #8). i := i:inc }) }).
        countStep:greaterOrEqual(#2):ifTrue({
            font:number(@expr(countCitiesUp * #100 * mult), #260, #260).
            i := #0.
            { i:lessThan(countCitiesUp) }:whileTrue({
                citySprite:paint(@expr(#280 + i * #32), #256). i := i:inc }) }) }).
    state:equals('end):ifTrue({ tint:value(#3). theEnd:value }).

    engine:show }).

"final score {}":fill([score]):display.
