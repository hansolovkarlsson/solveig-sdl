/* sdl.c -- an SDL2 surface for Solveig, loaded at run time.
 *
 *     solvm --extension=build/sdl.so program.sob
 *
 * The second bundle written against Solveig's extension interface, and written
 * partly to find out what the first one had got away with. It needed no change
 * to the mechanism at all -- same `extend.h`, same ABI, same foreign cell, same
 * loader. What it did need is noted where it comes up.
 *
 * **This is deliberately not shaped like solveig-gtk**, and the difference is
 * not stylistic. GTK owns the loop and calls into the program; SDL hands the
 * program a frame and gets out of the way. So there is no `sdl:run` and no
 * callback: a program written against this owns its own loop, the way an SDL
 * program in C does.
 *
 *     { running } whileTrue({
 *         event := sdl:poll.
 *         ...
 *         sdl:clear(screen, #20, #20, #30).
 *         sdl:fill(screen, x, y, #40, #40).
 *         sdl:present(screen).
 *         sdl:wait(#16) }).
 *
 * That is worth stating because the temptation was to give SDL a `run(block)`
 * so that the two extensions would look alike. Solveig's own notes argue
 * against it: a back end that borrows another's vocabulary makes every later
 * back end emulate a toolkit it has nothing to do with. A Plan 9 `draw` binding
 * would be shaped like this one, not like the GTK one.
 *
 * **And so this extension uses no callbacks and needs no retain registry.**
 * That is the check on a decision made when the registry was built: it is a
 * service an extension may use, not the shape an extension takes. If it had
 * been the shape, this file would be fighting it.
 *
 * See Solveig's docs/extensions.md for the contract, and solum/extend.h for the
 * four rules. Rules 1 and 2 are on every page here; rule 3 does not arise
 * because nothing is held between calls; rule 4 does not arise because nothing
 * calls back into the language.
 */
#include <SDL.h>

#include "solum/extend.h"

/* A window and the renderer that draws into it, which are two SDL objects and
   one thing to a program. Wrapped together so that `sdl:window` answers
   something a program can draw on rather than two handles it must keep in step. */
typedef struct {
    SDL_Window   *window;
    SDL_Renderer *renderer;
} Screen;

#define SCREEN "sdl screen"

static bool started;

/* ---- the shapes every primitive starts with ------------------------------ */

/* Rule 1: arity is not checked for you. */
static bool args(SolVM *vm, const char *name, int argc, int wanted)
{
    if (argc == wanted) return true;
    sol_vm_runtime_error(vm, "'%s' takes %d argument%s, got %d",
                         name, wanted, wanted == 1 ? "" : "s", argc);
    return false;
}

/* Every drawing message takes integers, and a float is the mistake a program
   will actually make -- `x` from a physics step is a float, and `#` is what
   turns it into a coordinate. So the message says that rather than only
   refusing. It says "an integer" and not "a coordinate" because `wait` and
   `beep` check the same way and neither takes one. */
static bool ints(SolVM *vm, const char *name, SolValue *a, int from, int count)
{
    for (int i = from; i < from + count; i++) {
        if (SOL_IS_INT(a[i])) continue;
        sol_vm_runtime_error(vm,
            "'%s' expects integers, got %s -- an integer is written with '#', "
            "and a float becomes one with 'truncated'", name, sol_type_name(a[i]));
        return false;
    }
    return true;
}

static Screen *screen_of(SolVM *vm, const char *name, SolValue value)
{
    void *handle = sol_foreign_handle(value, SCREEN);
    if (handle == NULL) {
        sol_vm_runtime_error(vm, "'%s' expects a screen, got %s",
                             name, sol_type_name(value));
        return NULL;
    }
    return handle;
}

static bool ready(SolVM *vm, const char *name)
{
    if (started) return true;
    sol_vm_runtime_error(vm, "'%s' before sdl:start", name);
    return false;
}

/* ---- the screen ---------------------------------------------------------- */

