class_name StageV2
extends Control
## The V2 split-lane battlefield, and the choreography that plays over it.
##
## Layout, top to bottom: rival Sanctuary, rival lanes, the front line, your
## lanes, your Sanctuary. Creatures never cross the front line — attacks travel
## to it and come home, exactly as docs/V2_CLARITY_REDESIGN.md describes.
##
## Every animation here reads a committed event. None of it decides an outcome.

signal lane_clicked(side: int, index: int)
signal sanctuary_clicked(side: int)
signal lane_hovered(side: int, index: int)
## Fired at the exact beat a sound should play. Nothing listens yet; wiring audio
## later means connecting this rather than hunting through the animation code.
signal cue(name: String, strength: float)

const LANE_W := 196.0
const LANE_H := 126.0
const LANE_GAP := 12.0
const SANCTUARY_H := 84.0
const FRONT_GAP := 24.0

var engine: MatchV2
var art: ArtRegistry
var highlights: Dictionary = {}          # "side,lane" -> "legal" | "attack"
var dim_others := false
var hover_side := -1
var hover_lane := -1
var selected_lane := -1
var ghost_card := ""
var fusion_pairs: Array = []             # lanes that currently show a linked rune

var _acts: Array = []                    # running choreography
var _particles: Array = []
var _pulse := 0.0
var _shake := 0.0
var _hitstop := 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_process(true)

func _process(delta: float) -> void:
    _pulse = fmod(_pulse + delta, 1.0)
    if _hitstop > 0.0:
        # Brief freeze on strong impacts; everything else waits with it.
        _hitstop = maxf(0.0, _hitstop - delta)
        queue_redraw()
        return
    if _shake > 0.0: _shake = maxf(0.0, _shake - delta * 3.4)
    var live: Array = []
    for act in _acts:
        act["t"] = float(act["t"]) + delta
        _tick_act(act, delta)
        if float(act["t"]) < float(act["dur"]): live.append(act)
    _acts = live
    var alive: Array = []
    for pt in _particles:
        pt["t"] = float(pt["t"]) + delta
        if float(pt["t"]) >= float(pt["life"]): continue
        pt["pos"] = Vector2(pt["pos"]) + Vector2(pt["vel"]) * delta
        pt["vel"] = Vector2(pt["vel"]) + Vector2(0, float(pt["gravity"])) * delta
        alive.append(pt)
    _particles = alive
    queue_redraw()

func busy() -> bool:
    return not _acts.is_empty()

# --- geometry ---------------------------------------------------------------

func _rows_height() -> float:
    return SANCTUARY_H * 2.0 + LANE_H * 2.0 + FRONT_GAP

func _origin() -> Vector2:
    var w: float = LANE_W * MatchV2.LANES + LANE_GAP * (MatchV2.LANES - 1)
    var jitter := Vector2.ZERO
    if _shake > 0.0:
        jitter = Vector2(sin(_shake * 41.0), cos(_shake * 33.0)) * _shake * 4.0
    return Vector2((size.x - w) * 0.5, (size.y - _rows_height()) * 0.5) + jitter

## side 0 is the player at the bottom, side 1 the rival at the top.
func lane_rect(side: int, index: int) -> Rect2:
    var o := _origin()
    var x: float = o.x + index * (LANE_W + LANE_GAP)
    var y: float = o.y + SANCTUARY_H if side == 1 else o.y + SANCTUARY_H + LANE_H + FRONT_GAP
    return Rect2(x, y, LANE_W, LANE_H)

func sanctuary_rect(side: int) -> Rect2:
    var o := _origin()
    var w: float = LANE_W * MatchV2.LANES + LANE_GAP * (MatchV2.LANES - 1)
    var y: float = o.y if side == 1 else o.y + _rows_height() - SANCTUARY_H
    return Rect2(o.x, y, w, SANCTUARY_H)

func creature_anchor(side: int, index: int) -> Vector2:
    var r := lane_rect(side, index)
    return Vector2(r.get_center().x + 14.0, r.position.y + r.size.y * (0.42 if side == 1 else 0.52))

func place_anchor(side: int, index: int) -> Vector2:
    var r := lane_rect(side, index)
    return Vector2(r.position.x + 42.0, r.position.y + r.size.y * (0.70 if side == 1 else 0.30))

func front_line_y() -> float:
    var o := _origin()
    return o.y + SANCTUARY_H + LANE_H + FRONT_GAP * 0.5

func deck_anchor(side: int) -> Vector2:
    var r := sanctuary_rect(side)
    return Vector2(r.position.x + r.size.x - 26.0, r.get_center().y)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        for side in range(2):
            if sanctuary_rect(side).has_point(event.position):
                sanctuary_clicked.emit(side)
                return
            for i in range(MatchV2.LANES):
                if lane_rect(side, i).has_point(event.position):
                    lane_clicked.emit(side, i)
                    return
    elif event is InputEventMouseMotion:
        var s := -1
        var l := -1
        for side in range(2):
            for i in range(MatchV2.LANES):
                if lane_rect(side, i).has_point(event.position):
                    s = side; l = i
        if s != hover_side or l != hover_lane:
            hover_side = s; hover_lane = l
            lane_hovered.emit(s, l)

# --- choreography API -------------------------------------------------------

func play(kind: String, payload: Dictionary, duration: float) -> void:
    var act := payload.duplicate(true)
    act["kind"] = kind
    act["t"] = 0.0
    act["dur"] = duration
    act["fired"] = {}
    _acts.append(act)

func shake(strength: float) -> void:
    _shake = clampf(_shake + strength, 0.0, 1.6)

