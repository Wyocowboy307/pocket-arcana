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

const SANCT_H := 104.0
const PLOT_H := 122.0
const CLASH_H := 92.0
const PLOT_W := 236.0
const PLOT_OVERLAP := 26.0            # plots overlap so a realm reads as one mass

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
var _scatter: Array = []             # per-plot decoration, built once
var _scatter_for := Vector2.ZERO
var _pulse := 0.0
var _shake := 0.0
var _hitstop := 0.0

func _ready() -> void:
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

func _field_width() -> float:
	return PLOT_W * MatchV2.LANES - PLOT_OVERLAP * (MatchV2.LANES - 1)

func _origin() -> Vector2:
	var total_h: float = SANCT_H * 2.0 + PLOT_H * 2.0 + CLASH_H
	var jitter := Vector2.ZERO
	if _shake > 0.0:
		jitter = Vector2(sin(_shake * 41.0), cos(_shake * 33.0)) * _shake * 4.0
	return Vector2((size.x - _field_width()) * 0.5, (size.y - total_h) * 0.5) + jitter

## The ground a lane owns. Not drawn as a rectangle — this is just its extent.
func lane_rect(side: int, index: int) -> Rect2:
	var o := _origin()
	var x: float = o.x + index * (PLOT_W - PLOT_OVERLAP)
	var y: float = o.y + SANCT_H if side == 1 else o.y + SANCT_H + PLOT_H + CLASH_H
	return Rect2(x, y, PLOT_W, PLOT_H)

func sanctuary_rect(side: int) -> Rect2:
	var o := _origin()
	var y: float = o.y if side == 1 else o.y + SANCT_H + PLOT_H * 2.0 + CLASH_H
	return Rect2(o.x, y, _field_width(), SANCT_H)

## Creatures stand at the front edge of their land, facing across the clash.
func creature_anchor(side: int, index: int) -> Vector2:
	var r := lane_rect(side, index)
	return Vector2(r.get_center().x, r.position.y + (r.size.y - 30.0 if side == 1 else 34.0))

## Places sit at the rear of the same land, behind their creature.
func place_anchor(side: int, index: int) -> Vector2:
	var r := lane_rect(side, index)
	return Vector2(r.position.x + 56.0, r.position.y + (32.0 if side == 1 else r.size.y - 28.0))

## Where the two sides actually meet.
func clash_centre(index: int) -> Vector2:
	var o := _origin()
	return Vector2(lane_rect(0, index).get_center().x, o.y + SANCT_H + PLOT_H + CLASH_H * 0.5)

func front_line_y() -> float:
	return clash_centre(0).y

func deck_anchor(side: int) -> Vector2:
	var r := sanctuary_rect(side)
	return Vector2(r.get_center().x + 200.0, r.get_center().y)

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
			if _at(act, "portal", 0.22): burst(at2, Color(act["colour"]), 12, "spark", 0.8)
			if _at(act, "pop", 0.55):
				cue.emit("summon", 1.0)
				burst(at2, Color(act["colour"]), 16,
					"leaf" if String(act.get("element", "")) == "life" else "ember", 1.0)
				shake(0.32)
		"place_build":
			var at3: Vector2 = place_anchor(int(act["side"]), int(act["lane"]))
			if _at(act, "found", 0.18): burst(at3, Color(act["colour"]), 8, "spark", 0.5)
			if _at(act, "rise", 0.58): shake(0.26)
			if _at(act, "click", 0.86):
				cue.emit("place_done", 1.0)
				burst(at3, Color(act["colour"]), 12, "spark", 0.7)
		"spell":
			if _at(act, "impact", 0.62):
				cue.emit("spell_hit", 1.0)
				burst(_spell_target(act), Color(act["colour"]), 16, "spark", 1.1)
				shake(0.45); hitstop(0.05)
		"attack":
			if _at(act, "impact", 0.50):
				cue.emit("hit", float(act.get("weight", 0.6)))
				burst(clash_centre(int(act["lane"])), Color(act["colour"]), 18, "spark", 1.3)
				shake(float(act.get("weight", 0.6))); hitstop(0.06)
		"heart_attack":
			if _at(act, "impact", 0.58):
				cue.emit("heart_hit", 1.5)
				burst(sanctuary_rect(int(act["target_side"])).get_center(), ArcanaTheme.HEART, 26, "spark", 1.7)
				play("heart_shock", {"side": int(act["target_side"])}, 0.55)
				shake(1.25); hitstop(0.09)
		"death":
			if _at(act, "burst", 0.28):
				burst(act["at"], Color(act["colour"]), 14, "spark", 0.8)
		"fusion":
			var at4: Vector2 = creature_anchor(int(act["side"]), int(act["lane"]))
			if _at(act, "lift", 0.12): shake(0.2)
			if _at(act, "core", 0.62): burst(at4, ArcanaTheme.GOLD, 22, "spark", 1.2); hitstop(0.06)
			if _at(act, "slam", 0.78):
				cue.emit("fusion_slam", 1.6)
				burst(at4, Color(act["colour"]), 28,
					"leaf" if String(act.get("element", "")) == "life" else "ember", 1.7)
				shake(1.3); hitstop(0.10)
		"commander":
			if _at(act, "flourish", 0.35): burst(act["from"], ArcanaTheme.GOLD, 18, "spark", 1.0)
			if _at(act, "land", 0.70):
				burst(act["to"], ArcanaTheme.GOLD, 14, "spark", 1.0)
				shake(0.6)

