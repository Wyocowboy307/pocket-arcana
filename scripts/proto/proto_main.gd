extends Node3D
## Arcana Visual Prototype — a 2.5D magical tabletop.
##
## One question, answered visually: does Pocket Arcana feel exciting as a
## physical card game whose cards bring miniature worlds to life?
##
## Deliberately NOT the full game. Two landscapes, two creatures, two spells,
## a flat 5-Aether refill, and about a minute of play. The V1/V2/V3
## implementations are untouched.

const TABLE_Y := 0.045
const GROVE_POS := Vector3(0.0, TABLE_Y, 1.02)
const CINDER_POS := Vector3(0.0, TABLE_Y, -1.42)
const SUMMON_DUR := 1.7
const ATTACK_DUR := 1.5
const SPELL_DUR := 2.3

var camera: Camera3D
var grove: ProtoDiorama
var cinder: ProtoDiorama
var hand: ProtoHand
var ui: CanvasLayer
var status_label: Label
var banner: Label
var inspect_panel: TextureRect
var aether_pips: Control
var end_turn_btn: Button
var arrow_layer: Control

var player_creature: ProtoCreature = null
var enemy_creature: ProtoCreature = null
var aether := 5
var player_heart := 20
var enemy_heart := 20
var mode := ""                        # "" | "card" | "attack"
var selected_card := -1
var enemy_step := 0
var acts: Array = []
var _shake := 0.0
var _cam_home: Transform3D

var card_textures := {}

func _ready() -> void:
    _build_environment()
    _build_table()
    _build_dioramas()
    _build_ui()
    _deal_hand()
    set_process(true)
    _banner("Your move — play a creature onto the Grove")

# --- scene ------------------------------------------------------------------

func _build_environment() -> void:
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#1a1420")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#7d7480")
    env.ambient_light_energy = 1.15
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.glow_enabled = true
    env.glow_intensity = 0.55
    env.glow_bloom = 0.06
    env.glow_hdr_threshold = 1.0
    env.ssao_enabled = true
    env.ssao_intensity = 0.8
    env.fog_enabled = true
    env.fog_light_color = Color("#241c28")
    env.fog_density = 0.012
    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)

    var key := DirectionalLight3D.new()
    key.light_color = Color("#ffe9cf")
    key.light_energy = 2.05
    key.shadow_enabled = true
    key.directional_shadow_max_distance = 30.0
    key.light_angular_distance = 2.0
    key.rotation_degrees = Vector3(-52, -28, 0)
    add_child(key)

    var fill := DirectionalLight3D.new()
    fill.light_color = Color("#8fa6e8")
    fill.light_energy = 0.35
    fill.rotation_degrees = Vector3(-38, 148, 0)
    add_child(fill)

    camera = Camera3D.new()
    camera.position = Vector3(0, 7.15, 5.55)
    camera.fov = 43.0
    add_child(camera)
    camera.look_at(Vector3(0, 0.05, -0.35))
    var attrs := CameraAttributesPractical.new()
    attrs.dof_blur_far_enabled = true
    attrs.dof_blur_far_distance = 11.5
    attrs.dof_blur_far_transition = 3.5
    attrs.dof_blur_amount = 0.07
    camera.attributes = attrs
    _cam_home = camera.transform

