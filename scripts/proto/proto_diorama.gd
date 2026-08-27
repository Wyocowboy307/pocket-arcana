class_name ProtoDiorama
extends Node3D
## A landscape as a miniature world sitting on the table.
##
## Not a coloured rectangle: a faceted island with real little trees, stones,
## lava and weather, wind sway on the foliage, and its own ambient particles.
## Everything is deterministic from `seed_v`, so the world is stable shot to
## shot.

const W := 3.5
const D := 1.95
const H := 0.15

var kind := "grove"
var seed_v := 11
var highlight_on := false

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _sway: Array = []                 # {node, phase, amp}
var _lava_mats: Array = []
var _lava_light: OmniLight3D
var _t := 0.0

static func grove(seed_value := 11) -> ProtoDiorama:
    var d := ProtoDiorama.new()
    d.kind = "grove"; d.seed_v = seed_value
    return d

static func cinder(seed_value := 23) -> ProtoDiorama:
    var d := ProtoDiorama.new()
    d.kind = "cinder"; d.seed_v = seed_value
    return d

func _ready() -> void:
    if kind == "grove": _build_grove()
    else: _build_cinder()
    _build_ring()
    set_process(true)

func surface_height(x: float, z: float) -> float:
    return ProtoMesh.island_height(x, z, W, D, H, seed_v)

## Where a summoned creature stands.
func creature_anchor() -> Vector3:
    var toward_foe := -1.0 if kind == "grove" else 1.0
    var z := toward_foe * 0.24
    return global_position + Vector3(0.34, surface_height(0.34, z), z)

## Where the played card tucks in as a little plaque at the front edge.
func plaque_anchor() -> Vector3:
    var toward_owner := 1.0 if kind == "grove" else -1.0
    return global_position + Vector3(-1.34, 0.05, toward_owner * (D * 0.5 + 0.2))

func set_highlight(on: bool) -> void:
    highlight_on = on
    _ring.visible = on

func _process(delta: float) -> void:
    _t += delta
    for s in _sway:
        var node: Node3D = s["node"]
        node.rotation.z = sin(_t * 1.5 + float(s["phase"])) * float(s["amp"])
        node.rotation.x = cos(_t * 1.1 + float(s["phase"]) * 1.7) * float(s["amp"]) * 0.6
    if highlight_on:
        var pulse := 0.65 + 0.35 * sin(_t * 5.0)
        _ring_mat.emission_energy_multiplier = 1.2 + 1.6 * pulse
    if _lava_light != null:
        _lava_light.light_energy = 0.85 + 0.3 * sin(_t * 7.0) * sin(_t * 3.1 + 1.0)
        for m in _lava_mats:
            (m as StandardMaterial3D).emission_energy_multiplier = 2.4 + 0.8 * sin(_t * 5.3)

# --- grove ------------------------------------------------------------------