func _spell_target(act: Dictionary) -> Vector2:
	if int(act.get("lane", -1)) >= 0:
		return creature_anchor(int(act["target_side"]), int(act["lane"]))
	return sanctuary_rect(int(act.get("target_side", 0))).get_center()

# --- world drawing ----------------------------------------------------------

func _draw() -> void:
	if engine == null or engine.players.is_empty(): return
	var f := ArcanaTheme.font()
	if _scatter_for != size: _build_scatter()

	_draw_backdrop()
	for side in range(2):
		_draw_realm_ground(side)        # one connected realm, not four plots
	_draw_clash_space(f)
	for side in range(2):
		_draw_sanctuary(side, f)
	# Pieces last, so nothing paints over a creature.
	for side in range(2):
		for i in range(MatchV2.LANES):
			var l: Dictionary = engine.lane(side, i)
			if l["place"] != null: _draw_place(side, i, l["place"])
			if l["place"] != null and l["creature"] != null: _draw_support_link(side, i, l["place"])
	for side in range(2):
		for i in range(MatchV2.LANES):
			var l2: Dictionary = engine.lane(side, i)
			if l2["creature"] != null: _draw_creature(side, i, l2["creature"], f)
	_draw_targeting(f)
	_draw_acts(f)
	_draw_particles()

## Sky above the far realm, warm ground light near ours.
## Sky above the far realm, warmer ground light near ours.
func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ArcanaTheme.BG)
	var o := _origin()
	var total_h: float = SANCT_H * 2.0 + PLOT_H * 2.0 + CLASH_H
	var slices := 44
	for i in range(slices):
		var t := float(i) / float(slices - 1)
		var y0: float = o.y - 24.0 + total_h * (float(i) / float(slices)) * 1.08
		var y1: float = o.y - 24.0 + total_h * (float(i + 1) / float(slices)) * 1.08
		draw_rect(Rect2(0.0, y0, size.x, y1 - y0 + 1.0),
			Color(0.115, 0.135, 0.170).lerp(Color(0.150, 0.160, 0.130), t))

## The band of ground a player's whole realm occupies.
func _realm_band(side: int) -> Rect2:
	var first := lane_rect(side, 0)
	var last := lane_rect(side, MatchV2.LANES - 1)
	return Rect2(first.position.x - 34.0, first.position.y - 6.0,
		last.position.x + last.size.x + 34.0 - (first.position.x - 34.0), first.size.y + 12.0)

## One connected realm, not four plots. Untamed ground everywhere, with built
## terrain blended over it so neighbouring lands of the same element merge into
## a single landscape.
func _draw_realm_ground(side: int) -> void:
	var band := _realm_band(side)
	_draw_wildland(side, band)

	# Group neighbouring lanes that share an element, and paint each run as one
	# feathered region. This is what makes a realm read as a place.
	var lane_index := 0
	while lane_index < MatchV2.LANES:
		var terrain := String(engine.lane(side, lane_index)["land"])
		if terrain == "":
			lane_index += 1
			continue
		var run_end := lane_index
		while run_end + 1 < MatchV2.LANES and String(engine.lane(side, run_end + 1)["land"]) == terrain:
			run_end += 1
		_draw_terrain_run(side, lane_index, run_end, terrain, band)
		lane_index = run_end + 1

	for i in range(MatchV2.LANES):
		var t2 := String(engine.lane(side, i)["land"])
		if t2 != "": _draw_growth(side, i, t2)

## Untamed land: scrub grass, stones and dead branches, so an unbuilt board still
## looks like somewhere rather than a void.
func _draw_wildland(side: int, band: Rect2) -> void:
	var pts := PackedVector2Array()
	var steps := 40
	for i in range(steps + 1):
		var fx: float = float(i) / float(steps)
		pts.append(Vector2(band.position.x + fx * band.size.x,
			band.position.y + (_vhash(side * 17 + i, 401) - 0.5) * 11.0))
	for i in range(steps + 1):
		var fx2: float = 1.0 - float(i) / float(steps)
		pts.append(Vector2(band.position.x + fx2 * band.size.x,
			band.position.y + band.size.y + (_vhash(side * 23 + i, 457) - 0.5) * 11.0))
	draw_colored_polygon(pts, Color(0.196, 0.204, 0.165))
	for item in _scatter[side]:
		var at := Vector2(band.position.x + float(item["u"]) * band.size.x,
						  band.position.y + 10.0 + float(item["v"]) * (band.size.y - 20.0))
		var sc: float = float(item["size"])
		match int(item["kind"]):
			0:
				var lean: float = (float(item["tilt"]) - 0.5) * 5.0
				draw_line(at, at + Vector2(lean, -7.0 * sc), Color(0.30, 0.35, 0.24), 2.0)
				draw_line(at, at + Vector2(lean - 3.0, -5.0 * sc), Color(0.26, 0.31, 0.21), 1.5)
			1:
				draw_circle(at, 2.8 * sc, Color(0.31, 0.30, 0.27))
				draw_circle(at - Vector2(0.8, 1.0), 1.4 * sc, Color(0.38, 0.37, 0.33))
			_:
				draw_line(at, at + Vector2(6.0 * sc, -2.0 * sc), Color(0.27, 0.24, 0.19), 2.0)

