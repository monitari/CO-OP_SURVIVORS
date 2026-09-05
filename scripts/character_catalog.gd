class_name CharacterCatalog
extends RefCounted

## The survivors are cats bound together by a magic chain; each entry's title
## and description carry that, while the numbers below carry the balance.
##
## Every survivor is budgeted rather than hand-tuned, because the roster is
## meant to grow and "does the new one feel fair?" is not a question anyone can
## answer by staring at ten dictionaries.
##
## The roster used to differ only in health (92-115) and speed (205-242) — a
## 25% spread on one axis and 18% on another, which is not a choice, it is a
## rounding error. There are now six axes and every one of them is wide enough
## to feel, guarded by SPREAD_FLOORS below:
##
##   health   78 - 165   how many mistakes the run affords
##   speed    152 - 288  whether you can leave
##   armor    0 - 4      flat damage shaved off every hit; a wall stat
##   crit     0 - 0.30   a spike stat that trades away bulk
##   pickup   0.7 - 1.7  the pair's shared magnet radius, averaged over both
##   chain    -35 - +85  this cat's contribution to the leash length
##
## `chain` is the one that changes how the game is played rather than how the
## numbers land: two short-leash cats fight at 275px and can never split, two
## anchors fight at 480px and can cover twice the field. It is picked at
## character select and never seen again as a stat screen, only as the length
## of the rope on the floor.
##
## Fairness is one budget over all six axes rather than a band per axis, since
## a band per axis is exactly what forced the old flat roster. A survivor may
## be extreme on any axis as long as it pays for it somewhere else:
##
##   defense  = health/100 + armor*0.10
##   mobility = speed/230 + chain/700
##   offense  = damage/cooldown*reach/34 * (1 + crit*1.5)
##   utility  = pickup*0.32
##
## tests/survivor_balance_test.gd asserts the sum lands in TOTAL_BUDGET_MIN..MAX
## and, separately, that the roster still spreads across every axis — because a
## budget alone is perfectly happy with ten identical cats.

const TOTAL_BUDGET_MIN := 3.90
const TOTAL_BUDGET_MAX := 4.00

## Minimum roster spread per axis: max/min for the ratio axes, max-min for the
## additive ones. These encode "the survivors are actually different" as a
## thing that fails a test rather than a thing someone remembers.
const SPREAD_FLOORS := {
	"health": 1.9, ## ratio
	"speed": 1.6, ## ratio
	"armor": 3.0, ## difference
	"crit": 0.2, ## difference
	"pickup": 2.0, ## ratio
	"chain": 100.0, ## difference, pixels
}

## Base leash before either survivor's contribution. The pair's actual chain is
## this plus both `chain` values, so the run's defining constraint is decided at
## character select.
const CHAIN_BASE_LENGTH := 330.0


static func defense_budget(character: Dictionary) -> float:
	return float(character["health"]) / 100.0 + float(character["armor"]) * 0.10


static func mobility_budget(character: Dictionary) -> float:
	return float(character["speed"]) / 230.0 + float(character["chain"]) / 700.0


static func offense_budget(character: Dictionary) -> float:
	var weapon: Dictionary = character["weapon"]
	var raw := float(weapon["damage"]) / float(weapon["cooldown"]) * float(weapon["reach"])
	# Persistent weapons buy several seconds of board control with one cast.
	# Their catalog cooldown now describes that real cast cycle, so the roster
	# budget prices the active window/lasting trap rather than pretending they
	# are one-frame hits.
	if character["weapon_id"] == "orbit": raw *= 4.8
	if character["weapon_id"] == "mine": raw *= 1.42
	return raw / 34.0 * (1.0 + float(character["crit"]) * 1.5)


static func utility_budget(character: Dictionary) -> float:
	return float(character["pickup"]) * 0.32


static func total_budget(character: Dictionary) -> float:
	return (defense_budget(character) + mobility_budget(character)
		+ offense_budget(character) + utility_budget(character))


