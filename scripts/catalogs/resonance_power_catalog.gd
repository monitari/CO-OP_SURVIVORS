extends RefCounted

## What the resonance trade is priced from: how much each enhanced weapon deals
## per second, and how much each resonance deals per cast, both measured on the
## same reference roof.
##
## A resonance absorbs two weapons (ResonanceSystem), and the promise to the pair
## is that the trade is a good one — RESONANCE_PREMIUM times what the two would
## have done. "What the two would have done" cannot be read off a weapon's
## numbers: a lance's 41 damage hits every body on a line, a thunder god's 23
## hits every body on the screen, and a mine's 30 only hits anything once
## something walks onto it. So it is measured instead, by
## `tests/resonance_power_calibration.gd`, which also writes the tables below.
##
## Two fields, because no single one is fair to everything. The crowd is a late
## screen — three packs and a scatter walking in on the pair — and the boss is
## one big body and nothing else. A resonance is priced against both (see
## `multiplier`), so an all-area resonance cannot be sold to a pair on crowd
## numbers and then do nothing to the boss they took it for.
##
## Keys: `weapon_id:tech_id` for weapons (a route changes how a weapon delivers,
## so it changes what it is worth), and ResonanceSystem's id — or `fusion:` plus
## the carrier and the element for a fused one — for resonances. Values are
## `[crowd, boss]`: damage per second for a weapon, damage per cast at a
## resonance multiplier of 1.0 for a resonance.

