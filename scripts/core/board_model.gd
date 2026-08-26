class_name BoardModel
extends RefCounted

const WIDTH := 7
const HEIGHT := 5
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var tiles: Array = []
var next_unit_id := 1

func _init() -> void:
    reset()

func reset() -> void:
    tiles.clear()
    for y in range(HEIGHT):
        var row: Array = []
        for x in range(WIDTH):
            row.append({
                "x": x, "y": y, "owner": -1,
                "terrain": "neutral", "states": [],
                "creature": null, "landmark": null,
                "sanctuary_owner": -1
            })
        tiles.append(row)
    get_tile(Vector2i(3, 4))["sanctuary_owner"] = 0
    get_tile(Vector2i(3, 0))["sanctuary_owner"] = 1

func get_tile(pos: Vector2i) -> Dictionary:
    if not in_bounds(pos):
        return {}
    return tiles[pos.y][pos.x]

func in_bounds(pos: Vector2i) -> bool:
    return pos.x >= 0 and pos.x < WIDTH and pos.y >= 0 and pos.y < HEIGHT

func neighbors(pos: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for d in DIRECTIONS:
        var p: Vector2i = pos + d
        if in_bounds(p): out.append(p)
    return out

func can_shape(player: int, pos: Vector2i, terrain: String = "") -> bool:
    if not in_bounds(pos): return false
    var tile := get_tile(pos)
    if int(tile.get("owner", -1)) not in [-1, player]: return false
    # Shaping is a whole turn: it must actually change the tile.
    if terrain != "" and int(tile.get("owner", -1)) == player and String(tile.get("terrain", "neutral")) == terrain:
        return false
    if int(tile.get("sanctuary_owner", -1)) == player: return true
    for n in neighbors(pos):
        var nt := get_tile(n)
        if int(nt.get("owner", -1)) == player or int(nt.get("sanctuary_owner", -1)) == player:
            return true
    return false

func shape(player: int, pos: Vector2i, terrain: String) -> bool:
    if not can_shape(player, pos, terrain): return false
    var tile := get_tile(pos)
    tile["owner"] = player
    tile["terrain"] = terrain
    return true

func add_state(pos: Vector2i, state: String) -> bool:
    var tile := get_tile(pos)
    if tile.is_empty(): return false
    var states: Array = tile["states"]
    if not states.has(state):
        states.append(state)
        return true
    return false

func clear_creatures_for_new_chapter() -> void:
    for row in tiles:
        for tile in row:
            tile["creature"] = null

## Realm Score, split so the UI can explain where a Chapter result came from.
## Rules v1: creature Power + landmark Presence + 1 per shaped tile you control.
func realm_score_breakdown(player: int) -> Dictionary:
    var terrain_points := 0
    var landmark_points := 0
    var creature_points := 0
    var tiles_held := 0
    for row in tiles:
        for tile in row:
            if int(tile.get("owner", -1)) == player:
                tiles_held += 1
                if String(tile.get("terrain", "neutral")) != "neutral": terrain_points += 1
                var lm = tile.get("landmark")
                if lm != null and int(lm.get("owner", -1)) == player:
                    landmark_points += int(lm.get("presence", 1))
            var creature = tile.get("creature")
            if creature != null and int(creature.get("owner", -1)) == player:
                creature_points += max(0, int(creature.get("power", 0)))
    return {
        "terrain": terrain_points,
        "landmarks": landmark_points,
        "creatures": creature_points,
        "tiles_held": tiles_held,
        "total": terrain_points + landmark_points + creature_points,
    }

func realm_score(player: int) -> int:
    return int(realm_score_breakdown(player)["total"])
