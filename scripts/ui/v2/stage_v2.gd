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

## A card-first battlefield.
##
## The card *is* the permanent piece. Creatures live inside their card and only
## come out to attack, so the board reads as a card game at rest and as a living
## world in motion.
##
## Composition follows from that: the two card rows take almost the whole
## screen, the clash between them is a deliberate seam rather than a region, and
## the Sanctuaries and Commanders moved out to side rails where they frame the
## battlefield instead of competing with it for space.
const RAIL_W := 150.0                 # left/right rails: homes, Hearts, decks
const EDGE_PAD := 8.0
const ROW_H := 232.0                  # a combat row — nearly all of the height
const CLASH_H := 68.0                 # a seam where they meet, not a strip
const CARD_W := 168.0                 # a played creature card, readable at rest
const CARD_H := 224.0
const PLACE_W := 104.0                # a Place, supporting from the lane's edge
const PLACE_H := 138.0
const CARD_NUDGE := 26.0              # creature shifts right so the Place is readable

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
var _emergent: Array = []            # creatures currently out of their card frame
var _motion: Dictionary = {}         # card_id -> motion style name
var _motion_styles: Dictionary = {}  # style name -> tuning
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
	_load_motion()

## How each creature leaves its card to attack. Presentation only — motion style
## never affects damage, legality or outcomes, which is why it lives here in the
## view and not in the simulation.
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
		var spin: float = float(e.get("spin", 0.0))
		if absf(spin) > 0.001:
			# draw_texture_rect cannot rotate, so put the rotation in the canvas
			# transform and draw the effect around its own origin.
			draw_set_transform(Vector2(e["at"]), spin, Vector2.ONE)
			draw_texture_rect_region(tex, Rect2(-src.size * sc * 0.5, src.size * sc),
				src, Color.WHITE, false)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			var dest := Rect2((Vector2(e["at"]) - src.size * sc * 0.5).round(), (src.size * sc).round())
			draw_texture_rect_region(tex, dest, src, Color.WHITE, false)

func busy() -> bool:
	return not _acts.is_empty()

# --- geometry ---------------------------------------------------------------

## The play area: everything between the two rails.
func _field_width() -> float:
	return maxf(320.0, size.x - RAIL_W * 2.0)

func lane_width() -> float:
	return _field_width() / float(MatchV2.LANES)

func _origin() -> Vector2:
	var jitter := Vector2.ZERO
	if _shake > 0.0:
		jitter = Vector2(sin(_shake * 41.0), cos(_shake * 33.0)) * _shake * 4.0
	return Vector2(RAIL_W, (size.y - _board_height()) * 0.5) + jitter

func _board_height() -> float:
	return ROW_H * 2.0 + CLASH_H

## The rail down one side of the screen. `left` holds the homes, `right` the
## Hearts, Aether and decks.
func rail_rect(left: bool) -> Rect2:
	return Rect2(0.0 if left else size.x - RAIL_W, 0.0, RAIL_W, size.y)

## A player's half of a rail: theirs at the bottom, the rival's at the top.
func rail_slot(left: bool, side: int) -> Rect2:
	var r := rail_rect(left)
	var h: float = r.size.y * 0.5 - EDGE_PAD
	return Rect2(r.position.x + EDGE_PAD, EDGE_PAD if side == 1 else r.size.y * 0.5,
		r.size.x - EDGE_PAD * 2.0, h)

## The click/hover region a lane owns. Wider than the card so the board is
## forgiving to aim at; the card is what the player actually sees.
func lane_rect(side: int, index: int) -> Rect2:
	var o := _origin()
	var lw := lane_width()
	var x: float = o.x + index * lw
	var y: float = o.y if side == 1 else o.y + ROW_H + CLASH_H
	return Rect2(x, y, lw, ROW_H)

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

## The home now lives on the left rail, framing the board rather than sitting
## across the top or bottom of it.
func sanctuary_rect(side: int) -> Rect2:
	return rail_slot(true, side)

func creature_anchor(side: int, index: int) -> Vector2:
	return card_rect(side, index).get_center()

func place_anchor(side: int, index: int) -> Vector2:
	return place_rect(side, index).get_center()

## Where the two sides actually meet.
func clash_centre(index: int) -> Vector2:
	var o := _origin()
	return Vector2(lane_rect(0, index).get_center().x, o.y + ROW_H + CLASH_H * 0.5)

func front_line_y() -> float:
	return clash_centre(0).y

## The rail reads outward from the board: Heart nearest the cards, then Aether,
## then the deck at the screen edge. Laid out explicitly because they collided
## when each was positioned from its own end of the slot.
func rail_row(side: int, which: String) -> Vector2:
	var r := rail_slot(false, side)
	var offsets := {"heart": 0.80, "aether": 0.56, "deck": 0.26}
	var u: float = float(offsets.get(which, 0.5))
	if side == 1: u = 1.0 - u
	return Vector2(r.get_center().x, r.position.y + r.size.y * u)

