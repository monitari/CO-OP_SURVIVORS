extends RefCounted

const CharacterCatalog := preload("res://scripts/catalogs/character_catalog.gd")

## Telegraphs need more room than ordinary body avoidance. These paddings add
## the survivor body and a small reaction margin to the attack's real shape.
const BOSS_SLAM_SAFE_PADDING := 28.0
const BOSS_CHARGE_LANE_PADDING := 30.0
const BOSS_CHARGE_LOOKAHEAD := 340.0

## Produces the same movement/dash command that a remote peer can supply.
## Decisions use nearby bodies only; combat still uses the normal weapon system.
static func command(player: ChainPlayer, partner: ChainPlayer, grid: EnemySpatialGrid,
		shots: Array, leash: float, main: Node = null) -> Dictionary:
	var offset := partner.global_position - player.global_position
	var distance := offset.length()
	var desired := Vector2.ZERO
	var rescuing := partner.downed
	var follow_distance := 48.0 if rescuing or player.downed else minf(125.0, leash * 0.36)
	if distance > follow_distance:
		desired = offset.normalized() * clampf((distance - follow_distance) / 65.0, 0.0, 1.0)
	var intent := "동료 따라가기"
	if main != null and not rescuing and not player.downed:
		var chain_build := false
		var close_build := false
		for weapon: Dictionary in main.weapon_loadouts[player.player_index - 1]:
			var id := String(weapon.get("weapon_id", ""))
			chain_build = chain_build or id == "chain"
			close_build = close_build or id in ["scythe", "frost", "orbit", "milk", "mine"]
		var build_key := str(chain_build) + str(close_build)
		if String(player.get_meta("ai_build", "")) != build_key:
			player.set_meta("ai_target_until", 0.0)
			player.set_meta("ai_build", build_key)
		var radius := leash * (0.57 if chain_build else 0.32)
		if main.chain_integrity < 45.0 or player.health < player.max_health * 0.3:
			radius = minf(radius, 85.0)
		var phase: float = main.elapsed * 0.28
		var target: Vector2 = partner.global_position + Vector2.from_angle(phase) * radius
		intent = "사슬 펼치기" if chain_build else "주변 탐색"
		# Keep objectives for a short interval so equal pickups do not cause jitter.
		if float(player.get_meta("ai_target_until", 0.0)) <= main.elapsed:
			var best := 0.0
			for item in main.field_items.active_items:
				if not is_instance_valid(item) or not item.active:
					continue
				if item.global_position.distance_to(partner.global_position) > leash * 0.62:
					continue
				var value := 500.0 - player.global_position.distance_to(item.global_position)
				if item.item_id == "heal" and player.health < player.max_health * 0.65:
					value += 300.0
				if value > best:
					best = value
					target = item.global_position
					intent = "보급품 수집"
			if best == 0.0:
				for enemy in grid.query_radius(player.global_position, 330.0):
					var away: Vector2 = player.global_position - enemy.global_position
					var candidate: Vector2 = enemy.global_position + away.normalized() * (115.0 if close_build else 220.0)
					if candidate.distance_to(partner.global_position) < leash * 0.62:
						target = candidate
						intent = "근접 무기 사거리 유지" if close_build else "원거리 견제"
						break
			player.set_meta("ai_target", target)
			player.set_meta("ai_intent", intent)
			player.set_meta("ai_target_until", main.elapsed + 0.8)
		else:
			target = player.get_meta("ai_target", target)
			intent = String(player.get_meta("ai_intent", intent))
		if target.distance_to(partner.global_position) > leash * 0.65:
			target = partner.global_position + (target - partner.global_position).limit_length(leash * 0.6)
		desired = (target - player.global_position).limit_length(60.0) / 60.0
		if chain_build and distance < radius and main.chain_integrity >= 45.0:
			desired += (player.global_position - partner.global_position).normalized() * 0.65
	if rescuing:
		intent = "동료 구조"
	var avoidance := Vector2.ZERO
	var danger := false
	for enemy in grid.query_radius(player.global_position, 155.0):
		var away := player.global_position - enemy.global_position
		var clearance := away.length() - enemy.radius - player.radius
		if clearance < 100.0:
			if away.length_squared() < 0.01:
				away = Vector2.RIGHT
			avoidance += away.normalized() * clampf((100.0 - clearance) / 100.0, 0.0, 1.5)
			danger = danger or clearance < 28.0
	for shot in shots:
		if not is_instance_valid(shot) or shot.is_queued_for_deletion() or shot.frozen:
			continue
		var future: Vector2 = shot.global_position + shot.direction * shot.speed * 0.22
		var away: Vector2 = player.global_position - future
		if away.length() < 65.0:
			avoidance += away.normalized() * 1.5
			danger = true
	var boss_escape := _boss_telegraph_escape(player, partner, main)
	if not boss_escape.is_empty():
		avoidance += Vector2(boss_escape["direction"]) * (2.4 + float(boss_escape["urgency"]))
		intent = String(boss_escape["intent"])
		danger = true
	# Stay within rescue distance unless a hit is imminent.
	if rescuing and distance < 72.0 and not danger:
		avoidance *= 0.1
	desired = (desired + avoidance * (0.65 if rescuing else 1.15)).limit_length(1.0)
	if distance > leash * 0.72:
		desired = (desired + offset.normalized() * 2.0).normalized()
	player.set_meta("ai_intent", intent)
	return {"movement": desired, "dash": danger and not player.downed and desired.length() > 0.3
		and (distance < leash * 0.6 or desired.dot(offset) > 0.0)}