## GENERATED:BEGIN — rewritten by tests/resonance_power_calibration.gd
const WEAPONS := {
	"absolute_zero:permafrost": [2373.44, 55.28],
	"absolute_zero:shatter": [2531.67, 58.96],
	"black_moon:dance": [2110.23, 48.91],
	"black_moon:execution": [5194.4, 120.4],
	"celestial:ritual": [2303.61, 153.05],
	"celestial:shards": [1467.11, 271.69],
	"cream_tide:downpour": [1912.5, 78.75],
	"cream_tide:tide": [5352.75, 102.38],
	"event_horizon:collapse": [2362.5, 56.25],
	"event_horizon:maelstrom": [3916.25, 97.5],
	"judgement:judgement": [3329.06, 173.91],
	"judgement:prism": [1731.11, 90.43],
	"ruin_garden:demolition": [3297.66, 105.47],
	"ruin_garden:garden": [1884.38, 63.28],
	"skipping_stone:ricochet": [4758.08, 199.5],
	"skipping_stone:tailwind": [4189.5, 133.0],
	"starpiercer:comet": [1864.69, 232.03],
	"starpiercer:pursuit": [1293.75, 235.13],
	"stigmata:tether": [2325.4, 53.9],
	"stigmata:vow": [3322.0, 77.0],
	"supernova:sun": [2789.5, 164.5],
	"supernova:wildfire": [1642.59, 120.09],
	"thunder_god:conductor": [2362.5, 52.5],
	"thunder_god:overload": [4872.66, 108.28],
}
const RESONANCES := {
	"arcane_circuit": [2758.8, 121.0],
	"astral_covenant": [2464.0, 140.8],
	"bonded_mantra": [668.8, 35.2],
	"bright_moon_flurry": [4505.6, 193.6],
	"comet_shower": [1892.0, 176.0],
	"eclipse_tether": [4206.4, 202.4],
	"frost_shade": [3141.6, 211.2],
	"frozen_tether": [2002.0, 66.0],
	"fusion:absolute_zero:arcane": [12206.93, 797.13],
	"fusion:absolute_zero:fire": [7894.66, 638.04],
	"fusion:absolute_zero:frost": [12467.22, 1062.29],
	"fusion:absolute_zero:holy": [7541.11, 638.04],
	"fusion:absolute_zero:lightning": [6034.77, 717.58],
	"fusion:absolute_zero:shadow": [7709.04, 478.94],
	"fusion:black_moon:arcane": [13510.93, 609.19],
	"fusion:black_moon:frost": [12483.99, 745.37],
	"fusion:black_moon:holy": [10661.59, 514.91],
	"fusion:black_moon:lightning": [9810.85, 562.05],
	"fusion:celestial:arcane": [20444.9, 727.78],
	"fusion:celestial:fire": [16639.29, 675.73],
	"fusion:celestial:frost": [19518.62, 1432.55],
	"fusion:celestial:holy": [16501.8, 675.73],
	"fusion:celestial:lightning": [14906.5, 714.53],
	"fusion:celestial:shadow": [15862.46, 598.15],
	"fusion:cream_tide:arcane": [7378.27, 273.34],
	"fusion:cream_tide:fire": [10464.12, 245.84],
	"fusion:cream_tide:holy": [10228.42, 245.84],
	"fusion:cream_tide:lightning": [7072.49, 259.59],
	"fusion:cream_tide:shadow": [8096.65, 218.34],
	"fusion:event_horizon:frost": [15939.2, 496.72],
	"fusion:event_horizon:holy": [10317.12, 336.97],
	"fusion:event_horizon:shadow": [9715.1, 318.31],
	"fusion:judgement:arcane": [4590.64, 636.13],
	"fusion:judgement:fire": [3668.54, 557.57],
	"fusion:judgement:holy": [3668.54, 557.57],
	"fusion:judgement:lightning": [2899.58, 596.85],
	"fusion:judgement:shadow": [3318.27, 479.0],
	"fusion:ruin_garden:arcane": [9269.31, 386.71],
	"fusion:ruin_garden:fire": [8720.45, 373.61],
	"fusion:ruin_garden:holy": [8484.75, 373.61],
	"fusion:ruin_garden:lightning": [7411.54, 339.57],
	"fusion:ruin_garden:shadow": [8516.18, 326.47],
	"fusion:skipping_stone:fire": [8783.6, 958.0],
	"fusion:skipping_stone:frost": [12329.16, 1358.69],
	"fusion:skipping_stone:holy": [8518.44, 958.0],
	"fusion:starpiercer:arcane": [9275.45, 313.02],
	"fusion:starpiercer:fire": [3843.84, 299.27],
	"fusion:starpiercer:frost": [5607.0, 317.6],
	"fusion:starpiercer:holy": [3735.81, 299.27],
	"fusion:starpiercer:lightning": [2716.01, 306.14],
	"fusion:starpiercer:shadow": [3781.31, 285.52],
	"fusion:stigmata:fire": [3936.98, 673.31],
	"fusion:stigmata:frost": [5675.92, 736.16],
	"fusion:stigmata:lightning": [3502.77, 694.26],
	"fusion:supernova:arcane": [12447.07, 291.03],
	"fusion:supernova:fire": [9092.69, 271.39],
	"fusion:supernova:frost": [12366.29, 271.39],
	"fusion:supernova:holy": [8929.01, 271.39],
	"fusion:supernova:lightning": [6604.55, 281.21],
	"fusion:supernova:shadow": [9040.31, 251.75],
	"fusion:thunder_god:frost": [8867.44, 731.6],
	"fusion:thunder_god:holy": [6536.64, 443.52],
	"fusion:thunder_god:shadow": [5649.49, 325.67],
	"glacial_prison": [5390.0, 198.0],
	"guided_bombardment": [915.2, 211.2],
	"guided_thunder": [523.04, 145.2],
	"inferno_crescent": [3801.6, 250.8],
	"inferno_storm": [4329.6, 290.4],
	"sacred_flame_vow": [3746.6, 103.4],
	"singularity": [8712.0, 193.6],
	"starbound_trajectory": [895.73, 132.0],
	"storm_core": [723.79, 72.6],
	"storm_cut_crescent": [2507.4, 264.0],
	"storm_field": [646.8, 215.6],
	"storm_volley": [1706.73, 272.8],
	"thermal_fracture": [5654.0, 136.4],
	"twilight_pursuit": [3759.36, 221.76],
	"umbral_communion": [9248.8, 228.8],
	"warding_garden": [9156.4, 448.8],
}
## GENERATED:END


static func weapon_key(state: Dictionary) -> String:
	return "%s:%s" % [String(state.get("weapon_id", "")), String(state.get("tech_id", ""))]


