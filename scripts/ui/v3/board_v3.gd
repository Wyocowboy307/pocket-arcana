class_name BoardV3
extends Control
## The V3 tabletop. Four lanes a side, three slots in each.
##
## This is a board you lay cards on, not a map things walk around. Every slot has
## a fixed home; a creature may animate out of its card to attack and then drop
## back in, but it never becomes a free-moving piece.
##
## Art is presentation only. Nothing here decides a rule.

signal slot_clicked(side: int, index: int, slot: String)
signal slot_hovered(side: int, index: int)

const RAIL_L := 148.0                 # commanders and Hearts
const RAIL_R := 132.0                 # resource pools and decks
const LAND_H := 48.0
const ROW_H := 186.0
const CLASH_H := 34.0
const CREATURE_W := 148.0
const CREATURE_H := 182.0
const SUPPORT_W := 86.0
const SUPPORT_H := 112.0
const LAND_W := 234.0

var engine: MatchV3
var art: ArtRegistry
var highlights: Dictionary = {}       # "side,lane" -> "legal" | "attack"
var hover_side := -1
var hover_lane := -1
var fusion_pairs: Array = []

var _ui: Dictionary = {}              # cached v3 UI textures
var _acts: Array = []
var _emergent: Array = []
var _motion: Dictionary = {}
var _motion_styles: Dictionary = {}
var _pulse := 0.0
var _shake := 0.0

func _ready() -> void:
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_STOP
    texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
    set_process(true)
    _load_ui()
    _load_motion()

func _load_ui() -> void:
    for element in ["life", "fire", "neutral"]:
        _ui["creature_plate:" + element] = _tex("creature_plate_%s" % element)
        _ui["creature_frame:" + element] = _tex("creature_frame_%s" % element)
        _ui["support:" + element] = _tex("support_%s" % element)
        if element != "neutral":
            _ui["landscape:" + element] = _tex("landscape_%s" % element)
            _ui["pip:" + element] = _tex("pip_%s" % element)
    for kind in ["landscape", "creature", "support"]:
        _ui["slot:" + kind] = _tex("slot_%s" % kind)

func _tex(name: String) -> Texture2D:
    var path := "res://assets/art/ui/v3/%s.png" % name
    if not ResourceLoader.exists(path): return null
    var res := ResourceLoader.load(path)
    return res if res is Texture2D else null

func _load_motion() -> void:
    if not FileAccess.file_exists("res://data/creature_motion.json"): return
    var file := FileAccess.open("res://data/creature_motion.json", FileAccess.READ)
    if file == null: return
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is not Dictionary: return
    _motion_styles = parsed.get("styles", {})
    _motion = parsed.get("creatures", {})

func motion_style(card_id: String) -> Dictionary:
    var name := String(_motion.get(card_id, "lunge"))
    var style = _motion_styles.get(name, {})
    var out: Dictionary = style.duplicate() if style is Dictionary else {}
    out["name"] = name
    return out

func _process(delta: float) -> void:
    _pulse = fmod(_pulse + delta, 1.0)
    if _shake > 0.0: _shake = maxf(0.0, _shake - delta * 3.4)
    var live: Array = []
    for act in _acts:
        act["t"] = float(act["t"]) + delta
        if float(act["t"]) < float(act["dur"]): live.append(act)
    _acts = live
    queue_redraw()

func busy() -> bool:
    return not _acts.is_empty()

func play(kind: String, payload: Dictionary, duration: float) -> void:
    var act := payload.duplicate()
    act["kind"] = kind
    act["t"] = 0.0
    act["dur"] = maxf(0.05, duration)
    _acts.append(act)

func shake(amount: float) -> void:
    _shake = maxf(_shake, amount)

func _find_act(kind: String, side: int, index: int) -> Dictionary:
    for act in _acts:
        if String(act["kind"]) == kind and int(act.get("side", -1)) == side \
                and int(act.get("lane", -1)) == index:
            return act
    return {}

# --- geometry ---------------------------------------------------------------

func _field_width() -> float:
    return maxf(400.0, size.x - RAIL_L - RAIL_R)

func lane_width() -> float:
    return _field_width() / float(MatchV3.LANES)

func _origin() -> Vector2:
    var jitter := Vector2.ZERO
    if _shake > 0.0:
        jitter = Vector2(sin(_shake * 41.0), cos(_shake * 33.0)) * _shake * 4.0
    var total := LAND_H * 2.0 + ROW_H * 2.0 + CLASH_H
    return Vector2(RAIL_L, (size.y - total) * 0.5) + jitter

## The whole lane column, top to bottom, for one side.
func lane_rect(side: int, index: int) -> Rect2:
    var o := _origin()
    var lw := lane_width()
    var top: float = o.y if side == 1 else o.y + LAND_H + ROW_H + CLASH_H
    return Rect2(o.x + index * lw, top, lw, LAND_H + ROW_H)

## Where the Landscape card lies. It is the floor of the lane, so it sits at the
## outside edge — nearest that player — with the creature standing in front of it.
func landscape_rect(side: int, index: int) -> Rect2:
    var lane := lane_rect(side, index)
    var y: float = lane.position.y if side == 1 else lane.position.y + ROW_H
    return Rect2(Vector2(lane.get_center().x - LAND_W * 0.5, y).round(),
        Vector2(LAND_W, LAND_H))

func creature_rect(side: int, index: int) -> Rect2:
    var lane := lane_rect(side, index)
    var y: float = lane.position.y + LAND_H if side == 1 else lane.position.y
    var x: float = lane.position.x + lane.size.x - CREATURE_W - 6.0
    return Rect2(Vector2(x, y + (ROW_H - CREATURE_H) * 0.5).round(),
        Vector2(CREATURE_W, CREATURE_H))

