class_name WeaponGrowth
extends RefCounted

const WeaponTechs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")

## How much one weapon card is worth, decided in one place.
##
## Every card used to be worth the same 28% from the first level of a run to the
## last, which put the strong part of a weapon's life at the start — a handful of
## cards took a starting weapon most of the way, and an enhanced weapon spent the
## last third of the run buying 12% steps. A weapon now lives through three
## stages and each is worth more than the one before it:
##
##   OPENING  no tech yet            small steps, the weapon is still being learned
##   ROUTE    tech chosen             the tech's own axes grow faster than the rest
##   FINAL    enhanced weapon         the largest steps in the run
##
## A tech is not a filter on which cards appear — every axis stays open — but it
## decides what each axis is worth. A tech that names two axes grows those much
## faster and the other two slower; one that names three leans less; a balanced
## tech that names all four grows everything at the ordinary rate and pays for
## its breadth with its delivery instead.

## A weapon has to have been grown this far before its route can be chosen. The
## first cards teach what the weapon does; the tech decides what it becomes.
const TECH_UNLOCK_TIER := 3

## What a weapon is worth before anyone has spent anything on it. It was 0.68,
## and with the old flat 28% cards the opening was the strong part of a run.
const OPENING_DAMAGE_SCALE := 0.62

enum Stage { OPENING, ROUTE, FINAL }

## Damage multiplier per 화력 card is 1 + POWER_GAIN[stage] * focus.
const POWER_GAIN := [0.16, 0.26, 0.30]
## Cooldown multiplier per 속도 card is 1 - RATE_GAIN[stage] * focus.
const RATE_GAIN := [0.05, 0.09, 0.11]
## Scales the continuous delta of a unique special (range, radius, slow...).
const SPECIAL_SCALE := [0.8, 1.0, 1.35]
const RATE_FLOOR := 0.32

const FOCUS_NARROW := 1.3
const OFF_NARROW := 0.75
const FOCUS_WIDE := 1.15
const OFF_WIDE := 0.85
## Count-style specials (+1 shot, +1 chain) cannot be scaled by a fraction, so a
## focused one also sharpens the weapon's damage by this much per stage step.
const FOCUS_INTEGER_DAMAGE := [0.04, 0.06, 0.08]

## How much of the damage and cooldown a weapon was grown by before its
## enhancement survives into the enhanced form. The enhancement used to reset a
## weapon to the catalogue numbers, so every 화력 card taken before it was thrown
## away the moment the pair reached the part of the tree they were playing for.
const EVOLUTION_CARRY := 0.35


static func base_id(state: Dictionary) -> String:
	return String(state.get("base_weapon_id", state.get("weapon_id", "")))


static func stage(state: Dictionary) -> int:
	if bool(state.get("evolved", false)):
		return Stage.FINAL
	if String(state.get("tech_id", "")).is_empty():
		return Stage.OPENING
	return Stage.ROUTE


## True once a weapon has reached the tier its route has to be chosen at and has
## not chosen one. Such a weapon takes no more tier cards until it does.
static func needs_tech(state: Dictionary) -> bool:
	return not bool(state.get("evolved", false)) \
		and String(state.get("tech_id", "")).is_empty() \
		and int(state.get("tier", 1)) >= TECH_UNLOCK_TIER


static func tech(state: Dictionary) -> Dictionary:
	var tech_id := String(state.get("tech_id", ""))
	if tech_id.is_empty():
		return {}
	return WeaponTechs.by_id(base_id(state), tech_id)


## What the chosen tech makes of one growth axis: >1 on its own axes, <1 on the
## others, 1.0 before a tech exists or for a tech that names all four.
static func focus(state: Dictionary, axis: String) -> float:
	var chosen := tech(state)
	if chosen.is_empty():
		return 1.0
	var axes: Array = chosen.get("upgrades", [])
	if axes.size() >= 4:
		return 1.0
	var narrow := axes.size() <= 2
	if axis in axes:
		return FOCUS_NARROW if narrow else FOCUS_WIDE
	return OFF_NARROW if narrow else OFF_WIDE


static func focus_label(state: Dictionary, axis: String) -> String:
	var value := focus(state, axis)
	if value > 1.0:
		return "테크 특화"
	if value < 1.0:
		return "테크 외"
	return ""


static func power_step(state: Dictionary) -> float:
	return 1.0 + float(POWER_GAIN[stage(state)]) * focus(state, "weapon_power")


static func rate_step(state: Dictionary) -> float:
	return 1.0 - float(RATE_GAIN[stage(state)]) * focus(state, "weapon_rate")


static func next_cooldown(state: Dictionary) -> float:
	return maxf(RATE_FLOOR, float(state["cooldown"]) * rate_step(state))


static func special_scale(state: Dictionary, key: String) -> float:
	return float(SPECIAL_SCALE[stage(state)]) * focus(state, "special_" + key)


static func integer_focus_damage(state: Dictionary, key: String) -> float:
	if focus(state, "special_" + key) <= 1.0:
		return 0.0
	return float(FOCUS_INTEGER_DAMAGE[stage(state)])


## The enhanced numbers, carrying part of what the base weapon was grown by.
## `base_damage` is the unscaled catalogue damage of the base weapon.
static func carry_into_evolution(evolved: Dictionary, grown: Dictionary, base_damage: float, base_cooldown: float) -> void:
	var opening := maxf(0.001, base_damage * OPENING_DAMAGE_SCALE)
	var damage_ratio := maxf(1.0, float(grown.get("damage", opening)) / opening)
	evolved["damage"] = float(evolved["damage"]) * (1.0 + (damage_ratio - 1.0) * EVOLUTION_CARRY)
	if base_cooldown > 0.0 and evolved.has("cooldown"):
		var rate_ratio := clampf(float(grown.get("cooldown", base_cooldown)) / base_cooldown, 0.1, 1.0)
		evolved["cooldown"] = maxf(RATE_FLOOR, float(evolved["cooldown"]) * (1.0 - (1.0 - rate_ratio) * EVOLUTION_CARRY))
