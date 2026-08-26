class_name ContentV3
extends RefCounted
## Loader for the V3 Life/Fire set (data/v3_*.json, authored by
## tools/build_v3_content.py).
##
## V3 is a separate set rather than a filter over core_set.json because its
## costs are element-specific and cap at 4 — you hold at most four Landscapes,
## so the V1/V2 curve that ran to 8 simply does not fit. Card IDs are shared
## with the old set on purpose, so every sprite and portrait already produced
## resolves without a second art pass.

var cards: Dictionary = {}          # card_id -> Dictionary
var fusions: Array = []
var commanders: Dictionary = {}     # commander_id -> Dictionary
var decks: Dictionary = {}          # deck_id -> Dictionary
var loaded := false

func load_all() -> bool:
    cards.clear(); fusions.clear(); commanders.clear(); decks.clear()
    var card_rows = _read("res://data/v3_set.json")
    if card_rows is not Array: return false
    for row in card_rows:
        cards[String(row.get("id", ""))] = row
    var fusion_rows = _read("res://data/v3_fusions.json")
    if fusion_rows is Array: fusions = fusion_rows
    var commander_rows = _read("res://data/v3_commanders.json")
    if commander_rows is Array:
        for row2 in commander_rows:
            commanders[String(row2.get("id", ""))] = row2
    var deck_rows = _read("res://data/v3_decks.json")
    if deck_rows is Array:
        for row3 in deck_rows:
            decks[String(row3.get("id", ""))] = row3
    loaded = not cards.is_empty()
    return loaded

func card(card_id: String) -> Dictionary:
    var found = cards.get(card_id, null)
    return found if found is Dictionary else {}

func commander(commander_id: String) -> Dictionary:
    var found = commanders.get(commander_id, null)
    return found if found is Dictionary else {}

func deck(deck_id: String) -> Dictionary:
    var found = decks.get(deck_id, null)
    return found if found is Dictionary else {}

func fusion(recipe_id: String) -> Dictionary:
    for recipe in fusions:
        if String(recipe.get("id", "")) == recipe_id: return recipe
    return {}

func card_type(card_id: String) -> String:
    return String(card(card_id).get("type", ""))

func element_of(card_id: String) -> String:
    return String(card(card_id).get("element", ""))

func _read(path: String):
    if not FileAccess.file_exists(path): return null
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null: return null
    return JSON.parse_string(file.get_as_text())
