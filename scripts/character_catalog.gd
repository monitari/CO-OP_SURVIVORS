class_name CharacterCatalog
extends RefCounted

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


static func power_budget(character: Dictionary) -> float:
	var weapon: Dictionary = character["weapon"]
	return float(weapon["damage"]) / float(weapon["cooldown"]) * float(weapon["reach"])



static func all_characters() -> Array[Dictionary]:
	return [
		{
			"id": "lyra",
			"name": "라이라",
			"title": "별길잡이",
			"weapon_id": "homing",
			"weapon_name": "추적 성탄",
			"tags": ["projectile", "tracking", "arcane"],
			"description": "빠른 유도탄으로 멀리 떨어진 적을 안정적으로 제거합니다.",
			"color": Color("43d9ff"),
			"health": 95.0,
			"speed": 240.0,
			"weapon": {"damage": 22.0, "cooldown": 0.62, "count": 1, "speed": 470.0, "reach": 1.0, "tier": 1}
		},
		{
			"id": "volta",
			"name": "볼타",
			"title": "폭풍술사",
			"weapon_id": "lightning",
			"weapon_name": "연쇄 낙뢰",
			"tags": ["lightning", "storm", "chain"],
			"description": "가까운 적들을 연달아 타고 흐르는 번개를 방출합니다.",
			"color": Color("b892ff"),
			# 90 health put Volta under the survival budget every other survivor sits on.
			"health": 95.0,
			"speed": 235.0,
			"weapon": {"damage": 18.0, "cooldown": 1.08, "jumps": 3, "range": 440.0, "reach": 2.2, "tier": 1}
		},
		{
			"id": "ignis",
			"name": "이그니스",
			"title": "잿불지기",
			"weapon_id": "flame",
			"weapon_name": "화염 성운",
			"tags": ["fire", "projectile", "burst"],
			"description": "사방으로 불씨를 뿌려 포위된 상황을 정리합니다.",
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
			"title": "서리무녀",
			"weapon_id": "frost",
			"weapon_name": "빙결 고리",
			"tags": ["frost", "control", "aura"],
			"description": "주변 적을 얼리는 파동으로 둘이 숨 쉴 공간을 만듭니다.",
			"color": Color("8ecae6"),
			"health": 100.0,
			"speed": 225.0,
			"weapon": {"damage": 14.0, "cooldown": 1.55, "radius": 185.0, "slow": 0.52, "reach": 4.0, "tier": 1}
		},
		{
			"id": "moro",
			"name": "모로",
			"title": "황혼사냥꾼",
			"weapon_id": "scythe",
			"weapon_name": "월식 낫",
			"tags": ["melee", "shadow", "arc"],
			"description": "바라보는 방향의 넓은 부채꼴을 한 번에 베어냅니다.",
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
			"title": "결속의 성녀",
			"weapon_id": "chain",
			"weapon_name": "결속 파동",
			"tags": ["tether", "holy", "aura"],
			"description": "두 사람 사이의 사슬 전체를 공격 판정으로 바꿉니다.",
			"color": Color("80ed99"),
			"health": 115.0,
			"speed": 205.0,
			"weapon": {"damage": 24.0, "cooldown": 0.95, "width": 58.0, "reach": 1.5, "tier": 1}
		}
	]