static func resonance_key(resonance: Dictionary) -> String:
	if String(resonance.get("kind", "")) == "template":
		var carrier := String(resonance.get("carrier", ""))
		if carrier.is_empty():
			carrier = String(ResonanceSystem.BEHAVIOR_TEMPLATES.get(String(resonance.get("behavior", "")), {}).get("carrier", ""))
		return "fusion:%s:%s" % [carrier, String(resonance.get("element", ""))]
	return String(resonance.get("id", ""))


## The weapon's measured output at its catalogue numbers. A weapon or route the
## tables have never seen — a thirteenth weapon added without re-running the
## calibration — is priced at the roster average rather than at zero, so it
## still gets a resonance that is worth having; the data test is what notices
## the gap.
static func weapon_reference(state: Dictionary) -> Array:
	var key := weapon_key(state)
	if WEAPONS.has(key):
		return WEAPONS[key]
	var prefix := String(state.get("weapon_id", "")) + ":"
	var same_weapon: Array = []
	for other: String in WEAPONS:
		if other.begins_with(prefix):
			same_weapon.append(WEAPONS[other])
	return _mean(same_weapon if not same_weapon.is_empty() else WEAPONS.values(), [60.0, 25.0])


static func resonance_reference(resonance: Dictionary) -> Array:
	var key := resonance_key(resonance)
	if RESONANCES.has(key):
		return RESONANCES[key]
	return _mean(RESONANCES.values(), [300.0, 120.0])


## The damage multiplier a resonance is cast at, given what its two absorbed
## weapons deal per second right now (their measured reference grown by
## everything spent on them since) in each field.
##
## RESONANCE_PREMIUM applies to a weighted geometric mean of what the two
## fields ask for (CROWD_WEIGHT), so a resonance strong in one and weak in the
## other is priced for both;
## RESONANCE_FLOOR then guarantees it beats the two weapons even in the field it
## is worst in. Without the floor, a resonance that is all area would be allowed
## to lose to the weapons it replaced against a lone boss.
static func multiplier(weapons_crowd: float, weapons_boss: float, resonance: Dictionary) -> float:
	var cooldown := float(resonance.get("cooldown", 5.0))
	var cast := resonance_reference(resonance)
	# A field the resonance measured (next to) nothing on cannot price it: the
	# multiplier that field asks for is unbounded, and taking it would make the
	# resonance astronomically strong everywhere else. The data test refuses a
	# zero reference; this keeps a near-zero one from doing damage in the
	# meantime by pricing from the field that did measure.
	var crowd_valid := float(cast[0]) >= MIN_REFERENCE
	var boss_valid := float(cast[1]) >= MIN_REFERENCE
	var need_crowd := weapons_crowd * cooldown / maxf(MIN_REFERENCE, float(cast[0]))
	var need_boss := weapons_boss * cooldown / maxf(MIN_REFERENCE, float(cast[1]))
	if not boss_valid:
		need_boss = need_crowd
	if not crowd_valid:
		need_crowd = need_boss
	var balanced := pow(need_crowd, CROWD_WEIGHT) * pow(need_boss, 1.0 - CROWD_WEIGHT)
	var priced := minf(ResonanceSystem.RESONANCE_PREMIUM * balanced, CEILING * minf(need_crowd, need_boss))
	return maxf(priced, ResonanceSystem.RESONANCE_FLOOR * maxf(need_crowd, need_boss))


## Below this a measured reference is treated as "did not land at all".
const MIN_REFERENCE := 1.0
## How much of the balance between the two fields is decided by the crowd. Most
## of a late run is a crowd and five minutes of it is a boss, so the premium is
## mostly spent where the pair spend their time, while the floor still keeps the
## resonance ahead of its weapons on the boss.
const CROWD_WEIGHT := 0.65
## And the most a resonance may out-deal its two weapons in the field it is best
## in, so a boss-killer paired with two crowd weapons does not end a boss in a
## single cast. The floor wins where the two disagree: the promise that the
## trade is never a loss matters more than the promise that it is never lopsided.
const CEILING := 4.0


static func _mean(entries: Array, fallback: Array) -> Array:
	if entries.is_empty():
		return fallback
	var crowd := 0.0
	var boss := 0.0
	for entry: Array in entries:
		crowd += float(entry[0])
		boss += float(entry[1])
	return [crowd / entries.size(), boss / entries.size()]
