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
## decides what each axis is worth. Every tech names exactly two of the four
## axes: those two grow much faster and the other two slower. Techs used to name
## anywhere from two to four, so "how much does this route lean?" was a third
## thing to learn per weapon on top of what the route did.

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

## What a route makes of one growth axis. Every route names exactly two of the
## four axes (WeaponTechCatalog enforces the shape), so there is one pair of
## numbers rather than a narrow pair and a wide pair: the two axes the route is
## about grow at FOCUS_WEIGHT, the two it is not grow at OFF_WEIGHT.
##
## These are balance numbers and the player is never shown them. What the card
## says is "화력 강화 효율 증가" / "공격 속도 성장 완만" — the meaning, not the
## multiplier, so the two can be retuned without rewriting any text.
const FOCUS_WEIGHT := 1.30
const OFF_WEIGHT := 0.75
## Count-style specials (+1 shot, +1 chain) cannot be scaled by a fraction, so a
## focused one also sharpens the weapon's damage by this much per stage step.
const FOCUS_INTEGER_DAMAGE := [0.04, 0.06, 0.08]

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


## What the chosen tech makes of one growth axis: FOCUS_WEIGHT on the two axes
## the route names, OFF_WEIGHT on the two it does not, and a flat 1.0 for a
## weapon that has not picked a route yet.
static func focus(state: Dictionary, axis: String) -> float:
	var chosen := tech(state)
	if chosen.is_empty():
		return 1.0
	var axes: Array = chosen.get("upgrades", [])
	return FOCUS_WEIGHT if axis in axes else OFF_WEIGHT


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


## The enhanced numbers, carrying everything the base weapon was grown by.
## `base_damage` is the unscaled catalogue damage of the base weapon.
##
## The growth carries at 100%: whatever multiple of its opening damage the base
## weapon had reached, the enhanced form opens at the same multiple of *its* own
## catalogue damage, and the same for how far the cooldown had come down. There
## used to be a 35% conversion here, which meant two thirds of every 화력 card
## bought before Lv.7 evaporated at the exact moment the pair reached the part of
## the tree they had been playing for — and no screen ever told them that was
## going to happen. A conversion rate nobody can see is a tax, not a mechanic.
static func carry_into_evolution(evolved: Dictionary, grown: Dictionary, base_damage: float, base_cooldown: float) -> void:
	var opening := maxf(0.001, base_damage * OPENING_DAMAGE_SCALE)
	var damage_ratio := maxf(1.0, float(grown.get("damage", opening)) / opening)
	evolved["damage"] = float(evolved["damage"]) * damage_ratio
	if base_cooldown > 0.0 and evolved.has("cooldown"):
		var rate_ratio := clampf(float(grown.get("cooldown", base_cooldown)) / base_cooldown, 0.1, 1.0)
		evolved["cooldown"] = maxf(RATE_FLOOR, float(evolved["cooldown"]) * rate_ratio)
