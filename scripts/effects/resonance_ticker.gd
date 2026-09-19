extends Node
## Calls a callback a fixed number of times on run time.
##
## Resonances that are described as lasting — a lightning field that keeps
## striking, a chain that keeps burning, a blast that lands after the frost it
## follows — used to be one instant hit, because the controller only had instant
## hits to build them from. This is the whole of what they needed: a clock that
## pauses with the run (a SceneTreeTimer would too, but could not be swept by
## WeaponController.clear_transients on a restart) and an index so a tick can
## tell the first strike from the ones after it.

var interval := 0.3
var remaining := 1
var fired := 0
var clock := 0.0
var on_tick := Callable()


func setup(first_delay: float, tick_interval: float, ticks: int, callback: Callable, first_index := 0) -> void:
	clock = first_delay
	interval = maxf(0.01, tick_interval)
	remaining = ticks
	fired = first_index
	on_tick = callback


func _physics_process(delta: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_physics_process(delta)
	FrameProbe.add(&"resonance_tickers", probe_started)


func _probed_physics_process(delta: float) -> void:
	clock -= delta
	while clock <= 0.0 and remaining > 0:
		if not on_tick.is_valid():
			queue_free()
			return
		on_tick.call(fired)
		fired += 1
		remaining -= 1
		clock += interval
	if remaining <= 0:
		queue_free()