/* Both SDL objects and the struct holding them. The collector calls this when
   the program lets go of the screen, and `sol_vm_free` calls it for one still
   held when the machine goes down -- including for a program a limit took away
   mid-frame, which is when a window left on screen would be most annoying. */
static void drop_screen(void *handle)
{
    Screen *screen = handle;
    if (screen->renderer) SDL_DestroyRenderer(screen->renderer);
    if (screen->window)   SDL_DestroyWindow(screen->window);
    free(screen);
}

static SolValue prim_start(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self; (void)a;
    if (!args(vm, "start", argc, 0)) return SOL_NIL_VAL;
    if (started) return SOL_BOOL_VAL(true);

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        sol_vm_runtime_error(vm, "sdl:start -- %s", SDL_GetError());
        return SOL_NIL_VAL;
    }
    started = true;
    return SOL_BOOL_VAL(true);
}

/* sdl:window("title", #width, #height) */
static SolValue prim_window(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self;
    if (!args(vm, "window", argc, 3)) return SOL_NIL_VAL;
    if (!ready(vm, "window")) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(a[0])) {
        sol_vm_runtime_error(vm, "'window' expects a title");
        return SOL_NIL_VAL;
    }
    if (!ints(vm, "window", a, 1, 2)) return SOL_NIL_VAL;

    Screen *screen = calloc(1, sizeof(Screen));
    if (screen == NULL) {
        sol_vm_runtime_error(vm, "sdl:window -- out of memory");
        return SOL_NIL_VAL;
    }

    screen->window = SDL_CreateWindow(SOL_AS_STRING(a[0])->chars,
                                      SDL_WINDOWPOS_CENTERED,
                                      SDL_WINDOWPOS_CENTERED,
                                      (int)SOL_AS_INT(a[1]),
                                      (int)SOL_AS_INT(a[2]),
                                      SDL_WINDOW_SHOWN);
    if (screen->window == NULL) {
        free(screen);
        sol_vm_runtime_error(vm, "sdl:window -- %s", SDL_GetError());
        return SOL_NIL_VAL;
    }

    screen->renderer = SDL_CreateRenderer(screen->window, -1,
                                          SDL_RENDERER_ACCELERATED);
    if (screen->renderer == NULL) {
        /* Software, so a machine with no acceleration draws rather than
           refusing -- which is what a headless CI run gets. */
        screen->renderer = SDL_CreateRenderer(screen->window, -1,
                                              SDL_RENDERER_SOFTWARE);
    }
    if (screen->renderer == NULL) {
        SDL_DestroyWindow(screen->window);
        free(screen);
        sol_vm_runtime_error(vm, "sdl:window -- %s", SDL_GetError());
        return SOL_NIL_VAL;
    }

    /* A window's pixels are the one thing here with a size worth declaring: a
       640x480 window is about 1.2MB of backing store, and `--memory` measuring
       the pointer instead would be measuring nothing. Approximate on purpose --
       the real figure is the driver's business -- and four bytes a pixel is the
       right order, which is what the number is for. */
    size_t footprint = (size_t)SOL_AS_INT(a[1]) * (size_t)SOL_AS_INT(a[2]) * 4;
    return SOL_FOREIGN_VAL(sol_foreign_new(vm, screen, drop_screen,
                                           SCREEN, footprint));
}

/* ---- drawing ------------------------------------------------------------- */

static SolValue prim_clear(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self;
    if (!args(vm, "clear", argc, 4)) return SOL_NIL_VAL;
    if (!ints(vm, "clear", a, 1, 3)) return SOL_NIL_VAL;

    Screen *screen = screen_of(vm, "clear", a[0]);
    if (screen == NULL) return SOL_NIL_VAL;

    SDL_SetRenderDrawColor(screen->renderer,
                           (Uint8)SOL_AS_INT(a[1]), (Uint8)SOL_AS_INT(a[2]),
                           (Uint8)SOL_AS_INT(a[3]), 255);
    SDL_RenderClear(screen->renderer);
    return a[0];
}

