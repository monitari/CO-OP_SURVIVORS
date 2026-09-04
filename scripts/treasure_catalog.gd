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
## the order of GameIconCatalog.UPGRADE_ORDER, so every treasure has an icon and
## an effect without either being defined twice.

const MAX_TIER := 5


static func all_treasures() -> Array[Dictionary]:
	return [
		{
			"id": "might",
			"name": "격노의 인장",
			"shared": false,
			"stat": "공격",
			"per_tier": "공격력 +15%",
		},
		{
			"id": "area",
			"name": "확장의 렌즈",
			"shared": false,
			"stat": "범위",
			"per_tier": "공격 범위 +15%",
		},
		{
			"id": "amount",
			"name": "분열의 화살통",
			"shared": false,
			"stat": "탄량",
			"per_tier": "발사체 +1",
		},
		{
			"id": "haste",
			"name": "질풍의 태엽",
			"shared": false,
			"stat": "신속",
			"per_tier": "발동 간격 -10%",
		},
		{
			"id": "projectile_speed",
			"name": "가속의 깃",
			"shared": false,
			"stat": "탄속",
			"per_tier": "발사체 속도 +15%",
		},
		{
			"id": "armor",
			"name": "수호의 갑주",
			"shared": false,
			"stat": "방어",
			"per_tier": "받는 피해 -2",
		},
		{
			"id": "recovery",
			"name": "재생의 성수",
			"shared": false,
			"stat": "재생",
			"per_tier": "초당 회복 +0.8",
		},
		{
			"id": "move",
			"name": "경보의 장화",
			"shared": false,
			"stat": "이동",
			"per_tier": "이동 속도 +8%",
		},
		{
			"id": "vitality",
			"name": "생명의 결정",
			"shared": false,
			"stat": "체력",
			"per_tier": "최대 체력 +15",
		},
		# The shared three change a team resource rather than the carrier, so one
		# survivor holding them benefits both. They stay in the same pool on
		# purpose: giving up a personal slot for a team effect is the trade.
		{
			"id": "magnet",
			"name": "인력의 나침반",
			"shared": true,
			"stat": "자석",
			"per_tier": "공유 획득 범위 +25%",
		},
		{
			"id": "growth",
			"name": "성장의 서",
			"shared": true,
			"stat": "성장",
			"per_tier": "공유 경험치 +15%",
		},
		{
			"id": "luck",
			"name": "행운의 주사위",
			"shared": true,
			"stat": "행운",
			"per_tier": "공유 행운 +1",
		},
	]


static func by_id(treasure_id: String) -> Dictionary:
	for treasure in all_treasures():
		if String(treasure["id"]) == treasure_id:
			return treasure
	return {}


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
