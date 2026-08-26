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

# --- landscape kit (hand-authored, built by tools/build_land_kit.py) --------
# Land is a tileset, not one texture stretched over a polygon: that is what
# makes two neighbouring Groves read as one region instead of two rectangles.
var land_tile := 32                     # rim/seam strip width
var land_rim := 18                      # how far a rim strip reaches outward
var land_fields: Dictionary = {}        # element -> Texture2D, one seamless field
var land_rims: Dictionary = {}          # "element:n" -> Array[Texture2D]
var land_corners: Dictionary = {}       # "element:nw" -> Texture2D
var land_faces: Dictionary = {}         # element -> Array[Texture2D]
var land_seams: Dictionary = {}         # "grove>cinder" -> Texture2D
var props: Dictionary = {}              # "element:name" -> Array[Texture2D]
var clash_art: Dictionary = {}          # "field" / "lane_mark:0" / "crack:1" ...
var ground_art: Dictionary = {}         # blends, foreground pieces, lighting
var ground_patches: Dictionary = {}     # element -> Array[Texture2D], anti-tiling
var card_art_frames: Dictionary = {}    # board/place/hand frames, gems, backs
var fx_strips: Dictionary = {}          # effect name -> Texture2D frame strip
var fx_meta: Dictionary = {}            # effect name -> {w, h, frames}
var prop_names: Dictionary = {}         # element -> Array[String]

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
    _load_land_kit()
    _load_clash_kit()
    _load_ground_kit()
    _load_card_frames()
    _load_fx()
    _loaded = true
    return true

const CLASH_DIR := "res://assets/art/board/clash"
const GROUND_DIR := "res://assets/art/board/ground"
const UI_DIR := "res://assets/art/ui"
const LAND_KIT_PATH := "res://data/land_kit_manifest.json"
const LAND_DIR := "res://assets/art/board/land"
const PROP_DIR := "res://assets/art/board/props"

## Load the authored landscape kit. Absent files simply leave an empty array,
## and the stage falls back to its procedural slab, same rule as everything else.
func _load_land_kit() -> void:
    land_fields.clear(); land_rims.clear(); land_corners.clear()
    land_faces.clear(); land_seams.clear(); props.clear(); prop_names.clear()
    var kit = _read_json(LAND_KIT_PATH)
    if kit is not Dictionary:
        return
    land_tile = int(kit.get("tile", 32))
    land_rim = int(kit.get("rim", 18))
    var rim_variants := int(kit.get("rim_variants", 3))
    for element_v in kit.get("elements", []):
        var element := String(element_v)
        land_fields[element] = _texture("%s/%s/field.png" % [LAND_DIR, element])
        for side_v in kit.get("edges", []):
            var side := String(side_v)
            var rims: Array[Texture2D] = []
            for v in range(rim_variants):
                var t := _texture("%s/%s/rim_%s_%d.png" % [LAND_DIR, element, side, v])
                if t != null: rims.append(t)
            land_rims["%s:%s" % [element, side]] = rims
        for corner_v in kit.get("corners", []):
            var corner := String(corner_v)
            land_corners["%s:%s" % [element, corner]] = _texture(
                "%s/%s/corner_%s.png" % [LAND_DIR, element, corner])
        var faces: Array[Texture2D] = []
        for suffix in ["", "_b"]:
            var fc := _texture("%s/%s/face%s.png" % [LAND_DIR, element, suffix])
            if fc != null: faces.append(fc)
        land_faces[element] = faces
    for pair in [["grove", "cinder"], ["cinder", "grove"], ["grove", "neutral"],
                 ["neutral", "grove"], ["cinder", "neutral"], ["neutral", "cinder"],
                 ["grove", "ashbloom"], ["cinder", "ashbloom"]]:
        var seam := _texture("%s/seam/%s_%s.png" % [LAND_DIR, pair[0], pair[1]])
        if seam != null: land_seams["%s>%s" % [pair[0], pair[1]]] = seam
    for element2 in ["grove", "cinder"]:
        var names: Array[String] = []
        for name_v in kit.get("%s_props" % element2, []):
            var name := String(name_v)
            var set: Array[Texture2D] = []
            for v2 in range(3):
                var pt := _texture("%s/%s/%s_%d.png" % [PROP_DIR, element2, name, v2])
                if pt != null: set.append(pt)
            if not set.is_empty():
                props["%s:%s" % [element2, name]] = set
                names.append(name)
        prop_names[element2] = names

