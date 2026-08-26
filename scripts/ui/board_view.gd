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
var _scatter: Array = []             # cached deterministic world detail
var _patches: Array = []             # cached low-frequency ground variation
var _detail_for := Vector2.ZERO      # board size the caches were built for
var _anim: Dictionary = {}           # "unit:<uid>" / "tile:x,y" -> progress 0..1
var _particles: Array = []           # lightweight decorative particles
var ghost_terrain := ""              # terrain previewed on legal tiles while shaping

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

    for key in _anim.keys():
        var v: float = float(_anim[key]) + delta * 3.2
        if v >= 1.0: _anim.erase(key)
        else: _anim[key] = v

    var live: Array = []
    for pt in _particles:
        pt["t"] = float(pt["t"]) + delta
        if float(pt["t"]) >= float(pt["life"]): continue
        pt["pos"] = Vector2(pt["pos"]) + Vector2(pt["vel"]) * delta
        pt["vel"] = Vector2(pt["vel"]) + Vector2(0, float(pt["gravity"])) * delta
        live.append(pt)
    _particles = live
    queue_redraw()

# --- effects API (driven by committed simulation events) --------------------

## A creature or landmark materialising: it squashes in rather than popping.
func note_spawn(key: String) -> void:
    _anim["spawn:" + key] = 0.0

## Land being shaped: the new terrain grows in over the old ground.
func note_shape(pos: Vector2i) -> void:
    _anim["tile:%d,%d" % [pos.x, pos.y]] = 0.0

func _anim_value(key: String) -> float:
    return float(_anim.get(key, 1.0))

## Elemental burst. Leaves drift for Life, embers rise for Fire, sparks for the rest.
func burst(pos: Vector2i, colour: Color, count: int, style: String = "spark", power: float = 1.0) -> void:
    var centre := tile_rect(pos).get_center()
    for i in range(count):
        var ang: float = TAU * float(i) / float(count) + _vhash(i, count) * 0.9
        var speed: float = (34.0 + 52.0 * _vhash(i, 7)) * power
        var vel := Vector2(cos(ang), sin(ang) * 0.7) * speed
        var gravity := 60.0
        var size := 2.0 + 2.0 * _vhash(i, 21)
        if style == "leaf":
            vel.y -= 42.0 * power
            gravity = 26.0
            size += 1.0
        elif style == "ember":
            vel.y -= 66.0 * power
            gravity = -18.0                     # embers float upward
        _particles.append({
            "pos": centre, "vel": vel, "gravity": gravity, "t": 0.0,
            "life": 0.5 + 0.5 * _vhash(i, 13), "colour": colour,
            "size": size, "style": style,
        })

func element_colour_for_card(card_id: String) -> Color:
    if engine == null or engine.db == null: return ArcanaTheme.GOLD
    var els: Array = engine.db.get_card(card_id).get("elements", [])
    if els.is_empty(): return ArcanaTheme.GOLD
    return ArcanaTheme.color_for_element(String(els[0]))

func _draw_particles() -> void:
    for pt in _particles:
        var t: float = float(pt["t"]) / float(pt["life"])
        var c: Color = pt["colour"]
        var a: float = 1.0 - t * t
        var at: Vector2 = pt["pos"]
        var sz: float = float(pt["size"])
        match String(pt["style"]):
            "leaf":
                # A little tumbling leaf rather than a dot.
                var w: float = sz * (0.5 + 0.5 * cos(t * 9.0))
                draw_rect(Rect2(at - Vector2(w, sz) * 0.5, Vector2(w * 2.0, sz)), Color(c, a))
            "ember":
                draw_circle(at, sz * (1.0 - t * 0.5), Color(c, a))
                draw_circle(at, sz * 1.9 * (1.0 - t), Color(c, a * 0.18))
            _:
                draw_circle(at, sz * (1.0 - t * 0.6), Color(c, a))

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

# --- deterministic world detail ---------------------------------------------
#
# The battlefield is built once per size and then just drawn, so it is stable
# frame to frame and costs nothing to redraw. Everything here is decoration: it
# never reads or changes game state.

func _vhash(x: int, y: int) -> float:
    var h: int = (x * 374761393 + y * 668265263) & 0x7fffffff
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
    return float((h ^ (h >> 16)) & 0xffff) / 65535.0

