class_name ArtRegistry
extends RefCounted
## Data-driven lookup from game IDs to production art.
##
## Every accessor returns null when the asset does not exist yet, and the views
## fall back to their procedural drawing. That lets art land one file at a time
## without breaking tests, which is the rule in docs/ART_PRODUCTION_PIPELINE.md.
##
## Art is presentation only. Nothing here may influence legality, coordinates,
## hitboxes, AI or determinism.

const MANIFEST_PATH := "res://data/vertical_slice_art_manifest.json"

var creature_paths: Dictionary = {}     # card_id -> res:// path
var landmark_paths: Dictionary = {}     # card_id -> res:// path
var spell_paths: Dictionary = {}        # card_id -> res:// path
var terrain_paths: Dictionary = {}      # terrain_id -> res:// path
var sanctuary_paths: Dictionary = {}    # element -> res:// path
var commander_board_paths: Dictionary = {}
var commander_portrait_paths: Dictionary = {}
var ui_paths: Dictionary = {}
var source_sizes: Dictionary = {}       # id -> Vector2i, the authored canvas

var _cache: Dictionary = {}             # res:// path -> Texture2D (absent = never looked up)
var _loaded := false

func load_manifest() -> bool:
    creature_paths.clear(); landmark_paths.clear(); spell_paths.clear()
    terrain_paths.clear(); sanctuary_paths.clear(); ui_paths.clear()
    commander_board_paths.clear(); commander_portrait_paths.clear()
    source_sizes.clear(); _cache.clear()
    var manifest = _read_json(MANIFEST_PATH)
    if manifest is not Dictionary:
        return false

    for entry in manifest.get("creatures", []):
        var cid := String(entry.get("card_id", ""))
        creature_paths[cid] = _res(entry.get("path", ""))
        source_sizes[cid] = _size(entry.get("size", []))
    for entry in manifest.get("landmarks", []):
        var cid := String(entry.get("card_id", ""))
        landmark_paths[cid] = _res(entry.get("path", ""))
        source_sizes[cid] = _size(entry.get("size", []))
    for entry in manifest.get("spell_visuals", []):
        spell_paths[String(entry.get("card_id", ""))] = _res(entry.get("path", ""))
    for entry in manifest.get("terrain", []):
        var tid := String(entry.get("id", ""))
        terrain_paths[tid] = _res(entry.get("path", ""))
        source_sizes[tid] = _size(entry.get("size", []))
    for entry in manifest.get("sanctuaries", []):
        # ids are sanctuary_life / sanctuary_fire; key them by element.
        var sid := String(entry.get("id", ""))
        sanctuary_paths[sid.trim_prefix("sanctuary_")] = _res(entry.get("path", ""))
        source_sizes[sid] = _size(entry.get("size", []))
    for entry in manifest.get("commanders", []):
        var cid := String(entry.get("id", ""))
        commander_board_paths[cid] = _res(entry.get("board_avatar", ""))
        commander_portrait_paths[cid] = _res(entry.get("portrait", ""))
    for entry in manifest.get("ui", []):
        ui_paths[String(entry.get("id", ""))] = _res(entry.get("path", ""))
    _loaded = true
    return true

# --- lookups ----------------------------------------------------------------

func creature(card_id: String) -> Texture2D:
    return _texture(String(creature_paths.get(card_id, "")))

func landmark(card_id: String) -> Texture2D:
    return _texture(String(landmark_paths.get(card_id, "")))

func terrain(terrain_id: String) -> Texture2D:
    return _texture(String(terrain_paths.get(terrain_id, "")))

func sanctuary(element: String) -> Texture2D:
    return _texture(String(sanctuary_paths.get(element, "")))

func commander_board(commander_id: String) -> Texture2D:
    return _texture(String(commander_board_paths.get(commander_id, "")))

func commander_portrait(commander_id: String) -> Texture2D:
    return _texture(String(commander_portrait_paths.get(commander_id, "")))

func ui(icon_id: String) -> Texture2D:
    return _texture(String(ui_paths.get(icon_id, "")))

## Art for a card's central window: a spell's own scene, otherwise its board sprite.
func card_art(card_id: String) -> Texture2D:
    var spell := _texture(String(spell_paths.get(card_id, "")))
    if spell != null: return spell
    var body := creature(card_id)
    if body != null: return body
    return landmark(card_id)

func source_size(id: String, fallback: Vector2i = Vector2i(64, 64)) -> Vector2i:
    return source_sizes.get(id, fallback)

# --- coverage reporting (used by the art-status tool) -----------------------

func coverage() -> Dictionary:
    var groups := {
        "creatures": creature_paths, "landmarks": landmark_paths,
        "spells": spell_paths, "terrain": terrain_paths,
        "sanctuaries": sanctuary_paths, "commander_board": commander_board_paths,
        "commander_portrait": commander_portrait_paths, "ui": ui_paths,
    }
    var out := {}
    for name in groups:
        var present := 0
        var missing: Array[String] = []
        var paths: Dictionary = groups[name]
        for key in paths:
            if _texture(String(paths[key])) != null: present += 1
            else: missing.append(String(key))
        out[name] = {"present": present, "total": paths.size(), "missing": missing}
    return out

func is_loaded() -> bool:
    return _loaded

# --- internals --------------------------------------------------------------

## Missing art is the normal state during production, so this never pushes an error.
func _texture(path: String) -> Texture2D:
    if path == "": return null
    if _cache.has(path): return _cache[path]
    var tex: Texture2D = null
    if ResourceLoader.exists(path):
        var res := ResourceLoader.load(path)
        if res is Texture2D: tex = res
    _cache[path] = tex
    return tex

func _res(path) -> String:
    var p := String(path)
    if p == "": return ""
    return p if p.begins_with("res://") else "res://" + p

func _size(raw) -> Vector2i:
    if raw is Array and raw.size() >= 2: return Vector2i(int(raw[0]), int(raw[1]))
    return Vector2i(64, 64)

func _read_json(path: String):
    if not FileAccess.file_exists(path): return null
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null: return null
    return JSON.parse_string(file.get_as_text())
