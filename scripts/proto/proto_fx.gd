class_name ProtoFX
extends RefCounted
## One-shot effects for the prototype: bursts, shockwaves, beams, flashes,
## flame cones, growing vines. Everything spawns, plays, and frees itself —
## except the pieces that deliberately stay, because a spell should visibly
## change the world (new flowers, scorch marks).

static func _timer_free(node: Node, seconds: float) -> void:
    node.get_tree().create_timer(seconds).timeout.connect(func() -> void:
        if is_instance_valid(node): node.queue_free())

## A radial one-shot burst of sprites.
static func burst(parent: Node3D, pos: Vector3, colour: Color, sprite: String,
        amount := 30, speed := 2.0, up := 0.6, additive := true, life := 0.9) -> void:
    var p := GPUParticles3D.new()
    p.amount = amount
    p.lifetime = life
    p.one_shot = true
    p.explosiveness = 1.0
    p.position = pos
    var pm := ParticleProcessMaterial.new()
    pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    pm.emission_sphere_radius = 0.06
    pm.direction = Vector3(0, 1, 0)
    pm.spread = 85.0
    pm.initial_velocity_min = speed * 0.4
    pm.initial_velocity_max = speed
    pm.gravity = Vector3(0, -3.4 + up * 3.0, 0)
    pm.scale_min = 0.03
    pm.scale_max = 0.085
    pm.angle_min = -180.0
    pm.angle_max = 180.0
    pm.color = colour
    var ramp := Gradient.new()
    ramp.set_color(0, Color(colour, 1.0))
    ramp.add_point(0.7, Color(colour, 0.9))
    ramp.set_color(1, Color(colour, 0.0))
    var ramp_tex := GradientTexture1D.new()
    ramp_tex.gradient = ramp
    pm.color_ramp = ramp_tex
    p.process_material = pm
    p.draw_pass_1 = ProtoDiorama._billboard_quad("res://assets/proto/fx/%s.png" % sprite, additive)
    parent.add_child(p)
    p.emitting = true
    _timer_free(p, life + 0.4)

## An expanding ground ring — the classic summon shockwave.
static func ring_shock(parent: Node3D, pos: Vector3, colour: Color, radius := 0.9,
        dur := 0.55) -> void:
    var torus := TorusMesh.new()
    torus.inner_radius = 0.94
    torus.outer_radius = 1.0
    torus.rings = 48
    var mi := MeshInstance3D.new()
    mi.mesh = torus
    var m := ProtoMesh.glow_mat(colour, 3.0)
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mi.material_override = m
    mi.position = pos + Vector3(0, 0.03, 0)
    mi.scale = Vector3(0.08, 0.05, 0.08)
    parent.add_child(mi)
    var tw := mi.create_tween().set_parallel(true)
    tw.tween_property(mi, "scale", Vector3(radius, 0.05, radius), dur) \
        .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tw.tween_property(m, "albedo_color:a", 0.0, dur)
    _timer_free(mi, dur + 0.1)

## A vertical pillar of light.
static func beam(parent: Node3D, pos: Vector3, colour: Color, dur := 0.5) -> void:
    var cyl := CylinderMesh.new()
    cyl.top_radius = 0.16
    cyl.bottom_radius = 0.30
    cyl.height = 2.2
    cyl.radial_segments = 12
    var m := ProtoMesh.glow_mat(colour, 2.2)
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.albedo_color = Color(colour, 0.55)
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var mi := MeshInstance3D.new()
    mi.mesh = cyl
    mi.material_override = m
    mi.position = pos + Vector3(0, 1.1, 0)
    parent.add_child(mi)
    var tw := mi.create_tween().set_parallel(true)
    tw.tween_property(mi, "scale", Vector3(0.35, 1.15, 0.35), dur)
    tw.tween_property(m, "albedo_color:a", 0.0, dur).set_trans(Tween.TRANS_CUBIC)
    _timer_free(mi, dur + 0.1)