func _build_grove() -> void:
    var palette := [Color("#568f3a"), Color("#65a447"), Color("#75b854"), Color("#88cb64")]
    ProtoMesh.put(self, ProtoMesh.island(W, D, H, palette, Color("#5d4632"), seed_v),
        ProtoMesh.vertex_mat(), Vector3.ZERO)

    # Trees along the back arc, both sides, so the island is not lopsided and
    # the resident still owns the centre-front.
    _tree(_ground(Vector2(-1.42, -0.22)), 1.35, 7)
    _pine(_ground(Vector2(-0.88, -0.55)), 1.15, 19)
    _tree(_ground(Vector2(-0.2, -0.62)), 1.0, 29)
    _pine(_ground(Vector2(0.72, -0.55)), 1.25, 37)
    _tree(_ground(Vector2(1.38, -0.2)), 1.2, 43)
    _tree(_ground(Vector2(1.6, 0.38)), 0.85, 51)

    # Undergrowth spread over the open ground rather than clumped.
    var spots: Array[Vector2] = [Vector2(-1.45, 0.28), Vector2(-1.05, 0.62), Vector2(-0.5, 0.34),
                  Vector2(-0.15, 0.68), Vector2(0.62, 0.6), Vector2(1.15, 0.34),
                  Vector2(1.42, 0.66), Vector2(-1.55, -0.1), Vector2(0.95, -0.12)]
    for i in range(spots.size()):
        var sp: Vector2 = spots[i]
        match i % 3:
            0: _grass(_ground(sp), i)
            1: _flower(_ground(sp), i)
            _: _clover(_ground(sp), i)
    for i in range(4):
        var stones: Array[Vector2] = [Vector2(-0.95, 0.15), Vector2(0.35, 0.5),
            Vector2(1.3, -0.2), Vector2(-0.2, -0.3)]
        var st: Vector2 = stones[i]
        ProtoMesh.put(self, ProtoMesh.blob(0.09 + ProtoMesh.hashf(i, seed_v, 19) * 0.05,
            0.25, Color("#8f8a7e"), Color("#a8a294"), seed_v + i),
            ProtoMesh.vertex_mat(), _ground(st) + Vector3(0, 0.02, 0),
            ProtoMesh.hashf(i, seed_v, 23) * TAU, Vector3(1, 0.55, 1))
    _mushroom(_ground(Vector2(-1.32, 0.62)))
    _mushroom(_ground(Vector2(1.05, 0.72)))
    _lantern_plant(_ground(Vector2(-1.62, 0.2)))
    _lantern_plant(_ground(Vector2(1.62, 0.42)))
    _mushroom(_ground(Vector2(0.5, -0.42)))

    _ambient_particles(Color(0.72, 0.95, 0.4), 14, 0.16, true)
    _butterflies()

## Snap a 2D spot to the island surface.
func _ground(at: Vector2) -> Vector3:
    return Vector3(at.x, surface_height(at.x, at.y) - 0.01, at.y)

func _clover(at: Vector3, salt: int) -> void:
    var c := Node3D.new()
    c.position = at
    add_child(c)
    for k in range(4):
        var a := TAU * float(k) / 4.0
        ProtoMesh.put(c, ProtoMesh.blob(0.035, 0.25, Color("#3f9a44"), Color("#5cba57"),
            seed_v + salt + k), ProtoMesh.vertex_mat(),
            Vector3(cos(a) * 0.035, 0.03, sin(a) * 0.035), 0.0, Vector3(1, 0.35, 1))
    _sway.append({"node": c, "phase": ProtoMesh.hashf(salt, 6, 3) * TAU, "amp": 0.06})

## Butterflies: slow, drifting, unmistakably alive.
func _butterflies() -> void:
    var p := GPUParticles3D.new()
    p.amount = 6
    p.lifetime = 7.0
    p.position = Vector3(0, 0.38, 0.1)
    var pm := ParticleProcessMaterial.new()
    pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    pm.emission_box_extents = Vector3(W * 0.36, 0.22, D * 0.32)
    pm.direction = Vector3(0, 1, 0)
    pm.spread = 60.0
    pm.initial_velocity_min = 0.05
    pm.initial_velocity_max = 0.16
    pm.gravity = Vector3(0, 0.02, 0)
    pm.turbulence_enabled = true
    pm.turbulence_noise_strength = 1.6
    pm.turbulence_noise_scale = 3.2
    # Small and softly lit. An HDR tint plus a 0.09 scale bloomed these into
    # giant glowing diamonds hanging over the grove.
    pm.scale_min = 0.022
    pm.scale_max = 0.038
    pm.color = Color(1.0, 0.72, 0.85)
    var ramp := Gradient.new()
    ramp.set_color(0, Color(1.0, 0.75, 0.9, 0.0))
    ramp.add_point(0.15, Color(1.0, 0.8, 0.92, 1.0))
    ramp.add_point(0.85, Color(0.95, 0.7, 0.88, 1.0))
    ramp.set_color(1, Color(1.0, 0.75, 0.9, 0.0))
    var ramp_tex := GradientTexture1D.new()
    ramp_tex.gradient = ramp
    pm.color_ramp = ramp_tex
    p.process_material = pm
    p.draw_pass_1 = _billboard_quad("res://assets/proto/fx/leaf.png", false)
    add_child(p)