func hitstop(seconds: float) -> void:
    _hitstop = maxf(_hitstop, seconds)

func burst(at: Vector2, colour: Color, count: int, style := "spark", power := 1.0) -> void:
    for i in range(count):
        var ang: float = TAU * float(i) / float(count) + float(i) * 0.7
        var speed: float = (40.0 + 60.0 * fmod(float(i) * 0.37, 1.0)) * power
        var vel := Vector2(cos(ang), sin(ang) * 0.75) * speed
        var gravity := 90.0
        if style == "leaf": vel.y -= 40.0 * power; gravity = 30.0
        elif style == "ember": vel.y -= 70.0 * power; gravity = -26.0
        _particles.append({"pos": at, "vel": vel, "gravity": gravity, "t": 0.0,
            "life": 0.45 + 0.4 * fmod(float(i) * 0.53, 1.0), "colour": colour,
            "size": 2.0 + 2.5 * fmod(float(i) * 0.29, 1.0), "style": style})

## Fire a payload beat once, at a normalised point in the act.
func _at(act: Dictionary, key: String, point: float) -> bool:
    var t: float = float(act["t"]) / float(act["dur"])
    if t < point: return false
    var fired: Dictionary = act["fired"]
    if fired.has(key): return false
    fired[key] = true
    return true

func element_colour(element: String) -> Color:
    return ArcanaTheme.color_for_element(element)

func card_colour(card_id: String) -> Color:
    if engine == null: return ArcanaTheme.GOLD
    var els: Array = engine.db.get_card(card_id).get("elements", [])
    return ArcanaTheme.color_for_element(String(els[0])) if not els.is_empty() else ArcanaTheme.GOLD

# --- act beats --------------------------------------------------------------
#
# Each act fires its own sound-and-fury at fixed points on its timeline, so the
# player always sees cause -> travel -> impact -> result.

func _tick_act(act: Dictionary, _delta: float) -> void:
    var kind := String(act["kind"])
    if _at(act, "cue_start", 0.0): cue.emit(kind + "_start", 1.0)
    match kind:
        "land_build":
            var at: Vector2 = lane_rect(int(act["side"]), int(act["lane"])).get_center()
            var colour: Color = element_colour(String(act["element"]))
            if _at(act, "seed", 0.18):
                burst(at, colour, 10, "spark", 0.7)
            if _at(act, "spread", 0.45):
                cue.emit("land_grow", 1.0)
                burst(at, colour, 18, "leaf" if String(act["element"]) == "life" else "ember", 1.1)
                shake(0.25)
            if _at(act, "aether", 0.82):
                burst(_aether_pip_pos(int(act["side"]), int(act["lane"])), ArcanaTheme.AETHER, 8, "spark", 0.5)
        "summon":
            var at2: Vector2 = creature_anchor(int(act["side"]), int(act["lane"]))
            if _at(act, "portal", 0.22):
                burst(at2, Color(act["colour"]), 12, "spark", 0.8)
            if _at(act, "pop", 0.55):
                cue.emit("summon", 1.0)
                burst(at2, Color(act["colour"]), 14,
                    "leaf" if String(act.get("element", "")) == "life" else "ember", 1.0)
                shake(0.3)
        "place_build":
            var at3: Vector2 = place_anchor(int(act["side"]), int(act["lane"]))
            if _at(act, "found", 0.20): burst(at3, Color(act["colour"]), 8, "spark", 0.5)
            if _at(act, "rise", 0.60): shake(0.28)
            if _at(act, "click", 0.86):
                cue.emit("place_done", 1.0)
                burst(at3, Color(act["colour"]), 10, "spark", 0.7)
        "spell":
            if _at(act, "impact", 0.62):
                burst(act["to"], Color(act["colour"]), 16, "spark", 1.1)
                shake(0.45)
                hitstop(0.05)
        "attack":
            if _at(act, "impact", 0.52):
                cue.emit("hit", float(act.get("weight", 0.6)))
                var target: Vector2 = creature_anchor(int(act["target_side"]), int(act["lane"]))
                burst(target, Color(act["colour"]), 16, "spark", 1.2)
                shake(float(act.get("weight", 0.6)))
                hitstop(0.06)
        "heart_attack":
            if _at(act, "impact", 0.58):
                cue.emit("heart_hit", 1.5)
                burst(sanctuary_rect(int(act["target_side"])).get_center(), ArcanaTheme.HEART, 24, "spark", 1.6)
                play("heart_shock", {"side": int(act["target_side"])}, 0.5)
                shake(1.2)
                hitstop(0.09)
        "death":
            if _at(act, "burst", 0.30):
                burst(act["at"], Color(act["colour"]), 14, "spark", 0.8)
        "fusion":
            var at4: Vector2 = creature_anchor(int(act["side"]), int(act["lane"]))
            if _at(act, "lift", 0.12): shake(0.2)
            if _at(act, "core", 0.62):
                burst(at4, ArcanaTheme.GOLD, 22, "spark", 1.2)
                hitstop(0.06)
            if _at(act, "slam", 0.78):
                cue.emit("fusion_slam", 1.6)
                burst(at4, Color(act["colour"]), 26,
                    "leaf" if String(act.get("element", "")) == "life" else "ember", 1.6)
                shake(1.3)
                hitstop(0.10)
        "commander":
            if _at(act, "flourish", 0.35):
                burst(act["from"], ArcanaTheme.GOLD, 18, "spark", 1.0)
            if _at(act, "land", 0.70):
                burst(act["to"], ArcanaTheme.GOLD, 14, "spark", 1.0)
                shake(0.6)

func _aether_pip_pos(side: int, index: int) -> Vector2:
    var r := lane_rect(side, index)
    return Vector2(r.position.x + r.size.x - 20.0, r.position.y + 18.0)

