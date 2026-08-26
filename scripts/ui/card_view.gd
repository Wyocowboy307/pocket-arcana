class_name CardView
extends Control
## One card in hand. Lifts on hover (ANIMATION_BIBLE step 1) and dims with a
## plain-English reason when it cannot be played.

signal card_clicked(card_id: String)
signal card_hovered(card_id: String)

const CARD_SIZE := Vector2(140, 164)

var card: Dictionary = {}
var card_id := ""
var selected := false
var block_reason := ""
var count := 1
var art: ArtRegistry = null           # may be null; layout falls back to text-only
var hovered := false

func setup(card_data: Dictionary, reason: String, registry: ArtRegistry = null) -> void:
    card = card_data
    art = registry
    card_id = String(card_data.get("id", ""))
    block_reason = reason
    custom_minimum_size = CARD_SIZE
    tooltip_text = "%s\n%s\n\n%s" % [
        String(card.get("name", "")),
        String(card.get("rules", "")),
        "Cannot play: " + reason if reason != "" else "Click, then click a glowing tile.",
    ]
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

    var body: Color = ArcanaTheme.PANEL.lightened(0.04) if playable else ArcanaTheme.PANEL.darkened(0.35)
    var edge: Color = accent if playable else ArcanaTheme.PANEL_EDGE
    if selected: edge = ArcanaTheme.GOLD
    elif hovered: edge = accent.lightened(0.3)
    # A raised card casts a shadow so it reads as lifted out of the hand.
    if hovered or selected:
        draw_style_box(ArcanaTheme.panel_box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 10, 0), rect.grow(4.0))
    draw_style_box(ArcanaTheme.panel_box(body, edge, 8, 3 if (selected or hovered) else 2), rect)

    var dim: Color = ArcanaTheme.TEXT if playable else ArcanaTheme.TEXT_FAINT

    # Element stripe: colour plus icon plus word.
    var stripe := Rect2(rect.position.x + 3, rect.position.y + 3, rect.size.x - 6, 20)
    draw_style_box(ArcanaTheme.panel_box(Color(accent, 0.24 if playable else 0.10), Color(accent, 0.0), 5, 0), stripe)
    var el_text := ""
    for el in elements:
        el_text += "%s %s  " % [ArcanaTheme.element_icon.get(el, ""), ArcanaTheme.element_name.get(el, el)]
    draw_string(f, Vector2(rect.position.x + 8, rect.position.y + 18),
        ArcanaTheme.fit(el_text.strip_edges(), 10, rect.size.x - 44),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, accent if playable else ArcanaTheme.TEXT_FAINT)

    # Aether cost gem.
    var cost := int(card.get("cost", 0))
    var gem := Vector2(rect.position.x + rect.size.x - 17, rect.position.y + 13)
    draw_circle(gem, 11.0, ArcanaTheme.AETHER.darkened(0.35) if playable else ArcanaTheme.PANEL_EDGE)
    draw_string(f, Vector2(gem.x - (7 if cost > 9 else 4), gem.y + 5), str(cost),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ArcanaTheme.TEXT)

    # Two layouts. With art the whole card tightens up; without it the rules keep
    # their full four lines. ART_BIBLE: readability outranks art size.
    var art_tex: Texture2D = art.card_art(card_id) if art != null else null
    var name_y := 42.0
    var type_y := 58.0
    var rules_y := 76.0
    var rules_lines := 4
    if art_tex != null:
        name_y = 34.0
        type_y = 46.0
        rules_y = 116.0
        rules_lines = 2

    draw_string(f, Vector2(rect.position.x + 8, rect.position.y + name_y),
        ArcanaTheme.fit(String(card.get("name", "")), 14, rect.size.x - 16),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim)
    draw_string(f, Vector2(rect.position.x + 8, rect.position.y + type_y),
        String(card.get("type", "")).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.TEXT_DIM)

    var window := Rect2()
    if art_tex != null:
        window = Rect2(rect.position.x + 7, rect.position.y + 50, rect.size.x - 14, 54)
        draw_style_box(ArcanaTheme.panel_box(Color(accent, 0.16), Color(accent, 0.5), 5, 1), window)
        var src := Vector2(art_tex.get_width(), art_tex.get_height())
        if src.x > 0.0 and src.y > 0.0:
            var scale: float = min((window.size.x - 6.0) / src.x, (window.size.y - 6.0) / src.y)
            var drawn := src * scale
            draw_texture_rect(art_tex, Rect2(window.get_center() - drawn * 0.5, drawn), false)

    draw_multiline_string(f, Vector2(rect.position.x + 8, rect.position.y + rules_y),
        String(card.get("rules", "")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 11, rules_lines,
        ArcanaTheme.TEXT_DIM if playable else ArcanaTheme.TEXT_FAINT)

    # Stat line.
    if String(card.get("type", "")) == "creature":
        draw_string(f, Vector2(rect.position.x + 8, rect.position.y + rect.size.y - 10),
            "%d ⚔   %d ♥" % [int(card.get("power", 0)), int(card.get("health", 0))],
            HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim)
    elif String(card.get("type", "")) == "landmark":
        draw_string(f, Vector2(rect.position.x + 8, rect.position.y + rect.size.y - 10),
            "⌂ %d Presence" % int(card.get("presence", 1)),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)

    if not playable:
        # Sits over the bottom of the art window rather than fighting the rules.
        var reason_baseline: float = rect.position.y + rect.size.y - 26.0
        if art_tex != null:
            var strip_y: float = window.position.y + window.size.y - 15.0
            draw_style_box(ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.86), Color(accent, 0.0), 3, 0),
                Rect2(window.position.x + 1, strip_y, window.size.x - 2, 14))
            reason_baseline = strip_y + 11.0
        draw_string(f, Vector2(rect.position.x + 9, reason_baseline),
            ArcanaTheme.fit(block_reason, 10, rect.size.x - 18),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ArcanaTheme.DANGER)

    if count > 1:
        draw_string(f, Vector2(rect.position.x + rect.size.x - 30, rect.position.y + rect.size.y - 10),
            "×%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ArcanaTheme.GOLD)

