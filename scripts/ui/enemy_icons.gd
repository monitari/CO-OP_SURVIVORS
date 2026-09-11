extends RefCounted

## One PNG per archetype under assets/sprites/enemies/, named by the behaviour
## id the field asks for.
##
## The seven original enemies used to be cut out of a shared atlas at load time
## with hand-written normalized rectangles, because the generated sheet did not
## respect its own cell boundaries — a crow's wings crossed into the third cell.
## They are checked in as individual files now, so nothing has to know where a
## silhouette sits inside a sheet.
##
## Icons are stored tight to their content rather than padded square: Enemy
## scales its sprite by the texture's longer edge, so empty margin would shrink
## the enemy on the field.
##
## Directional silhouettes must face +X (right) in the source PNG. Enemy keeps
## the painted body upright and mirrors it for a leftward heading; normalizing
## the files here avoids archetype-specific facing exceptions in the hot path.
const FALLBACK := "chaser"

static var textures: Dictionary = {}


static func get_icon(id: String) -> Texture2D:
	if not textures.has(id):
		var path := "res://assets/sprites/enemies/%s.png" % id
		textures[id] = load(path) if ResourceLoader.exists(path) else null
	var art: Texture2D = textures[id]
	if art != null:
		return art
	return null if id == FALLBACK else get_icon(FALLBACK)