# --- drawing ----------------------------------------------------------------

func _draw() -> void:
    if engine == null or engine.players.is_empty(): return
    var f := ArcanaTheme.font()
    _draw_field(f)
    for side in range(2):
        for i in range(MatchV2.LANES):
            _draw_lane(side, i, f)
    _draw_front_line(f)
    for side in range(2):
        _draw_sanctuary(side, f)
    _draw_acts(f)
    _draw_particles()

func _draw_field(f: Font) -> void:
    var o := _origin()
    var w: float = LANE_W * MatchV2.LANES + LANE_GAP * (MatchV2.LANES - 1)
    var field := Rect2(o.x - 16.0, o.y - 10.0, w + 32.0, _rows_height() + 20.0)
    draw_style_box(ArcanaTheme.panel_box(ArcanaTheme.WORLD_GROUND.darkened(0.25),
        Color(ArcanaTheme.PANEL_EDGE, 0.5), 16, 1), field)

## One lane: the land, the Place standing on it, and the creature living there.
func _draw_lane(side: int, index: int, f: Font) -> void:
    var r := lane_rect(side, index)
    var l: Dictionary = engine.lane(side, index)
    var terrain := String(l["land"])
    var key := "%d,%d" % [side, index]
    var mine := side == 0

    var build := _find_act("land_build", side, index)
    var grow: float = 1.0
    if not build.is_empty(): grow = clampf(float(build["t"]) / float(build["dur"]) / 0.72, 0.0, 1.0)

    if terrain == "":
        # An empty realm slot has to look like an invitation, not a hole.
        draw_style_box(ArcanaTheme.panel_box(Color(0.13, 0.14, 0.12, 0.85),
            Color(ArcanaTheme.PANEL_EDGE, 0.7), 12, 2), r)
        var dash := Color(ArcanaTheme.TEXT_FAINT, 0.5)
        draw_string(f, Vector2(r.get_center().x - 46.0, r.get_center().y + 5.0),
            "EMPTY REALM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dash)
    else:
        var tex: Texture2D = art.terrain(terrain) if art != null else null
        var inner := r.grow(-2.0)
        if grow < 1.0:
            var eased: float = 1.0 - pow(1.0 - grow, 3.0)
            inner = Rect2(r.get_center() - r.size * 0.5 * eased, r.size * eased)
        if tex != null:
            draw_texture_rect(tex, inner, false, Color(1, 1, 1, minf(1.0, grow * 1.5)))
        else:
            draw_rect(inner, Color(ArcanaTheme.color_for_terrain(terrain).darkened(0.5), grow))
        draw_style_box(ArcanaTheme.panel_box(Color(0, 0, 0, 0),
            Color(ArcanaTheme.owner_color(side), 0.55), 12, 2), r)
        # The Aether pip this land pays for.
        var pip := _aether_pip_pos(side, index)
        if grow > 0.8:
            draw_circle(pip, 9.0, Color(ArcanaTheme.BG, 0.7))
            draw_circle(pip, 6.0, ArcanaTheme.AETHER)
            draw_circle(pip - Vector2(2, 2), 2.0, Color(1, 1, 1, 0.4))

    if l["place"] != null: _draw_place(side, index, l["place"], f)
    if l["place"] != null and l["creature"] != null:
        _draw_support_link(side, index, l["place"], f)
    if l["creature"] != null: _draw_creature(side, index, l["creature"], f)

    # Targeting language.
    var hl := String(highlights.get(key, ""))
    if hl != "":
        var glow: Color = ArcanaTheme.LEGAL if hl == "legal" else ArcanaTheme.ATTACK
        var wave: float = 0.5 + 0.5 * sin(_pulse * TAU)
        draw_style_box(ArcanaTheme.panel_box(Color(glow, 0.16 + 0.12 * wave),
            Color(glow, 0.75 + 0.25 * wave), 12, 3), r)
    elif dim_others:
        draw_rect(r, Color(0.02, 0.02, 0.05, 0.58))
    if side == hover_side and index == hover_lane and hl != "":
        draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.TEXT, 0.10),
            Color(ArcanaTheme.TEXT, 0.6), 12, 2), r.grow(-3.0))
    if mine and index == selected_lane:
        draw_style_box(ArcanaTheme.panel_box(Color(1, 1, 1, 0), ArcanaTheme.GOLD, 12, 3), r.grow(-2.0))
    # A pair that can combine wears a linked rune.
    for pair in fusion_pairs:
        if int(pair) == index and side == 0:
            var wave2: float = 0.5 + 0.5 * sin(_pulse * TAU * 1.5)
            draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.GOLD, 0.10 + 0.08 * wave2),
                Color(ArcanaTheme.GOLD, 0.7 + 0.3 * wave2), 12, 3), r)
            var rune := Vector2(r.position.x + 22.0, r.position.y + 22.0)
            draw_circle(rune, 14.0, Color(ArcanaTheme.BG, 0.85))
            draw_arc(rune, 14.0, _pulse * TAU, _pulse * TAU + PI * 1.5, 22, ArcanaTheme.GOLD, 2.5)
            draw_string(f, rune - Vector2(6, -6), "∞", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ArcanaTheme.GOLD)

func _find_act(kind: String, side: int, index: int) -> Dictionary:
    for act in _acts:
        if String(act["kind"]) == kind and int(act.get("side", -1)) == side and int(act.get("lane", -1)) == index:
            return act
    return {}