func support_rect(side: int, index: int) -> Rect2:
    var lane := lane_rect(side, index)
    var y: float = lane.position.y + LAND_H if side == 1 else lane.position.y
    return Rect2(Vector2(lane.position.x + 6.0,
        y + (ROW_H - SUPPORT_H) * 0.5).round(), Vector2(SUPPORT_W, SUPPORT_H))

func clash_centre(index: int) -> Vector2:
    var o := _origin()
    return Vector2(lane_rect(0, index).get_center().x, o.y + LAND_H + ROW_H + CLASH_H * 0.5)

func commander_rect(side: int) -> Rect2:
    var h: float = size.y * 0.5 - 12.0
    return Rect2(8.0, 8.0 if side == 1 else size.y * 0.5 + 4.0, RAIL_L - 16.0, h)

func status_rect(side: int) -> Rect2:
    var h: float = size.y * 0.5 - 12.0
    return Rect2(size.x - RAIL_R + 8.0, 8.0 if side == 1 else size.y * 0.5 + 4.0,
        RAIL_R - 16.0, h)

## The deck sits at the rail's outer end and the resource pool inboard of it,
## so neither lands on the other.
func deck_anchor(side: int) -> Vector2:
    var r := status_rect(side)
    return Vector2(r.get_center().x, r.position.y + (46.0 if side == 1 else r.size.y - 52.0))

## Where the resource rows start, reading inward from the deck.
func pool_top(side: int) -> float:
    var r := status_rect(side)
    return r.position.y + (r.size.y - 118.0 if side == 1 else 104.0)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        for side in range(2):
            for i in range(MatchV3.LANES):
                if creature_rect(side, i).has_point(event.position):
                    slot_clicked.emit(side, i, "creature"); return
                if support_rect(side, i).has_point(event.position):
                    slot_clicked.emit(side, i, "support"); return
                if landscape_rect(side, i).has_point(event.position):
                    slot_clicked.emit(side, i, "landscape"); return
                if lane_rect(side, i).has_point(event.position):
                    slot_clicked.emit(side, i, "creature"); return
    elif event is InputEventMouseMotion:
        for side in range(2):
            for i in range(MatchV3.LANES):
                if lane_rect(side, i).has_point(event.position):
                    if side != hover_side or i != hover_lane:
                        hover_side = side; hover_lane = i
                        slot_hovered.emit(side, i)
                    return
        hover_side = -1; hover_lane = -1

# --- drawing ----------------------------------------------------------------

func _draw() -> void:
    if engine == null or engine.players.is_empty(): return
    var f := ArcanaTheme.font()
    _draw_table()
    for side in range(2):
        for i in range(MatchV3.LANES):
            _draw_lane_bed(side, i)
    _draw_clash_line()
    for side in range(2):
        for i in range(MatchV3.LANES):
            _draw_landscape(side, i, f)
    for side in range(2):
        for i in range(MatchV3.LANES):
            _draw_support(side, i, f)
    for side in range(2):
        for i in range(MatchV3.LANES):
            _draw_creature(side, i, f)
    _draw_orphan_attackers()
    _draw_emergent()
    for side in range(2):
        _draw_commander(side, f)
        _draw_status(side, f)
    _draw_fusion_acts(f)
    _draw_floats(f)
    _draw_vignette()

## The table itself: neutral ground, so the lanes read as cards laid on wood
## rather than as a landscape the player walks through.
func _draw_table() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), ArcanaTheme.BG)
    if art == null: return
    var field: Texture2D = art.land_field("neutral")
    if field == null: return
    _tile(field, Rect2(Vector2.ZERO, size))
    # Lift it toward daylight. The reference boards are bright and saturated;
    # a dark table makes every lane read as the same murky colour.
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.70, 0.66, 0.56, 0.42))

## Bright, unmistakable lane colours. Grove is spring green, Cinder is hot
## charcoal-orange; nothing else on the board uses either.
const LANE_COLOUR := {
    "grove": Color(0.44, 0.70, 0.27),
    "cinder": Color(0.56, 0.27, 0.16),
    "ashbloom": Color(0.40, 0.42, 0.24),
}

func _tile_tinted(tex: Texture2D, r: Rect2, tint: Color) -> void:
    var fw := float(tex.get_width())
    var fh := float(tex.get_height())
    var y := r.position.y
    while y < r.position.y + r.size.y:
        var sy: float = fposmod(y, fh)
        var h: float = minf(fh - sy, r.position.y + r.size.y - y)
        var x := r.position.x
        while x < r.position.x + r.size.x:
            var sx: float = fposmod(x, fw)
            var w: float = minf(fw - sx, r.position.x + r.size.x - x)
            draw_texture_rect_region(tex, Rect2(Vector2(x, y).round(), Vector2(w, h).round()),
                Rect2(sx, sy, w, h), tint, false)
            x += w
        y += h

func _tile(tex: Texture2D, r: Rect2) -> void:
    var fw := float(tex.get_width())
    var fh := float(tex.get_height())
    var y := r.position.y
    while y < r.position.y + r.size.y:
        var sy: float = fposmod(y, fh)
        var h: float = minf(fh - sy, r.position.y + r.size.y - y)
        var x := r.position.x
        while x < r.position.x + r.size.x:
            var sx: float = fposmod(x, fw)
            var w: float = minf(fw - sx, r.position.x + r.size.x - x)
            draw_texture_rect_region(tex, Rect2(Vector2(x, y).round(), Vector2(w, h).round()),
                Rect2(sx, sy, w, h), Color.WHITE, false)
            x += w
        y += h

