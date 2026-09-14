# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Start here

`scratch/daily-standup.md` — written at the end of the previous working day to
be read at the start of the next: where the tree was left, what went in, and
what is outstanding. `scratch/` is gitignored and is not part of this
repository, so the file is absent on a fresh clone and on any day that was not
closed out. When it is absent, `git log` and the documents named below are the
way in.

## What this is

An SDL2 surface for Solveig, loaded at run time as a VM extension.

## Commands

`make` builds `build/sdl.so`; `make check` runs the examples;
`make clean`. Run one against a Solveig VM:

```sh
../Solveig/bin/solvm --extension=build/sdl.so examples/bounce.sob
```

## The records

**This repository keeps none.** It is an extension of
[Solveig](https://github.com/hansolovkarlsson/Solveig), and the journal,
roadmap, completed and changelog that cover it live in that repository. A
closeout here is a `README.md` update and a commit; anything worth recording
belongs next door.