## A run of same-element lanes as one chunky cut-out slab of world: bright top
## surface, a thick dark rim, and a side face so it reads as a physical piece of
## board you could pick up. Deliberately hard-edged — soft blending was reading
## as an atmospheric strip rather than a bold biome.
func _draw_terrain_run(side: int, from_lane: int, to_lane: int, terrain: String, band: Rect2) -> void:
	var left := lane_rect(side, from_lane)
	var right := lane_rect(side, to_lane)
	var grow := 1.0
	for i in range(from_lane, to_lane + 1):
		var act := _find_act("land_build", side, i)
		if not act.is_empty():
			grow = minf(grow, clampf(float(act["t"]) / float(act["dur"]) / 0.72, 0.0, 1.0))

	var x0: float = left.position.x - 16.0
	var x1: float = right.position.x + right.size.x + 16.0
	var top: float = band.position.y + 6.0
	var bottom: float = band.position.y + band.size.y - 14.0
	if grow < 1.0:
		var eased: float = 1.0 - pow(1.0 - grow, 3.0)
		var cx: float = (x0 + x1) * 0.5
		var cy: float = (top + bottom) * 0.5
		x0 = cx + (x0 - cx) * eased; x1 = cx + (x1 - cx) * eased
		top = cy + (top - cy) * eased; bottom = cy + (bottom - cy) * eased

	# Chunky hand-cut outline: few points, big steps.
	var seed_base := side * 991 + from_lane * 37
	var surface := PackedVector2Array()
	var steps := maxi(6, int((x1 - x0) / 74.0))
	for i in range(steps + 1):
		var fx: float = float(i) / float(steps)
		surface.append(Vector2(lerpf(x0, x1, fx),
			top + (_vhash(seed_base + i, 401) - 0.5) * 18.0))
	for i in range(steps + 1):
		var fx2: float = 1.0 - float(i) / float(steps)
		surface.append(Vector2(lerpf(x0, x1, fx2),
			bottom + (_vhash(seed_base + i, 457) - 0.5) * 16.0))

	var tex: Texture2D = art.terrain(terrain) if art != null else null
	var tint: Color = ArcanaTheme.color_for_terrain(terrain)
	# Side face first, so the slab has thickness under its front edge.
	var face := PackedVector2Array()
	var depth := 16.0
	for i in range(steps + 1):
		var fx3: float = float(i) / float(steps)
		face.append(Vector2(lerpf(x0, x1, fx3),
			bottom + (_vhash(seed_base + (steps - i), 457) - 0.5) * 16.0))
	for i in range(steps + 1):
		var fx4: float = 1.0 - float(i) / float(steps)
		face.append(Vector2(lerpf(x0, x1, fx4),
			bottom + depth + (_vhash(seed_base + i, 509) - 0.5) * 8.0))
	draw_colored_polygon(face, tint.darkened(0.72))

	if tex != null:
		var uvs := PackedVector2Array()
		var tile := Vector2(float(tex.get_width()), float(tex.get_height())) * 1.35
		for p in surface: uvs.append(Vector2(p.x / tile.x, p.y / tile.y))
		var cols := PackedColorArray()
		for p in surface: cols.append(Color(1.06, 1.06, 1.02, 1.0))   # a little lift, not a wash
		draw_polygon(surface, cols, uvs, tex)
	else:
		draw_colored_polygon(surface, tint.darkened(0.30))
	# Thick rim: the single biggest "toy board" cue.
	draw_polyline(surface + PackedVector2Array([surface[0]]), Color(0.07, 0.06, 0.05, 0.95), 5.0)
	draw_polyline(face + PackedVector2Array([face[0]]), Color(0.07, 0.06, 0.05, 0.95), 4.0)
	# A lit lip along the top edge so the slab catches light.
	for i in range(steps):
		draw_line(surface[i], surface[i + 1], Color(tint.lightened(0.35), 0.55), 2.5)

func _edge_falloff(x: float, x0: float, x1: float, feather: float) -> float:
	var left: float = clampf((x - x0) / feather, 0.0, 1.0)
	var right: float = clampf((x1 - x) / feather, 0.0, 1.0)
	var k: float = minf(left, right)
	return k * k * (3.0 - 2.0 * k)

## Bold props, outlined like board pieces. This is what turns a textured patch
## into a recognisable biome — a Grove has mushrooms and stumps, a Cinder field
## has fire pits and burnt trunks.
func _draw_growth(side: int, index: int, terrain: String) -> void:
	var r := lane_rect(side, index)
	var act := _find_act("land_build", side, index)
	var grow := 1.0
	if not act.is_empty(): grow = clampf(float(act["t"]) / float(act["dur"]) / 0.80, 0.0, 1.0)
	var life := terrain == "grove" or terrain == "ashbloom"
	var band := _realm_band(side)
	# Props hug the back of the plot so creatures keep the front edge clear.
	var back_y: float = band.position.y + (band.size.y - 30.0 if side == 0 else 22.0)
	var items: Array = _scatter[2 + side * MatchV2.LANES + index]
	for n in range(min(5, items.size())):
		var item: Dictionary = items[n]
		if float(item["u"]) > grow: continue
		var at := Vector2(r.position.x + 20.0 + float(item["u"]) * (r.size.x - 40.0),
						  back_y + (float(item["v"]) - 0.5) * 34.0)
		var sc: float = 0.85 + 0.5 * float(item["size"])
		if life: _grove_prop(at, sc, int(item["kind"]), float(item["tilt"]))
		else: _cinder_prop(at, sc, int(item["kind"]), float(item["tilt"]))

const INK := Color(0.07, 0.06, 0.05, 0.95)