func deck_anchor(side: int) -> Vector2:
	return rail_row(side, "deck")

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
			var lane_r := lane_rect(int(act["side"]), int(act["lane"]))
			var at: Vector2 = lane_r.get_center()
			var colour: Color = element_colour(String(act["element"]))
			var life: bool = String(act["element"]) == "life"
			if _at(act, "seed", 0.12):
				effect("rune_%s" % ("life" if life else "fire"), at, 0.5, 2.2)
				burst(at, colour, 10, "spark", 0.7)
			if _at(act, "spread", 0.38):
				# Growth running outward across the ground it is claiming: roots and
				# vines for Grove, cracks and embers for Cinder.
				cue.emit("land_grow", 1.0)
				for k in range(4):
					var ang: float = TAU * float(k) / 4.0 + 0.4
					var out_at := at + Vector2(cos(ang), sin(ang) * 0.62) * lane_r.size.x * 0.30
					effect("vine_growth" if life else "fire_bolt", out_at, 0.5, 1.5, ang)
				burst(at, colour, 20, "leaf" if life else "ember", 1.2)
				shake(0.3)
			if _at(act, "bloom", 0.62):
				for k2 in range(3):
					var spot := at + Vector2((_vhash(k2, 71) - 0.5) * lane_r.size.x * 0.7,
						(_vhash(k2, 73) - 0.5) * lane_r.size.y * 0.6)
					effect("flower_pop" if life else "ember_burst", spot, 0.5, 1.6)
			if _at(act, "settle", 0.84):
				effect("leaf_burst" if life else "smoke_puff", at, 0.5, 2.0)
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
			if _at(act, "wind", 0.34):
				var from_card := card_rect(int(act["side"]), int(act["lane"])).get_center()
				var projectile := String(act.get("projectile", ""))
				var aim: float = (hit_at - from_card).angle()
				if projectile == "cone":
					# The breath itself crosses the battlefield, aimed at the target.
					# The cone is centred on its own length, so push it out far enough
					# that its narrow end starts at the creature, not behind it.
					var mouth := from_card.lerp(hit_at, 0.52)
					effect("flame_cone" if atk_el == "fire" else "bloom_cone",
						mouth, 0.62, 3.4, aim)
				elif projectile == "orb":
					effect("fire_bolt" if atk_el == "fire" else "leaf_burst",
						from_card.lerp(hit_at, 0.5), 0.42, 1.3, aim)
				elif weight > 0.9:
					effect("ember_burst" if atk_el == "fire" else "leaf_burst", hit_at, 0.4, 1.4)
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
		_draw_status_rail(side, f)
	# Cards last, so nothing paints over the thing the player is reading.
	for side in range(2):
		for i in range(MatchV2.LANES):
			var l: Dictionary = engine.lane(side, i)
			if l["place"] != null: _draw_place(side, i, l["place"])
	for side in range(2):
		for i in range(MatchV2.LANES):
			var l2: Dictionary = engine.lane(side, i)
			if l2["creature"] != null: _draw_creature(side, i, l2["creature"], f)
	_draw_emergent()
	_draw_targeting(f)
	_draw_acts(f)
	_draw_effects()
	_draw_particles()
	_draw_atmosphere()              # light pool, vignette, framing scenery

# --- the ground -------------------------------------------------------------

## Wild ground everywhere, then the land each Realm card has actually built.
##
## Unbuilt board is neutral scrub. A Realm card transforms *its own lane*, and
## because a lane patch is wider than a lane, two neighbouring Groves overlap
## into one continuous region while a lone one still looks hand-torn.
func _draw_ground() -> void:
	if art == null or not art.has_land_kit("neutral"):
		draw_rect(Rect2(Vector2.ZERO, size), ArcanaTheme.BG)
		return

	_tile_field(art.land_field("neutral"), Rect2(Vector2.ZERO, size))
	_scatter_patches("neutral", Rect2(0.0, 0.0, size.x, size.y), 14)

	# Built land, back row first so the near row overlaps it.
	for side in [1, 0]:
		for i in range(MatchV2.LANES):
			var terrain := String(engine.lane(side, i)["land"])
			if terrain == "": continue
			_draw_lane_land(side, i, terrain)

	_draw_clash_seam()

	for mark_entry in _decals:
		var tex2: Texture2D = art.clash("decal_%s" % String(mark_entry["kind"]), int(mark_entry["v"]))
		if tex2 == null: continue
		var ds := Vector2(tex2.get_width(), tex2.get_height())
		draw_texture_rect(tex2, Rect2((Vector2(mark_entry["at"]) - ds * 0.5).round(), ds), false)