func _build_table() -> void:
    var table := Node3D.new()
    add_child(table)
    var base := BoxMesh.new()
    base.size = Vector3(7.6, 0.12, 6.4)
    var base_mat := StandardMaterial3D.new()
    base_mat.albedo_color = Color("#241812")
    ProtoMesh.put(table, base, base_mat, Vector3(0, -0.10, 0))
    # Planks, each its own warmth — a real table, not a texture.
    var plank := BoxMesh.new()
    plank.size = Vector3(0.62, 0.08, 6.3)
    for i in range(13):
        var m := StandardMaterial3D.new()
        var warm := 0.86 + ProtoMesh.hashf(i, 3, 5) * 0.24
        m.albedo_color = Color(0.42 * warm, 0.29 * warm, 0.185 * warm)
        m.roughness = 0.78
        ProtoMesh.put(table, plank, m, Vector3(-3.5 + float(i) * 0.585, -0.04, 0))
        var groove := BoxMesh.new()
        groove.size = Vector3(0.02, 0.085, 6.3)
        var gm := StandardMaterial3D.new()
        gm.albedo_color = Color("#1d120b")
        ProtoMesh.put(table, groove, gm, Vector3(-3.21 + float(i) * 0.585, -0.038, 0))
    for side in [-1.0, 1.0]:               # aprons
        var apron := BoxMesh.new()
        apron.size = Vector3(7.6, 0.3, 0.18)
        var am := StandardMaterial3D.new()
        am.albedo_color = Color("#2e1f15")
        ProtoMesh.put(table, apron, am, Vector3(0, -0.2, side * 3.2))
    # The play mat, with a darker border rim so it reads as a real object.
    var rim := BoxMesh.new()
    rim.size = Vector3(4.45, 0.045, 4.95)
    var rm := StandardMaterial3D.new()
    rm.albedo_color = Color("#182228")
    rm.roughness = 0.95
    ProtoMesh.put(table, rim, rm, Vector3(0, 0.016, -0.2))
    var mat := BoxMesh.new()
    mat.size = Vector3(4.2, 0.05, 4.7)
    var mm := StandardMaterial3D.new()
    mm.albedo_color = Color("#2b4149")
    mm.roughness = 0.96
    ProtoMesh.put(table, mat, mm, Vector3(0, 0.022, -0.2))
    var seam := BoxMesh.new()
    seam.size = Vector3(4.2, 0.052, 0.40)
    var sm2 := StandardMaterial3D.new()
    sm2.albedo_color = Color("#22343b")
    sm2.roughness = 0.98
    ProtoMesh.put(table, seam, sm2, Vector3(0, 0.024, -0.2), 0.0, Vector3(1, 1, 1))
    for i in range(9):                       # scuffs along the seam
        var sx := -1.8 + float(i) * 0.45
        var scuff := BoxMesh.new()
        scuff.size = Vector3(0.3 + ProtoMesh.hashf(i, 9, 3) * 0.3, 0.054, 0.10)
        var cm := StandardMaterial3D.new()
        cm.albedo_color = Color("#1b2a30")
        cm.roughness = 0.99
        ProtoMesh.put(table, scuff, cm,
            Vector3(sx, 0.025, -0.2 + (ProtoMesh.hashf(i, 9, 5) - 0.5) * 0.36))

    # A few pebbles spilled where the miniature worlds meet the mat.
    for i in range(8):
        var near_grove := i < 4
        var anchor := GROVE_POS if near_grove else CINDER_POS
        var a := ProtoMesh.hashf(i, 5, 7) * TAU
        var r := 1.75 + ProtoMesh.hashf(i, 5, 11) * 0.35
        var col_a := Color("#7d8a72") if near_grove else Color("#4a3c33")
        ProtoMesh.put(table, ProtoMesh.blob(0.035 + ProtoMesh.hashf(i, 5, 13) * 0.03,
            0.3, col_a, col_a.lightened(0.2), 60 + i), ProtoMesh.vertex_mat(),
            anchor + Vector3(cos(a) * r, 0.0, sin(a) * r * 0.55), 0.0, Vector3(1, 0.55, 1))
    _deck(Vector3(2.62, TABLE_Y, 1.72), -0.14)
    _deck(Vector3(-2.62, TABLE_Y, -2.05), 0.11)
    _heart_crystal(Vector3(-2.62, TABLE_Y, 1.72), true)
    _heart_crystal(Vector3(2.62, TABLE_Y, -2.05), false)

func _deck(at: Vector3, tilt: float) -> void:
    var stack := Node3D.new()
    stack.position = at
    stack.rotation.y = tilt
    add_child(stack)
    var paper := StandardMaterial3D.new()
    paper.albedo_color = Color("#d8cdb8")
    for i in range(6):
        var b := BoxMesh.new()
        b.size = Vector3(0.52, 0.015, 0.72)
        ProtoMesh.put(stack, b, paper,
            Vector3(ProtoMesh.hashf(i, 7, 3) * 0.02 - 0.01, 0.008 + float(i) * 0.016,
                ProtoMesh.hashf(i, 7, 5) * 0.02 - 0.01),
            (ProtoMesh.hashf(i, 7, 9) - 0.5) * 0.06)
    var back := QuadMesh.new()
    back.size = Vector2(0.52, 0.72)
    var bm := StandardMaterial3D.new()
    bm.albedo_texture = load("res://assets/proto/cards/card_back.png")
    bm.roughness = 0.6
    var top := MeshInstance3D.new()
    top.mesh = back
    top.material_override = bm
    top.rotation_degrees = Vector3(-90, 0, 0)
    top.position = Vector3(0, 0.105, 0)
    stack.add_child(top)

func _heart_crystal(at: Vector3, mine: bool) -> void:
    var gem := MeshInstance3D.new()
    gem.mesh = ProtoMesh.gem(0.13, 0.42, Color(1.6, 0.45, 0.7), Color(2.0, 0.7, 0.95), 5)
    var m := ProtoMesh.glow_mat(Color(1.0, 0.32, 0.52), 1.3)
    m.vertex_color_use_as_albedo = true
    gem.material_override = m
    gem.position = at + Vector3(0, 0.07, 0)
    add_child(gem)
    var spin := gem.create_tween().set_loops()
    spin.tween_property(gem, "rotation:y", TAU, 9.0).from(0.0)
    var l := OmniLight3D.new()
    l.position = at + Vector3(0, 0.4, 0)
    l.light_color = Color(1.0, 0.4, 0.6)
    l.omni_range = 1.3
    l.light_energy = 0.5
    add_child(l)
    var plinth := MeshInstance3D.new()
    plinth.mesh = ProtoMesh.prism(6, 0.2, 0.16, 0.06, Color("#3a3341"), Color("#4d4455"), 9)
    plinth.material_override = ProtoMesh.vertex_mat()
    plinth.position = at
    add_child(plinth)