func _grove_prop(at: Vector2, sc: float, kind: int, tilt: float) -> void:
	match kind:
		0:
			# Fat mushroom with a chunky cap.
			var h: float = 13.0 * sc
			draw_line(at, at + Vector2(0, -h), Color("#e8dcc0"), 6.0 * sc)
			draw_line(at, at + Vector2(0, -h), INK, 8.0 * sc * 0.35)
			var cap := at + Vector2(0, -h)
			draw_circle(cap, 11.0 * sc, INK)
			draw_circle(cap, 9.0 * sc, Color("#e0556a"))
			draw_circle(cap + Vector2(-3.0 * sc, -2.0 * sc), 2.5 * sc, Color("#fff1d6"))
			draw_circle(cap + Vector2(4.0 * sc, 1.0 * sc), 2.0 * sc, Color("#fff1d6"))
		1:
			# Bushy clump.
			for i in range(3):
				var o := Vector2((float(i) - 1.0) * 8.0 * sc, -float(i % 2) * 5.0 * sc)
				draw_circle(at + o, 10.0 * sc, INK)
				draw_circle(at + o, 8.0 * sc, Color("#57913f"))
			draw_circle(at + Vector2(2.0 * sc, -6.0 * sc), 3.0 * sc, Color("#f2c7dd"))
		_:
			# Stump with rings and a sprout.
			var w: float = 12.0 * sc
			var h2: float = 11.0 * sc
			draw_rect(Rect2(at - Vector2(w, h2), Vector2(w * 2.0, h2)), INK)
			draw_rect(Rect2(at - Vector2(w - 2.0, h2 - 2.0), Vector2(w * 2.0 - 4.0, h2 - 2.0)),
				Color("#7a5a3a"))
			draw_circle(at + Vector2(0, -h2), w - 2.0, Color("#a1794f"))
			draw_arc(at + Vector2(0, -h2), (w - 2.0) * 0.55, 0, TAU, 14, Color("#7a5a3a"), 2.0)
			draw_line(at + Vector2(3.0 * sc, -h2), at + Vector2(6.0 * sc, -h2 - 10.0 * sc),
				Color("#6fae4f"), 3.0)

func _cinder_prop(at: Vector2, sc: float, kind: int, tilt: float) -> void:
	match kind:
		0:
			# Burnt trunk, snapped off.
			var h: float = 20.0 * sc
			var lean: float = (tilt - 0.5) * 8.0
			draw_line(at, at + Vector2(lean, -h), INK, 9.0 * sc)
			draw_line(at, at + Vector2(lean, -h), Color("#3a2c26"), 6.0 * sc)
			draw_line(at + Vector2(lean, -h * 0.6), at + Vector2(lean + 9.0 * sc, -h * 0.85),
				Color("#3a2c26"), 4.0 * sc)
			draw_circle(at + Vector2(lean, -h), 3.0 * sc, Color("#ff8a3d", 0.8))
		1:
			# Fire pit: ring of stones with a flame in it.
			for i in range(7):
				var a: float = TAU * float(i) / 7.0
				var p := at + Vector2(cos(a), sin(a) * 0.45) * 13.0 * sc
				draw_circle(p, 4.5 * sc, INK)
				draw_circle(p, 3.2 * sc, Color("#4a423e"))
			var flick: float = 0.6 + 0.4 * sin(_pulse * TAU * 2.4 + tilt * 8.0)
			draw_circle(at + Vector2(0, -4.0 * sc), 7.0 * sc * flick, Color("#ff7a2f"))
			draw_circle(at + Vector2(0, -7.0 * sc), 4.0 * sc * flick, Color("#ffd98a"))
			draw_circle(at + Vector2(0, -4.0 * sc), 15.0 * sc, Color(1.0, 0.5, 0.15, 0.10 * flick))
		_:
			# Cracked boulder with a glowing seam.
			var w: float = 13.0 * sc
			draw_circle(at, w, INK)
			draw_circle(at - Vector2(0, 1.5), w - 2.5, Color("#3d3733"))
			draw_line(at + Vector2(-w * 0.4, -w * 0.3), at + Vector2(w * 0.3, w * 0.35),
				Color("#ff8a3d", 0.75), 2.5)

func _build_scatter() -> void:
	_scatter.clear()
	# Two wildland sets, then one growth set per lane per side.
	for side in range(2):
		var wild: Array = []
		for i in range(120):
			var sv := side * 977 + i
			wild.append({"u": _vhash(sv, 5), "v": _vhash(sv, 13),
				"kind": int(_vhash(sv, 19) * 3.0), "size": 0.7 + 0.7 * _vhash(sv, 27),
				"tilt": _vhash(sv, 33)})
		_scatter.append(wild)
	for side in range(2):
		for lane in range(MatchV2.LANES):
			var items: Array = []
			for i in range(30):
				var seed_value := side * 733 + lane * 131 + i
				items.append({"u": _vhash(seed_value, 3), "v": _vhash(seed_value, 11),
					"kind": int(_vhash(seed_value, 17) * 3.0),
					"size": 0.7 + 0.7 * _vhash(seed_value, 23), "tilt": _vhash(seed_value, 29)})
			_scatter.append(items)
	_scatter_for = size