## A camera-facing flash at the point of impact.
static func flash(parent: Node3D, pos: Vector3, colour: Color, size := 0.8,
        dur := 0.22) -> void:
    var q := QuadMesh.new()
    q.size = Vector2(size, size)
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    m.albedo_texture = load("res://assets/proto/fx/soft_dot.png")
    m.albedo_color = colour
    var mi := MeshInstance3D.new()
    mi.mesh = q
    mi.material_override = m
    mi.position = pos
    parent.add_child(mi)
    var tw := mi.create_tween().set_parallel(true)
    tw.tween_property(mi, "scale", Vector3.ONE * 2.2, dur)
    tw.tween_property(m, "albedo_color:a", 0.0, dur)
    _timer_free(mi, dur + 0.1)

## A pulse of light — summons, impacts, spell moments.
static func light_pulse(parent: Node3D, pos: Vector3, colour: Color, energy := 2.4,
        dur := 0.5) -> void:
    var l := OmniLight3D.new()
    l.position = pos + Vector3(0, 0.5, 0)
    l.light_color = colour
    l.omni_range = 2.6
    l.light_energy = energy
    parent.add_child(l)
    var tw := l.create_tween()
    tw.tween_property(l, "light_energy", 0.0, dur).set_trans(Tween.TRANS_CUBIC)
    _timer_free(l, dur + 0.1)

## A gout of flame that erupts and dies back, leaving a scorch mark that stays.
##
## Built from stacked blobs rather than one cone: a single hard-shaded cone read
## as a flat yellow triangle, which is the opposite of fire.
static func flame_cone(parent: Node3D, pos: Vector3, scale_v := 1.0) -> void:
    var holder := Node3D.new()
    holder.position = pos
    parent.add_child(holder)
    var seed_v := int(absf(pos.x) * 91.0 + absf(pos.z) * 57.0)
    var tiers := [
        {"y": 0.10, "r": 0.34, "col": Color(1.5, 0.42, 0.10), "hot": Color(1.7, 0.55, 0.14)},
        {"y": 0.42, "r": 0.27, "col": Color(1.8, 0.62, 0.16), "hot": Color(2.1, 0.8, 0.22)},
        {"y": 0.70, "r": 0.19, "col": Color(2.2, 0.95, 0.30), "hot": Color(2.6, 1.2, 0.45)},
        {"y": 0.94, "r": 0.11, "col": Color(2.6, 1.35, 0.55), "hot": Color(3.0, 1.7, 0.8)},
    ]
    for i in range(tiers.size()):
        var tier: Dictionary = tiers[i]
        var mi := MeshInstance3D.new()
        mi.mesh = ProtoMesh.blob(float(tier["r"]) * scale_v, 0.34,
            tier["col"], tier["hot"], seed_v + i * 7)
        var m := ProtoMesh.glow_mat(Color(1.0, 0.55, 0.15), 2.2)
        m.vertex_color_use_as_albedo = true
        m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mi.material_override = m
        mi.position = Vector3((ProtoMesh.hashf(i, seed_v, 3) - 0.5) * 0.14 * scale_v,
            float(tier["y"]) * scale_v, (ProtoMesh.hashf(i, seed_v, 5) - 0.5) * 0.12 * scale_v)
        mi.scale = Vector3(1.0, 1.35, 1.0)
        holder.add_child(mi)
    holder.scale = Vector3(0.12, 0.05, 0.12)
    var tw := holder.create_tween()
    tw.tween_property(holder, "scale", Vector3(1, 1, 1), 0.18) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_interval(0.24)
    tw.tween_property(holder, "scale", Vector3(0.10, 1.5, 0.10), 0.34) \
        .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    _timer_free(holder, 0.9)
    decal(parent, pos, "res://assets/proto/ui/scorch.png", 0.85 * scale_v)
    burst(parent, pos + Vector3(0, 0.25, 0), Color(1.0, 0.6, 0.2), "soft_dot", 26, 2.4, 0.95)
    burst(parent, pos + Vector3(0, 0.2, 0), Color(1.0, 0.85, 0.4), "spark", 12, 3.0, 0.7)
    light_pulse(parent, pos, Color(1.0, 0.5, 0.15), 3.2, 0.5)