func _build_dioramas() -> void:
    grove = ProtoDiorama.grove()
    grove.position = GROVE_POS
    add_child(grove)
    cinder = ProtoDiorama.cinder()
    cinder.position = CINDER_POS
    add_child(cinder)

# --- ui ---------------------------------------------------------------------

func _build_ui() -> void:
    ui = CanvasLayer.new()
    add_child(ui)

    var vignette := TextureRect.new()
    vignette.texture = load("res://assets/proto/ui/vignette.png")
    vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
    vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    ui.add_child(vignette)

    arrow_layer = Control.new()
    arrow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
    arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    arrow_layer.draw.connect(_draw_arrow)
    ui.add_child(arrow_layer)

    hand = ProtoHand.new()
    hand.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    hand.offset_top = -330.0
    hand.offset_left = 240.0
    hand.offset_right = -240.0
    hand.card_clicked.connect(_on_card_clicked)
    ui.add_child(hand)

    status_label = Label.new()
    status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    status_label.offset_top = -330.0
    status_label.offset_left = -420.0
    status_label.offset_right = 420.0
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status_label.add_theme_font_size_override("font_size", 17)
    status_label.add_theme_color_override("font_color", Color("#e8dfcf"))
    status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
    status_label.add_theme_constant_override("shadow_offset_y", 2)
    ui.add_child(status_label)

    banner = Label.new()
    banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
    banner.offset_top = 18.0
    banner.offset_left = -420.0
    banner.offset_right = 420.0
    banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner.add_theme_font_size_override("font_size", 21)
    banner.add_theme_color_override("font_color", Color("#f0d68a"))
    banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
    banner.add_theme_constant_override("shadow_offset_y", 2)
    ui.add_child(banner)

    inspect_panel = TextureRect.new()
    inspect_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    inspect_panel.stretch_mode = TextureRect.STRETCH_SCALE
    inspect_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    inspect_panel.custom_minimum_size = Vector2(300, 420)
    inspect_panel.size = Vector2(300, 420)
    inspect_panel.position = Vector2(26, 130)
    inspect_panel.visible = false
    inspect_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(inspect_panel)

    end_turn_btn = Button.new()
    end_turn_btn.text = "END TURN"
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.12, 0.10, 0.16, 0.88)
    sb.border_color = Color("#c9a34c")
    sb.set_border_width_all(2)
    sb.set_corner_radius_all(10)
    sb.content_margin_left = 26; sb.content_margin_right = 26
    sb.content_margin_top = 12; sb.content_margin_bottom = 12
    end_turn_btn.add_theme_stylebox_override("normal", sb)
    var sb2 := sb.duplicate()
    sb2.bg_color = Color(0.2, 0.16, 0.24, 0.92)
    end_turn_btn.add_theme_stylebox_override("hover", sb2)
    end_turn_btn.add_theme_color_override("font_color", Color("#f0d68a"))
    end_turn_btn.add_theme_font_size_override("font_size", 18)
    end_turn_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    end_turn_btn.offset_left = -190.0
    end_turn_btn.offset_top = -96.0
    end_turn_btn.offset_right = -30.0
    end_turn_btn.offset_bottom = -40.0
    end_turn_btn.pressed.connect(_on_end_turn)
    ui.add_child(end_turn_btn)

    aether_pips = Control.new()
    aether_pips.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    aether_pips.offset_left = 34.0
    aether_pips.offset_top = -78.0
    aether_pips.offset_right = 260.0
    aether_pips.offset_bottom = -30.0
    aether_pips.draw.connect(_draw_aether)
    ui.add_child(aether_pips)

    _heart_label(true)
    _heart_label(false)

func _heart_label(mine: bool) -> void:
    var l := Label.new()
    l.name = "heart_player" if mine else "heart_enemy"
    l.add_theme_font_size_override("font_size", 26)
    l.add_theme_color_override("font_color", Color("#ff9ab8"))
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    l.add_theme_constant_override("shadow_offset_y", 2)
    l.text = "20"
    ui.add_child(l)

func _draw_aether() -> void:
    for i in range(5):
        var at := Vector2(20 + i * 40, 24)
        if i < aether:
            aether_pips.draw_circle(at, 12.0, Color(0.36, 0.5, 0.95, 0.35))
            aether_pips.draw_circle(at, 8.0, Color(0.55, 0.68, 1.0))
            aether_pips.draw_circle(at - Vector2(2.5, 2.5), 3.0, Color(0.9, 0.95, 1.0, 0.9))
        else:
            aether_pips.draw_arc(at, 9.0, 0, TAU, 24, Color(0.5, 0.55, 0.7, 0.5), 2.0)

func _draw_arrow() -> void:
    if mode != "attack" or player_creature == null: return
    var from := camera.unproject_position(player_creature.global_position + Vector3(0, 0.5, 0))
    var to := arrow_layer.get_local_mouse_position()
    var mid := (from + to) * 0.5 + Vector2(0, -90)
    var prev := from
    for i in range(1, 17):
        var t := float(i) / 16.0
        var p := from.lerp(mid, t).lerp(mid.lerp(to, t), t)
        if i % 2 == 1:
            arrow_layer.draw_line(prev, p, Color(0.95, 0.8, 0.35, 0.9), 4.0)
        prev = p
    var dir := (to - prev).normalized()
    var n := Vector2(-dir.y, dir.x)
    arrow_layer.draw_colored_polygon(PackedVector2Array([
        to + dir * 16.0, to - dir * 6.0 + n * 11.0, to - dir * 6.0 - n * 11.0]),
        Color(0.95, 0.8, 0.35, 0.95))

