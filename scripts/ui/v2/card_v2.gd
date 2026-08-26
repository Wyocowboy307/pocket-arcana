class_name CardV2
extends Control
## A V2 card, laid out exactly as docs/V2_CARD_LANGUAGE.md specifies:
## cost top-left, name top-centre, element crest top-right, an unmistakable type
## ribbon, a large art window, then PLAY ON / TARGET, then at most two rules
## lines, with Attack and Health gems in the bottom corners of a creature.
##
## Type must read in grayscale, so each role also has its own frame silhouette.

signal card_clicked(card_id: String)
signal card_hovered(card_id: String)

const SIZE := Vector2(148, 158)
## A distinct glyph per role, so type reads before any text does.
const ROLE_GLYPH := {
    "Realm": "▰", "Creature": "❖", "Place": "⌂", "Spell": "✦",
}
const RIBBON := {
    "Realm": Color("#8bd0a0"), "Creature": Color("#e6d9a8"),
    "Place": Color("#c9b79a"), "Spell": Color("#d3b6e8"),
}

var card: Dictionary = {}
var card_id := ""
var role := "Spell"
var placement := ""
var block_reason := ""
var count := 1
var selected := false
var hovered := false
var art: ArtRegistry

func setup(data: Dictionary, role_name: String, placement_line: String,
           reason: String, registry: ArtRegistry) -> void:
    card = data
    card_id = String(data.get("id", ""))
    role = role_name
    placement = placement_line
    block_reason = reason
    art = registry
    custom_minimum_size = SIZE
    tooltip_text = "%s\n%s\n%s%s" % [String(card.get("name", "")), role, placement,
        "\n\n" + reason if reason != "" else ""]
    queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    custom_minimum_size = SIZE
    mouse_entered.connect(func() -> void: card_hovered.emit(card_id))

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        card_clicked.emit(card_id)

## Regions of the authored frame (tools/pixelart/cards.py). If these move,
## move them there too — the frame recesses every one of them so text always
## lands on a dark plate.
const NAME_Y := 5.0
const NAME_H := 20.0
const ROLE_Y := 27.0
const ROLE_H := 17.0
const ART_Y := 46.0
const ART_H := 62.0
const FOOT_Y := 110.0
const FOOT_H := 17.0
const RULES_Y := 129.0