func _pine(at: Vector3, s: float, salt: int) -> void:
    var tree := Node3D.new()
    tree.position = at
    add_child(tree)
    ProtoMesh.put(tree, ProtoMesh.prism(5, 0.05 * s, 0.04 * s, 0.22 * s,
        Color("#6a4a30"), Color("#7d5a3c"), seed_v + salt), ProtoMesh.vertex_mat(),
        Vector3.ZERO)
    var crown := Node3D.new()
    crown.position = Vector3(0, 0.16 * s, 0)
    tree.add_child(crown)
    for k in range(3):
        ProtoMesh.put(crown, ProtoMesh.cone(7, (0.30 - float(k) * 0.075) * s, 0.30 * s,
            Color("#3f9a44"), Color("#5cba57"), seed_v + salt + k),
            ProtoMesh.vertex_mat(), Vector3(0, float(k) * 0.18 * s, 0))
    _sway.append({"node": crown, "phase": ProtoMesh.hashf(salt, 4, 7) * TAU, "amp": 0.03})

func _lantern_plant(at: Vector3) -> void:
    var plant := Node3D.new()
    plant.position = at
    add_child(plant)
    ProtoMesh.put(plant, ProtoMesh.prism(4, 0.014, 0.009, 0.20, Color("#4a7c34"),
        Color("#5d9440"), seed_v + 71), ProtoMesh.vertex_mat(), Vector3.ZERO)
    var bulb := ProtoMesh.put(plant, ProtoMesh.blob(0.055, 0.18,
        Color(0.9, 1.7, 0.6), Color(1.3, 2.0, 0.8), seed_v + 73),
        ProtoMesh.glow_mat(Color(0.75, 1.5, 0.45), 1.6), Vector3(0, 0.22, 0))
    bulb.scale = Vector3(1, 1.25, 1)
    var l := OmniLight3D.new()
    l.position = Vector3(0, 0.3, 0)
    l.light_color = Color(0.65, 1.0, 0.5)
    l.omni_range = 0.62
    l.light_energy = 0.4
    plant.add_child(l)
    _sway.append({"node": plant, "phase": 2.1, "amp": 0.05})

func _tree(at: Vector3, s: float, salt: int) -> void:
    var tree := Node3D.new()
    tree.position = at
    add_child(tree)
    ProtoMesh.put(tree, ProtoMesh.prism(6, 0.055 * s, 0.035 * s, 0.34 * s,
        Color("#6a4a30"), Color("#7d5a3c"), seed_v + salt), ProtoMesh.vertex_mat(),
        Vector3.ZERO)
    var crown := Node3D.new()
    crown.position = Vector3(0, 0.30 * s, 0)
    tree.add_child(crown)
    var greens := [[Color("#357f39"), Color("#4a9c48")], [Color("#3f9a44"), Color("#58b455")],
                   [Color("#4aa84c"), Color("#6ac461")]]
    for k in range(11):
        var g: Array = greens[k % 3]
        var a := TAU * float(k) * 0.618 + ProtoMesh.hashf(k, salt, 17)
        var tier := float(k) / 11.0
        var rad := (0.155 - tier * 0.05) * s
        var spread := (0.18 - tier * 0.10) * s
        ProtoMesh.put(crown, ProtoMesh.blob(rad, 0.34, g[0], g[1], seed_v + salt + k),
            ProtoMesh.vertex_mat(),
            Vector3(cos(a) * spread, tier * 0.32 * s, sin(a) * spread * 0.85))
    _sway.append({"node": crown, "phase": ProtoMesh.hashf(salt, 1, 7) * TAU, "amp": 0.035})

