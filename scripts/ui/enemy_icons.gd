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
## The v2 sheet authors every creature facing right, including boss bodies.
## The standalone planter has no directional pose.
const FALLBACK := "chaser"
const FACING_FRONT := 0
const FACING_RIGHT := 1
const FACING_LEFT := -1
const SOURCE_FACING := {
	"chaser": FACING_RIGHT,
	"rat_runner": FACING_RIGHT,
	"hedgehog": FACING_RIGHT,
	"wasp": FACING_RIGHT,
	"mole": FACING_RIGHT,
	"swarm": FACING_RIGHT,
	"charger": FACING_RIGHT,
	"shooter": FACING_RIGHT,
	"chain_hunter": FACING_RIGHT,
	"bulwark": FACING_RIGHT,
	"brute": FACING_RIGHT,
	"owl": FACING_RIGHT,
	"planter": FACING_FRONT,
}

static var textures: Dictionary = {}


static func source_facing(id: String) -> int:
	return int(SOURCE_FACING.get(id, FACING_FRONT))


static func get_icon(id: String) -> Texture2D:
	if not textures.has(id):
		var path := "res://assets/sprites/enemies/%s.png" % id
		textures[id] = load(path) if ResourceLoader.exists(path) else null
	var art: Texture2D = textures[id]
	if art != null:
		return art
	return null if id == FALLBACK else get_icon(FALLBACK)