## Smooth value noise, for lushness that varies across the world rather than
## uniform speckle.
func _noise(fx: float, fy: float) -> float:
    var x0 := int(floor(fx)); var y0 := int(floor(fy))
    var tx: float = fx - float(x0); var ty: float = fy - float(y0)
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    var a: float = lerpf(_vhash(x0, y0), _vhash(x0 + 1, y0), tx)
    var b: float = lerpf(_vhash(x0, y0 + 1), _vhash(x0 + 1, y0 + 1), tx)
    return lerpf(a, b, ty)

func _rebuild_detail(board: Rect2) -> void:
    _scatter.clear()
    _patches.clear()

    # Low-frequency blotches so the middle of the field is never one flat tone.
    for i in range(26):
        var u := _vhash(i, 917)
        var v := _vhash(i, 4211)
        _patches.append({
            "u": u, "v": v,
            "r": 0.05 + 0.10 * _vhash(i, 77),
            "shade": _vhash(i, 313),
        })

    # Scatter points on a jittered lattice. Each one renders differently
    # depending on the biome it lands in, so a region's detail is continuous
    # across its tiles and reads as one place.
    var cols := 54
    var rows := 34
    for gy in range(rows):
        for gx in range(cols):
            var lush := _noise(float(gx) * 0.18, float(gy) * 0.18)
            if _vhash(gx * 7 + 3, gy * 11 + 5) > 0.30 + lush * 0.55: continue
            var u := (float(gx) + _vhash(gx, gy) * 0.9) / float(cols)
            var v := (float(gy) + _vhash(gx + 91, gy + 17) * 0.9) / float(rows)
            if u >= 1.0 or v >= 1.0: continue
            var roll := _vhash(gx + 500, gy + 900)
            var kind := "tuft"
            if roll > 0.78: kind = "stone"
            elif roll > 0.58: kind = "bloom"
            _scatter.append({
                "u": u, "v": v, "kind": kind, "lush": lush,
                "size": 0.7 + 0.6 * _vhash(gx + 31, gy + 63),
                "tilt": _vhash(gx + 12, gy + 88),
            })
    _detail_for = board.size

## Small ground features, drawn in the language of whatever biome they sit in.
func _draw_scatter(board: Rect2) -> void:
    var tw: float = board.size.x / BoardModel.WIDTH
    var th: float = board.size.y / BoardModel.HEIGHT
    for d in _scatter:
        var px: float = board.position.x + float(d["u"]) * board.size.x
        var py: float = board.position.y + float(d["v"]) * board.size.y
        var tx := int(float(d["u"]) * BoardModel.WIDTH)
        var ty := int(float(d["v"]) * BoardModel.HEIGHT)
        var terrain := String(engine.board.get_tile(Vector2i(tx, ty)).get("terrain", "neutral"))
        var scale: float = float(d["size"]) * (tw / 130.0)
        var kind := String(d["kind"])
        match terrain:
            "grove":
                if kind == "bloom":
                    draw_circle(Vector2(px, py), 2.4 * scale, Color("#f2c7dd"))
                    draw_circle(Vector2(px, py), 1.1 * scale, Color("#fff4d2"))
                elif kind == "stone":
                    draw_circle(Vector2(px, py), 2.2 * scale, Color("#5d7a44"))
                else:
                    _draw_tuft(Vector2(px, py), scale * 1.15, Color("#8fd06a"), float(d["tilt"]))
            "cinder":
                if kind == "bloom":
                    draw_circle(Vector2(px, py), 2.0 * scale, Color("#ff9a4d"))
                    draw_circle(Vector2(px, py), 3.6 * scale, Color(1.0, 0.55, 0.2, 0.14))
                elif kind == "stone":
                    draw_circle(Vector2(px, py), 2.6 * scale, Color("#241d1a"))
                else:
                    _draw_tuft(Vector2(px, py), scale * 0.9, Color("#4a3b33"), float(d["tilt"]))
            "ashbloom":
                if kind == "bloom":
                    draw_circle(Vector2(px, py), 2.3 * scale, Color("#ffd08a"))
                    draw_circle(Vector2(px, py), 1.0 * scale, Color("#fff6e0"))
                else:
                    _draw_tuft(Vector2(px, py), scale, Color("#7d8f5a"), float(d["tilt"]))
            "neutral":
                var lush: float = float(d["lush"])
                if kind == "stone":
                    draw_circle(Vector2(px, py), 2.3 * scale, Color(0.30, 0.31, 0.26, 0.75))
                    draw_circle(Vector2(px - 0.6, py - 0.8), 1.3 * scale, Color(0.38, 0.39, 0.33, 0.7))
                elif kind == "bloom" and lush > 0.62:
                    draw_circle(Vector2(px, py), 1.5 * scale, Color(0.72, 0.76, 0.55, 0.55))
                else:
                    _draw_tuft(Vector2(px, py), scale, Color(0.26, 0.34, 0.22, 0.85), float(d["tilt"]))
            _:
                _draw_tuft(Vector2(px, py), scale, Color(0.28, 0.33, 0.25, 0.7), float(d["tilt"]))

