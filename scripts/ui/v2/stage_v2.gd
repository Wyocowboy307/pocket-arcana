class_name StageV2
extends Control
## The V2 battlefield: two miniature magical realms facing each other.
##
## The four lanes are still exactly the V2 rules underneath, but nothing here is
## drawn as a panel. Landscapes are irregular plots of ground that grow when a
## Realm card lands on them and merge with their neighbours when they share an
## element. Creatures stand at the front edge of their own land facing across a
## clash space in the middle, where fights actually happen. Sanctuaries are built
## places behind each realm rather than status bars.
##
## Every animation reads a committed event. None of it decides an outcome.

signal lane_clicked(side: int, index: int)
signal sanctuary_clicked(side: int)
signal lane_hovered(side: int, index: int)
## Fires at the beat a sound belongs on; wiring audio means connecting this.
signal cue(name: String, strength: float)

## One continuous battlefield.
##
## There are no slabs, rims or side faces any more, and no dark divider strip.
## The ground is a single lit surface: Cinder at the top, worn neutral where the
## two sides meet, Grove at the bottom. Rows read from a trodden path, a light
## pool and the cards' own shadows, never from a box.
const SANCT_H := 100.0                # sanctuary band, top and bottom
const ROW_H := 144.0                  # a combat row
const MID_H := 64.0                   # neutral ground where the rows meet
const LANE_W := 210.0
const CARD_W := 112.0                 # a played creature card
const CARD_H := 128.0
const PLACE_W := 86.0                 # a Place, beside the creature it supports
const PLACE_H := 104.0
const CARD_NUDGE := 18.0              # creature shifts right so the Place is readable

var engine: MatchV2
var art: ArtRegistry
var highlights: Dictionary = {}      # "side,lane" -> "legal" | "attack"
var dim_others := false
var hover_side := -1
var hover_lane := -1
var selected_lane := -1
var ghost_card := ""
var fusion_pairs: Array = []

var _acts: Array = []
var _particles: Array = []
var _decals: Array = []              # lasting impact marks in the clash zone
var _effects: Array = []             # playing frame strips from the VFX library
var _pulse := 0.0
var _shake := 0.0
var _hitstop := 0.0

func _ready() -> void:
	# Ground patches and framing scenery deliberately overhang the play area;
	# without this they spill over the hand row below.
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	set_process(true)

func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, 1.0)
	if _hitstop > 0.0:
		_hitstop = maxf(0.0, _hitstop - delta)
		queue_redraw()
		return
	if _shake > 0.0: _shake = maxf(0.0, _shake - delta * 3.4)
	var live: Array = []
	for act in _acts:
		act["t"] = float(act["t"]) + delta
		_tick_act(act)
		if float(act["t"]) < float(act["dur"]): live.append(act)
	_acts = live
	_tick_effects(delta)
	var alive: Array = []
	for pt in _particles:
		pt["t"] = float(pt["t"]) + delta
		if float(pt["t"]) >= float(pt["life"]): continue
		pt["pos"] = Vector2(pt["pos"]) + Vector2(pt["vel"]) * delta
		pt["vel"] = Vector2(pt["vel"]) + Vector2(0, float(pt["gravity"])) * delta
		alive.append(pt)
	_particles = alive
	queue_redraw()

func _tick_effects(delta: float) -> void:
	var keep: Array = []
	for e in _effects:
		e["t"] = float(e["t"]) + delta
		if float(e["t"]) < float(e["dur"]): keep.append(e)
	_effects = keep

func _draw_effects() -> void:
	if art == null: return
	for e in _effects:
		var name := String(e["name"])
		var tex: Texture2D = art.fx(name)
		if tex == null: continue
		var t: float = clampf(float(e["t"]) / float(e["dur"]), 0.0, 1.0)
		var src: Rect2 = art.fx_frame(name, t)
		if src.size.x <= 0.0: continue
		var sc: float = float(e["scale"])
		var dest := Rect2((Vector2(e["at"]) - src.size * sc * 0.5).round(), (src.size * sc).round())
		draw_texture_rect_region(tex, dest, src, Color.WHITE, false)

func busy() -> bool:
	return not _acts.is_empty()

# --- geometry ---------------------------------------------------------------

func _field_width() -> float:
	return LANE_W * MatchV2.LANES

func _origin() -> Vector2:
	var total_h: float = _board_height()
	var jitter := Vector2.ZERO
	if _shake > 0.0:
		jitter = Vector2(sin(_shake * 41.0), cos(_shake * 33.0)) * _shake * 4.0
	return Vector2((size.x - _field_width()) * 0.5, (size.y - total_h) * 0.5) + jitter

func _board_height() -> float:
	return SANCT_H * 2.0 + ROW_H * 2.0 + MID_H

## The click/hover region a lane owns. Wider than the card so the board is
## forgiving to aim at; the card is what the player actually sees.
func lane_rect(side: int, index: int) -> Rect2:
	var o := _origin()
	var x: float = o.x + index * LANE_W
	var y: float = o.y + SANCT_H if side == 1 else o.y + SANCT_H + ROW_H + MID_H
	return Rect2(x, y, LANE_W, ROW_H)

## Where a played creature card actually lies.
func card_rect(side: int, index: int) -> Rect2:
	var r := lane_rect(side, index)
	var c := r.get_center()
	# Sits right of the lane's centre so a Place can stand beside it rather than
	# behind it. A half-hidden support card is a card the player cannot read.
	return Rect2(Vector2(c.x - CARD_W * 0.5 + CARD_NUDGE, c.y - CARD_H * 0.5).round(),
		Vector2(CARD_W, CARD_H))

## A Place tucks behind its lane, toward that player's own sanctuary, so both
## cards stay readable and the support relationship is visible.
func place_rect(side: int, index: int) -> Rect2:
	var lane := lane_rect(side, index)
	var cr := card_rect(side, index)
	# Sits in the lane's own margin and a little toward that player's home, so it
	# reads as supporting the creature in front of it without hiding either card.
	var toward_home: float = 14.0 if side == 0 else -14.0
	return Rect2(Vector2(lane.position.x + 2.0,
		cr.get_center().y - PLACE_H * 0.5 + toward_home).round(), Vector2(PLACE_W, PLACE_H))

func sanctuary_rect(side: int) -> Rect2:
	var o := _origin()
	var y: float = o.y if side == 1 else o.y + SANCT_H + ROW_H * 2.0 + MID_H
	return Rect2(o.x, y, _field_width(), SANCT_H)

func creature_anchor(side: int, index: int) -> Vector2:
	return card_rect(side, index).get_center()

func place_anchor(side: int, index: int) -> Vector2:
	return place_rect(side, index).get_center()

## Where the two sides actually meet.
func clash_centre(index: int) -> Vector2:
	var o := _origin()
	return Vector2(lane_rect(0, index).get_center().x, o.y + SANCT_H + ROW_H + MID_H * 0.5)

func front_line_y() -> float:
	return clash_centre(0).y

func deck_anchor(side: int) -> Vector2:
	var r := sanctuary_rect(side)
	return Vector2(r.position.x + r.size.x - 64.0, r.get_center().y)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for side in range(2):
			for i in range(MatchV2.LANES):
				if lane_rect(side, i).has_point(event.position):
					lane_clicked.emit(side, i)
					return
			if sanctuary_rect(side).has_point(event.position):
				sanctuary_clicked.emit(side)
				return
	elif event is InputEventMouseMotion:
		var s := -1
		var l := -1
		for side in range(2):
			for i in range(MatchV2.LANES):
				if lane_rect(side, i).has_point(event.position): s = side; l = i
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

