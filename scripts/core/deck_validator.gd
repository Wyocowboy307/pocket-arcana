class_name DeckValidator
extends RefCounted

func validate(deck: Dictionary, db: ContentDatabase) -> Array[String]:
    var errors: Array[String] = []
    var total := 0
    var seen := {}
    if not db.commanders.has(String(deck.get("commander_id", ""))):
        errors.append("Choose a valid Commander.")
    for entry in deck.get("cards", []):
        var card_id := String(entry.get("card_id", ""))
        var count := int(entry.get("count", 0))
        total += count
        seen[card_id] = int(seen.get(card_id, 0)) + count
        if not db.cards.has(card_id):
            errors.append("Missing card: " + card_id)
            continue
        var card: Dictionary = db.cards[card_id]
        var limit := 1 if String(card.get("rarity", "")) == "mythic" else 3
        if int(seen[card_id]) > limit:
            errors.append("Too many copies of " + String(card.get("name", card_id)) + ".")
    if total != 40:
        errors.append("A constructed deck needs exactly 40 cards.")
    return errors