/* sdl:colour(screen, #r, #g, #b) -- what the next fill or line is drawn in. */
static SolValue prim_colour(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self;
    if (!args(vm, "colour", argc, 4)) return SOL_NIL_VAL;
    if (!ints(vm, "colour", a, 1, 3)) return SOL_NIL_VAL;

    Screen *screen = screen_of(vm, "colour", a[0]);
    if (screen == NULL) return SOL_NIL_VAL;

    SDL_SetRenderDrawColor(screen->renderer,
                           (Uint8)SOL_AS_INT(a[1]), (Uint8)SOL_AS_INT(a[2]),
                           (Uint8)SOL_AS_INT(a[3]), 255);
    return a[0];
}

/* sdl:fill(screen, #x, #y, #width, #height) */
static SolValue prim_fill(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self;
    if (!args(vm, "fill", argc, 5)) return SOL_NIL_VAL;
    if (!ints(vm, "fill", a, 1, 4)) return SOL_NIL_VAL;

    Screen *screen = screen_of(vm, "fill", a[0]);
    if (screen == NULL) return SOL_NIL_VAL;

    SDL_Rect rect = { (int)SOL_AS_INT(a[1]), (int)SOL_AS_INT(a[2]),
                      (int)SOL_AS_INT(a[3]), (int)SOL_AS_INT(a[4]) };
    SDL_RenderFillRect(screen->renderer, &rect);
    return a[0];
}

/* sdl:line(screen, #x1, #y1, #x2, #y2) */
static SolValue prim_line(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self;
    if (!args(vm, "line", argc, 5)) return SOL_NIL_VAL;
    if (!ints(vm, "line", a, 1, 4)) return SOL_NIL_VAL;

    Screen *screen = screen_of(vm, "line", a[0]);
    if (screen == NULL) return SOL_NIL_VAL;

    SDL_RenderDrawLine(screen->renderer,
                       (int)SOL_AS_INT(a[1]), (int)SOL_AS_INT(a[2]),
                       (int)SOL_AS_INT(a[3]), (int)SOL_AS_INT(a[4]));
    return a[0];
}

static SolValue prim_present(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self;
    if (!args(vm, "present", argc, 1)) return SOL_NIL_VAL;

    Screen *screen = screen_of(vm, "present", a[0]);
    if (screen == NULL) return SOL_NIL_VAL;

    SDL_RenderPresent(screen->renderer);
    return a[0];
}

/* ---- what happened ------------------------------------------------------- */

/* An event is an ordinary object with slots, so a program asks it questions the
   way it asks anything else -- `event:kind`, `event:key`, `event:x`.
 *
 * A dictionary would have done and is not reachable: `sol_dict_new` exists and
 * is not part of the interface an extension is promised, which is the one gap
 * this extension found in it. An object is the better answer here anyway, since
 * `everything is a message send` is the language's whole premise and
 * `event:at('kind)` would be a lookup pretending to be one. */
static SolValue event_object(SolVM *vm, const char *kind)
{
    SolObject *event = sol_object_new(vm, vm->object_class);
    sol_object_define(vm, event, "kind",
        SOL_SYMBOL_VAL(sol_symbol_intern(vm, kind, (int)strlen(kind))));
    return SOL_OBJ_VAL(event);
}

static void define_int(SolVM *vm, SolValue event, const char *name, int value)
{
    sol_object_define(vm, SOL_AS_OBJ(event), name, SOL_INT_VAL(value));
}

static void define_text(SolVM *vm, SolValue event, const char *name,
                        const char *text)
{
    sol_object_define(vm, SOL_AS_OBJ(event), name,
                      SOL_STRING_VAL(sol_string_new(vm, text, (int)strlen(text))));
}

/* sdl:poll -- the next event, or nil when there is none waiting.
 *
 * Answering nil rather than blocking is what lets a program own its loop: it
 * drains what has happened, draws a frame, and comes back. */