func _deal_hand() -> void:
    for id in ["sprigget", "wild_bloom", "sprigget", "wild_bloom"]:
        if not card_textures.has(id):
            card_textures[id] = load("res://assets/proto/cards/%s.png" % id)
    card_textures["cinderbelly"] = load("res://assets/proto/cards/cinderbelly.png")
    card_textures["ember_storm"] = load("res://assets/proto/cards/ember_storm.png")
    hand.set_cards([
        {"id": "sprigget", "tex": card_textures["sprigget"], "cost": 3},
        {"id": "wild_bloom", "tex": card_textures["wild_bloom"], "cost": 2},
        {"id": "sprigget", "tex": card_textures["sprigget"], "cost": 3},
        {"id": "wild_bloom", "tex": card_textures["wild_bloom"], "cost": 2},
    ])
    _refresh_playable()

func _refresh_playable() -> void:
    for i in range(hand.cards.size()):
        var id := String(hand.cards[i]["id"])
        var cost := int(hand.cards[i]["cost"])
        var ok := aether >= cost
        if id == "sprigget" and player_creature != null: ok = false
        if id == "wild_bloom" and player_creature == null: ok = false
        hand.set_playable(i, ok)

func _banner(text: String) -> void:
    banner.text = text
    banner.modulate = Color(1, 1, 1, 0)
    var tw := banner.create_tween()
    tw.tween_property(banner, "modulate:a", 1.0, 0.3)

func _status(text: String) -> void:
    status_label.text = text

# --- interaction ------------------------------------------------------------

func _on_card_clicked(index: int) -> void:
    if not bool(hand.cards[index]["playable"]):
        var id := String(hand.cards[index]["id"])
        if id == "sprigget" and player_creature != null:
            _status("The Grove already has a resident.")
        elif id == "wild_bloom" and player_creature == null:
            _status("Wild Bloom needs a creature to bless.")
        else:
            _status("Not enough Aether.")
        return
    if selected_card == index:
        _clear_selection()
        return
    selected_card = index
    mode = "card"
    hand.set_selected(index)
    grove.set_highlight(true)
    var id2 := String(hand.cards[index]["id"])
    _status("The Grove is glowing — click it to %s." %
        ("summon Sprigget" if id2 == "sprigget" else "cast Wild Bloom"))

func _clear_selection() -> void:
    selected_card = -1
    mode = ""
    hand.set_selected(-1)
    grove.set_highlight(false)
    cinder.set_highlight(false)
    arrow_layer.queue_redraw()
    _status("")

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed \
            and event.button_index == MOUSE_BUTTON_LEFT:
        _click(event.position)
    elif event is InputEventMouseMotion:
        if mode == "attack": arrow_layer.queue_redraw()
        _hover_inspect(event.position)

func _click(at: Vector2) -> void:
    var grove_px := camera.unproject_position(grove.global_position + Vector3(0, 0.1, 0))
    var enemy_px := camera.unproject_position(cinder.global_position + Vector3(0, 0.4, 0))
    var own_px := Vector2(-999, -999)
    if player_creature != null:
        own_px = camera.unproject_position(player_creature.global_position + Vector3(0, 0.4, 0))

    if mode == "card" and at.distance_to(grove_px) < 170.0:
        var id := String(hand.cards[selected_card]["id"])
        if id == "sprigget": _play_summon()
        else: _play_wild_bloom()
        return
    if mode == "attack":
        if enemy_creature != null and at.distance_to(enemy_px) < 150.0:
            _start_attack()
            return
        mode = ""
        arrow_layer.queue_redraw()
        _status("")
        return
    if player_creature != null and player_creature.ready_to_act \
            and at.distance_to(own_px) < 110.0 and enemy_creature != null:
        mode = "attack"
        _status("Sprigget is ready — choose a target.")
        arrow_layer.queue_redraw()
        return
    if mode == "card":
        _clear_selection()

func _hover_inspect(at: Vector2) -> void:
    var show: Texture2D = null
    if enemy_creature != null:
        var px := camera.unproject_position(enemy_creature.global_position + Vector3(0, 0.45, 0))
        if at.distance_to(px) < 95.0: show = card_textures["cinderbelly"]
    if show == null and player_creature != null:
        var px2 := camera.unproject_position(player_creature.global_position + Vector3(0, 0.45, 0))
        if at.distance_to(px2) < 95.0: show = card_textures["sprigget"]
    inspect_panel.texture = show
    inspect_panel.visible = show != null

func _on_end_turn() -> void:
    _clear_selection()
    aether = 5
    if player_creature != null: player_creature.ready_to_act = true
    aether_pips.queue_redraw()
    _refresh_playable()
    _enemy_turn()