## Play one effect from the shared library at a point on the board.
##
## Effects are art, never rules: this only ever draws. Everything here is
## triggered from a beat that the simulation has already committed.
func effect(name: String, at: Vector2, duration := 0.45, scale := 1.0, spin := 0.0) -> void:
	if art == null or art.fx(name) == null: return
	_effects.append({"name": name, "at": at, "t": 0.0, "dur": maxf(0.05, duration),
		"scale": scale, "spin": spin})

## A mark the battlefield keeps after something lands there.
func scar(at: Vector2, kind: String) -> void:
	if _decals.size() > 14: _decals.pop_front()
	_decals.append({"at": at, "kind": kind, "v": _decals.size() % 3})

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

func _at(act: Dictionary, key: String, point: float) -> bool:
	if float(act["t"]) / float(act["dur"]) < point: return false
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

func _find_act(kind: String, side: int, index: int) -> Dictionary:
	for act in _acts:
		if String(act["kind"]) == kind and int(act.get("side", -1)) == side and int(act.get("lane", -1)) == index:
			return act
	return {}

func _vhash(x: int, y: int) -> float:
	var h: int = (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0

# --- act beats --------------------------------------------------------------

func _tick_act(act: Dictionary) -> void:
	var kind := String(act["kind"])
	match kind:
		"land_build":
			var at: Vector2 = lane_rect(int(act["side"]), int(act["lane"])).get_center()
			var colour: Color = element_colour(String(act["element"]))
			var life: bool = String(act["element"]) == "life"
			if _at(act, "seed", 0.14): burst(at, colour, 10, "spark", 0.7)
			if _at(act, "spread", 0.42):
				cue.emit("land_grow", 1.0)
				burst(at, colour, 20, "leaf" if life else "ember", 1.2)
				shake(0.3)
			if _at(act, "settle", 0.80):
				burst(at, colour, 10, "leaf" if life else "ember", 0.7)
		"summon":
			var at2: Vector2 = creature_anchor(int(act["side"]), int(act["lane"]))
			var summon_el := String(act.get("element", "life"))
			if _at(act, "portal", 0.22):
				effect("summon_portal_%s" % summon_el,
					at2 + Vector2(0.0, CARD_H * 0.42), 0.55, 2.0)
				burst(at2, Color(act["colour"]), 12, "spark", 0.8)
			if _at(act, "pop", 0.55):
				effect("leaf_burst" if summon_el == "life" else "ember_burst", at2, 0.42, 1.7)
				cue.emit("summon", 1.0)
				burst(at2, Color(act["colour"]), 16,
					"leaf" if String(act.get("element", "")) == "life" else "ember", 1.0)
				shake(0.32)
		"place_build":
			var at3: Vector2 = place_anchor(int(act["side"]), int(act["lane"]))
			if _at(act, "found", 0.18):
				effect("rune_%s" % String(act.get("element", "life")), at3, 0.5, 1.2)
				burst(at3, Color(act["colour"]), 8, "spark", 0.5)
			if _at(act, "rise", 0.58): shake(0.26)
			if _at(act, "click", 0.86):
				cue.emit("place_done", 1.0)
				burst(at3, Color(act["colour"]), 12, "spark", 0.7)
		"spell":
			var spell_el := String(act.get("element", "life"))
			if _at(act, "cast", 0.10):
				var cast_from: Vector2 = act["from"] if act.has("from") else _spell_target(act)
				effect("rune_%s" % spell_el, cast_from, 0.55, 1.6)
			if _at(act, "impact", 0.62):
				var target := _spell_target(act)
				effect("hit_flash", target, 0.34, 1.5)
				effect("leaf_burst" if spell_el == "life" else "ember_burst", target, 0.5, 2.0)
				effect("flower_pop" if spell_el == "life" else "smoke_puff", target, 0.55, 1.6)
				scar(target, "growth" if spell_el == "life" else "scorch")
				cue.emit("spell_hit", 1.0)
				burst(_spell_target(act), Color(act["colour"]), 16, "spark", 1.1)
				shake(0.45); hitstop(0.05)
		"attack":
			var hit_at := clash_centre(int(act["lane"]))
			var atk_el := String(act.get("element", "life"))
			# A dragon's attack must not look like a deer's: heavy attackers get the
			# cone and a scar, light ones a quick spark.
			var weight: float = float(act.get("weight", 0.6))
			if _at(act, "wind", 0.30) and weight > 0.9:
				effect("flame_cone" if atk_el == "fire" else "vine_growth", hit_at, 0.40, 1.5)
			if _at(act, "impact", 0.50):
				effect("hit_flash", hit_at, 0.30, 1.0 + weight * 0.7)
				effect("sparks_%s" % ("fire" if atk_el == "fire" else "life"), hit_at, 0.36, 1.2)
				if weight > 0.9:
					effect("ember_burst" if atk_el == "fire" else "leaf_burst", hit_at, 0.5, 1.8)
					scar(hit_at, "scorch" if atk_el == "fire" else "growth")
				cue.emit("hit", float(act.get("weight", 0.6)))
				burst(clash_centre(int(act["lane"])), Color(act["colour"]), 18, "spark", 1.3)
				shake(float(act.get("weight", 0.6))); hitstop(0.06)
		"heart_attack":
			if _at(act, "impact", 0.58):
				effect("heart_strike", sanctuary_rect(int(act["target_side"])).get_center(), 0.6, 2.2)
				effect("hit_flash", sanctuary_rect(int(act["target_side"])).get_center(), 0.36, 2.0)
				cue.emit("heart_hit", 1.5)
				burst(sanctuary_rect(int(act["target_side"])).get_center(), ArcanaTheme.HEART, 26, "spark", 1.7)
				play("heart_shock", {"side": int(act["target_side"])}, 0.55)
				shake(1.25); hitstop(0.09)
		"death":
			if _at(act, "burst", 0.28):
				var death_at: Vector2 = act["at"]
				effect("smoke_puff", death_at, 0.55, 1.6)
				burst(act["at"], Color(act["colour"]), 14, "spark", 0.8)
		"fusion":
			var at4: Vector2 = creature_anchor(int(act["side"]), int(act["lane"]))
			if _at(act, "lift", 0.12): shake(0.2)
			if _at(act, "core", 0.62):
				effect("fusion_core", at4, 0.62, 2.4)
				burst(at4, ArcanaTheme.GOLD, 22, "spark", 1.2); hitstop(0.06)
			if _at(act, "slam", 0.78):
				effect("hit_flash", at4, 0.4, 2.6)
				cue.emit("fusion_slam", 1.6)
				burst(at4, Color(act["colour"]), 28,
					"leaf" if String(act.get("element", "")) == "life" else "ember", 1.7)
				shake(1.3); hitstop(0.10)
		"commander":
			if _at(act, "flourish", 0.35): burst(act["from"], ArcanaTheme.GOLD, 18, "spark", 1.0)
			if _at(act, "land", 0.70):
				burst(act["to"], ArcanaTheme.GOLD, 14, "spark", 1.0)
				shake(0.6)

## Where a spell actually lands.
##
## main_v2 sends the resolved point as "to"; the older target_side/lane form is
## kept only as a fallback. Without the "to" branch every spell impact burst on
## side 0's Sanctuary regardless of what the spell hit, because the real payload
## carries no "lane" key at all.
func _spell_target(act: Dictionary) -> Vector2:
	if act.has("to"):
		var to: Vector2 = act["to"]
		return to
	if int(act.get("lane", -1)) >= 0:
		return creature_anchor(int(act.get("target_side", 0)), int(act["lane"]))
	return sanctuary_rect(int(act.get("target_side", 0))).get_center()

# --- world drawing ----------------------------------------------------------

func _draw() -> void:
	if engine == null or engine.players.is_empty(): return
	var f := ArcanaTheme.font()

	_draw_ground()                  # one continuous surface, top to bottom
	_draw_row_zones()               # trodden paths: clarity without boxes
	for side in range(2):
		_draw_realm_dressing(side)  # props growing out of each half
	for side in range(2):
		_draw_sanctuary(side, f)
	# Cards last, so nothing paints over the thing the player is reading.
	for side in range(2):
		for i in range(MatchV2.LANES):
			var l: Dictionary = engine.lane(side, i)
			if l["place"] != null: _draw_place(side, i, l["place"])
	for side in range(2):
		for i in range(MatchV2.LANES):
			var l2: Dictionary = engine.lane(side, i)
			if l2["creature"] != null: _draw_creature(side, i, l2["creature"], f)
	_draw_targeting(f)
	_draw_acts(f)
	_draw_effects()
	_draw_particles()
	_draw_atmosphere()              # light pool, vignette, framing scenery

# --- the ground -------------------------------------------------------------

## The whole battlefield as one surface. Cinder fills the rival's half, Grove
## ours, worn neutral through the middle, joined by interlocking blend strips
## rather than a hard line or a fade.
func _draw_ground() -> void:
	var mid := front_line_y()
	var neutral_top: float = mid - MID_H * 0.5 - 8.0
	var neutral_bottom: float = mid + MID_H * 0.5 + 8.0

	if art == null or not art.has_land_kit("grove"):
		draw_rect(Rect2(Vector2.ZERO, size), ArcanaTheme.BG)
		return

	var rival_element := _element_ground(1)
	var own_element := _element_ground(0)
	_tile_field(art.land_field(rival_element), Rect2(0.0, 0.0, size.x, neutral_top))
	_tile_field(art.clash("field"), Rect2(0.0, neutral_top, size.x, neutral_bottom - neutral_top))
	_tile_field(art.land_field(own_element), Rect2(0.0, neutral_bottom, size.x, size.y - neutral_bottom))

	# Break the field's repeat before anything else lands on the ground.
	_scatter_patches(rival_element, Rect2(0.0, 0.0, size.x, neutral_top), 11)
	_scatter_patches("neutral", Rect2(0.0, neutral_top, size.x, neutral_bottom - neutral_top), 5)
	_scatter_patches(own_element, Rect2(0.0, neutral_bottom, size.x, size.y - neutral_bottom), 11)

	_draw_blend_strip(rival_element, "neutral", neutral_top)
	_draw_blend_strip("neutral", own_element, neutral_bottom)

	# Arcane cracks and loose stone gather along the line where they meet.
	for i in range(7):
		var crack: Texture2D = art.clash("crack", i % 3)
		if crack == null: continue
		var cs := Vector2(crack.get_width(), crack.get_height())
		draw_texture_rect(crack, Rect2(Vector2(
			_vhash(i, 811) * (size.x - cs.x),
			neutral_top + 10.0 + _vhash(i, 823) * (neutral_bottom - neutral_top - cs.y - 20.0)
		).round(), cs), false)
	for i in range(16):
		var rub: Texture2D = art.clash("rubble", i % 3)
		if rub == null: continue
		var rs := Vector2(rub.get_width(), rub.get_height())
		draw_texture_rect(rub, Rect2(Vector2(
			_vhash(i, 857) * (size.x - rs.x),
			neutral_top + 4.0 + _vhash(i, 863) * (neutral_bottom - neutral_top - rs.y - 8.0)
		).round(), rs), false)
	for mark_entry in _decals:
		var tex2: Texture2D = art.clash("decal_%s" % String(mark_entry["kind"]), int(mark_entry["v"]))
		if tex2 == null: continue
		var ds := Vector2(tex2.get_width(), tex2.get_height())
		draw_texture_rect(tex2, Rect2((Vector2(mark_entry["at"]) - ds * 0.5).round(), ds), false)

## Which ground a player's half of the board is made of. Built Realms tint the
## whole half rather than only their own plot, because the board is one place.
## Large patches at hashed positions. Their spacing shares no period with the
## tile, so the eye stops finding the grid.
func _scatter_patches(element: String, region: Rect2, count: int) -> void:
	if region.size.y <= 8.0: return
	var seed_base := 500 + sum_chars(element)
	for i in range(count):
		var tex: Texture2D = art.ground_patch(element, seed_base + i)
		if tex == null: return
		var ts := Vector2(tex.get_width(), tex.get_height())
		var at := Vector2(
			region.position.x - ts.x * 0.3 + _vhash(seed_base + i, 1201) * (region.size.x + ts.x * 0.6),
			region.position.y - ts.y * 0.35 + _vhash(seed_base + i, 1213) * (region.size.y + ts.y * 0.7))
		draw_texture_rect(tex, Rect2(at.round(), ts), false)

func sum_chars(text: String) -> int:
	var total := 0
	for i in range(text.length()): total += text.unicode_at(i)
	return total

func _element_ground(side: int) -> String:
	var terrain := String(engine.players[side]["terrain"])
	var built := 0
	var ash := 0
	for i in range(MatchV2.LANES):
		var land_id := String(engine.lane(side, i)["land"])
		if land_id != "": built += 1
		if land_id == "ashbloom": ash += 1
	if ash > built / 2 and ash > 0: return "ashbloom"
	if built == 0: return "neutral"
	return terrain

func _draw_blend_strip(top: String, bottom: String, at_y: float) -> void:
	var tex: Texture2D = art.ground_blend(top, bottom)
	if tex == null: return
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var x := 0.0
	while x < size.x:
		var seg: float = minf(w, size.x - x)
		draw_texture_rect_region(tex, Rect2(Vector2(x, at_y - h * 0.5).round(), Vector2(seg, h)),
			Rect2(0, 0, seg, h), Color.WHITE, false)
		x += seg

## A trodden path along each combat row. This is the whole answer to "clear
## rows without ugly boxes": the ground is worn where things stand, so the row
## reads as a zone in the world instead of a slot graphic.
func _draw_row_zones() -> void:
	if art == null: return
	for side in range(2):
		var path: Texture2D = art.ground("row_path:%s" % _element_ground(side))
		if path == null: path = art.ground("row_path:neutral")
		if path == null: continue
		var pw := float(path.get_width())
		var ph := float(path.get_height())
		var r := lane_rect(side, 0)
		var band := Rect2(_origin().x - 26.0, r.get_center().y - ph * 0.5,
			_field_width() + 52.0, ph)
		var x := band.position.x
		while x < band.position.x + band.size.x:
			var seg: float = minf(pw, band.position.x + band.size.x - x)
			draw_texture_rect_region(path, Rect2(Vector2(x, band.position.y).round(), Vector2(seg, ph)),
				Rect2(0, 0, seg, ph), Color.WHITE, false)
			x += seg
		# A lane that is highlighted lifts out of the path, still without a box.
		for i in range(MatchV2.LANES):
			var key := "%d,%d" % [side, i]
			if not highlights.has(key): continue
			var mark: Texture2D = art.clash("lane_mark", i)
			if mark == null: continue
			var ms := Vector2(mark.get_width(), mark.get_height()) * 1.6
			var tint: Color = ArcanaTheme.HEART if String(highlights[key]) == "attack" \
				else ArcanaTheme.color_for_element(String(engine.players[side]["element"]))
			var pulse: float = 0.35 + 0.25 * sin(_pulse * TAU)
			draw_texture_rect(mark, Rect2((lane_rect(side, i).get_center() - ms * 0.5).round(), ms),
				false, Color(tint, pulse))

## Props growing out of each half of the battlefield: the biome dressing that
## says which element owns this ground. Kept off the rows so cards stay clean.
func _draw_realm_dressing(side: int) -> void:
	if art == null: return
	var element_id := _element_ground(side)
	var life := element_id == "grove" or element_id == "ashbloom"
	if element_id == "neutral": return
	var element := "grove" if life else "cinder"
	if art.prop_kinds(element).is_empty(): return
	var mix: Array = GROVE_PROP_MIX if life else CINDER_PROP_MIX
	var row := lane_rect(side, 0)
	# Two dressing bands per half: behind the row, and out past the lanes.
	var bands: Array = [
		Rect2(0.0, row.position.y - 46.0, size.x, 44.0),
		Rect2(0.0, row.position.y + row.size.y + 2.0, size.x, 44.0),
	]
	var placed: Array = []
	for b in range(bands.size()):
		var band: Rect2 = bands[b]
		if band.position.y < 4.0 or band.position.y + band.size.y > size.y - 4.0: continue
		for n in range(18):
			var seed_value := side * 733 + b * 131 + n
			var u := _vhash(seed_value, 3)
			var at := Vector2(band.position.x + u * band.size.x,
				band.position.y + _vhash(seed_value, 11) * band.size.y)
			# Keep the middle of the board — where the cards are — clear.
			if absf(at.y - front_line_y()) < MID_H * 0.5 + 6.0: continue
			placed.append({"at": at, "seed": seed_value})
	placed.sort_custom(func(a, b2): return float(a["at"].y) < float(b2["at"].y))
	for entry in placed:
		var at: Vector2 = entry["at"]
		var seed_value: int = int(entry["seed"])
		var pick: int = int(_vhash(seed_value, 29) * float(mix.size())) % mix.size()
		var tex: Texture2D = art.prop(element, String(mix[pick]), seed_value)
		if tex == null: continue
		var w := float(tex.get_width())
		var h := float(tex.get_height())
		draw_rect(Rect2(at.x - w * 0.30, at.y - 2.0, w * 0.60, 3.0), Color(0.05, 0.05, 0.04, 0.30))
		draw_texture_rect(tex, Rect2(Vector2(at.x - w * 0.5, at.y - h).round(), Vector2(w, h)), false)

const GROVE_PROP_MIX := ["grass", "grass", "flower", "flower", "mushroom", "mushroom",
	"stone", "root", "glowplant", "detail", "vine", "tree"]
const CINDER_PROP_MIX := ["crack", "crack", "embers", "embers", "rock", "rock",
	"scorched", "scorched", "debris", "vent", "brazier", "burnt_tree"]

## Tile a wrapping texture across a rect with continuous UVs, so neighbouring
## regions on the same row line up instead of each restarting the pattern.
func _tile_field(tex: Texture2D, r: Rect2) -> void:
	if tex == null: return
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

# --- atmosphere -------------------------------------------------------------

## Depth, drawn last: a warm pool over the middle of the board, dark framing
## scenery at the screen edges, and a vignette that pushes the corners back.
func _draw_atmosphere() -> void:
	if art == null: return
	var pool: Texture2D = art.ground("light_pool")
	if pool != null:
		var pw: float = size.x * 1.5
		var phh: float = size.y * 1.7
		draw_texture_rect(pool, Rect2(Vector2(size.x * 0.5 - pw * 0.5, front_line_y() - phh * 0.5),
			Vector2(pw, phh)), false)
		draw_texture_rect(pool, Rect2(Vector2(size.x * 0.5 - pw * 0.35, front_line_y() - phh * 0.32),
			Vector2(pw * 0.7, phh * 0.64)), false)

	for entry in _framing():
		var tex: Texture2D = art.ground("fg:%s:%d" % [String(entry["kind"]), int(entry["v"])])
		if tex == null: continue
		var w := float(tex.get_width()) * float(entry["scale"])
		var h := float(tex.get_height()) * float(entry["scale"])
		var at: Vector2 = entry["at"]
		draw_texture_rect(tex, Rect2(Vector2(at.x, at.y).round(), Vector2(w, h)),
			false, Color(1, 1, 1, float(entry["alpha"])))

	_draw_vignette()

## Corner scenery. Nearly silhouette, and only at the edges, so it encloses the
## board without ever covering a card.
func _framing() -> Array:
	return [
		{"kind": "branch", "v": 0, "at": Vector2(-30.0, -18.0), "scale": 1.25, "alpha": 0.92},
		{"kind": "branch", "v": 1, "at": Vector2(size.x - 200.0, -26.0), "scale": 1.2, "alpha": 0.9},
		{"kind": "roots", "v": 0, "at": Vector2(-24.0, size.y - 74.0), "scale": 1.2, "alpha": 0.95},
		{"kind": "roots", "v": 1, "at": Vector2(size.x - 150.0, size.y - 78.0), "scale": 1.2, "alpha": 0.95},
		{"kind": "rock", "v": 0, "at": Vector2(-40.0, front_line_y() - 110.0), "scale": 1.0, "alpha": 0.85},
		{"kind": "rock", "v": 1, "at": Vector2(size.x - 84.0, front_line_y() - 30.0), "scale": 1.0, "alpha": 0.85},
	]

## Gradient quads rather than a texture: a vignette is lighting, and drawing it
## as four polygons costs nothing and always matches the window size.
func _draw_vignette() -> void:
	# Enough to push the corners back, not enough to grey out the battlefield.
	var dark := Color(0.03, 0.02, 0.045, 0.52)
	var clear := Color(0.03, 0.02, 0.045, 0.0)
	var depth: float = size.y * 0.20
	var side_depth: float = size.x * 0.15
	var quads := [
		[PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0),
			Vector2(size.x, depth), Vector2(0, depth)]), [dark, dark, clear, clear]],
		[PackedVector2Array([Vector2(0, size.y - depth), Vector2(size.x, size.y - depth),
			Vector2(size.x, size.y), Vector2(0, size.y)]), [clear, clear, dark, dark]],
		[PackedVector2Array([Vector2(0, 0), Vector2(side_depth, 0),
			Vector2(side_depth, size.y), Vector2(0, size.y)]), [dark, clear, clear, dark]],
		[PackedVector2Array([Vector2(size.x - side_depth, 0), Vector2(size.x, 0),
			Vector2(size.x, size.y), Vector2(size.x - side_depth, size.y)]),
			[clear, dark, dark, clear]],
	]
	for q in quads:
		var cols := PackedColorArray(q[1])
		draw_polygon(q[0], cols)

