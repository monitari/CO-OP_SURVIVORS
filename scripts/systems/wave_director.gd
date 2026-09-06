class_name WaveDirector
extends Node2D

## Spawning used to be one continuous trickle whose interval shrank with time,
## which gave a run no shape at all — no build-up, no relief, nothing to read
## as "here comes another one". It now runs in waves: an assault stretch that
## opens with a surge, then a short lull before the next wave escalates.

signal wave_started(wave_index: int, is_surge_wave: bool)
signal wave_calm_started(wave_index: int)
signal boss_incoming(boss_rank: int)
signal encounter_started(encounter_id: String)

const EnemyScript := preload("res://scripts/entities/enemy.gd")

## A run is now twenty-five minutes rather than five. Five minutes was shorter
## than the content the game hands out — four weapon slots, four treasure slots,
## a seven-tier weapon track and twenty-one resonances are not reachable in the
## dozen level-ups a five-minute run affords, so most of the tree existed only
## in theory. Twenty-five minutes is five boss fights with four full escalation
## stretches between them, which is what the build actually needs to finish.
const WAVE_DURATION := 30.0
const WAVE_CALM := 9.0 ## Trailing quiet stretch of each wave, for regrouping and picking up drops.
const SURGE_EVERY := 3 ## Every third wave opens with a much larger surge.
const BOSS_INTERVAL := 300.0
const BOSS_COUNT := 5
const RUN_LENGTH := BOSS_INTERVAL * float(BOSS_COUNT)
## Seconds of elapsed run per point of difficulty. Stretched with the run so a
## twenty-five-minute fight does not simply arrive at five times the old scaling.
const DIFFICULTY_SECONDS := 62.0
const OPENING_SPAWN_INTERVAL := 1.25
const SECOND_WAVE_SPAWN_INTERVAL := 1.05
const THIRD_WAVE_SPAWN_INTERVAL := 0.88
const FIRST_REINFORCEMENT_COUNT := 3
const CHARGER_UNLOCK_TIME := 30.0
const BULWARK_UNLOCK_TIME := 75.0
const SWARM_UNLOCK_TIME := 45.0
const SWARM_INTERVAL := 22.0

## Named encounters, on their own clock, so a long run has events in it rather
## than a single rising slope. Each one poses a different question: a tide is
## free experience if the pair is positioned for it, a siege is the surrounded
## problem with no gap to walk through, a stampede comes from one bearing and
## has to be side-stepped, and a squad is four elites at once.
const ENCOUNTER_FIRST := 105.0
const ENCOUNTER_INTERVAL := 78.0
const ENCOUNTER_ORDER := ["swarm_tide", "stampede", "ring_siege", "elite_squad", "deluge"]
const ENCOUNTER_NAMES := {
	"swarm_tide": "군체 해일",
	"stampede": "돌진 폭주",
	"ring_siege": "포위 진형",
	"elite_squad": "정예 편대",
	"deluge": "대범람",
}
## 대범람 is the one encounter that is supposed to be frightening rather than
## interesting: enemies from every bearing at once, enough of them to cover the
## screen. It is held back until the pair has a build to answer it with — before
## this it is not a climax, it is a wall.
const DELUGE_UNLOCK_TIME := 420.0
const DELUGE_BASE_COUNT := 46
const DELUGE_PER_MINUTE := 5.0

var enemy_pool: Array[ChaserEnemy] = []
var spawn_timer := 0.0
var elite_timer := 35.0
var swarm_timer := SWARM_UNLOCK_TIME
var boss_spawned := false ## True once the first boss of the run has arrived.
var bosses_spawned := 0
var boss_active := false ## Kept current by main; holds the next boss back while one is still alive.
var enemy_cap := 620
## Host returns the number of ordinary enemies recycled for scheduled arrivals.
var reclaim_capacity: Callable

var wave_index := 0
var wave_elapsed := 0.0
var in_calm := false
var encounter_timer := ENCOUNTER_FIRST
var encounters_run := 0