## A lane's bed. Once a Landscape is down the whole column takes its element, so
## the lane is visibly *that* land and not a slot that happens to contain a card.
func _draw_lane_bed(side: int, index: int) -> void:
    var lane := lane_rect(side, index)
    var terrain := String(engine.lane(side, index)["terrain"])
    var inner := lane.grow(-4.0)
    if terrain == "":
        draw_rect(inner, Color(0.46, 0.44, 0.38, 0.55))
        draw_rect(inner, Color(0.66, 0.63, 0.56, 0.85), false, 2.0)
        var f2 := ArcanaTheme.font()
        var prompt := "PLAY A LANDSCAPE"
        var pw2: float = f2.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
        draw_string(f2, Vector2(inner.get_center().x - pw2 * 0.5, inner.get_center().y + 4.0),
            prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.90, 0.84, 0.65))
        return
    var grow := 1.0
    var act := _find_act("landscape", side, index)
    if not act.is_empty():
        grow = clampf(float(act["t"]) / float(act["dur"]) / 0.7, 0.0, 1.0)
    var field: Texture2D = art.land_field(terrain) if art != null else null
    var eased: float = 1.0 - pow(1.0 - grow, 3.0)
    var bed := Rect2(inner.get_center() - inner.size * 0.5 * eased, inner.size * eased)
    var element := String(MatchV3.TERRAIN_ELEMENT.get(terrain, "life"))
    var strip: Color = LANE_COLOUR.get(terrain, Color(0.4, 0.5, 0.3))
    # A saturated bed under the texture, then the texture over it. The land has
    # to be identifiable by colour alone from across the table — that is what
    # lets a player match a card's landscape strip to the lane it belongs in.
    draw_rect(bed, strip)
    if field != null:
        _tile_tinted(field, bed, Color(1.25, 1.22, 1.10, 0.55))
    draw_rect(bed, Color(strip, 0.30))
    var accent: Color = ArcanaTheme.color_for_element(element)
    draw_rect(bed, Color(accent.lightened(0.30), 0.85), false, 3.0)

    var key := "%d,%d" % [side, index]
    if highlights.has(key):
        var tint: Color = ArcanaTheme.HEART if String(highlights[key]) == "attack" else accent
        var pulse: float = 0.30 + 0.26 * sin(_pulse * TAU)
        draw_rect(bed, Color(tint, pulse * 0.35))
        draw_rect(bed.grow(2.0), Color(tint, 0.55 + 0.35 * sin(_pulse * TAU)), false, 3.0)
    elif side == hover_side and index == hover_lane:
        draw_rect(bed, Color(1, 1, 1, 0.06))

func _draw_clash_line() -> void:
    var o := _origin()
    var y: float = o.y + LAND_H + ROW_H
    var band := Rect2(o.x - 8.0, y, _field_width() + 16.0, CLASH_H)
    draw_rect(band, Color(0.06, 0.05, 0.08, 0.55))
    for i in range(MatchV3.LANES):
        var c := clash_centre(i)
        var open: bool = engine.lane(1, i)["creature"] == null
        var tint: Color = ArcanaTheme.HEART if open else Color(0.36, 0.34, 0.32)
        var wave: float = 0.5 + 0.5 * sin(_pulse * TAU + float(i) * 0.7)
        draw_line(Vector2(c.x - 26.0, c.y), Vector2(c.x + 26.0, c.y), Color(tint, 0.35), 2.0)
        draw_circle(c, 5.0 + 1.5 * wave, Color(tint, 0.70 + 0.25 * wave))

## The Landscape card: the lane's floor, and the thing that pays for everything
## played on it.
func _draw_landscape(side: int, index: int, f: Font) -> void:
    var r := landscape_rect(side, index)
    var terrain := String(engine.lane(side, index)["terrain"])
    if terrain == "":
        var slot: Texture2D = _ui.get("slot:landscape", null)
        if slot != null: draw_texture_rect(slot, r, false, Color(1, 1, 1, 0.5))
        var label := "LANDSCAPE"
        var lw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
        draw_string(f, Vector2(r.get_center().x - lw * 0.5, r.get_center().y + 4.0), label,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ArcanaTheme.TEXT_FAINT, 0.7))
        return
    var element := String(MatchV3.TERRAIN_ELEMENT.get(terrain, "life"))
    var grow := 1.0
    var act := _find_act("landscape", side, index)
    if not act.is_empty():
        grow = clampf(float(act["t"]) / float(act["dur"]) / 0.55, 0.0, 1.0)
    var eased: float = 1.0 - pow(1.0 - grow, 3.0)
    if eased <= 0.02: return
    var drawn := Rect2(r.get_center() - r.size * 0.5 * eased, r.size * eased)
    var tex: Texture2D = _ui.get("landscape:" + element, null)
    if tex != null: draw_texture_rect(tex, Rect2(drawn.position.round(), drawn.size.round()), false)
    else: draw_rect(drawn, ArcanaTheme.color_for_terrain(terrain))
    if eased < 0.99: return
    var name := String(engine.db.card(String(engine.lane(side, index)["landscape_card"])).get("name", terrain.capitalize()))
    draw_string(f, Vector2(r.position.x + 9.0, r.position.y + r.size.y - 6.0), name.to_upper(),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ArcanaTheme.TEXT)
    # The pip is the point: this card is one resource, every turn.
    var pip: Texture2D = _ui.get("pip:" + element, null)
    if pip != null:
        var ps := Vector2(pip.get_width(), pip.get_height()) * 0.8
        draw_texture_rect(pip, Rect2(Vector2(r.position.x + r.size.x - ps.x - 8.0,
            r.get_center().y - ps.y * 0.5).round(), ps), false)

