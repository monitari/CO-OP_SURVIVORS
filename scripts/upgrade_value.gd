extends RefCounted
## A deterministic comparison, not measured DPS: catalog hit coverage, actual
## delivery/count/area changes and cooldown floors. Same assumptions before/after.
const Cats := preload("res://scripts/character_catalog.gd")
const Evolutions := preload("res://scripts/evolution_catalog.gd")

static func has_effect(main: Node, slot: int, option: Dictionary) -> bool:
	var id := String(option["id"])
	var index := int(option.get("weapon_slot", -1))
	if index >= 0:
		var w: Dictionary = main.weapon_loadouts[slot][index]
		if id == "weapon_rate":
			return maxf(0.12, maxf(0.2, float(w["cooldown"]) * 0.88) * main.players[slot].haste) < main._weapon_interval(slot, index) - 0.00001
		if id == "special_b":
			if w["weapon_id"] == "frost": return float(w["slow"]) > 0.25001
			if w["weapon_id"] == "scythe": return float(w["arc"]) * main.players[slot].area < TAU and float(w["arc"]) < PI * 1.75 - 0.00001
	if id in ["unlock_treasure", "treasure_upgrade"]:
		var effect: String = main._option_icon_id(slot, option)
		if effect == "haste": return main.players[slot].haste > 0.40001
		if effect == "crit": return main.players[slot].crit_chance < 0.84999
	return true

static func attributes(player: Node) -> Dictionary:
	return {"might": player.might, "haste": player.haste, "area": player.area,
		"amount": player.amount, "pierce": player.pierce, "crit": player.crit_chance,
		"projectile_speed": player.projectile_speed}

static func benefits_loadout(loadout: Array, effect: String) -> bool:
	for w: Dictionary in loadout:
		var id := String(w["weapon_id"])
		match effect:
			"amount":
				if w.has("count"): return true
			"pierce":
				if id in ["homing", "flame", "starpiercer", "supernova"]: return true
			"projectile_speed":
				if w.has("speed"): return true
			"area":
				if id not in ["homing", "flame"]: return true
			_: return true
	return false

static func baseline(w: Dictionary) -> Dictionary:
	for cat in Cats.all_characters():
		if cat["weapon_id"] == w["weapon_id"]: return cat["weapon"]
	for evo in Evolutions.all_evolutions():
		if evo["weapon_id"] == w["weapon_id"]: return evo["weapon"]
	return w

static func output(w: Dictionary, a: Dictionary) -> float:
	var base := baseline(w)
	var id := String(w["weapon_id"])
	var coverage := float(base.get("reach", 1.0))
	if w.has("count"):
		coverage *= (float(w["count"]) + float(a["amount"])) / maxf(1.0, float(base["count"]))
	if id == "lightning":
		coverage *= (1.0 - pow(0.82, float(w["jumps"]))) / (1.0 - pow(0.82, float(base["jumps"])))
	if id in ["homing", "flame", "starpiercer", "supernova"]:
		coverage *= 1.0 + float(a["pierce"]) * 0.35
	# Area is not a damage upgrade for homing or fixed-radius orbit shards.
	if id not in ["homing", "flame", "orbit", "celestial", "lightning"]:
		for key in ["radius", "range", "width"]:
			if w.has(key) and base.has(key):
				var ratio := float(w[key]) * float(a["area"]) / maxf(1.0, float(base[key]))
				# Circle/sector coverage scales with radius squared; beams and
				# the tether instead scale by their length and width separately.
				coverage *= ratio * ratio if key == "radius" or (key == "range" and id in ["scythe", "black_moon", "thunder_god"]) else ratio
		if w.has("arc"):
			coverage *= minf(TAU, float(w["arc"]) * float(a["area"])) / float(base["arc"])
	if id == "thunder_god": coverage = minf(24.0, coverage)
	return float(w["damage"]) * float(a["might"]) * (1.0 + float(a["crit"])) * coverage / maxf(0.12, float(w["cooldown"]) * float(a["haste"]))

static func gain(main: Node, slot: int, option: Dictionary) -> float:
	var loadout: Array = main.weapon_loadouts[slot].duplicate(true)
	var a := attributes(main.players[slot])
	var before := 0.0
	for w: Dictionary in loadout: before += output(w, a)
	var id := String(option["id"])
	var index := int(option.get("weapon_slot", -1))
	if id == "unlock_weapon": loadout.append(main._build_weapon_state(option["character"]))
	elif id == "evolve_weapon": loadout[index] = Evolutions.build_state(option["evolution"], loadout[index])
	elif id in ["unlock_treasure", "treasure_upgrade"]:
		match main._option_icon_id(slot, option):
			"might": a["might"] += 0.15
			"area": a["area"] += 0.15
			"amount": a["amount"] += 1
			"haste": a["haste"] = maxf(0.4, a["haste"] - 0.1)
			"crit": a["crit"] = minf(0.85, a["crit"] + 0.08)
			"pierce": a["pierce"] += 1
	elif index >= 0:
		var w: Dictionary = loadout[index]
		match id:
			"weapon_power": w["damage"] *= 1.25
			"weapon_rate": w["cooldown"] = maxf(0.2, w["cooldown"] * 0.88)
			"special_a":
				match w["weapon_id"]:
					"homing": w["count"] += 1
					"flame": w["count"] += 2
					"lightning": w["jumps"] += 1
					"frost": w["radius"] += 30.0
					"scythe": w["range"] += 30.0
					"chain": w["width"] += 14.0
			"special_b":
				if w["weapon_id"] == "scythe": w["arc"] = minf(PI * 1.75, w["arc"] + 0.25)
	var after := 0.0
	for w: Dictionary in loadout: after += output(w, a)
	return maxf(0.0, after / maxf(0.001, before) - 1.0)
