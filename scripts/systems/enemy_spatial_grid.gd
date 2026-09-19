class_name EnemySpatialGrid
extends RefCounted
## The crowd, bucketed by where it stands, plus the separation pass that keeps
## bodies from standing inside each other.
##
## Rebuilt once a tick. Alongside the buckets it keeps the crowd as flat arrays —
## positions, radii, flags — because the separation pass reads those for every
## sampled pair, and a packed array element costs a fraction of a property read
## through a node. Buckets hold indices into those arrays, keyed by one integer
## per cell rather than a Vector2i, which hashes several times faster.

const FLAG_SCENERY := 1
const FLAG_IMMOVABLE := 2
## Off-screen bodies separate on one tick in this many; on-screen ones on one in
## CROWD_UPDATE_DIVISOR. Nobody can see a pile nobody is looking at, and it has
## come apart by the time it walks into view.
const OFFSCREEN_DIVISOR := 4
const CROWD_UPDATE_DIVISOR := 2
## How hard two overlapping bodies push apart per tick, as a fraction of how
## far they are inside each other. Not 1.0: a hard resolve makes a dense crowd
## jitter, because every pair is corrected against a position two other pairs
## are also correcting. Partial correction over several ticks settles instead.
const CROWD_PUSH := 0.34
## Bodies are allowed to touch a little. Without this, enemies that are meant to
## arrive as a pack visibly repel each other on contact and a swarm stops
## reading as a swarm.
const CROWD_OVERLAP_SLACK := 0.82
## How many partners one body resolves against per tick. Capped because a
## gravity pile in a single cell would otherwise make separation quadratic;
## raised from 4/2 because at those numbers a twenty-body stack never came
## apart and a crowd standing on a boss stayed standing on it.
const CROWD_SAMPLES := 7
const CROWD_NEIGHBOUR_SAMPLES := 4
## The four forward neighbours. Walking only these plus the cell itself visits
## every neighbouring pair once; the backward four would visit each pair a
## second time and cancel half the correction.
const CROWD_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1),
]
const KEY_OFFSET := 1 << 20
const KEY_SHIFT := 21
const KEY_MASK := (1 << 21) - 1

var cell_size := 192.0
## int cell key -> Array of indices into `bodies`.
var cells: Dictionary = {}
var _bucket_pool: Array[Array] = []
var occupied_min := Vector2i.ZERO
var occupied_max := Vector2i.ZERO
## The largest body currently in the grid. Separation uses it to decide whether a
## body is close enough to a cell boundary for anything in the next cell to be
## able to reach it — an exact test, so it skips only pairs that provably cannot
## touch. Tracked here rather than written as a constant so a bigger boss cannot
## silently invalidate it.
var max_radius := 0.0
## Live bodies at the last rebuild, and their state as flat arrays.
var bodies: Array[ChaserEnemy] = []
var positions := PackedVector2Array()
var radii := PackedFloat32Array()
var flags := PackedByteArray()
var batches := PackedInt32Array()
var _moved := PackedByteArray()
## Where the pass counts as on screen. Anything outside separates less often.
var view_rect := Rect2(-1e9, -1e9, 2e9, 2e9)
var _phase := 0

## --- projectile lookups -----------------------------------------------------
##
## The 192px buckets suit separation, where a body wants every neighbour it can
## touch. They suit a projectile badly: a shot 8px wide looking up its contacts
## walked every body in a 192px cell, and a nearest-target search walked every
## cell inside 900px even after it had found a body right next to it. With a
## thousand shots in a 620-body crowd those two lookups were most of a tick
## (docs/projectile-performance-2026-09-15.md).
##
## So the same rebuild also lays the bodies into a finer, dense grid: one int per
## cell pointing at the first body in it and one int per body pointing at the
## next, bounded by the crowd. No dictionary lookups, no per-query allocation, and
## an occupied-row count lets a search step over empty rows without touching them.
##
## Tests read the flat `positions` array, which separate() keeps current, rather
## than each node's position: a node property read per body was most of the cost
## of a lookup. A body separation pushed across a cell edge after the rebuild is
## still found because every search is padded by DRIFT_MARGIN. Weapons that drag
## bodies mid-tick (a gravity well) are seen from the next rebuild, one tick later.
const DRIFT_MARGIN := 8.0
## Beyond this many cells the fine grid coarsens itself for that rebuild, so a
## body stranded far from the crowd cannot allocate a huge sparse array.
const FINE_MAX_CELLS := 1 << 16
## Chosen by A/B measurement against 192/96/64/32 (see the report).
var projectile_cell_size := 48.0
var fine_cell_size := 48.0
var _fine_min := Vector2i.ZERO
var _fine_width := 0
var _fine_height := 0
var _fine_heads := PackedInt32Array()
var _fine_next := PackedInt32Array()
var _fine_row_counts := PackedInt32Array()
## Instance ids at the rebuild, so a hit-history check never touches the node.
var ids := PackedInt64Array()