func _draw_support(side: int, index: int, f: Font) -> void:
    var r := support_rect(side, index)
    var support = engine.lane(side, index)["support"]
    if support == null:
        if String(engine.lane(side, index)["terrain"]) == "": return
        var slot: Texture2D = _ui.get("slot:support", null)
        if slot != null: draw_texture_rect(slot, r, false, Color(1, 1, 1, 0.4))
        return
    var element := String(engine.db.element_of(String(support["card_id"])))
    var tex: Texture2D = _ui.get("support:" + element, null)
    var grow := 1.0
    var act := _find_act("support", side, index)
    if not act.is_empty():
        grow = clampf(float(act["t"]) / float(act["dur"]) / 0.8, 0.0, 1.0)
    var eased: float = 1.0 - pow(1.0 - grow, 3.0)
    if eased <= 0.02: return
    var drawn := Rect2(r.get_center() - r.size * 0.5 * eased, r.size * eased)
    if tex != null: draw_texture_rect(tex, Rect2(drawn.position.round(), drawn.size.round()), false)
    var body: Texture2D = art.landmark(String(support["card_id"])) if art != null else null
    if body != null and eased > 0.4:
        var bs := Vector2(body.get_width(), body.get_height())
        var win := Rect2(drawn.position + Vector2(5, 5), Vector2(drawn.size.x - 10, drawn.size.y - 28))
        var fit: float = minf(win.size.x / bs.x, win.size.y / bs.y)
        var bd := bs * fit
        draw_texture_rect(body, Rect2((win.get_center() - bd * 0.5).round(), bd.round()), false)
    if eased < 0.99: return
    var name := ArcanaTheme.fit(String(support["name"]), 8, r.size.x - 8.0)
    var nw: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
    draw_string(f, Vector2(r.get_center().x - nw * 0.5, r.position.y + r.size.y - 8.0), name,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ArcanaTheme.TEXT_DIM)