func _draw_tuft(at: Vector2, scale: float, colour: Color, tilt: float) -> void:
    var h: float = 4.5 * scale
    var lean: float = (tilt - 0.5) * 2.4 * scale
    draw_line(at, at + Vector2(lean, -h), colour, maxf(1.0, 1.2 * scale))
    draw_line(at, at + Vector2(lean - 2.0 * scale, -h * 0.66), colour, maxf(1.0, 1.0 * scale))
    draw_line(at, at + Vector2(lean + 2.0 * scale, -h * 0.72), colour, maxf(1.0, 1.0 * scale))

# --- drawing ----------------------------------------------------------------

func _draw() -> void:
    if engine == null or engine.board == null: return
    var f := ArcanaTheme.font()
    var board := _board_rect()

    if _detail_for != board.size: _rebuild_detail(board)
    _draw_ground(board)
    _draw_terrain()
    _feather_terrain_edges()
    _draw_scatter(board)
    _draw_ghost_terrain()
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
    _draw_particles()

## One continuous field of land, not 35 panels.
func _draw_ground(board: Rect2) -> void:
    draw_rect(board, ArcanaTheme.WORLD_GROUND)
    # Broad soft blotches so the middle of the field is a landscape, not a mat.
    for patch in _patches:
        var centre := board.position + Vector2(float(patch["u"]) * board.size.x,
                                               float(patch["v"]) * board.size.y)
        var radius: float = float(patch["r"]) * board.size.x
        var shade: float = float(patch["shade"])
        var tint: Color = ArcanaTheme.WORLD_GROUND_ALT if shade > 0.5 else ArcanaTheme.WORLD_EDGE
        for i in range(4):
            var t := float(i) / 4.0
            draw_circle(centre, radius * (1.0 - t * 0.30), Color(tint, 0.05))

func _draw_terrain() -> void:
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var pos := Vector2i(x, y)
            var tile: Dictionary = engine.board.get_tile(pos)
            var terrain := String(tile.get("terrain", "neutral"))
            if terrain == "neutral": continue
            var grow: float = _anim_value("tile:%d,%d" % [pos.x, pos.y])
            var rect := tile_rect(pos).grow(BLEED)
            if grow < 1.0:
                # New land pushes outward from the middle of the tile as it forms.
                var eased: float = 1.0 - pow(1.0 - grow, 3.0)
                rect = Rect2(rect.get_center() - rect.size * 0.5 * eased, rect.size * eased)
            var tex: Texture2D = art.terrain(terrain) if art != null else null
            if tex != null:
                draw_texture_rect(tex, rect, false, Color(1, 1, 1, minf(1.0, grow * 1.4)))
            else:
                draw_rect(rect, Color(ArcanaTheme.color_for_terrain(terrain).darkened(0.55), minf(1.0, grow * 1.4)))