func _grass(at: Vector3, salt: int) -> void:
    var tuft := Node3D.new()
    tuft.position = at
    add_child(tuft)
    for k in range(4):
        var lean := Vector3((ProtoMesh.hashf(k, salt, 3) - 0.5) * 0.05, 0,
            (ProtoMesh.hashf(k, salt, 5) - 0.5) * 0.05)
        ProtoMesh.put(tuft, ProtoMesh.cone(4, 0.022, 0.14 + ProtoMesh.hashf(k, salt, 7) * 0.07,
            Color("#5da344"), Color("#7cc25b"), seed_v + salt + k),
            ProtoMesh.vertex_mat(), lean)
    _sway.append({"node": tuft, "phase": ProtoMesh.hashf(salt, 2, 9) * TAU, "amp": 0.10})

func _flower(at: Vector3, salt: int) -> void:
    var f := Node3D.new()
    f.position = at
    add_child(f)
    var petals := [Color("#e88fa6"), Color("#f0d060"), Color("#b48fe8"), Color("#f0f0e0")]
    ProtoMesh.put(f, ProtoMesh.prism(4, 0.012, 0.009, 0.11, Color("#4a7c34"),
        Color("#5d9440"), seed_v + salt), ProtoMesh.vertex_mat(), Vector3.ZERO)
    var head: Color = petals[salt % petals.size()]
    ProtoMesh.put(f, ProtoMesh.blob(0.05, 0.3, head, head.lightened(0.25), seed_v + salt),
        ProtoMesh.vertex_mat(), Vector3(0, 0.12, 0))
    _sway.append({"node": f, "phase": ProtoMesh.hashf(salt, 3, 11) * TAU, "amp": 0.07})

func _mushroom(at: Vector3) -> void:
    var m := Node3D.new()
    m.position = at
    add_child(m)
    ProtoMesh.put(m, ProtoMesh.prism(5, 0.045, 0.036, 0.11, Color("#e0d6c0"),
        Color("#f0e8d8"), seed_v + 31), ProtoMesh.vertex_mat(), Vector3.ZERO)
    ProtoMesh.put(m, ProtoMesh.blob(0.085, 0.2, Color("#c04f46"), Color("#d4685c"),
        seed_v + 33), ProtoMesh.vertex_mat(), Vector3(0, 0.13, 0), 0.0, Vector3(1, 0.6, 1))

# --- cinder -----------------------------------------------------------------

