class_name CharacterCatalog
extends RefCounted

## The survivors are cats bound together by a magic chain; each entry's title
## and description carry that, while the numbers below carry the balance.
##
## Every survivor is budgeted rather than hand-tuned, because the roster is
## meant to grow and "does the new one feel fair?" is not a question anyone can
## answer by staring at six dictionaries.
##
## Two budgets, both checked by tests/survivor_balance_test.gd:
##
##   survival = health / 100 + speed / 220
##       Toughness and mobility trade against each other. Serin is the wall,
##       Lyra is the runner, and they cost the same.
##
##   power = damage / cooldown * reach
##       `reach` is declared per weapon and says how much of a cast actually
##       lands: a frost aura hits everything around both survivors, a homing
##       bolt hits one thing, a scythe only hits what you are facing. Without
##       it raw DPS makes the aura weapons look worthless and the melee ones
##       look broken.
##
## A new survivor is balanced when both budgets land inside the bands the test
## asserts. Adjust `reach` only when a weapon's delivery actually changes.

const SURVIVAL_BUDGET_MIN := 1.95
const SURVIVAL_BUDGET_MAX := 2.15
const POWER_BUDGET_MIN := 33.0
const POWER_BUDGET_MAX := 41.0


static func survival_budget(character: Dictionary) -> float:
	return float(character["health"]) / 100.0 + float(character["speed"]) / 220.0


## How hard this survivor is to play well, on a 1-3 scale, derived from the two
## numbers that actually decide it rather than declared by hand.
##
## `reach` is the honest measure of positioning demand: every weapon aims itself
## now, so the question is no longer "can you point it" but "how much of the
## field does one cast cover". A low-reach weapon kills one thing at a time,
## which means being surrounded is fatal and the pair has to keep moving. Low
## health compounds that, because the same mistake costs more.
## How demanding a survivor is to play, as a continuous read rather than two
## threshold flips.
##
## The old version was `reach < 1.4` plus `health < 100`, which made 99 health a
## whole grade harder than 100 and ignored speed entirely. It also had nothing to
## say when the roster grew — every new survivor had to be hand-fitted around
## those two constants.
##
## Each axis is now normalised against the roster's own spread, so adding a
## survivor recalibrates the scale instead of breaking it, and the three axes are
## the three ways a run actually goes wrong:
##
##   coverage   how much one cast handles, from `reach` — the difference between
##              being surrounded and clearing the ring
##   durability how much a mistake costs, from health
##   mobility   whether you can leave, from speed
##
## Coverage is weighted heaviest because being surrounded is what kills pairs;
## mobility is lightest because the chain caps how far either cat can run anyway.
const DIFFICULTY_WEIGHTS := {"coverage": 0.5, "durability": 0.3, "mobility": 0.2}


static func difficulty_profile(character: Dictionary) -> Dictionary:
	var roster := all_characters()
	var reach_span := _span(roster, "reach")
	var health_span := _span(roster, "health")
	var speed_span := _span(roster, "speed")

	var coverage := _normalise(float((character["weapon"] as Dictionary)["reach"]), reach_span)
	var durability := _normalise(float(character["health"]), health_span)
	var mobility := _normalise(float(character["speed"]), speed_span)
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
		"headline": _difficulty_headline(coverage, durability, mobility),
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
## feel first.
static func _difficulty_headline(coverage: float, durability: float, mobility: float) -> String:
	var weakest := minf(coverage, minf(durability, mobility))
	if weakest > 0.55:
		return "약점이 뚜렷하지 않아 무난합니다"
	if is_equal_approx(weakest, coverage):
		return "한 번에 처리하는 수가 적어 포위에 약합니다"
	if is_equal_approx(weakest, durability):
		return "한 대가 크게 아파 실수를 아낄 수 없습니다"
	return "느려서 위치를 미리 잡아 두어야 합니다"


static func _span(roster: Array[Dictionary], field: String) -> Vector2:
	var low := INF
	var high := -INF
	for character in roster:
		var value := float((character["weapon"] as Dictionary)["reach"]) if field == "reach" else float(character[field])
		low = minf(low, value)
		high = maxf(high, value)
	return Vector2(low, high)


static func _normalise(value: float, span: Vector2) -> float:
	if is_equal_approx(span.y, span.x):
		return 0.5
	return clampf((value - span.x) / (span.y - span.x), 0.0, 1.0)


static func power_budget(character: Dictionary) -> float:
	var weapon: Dictionary = character["weapon"]
	return float(weapon["damage"]) / float(weapon["cooldown"]) * float(weapon["reach"])



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
			"health": 95.0,
			"speed": 240.0,
			"weapon": {"damage": 22.0, "cooldown": 0.62, "count": 1, "speed": 470.0, "reach": 1.0, "tier": 1}
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
			# 90 health put Volta under the survival budget every other survivor sits on.
			"health": 95.0,
			"speed": 235.0,
			"weapon": {"damage": 18.0, "cooldown": 1.08, "jumps": 3, "range": 440.0, "reach": 2.2, "tier": 1}
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
			"health": 110.0,
			"speed": 215.0,
			# Radial shots trade reliability for coverage. Nine slightly stronger
			# embers give the starting version enough intersections to finish a
			# basic enemy before the ring has already closed on both survivors.
			"weapon": {"damage": 17.0, "cooldown": 1.2, "count": 9, "speed": 315.0, "reach": 2.6, "tier": 1}
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
			"health": 100.0,
			"speed": 225.0,
			"weapon": {"damage": 14.0, "cooldown": 1.55, "radius": 185.0, "slow": 0.52, "reach": 4.0, "tier": 1}
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
			"health": 102.0,
			"speed": 230.0,
			# Melee carries a low reach factor because it only hits what you face,
			# so it is allowed a much higher per-swing number than the auras.
			"weapon": {"damage": 33.0, "cooldown": 0.98, "range": 220.0, "arc": 2.1, "reach": 1.15, "tier": 1}
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
			"health": 115.0,
			"speed": 205.0,
			"weapon": {"damage": 24.0, "cooldown": 0.95, "width": 58.0, "reach": 1.5, "tier": 1}
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
			"health": 108.0,
			"speed": 218.0,
			# Orbiting shards hit whatever walks into them without any aiming at
			# all, so the per-shard number is small and reach carries the weight.
			"weapon": {"damage": 11.0, "cooldown": 1.0, "count": 3, "radius": 96.0, "speed": 2.4, "reach": 3.2, "tier": 1}
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
			"health": 92.0,
			"speed": 242.0,
			"weapon": {"damage": 34.0, "cooldown": 1.15, "range": 520.0, "width": 34.0, "reach": 1.25, "tier": 1}
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
			"health": 112.0,
			"speed": 212.0,
			"weapon": {"damage": 26.0, "cooldown": 1.35, "count": 1, "radius": 84.0, "reach": 1.9, "tier": 1}
		},
		{
			"id": "nova",
			"name": "노바",
			"title": "무너뜨리는 카오스",
			"weapon_id": "gravity",
			"weapon_name": "중력 붕괴",
			"tags": ["arcane", "storm", "control"],
			"description": "한곳으로 몰아 뭉친 뒤 그 자리를 통째로 주저앉힙니다.",
			"color": Color("ff7bd5"),
			"health": 96.0,
			"speed": 232.0,
			"weapon": {"damage": 19.0, "cooldown": 1.7, "radius": 210.0, "pull": 160.0, "reach": 3.3, "tier": 1}
		}
	]
