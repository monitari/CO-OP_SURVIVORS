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
##
## These were [0.16, 0.26, 0.30] and they compounded into the single biggest
## balance failure in the game. Eleven cards poured into 화력 on a focused route
## multiplied a weapon's damage by **thirty-five**, and the 격노의 인장 treasure
## multiplied that again — so a pair with one committed weapon was roughly
## seventy times their opening output around the midpoint of a run, against
## enemies that scale nothing like that. Everything after minute twelve was a
## formality. The ladder still rises across the three stages, because a late
## card should be worth more than an early one, but the whole staircase is much
## shallower: the same eleven cards now land near ×8 instead of ×35.
const POWER_GAIN := [0.12, 0.16, 0.19]
## A focused 속도 card pays the same damage-per-second multiplier as a
## 화력 card at the same stage and focus. A cooldown factor of 1 / (1 + gain)
## makes the reciprocal cadence grow by exactly the damage card's multiplier.
## The cooldown floor still limits total stacking.

## Scales the continuous delta of a unique special (range, radius, slow...).
const SPECIAL_SCALE := [0.70, 0.85, 1.00]
## The absolute fastest any weapon may ever be cast, whatever it started at.
const RATE_FLOOR := 0.32

## And the floor that actually bites: no weapon may be brought below this share
## of its own catalogue interval by 속도 cards.
##
## Without it every weapon converged on the same number. 속도 cards are
## multiplicative and 질풍의 태엽 multiplies again, so 궤도 파편 (6.6s), 초신성
## (2.02s) and 성좌 관통포 (1.12s) all ended a run pinned to the same hard 0.25s
## floor — which erased the difference between a slow heavy weapon and a fast
## light one, and is most of the reason the late game turns into a wall of
## projectiles the renderer cannot keep up with. A weapon is now allowed to get
## much faster and never allowed to stop being what it is.
const RATE_MIN_RATIO := 0.45
## The same rule after 질풍의 태엽 and 광란 are applied, which is where a weapon's
## real interval is decided (see main._weapon_interval). Lower than the ratio
## above, so haste is still worth carrying once the card ladder has bottomed out.
const INTERVAL_MIN_RATIO := 0.33

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
const FOCUS_INTEGER_DAMAGE := [0.03, 0.04, 0.05]

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
	var equivalent_power := float(POWER_GAIN[stage(state)]) * focus(state, "weapon_rate")
	return 1.0 / (1.0 + equivalent_power)


## What this weapon's interval was in the catalogue, before anything was spent
## on it. Stashed on the state when the weapon is built (main._build_weapon_state
## and EvolutionCatalog.build_state) rather than looked up here, because the
## catalogues preload this file and asking them back would close the loop.
static func catalogue_cooldown(state: Dictionary) -> float:
	return float(state.get("base_cooldown", state.get("cooldown", 1.0)))


## The fastest this weapon may be cast from 속도 cards alone.
static func cooldown_floor(state: Dictionary) -> float:
	return maxf(RATE_FLOOR, catalogue_cooldown(state) * RATE_MIN_RATIO)


## The fastest it may be cast once every other source has had its say.
static func interval_floor(state: Dictionary) -> float:
	return maxf(RATE_FLOOR * 0.78, catalogue_cooldown(state) * INTERVAL_MIN_RATIO)


static func next_cooldown(state: Dictionary) -> float:
	return maxf(cooldown_floor(state), float(state["cooldown"]) * rate_step(state))


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


## How big a weapon *is* on the roof, as a multiple of how it looked at Lv.1.
##
## Every card used to change a number and nothing else, so a Lv.12 enhanced
## weapon fired the same eight-pixel ember as a Lv.1 one and the only evidence
## that a run had gone anywhere was the damage text. A weapon now visibly grows
## with it: each level adds a step, the enhancement adds a jump, and the route
## decides which way it grows — 화력 routes (A) put everything into fewer, much
## bigger shots, 속도 routes (B) into more of slightly smaller ones.
##
## Shots carry this into their hit radius as well as their drawing (a shot that
## looks huge and hits like a pellet reads as a bug); blades, rings, bolts and
## beams carry it into their drawing only, since their reach is already a stat.
const PRESENCE_PER_TIER := 0.075
const PRESENCE_ENHANCED := 1.3
const PRESENCE_ROUTE := {"a": 1.25, "b": 0.92}
const PRESENCE_MAX := 3.2


static func presence(state: Dictionary) -> float:
	var value := 1.0 + PRESENCE_PER_TIER * float(maxi(0, int(state.get("tier", 1)) - 1))
	if bool(state.get("evolved", false)):
		value *= PRESENCE_ENHANCED
	value *= float(PRESENCE_ROUTE.get(String(tech(state).get("role", "")), 1.0))
	return minf(PRESENCE_MAX, value)
