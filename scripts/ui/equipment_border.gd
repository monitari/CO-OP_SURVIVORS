extends Control

const SILVER := Color("d4dde7")
var game: Node
var owner_slot := 0
var item_slot := 0
var weapon := true
var progress := 0.0
var continuous := false
var phase := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh() -> void:
	var loadout: Array = game.weapon_loadouts[owner_slot] if weapon else game.treasure_loadouts[owner_slot]
	visible = item_slot < loadout.size()
	if not visible:
		return
	var state: Dictionary = loadout[item_slot]
	continuous = not weapon or String(state.get("weapon_id", "")) == "frost"
	var art: TextureRect = get_parent().get_parent().get_node("%s%d" % ["Weapon" if weapon else "Treasure", item_slot])
	var tier: Label = art.get_node("Tier")
	tier.text = str(int(state.get("tier", 1)))
	tier.add_theme_color_override("font_color", SILVER)
	# The ring is this weapon's own cooldown, always. It used to switch to the
	# resonance's cooldown for a weapon a resonance was firing for, because that
	# weapon had stopped attacking and its own timer meant nothing. Weapons keep
	# attacking through a resonance now, so the ring showing anything but their
	# own next shot would be the ring lying about when they fire.
	if weapon and not continuous:
		var timers: Array = game.attack_timers[owner_slot]
		var remaining: float = float(timers[item_slot]) if item_slot < timers.size() else 0.0
		progress = 1.0 - remaining / maxf(0.01, game._weapon_interval(owner_slot, item_slot))
	else:
		progress = 1.0
	phase = fposmod(float(game.elapsed) * 0.45, 1.0)
	progress = clampf(progress, 0.0, 1.0)
	queue_redraw()

func _process(_delta: float) -> void:
	if is_instance_valid(game) and get_parent().is_visible_in_tree():
		refresh()

func point_at(t: float) -> Vector2:
	var corners := [Vector2(size.x * 0.5, 2), Vector2(size.x - 2, 2), Vector2(size.x - 2, size.y - 2), Vector2(2, size.y - 2), Vector2(2, 2), Vector2(size.x * 0.5, 2)]
	var lengths := [0.125, 0.25, 0.25, 0.25, 0.125]
	var part := fposmod(t, 1.0)
	for i in lengths.size():
		if part <= lengths[i]:
			return corners[i].lerp(corners[i + 1], part / lengths[i])
		part -= lengths[i]
	return corners[0]

func _draw() -> void:
	for i in 96:
		var t := float(i) / 96.0
		var strength := 1.0
		if continuous:
			strength = 0.25 + 0.75 * (1.0 - fposmod(phase - t, 1.0))
		elif t > progress:
			strength = 0.12
		draw_line(point_at(t), point_at(t + 1.0 / 96.0), Color(SILVER, strength), 2.0, true)
