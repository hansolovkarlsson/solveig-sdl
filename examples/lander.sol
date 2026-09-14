; lander.sol -- the sixth game, and the first that is not a fight.
;
;     solvm --extension=build/sdl.so examples/lander.sob
;
;   Left / Right   turn; A / D do the same
;   Up / Down      the throttle, 0 to 100; W / S do the same
;   Space          abort: full burn and level, at a cost of fuel;
;                  when no game is on, start one
;   Escape         quit
;
; The shape of the 1979 rules. A line terrain, new each time, with three
; pads marked 2, 3 and 5. One tank of fuel for the whole game, spent by the
; throttle; a landing is on a pad, upright, slow, and scores fifty times
; the pad, twenty-five if it is hard, and a soft one earns fuel. Anything
; else is a crash, which scores nothing and costs a new terrain. The game
; ends when the tank is dry and the craft is down. Altitude, the two speeds
; and the fuel are numbers, and this is the first game that wanted words:
; five of them, in the same 3x5 cells as the digits. No zoom.
;
; **What was predicted before this was written.** That `craft` would carry
; its third game with `burn` taking a throttle rather than a key; that
; gravity would be a second force after Spacewar's, but a field rather than
; a well, so `pull` would not fit and a force is what the two have in
; common; that the thing must not wrap in y, so `wrap` would be overridden
; for the first time; that the first collision against a line rather than a
; radius is a few lines of the game; that the words are sprites, and so the
; font is the special case again; and that the binding is asked for nothing.
; (The words are the engine's now: the reading of seven moved the alphabet
; in beside the digits when Tetris wanted words too, and `font:word` paints
; one. This file keeps the numbers it names and the bar for a minus.)
;
; The tones are pitches chosen for this file.

@include "engine.sol".