# --- the scripted rival -----------------------------------------------------

func _enemy_turn() -> void:
    enemy_step += 1
    if enemy_step == 1 and enemy_creature == null:
        _banner("Poppy Cinder summons…")
        _enemy_summon()
    elif enemy_step == 2 and player_creature != null:
        _banner("Poppy Cinder casts Ember Storm!")
        _play_ember_storm()
    elif enemy_creature != null and player_creature != null:
        _banner("Cinderbelly attacks!")
        _start_attack_enemy()
    else:
        _banner("Your move")

# --- choreography -----------------------------------------------------------

func _process(delta: float) -> void:
    var live: Array = []
    for act in acts:
        act["t"] = float(act["t"]) + delta
        _tick(act)
        if float(act["t"]) < float(act["dur"]): live.append(act)
    acts = live
    if _shake > 0.0:
        _shake = maxf(0.0, _shake - delta * 3.2)
        camera.transform = _cam_home
        camera.position += Vector3(sin(_shake * 47.0), cos(_shake * 39.0), 0) * _shake * 0.05
    if acts.is_empty() and _shake <= 0.0:
        camera.transform = _cam_home

func busy() -> bool:
    return not acts.is_empty()

func _at(act: Dictionary, key: String, frac: float) -> bool:
    if act.has(key): return false
    if float(act["t"]) / float(act["dur"]) < frac: return false
    act[key] = true
    return true

func _play(kind: String, data: Dictionary, dur: float) -> void:
    var act := data.duplicate()
    act["kind"] = kind
    act["t"] = 0.0
    act["dur"] = dur
    acts.append(act)

func _float_label(world: Vector3, text: String, colour: Color) -> void:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", 34)
    l.add_theme_color_override("font_color", colour)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    l.add_theme_constant_override("shadow_offset_y", 3)
    l.position = camera.unproject_position(world) - Vector2(20, 0)
    ui.add_child(l)
    var tw := l.create_tween().set_parallel(true)
    tw.tween_property(l, "position:y", l.position.y - 70.0, 1.0) \
        .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.35)
    get_tree().create_timer(1.5).timeout.connect(func() -> void:
        if is_instance_valid(l): l.queue_free())

# --- summoning --------------------------------------------------------------

func _play_summon() -> void:
    aether -= 3
    aether_pips.queue_redraw()
    var start_px: Vector2 = (hand.cards[selected_card]["node"] as Control).global_position \
        + Vector2(ProtoHand.CARD_W * 0.5, 40.0)
    hand.remove_card(selected_card)
    _clear_selection()
    _refresh_playable()
    _summon("player", start_px)

func _enemy_summon() -> void:
    _summon("enemy", camera.unproject_position(Vector3(-3.45, 0.3, -1.85)))

func _summon(side: String, from_px: Vector2) -> void:
    var diorama := grove if side == "player" else cinder
    var card_tex: Texture2D = card_textures["sprigget" if side == "player" else "cinderbelly"]
    # The physical card that flies from the hand and tucks in as a plaque.
    var card := Node3D.new()
    var q := QuadMesh.new()
    q.size = Vector2(0.62, 0.87)
    var m := StandardMaterial3D.new()
    m.albedo_texture = card_tex
    m.roughness = 0.55
    var mi := MeshInstance3D.new()
    mi.mesh = q
    mi.material_override = m
    mi.rotation_degrees = Vector3(0, 180, 0)
    card.add_child(mi)
    var back := MeshInstance3D.new()
    back.mesh = q
    var bm := StandardMaterial3D.new()
    bm.albedo_texture = load("res://assets/proto/cards/card_back.png")
    back.material_override = bm
    back.position.z = -0.003
    card.add_child(back)
    add_child(card)
    # Start where the hand card was: a point along the camera ray.
    var origin := camera.project_ray_origin(from_px)
    var dir := camera.project_ray_normal(from_px)
    card.position = origin + dir * 1.6
    card.look_at(camera.global_position)
    _play("summon", {"side": side, "card": card, "diorama": diorama,
        "from": card.position}, SUMMON_DUR)

func _tick(act: Dictionary) -> void:
    match String(act["kind"]):
        "summon": _tick_summon(act)
        "attack": _tick_attack(act)
        "bloom": _tick_bloom(act)
        "storm": _tick_storm(act)
        "death": pass