## A played creature: a card standing in its lane.
##
## The card is the piece and it stays in its slot. During an attack the card
## anticipates and the creature climbs out over its own frame — collected into
## `_emergent` and drawn after every card, so a lunging creature is never painted
## over by the card next door — then drops back in.
func _draw_creature(side: int, index: int, f: Font) -> void:
    var unit = engine.lane(side, index)["creature"]
    if unit == null:
        if String(engine.lane(side, index)["terrain"]) == "": return
        var slot: Texture2D = _ui.get("slot:creature", null)
        if slot != null:
            draw_texture_rect(slot, creature_rect(side, index), false, Color(1, 1, 1, 0.4))
        return

    var base := creature_rect(side, index)
    var card_id := String(unit["card_id"])
    var element := String(unit["element"])
    var offset := Vector2.ZERO
    var squash := Vector2.ONE
    var scale := 1.0
    var glow := 0.0
    var beat := {}

    var summon := _find_act("summon", side, index)
    if not summon.is_empty():
        var st: float = clampf(float(summon["t"]) / float(summon["dur"]), 0.0, 1.0)
        if st < 0.32: scale = 0.0
        else:
            var k: float = (st - 0.32) / 0.68
            var e1: float = 1.0 - pow(1.0 - k, 3.0)
            scale = e1
            squash = Vector2(0.80 + 0.20 * e1 + 0.18 * sin(e1 * PI),
                             0.70 + 0.30 * e1 - 0.14 * sin(e1 * PI))
    var fuse := _find_act("fusion", side, index)
    if not fuse.is_empty():
        var ft: float = clampf(float(fuse["t"]) / float(fuse["dur"]), 0.0, 1.0)
        if ft < 0.76: scale = 0.0
        else:
            var k2: float = (ft - 0.76) / 0.24
            scale = 1.0 + 0.45 * (1.0 - k2)
            squash = Vector2(1.0 + 0.22 * (1.0 - k2), 1.0 - 0.22 * (1.0 - k2))
    for act in _acts:
        if String(act["kind"]) == "attack" and int(act.get("uid", -1)) == int(unit["uid"]):
            beat = _attack_beat(act, side, index, card_id)
            offset += Vector2(beat["card_offset"])
            glow = maxf(glow, float(beat["glow"]))
        elif String(act["kind"]) == "hurt" and int(act.get("uid", -1)) == int(unit["uid"]):
            var ht: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
            offset += Vector2(sin(ht * 52.0) * (1.0 - ht) * 9.0, 0.0)
            squash *= Vector2(1.0 + 0.09 * (1.0 - ht), 1.0 - 0.09 * (1.0 - ht))
            glow = maxf(glow, 1.0 - ht)
    if scale <= 0.001: return
    if side == hover_side and index == hover_lane: offset += Vector2(0.0, -5.0)

    var drawn := base.size * squash * scale
    var r := Rect2((base.get_center() + offset - drawn * 0.5).round(), drawn.round())

    draw_rect(Rect2(r.position.x + 6.0, r.position.y + r.size.y - 6.0, r.size.x - 12.0, 8.0),
        Color(0.03, 0.02, 0.04, 0.35))
    if glow > 0.0:
        draw_rect(r.grow(4.0 + 6.0 * glow), Color(ArcanaTheme.color_for_element(element), 0.26 * glow))

    var ready: bool = bool(unit.get("ready", true))
    var tint := Color(1, 1, 1, 1)
    if side == 0 and not ready: tint = Color(0.70, 0.70, 0.76, 1.0)
    var plate: Texture2D = _ui.get("creature_plate:" + element, null)
    var frame: Texture2D = _ui.get("creature_frame:" + element, null)
    if plate != null: draw_texture_rect(plate, r, false, tint)
    else: draw_rect(r, Color(0.12, 0.11, 0.15))

    var tex: Texture2D = art.creature(card_id) if art != null else null
    var out: float = float(beat.get("out", 0.0)) if not beat.is_empty() else 0.0
    if tex != null:
        var ts := Vector2(tex.get_width(), tex.get_height())
        var k3: float = r.size.y / CREATURE_H
        var win := Rect2(r.position + Vector2(5.0 * k3, 27.0 * k3),
            Vector2(r.size.x - 10.0 * k3, 124.0 * k3))
        var fit: float = minf(win.size.x / ts.x, win.size.y / ts.y) * clampf(ts.y / 96.0, 0.70, 1.0)
        if out <= 0.001:
            var cd := ts * fit
            draw_texture_rect(tex, Rect2((win.get_center() - cd * 0.5).round(), cd.round()), false, tint)
        else:
            _emergent.append({"tex": tex, "at": Vector2(beat["at"]), "fit": fit,
                "scale": float(beat["scale"]), "squash": Vector2(beat["squash"]),
                "flip": bool(beat["flip"]), "glow": float(beat["glow"]),
                "colour": ArcanaTheme.color_for_element(element)})
    if frame != null: draw_texture_rect(frame, r, false, tint)
    if scale < 0.7: return

    var k4: float = r.size.y / CREATURE_H
    var name := ArcanaTheme.fit(String(unit["name"]), 11, r.size.x - 12.0)
    var nw: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
    draw_string(f, Vector2(r.get_center().x - nw * 0.5, r.position.y + 18.0 * k4), name,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT)
    # The landscape strip: the same colour as the lane this card belongs in, so
    # card and land can be matched by colour without reading a word.
    var required := String(engine.db.card(card_id).get("play_on", ""))
    if required != "":
        var strip_colour: Color = LANE_COLOUR.get(required, Color(0.4, 0.4, 0.4))
        var band := Rect2(r.position.x + 5.0 * k4, r.position.y + 152.0 * k4,
            r.size.x - 10.0 * k4, 14.0 * k4)
        draw_rect(band, strip_colour)
        draw_rect(band, Color(strip_colour.lightened(0.35), 0.9), false, 1.0)
        var tag := "%s CREATURE" % required.to_upper()
        var tw2: float = f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
        draw_string(f, Vector2(band.get_center().x - tw2 * 0.5, band.position.y + 10.0 * k4),
            tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.94))

    # Power reads its *effective* value, so a buffed creature shows its real number.
    var power := engine.effective_power(side, index)
    var buffed: bool = power > int(unit["power"])
    _pip(f, Vector2(r.position.x + 16.0, r.position.y + r.size.y - 15.0), str(power),
        ArcanaTheme.GOLD if not buffed else Color("#b8f27a"))
    _pip(f, Vector2(r.position.x + r.size.x - 16.0, r.position.y + r.size.y - 15.0),
        str(int(unit["health"])),
        ArcanaTheme.HEART if int(unit["health"]) < int(unit["max_health"]) else Color("#ffb3c4"))
    if side == 0 and not ready:
        var rest := "RESTING"
        var rw: float = f.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
        draw_string(f, Vector2(r.get_center().x - rw * 0.5, r.position.y + r.size.y - 4.0),
            rest, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ArcanaTheme.TEXT_FAINT)
    if fusion_pairs.has(index) and side == 0:
        var c := Vector2(r.position.x + r.size.x - 5.0, r.position.y - 3.0)
        draw_circle(c, 11.0, Color(ArcanaTheme.BG, 0.9))
        draw_arc(c, 11.0, _pulse * TAU, _pulse * TAU + PI * 1.5, 18, ArcanaTheme.GOLD, 2.5)
        draw_string(f, c - Vector2(5, -5), "∞", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ArcanaTheme.GOLD)

func _pip(f: Font, centre: Vector2, text: String, colour: Color) -> void:
    draw_circle(centre, 11.0, Color(0.05, 0.04, 0.07, 0.94))
    draw_arc(centre, 11.0, 0, TAU, 20, Color(colour, 0.95), 2.0)
    var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
    draw_string(f, Vector2(centre.x - w * 0.5, centre.y + 5.0), text,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colour)