## The middle of the board: a deliberate arena where the two realms collide.
## Stone-kerbed on both sides, scarred from previous fights, with a marker at
## each lane so it is obvious where an attack will land.
func _draw_clash_space(f: Font) -> void:
	var o := _origin()
	var top: float = o.y + SANCT_H + PLOT_H
	var band := Rect2(o.x - 44.0, top, _field_width() + 88.0, CLASH_H)

	var ground := PackedVector2Array()
	var steps := 22
	for i in range(steps + 1):
		var fx: float = float(i) / float(steps)
		ground.append(Vector2(band.position.x + fx * band.size.x,
			band.position.y + (_vhash(i, 611) - 0.5) * 10.0))
	for i in range(steps + 1):
		var fx2: float = 1.0 - float(i) / float(steps)
		ground.append(Vector2(band.position.x + fx2 * band.size.x,
			band.position.y + band.size.y + (_vhash(i, 733) - 0.5) * 10.0))
	draw_colored_polygon(ground, Color(0.128, 0.120, 0.108))

	# Scars, rubble and old scorch marks.
	for i in range(60):
		var u := _vhash(i, 91)
		var v := _vhash(i, 137)
		var at := Vector2(band.position.x + u * band.size.x,
						  band.position.y + 10.0 + v * (band.size.y - 20.0))
		var tone: float = _vhash(i, 53)
		if tone > 0.86:
			draw_circle(at, 5.0 + 4.0 * tone, Color(0.075, 0.065, 0.055, 0.85))
			draw_circle(at + Vector2(1.0, -1.0), 3.0 + 2.0 * tone, Color(0.20, 0.16, 0.13, 0.6))
		elif tone > 0.55:
			draw_circle(at, 2.0 + 3.0 * tone, Color(0.21, 0.20, 0.17, 0.9))
		else:
			draw_line(at, at + Vector2(7.0 + 8.0 * tone, 2.0), Color(0.09, 0.08, 0.07, 0.8), 2.5)

	# Kerb stones down both sides of the arena.
	for edge in [band.position.y + 2.0, band.position.y + band.size.y - 2.0]:
		var n := int(band.size.x / 34.0)
		for i in range(n):
			var x: float = band.position.x + 12.0 + float(i) * 34.0
			var w: float = 12.0 + 5.0 * _vhash(i, 313)
			var h: float = 7.0 + 3.0 * _vhash(i, 421)
			draw_rect(Rect2(x - w * 0.5, edge - h * 0.5, w, h), Color(0.07, 0.06, 0.05))
			draw_rect(Rect2(x - w * 0.5 + 1.5, edge - h * 0.5 + 1.5, w - 3.0, h - 3.0),
				Color(0.30, 0.28, 0.25))

	# A totem at each lane meeting point, lit when that lane is open to the Heart.
	for index in range(MatchV2.LANES):
		var c := clash_centre(index)
		var open: bool = engine.lane(1, index)["creature"] == null
		var wave: float = 0.5 + 0.5 * sin(_pulse * TAU + float(index) * 0.7)
		var tint: Color = ArcanaTheme.HEART if open else Color(0.34, 0.32, 0.29)
		# Post with a ring on top.
		draw_line(Vector2(c.x, c.y + 16.0), Vector2(c.x, c.y - 14.0), Color(0.07, 0.06, 0.05), 7.0)
		draw_line(Vector2(c.x, c.y + 16.0), Vector2(c.x, c.y - 14.0), Color(0.28, 0.24, 0.20), 4.0)
		draw_circle(Vector2(c.x, c.y - 18.0), 8.0, Color(0.07, 0.06, 0.05))
		draw_circle(Vector2(c.x, c.y - 18.0), 6.0, Color(tint, 0.75 + 0.25 * wave))
		draw_circle(Vector2(c.x, c.y + 16.0), 9.0, Color(0.09, 0.08, 0.07, 0.6))
		if open:
			draw_circle(Vector2(c.x, c.y - 18.0), 14.0, Color(tint, 0.12 * wave))
			for k in range(4):
				var t := float(k) / 4.0
				draw_circle(Vector2(c.x, c.y - 26.0 - t * 22.0), 2.5 - t,
					Color(tint, (0.28 - t * 0.20) * (0.6 + 0.4 * wave)))