# --- lookups ----------------------------------------------------------------

func creature(card_id: String) -> Texture2D:
    return _texture(String(creature_paths.get(card_id, "")))

func landmark(card_id: String) -> Texture2D:
    return _texture(String(landmark_paths.get(card_id, "")))

## A Place part-way through being built. Stages are derived from the finished
## building (tools/pixelart/construction.py) so they register with it exactly.
func landmark_stage(card_id: String, stage: int) -> Texture2D:
    var base := String(landmark_paths.get(card_id, ""))
    if base == "": return null
    if stage >= 3: return _texture(base)
    var tags: Array[String] = ["foundation", "stage1", "stage2"]
    var tag: String = tags[clampi(stage, 0, 2)]
    var staged := base.replace(".png", "_%s.png" % tag)
    var tex := _texture(staged)
    return tex if tex != null else _texture(base)

func landmark_passive(card_id: String) -> Texture2D:
    var base := String(landmark_paths.get(card_id, ""))
    if base == "": return null
    return _texture(base.replace(".png", "_passive.png"))

func terrain(terrain_id: String) -> Texture2D:
    return _texture(String(terrain_paths.get(terrain_id, "")))

func sanctuary(element: String) -> Texture2D:
    return _texture(String(sanctuary_paths.get(element, "")))

func commander_board(commander_id: String) -> Texture2D:
    return _texture(String(commander_board_paths.get(commander_id, "")))

func commander_portrait(commander_id: String) -> Texture2D:
    return _texture(String(commander_portrait_paths.get(commander_id, "")))

## The continuous ground: blend seams, framing scenery and lighting.
func _load_ground_kit() -> void:
    ground_art.clear()
    for name in ["cinder_neutral", "neutral_grove", "grove_neutral", "neutral_cinder"]:
        ground_art["blend:%s" % name] = _texture("%s/blend_%s.png" % [GROUND_DIR, name])
    for kind in ["roots", "branch", "rock"]:
        for v in range(2):
            ground_art["fg:%s:%d" % [kind, v]] = _texture("%s/fg_%s_%d.png" % [GROUND_DIR, kind, v])
    ground_art["light_pool"] = _texture("%s/light_pool.png" % GROUND_DIR)
    ground_art["card_shadow"] = _texture("%s/card_shadow.png" % GROUND_DIR)
    for element in ["grove", "cinder", "ashbloom", "neutral"]:
        ground_art["row_path:%s" % element] = _texture("%s/row_path_%s.png" % [GROUND_DIR, element])
        var patches: Array[Texture2D] = []
        for v in range(3):
            var pt := _texture("%s/patch_%s_%d.png" % [GROUND_DIR, element, v])
            if pt != null: patches.append(pt)
        ground_patches[element] = patches

func ground(key: String) -> Texture2D:
    return ground_art.get(key, null)

## A large ground patch, scattered at hashed positions to break the field's
## 128px repeat.
func ground_patch(element: String, variant: int) -> Texture2D:
    var set: Array = ground_patches.get(element, [])
    if set.is_empty(): return null
    return set[posmod(variant, set.size())]

func ground_blend(top: String, bottom: String) -> Texture2D:
    return ground_art.get("blend:%s_%s" % [top, bottom], null)

## Card frames. Board cards are what a played creature looks like lying on the
## battlefield; hand frames are what the player reads before committing.
func _load_card_frames() -> void:
    card_art_frames.clear()
    for element in ["life", "fire", "neutral"]:
        card_art_frames["board_plate:%s" % element] = _texture("%s/board_plate_%s.png" % [UI_DIR, element])
        card_art_frames["board_frame:%s" % element] = _texture("%s/board_frame_%s.png" % [UI_DIR, element])
        card_art_frames["place_frame:%s" % element] = _texture("%s/place_frame_%s.png" % [UI_DIR, element])
        card_art_frames["card_back:%s" % element] = _texture("%s/card_back_%s.png" % [UI_DIR, element])
        for role in ["creature", "place", "spell", "realm"]:
            card_art_frames["hand_frame:%s:%s" % [element, role]] = _texture(
                "%s/hand_frame_%s_%s.png" % [UI_DIR, element, role])
    for kind in ["cost", "power", "health", "presence", "attack"]:
        card_art_frames["gem:%s" % kind] = _texture("%s/gem_%s.png" % [UI_DIR, kind])

