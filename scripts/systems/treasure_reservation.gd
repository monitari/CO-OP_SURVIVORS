class_name TreasureReservation
extends RefCounted

## Keep enough treasure slots for every unfinished weapon to have at least one
## reachable route. Untyped weapons consider both Lv.3 routes; once a route is
## chosen only its required treasure counts. Four weapons therefore never need
## more than four material slots, even when some requirements overlap.

const Techs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")


static func missing_slots(weapons: Array, treasures: Array, extra_weapon_id := "",
		route_slot := -1, route_treasure_id := "", extra_treasure_id := "") -> int:
	var owned := {}
	for treasure: Dictionary in treasures:
		owned[String(treasure["id"])] = true
	if not extra_treasure_id.is_empty():
		owned[extra_treasure_id] = true
	var possible: Array[Dictionary] = [{}]
	for index in weapons.size():
		var weapon: Dictionary = weapons[index]
		if bool(weapon.get("evolved", false)):
			continue
		var required: Array[String] = []
		if index == route_slot:
			required.append(route_treasure_id)
		else:
			var chosen := String(weapon.get("tech_synergy_treasure_id", ""))
			if not chosen.is_empty():
				required.append(chosen)
			else:
				required = _route_treasures(String(weapon.get("base_weapon_id", weapon.get("weapon_id", ""))))
		possible = _with_requirements(possible, required)
	if not extra_weapon_id.is_empty():
		possible = _with_requirements(possible, _route_treasures(extra_weapon_id))
	var minimum := 1000
	for required: Dictionary in possible:
		var missing := 0
		for treasure_id in required:
			if not owned.has(treasure_id):
				missing += 1
		minimum = mini(minimum, missing)
	return minimum


static func viable(weapons: Array, treasures: Array, capacity: int,
		extra_weapon_id := "", route_slot := -1, route_treasure_id := "",
		extra_treasure_id := "") -> bool:
	var used := treasures.size()
	if not extra_treasure_id.is_empty():
		var already_owned := false
		for treasure: Dictionary in treasures:
			if String(treasure["id"]) == extra_treasure_id:
				already_owned = true
				break
		if not already_owned:
			used += 1
	return used + missing_slots(weapons, treasures, extra_weapon_id,
		route_slot, route_treasure_id, extra_treasure_id) <= capacity


static func _route_treasures(weapon_id: String) -> Array[String]:
	var result: Array[String] = []
	for tech: Dictionary in Techs.for_weapon(weapon_id):
		var treasure_id := String(tech.get("synergy_treasure_id", ""))
		if not treasure_id.is_empty() and not result.has(treasure_id):
			result.append(treasure_id)
	return result


static func _with_requirements(possible: Array[Dictionary], choices: Array[String]) -> Array[Dictionary]:
	if choices.is_empty():
		return possible
	var expanded: Array[Dictionary] = []
	for required: Dictionary in possible:
		for treasure_id in choices:
			var next := required.duplicate()
			next[treasure_id] = true
			expanded.append(next)
	return expanded
