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

const MAX_TIER := 6


static func all_treasures() -> Array[Dictionary]:
	return [
		{
			"id": "might",
			"name": "격노의 인장",
			"shared": false,
			"stat": "공격",
			"per_tier": "공격력 +9%",
		},
		{
			"id": "area",
			"name": "확장의 렌즈",
			"shared": false,
			"stat": "범위",
			"per_tier": "공격 범위 +9%",
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
			"per_tier": "발동 간격 -6%",
		},
		{
			"id": "projectile_speed",
			"name": "가속의 깃",
			"shared": false,
			"stat": "탄속",
			"per_tier": "발사체 속도 +10%",
		},
		{
			"id": "armor",
			"name": "수호의 갑주",
			"shared": false,
			"stat": "방어",
			"per_tier": "받는 피해 -1.5",
		},
		{
			"id": "recovery",
			"name": "재생의 성수",
			"shared": false,
			"stat": "재생",
			"per_tier": "초당 회복 +0.5",
		},
		{
			"id": "move",
			"name": "경보의 장화",
			"shared": false,
			"stat": "이동",
			"per_tier": "이동 속도 +5%",
		},
		{
			"id": "vitality",
			"name": "생명의 결정",
			"shared": false,
			"stat": "체력",
			"per_tier": "최대 체력 +12",
		},
		# Added with the evolution pass. These are the treasures the fused weapons
		# require, so a survivor picking one is also picking a tech tree branch.
		{
			"id": "crit",
			"name": "처형자의 표식",
			"shared": false,
			"stat": "치명",
			"per_tier": "치명타 확률 +5%",
		},
		{
			"id": "pierce",
			"name": "관통의 송곳",
			"shared": false,
			"stat": "관통",
			"per_tier": "발사체 관통 +1",
		},
		{
			"id": "thorns",
			"name": "가시의 견장",
			"shared": false,
			"stat": "가시",
			"per_tier": "접촉 피해 10% 반사",
		},
		{
			"id": "resolve",
			"name": "불굴의 부적",
			"shared": false,
			"stat": "불굴",
			"per_tier": "출혈 시간 +3초, 구조 속도 +15%",
		},
		# The shared ones change a team resource rather than the carrier, so one
		# survivor holding them benefits both. They stay in the same pool on
		# purpose: giving up a personal slot for a team effect is the trade.
		{
			"id": "overcharge",
			"name": "과충전 코어",
			"shared": true,
			"stat": "과충전",
			"per_tier": "과충전 피해 +6%, 내구도 소모 -12%",
		},
		{
			"id": "greed",
			"name": "탐욕의 저울",
			"shared": true,
			"stat": "탐욕",
			"per_tier": "필드 아이템 확률 +30%",
		},
		{
			"id": "magnet",
			"name": "인력의 나침반",
			"shared": true,
			"stat": "자석",
			"per_tier": "공유 획득 범위 +20%",
		},
		{
			"id": "growth",
			"name": "성장의 서",
			"shared": true,
			"stat": "성장",
			"per_tier": "공유 경험치 +10%",
		},
		{
			"id": "luck",
			"name": "행운의 주사위",
			"shared": true,
			"stat": "행운",
			"per_tier": "공유 행운 +1",
		},
		{
			"id": "catnip",
			"name": "별빛 캣닢",
			"shared": true,
			"stat": "성장 회복",
			"per_tier": "레벨업마다 둘 다 최대 체력의 4% 회복",
		},
		{
			"id": "bounty_bell",
			"name": "사냥꾼 방울",
			"shared": true,
			"stat": "강적 경험치",
			"per_tier": "엘리트·보스 경험치 +18%",
		},
		{
			"id": "twin_charm",
			"name": "쌍둥이 부적",
			"shared": true,
			"stat": "밀착 화력",
			"per_tier": "사슬 거리 45% 이내일 때 피해 +5%",
		},
		{
			"id": "dash_claw",
			"name": "질주 발톱",
			"shared": true,
			"stat": "대시 공격",
			"per_tier": "대시 시작점에 피해 11 충격파",
		},
		{
			"id": "lucky_paw",
			"name": "행운의 앞발",
			"shared": false,
			"stat": "회피",
			"per_tier": "피해를 무시할 확률 +4%",
		},
		{
			"id": "nine_lives",
			"name": "아홉 목숨 리본",
			"shared": false,
			"stat": "기사회생",
			"per_tier": "치명타를 1회 막고 체력 28% 회복",
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
