class_name BoardView
extends Control
## Draws the 7x5 living board and reports clicks. It renders whatever the
## simulation currently holds and never decides a rule; events only add
## transient flourishes on top (ANIMATION_BIBLE).

signal tile_clicked(pos: Vector2i)
signal tile_hovered(pos: Vector2i)

const GAP := 6.0

var engine: MatchEngine
var art: ArtRegistry                 # may be null; every use falls back to drawing
var highlights: Dictionary = {}      # Vector2i -> "target" | "move" | "attack" | "heart"
var selected_pos := Vector2i(-1, -1)
var hover_pos := Vector2i(-1, -1)

var _flourishes: Array = []          # transient visual effects, purely cosmetic
var _pulse := 0.0
var _shake := 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_process(true)

func _process(delta: float) -> void:
    _pulse = fmod(_pulse + delta, 1.0)
    if _shake > 0.0: _shake = maxf(0.0, _shake - delta * 4.0)
    var alive: Array = []
    for f in _flourishes:
        f["t"] = float(f["t"]) + delta
        if float(f["t"]) < float(f["life"]): alive.append(f)
    _flourishes = alive
    queue_redraw()

# --- geometry ---------------------------------------------------------------

## Short board punch for impactful plays (ANIMATION_BIBLE step 5).
func shake(strength: float = 1.0) -> void:
    _shake = clampf(_shake + strength, 0.0, 1.4)

func _board_rect() -> Rect2:
    var cols := float(BoardModel.WIDTH)
    var rows := float(BoardModel.HEIGHT)
    var tile_w: float = (size.x - GAP * (cols - 1)) / cols
    var tile_h: float = (size.y - GAP * (rows - 1)) / rows
    var tile: float = min(tile_w, tile_h * 1.5)
    var total_w: float = tile * cols + GAP * (cols - 1)
    var th: float = min(tile_h, tile / 1.5)
    var total_h: float = th * rows + GAP * (rows - 1)
    var jitter := Vector2.ZERO
    if _shake > 0.0:
        jitter = Vector2(sin(_shake * 47.0), cos(_shake * 39.0)) * _shake * 3.0
    return Rect2((size.x - total_w) * 0.5 + jitter.x, (size.y - total_h) * 0.5 + jitter.y, total_w, total_h)

func tile_rect(pos: Vector2i) -> Rect2:
    var board := _board_rect()
    var tw: float = (board.size.x - GAP * (BoardModel.WIDTH - 1)) / BoardModel.WIDTH
    var th: float = (board.size.y - GAP * (BoardModel.HEIGHT - 1)) / BoardModel.HEIGHT
    return Rect2(board.position.x + pos.x * (tw + GAP), board.position.y + pos.y * (th + GAP), tw, th)

func tile_at(point: Vector2) -> Vector2i:
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            if tile_rect(Vector2i(x, y)).has_point(point): return Vector2i(x, y)
    return Vector2i(-1, -1)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var pos := tile_at(event.position)
        if pos.x >= 0: tile_clicked.emit(pos)
    elif event is InputEventMouseMotion:
        var pos := tile_at(event.position)
        if pos != hover_pos:
            hover_pos = pos
            tile_hovered.emit(pos)
            queue_redraw()

# --- transient flourishes ---------------------------------------------------

const MAX_FLOURISHES := 7

func _push(f: Dictionary) -> void:
    _flourishes.append(f)
    while _flourishes.size() > MAX_FLOURISHES:
        _flourishes.pop_front()

func flash_tile(pos: Vector2i, color: Color, life: float = 0.45) -> void:
    _push({"kind": "flash", "pos": pos, "color": color, "t": 0.0, "life": life})

func float_text(pos: Vector2i, text: String, color: Color, life: float = 0.85) -> void:
    # Two identical labels on one tile just smear into each other.
    for f in _flourishes:
        if String(f["kind"]) == "text" and f["pos"] == pos and String(f["text"]) == text:
            return
    _push({"kind": "text", "pos": pos, "text": text, "color": color, "t": 0.0, "life": life})

func ring(pos: Vector2i, color: Color, life: float = 0.7) -> void:
    _push({"kind": "ring", "pos": pos, "color": color, "t": 0.0, "life": life})

func clear_flourishes() -> void:
    _flourishes.clear()

# --- drawing ----------------------------------------------------------------

func _draw() -> void:
    if engine == null or engine.board == null: return
    var f := ArcanaTheme.font()
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            _draw_tile(Vector2i(x, y), f)
    for fl in _flourishes:
        _draw_flourish(fl, f)