## Where a creature is part-way through leaving its card. Reach and arc come from
## data/creature_motion.json, so a Sproutling hops a short way while a Petal Deer
## charges the whole lane and a dragon never leaves home at all.
func _attack_beat(act: Dictionary, side: int, index: int, card_id: String) -> Dictionary:
    var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
    var style := motion_style(card_id)
    var reach: float = float(style.get("reach", 0.6))
    var arc: float = float(style.get("arc", 0.0))
    var wind: float = float(style.get("wind", 0.2))
    var stationary: bool = style.has("projectile")
    var home := creature_rect(side, index).get_center()
    var meet := clash_centre(index)
    var toward := meet - home
    var card_offset := Vector2.ZERO
    var glow := 0.0
    var out := 0.0
    var at := home
    var scale := 1.0
    var squash := Vector2.ONE

    if t < wind:
        var k: float = t / maxf(wind, 0.001)
        glow = k * 0.85
        card_offset = -toward.normalized() * 4.0 * k
        out = k * 0.3
        at = home - toward.normalized() * 5.0 * k
        scale = 1.0 + 0.10 * k
        squash = Vector2(1.0 + 0.12 * k, 1.0 - 0.12 * k)
    elif t < 0.52:
        var k2: float = (t - wind) / maxf(0.52 - wind, 0.001)
        var eased: float = 1.0 - pow(1.0 - k2, 2.2)
        glow = 0.85 - 0.45 * k2
        out = 1.0
        scale = 1.16 + 0.14 * eased
        if stationary:
            at = home + Vector2(0.0, (-1.0 if side == 0 else 1.0) * 74.0 * eased)
            scale = 1.2 + 0.5 * eased
        else:
            at = home + toward * reach * eased
            if arc > 0.0: at.y -= sin(eased * PI) * toward.length() * arc * 0.4
            elif String(style.get("name", "")) == "hop": at.y -= absf(sin(eased * PI * 2.4)) * 20.0
            elif String(style.get("name", "")) == "slam": at.y -= sin(minf(eased * 1.6, 1.0) * PI) * 26.0
    elif t < 0.88:
        var k3: float = (t - 0.52) / 0.36
        var back: float = 1.0 - (1.0 - pow(1.0 - k3, 2.0))
        glow = 0.4 * (1.0 - k3)
        out = 1.0 - k3 * 0.8
        scale = 1.0 + 0.28 * back
        at = home + Vector2(0.0, (-1.0 if side == 0 else 1.0) * 74.0 * back) if stationary \
            else home + toward * reach * back
    else:
        var k4: float = (t - 0.88) / 0.12
        out = (1.0 - k4) * 0.2
        scale = 1.0 + 0.06 * (1.0 - k4)
    # No mirroring. Lanes face each other head-on, so a flip buys nothing, and
    # drawing a negative-width rect displaced the sprite instead of mirroring it.
    return {"card_offset": card_offset, "glow": glow, "out": out, "at": at,
            "scale": scale, "squash": squash, "flip": false}

## An attacker that died to the counter-blow still has to finish its lunge.
## Its card has already left the lane, so the creature is drawn from the act.
func _draw_orphan_attackers() -> void:
    if art == null: return
    for act in _acts:
        if String(act["kind"]) != "attack": continue
        var side := int(act.get("side", 0))
        var index := int(act.get("lane", 0))
        if engine.lane(side, index)["creature"] != null: continue
        var card_id := String(act.get("card_id", ""))
        if card_id == "": continue
        var tex: Texture2D = art.creature(card_id)
        if tex == null: continue
        var beat := _attack_beat(act, side, index, card_id)
        if float(beat["out"]) <= 0.001: continue
        var ts := Vector2(tex.get_width(), tex.get_height())
        var win := Rect2(creature_rect(side, index).position + Vector2(5, 27),
            Vector2(CREATURE_W - 10, 124))
        var fit: float = minf(win.size.x / ts.x, win.size.y / ts.y) * clampf(ts.y / 96.0, 0.70, 1.0)
        _emergent.append({"tex": tex, "at": Vector2(beat["at"]), "fit": fit,
            "scale": float(beat["scale"]), "squash": Vector2(beat["squash"]),
            "flip": bool(beat["flip"]), "glow": float(beat["glow"]),
            "colour": ArcanaTheme.color_for_element(engine.db.element_of(card_id))})

func _draw_emergent() -> void:
    for e in _emergent:
        var tex: Texture2D = e["tex"]
        var ts := Vector2(tex.get_width(), tex.get_height())
        var drawn := ts * float(e["fit"]) * float(e["scale"]) * Vector2(e["squash"])
        var at: Vector2 = e["at"]
        draw_circle(Vector2(at.x, at.y + drawn.y * 0.44), drawn.x * 0.28, Color(0.03, 0.02, 0.04, 0.32))
        if float(e["glow"]) > 0.0:
            draw_circle(at, drawn.x * 0.52, Color(e["colour"], 0.16 * float(e["glow"])))
        draw_texture_rect(tex, Rect2((at - drawn * 0.5).round(), drawn.round()), false)
    _emergent.clear()