static SolValue prim_poll(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self; (void)a;
    if (!args(vm, "poll", argc, 0)) return SOL_NIL_VAL;
    if (!ready(vm, "poll")) return SOL_NIL_VAL;

    SDL_Event event;
    if (!SDL_PollEvent(&event)) return SOL_NIL_VAL;

    switch (event.type) {
    case SDL_QUIT:
        return event_object(vm, "quit");

    case SDL_KEYDOWN:
    case SDL_KEYUP: {
        SolValue answer = event_object(vm,
            event.type == SDL_KEYDOWN ? "keyDown" : "keyUp");
        /* Rule 3's window: `answer` is a cell held only in a C local, and the
           two calls below allocate. Rooted for as long as that is true. */
        sol_gc_push_temp(vm, (SolGCHeader *)SOL_AS_OBJ(answer));
        define_text(vm, answer, "key", SDL_GetKeyName(event.key.keysym.sym));
        define_int(vm, answer, "repeat", event.key.repeat);
        sol_gc_pop_temp(vm);
        return answer;
    }

    case SDL_MOUSEBUTTONDOWN:
    case SDL_MOUSEBUTTONUP: {
        SolValue answer = event_object(vm,
            event.type == SDL_MOUSEBUTTONDOWN ? "mouseDown" : "mouseUp");
        sol_gc_push_temp(vm, (SolGCHeader *)SOL_AS_OBJ(answer));
        define_int(vm, answer, "x", event.button.x);
        define_int(vm, answer, "y", event.button.y);
        define_int(vm, answer, "button", event.button.button);
        sol_gc_pop_temp(vm);
        return answer;
    }

    case SDL_MOUSEMOTION: {
        SolValue answer = event_object(vm, "mouseMove");
        sol_gc_push_temp(vm, (SolGCHeader *)SOL_AS_OBJ(answer));
        define_int(vm, answer, "x", event.motion.x);
        define_int(vm, answer, "y", event.motion.y);
        sol_gc_pop_temp(vm);
        return answer;
    }

    default:
        /* Everything else is an event this binding does not name yet. It is
           still an event, and a program draining the queue has to see
           *something* or the loop it wrote would spin -- so it gets a kind it
           can ignore rather than a nil that means "queue empty". */
        return event_object(vm, "other");
    }
}

/* ---- time ---------------------------------------------------------------- */

static SolValue prim_wait(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self;
    if (!args(vm, "wait", argc, 1)) return SOL_NIL_VAL;
    if (!ints(vm, "wait", a, 0, 1)) return SOL_NIL_VAL;
    if (SOL_AS_INT(a[0]) < 0) {
        sol_vm_runtime_error(vm, "'wait' wants a delay of 0 or more");
        return SOL_NIL_VAL;
    }
    SDL_Delay((Uint32)SOL_AS_INT(a[0]));
    return SOL_NIL_VAL;
}

/* Milliseconds since sdl:start. A frame loop wants elapsed time rather than a
   date, which is what `system:clock` gives. */
static SolValue prim_ticks(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self; (void)a;
    if (!args(vm, "ticks", argc, 0)) return SOL_NIL_VAL;
    if (!ready(vm, "ticks")) return SOL_NIL_VAL;
    return SOL_INT_VAL((int64_t)SDL_GetTicks());
}

/* ---- sound --------------------------------------------------------------- */

/* sdl:beep(#hertz, #milliseconds) -- a square wave, the sound the 1972 machine
 * made and the one message Pong asked for after eleven had drawn it.
 *
 * The samples are written here and queued with `SDL_QueueAudio`, so there is
 * no audio callback: the one place SDL offers to call into a program is the
 * one place this binding declines, for the reason at the top of the file. The
 * device is opened by the first beep rather than by `sdl:start`, since a
 * program that never beeps should not hold a sound device, and it is never
 * closed by hand -- SDL's own shutdown reclaims it with the window.
 *
 * A machine with nothing to play on gets `false` and silence rather than an
 * error, the way a machine with no acceleration gets software rendering: a
 * game is still a game with the sound off, and a headless run is the case
 * that would otherwise refuse. The refusal is remembered, so a beep costs one
 * failed open and not one per frame.
 *
 * What is already queued is dropped first. A beep is about now, and a wall
 * tone that has to wait for the paddle tone to finish is a tone about a moment
 * ago. */