## Kept because the power band is still the honest read on a weapon in
## isolation, which is what the fusion and treasure tuning compares against.
static func power_budget(character: Dictionary) -> float:
	var weapon: Dictionary = character["weapon"]
	return float(weapon["damage"]) / float(weapon["cooldown"]) * float(weapon["reach"])


## The leash two picked survivors end up sharing.
static func chain_length_for(first: Dictionary, second: Dictionary) -> float:
	return CHAIN_BASE_LENGTH + float(first["chain"]) + float(second["chain"])


## How demanding a survivor is to play, as a continuous read rather than a set
## of threshold flips, normalised against the roster's own spread so adding a
## survivor recalibrates the scale instead of breaking it.
##
##   coverage   how much one cast handles, from `reach` — the difference between
##              being surrounded and clearing the ring
##   durability how much a mistake costs, from health *and* armor: 4 armor is
##              worth roughly 48 health against the contact hits that actually
##              kill pairs, and ignoring it made the wall cats read as fragile
##   mobility   whether you can leave, from speed and the leash this cat brings
##
## Coverage is weighted heaviest because being surrounded is what kills pairs;
## mobility is lightest because the chain caps how far either cat can run anyway.
const DIFFICULTY_WEIGHTS := {"coverage": 0.45, "durability": 0.35, "mobility": 0.20}
const ARMOR_AS_HEALTH := 12.0
const CHAIN_AS_SPEED := 0.6


static func effective_health(character: Dictionary) -> float:
	return float(character["health"]) + float(character["armor"]) * ARMOR_AS_HEALTH


static func effective_mobility(character: Dictionary) -> float:
	return float(character["speed"]) + float(character["chain"]) * CHAIN_AS_SPEED


static func difficulty_profile(character: Dictionary) -> Dictionary:
	var roster := all_characters()
	var coverage := _normalise(float((character["weapon"] as Dictionary)["reach"]), _span(roster, "reach"))
	var durability := _normalise(effective_health(character), _span(roster, "effective_health"))
	var mobility := _normalise(effective_mobility(character), _span(roster, "effective_mobility"))
	var ease := (
		coverage * float(DIFFICULTY_WEIGHTS["coverage"])
		+ durability * float(DIFFICULTY_WEIGHTS["durability"])
		+ mobility * float(DIFFICULTY_WEIGHTS["mobility"])
	)
	return {
		"coverage": coverage,
		"durability": durability,
		"mobility": mobility,
		"ease": ease,
		"rating": difficulty_from_ease(ease),
		"headline": _difficulty_headline(character, coverage, durability, mobility),
	}


## 1 (easiest) to 5. Five bands rather than three because ten survivors spread
## across three grades left seven of them labelled the same thing.
static func difficulty_from_ease(ease: float) -> int:
	return clampi(5 - int(floor(ease * 5.0)), 1, 5)


static func difficulty(character: Dictionary) -> int:
	return int(difficulty_profile(character)["rating"])


static func difficulty_stars(character: Dictionary) -> String:
	var rating := difficulty(character)
	return "★".repeat(rating) + "☆".repeat(5 - rating)


static func difficulty_label(character: Dictionary) -> String:
	match difficulty(character):
		1:
			return "아주 쉬움"
		2:
			return "쉬움"
		3:
			return "보통"
		4:
			return "어려움"
		_:
			return "매우 어려움"


static func difficulty_reason(character: Dictionary) -> String:
	return String(difficulty_profile(character)["headline"])


## Names the axis that actually makes this survivor hard, rather than reciting
## all three. Whichever normalised value is lowest is the one the player will
## feel first — with a special case for the leash, because a short chain is felt
## by both players at once and no amount of speed makes up for it.
static func _difficulty_headline(character: Dictionary, coverage: float, durability: float, mobility: float) -> String:
	if float(character["chain"]) <= -25.0:
		return "사슬이 짧아 둘이 붙어 다녀야 합니다"
	var weakest := minf(coverage, minf(durability, mobility))
	if weakest > 0.55:
		return "약점이 뚜렷하지 않아 무난합니다"
	if is_equal_approx(weakest, coverage):
		return "한 번에 처리하는 수가 적어 포위에 약합니다"
	if is_equal_approx(weakest, durability):
		return "한 대가 크게 아파 실수를 아낄 수 없습니다"
	return "느려서 위치를 미리 잡아 두어야 합니다"