func _draw_place(side: int, index: int, place: Dictionary, f: Font) -> void:
    var at := place_anchor(side, index)
    var colour := card_colour(String(place["card_id"]))
    var act := _find_act("place_build", side, index)
    var build: float = 1.0
    if not act.is_empty(): build = clampf(float(act["t"]) / float(act["dur"]) / 0.88, 0.0, 1.0)
    # Foundation runes appear before the structure does.
    draw_circle(at + Vector2(0, 16), 26.0, Color(0.14, 0.12, 0.10, 0.55))
    for i in range(5):
        var ang: float = TAU * float(i) / 5.0
        draw_circle(at + Vector2(0, 16) + Vector2(cos(ang), sin(ang) * 0.45) * 24.0, 2.0,
            Color(colour, 0.5 * minf(1.0, build * 3.0)))
    var tex: Texture2D = art.landmark(String(place["card_id"])) if art != null else null
    if tex != null and build > 0.15:
        var src := Vector2(tex.get_width(), tex.get_height())
        var sc: float = min(56.0 / src.x, 56.0 / src.y)
        var drawn := src * sc * Vector2(1.0, clampf((build - 0.15) / 0.85, 0.05, 1.0))
        draw_texture_rect(tex, Rect2(at + Vector2(-drawn.x * 0.5, 16.0 - drawn.y), drawn), false)

## A living thread from the building to the creature it supports, so "what does
## this building actually affect" never has to be guessed.
func _draw_support_link(side: int, index: int, place: Dictionary, f: Font) -> void:
    var a := place_anchor(side, index) + Vector2(0, 4)
    var b := creature_anchor(side, index) + Vector2(0, 10)
    var colour := card_colour(String(place["card_id"]))
    var flow: float = fmod(_pulse * 1.4, 1.0)
    for i in range(7):
        var k: float = float(i) / 6.0
        var at: Vector2 = a.lerp(b, k)
        at.y -= sin(k * PI) * 12.0
        var near: float = absf(fmod(k - flow + 1.0, 1.0))
        var glow: float = 0.22 + 0.55 * pow(1.0 - min(near, 1.0 - near) * 2.0, 3.0)
        draw_circle(at, 2.6, Color(colour, glow))
    # A soft aura under the creature it is helping.
    draw_circle(b + Vector2(0, 14), 24.0, Color(colour, 0.07 + 0.04 * sin(_pulse * TAU)))

func _draw_creature(side: int, index: int, unit: Dictionary, f: Font) -> void:
    var at := creature_anchor(side, index)
    var card_id := String(unit["card_id"])
    var colour := card_colour(card_id)
    var offset := Vector2.ZERO
    var squash := Vector2.ONE
    var flash := 0.0
    var scale := 1.0

    var summon := _find_act("summon", side, index)
    if not summon.is_empty():
        var st: float = clampf(float(summon["t"]) / float(summon["dur"]), 0.0, 1.0)
        if st < 0.45: scale = 0.0
        else:
            var k: float = (st - 0.45) / 0.55
            var eased: float = 1.0 - pow(1.0 - k, 3.0)
            scale = eased
            squash = Vector2(0.7 + 0.3 * eased + 0.22 * sin(eased * PI),
                             0.6 + 0.4 * eased - 0.16 * sin(eased * PI))

    var fuse := _find_act("fusion", side, index)
    if not fuse.is_empty():
        var ft: float = clampf(float(fuse["t"]) / float(fuse["dur"]), 0.0, 1.0)
        if ft < 0.78: scale = 0.0
        else:
            var k2: float = (ft - 0.78) / 0.22
            scale = 1.0 + 0.5 * (1.0 - k2)
            squash = Vector2(1.0 + 0.25 * (1.0 - k2), 1.0 - 0.25 * (1.0 - k2))

    for act in _acts:
        if String(act["kind"]) not in ["attack", "heart_attack"]: continue
        if int(act.get("uid", -1)) != int(unit["uid"]): continue
        var tr := _attack_transform(act)
        offset = tr["offset"]
        squash *= Vector2(tr["squash"])
        flash = maxf(flash, float(tr["glow"]))
    for act in _acts:
        if String(act["kind"]) != "recoil": continue
        if int(act.get("uid", -1)) != int(unit["uid"]): continue
        var rt: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
        offset += Vector2(act["push"]) * sin(rt * PI) * 14.0
        flash = maxf(flash, 1.0 - rt)

    if scale <= 0.001: return
    var box := Rect2(at - Vector2(72, 72) * 0.5 + offset, Vector2(72, 72))
    # Ground shadow keeps the creature standing on its land.
    draw_circle(Vector2(at.x + offset.x, at.y + 26.0), 22.0 * scale, Color(0, 0, 0, 0.22))
    if flash > 0.0:
        draw_circle(box.get_center(), 40.0 * scale, Color(colour, 0.22 * flash))

    var tex: Texture2D = art.creature(card_id) if art != null else null
    if tex != null:
        var src := Vector2(tex.get_width(), tex.get_height())
        var tier: float = clampf(float(src.y) / 96.0, 0.5, 1.0)
        var target_h: float = 54.0 + 34.0 * tier
        var sc: float = target_h / src.y
        var drawn := src * sc * squash * scale
        var pos := Vector2(box.get_center().x - drawn.x * 0.5, at.y + 26.0 - drawn.y + offset.y)
        var tint := Color(1, 1, 1, 1)
        if flash > 0.4: tint = Color(1.0, 0.85 + 0.15 * (1.0 - flash), 0.85, 1.0)
        draw_texture_rect(tex, Rect2(pos, drawn), false, tint)
    else:
        draw_style_box(ArcanaTheme.panel_box(colour.darkened(0.45), colour, 10, 2),
            Rect2(box.position, box.size * squash * scale))

    _draw_unit_stats(at + offset, unit, f, side)