func _tick_summon(act: Dictionary) -> void:
    var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
    var card: Node3D = act["card"]
    var diorama: ProtoDiorama = act["diorama"]
    var side := String(act["side"])
    var plaque := diorama.plaque_anchor()
    var hover := diorama.global_position + Vector3(0, 1.1, 0)
    if t < 0.42:
        # The card flies from the hand to hover over its new home.
        var k := t / 0.42
        var e := 1.0 - pow(1.0 - k, 2.4)
        var from: Vector3 = act["from"]
        var p := from.lerp(hover, e)
        p.y += sin(e * PI) * 0.5
        card.position = p
        var face_cam := card.global_transform.looking_at(camera.global_position, Vector3.UP)
        card.global_transform.basis = card.global_transform.basis.slerp(
            face_cam.basis.rotated(Vector3.RIGHT, -0.9 * e), 0.4)
    elif t < 0.62:
        # It settles down into the plaque slot at the diorama's front edge.
        var k2 := (t - 0.42) / 0.2
        var e2 := k2 * k2 * (3.0 - 2.0 * k2)
        card.position = hover.lerp(plaque, e2)
        card.rotation = Vector3(-1.25 * e2 - 0.35, 0.0, 0.0)
        card.scale = Vector3.ONE * (1.0 - 0.55 * e2)
        if _at(act, "shock", 0.55):
            var colour := Color(0.55, 1.0, 0.45) if side == "player" else Color(1.0, 0.55, 0.2)
            ProtoFX.ring_shock(self, diorama.global_position + Vector3(0, 0.16, 0), colour, 1.7)
            ProtoFX.beam(self, diorama.creature_anchor(), colour)
            ProtoFX.light_pulse(self, diorama.global_position, colour, 3.0, 0.7)
            _shake = maxf(_shake, 0.35)
    else:
        if _at(act, "spawn", 0.62):
            var burst_col := Color(0.6, 1.0, 0.4) if side == "player" else Color(1.0, 0.6, 0.2)
            ProtoFX.burst(self, diorama.creature_anchor() + Vector3(0, 0.3, 0), burst_col,
                "leaf" if side == "player" else "soft_dot", 34, 2.2, 0.8, side != "player")
            var creature := ProtoCreature.make(
                "res://assets/proto/creatures/%s.png" % ("sprigget" if side == "player" else "cinderbelly"),
                "Sprigget" if side == "player" else "Cinderbelly",
                "life" if side == "player" else "fire",
                1.32 if side == "player" else 1.46,
                3 if side == "player" else 4,
                8 if side == "player" else 10)
            creature.position = diorama.creature_anchor()
            creature.ready_to_act = false
            add_child(creature)
            if side == "player": player_creature = creature
            else: enemy_creature = creature
            act["creature"] = creature
        var creature2: ProtoCreature = act["creature"]
        var k3 := (t - 0.62) / 0.38
        var pop := 1.0
        if k3 < 0.55: pop = 1.2 * (k3 / 0.55)
        else: pop = 1.2 - 0.2 * ((k3 - 0.55) / 0.45)
        creature2.set_visual(Vector3.ZERO, Vector2(pop, pop), Color(1, 1, 1), pop, false)
        if t >= 0.999:
            creature2.set_visual(Vector3.ZERO, Vector2.ONE, Color(1, 1, 1), 1.0, true)
            creature2.ready_to_act = String(act["side"]) == "player"
            _refresh_playable()
            if String(act["side"]) == "player":
                _banner("Sprigget settles into the Grove")
                _status("End your turn — or click Sprigget once a foe appears.")
            else:
                _banner("Cinderbelly squats on the Cinder — your move")
                _status("Click Sprigget, then click Cinderbelly to attack.")

## Instantly place a resident — the capture harness uses this to stage states.
func place_instant(side: String) -> void:
    var diorama := grove if side == "player" else cinder
    var creature := ProtoCreature.make(
        "res://assets/proto/creatures/%s.png" % ("sprigget" if side == "player" else "cinderbelly"),
        "Sprigget" if side == "player" else "Cinderbelly",
        "life" if side == "player" else "fire",
        1.32 if side == "player" else 1.46,
        3 if side == "player" else 4, 8 if side == "player" else 10)
    creature.position = diorama.creature_anchor()
    add_child(creature)
    if side == "player":
        player_creature = creature
        var idx := -1
        for i in range(hand.cards.size()):
            if String(hand.cards[i]["id"]) == "sprigget": idx = i; break
        if idx >= 0: hand.remove_card(idx)
    else: enemy_creature = creature
    var card := Node3D.new()
    var q := QuadMesh.new()
    q.size = Vector2(0.62, 0.87)
    var m := StandardMaterial3D.new()
    m.albedo_texture = card_textures["sprigget" if side == "player" else "cinderbelly"]
    var mi := MeshInstance3D.new()
    mi.mesh = q
    mi.material_override = m
    card.add_child(mi)
    card.position = diorama.plaque_anchor()
    card.rotation = Vector3(-1.6, 0, 0)
    card.scale = Vector3.ONE * 0.45
    add_child(card)
    _refresh_playable()

# --- combat -----------------------------------------------------------------

func _start_attack() -> void:
    mode = ""
    arrow_layer.queue_redraw()
    player_creature.ready_to_act = false
    _status("")
    _play("attack", {"attacker": player_creature, "defender": enemy_creature,
        "colour": Color(0.6, 1.0, 0.4), "sprite": "leaf", "damage": 3}, ATTACK_DUR)

func _start_attack_enemy() -> void:
    _play("attack", {"attacker": enemy_creature, "defender": player_creature,
        "colour": Color(1.0, 0.6, 0.2), "sprite": "soft_dot", "damage": 5}, ATTACK_DUR)