## The shared Life/Fire effect library. Each entry is one horizontal strip of
## frames; the stage plays a window across it.
func _load_fx() -> void:
    fx_strips.clear(); fx_meta.clear()
    var manifest = _read_json("res://data/vfx_manifest.json")
    if manifest is not Dictionary: return
    var effects = manifest.get("effects", {})
    for name in effects:
        var tex := _texture("res://assets/art/fx/%s.png" % String(name))
        if tex != null:
            fx_strips[String(name)] = tex
            fx_meta[String(name)] = effects[name]

func fx(name: String) -> Texture2D:
    return fx_strips.get(name, null)

## The source rect for one frame of an effect, given progress 0..1.
func fx_frame(name: String, t: float) -> Rect2:
    var meta = fx_meta.get(name, null)
    if meta == null: return Rect2()
    var count := int(meta.get("frames", 1))
    var w := float(meta.get("w", 0))
    var h := float(meta.get("h", 0))
    var index := clampi(int(t * float(count)), 0, count - 1)
    return Rect2(float(index) * w, 0.0, w, h)

func has_fx() -> bool:
    return not fx_strips.is_empty()

func frame(key: String) -> Texture2D:
    return card_art_frames.get(key, null)

func has_card_frames() -> bool:
    return card_art_frames.get("board_plate:life", null) != null

## The neutral clash-zone kit: the middle strip is a real place, not a divider.
func _load_clash_kit() -> void:
    clash_art.clear()
    clash_art["field"] = _texture("%s/field.png" % CLASH_DIR)
    for i in range(4):
        clash_art["lane_mark:%d" % i] = _texture("%s/lane_mark_%d.png" % [CLASH_DIR, i])
    for v in range(3):
        clash_art["crack:%d" % v] = _texture("%s/crack_%d.png" % [CLASH_DIR, v])
        clash_art["rubble:%d" % v] = _texture("%s/rubble_%d.png" % [CLASH_DIR, v])
        clash_art["kerb:%d" % v] = _texture("%s/kerb_%d.png" % [CLASH_DIR, v])
        clash_art["decal_scorch:%d" % v] = _texture("%s/decal_scorch_%d.png" % [CLASH_DIR, v])
        clash_art["decal_growth:%d" % v] = _texture("%s/decal_growth_%d.png" % [CLASH_DIR, v])
    for element in ["life", "fire"]:
        clash_art["influence:%s" % element] = _texture("%s/influence_%s.png" % [CLASH_DIR, element])

func clash(key: String, variant := -1) -> Texture2D:
    if variant < 0: return clash_art.get(key, null)
    return clash_art.get("%s:%d" % [key, variant], null)

func has_clash_kit() -> bool:
    return clash_art.get("field", null) != null

## True once the authored landscape kit is on disk; the stage uses this to
## decide between tiled land and the old procedural slab.
func has_land_kit(element: String) -> bool:
    return land_fields.get(element, null) != null

## The seamless ground field. Tiled with continuous UVs so a realm is one
## surface, not a grid.
func land_field(element: String) -> Texture2D:
    return land_fields.get(element, null)

## An organic rim strip. Rims are additive — they extend the land outward past
## the field rect, because immediate-mode drawing cannot cut a hole in a rect.
func land_rim_tex(element: String, side: String, variant := 0) -> Texture2D:
    var set: Array = land_rims.get("%s:%s" % [element, side], [])
    if set.is_empty(): return null
    return set[posmod(variant, set.size())]

func land_corner(element: String, corner: String) -> Texture2D:
    return land_corners.get("%s:%s" % [element, corner], null)

func land_face(element: String, variant := 0) -> Texture2D:
    var set: Array = land_faces.get(element, [])
    if set.is_empty(): return null
    return set[posmod(variant, set.size())]

func land_seam(left: String, right: String) -> Texture2D:
    return land_seams.get("%s>%s" % [left, right], null)

## A decorative prop sprite. `which` and `variant` are hashes from the caller,
## so a field of five mushrooms is five different mushrooms.
func prop(element: String, name: String, variant := 0) -> Texture2D:
    var set: Array = props.get("%s:%s" % [element, name], [])
    if set.is_empty(): return null
    return set[posmod(variant, set.size())]

func prop_kinds(element: String) -> Array:
    return prop_names.get(element, [])

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
