class_name ProximityMine
extends Node2D

## Ordnance the pair leaves behind them. Every other weapon in the roster fires
## outward from where a survivor is standing; this one turns the ground they
## have already crossed into a threat, which is the only weapon that rewards
## retreating through your own path.
##
## The mine owns its timers but not its damage: it reports a detonation and the
## weapon controller resolves it, so mines go through the same area-damage and
## effect code as everything else rather than duplicating it.

signal detonated(centre: Vector2, damage: float, radius: float, color: Color)

const ARM_TIME := 0.45 ## Cannot be used as an instant nova at point blank.
const LIFETIME := INF ## Persists until triggered or replaced by the placement cap.
## Wide enough that walking past a mine sets it off. At the original 46px an
## enemy could pass within its own body width and survive.
const TRIGGER_RADIUS := 64.0

var damage := 26.0
var blast_radius := 84.0
var mine_color := Color("bdb2ff")
var armed := false
var age := 0.0
var spatial_grid: EnemySpatialGrid
var spent := false
var owner_index := -1


func configure(new_damage: float, new_radius: float, color: Color, new_owner := -1) -> void:
	damage = new_damage
	blast_radius = new_radius
	mine_color = color
	armed = false
	age = 0.0
	spent = false
	owner_index = new_owner
	z_index = -1
	queue_redraw()


func _physics_process(delta: float) -> void:
	if spent:
		return
	age += delta
	if not armed and age >= ARM_TIME:
		armed = true
		queue_redraw()
	if not armed:
		scale = Vector2.ONE * lerpf(0.55, 1.0, clampf(age / ARM_TIME, 0.0, 1.0))
		rotation = -age * 2.6
		return
	# Rotation and modulate are node properties, so the sigil turns and the
	# danger halo breathes without a single redraw. 결계 지뢰 used to be two flat
	# circles that never moved after arming, which is why a field of them read
	# as debris rather than as something about to go off.
	rotation += delta * 0.9
	modulate.a = 0.78 + 0.22 * sin(age * 4.4)
	if spatial_grid == null:
		return
	for enemy in spatial_grid.query_radius(global_position, TRIGGER_RADIUS + 40.0):
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		if global_position.distance_to(enemy.global_position) <= TRIGGER_RADIUS + enemy.radius:
			_detonate()
			return


func _detonate() -> void:
	if spent:
		return
	spent = true
	detonated.emit(global_position, damage, blast_radius, mine_color)
	queue_free()


func force_detonate() -> void:
	armed = true
	_detonate()


## A ward sigil, not a dot. Unarmed mines stay hollow and unlit so a survivor
## can still tell at a glance which of the things underfoot will actually go off.
## Nothing here reads the clock: the turning comes from the node rotation and the
## breathing from its modulate, so a screenful of mines costs one draw each.
func _draw() -> void:
	if not armed:
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color(mine_color, 0.4), 2.0, true)
		for spoke in 3:
			var angle := TAU * float(spoke) / 3.0
			draw_line(Vector2.from_angle(angle) * 5.0, Vector2.from_angle(angle) * 11.0,
				Color(mine_color, 0.3), 1.6, true)
		return

	draw_circle(Vector2.ZERO, 26.0, Color(mine_color, 0.09))
	# Outer rune ring: six notches on a broken circle.
	for notch in 6:
		var start := TAU * float(notch) / 6.0
		draw_arc(Vector2.ZERO, 18.0, start + 0.16, start + TAU / 6.0 - 0.16, 6,
			Color(mine_color, 0.62), 2.4, true)
		draw_circle(Vector2.from_angle(start) * 18.0, 2.4, Color(mine_color.lightened(0.35), 0.9))
	# Inner sigil: two counter-set triangles around a bright core.
	for flip in 2:
		var offset := PI * float(flip)
		var points := PackedVector2Array()
		for corner in 3:
			points.append(Vector2.from_angle(offset + TAU * float(corner) / 3.0) * 11.0)
		draw_polyline(points + PackedVector2Array([points[0]]), Color(mine_color, 0.72), 2.0, true)
	draw_circle(Vector2.ZERO, 6.0, Color(mine_color, 0.9))
	draw_circle(Vector2.ZERO, 3.0, Color(mine_color.lightened(0.7), 1.0))
