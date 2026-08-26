class_name ComboResolver
extends RefCounted

var recipes: Array = []
var terrain_attunement: Dictionary = {}

func setup(recipe_data: Array, attunement_data: Dictionary) -> void:
    recipes = recipe_data
    terrain_attunement = attunement_data

func resolve_tile(board: BoardModel, pos: Vector2i) -> Array:
    var events: Array = []
    var tile := board.get_tile(pos)
    if tile.is_empty(): return events
    var states: Array = tile.get("states", [])
    for recipe in recipes:
        var need: Array = recipe.get("states", [])
        if need.size() != 2: continue
        if states.has(need[0]) and states.has(need[1]):
            var result := String(recipe.get("result_terrain", ""))
            if result != "" and String(tile.get("terrain", "")) != result:
                tile["terrain"] = result
                events.append({"type":"recipe","recipe_id":recipe.get("id",""),"name":recipe.get("name",result),"pos":pos,"wonder":int(recipe.get("wonder",0))})
            break
    return events