func _draw() -> void:
    var f := ArcanaTheme.font()
    var playable := block_reason == ""
    var elements: Array = card.get("elements", [])
    var element := String(elements[0]) if not elements.is_empty() else "neutral"
    var accent: Color = ArcanaTheme.color_for_element(element) if not elements.is_empty() \
        else ArcanaTheme.TEXT_DIM
    var ribbon: Color = RIBBON.get(role, ArcanaTheme.TEXT_DIM)
    var rect := Rect2(Vector2.ZERO, size)
    var dim: Color = ArcanaTheme.TEXT if playable else ArcanaTheme.TEXT_FAINT

    var frame_key := "hand_frame:%s:%s" % [element, role.to_lower()]
    var frame: Texture2D = art.frame(frame_key) if art != null else null
    if frame == null and art != null:
        frame = art.frame("hand_frame:neutral:%s" % role.to_lower())

    if hovered or selected:
        draw_rect(rect.grow(7.0), Color(0, 0, 0, 0.34))
        draw_rect(rect.grow(3.0), Color(ArcanaTheme.GOLD if selected else accent, 0.55))

    if frame == null:
        # Procedural fallback, kept so a missing frame never blanks the hand.
        var body: Color = ArcanaTheme.PANEL.lightened(0.06) if playable else ArcanaTheme.PANEL.darkened(0.34)
        draw_style_box(ArcanaTheme.panel_box(body, accent, 8, 2), rect)
    else:
        var tint := Color(1, 1, 1, 1) if playable else Color(0.58, 0.56, 0.62, 1.0)
        draw_texture_rect(frame, rect, false, tint)

    # Art, inside the window the frame recessed for it.
    var win := Rect2(6.0, ART_Y + 1.0, size.x - 12.0, ART_H - 2.0)
    var tex: Texture2D = art.card_art(card_id) if art != null else null
    if tex != null:
        var src := Vector2(tex.get_width(), tex.get_height())
        var sc: float = minf((win.size.x - 8.0) / src.x, (win.size.y - 8.0) / src.y)
        var drawn := src * sc
        draw_texture_rect(tex, Rect2((win.get_center() - drawn * 0.5).round(), drawn.round()),
            false, Color(1, 1, 1, 1) if playable else Color(0.6, 0.58, 0.64, 1.0))
    else:
        var icon0 := String(ArcanaTheme.element_icon.get(element, "*"))
        _sigil(f, win, accent, icon0)

    # Name, centred in its ribbon, clear of the cost gem and the crest.
    draw_string(f, Vector2(28.0, NAME_Y + 15.0),
        ArcanaTheme.fit(String(card.get("name", "")), 12, size.x - 56.0),
        HORIZONTAL_ALIGNMENT_CENTER, size.x - 56.0, 12, dim)

    # Type ribbon — type must read before any other text.
    var glyph := String(ROLE_GLYPH.get(role, "•"))
    var label := "%s  %s" % [glyph, role.to_upper()]
    var lw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
    draw_string(f, Vector2(size.x * 0.5 - lw * 0.5, ROLE_Y + 14.0), label,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ribbon if playable else ArcanaTheme.TEXT_FAINT)

    var detailed := hovered or selected
    if detailed:
        draw_string(f, Vector2(11.0, FOOT_Y + 14.0),
            ArcanaTheme.fit(placement, 10, size.x - 22.0),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
            ArcanaTheme.TEXT if playable else ArcanaTheme.TEXT_FAINT)
        draw_multiline_string(f, Vector2(11.0, RULES_Y + 13.0), String(card.get("rules", "")),
            HORIZONTAL_ALIGNMENT_LEFT, size.x - 22.0, 9, 2,
            ArcanaTheme.TEXT_DIM if playable else ArcanaTheme.TEXT_FAINT)

    # Cost, top-left, overlapping the card edge like a real badge.
    _socket(f, "cost", Vector2(-4.0, -4.0), str(int(card.get("cost", 0))),
        ArcanaTheme.AETHER if playable else ArcanaTheme.PANEL_EDGE)

    # Element crest, top-right.
    var crest := Vector2(size.x - 17.0, 16.0)
    draw_circle(crest, 12.0, Color(accent, 0.32))
    draw_arc(crest, 12.0, 0, TAU, 22, Color(accent, 0.9), 2.0)
    var icon := String(ArcanaTheme.element_icon.get(element, "*"))
    var iw: float = f.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
    draw_string(f, Vector2(crest.x - iw * 0.5, crest.y + 5.0), icon,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ArcanaTheme.TEXT)

    if role == "Creature":
        _socket(f, "power", Vector2(-4.0, size.y - 26.0), str(int(card.get("power", 0))), Color("#ffd98a"))
        _socket(f, "health", Vector2(size.x - 26.0, size.y - 26.0), str(int(card.get("health", 0))), Color("#ffb3c4"))
    elif role == "Place":
        _socket(f, "presence", Vector2(-4.0, size.y - 26.0), str(int(card.get("presence", 1))), Color("#b8f27a"))
    if count > 1:
        draw_string(f, Vector2(size.x - 40.0, size.y - 9.0), "×%d" % count,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.GOLD)

    # One short reason, over the art rather than over the rules.
    if not playable:
        var strip := Rect2(win.position.x + 1.0, win.position.y + win.size.y - 17.0,
            win.size.x - 2.0, 16.0)
        draw_rect(strip, Color(ArcanaTheme.BG, 0.92))
        draw_string(f, Vector2(strip.position.x + 5.0, strip.position.y + 12.0),
            ArcanaTheme.fit(block_reason, 10, strip.size.x - 10.0),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.DANGER)

## A live number in an authored socket, overlapping the card edge.
func _socket(f: Font, kind: String, at: Vector2, text: String, fallback: Color) -> void:
    var tex: Texture2D = art.frame("gem:%s" % kind) if art != null else null
    var s := 28.0
    if tex != null:
        draw_texture_rect(tex, Rect2(at.round(), Vector2(s, s)), false)
    else:
        draw_circle(at + Vector2(s * 0.5, s * 0.5), s * 0.44, fallback)
    var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
    draw_string(f, Vector2(at.x + s * 0.5 - w * 0.5, at.y + s * 0.5 + 5.0), text,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ArcanaTheme.TEXT)

## No card ever shows an empty rectangle: missing art becomes a deliberate sigil.
func _sigil(f: Font, win: Rect2, accent: Color, icon: String) -> void:
    var c := win.get_center()
    for i in range(4):
        var t := float(i) / 4.0
        draw_circle(c, win.size.y * (0.44 - t * 0.09), Color(accent, 0.10))
    draw_arc(c, win.size.y * 0.30, 0, TAU, 30, Color(accent, 0.55), 2.0)
    for i in range(6):
        var ang: float = TAU * float(i) / 6.0
        draw_circle(c + Vector2(cos(ang), sin(ang)) * win.size.y * 0.30, 2.0, Color(accent, 0.8))
    var w: float = f.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
    draw_string(f, Vector2(c.x - w * 0.5, c.y + 10), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 28,
        Color(accent, 0.95))

func _gem(f: Font, centre: Vector2, text: String, colour: Color) -> void:
    draw_circle(centre, 13.0, Color(0.05, 0.05, 0.08, 0.92))
    draw_arc(centre, 13.0, 0, TAU, 22, Color(colour, 0.9), 2.0)
    var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
    draw_string(f, Vector2(centre.x - w * 0.5, centre.y + 6), text,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, colour)
