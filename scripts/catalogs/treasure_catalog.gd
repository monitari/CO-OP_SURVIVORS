class_name TreasureCatalog
extends RefCounted

## Attributes used to be free-floating level-up cards: all twelve were always in
## the pool, every one of them stacked without limit, and a build was therefore
## just a record of what happened to come up. They are now treasures. A survivor
## carries at most TREASURE_LOADOUT_CAP of them and can only deepen the ones
## they already hold, so the first sight of a treasure is a real decision and a
## finished build is something the pair chose rather than something that
## accumulated.
##
## The ids deliberately match the attribute names main.gd already applies and
## the filenames under assets/sprites/upgrades/, so every treasure has an icon
## and an effect without either being defined twice.

## Six tiers was the whole of a treasure's life, and with four slots a survivor
## had bought everything a treasure could ever give them well before the run was
## over. Ten gives the second half of a run something to spend levels on.
const MAX_TIER := 10

## What each tier is worth as a share of a treasure's `value`. Every tier used to
## pay the same, so the first pick of a treasure was as strong as the last and a
## treasure was front-loaded like everything else in a build. The first tiers are
## now light and the last ones heavy: taking a treasure is a promise, deepening
## it is where it pays. The weighted total catches the old flat ladder at tier 7
## and finishes a fifth above it; at the enhancement gate (tier 4) it is worth
## 3.25 × value instead of 4.
##
## Treasures that pace the run rather than power it — experience, pickup range,
## drop chance — stay flat (`flat`). Weighting them slowed every level-up of the
## early game, which compounds into a whole run of fewer cards and was measured
## costing the late game half its damage.
const TIER_WEIGHTS := [0.6, 0.75, 0.9, 1.0, 1.1, 1.25, 1.4, 1.55, 1.7, 1.85]


static func all_treasures() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"id": "might", "name": "격노의 인장", "shared": false, "stat": "공격",
			"value": 0.09, "display": 100.0, "text": "공격력 +{v}%"},
		{"id": "area", "name": "확장의 렌즈", "shared": false, "stat": "범위",
			"value": 0.09, "display": 100.0, "text": "공격 범위 +{v}%"},
		# Half a projectile per tier, accumulated on the survivor and floored where
		# a volley is actually counted. At a whole one per tier this was +10 shots
		# on every count weapon in the game by the end of a run — eleven times the
		# volley of a weapon that fires one — and between that and uncapped 발사 수
		# cards it was the main reason the late game became a wall of projectiles.
		# The text says the cadence rather than the step, because "발사체 +0.50" is
		# a number no player can act on.
		{"id": "amount", "name": "분열의 화살통", "shared": false, "stat": "탄량",
			"value": 0.5, "flat": true, "text": "두 단계마다 발사체 +1"},
		{"id": "haste", "name": "질풍의 태엽", "shared": false, "stat": "신속",
			"value": 0.05, "display": 100.0, "text": "발동 간격 -{v}%"},
		{"id": "projectile_speed", "name": "가속의 깃", "shared": false, "stat": "탄속",
			"value": 0.10, "display": 100.0, "text": "발사체 속도 +{v}%"},
		{"id": "duration", "name": "달빛 모래시계", "shared": false, "stat": "지속",
			"value": 0.10, "display": 100.0, "text": "투사체  장판 지속시간 +{v}%"},
		{"id": "armor", "name": "수호의 갑주", "shared": false, "stat": "방어",
			"value": 1.5, "text": "받는 피해 -{v}"},
		{"id": "recovery", "name": "재생의 성수", "shared": false, "stat": "재생",
			"value": 0.5, "text": "초당 회복 +{v}"},
		{"id": "move", "name": "경보의 장화", "shared": false, "stat": "이동",
			"value": 0.05, "display": 100.0, "text": "이동 속도 +{v}%"},
		{"id": "vitality", "name": "생명의 결정", "shared": false, "stat": "체력",
			"value": 12.0, "text": "최대 체력 +{v}"},
		# Added with the evolution pass. These are the treasures the fused weapons
		# require, so a survivor picking one is also picking a tech tree branch.
		{"id": "crit", "name": "처형자의 표식", "shared": false, "stat": "치명",
			"value": 0.05, "display": 100.0, "text": "치명타 확률 +{v}%p"},
		{"id": "pierce", "name": "관통의 송곳", "shared": false, "stat": "관통",
			"value": 1.0, "flat": true, "text": "발사체 관통 +{v}"},
		{"id": "thorns", "name": "가시의 견장", "shared": false, "stat": "가시",
			"value": 0.10, "display": 100.0, "text": "접촉 피해 {v}% 반사"},
		{"id": "resolve", "name": "불굴의 부적", "shared": false, "stat": "불굴",
			"value": 3.0, "text": "출혈 시간 +{v}초, 구조 속도 증가"},
		# The shared ones change a team resource rather than the carrier, so one
		# survivor holding them benefits both. They stay in the same pool on
		# purpose: giving up a personal slot for a team effect is the trade.
		{"id": "overcharge", "name": "과충전 코어", "shared": true, "stat": "과충전",
			"value": 0.06, "display": 100.0, "text": "과충전 피해 +{v}%, 내구도 소모 감소"},
		{"id": "greed", "name": "탐욕의 저울", "shared": true, "stat": "탐욕",
			"value": 0.30, "flat": true, "display": 100.0, "text": "필드 아이템 확률 +{v}%"},
		{"id": "magnet", "name": "인력의 나침반", "shared": true, "stat": "자석",
			"value": 0.20, "flat": true, "display": 100.0, "text": "공유 획득 범위 +{v}%"},
		# Halved with the 2026-09-19 pass; see main._recompute_team_effects for
		# why. The card's own number has to move with the effect or the card
		# starts lying about what it gives.
		{"id": "growth", "name": "성장의 서", "shared": true, "stat": "성장",
			"value": 0.05, "flat": true, "display": 100.0, "text": "공유 경험치 +{v}%"},
		{"id": "luck", "name": "행운의 주사위", "shared": true, "stat": "행운",
			"value": 1.0, "flat": true, "text": "공유 행운 +{v}"},
		{"id": "lifesteal", "name": "진홍 목방울", "shared": true, "stat": "흡혈",
			"value": 0.006, "display": 100.0, "text": "가한 피해 {v}%를 팀 체력으로 회복    초당 최대 1.5"},
		{"id": "catnip", "name": "별빛 캣닢", "shared": true, "stat": "성장 회복",
			"value": 0.04, "display": 100.0, "text": "레벨업마다 둘 다 최대 체력의 {v}% 회복"},
		{"id": "bounty_bell", "name": "사냥꾼 방울", "shared": true, "stat": "강적 경험치",
			"value": 0.18, "flat": true, "display": 100.0, "text": "엘리트  보스 경험치 +{v}%"},
		{"id": "twin_charm", "name": "쌍둥이 부적", "shared": true, "stat": "밀착 화력",
			"value": 0.05, "display": 100.0, "text": "사슬 거리 45% 이내일 때 피해 +{v}%"},
		{"id": "dash_claw", "name": "질주 발톱", "shared": true, "stat": "대시 공격",
			"value": 11.0, "text": "대시 시작점에 피해 {v} 충격파"},
		{"id": "lucky_paw", "name": "행운의 앞발", "shared": false, "stat": "회피",
			"value": 0.035, "display": 100.0, "text": "피해를 무시할 확률 +{v}%"},
		{"id": "nine_lives", "name": "아홉 목숨 리본", "shared": false, "stat": "기사회생",
			"value": 1.0, "flat": true, "text": "치명타를 1회 막고 체력 28% 회복"},
	]
	for treasure in result:
		# What taking it right now gives. Kept under the old key because the
		# carried state and the card body both read it.
		treasure["per_tier"] = tier_text(treasure, 1)
	return result


