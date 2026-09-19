extends Node

## Stamps the moment its physics callback runs. Two of these, at the extreme
## process_physics_priority values, bracket every script callback in a tick, so
## the benchmark can split a tick into "scripts" and "everything the engine does
## around them" (timers, tweens, the message queue, transform notifications, the
## delete queue).

signal stamped(first: bool)
var first := true


func _physics_process(_delta: float) -> void:
	stamped.emit(first)