## A built home place behind the realm, not a status bar.
## A player's home, standing on the battlefield itself.
##
## No platform, no raised deck, no panel: the Sanctuary is a building that sits
## on the same ground everything else does, and the Heart is a physical thing
## attached to it. That is the whole difference between a home and a status bar.
func _draw_sanctuary(side: int, f: Font) -> void:
	var r := sanctuary_rect(side)
	var p: Dictionary = engine.players[side]
	var element := String(p["element"])
	var accent: Color = ArcanaTheme.color_for_element(element)
	var breathe: float = 0.5 + 0.5 * sin(_pulse * TAU + side * PI)

	var hurt := 0.0
	for act in _acts:
		if String(act["kind"]) == "heart_shock" and int(act.get("side", -1)) == side:
			hurt = 1.0 - clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
	var nudge := Vector2(sin(hurt * 46.0) * 7.0 * hurt, sin(hurt * 31.0) * 3.0 * hurt)

	# The ground in front of a home is worn from everything walking out of it.
	var path: Texture2D = art.ground("row_path:%s" % _element_ground(side)) if art != null else null
	if path != null:
		var pw := float(path.get_width())
		var ph := float(path.get_height())
		var y0: float = r.get_center().y - ph * 0.5
		var x := r.position.x - 20.0
		while x < r.position.x + r.size.x + 20.0:
			var seg: float = minf(pw, r.position.x + r.size.x + 20.0 - x)
			draw_texture_rect_region(path, Rect2(Vector2(x, y0).round(), Vector2(seg, ph)),
				Rect2(0, 0, seg, ph), Color.WHITE, false)
			x += seg

	var base_y: float = r.position.y + r.size.y - 4.0 if side == 0 else r.position.y + r.size.y - 6.0
	var centre_x: float = r.get_center().x + nudge.x

	# The building itself.
	var tex: Texture2D = art.sanctuary(element) if art != null else null
	if tex != null:
		var src := Vector2(tex.get_width(), tex.get_height())
		# Ours can grow up behind our own row; the rival's is at the very top of
		# the screen and would simply be cut off, so it stays inside its band.
		var sc: float = (r.size.y + (84.0 if side == 0 else 22.0)) / src.y
		var drawn := src * sc
		draw_circle(Vector2(centre_x, base_y - 2.0), drawn.x * 0.34, Color(0.03, 0.02, 0.04, 0.34))
		draw_circle(Vector2(centre_x, base_y - drawn.y * 0.45), drawn.y * 0.52,
			Color(accent, 0.06 + 0.05 * breathe))
		draw_texture_rect(tex, Rect2(Vector2(centre_x - drawn.x * 0.5,
			base_y - drawn.y + nudge.y).round(), drawn), false,
			Color(1, 1, 1, 1).lerp(Color(1.0, 0.6, 0.65, 1.0), hurt * 0.5))

	# Commander standing outside their own home.
	var avatar: Texture2D = art.commander_board(String(p["commander_id"])) if art != null else null
	var ax: float = centre_x - 150.0
	if avatar != null:
		var asrc := Vector2(avatar.get_width(), avatar.get_height())
		var asc: float = (r.size.y - 4.0) / asrc.y
		var adr := asrc * asc
		var lift := 0.0
		for act2 in _acts:
			if String(act2["kind"]) == "commander" and int(act2.get("side", -1)) == side:
				lift = sin(clampf(float(act2["t"]) / float(act2["dur"]), 0.0, 1.0) * PI) * 14.0
		draw_circle(Vector2(ax, base_y - 2.0), adr.x * 0.30, Color(0.03, 0.02, 0.04, 0.30))
		draw_texture_rect(avatar, Rect2(Vector2(ax - adr.x * 0.5, base_y - adr.y - lift).round(), adr), false)

	_draw_heart(side, Vector2(centre_x + 152.0, r.get_center().y - 6.0), p, f, breathe, hurt)
	_draw_aether(p, Vector2(centre_x + 152.0, r.get_center().y + 32.0))
	_draw_deck(side, p, element, f)

