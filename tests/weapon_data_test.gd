extends SceneTree

## The data contract for weapons, routes, enhancements and resonances (§21).
##
## Everything this system promises the player is a promise about *shape*: every
## weapon has two routes, every route names 화력 or 공격 속도 plus exactly one of
## that weapon's two 고유 axes, every weapon enhances at Lv.7, every enhanced
## weapon carries exactly two tags, and every pair of enhanced weapons can reach
## at least one resonance. None of that is enforced by the type system, and all
## of it is the sort of thing that a hurried thirteenth weapon breaks quietly —
## the weapon works, the run plays, and one pairing in seventy-eight has no
## resonance for the rest of the game's life.
##
## So it is checked mechanically instead of remembered. A failure here is a data
## entry mistake, not a balance opinion.

const Cats := preload("res://scripts/catalogs/character_catalog.gd")
const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")
const WeaponTechs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const Growth := preload("res://scripts/systems/weapon_growth.gd")
const ResonanceScript := preload("res://scripts/systems/resonance_system.gd")
const MainScript := preload("res://scripts/main.gd")

## §4. The shared vocabulary every weapon's 고유 A/B is expressed in. A special
## that invents its own is the beginning of a per-weapon upgrade function, which
## is the thing this list exists to prevent.
const PRIMITIVES := [
	"Damage", "Cooldown", "Count", "Range", "Radius", "ProjectileSpeed",
	"Pierce", "Chain", "Duration", "Force", "Slow", "Heal", "Crit", "Area",
]

