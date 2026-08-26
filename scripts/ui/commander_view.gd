class_name CommanderView
extends Control
## A Commander as a character standing at their side of the board, carrying the
## few numbers that actually matter. Replaces the old dashboard scoreboard row.

signal command_pressed

const WIDTH := 150.0

var engine: MatchEngine
var art: ArtRegistry
var player := 0
var is_active := false
var _pulse := 0.0
var _hover_command := false

func _ready() -> void:
    custom_minimum_size = Vector2(WIDTH, 0)
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_process(true)

func _process(delta: float) -> void:
    _pulse = fmod(_pulse + delta, 1.0)
    queue_redraw()

func _command_rect() -> Rect2:
    return Rect2(8, size.y - 46, size.x - 16, 30)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        _hover_command = _command_rect().has_point(event.position)
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if player == 0 and _command_rect().has_point(event.position): command_pressed.emit()

func _draw() -> void:
    if engine == null or engine.players.size() <= player: return
    var f := ArcanaTheme.font()
    var p: Dictionary = engine.players[player]
    var cmd: Dictionary = engine.db.get_commander(String(p["commander_id"]))
    var colour: Color = ArcanaTheme.owner_color(player)

    # The character: a standing pool of light, then the avatar over it.
    var avatar_h: float = min(size.x * 1.05, 168.0)
    var centre := Vector2(size.x * 0.5, 20.0 + avatar_h * 0.5)
    var breathe: float = 0.5 + 0.5 * sin(_pulse * TAU + player * PI)
    if is_active:
        for i in range(6):
            var t := float(i) / 6.0
            draw_circle(centre, avatar_h * (0.52 - t * 0.22), Color(colour, 0.05 + 0.04 * breathe))
    draw_circle(Vector2(centre.x, centre.y + avatar_h * 0.40), avatar_h * 0.26, Color(0, 0, 0, 0.30))

    var tex: Texture2D = art.commander_board(String(p["commander_id"])) if art != null else null
    if tex != null:
        var src := Vector2(tex.get_width(), tex.get_height())
        var scale: float = min(size.x * 0.86 / src.x, avatar_h * 0.94 / src.y)
        var drawn := src * scale
        draw_texture_rect(tex, Rect2(centre - drawn * 0.5, drawn), false)
    else:
        draw_arc(centre, avatar_h * 0.34, 0, TAU, 32, Color(colour, 0.8), 3.0)

    var y := 20.0 + avatar_h + 6.0
    var name := String(cmd.get("name", "Commander"))
    var nw: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
    draw_string(f, Vector2(size.x * 0.5 - nw * 0.5, y), name,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, colour)
    y += 8.0

    # Heart as a bar: a shape you can read without reading a number.
    y += 14.0
    var heart := int(p["heart"])
    var bar := Rect2(10, y, size.x - 20, 14)
    draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.85), Color(ArcanaTheme.HEART, 0.45), 7, 1), bar)
    var frac: float = clampf(float(heart) / float(MatchEngine.HEART_CAP), 0.0, 1.0)
    if frac > 0.0:
        draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.HEART, 0.80), Color(ArcanaTheme.HEART, 0.0), 7, 0),
            Rect2(bar.position + Vector2(1, 1), Vector2((bar.size.x - 2) * frac, bar.size.y - 2)))
    draw_string(f, Vector2(bar.position.x + 6, bar.position.y + 11), "♥ %d" % heart,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT)
    y += 22.0

    # Seals, Wonder, Aether, hand — icons and counts, no table.
    var seals := ""
    for i in range(MatchEngine.SEALS_TO_WIN):
        seals += "◆" if i < int(p["seals"]) else "◇"
    draw_string(f, Vector2(10, y + 11), seals, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ArcanaTheme.SEAL)
    var wonder := "✦ %d" % int(p["wonder"])
    var ww: float = f.get_string_size(wonder, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
    draw_string(f, Vector2(size.x - 10 - ww, y + 11), wonder,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.WONDER)
    y += 20.0

    # Aether pips read as a resource, not a fraction in a status bar.
    var maxa: int = int(p["max_aether"])
    var cur: int = int(p["aether"])
    var pip_r := 4.0
    var span: float = min(size.x - 20.0, float(maxi(maxa, 1)) * (pip_r * 2.0 + 3.0))
    var step: float = span / float(maxi(maxa, 1))
    for i in range(maxa):
        var c: Color = ArcanaTheme.AETHER if i < cur else ArcanaTheme.PANEL_EDGE
        draw_circle(Vector2(10 + step * (i + 0.5), y + 6), pip_r, c)
    draw_string(f, Vector2(size.x - 34, y + 10), "✋%d" % p["hand"].size(),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT_DIM)

    if bool(p["passed"]):
        draw_string(f, Vector2(10, y + 30), "passed this Chapter",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ArcanaTheme.TEXT_FAINT)

    # Only the human's Commander offers a button, and only while it is usable.
    if player == 0:
        var usable: bool = is_active and not bool(p["commander_used"]) and not engine.match_over
        var r := _command_rect()
        var edge: Color = ArcanaTheme.GOLD if usable else ArcanaTheme.PANEL_EDGE
        var fill: Color = Color(ArcanaTheme.GOLD, 0.22 if (usable and _hover_command) else 0.10)
        draw_style_box(ArcanaTheme.panel_box(fill, edge, 8, 2), r)
        var label := "COMMAND" if not bool(p["commander_used"]) else "COMMAND USED"
        var lw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
        draw_string(f, Vector2(r.get_center().x - lw * 0.5, r.get_center().y + 4), label,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            ArcanaTheme.GOLD if usable else ArcanaTheme.TEXT_FAINT)