#define BEEP_RATE 44100

static SDL_AudioDeviceID speaker;
static bool speaker_refused;

static bool open_speaker(void)
{
    if (speaker) return true;
    if (speaker_refused) return false;
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) { speaker_refused = true; return false; }

    SDL_AudioSpec want = { 0 }, have;
    want.freq     = BEEP_RATE;
    want.format   = AUDIO_S16SYS;
    want.channels = 1;
    want.samples  = 512;
    speaker = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
    if (speaker == 0) { speaker_refused = true; return false; }
    SDL_PauseAudioDevice(speaker, 0);
    return true;
}

static SolValue prim_beep(SolVM *vm, SolValue self, SolValue *a, int argc)
{
    (void)self;
    if (!args(vm, "beep", argc, 2)) return SOL_NIL_VAL;
    if (!ready(vm, "beep")) return SOL_NIL_VAL;
    if (!ints(vm, "beep", a, 0, 2)) return SOL_NIL_VAL;
    int64_t hertz = SOL_AS_INT(a[0]), ms = SOL_AS_INT(a[1]);
    if (hertz < 20 || hertz > 20000) {
        sol_vm_runtime_error(vm, "'beep' wants a pitch from #20 to #20000 hertz, got #%lld",
                             (long long)hertz);
        return SOL_NIL_VAL;
    }
    if (ms < 0 || ms > 10000) {
        sol_vm_runtime_error(vm, "'beep' wants a length from #0 to #10000 milliseconds, got #%lld",
                             (long long)ms);
        return SOL_NIL_VAL;
    }
    if (!open_speaker()) return SOL_BOOL_VAL(false);

    /* Whole periods only, so the tone ends where the wave crosses zero and
       does not click on the way out. */
    int period = BEEP_RATE / (int)hertz;
    int count  = (int)(BEEP_RATE * ms / 1000) / period * period;
    int16_t *samples = malloc((size_t)count * sizeof *samples);
    if (samples == NULL) {
        sol_vm_runtime_error(vm, "sdl:beep -- out of memory");
        return SOL_NIL_VAL;
    }
    for (int i = 0; i < count; i++)
        samples[i] = (i % period) * 2 < period ? 6000 : -6000;

    SDL_ClearQueuedAudio(speaker);
    int queued = SDL_QueueAudio(speaker, samples, (Uint32)count * sizeof *samples);
    free(samples);
    if (queued != 0) {
        sol_vm_runtime_error(vm, "sdl:beep -- %s", SDL_GetError());
        return SOL_NIL_VAL;
    }
    return SOL_BOOL_VAL(true);
}

/* ---- installation -------------------------------------------------------- */

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != SOL_EXTENSION_ABI) return -1;

    SolObject *sdl = sol_object_new(vm, vm->object_class);

    sol_object_define_primitive(vm, sdl, "start",   prim_start);
    sol_object_define_primitive(vm, sdl, "window",  prim_window);

    sol_object_define_primitive(vm, sdl, "clear",   prim_clear);
    sol_object_define_primitive(vm, sdl, "colour",  prim_colour);
    /* Both spellings, because the language is written in one and its author
       programs in the other, and a graphics binding is the wrong place to make
       somebody remember which. */
    sol_object_define_primitive(vm, sdl, "color",   prim_colour);
    sol_object_define_primitive(vm, sdl, "fill",    prim_fill);
    sol_object_define_primitive(vm, sdl, "line",    prim_line);
    sol_object_define_primitive(vm, sdl, "present", prim_present);

    sol_object_define_primitive(vm, sdl, "poll",    prim_poll);
    sol_object_define_primitive(vm, sdl, "wait",    prim_wait);
    sol_object_define_primitive(vm, sdl, "ticks",   prim_ticks);

    sol_object_define_primitive(vm, sdl, "beep",    prim_beep);

    sol_vm_set_global(vm, "sdl", SOL_OBJ_VAL(sdl));
    return 0;
}