var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _init() -> void:
	_check_techs()
	_check_evolutions()
	_check_specials()
	_check_tags()
	_check_resonances()
	_check_internal_ids()
	if failures.is_empty():
		print("WEAPON_DATA_PASS: routes, enhancements, primitives, tags, resonance coverage and internal ids")
	else:
		for failure in failures:
			printerr("WEAPON_DATA_FAIL: " + failure)
		printerr("WEAPON_DATA_FAIL: %d problem(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _weapon_ids() -> Array:
	var ids: Array = []
	for character in Cats.all_characters():
		var id := String(character["weapon_id"])
		if id not in ids:
			ids.append(id)
	return ids


## §3, §5. Two routes per weapon, A is the 화력 one and B is the 속도 one, and
## each names exactly one 고유 axis so neither route is a superset of the other.
func _check_techs() -> void:
	for weapon_id in _weapon_ids():
		var techs := WeaponTechs.for_weapon(weapon_id)
		_check(techs.size() == 2, "%s has %d routes, expected exactly 2" % [weapon_id, techs.size()])
		if techs.size() != 2:
			continue
		var roles: Array = []
		for tech in techs:
			var tech_id := String(tech["id"])
			var role := String(tech.get("role", ""))
			roles.append(role)
			var axes: Array = tech.get("upgrades", [])
			_check(axes.size() == 2, "%s/%s names %d axes, expected exactly 2" % [weapon_id, tech_id, axes.size()])
			var lead := "weapon_power" if role == "a" else "weapon_rate"
			_check(lead in axes, "%s/%s is route %s but does not name %s" % [weapon_id, tech_id, role, lead])
			var specials := 0
			for axis in axes:
				if String(axis).begins_with("special_"):
					specials += 1
			_check(specials == 1, "%s/%s names %d 고유 axes, expected exactly 1" % [weapon_id, tech_id, specials])
			_check(not String(tech.get("synergy_treasure_id", "")).is_empty(),
				"%s/%s has no synergy treasure" % [weapon_id, tech_id])
			# §8. A route must never be the reason a weapon cannot finish.
			_check(not tech.has("treasure_id"),
				"%s/%s still carries a required treasure; treasures are synergy only" % [weapon_id, tech_id])
			_check(not WeaponTechs.BEHAVIORS.get(weapon_id, {}).get(tech_id, {}).is_empty(),
				"%s/%s has no behaviour, so the route changes nothing about delivery" % [weapon_id, tech_id])
		roles.sort()
		_check(roles == ["a", "b"], "%s routes are %s, expected one 'a' and one 'b'" % [weapon_id, roles])


## §8. One enhancement per weapon, reachable by Lv.7 alone.
func _check_evolutions() -> void:
	var seen_weapon_ids: Dictionary = {}
	for weapon_id in _weapon_ids():
		var evolution := Evolutions.for_base(weapon_id)
		_check(not evolution.is_empty(), "%s has no enhancement" % weapon_id)
	for evolution in Evolutions.all_evolutions():
		var id := String(evolution["weapon_id"])
		_check(not seen_weapon_ids.has(id), "two enhancements share the weapon id %s" % id)
		seen_weapon_ids[id] = true
		_check(Evolutions.for_base(String(evolution["base_weapon_id"]))["weapon_id"] == id,
			"%s is not the enhancement its own base weapon resolves to" % id)
		_check(not evolution.has("treasure_id"),
			"%s still names a required treasure" % id)
	_check(not ("REQUIRED_TREASURE_TIER" in Evolutions),
		"the treasure gate constant is back; Lv.7 is meant to be the only condition")
	# §8. Growth carries in full: an enhanced weapon opens at the same multiple
	# of its own catalogue damage that the base weapon had reached of its.
	var base: Dictionary = Cats.all_characters()[0]["weapon"]
	var grown := (base as Dictionary).duplicate(true)
	grown["damage"] = float(base["damage"]) * Growth.OPENING_DAMAGE_SCALE * 3.0
	grown["cooldown"] = float(base["cooldown"]) * 0.5
	var evolved := {"damage": 100.0, "cooldown": 2.0}
	Growth.carry_into_evolution(evolved, grown, float(base["damage"]), float(base["cooldown"]))
	_check(is_equal_approx(float(evolved["damage"]), 300.0),
		"growth carried at %.1f%% rather than 100%%" % (float(evolved["damage"]) / 3.0))
	_check(is_equal_approx(float(evolved["cooldown"]), 1.0),
		"cooldown growth carried to %.2f rather than 1.00" % float(evolved["cooldown"]))


## §4, §18. Every 고유 upgrade is one of the shared primitives, so a new weapon
## needs data rather than a bespoke upgrade function.
func _check_specials() -> void:
	var main = MainScript.new()
	for weapon_id in _weapon_ids():
		for key in ["a", "b"]:
			var spec: Dictionary = main.WEAPON_SPECIALS.get(weapon_id, {}).get(key, {})
			_check(not spec.is_empty(), "%s has no 고유 %s" % [weapon_id, key])
			if spec.is_empty():
				continue
			var primitive := String(spec.get("primitive", ""))
			_check(primitive in PRIMITIVES,
				"%s 고유 %s uses primitive %s, which is not in the shared list" % [weapon_id, key, primitive])
	for weapon_id in WeaponTechs.SPECIAL_OVERRIDES:
		for tech_id in WeaponTechs.SPECIAL_OVERRIDES[weapon_id]:
			_check(not WeaponTechs.by_id(weapon_id, tech_id).is_empty(),
				"%s has a special override for the retired route %s" % [weapon_id, tech_id])
			for key in WeaponTechs.SPECIAL_OVERRIDES[weapon_id][tech_id]:
				var primitive := String(WeaponTechs.SPECIAL_OVERRIDES[weapon_id][tech_id][key].get("primitive", ""))
				_check(primitive in PRIMITIVES,
					"%s/%s override %s uses unknown primitive %s" % [weapon_id, tech_id, key, primitive])
	main.free()
	for weapon_id in WeaponTechs.BEHAVIORS:
		for tech_id in WeaponTechs.BEHAVIORS[weapon_id]:
			_check(not WeaponTechs.by_id(weapon_id, tech_id).is_empty(),
				"%s has a behaviour for the retired route %s" % [weapon_id, tech_id])


## §10. At most two tags per weapon, one from each list, and the two lists never
## overlap — 뇌전 is what an attack is made of, 폭풍 is how it covers ground.
func _check_tags() -> void:
	for tag in Evolutions.PRIMARY_TAGS:
		_check(not (tag in Evolutions.BEHAVIOR_TAGS), "%s is registered as both a primary and a behaviour tag" % tag)
	for evolution in Evolutions.all_evolutions():
		var id := String(evolution["weapon_id"])
		var tags := Evolutions.tags_of(evolution)
		_check(tags.size() == 2, "%s carries %d tags, expected exactly 2" % [id, tags.size()])
		_check(String(evolution["primary_tag"]) in Evolutions.PRIMARY_TAGS,
			"%s has unregistered primary tag %s" % [id, evolution["primary_tag"]])
		_check(String(evolution["behavior_tag"]) in Evolutions.BEHAVIOR_TAGS,
			"%s has unregistered behaviour tag %s" % [id, evolution["behavior_tag"]])
	for character in Cats.all_characters():
		var tags: Array = character["tags"]
		_check(tags.size() <= 2, "%s carries %d tags, at most 2 allowed" % [character["weapon_id"], tags.size()])
		for tag in tags:
			_check(tag in Evolutions.PRIMARY_TAGS or tag in Evolutions.BEHAVIOR_TAGS,
				"%s has unregistered tag %s" % [character["weapon_id"], tag])
	# Every tag in either list has to be reachable, or it is a word in a table
	# that no weapon can ever produce and no resonance can ever ask for.
	var present: Dictionary = {}
	for evolution in Evolutions.all_evolutions():
		for tag in Evolutions.tags_of(evolution):
			present[tag] = true
	for tag in Evolutions.BEHAVIOR_TAGS:
		_check(present.has(tag), "behaviour tag %s is carried by no enhanced weapon" % tag)
		_check(ResonanceScript.BEHAVIOR_TEMPLATES.has(tag), "behaviour tag %s has no generic template" % tag)
	for tag in Evolutions.PRIMARY_TAGS:
		_check(present.has(tag), "primary tag %s is carried by no enhanced weapon" % tag)
		_check(ResonanceScript.ELEMENT_RIDERS.has(tag), "primary tag %s has no element rider" % tag)


## §10, §13, §15. Every requirement is a registered tag, every catalogue entry is
## reachable, and — the one that actually matters to a player — every pair of
## enhanced weapons has at least one resonance, so no pair can finish two builds
## and be told the top of the tree is not for them.
func _check_resonances() -> void:
	var catalog := ResonanceScript.all_resonances()
	var seen: Dictionary = {}
	for resonance in catalog:
		var id := String(resonance["id"])
		_check(not seen.has(id), "duplicate resonance id %s" % id)
		seen[id] = true
		var requires: Array = resonance["requires"]
		_check(requires.size() == 2, "%s requires %d tags, expected 2" % [id, requires.size()])
		for tag in requires:
			_check(tag in Evolutions.PRIMARY_TAGS or tag in Evolutions.BEHAVIOR_TAGS,
				"%s requires unregistered tag %s" % [id, tag])
		_check(float(resonance["cooldown"]) > 0.0, "%s has no cooldown of its own" % id)
		_check(not String(resonance.get("description", "")).is_empty(), "%s has no description" % id)
		_check(Evolutions.by_weapon_id(id).is_empty(),
			"resonance %s collides with an enhanced weapon of the same id" % id)

	var evolutions := Evolutions.all_evolutions()
	var reached: Dictionary = {}
	for first in evolutions.size():
		for second in range(first, evolutions.size()):
			var tags_a := Evolutions.tags_of(evolutions[first])
			var tags_b := Evolutions.tags_of(evolutions[second])
			var matches: Array[String] = []
			for resonance in catalog:
				if ResonanceScript.pair_satisfies(resonance["requires"], tags_a, tags_b):
					matches.append(String(resonance["id"]))
					reached[String(resonance["id"])] = true
			_check(not matches.is_empty(), "%s + %s reach no resonance at all" % [
				evolutions[first]["weapon_id"], evolutions[second]["weapon_id"]])
	for resonance in catalog:
		_check(reached.has(String(resonance["id"])),
			"%s can never be produced by any pair of enhanced weapons" % resonance["id"])
	# §11. Slots and cores are the same number on purpose, so the run explains
	# the cap instead of a rule having to.
	_check(ResonanceScript.MAX_ACTIVE_RESONANCES == 2,
		"resonance slots are %d; the run hands out two cores" % ResonanceScript.MAX_ACTIVE_RESONANCES)
	# §16. A global cooldown multiplier makes every catalogue number a lie.
	_check(not ("COOLDOWN_SCALE" in ResonanceScript),
		"a global resonance cooldown scale is back; cooldowns are per-resonance")


## §19. Display names are not identities. Internal ids are, so they have to be
## unique across the whole system — routes, enhancements and resonances share one
## namespace because saves, logs and telemetry do too.
func _check_internal_ids() -> void:
	var seen: Dictionary = {}
	var check_unique := func(internal_id: String, owner: String) -> void:
		_check(not internal_id.is_empty(), "%s has no internal id" % owner)
		_check(not seen.has(internal_id), "internal id %s is used by both %s and %s" % [
			internal_id, seen.get(internal_id, "?"), owner])
		seen[internal_id] = owner
	for weapon_id in _weapon_ids():
		for tech in WeaponTechs.for_weapon(weapon_id):
			var internal_id := String(tech.get("internal_id", ""))
			check_unique.call(internal_id, "%s/%s" % [weapon_id, tech["id"]])
			_check(internal_id.begins_with("TECH_"), "%s does not start with TECH_" % internal_id)
	for evolution in Evolutions.all_evolutions():
		var internal_id := String(evolution.get("internal_id", ""))
		check_unique.call(internal_id, String(evolution["weapon_id"]))
		_check(internal_id.begins_with("EVOLUTION_"), "%s does not start with EVOLUTION_" % internal_id)
	for resonance in ResonanceScript.all_resonances():
		var internal_id := String(resonance.get("internal_id", ""))
		check_unique.call(internal_id, String(resonance["id"]))
		_check(internal_id.begins_with("RESONANCE_"), "%s does not start with RESONANCE_" % internal_id)