## Reads the boss's committed warning shapes instead of waiting for proximity
## avoidance to notice the boss body. The strongest overlapping warning wins,
## which keeps two simultaneous escape vectors from cancelling each other.
static func _boss_telegraph_escape(player: ChainPlayer, partner: ChainPlayer,
		main: Node) -> Dictionary:
	if main == null:
		return {}
	var best_direction := Vector2.ZERO
	var best_urgency := 0.0
	var best_intent := ""
	var enemy := main.boss_enemy as ChaserEnemy
	if enemy == null or not is_instance_valid(enemy) or not enemy.active or not enemy.boss:
		return {}
	if enemy.boss_slam_windup > 0.0:
		var from_impact := player.global_position - enemy.boss_slam_point
		var safe_radius := enemy.BOSS_SLAM_RADIUS + player.radius + BOSS_SLAM_SAFE_PADDING
		var impact_distance := from_impact.length()
		if impact_distance < safe_radius:
			var escape := from_impact.normalized()
			if escape.is_zero_approx():
				escape = (partner.global_position - enemy.boss_slam_point).normalized()
			if escape.is_zero_approx():
				escape = enemy.global_position.direction_to(enemy.boss_slam_point)
			if escape.is_zero_approx():
				escape = Vector2.RIGHT
			var urgency := 1.0 + (safe_radius - impact_distance) / safe_radius
			if urgency > best_urgency:
				best_direction = escape
				best_urgency = urgency
				best_intent = "보스 강타 회피"
	if enemy.charge_windup > 0.0 or enemy.charge_timer > 0.0:
		var heading := enemy.telegraph_direction if enemy.charge_windup > 0.0 else enemy.charge_direction
		if not heading.is_zero_approx():
			heading = heading.normalized()
			var lookahead := BOSS_CHARGE_LOOKAHEAD
			if enemy.charge_windup <= 0.0:
				lookahead = maxf(140.0, enemy.move_speed * 2.6 * (enemy.charge_timer + 0.22))
			var relative := player.global_position - enemy.global_position
			var along := relative.dot(heading)
			var lane_radius := enemy.radius + player.radius + BOSS_CHARGE_LANE_PADDING
			if along >= -lane_radius and along <= lookahead:
				var closest := enemy.global_position + heading * clampf(along, 0.0, lookahead)
				var lateral := player.global_position - closest
				var lane_distance := lateral.length()
				if lane_distance < lane_radius:
					var escape := lateral.normalized()
					if escape.is_zero_approx():
						escape = heading.orthogonal()
						if (partner.global_position - closest).dot(escape) < 0.0:
							escape = -escape
					var urgency := 1.2 + (lane_radius - lane_distance) / lane_radius
					if urgency > best_urgency:
						best_direction = escape
						best_urgency = urgency
						best_intent = "보스 돌진 회피"
	if best_urgency <= 0.0:
		return {}
	return {"direction": best_direction, "urgency": best_urgency, "intent": best_intent}


static func choose(main: Node, slot: int, choices: Array) -> int:
	var weights: Array[float] = []
	var total := 0.0
	for index in choices.size():
		var option: Dictionary = choices[index]
		var score := float(main._score_upgrade_option(slot, option).get("score", 0.0))
		# Variety matters: avoid spending every level on the same numeric axis.
		if String(option["id"]) in ["special_a", "special_b", "unlock_weapon"]:
			score += 18.0
		if String(option["id"]) == "choose_tech":
			score += float((index + slot) % maxi(1, choices.size()))
		# Favour useful choices without behaving like a perfect optimiser.
		var weight := exp(clampf(score, -40.0, 160.0) / 38.0)
		weights.append(weight)
		total += weight
	var roll := randf() * total
	for index in weights.size():
		roll -= weights[index]
		if roll <= 0.0:
			return index
	return choices.size() - 1


## Picks a partner that covers the human survivor's weakest axes. Raw coverage
## used to dominate this calculation, so Latte won almost every pairing. Keep
## the best few credible complements and use one stable AI lobby preference.
static func choose_character(main: Node, human_slot := 0) -> int:
	if main.character_catalog.is_empty():
		return 0
	var human_index := clampi(main.selected_character_indices[human_slot], 0,
		main.character_catalog.size() - 1)
	var human: Dictionary = main.character_catalog[human_index]
	var human_profile := CharacterCatalog.difficulty_profile(human)
	var human_tags: Array = human.get("tags", [])
	var ranked: Array[Dictionary] = []
	for index in main.character_catalog.size():
		if index == human_index:
			continue
		var candidate: Dictionary = main.character_catalog[index]
		var profile := CharacterCatalog.difficulty_profile(candidate)
		var score := 0.0
		score += float(profile["coverage"]) * (1.25 - float(human_profile["coverage"])) * 3.2
		score += float(profile["durability"]) * (1.25 - float(human_profile["durability"])) * 2.8
		score += float(profile["mobility"]) * (1.15 - float(human_profile["mobility"])) * 1.8
		for tag in candidate.get("tags", []):
			if tag not in human_tags:
				score += 0.18
		var pair_length := CharacterCatalog.chain_length_for(human, candidate)
		score -= absf(pair_length - 390.0) / 180.0
		# Extreme reach is useful, but it is one tool rather than an automatic
		# answer. Character balance and the actual weapon remain unchanged.
		score -= maxf(0.0, float(profile["coverage"]) - 0.72) * 1.35
		ranked.append({"index": index, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["score"]), float(b["score"])):
			return float(a["score"]) > float(b["score"])
		return int(a["index"]) < int(b["index"])
	)
	var shortlist: Array[int] = []
	for entry: Dictionary in ranked:
		if shortlist.size() >= 5:
			break
		shortlist.append(int(entry["index"]))
	if shortlist.is_empty():
		return human_index
	var preference := int(main.get("ai_character_preference"))
	return shortlist[posmod(preference + human_index * 7, shortlist.size())]