## The assault stretch tightens as waves go on, but never below a floor — the
## enemy cap and the cull radius are what bound the fight, not the interval.
func spawn_interval() -> float:
	# The first two waves are the learning window: the pair is still on one
	# weapon each and has not yet had time to establish armor, recovery, or a
	# resonance. Ease the stream here, then join the original curve from wave 2.
	if wave_index == 0:
		return OPENING_SPAWN_INTERVAL
	if wave_index == 1:
		return SECOND_WAVE_SPAWN_INTERVAL
	if wave_index == 2:
		return THIRD_WAVE_SPAWN_INTERVAL
	# Steeper and with a lower floor than before. The old curve flattened out
	# around wave eight, so minute ten and minute twenty-five felt the same —
	# and with bodies no longer able to stack, a given number of enemies now
	# takes up much more room than it used to.
	return maxf(0.10, 0.62 - float(wave_index) * 0.055)


func is_surge_wave(index: int) -> bool:
	return index > 0 and index % SURGE_EVERY == 0


## When the next boss is due, or RUN_LENGTH once all five have been sent.
func next_boss_time() -> float:
	if bosses_spawned >= BOSS_COUNT:
		return RUN_LENGTH
	return BOSS_INTERVAL * float(bosses_spawned + 1)


func bosses_remaining() -> int:
	return maxi(0, BOSS_COUNT - bosses_spawned)


func encounter_name(encounter_id: String) -> String:
	return String(ENCOUNTER_NAMES.get(encounter_id, encounter_id))


func step(delta: float, elapsed: float, center: Vector2, active_count: int) -> Array[ChaserEnemy]:
	var spawned: Array[ChaserEnemy] = []
	var difficulty := elapsed / DIFFICULTY_SECONDS
	var reserved := scheduled_slots(delta, elapsed)
	var shortage := maxi(0, active_count + reserved - enemy_cap)
	if reserved > 0 and shortage > 0 and reclaim_capacity.is_valid():
		active_count -= int(reclaim_capacity.call(shortage, center))
	var ordinary_cap := maxi(0, enemy_cap - reserved)

	# --- wave clock ---------------------------------------------------------
	wave_elapsed += delta
	if wave_elapsed >= WAVE_DURATION:
		wave_elapsed -= WAVE_DURATION
		wave_index += 1
		in_calm = false
		wave_started.emit(wave_index, is_surge_wave(wave_index))
		# A wave opens with a burst so it lands as an event rather than as a
		# slightly faster trickle.
		# The first boundary used to combine four instant reinforcements with
		# the charger unlock two seconds earlier. Three plain chasers make it a
		# readable escalation without turning the end of the tutorial into a wall.
		# Wave openers grow with the run rather than being a fixed handful, so a
		# late surge actually lands as a surge.
		var growth := int(float(wave_index) * 0.8)
		var surge := (10 + growth * 2) if is_surge_wave(wave_index) else (
			FIRST_REINFORCEMENT_COUNT if wave_index == 1 else 4 + growth)
		for index in surge:
			if active_count + spawned.size() >= ordinary_cap:
				break
			spawned.append(_acquire_enemy(_pick_archetype(elapsed), difficulty, center, false, false))
	elif not in_calm and wave_elapsed >= WAVE_DURATION - WAVE_CALM:
		in_calm = true
		wave_calm_started.emit(wave_index)

	spawn_timer -= delta
	elite_timer -= delta

	# --- bosses -------------------------------------------------------------
	# One every five minutes, each stronger than the last, and never two at
	# once: if the pair is still fighting boss three when boss four comes due,
	# the schedule waits rather than stacking two health bars on one HUD.
	if bosses_spawned < BOSS_COUNT and not boss_active and elapsed >= next_boss_time() and active_count + spawned.size() < enemy_cap:
		bosses_spawned += 1
		boss_spawned = true
		boss_active = true
		boss_incoming.emit(bosses_spawned)
		# Not flagged elite: the boss multiplier already covers its stat block,
		# and stacking both produced a boss with four times the health anyone
		# had budgeted for.
		spawned.append(_acquire_enemy("owl" if bosses_spawned == 2 or bosses_spawned == 4 else "brute", difficulty, center, false, true, bosses_spawned))
	# Elites and the boss ignore the lull — the calm is a break from the swarm,
	# not a guarantee that nothing happens.
	if elite_timer <= 0.0 and active_count + spawned.size() < enemy_cap:
		elite_timer = 38.0
		spawned.append(_acquire_enemy(_pick_archetype(elapsed), difficulty, center, true, false))

	# A swarm pack is its own event on its own clock, and it ignores the lull
	# for the same reason elites do: the calm is a breather from pressure, not
	# a window where nothing at all happens.
	swarm_timer -= delta
	if swarm_timer <= 0.0 and elapsed >= SWARM_UNLOCK_TIME:
		swarm_timer = SWARM_INTERVAL
		for index in _swarm_pack_size(elapsed):
			if active_count + spawned.size() >= ordinary_cap:
				break
			spawned.append(_acquire_enemy("swarm", difficulty, center, false, false))

	# --- named encounters ---------------------------------------------------
	encounter_timer -= delta
	if encounter_timer <= 0.0 and enemy_cap - active_count - spawned.size() >= encounter_size(elapsed):
		encounter_timer = ENCOUNTER_INTERVAL
		var encounter_id: String = ENCOUNTER_ORDER[encounters_run % ENCOUNTER_ORDER.size()]
		encounters_run += 1
		if encounter_id == "deluge" and elapsed < DELUGE_UNLOCK_TIME:
			encounter_id = "swarm_tide"
		encounter_started.emit(encounter_id)
		_run_encounter(encounter_id, difficulty, center, active_count, spawned)

	if in_calm:
		return spawned

	if spawn_timer <= 0.0:
		spawn_timer = spawn_interval()
		var count := 1 + int(float(wave_index) / 4.0)
		if wave_index >= 2 and randf() < 0.4:
			count += 1
		for index in count:
			if active_count + spawned.size() >= enemy_cap:
				break
			spawned.append(_acquire_enemy(_pick_archetype(elapsed), difficulty, center, false, false))
	return spawned