## One Realm's land, growing out of the point it was played.
func _draw_lane_land(side: int, index: int, terrain: String) -> void:
	var grow := 1.0
	var act := _find_act("land_build", side, index)
	if not act.is_empty():
		grow = clampf(float(act["t"]) / float(act["dur"]) / 0.72, 0.0, 1.0)
	if grow <= 0.02: return
	var tex: Texture2D = art.lane_ground(terrain, side * 3 + index)
	if tex == null: return
	var lane := lane_rect(side, index)
	var full := Vector2(tex.get_width(), tex.get_height())
	# Spreads outward from the centre of the lane as the land takes hold.
	var eased: float = 1.0 - pow(1.0 - grow, 3.0)
	var drawn := full * (0.55 + 0.45 * eased)
	var centre := lane.get_center()
	draw_texture_rect(tex, Rect2((centre - drawn * 0.5).round(), drawn.round()), false,
		Color(1, 1, 1, clampf(eased * 1.6, 0.0, 1.0)))

## Where the two sides meet: a worn seam, deliberately narrow.
func _draw_clash_seam() -> void:
	var o := _origin()
	var band := Rect2(o.x - 30.0, o.y + ROW_H - 6.0, _field_width() + 60.0, CLASH_H + 12.0)
	var path: Texture2D = art.ground("row_path:neutral")
	if path != null:
		var pw := float(path.get_width())
		var ph := float(path.get_height())
		var x := band.position.x
		while x < band.position.x + band.size.x:
			var seg: float = minf(pw, band.position.x + band.size.x - x)
			draw_texture_rect_region(path,
				Rect2(Vector2(x, band.get_center().y - ph * 0.5).round(), Vector2(seg, ph)),
				Rect2(0, 0, seg, ph), Color.WHITE, false)
			x += seg
	for i in range(5):
		var crack: Texture2D = art.clash("crack", i % 3)
		if crack == null: break
		var cs := Vector2(crack.get_width(), crack.get_height())
		draw_texture_rect(crack, Rect2(Vector2(
			band.position.x + _vhash(i, 811) * (band.size.x - cs.x),
			band.get_center().y - cs.y * 0.5 + (_vhash(i, 823) - 0.5) * 26.0).round(), cs), false)
	for i in range(10):
		var rub: Texture2D = art.clash("rubble", i % 3)
		if rub == null: break
		var rs := Vector2(rub.get_width(), rub.get_height())
		draw_texture_rect(rub, Rect2(Vector2(
			band.position.x + _vhash(i, 857) * (band.size.x - rs.x),
			band.get_center().y - rs.y * 0.5 + (_vhash(i, 863) - 0.5) * 34.0).round(), rs), false)

## Which ground a player's half reads as. Used for rail dressing and row paths.
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

## Highlighting a legal lane. No box: the land itself lights up, which is what
## "selecting Sproutling makes valid Grove areas glow" should look like.
func _draw_row_zones() -> void:
	if art == null: return
	for side in range(2):
		for i in range(MatchV2.LANES):
			var key := "%d,%d" % [side, i]
			if not highlights.has(key): continue
			var lane := lane_rect(side, i)
			var attack: bool = String(highlights[key]) == "attack"
			var tint: Color = ArcanaTheme.HEART if attack \
				else ArcanaTheme.color_for_element(String(engine.players[side]["element"]))
			var pulse: float = 0.30 + 0.22 * sin(_pulse * TAU)
			var mark: Texture2D = art.clash("lane_mark", i)
			if mark != null:
				var ms := Vector2(lane.size.x * 0.94, lane.size.y * 0.80)
				draw_texture_rect(mark, Rect2((lane.get_center() - ms * 0.5).round(), ms),
					false, Color(tint, pulse))
			# A bright contact line on the ground, so the legal lane reads instantly.
			var foot := lane.position.y + lane.size.y - 12.0 if side == 0 else lane.position.y + 12.0
			draw_rect(Rect2(lane.position.x + 14.0, foot, lane.size.x - 28.0, 3.0),
				Color(tint, 0.55 + 0.35 * sin(_pulse * TAU)))