## The stats the select screen shows, in the order it shows them, each with the
## upgrade glyph that already stands for that idea elsewhere in the game.
const DISPLAYED_STATS := [
	{"field": "health", "name": "체력", "icon": "vitality"},
	{"field": "speed", "name": "이속", "icon": "move"},
	{"field": "might", "name": "위력", "icon": "might"},
	{"field": "haste", "name": "공속", "icon": "haste"},
	{"field": "armor", "name": "방어", "icon": "armor"},
	{"field": "crit", "name": "치명", "icon": "crit"},
	{"field": "area", "name": "범위", "icon": "area"},
	{"field": "recovery", "name": "재생", "icon": "recovery"},
]


## One stat as the select screen prints it. Units matter here: a raw 1.35 or a
## raw -20 tells a player nothing, while "135%" and "-20" against a leash they
## can see on the floor tell them what the pick actually costs.
static func stat_text(character: Dictionary, field: String) -> String:
	match field:
		"health":
			return "체력 %.0f" % float(character["health"])
		"speed":
			return "이속 %.0f" % float(character["speed"])
		"armor":
			return "방어 %.0f" % float(character["armor"])
		"crit":
			return "치명 %.0f%%" % (float(character["crit"]) * 100.0)
		"might":
			return "위력 %.0f%%" % (float(character["might"]) * 100.0)
		"haste":
			return "공속 %.0f%%" % (100.0 / float(character["haste"]))
		"area":
			return "범위 %.0f%%" % (float(character["area"]) * 100.0)
		"recovery":
			return "재생 %.1f" % float(character["recovery"])
		"pickup":
			return "자력 %.0f%%" % (float(character["pickup"]) * 100.0)
		_:
			return "사슬 %+.0f" % float(character["chain"])


static func _span(roster: Array[Dictionary], field: String) -> Vector2:
	var low := INF
	var high := -INF
	for character in roster:
		var value := _field_value(character, field)
		low = minf(low, value)
		high = maxf(high, value)
	return Vector2(low, high)


static func _field_value(character: Dictionary, field: String) -> float:
	match field:
		"reach":
			return float((character["weapon"] as Dictionary)["reach"])
		"effective_health":
			return effective_health(character)
		"effective_mobility":
			return effective_mobility(character)
		_:
			return float(character[field])


static func _normalise(value: float, span: Vector2) -> float:
	if is_equal_approx(span.y, span.x):
		return 0.5
	return clampf((value - span.x) / (span.y - span.x), 0.0, 1.0)