func encounter_size(elapsed: float) -> int:
	match String(ENCOUNTER_ORDER[encounters_run % ENCOUNTER_ORDER.size()]):
		"stampede": return 12
		"ring_siege": return 16
		"elite_squad": return 4
		"deluge":
			if elapsed >= DELUGE_UNLOCK_TIME:
				return DELUGE_BASE_COUNT + int(elapsed / 60.0 * DELUGE_PER_MINUTE)
	return _swarm_pack_size(elapsed) * 2


func scheduled_slots(delta: float, elapsed: float) -> int:
	var count := 0
	if bosses_spawned < BOSS_COUNT and not boss_active and elapsed >= next_boss_time():
		count += 1
	if elite_timer <= delta:
		count += 1
	if encounter_timer <= delta:
		count += encounter_size(elapsed)
	return mini(enemy_cap, count)


## Appends this encounter's arrivals to `spawned`. Written as one function per
## shape rather than as data, because what makes each encounter distinct is
## where the enemies appear relative to the pair, not how many of them there are.
func _run_encounter(
	encounter_id: String, difficulty: float, center: Vector2,
	active_count: int, spawned: Array[ChaserEnemy]
) -> void:
	var budget := func() -> bool: return active_count + spawned.size() < enemy_cap
	match encounter_id:
		"swarm_tide":
			# Free experience for a pair that is standing somewhere it can
			# clear a crowd, and a wall for one that is not.
			for index in _swarm_pack_size(difficulty * DIFFICULTY_SECONDS) * 2:
				if not budget.call():
					return
				spawned.append(_acquire_enemy("swarm", difficulty, center, false, false))
		"stampede":
			# One bearing, one line. The answer is to move sideways, which the
			# chain makes a decision rather than a reflex.
			var bearing := randf() * TAU
			for index in 12:
				if not budget.call():
					return
				var enemy := _acquire_enemy("charger", difficulty, center, false, false)
				var lateral := float(index - 6) * 62.0
				enemy.position = (center + Vector2.from_angle(bearing) * 780.0
					+ Vector2.from_angle(bearing + PI * 0.5) * lateral)
				spawned.append(enemy)
		"ring_siege":
			# The surrounded problem stated plainly: a closed circle with no
			# gap, which is what the wide-reach weapons and the fused forms
			# exist to answer.
			var count := 16
			for index in count:
				if not budget.call():
					return
				var enemy := _acquire_enemy(_pick_archetype(difficulty * DIFFICULTY_SECONDS), difficulty, center, false, false)
				enemy.position = center + Vector2.from_angle(TAU * float(index) / float(count)) * 640.0
				spawned.append(enemy)
		"elite_squad":
			for index in 4:
				if not budget.call():
					return
				spawned.append(_acquire_enemy(_pick_archetype(difficulty * DIFFICULTY_SECONDS), difficulty, center, true, false))
		"deluge":
			# Four rings at four radii so they do not arrive as one wall the pair
			# can simply out-walk: the near ring is on them immediately and the
			# far one closes while they are still dealing with it.
			var elapsed_now := difficulty * DIFFICULTY_SECONDS
			var total := DELUGE_BASE_COUNT + int(elapsed_now / 60.0 * DELUGE_PER_MINUTE)
			for index in total:
				if not budget.call():
					return
				var enemy := _acquire_enemy(_pick_archetype(elapsed_now), difficulty, center, false, false)
				var ring := index % 4
				var angle := TAU * float(index) / float(total) + float(ring) * 0.31
				enemy.position = center + Vector2.from_angle(angle) * (560.0 + float(ring) * 175.0)
				spawned.append(enemy)


