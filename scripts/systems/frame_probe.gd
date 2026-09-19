class_name FrameProbe
extends RefCounted

## Timing for the work main._profile cannot see.
##
## main._profile brackets the phases of main's own physics tick, and for a long
## time that was taken to be "the tick". It is not: every weapon field, milk pool,
## mine, returning toy and the projectile loop runs in its own node's callback,
## which the engine calls directly, and at the end of a long run those callbacks
## were most of the frame while main's phases added up to a few milliseconds.
## This is the same accumulator idea, reachable from any script, so those
## callbacks can report into the same readout (DebugInspector, F11) and the same
## benchmark (tests/perf_bench_capture.gd).
##
## Off costs one static bool read per call site. Nothing here allocates while
## disabled.

static var enabled := false
## Microseconds per section since the last clear().
static var totals: Dictionary = {}
## How many times each section ran since the last clear().
static var calls: Dictionary = {}


## Start of a timed span, or 0 when probing is off.
static func mark() -> int:
	return Time.get_ticks_usec() if enabled else 0


## End of a span started with mark(). Spans may nest; a nested section's time is
## also inside its parent's, and the readout says which sections are inclusive.
static func add(section: StringName, started: int) -> void:
	if not enabled or started == 0:
		return
	totals[section] = int(totals.get(section, 0)) + (Time.get_ticks_usec() - started)
	calls[section] = int(calls.get(section, 0)) + 1


static func clear() -> void:
	totals.clear()
	calls.clear()
