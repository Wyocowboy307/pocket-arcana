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

const SIZE := Vector2(156, 214)
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

func _draw() -> void:
    var f := ArcanaTheme.font()
    var playable := block_reason == ""
    var rect := Rect2(Vector2.ZERO, size)
    var elements: Array = card.get("elements", [])
    var accent: Color = ArcanaTheme.color_for_element(String(elements[0])) if not elements.is_empty() else ArcanaTheme.TEXT_DIM
    var ribbon: Color = RIBBON.get(role, ArcanaTheme.TEXT_DIM)

    # Frame silhouette by role: Realm wide and soft, Creature rounded, Place
    # square-shouldered, Spell sharp.
    var radius := 12
    if role == "Spell": radius = 2
    elif role == "Place": radius = 4
    elif role == "Realm": radius = 18
    if hovered or selected:
        draw_style_box(ArcanaTheme.panel_box(Color(0, 0, 0, 0.42), Color(0, 0, 0, 0), radius + 2, 0), rect.grow(6.0))
    var body: Color = ArcanaTheme.PANEL.lightened(0.06) if playable else ArcanaTheme.PANEL.darkened(0.34)
    var edge: Color = ArcanaTheme.GOLD if selected else (accent.lightened(0.25) if hovered else (accent if playable else ArcanaTheme.PANEL_EDGE))
    draw_style_box(ArcanaTheme.panel_box(body, edge, radius, 3 if (selected or hovered) else 2), rect)
    var dim: Color = ArcanaTheme.TEXT if playable else ArcanaTheme.TEXT_FAINT

    # Cost, top left, big.
    var cost := int(card.get("cost", 0))
    var gem := Vector2(20, 21)
    draw_circle(gem, 15.0, ArcanaTheme.AETHER.darkened(0.1) if playable else ArcanaTheme.PANEL_EDGE)
    draw_circle(gem + Vector2(-4, -4), 5.0, Color(1, 1, 1, 0.25))
    var cw: float = f.get_string_size(str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
    draw_string(f, Vector2(gem.x - cw * 0.5, gem.y + 6), str(cost),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ArcanaTheme.TEXT)

    # Element crest, top right.
    var crest := Vector2(size.x - 20, 21)
    draw_circle(crest, 14.0, Color(accent, 0.28))
    draw_arc(crest, 14.0, 0, TAU, 22, Color(accent, 0.85), 2.0)
    var icon := String(ArcanaTheme.element_icon.get(String(elements[0]), "*")) if not elements.is_empty() else "*"
    var iw: float = f.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
    draw_string(f, Vector2(crest.x - iw * 0.5, crest.y + 5), icon,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ArcanaTheme.TEXT)

    # Name, top centre between them.
    draw_string(f, Vector2(40, 26), ArcanaTheme.fit(String(card.get("name", "")), 13, size.x - 78),
        HORIZONTAL_ALIGNMENT_CENTER, size.x - 78, 13, dim)

    # Type ribbon — the loudest single element of the card.
    var band := Rect2(6, 38, size.x - 12, 19)
    draw_style_box(ArcanaTheme.panel_box(Color(ribbon, 0.30 if playable else 0.12),
        Color(ribbon, 0.85 if playable else 0.3), 3, 1), band)
    var glyph := String(ROLE_GLYPH.get(role, "•"))
    var label := "%s  %s" % [glyph, role.to_upper()]
    var lw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
    draw_string(f, Vector2(band.get_center().x - lw * 0.5, band.position.y + 14), label,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ribbon if playable else ArcanaTheme.TEXT_FAINT)

    # Art window.
    var win := Rect2(7, 62, size.x - 14, 72)
    draw_style_box(ArcanaTheme.panel_box(accent.darkened(0.6), Color(accent, 0.0), 5, 0), win)
    var tex: Texture2D = art.card_art(card_id) if art != null else null
    if tex != null:
        var src := Vector2(tex.get_width(), tex.get_height())
        var sc: float = min((win.size.x - 8.0) / src.x, (win.size.y - 8.0) / src.y)
        var drawn := src * sc
        draw_texture_rect(tex, Rect2(win.get_center() - drawn * 0.5, drawn), false)
    else:
        _sigil(f, win, accent, icon)
    draw_style_box(ArcanaTheme.panel_box(Color(0, 0, 0, 0), Color(accent, 0.75), 5, 2), win)

    var detailed := hovered or selected
    # PLAY ON / TARGET — printed, never inferred.
    var foot := Rect2(6, 139, size.x - 12, 19)
    if not detailed:
        foot = Rect2(6, 139, size.x - 12, 0)
    if detailed:
        draw_style_box(ArcanaTheme.panel_box(Color(accent, 0.24 if playable else 0.08),
            Color(accent, 0.7 if playable else 0.25), 3, 1), foot)
        draw_string(f, Vector2(foot.position.x + 6, foot.position.y + 14),
            ArcanaTheme.fit(placement, 10, foot.size.x - 12),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT if playable else ArcanaTheme.TEXT_FAINT)
        draw_multiline_string(f, Vector2(9, 174), String(card.get("rules", "")),
            HORIZONTAL_ALIGNMENT_LEFT, size.x - 18, 10, 2,
            ArcanaTheme.TEXT_DIM if playable else ArcanaTheme.TEXT_FAINT)

    # Creature gems in the bottom corners.
    if role == "Creature":
        _gem(f, Vector2(19, size.y - 19), str(int(card.get("power", 0))), Color("#ffd98a"))
        _gem(f, Vector2(size.x - 19, size.y - 19), str(int(card.get("health", 0))), Color("#ffb3c4"))
    elif role == "Place":
        draw_string(f, Vector2(9, size.y - 9), "⌂ %d Presence" % int(card.get("presence", 1)),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)
    if count > 1:
        draw_string(f, Vector2(size.x - 40, size.y - 9), "×%d" % count,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ArcanaTheme.GOLD)

    # One short reason, over the art rather than over the rules.
    if not playable:
        var strip := Rect2(win.position.x + 1, win.position.y + win.size.y - 17.0, win.size.x - 2, 16)
        draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.9), Color(0, 0, 0, 0), 3, 0), strip)
        draw_string(f, Vector2(strip.position.x + 5, strip.position.y + 12),
            ArcanaTheme.fit(block_reason, 10, strip.size.x - 10),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.DANGER)

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
