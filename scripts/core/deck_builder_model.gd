class_name DeckBuilderModel
extends RefCounted

var db: ContentDatabase
var validator := DeckValidator.new()
var commander_id := ""
var counts: Dictionary = {}
var deck_name := "New Deck"

func setup(content: ContentDatabase, initial_commander_id: String = "") -> void:
    db = content
    commander_id = initial_commander_id
    counts.clear()

func set_commander(value: String) -> bool:
    if not db.commanders.has(value):
        return false
    commander_id = value
    return true

func add_card(card_id: String) -> Dictionary:
    var card := db.get_card(card_id)
    if card.is_empty(): return {"ok":false,"reason":"Unknown card."}
    var limit := 1 if String(card.get("rarity","")) == "mythic" else 3
    var current := int(counts.get(card_id, 0))
    if current >= limit: return {"ok":false,"reason":"Copy limit reached."}
    if total_cards() >= 40: return {"ok":false,"reason":"Deck is already 40 cards."}
    counts[card_id] = current + 1
    return {"ok":true}

func remove_card(card_id: String) -> bool:
    var current := int(counts.get(card_id, 0))
    if current <= 0: return false
    if current == 1: counts.erase(card_id)
    else: counts[card_id] = current - 1
    return true

func total_cards() -> int:
    var total := 0
    for count in counts.values(): total += int(count)
    return total

func to_deck_definition() -> Dictionary:
    var entries: Array = []
    var ids := counts.keys(); ids.sort()
    for card_id in ids:
        entries.append({"card_id":card_id,"count":counts[card_id]})
    return {"id":"custom","name":deck_name,"commander_id":commander_id,"cards":entries}

func validate() -> Array[String]:
    return validator.validate(to_deck_definition(), db)

func filtered_cards(search: String = "", element: String = "", type_filter: String = "", max_cost: int = -1) -> Array:
    var out: Array = []
    var needle := search.strip_edges().to_lower()
    for card in db.cards.values():
        if needle != "" and needle not in String(card.get("name","")).to_lower() and needle not in String(card.get("rules","")).to_lower(): continue
        if element != "" and not card.get("elements",[]).has(element): continue
        if type_filter != "" and String(card.get("type","")) != type_filter: continue
        if max_cost >= 0 and int(card.get("cost",0)) > max_cost: continue
        out.append(card)
    out.sort_custom(func(a,b):
        var cost_a := int(a.get("cost",0)); var cost_b := int(b.get("cost",0))
        if cost_a == cost_b: return String(a.get("name","")).naturalnocasecmp_to(String(b.get("name",""))) < 0
        return cost_a < cost_b
    )
    return out
