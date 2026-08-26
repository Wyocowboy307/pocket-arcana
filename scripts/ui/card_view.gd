class_name CardView
extends Control
## One card in hand.
##
## A first-time player has to be able to answer three questions without reading a
## paragraph: what kind of card is this, where can I put it, and why can't I play
## it. So every card carries a role badge, a "Play on" line and, when it is
## blocked, the simulation's own refusal. Each role also gets its own frame
## shape, so the type is readable from silhouette alone.

signal card_clicked(card_id: String)
signal card_hovered(card_id: String)

const CARD_SIZE := Vector2(148, 196)

## Role → icon, accent tint and frame character.
const ROLE_ICON := {
    "Creature": "❖", "Spell": "✦", "Place": "⌂", "Land": "▦", "Relic": "◈",
}

var card: Dictionary = {}
var card_id := ""
var selected := false
var hovered := false
var block_reason := ""
var count := 1
var role := "Card"
var play_on := ""
var art: ArtRegistry = null

func setup(card_data: Dictionary, reason: String, registry: ArtRegistry = null,
           role_name: String = "Card", placement: String = "") -> void:
    card = card_data
    card_id = String(card_data.get("id", ""))
    block_reason = reason
    art = registry
    role = role_name
    play_on = placement
    custom_minimum_size = CARD_SIZE
    tooltip_text = "%s — %s\n%s\n\nPlay on: %s%s" % [
        String(card.get("name", "")), role, String(card.get("rules", "")), placement,
        "\n\nCannot play: " + reason if reason != "" else ""]
    queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    custom_minimum_size = CARD_SIZE
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
    var dim: Color = ArcanaTheme.TEXT if playable else ArcanaTheme.TEXT_FAINT

    # Frame. The corner radius is part of the type language: creatures are
    # rounded, spells are sharp, places are square-shouldered.
    var radius := 10
    if role == "Spell": radius = 3
    elif role == "Place": radius = 5
    elif role == "Land": radius = 14
    var body: Color = ArcanaTheme.PANEL.lightened(0.05) if playable else ArcanaTheme.PANEL.darkened(0.32)
    var edge: Color = accent if playable else ArcanaTheme.PANEL_EDGE
    if selected: edge = ArcanaTheme.GOLD
    elif hovered: edge = accent.lightened(0.3)
    if hovered or selected:
        draw_style_box(ArcanaTheme.panel_box(Color(0, 0, 0, 0.38), Color(0, 0, 0, 0), radius + 2, 0), rect.grow(5.0))
    draw_style_box(ArcanaTheme.panel_box(body, edge, radius, 3 if (selected or hovered) else 2), rect)

    # Header: element + cost.
    var head := Rect2(rect.position.x + 3, rect.position.y + 3, rect.size.x - 6, 19)
    draw_style_box(ArcanaTheme.panel_box(Color(accent, 0.26 if playable else 0.10), Color(accent, 0.0), radius - 2, 0), head)
    var el_text := ""
    for el in elements:
        el_text += "%s %s " % [ArcanaTheme.element_icon.get(el, ""), ArcanaTheme.element_name.get(el, el)]
    draw_string(f, Vector2(rect.position.x + 8, rect.position.y + 17),
        ArcanaTheme.fit(el_text.strip_edges(), 10, rect.size.x - 46),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, accent if playable else ArcanaTheme.TEXT_FAINT)
    var cost := int(card.get("cost", 0))
    var gem := Vector2(rect.position.x + rect.size.x - 17, rect.position.y + 13)
    draw_circle(gem, 12.0, ArcanaTheme.AETHER.darkened(0.15) if playable else ArcanaTheme.PANEL_EDGE)
    draw_circle(gem + Vector2(-3, -3), 4.0, Color(1, 1, 1, 0.22))
    var cw: float = f.get_string_size(str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
    draw_string(f, Vector2(gem.x - cw * 0.5, gem.y + 5), str(cost),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ArcanaTheme.TEXT)

    # Role badge — the single strongest "what is this card" signal.
    var badge := Rect2(rect.position.x + 5, rect.position.y + 25, rect.size.x - 10, 16)
    draw_style_box(ArcanaTheme.panel_box(Color(accent, 0.16), Color(accent, 0.55), 4, 1), badge)
    draw_string(f, Vector2(badge.position.x + 6, badge.position.y + 12),
        "%s  %s" % [String(ROLE_ICON.get(role, "•")), role.to_upper()],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, accent if playable else ArcanaTheme.TEXT_FAINT)

    draw_string(f, Vector2(rect.position.x + 7, rect.position.y + 57),
        ArcanaTheme.fit(String(card.get("name", "")), 14, rect.size.x - 14),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim)

    # Art window. Its shape also carries the role: places stand on a plinth,
    # land is a wide horizon, creatures get a portrait.
    var art_tex: Texture2D = art.card_art(card_id) if art != null else null
    var win := Rect2(rect.position.x + 6, rect.position.y + 63, rect.size.x - 12, 60)
    if role == "Land": win = Rect2(rect.position.x + 6, rect.position.y + 66, rect.size.x - 12, 50)
    draw_style_box(ArcanaTheme.panel_box(accent.darkened(0.62), Color(accent, 0.0), 5, 0), win)
    if art_tex != null:
        var src := Vector2(art_tex.get_width(), art_tex.get_height())
        if src.x > 0.0 and src.y > 0.0:
            var sc: float = min((win.size.x - 8.0) / src.x, (win.size.y - 8.0) / src.y)
            var drawn := src * sc
            draw_texture_rect(art_tex, Rect2(win.get_center() - drawn * 0.5, drawn), false)
    else:
        # No illustration yet: draw an elemental sigil so the card reads as magic
        # rather than as a missing asset.
        var c := win.get_center()
        for i in range(4):
            var t := float(i) / 4.0
            draw_circle(c, win.size.y * (0.42 - t * 0.09), Color(accent, 0.10))
        draw_arc(c, win.size.y * 0.30, 0, TAU, 30, Color(accent, 0.55), 2.0)
        for i in range(6):
            var ang: float = TAU * float(i) / 6.0
            draw_circle(c + Vector2(cos(ang), sin(ang)) * win.size.y * 0.30, 2.0, Color(accent, 0.8))
        var sigil := String(ROLE_ICON.get(role, "•"))
        if not elements.is_empty():
            sigil = String(ArcanaTheme.element_icon.get(String(elements[0]), sigil))
        var sw: float = f.get_string_size(sigil, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
        draw_string(f, Vector2(c.x - sw * 0.5, c.y + 9), sigil,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(accent, 0.95))
    if role == "Place":
        draw_rect(Rect2(win.position.x + 8, win.position.y + win.size.y - 5, win.size.x - 16, 4),
            Color(accent, 0.65))
    draw_style_box(ArcanaTheme.panel_box(Color(0, 0, 0, 0), Color(accent, 0.7), 5, 2), win)

    # Rules, kept to two lines; the full text lives in the hover panel.
    draw_multiline_string(f, Vector2(rect.position.x + 8, rect.position.y + 137),
        String(card.get("rules", "")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 11, 2,
        ArcanaTheme.TEXT_DIM if playable else ArcanaTheme.TEXT_FAINT)

    # "Play on" — where this card is allowed to go.
    var foot := Rect2(rect.position.x + 4, rect.position.y + rect.size.y - 42, rect.size.x - 8, 18)
    var foot_tint: Color = accent if playable else ArcanaTheme.PANEL_EDGE
    draw_style_box(ArcanaTheme.panel_box(Color(foot_tint, 0.22), Color(foot_tint, 0.6), 4, 1), foot)
    draw_string(f, Vector2(foot.position.x + 5, foot.position.y + 13),
        ArcanaTheme.fit(play_on.to_upper(), 9, foot.size.x - 10),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ArcanaTheme.TEXT if playable else ArcanaTheme.TEXT_FAINT)

    # Stats, in the role's own language.
    var base_y: float = rect.position.y + rect.size.y - 8
    if role == "Creature":
        _stat_gem(f, Vector2(rect.position.x + 16, base_y - 7), str(int(card.get("power", 0))), Color("#ffd98a"))
        _stat_gem(f, Vector2(rect.position.x + rect.size.x - 16, base_y - 7), str(int(card.get("health", 0))), Color("#ffb3c4"))
    elif role == "Place":
        draw_string(f, Vector2(rect.position.x + 8, base_y), "⌂ %d Presence" % int(card.get("presence", 1)),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
    else:
        draw_string(f, Vector2(rect.position.x + 8, base_y), "Resolves at once",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT_FAINT)

    if count > 1:
        draw_string(f, Vector2(rect.position.x + rect.size.x - 32, base_y), "×%d" % count,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ArcanaTheme.GOLD)

    # Why it cannot be played, over the art rather than over the rules.
    if not playable:
        var strip_y: float = win.position.y + win.size.y - 16.0
        draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.90), Color(accent, 0.0), 3, 0),
            Rect2(win.position.x + 1, strip_y, win.size.x - 2, 15))
        draw_string(f, Vector2(win.position.x + 6, strip_y + 11),
            ArcanaTheme.fit(block_reason, 10, win.size.x - 12),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.DANGER)

func _stat_gem(f: Font, centre: Vector2, text: String, colour: Color) -> void:
    draw_circle(centre, 12.0, Color(0.06, 0.06, 0.09, 0.9))
    draw_arc(centre, 12.0, 0, TAU, 22, Color(colour, 0.85), 2.0)
    var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
    draw_string(f, Vector2(centre.x - w * 0.5, centre.y + 6), text,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, colour)
