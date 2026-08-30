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
const RAIL_W := 168.0                 # left/right rails: homes and components
const EDGE_PAD := 8.0
const ROW_H := 232.0                  # a combat row — nearly all of the height
const CLASH_H := 68.0                 # a seam where they meet, not a strip
const CARD_W := 168.0                 # a travelling card in flight (draw/play)
const CARD_H := 224.0
const PLACE_W := 104.0                # a Place building's ground footprint
const PLACE_H := 130.0

var engine: MatchV2
var art: ArtRegistry
var realm := RealmVisualSystem.new()  # sim state -> living environment
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
	realm.stage = self
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

## Where a piece's feet stand on its plot. The card frame is gone from the
## board (direction lock M3): the creature IS the piece.
func creature_stand(side: int, index: int) -> Vector2:
	var p := plot_rect(side, index)
	var nudge := 0.0
	if engine != null and not engine.players.is_empty() \
			and engine.lane(side, index)["place"] != null:
		nudge = 18.0
	return Vector2(p.get_center().x + nudge, p.position.y + p.size.y - 12.0)

## Size classes are real: a 48px sprite is a critter, a 96px sprite is a
## monument. The scale keeps their authored mass ratio instead of fitting
## everything into one window.
func creature_scale(card_id: String) -> float:
	var h: float = float(art.source_size(card_id).y) if art != null else 64.0
	if h <= 48.0: return 1.7
	if h <= 64.0: return 1.85
	return 2.0

## The rect a standing creature's body occupies on screen.
func creature_body(side: int, index: int, card_id: String) -> Rect2:
	var src := Vector2(art.source_size(card_id)) if art != null else Vector2(64, 64)
	var s := src * creature_scale(card_id)
	var feet := creature_stand(side, index)
	return Rect2(feet - Vector2(s.x * 0.5, s.y - 6.0), s)

## Kept under its old name — a dozen callers only ever wanted "where is the
## piece in this lane". With a creature standing there it is the body; empty,
## it is a modest zone round the stand point (card flights land there).
func card_rect(side: int, index: int) -> Rect2:
	if engine != null and not engine.players.is_empty():
		var l: Dictionary = engine.lane(side, index)
		if l["creature"] != null:
			return creature_body(side, index, String(l["creature"]["card_id"]))
	var p := plot_rect(side, index)
	return Rect2(p.get_center() - Vector2(52.0, 64.0), Vector2(104.0, 128.0))

## A Place stands at the back-left of its plot; the creature holds the front.
func place_rect(side: int, index: int) -> Rect2:
	var p := plot_rect(side, index)
	return Rect2(Vector2(p.position.x + 10.0, p.position.y + 2.0).round(),
		Vector2(PLACE_W, PLACE_H))

## The home now lives on the left rail, framing the board rather than sitting
## across the top or bottom of it.
func sanctuary_rect(side: int) -> Rect2:
	return rail_slot(true, side)

## Where a player's Heart crystal sits on their home slab.
func heart_anchor(side: int) -> Vector2:
	var r := sanctuary_rect(side)
	var slab_y: float = (r.position.y + 14.0) if side == 1 \
		else (r.position.y + r.size.y - 252.0)
	return Vector2(r.position.x + 2.0 + r.size.x - 6.0 - 26.0, slab_y + 196.0 - 24.0)

func creature_anchor(side: int, index: int) -> Vector2:
	return card_rect(side, index).get_center()

func place_anchor(side: int, index: int) -> Vector2:
	var r := place_rect(side, index)
	return Vector2(r.get_center().x, r.position.y + r.size.y - 24.0)

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
	var offsets := {"deck": 0.24, "aether": 0.50, "realm": 0.70}
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
	realm.on_act(kind, act)

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
					creature_stand(int(act["side"]), int(act["lane"])), 0.55, 2.0)
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
				shake(1.25); hitstop(0.09)
		"death":
			if _at(act, "burst", 0.28):
				var death_at: Vector2 = act["at"]
				effect("smoke_puff", death_at, 0.55, 1.6)
				burst(act["at"], Color(act["colour"]), 14, "spark", 0.8)
				# What falls stays fallen: a wilt of flowers or a scorch mark.
				scar(death_at + Vector2(0.0, 18.0),
					"scorch" if String(act.get("element", "")) == "fire" else "growth")
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

## The arcane table, with a carved socket per lane and the chunky elevated
## plots that Realm cards drop into them.
##
## Direction lock (docs/V2_ART_PASS_TRIAGE.md): the unbuilt board is a calm
## slate game table — the world only exists where a player has built it, which
## is what makes building feel like building.
const PLOT_RADIUS := 14.0
const PLOT_FACE_H := 26.0
const PLOT_INSET_X := 7.0             # breathing room between neighbouring plots
const PLOT_TOP_GAP := 10.0            # from the lane's far edge
const PLOT_CLASH_GAP := 26.0          # from the clash channel

func _draw_ground() -> void:
	if art == null or not art.has_table():
		draw_rect(Rect2(Vector2.ZERO, size), ArcanaTheme.BG)
		return

	_tile_field(art.table("field:0"), Rect2(Vector2.ZERO, size))

	# A whisper of ownership: the rival's half runs warm, yours runs green.
	var mid := front_line_y()
	draw_rect(Rect2(0.0, 0.0, size.x, mid), Color(0.95, 0.45, 0.20, 0.030))
	draw_rect(Rect2(0.0, mid, size.x, size.y - mid), Color(0.40, 0.90, 0.50, 0.025))

	_draw_clash_seam()

	# Empty positions are seed-points — faint rune rings where a world could
	# grow — never sockets. The grid belongs to the simulation, not the eye.
	for side in range(2):
		for i in range(MatchV2.LANES):
			if String(engine.lane(side, i)["land"]) == "":
				realm.draw_seedpoint(side, i)

	# Built land: merged runs of same-element neighbours, back row first.
	for side in [1, 0]:
		_draw_land_runs(side)

	realm.draw_fusion_sites()

	for mark_entry in _decals:
		var tex2: Texture2D = art.clash("decal_%s" % String(mark_entry["kind"]), int(mark_entry["v"]))
		if tex2 == null: continue
		var ds := Vector2(tex2.get_width(), tex2.get_height())
		draw_texture_rect(tex2, Rect2((Vector2(mark_entry["at"]) - ds * 0.5).round(), ds), false)

