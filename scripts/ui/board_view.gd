class_name BoardView
extends Control
## Draws the 7x5 board as one continuous living world.
##
## The logical board is unchanged — this only decides how it looks. Cell
## boundaries are invisible during normal play; a realm reads as a connected
## region because only its *outer* border is drawn, and placement indicators
## appear only while the player is targeting.
##
## Nothing here may influence legality, coordinates, hitboxes, AI or determinism.

signal tile_clicked(pos: Vector2i)
signal tile_hovered(pos: Vector2i)

const MAX_FLOURISHES := 7
const TILE_ASPECT := 1.45
## Terrain cells are drawn slightly oversized so neighbours overlap and the
## seam between them softens instead of reading as a grid line.
const BLEED := 2.0

var engine: MatchEngine
var art: ArtRegistry
var highlights: Dictionary = {}      # Vector2i -> "target" | "move" | "attack" | "heart"
var selected_pos := Vector2i(-1, -1)
var hover_pos := Vector2i(-1, -1)
var targeting := false               # show placement indicators only while aiming

var _flourishes: Array = []
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

func shake(strength: float = 1.0) -> void:
    _shake = clampf(_shake + strength, 0.0, 1.4)

func _board_rect() -> Rect2:
    var cols := float(BoardModel.WIDTH)
    var rows := float(BoardModel.HEIGHT)
    var tile_w: float = size.x / cols
    var tile_h: float = size.y / rows
    if tile_w / tile_h > TILE_ASPECT: tile_w = tile_h * TILE_ASPECT
    else: tile_h = tile_w / TILE_ASPECT
    var total := Vector2(tile_w * cols, tile_h * rows)
    var jitter := Vector2.ZERO
    if _shake > 0.0:
        jitter = Vector2(sin(_shake * 47.0), cos(_shake * 39.0)) * _shake * 3.0
    return Rect2((size - total) * 0.5 + jitter, total)

func tile_rect(pos: Vector2i) -> Rect2:
    var board := _board_rect()
    var tw: float = board.size.x / BoardModel.WIDTH
    var th: float = board.size.y / BoardModel.HEIGHT
    return Rect2(board.position.x + pos.x * tw, board.position.y + pos.y * th, tw, th)

func tile_at(point: Vector2) -> Vector2i:
    var board := _board_rect()
    if not board.has_point(point): return Vector2i(-1, -1)
    var tw: float = board.size.x / BoardModel.WIDTH
    var th: float = board.size.y / BoardModel.HEIGHT
    var x := int((point.x - board.position.x) / tw)
    var y := int((point.y - board.position.y) / th)
    if x < 0 or y < 0 or x >= BoardModel.WIDTH or y >= BoardModel.HEIGHT: return Vector2i(-1, -1)
    return Vector2i(x, y)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var pos := tile_at(event.position)
        if pos.x >= 0: tile_clicked.emit(pos)
    elif event is InputEventMouseMotion:
        var pos := tile_at(event.position)
        if pos != hover_pos:
            hover_pos = pos
            tile_hovered.emit(pos)

# --- flourishes -------------------------------------------------------------

func _push(f: Dictionary) -> void:
    _flourishes.append(f)
    while _flourishes.size() > MAX_FLOURISHES: _flourishes.pop_front()

func flash_tile(pos: Vector2i, color: Color, life: float = 0.45) -> void:
    _push({"kind": "flash", "pos": pos, "color": color, "t": 0.0, "life": life})

func float_text(pos: Vector2i, text: String, color: Color, life: float = 0.85) -> void:
    for f in _flourishes:
        if String(f["kind"]) == "text" and f["pos"] == pos and String(f["text"]) == text: return
    _push({"kind": "text", "pos": pos, "text": text, "color": color, "t": 0.0, "life": life})

func ring(pos: Vector2i, color: Color, life: float = 0.7) -> void:
    _push({"kind": "ring", "pos": pos, "color": color, "t": 0.0, "life": life})

func clear_flourishes() -> void:
    _flourishes.clear()

# --- drawing ----------------------------------------------------------------

func _draw() -> void:
    if engine == null or engine.board == null: return
    var f := ArcanaTheme.font()
    var board := _board_rect()

    _draw_ground(board)
    _draw_terrain()
    _feather_terrain_edges()
    _draw_realm_outlines()
    _draw_world_edge(board)
    _draw_sanctuaries(f)

    # Landmarks sit under creatures so the two can share a tile.
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            _draw_landmark(Vector2i(x, y), f)
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            _draw_creature(Vector2i(x, y), f)

    _draw_depth(board)
    _draw_indicators(f)
    for fl in _flourishes: _draw_flourish(fl, f)

