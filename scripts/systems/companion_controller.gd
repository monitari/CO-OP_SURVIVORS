extends RefCounted

const CharacterCatalog := preload("res://scripts/catalogs/character_catalog.gd")

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


## Picks a partner that covers the human survivor's weakest axes. Keeping this
## deterministic makes the lobby recommendation understandable: choosing the
## same cat again always produces the same companion.
static func choose_character(main: Node, human_slot := 0) -> int:
	if main.character_catalog.is_empty():
		return 0
	var human_index := clampi(main.selected_character_indices[human_slot], 0,
		main.character_catalog.size() - 1)
	var human: Dictionary = main.character_catalog[human_index]
	var human_profile := CharacterCatalog.difficulty_profile(human)
	var human_tags: Array = human.get("tags", [])
	var best := human_index
	var best_score := -INF
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
		if score > best_score:
			best_score = score
			best = index
	return best
