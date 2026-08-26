class_name CardFlight
extends Control
## The played card physically travels from the hand to where it lands.
##
## Purely cosmetic: the simulation already resolved before this is created, so
## the flight can never delay or change an outcome.

var accent: Color = Color.WHITE
var label := ""
var role := ""
var from_pos := Vector2.ZERO
var to_pos := Vector2.ZERO
var _t := 0.0
var _life := 0.42

func launch(start: Vector2, target: Vector2, card_name: String, role_name: String, tint: Color) -> void:
    from_pos = start
    to_pos = target
    label = card_name
    role = role_name
    accent = tint
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    z_index = 90
    set_process(true)

func _process(delta: float) -> void:
    _t += delta
    if _t >= _life:
        queue_free()
        return
    queue_redraw()

func _draw() -> void:
    var k: float = clampf(_t / _life, 0.0, 1.0)
    # Ease out, with a small arc so the card feels thrown rather than slid.
    var eased: float = 1.0 - pow(1.0 - k, 2.6)
    var at: Vector2 = from_pos.lerp(to_pos, eased)
    at.y -= sin(eased * PI) * 46.0
    # Shrinks as it flies away from the hand and into the world.
    var scale: float = 1.0 - 0.55 * eased
    var card := Vector2(120, 158) * scale
    var rect := Rect2(at - card * 0.5, card)

    draw_set_transform(rect.get_center(), (1.0 - eased) * 0.35 - 0.12, Vector2.ONE)
    var local := Rect2(-card * 0.5, card)
    draw_style_box(ArcanaTheme.panel_box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 10, 0), local.grow(5.0))
    draw_style_box(ArcanaTheme.panel_box(ArcanaTheme.PANEL.lightened(0.08), accent, 9, 3), local)
    draw_style_box(ArcanaTheme.panel_box(Color(accent, 0.30), Color(accent, 0.0), 7, 0),
        Rect2(local.position + Vector2(4, 4), Vector2(local.size.x - 8, 18 * scale)))
    var f := ArcanaTheme.font()
    draw_string(f, local.position + Vector2(7, 40 * scale),
        ArcanaTheme.fit(label, int(13 * scale) + 1, local.size.x - 14),
        HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * scale) + 1, ArcanaTheme.TEXT)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

    # Trailing motes so the flight reads as magic, not a sliding rectangle.
    for i in range(5):
        var trail: float = maxf(0.0, eased - 0.05 * float(i + 1))
        var tp: Vector2 = from_pos.lerp(to_pos, trail)
        tp.y -= sin(trail * PI) * 46.0
        draw_circle(tp, 5.0 - float(i), Color(accent, 0.22 * (1.0 - float(i) / 5.0)))
