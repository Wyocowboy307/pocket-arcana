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

const SIZE := Vector2(156, 196)
## A distinct glyph per role, so type reads before any text does.
const ROLE_GLYPH := {
    "Realm": "▰", "Creature": "❖", "Place": "⌂", "Spell": "✦",
}
## Mirrored in tools/pixelart/cards.py ROLE_RIBBON.
const RIBBON := {
    "Realm": Color(0.43, 0.75, 0.51), "Creature": Color(0.89, 0.70, 0.33),
    "Place": Color(0.67, 0.54, 0.38), "Spell": Color(0.83, 0.71, 0.91),
}
## Ink on parchment: the card's own text colours.
const INK := Color(0.09, 0.067, 0.059)
const INK_SOFT := Color(0.28, 0.22, 0.18)

var card: Dictionary = {}
var card_id := ""
var role := "Spell"
var placement := ""
var block_reason := ""
var count := 1
var selected := false
var hovered := false
var art: ArtRegistry
## V3 uses the ribbon for the landscape requirement ("GROVE CREATURE") and
## colours it to match the lane, so a card can be matched to its land by colour
## before a word is read. Left unset, the role colours it as before.
var ribbon_override: Color = Color(0, 0, 0, 0)

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
const ROLE_Y := 26.0
const ROLE_H := 14.0
const ART_Y := 42.0
const ART_H := 116.0
const FOOT_Y := 160.0
const FOOT_H := 16.0
const RULES_Y := 178.0

func _draw() -> void:
    var f := ArcanaTheme.font()
    var playable := block_reason == ""
    var elements: Array = card.get("elements", [])
    var element := String(elements[0]) if not elements.is_empty() else "neutral"
    var accent: Color = ArcanaTheme.color_for_element(element) if not elements.is_empty() \
        else ArcanaTheme.TEXT_DIM
    var ribbon: Color = RIBBON.get(role, ArcanaTheme.TEXT_DIM)
    if ribbon_override.a > 0.0: ribbon = ribbon_override
    var rect := Rect2(Vector2.ZERO, size)

    var frame_key := "hand_frame:%s:%s" % [element, role.to_lower()]
    var frame: Texture2D = art.frame(frame_key) if art != null else null
    if frame == null and art != null:
        frame = art.frame("hand_frame:neutral:%s" % role.to_lower())

    if hovered or selected:
        draw_rect(rect.grow(7.0), Color(0, 0, 0, 0.34))
        draw_rect(rect.grow(3.0), Color(ArcanaTheme.GOLD if selected else accent, 0.62))

    if frame == null:
        # Procedural fallback, kept so a missing frame never blanks the hand.
        draw_style_box(ArcanaTheme.panel_box(Color(0.85, 0.79, 0.62), accent, 8, 2), rect)
    else:
        draw_texture_rect(frame, rect, false)

    # Art, inside the window the frame recessed for it.
    var win := Rect2(4.0, ART_Y + 1.0, size.x - 8.0, ART_H - 2.0)
    var tex: Texture2D = art.card_art(card_id) if art != null else null
    if tex != null:
        var src := Vector2(tex.get_width(), tex.get_height())
        var sc: float = minf((win.size.x - 8.0) / src.x, (win.size.y - 8.0) / src.y)
        var drawn := src * sc
        # Creatures stand at the window's floor, like they will on the board.
        var at := Vector2(win.get_center().x - drawn.x * 0.5,
            win.position.y + win.size.y - drawn.y - 4.0)
        draw_texture_rect(tex, Rect2(at.round(), drawn.round()), false)
    else:
        var icon0 := String(ArcanaTheme.element_icon.get(element, "*"))
        _sigil(f, win, accent, icon0)

    # Name in ink, centred, clear of the cost token and the crest.
    draw_string(f, Vector2(30.0, NAME_Y + 15.0),
        ArcanaTheme.fit(String(card.get("name", "")), 13, size.x - 60.0),
        HORIZONTAL_ALIGNMENT_CENTER, size.x - 60.0, 13, INK)

    # Type ribbon — type must read before any other text.
    var glyph := String(ROLE_GLYPH.get(role, "•"))
    var label := "%s %s" % [glyph, role.to_upper()]
    if ribbon_override.a > 0.0:
        var band := Rect2(4.0, ROLE_Y, size.x - 8.0, ROLE_H)
        draw_rect(band, Color(ribbon, 0.95))
        label = role.to_upper()
    var lw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
    draw_string(f, Vector2(size.x * 0.5 - lw * 0.5, ROLE_Y + 11.0), label,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)

    # PLAY ON always; rules on approach. Indented clear of the corner tokens.
    draw_string(f, Vector2(30.0, FOOT_Y + 12.0),
        ArcanaTheme.fit(placement, 10, size.x - 60.0),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)
    if hovered or selected:
        draw_multiline_string(f, Vector2(30.0, RULES_Y + 10.0), String(card.get("rules", "")),
            HORIZONTAL_ALIGNMENT_LEFT, size.x - 60.0, 9, 2, INK_SOFT)

    # Element crest, top-right.
    var crest := Vector2(size.x - 16.0, 15.0)
    draw_circle(crest, 11.0, Color(accent, 0.9))
    draw_circle(crest, 8.5, Color(accent.darkened(0.4), 1.0))
    var icon := String(ArcanaTheme.element_icon.get(element, "*"))
    var iw: float = f.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
    draw_string(f, Vector2(crest.x - iw * 0.5, crest.y + 4.0), icon,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.95))

    # Cost, top-left, overlapping the card edge like a real badge.
    _socket(f, "cost", Vector2(-6.0, -6.0), str(int(card.get("cost", 0))))

    if role == "Creature":
        _socket(f, "power", Vector2(-6.0, size.y - 30.0), str(int(card.get("power", 0))))
        _socket(f, "health", Vector2(size.x - 30.0, size.y - 30.0), str(int(card.get("health", 0))))
    elif role == "Place":
        _socket(f, "presence", Vector2(-6.0, size.y - 30.0), str(int(card.get("presence", 1))))
    if count > 1:
        var chip := Rect2(size.x - 42.0, ART_Y + 4.0, 32.0, 18.0)
        draw_style_box(ArcanaTheme.panel_box(Color(0.07, 0.06, 0.09, 0.9), ArcanaTheme.GOLD, 5, 1), chip)
        draw_string(f, Vector2(chip.position.x + 6.0, chip.position.y + 14.0), "×%d" % count,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.GOLD)

    # Unaffordable: the whole card sleeps under a cool veil. The reason lives
    # in the tooltip — never as a strip defacing the art.
    if not playable:
        draw_rect(rect, Color(0.12, 0.11, 0.18, 0.44))

## A live number on a chunky bevelled token, overlapping the card edge.
func _socket(f: Font, kind: String, at: Vector2, text: String) -> void:
    var tex: Texture2D = art.frame("token:%s" % kind) if art != null else null
    if tex == null and art != null: tex = art.frame("gem:%s" % kind)
    var s := 36.0
    if tex != null:
        draw_texture_rect(tex, Rect2(at.round(), Vector2(s, s)), false)
    else:
        draw_circle(at + Vector2(s * 0.5, s * 0.5), s * 0.44, Color(0.1, 0.09, 0.12))
    var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
    draw_string(f, Vector2(at.x + s * 0.5 - w * 0.5, at.y + s * 0.5 + 5.0), text,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)

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