## The top surface of a lane's plot (the face hangs below it).
func plot_rect(side: int, index: int) -> Rect2:
	var lane := lane_rect(side, index)
	var top: float = lane.position.y + (PLOT_TOP_GAP if side == 1 else PLOT_CLASH_GAP)
	var h: float = lane.size.y - PLOT_TOP_GAP - PLOT_CLASH_GAP - PLOT_FACE_H
	return Rect2(lane.position.x + PLOT_INSET_X, top, lane.size.x - PLOT_INSET_X * 2.0, h)

## A rounded-rect polygon. Corners can be squared off per edge so merged plots
## share a continuous silhouette.
func _rounded_poly(r: Rect2, rad: float, round_left: bool, round_right: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var segs := 5
	var corners := [
		[Vector2(r.position.x + r.size.x, r.position.y), round_right, PI * 1.5],   # ne
		[Vector2(r.position.x + r.size.x, r.position.y + r.size.y), round_right, 0.0],  # se
		[Vector2(r.position.x, r.position.y + r.size.y), round_left, PI * 0.5],    # sw
		[Vector2(r.position.x, r.position.y), round_left, PI],                     # nw
	]
	for c in corners:
		var at: Vector2 = c[0]
		if not bool(c[1]):
			pts.append(at)
			continue
		var centre := at + Vector2(-rad if at.x > r.get_center().x else rad,
			-rad if at.y > r.get_center().y else rad)
		var start: float = float(c[2])
		for s in range(segs + 1):
			var a: float = start + (PI * 0.5) * float(s) / float(segs)
			pts.append(centre + Vector2(cos(a), sin(a)) * rad)
	return pts

## Fill a polygon with a texture in continuous world UVs, so neighbouring
## plots of the same element read as one piece of ground.
func _poly_textured(poly: PackedVector2Array, tex: Texture2D, tint: Color, v_anchor := 0.0) -> void:
	if tex == null or poly.size() < 3: return
	var ts := Vector2(tex.get_width(), tex.get_height())
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(Vector2(p.x / ts.x, (p.y - v_anchor) / ts.y))
	var cols := PackedColorArray()
	for _p in poly: cols.append(tint)
	draw_polygon(poly, cols, uvs, tex)

## A lane is still "building" until its slab has visibly landed — after that
## it merges with its neighbours even while the bloom effects finish on top.
func _land_building(side: int, index: int) -> bool:
	var act := _find_act("land_build", side, index)
	if act.is_empty(): return false
	return float(act["t"]) / float(act["dur"]) / 0.72 < 1.0

## Built lanes drawn as merged runs: [1,1,0,1] grove becomes two slabs.
func _draw_land_runs(side: int) -> void:
	var i := 0
	while i < MatchV2.LANES:
		var terrain := String(engine.lane(side, i)["land"])
		if terrain == "":
			i += 1
			continue
		var j := i
		while j + 1 < MatchV2.LANES \
				and String(engine.lane(side, j + 1)["land"]) == terrain \
				and not _land_building(side, j + 1) \
				and not _land_building(side, i):
			j += 1
		_draw_plot_run(side, i, j, terrain)
		i = j + 1

## One slab: ink silhouette, earth face, top surface, lit rim.
func _draw_plot_run(side: int, first: int, last: int, terrain: String) -> void:
	var grow := 1.0
	var act := _find_act("land_build", side, first)
	if not act.is_empty():
		grow = clampf(float(act["t"]) / float(act["dur"]) / 0.72, 0.0, 1.0)
	if grow <= 0.02: return
	var eased: float = 1.0 - pow(1.0 - grow, 3.0)

	var a := plot_rect(side, first)
	var b := plot_rect(side, last)
	var top := Rect2(a.position, Vector2(b.position.x + b.size.x - a.position.x, a.size.y))
	# The slab drops in from above and lands as one piece.
	var lift: float = (1.0 - eased) * -26.0
	top.position.y += lift
	var alpha: float = clampf(eased * 1.5, 0.0, 1.0)

	_draw_slab(top, terrain, alpha, side * 977 + first * 131 + last * 17)

	# Faint carved grooves at internal lane boundaries, so a merged slab still
	# counts as lanes at a glance.
	var lit: Color = LAND_RIM_LIGHT.get(terrain, Color(1, 1, 1))
	for k in range(first + 1, last + 1):
		var gx: float = lane_rect(side, k).position.x
		draw_line(Vector2(gx, top.position.y + 6.0), Vector2(gx, top.position.y + top.size.y - 4.0),
			Color(0.09, 0.067, 0.059, 0.42 * alpha), 2.0)
		draw_line(Vector2(gx + 2.0, top.position.y + 6.0),
			Vector2(gx + 2.0, top.position.y + top.size.y - 4.0),
			Color(lit, 0.20 * alpha), 1.0)
		# small carved notches where the groove meets the rims
		draw_rect(Rect2(gx - 3.0, top.position.y + 1.0, 8.0, 5.0),
			Color(0.09, 0.067, 0.059, 0.55 * alpha))
		draw_rect(Rect2(gx - 3.0, top.position.y + top.size.y - 6.0, 8.0, 5.0),
			Color(0.09, 0.067, 0.059, 0.55 * alpha))

const LAND_RIM_LIGHT := {
	"grove": Color("a8cf8a"), "cinder": Color("f65600"),
	"ashbloom": Color("e88fa6"), "neutral": Color("8f8474"),
}

## Where the two sides meet: an inlaid channel with a rune medallion per lane.
func _draw_clash_seam() -> void:
	var o := _origin()
	var band := Rect2(o.x - 20.0, o.y + ROW_H + 6.0, _field_width() + 40.0, CLASH_H - 12.0)
	var poly := _rounded_poly(band, 12.0, true, true)
	_poly_textured(poly, art.table("channel"), Color(1, 1, 1, 1), band.position.y)
	if art.table("channel") == null:
		var cols := PackedColorArray()
		for _p in poly: cols.append(Color(0.0, 0.0, 0.02, 0.30))
		draw_polygon(poly, cols)
	poly.append(poly[0])
	draw_polyline(poly, Color(0.06, 0.06, 0.10, 0.9), 2.0)
	for i in range(MatchV2.LANES):
		var med: Texture2D = art.table("medallion:%d" % i)
		if med == null: continue
		var ms := Vector2(med.get_width(), med.get_height())
		draw_texture_rect(med, Rect2((clash_centre(i) - ms * 0.5).round(), ms), false)

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

## Highlighting a legal lane: the plot (or its empty socket) itself lights up —
## the world illuminates, no debug rectangles.
func _draw_row_zones() -> void:
	if art == null: return
	for side in range(2):
		for i in range(MatchV2.LANES):
			var key := "%d,%d" % [side, i]
			if not highlights.has(key): continue
			var attack: bool = String(highlights[key]) == "attack"
			var tint: Color = ArcanaTheme.HEART if attack \
				else ArcanaTheme.color_for_element(String(engine.players[side]["element"]))
			var pulse: float = 0.5 + 0.5 * sin(_pulse * TAU)
			var r := plot_rect(side, i)
			var built: bool = String(engine.lane(side, i)["land"]) != ""
			if built:
				var poly := realm.organic_poly(r, PLOT_RADIUS, side * 733 + i * 149)
				var cols := PackedColorArray()
				for _p in poly: cols.append(Color(tint, 0.14 + 0.06 * pulse))
				draw_polygon(poly, cols)
				poly.append(poly[0])
				draw_polyline(poly, Color(tint, 0.55 + 0.35 * pulse), 3.0)
			else:
				# The sleeping seed-point wakes: light pools on the ground and
				# the rune ring blooms. No rectangle, ever.
				var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.58)
				for g in range(5):
					var ga := TAU * float(g) / 5.0 + float(i) * 1.3
					draw_circle(c + Vector2(cos(ga), sin(ga) * 0.6) * 22.0,
						34.0, Color(tint, 0.05 + 0.02 * pulse))
				draw_circle(c, 40.0, Color(tint, 0.07 + 0.04 * pulse))
				draw_arc(c, 26.0 + 3.0 * pulse, 0, TAU, 28, Color(tint, 0.85), 2.5)
				draw_arc(c, 34.0 + 5.0 * pulse, 0, TAU, 32, Color(tint, 0.35), 1.5)
			# An open way to the Heart shows its whole consequence: a dotted
			# trail runs from the lit lane to the rival crystal, which pulses.
			if attack and engine.lane(side, i)["creature"] == null:
				var ha := Vector2(r.get_center().x, r.position.y + r.size.y * 0.4)
				var hb := heart_anchor(side)
				for k in range(9):
					var u: float = (float(k) + fmod(_pulse * 2.0, 1.0)) / 9.0
					if u > 1.0: u -= 1.0
					var q := ha.lerp(hb, u) + Vector2(0.0, -30.0 * sin(u * PI))
					draw_circle(q, 3.0, Color(ArcanaTheme.HEART, 0.35 + 0.35 * sin(u * PI)))
				draw_arc(hb, 30.0 + 6.0 * pulse, 0, TAU, 28,
					Color(ArcanaTheme.HEART, 0.65), 2.5)

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
		var plot := plot_rect(side, index)
		var lane_state: Dictionary = engine.lane(side, index)
		# Keep the piece's ground clear: the standing creature's body if one is
		# here, otherwise a modest arrival zone round the stand point.
		var clear := Rect2(creature_stand(side, index) - Vector2(48.0, 84.0), Vector2(96.0, 100.0))
		if lane_state["creature"] != null:
			# Only the piece's footing needs to stay clear — excluding the whole
			# body rect stripped every prop off a large creature's plot.
			var body := card_rect(side, index)
			clear = Rect2(body.get_center().x - minf(body.size.x, 116.0) * 0.5,
				body.position.y + body.size.y - 96.0, minf(body.size.x, 116.0), 104.0)
		var place_zone := place_rect(side, index).grow(4.0) if lane_state["place"] != null \
			else Rect2(-999.0, -999.0, 0.0, 0.0)
		var placed: Array = []
		for n in range(14):
			var seed_value := side * 733 + index * 131 + n
			var u := _vhash(seed_value, 3)
			if u > grow: continue
			# Props stand ON the plot's top surface; feet stay inside the slab.
			var at := Vector2(plot.position.x + 8.0 + _vhash(seed_value, 7) * (plot.size.x - 16.0),
				plot.position.y + 30.0 + _vhash(seed_value, 11) * (plot.size.y - 32.0))
			if clear.has_point(at) or place_zone.has_point(at): continue
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