func _build_cinder() -> void:
    var palette := [Color("#4a3a30"), Color("#5b4738"), Color("#6b5442"), Color("#7d634e")]
    ProtoMesh.put(self, ProtoMesh.island(W, D, H, palette, Color("#2b211a"), seed_v),
        ProtoMesh.vertex_mat(), Vector3.ZERO)
    ProtoMesh.put(self, ProtoMesh.cracks(W, D, H, seed_v),
        ProtoMesh.glow_mat(Color(1.0, 0.42, 0.1), 2.6), Vector3.ZERO)

    # The lava pool, banked with dark stones.
    var pool_at := Vector3(-1.02, surface_height(-1.02, 0.30) + 0.015, 0.30)
    var hot := ProtoMesh.glow_mat(Color(1.0, 0.5, 0.12), 2.6)
    var core := ProtoMesh.glow_mat(Color(1.0, 0.82, 0.35), 3.4)
    _lava_mats = [hot, core]
    ProtoMesh.put(self, ProtoMesh.pool(0.52, Color(1, 1, 1), seed_v + 5), hot, pool_at)
    ProtoMesh.put(self, ProtoMesh.pool(0.28, Color(1, 1, 1), seed_v + 7), core,
        pool_at + Vector3(0.02, 0.006, 0.02))
    for i in range(6):
        var a := TAU * float(i) / 6.0 + 0.4
        var rp := pool_at + Vector3(cos(a) * 0.5, 0.01, sin(a) * 0.4)
        ProtoMesh.put(self, ProtoMesh.blob(0.06 + ProtoMesh.hashf(i, seed_v, 3) * 0.04,
            0.3, Color("#332822"), Color("#48392f"), seed_v + 40 + i),
            ProtoMesh.vertex_mat(), rp, 0.0, Vector3(1, 0.7, 1))
    _lava_light = OmniLight3D.new()
    _lava_light.position = pool_at + Vector3(0, 0.35, 0)
    _lava_light.light_color = Color(1.0, 0.55, 0.2)
    _lava_light.omni_range = 1.9
    _lava_light.light_energy = 0.9
    add_child(_lava_light)

    for i in range(5):                        # jagged shards along the back
        var x := -0.35 + float(i) * 0.52 + ProtoMesh.hashf(i, seed_v, 9) * 0.18
        var z := -D * 0.30 + ProtoMesh.hashf(i, seed_v, 11) * 0.34
        ProtoMesh.put(self, ProtoMesh.cone(5, 0.10 + ProtoMesh.hashf(i, seed_v, 13) * 0.05,
            0.30 + ProtoMesh.hashf(i, seed_v, 15) * 0.28,
            Color("#332822"), Color("#4d3f34"), seed_v + 50 + i),
            ProtoMesh.vertex_mat(), Vector3(x, surface_height(x, z) - 0.01, z),
            ProtoMesh.hashf(i, seed_v, 17) * TAU)
    _burnt_tree(Vector3(-1.55, surface_height(-1.55, -0.28) - 0.01, -0.28), 55)
    _burnt_tree(Vector3(1.42, surface_height(1.42, 0.36) - 0.01, 0.36), 61)
    _burnt_tree(Vector3(0.35, surface_height(0.35, 0.6) - 0.01, 0.6), 67)
    for i in range(6):                        # charred stubble and coal chunks
        var cx := -1.5 + float(i) * 0.58
        var cz := 0.18 + (ProtoMesh.hashf(i, seed_v, 31) - 0.5) * 0.7
        ProtoMesh.put(self, ProtoMesh.blob(0.055 + ProtoMesh.hashf(i, seed_v, 33) * 0.04,
            0.35, Color("#2b221c"), Color("#3f3229"), seed_v + 80 + i),
            ProtoMesh.vertex_mat(),
            Vector3(cx, surface_height(cx, cz), cz), 0.0, Vector3(1, 0.6, 1))
    for i in range(4):                        # small ember pockets
        var ex := -0.9 + float(i) * 0.72
        var ez := -0.55 + ProtoMesh.hashf(i, seed_v, 37) * 0.3
        ProtoMesh.put(self, ProtoMesh.pool(0.10, Color(1, 1, 1), seed_v + 90 + i),
            ProtoMesh.glow_mat(Color(1.0, 0.42, 0.1), 2.2),
            Vector3(ex, surface_height(ex, ez) + 0.012, ez))

    _ambient_particles(Color(1.6, 0.75, 0.2), 26, 0.55, false)   # embers
    _smoke(Vector3(-0.95, surface_height(-0.95, 0.38) + 0.1, 0.38))

func _burnt_tree(at: Vector3, salt: int) -> void:
    var tree := Node3D.new()
    tree.position = at
    add_child(tree)
    ProtoMesh.put(tree, ProtoMesh.prism(5, 0.04, 0.02, 0.30, Color("#1c1512"),
        Color("#382d25"), seed_v + salt), ProtoMesh.vertex_mat(), Vector3.ZERO)
    for k in range(3):
        var a := 0.7 + float(k) * 1.9
        var branch := ProtoMesh.put(tree, ProtoMesh.cone(4, 0.016, 0.16,
            Color("#1c1512"), Color("#2a211c"), seed_v + salt + k),
            ProtoMesh.vertex_mat(), Vector3(cos(a) * 0.03, 0.16 + float(k) * 0.05, sin(a) * 0.03))
        branch.rotation = Vector3(cos(a) * 1.1, 0, sin(a) * 1.1)
        ProtoMesh.put(tree, ProtoMesh.blob(0.012, 0.3, Color(1.0, 0.5, 0.15),
            Color(1.0, 0.7, 0.3), seed_v + salt + k),
            ProtoMesh.glow_mat(Color(1.0, 0.5, 0.15), 2.0),
            Vector3(cos(a) * 0.14, 0.20 + float(k) * 0.05, sin(a) * 0.14))

