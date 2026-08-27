class_name ProtoCreature
extends Node3D
## A resident of a landscape: the illustrated character standing on the
## miniature world, as a 2.5D cutout.
##
## The billboard technique is a prototype choice, not a production commitment.
## All motion is applied from outside (proto_main's choreography) through
## `set_visual`, so the same actor works for idle, attack, hurt and death.

var art_path := ""
var world_height := 0.9
var atk := 3
var hp := 8
var max_hp := 8
var display_name := ""
var element := "life"
var ready_to_act := true

var _quad: MeshInstance3D
var _mat: StandardMaterial3D
var _shadow: MeshInstance3D
var _t := 0.0
var _idle_on := true
var _base_offset := Vector3.ZERO      # choreography offset
var _base_squash := Vector2.ONE
var _shadow_scale := 1.0

static func make(art: String, name_v: String, element_v: String, height: float,
        atk_v: int, hp_v: int) -> ProtoCreature:
    var c := ProtoCreature.new()
    c.art_path = art
    c.display_name = name_v
    c.element = element_v
    c.world_height = height
    c.atk = atk_v
    c.hp = hp_v
    c.max_hp = hp_v
    return c

func _ready() -> void:
    var tex: Texture2D = load(art_path)
    var aspect := float(tex.get_width()) / float(tex.get_height())
    var q := QuadMesh.new()
    q.size = Vector2(world_height * aspect, world_height)
    _mat = StandardMaterial3D.new()
    _mat.albedo_texture = tex
    _mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
    _mat.billboard_keep_scale = true
    _quad = MeshInstance3D.new()
    _quad.mesh = q
    _quad.material_override = _mat
    _quad.position = Vector3(0, world_height * 0.5, 0)
    _quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_quad)

    var sq := QuadMesh.new()
    sq.size = Vector2(world_height * 0.66, world_height * 0.40)
    var sm := StandardMaterial3D.new()
    sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    sm.albedo_texture = load("res://assets/proto/ui/blob_shadow.png")
    _shadow = MeshInstance3D.new()
    _shadow.mesh = sq
    _shadow.material_override = sm
    _shadow.rotation.x = -PI / 2.0
    _shadow.position = Vector3(0, 0.012, 0)
    add_child(_shadow)
    set_process(true)

func _process(delta: float) -> void:
    _t += delta
    var idle_bob := 0.0
    var idle_squash := Vector2.ONE
    if _idle_on:
        idle_bob = sin(_t * 2.1) * 0.012
        idle_squash = Vector2(1.0 + sin(_t * 2.1) * 0.012, 1.0 - sin(_t * 2.1) * 0.012)
    _quad.position = Vector3(0, world_height * 0.5 * _base_squash.y + idle_bob, 0) + _base_offset
    _quad.scale = Vector3(_base_squash.x * idle_squash.x, _base_squash.y * idle_squash.y, 1.0)
    _shadow.scale = Vector3(_shadow_scale, _shadow_scale, 1.0)

## The choreography's single handle on this actor.
func set_visual(offset: Vector3, squash: Vector2, tint: Color, shadow_scale: float,
        idle := true) -> void:
    _base_offset = offset
    _base_squash = squash
    _mat.albedo_color = tint
    _shadow_scale = shadow_scale
    _idle_on = idle