## A wall of fire that rolls across the board — the spell's travelling front.
static func fire_wall(parent: Node3D, from: Vector3, to: Vector3, dur := 0.85) -> void:
    var p := GPUParticles3D.new()
    p.amount = 90
    p.lifetime = 0.9
    p.position = from
    var pm := ParticleProcessMaterial.new()
    pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    pm.emission_box_extents = Vector3(1.7, 0.12, 0.06)
    pm.direction = Vector3(0, 1, 0)
    pm.spread = 40.0
    pm.initial_velocity_min = 0.7
    pm.initial_velocity_max = 1.7
    pm.gravity = Vector3(0, -0.5, 0)
    pm.scale_min = 0.10
    pm.scale_max = 0.30
    var ramp := Gradient.new()
    ramp.set_color(0, Color(1.6, 1.0, 0.4, 0.0))
    ramp.add_point(0.15, Color(1.7, 0.9, 0.3, 1.0))
    ramp.add_point(0.6, Color(1.3, 0.45, 0.1, 0.9))
    ramp.set_color(1, Color(0.5, 0.2, 0.15, 0.0))
    var ramp_tex := GradientTexture1D.new()
    ramp_tex.gradient = ramp
    pm.color_ramp = ramp_tex
    p.process_material = pm
    p.draw_pass_1 = ProtoDiorama._billboard_quad("res://assets/proto/fx/soft_dot.png", true)
    parent.add_child(p)
    p.emitting = true
    var tw := p.create_tween()
    tw.tween_property(p, "position", to, dur).set_trans(Tween.TRANS_SINE)
    _timer_free(p, dur + 1.2)

## A mark on the world that stays. Spells should leave evidence.
static func decal(parent: Node3D, pos: Vector3, tex_path: String, size := 0.4) -> void:
    var q := QuadMesh.new()
    q.size = Vector2(size, size)
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.albedo_texture = load(tex_path)
    var mi := MeshInstance3D.new()
    mi.mesh = q
    mi.material_override = m
    mi.rotation.x = -PI / 2.0
    mi.rotation.z = pos.x * 3.7
    mi.position = pos + Vector3(0, 0.018, 0)
    parent.add_child(mi)

## Vines and flowers that erupt and REMAIN — Wild Bloom changes the world.
static func grow_bloom(parent: Node3D, diorama: ProtoDiorama) -> void:
    var rng_seed := 77
    for i in range(6):
        var x := (ProtoMesh.hashf(i, rng_seed, 3) - 0.5) * 1.9
        var z := (ProtoMesh.hashf(i, rng_seed, 5) - 0.35) * 1.15
        var at := Vector3(x, diorama.surface_height(x, z) - 0.01, z)
        var vine := MeshInstance3D.new()
        vine.mesh = ProtoMesh.cone(5, 0.035, 0.22 + ProtoMesh.hashf(i, rng_seed, 7) * 0.2,
            Color("#3f8a3c"), Color("#6fc25b"), rng_seed + i)
        vine.material_override = ProtoMesh.vertex_mat()
        vine.position = at
        vine.scale = Vector3(0.05, 0.02, 0.05)
        vine.rotation.y = ProtoMesh.hashf(i, rng_seed, 9) * TAU
        vine.rotation.x = (ProtoMesh.hashf(i, rng_seed, 11) - 0.5) * 0.5
        diorama.add_child(vine)
        var tw := vine.create_tween()
        tw.tween_interval(float(i) * 0.09)
        tw.tween_property(vine, "scale", Vector3.ONE, 0.34) \
            .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    for i in range(5):
        var x2 := (ProtoMesh.hashf(i + 9, rng_seed, 3) - 0.5) * 1.9
        var z2 := (ProtoMesh.hashf(i + 9, rng_seed, 5) - 0.2) * 1.1
        var at2 := Vector3(x2, diorama.surface_height(x2, z2) + 0.05, z2)
        var petals := [Color("#e88fa6"), Color("#f0d060"), Color("#b48fe8")]
        var head := MeshInstance3D.new()
        var col: Color = petals[i % petals.size()]
        head.mesh = ProtoMesh.blob(0.045, 0.3, col, col.lightened(0.3), rng_seed + 20 + i)
        head.material_override = ProtoMesh.vertex_mat()
        head.position = at2
        head.scale = Vector3.ONE * 0.02
        diorama.add_child(head)
        var tw2 := head.create_tween()
        tw2.tween_interval(0.25 + float(i) * 0.08)
        tw2.tween_property(head, "scale", Vector3.ONE, 0.3) \
            .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
