; kit.sol -- the ball-and-paddle kit, over the engine.
;
;     @include "kit.sol".
;
; What Pong and Breakout share that is not the engine: a ball that bounces
; off a wall, and a paddle that sets the angle by where the ball meets it.
; Asteroids would want neither, which is why this is a second file and not
; the bottom of the first. Everything here is a method on `ball` or `rect`.

@include "engine.sol".

; A wall. The ball is put flush against it and the component toward it is
; turned; the caller says which edge, so the same message serves all four.
ball:bounceX := { at | self:putX(at). self:vx := self:vx:negated }.
ball:bounceY := { at | self:putY(at). self:vy := self:vy:negated }.

; Where a ball meets a paddle, along the paddle: -1.0 at one end, 1.0 at
; the other, 0.0 dead centre. Clamped, since a ball can catch a corner.
rect:offsetX := { box | | o |
    o := @expr(((box:x + box:w / #2) - (self:x + self:w / #2)):asFloat
               / (self:w / #2):asFloat).
    o:greaterThan(1.0):ifTrue({ o := 1.0 }).
    o:lessThan(-1.0):ifTrue({ o := -1.0 }).
    o }.
rect:offsetY := { box | | o |
    o := @expr(((box:y + box:h / #2) - (self:y + self:h / #2)):asFloat
               / (self:h / #2):asFloat).
    o:greaterThan(1.0):ifTrue({ o := 1.0 }).
    o:lessThan(-1.0):ifTrue({ o := -1.0 }).
    o }.

; The angle from the offset. Dead centre sends the ball straight off the
; paddle, an edge sends it off at about sixty degrees, and the result has
; the speed given. `aimX` is for a paddle the ball meets travelling in x, a
; Pong paddle, and sets the other component from the offset; `aimY` is the
; same for a Breakout paddle. `direction` is 1.0 or -1.0, the way the ball
; leaves.
ball:aimX := { offset, speed, direction |
    self:vy := @expr(offset * speed * 0.85).
    self:vx := @expr(direction * sqrt(speed * speed - self:vy * self:vy)) }.
ball:aimY := { offset, speed, direction |
    self:vx := @expr(offset * speed * 0.85).
    self:vy := @expr(direction * sqrt(speed * speed - self:vx * self:vx)) }.