func rebuild(enemies: Array[ChaserEnemy]) -> void:
	# Recycle the buckets; dense waves then reuse stable storage instead of
	# feeding the allocator hundreds of tiny arrays every tick.
	for bucket: Array in cells.values():
		bucket.clear()
		_bucket_pool.append(bucket)
	cells.clear()
	bodies.clear()
	max_radius = 0.0
	var count := enemies.size()
	positions.resize(count)
	radii.resize(count)
	flags.resize(count)
	batches.resize(count)
	var index := 0
	var inverse := 1.0 / cell_size
	var low_x := 0
	var low_y := 0
	var high_x := -1
	var high_y := -1
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or not enemy.active:
			continue
		var at := enemy.position
		var radius := enemy.radius
		if radius > max_radius:
			max_radius = radius
		var cell_x := floori(at.x * inverse)
		var cell_y := floori(at.y * inverse)
		if index == 0:
			low_x = cell_x; high_x = cell_x; low_y = cell_y; high_y = cell_y
		else:
			if cell_x < low_x: low_x = cell_x
			elif cell_x > high_x: high_x = cell_x
			if cell_y < low_y: low_y = cell_y
			elif cell_y > high_y: high_y = cell_y
		var key := ((cell_x + KEY_OFFSET) << KEY_SHIFT) | (cell_y + KEY_OFFSET)
		var bucket: Variant = cells.get(key)
		if bucket == null:
			bucket = _bucket_pool.pop_back() if not _bucket_pool.is_empty() else []
			cells[key] = bucket
		(bucket as Array).append(index)
		bodies.append(enemy)
		positions[index] = at
		radii[index] = radius
		flags[index] = (FLAG_SCENERY if enemy.scenery else 0) | (FLAG_IMMOVABLE if enemy.immovable else 0)
		batches[index] = enemy.ai_batch
		index += 1
	occupied_min = Vector2i(low_x, low_y)
	occupied_max = Vector2i(high_x, high_y)
	positions.resize(index)
	radii.resize(index)
	flags.resize(index)
	batches.resize(index)
	_rebuild_fine()


func _rebuild_fine() -> void:
	var count := bodies.size()
	ids.resize(count)
	_fine_next.resize(count)
	if count == 0:
		_fine_width = 0
		_fine_height = 0
		return
	var low := positions[0]
	var high := positions[0]
	for index in count:
		var at := positions[index]
		if at.x < low.x: low.x = at.x
		elif at.x > high.x: high.x = at.x
		if at.y < low.y: low.y = at.y
		elif at.y > high.y: high.y = at.y
		ids[index] = bodies[index].get_instance_id()
	var size := maxf(4.0, projectile_cell_size)
	var width := 0
	var height := 0
	while true:
		_fine_min = Vector2i(floori(low.x / size), floori(low.y / size))
		width = floori(high.x / size) - _fine_min.x + 1
		height = floori(high.y / size) - _fine_min.y + 1
		if width * height <= FINE_MAX_CELLS:
			break
		size *= 2.0
	fine_cell_size = size
	_fine_width = width
	_fine_height = height
	_fine_heads.resize(width * height)
	_fine_heads.fill(-1)
	_fine_row_counts.resize(height)
	_fine_row_counts.fill(0)
	var inverse := 1.0 / size
	# Walked backwards so each cell's list comes out in body order — the order the
	# 192px buckets used — which keeps "first body found" stable between the two.
	for index in range(count - 1, -1, -1):
		var at := positions[index]
		var row := floori(at.y * inverse) - _fine_min.y
		var cell := row * width + floori(at.x * inverse) - _fine_min.x
		_fine_next[index] = _fine_heads[cell]
		_fine_heads[cell] = index
		_fine_row_counts[row] += 1


