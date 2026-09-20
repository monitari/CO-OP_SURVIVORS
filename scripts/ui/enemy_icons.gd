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
## The checked-in art was produced in several poses: some silhouettes look to
## the right, while the bosses and several enemies face the camera. Record that
## authored pose instead of pretending every PNG faces +X. A future left-facing
## asset is supported too, without another renderer special case.
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
	"swarm": FACING_FRONT,
	"charger": FACING_FRONT,
	"shooter": FACING_FRONT,
	"chain_hunter": FACING_FRONT,
	"bulwark": FACING_FRONT,
	"brute": FACING_FRONT,
	"owl": FACING_FRONT,
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
