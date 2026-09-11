extends RefCounted

## Produces the same movement/dash command that a remote peer can supply.
## Decisions use nearby bodies only; combat still uses the normal weapon system.
static func command(player: ChainPlayer, partner: ChainPlayer, grid: EnemySpatialGrid,
		shots: Array, leash: float) -> Dictionary:
	var offset := partner.global_position - player.global_position
	var distance := offset.length()
	var desired := Vector2.ZERO
	var rescuing := partner.downed
	var follow_distance := 48.0 if rescuing or player.downed else minf(125.0, leash * 0.36)
	if distance > follow_distance:
		desired = offset.normalized() * clampf((distance - follow_distance) / 65.0, 0.0, 1.0)
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
	# Stay within rescue distance unless a hit is imminent.
	if rescuing and distance < 72.0 and not danger:
		avoidance *= 0.1
	desired = (desired + avoidance * (0.65 if rescuing else 1.15)).limit_length(1.0)
	if distance > leash * 0.72:
		desired = (desired + offset.normalized() * 2.0).normalized()
	return {"movement": desired, "dash": danger and not player.downed and desired.length() > 0.3
		and (distance < leash * 0.6 or desired.dot(offset) > 0.0)}


static func choose(main: Node, slot: int, choices: Array) -> int:
	var best := -1
	var best_score := -INF
	for index in choices.size():
		var option: Dictionary = choices[index]
		var score := float(main._score_upgrade_option(slot, option).get("score", 0.0))
		# Variety matters: avoid spending every level on the same numeric axis.
		if String(option["id"]) in ["special_a", "special_b", "unlock_weapon"]:
			score += 18.0
		if String(option["id"]) == "choose_tech":
			score += float((index + slot) % maxi(1, choices.size()))
		if score > best_score:
			best_score = score
			best = index
	return best