## Bodies a shot of `shot_radius` touches on its way from `from` to `to`, written
## into `out` (cleared first) in the order they are found, and at most `limit` of
## them. Ids in `exclude` (a shot's hit history) are skipped without being counted.
##
## The test is against the swept segment, not the end point, so a shot that moves
## further in one tick than a body is wide still hits it; and the reach uses each
## body's own radius, so a boss wider than the old fixed 32px pad is not missed at
## its edge. A single-hit shot stops scanning at its first contact.
func projectile_contacts(from: Vector2, to: Vector2, shot_radius: float, limit: int, exclude: Dictionary, out: Array[ChaserEnemy]) -> int:
	out.clear()
	if _fine_width == 0 or limit <= 0:
		return 0
	var pad := shot_radius + max_radius + DRIFT_MARGIN
	var size := fine_cell_size
	var first_x := maxi(0, floori((minf(from.x, to.x) - pad) / size) - _fine_min.x)
	var last_x := mini(_fine_width - 1, floori((maxf(from.x, to.x) + pad) / size) - _fine_min.x)
	var first_y := maxi(0, floori((minf(from.y, to.y) - pad) / size) - _fine_min.y)
	var last_y := mini(_fine_height - 1, floori((maxf(from.y, to.y) + pad) / size) - _fine_min.y)
	if first_x > last_x or first_y > last_y:
		return 0
	var segment := to - from
	var length_squared := segment.length_squared()
	# Zero for a shot that did not move, which collapses the sweep to a point test.
	var inverse := 1.0 / length_squared if length_squared > 0.0001 else 0.0
	var check_exclude := not exclude.is_empty()
	var found := 0
	# Scanned from the side the shot is travelling from, so a single-hit shot
	# crossing several cells in one tick meets the near body before the far one.
	var step_x := 1 if segment.x >= 0.0 else -1
	var step_y := 1 if segment.y >= 0.0 else -1
	var columns := last_x - first_x + 1
	var y := first_y if step_y > 0 else last_y
	for _row in last_y - first_y + 1:
		if _fine_row_counts[y] > 0:
			var x := first_x if step_x > 0 else last_x
			var row_start := y * _fine_width
			for _column in columns:
				var body := _fine_heads[row_start + x]
				while body >= 0:
					var offset := positions[body] - from
					var along := clampf(offset.dot(segment) * inverse, 0.0, 1.0)
					var reach := shot_radius + radii[body]
					if (offset - segment * along).length_squared() <= reach * reach 							and not (check_exclude and exclude.has(ids[body])):
						var enemy := bodies[body]
						if is_instance_valid(enemy) and not enemy.dead:
							out.append(enemy)
							found += 1
							if found >= limit:
								return found
					body = _fine_next[body]
				x += step_x
		y += step_y
	return found


static func _segment_distance_squared(point: Vector2, from: Vector2, segment: Vector2, length_squared: float) -> float:
	var offset := point - from
	if length_squared <= 0.0001:
		return offset.length_squared()
	var t := clampf(offset.dot(segment) / length_squared, 0.0, 1.0)
	return (offset - segment * t).length_squared()


## Every living body within `radius` of `origin`.
##
## Answered from the fine grid and the flat `positions` array, touching a node
## only for a body that already passed the distance test there. It used to walk
## the 192px buckets and read `is_instance_valid`, `dead` and `position` off every
## body in every bucket the square touched — and in a packed crowd one 192px
## bucket holds a hundred bodies or more. A 34px orbit-shard query was scanning
## several hundred nodes to return a handful, thirteen shards a ring, every tick;
## on the late-run benchmark the orbit ring alone cost a millisecond a tick.
##
## Same contract as before: the final test is against the live position, so a
## body knocked about since the rebuild is judged where it is now. The prefilter
## is padded by DRIFT_MARGIN for the same reason nearest() is.
func query_radius(origin: Vector2, radius: float) -> Array[ChaserEnemy]:
	var results: Array[ChaserEnemy] = []
	if _fine_width == 0 or bodies.is_empty():
		return results
	var size := fine_cell_size
	var reach := radius + DRIFT_MARGIN
	var reach_squared := reach * reach
	var radius_squared := radius * radius
	var min_x := maxi(0, floori((origin.x - reach) / size) - _fine_min.x)
	var max_x := mini(_fine_width - 1, floori((origin.x + reach) / size) - _fine_min.x)
	var min_y := maxi(0, floori((origin.y - reach) / size) - _fine_min.y)
	var max_y := mini(_fine_height - 1, floori((origin.y + reach) / size) - _fine_min.y)
	for y in range(min_y, max_y + 1):
		if _fine_row_counts[y] == 0:
			continue
		var row_start := y * _fine_width
		for x in range(min_x, max_x + 1):
			var body := _fine_heads[row_start + x]
			while body >= 0:
				if positions[body].distance_squared_to(origin) <= reach_squared:
					var enemy := bodies[body]
					if is_instance_valid(enemy) and not enemy.dead and enemy.position.distance_squared_to(origin) <= radius_squared:
						results.append(enemy)
				body = _fine_next[body]
	return results