## One continuous field of land, not 35 panels.
func _draw_ground(board: Rect2) -> void:
    draw_rect(board, ArcanaTheme.WORLD_GROUND)
    # Fine deterministic speckle so bare land reads as soil rather than a panel.
    # Kept small and low-contrast: anything larger looks like UI bubbles.
    var tw: float = board.size.x / BoardModel.WIDTH
    var th: float = board.size.y / BoardModel.HEIGHT
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var h := (x * 73856093) ^ (y * 19349663)
            for k in range(5):
                var hk := h ^ (k * 83492791)
                var cx: float = board.position.x + (x + float((hk >> 3) % 32) / 32.0) * tw
                var cy: float = board.position.y + (y + float((hk >> 11) % 32) / 32.0) * th
                var r: float = 1.5 + float((hk >> 19) % 3)
                draw_circle(Vector2(cx, cy), r, Color(ArcanaTheme.WORLD_GROUND_ALT, 0.55))

func _draw_terrain() -> void:
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var pos := Vector2i(x, y)
            var tile: Dictionary = engine.board.get_tile(pos)
            var terrain := String(tile.get("terrain", "neutral"))
            if terrain == "neutral": continue
            var rect := tile_rect(pos).grow(BLEED)
            var tex: Texture2D = art.terrain(terrain) if art != null else null
            if tex != null:
                draw_texture_rect(tex, rect, false)
            else:
                draw_rect(rect, ArcanaTheme.color_for_terrain(terrain).darkened(0.55))

func _feather_terrain_edges() -> void:
    const STEPS := 5
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var pos := Vector2i(x, y)
            var terrain := String(engine.board.get_tile(pos).get("terrain", "neutral"))
            if terrain == "neutral": continue
            var r := tile_rect(pos)
            for d in BoardModel.DIRECTIONS:
                var n := pos + d
                var different := true
                if engine.board.in_bounds(n):
                    different = String(engine.board.get_tile(n).get("terrain", "neutral")) != terrain
                if not different: continue
                for i in range(STEPS):
                    var t := float(i) / float(STEPS)
                    var alpha: float = 0.42 * (1.0 - t)
                    var off: float = t * 9.0
                    var a := r.position
                    var b := r.position
                    if d == Vector2i.LEFT:
                        a += Vector2(off, 0); b += Vector2(off, r.size.y)
                    elif d == Vector2i.RIGHT:
                        a += Vector2(r.size.x - off, 0); b += Vector2(r.size.x - off, r.size.y)
                    elif d == Vector2i.UP:
                        a += Vector2(0, off); b += Vector2(r.size.x, off)
                    else:
                        a += Vector2(0, r.size.y - off); b += Vector2(r.size.x, r.size.y - off)
                    draw_line(a, b, Color(ArcanaTheme.WORLD_GROUND, alpha), 3.0)

## Draw only the outside edge of each realm, so a player's land reads as one
## connected shape instead of a row of bordered cells.
func _draw_realm_outlines() -> void:
    for player in range(2):
        var colour: Color = ArcanaTheme.owner_color(player)
        for y in range(BoardModel.HEIGHT):
            for x in range(BoardModel.WIDTH):
                var pos := Vector2i(x, y)
                if int(engine.board.get_tile(pos).get("owner", -1)) != player: continue
                var r := tile_rect(pos)
                for d in BoardModel.DIRECTIONS:
                    var n := pos + d
                    var outside := true
                    if engine.board.in_bounds(n):
                        outside = int(engine.board.get_tile(n).get("owner", -1)) != player
                    if not outside: continue
                    var a := r.position
                    var b := r.position
                    if d == Vector2i.LEFT: b += Vector2(0, r.size.y)
                    elif d == Vector2i.RIGHT: a += Vector2(r.size.x, 0); b += r.size
                    elif d == Vector2i.UP: b += Vector2(r.size.x, 0)
                    else: a += Vector2(0, r.size.y); b += r.size
                    draw_line(a, b, Color(colour, 0.10), 7.0)
                    draw_line(a, b, Color(colour, 0.30), 2.0)

## Soft dark rim so the world ends organically rather than as a UI rectangle.
func _draw_world_edge(board: Rect2) -> void:
    var steps := 7
    for i in range(steps):
        var t := float(i) / float(steps)
        var inset: float = t * 14.0
        draw_rect(Rect2(board.position + Vector2(inset, inset),
            board.size - Vector2(inset, inset) * 2.0),
            Color(ArcanaTheme.WORLD_EDGE, 0.16 * (1.0 - t)), false, 3.0)

