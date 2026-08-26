class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://pocket_arcana_profile_v1.json"
const SAVE_VERSION := 1

func default_profile() -> Dictionary:
    return {
        "version": SAVE_VERSION,
        "coins": 0,
        "owned_cards": {},
        "unlocked_commanders": [],
        "commander_mastery": {},
        "discovered_recipes": [],
        "discovered_terrain": [],
        "defeated_opponents": [],
        "completed_encounters": [],
        "custom_decks": [],
        "cosmetics": [],
        "settings": {"tutorial_hints": true, "recipe_previews": true}
    }

func load_profile() -> Dictionary:
    if not FileAccess.file_exists(SAVE_PATH):
        return default_profile()
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is not Dictionary:
        push_warning("Pocket Arcana save was unreadable; using a fresh profile without deleting the old file.")
        return default_profile()
    return _migrate(parsed)

func save_profile(profile: Dictionary) -> bool:
    var copy := profile.duplicate(true)
    copy["version"] = SAVE_VERSION
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        push_error("Could not open Pocket Arcana save path for writing.")
        return false
    file.store_string(JSON.stringify(copy, "  "))
    return true

func grant_card(profile: Dictionary, card_id: String, amount: int = 1) -> void:
    var owned: Dictionary = profile.get("owned_cards", {})
    owned[card_id] = int(owned.get(card_id, 0)) + max(0, amount)
    profile["owned_cards"] = owned

func unlock_commander(profile: Dictionary, commander_id: String) -> void:
    var unlocked: Array = profile.get("unlocked_commanders", [])
    if not unlocked.has(commander_id):
        unlocked.append(commander_id)
    profile["unlocked_commanders"] = unlocked

func discover_recipe(profile: Dictionary, recipe_id: String) -> bool:
    var found: Array = profile.get("discovered_recipes", [])
    if found.has(recipe_id):
        return false
    found.append(recipe_id)
    profile["discovered_recipes"] = found
    return true

func add_coins(profile: Dictionary, amount: int) -> void:
    profile["coins"] = max(0, int(profile.get("coins", 0)) + amount)

func add_commander_mastery(profile: Dictionary, commander_id: String, xp: int) -> void:
    var mastery: Dictionary = profile.get("commander_mastery", {})
    mastery[commander_id] = max(0, int(mastery.get(commander_id, 0)) + xp)
    profile["commander_mastery"] = mastery

func _migrate(profile: Dictionary) -> Dictionary:
    # v1 is the first schema. Future versions should migrate forward here without wiping collections.
    var base := default_profile()
    for key in base:
        if not profile.has(key):
            profile[key] = base[key]
    profile["version"] = SAVE_VERSION
    return profile