## Depth, drawn last: dark framing scenery at the screen edges and a gentle
## vignette. The old central light pool is gone — it fogged the whole board
## khaki; local realm glows carry the atmosphere instead.
func _draw_atmosphere() -> void:
	if art == null: return
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
		# The rock pieces are gone: against the slate table they collapsed into
		# black boxes that read as rendering errors beside the home slabs.
	]

## Gradient quads rather than a texture: a vignette is lighting, and drawing it
## as four polygons costs nothing and always matches the window size.
func _draw_vignette() -> void:
	# Enough to push the corners back, not enough to grey out the battlefield.
	var dark := Color(0.03, 0.02, 0.045, 0.30)
	var clear := Color(0.03, 0.02, 0.045, 0.0)
	var depth: float = size.y * 0.13
	var side_depth: float = size.x * 0.10
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

## A player's home: the Sanctuary standing on its own element slab, with the
## Heart crystal set into the slab beside it. One home, one Heart, one place
## on screen — the rail diamonds are gone.
func _draw_sanctuary(side: int, f: Font) -> void:
	var r := sanctuary_rect(side)
	var p: Dictionary = engine.players[side]
	var element := String(p["element"])
	var terrain := String(p["terrain"])
	var accent: Color = ArcanaTheme.color_for_element(element)
	var breathe: float = 0.5 + 0.5 * sin(_pulse * TAU + side * PI)

	var hurt := 0.0
	for act in _acts:
		if String(act["kind"]) == "heart_shock" and int(act.get("side", -1)) == side:
			hurt = 1.0 - clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
	var nudge := Vector2(sin(hurt * 46.0) * 6.0 * hurt, sin(hurt * 31.0) * 3.0 * hurt)

	# The home slab: same construction as a lane plot, so the home reads as the
	# realm's first and oldest piece of world.
	var slab := Rect2(r.position.x + 2.0,
		(r.position.y + 14.0) if side == 1 else (r.position.y + r.size.y - 252.0),
		r.size.x - 6.0, 196.0)
	_draw_slab(slab, terrain, 1.0, 4000 + side * 313)

	var centre_x: float = slab.get_center().x + nudge.x
	var base_y: float = slab.position.y + slab.size.y - 10.0

	var tex: Texture2D = art.sanctuary(element) if art != null else null
	if tex != null:
		var srcs := Vector2(tex.get_width(), tex.get_height())
		var sc: float = (slab.size.x + 30.0) / srcs.x
		var drawn := srcs * sc
		_ellipse_shadow(Vector2(centre_x, base_y - 6.0), drawn.x * 0.34, 10.0, 0.30)
		draw_circle(Vector2(centre_x, base_y - drawn.y * 0.45), drawn.y * 0.55,
			Color(accent, 0.06 + 0.05 * breathe))
		draw_texture_rect(tex, Rect2(Vector2(centre_x - drawn.x * 0.5,
			base_y - drawn.y + nudge.y).round(), drawn.round()), false,
			Color(1, 1, 1, 1).lerp(Color(1.0, 0.6, 0.65, 1.0), hurt * 0.5))

	# The Heart, physically part of the home.
	_draw_heart(side, heart_anchor(side) + nudge, p, f, breathe, hurt)

	# Commander in front of their own home, still full personality.
	var avatar: Texture2D = art.commander_board(String(p["commander_id"])) if art != null else null
	if avatar != null:
		var asrc := Vector2(avatar.get_width(), avatar.get_height())
		var adr := asrc * 1.15
		var lift := 0.0
		for act2 in _acts:
			if String(act2["kind"]) == "commander" and int(act2.get("side", -1)) == side:
				lift = sin(clampf(float(act2["t"]) / float(act2["dur"]), 0.0, 1.0) * PI) * 14.0
		var ax: float = slab.position.x + 34.0
		var ay: float = base_y + 4.0
		_ellipse_shadow(Vector2(ax, ay - 2.0), adr.x * 0.32, 8.0, 0.28)
		draw_texture_rect(avatar, Rect2(Vector2(ax - adr.x * 0.5, ay - adr.y - lift).round(),
			adr.round()), false)
	var cname := ArcanaTheme.fit(String(engine.db.get_commander(
		String(p["commander_id"])).get("name", "")), 11, r.size.x - 12.0)
	if cname != "":
		var cw: float = f.get_string_size(cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var ny: float = (slab.position.y - 8.0) if side == 0 \
			else (slab.position.y + slab.size.y + PLOT_FACE_H + 2.0)
		draw_rect(Rect2(centre_x - cw * 0.5 - 7.0, ny - 12.0, cw + 14.0, 17.0),
			Color(0.07, 0.06, 0.09, 0.72))
		draw_string(f, Vector2(centre_x - cw * 0.5, ny), cname,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT_DIM)

## One slab, drawn anywhere: ink silhouette, banded-earth face, calm top, rim.
## The silhouette is organic — a deterministic hand-torn wobble per seed — so
## built land reads as a piece of world, never a rounded rectangle.
func _draw_slab(top: Rect2, terrain: String, alpha: float, seed_v := 0) -> void:
	var whole := Rect2(top.position, Vector2(top.size.x, top.size.y + PLOT_FACE_H))
	var centre := whole.get_center()
	var sil := realm.organic_poly(whole.grow(2.0), PLOT_RADIUS + 2.0, seed_v, 5.0, centre)
	var ink_cols := PackedColorArray()
	for _p in sil: ink_cols.append(Color(0.09, 0.067, 0.059, alpha))
	draw_polygon(sil, ink_cols)
	# The face overlaps up under the field so the shared wobble never opens a
	# seam between the two textures.
	var face_rect := Rect2(top.position.x, top.position.y + top.size.y - 8.0,
		top.size.x, PLOT_FACE_H + 8.0)
	var face_poly := realm.organic_poly(face_rect, PLOT_RADIUS - 2.0, seed_v, 5.0, centre)
	_poly_textured(face_poly, art.land_face(terrain, 0), Color(1, 1, 1, alpha),
		top.position.y + top.size.y - 1.0)
	var top_poly := realm.organic_poly(top, PLOT_RADIUS, seed_v, 5.0, centre)
	_poly_textured(top_poly, art.land_field(terrain), Color(1, 1, 1, alpha))
	var rim := realm.organic_poly(top.grow(-1.0), PLOT_RADIUS - 1.0, seed_v, 5.0, centre)
	rim.append(rim[0])
	var lit: Color = LAND_RIM_LIGHT.get(terrain, Color(1, 1, 1))
	draw_polyline(rim, Color(lit, 0.30 * alpha), 2.0)

## The right rail: a stone plinth holding deck, aether and the Realm Stack —
## physical components on a shelf, not numbers floating on the table.
func _draw_status_rail(side: int, f: Font) -> void:
	var p: Dictionary = engine.players[side]
	var slot := rail_slot(false, side)
	var shelf := Rect2(slot.position.x + 4.0,
		(slot.position.y + 12.0) if side == 1 else (slot.position.y + slot.size.y - 262.0),
		slot.size.x - 8.0, 206.0)
	_draw_slab(shelf, "neutral", 0.9, 5000 + side * 401)
	_draw_deck(side, p, String(p["element"]), f)
	_draw_aether(p, rail_row(side, "aether"))
	_draw_realm_stack(side, p, rail_row(side, "realm"), f)

## The Heart: a faceted crystal set into the home slab, cracking as it empties.
func _draw_heart(side: int, at: Vector2, p: Dictionary, f: Font,
		breathe: float, hurt: float) -> void:
	var heart := int(p["heart"])
	var frac: float = clampf(float(heart) / float(MatchV2.HEART_START), 0.0, 1.0)
	var rad: float = 24.0 * (1.0 + 0.05 * sin(_pulse * TAU * (2.4 if frac < 0.35 else 1.2)))
	if hurt > 0.0:
		draw_circle(at, rad * (2.0 + hurt), Color(ArcanaTheme.HEART, 0.22 * hurt))
	draw_circle(at, rad * 1.45, Color(ArcanaTheme.HEART, 0.10 + 0.08 * breathe))
	var facets := PackedVector2Array([at + Vector2(0, -rad), at + Vector2(rad * 0.76, 0),
		at + Vector2(0, rad), at + Vector2(-rad * 0.76, 0)])
	draw_colored_polygon(facets, Color(0.24, 0.09, 0.15, 0.96))
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
	# A wounded Heart shows it: cracks spread as it empties.
	if frac < 0.55:
		draw_polyline(PackedVector2Array([at + Vector2(-6.0, -rad * 0.5),
			at + Vector2(2.0, -rad * 0.1), at + Vector2(-3.0, rad * 0.35)]),
			Color(0.06, 0.02, 0.04, 0.85), 1.5)
	if frac < 0.30:
		draw_polyline(PackedVector2Array([at + Vector2(rad * 0.4, -rad * 0.2),
			at + Vector2(rad * 0.1, rad * 0.2), at + Vector2(rad * 0.35, rad * 0.55)]),
			Color(0.06, 0.02, 0.04, 0.85), 1.5)
	# The number on a stone plaque under the crystal, always full-contrast.
	var plq := Rect2(at.x - 18.0, at.y + rad + 2.0, 36.0, 20.0)
	draw_style_box(ArcanaTheme.panel_box(Color(0.16, 0.15, 0.13, 0.96),
		Color(0.34, 0.31, 0.27), 5, 1), plq)
	var hw: float = f.get_string_size(str(heart), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(f, Vector2(at.x - hw * 0.5, plq.position.y + 15.0), str(heart),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ArcanaTheme.TEXT)

## Aether as physical crystals on the shelf: spent orbs go dark, never absent.
func _draw_aether(p: Dictionary, at: Vector2) -> void:
	var total := int(p["max_aether"])
	var per_row := 5
	for i in range(total):
		var col := i % per_row
		var row := i / per_row
		var o := Vector2(at.x - float(mini(total, per_row) - 1) * 10.0 + float(col) * 20.0,
			at.y + float(row) * 20.0)
		if i < int(p["aether"]):
			draw_circle(o, 9.5, Color(0.09, 0.067, 0.059))
			draw_circle(o, 8.0, Color(ArcanaTheme.AETHER, 0.4))
			draw_circle(o, 6.0, ArcanaTheme.AETHER)
			draw_circle(o - Vector2(2.0, 2.0), 2.2, Color(1, 1, 1, 0.75))
		else:
			draw_circle(o, 8.0, Color(0.05, 0.05, 0.09, 0.85))
			draw_arc(o, 8.0, 0, TAU, 16, Color(ArcanaTheme.PANEL_EDGE, 0.8), 1.5)

## The Realm Stack: a physical pile of unbuilt land slabs, with its count.
func _draw_realm_stack(side: int, p: Dictionary, at: Vector2, f: Font) -> void:
	var count := int(p.get("realm_stack", 0))
	var terrain := String(p["terrain"])
	var lit: Color = LAND_RIM_LIGHT.get(terrain, Color(1, 1, 1))
	var field: Texture2D = art.land_field(terrain) if art != null else null
	var w := 58.0
	var h := 15.0
	var layers: int = maxi(count, 0)
	for i in range(layers):
		var rr := Rect2(at.x - w * 0.5 + float(i % 2) * 2.0,
			at.y + 12.0 - float(i) * 9.0, w, h)
		var poly := _rounded_poly(rr.grow(1.5), 6.0, true, true)
		var cols := PackedColorArray()
		for _pt in poly: cols.append(Color(0.09, 0.067, 0.059))
		draw_polygon(poly, cols)
		var inner := _rounded_poly(rr, 5.0, true, true)
		_poly_textured(inner, field, Color(1, 1, 1, 1), rr.position.y)
		if field == null:
			var cols2 := PackedColorArray()
			for _pt2 in inner: cols2.append(Color(lit, 0.6))
			draw_polygon(inner, cols2)
	if count > 0:
		var label := str(count)
		var lw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(at.x - lw * 0.5, at.y + 40.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.TEXT_DIM)

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
	draw_rect(Rect2(deck.x - lw * 0.5 - 5.0, deck.y + h * 0.5 + 4.0, lw + 10.0, 15.0),
		Color(0.07, 0.06, 0.09, 0.72))
	draw_string(f, Vector2(deck.x - lw * 0.5, deck.y + h * 0.5 + 16.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT)

## A Place: a real building standing at the back of its plot — never a second
## card. Construction still climbs through its authored stages.
func _draw_place(side: int, index: int, place: Dictionary) -> void:
	var r := place_rect(side, index)
	var card_id := String(place["card_id"])
	var act := _find_act("place_build", side, index)
	var build := 1.0
	if not act.is_empty(): build = clampf(float(act["t"]) / float(act["dur"]) / 0.88, 0.0, 1.0)
	if build <= 0.02: return
	var eased: float = 1.0 - pow(1.0 - build, 3.0)

	# footing -> lower storey -> most of it -> finished.
	var stage_index: int = 3
	if eased < 0.30: stage_index = 0
	elif eased < 0.58: stage_index = 1
	elif eased < 0.86: stage_index = 2
	var tex: Texture2D = art.landmark_stage(card_id, stage_index) if art != null else null
	var feet := Vector2(r.get_center().x, r.position.y + r.size.y)
	if tex == null:
		draw_style_box(ArcanaTheme.panel_box(card_colour(card_id).darkened(0.55),
			card_colour(card_id), 8, 2), r)
		return
	var ts := Vector2(tex.get_width(), tex.get_height())
	var sc: float = minf(r.size.x / ts.x, r.size.y / ts.y)
	var drawn := ts * sc
	_ellipse_shadow(Vector2(feet.x, feet.y - 5.0), drawn.x * 0.44, 10.0, 0.30 * eased)
	draw_texture_rect(tex, Rect2(Vector2(feet.x - drawn.x * 0.5,
		feet.y - drawn.y).round(), drawn.round()), false)

	if eased >= 0.99:
		# A finished Place shows what it is doing to its lane.
		var glow: Texture2D = art.landmark_passive(card_id) if art != null else null
		if glow != null:
			var gs := Vector2(glow.get_width(), glow.get_height())
			var breathe: float = 0.45 + 0.30 * sin(_pulse * TAU + float(index) * 0.8)
			draw_texture_rect(glow, Rect2((Vector2(feet.x, feet.y + 2.0) - gs * 0.5).round(),
				gs), false, Color(1, 1, 1, breathe))
		_token("presence", Vector2(feet.x + drawn.x * 0.5 - 8.0, feet.y - 16.0),
			str(int(place.get("presence", 1))), ArcanaTheme.font())

## A flat elliptical contact shadow: what keeps a standing piece ON the world.
func _ellipse_shadow(at: Vector2, rx: float, ry: float, alpha: float) -> void:
	if alpha <= 0.0: return
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, Color(0.03, 0.02, 0.04, alpha))

## A chunky bevelled stat chip with a live numeral (tools/pixelart/ui_kit.py).
func _token(kind: String, at: Vector2, text: String, f: Font, alert := false) -> void:
	var tex: Texture2D = art.frame("token:%s" % kind) if art != null else null
	var s := 44.0
	if tex != null:
		draw_texture_rect(tex, Rect2((at - Vector2(s, s) * 0.5).round(), Vector2(s, s)),
			false, Color(1.0, 0.80, 0.80) if alert else Color.WHITE)
	else:
		draw_circle(at, s * 0.42, Color(0.1, 0.09, 0.12))
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(f, Vector2(at.x - tw * 0.5, at.y + 6.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.09, 0.07, 0.06))

## A played creature: a living piece standing on its land.
##
## No frame, no window — the sprite stands at its plot's front edge with a
## contact shadow, chunky stat chips at its feet, and posture that tells its
## state: ready pieces breathe, resting pieces settle and dim. During an attack
## the piece itself leaves home (collected into `_emergent` so it draws over
## every other piece), travels, hits, and returns.
func _draw_creature(side: int, index: int, unit: Dictionary, f: Font) -> void:
	var card_id := String(unit["card_id"])
	var colour := card_colour(card_id)
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
			# The defender takes the hit: shove, then a rattling shake.
			var rt: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
			offset += Vector2(act["push"]) * sin(rt * PI) * 22.0
			offset += Vector2(sin(rt * 58.0), 0.0) * (1.0 - rt) * 6.0
			squash *= Vector2(1.0 + 0.10 * (1.0 - rt), 1.0 - 0.10 * (1.0 - rt))
			glow = maxf(glow, 1.0 - rt)

	if scale <= 0.001: return
	var hovered: bool = side == hover_side and index == hover_lane
	var ready: bool = bool(unit.get("ready", true))
	var acting: bool = not beat.is_empty()

	if hovered: offset += Vector2(0.0, -6.0)
	if not ready and not acting:
		# Settled low, a shade dimmer: asleep until its next turn.
		offset += Vector2(0.0, 4.0)
		squash *= Vector2(1.05, 0.93)
	elif ready and not acting:
		# Alive and willing: a slow breath.
		offset.y += sin(_pulse * TAU + float(index) * 1.3 + float(side) * 2.1) * 1.5

	var tint := Color(1, 1, 1, 1)
	if not ready: tint = Color(0.66, 0.66, 0.72, 1.0)
	if glow > 0.4: tint = Color(1.0, 0.88 + 0.12 * (1.0 - glow), 0.88, 1.0)
	if dim_others and not highlights.has("%d,%d" % [side, index]):
		tint = Color(tint.r * 0.55, tint.g * 0.55, tint.b * 0.6, 1.0)

	var tex: Texture2D = art.creature(card_id) if art != null else null
	var stand := creature_stand(side, index)
	var feet := stand + offset
	var out: float = float(beat.get("out", 0.0)) if not beat.is_empty() else 0.0

	if tex == null:
		# Graybox standee while art is missing.
		var box := Rect2(feet - Vector2(44.0, 96.0), Vector2(88.0, 96.0))
		draw_style_box(ArcanaTheme.panel_box(colour.darkened(0.5), colour, 10, 2), box)
		return

	var k3: float = creature_scale(card_id) * scale
	var ts := Vector2(tex.get_width(), tex.get_height())
	var drawn := ts * k3 * squash
	if out <= 0.001:
		# Grounding: shadow, then a soft pool of its element light so even a
		# soot-dark Fire body never sinks into its own scorched land.
		_ellipse_shadow(Vector2(feet.x, feet.y + 2.0), drawn.x * 0.36, 9.0, 0.32 * scale)
		draw_circle(Vector2(feet.x, feet.y - drawn.y * 0.30),
			drawn.x * 0.52, Color(colour, 0.07 + 0.10 * glow))
		var dest := Rect2(Vector2(feet.x - drawn.x * 0.5, feet.y - drawn.y + 6.0).round(),
			drawn.round())
		draw_texture_rect(tex, dest, false, tint)
	else:
		_emergent.append({"tex": tex, "at": Vector2(beat["at"]), "fit": creature_scale(card_id),
			"scale": float(beat["scale"]), "squash": Vector2(beat["squash"]),
			"flip": bool(beat["flip"]), "glow": float(beat["glow"]),
			"colour": colour, "ground": float(beat["ground"])})

	# The numbers it wears: power and health chips at its feet.
	if out <= 0.2 and scale >= 0.95:
		var chip_off: float = minf(drawn.x * 0.5, 46.0)
		var chip_y: float = feet.y - 2.0
		_token("power", Vector2(feet.x - chip_off, chip_y), str(int(unit["power"])), f)
		_token("health", Vector2(feet.x + chip_off, chip_y), str(int(unit["health"])), f,
			int(unit["health"]) < int(unit["max_health"]))
		if not ready:
			var moon: Texture2D = art.frame("chip:resting") if art != null else null
			if moon != null:
				var breathe2: float = 0.65 + 0.25 * sin(_pulse * TAU)
				var ms := Vector2(30.0, 30.0)
				draw_texture_rect(moon, Rect2((Vector2(feet.x + drawn.x * 0.30,
					feet.y - drawn.y - 4.0) - ms * 0.5).round(), ms), false,
					Color(1, 1, 1, breathe2))

	# Name on approach, not as permanent chrome: a small plaque over its head.
	if hovered and out <= 0.001:
		var cname := ArcanaTheme.fit(String(unit["name"]), 13, 150.0)
		var nw: float = f.get_string_size(cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var plq := Rect2(feet.x - nw * 0.5 - 10.0, feet.y - drawn.y - 28.0, nw + 20.0, 22.0)
		draw_style_box(ArcanaTheme.panel_box(Color(0.07, 0.06, 0.09, 0.92), colour, 6, 1), plq)
		draw_string(f, Vector2(plq.position.x + 10.0, plq.position.y + 16.0), cname,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ArcanaTheme.TEXT)

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
		scale = 1.06 + 0.12 * eased
		if stationary:
			# Rears up over its own card and holds — the dragon's beat. It never
			# crosses the board; the breath does that for it.
			var rise: float = -1.0 if side == 0 else 1.0
			at = home + Vector2(0.0, rise * 104.0 * eased)
			scale = 1.12 + 0.22 * eased
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
		scale = 1.0 + 0.16 * back
		if stationary:
			var rise2: float = -1.0 if side == 0 else 1.0
			at = home + Vector2(0.0, rise2 * 104.0 * back)
			scale = 1.12 + 0.22 * back
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

## The attacker leaves its land, meets in the clash space, and returns.
func _defend_offset(act: Dictionary, side: int, index: int) -> Vector2:
	var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
	var home := creature_anchor(side, index)
	var meet := clash_centre(index)
	var step := (meet - home) * 0.28
	return step * sin(clampf(t / 0.6, 0.0, 1.0) * PI)

func _draw_targeting(f: Font) -> void:
	# Legal/attack lanes are lit by _draw_row_zones — the plot itself glows.
	# This pass adds only the dim, the selected piece, previews and chips.
	if dim_others:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.52))
	if selected_lane >= 0:
		var poly := _rounded_poly(plot_rect(0, selected_lane), PLOT_RADIUS, true, true)
		poly.append(poly[0])
		draw_polyline(poly, Color(ArcanaTheme.GOLD, 0.95), 3.0)
	# Placement preview: the selected creature stands as a ghost on the legal
	# lane under the cursor — playing a card reads as placing a piece.
	if ghost_card != "" and hover_side == 0 and hover_lane >= 0 \
			and String(highlights.get("0,%d" % hover_lane, "")) == "legal":
		var gtex: Texture2D = art.creature(ghost_card) if art != null else null
		if gtex != null:
			var gts := Vector2(gtex.get_width(), gtex.get_height()) * creature_scale(ghost_card)
			var gfeet := creature_stand(0, hover_lane)
			_ellipse_shadow(gfeet + Vector2(0.0, 2.0), gts.x * 0.30, 8.0, 0.16)
			draw_texture_rect(gtex, Rect2(Vector2(gfeet.x - gts.x * 0.5,
				gfeet.y - gts.y + 6.0).round(), gts.round()), false,
				Color(1.0, 1.0, 1.0, 0.42 + 0.10 * sin(_pulse * TAU)))
	# Fusion availability is world language: a golden thread of runes arcs
	# between the two creatures that can combine, with the link chip riding
	# its crest. fusion_pairs arrives flat: [a, b, a2, b2, ...].
	var pi_i := 0
	while pi_i + 1 < fusion_pairs.size():
		var ra := card_rect(0, int(fusion_pairs[pi_i]))
		var rb := card_rect(0, int(fusion_pairs[pi_i + 1]))
		pi_i += 2
		var pa := ra.get_center()
		var pb := rb.get_center()
		var apex := pa.lerp(pb, 0.5) + Vector2(0.0, -minf(ra.size.y, rb.size.y) * 0.5 - 18.0)
		var flow: float = fmod(_pulse, 1.0)
		for i in range(11):
			var u: float = (float(i) + flow) / 11.0
			if u > 1.0: u -= 1.0
			# Quadratic arc between the two heads.
			var q := pa.lerp(apex, u).lerp(apex.lerp(pb, u), u)
			draw_circle(q, 2.5 + sin(u * PI) * 1.5,
				Color(ArcanaTheme.GOLD, 0.35 + 0.45 * sin(u * PI)))
		var chip: Texture2D = art.frame("chip:fuse_link") if art != null else null
		var c := apex + Vector2(0.0, -3.0 * sin(_pulse * TAU))
		if chip != null:
			var cs := Vector2(40.0, 40.0)
			draw_texture_rect(chip, Rect2((c - cs * 0.5).round(), cs), false,
				Color(1, 1, 1, 0.85 + 0.15 * sin(_pulse * TAU)))
		else:
			draw_circle(c, 13.0, Color(ArcanaTheme.BG, 0.85))
			draw_arc(c, 13.0, _pulse * TAU, _pulse * TAU + PI * 1.5, 20, ArcanaTheme.GOLD, 2.5)

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
	var a: Vector2 = act["from"] if act.has("from") \
		else sanctuary_rect(int(act.get("side", 0))).get_center()
	var b: Vector2 = _spell_target(act)
	if t < 0.18:
		draw_circle(a, 10.0 + 26.0 * (t / 0.18), Color(colour, 0.35))
		return
	var k: float = clampf((t - 0.18) / 0.44, 0.0, 1.0)
	# The destination is marked for the whole flight, so cause and impact
	# connect even in a single frozen frame.
	draw_arc(b, 26.0 + 5.0 * sin(_pulse * TAU), 0, TAU, 28, Color(colour, 0.75), 2.5)
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
	if bool(act.get("heart", false)) and style not in ["breath", "cast"]:
		# A melee Heart strike: the blow lands at the open lane, and its energy
		# races on across the table into the Sanctuary crystal.
		if t >= 0.44 and t <= 0.72:
			var hk: float = (t - 0.44) / 0.28
			var ha := clash_centre(int(act["lane"]))
			var hb: Vector2 = sanctuary_rect(int(act["target_side"])).get_center()
			var head: Vector2 = ha.lerp(hb, hk)
			for i in range(6):
				var trail: float = maxf(0.0, hk - 0.07 * float(i))
				var tp: Vector2 = ha.lerp(hb, trail)
				draw_circle(tp, 10.0 - float(i) * 1.2,
					Color(ArcanaTheme.HEART, 0.55 * (1.0 - float(i) / 6.0)))
			draw_circle(head, 11.0, Color(ArcanaTheme.HEART, 0.9))
			draw_circle(head, 5.0, Color(1, 1, 1, 0.85))
		return
	if style not in ["breath", "cast"]: return
	if t < 0.30 or t > 0.62: return
	var k: float = clampf((t - 0.30) / 0.32, 0.0, 1.0)
	var a := creature_anchor(int(act["side"]), int(act["lane"]))
	var b: Vector2 = sanctuary_rect(int(act["target_side"])).get_center() if bool(act.get("heart", false)) \
		else creature_anchor(int(act["target_side"]), int(act["lane"]))
	var colour: Color = act["colour"]
	if style == "breath":
		# The breath leaves the RISEN mouth: stationary attackers rear up
		# during the beat (_attack_beat), and a beam drawn from the rest
		# anchor read as firing backwards out of the dragon's feet.
		a.y += -96.0 if int(act["side"]) == 0 else 96.0
	var at: Vector2 = a.lerp(b, k)
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

## Fusion: the signature spectacle, staged on the board itself.
##
## The two source CREATURES (never card frames) lift off their plots and are
## pulled into a midpoint while ribbons wind between them; they collapse into
## a core of light; the result slams down as a black silhouette that floods
## with colour. The result creature's overshoot pop is _draw_creature's fusion
## branch — this act sells convergence, collapse and reveal.
func _draw_fusion(act: Dictionary, t: float, f: Font) -> void:
	var side := int(act["side"])
	var lane_a := int(act["lane"])
	var lane_b := int(act["freed_lane"])
	var a := creature_stand(side, lane_a)
	var b := creature_stand(side, lane_b)
	var target := creature_anchor(side, lane_a)
	var colour: Color = act["colour"]

	if t < 0.84:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45 * clampf(t / 0.18, 0.0, 1.0)))

	if t < 0.62:
		# Lift and converge: the creatures themselves are pulled together.
		var k: float = t / 0.62
		var eased: float = k * k * (3.0 - 2.0 * k)
		var mid := a.lerp(b, 0.5) + Vector2(0.0, -46.0 * sin(eased * PI * 0.9) - 30.0)
		var pa := a.lerp(mid, eased)
		var pb := b.lerp(mid, eased)
		var spin: float = eased * TAU * 1.2
		# Ribbons winding between the two.
		for i in range(14):
			var u: float = float(i) / 14.0
			var p0 := pa.lerp(pb, u)
			var p1 := pa.lerp(pb, u + 0.075)
			var wob: float = sin(u * PI * 3.0 + spin) * 26.0 * (1.0 - eased * 0.5)
			draw_line(p0 + Vector2(0.0, wob), p1 + Vector2(0.0, wob * 0.8),
				Color(colour, 0.30 + 0.55 * sin((u + t) * PI * 3.0)), 3.0)
		var source: Dictionary = act.get("cards", {})
		for pair in [[pa, lane_a, a], [pb, lane_b, b]]:
			var at: Vector2 = pair[0]
			var lane_i: int = int(pair[1])
			var from: Vector2 = pair[2]
			var cid := String(source.get(str(lane_i), ""))
			var tex: Texture2D = art.creature(cid) if (art != null and cid != "") else null
			if tex == null:
				draw_circle(at, 26.0, Color(colour, 0.8))
				continue
			var ts := Vector2(tex.get_width(), tex.get_height())
			var toward := (mid - from).normalized()
			# Stretch along the pull, squash across it: taffy into the ritual.
			var stretch: float = 1.0 + 0.55 * eased
			var drawn := ts * creature_scale(cid) * (1.0 - 0.22 * eased)
			drawn = Vector2(drawn.x / sqrt(stretch), drawn.y * stretch) \
				if absf(toward.y) > absf(toward.x) \
				else Vector2(drawn.x * stretch, drawn.y / sqrt(stretch))
			draw_circle(at, drawn.x * 0.45, Color(colour, 0.16 * eased))
			draw_texture_rect(tex, Rect2((at - drawn * 0.5).round(), drawn.round()), false,
				Color(1.0 + eased * 0.4, 1.0 + eased * 0.4, 1.0 + eased * 0.4, 1.0))
		draw_circle(mid, 8.0 + 54.0 * eased * eased, Color(1, 1, 1, 0.20 + 0.65 * eased * eased))
	elif t < 0.78:
		# Collapse into light.
		var k2: float = (t - 0.62) / 0.16
		draw_circle(target, 66.0 * (1.0 - k2) + 22.0, Color(1, 1, 1, 0.88 * (1.0 - k2)))
		draw_arc(target, 44.0 + 130.0 * k2, 0, TAU, 44, Color(colour, 1.0 - k2), 5.0)
	else:
		# Reveal: the new creature lands as a silhouette and floods with colour;
		# a shockwave rolls across the board.
		var k3: float = (t - 0.78) / 0.22
		var unit = engine.lane(side, lane_a)["creature"]
		if unit != null and k3 < 0.4 and art != null:
			var tex2: Texture2D = art.creature(String(unit["card_id"]))
			if tex2 != null:
				var ts2 := Vector2(tex2.get_width(), tex2.get_height())
				var d2 := ts2 * creature_scale(String(unit["card_id"])) * (1.15 - 0.15 * k3 / 0.4)
				var feet := creature_stand(side, lane_a)
				var sil: float = clampf(1.0 - k3 / 0.4, 0.0, 1.0)
				draw_texture_rect(tex2, Rect2(Vector2(feet.x - d2.x * 0.5,
					feet.y - d2.y + 6.0).round(), d2.round()), false,
					Color(1.0 - sil * 0.94, 1.0 - sil * 0.96, 1.0 - sil * 0.95, 1.0))
		draw_arc(target, 34.0 + 260.0 * k3, 0, TAU, 48,
			Color(ArcanaTheme.GOLD, 0.8 * (1.0 - k3)), 6.0 * (1.0 - k3) + 1.0)
		draw_arc(target, 20.0 + 190.0 * k3, 0, TAU, 48, Color(colour, 0.5 * (1.0 - k3)), 3.0)
		var fname := String(act.get("name", ""))
		var w: float = f.get_string_size(fname, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var ny: float = creature_stand(side, lane_a).y - 150.0 - 10.0 * k3
		if fname != "":
			draw_rect(Rect2(target.x - w * 0.5 - 12.0, ny - 20.0, w + 24.0, 30.0),
				Color(0.07, 0.06, 0.09, 0.85 * (1.0 - k3 * k3)))
			draw_string(f, Vector2(target.x - w * 0.5, ny + 2.0), fname,
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
