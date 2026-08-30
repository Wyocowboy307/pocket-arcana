class_name RealmVisualSystem
extends RefCounted
## Turns simulation state into a living little environment.
##
## The simulation keeps its exact four-lane coordinates; this system is the
## only thing that knows how to show them. The player must never see a
## gameplay slot: an empty position is a faint rune seed-point where a world
## COULD grow, a built position is an organic slab of terrain, and everything
## that happens in a match — construction, deaths, spells, fusions, a wounded
## Heart — leaves visible history on the board.
##
## Presentation only. Nothing here may influence legality, coordinates,
## hitboxes, AI or determinism. Drawing happens inside the stage's _draw, so
## every method takes the stage (untyped, to avoid a class-name cycle) and
## draws through it.

var stage                              # StageV2
var dressing_enabled := true           # the Living Board Lab flips these
var micro_enabled := true

## Match history the view keeps: which turn each lane's land arrived (worlds
## grow more props as they age) and where fusions happened (the land
## remembers its miracles).
var built_turn: Dictionary = {}        # "side,lane" -> turn number
var fusion_sites: Array = []           # {side, lane}

func _engine():
	return stage.engine

func _art():
	return stage.art

## Called by the stage whenever an act starts, so history can accumulate.
func on_act(kind: String, act: Dictionary) -> void:
	match kind:
		"land_build":
			built_turn["%d,%d" % [int(act.get("side", 0)), int(act.get("lane", 0))]] = \
				int(_engine().turn)
		"fusion":
			if fusion_sites.size() > 5: fusion_sites.pop_front()
			fusion_sites.append({"side": int(act.get("side", 0)), "lane": int(act.get("lane", 0))})

func reset() -> void:
	built_turn.clear()
	fusion_sites.clear()

# --- organic silhouettes -----------------------------------------------------

## A rounded polygon with a deterministic hand-torn wobble: the same lane
## always wears the same silhouette, and no two positions match exactly.
## The wobble is radial, so a grown copy (the ink outline) stays parallel.
func organic_poly(r: Rect2, rad: float, seed_v: int, wobble := 5.0,
		centre := Vector2.INF) -> PackedVector2Array:
	var base: PackedVector2Array = stage._rounded_poly(r, rad, true, true)
	var c := r.get_center() if centre == Vector2.INF else centre
	var out := PackedVector2Array()
	for i in range(base.size()):
		var p: Vector2 = base[i]
		var n: float = (stage._vhash(seed_v + i * 7, 911) - 0.5) * 2.0 * wobble
		# Pull along the outward direction; flat edges wobble too, which is
		# what breaks the rectangle read. A slab's ink, top and face polys all
		# pass the same centre and seed, so their wobbles stay parallel and
		# the outline ring keeps its width.
		var dir := (p - c)
		dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
		out.append(p + dir * n)
	return out

# --- seed-points: where a world could grow -----------------------------------

## An empty gameplay position. Not a socket, not a recess, not a rectangle:
## a faint rune ring sleeping in the table with a whisper of the element that
## would grow here. Godot knows where the slot is; the player sees potential.
func draw_seedpoint(side: int, index: int) -> void:
	var r: Rect2 = stage.plot_rect(side, index)
	var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.58)
	var seed_v := side * 733 + index * 149
	var breathe: float = 0.5 + 0.5 * sin(stage._pulse * TAU + float(index) * 1.7 + float(side) * 2.3)

	# The sleeping ring, barely brighter than the table.
	var ring := Color(0.25, 0.28, 0.41, 0.34 + 0.10 * breathe)
	stage.draw_arc(c, 26.0, 0, TAU, 28, ring, 2.0)
	stage.draw_arc(c, 19.0, PI * 0.25, PI * 1.15, 14, Color(ring, 0.22), 1.5)
	for k in range(4):
		var a: float = TAU * float(k) / 4.0 + PI * 0.25
		stage.draw_circle(c + Vector2(cos(a), sin(a) * 0.7) * 32.0, 1.5, ring)

	if not dressing_enabled: return
	# A whisper of what would grow: sprouts on the Life side, ember specks on
	# the Fire side, scattered deterministically round the ring.
	var element := String(_engine().players[side]["element"])
	for k2 in range(3):
		var at := c + Vector2((stage._vhash(seed_v + k2, 31) - 0.5) * r.size.x * 0.7,
			(stage._vhash(seed_v + k2, 37) - 0.5) * r.size.y * 0.6)
		if element == "life":
			stage.draw_rect(Rect2(at.x, at.y - 3.0, 2.0, 4.0), Color(0.35, 0.50, 0.30, 0.8))
			stage.draw_rect(Rect2(at.x - 1.0, at.y - 5.0, 2.0, 2.0), Color(0.42, 0.62, 0.34, 0.8))
		else:
			stage.draw_rect(Rect2(at.x, at.y, 2.0, 2.0), Color(0.76, 0.24, 0.08, 0.65))
			stage.draw_rect(Rect2(at.x + 3.0, at.y + 2.0, 1.0, 1.0), Color(0.96, 0.34, 0.0, 0.5))

# --- history on the world ----------------------------------------------------

## The land remembers a fusion: a soft rune scar where the miracle happened.
func draw_fusion_sites() -> void:
	for site in fusion_sites:
		var side := int(site["side"])
		var lane := int(site["lane"])
		if String(_engine().lane(side, lane)["land"]) == "": continue
		var r: Rect2 = stage.plot_rect(side, lane)
		var c := Vector2(r.get_center().x, r.position.y + r.size.y - 34.0)
		var gold := Color(ArcanaTheme.GOLD, 0.16)
		stage.draw_arc(c, 30.0, 0, TAU, 26, gold, 2.0)
		stage.draw_arc(c, 22.0, PI * 0.3, PI * 1.6, 16, Color(ArcanaTheme.GOLD, 0.10), 1.5)

## How developed a lane's world is, 0..4: older land grows more.
func land_age(side: int, index: int) -> int:
	var key := "%d,%d" % [side, index]
	if not built_turn.has(key): return 2      # pre-recorded land starts settled
	return clampi(int(_engine().turn) - int(built_turn[key]), 0, 4)