## Fusion, done with the cards: two lift, converge, collapse into light, and the
## result slams down in the first lane.
func _draw_fusion_acts(f: Font) -> void:
    for act in _acts:
        if String(act["kind"]) != "fusion": continue
        var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
        var side := int(act["side"])
        var a := creature_rect(side, int(act["lane"]))
        var b := creature_rect(side, int(act["freed_lane"]))
        var colour: Color = act.get("colour", ArcanaTheme.GOLD)
        if t < 0.82: draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.42 * clampf(t / 0.16, 0.0, 1.0)))
        if t < 0.60:
            var k: float = t / 0.60
            var eased: float = k * k * (3.0 - 2.0 * k)
            var mid := a.get_center().lerp(b.get_center(), 0.5) - Vector2(0.0, 22.0 * sin(eased * PI * 0.9))
            var pa := a.get_center().lerp(mid, eased)
            var pb := b.get_center().lerp(mid, eased)
            for i in range(14):
                var u: float = float(i) / 14.0
                var wob: float = sin(u * PI * 3.0 + eased * TAU) * 22.0 * (1.0 - eased * 0.5)
                draw_line(pa.lerp(pb, u) + Vector2(0, wob), pa.lerp(pb, u + 0.075) + Vector2(0, wob * 0.8),
                    Color(colour, 0.28 + 0.55 * sin((u + t) * PI * 3.0)), 3.0)
            var shrink: float = 1.0 - 0.28 * eased
            for pair in [[pa, String(act.get("card_a", ""))], [pb, String(act.get("card_b", ""))]]:
                var at: Vector2 = pair[0]
                var cid := String(pair[1])
                var element := engine.db.element_of(cid) if cid != "" else "life"
                var dsz := a.size * shrink
                var rr := Rect2((at - dsz * 0.5).round(), dsz.round())
                var plate: Texture2D = _ui.get("creature_plate:" + element, null)
                if plate != null: draw_texture_rect(plate, rr, false)
                var body: Texture2D = art.creature(cid) if (art != null and cid != "") else null
                if body != null:
                    var bs := Vector2(body.get_width(), body.get_height())
                    var win := Rect2(rr.position + Vector2(5, 27) * shrink,
                        Vector2(rr.size.x - 10 * shrink, 124 * shrink))
                    var fit: float = minf(win.size.x / bs.x, win.size.y / bs.y)
                    var bd := bs * fit
                    draw_texture_rect(body, Rect2((win.get_center() - bd * 0.5).round(), bd.round()), false)
                var fr: Texture2D = _ui.get("creature_frame:" + element, null)
                if fr != null: draw_texture_rect(fr, rr, false)
            draw_circle(mid, 8.0 + 48.0 * eased * eased, Color(1, 1, 1, 0.20 + 0.66 * eased * eased))
        elif t < 0.76:
            var k2: float = (t - 0.60) / 0.16
            draw_circle(a.get_center(), 62.0 * (1.0 - k2) + 20.0, Color(1, 1, 1, 0.88 * (1.0 - k2)))
            draw_arc(a.get_center(), 40.0 + 120.0 * k2, 0, TAU, 40, Color(colour, 1.0 - k2), 5.0)
        else:
            var k3: float = (t - 0.76) / 0.24
            draw_arc(a.get_center(), 30.0 + 96.0 * k3, 0, TAU, 34,
                Color(ArcanaTheme.GOLD, 0.8 * (1.0 - k3)), 4.0)
            var name := String(act.get("name", ""))
            var w: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
            draw_string(f, Vector2(a.get_center().x - w * 0.5, a.position.y - 14.0 - 10.0 * k3),
                name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ArcanaTheme.GOLD, 1.0 - k3 * k3))

func _draw_floats(f: Font) -> void:
    for act in _acts:
        if String(act["kind"]) != "float": continue
        var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
        var at: Vector2 = act["at"]
        var text := String(act["text"])
        var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
        draw_string(f, Vector2(at.x - w * 0.5, at.y - 20.0 - t * 26.0), text,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(act.get("colour", ArcanaTheme.TEXT), 1.0 - t * t))

func _draw_vignette() -> void:
    var dark := Color(0.06, 0.05, 0.09, 0.30)
    var clear := Color(0.06, 0.05, 0.09, 0.0)
    var d: float = size.y * 0.12
    var sd: float = size.x * 0.07
    for q in [[PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, d), Vector2(0, d)]),
               [dark, dark, clear, clear]],
              [PackedVector2Array([Vector2(0, size.y - d), Vector2(size.x, size.y - d),
                                   Vector2(size.x, size.y), Vector2(0, size.y)]),
               [clear, clear, dark, dark]],
              [PackedVector2Array([Vector2(0, 0), Vector2(sd, 0), Vector2(sd, size.y), Vector2(0, size.y)]),
               [dark, clear, clear, dark]],
              [PackedVector2Array([Vector2(size.x - sd, 0), Vector2(size.x, 0),
                                   Vector2(size.x, size.y), Vector2(size.x - sd, size.y)]),
               [clear, dark, dark, clear]]]:
        draw_polygon(q[0], PackedColorArray(q[1]))

