; spacewar.sol -- the fifth game, and the second one drawn with lines.
;
;     solvm --extension=build/sdl.so examples/spacewar.sob
;
;   A / D          the needle turns        Left / Right   the wedge turns
;   W              thrust                  Up             thrust
;   S              torpedo                 Down           torpedo
;   Q              hyperspace              Return         hyperspace
;   C              hand the wedge to the machine, or take it back
;   Space          start a round; after a match, start another
;   Escape         quit
;
; The 1962 rules. A star in the middle whose gravity bends both ships and
; kills one that touches it; torpedoes fly straight, as they did on the
; PDP-1. Each ship has a tank of fuel and thirty-one torpedoes a round,
; shown as two bars. Hyperspace takes a ship off the screen for a moment
; and puts it back somewhere else, with a chance of not coming back that
; rises each time it is used. The screen wraps. A round ends when a ship
; dies, both dying is nobody's point, and the match is first to five. The
; machine flies the wedge until C.
;
; **What was predicted before this was written.** That `thing` and `draw`
; would be wanted here exactly as Asteroids wrote them, a float position
; with a radius that wraps and a shape as unit points drawn as lines, and
; are copied in rather than shared, so that the reading of five can move
; them by the two-game rule rather than this file reaching into another.
; (It did: they are the engine's now, with `mote` and with `craft`, which
; is what this file's ship and Asteroids' had in common. This file keeps
; the star, the pull, the torpedo, the two ships' rules and the pilot.)
; That gravity is a force and the first one, a few lines on the thing;
; that the two bars are `fill`s and the star is four lines; and that the
; binding is asked for nothing, again.
;
; The tones are pitches chosen for this file; the PDP-1 had no speaker.

@include "engine.sol".

engine:open("spacewar", #640, #480).


; -- the ships
turnRate  := 0.07.
thrustAt  := 0.06.
topSpeed  := 5.0.
fuelFull  := #900.                   ; frames of thrust
torpsFull := #31.
torpSpeed := 6.0.
torpLife  := #120.
fireEvery := #10.
shipRadius := 8.0.
winningScore := #5.

; -- the star
gravity := 150.0.                    ; acceleration is gravity / distance^2
starRadius := 14.0.
nearest := 20.0.                     ; the pull is capped here

; -- the sounds
fireTone   := tone:make(#800, #30).
bangTone   := tone:make(#90, #250).
thrustTone := tone:make(#55, #40).
hyperTone  := tone:make(#300, #60).
roundTone  := tone:make(#500, #120).

; -- the game
state := 'waiting.                   ; 'waiting  'playing  'between  'over
betweenIn := #0.
debris := []. torps := [].
i := #0.
leftScore := #0. rightScore := #0.

; ---------------------------------------------------------------------------
; The shapes, as unit points drawn in order and closed.

needleShape := [[1.0, 0.0], [-0.2, 0.25], [-1.0, 0.15], [-1.0, -0.15], [-0.2, -0.25]].
wedgeShape  := [[1.0, 0.0], [-0.8, 0.7], [-0.4, 0.0], [-0.8, -0.7]].

; ---------------------------------------------------------------------------
; The star is a thing that does not move, so that `within` and `touches`
; work against it.
star := thing:new.
star:x := @expr(fw / 2.0). star:y := @expr(fh / 2.0). star:r := starRadius.

; Gravity: toward the star, as one over the square of the distance, capped
; close in so that a near miss is a slingshot rather than an explosion of
; arithmetic. A method on the engine's `thing`, added here, which claims no
; name; it is this game's until a second game has a force.
thing:pull := { | dx, dy, d, a |
    dx := @expr(star:x - self:x). dy := @expr(star:y - self:y).
    d := @expr(sqrt(dx * dx + dy * dy)).
    d:lessThan(nearest):ifTrue({ d := nearest }).
    a := @expr(gravity / (d * d * d)).
    self:vx := @expr(self:vx + dx * a). self:vy := @expr(self:vy + dy * a) }.

; -- a torpedo
torp := thing:new.
torp:life := #0. torp:owner := nil.
torp:make := { from | | t |
    t := self:new. t:owner := from. t:life := torpLife.
    t:x := @expr(from:x + from:heading:cos * 14.0).
    t:y := @expr(from:y + from:heading:sin * 14.0).
    t:aim(from:heading, torpSpeed).
    t:vx := @expr(t:vx + from:vx). t:vy := @expr(t:vy + from:vy).
    t }.
torp:step := { self:via(thing):step. self:life := self:life:dec.
    self:life:equals(#0):ifTrue({ self:alive := false }) }.
torp:paint := { sdl:fill(screen, self:x:truncated, self:y:truncated, #2, #2) }.

; ---------------------------------------------------------------------------
; A ship: a craft with a tank, a rack of torpedoes, a set of keys, and a
; mode. Two of them, and they are reset rather than remade.

ship := craft:new.
ship:shape := nil. ship:mode := 'dead.                          ; 'alive 'hyper 'dead
ship:fuel := #0. ship:rack := #0. ship:fireIn := #0.
ship:hyperIn := #0. ship:hyperUses := #0.
ship:leftKey := "". ship:rightKey := "". ship:thrustKey := "".
ship:homeX := 0.0. ship:homeY := 0.0. ship:homeHeading := 0.0.
ship:thrusting := false. ship:machine := false.
ship:make := { shape, homeX, homeY, homeHeading, left, right, thrust | | s |
    s := self:new. s:shape := shape. s:r := shipRadius.
    s:homeX := homeX. s:homeY := homeY. s:homeHeading := homeHeading.
    s:leftKey := left. s:rightKey := right. s:thrustKey := thrust.
    s }.
ship:reset := {
    self:x := self:homeX. self:y := self:homeY. self:heading := self:homeHeading.
    self:vx := 0.0. self:vy := 0.0.
    self:fuel := fuelFull. self:rack := torpsFull.
    self:fireIn := #0. self:hyperIn := #0. self:hyperUses := #0.
    self:mode := 'alive }.
ship:thrust := {
    self:fuel:greaterThan(#0):ifTrue({
        self:fuel := self:fuel:dec. self:thrusting := true.
        self:burn(thrustAt, topSpeed).
        thrustTone:hum }) }.
ship:fire := {
    self:mode:equals('alive):and({ self:rack:greaterThan(#0) }):and({
        self:fireIn:equals(#0) }):ifTrue({
        self:rack := self:rack:dec. self:fireIn := fireEvery.
        torps:add(torp:make(self)).
        fireTone:play }) }.
ship:hyperspace := {
    self:mode:equals('alive):ifTrue({
        self:mode := 'hyper. self:hyperIn := #60.
        self:hyperUses := self:hyperUses:inc.
        hyperTone:play }) }.
ship:die := {
    self:mode := 'dead.
    i := #0.
    { i:lessThan(#10) }:whileTrue({ debris:add(mote:make(self:x, self:y, true, #60)). i := i:inc }).
    bangTone:play }.
ship:paint := { self:via(craft):paint(self:shape, 12.0, self:thrusting) }.

; One frame of a ship: the keys, the pull, the move, and the timers.
ship:fly := {
    self:thrusting := false.
    self:mode:equals('alive):ifTrue({
        self:machine:ifFalse({
            keys:down(self:leftKey):ifTrue({ self:turn(turnRate:negated) }).
            keys:down(self:rightKey):ifTrue({ self:turn(turnRate) }).
            keys:down(self:thrustKey):ifTrue({ self:thrust }) }).
        self:pull. self:step.
        self:fireIn:greaterThan(#0):ifTrue({ self:fireIn := self:fireIn:dec }) }).
    self:mode:equals('hyper):ifTrue({
        self:hyperIn := self:hyperIn:dec.
        self:hyperIn:equals(#0):ifTrue({
            self:x := @expr(rng:fraction * fw). self:y := @expr(rng:fraction * fh).
            self:vx := 0.0. self:vy := 0.0.
            self:mode := 'alive.
            rng:upTo(#8):lessOrEqual(self:hyperUses):ifTrue({ self:die }) }) }) }.

needle := ship:make(needleShape, @expr(fw * 0.2), @expr(fh * 0.2), 0.0, "A", "D", "W").
wedge  := ship:make(wedgeShape,  @expr(fw * 0.8), @expr(fh * 0.8), 3.141592653589793,
                    "Left", "Right", "Up").
wedge:machine := true.

; The machine flies the wedge. Three rules, in order of urgency. Falling
; toward the star, close and with the velocity pointed in, it turns
; against its velocity and burns, which is how a pilot gets out of a well.
; Otherwise near the star it points away and burns. Otherwise it hunts:
; turns toward the needle, burns when lined up and not already quick,
; fires when lined up and in range. It never uses hyperspace, so a person
; who does has an edge.
machineFly := { | dx, dy, dn, ds, inward, want, diff, mode |
    wedge:mode:equals('alive):ifTrue({
        dx := @expr(wedge:x - star:x). dy := @expr(wedge:y - star:y).
        ds := @expr(sqrt(dx * dx + dy * dy)).
        ds:lessThan(1.0):ifTrue({ ds := 1.0 }).
        inward := @expr(-(wedge:vx * dx + wedge:vy * dy) / ds).
        mode := 'hunt.
        ds:lessThan(120.0):ifTrue({ mode := 'away }).
        ds:lessThan(240.0):and({ inward:greaterThan(0.8) }):ifTrue({ mode := 'brake }).
        mode:equals('brake):ifTrue({ want := float:atan2(wedge:vy:negated, wedge:vx:negated) }).
        mode:equals('away):ifTrue({ want := float:atan2(dy, dx) }).
        mode:equals('hunt):ifTrue({
            want := float:atan2(@expr(needle:y - wedge:y), @expr(needle:x - wedge:x)) }).
        diff := @expr(want - wedge:heading).
        { diff:greaterThan(3.141592653589793) }:whileTrue({ diff := @expr(diff - tau) }).
        { diff:lessThan(-3.141592653589793) }:whileTrue({ diff := @expr(diff + tau) }).
        diff:greaterThan(0.05):ifTrue({ wedge:turn(turnRate) }).
        diff:lessThan(-0.05):ifTrue({ wedge:turn(turnRate:negated) }).
        mode:equals('hunt):ifElse(
            { diff:abs:lessThan(0.3):and({ wedge:speed:lessThan(1.5) }):ifTrue({ wedge:thrust }).
              diff:abs:lessThan(0.12):and({ wedge:within(needle, 320.0) }):ifTrue({ wedge:fire }) },
            { diff:abs:lessThan(0.5):ifTrue({ wedge:thrust }) }) }) }.

; ---------------------------------------------------------------------------
; Rounds

startRound := {
    needle:reset. wedge:reset.
    torps := []. debris := [].
    state := 'playing. roundTone:play }.

; A round ends the frame a ship dies; who is left standing scores.
endRound := {
    needle:mode:equals('dead):and({ wedge:mode:equals('dead) }):ifFalse({
        needle:mode:equals('dead):ifTrue({ rightScore := rightScore:inc }).
        wedge:mode:equals('dead):ifTrue({ leftScore := leftScore:inc }) }).
    leftScore:greaterOrEqual(winningScore):or({ rightScore:greaterOrEqual(winningScore) }):ifElse(
        { state := 'over },
        { state := 'between. betweenIn := #120 }) }.

; A bar along the bottom, `have` of `full` in `span` pixels.
bar := { left, top, span, have, full |
    sdl:fill(screen, left, top, @expr(span * have / full), #4) }.

; ---------------------------------------------------------------------------

needle:reset. wedge:reset.           ; on the screen before the first round

{ running }:whileTrue({
    engine:drain({ event |
        event:kind:equals('keyDown):ifTrue({
            event:key:equals("C"):ifTrue({ wedge:machine := wedge:machine:not }).
            state:equals('playing):ifTrue({
                event:key:equals("S"):ifTrue({ needle:fire }).
                event:key:equals("Q"):ifTrue({ needle:hyperspace }).
                wedge:machine:ifFalse({
                    event:key:equals("Down"):ifTrue({ wedge:fire }).
                    event:key:equals("Return"):ifTrue({ wedge:hyperspace }) }) }).
            event:key:equals("Space"):ifTrue({
                state:equals('waiting):ifTrue({ startRound:value }).
                state:equals('over):ifTrue({
                    leftScore := #0. rightScore := #0. startRound:value }) }) }) }).

    state:equals('between):ifTrue({
        betweenIn := betweenIn:dec.
        betweenIn:equals(#0):ifTrue({ startRound:value }) }).

    state:equals('playing):ifTrue({
        ; -- the ships
        wedge:machine:ifTrue({ machineFly:value }).
        needle:fly. wedge:fly.

        ; -- the torpedoes, straight, and gone into the star
        torps:do({ t | t:step. t:touches(star):ifTrue({ t:alive := false }) }).

        ; -- what hits what
        [needle, wedge]:do({ s |
            s:mode:equals('alive):ifTrue({
                s:touches(star):ifTrue({ s:die }).
                torps:do({ t |
                    t:alive:and({ s:mode:equals('alive) }):and({ t:touches(s) }):ifTrue({
                        t:alive := false. s:die }) }) }) }).
        needle:mode:equals('alive):and({ wedge:mode:equals('alive) }):and({
            needle:touches(wedge) }):ifTrue({ needle:die. wedge:die }).
        torps := torps:select({ t | t:alive }).

        needle:mode:equals('dead):or({ wedge:mode:equals('dead) }):ifTrue({ endRound:value }) }).

    debris:do({ m | m:step }).
    debris := debris:select({ m | m:alive }).

    ; -- one whole frame, then show it
    sdl:clear(screen, #0, #0, #0).
    sdl:colour(screen, #230, #230, #230).

    ; the star, four lines that flicker
    i := @expr(#3 + frames:mod(#3)).
    sdl:line(screen, @expr(star:x:truncated - i), star:y:truncated, @expr(star:x:truncated + i), star:y:truncated).
    sdl:line(screen, star:x:truncated, @expr(star:y:truncated - i), star:x:truncated, @expr(star:y:truncated + i)).
    sdl:line(screen, @expr(star:x:truncated - #2), @expr(star:y:truncated - #2), @expr(star:x:truncated + #2), @expr(star:y:truncated + #2)).
    sdl:line(screen, @expr(star:x:truncated - #2), @expr(star:y:truncated + #2), @expr(star:x:truncated + #2), @expr(star:y:truncated - #2)).

    needle:mode:equals('alive):ifTrue({ needle:paint }).
    wedge:machine:ifTrue({ sdl:colour(screen, #160, #180, #220) }).
    wedge:mode:equals('alive):ifTrue({ wedge:paint }).
    sdl:colour(screen, #230, #230, #230).
    torps:do({ t | t:paint }).
    debris:do({ m | m:paint }).

    font:number(leftScore, #60, #14).
    font:number(rightScore, @expr(width - #40), #14).
    bar:value(#20, #464, #120, needle:fuel, fuelFull).
    bar:value(#20, #472, #120, needle:rack, torpsFull).
    bar:value(#500, #464, #120, wedge:fuel, fuelFull).
    bar:value(#500, #472, #120, wedge:rack, torpsFull).

    engine:show }).

"final score {} - {}":fill([leftScore, rightScore]):display.
