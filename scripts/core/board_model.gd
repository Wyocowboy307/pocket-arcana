class_name BoardModel
extends RefCounted

const WIDTH := 7
const HEIGHT := 5
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
    for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
        var p := pos + d
        if in_bounds(p): out.append(p)
    return out

func can_shape(player: int, pos: Vector2i) -> bool:
    if not in_bounds(pos): return false
    var tile := get_tile(pos)
    if int(tile.get("owner", -1)) not in [-1, player]: return false
    if int(tile.get("sanctuary_owner", -1)) == player: return true
    for n in neighbors(pos):
        var nt := get_tile(n)
        if int(nt.get("owner", -1)) == player or int(nt.get("sanctuary_owner", -1)) == player:
            return true
    return false

func shape(player: int, pos: Vector2i, terrain: String) -> bool:
    if not can_shape(player, pos): return false
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

func realm_score(player: int) -> int:
    var score := 0
    for row in tiles:
        for tile in row:
            if int(tile.get("owner", -1)) == player:
                if String(tile.get("terrain", "neutral")) != "neutral": score += 1
                var lm = tile.get("landmark")
                if lm != null and int(lm.get("owner", -1)) == player:
                    score += int(lm.get("presence", 1))
            var creature = tile.get("creature")
            if creature != null and int(creature.get("owner", -1)) == player:
                score += max(0, int(creature.get("power", 0)))
    return score