func _draw_tile(pos: Vector2i, f: Font) -> void:
    var rect := tile_rect(pos)
    var tile: Dictionary = engine.board.get_tile(pos)
    var owner := int(tile.get("owner", -1))
    var terrain := String(tile.get("terrain", "neutral"))
    var sanc := int(tile.get("sanctuary_owner", -1))

    # Ground: production terrain art when it exists, procedural panel otherwise.
    var ground: Color = ArcanaTheme.color_for_terrain(terrain)
    var edge: Color = ArcanaTheme.PANEL_EDGE
    var edge_w := 1
    if owner >= 0:
        edge = ArcanaTheme.owner_color(owner).darkened(0.15)
        edge_w = 2
    var ground_tex: Texture2D = null
    if art != null:
        ground_tex = art.sanctuary(_sanctuary_element(sanc)) if sanc >= 0 else null
        if ground_tex == null: ground_tex = art.terrain(terrain)
    if ground_tex != null:
        draw_texture_rect(ground_tex, rect, false)
        # Ownership stays legible without hiding the artwork.
        if owner >= 0:
            draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.owner_color(owner), 0.13), edge, 7, edge_w), rect)
        else:
            draw_style_box(ArcanaTheme.panel_box(Color(0, 0, 0, 0), edge, 7, edge_w), rect)
    else:
        var fill: Color = ArcanaTheme.TILE_EMPTY if terrain == "neutral" else ground.darkened(0.62)
        draw_style_box(ArcanaTheme.panel_box(fill, edge, 7, edge_w), rect)

    # Terrain name, always a word as well as a colour.
    var states: Array = tile.get("states", [])
    if terrain != "neutral" and ground_tex == null:
        var reserved: float = 14.0 + states.size() * 13.0
        draw_string(f, Vector2(rect.position.x + 7, rect.position.y + 15),
            ArcanaTheme.fit(ArcanaTheme.label_for_terrain(terrain), 11, rect.size.x - reserved - 8),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ground.lightened(0.25))

    # Element states as icon pips along the top-right.
    var pip_x := rect.position.x + rect.size.x - 12
    for state in states:
        var sc: Color = ArcanaTheme.color_for_state(String(state))
        draw_circle(Vector2(pip_x, rect.position.y + 11), 5.0, sc)
        draw_circle(Vector2(pip_x, rect.position.y + 11), 5.0, sc.darkened(0.4), false, 1.0)
        pip_x -= 13

    # Sanctuary marker.
    if sanc >= 0:
        var sc: Color = ArcanaTheme.owner_color(sanc)
        var heart: int = int(engine.players[sanc]["heart"]) if engine.players.size() > sanc else 0
        draw_string(f, Vector2(rect.position.x + 7, rect.position.y + rect.size.y - 8),
            "♥ %d" % heart, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ArcanaTheme.HEART)
        draw_string(f, Vector2(rect.position.x + 44, rect.position.y + rect.size.y - 9),
            "SANCTUARY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, sc.darkened(0.1))

    # Landmark sits on its own layer and can share the tile with a creature.
    var lm = tile.get("landmark")
    if lm != null:
        var lm_tex: Texture2D = art.landmark(String(lm.get("card_id", ""))) if art != null else null
        if lm_tex != null:
            # Behind the creature, so the two can share a tile.
            _draw_sprite(lm_tex, rect, 0.86, -4.0)
        elif tile.get("creature") == null:
            var lc: Color = ArcanaTheme.owner_color(int(lm.get("owner", -1)))
            draw_string(f, Vector2(rect.position.x + 7, rect.position.y + rect.size.y - 24),
                ArcanaTheme.fit("⌂ " + String(lm.get("name", "Landmark")), 10, rect.size.x - 14),
                HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lc)
        else:
            # A creature is on top; mark the landmark with a corner glyph only.
            draw_string(f, Vector2(rect.position.x + 5, rect.position.y + rect.size.y - 5), "⌂",
                HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.owner_color(int(lm.get("owner", -1))))

    # Creature chip.
    var unit = tile.get("creature")
    if unit != null:
        _draw_unit(rect, unit, f)

    # Selection and legality overlays.
    var hl := String(highlights.get(pos, ""))
    if hl != "":
        var glow: Color = ArcanaTheme.LEGAL
        if hl == "move": glow = ArcanaTheme.MOVE
        elif hl == "attack": glow = ArcanaTheme.ATTACK
        elif hl == "heart": glow = ArcanaTheme.HEART
        # Keep a strong floor: a legal tile must read as legal at any point in the pulse.
        var wave: float = 0.5 + 0.5 * sin(_pulse * TAU)
        draw_style_box(ArcanaTheme.panel_box(Color(glow, 0.16 + 0.12 * wave), Color(glow, 0.7 + 0.3 * wave), 7, 3), rect)
        if hl == "heart":
            draw_string(f, Vector2(rect.position.x + rect.size.x * 0.5 - 22, rect.position.y + rect.size.y * 0.5 + 6),
                "STRIKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ArcanaTheme.HEART)
    if pos == selected_pos:
        draw_style_box(ArcanaTheme.panel_box(Color(1, 1, 1, 0), Color(ArcanaTheme.GOLD, 0.95), 7, 3), rect)
    elif pos == hover_pos:
        draw_style_box(ArcanaTheme.panel_box(Color(1, 1, 1, 0), Color(ArcanaTheme.TEXT, 0.28), 7, 2), rect)

## Scale a source sprite to fit the tile without smoothing or distortion.
func _draw_sprite(tex: Texture2D, tile_rect_in: Rect2, fill_ratio: float, y_offset: float) -> void:
    var src := Vector2(tex.get_width(), tex.get_height())
    if src.x <= 0.0 or src.y <= 0.0: return
    var budget := Vector2(tile_rect_in.size.x * fill_ratio, tile_rect_in.size.y * fill_ratio)
    var scale: float = min(budget.x / src.x, budget.y / src.y)
    var drawn := src * scale
    var pos := Vector2(
        tile_rect_in.position.x + (tile_rect_in.size.x - drawn.x) * 0.5,
        tile_rect_in.position.y + (tile_rect_in.size.y - drawn.y) * 0.5 + y_offset)
    draw_texture_rect(tex, Rect2(pos, drawn), false)

## The manifest's 48/64/96 canvases are a size language, so a small creature has
## to render smaller than a dragon rather than both filling the tile equally.
func _tier_fill(card_id: String) -> float:
    if art == null: return 0.78
    var tier: float = float(art.source_size(card_id, Vector2i(64, 64)).y)
    return clampf(0.60 + 0.28 * (tier - 48.0) / 48.0, 0.58, 0.90)

func _sanctuary_element(sanc: int) -> String:
    if engine == null or sanc < 0 or engine.players.size() <= sanc: return ""
    return engine.commander_element(sanc)

func _draw_unit(tile_rect_in: Rect2, unit: Dictionary, f: Font) -> void:
    var owner := int(unit.get("owner", -1))
    var c: Color = ArcanaTheme.owner_color(owner)
    var sprite: Texture2D = art.creature(String(unit.get("card_id", ""))) if art != null else null
    if sprite != null:
        _draw_sprite(sprite, tile_rect_in, _tier_fill(String(unit.get("card_id", ""))), -3.0)
        _draw_stat_plate(tile_rect_in, unit, f, c)
        return
    var w: float = tile_rect_in.size.x - 16
    var h := 34.0
    var chip := Rect2(tile_rect_in.position.x + 8, tile_rect_in.position.y + tile_rect_in.size.y * 0.5 - h * 0.5 - 3, w, h)
    draw_style_box(ArcanaTheme.panel_box(c.darkened(0.55), c, 6, 2), chip)
    draw_string(f, Vector2(chip.position.x + 6, chip.position.y + 14),
        ArcanaTheme.fit(String(unit.get("name", "Unit")), 11, w - 12),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT)
    var hp := int(unit.get("health", 0))
    var max_hp: int = maxi(1, int(unit.get("max_health", hp)))
    draw_string(f, Vector2(chip.position.x + 6, chip.position.y + 28),
        "%d ⚔  %d ♥" % [int(unit.get("power", 0)), hp],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.TEXT)
    # Wound bar, so a damaged creature reads at a glance.
    if hp < max_hp:
        var bar := Rect2(chip.position.x + 2, chip.position.y + chip.size.y - 3, (chip.size.x - 4) * (float(hp) / float(max_hp)), 2)
        draw_rect(bar, ArcanaTheme.HEART)

## Small unobtrusive Power/Health plate for a creature that has real art.
func _draw_stat_plate(tile_rect_in: Rect2, unit: Dictionary, f: Font, c: Color) -> void:
    var hp := int(unit.get("health", 0))
    var max_hp: int = maxi(1, int(unit.get("max_health", hp)))
    var text := "%d ⚔ %d ♥" % [int(unit.get("power", 0)), hp]
    var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0
    var plate := Rect2(tile_rect_in.position.x + (tile_rect_in.size.x - w) * 0.5,
        tile_rect_in.position.y + tile_rect_in.size.y - 19.0, w, 15.0)
    draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.82), c, 4, 1), plate)
    draw_string(f, Vector2(plate.position.x + 5, plate.position.y + 11), text,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT)
    if hp < max_hp:
        var bar := Rect2(plate.position.x + 1, plate.position.y + plate.size.y - 2,
            (plate.size.x - 2) * (float(hp) / float(max_hp)), 2)
        draw_rect(bar, ArcanaTheme.HEART)

func _draw_flourish(fl: Dictionary, f: Font) -> void:
    var rect := tile_rect(fl["pos"])
    var t := float(fl["t"]) / float(fl["life"])
    match String(fl["kind"]):
        "flash":
            draw_style_box(ArcanaTheme.panel_box(Color(fl["color"], 0.55 * (1.0 - t)), Color(fl["color"], 0.9 * (1.0 - t)), 7, 3), rect)
        "ring":
            var r: float = rect.size.x * (0.25 + 0.45 * t)
            draw_arc(rect.get_center(), r, 0, TAU, 32, Color(fl["color"], 1.0 - t), 3.0)
        "text":
            var rise: float = 24.0 * t
            var label: String = ArcanaTheme.fit(String(fl["text"]), 16, rect.size.x - 6)
            draw_string(f, Vector2(rect.position.x + 3, rect.position.y + rect.size.y * 0.5 - rise),
                label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 6, 16, Color(fl["color"], 1.0 - t * t))