## While a Shape element is chosen, legal tiles show a faint preview of the land
## they could become — bare ground reads as potential, not emptiness.
func _draw_ghost_terrain() -> void:
    if ghost_terrain == "" or art == null: return
    var tex: Texture2D = art.terrain(ghost_terrain)
    var wave: float = 0.5 + 0.5 * sin(_pulse * TAU)
    for pos in highlights:
        if String(highlights[pos]) != "target": continue
        var rect := tile_rect(pos)
        if tex != null:
            draw_texture_rect(tex, rect.grow(BLEED), false, Color(1, 1, 1, 0.20 + 0.10 * wave))
        else:
            draw_rect(rect, Color(ArcanaTheme.color_for_terrain(ghost_terrain), 0.18))

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
        # A magical place: a raised dais, banners, breathing glow and rune ring.
        var breathe: float = 0.5 + 0.5 * sin(_pulse * TAU + player * PI)
        var radius: float = rect.size.y * 0.42
        var dais := Vector2(centre.x, centre.y + rect.size.y * 0.10)
        draw_circle(dais, radius * 1.12, Color(0.16, 0.15, 0.13, 0.55))
        draw_circle(dais, radius * 0.98, Color(0.24, 0.23, 0.20, 0.75))
        draw_circle(dais + Vector2(0, -2), radius * 0.84, Color(0.30, 0.29, 0.25, 0.7))
        for side in [-1.0, 1.0]:
            var px: float = centre.x + side * rect.size.x * 0.33
            var top: float = centre.y - rect.size.y * 0.30
            draw_line(Vector2(px, top), Vector2(px, dais.y), Color(0.22, 0.20, 0.17, 0.9), 3.0)
            var flap: float = sin(_pulse * TAU + side) * 3.0
            draw_colored_polygon(PackedVector2Array([
                Vector2(px, top + 2.0),
                Vector2(px + side * 15.0 + flap, top + 8.0),
                Vector2(px, top + 20.0)]), Color(colour, 0.85))
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
    var colour: Color = ArcanaTheme.owner_color(int(lm.get("owner", -1)))
    var element := element_colour_for_card(String(lm.get("card_id", "")))
    var grow: float = _anim_value("spawn:lm%d%d" % [pos.x, pos.y])
    # A cleared, trodden foundation: the tile has been built on.
    var plot := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.72)
    draw_circle(plot, rect.size.x * 0.32, Color(0.19, 0.17, 0.14, 0.55))
    draw_circle(plot, rect.size.x * 0.27, Color(0.26, 0.23, 0.19, 0.55))
    for i in range(6):
        var ang: float = TAU * float(i) / 6.0
        draw_circle(plot + Vector2(cos(ang), sin(ang) * 0.5) * rect.size.x * 0.30, 2.2, Color(element, 0.45))
    var tex: Texture2D = art.landmark(String(lm.get("card_id", ""))) if art != null else null
    if tex != null:
        _draw_sprite_scaled(tex, rect, 0.78, -rect.size.y * 0.04, Vector2(1.0, grow))
        return
    var h: float = rect.size.y * 0.40 * grow
    var w: float = rect.size.x * 0.34
    var base := Rect2(rect.get_center().x - w * 0.5, plot.y - h, w, h)
    draw_style_box(ArcanaTheme.panel_box(element.darkened(0.55), element.lightened(0.1), 5, 2), base)
    var roof := PackedVector2Array([
        Vector2(base.position.x - 5.0, base.position.y),
        Vector2(base.get_center().x, base.position.y - rect.size.y * 0.16 * grow),
        Vector2(base.position.x + base.size.x + 5.0, base.position.y)])
    draw_colored_polygon(roof, element.darkened(0.25))

func _draw_creature(pos: Vector2i, f: Font) -> void:
    var unit = engine.board.get_tile(pos).get("creature")
    if unit == null: return
    var rect := tile_rect(pos)
    var owner := int(unit.get("owner", -1))
    var card_id := String(unit.get("card_id", ""))
    var element: Color = element_colour_for_card(card_id)
    var spawn: float = _anim_value("spawn:%d" % int(unit.get("uid", 0)))

    # Elemental aura on the ground: the fastest possible read of which side a
    # creature belongs to, without any text.
    var base := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.74)
    var aura: float = rect.size.x * 0.30 * _tier_fill(card_id)
    for i in range(4):
        var t := float(i) / 4.0
        draw_circle(base, aura * (1.0 - t * 0.55), Color(element, 0.09))
    draw_arc(base, aura, 0, TAU, 26, Color(element, 0.30), 1.5)
    for i in range(3):
        var t := float(i) / 3.0
        draw_circle(base, rect.size.x * (0.17 - t * 0.045), Color(0, 0, 0, 0.11))

    # Squash-and-stretch entrance.
    var scale_x := 1.0
    var scale_y := 1.0
    if spawn < 1.0:
        var e: float = 1.0 - pow(1.0 - spawn, 3.0)
        scale_x = 0.55 + 0.45 * e + 0.16 * sin(e * PI)
        scale_y = 0.40 + 0.60 * e - 0.12 * sin(e * PI)

    var sprite: Texture2D = art.creature(card_id) if art != null else null
    if sprite != null:
        _draw_sprite_scaled(sprite, rect, _tier_fill(card_id), -rect.size.y * 0.08,
            Vector2(scale_x, scale_y))
    else:
        # Fallback silhouette still carries element colour and size tier.
        var tier: float = _tier_fill(card_id)
        var body := Rect2(Vector2.ZERO, rect.size * Vector2(0.46, 0.50) * tier * Vector2(scale_x, scale_y))
        body.position = rect.get_center() - body.size * 0.5 - Vector2(0, rect.size.y * 0.06)
        draw_style_box(ArcanaTheme.panel_box(element.darkened(0.45), element.lightened(0.15), 10, 2), body)
        draw_string(f, Vector2(body.position.x + 4, body.get_center().y + 4),
            ArcanaTheme.fit(String(unit.get("name", "Unit")), 11, body.size.x - 8),
            HORIZONTAL_ALIGNMENT_CENTER, body.size.x - 8, 11, ArcanaTheme.TEXT)

    _draw_unit_stats(rect, unit, f, ArcanaTheme.owner_color(owner))

