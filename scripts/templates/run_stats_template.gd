extends RefCounted
## Canonical shape for one run's result data.
##
## Call `create()` instead of keeping a shared Dictionary: the nested arrays and
## dictionaries are mutable and must never leak values into the next run.

const DEFAULTS := {
	"bosses": 0,
	"revives": 0,
	"dashes": 0,
	"overcharge_time": 0.0,
	"overloads": 0,
	"resonance_casts": 0,
	"items": 0,
	"reflected": 0.0,
	"planters": 0,
	"xp_by_player": [0, 0],
	"personal_levels": [1, 1],
	"items_by_player": [0, 0],
	"items_by_type": {},
	"weapon_damage": [{}, {}],
	"resonance_damage": 0.0,
}


static func create() -> Dictionary:
	return DEFAULTS.duplicate(true)