func _draw_sanctuaries(f: Font) -> void:
    for player in range(2):
        var pos: Vector2i = engine.sanctuary_pos(player)
        var rect := tile_rect(pos)
        var centre := rect.get_center()
        var colour: Color = ArcanaTheme.owner_color(player)
        var tex: Texture2D = art.sanctuary(engine.commander_element(player)) if art != null else null
        if tex != null:
            draw_texture_rect(tex, rect.grow(BLEED), false)
        # A magical place: breathing glow, rune ring, and a heart at its heart.
        var breathe: float = 0.5 + 0.5 * sin(_pulse * TAU + player * PI)
        var radius: float = rect.size.y * 0.42
        for i in range(5):
            var t := float(i) / 5.0
            draw_circle(centre, radius * (1.0 - t * 0.55), Color(colour, 0.05 + 0.05 * breathe))
        draw_arc(centre, radius, 0, TAU, 40, Color(colour, 0.55 + 0.25 * breathe), 2.0)
        draw_arc(centre, radius * 0.72, _pulse * TAU, _pulse * TAU + PI * 1.3, 24, Color(colour, 0.4), 1.5)
        # Standing stones around the rim make it a place, not a marked tile.
        for i in range(8):
            var ang: float = TAU * float(i) / 8.0 + _pulse * 0.15
            var at := centre + Vector2(cos(ang), sin(ang) * 0.62) * radius * 0.92
            draw_circle(at, 3.0, Color(colour, 0.55))
        var heart := int(engine.players[player]["heart"]) if engine.players.size() > player else 0
        var label := "♥ %d" % heart
        var w: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
        var plate := Rect2(centre.x - w * 0.5 - 8.0, centre.y - 12.0, w + 16.0, 24.0)
        draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.72), Color(colour, 0.8), 11, 1), plate)
        draw_string(f, Vector2(plate.position.x + 8, plate.position.y + 17), label,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ArcanaTheme.TEXT)

func _draw_landmark(pos: Vector2i, f: Font) -> void:
    var lm = engine.board.get_tile(pos).get("landmark")
    if lm == null: return
    var rect := tile_rect(pos)
    var tex: Texture2D = art.landmark(String(lm.get("card_id", ""))) if art != null else null
    if tex != null:
        _draw_sprite(tex, rect, 0.80, -2.0)
        return
    var colour: Color = ArcanaTheme.owner_color(int(lm.get("owner", -1)))
    var base := Rect2(rect.position.x + rect.size.x * 0.24, rect.position.y + rect.size.y * 0.30,
        rect.size.x * 0.52, rect.size.y * 0.46)
    draw_style_box(ArcanaTheme.panel_box(Color(colour, 0.22), Color(colour, 0.7), 6, 2), base)
    draw_string(f, Vector2(base.position.x + base.size.x * 0.5 - 7, base.get_center().y + 7),
        "⌂", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, colour)

func _draw_creature(pos: Vector2i, f: Font) -> void:
    var unit = engine.board.get_tile(pos).get("creature")
    if unit == null: return
    var rect := tile_rect(pos)
    var owner := int(unit.get("owner", -1))
    var colour: Color = ArcanaTheme.owner_color(owner)
    # Contact shadow so the creature stands in the world instead of floating.
    for i in range(3):
        var t := float(i) / 3.0
        draw_circle(Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.76),
            rect.size.x * (0.20 - t * 0.05), Color(0, 0, 0, 0.10))
    var sprite: Texture2D = art.creature(String(unit.get("card_id", ""))) if art != null else null
    if sprite != null:
        _draw_sprite(sprite, rect, _tier_fill(String(unit.get("card_id", ""))), -rect.size.y * 0.06)
    else:
        var body := Rect2(rect.position.x + rect.size.x * 0.22, rect.position.y + rect.size.y * 0.18,
            rect.size.x * 0.56, rect.size.y * 0.56)
        draw_style_box(ArcanaTheme.panel_box(colour.darkened(0.5), colour, 8, 2), body)
        draw_string(f, Vector2(body.position.x + 5, body.get_center().y + 4),
            ArcanaTheme.fit(String(unit.get("name", "Unit")), 11, body.size.x - 10),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT)
    _draw_stat_pill(rect, unit, f, colour)

## Scale a sprite into the tile without smoothing or distortion.
func _draw_sprite(tex: Texture2D, rect: Rect2, fill_ratio: float, y_offset: float) -> void:
    var src := Vector2(tex.get_width(), tex.get_height())
    if src.x <= 0.0 or src.y <= 0.0: return
    var budget := rect.size * fill_ratio
    var scale: float = min(budget.x / src.x, budget.y / src.y)
    var drawn := src * scale
    draw_texture_rect(tex, Rect2(rect.get_center() - drawn * 0.5 + Vector2(0, y_offset), drawn), false)