## The living body closest to `origin`, strictly inside `radius`.
##
## Searched ring by ring outward from the origin's cell on the fine grid. After
## each ring, everything not yet scanned lies at least the distance to that
## square's edge away (less DRIFT_MARGIN); once the best body found is nearer
## than that, no unscanned body can beat it and the search stops. The result is
## the same nearest body the old full scan returned — equal distances resolve to
## the lower body index — at a fraction of the cells.
func nearest(origin: Vector2, radius: float, excluded: Array[ChaserEnemy] = []) -> ChaserEnemy:
	if _fine_width == 0 or cells.is_empty():
		return null
	var size := fine_cell_size
	var best: ChaserEnemy = null
	var best_index := -1
	var best_distance := radius * radius
	var check_excluded := not excluded.is_empty()
	var centre_x := floori(origin.x / size) - _fine_min.x
	var centre_y := floori(origin.y / size) - _fine_min.y
	# Rings that lie wholly outside the grid hold nothing; start at the first
	# one that can reach it.
	var gap_x := maxi(0, maxi(-centre_x, centre_x - (_fine_width - 1)))
	var gap_y := maxi(0, maxi(-centre_y, centre_y - (_fine_height - 1)))
	var ring := maxi(gap_x, gap_y)
	var last_ring := maxi(maxi(centre_x, _fine_width - 1 - centre_x), maxi(centre_y, _fine_height - 1 - centre_y))
	var local := origin / size - Vector2(floorf(origin.x / size), floorf(origin.y / size))
	while ring <= last_ring:
		var top := centre_y - ring
		var bottom := centre_y + ring
		var left := maxi(0, centre_x - ring)
		var right := mini(_fine_width - 1, centre_x + ring)
		for y in range(maxi(0, top), mini(_fine_height - 1, bottom) + 1):
			if _fine_row_counts[y] == 0:
				continue
			var row_start := y * _fine_width
			var edge_row := y == top or y == bottom
			var x := left
			while x <= right:
				if not edge_row and x != centre_x - ring and x != centre_x + ring:
					# Interior of the ring was scanned by an earlier ring: jump to
					# the right-hand column.
					x = centre_x + ring
					continue
				var body := _fine_heads[row_start + x]
				while body >= 0:
					var distance := positions[body].distance_squared_to(origin)
					if distance < best_distance or (distance == best_distance and best != null and body < best_index):
						var enemy := bodies[body]
						if is_instance_valid(enemy) and not enemy.dead and not (check_excluded and enemy in excluded):
							best_distance = distance
							best = enemy
							best_index = body
					body = _fine_next[body]
				x += 1
		# Distance from the origin to the nearest edge of the square scanned so far.
		var clearance := (float(ring) + minf(minf(local.x, 1.0 - local.x), minf(local.y, 1.0 - local.y))) * size - DRIFT_MARGIN
		if clearance > 0.0:
			var clearance_squared := clearance * clearance
			if clearance_squared >= best_distance:
				break
		ring += 1
	return best