## A built home place behind the realm, not a status bar.
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

	# The base itself: a broad mound of home ground, wider in the middle.
	# A raised platform, wider at the front, so it reads as a built place.
	var mw: float = 470.0
	var mound := Rect2(r.get_center().x - mw * 0.5 + nudge.x, r.position.y + 10.0 + nudge.y,
		mw, r.size.y - 20.0)
	var cx: float = mound.get_center().x
	var top: float = mound.position.y
	var bottom: float = mound.position.y + mound.size.y
	var back: float = mw * 0.80
	var deck_face := 12.0
	var top_face := PackedVector2Array()
	for i in range(9):
		var fx: float = float(i) / 8.0
		top_face.append(Vector2(cx - back * 0.5 + back * fx,
			top + (_vhash(side * 31 + i, 7) - 0.5) * 4.0))
	for i in range(9):
		var fx2: float = 1.0 - float(i) / 8.0
		top_face.append(Vector2(cx - mw * 0.5 + mw * fx2,
			bottom - deck_face + (_vhash(side * 47 + i, 11) - 0.5) * 4.0))
	var stone: Color = accent.darkened(0.70).lerp(ArcanaTheme.HEART, hurt * 0.4)
	draw_colored_polygon(top_face, stone)
	# The lip of the platform, so it has thickness.
	var lip := PackedVector2Array([
		Vector2(cx - mw * 0.5, bottom - deck_face), Vector2(cx + mw * 0.5, bottom - deck_face),
		Vector2(cx + mw * 0.5 - 10.0, bottom), Vector2(cx - mw * 0.5 + 10.0, bottom)])
	draw_colored_polygon(lip, stone.darkened(0.35))
	draw_polyline(top_face, Color(accent, 0.40 + 0.25 * breathe), 2.0)
	# Steps down to the field.
	for i in range(3):
		var inset: float = 40.0 + float(i) * 26.0
		draw_line(Vector2(cx - mw * 0.5 + inset, bottom - 3.0 + float(i) * 1.5),
			Vector2(cx + mw * 0.5 - inset, bottom - 3.0 + float(i) * 1.5),
			Color(stone.darkened(0.2), 0.9), 3.0)
	if element == "life": _draw_life_home(mound, accent, breathe)
	else: _draw_fire_home(mound, accent, breathe)

	var mid_y: float = mound.get_center().y
	# Shrine at the heart of the base.
	var shrine_x: float = mound.get_center().x
	var tex: Texture2D = art.sanctuary(element) if art != null else null
	if tex != null:
		var src := Vector2(tex.get_width(), tex.get_height())
		var sc: float = (mound.size.y - 8.0) / src.y
		var drawn := src * sc
		draw_circle(Vector2(shrine_x, mound.position.y + mound.size.y - 8.0),
			drawn.x * 0.30, Color(0, 0, 0, 0.28))
		draw_circle(Vector2(shrine_x, mid_y), drawn.y * 0.55, Color(accent, 0.07 + 0.05 * breathe))
		draw_texture_rect(tex, Rect2(Vector2(shrine_x - drawn.x * 0.5,
			mound.position.y + mound.size.y - drawn.y - 4.0), drawn), false)

	# Commander standing in front of their own base.
	var avatar: Texture2D = art.commander_board(String(p["commander_id"])) if art != null else null
	var ax: float = shrine_x - 96.0
	if avatar != null:
		var asrc := Vector2(avatar.get_width(), avatar.get_height())
		var asc: float = (mound.size.y - 14.0) / asrc.y
		var adr := asrc * asc
		var lift := 0.0
		for act in _acts:
			if String(act["kind"]) == "commander" and int(act.get("side", -1)) == side:
				lift = sin(clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0) * PI) * 14.0
		draw_circle(Vector2(ax, mound.position.y + mound.size.y - 10.0), adr.x * 0.26, Color(0, 0, 0, 0.26))
		draw_texture_rect(avatar, Rect2(Vector2(ax - adr.x * 0.5,
			mound.position.y + mound.size.y - adr.y - 6.0 - lift), adr), false)

	# Compact Heart crystal attached to the base.
	var heart := int(p["heart"])
	var frac: float = clampf(float(heart) / float(MatchV2.HEART_START), 0.0, 1.0)
	var hc := Vector2(shrine_x + 96.0, mid_y)
	var rad: float = 20.0 * (1.0 + 0.05 * sin(_pulse * TAU * (2.4 if frac < 0.35 else 1.2)))
	draw_circle(hc, rad * 1.5, Color(ArcanaTheme.HEART, 0.07 + 0.05 * breathe))
	var facets := PackedVector2Array([hc + Vector2(0, -rad), hc + Vector2(rad * 0.76, 0),
		hc + Vector2(0, rad), hc + Vector2(-rad * 0.76, 0)])
	draw_colored_polygon(facets, Color(0.10, 0.04, 0.08, 0.95))
	var fill_top: float = hc.y + rad - 2.0 * rad * frac
	var filled := PackedVector2Array()
	for i in range(facets.size()):
		var a: Vector2 = facets[i]
		var b: Vector2 = facets[(i + 1) % facets.size()]
		if a.y >= fill_top: filled.append(a)
		if (a.y < fill_top) != (b.y < fill_top):
			filled.append(a.lerp(b, (fill_top - a.y) / (b.y - a.y)))
	if filled.size() >= 3: draw_colored_polygon(filled, Color(ArcanaTheme.HEART, 0.9))
	draw_polyline(PackedVector2Array([facets[0], facets[1], facets[2], facets[3], facets[0]]),
		Color(ArcanaTheme.HEART, 0.95), 2.0)
	var hw: float = f.get_string_size(str(heart), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(f, Vector2(hc.x - hw * 0.5, hc.y + 6.0), str(heart),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ArcanaTheme.TEXT)

	# Aether orbs tucked under the crystal.
	var px: float = hc.x - 30.0
	var py: float = hc.y + rad + 12.0
	for i in range(int(p["max_aether"])):
		var at := Vector2(px + i * 15.0, py)
		if i < int(p["aether"]):
			draw_circle(at, 8.0, Color(ArcanaTheme.AETHER, 0.20))
			draw_circle(at, 5.0, ArcanaTheme.AETHER)
		else:
			draw_arc(at, 5.0, 0, TAU, 14, Color(ArcanaTheme.PANEL_EDGE, 0.9), 2.0)

	# Deck, so drawing has a visible source.
	var deck := deck_anchor(side)
	for i in range(3):
		var off := Vector2(float(i) * 1.6, float(i) * 1.6)
		draw_style_box(ArcanaTheme.panel_box(ArcanaTheme.PANEL.darkened(0.1 * float(i)),
			Color(accent, 0.5), 4, 1), Rect2(deck - Vector2(15, 22) + off, Vector2(30, 44)))
	draw_string(f, deck - Vector2(8, -4), str(p["deck"].size()),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT_DIM)

## A living tree-and-garden home: trunks, canopy, hanging lanterns, flower beds.
func _draw_life_home(mound: Rect2, accent: Color, breathe: float) -> void:
	var base_y: float = mound.position.y + mound.size.y - 14.0
	for i in range(4):
		# Two trees a side, framing the middle of the platform.
		var slot: float = [0.06, 0.20, 0.80, 0.94][i]
		var tx: float = mound.position.x + slot * mound.size.x
		var h: float = 30.0 + 9.0 * _vhash(i, 71)
		# Trunk.
		draw_line(Vector2(tx, base_y), Vector2(tx + (_vhash(i, 5) - 0.5) * 8.0, base_y - h),
			Color("#4a3a2a"), 7.0)
		# Canopy, breathing gently.
		var top := Vector2(tx + (_vhash(i, 5) - 0.5) * 8.0, base_y - h)
		for k in range(3):
			var rr: float = (17.0 - float(k) * 3.0) * (1.0 + 0.02 * sin(_pulse * TAU + float(i)))
			draw_circle(top + Vector2((_vhash(i, k + 9) - 0.5) * 11.0, -float(k) * 5.0), rr,
				Color("#4f7d3c").lerp(accent, 0.25 + 0.1 * float(k)))
		# A lantern hanging in the branches.
		var lan := top + Vector2(11.0, -2.0)
		draw_line(top + Vector2(10.0, -9.0), lan, Color("#3a2f22"), 1.5)
		draw_circle(lan, 3.5, Color("#ffd98a", 0.55 + 0.3 * breathe))
		draw_circle(lan, 7.0, Color(1.0, 0.85, 0.5, 0.10 + 0.06 * breathe))
	# Flower beds along the front.
	for i in range(18):
		var fx: float = float(i) / 18.0
		var at := Vector2(mound.position.x + 26.0 + fx * (mound.size.x - 52.0), base_y + 6.0)
		draw_circle(at, 2.6, Color("#f2c7dd") if i % 3 else Color("#fff4d2"))
		draw_line(at, at + Vector2(0, -6.0), Color("#5f8a45"), 1.5)

## A forge home: furnace, chimney, anvil, heat and smoke.
func _draw_fire_home(mound: Rect2, accent: Color, breathe: float) -> void:
	var base_y: float = mound.position.y + mound.size.y - 14.0
	var cx: float = mound.get_center().x
	# Forge house, blackened stone.
	var house := Rect2(mound.position.x + 16.0, base_y - 42.0, 88.0, 42.0)
	draw_rect(house, Color("#2b2320"))
	draw_rect(Rect2(house.position, Vector2(house.size.x, 8.0)), Color("#38302c"))
	# Furnace mouth, glowing.
	var mouth := Rect2(house.position.x + 24.0, base_y - 24.0, 38.0, 24.0)
	draw_rect(mouth, Color("#1a120f"))
	for i in range(4):
		var t := float(i) / 4.0
		draw_rect(Rect2(mouth.position.x + t * 6.0, mouth.position.y + t * 5.0,
			mouth.size.x - t * 12.0, mouth.size.y - t * 8.0),
			Color("#ff7a2f").lerp(Color("#ffd98a"), t) * Color(1, 1, 1, 0.55 + 0.3 * breathe))
	# Chimney with smoke.
	draw_rect(Rect2(house.position.x + 62.0, house.position.y - 16.0, 16.0, 18.0), Color("#241d1a"))
	for i in range(4):
		var rise: float = fmod(_pulse * 30.0 + float(i) * 11.0, 34.0)
		draw_circle(Vector2(house.position.x + 70.0 + sin(rise * 0.12) * 6.0,
			house.position.y - 16.0 - rise), 3.0 + rise * 0.10,
			Color(0.42, 0.39, 0.37, 0.20 * (1.0 - rise / 34.0)))
	# Anvil on a block.
	var ax2: float = mound.position.x + mound.size.x - 46.0
	draw_rect(Rect2(ax2 - 13.0, base_y - 10.0, 26.0, 10.0), Color("#3b2f26"))
	draw_rect(Rect2(ax2 - 16.0, base_y - 16.0, 32.0, 6.0), Color("#4a4a50"))
	draw_rect(Rect2(ax2 - 6.0, base_y - 21.0, 12.0, 6.0), Color("#5a5a62"))
	# Cinder blocks and heat shimmer along the front.
	for i in range(16):
		var fx2: float = float(i) / 16.0
		var at2 := Vector2(mound.position.x + 26.0 + fx2 * (mound.size.x - 52.0), base_y + 6.0)
		draw_circle(at2, 2.4, Color("#241d1a"))
		var lift: float = fmod(fx2 * 3.3 + _pulse, 1.0) * 16.0
		draw_circle(at2 - Vector2(0, lift), 1.8,
			Color("#ffb066", 0.5 * (1.0 - lift / 16.0) + 0.1 * breathe))

func _draw_home_decor(mound: Rect2, element: String, accent: Color, breathe: float) -> void:
	for i in range(12):
		var fx: float = float(i) / 12.0
		var x: float = mound.position.x + 14.0 + fx * (mound.size.x - 28.0)
		if element == "life":
			var h: float = 12.0 + 8.0 * sin(fx * 9.0 + _pulse * 1.2)
			draw_arc(Vector2(x, mound.position.y + 6.0), h, PI * 0.1, PI * 0.9, 10, Color(accent, 0.30), 2.0)
			draw_circle(Vector2(x + 4.0, mound.position.y + 6.0 + h * 0.8), 3.0, Color(accent, 0.45))
		else:
			var y0: float = mound.position.y + mound.size.y - 8.0
			var lift: float = 6.0 + 12.0 * fmod(fx * 3.7 + _pulse, 1.0)
			draw_line(Vector2(x, y0), Vector2(x + 6.0, y0 - 9.0), Color(accent, 0.28), 2.0)
			draw_circle(Vector2(x + 3.0, y0 - lift), 2.0,
				Color("#ffb066", 0.5 * (1.0 - lift / 20.0) + 0.15 * breathe))

func _draw_place(side: int, index: int, place: Dictionary) -> void:
	var at := place_anchor(side, index)
	var colour := card_colour(String(place["card_id"]))
	var act := _find_act("place_build", side, index)
	var build := 1.0
	if not act.is_empty(): build = clampf(float(act["t"]) / float(act["dur"]) / 0.88, 0.0, 1.0)
	draw_circle(at + Vector2(0, 12), 26.0, Color(0.15, 0.13, 0.11, 0.5))
	for i in range(5):
		var ang: float = TAU * float(i) / 5.0
		draw_circle(at + Vector2(0, 12) + Vector2(cos(ang), sin(ang) * 0.45) * 24.0, 2.0,
			Color(colour, 0.5 * minf(1.0, build * 3.0)))
	var tex: Texture2D = art.landmark(String(place["card_id"])) if art != null else null
	if tex != null and build > 0.12:
		var src := Vector2(tex.get_width(), tex.get_height())
		var sc: float = 54.0 / src.y
		var drawn := src * sc * Vector2(1.0, clampf((build - 0.12) / 0.88, 0.05, 1.0))
		draw_texture_rect(tex, Rect2(at + Vector2(-drawn.x * 0.5, 12.0 - drawn.y), drawn), false)

func _draw_support_link(side: int, index: int, place: Dictionary) -> void:
	var a := place_anchor(side, index) + Vector2(0, 2)
	var b := creature_anchor(side, index) + Vector2(0, 6)
	var colour := card_colour(String(place["card_id"]))
	var flow: float = fmod(_pulse * 1.4, 1.0)
	for i in range(7):
		var k: float = float(i) / 6.0
		var at: Vector2 = a.lerp(b, k)
		var near: float = absf(fmod(k - flow + 1.0, 1.0))
		draw_circle(at, 2.4, Color(colour, 0.20 + 0.5 * pow(1.0 - min(near, 1.0 - near) * 2.0, 3.0)))

## A creature standing on the front edge of its land. During an attack it walks
## out into the clash space, meets its opposite number, and comes home.
func _draw_creature(side: int, index: int, unit: Dictionary, f: Font) -> void:
	var home := creature_anchor(side, index)
	var card_id := String(unit["card_id"])
	var colour := card_colour(card_id)
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
			var eased: float = 1.0 - pow(1.0 - k, 3.0)
			scale = eased
			squash = Vector2(0.7 + 0.3 * eased + 0.24 * sin(eased * PI),
							 0.6 + 0.4 * eased - 0.18 * sin(eased * PI))

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
	var at := home + offset
	draw_circle(Vector2(at.x, at.y + 18.0), 22.0 * scale, Color(0, 0, 0, 0.26))
	if glow > 0.0: draw_circle(at, 38.0 * scale, Color(colour, 0.20 * glow))

	var tex: Texture2D = art.creature(card_id) if art != null else null
	if tex != null:
		var src := Vector2(tex.get_width(), tex.get_height())
		var tier: float = clampf(float(src.y) / 96.0, 0.5, 1.0)
		var sc: float = (52.0 + 34.0 * tier) / src.y
		var drawn := src * sc * squash * scale
		var tint := Color(1, 1, 1, 1)
		if glow > 0.4: tint = Color(1.0, 0.86 + 0.14 * (1.0 - glow), 0.86, 1.0)
		draw_texture_rect(tex, Rect2(Vector2(at.x - drawn.x * 0.5, at.y + 18.0 - drawn.y), drawn), false, tint)
	else:
		var box := Rect2(at - Vector2(30, 54) * scale, Vector2(60, 60) * squash * scale)
		draw_style_box(ArcanaTheme.panel_box(colour.darkened(0.45), colour, 10, 2), box)

	# Only the numbers stay on the board; the name lives on hover.
	var y: float = at.y + 30.0
	_gem(f, Vector2(at.x - 22.0, y), str(int(unit["power"])), Color("#ffd98a"))
	_gem(f, Vector2(at.x + 22.0, y), str(int(unit["health"])),
		ArcanaTheme.HEART if int(unit["health"]) < int(unit["max_health"]) else Color("#ffb3c4"))
	if side == 0 and not bool(unit.get("ready", true)):
		draw_arc(Vector2(at.x, at.y - 34.0), 7.0, 0, TAU, 14, Color(ArcanaTheme.TEXT_FAINT, 0.7), 1.5)
	if side == hover_side and index == hover_lane:
		var name := String(unit["name"])
		var nw: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var plate := Rect2(at.x - nw * 0.5 - 7.0, at.y - 58.0, nw + 14.0, 19.0)
		draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.88), Color(colour, 0.8), 6, 1), plate)
		draw_string(f, Vector2(plate.position.x + 7.0, plate.position.y + 14.0), name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ArcanaTheme.TEXT)

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