## The manifest's 48/64/96 canvases are a size language: a dragon must dwarf a sprout.
func _tier_fill(card_id: String) -> float:
    if art == null: return 0.80
    var tier: float = float(art.source_size(card_id, Vector2i(64, 64)).y)
    return clampf(0.70 + 0.30 * (tier - 48.0) / 48.0, 0.68, 1.0)

func _draw_stat_pill(rect: Rect2, unit: Dictionary, f: Font, colour: Color) -> void:
    var hp := int(unit.get("health", 0))
    var max_hp: int = maxi(1, int(unit.get("max_health", hp)))
    var text := "%d/%d" % [int(unit.get("power", 0)), hp]
    var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12.0
    var pill := Rect2(rect.get_center().x - w * 0.5, rect.position.y + rect.size.y - 21.0, w, 16.0)
    draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.78), Color(colour, 0.85), 8, 1), pill)
    draw_string(f, Vector2(pill.position.x + 6, pill.position.y + 12), text,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ArcanaTheme.TEXT)
    if hp < max_hp:
        draw_rect(Rect2(pill.position.x + 1, pill.position.y + pill.size.y - 2,
            (pill.size.x - 2) * (float(hp) / float(max_hp)), 2), ArcanaTheme.HEART)

## Aerial perspective without touching geometry: the far half hazes out, the near
## half warms up, so the battlefield reads as a landscape receding from the player.
func _draw_depth(board: Rect2) -> void:
    const SLICES := 48
    for i in range(SLICES):
        var t := float(i) / float(SLICES - 1)                # 0 = far, 1 = near
        # Exact edges: overlapping bands double-blend and read as stripes.
        var y0: float = board.position.y + board.size.y * (float(i) / float(SLICES))
        var y1: float = board.position.y + board.size.y * (float(i + 1) / float(SLICES))
        var band := Rect2(board.position.x, y0, board.size.x, y1 - y0)
        if t < 0.5:
            draw_rect(band, Color(0.42, 0.50, 0.62, 0.15 * (1.0 - t * 2.0)))
        else:
            draw_rect(band, Color(0.98, 0.86, 0.62, 0.05 * ((t - 0.5) * 2.0)))

## Placement indicators exist only while the player is aiming.
func _draw_indicators(f: Font) -> void:
    if not targeting and selected_pos.x < 0: return
    var wave: float = 0.5 + 0.5 * sin(_pulse * TAU)
    for pos in highlights:
        var rect := tile_rect(pos)
        var kind := String(highlights[pos])
        var glow: Color = ArcanaTheme.LEGAL
        if kind == "move": glow = ArcanaTheme.MOVE
        elif kind == "attack": glow = ArcanaTheme.ATTACK
        elif kind == "heart": glow = ArcanaTheme.HEART
        var inner := rect.grow(-4.0)
        draw_style_box(ArcanaTheme.panel_box(Color(glow, 0.14 + 0.10 * wave),
            Color(glow, 0.7 + 0.3 * wave), 10, 2), inner)
        if kind == "target":
            draw_circle(rect.get_center(), 5.0 + 2.0 * wave, Color(glow, 0.75))
        elif kind == "heart":
            draw_string(f, Vector2(rect.get_center().x - 24, rect.get_center().y + 5),
                "STRIKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ArcanaTheme.HEART)
    if selected_pos.x >= 0:
        draw_style_box(ArcanaTheme.panel_box(Color(1, 1, 1, 0), Color(ArcanaTheme.GOLD, 0.95), 10, 3),
            tile_rect(selected_pos).grow(-3.0))
    if targeting and hover_pos.x >= 0 and highlights.has(hover_pos):
        draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.TEXT, 0.10), Color(ArcanaTheme.TEXT, 0.5), 10, 2),
            tile_rect(hover_pos).grow(-4.0))

func _draw_flourish(fl: Dictionary, f: Font) -> void:
    var rect := tile_rect(fl["pos"])
    var t := float(fl["t"]) / float(fl["life"])
    match String(fl["kind"]):
        "flash":
            draw_style_box(ArcanaTheme.panel_box(Color(fl["color"], 0.45 * (1.0 - t)),
                Color(fl["color"], 0.8 * (1.0 - t)), 10, 3), rect.grow(-3.0))
        "ring":
            draw_arc(rect.get_center(), rect.size.x * (0.25 + 0.45 * t), 0, TAU, 32,
                Color(fl["color"], 1.0 - t), 3.0)
        "text":
            var label: String = ArcanaTheme.fit(String(fl["text"]), 18, rect.size.x - 6)
            draw_string(f, Vector2(rect.position.x + 3, rect.position.y + rect.size.y * 0.42 - 26.0 * t),
                label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 6, 18,
                Color(fl["color"], 1.0 - t * t))
