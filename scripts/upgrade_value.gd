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
			return maxf(0.25, maxf(0.32, float(w["cooldown"]) * 0.93) * main.players[slot].haste) < main._weapon_interval(slot, index) - 0.00001
		if id in ["special_a", "special_b"]:
			# 보름베기 has a second way of being useless that the spec itself
			# cannot see: a survivor whose area multiplier has already pushed
			# the arc to a full circle gains nothing from a wider one.
			if w["weapon_id"] == "scythe" and id == "special_b":
				if float(w["arc"]) * main.players[slot].area >= TAU: return false
			return main._special_has_room(slot, index, id.substr(id.length() - 1))
	if id in ["unlock_treasure", "treasure_upgrade"]:
		var effect: String = main._option_icon_id(slot, option)
		if effect == "haste": return main.players[slot].haste > 0.60001
		if effect == "crit": return main.players[slot].crit_chance < 0.59999
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
	# 분광 splits the lance into parallel beams, which is a straight multiple of
	# what one cast covers.
	if w.has("beams"):
		coverage *= float(w["beams"]) / maxf(1.0, float(base.get("beams", 1)))
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
	return float(w["damage"]) * float(a["might"]) * (1.0 + float(a["crit"])) * coverage / maxf(0.25, float(w["cooldown"]) * float(a["haste"]))

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
			"might": a["might"] += 0.09
			"area": a["area"] += 0.09
			"amount": a["amount"] += 1
			"haste": a["haste"] = maxf(0.6, a["haste"] - 0.06)
			"crit": a["crit"] = minf(0.60, a["crit"] + 0.05)
			"pierce": a["pierce"] += 1
	elif index >= 0:
		var w: Dictionary = loadout[index]
		match id:
			"weapon_power": w["damage"] *= 1.16
			"weapon_rate": w["cooldown"] = maxf(0.32, w["cooldown"] * 0.93)
			# Both specials run through the same table the real upgrade does, on
			# this throwaway copy of the loadout. The old version listed six of
			# the twenty specials by hand, so the scorer was silently pricing
			# the other fourteen at zero and never recommending them.
			"special_a", "special_b": main.apply_special_to_state(w, id.substr(id.length() - 1))
	var after := 0.0
	for w: Dictionary in loadout: after += output(w, a)
	return maxf(0.0, after / maxf(0.001, before) - 1.0)