func _draw_unit_stats(at: Vector2, unit: Dictionary, f: Font, side: int) -> void:
    var y: float = at.y + 34.0
    var power := str(int(unit["power"]))
    var health := str(int(unit["health"]))
    _gem(f, Vector2(at.x - 26.0, y), power, Color("#ffd98a"))
    _gem(f, Vector2(at.x + 26.0, y), health,
        ArcanaTheme.HEART if int(unit["health"]) < int(unit["max_health"]) else Color("#ffb3c4"))
    if side == 0 and not bool(unit.get("ready", true)):
        draw_string(f, Vector2(at.x - 30.0, at.y - 34.0), "resting",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT_FAINT)

func _gem(f: Font, centre: Vector2, text: String, colour: Color) -> void:
    draw_circle(centre, 12.0, Color(0.05, 0.05, 0.08, 0.92))
    draw_arc(centre, 12.0, 0, TAU, 20, Color(colour, 0.9), 2.0)
    var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
    draw_string(f, Vector2(centre.x - w * 0.5, centre.y + 5), text,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, colour)

## The line creatures never cross. Attacks travel to it and come home.
func _draw_front_line(f: Font) -> void:
    var o := _origin()
    var w: float = LANE_W * MatchV2.LANES + LANE_GAP * (MatchV2.LANES - 1)
    var y := front_line_y()
    draw_line(Vector2(o.x - 10.0, y), Vector2(o.x + w + 10.0, y), Color(ArcanaTheme.PANEL_EDGE, 0.8), 2.0)
    for i in range(MatchV2.LANES):
        var r := lane_rect(0, i)
        var cx: float = r.get_center().x
        # An open lane shows a path straight through to the rival Heart.
        var open: bool = engine.lane(1, i)["creature"] == null
        var tint: Color = ArcanaTheme.HEART if open else ArcanaTheme.PANEL_EDGE
        var wave: float = 0.5 + 0.5 * sin(_pulse * TAU + float(i) * 0.6)
        draw_circle(Vector2(cx, y), 5.0, Color(tint, 0.35 + 0.35 * wave if open else 0.35))
        if open:
            draw_line(Vector2(cx, y - 12.0), Vector2(cx, y + 12.0), Color(tint, 0.25 + 0.25 * wave), 2.0)