engine:open("lander", #640, #480).

up := -1.5707963267948966.           ; nose up, since y runs down the screen

; -- the craft
turnRate  := 0.03.
gravity   := 0.012.                  ; pixels a frame a frame, down
maxBurn   := 0.045.                  ; at full throttle
fuelFull  := 1500.0.
burnRate  := 0.5.                    ; fuel a frame at full throttle
abortCost := 60.0.
entryVx   := 1.2.
scale     := 10.0.

; -- a landing
softVy := 0.5. hardVy := 1.2. maxVx := 0.6. maxTilt := 0.2.
softBonus := 100.0.                  ; fuel, for a soft landing

; -- the sounds
thrustTone := tone:make(#55, #40).
crashTone  := tone:make(#80, #400).
landTone   := tone:make(#600, #150).
lowTone    := tone:make(#900, #40).

; -- the game
state := 'attract.                   ; 'attract  'flying  'down  'over
score := #0.
downIn := #0. gained := #0. crashed := false.
debris := []. burning := false.
i := #0. j := #0.

; ---------------------------------------------------------------------------
; The shapes

bodyShape := [[0.6, 0.0], [0.3, 0.5], [-0.3, 0.5], [-0.6, 0.2], [-0.6, -0.2], [-0.3, -0.5], [0.3, -0.5]].
legShapes := [[[-0.5, 0.4], [-1.0, 0.8]], [[-0.5, -0.4], [-1.0, -0.8]]].
footShapes := [[[-1.0, 0.6], [-1.0, 1.0]], [[-1.0, -0.6], [-1.0, -1.0]]].

; A signed number: the digits, and a bar for a minus, right-aligned at `right`.
signed := { value, right, top |
    font:number(value:abs, right, top).
    value:lessThan(#0):ifTrue({
        sdl:fill(screen, @expr(right - #7 * font:cell), @expr(top + #2 * font:cell),
                 @expr(#3 * font:cell), font:cell) }) }.

; ---------------------------------------------------------------------------
; The terrain: points left to right, and three of its segments flat and
; marked. Random each time, so no landing is learnt by heart.

terrain := [].                       ; [x, y] pairs, x rising
pads := [].                          ; [x1, x2, y, multiplier]

makeTerrain := { | x, y, padsAt, padWidths, k |
    terrain := []. pads := [].
    padsAt := [@expr(#60 + rng:upTo(#120)), @expr(#260 + rng:upTo(#120)), @expr(#460 + rng:upTo(#100))].
    padWidths := [#56, #44, #32].
    x := #0. y := @expr(#320 + rng:upTo(#100)). k := #1.
    terrain:add([x, y]).
    { x:lessThan(width) }:whileTrue({
        k:lessOrEqual(#3):and({ x:greaterOrEqual(padsAt:at(k)) }):ifElse(
            { pads:add([x, @expr(x + padWidths:at(k)), y, [#2, #3, #5]:at(k)]).
              x := @expr(x + padWidths:at(k)). terrain:add([x, y]). k := k:inc },
            { x := @expr(x + #12 + rng:upTo(#18)).
              x:greaterThan(width):ifTrue({ x := width }).
              y := @expr(y + rng:between(#-40, #40)).
              y:lessThan(#260):ifTrue({ y := #260 }).
              y:greaterThan(#450):ifTrue({ y := #450 }).
              terrain:add([x, y]) }) }) }.

; The ground under a pixel column, by the segment it falls in.
groundAt := { px | | k, a, b, found |
    found := #460. k := #1.
    { k:lessThan(terrain:size) }:whileTrue({
        a := terrain:at(k). b := terrain:at(k:inc).
        @expr(px >= a:at(#1) & px <= b:at(#1)):ifTrue({
            found := @expr(a:at(#2) + (b:at(#2) - a:at(#2)) * (px - a:at(#1)) / (b:at(#1) - a:at(#1))).
            k := terrain:size }).
        k := k:inc }).
    found }.

; The pad a pixel column is over, or nil.
padAt := { px | | found |
    found := nil.
    pads:do({ p | @expr(px >= p:at(#1) & px <= p:at(#2)):ifTrue({ found := p }) }).
    found }.

drawTerrain := { | k, a, b |
    k := #1.
    { k:lessThan(terrain:size) }:whileTrue({
        a := terrain:at(k). b := terrain:at(k:inc).
        sdl:line(screen, a:at(#1), a:at(#2), b:at(#1), b:at(#2)).
        k := k:inc }).
    pads:do({ p |
        sdl:fill(screen, p:at(#1), @expr(p:at(#3) - #1), @expr(p:at(#2) - p:at(#1)), #3).
        font:number(p:at(#4), @expr((p:at(#1) + p:at(#2)) / #2 + font:cell), @expr(p:at(#3) + #8)) }) }.

; ---------------------------------------------------------------------------
; The craft: a craft with a throttle and a tank, that wraps sideways only.

lander := craft:new.
lander:r := 8.0. lander:heading := up.
lander:throttle := #0. lander:fuel := fuelFull. lander:abortIn := #0.
lander:wrap := {
    self:x:lessThan(@expr(-self:r)):ifTrue({ self:x := @expr(self:x + fw + 2.0 * self:r) }).
    self:x:greaterThan(@expr(fw + self:r)):ifTrue({ self:x := @expr(self:x - fw - 2.0 * self:r) }) }.
lander:enter := {
    self:x := 40.0. self:y := 60.0.
    self:vx := entryVx. self:vy := 0.0.
    self:heading := up. self:throttle := #0. self:abortIn := #0 }.

; A frame of flight: the throttle, or the abort; gravity; the move.
lander:fly := { | burning |
    self:abortIn:greaterThan(#0):ifTrue({
        self:abortIn := self:abortIn:dec.
        self:throttle := #100.
        self:heading:greaterThan(@expr(up + 0.05)):ifTrue({ self:turn(-0.1) }).
        self:heading:lessThan(@expr(up - 0.05)):ifTrue({ self:turn(0.1) }) }).
    burning := self:throttle:greaterThan(#0):and({ self:fuel:greaterThan(0.0) }).
    burning:ifTrue({
        self:burn(@expr(maxBurn * self:throttle:asFloat / 100.0), 100.0).
        self:fuel := @expr(self:fuel - burnRate * self:throttle:asFloat / 100.0).
        self:fuel:lessThan(0.0):ifTrue({ self:fuel := 0.0 }).
        thrustTone:hum }).
    self:vy := @expr(self:vy + gravity).
    self:step.
    burning }.

; A foot, in pixels: the end of a leg turned by the heading.
lander:foot := { which | | p, c, s |
    p := footShapes:at(which):at(#2).
    c := self:heading:cos. s := self:heading:sin.
    [@expr(self:x + (p:at(#1) * c - p:at(#2) * s) * scale):truncated,
     @expr(self:y + (p:at(#1) * s + p:at(#2) * c) * scale):truncated] }.

lander:paint := { burning |
    self:via(craft):paint(bodyShape, scale, burning).
    legShapes:do({ leg | draw:value(leg, self:x, self:y, self:heading, scale) }).
    footShapes:do({ ft | draw:value(ft, self:x, self:y, self:heading, scale) }) }.

; ---------------------------------------------------------------------------
; Touching down. Both feet on the ground, on one pad, upright and slow is
; a landing; one foot on anything else is a crash.

touchDown := { | left, right, pad, tilt |
    left := lander:foot(#1). right := lander:foot(#2).
    left:at(#2):greaterOrEqual(groundAt:value(left:at(#1))):or({
        right:at(#2):greaterOrEqual(groundAt:value(right:at(#1))) }):ifTrue({
        pad := padAt:value(left:at(#1)).
        tilt := @expr(lander:heading - up).
        { tilt:greaterThan(3.141592653589793) }:whileTrue({ tilt := @expr(tilt - tau) }).
        { tilt:lessThan(-3.141592653589793) }:whileTrue({ tilt := @expr(tilt + tau) }).
        tilt := tilt:abs.
        pad:notNil:and({ padAt:value(right:at(#1)):equals(pad) }):and({
            tilt:lessThan(maxTilt) }):and({ lander:vy:abs:lessThan(hardVy) }):and({
            lander:vx:abs:lessThan(maxVx) }):ifElse(
            { lander:vy:abs:lessThan(softVy):ifElse(
                { gained := @expr(#50 * pad:at(#4)). lander:fuel := @expr(lander:fuel + softBonus) },
                { gained := @expr(#25 * pad:at(#4)) }).
              score := @expr(score + gained). crashed := false.
              lander:vx := 0.0. lander:vy := 0.0. lander:throttle := #0.
              lander:y := @expr(pad:at(#3):asFloat - scale).
              landTone:play },
            { crashed := true. gained := #0.
              i := #0.
              { i:lessThan(#12) }:whileTrue({
                  debris:add(mote:make(lander:x, lander:y, true, #80)). i := i:inc }).
              crashTone:play }).
        state := 'down. downIn := #150 }) }.

newGame := {
    score := #0. lander:fuel := fuelFull.
    makeTerrain:value. lander:enter. debris := [].
    state := 'flying }.

; ---------------------------------------------------------------------------

makeTerrain:value. lander:enter.

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):and({ event:key:equals("Space") }):ifTrue({
            state:equals('flying):ifTrue({
                lander:abortIn:equals(#0):and({ lander:fuel:greaterThan(abortCost) }):ifTrue({
                    lander:abortIn := #45.
                    lander:fuel := @expr(lander:fuel - abortCost) }) }).
            state:equals('attract):or({ state:equals('over) }):ifTrue({ newGame:value }) }) }).

    burning := false.
    state:equals('flying):ifTrue({
        lander:abortIn:equals(#0):ifTrue({
            keys:any(["Left", "A"]):ifTrue({ lander:turn(turnRate:negated) }).
            keys:any(["Right", "D"]):ifTrue({ lander:turn(turnRate) }).
            keys:any(["Up", "W"]):ifTrue({ lander:throttle := @expr(lander:throttle + #2) }).
            keys:any(["Down", "S"]):ifTrue({ lander:throttle := @expr(lander:throttle - #2) }).
            lander:throttle:greaterThan(#100):ifTrue({ lander:throttle := #100 }).
            lander:throttle:lessThan(#0):ifTrue({ lander:throttle := #0 }) }).
        burning := lander:fly.
        lander:fuel:lessThan(200.0):and({ frames:mod(#30):equals(#0) }):ifTrue({ lowTone:hum }).
        touchDown:value }).

    ; -- down, on a pad or in pieces: a pause, then the next terrain, or the end
    state:equals('down):ifTrue({
        downIn := downIn:dec.
        downIn:equals(#0):ifTrue({
            lander:fuel:lessThan(1.0):ifElse(
                { state := 'over },
                { makeTerrain:value. lander:enter. state := 'flying }) }) }).

    debris:do({ m | m:step }).
    debris := debris:select({ m | m:alive }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #0, #0, #0).
    sdl:colour(screen, #230, #230, #230).
    drawTerrain:value.
    crashed:and({ state:equals('down) }):ifFalse({ lander:paint(burning) }).
    debris:do({ m | m:paint }).

    ; the numbers
    font:word("SCORE", #16, #12). font:number(score, #200, #12).
    font:word("FUEL", #16, #52).  font:number(lander:fuel:truncated, #200, #52).
    font:word("ALT", #400, #12).
    font:number(@expr(groundAt:value(lander:x:truncated) - lander:y:truncated - #10):abs, #600, #12).
    font:word("HS", #400, #52).   signed:value(@expr(lander:vx * 10.0):truncated, #600, #52).
    font:word("VS", #400, #92).   signed:value(@expr(lander:vy * 10.0):truncated, #600, #92).

    ; the throttle, as a bar up the left edge
    sdl:fill(screen, #16, @expr(#300 - #2 * lander:throttle), #8, @expr(#2 * lander:throttle)).
    sdl:line(screen, #14, #100, #14, #300). sdl:line(screen, #26, #100, #26, #300).

    ; what the landing was worth, while down
    state:equals('down):and({ crashed:not }):ifTrue({
        font:number(gained, @expr(lander:x:truncated + #20), @expr(lander:y:truncated - #40)) }).

    engine:show }).

"final score {}":fill([score]):display.