## Props growing out of built land: the roots, vines, flowers and embers that
## make a Realm card's transformation visible. Kept clear of the card itself.
func _draw_realm_dressing(side: int) -> void:
	if art == null: return
	for index in range(MatchV2.LANES):
		var terrain := String(engine.lane(side, index)["land"])
		if terrain == "": continue
		var life := terrain == "grove" or terrain == "ashbloom"
		var element := "grove" if life else "cinder"
		if art.prop_kinds(element).is_empty(): continue
		var grow := 1.0
		var act := _find_act("land_build", side, index)
		if not act.is_empty():
			grow = clampf(float(act["t"]) / float(act["dur"]) / 0.88, 0.0, 1.0)
		var mix: Array = GROVE_PROP_MIX if life else CINDER_PROP_MIX
		var lane := lane_rect(side, index)
		var card := card_rect(side, index)
		var placed: Array = []
		for n in range(14):
			var seed_value := side * 733 + index * 131 + n
			var u := _vhash(seed_value, 3)
			if u > grow: continue
			var at := Vector2(lane.position.x + 6.0 + _vhash(seed_value, 7) * (lane.size.x - 12.0),
				lane.position.y + 10.0 + _vhash(seed_value, 11) * (lane.size.y - 20.0))
			# Never behind the card the player is trying to read.
			if card.grow(4.0).has_point(at): continue
			placed.append({"at": at, "seed": seed_value})
		placed.sort_custom(func(a, b): return float(a["at"].y) < float(b["at"].y))
		for entry in placed:
			var at2: Vector2 = entry["at"]
			var seed_value2: int = int(entry["seed"])
			var pick: int = int(_vhash(seed_value2, 29) * float(mix.size())) % mix.size()
			var tex: Texture2D = art.prop(element, String(mix[pick]), seed_value2)
			if tex == null: continue
			var w := float(tex.get_width())
			var h := float(tex.get_height())
			draw_rect(Rect2(at2.x - w * 0.30, at2.y - 2.0, w * 0.60, 3.0), Color(0.05, 0.05, 0.04, 0.30))
			draw_texture_rect(tex, Rect2(Vector2(at2.x - w * 0.5, at2.y - h).round(), Vector2(w, h)), false)

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
## A player's home, framing the board from the left rail.
##
## It used to sit in a band across the top and bottom of the battlefield, where
## it took a third of the height and competed with the cards. On the rail it
## still reads as a real place standing on the same ground, but the cards get
## the screen.
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
	var nudge := Vector2(sin(hurt * 46.0) * 6.0 * hurt, sin(hurt * 31.0) * 3.0 * hurt)

	# The home's own ground, so the rail is part of the world and not a panel.
	var patch: Texture2D = art.ground_patch(_element_ground(side), side * 7 + 3) if art != null else null
	if patch != null:
		var ps := Vector2(patch.get_width(), patch.get_height()) * 1.15
		draw_texture_rect(patch, Rect2((r.get_center() - ps * 0.5 + Vector2(-14.0, 0.0)).round(), ps), false)

	var centre_x: float = r.get_center().x + nudge.x
	var base_y: float = r.position.y + r.size.y * 0.62

	var tex: Texture2D = art.sanctuary(element) if art != null else null
	if tex != null:
		var src := Vector2(tex.get_width(), tex.get_height())
		var sc: float = minf((r.size.x + 26.0) / src.x, (r.size.y * 0.60) / src.y)
		var drawn := src * sc
		draw_circle(Vector2(centre_x, base_y - 2.0), drawn.x * 0.34, Color(0.03, 0.02, 0.04, 0.34))
		draw_circle(Vector2(centre_x, base_y - drawn.y * 0.45), drawn.y * 0.55,
			Color(accent, 0.07 + 0.05 * breathe))
		draw_texture_rect(tex, Rect2(Vector2(centre_x - drawn.x * 0.5,
			base_y - drawn.y + nudge.y).round(), drawn), false,
			Color(1, 1, 1, 1).lerp(Color(1.0, 0.6, 0.65, 1.0), hurt * 0.5))

	# Commander in front of their own home, still full personality.
	var avatar: Texture2D = art.commander_board(String(p["commander_id"])) if art != null else null
	if avatar != null:
		var asrc := Vector2(avatar.get_width(), avatar.get_height())
		var asc: float = minf(76.0 / asrc.x, 76.0 / asrc.y)
		var adr := asrc * asc
		var lift := 0.0
		for act2 in _acts:
			if String(act2["kind"]) == "commander" and int(act2.get("side", -1)) == side:
				lift = sin(clampf(float(act2["t"]) / float(act2["dur"]), 0.0, 1.0) * PI) * 14.0
		var ax: float = centre_x - 34.0
		var ay: float = base_y + 44.0
		draw_circle(Vector2(ax, ay - 2.0), adr.x * 0.30, Color(0.03, 0.02, 0.04, 0.30))
		draw_texture_rect(avatar, Rect2(Vector2(ax - adr.x * 0.5, ay - adr.y - lift).round(), adr), false)
		var cname := ArcanaTheme.fit(String(p.get("commander_name", "")), 10, r.size.x - 8.0)
		if cname != "":
			var cw: float = f.get_string_size(cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(f, Vector2(r.get_center().x - cw * 0.5, ay + 16.0), cname,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT_DIM)

## The right rail: Heart, Aether and deck. Everything the player checks between
## decisions, out of the battlefield's way.
func _draw_status_rail(side: int, f: Font) -> void:
	var p: Dictionary = engine.players[side]
	var breathe: float = 0.5 + 0.5 * sin(_pulse * TAU + side * PI)
	var hurt := 0.0
	for act in _acts:
		if String(act["kind"]) == "heart_shock" and int(act.get("side", -1)) == side:
			hurt = 1.0 - clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
	_draw_heart(side, rail_row(side, "heart"), p, f, breathe, hurt)
	_draw_aether(p, rail_row(side, "aether"))
	_draw_deck(side, p, String(p["element"]), f)

## The Heart: a physical crystal, filling and emptying.
func _draw_heart(side: int, at: Vector2, p: Dictionary, f: Font,
		breathe: float, hurt: float) -> void:
	var heart := int(p["heart"])
	var frac: float = clampf(float(heart) / float(MatchV2.HEART_START), 0.0, 1.0)
	var rad: float = 30.0 * (1.0 + 0.05 * sin(_pulse * TAU * (2.4 if frac < 0.35 else 1.2)))
	if hurt > 0.0:
		draw_circle(at, rad * (2.0 + hurt), Color(ArcanaTheme.HEART, 0.22 * hurt))
	draw_circle(at, rad * 1.55, Color(ArcanaTheme.HEART, 0.08 + 0.06 * breathe))
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
	var hw: float = f.get_string_size(str(heart), HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	draw_string(f, Vector2(at.x - hw * 0.5, at.y + 7.0), str(heart),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 21, ArcanaTheme.TEXT)

func _draw_aether(p: Dictionary, at: Vector2) -> void:
	var total := int(p["max_aether"])
	var per_row := 5
	for i in range(total):
		var col := i % per_row
		var row := i / per_row
		var o := Vector2(at.x - float(mini(total, per_row) - 1) * 8.0 + float(col) * 16.0,
			at.y + float(row) * 16.0)
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
	var w := 52.0
	var h := 62.0
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
		var win := Rect2(r.position + Vector2(4.0, 4.0), Vector2(r.size.x - 8.0, r.size.y - 22.0))
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

## A played creature.
##
## The card is the piece and it stays put. The creature lives inside its frame
## and only comes out to act: during an attack the card anticipates and glows
## while the creature itself climbs out over the frame, travels, hits, and drops
## back in. Everything that leaves the frame is collected into `_emergent` and
## drawn after every card, so a lunging creature is never painted over by the
## card next door.
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
	var beat := {}

	var summon := _find_act("summon", side, index)
	if not summon.is_empty():
		var st: float = clampf(float(summon["t"]) / float(summon["dur"]), 0.0, 1.0)
		if st < 0.42: scale = 0.0
		else:
			var k: float = (st - 0.42) / 0.58
			var e1: float = 1.0 - pow(1.0 - k, 3.0)
			scale = e1
			squash = Vector2(0.78 + 0.22 * e1 + 0.20 * sin(e1 * PI),
							 0.66 + 0.34 * e1 - 0.16 * sin(e1 * PI))

	var fuse := _find_act("fusion", side, index)
	if not fuse.is_empty():
		var ft: float = clampf(float(fuse["t"]) / float(fuse["dur"]), 0.0, 1.0)
		if ft < 0.78: scale = 0.0
		else:
			var k2: float = (ft - 0.78) / 0.22
			scale = 1.0 + 0.45 * (1.0 - k2)
			squash = Vector2(1.0 + 0.24 * (1.0 - k2), 1.0 - 0.24 * (1.0 - k2))

	for act in _acts:
		if String(act["kind"]) in ["attack", "heart_attack"] and int(act.get("uid", -1)) == int(unit["uid"]):
			beat = _attack_beat(act, side, index, card_id)
			offset += Vector2(beat["card_offset"])
			glow = maxf(glow, float(beat["card_glow"]))
		elif String(act["kind"]) == "defend" and int(act.get("uid", -1)) == int(unit["uid"]):
			offset += _defend_offset(act, side, index)
			glow = maxf(glow, 0.25)
		elif String(act["kind"]) == "recoil" and int(act.get("uid", -1)) == int(unit["uid"]):
			# The defender's card takes the hit: shove, then a rattling shake.
			var rt: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
			offset += Vector2(act["push"]) * sin(rt * PI) * 22.0
			offset += Vector2(sin(rt * 58.0), 0.0) * (1.0 - rt) * 6.0
			squash *= Vector2(1.0 + 0.10 * (1.0 - rt), 1.0 - 0.10 * (1.0 - rt))
			glow = maxf(glow, 1.0 - rt)

	if scale <= 0.001: return
	var hovered: bool = side == hover_side and index == hover_lane
	if hovered: offset += Vector2(0.0, -8.0)

	var drawn_size := base.size * squash * scale
	var r := Rect2((home + offset - drawn_size * 0.5).round(), drawn_size.round())

	_card_shadow(r, 0.7 * scale)
	if glow > 0.0:
		draw_rect(r.grow(5.0 + 7.0 * glow), Color(colour, 0.26 * glow))

	var plate: Texture2D = art.frame("board_plate:%s" % element) if art != null else null
	var frame: Texture2D = art.frame("board_frame:%s" % element) if art != null else null
	var ready: bool = bool(unit.get("ready", true))
	var tint := Color(1, 1, 1, 1)
	if side == 0 and not ready: tint = Color(0.68, 0.68, 0.74, 1.0)
	if glow > 0.4: tint = Color(1.0, 0.88 + 0.12 * (1.0 - glow), 0.88, 1.0)
	if dim_others and not highlights.has("%d,%d" % [side, index]):
		tint = Color(tint.r * 0.55, tint.g * 0.55, tint.b * 0.6, 1.0)

	if plate == null:
		draw_style_box(ArcanaTheme.panel_box(colour.darkened(0.5), colour, 10, 2), r)
	else:
		draw_texture_rect(plate, r, false, tint)

	# The creature. Inside the frame at rest; handed to the emergent pass while
	# it is out acting, so it can be drawn over every card on the board.
	var tex: Texture2D = art.creature(card_id) if art != null else null
	var window := _card_window(r, scale)
	var out: float = float(beat.get("out", 0.0)) if not beat.is_empty() else 0.0
	if tex != null:
		var ts := Vector2(tex.get_width(), tex.get_height())
		var tier: float = clampf(ts.y / 96.0, 0.68, 1.0)
		var fit: float = minf(window.size.x / ts.x, window.size.y / ts.y) * tier
		if out <= 0.001:
			var drawn := ts * fit
			draw_texture_rect(tex, Rect2((window.get_center() - drawn * 0.5).round(),
				drawn.round()), false, tint)
		else:
			_emergent.append({"tex": tex, "at": Vector2(beat["at"]), "fit": fit,
				"scale": float(beat["scale"]), "squash": Vector2(beat["squash"]),
				"flip": bool(beat["flip"]), "glow": float(beat["glow"]),
				"colour": colour, "ground": float(beat["ground"])})

	if frame != null:
		draw_texture_rect(frame, r, false, tint)

	_draw_card_face(r, scale, unit, side, ready, f, tint)

## The art window inside a board card, matching tools/pixelart/cards.py.
func _card_window(r: Rect2, scale: float) -> Rect2:
	var k: float = r.size.y / CARD_H
	return Rect2(r.position.x + 5.0 * (r.size.x / CARD_W), r.position.y + 29.0 * k,
		r.size.x - 10.0 * (r.size.x / CARD_W), 150.0 * k)

## Name, cost, attack, health and status — everything readable at rest.
func _draw_card_face(r: Rect2, scale: float, unit: Dictionary, side: int,
		ready: bool, f: Font, tint: Color) -> void:
	if scale < 0.6: return
	var k: float = r.size.y / CARD_H
	var name := ArcanaTheme.fit(String(unit["name"]), 13, r.size.x - 16.0)
	var nw: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(f, Vector2(r.get_center().x - nw * 0.5, r.position.y + 20.0 * k), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ArcanaTheme.TEXT)

	var foot_y: float = r.position.y + 186.0 * k
	_gem_art("power", Vector2(r.position.x - 6.0, foot_y), str(int(unit["power"])), f)
	_gem_art("health", Vector2(r.position.x + r.size.x - 24.0, foot_y),
		str(int(unit["health"])), f, int(unit["health"]) < int(unit["max_health"]))

	# Status the player must see without hovering.
	if side == 0 and not ready:
		var label := "RESTING"
		var lw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_rect(Rect2(r.get_center().x - lw * 0.5 - 6.0, foot_y + 4.0, lw + 12.0, 15.0),
			Color(ArcanaTheme.BG, 0.82))
		draw_string(f, Vector2(r.get_center().x - lw * 0.5, foot_y + 15.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT_FAINT)

## Where a creature is, and what its card is doing, part-way through an attack.
##
## The phases are the choreography rule from CLAUDE.md made literal:
## anticipate -> emerge and travel -> impact -> return -> settle. Reach and arc
## come from data/creature_motion.json, so a Sproutling hops a short way, a
## Petal Deer charges the whole distance, a flier swoops in an arc, and a dragon
## never leaves home — it rises over its own card and breathes.
func _attack_beat(act: Dictionary, side: int, index: int, card_id: String) -> Dictionary:
	var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
	var style := motion_style(card_id)
	var reach: float = float(style.get("reach", act.get("reach", 0.6)))
	var arc: float = float(style.get("arc", 0.0))
	var wind: float = float(style.get("wind", 0.2))
	var stationary: bool = style.has("projectile")

	var home := card_rect(side, index).get_center()
	var meet := clash_centre(int(act["lane"]))
	var toward := (meet - home)
	# Only flip for a genuinely sideways attack. Lanes face each other almost
	# straight on, so flipping on the sign of a 20px drift mirrors every creature
	# for no reason.
	var facing: float = -1.0 if toward.x < -34.0 else 1.0

	var card_offset := Vector2.ZERO
	var card_glow := 0.0
	var out := 0.0
	var at := home
	var scale := 1.0
	var squash := Vector2.ONE
	var ground := 0.0

	if t < wind:
		# Anticipation: the card glows and the creature crouches inside it.
		var k: float = t / maxf(wind, 0.001)
		card_glow = k * 0.8
		card_offset = -toward.normalized() * 5.0 * k
		out = k * 0.35
		at = home - toward.normalized() * 6.0 * k
		scale = 1.0 + 0.12 * k
		squash = Vector2(1.0 + 0.14 * k, 1.0 - 0.14 * k)
	elif t < 0.52:
		# Out of the frame and across the board.
		var k2: float = (t - wind) / maxf(0.52 - wind, 0.001)
		var eased: float = 1.0 - pow(1.0 - k2, 2.2)
		card_glow = 0.8 - 0.4 * k2
		out = 1.0
		scale = 1.18 + 0.16 * eased
		if stationary:
			# Rears up over its own card and holds — the dragon's beat. It never
			# crosses the board; the breath does that for it.
			var rise: float = -1.0 if side == 0 else 1.0
			at = home + Vector2(0.0, rise * 146.0 * eased)
			scale = 1.3 + 0.75 * eased
			ground = eased
		else:
			at = home + toward * reach * eased
			if arc > 0.0:
				at.y -= sin(eased * PI) * toward.length() * arc * 0.42
			elif String(style.get("name", "")) == "hop":
				at.y -= absf(sin(eased * PI * 2.4)) * 26.0
			elif String(style.get("name", "")) == "slam":
				at.y -= sin(minf(eased * 1.6, 1.0) * PI) * 34.0
		squash = Vector2(1.0 + 0.10 * (1.0 - k2), 1.0 - 0.10 * (1.0 - k2))
	elif t < 0.88:
		# Back home.
		var k3: float = (t - 0.52) / 0.36
		var back: float = 1.0 - (1.0 - pow(1.0 - k3, 2.0))
		card_glow = 0.4 * (1.0 - k3)
		out = 1.0 - k3 * 0.8
		scale = 1.0 + 0.34 * back
		if stationary:
			var rise2: float = -1.0 if side == 0 else 1.0
			at = home + Vector2(0.0, rise2 * 146.0 * back)
			scale = 1.3 + 0.75 * back
			ground = back
		else:
			at = home + toward * reach * back
		squash = Vector2(1.0 - 0.06 * (1.0 - k3), 1.0 + 0.06 * (1.0 - k3))
	else:
		# Settling back into the frame.
		var k4: float = (t - 0.88) / 0.12
		out = (1.0 - k4) * 0.2
		at = home
		scale = 1.0 + 0.08 * (1.0 - k4)
		squash = Vector2(1.0 + 0.06 * (1.0 - k4), 1.0 - 0.06 * (1.0 - k4))

	return {"card_offset": card_offset, "card_glow": card_glow, "out": out,
		"at": at, "scale": scale, "squash": squash, "flip": facing < 0.0,
		"glow": card_glow, "ground": ground}

## Creatures currently outside their frames, drawn over every card.
func _draw_emergent() -> void:
	for e in _emergent:
		var tex: Texture2D = e["tex"]
		var ts := Vector2(tex.get_width(), tex.get_height())
		var drawn := ts * float(e["fit"]) * float(e["scale"]) * Vector2(e["squash"])
		var at: Vector2 = e["at"]
		var glow: float = float(e["glow"])
		# A shadow on the ground under it: without one it reads as a floating cutout.
		var lift: float = float(e["ground"])
		draw_circle(Vector2(at.x, at.y + drawn.y * 0.42 + lift * 26.0),
			drawn.x * (0.30 - lift * 0.08), Color(0.03, 0.02, 0.04, 0.34 - lift * 0.12))
		if glow > 0.0:
			draw_circle(at, drawn.x * (0.52 + 0.12 * glow), Color(e["colour"], 0.16 * glow))
		var dest := Rect2((at - drawn * 0.5).round(), drawn.round())
		if bool(e["flip"]):
			# A negative width mirrors in place; offsetting by the width and using a
			# region instead just moved the sprite sideways.
			draw_texture_rect(tex, Rect2(dest.position + Vector2(dest.size.x, 0.0),
				Vector2(-dest.size.x, dest.size.y)), false)
		else:
			draw_texture_rect(tex, dest, false)
	_emergent.clear()

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
## Ink on the light sockets, parchment on the dark ones. A gold number on a
## gold gem is invisible, which is how the power badge shipped blank.
const GEM_INK := {"power": true, "presence": true}

func _gem_art(kind: String, at: Vector2, text: String, f: Font, alert := false) -> void:
	var tex: Texture2D = art.frame("gem:%s" % kind) if art != null else null
	var size_v := 24.0
	if tex != null:
		size_v = float(tex.get_width())
		draw_texture_rect(tex, Rect2(at.round(), Vector2(size_v, size_v)), false,
			Color(1.0, 0.8, 0.8, 1.0) if alert else Color.WHITE)
	else:
		draw_circle(at + Vector2(size_v * 0.5, size_v * 0.5), size_v * 0.45, Color(0.1, 0.09, 0.12))
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var ink: Color = Color(0.09, 0.07, 0.06) if bool(GEM_INK.get(kind, false)) else ArcanaTheme.TEXT
	draw_string(f, Vector2(at.x + size_v * 0.5 - tw * 0.5, at.y + size_v * 0.5 + 5.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)

func _gem(f: Font, centre: Vector2, text: String, colour: Color) -> void:
	draw_circle(centre, 11.0, Color(0.05, 0.05, 0.08, 0.92))
	draw_arc(centre, 11.0, 0, TAU, 18, Color(colour, 0.9), 2.0)
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(f, Vector2(centre.x - w * 0.5, centre.y + 5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colour)

## The attacker leaves its land, meets in the clash space, and returns.
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
		var r3 := card_rect(0, int(pair))
		# On the card's shoulder, not across its name ribbon.
		var c := Vector2(r3.position.x + r3.size.x - 6.0, r3.position.y - 4.0)
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

## Fusion, done with the cards themselves.
##
## Two compatible cards lift off the battlefield, drift toward each other while
## ribbons wind between them, collapse into a single point of light, and the
## fused card slams down. The creature bursting out of the new frame is the
## summon beat that follows, so this only has to sell the collapse.
func _draw_fusion(act: Dictionary, t: float, f: Font) -> void:
	var side := int(act["side"])
	var lane_a := int(act["lane"])
	var lane_b := int(act["freed_lane"])
	var a := card_rect(side, lane_a)
	var b := card_rect(side, lane_b)
	var target := card_rect(side, lane_a)
	var colour: Color = act["colour"]
	var element := String(engine.players[side]["element"])
	var plate: Texture2D = art.frame("board_plate:%s" % element) if art != null else null
	var frame: Texture2D = art.frame("board_frame:%s" % element) if art != null else null

	if t < 0.84:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.40 * clampf(t / 0.18, 0.0, 1.0)))

	if t < 0.62:
		# Lift and converge. The cards are the thing moving, not a pair of orbs.
		var k: float = t / 0.62
		var eased: float = k * k * (3.0 - 2.0 * k)
		var mid := a.get_center().lerp(b.get_center(), 0.5)
		mid.y -= 30.0 * sin(eased * PI * 0.9)
		var pa := a.get_center().lerp(mid, eased)
		var pb := b.get_center().lerp(mid, eased)
		var shrink: float = 1.0 - 0.30 * eased
		var spin: float = eased * TAU * 1.2
		# Ribbons winding between the two cards.
		for i in range(14):
			var u: float = float(i) / 14.0
			var p0 := pa.lerp(pb, u)
			var p1 := pa.lerp(pb, u + 0.075)
			var wob: float = sin(u * PI * 3.0 + spin) * 26.0 * (1.0 - eased * 0.5)
			draw_line(p0 + Vector2(0.0, wob), p1 + Vector2(0.0, wob * 0.8),
				Color(colour, 0.30 + 0.55 * sin((u + t) * PI * 3.0)), 3.0)
		for pair in [[pa, lane_a], [pb, lane_b]]:
			var at: Vector2 = pair[0]
			var lane_i: int = int(pair[1])
			var drawn := a.size * shrink
			var r := Rect2((at - drawn * 0.5).round(), drawn.round())
			draw_rect(r.grow(6.0), Color(colour, 0.30 * eased))
			if plate != null: draw_texture_rect(plate, r, false)
			# Whose cards these are has to stay legible right up to the collapse.
			var source: Dictionary = act.get("cards", {})
			var cid := String(source.get(str(lane_i), ""))
			var tex: Texture2D = art.creature(cid) if (art != null and cid != "") else null
			if tex != null:
				var ts := Vector2(tex.get_width(), tex.get_height())
				var win := _card_window(r, shrink)
				var fit: float = minf(win.size.x / ts.x, win.size.y / ts.y) * clampf(ts.y / 96.0, 0.68, 1.0)
				var cd := ts * fit
				draw_texture_rect(tex, Rect2((win.get_center() - cd * 0.5).round(), cd.round()), false)
			if frame != null: draw_texture_rect(frame, r, false)
		draw_circle(mid, 8.0 + 54.0 * eased * eased, Color(1, 1, 1, 0.20 + 0.65 * eased * eased))
	elif t < 0.78:
		# Collapse into light.
		var k2: float = (t - 0.62) / 0.16
		var c := target.get_center()
		draw_circle(c, 66.0 * (1.0 - k2) + 22.0, Color(1, 1, 1, 0.88 * (1.0 - k2)))
		draw_arc(c, 44.0 + 130.0 * k2, 0, TAU, 44, Color(colour, 1.0 - k2), 5.0)
	else:
		# The fused card slams down.
		var k3: float = (t - 0.78) / 0.22
		var drop: float = (1.0 - k3) * (1.0 - k3) * 70.0
		var over: float = 1.0 + 0.22 * (1.0 - k3)
		var drawn2 := target.size * Vector2(over, 1.0 / over)
		var r2 := Rect2((target.get_center() - drawn2 * 0.5 - Vector2(0.0, drop)).round(),
			drawn2.round())
		draw_rect(r2.grow(8.0 * (1.0 - k3)), Color(ArcanaTheme.GOLD, 0.55 * (1.0 - k3)))
		if plate != null: draw_texture_rect(plate, r2, false)
		if frame != null: draw_texture_rect(frame, r2, false)
		draw_arc(target.get_center(), 34.0 + 100.0 * k3, 0, TAU, 36,
			Color(ArcanaTheme.GOLD, 0.8 * (1.0 - k3)), 4.0)
		var name := String(act.get("name", ""))
		var w: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f, Vector2(target.get_center().x - w * 0.5,
			target.position.y - 18.0 - 10.0 * k3), name,
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