## The Heart: a physical crystal attached to the home, filling and emptying.
func _draw_heart(side: int, at: Vector2, p: Dictionary, f: Font,
		breathe: float, hurt: float) -> void:
	var heart := int(p["heart"])
	var frac: float = clampf(float(heart) / float(MatchV2.HEART_START), 0.0, 1.0)
	var rad: float = 28.0 * (1.0 + 0.05 * sin(_pulse * TAU * (2.4 if frac < 0.35 else 1.2)))
	if hurt > 0.0:
		draw_circle(at, rad * (2.2 + hurt), Color(ArcanaTheme.HEART, 0.22 * hurt))
	draw_circle(at, rad * 1.6, Color(ArcanaTheme.HEART, 0.08 + 0.06 * breathe))
	var facets := PackedVector2Array([at + Vector2(0, -rad), at + Vector2(rad * 0.76, 0),
		at + Vector2(0, rad), at + Vector2(-rad * 0.76, 0)])
	draw_colored_polygon(facets, Color(0.08, 0.03, 0.06, 0.96))
	var fill_top: float = at.y + rad - 2.0 * rad * frac
	var filled := PackedVector2Array()
	for i in range(facets.size()):
		var a: Vector2 = facets[i]
		var b: Vector2 = facets[(i + 1) % facets.size()]
		if a.y >= fill_top: filled.append(a)
		if (a.y < fill_top) != (b.y < fill_top):
			filled.append(a.lerp(b, (fill_top - a.y) / (b.y - a.y)))
	if filled.size() >= 3: draw_colored_polygon(filled, Color(ArcanaTheme.HEART, 0.92))
	draw_polyline(PackedVector2Array([facets[0], facets[1], facets[2], facets[3], facets[0]]),
		Color(0.06, 0.04, 0.05, 0.95), 3.0)
	draw_polyline(PackedVector2Array([facets[0], facets[1], facets[2], facets[3], facets[0]]),
		Color(ArcanaTheme.HEART, 0.95), 1.5)
	var hw: float = f.get_string_size(str(heart), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(f, Vector2(at.x - hw * 0.5, at.y + 7.0), str(heart),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ArcanaTheme.TEXT)

func _draw_aether(p: Dictionary, at: Vector2) -> void:
	var total := int(p["max_aether"])
	var px: float = at.x - float(total - 1) * 7.5
	for i in range(total):
		var o := Vector2(px + i * 15.0, at.y)
		if i < int(p["aether"]):
			draw_circle(o, 8.0, Color(ArcanaTheme.AETHER, 0.22))
			draw_circle(o, 5.0, ArcanaTheme.AETHER)
			draw_circle(o - Vector2(1.4, 1.4), 2.0, Color(1, 1, 1, 0.7))
		else:
			draw_arc(o, 5.0, 0, TAU, 14, Color(ArcanaTheme.PANEL_EDGE, 0.9), 2.0)

## A real stack of cards, so drawing has a visible source.
func _draw_deck(side: int, p: Dictionary, element: String, f: Font) -> void:
	var deck := deck_anchor(side)
	var back: Texture2D = art.frame("card_back:%s" % element) if art != null else null
	var w := 42.0
	var h := 50.0
	var count: int = p["deck"].size()
	var layers: int = clampi(int(count / 6) + 1, 1, 4)
	for i in range(layers):
		var off := Vector2(float(i) * 2.0, float(-i) * 2.0)
		var dest := Rect2((deck - Vector2(w, h) * 0.5 + off).round(), Vector2(w, h))
		if back != null: draw_texture_rect(back, dest, false)
		else: draw_style_box(ArcanaTheme.panel_box(ArcanaTheme.PANEL,
			ArcanaTheme.color_for_element(element), 4, 1), dest)
	var label := str(count)
	var lw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(f, Vector2(deck.x - lw * 0.5, deck.y + h * 0.5 + 14.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT_DIM)

## A Place: a built thing, laid on the board as its own smaller card behind the
## lane it supports.
func _draw_place(side: int, index: int, place: Dictionary) -> void:
	var r := place_rect(side, index)
	var card_id := String(place["card_id"])
	var element := String(engine.players[side]["element"])
	var act := _find_act("place_build", side, index)
	var build := 1.0
	if not act.is_empty(): build = clampf(float(act["t"]) / float(act["dur"]) / 0.88, 0.0, 1.0)
	if build <= 0.02: return

	# Construction: the card rises out of its own foundation.
	var eased: float = 1.0 - pow(1.0 - build, 3.0)
	var shown := Rect2(r.position + Vector2(0.0, r.size.y * (1.0 - eased)),
		Vector2(r.size.x, r.size.y * eased))
	_card_shadow(Rect2(r.position, r.size), 0.55 * eased)

	var frame: Texture2D = art.frame("place_frame:%s" % element) if art != null else null
	if frame == null:
		draw_style_box(ArcanaTheme.panel_box(card_colour(card_id).darkened(0.55),
			card_colour(card_id), 8, 2), shown)
		return
	var fw := float(frame.get_width())
	var fh := float(frame.get_height())
	var src := Rect2(0.0, fh * (1.0 - eased), fw, fh * eased)
	draw_texture_rect_region(frame, shown, src, Color.WHITE, false)

	# The building itself, inside the card's window, going up as the card lands:
	# footing -> lower storey -> most of it -> finished.
	var stage_index: int = 3
	if eased < 0.30: stage_index = 0
	elif eased < 0.58: stage_index = 1
	elif eased < 0.86: stage_index = 2
	var tex: Texture2D = art.landmark_stage(card_id, stage_index) if art != null else null
	if tex != null and eased > 0.08:
		var ts := Vector2(tex.get_width(), tex.get_height())
		var win := Rect2(r.position + Vector2(4.0, 4.0), Vector2(r.size.x - 8.0, r.size.y - 24.0))
		var sc: float = minf(win.size.x / ts.x, win.size.y / ts.y)
		var drawn := ts * sc
		var dest := Rect2((win.get_center() - drawn * 0.5).round(), drawn)
		draw_texture_rect(tex, dest, false)

	if eased >= 0.99:
		# A finished Place shows what it is doing to its lane.
		var glow: Texture2D = art.landmark_passive(card_id) if art != null else null
		if glow != null:
			var gs := Vector2(glow.get_width(), glow.get_height())
			var breathe: float = 0.45 + 0.30 * sin(_pulse * TAU + float(index) * 0.8)
			draw_texture_rect(glow, Rect2((Vector2(r.get_center().x,
				r.position.y + r.size.y + 4.0) - gs * 0.5).round(), gs), false,
				Color(1, 1, 1, breathe))
		var f2 := ArcanaTheme.font()
		var label := ArcanaTheme.fit(String(place.get("name", "")), 9, r.size.x - 30.0)
		if label != "":
			var tw: float = f2.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(f2, Vector2(r.get_center().x - tw * 0.5 + 6.0,
				r.position.y + r.size.y - 6.0),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ArcanaTheme.TEXT_DIM)
		_gem_art("presence", Vector2(r.position.x - 5.0, r.position.y + r.size.y - 20.0),
			str(int(place.get("presence", 1))), ArcanaTheme.font())

## A played creature: a card lying on the battlefield.
##
## The card is the unit. Every animation the choreography drives — summon,
## fusion, attack lunge, defend, recoil — moves and squashes this card, so the
## thing the player reads is the thing that acts.
func _draw_creature(side: int, index: int, unit: Dictionary, f: Font) -> void:
	var base := card_rect(side, index)
	var home := base.get_center()
	var card_id := String(unit["card_id"])
	var colour := card_colour(card_id)
	var element := String(engine.players[side]["element"])
	var offset := Vector2.ZERO
	var squash := Vector2.ONE
	var glow := 0.0
	var scale := 1.0

	var summon := _find_act("summon", side, index)
	if not summon.is_empty():
		var st: float = clampf(float(summon["t"]) / float(summon["dur"]), 0.0, 1.0)
		if st < 0.42: scale = 0.0
		else:
			var k: float = (st - 0.42) / 0.58
			var e1: float = 1.0 - pow(1.0 - k, 3.0)
			scale = e1
			squash = Vector2(0.7 + 0.3 * e1 + 0.24 * sin(e1 * PI),
							 0.6 + 0.4 * e1 - 0.18 * sin(e1 * PI))

	var fuse := _find_act("fusion", side, index)
	if not fuse.is_empty():
		var ft: float = clampf(float(fuse["t"]) / float(fuse["dur"]), 0.0, 1.0)
		if ft < 0.78: scale = 0.0
		else:
			var k2: float = (ft - 0.78) / 0.22
			scale = 1.0 + 0.55 * (1.0 - k2)
			squash = Vector2(1.0 + 0.28 * (1.0 - k2), 1.0 - 0.28 * (1.0 - k2))

	for act in _acts:
		if String(act["kind"]) in ["attack", "heart_attack"] and int(act.get("uid", -1)) == int(unit["uid"]):
			var tr := _attack_transform(act, home)
			offset = tr["offset"]; squash *= Vector2(tr["squash"]); glow = maxf(glow, float(tr["glow"]))
		elif String(act["kind"]) == "defend" and int(act.get("uid", -1)) == int(unit["uid"]):
			offset = _defend_offset(act, side, index)
			glow = maxf(glow, 0.25)
		elif String(act["kind"]) == "recoil" and int(act.get("uid", -1)) == int(unit["uid"]):
			var rt: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
			offset += Vector2(act["push"]) * sin(rt * PI) * 16.0
			glow = maxf(glow, 1.0 - rt)

	if scale <= 0.001: return
	var hovered: bool = side == hover_side and index == hover_lane
	if hovered: offset += Vector2(0.0, -6.0)

	var drawn_size := base.size * squash * scale
	var r := Rect2((home + offset - drawn_size * 0.5).round(), drawn_size.round())

	_card_shadow(r, 0.7 * scale)
	if glow > 0.0:
		draw_rect(r.grow(6.0 + 6.0 * glow), Color(colour, 0.22 * glow))

	var plate: Texture2D = art.frame("board_plate:%s" % element) if art != null else null
	var frame: Texture2D = art.frame("board_frame:%s" % element) if art != null else null
	var ready: bool = bool(unit.get("ready", true))
	var tint := Color(1, 1, 1, 1)
	if side == 0 and not ready: tint = Color(0.66, 0.66, 0.72, 1.0)
	if glow > 0.4: tint = Color(1.0, 0.86 + 0.14 * (1.0 - glow), 0.86, 1.0)
	if dim_others and not highlights.has("%d,%d" % [side, index]):
		tint = Color(tint.r * 0.55, tint.g * 0.55, tint.b * 0.6, 1.0)

	if plate == null:
		draw_style_box(ArcanaTheme.panel_box(colour.darkened(0.5), colour, 10, 2), r)
	else:
		draw_texture_rect(plate, r, false, tint)

	# The creature, inside the card's window.
	var tex: Texture2D = art.creature(card_id) if art != null else null
	if tex != null:
		var ts := Vector2(tex.get_width(), tex.get_height())
		var win := Rect2(r.position + Vector2(4.0, 4.0) * scale,
			Vector2(r.size.x - 8.0 * scale, r.size.y - 26.0 * scale))
		var fit: float = minf(win.size.x / ts.x, win.size.y / ts.y)
		# Big creatures fill more of the window than small ones: a Sproutling and
		# a Garden Dragon must not end up the same size on the board.
		var tier: float = clampf(ts.y / 96.0, 0.62, 1.0)
		var drawn := ts * fit * tier
		draw_texture_rect(tex, Rect2((win.get_center() - drawn * 0.5).round(), drawn.round()), false, tint)

	if frame != null:
		draw_texture_rect(frame, r, false, tint)

	# Name in the card's own strip: readable without hovering, which is the point
	# of giving the creature a card in the first place.
	var name := String(unit["name"])
	var strip_y: float = r.position.y + r.size.y - 7.0
	# The badges hang off both bottom corners, so the name only owns the middle.
	var name_room: float = r.size.x - 44.0
	var nw: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	if nw > name_room:
		while name.length() > 3 and f.get_string_size(name + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x > name_room:
			name = name.substr(0, name.length() - 1)
		name += "…"
		nw = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(f, Vector2(r.get_center().x - nw * 0.5, strip_y), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT)

	if scale > 0.85:
		_gem_art("power", Vector2(r.position.x - 5.0, r.position.y + r.size.y - 20.0),
			str(int(unit["power"])), f)
		_gem_art("health", Vector2(r.position.x + r.size.x - 19.0, r.position.y + r.size.y - 20.0),
			str(int(unit["health"])), f,
			int(unit["health"]) < int(unit["max_health"]))
		if side == 0 and not ready:
			draw_arc(Vector2(r.get_center().x, r.position.y + 12.0), 7.0, 0, TAU, 14,
				Color(ArcanaTheme.TEXT_FAINT, 0.75), 1.5)

## A grounded shadow under a card, so it lies on the battlefield rather than
## floating above it.
func _card_shadow(r: Rect2, strength: float) -> void:
	var tex: Texture2D = art.ground("card_shadow") if art != null else null
	var w: float = r.size.x * 1.15
	var h: float = 34.0
	var at := Vector2(r.get_center().x - w * 0.5, r.position.y + r.size.y - h * 0.55)
	if tex == null:
		draw_rect(Rect2(at, Vector2(w, h)), Color(0.03, 0.02, 0.04, 0.35 * strength))
		return
	draw_texture_rect(tex, Rect2(at.round(), Vector2(w, h)), false,
		Color(1, 1, 1, clampf(strength, 0.0, 1.0)))

## A live number in an authored socket.
func _gem_art(kind: String, at: Vector2, text: String, f: Font, alert := false) -> void:
	var tex: Texture2D = art.frame("gem:%s" % kind) if art != null else null
	var size_v := 24.0
	if tex != null:
		size_v = float(tex.get_width())
		draw_texture_rect(tex, Rect2(at.round(), Vector2(size_v, size_v)), false,
			Color(1.0, 0.8, 0.8, 1.0) if alert else Color.WHITE)
	else:
		draw_circle(at + Vector2(size_v * 0.5, size_v * 0.5), size_v * 0.45, Color(0.1, 0.09, 0.12))
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(f, Vector2(at.x + size_v * 0.5 - tw * 0.5, at.y + size_v * 0.5 + 4.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.TEXT)

func _gem(f: Font, centre: Vector2, text: String, colour: Color) -> void:
	draw_circle(centre, 11.0, Color(0.05, 0.05, 0.08, 0.92))
	draw_arc(centre, 11.0, 0, TAU, 18, Color(colour, 0.9), 2.0)
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(f, Vector2(centre.x - w * 0.5, centre.y + 5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colour)

## The attacker leaves its land, meets in the clash space, and returns.
func _attack_transform(act: Dictionary, home: Vector2) -> Dictionary:
	var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
	var meet := clash_centre(int(act["lane"]))
	if bool(act.get("heart", false)):
		meet = clash_centre(int(act["lane"]))       # still only as far as the middle
	var reach: float = float(act.get("reach", 0.6))
	var travel := (meet - home) * reach
	var offset := Vector2.ZERO
	var squash := Vector2.ONE
	var glow := 0.0
	if t < 0.18:
		var k: float = t / 0.18
		offset = -travel.normalized() * 12.0 * k
		squash = Vector2(1.0 + 0.12 * k, 1.0 - 0.12 * k)
	elif t < 0.32:
		var k2: float = (t - 0.18) / 0.14
		offset = -travel.normalized() * 12.0 * (1.0 - k2)
		squash = Vector2(1.0 - 0.08 * k2, 1.0 + 0.16 * k2)
		glow = k2
	elif t < 0.50:
		var k3: float = (t - 0.32) / 0.18
		var eased: float = k3 * k3
		offset = travel * eased
		offset.x += sin(k3 * PI) * float(act.get("arc", 0.0)) * 46.0
		squash = Vector2(1.14, 0.90)
		glow = 1.0
	elif t < 0.60:
		offset = travel
		squash = Vector2(0.86, 1.16)
		glow = 1.0
	else:
		var k4: float = (t - 0.60) / 0.40
		offset = travel * (1.0 - (1.0 - pow(1.0 - k4, 3.0)))
	return {"offset": offset, "squash": squash, "glow": glow}

## The defender steps in to meet the blow rather than waiting to be hit.
func _defend_offset(act: Dictionary, side: int, index: int) -> Vector2:
	var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
	var home := creature_anchor(side, index)
	var meet := clash_centre(index)
	var step := (meet - home) * 0.28
	return step * sin(clampf(t / 0.6, 0.0, 1.0) * PI)

func _draw_targeting(f: Font) -> void:
	var wave: float = 0.5 + 0.5 * sin(_pulse * TAU)
	if dim_others:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.52))
	for key in highlights:
		var parts: PackedStringArray = String(key).split(",")
		var side := int(parts[0])
		var index := int(parts[1])
		var r2 := lane_rect(side, index)
		var glow: Color = ArcanaTheme.LEGAL if String(highlights[key]) == "legal" else ArcanaTheme.ATTACK
		# A pool of light on the ground rather than an outlined slot.
		var c := r2.get_center()
		# Lift the dim back off the legal ground, then pool light on it.
		for ring in range(7):
			var t := float(ring) / 7.0
			draw_circle(c, r2.size.x * (0.46 - t * 0.06),
				Color(glow, (0.055 + 0.045 * wave) * (1.0 - t * 0.6)))
		draw_arc(c, r2.size.x * 0.42, 0, TAU, 44, Color(glow, 0.6 + 0.3 * wave), 2.5)
	if selected_lane >= 0:
		var sr := lane_rect(0, selected_lane)
		draw_arc(sr.get_center(), sr.size.x * 0.42, 0, TAU, 40, Color(ArcanaTheme.GOLD, 0.95), 3.0)
	for pair in fusion_pairs:
		var r3 := lane_rect(0, int(pair))
		var c := Vector2(r3.get_center().x, r3.position.y + 16.0)
		draw_circle(c, 13.0, Color(ArcanaTheme.BG, 0.85))
		draw_arc(c, 13.0, _pulse * TAU, _pulse * TAU + PI * 1.5, 20, ArcanaTheme.GOLD, 2.5)
		draw_string(f, c - Vector2(6, -6), "∞", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ArcanaTheme.GOLD)

# --- effect drawing ---------------------------------------------------------

func _draw_acts(f: Font) -> void:
	for act in _acts:
		var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
		match String(act["kind"]):
			"draw", "card_flight": _draw_card_travel(act, t, f)
			"land_build": _draw_land_growth(act, t)
			"spell": _draw_spell_travel(act, t)
			"attack", "heart_attack": _draw_attack_projectile(act, t)
			"death": _draw_death(act, t)
			"fusion": _draw_fusion(act, t, f)
			"float":
				var col: Color = act["colour"]
				draw_string(f, Vector2(act["at"].x - 20.0, act["at"].y - 32.0 * t),
					String(act["text"]), HORIZONTAL_ALIGNMENT_CENTER, 40.0, 20,
					Color(col, 1.0 - t * t))

func _draw_card_travel(act: Dictionary, t: float, f: Font) -> void:
	if String(act["kind"]) == "draw" and t < 0.16:
		var deck: Vector2 = act["from"]
		var k: float = t / 0.16
		draw_arc(deck, 26.0 + 22.0 * k, 0, TAU, 24, Color(act["colour"], 0.7 * (1.0 - k)), 3.0)
	var eased: float = 1.0 - pow(1.0 - t, 2.6)
	var at: Vector2 = Vector2(act["from"]).lerp(Vector2(act["to"]), eased)
	at.y -= sin(eased * PI) * 40.0
	var flip: float = clampf((t - 0.35) / 0.3, 0.0, 1.0)
	var w: float = 60.0 * (1.0 - 0.4 * eased) * absf(cos((1.0 - flip) * PI * 0.5))
	var h: float = 82.0 * (1.0 - 0.4 * eased)
	var colour: Color = act["colour"]
	var rect := Rect2(at - Vector2(w, h) * 0.5, Vector2(maxf(w, 3.0), h))
	draw_style_box(ArcanaTheme.panel_box(
		ArcanaTheme.PANEL.darkened(0.2) if flip < 0.5 else ArcanaTheme.PANEL.lightened(0.1),
		colour, 6, 2), rect)
	if flip >= 0.5 and w > 30.0:
		draw_string(f, rect.position + Vector2(5, 16),
			ArcanaTheme.fit(String(act.get("label", "")), 10, rect.size.x - 10),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT)
		var role := String(act.get("role", ""))
		if role != "":
			draw_string(f, rect.position + Vector2(5, 30), role.to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, colour)

## Life sends roots and blossoms through the ground; Fire chars and cracks it.
func _draw_land_growth(act: Dictionary, t: float) -> void:
	var r := lane_rect(int(act["side"]), int(act["lane"]))
	var centre := r.get_center()
	var life: bool = String(act["element"]) == "life"
	var colour: Color = element_colour(String(act["element"]))
	if t < 0.55:
		var k: float = t / 0.55
		draw_arc(centre, 18.0 + 110.0 * k, 0, TAU, 40, Color(colour, 0.75 * (1.0 - k)), 3.0)
	var spokes: float = clampf((t - 0.10) / 0.55, 0.0, 1.0)
	if spokes <= 0.0: return
	for i in range(14):
		var ang: float = TAU * float(i) / 14.0 + float(act["lane"]) * 0.6
		var reach: float = spokes * r.size.x * 0.46
		var dir := Vector2(cos(ang), sin(ang) * 0.58)
		var tip := centre + dir * reach
		if life:
			# Vines crawl outward, curling, with leaves opening behind them.
			var prev := centre
			for seg in range(4):
				var fseg: float = float(seg + 1) / 4.0
				var wobble: float = sin(fseg * 6.0 + float(i)) * 7.0 * spokes
				var p: Vector2 = centre + dir * reach * fseg + Vector2(-dir.y, dir.x) * wobble
				draw_line(prev, p, Color(colour, 0.7 * (1.0 - spokes * 0.35)), 3.0 - fseg)
				prev = p
			draw_circle(prev, 3.5 * (1.0 - spokes * 0.3), Color("#f2c7dd"))
		else:
			draw_line(centre, tip, Color("#ff8a3d", 0.55 * (1.0 - spokes * 0.4)), 2.5)
			draw_circle(tip, 3.0, Color("#ffb066"))
			draw_circle(tip - dir * 12.0, 2.0, Color(0.22, 0.19, 0.18, 0.7))

func _draw_spell_travel(act: Dictionary, t: float) -> void:
	var colour: Color = act["colour"]
	var a: Vector2 = sanctuary_rect(int(act["side"])).get_center()
	var b: Vector2 = _spell_target(act)
	if t < 0.18:
		draw_circle(a, 10.0 + 26.0 * (t / 0.18), Color(colour, 0.35))
		return
	var k: float = clampf((t - 0.18) / 0.44, 0.0, 1.0)
	for i in range(6):
		var trail: float = maxf(0.0, k - 0.06 * float(i))
		var tp: Vector2 = a.lerp(b, trail)
		tp.y -= sin(trail * PI) * 34.0
		draw_circle(tp, 9.0 - float(i), Color(colour, 0.5 * (1.0 - float(i) / 6.0)))
	var at: Vector2 = a.lerp(b, k)
	at.y -= sin(k * PI) * 34.0
	draw_circle(at, 11.0, Color(colour, 0.9))
	draw_circle(at, 5.0, Color(1, 1, 1, 0.8))

## Ranged attacks physically cross the clash space.
func _draw_attack_projectile(act: Dictionary, t: float) -> void:
	var style := String(act.get("style", "lunge"))
	if style not in ["breath", "cast"]: return
	if t < 0.30 or t > 0.62: return
	var k: float = clampf((t - 0.30) / 0.32, 0.0, 1.0)
	var a := creature_anchor(int(act["side"]), int(act["lane"]))
	var b: Vector2 = sanctuary_rect(int(act["target_side"])).get_center() if bool(act.get("heart", false)) \
		else creature_anchor(int(act["target_side"]), int(act["lane"]))
	var at: Vector2 = a.lerp(b, k)
	var colour: Color = act["colour"]
	if style == "breath":
		var width: float = 18.0 + 46.0 * k
		draw_line(a, at, Color(colour, 0.20), width)
		draw_line(a, at, Color(colour, 0.48), width * 0.55)
		draw_line(a, at, Color(colour, 0.9), width * 0.22)
		draw_circle(at, width * 0.40, Color(colour, 0.6))
		draw_circle(at, width * 0.20, Color(1, 1, 1, 0.6))
		for i in range(7):
			var f2: float = _vhash(i, 3)
			var along: float = clampf(k - f2 * 0.32, 0.0, 1.0)
			var p2: Vector2 = a.lerp(b, along)
			draw_circle(p2 + Vector2((f2 - 0.5) * width, 0.0), 2.5 + 2.0 * f2,
				Color(colour, 0.7 * (1.0 - along)))
	else:
		draw_circle(at, 13.0, Color(colour, 0.4))
		draw_circle(at, 6.0, Color(colour, 0.95))

func _draw_death(act: Dictionary, t: float) -> void:
	if t < 0.22: return
	var k: float = (t - 0.22) / 0.78
	var at: Vector2 = act["at"]
	var colour: Color = act["colour"]
	for i in range(9):
		var ang: float = TAU * float(i) / 9.0
		draw_circle(at + Vector2(cos(ang), sin(ang) - 0.7) * k * 44.0, 4.0 * (1.0 - k),
			Color(colour, 1.0 - k))
	draw_arc(at, 26.0 * (1.0 + k), 0, TAU, 24, Color(colour, 0.5 * (1.0 - k)), 2.0)

func _draw_fusion(act: Dictionary, t: float, f: Font) -> void:
	var side := int(act["side"])
	var a := creature_anchor(side, int(act["lane"]))
	var b := creature_anchor(side, int(act["freed_lane"]))
	var target := creature_anchor(side, int(act["lane"]))
	var colour: Color = act["colour"]
	if t < 0.70:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.32 * clampf(t / 0.2, 0.0, 1.0)))
	if t < 0.62:
		var k: float = t / 0.62
		var lift: float = sin(k * PI * 0.5) * 28.0
		var spin: float = k * TAU * 1.4
		var radius: float = (1.0 - k) * a.distance_to(b) * 0.5
		var mid: Vector2 = a.lerp(b, 0.5).lerp(target, k)
		var pa: Vector2 = mid + Vector2(cos(spin), sin(spin) * 0.5) * radius - Vector2(0, lift)
		var pb: Vector2 = mid - Vector2(cos(spin), sin(spin) * 0.5) * radius - Vector2(0, lift)
		for i in range(10):
			var f2: float = float(i) / 10.0
			draw_line(pa.lerp(pb, f2), pa.lerp(pb, f2 + 0.10),
				Color(colour, 0.25 + 0.5 * sin((f2 + t) * PI * 3.0)), 3.0)
		draw_circle(pa, 16.0 * (1.0 - k * 0.5), Color(colour, 0.75))
		draw_circle(pb, 16.0 * (1.0 - k * 0.5), Color(colour, 0.75))
		draw_circle(mid, 10.0 + 48.0 * k * k, Color(1, 1, 1, 0.22 + 0.6 * k * k))
	elif t < 0.78:
		var k2: float = (t - 0.62) / 0.16
		draw_circle(target, 62.0 * (1.0 - k2) + 20.0, Color(1, 1, 1, 0.85 * (1.0 - k2)))
		draw_arc(target, 40.0 + 120.0 * k2, 0, TAU, 40, Color(colour, 1.0 - k2), 5.0)
	else:
		var k3: float = (t - 0.78) / 0.22
		draw_arc(target, 30.0 + 90.0 * k3, 0, TAU, 32, Color(ArcanaTheme.GOLD, 0.8 * (1.0 - k3)), 4.0)
		var name := String(act.get("name", ""))
		var w: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f, Vector2(target.x - w * 0.5, target.y - 64.0 - 10.0 * k3), name,
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