## Stops bodies standing inside each other.
##
## Enemies all walk at the nearest survivor along their own straight line, so
## anything spawned on a similar bearing converges into one stack: twenty mice
## occupying one mouse's worth of screen, dealing twenty mice's worth of contact
## damage from a single silhouette. A crowd that cannot be read cannot be
## fought.
##
## Walks the buckets rather than querying per body, samples a bounded number of
## partners per body so a pile cannot go quadratic, and resolves on the flat
## arrays; only bodies that actually moved are written back to their nodes.
## Survivors are solid one way: an enemy is pushed out of a cat, never the
## other way round.
func separate(players: Array) -> void:
	# Advanced per call rather than read from the physics frame counter: inside
	# one tick the frame number is constant, so every body sampled the same
	# neighbours and a deep pile took dozens of frames to unstick, or never did.
	_phase += 1
	var count := bodies.size()
	_moved.resize(count)
	_moved.fill(0)
	var slack := CROWD_OVERLAP_SLACK
	for key: int in cells:
		var bucket: Array = cells[key]
		var bucket_size := bucket.size()
		var own_samples := mini(CROWD_SAMPLES, bucket_size - 1)
		var cell_x := float((key >> KEY_SHIFT) - KEY_OFFSET)
		var cell_y := float((key & KEY_MASK) - KEY_OFFSET)
		for slot in bucket_size:
			var a: int = bucket[slot]
			if flags[a] & FLAG_SCENERY:
				continue
			var at := positions[a]
			var divisor := CROWD_UPDATE_DIVISOR if view_rect.has_point(at) else OFFSCREEN_DIVISOR
			if (batches[a] + _phase) % divisor != 0:
				continue
			var radius := radii[a]
			for sample in own_samples:
				var b: int = bucket[(slot + 1 + sample * 3 + _phase) % bucket_size]
				if b == a or flags[b] & FLAG_SCENERY:
					continue
				var reach := (radius + radii[b]) * slack
				if (positions[b] - at).length_squared() < reach * reach:
					_resolve(a, b)
					at = positions[a]
			# A body in the middle of its own cell cannot touch anything in the
			# next one, so the neighbour walk only runs near a boundary. Exact:
			# the reach is the widest overlap the grid currently holds.
			var edge := (radius + max_radius) * slack
			var local_x := at.x - cell_x * cell_size
			var local_y := at.y - cell_y * cell_size
			var near_right := local_x > cell_size - edge
			var near_bottom := local_y > cell_size - edge
			var near_top := local_y < edge
			if not (near_right or near_bottom or near_top):
				continue
			for offset in CROWD_NEIGHBOURS:
				if (offset.x == 1 and not near_right) or (offset.y == 1 and not near_bottom) or (offset.y == -1 and not near_top):
					continue
				var neighbour: Variant = cells.get(((int(cell_x) + offset.x + KEY_OFFSET) << KEY_SHIFT) | (int(cell_y) + offset.y + KEY_OFFSET))
				if neighbour == null:
					continue
				var other_bucket: Array = neighbour
				var other_size := other_bucket.size()
				for sample in mini(CROWD_NEIGHBOUR_SAMPLES, other_size):
					var b: int = other_bucket[(sample * 3 + _phase + slot) % other_size]
					if flags[b] & FLAG_SCENERY:
						continue
					var reach := (radius + radii[b]) * slack
					if (positions[b] - at).length_squared() < reach * reach:
						_resolve(a, b)
						at = positions[a]
	for player in players:
		var centre: Vector2 = player.global_position
		var player_radius: float = player.radius
		var minimum := _cell_of(centre - Vector2.ONE * (player_radius + 64.0)).max(occupied_min)
		var maximum := _cell_of(centre + Vector2.ONE * (player_radius + 64.0)).min(occupied_max)
		for x in range(minimum.x, maximum.x + 1):
			for y in range(minimum.y, maximum.y + 1):
				var bucket: Variant = cells.get(((x + KEY_OFFSET) << KEY_SHIFT) | (y + KEY_OFFSET))
				if bucket == null:
					continue
				for body: int in bucket:
					if flags[body] != 0 or bodies[body].boss:
						continue
					var offset := positions[body] - centre
					var overlap := player_radius + radii[body] - offset.length()
					if overlap <= 0.0:
						continue
					var direction := offset.normalized() if offset.length_squared() > 0.01 else Vector2.from_angle(randf() * TAU)
					positions[body] += direction * overlap
					_moved[body] = 1
	for body in count:
		if _moved[body]:
			bodies[body].position = positions[body]


## Pushes two overlapping bodies apart, weighted by size so a mouse bounces off
## a bulwark rather than moving it. An immovable body (a boss) takes none of it.
func _resolve(a: int, b: int) -> void:
	var a_fixed := flags[a] & FLAG_IMMOVABLE != 0
	var b_fixed := flags[b] & FLAG_IMMOVABLE != 0
	if a_fixed and b_fixed:
		return
	var offset := positions[b] - positions[a]
	var ra := radii[a]
	var rb := radii[b]
	var minimum := (ra + rb) * CROWD_OVERLAP_SLACK
	var distance_squared := offset.length_squared()
	if distance_squared >= minimum * minimum:
		return
	var distance := sqrt(distance_squared)
	var direction := offset / distance if distance > 0.01 else Vector2.from_angle(randf() * TAU)
	var push := (minimum - distance) * CROWD_PUSH
	if not a_fixed:
		positions[a] -= direction * push * (1.0 if b_fixed else rb / (ra + rb))
		_moved[a] = 1
	if not b_fixed:
		positions[b] += direction * push * (1.0 if a_fixed else ra / (ra + rb))
		_moved[b] = 1


func _cell_of(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / cell_size), floori(at.y / cell_size))