func _tick_attack(act: Dictionary) -> void:
    var t: float = clampf(float(act["t"]) / float(act["dur"]), 0.0, 1.0)
    var attacker: ProtoCreature = act["attacker"]
    var defender: ProtoCreature = act["defender"]
    if not is_instance_valid(attacker) or not is_instance_valid(defender): return
    var home := attacker.global_position
    if not act.has("home"):
        act["home"] = home
        act["target"] = defender.global_position
    var from: Vector3 = act["home"]
    var to: Vector3 = act["target"]
    var dir := (to - from).normalized()

    if t < 0.16:
        # Anticipation: crouch back and charge up.
        var k := t / 0.16
        attacker.set_visual(-dir * 0.14 * k, Vector2(1.0 + 0.14 * k, 1.0 - 0.14 * k),
            Color(1.15, 1.15, 1.0), 1.0, false)
    elif t < 0.52:
        # The leap: a real arc across the table.
        var k2 := (t - 0.16) / 0.36
        var e := k2 * k2 * (3.0 - 2.0 * k2)
        var p := from.lerp(to - dir * 0.78 + Vector3(0, 0, 0.42), e)
        p.y += sin(e * PI) * 1.05
        attacker.set_visual(p - from, Vector2(0.92, 1.12), Color(1.05, 1.05, 1.0),
            maxf(0.25, 1.0 - sin(e * PI) * 0.8), false)
        if _at(act, "impact", 0.505):
            var hit := to + Vector3(0, 0.55, 0)
            ProtoFX.flash(self, hit, Color(1.0, 0.95, 0.8), 1.0)
            ProtoFX.burst(self, hit, act["colour"], String(act["sprite"]), 30, 2.6, 0.5,
                String(act["sprite"]) != "leaf")
            ProtoFX.burst(self, hit, Color(1.0, 0.9, 0.5), "spark", 14, 3.2, 0.4)
            ProtoFX.light_pulse(self, to, act["colour"], 2.6, 0.4)
            _shake = 0.55
            _float_label(hit + Vector3(0, 0.3, 0), "-%d" % int(act["damage"]),
                Color(1.0, 0.45, 0.5))
            defender.hp -= int(act["damage"])
    elif t < 0.66:
        # Impact hold: the defender takes it.
        var k3 := (t - 0.52) / 0.14
        attacker.set_visual(to - dir * 0.78 + Vector3(0, 0.04, 0.42) - from,
            Vector2(1.14, 0.86), Color(1, 1, 1), 1.0, false)
        defender.set_visual(dir * 0.22 * (1.0 - k3), Vector2(1.0 + 0.18 * (1.0 - k3),
            1.0 - 0.18 * (1.0 - k3)), Color(1.6, 0.75, 0.75), 1.0, false)
    elif t < 0.94:
        # Home again, low arc.
        var k4 := (t - 0.66) / 0.28
        var e2 := k4 * k4 * (3.0 - 2.0 * k4)
        var p2: Vector3 = (to - dir * 0.78 + Vector3(0, 0, 0.42)).lerp(from, e2)
        p2.y += sin(e2 * PI) * 0.5
        attacker.set_visual(p2 - from, Vector2(1.0, 1.0), Color(1, 1, 1),
            maxf(0.3, 1.0 - sin(e2 * PI) * 0.6), false)
        defender.set_visual(Vector3.ZERO, Vector2.ONE, Color(1, 1, 1), 1.0, true)
    else:
        var k5 := (t - 0.94) / 0.06
        attacker.set_visual(Vector3.ZERO, Vector2(1.0 + 0.1 * (1.0 - k5),
            1.0 - 0.1 * (1.0 - k5)), Color(1, 1, 1), 1.0, k5 > 0.9)
        if _at(act, "resolve", 0.97):
            if defender.hp <= 0: _die(defender)
            elif is_instance_valid(defender):
                defender.set_visual(Vector3.ZERO, Vector2.ONE, Color(1, 1, 1), 1.0, true)

func _die(creature: ProtoCreature) -> void:
    var was_enemy := creature == enemy_creature
    if was_enemy: enemy_creature = null
    else: player_creature = null
    _banner("%s is undone!" % creature.display_name)
    ProtoFX.burst(self, creature.global_position + Vector3(0, 0.4, 0),
        Color(0.7, 0.65, 0.8), "puff", 16, 1.2, 0.9, false, 1.2)
    var tw := creature.create_tween()
    tw.tween_method(func(v: float) -> void:
        if is_instance_valid(creature):
            creature.set_visual(Vector3(0, -0.25 * v, 0), Vector2(1.0 + 0.2 * v, 1.0 - 0.6 * v),
                Color(0.8, 0.8, 0.85, 1.0 - v), 1.0 - v, false),
        0.0, 1.0, 0.7)
    tw.tween_callback(func() -> void:
        if is_instance_valid(creature): creature.queue_free())

# --- spells -----------------------------------------------------------------

func _play_wild_bloom() -> void:
    aether -= 2
    aether_pips.queue_redraw()
    hand.remove_card(selected_card)
    _clear_selection()
    _refresh_playable()
    _banner("Wild Bloom!")
    _play("bloom", {}, SPELL_DUR)

