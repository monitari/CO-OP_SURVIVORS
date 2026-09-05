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
		return
	rotation += delta * 0.42
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


func _draw() -> void:
	# Unarmed mines read as hollow so a survivor can tell at a glance which of
	# the things underfoot will actually go off.
	var pulse := 0.5 + 0.5 * sin(age * 9.0)
	if armed:
		draw_circle(Vector2.ZERO, 11.0, Color(mine_color, 0.85))
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 20, Color(mine_color, 0.35 + pulse * 0.4), 2.5, true)
	else:
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 18, Color(mine_color, 0.55), 2.0, true)