func release_enemy(enemy: ChaserEnemy) -> void:
	if enemy in enemy_pool:
		return
	enemy.deactivate()
	enemy_pool.append(enemy)


func _acquire_enemy(
	archetype: String, difficulty: float, center: Vector2,
	elite: bool, boss: bool, boss_rank: int = 0
) -> ChaserEnemy:
	var enemy: ChaserEnemy
	if enemy_pool.is_empty():
		enemy = EnemyScript.new() as ChaserEnemy
		add_child(enemy)
	else:
		enemy = enemy_pool.pop_back()
	enemy.setup(difficulty, archetype, elite, boss, boss_rank)
	var angle := randf() * TAU
	var distance := randf_range(610.0, 760.0) if not boss else 820.0
	enemy.position = center + Vector2.from_angle(angle) * distance
	return enemy


func _pick_archetype(elapsed: float) -> String:
	var roll := randf()
	if elapsed >= 120.0 and roll > 0.62:
		var unlocked := mini(5, 1 + int((elapsed - 120.0) / 60.0))
		return ["rat_runner", "wasp", "hedgehog", "mole", "owl"][randi_range(0, unlocked - 1)]
	if elapsed >= BULWARK_UNLOCK_TIME and roll < 0.09:
		return "bulwark"
	if elapsed >= 55.0 and roll < 0.22:
		return "chain_hunter"
	if elapsed >= 36.0 and roll < 0.40:
		return "shooter"
	if elapsed >= CHARGER_UNLOCK_TIME and roll < 0.60:
		return "charger"
	return "chaser"


## Swarms do not trickle. They arrive as a pack or not at all, which is what
## makes them a farming opportunity rather than background noise. Capped so the
## back half of a twenty-five-minute run does not spend its whole enemy budget
## on things worth three experience each.
func _swarm_pack_size(elapsed: float) -> int:
	return mini(46, 7 + int(elapsed / 70.0) * 4)