static func all_characters() -> Array[Dictionary]:
	return [
		{
			"id": "lyra",
			"name": "라이라",
			"title": "별을 쫓는 러시안블루",
			"weapon_id": "homing",
			"weapon_name": "추적 성탄",
			"tags": ["projectile", "tracking", "arcane"],
			"description": "밤하늘을 보고 앞발을 뻗으면 별똥이 알아서 목표를 찾아갑니다.",
			"color": Color("43d9ff"),
			# The roster's glass cannon: fastest cat, highest crit, and the
			# thinnest health bar on the team. Every point she spends is spent
			# on killing things before they arrive.
			"health": 78.0,
			"speed": 288.0,
			"armor": 0.0,
			"crit": 0.30,
			"pickup": 1.35,
			"chain": -20.0,
			"might": 1.12, "area": 0.86, "haste": 0.90, "recovery": 0.0,
			"projectile_speed": 1.18, "dodge": 0.06,
			"weapon": {"damage": 33.0, "cooldown": 0.92, "count": 1, "speed": 470.0, "reach": 1.0, "tier": 1}
		},
		{
			"id": "volta",
			"name": "볼타",
			"title": "번개 밟는 턱시도",
			"weapon_id": "lightning",
			"weapon_name": "연쇄 낙뢰",
			"tags": ["lightning", "storm", "chain"],
			"description": "정전기를 잔뜩 머금은 털이 가까운 것들을 차례로 타고 흐릅니다.",
			"color": Color("b892ff"),
			"health": 110.0,
			"speed": 262.0,
			"armor": 1.0,
			"crit": 0.10,
			"pickup": 1.1,
			"chain": 10.0,
			"might": 1.0, "area": 1.08, "haste": 0.96, "recovery": 0.2,
			"weapon": {"damage": 24.0, "cooldown": 1.45, "jumps": 3, "range": 440.0, "reach": 2.2, "tier": 1}
		},
		{
			"id": "ignis",
			"name": "이그니스",
			"title": "잿불 위의 치즈",
			"weapon_id": "flame",
			"weapon_name": "화염 성운",
			"tags": ["fire", "projectile", "burst"],
			"description": "따뜻한 자리를 독차지하려고 사방으로 불씨를 흩뿌립니다.",
			"color": Color("ff8c42"),
			"health": 138.0,
			"speed": 198.0,
			"armor": 2.0,
			"crit": 0.04,
			"pickup": 1.0,
			"chain": 25.0,
			"might": 1.08, "area": 1.12, "haste": 1.08, "recovery": 0.25,
			# Radial shots trade reliability for coverage. Nine slightly stronger
			# embers give the starting version enough intersections to finish a
			# basic enemy before the ring has already closed on both survivors.
			"weapon": {"damage": 23.5, "cooldown": 1.65, "count": 9, "speed": 315.0, "reach": 2.6, "tier": 1}
		},
		{
			"id": "neve",
			"name": "네베",
			"title": "서리 두른 하양이",
			"weapon_id": "frost",
			"weapon_name": "빙결 고리",
			"tags": ["frost", "control", "aura"],
			"description": "숨을 뱉으면 주변이 얼어붙어 둘이 앉을 자리가 생깁니다.",
			"color": Color("8ecae6"),
			"health": 126.0,
			"speed": 186.0,
			"armor": 4.0,
			"crit": 0.0,
			"pickup": 1.0,
			"chain": 65.0,
			"might": 0.90, "area": 1.25, "haste": 1.10, "recovery": 0.9,
			"resolve": 2.0,
			"weapon": {"damage": 19.0, "cooldown": 2.1, "radius": 135.0, "slow": 0.52, "reach": 4.0, "tier": 1}
		},
		{
			"id": "moro",
			"name": "모로",
			"title": "달그림자 삼색",
			"weapon_id": "scythe",
			"weapon_name": "월식 낫",
			"tags": ["melee", "shadow", "arc"],
			"description": "노리던 쪽으로 몸을 틀어 초승달 모양으로 크게 할큅니다.",
			"color": Color("ef476f"),
			# The shortest leash on the roster. Moro fights at claw range and
			# drags a partner in with them, which is either the best thing about
			# the pick or the worst.
			"health": 104.0,
			"speed": 262.0,
			"armor": 1.0,
			"crit": 0.16,
			"pickup": 0.95,
			"chain": -35.0,
			"might": 1.16, "area": 0.90, "haste": 0.92, "recovery": 0.1,
			"dodge": 0.04,
			# Melee carries a low reach factor because it only hits what you face,
			# so it is allowed a much higher per-swing number than the auras.
			"weapon": {"damage": 45.0, "cooldown": 1.35, "range": 220.0, "arc": 2.1, "reach": 1.15, "tier": 1}
		},
		{
			"id": "serin",
			"name": "세린",
			"title": "사슬을 지키는 젖소",
			"weapon_id": "chain",
			"weapon_name": "결속 파동",
			"tags": ["tether", "holy", "aura"],
			"description": "골골거리는 소리가 사슬을 타고 흘러 닿는 것을 모두 태웁니다.",
			"color": Color("80ed99"),
			# The anchor: twice Lyra's health, half her speed, and the longest
			# leash in the game. A Serin run is played by standing somewhere on
			# purpose and letting the partner range.
			"health": 165.0,
			"speed": 152.0,
			# 1, not 2: the raw health bar and the leash are already the most
			# expensive things on the roster, and Serin has to pay for them.
			"armor": 1.0,
			"crit": 0.0,
			"pickup": 0.7,
			"chain": 85.0,
			"might": 0.88, "area": 1.0, "haste": 1.08, "recovery": 1.3,
			"thorns": 0.10, "resolve": 3.0,
			"weapon": {"damage": 34.0, "cooldown": 1.35, "width": 58.0, "reach": 1.6, "tier": 1}
		},
		{
			"id": "kael",
			"name": "카일",
			"title": "궤도를 도는 노랑둥이",
			"weapon_id": "orbit",
			"weapon_name": "궤도 파편",
			"tags": ["arcane", "aura", "control"],
			"description": "장난감처럼 파편 몇 개를 계속 굴려 다가오는 것을 알아서 쳐냅니다.",
			"color": Color("ffd166"),
			"health": 120.0,
			"speed": 214.0,
			"armor": 3.0,
			"crit": 0.02,
			"pickup": 1.3,
			"chain": 20.0,
			"might": 0.94, "area": 1.12, "haste": 0.92, "recovery": 0.3,
			"amount": 1,
			# Orbiting shards hit whatever walks into them without any aiming at
			# all, so the per-shard number is small and reach carries the weight.
			"weapon": {"damage": 12.5, "cooldown": 5.4, "count": 3, "radius": 96.0, "speed": 3.15, "reach": 3.2, "tier": 1}
		},
		{
			"id": "rian",
			"name": "리안",
			"title": "빛을 꿰는 샴",
			"weapon_id": "lance",
			"weapon_name": "관통 광선",
			"tags": ["projectile", "holy", "burst"],
			"description": "노린 것을 한 줄로 세워 앞발 한 번에 전부 꿰뚫습니다.",
			"color": Color("caffbf"),
			"health": 88.0,
			"speed": 274.0,
			"armor": 0.0,
			"crit": 0.24,
			"pickup": 1.2,
			"chain": 15.0,
			"might": 1.10, "area": 0.82, "haste": 1.0, "recovery": 0.0,
			"projectile_speed": 1.25, "pierce": 1,
			"weapon": {"damage": 46.0, "cooldown": 1.55, "range": 520.0, "width": 34.0, "beams": 1, "reach": 1.25, "tier": 1}
		},
		{
			"id": "tera",
			"name": "테라",
			"title": "결계를 놓는 고등어",
			"weapon_id": "mine",
			"weapon_name": "지뢰 결계",
			"tags": ["control", "burst", "shadow"],
			"description": "지나가는 길목마다 발자국 결계를 묻어 두고 돌아섭니다.",
			"color": Color("bdb2ff"),
			"health": 135.0,
			"speed": 190.0,
			"armor": 3.0,
			"crit": 0.0,
			"pickup": 1.05,
			"chain": 40.0,
			"might": 0.98, "area": 1.16, "haste": 1.10, "recovery": 0.7,
			"resolve": 2.0,
			"weapon": {"damage": 41.0, "cooldown": 3.0, "count": 1, "radius": 96.0, "reach": 1.9, "tier": 1}
		},
		{
			"id": "nova",
			"name": "노바",
			"title": "무너뜨리는 카오스",
			"weapon_id": "gravity",
			"weapon_name": "중력 붕괴",
			"tags": ["arcane", "storm", "control"],
			"description": "멀리 몰려 있는 쪽을 골라 그 자리를 통째로 주저앉힙니다.",
			"color": Color("ff7bd5"),
			# Nova's identity is the pull, and not only the one the weapon casts:
			# the biggest pickup radius on the roster means a Nova pair farms a
			# whole screen of gems without walking to any of them.
			"health": 105.0,
			"speed": 240.0,
			"armor": 1.0,
			"crit": 0.08,
			"pickup": 1.7,
			"chain": 5.0,
			"might": 1.0, "area": 1.20, "haste": 1.05, "recovery": 0.2,
			"projectile_speed": 0.90,
			"weapon": {"damage": 26.0, "cooldown": 2.35, "radius": 210.0, "pull": 160.0, "cast_range": 520.0, "reach": 3.3, "tier": 1}
		}
	]
