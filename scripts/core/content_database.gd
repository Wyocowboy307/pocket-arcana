class_name ContentDatabase
extends RefCounted

var cards: Dictionary = {}
var commanders: Dictionary = {}
var decks: Dictionary = {}
var recipes: Array = []
var tokens: Dictionary = {}
var elements: Dictionary = {}
var terrain_attunement: Dictionary = {}
var keywords: Array = []
var tutorial: Dictionary = {}
var motion: Dictionary = {}
var fusion_recipes: Array = []

func load_all() -> bool:
    cards = _index_by_id(_load_json("res://data/core_set.json"))
    commanders = _index_by_id(_load_json("res://data/commanders.json"))
    decks = _index_by_id(_load_json("res://data/starter_decks.json"))
    recipes = _load_json("res://data/combo_recipes.json")
    tokens = _index_by_id(_load_json("res://data/tokens.json"))
    elements = _index_by_id(_load_json("res://data/elements.json"))
    terrain_attunement = _load_json("res://data/terrain_attunement.json")
    keywords = _load_json("res://data/keywords.json")
    var tut = _load_json("res://data/tutorial_steps.json")
    tutorial = tut if tut is Dictionary else {}
    var mo = _load_json("res://data/creature_motion.json")
    motion = mo if mo is Dictionary else {}
    var fr = _load_json("res://data/v2_fusion_recipes.json")
    fusion_recipes = fr if fr is Array else []
    return not cards.is_empty() and not commanders.is_empty() and not decks.is_empty()

func get_card(card_id: String) -> Dictionary:
    return cards.get(card_id, {})

func get_commander(commander_id: String) -> Dictionary:
    return commanders.get(commander_id, {})

func get_deck(deck_id: String) -> Dictionary:
    return decks.get(deck_id, {})

func get_token(token_id: String) -> Dictionary:
    return tokens.get(token_id, {})

func _index_by_id(items) -> Dictionary:
    var out := {}
    if items is Array:
        for item in items:
            if item is Dictionary and item.has("id"):
                out[String(item["id"])] = item
    return out

func _load_json(path: String):
    if not FileAccess.file_exists(path):
        push_error("Pocket Arcana missing content file: " + path)
        return []
    var file := FileAccess.open(path, FileAccess.READ)
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null:
        push_error("Pocket Arcana invalid JSON: " + path)
        return []
    return parsed