## A home base, not a status bar: the shrine, the Commander standing at it, a
## Heart crystal you can watch drain, and element decoration filling the band.
func _draw_sanctuary(side: int, f: Font) -> void:
    var r := sanctuary_rect(side)
    var p: Dictionary = engine.players[side]
    var element := String(p["element"])
    var colour: Color = ArcanaTheme.owner_color(side)
    var accent: Color = ArcanaTheme.color_for_element(element)
    var breathe: float = 0.5 + 0.5 * sin(_pulse * TAU + side * PI)

    var hurt := 0.0
    for act in _acts:
        if String(act["kind"]) == "heart_shock" and int(act.get("side", -1)) == side:
            hurt = 1.0 - clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
    var offset := Vector2(sin(hurt * 46.0) * 7.0 * hurt, sin(hurt * 31.0) * 3.0 * hurt)
    var base := Rect2(r.position + offset, r.size)

    # Ground of the base, tinted by element and flushed red when the Heart is hit.
    var ground: Color = accent.darkened(0.74).lerp(ArcanaTheme.HEART, hurt * 0.45)
    draw_style_box(ArcanaTheme.panel_box(ground, Color(accent, 0.55 + 0.35 * breathe), 14, 2), base)
    _draw_sanctuary_decor(base, element, accent, breathe)

    # The shrine itself.
    var shrine_w := 0.0
    var tex: Texture2D = art.sanctuary(element) if art != null else null
    if tex != null:
        var src := Vector2(tex.get_width(), tex.get_height())
        var sc: float = (base.size.y - 10.0) / src.y
        var drawn := src * sc
        draw_circle(base.position + Vector2(10 + drawn.x * 0.5, base.size.y - 12.0),
            drawn.x * 0.30, Color(0, 0, 0, 0.24))
        draw_texture_rect(tex, Rect2(base.position + Vector2(10, base.size.y - drawn.y - 4.0), drawn), false)
        shrine_w = drawn.x + 16.0
        # A shrine glows with its own magic.
        draw_circle(base.position + Vector2(10 + drawn.x * 0.5, 5 + drawn.y * 0.5),
            drawn.y * 0.55, Color(accent, 0.06 + 0.05 * breathe))

    # Commander standing at their base.
    var ax: float = base.position.x + maxf(shrine_w, 12.0)
    var avatar: Texture2D = art.commander_board(String(p["commander_id"])) if art != null else null
    if avatar != null:
        var asrc := Vector2(avatar.get_width(), avatar.get_height())
        var asc: float = (base.size.y - 6.0) / asrc.y
        var adr := asrc * asc
        var lift := 0.0
        for act in _acts:
            if String(act["kind"]) == "commander" and int(act.get("side", -1)) == side:
                lift = sin(clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0) * PI) * 14.0
        draw_circle(Vector2(ax + adr.x * 0.5, base.position.y + base.size.y - 12.0),
            adr.x * 0.24, Color(0, 0, 0, 0.24))
        draw_texture_rect(avatar, Rect2(Vector2(ax, base.position.y + 3.0 - lift), adr), false)
        ax += adr.x + 10.0

    var cmd: Dictionary = engine.db.get_commander(String(p["commander_id"]))
    draw_string(f, Vector2(ax, base.position.y + 20.0), String(cmd.get("name", "Commander")),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, colour)

    # Heart crystal: the whole match is about this number, so it is a thing, not a bar.
    var heart := int(p["heart"])
    var frac: float = clampf(float(heart) / float(MatchV2.HEART_START), 0.0, 1.0)
    var hc := Vector2(ax + 26.0, base.position.y + base.size.y * 0.62)
    var pulse: float = 1.0 + 0.06 * sin(_pulse * TAU * (2.4 if frac < 0.35 else 1.2))
    var rad: float = 22.0 * pulse
    for i in range(4):
        var t := float(i) / 4.0
        draw_circle(hc, rad * (1.35 - t * 0.3), Color(ArcanaTheme.HEART, 0.06 + 0.05 * breathe))
    var facets := PackedVector2Array([
        hc + Vector2(0, -rad), hc + Vector2(rad * 0.78, 0),
        hc + Vector2(0, rad), hc + Vector2(-rad * 0.78, 0)])
    draw_colored_polygon(facets, Color(0.10, 0.04, 0.08, 0.95))
    # The crystal fills from the bottom as a readable "how much is left".
    var fill_top: float = hc.y + rad - 2.0 * rad * frac
    var filled := PackedVector2Array()
    for i in range(facets.size()):
        var a: Vector2 = facets[i]
        var b: Vector2 = facets[(i + 1) % facets.size()]
        if a.y >= fill_top: filled.append(a)
        if (a.y < fill_top) != (b.y < fill_top):
            var k: float = (fill_top - a.y) / (b.y - a.y)
            filled.append(a.lerp(b, k))
    if filled.size() >= 3:
        draw_colored_polygon(filled, Color(ArcanaTheme.HEART, 0.9))
    draw_polyline(PackedVector2Array([facets[0], facets[1], facets[2], facets[3], facets[0]]),
        Color(ArcanaTheme.HEART, 0.95), 2.0)
    var hw: float = f.get_string_size(str(heart), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
    draw_string(f, Vector2(hc.x - hw * 0.5, hc.y + 7.0), str(heart),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ArcanaTheme.TEXT)

    # Aether orbs, then the small counts.
    var px: float = hc.x + 46.0
    var py: float = base.position.y + base.size.y * 0.42
    for i in range(int(p["max_aether"])):
        var lit: bool = i < int(p["aether"])
        var at := Vector2(px + i * 17.0, py)
        if lit:
            draw_circle(at, 10.0, Color(ArcanaTheme.AETHER, 0.18))
            draw_circle(at, 6.0, ArcanaTheme.AETHER)
            draw_circle(at - Vector2(2, 2), 2.0, Color(1, 1, 1, 0.5))
        else:
            draw_arc(at, 6.0, 0, TAU, 16, Color(ArcanaTheme.PANEL_EDGE, 0.9), 2.0)
    draw_string(f, Vector2(px, py + 22.0),
        "%d/%d Aether · %d Realm cards · %d in hand" % [int(p["aether"]), int(p["max_aether"]),
            int(p["realm_stack"]), p["hand"].size()],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT_DIM)

    # Deck, so drawing has a visible source.
    var deck := deck_anchor(side)
    for i in range(3):
        draw_style_box(ArcanaTheme.panel_box(ArcanaTheme.PANEL.darkened(0.1 * float(i)),
            Color(colour, 0.55), 4, 1),
            Rect2(deck - Vector2(16, 24) + Vector2(float(i) * 1.5, float(i) * 1.5), Vector2(32, 46)))
    draw_string(f, deck - Vector2(9, -4), str(p["deck"].size()),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.TEXT)

## Element motifs so a base is unmistakably Life or Fire.
func _draw_sanctuary_decor(base: Rect2, element: String, accent: Color, breathe: float) -> void:
    var n := 10
    for i in range(n):
        var fx: float = float(i) / float(n)
        var x: float = base.position.x + 8.0 + fx * (base.size.x - 16.0)
        if element == "life":
            # Vine arcs along the top edge with leaves hanging off them.
            var h: float = 10.0 + 7.0 * sin(fx * 9.0 + _pulse * 1.2)
            draw_arc(Vector2(x, base.position.y), h, PI * 0.15, PI * 0.85, 10,
                Color(accent, 0.32), 2.0)
            draw_circle(Vector2(x + 4.0, base.position.y + h * 0.8), 3.0, Color(accent, 0.45))
            if i % 3 == 0:
                draw_circle(Vector2(x, base.position.y + base.size.y - 6.0), 2.5,
                    Color("#f2c7dd").lerp(accent, 0.3))
        else:
            # Cracks glowing along the floor, with embers drifting up off them.
            var y0: float = base.position.y + base.size.y - 4.0
            var lift: float = 6.0 + 10.0 * fmod(fx * 3.7 + _pulse, 1.0)
            draw_line(Vector2(x, y0), Vector2(x + 6.0, y0 - 9.0), Color(accent, 0.30), 2.0)
            draw_circle(Vector2(x + 3.0, y0 - lift), 2.0,
                Color("#ffb066", 0.55 * (1.0 - lift / 18.0) + 0.15 * breathe))

## Where an attacker travels: out to the front line, never onto rival land.
func _attack_transform(act: Dictionary) -> Dictionary:
    var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
    var dir: float = -1.0 if int(act["side"]) == 0 else 1.0
    var reach: float = float(act.get("reach", 0.6)) * (LANE_H * 0.62 + FRONT_GAP)
    var offset := Vector2.ZERO
    var squash := Vector2.ONE
    var glow := 0.0
    if t < 0.18:
        var k: float = t / 0.18
        offset.y = -dir * 12.0 * k
        squash = Vector2(1.0 + 0.12 * k, 1.0 - 0.12 * k)
    elif t < 0.34:
        var k2: float = (t - 0.18) / 0.16
        offset.y = -dir * 12.0 * (1.0 - k2)
        squash = Vector2(1.0 - 0.08 * k2, 1.0 + 0.16 * k2)
        glow = k2
    elif t < 0.52:
        var k3: float = (t - 0.34) / 0.18
        var eased: float = k3 * k3
        offset.y = dir * reach * eased
        offset.x = sin(k3 * PI) * float(act.get("arc", 0.0)) * 40.0
        squash = Vector2(1.14, 0.90)
        glow = 1.0
    elif t < 0.62:
        offset.y = dir * reach
        squash = Vector2(0.86, 1.16)
        glow = 1.0
    else:
        var k4: float = (t - 0.62) / 0.38
        var eased2: float = 1.0 - pow(1.0 - k4, 3.0)
        offset.y = dir * reach * (1.0 - eased2)
    return {"offset": offset, "squash": squash, "glow": glow}

func _draw_acts(f: Font) -> void:
    for act in _acts:
        var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
        match String(act["kind"]):
            "draw":
                _draw_card_travel(act, t, f)
            "card_flight":
                _draw_card_travel(act, t, f)
            "land_build":
                _draw_land_growth(act, t)
            "spell":
                _draw_spell_travel(act, t)
            "attack", "heart_attack":
                _draw_attack_projectile(act, t)
            "death":
                _draw_death(act, t, f)
            "fusion":
                _draw_fusion(act, t, f)
            "float":
                var rise: float = 30.0 * t
                var col: Color = act["colour"]
                draw_string(f, Vector2(act["at"].x - 18.0, act["at"].y - rise), String(act["text"]),
                    HORIZONTAL_ALIGNMENT_CENTER, 36.0, 20, Color(col, 1.0 - t * t))

func _draw_card_travel(act: Dictionary, t: float, f: Font) -> void:
    if String(act["kind"]) == "draw" and t < 0.16:
        # Deck pulse before the card lifts.
        var deck: Vector2 = act["from"]
        var k: float = t / 0.16
        draw_arc(deck, 26.0 + 22.0 * k, 0, TAU, 24, Color(act["colour"], 0.7 * (1.0 - k)), 3.0)
    var eased: float = 1.0 - pow(1.0 - t, 2.6)
    var at: Vector2 = Vector2(act["from"]).lerp(Vector2(act["to"]), eased)
    at.y -= sin(eased * PI) * 40.0
    var flip: float = clampf((t - 0.35) / 0.3, 0.0, 1.0)
    var w: float = 62.0 * (1.0 - 0.35 * eased) * absf(cos((1.0 - flip) * PI * 0.5))
    var h: float = 84.0 * (1.0 - 0.35 * eased)
    var colour: Color = act["colour"]
    var rect := Rect2(at - Vector2(w, h) * 0.5, Vector2(maxf(w, 3.0), h))
    if flip < 0.5:
        draw_style_box(ArcanaTheme.panel_box(ArcanaTheme.PANEL.darkened(0.2), colour, 6, 2), rect)
    else:
        draw_style_box(ArcanaTheme.panel_box(ArcanaTheme.PANEL.lightened(0.1), colour, 6, 2), rect)
        if w > 30.0:
            draw_string(f, rect.position + Vector2(5, 16),
                ArcanaTheme.fit(String(act.get("label", "")), 10, rect.size.x - 10),
                HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT)
            var role := String(act.get("role", ""))
            if role != "":
                draw_string(f, rect.position + Vector2(5, 30),
                    role.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(act["colour"]))

## Life sends roots and vines outward; Fire cracks and chars the ground.
func _draw_land_growth(act: Dictionary, t: float) -> void:
    var r := lane_rect(int(act["side"]), int(act["lane"]))
    var centre := r.get_center()
    var colour: Color = element_colour(String(act["element"]))
    if t < 0.55:
        var k: float = t / 0.55
        draw_arc(centre, 20.0 + 100.0 * k, 0, TAU, 36, Color(colour, 0.8 * (1.0 - k)), 3.0)
    var spokes: float = clampf((t - 0.15) / 0.5, 0.0, 1.0)
    if spokes > 0.0:
        for i in range(10):
            var ang: float = TAU * float(i) / 10.0 + float(act["lane"])
            var reach: float = spokes * r.size.x * 0.44
            var tip := centre + Vector2(cos(ang), sin(ang) * 0.6) * reach
            if String(act["element"]) == "life":
                draw_line(centre, tip, Color(colour, 0.55 * (1.0 - spokes * 0.5)), 3.0)
                draw_circle(tip, 3.0 * (1.0 - spokes * 0.4), Color("#f2c7dd"))
            else:
                draw_line(centre, tip, Color(colour, 0.5 * (1.0 - spokes * 0.5)), 2.0)
                draw_circle(tip, 2.5, Color("#ffb066"))

func _draw_spell_travel(act: Dictionary, t: float) -> void:
    var colour: Color = act["colour"]
    var a: Vector2 = act["from"]
    var b: Vector2 = act["to"]
    if t < 0.18:
        draw_circle(a, 10.0 + 24.0 * (t / 0.18), Color(colour, 0.35))
        return
    var k: float = clampf((t - 0.18) / 0.44, 0.0, 1.0)
    var at: Vector2 = a.lerp(b, k)
    at.y -= sin(k * PI) * 30.0
    for i in range(5):
        var trail: float = maxf(0.0, k - 0.07 * float(i))
        var tp: Vector2 = a.lerp(b, trail)
        tp.y -= sin(trail * PI) * 30.0
        draw_circle(tp, 8.0 - float(i), Color(colour, 0.5 * (1.0 - float(i) / 5.0)))
    draw_circle(at, 11.0, Color(colour, 0.9))
    draw_circle(at, 5.0, Color(1, 1, 1, 0.8))

func _draw_attack_projectile(act: Dictionary, t: float) -> void:
    var style := String(act.get("style", "lunge"))
    if style not in ["breath", "cast"]: return
    if t < 0.34 or t > 0.62: return
    var k: float = clampf((t - 0.34) / 0.28, 0.0, 1.0)
    var a: Vector2 = creature_anchor(int(act["side"]), int(act["lane"]))
    var b: Vector2 = sanctuary_rect(int(act["target_side"])).get_center() if bool(act.get("heart", false)) \
        else creature_anchor(int(act["target_side"]), int(act["lane"]))
    var at: Vector2 = a.lerp(b, k)
    var colour: Color = act["colour"]
    if style == "breath":
        var width: float = 16.0 + 44.0 * k
        draw_line(a, at, Color(colour, 0.22), width)
        draw_line(a, at, Color(colour, 0.5), width * 0.55)
        draw_line(a, at, Color(colour, 0.9), width * 0.22)
        draw_circle(at, width * 0.4, Color(colour, 0.6))
        draw_circle(at, width * 0.2, Color(1, 1, 1, 0.6))
    else:
        draw_circle(at, 12.0, Color(colour, 0.4))
        draw_circle(at, 6.0, Color(colour, 0.95))

func _draw_death(act: Dictionary, t: float, f: Font) -> void:
    if t < 0.22: return                              # hold the pose first
    var k: float = (t - 0.22) / 0.78
    var at: Vector2 = act["at"]
    var colour: Color = act["colour"]
    for i in range(8):
        var ang: float = TAU * float(i) / 8.0
        var d: float = k * 40.0
        draw_circle(at + Vector2(cos(ang), sin(ang) - 0.6) * d, 4.0 * (1.0 - k), Color(colour, 1.0 - k))
    draw_arc(at, 26.0 * (1.0 + k), 0, TAU, 24, Color(colour, 0.5 * (1.0 - k)), 2.0)

## The signature spectacle: lift, ribbons, orbit, flash, slam.
func _draw_fusion(act: Dictionary, t: float, f: Font) -> void:
    var side := int(act["side"])
    var a: Vector2 = creature_anchor(side, int(act["lane"]))
    var b: Vector2 = creature_anchor(side, int(act["freed_lane"]))
    var target: Vector2 = creature_anchor(side, int(act["lane"]))
    var colour: Color = act["colour"]
    if t < 0.70:
        draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.30 * clampf(t / 0.2, 0.0, 1.0)))
    if t < 0.62:
        var k: float = t / 0.62
        var lift: float = sin(k * PI * 0.5) * 26.0
        var spin: float = k * TAU * 1.4
        var radius: float = (1.0 - k) * a.distance_to(b) * 0.5
        var mid: Vector2 = a.lerp(b, 0.5).lerp(target, k)
        var pa: Vector2 = mid + Vector2(cos(spin), sin(spin) * 0.5) * radius - Vector2(0, lift)
        var pb: Vector2 = mid - Vector2(cos(spin), sin(spin) * 0.5) * radius - Vector2(0, lift)
        for i in range(9):
            var f2: float = float(i) / 9.0
            draw_line(pa.lerp(pb, f2), pa.lerp(pb, f2 + 0.11),
                Color(colour, 0.25 + 0.5 * sin((f2 + t) * PI * 3.0)), 3.0)
        draw_circle(pa, 16.0 * (1.0 - k * 0.5), Color(colour, 0.75))
        draw_circle(pb, 16.0 * (1.0 - k * 0.5), Color(colour, 0.75))
        draw_circle(mid, 10.0 + 46.0 * k * k, Color(1, 1, 1, 0.22 + 0.6 * k * k))
    elif t < 0.78:
        var k2: float = (t - 0.62) / 0.16
        draw_circle(target, 60.0 * (1.0 - k2) + 20.0, Color(1, 1, 1, 0.85 * (1.0 - k2)))
        draw_arc(target, 40.0 + 120.0 * k2, 0, TAU, 40, Color(colour, 1.0 - k2), 5.0)
    else:
        var k3: float = (t - 0.78) / 0.22
        draw_arc(target, 30.0 + 90.0 * k3, 0, TAU, 32, Color(ArcanaTheme.GOLD, 0.8 * (1.0 - k3)), 4.0)
        var name := String(act.get("name", ""))
        var w: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
        draw_string(f, Vector2(target.x - w * 0.5, target.y - 60.0 - 10.0 * k3), name,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ArcanaTheme.GOLD, 1.0 - k3 * k3))

func _draw_particles() -> void:
    for pt in _particles:
        var t: float = float(pt["t"]) / float(pt["life"])
        var c: Color = pt["colour"]
        var a: float = 1.0 - t * t
        var at: Vector2 = pt["pos"]
        var sz: float = float(pt["size"])
        match String(pt["style"]):
            "leaf":
                var w: float = sz * (0.5 + 0.5 * cos(t * 9.0))
                draw_rect(Rect2(at - Vector2(w, sz) * 0.5, Vector2(w * 2.0, sz)), Color(c, a))
            "ember":
                draw_circle(at, sz * (1.0 - t * 0.5), Color(c, a))
                draw_circle(at, sz * 1.9 * (1.0 - t), Color(c, a * 0.2))
            _:
                draw_circle(at, sz * (1.0 - t * 0.6), Color(c, a))