static func by_id(treasure_id: String) -> Dictionary:
	for treasure in all_treasures():
		if String(treasure["id"]) == treasure_id:
			return treasure
	return {}


## Share of `value` the step *into* this tier pays.
static func tier_weight(tier: int) -> float:
	return float(TIER_WEIGHTS[clampi(tier, 1, MAX_TIER) - 1])


## Total shares a treasure held at `tier` is worth.
static func cumulative_weight(tier: int) -> float:
	var total := 0.0
	for step in range(1, clampi(tier, 0, MAX_TIER) + 1):
		total += tier_weight(step)
	return total


## Integer effects (one more projectile, one more pierce, one more luck, one more
## life) cannot pay a fraction, and pacing treasures should not slow the opening,
## so both keep a flat ladder.
static func is_flat(treasure_id: String) -> bool:
	return bool(by_id(treasure_id).get("flat", false))


## What the step into `tier` adds, in the treasure's own units.
static func increment(treasure_id: String, tier: int) -> float:
	var treasure := by_id(treasure_id)
	if treasure.is_empty():
		return 0.0
	if bool(treasure.get("flat", false)):
		return float(treasure["value"])
	return float(treasure["value"]) * tier_weight(tier)


## Tiers as the ladder counts them: equal to the tier for flat treasures and the
## weighted total for the rest. Shared effects are rebuilt from this.
static func effective_tiers(treasure_id: String, tier: int) -> float:
	if tier <= 0:
		return 0.0
	return float(tier) if is_flat(treasure_id) else cumulative_weight(tier)


## The card line for the step into `tier`.
static func tier_text(treasure: Dictionary, tier: int) -> String:
	var amount := float(treasure["value"])
	if not bool(treasure.get("flat", false)):
		amount *= tier_weight(tier)
	amount *= float(treasure.get("display", 1.0))
	return String(treasure["text"]).replace("{v}", _number(amount))


static func _number(amount: float) -> String:
	if absf(amount - round(amount)) < 0.05:
		return "%d" % roundi(amount)
	if absf(amount) < 1.0:
		return "%.2f" % amount
	return "%.1f" % amount


## The carried form of a treasure: catalog identity plus the tier the owner has
## taken it to.
static func build_state(treasure: Dictionary) -> Dictionary:
	return {
		"id": String(treasure["id"]),
		"name": String(treasure["name"]),
		"stat": String(treasure["stat"]),
		"shared": bool(treasure["shared"]),
		"per_tier": String(treasure["per_tier"]),
		"tier": 1,
	}