func _tick_bloom(act: Dictionary) -> void:
    if _at(act, "rune", 0.02):
        ProtoFX.ring_shock(self, grove.global_position + Vector3(0, 0.14, 0),
            Color(0.55, 1.0, 0.45), 1.6, 0.8)
        ProtoFX.light_pulse(self, grove.global_position, Color(0.5, 1.0, 0.4), 2.6, 1.0)
    if _at(act, "grow", 0.18):
        ProtoFX.grow_bloom(self, grove)
        ProtoFX.burst(self, grove.global_position + Vector3(0, 0.4, 0),
            Color(0.7, 1.0, 0.5), "leaf", 44, 2.4, 0.95, false, 1.3)
        ProtoFX.beam(self, grove.global_position, Color(0.55, 1.0, 0.45), 0.8)
        _shake = 0.4
    if _at(act, "second", 0.36):
        ProtoFX.ring_shock(self, grove.global_position + Vector3(0, 0.16, 0),
            Color(0.7, 1.0, 0.5), 2.1, 0.7)
        ProtoFX.burst(self, grove.global_position + Vector3(0, 0.3, 0),
            Color(1.0, 0.85, 0.95), "leaf", 26, 1.6, 0.9, false, 1.2)
    if _at(act, "heal", 0.55) and player_creature != null:
        player_creature.hp = mini(player_creature.max_hp, player_creature.hp + 3)
        _float_label(player_creature.global_position + Vector3(0, 1.0, 0), "+3",
            Color(0.6, 1.0, 0.55))
        player_creature.set_visual(Vector3.ZERO, Vector2.ONE, Color(0.8, 1.3, 0.8), 1.0, true)
    if float(act["t"]) >= float(act["dur"]) - 0.05 and player_creature != null:
        player_creature.set_visual(Vector3.ZERO, Vector2.ONE, Color(1, 1, 1), 1.0, true)

func _play_ember_storm() -> void:
    _play("storm", {}, SPELL_DUR)

func _tick_storm(act: Dictionary) -> void:
    # A front of fire rolls out of the Cinder and breaks over the Grove. A spell
    # has to visibly change the world, so it also leaves scorch behind.
    if _at(act, "charge", 0.03):
        ProtoFX.ring_shock(self, cinder.global_position + Vector3(0, 0.16, 0),
            Color(1.0, 0.5, 0.15), 1.9, 0.6)
        ProtoFX.light_pulse(self, cinder.global_position, Color(1.0, 0.5, 0.15), 3.2, 0.6)
        ProtoFX.burst(self, cinder.global_position + Vector3(0, 0.4, 0),
            Color(1.0, 0.6, 0.2), "soft_dot", 30, 2.0, 0.9)
        _shake = 0.5
    if _at(act, "wall", 0.16):
        ProtoFX.fire_wall(self, cinder.global_position + Vector3(0, 0.18, 0.7),
            grove.global_position + Vector3(0, 0.22, -0.2), 0.9)
    for i in range(5):
        if _at(act, "cone_%d" % i, 0.24 + float(i) * 0.085):
            var frac := float(i) / 4.0
            var p := cinder.global_position.lerp(grove.global_position, 0.28 + frac * 0.78)
            p.x += (ProtoMesh.hashf(i, 3, 7) - 0.5) * 1.5
            p.y = TABLE_Y
            if frac > 0.45:
                p.y = grove.global_position.y + grove.surface_height(
                    p.x - grove.global_position.x, p.z - grove.global_position.z)
            ProtoFX.flame_cone(self, p, 0.85 + frac * 0.65)
            _shake = maxf(_shake, 0.45)
    if _at(act, "hit", 0.66) and player_creature != null:
        player_creature.hp -= 2
        ProtoFX.flash(self, player_creature.global_position + Vector3(0, 0.5, 0),
            Color(1.0, 0.7, 0.4), 1.4)
        _float_label(player_creature.global_position + Vector3(0, 1.1, 0), "-2",
            Color(1.0, 0.5, 0.4))
        player_creature.set_visual(Vector3.ZERO, Vector2(1.12, 0.88),
            Color(1.7, 0.7, 0.6), 1.0, false)
        _shake = 0.7
    if float(act["t"]) >= float(act["dur"]) - 0.05 and player_creature != null:
        player_creature.set_visual(Vector3.ZERO, Vector2.ONE, Color(1, 1, 1), 1.0, true)
        _banner("Your move")

func _first_process_setup() -> void:
    pass

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_SIZE_CHANGED or what == NOTIFICATION_READY:
        call_deferred("_place_heart_labels")

func _place_heart_labels() -> void:
    if ui == null or camera == null: return
    var lp := ui.get_node_or_null("heart_player")
    var le := ui.get_node_or_null("heart_enemy")
    if lp != null:
        lp.position = camera.unproject_position(Vector3(-2.62, 0.82, 1.72)) - Vector2(14, 16)
        lp.text = str(player_heart)
    if le != null:
        le.position = camera.unproject_position(Vector3(2.62, 0.82, -2.05)) - Vector2(14, 16)
        le.text = str(enemy_heart)