## The left rail: who you are and what you are protecting.
func _draw_commander(side: int, f: Font) -> void:
    var r := commander_rect(side)
    var p: Dictionary = engine.players[side]
    var cmd := engine.commander(side)
    var element := String(p["element"])
    var accent: Color = ArcanaTheme.color_for_element(element)
    var breathe: float = 0.5 + 0.5 * sin(_pulse * TAU + side * PI)

    draw_rect(r, Color(0.07, 0.06, 0.10, 0.74))
    draw_rect(r, Color(accent, 0.42), false, 2.0)

    var home: Texture2D = art.sanctuary(element) if art != null else null
    if home != null:
        var hs := Vector2(home.get_width(), home.get_height())
        var fit: float = minf((r.size.x - 16.0) / hs.x, 74.0 / hs.y)
        var hd := hs * fit
        draw_texture_rect(home, Rect2(Vector2(r.get_center().x - hd.x * 0.5,
            r.position.y + 10.0).round(), hd), false, Color(1, 1, 1, 0.55))

    var avatar: Texture2D = art.commander_board(String(p["commander_id"])) if art != null else null
    var face_y: float = r.position.y + 96.0
    if avatar != null:
        var asz := Vector2(avatar.get_width(), avatar.get_height())
        var afit: float = minf(72.0 / asz.x, 72.0 / asz.y)
        var ad := asz * afit
        draw_circle(Vector2(r.get_center().x, face_y + 2.0), ad.x * 0.34, Color(0, 0, 0, 0.3))
        draw_texture_rect(avatar, Rect2(Vector2(r.get_center().x - ad.x * 0.5,
            face_y - ad.y).round(), ad), false)
    var name := ArcanaTheme.fit(String(cmd.get("name", "")), 12, r.size.x - 10.0)
    var nw: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
    draw_string(f, Vector2(r.get_center().x - nw * 0.5, face_y + 16.0), name,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.TEXT)

    # The Heart, big, because breaking it is the whole win condition.
    var heart := int(p["heart"])
    var frac: float = clampf(float(heart) / float(MatchV3.HEART_START), 0.0, 1.0)
    var hc := Vector2(r.get_center().x, face_y + 62.0)
    var rad: float = 27.0 * (1.0 + 0.05 * sin(_pulse * TAU * (2.4 if frac < 0.35 else 1.2)))
    draw_circle(hc, rad * 1.5, Color(ArcanaTheme.HEART, 0.08 + 0.06 * breathe))
    var facets := PackedVector2Array([hc + Vector2(0, -rad), hc + Vector2(rad * 0.76, 0),
        hc + Vector2(0, rad), hc + Vector2(-rad * 0.76, 0)])
    draw_colored_polygon(facets, Color(0.08, 0.03, 0.06, 0.96))
    var fill_top: float = hc.y + rad - 2.0 * rad * frac
    var filled := PackedVector2Array()
    for i in range(facets.size()):
        var a: Vector2 = facets[i]
        var b: Vector2 = facets[(i + 1) % facets.size()]
        if a.y >= fill_top: filled.append(a)
        if (a.y < fill_top) != (b.y < fill_top):
            filled.append(a.lerp(b, (fill_top - a.y) / (b.y - a.y)))
    if filled.size() >= 3: draw_colored_polygon(filled, Color(ArcanaTheme.HEART, 0.92))
    draw_polyline(PackedVector2Array([facets[0], facets[1], facets[2], facets[3], facets[0]]),
        Color(ArcanaTheme.HEART, 0.95), 2.0)
    var hw: float = f.get_string_size(str(heart), HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
    draw_string(f, Vector2(hc.x - hw * 0.5, hc.y + 7.0), str(heart),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 19, ArcanaTheme.TEXT)

    # Passive always on; the power is a single charge you spend once a match.
    var passive := ArcanaTheme.fit(String(cmd.get("passive_name", "")), 9, r.size.x - 10.0)
    var pw: float = f.get_string_size(passive, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
    draw_string(f, Vector2(r.get_center().x - pw * 0.5, hc.y + rad + 18.0), passive,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ArcanaTheme.TEXT_DIM)
    var used: bool = bool(p["power_used"])
    var badge := Rect2(r.position.x + 8.0, hc.y + rad + 26.0, r.size.x - 16.0, 22.0)
    draw_rect(badge, Color(ArcanaTheme.GOLD if not used else ArcanaTheme.PANEL_EDGE,
        0.24 if not used else 0.10))
    draw_rect(badge, Color(ArcanaTheme.GOLD if not used else ArcanaTheme.PANEL_EDGE, 0.7), false, 1.0)
    var label := ArcanaTheme.fit(String(cmd.get("power_name", "")), 10, badge.size.x - 8.0)
    if used: label = "SPENT"
    var lw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
    draw_string(f, Vector2(badge.get_center().x - lw * 0.5, badge.position.y + 15.0), label,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
        ArcanaTheme.GOLD if not used else ArcanaTheme.TEXT_FAINT)

## The right rail: the pool, which is the whole economy, and the deck.
func _draw_status(side: int, f: Font) -> void:
    var r := status_rect(side)
    var p: Dictionary = engine.players[side]
    draw_rect(r, Color(0.07, 0.06, 0.10, 0.66))
    draw_rect(r, Color(ArcanaTheme.PANEL_EDGE, 0.5), false, 1.0)

    var title := "RESOURCE"
    var tw: float = f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
    var top: float = pool_top(side)
    draw_string(f, Vector2(r.get_center().x - tw * 0.5, top), title,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ArcanaTheme.TEXT_FAINT)

    # One row per element: pip, spendable, and how much land is behind it.
    var row := top + 8.0
    var shown := 0
    for element in MatchV3.ELEMENTS:
        var have := engine.pool(side, element)
        var land := engine.landscape_count(side, element)
        if have == 0 and land == 0: continue
        shown += 1
        var pip: Texture2D = _ui.get("pip:" + element, null)
        if pip != null:
            var ps := Vector2(pip.get_width(), pip.get_height())
            draw_texture_rect(pip, Rect2(Vector2(r.position.x + 8.0, row).round(), ps), false)
        var text := "%d" % have
        draw_string(f, Vector2(r.position.x + 40.0, row + 20.0), text,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ArcanaTheme.TEXT)
        draw_string(f, Vector2(r.position.x + 62.0, row + 20.0), "/%d" % land,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.TEXT_FAINT)
        row += 32.0
    if shown == 0:
        # Before any land is down, say so rather than leaving the label bare.
        var none := "no land yet"
        var nw2: float = f.get_string_size(none, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
        draw_string(f, Vector2(r.get_center().x - nw2 * 0.5, row + 14.0), none,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ArcanaTheme.TEXT_FAINT)

    var deck := deck_anchor(side)
    var back: Texture2D = art.frame("card_back:%s" % String(p["element"])) if art != null else null
    var layers: int = clampi(int(p["deck"].size() / 8) + 1, 1, 4)
    for i in range(layers):
        var dest := Rect2((deck - Vector2(23.0, 28.0) + Vector2(i * 2.0, -i * 2.0)).round(),
            Vector2(46.0, 56.0))
        if back != null: draw_texture_rect(back, dest, false)
        else: draw_rect(dest, Color(0.14, 0.12, 0.18))
    var count := str(p["deck"].size())
    var cw: float = f.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
    draw_string(f, Vector2(deck.x - cw * 0.5, deck.y + 44.0), count,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT_DIM)
