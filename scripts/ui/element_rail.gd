class_name ElementRail
extends Control
## The eight Shape elements as small magical runes rather than a button toolbar.
## The name appears on hover, so colour is never the only signal.

signal element_chosen(element: String)

const ORDER := ["frost", "lightning", "life", "fire", "water", "earth", "wind", "death"]
const COLS := 4
const R := 17.0

var engine: MatchEngine
var chosen := ""
var enabled_for_player := 0
var _hover := -1

func _ready() -> void:
    custom_minimum_size = Vector2(COLS * (R * 2 + 8) + 8, 2 * (R * 2 + 8) + 26)
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_process(true)

func _process(_d: float) -> void:
    queue_redraw()

func _centre(i: int) -> Vector2:
    return Vector2(8 + R + (i % COLS) * (R * 2 + 8), 22 + R + (i / COLS) * (R * 2 + 8))

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        _hover = -1
        for i in range(ORDER.size()):
            if event.position.distance_to(_centre(i)) <= R: _hover = i
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        for i in range(ORDER.size()):
            if event.position.distance_to(_centre(i)) <= R:
                element_chosen.emit(ORDER[i])
                return

func _draw() -> void:
    var f := ArcanaTheme.font()
    draw_string(f, Vector2(8, 14), "SHAPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT_FAINT)
    for i in range(ORDER.size()):
        var el: String = ORDER[i]
        var c: Color = ArcanaTheme.color_for_element(el)
        var centre := _centre(i)
        var usable := engine != null and not engine.match_open_blocked() \
            and not engine.legal_shape_tiles(enabled_for_player, el).is_empty()
        var active := chosen == el
        var alpha: float = 1.0 if usable else 0.28
        if active:
            draw_circle(centre, R + 4.0, Color(ArcanaTheme.GOLD, 0.35))
        draw_circle(centre, R, Color(c, 0.22 * alpha))
        draw_arc(centre, R, 0, TAU, 28, Color(c, (0.95 if active else 0.7) * alpha), 2.0)
        var icon := String(ArcanaTheme.element_icon.get(el, "*"))
        var w: float = f.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
        draw_string(f, Vector2(centre.x - w * 0.5, centre.y + 6), icon,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(ArcanaTheme.TEXT, alpha))
    if _hover >= 0:
        var el: String = ORDER[_hover]
        var label := String(ArcanaTheme.element_name.get(el, el))
        draw_string(f, Vector2(8, size.y - 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            ArcanaTheme.color_for_element(el))