## Power and Health on a soft plate directly beneath the creature. Centring it
## under the sprite is what makes the association unambiguous — numbers parked in
## tile corners blur together between neighbouring units.
func _draw_unit_stats(rect: Rect2, unit: Dictionary, f: Font, owner_colour: Color) -> void:
    var hp := int(unit.get("health", 0))
    var max_hp: int = maxi(1, int(unit.get("max_health", hp)))
    var power := int(unit.get("power", 0))
    var ps := str(power)
    var hs := str(hp)
    var pw: float = f.get_string_size(ps, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
    var hw: float = f.get_string_size(hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
    var w: float = pw + hw + 30.0
    var plate := Rect2(rect.get_center().x - w * 0.5, rect.position.y + rect.size.y - 22.0, w, 18.0)
    # Soft shadow rather than a bordered widget.
    draw_style_box(ArcanaTheme.panel_box(Color(0.05, 0.05, 0.07, 0.60), Color(0, 0, 0, 0), 9, 0), plate)
    draw_style_box(ArcanaTheme.panel_box(Color(0, 0, 0, 0), Color(owner_colour, 0.45), 9, 1), plate)
    var y: float = plate.position.y + 13.0
    draw_string(f, Vector2(plate.position.x + 7, y), ps, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#ffd98a"))
    draw_circle(Vector2(plate.get_center().x, y - 4.0), 1.6, Color(1, 1, 1, 0.35))
    draw_string(f, Vector2(plate.position.x + plate.size.x - hw - 7, y), hs,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#ffb3c4"))
    if hp < max_hp:
        draw_rect(Rect2(plate.position.x + 2, plate.position.y + plate.size.y - 3.0,
            (plate.size.x - 4) * (float(hp) / float(max_hp)), 2.0), ArcanaTheme.HEART)
    draw_circle(Vector2(rect.get_center().x, rect.position.y + 8.0), 3.5, Color(owner_colour, 0.9))

## Scale a sprite into the tile without smoothing or distortion.
func _draw_sprite(tex: Texture2D, rect: Rect2, fill_ratio: float, y_offset: float) -> void:
    _draw_sprite_scaled(tex, rect, fill_ratio, y_offset, Vector2.ONE)

func _draw_sprite_scaled(tex: Texture2D, rect: Rect2, fill_ratio: float, y_offset: float, squash: Vector2) -> void:
    var src := Vector2(tex.get_width(), tex.get_height())
    if src.x <= 0.0 or src.y <= 0.0: return
    var budget := rect.size * fill_ratio
    var scale: float = min(budget.x / src.x, budget.y / src.y)
    var drawn := src * scale * squash
    # Feet stay planted while the body squashes.
    var foot: float = rect.get_center().y + budget.y * 0.5 + y_offset
    var at := Vector2(rect.get_center().x - drawn.x * 0.5, foot - drawn.y)
    draw_texture_rect(tex, Rect2(at, drawn), false)

## The manifest's 48/64/96 canvases are a size language: a dragon must dwarf a sprout.
func _tier_fill(card_id: String) -> float:
    if art == null: return 0.80
    var tier: float = float(art.source_size(card_id, Vector2i(64, 64)).y)
    return clampf(0.62 + 0.44 * (tier - 48.0) / 48.0, 0.60, 1.08)

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