# --- ambient particles ------------------------------------------------------

func _ambient_particles(colour: Color, amount: int, rise: float, drift: bool) -> void:
    var p := GPUParticles3D.new()
    p.amount = amount
    p.lifetime = 4.0
    p.position = Vector3(0, 0.25, 0)
    var pm := ParticleProcessMaterial.new()
    pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    pm.emission_box_extents = Vector3(W * 0.42, 0.16, D * 0.42)
    pm.direction = Vector3(0, 1, 0)
    pm.spread = 25.0
    pm.initial_velocity_min = rise * 0.4
    pm.initial_velocity_max = rise
    pm.gravity = Vector3(0, 0.05 if not drift else -0.01, 0)
    pm.scale_min = 0.024
    pm.scale_max = 0.05
    pm.color = colour * 1.6 if drift else colour
    if drift:
        pm.turbulence_enabled = true
        pm.turbulence_noise_strength = 0.45
        pm.turbulence_noise_scale = 1.6
    var ramp := Gradient.new()
    ramp.set_color(0, Color(colour, 0.0))
    ramp.add_point(0.2, Color(colour, 1.0))
    ramp.add_point(0.8, Color(colour, 0.9))
    ramp.set_color(1, Color(colour, 0.0))
    var ramp_tex := GradientTexture1D.new()
    ramp_tex.gradient = ramp
    pm.color_ramp = ramp_tex
    p.process_material = pm
    p.draw_pass_1 = _billboard_quad("res://assets/proto/fx/soft_dot.png", true)
    add_child(p)

func _smoke(at: Vector3) -> void:
    var p := GPUParticles3D.new()
    p.amount = 7
    p.lifetime = 4.5
    p.position = at
    var pm := ParticleProcessMaterial.new()
    pm.direction = Vector3(0, 1, 0)
    pm.spread = 10.0
    pm.initial_velocity_min = 0.16
    pm.initial_velocity_max = 0.26
    pm.gravity = Vector3(0.04, 0.05, 0)
    pm.scale_min = 0.20
    pm.scale_max = 0.42
    var ramp := Gradient.new()
    ramp.set_color(0, Color(0.35, 0.32, 0.34, 0.0))
    ramp.add_point(0.25, Color(0.38, 0.35, 0.37, 0.5))
    ramp.set_color(1, Color(0.42, 0.40, 0.42, 0.0))
    var ramp_tex := GradientTexture1D.new()
    ramp_tex.gradient = ramp
    pm.color_ramp = ramp_tex
    p.process_material = pm
    p.draw_pass_1 = _billboard_quad("res://assets/proto/fx/puff.png", false)
    add_child(p)

static func _billboard_quad(tex_path: String, additive: bool) -> QuadMesh:
    var q := QuadMesh.new()
    q.size = Vector2.ONE
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    # Without this a billboarded particle ignores its own scale and draws at the
    # full quad size — every mote rendered as a metre-wide glowing diamond.
    m.billboard_keep_scale = true
    m.vertex_color_use_as_albedo = true
    m.albedo_texture = load(tex_path)
    if additive: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    q.material = m
    return q

# --- highlight ring ---------------------------------------------------------

func _build_ring() -> void:
    var torus := TorusMesh.new()
    torus.inner_radius = W * 0.52
    torus.outer_radius = W * 0.52 + 0.05
    torus.rings = 40
    var colour := Color(0.55, 1.0, 0.45) if kind == "grove" else Color(1.0, 0.55, 0.25)
    _ring_mat = ProtoMesh.glow_mat(colour, 2.0)
    _ring = MeshInstance3D.new()
    _ring.mesh = torus
    _ring.material_override = _ring_mat
    _ring.position = Vector3(0, 0.05, 0)
    _ring.scale = Vector3(1.0, 0.35, D / W + 0.16)
    _ring.visible = false
    add_child(_ring)
