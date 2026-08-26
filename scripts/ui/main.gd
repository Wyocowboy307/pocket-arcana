extends Control
## Pocket Arcana match screen.
##
## Every legality question goes to MatchEngine; this script only draws the
## answer and explains refusals in plain English (ONBOARDING_AND_ACCESSIBILITY).

const HUMAN := 0
const RIVAL := 1
const AI_THINK_TIME := 0.55

var db := ContentDatabase.new()
var engine := MatchEngine.new()
var art := ArtRegistry.new()

# Interaction state.
var mode := ""                       # "" | "card" | "shape" | "command" | "unit"
var selected_card_id := ""
var shape_element := ""
var selected_unit_pos := Vector2i(-1, -1)
var pending_primary := Vector2i(-1, -1)   # first click of a two-step card
var ai_busy := false
var overlay_open := false
var discovered: Dictionary = {}      # recipe_id -> true, for first-time celebration
var tutorial_done: Dictionary = {}   # tutorial step id -> true

# Nodes.
var board_view: BoardView
var hand_row: HBoxContainer
var turn_label: Label
var chapter_label: Label
var detail_title: Label
var detail_body: RichTextLabel
var pass_body: RichTextLabel
var log_label: RichTextLabel
var pass_button: Button
var command_button: Button
var cancel_button: Button
var help_panel: PanelContainer
var coach_panel: PanelContainer
var coach_title: Label
var coach_body: RichTextLabel
var overlay: PanelContainer
var overlay_title: Label
var overlay_body: RichTextLabel
var overlay_button: Button
var banner: Label
var shape_buttons: Dictionary = {}
var player_strips: Array = []
var _hand_signature := ""

func _ready() -> void:
    if not db.load_all():
        _fatal("Content failed to load. Check the Godot error panel.")
        return
    ArcanaTheme.configure(db)
    art.load_manifest()
    _build_ui()
    add_child(engine)
    engine.state_changed.connect(_refresh)
    engine.event_emitted.connect(_on_event)
    engine.chapter_resolved.connect(_on_chapter_resolved)
    engine.match_finished.connect(_on_match_finished)
    engine.setup(db, "starter_life", "starter_fire")
    _clear_selection()

func _fatal(text: String) -> void:
    var label := Label.new()
    label.text = text
    label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    add_child(label)

# --- construction -----------------------------------------------------------

func _build_ui() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var bg := ColorRect.new()
    bg.color = ArcanaTheme.BG
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 12)
    add_child(margin)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    margin.add_child(root)

    root.add_child(_build_top_bar())

    var mid := HBoxContainer.new()
    mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    mid.add_theme_constant_override("separation", 10)
    root.add_child(mid)

    board_view = BoardView.new()
    board_view.engine = engine
    board_view.art = art
    board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    board_view.tile_clicked.connect(_on_tile_clicked)
    board_view.tile_hovered.connect(_on_tile_hovered)
    mid.add_child(board_view)

    mid.add_child(_build_side_panel())
    root.add_child(_build_action_bar())
    root.add_child(_build_hand())

    _build_banner()
    _build_overlay()

func _panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", ArcanaTheme.panel_box())
    if min_size != Vector2.ZERO: p.custom_minimum_size = min_size
    return p

func _label(text: String, font_size: int, color: Color = ArcanaTheme.TEXT) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    return l

func _rich(min_h: int) -> RichTextLabel:
    var r := RichTextLabel.new()
    r.bbcode_enabled = true
    r.fit_content = true
    r.scroll_active = false
    r.custom_minimum_size = Vector2(0, min_h)
    r.add_theme_font_size_override("normal_font_size", 12)
    r.add_theme_font_size_override("bold_font_size", 12)
    r.add_theme_font_size_override("italics_font_size", 12)
    r.add_theme_color_override("default_color", ArcanaTheme.TEXT_DIM)
    return r

## Fixed-height text block: RichTextLabel with fit_content grows without bound
## and pushes the hand off the bottom of the screen.
func _rich_fixed(height: int) -> RichTextLabel:
    var r := _rich(height)
    r.fit_content = false
    r.custom_minimum_size = Vector2(0, height)
    return r

func _build_top_bar() -> Control:
    var panel := _panel(Vector2(0, 68))
    var rows := VBoxContainer.new()
    rows.add_theme_constant_override("separation", 2)
    var m := MarginContainer.new()
    for side in ["left", "right"]: m.add_theme_constant_override("margin_" + side, 12)
    for side in ["top", "bottom"]: m.add_theme_constant_override("margin_" + side, 6)
    m.add_child(rows)
    panel.add_child(m)

    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 14)
    rows.add_child(top)
    top.add_child(_label("POCKET ARCANA", 17, ArcanaTheme.GOLD))
    chapter_label = _label("", 12, ArcanaTheme.TEXT_DIM)
    top.add_child(chapter_label)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(spacer)
    turn_label = _label("", 14, ArcanaTheme.YOU)
    top.add_child(turn_label)
    var help := Button.new()
    help.text = "How to play"
    help.toggle_mode = true
    help.add_theme_font_size_override("font_size", 11)
    help.pressed.connect(func() -> void: help_panel.get_meta("dimmer").visible = help.button_pressed)
    top.add_child(help)

    # Both scoreboards live on one line so the board and hand keep their room.
    var scores := HBoxContainer.new()
    scores.add_theme_constant_override("separation", 12)
    rows.add_child(scores)
    for player in [HUMAN, RIVAL]:
        var strip := _rich_fixed(20)
        strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scores.add_child(strip)
        player_strips.append({"stats": strip})
    return panel

func _build_side_panel() -> Control:
    var side := VBoxContainer.new()
    side.custom_minimum_size = Vector2(312, 0)
    side.add_theme_constant_override("separation", 6)

    coach_panel = _panel()
    var cv := VBoxContainer.new()
    var cm := MarginContainer.new()
    for s2 in ["left", "right", "top", "bottom"]: cm.add_theme_constant_override("margin_" + s2, 8)
    cm.add_child(cv)
    coach_panel.add_child(cm)
    coach_title = _label("", 12, ArcanaTheme.GOLD)
    coach_body = _rich_fixed(20)
    cv.add_child(coach_title); cv.add_child(coach_body)
    side.add_child(coach_panel)

    var detail := _panel()
    detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var dv := VBoxContainer.new()
    var dm := MarginContainer.new()
    for s2 in ["left", "right", "top", "bottom"]: dm.add_theme_constant_override("margin_" + s2, 8)
    dm.add_child(dv)
    detail.add_child(dm)
    detail_title = _label("Take your turn", 13, ArcanaTheme.GOLD)
    detail_body = _rich_fixed(90)
    detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    detail_body.scroll_active = true
    dv.add_child(detail_title); dv.add_child(detail_body)
    side.add_child(detail)

    var pass_panel := _panel()
    var pv := VBoxContainer.new()
    var pm := MarginContainer.new()
    for s2 in ["left", "right", "top", "bottom"]: pm.add_theme_constant_override("margin_" + s2, 8)
    pm.add_child(pv)
    pass_panel.add_child(pm)
    pv.add_child(_label("IF YOU PASS NOW", 10, ArcanaTheme.TEXT_FAINT))
    pass_body = _rich_fixed(52)
    pv.add_child(pass_body)
    side.add_child(pass_panel)

    var log_panel := _panel()
    var lv := VBoxContainer.new()
    var lm := MarginContainer.new()
    for s2 in ["left", "right", "top", "bottom"]: lm.add_theme_constant_override("margin_" + s2, 8)
    lm.add_child(lv)
    log_panel.add_child(lm)
    lv.add_child(_label("RECENT EVENTS", 10, ArcanaTheme.TEXT_FAINT))
    log_label = _rich_fixed(48)
    lv.add_child(log_label)
    side.add_child(log_panel)

    _build_help_panel(side)
    return side

func _build_help_panel(_parent: Control) -> void:
    var dimmer := ColorRect.new()
    dimmer.color = Color(0, 0, 0, 0.55)
    dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
    dimmer.visible = false
    add_child(dimmer)

    var centre := CenterContainer.new()
    centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
    dimmer.add_child(centre)

    help_panel = PanelContainer.new()
    help_panel.add_theme_stylebox_override("panel", ArcanaTheme.panel_box(ArcanaTheme.PANEL, ArcanaTheme.GOLD, 12, 2))
    help_panel.custom_minimum_size = Vector2(620, 0)
    centre.add_child(help_panel)

    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    var m := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, 22)
    m.add_child(v)
    help_panel.add_child(m)

    var title := _label("HOW TO PLAY", 22, ArcanaTheme.GOLD)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(title)
    var text := _rich(300)
    text.add_theme_font_size_override("normal_font_size", 13)
    text.add_theme_font_size_override("bold_font_size", 13)
    var lines := "[b]Goal.[/b] Win two Chapters, break the rival Heart, or reach 10 Wonder.\n"
    lines += "[b]Your turn.[/b] Do exactly one thing: play a card, Shape a tile, move or fight with one creature, use your Command, or Pass.\n"
    lines += "[b]Shape.[/b] Shaping turns a tile beside your realm into your element. Your realm's terrain is what lets you cast cards.\n"
    lines += "[b]Passing.[/b] When your rival Passes you get one last turn, then the Chapter scores. Cards you did not spend stay in your hand for the next Chapter.\n\n"
    for kw in db.keywords:
        lines += "[b]%s[/b] — %s\n" % [String(kw.get("name", "")), String(kw.get("plain", ""))]
    text.text = lines
    v.add_child(text)

    var close := Button.new()
    close.text = "Back to the match"
    close.custom_minimum_size = Vector2(0, 32)
    close.pressed.connect(func() -> void: dimmer.visible = false)
    v.add_child(close)
    help_panel.set_meta("dimmer", dimmer)

func _build_action_bar() -> Control:
    var panel := _panel(Vector2(0, 40))
    var box := HBoxContainer.new()
    box.add_theme_constant_override("separation", 4)
    var m := MarginContainer.new()
    for s in ["left", "right"]: m.add_theme_constant_override("margin_" + s, 10)
    m.add_child(box)
    panel.add_child(m)

    box.add_child(_label("SHAPE", 11, ArcanaTheme.TEXT_FAINT))
    for el_id in ["frost", "lightning", "life", "fire", "water", "earth", "wind", "death"]:
        var b := Button.new()
        b.text = "%s %s" % [ArcanaTheme.element_icon.get(el_id, ""), ArcanaTheme.element_name.get(el_id, el_id)]
        b.tooltip_text = "Shape a tile into %s terrain. Shaping is your whole turn." % ArcanaTheme.element_name.get(el_id, el_id)
        b.add_theme_font_size_override("font_size", 11)
        b.add_theme_color_override("font_color", ArcanaTheme.color_for_element(el_id))
        b.pressed.connect(_choose_shape.bind(el_id))
        box.add_child(b)
        shape_buttons[el_id] = b

    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(spacer)

    cancel_button = Button.new()
    cancel_button.text = "Cancel"
    cancel_button.pressed.connect(_clear_selection)
    box.add_child(cancel_button)

    command_button = Button.new()
    command_button.text = "COMMAND"
    command_button.pressed.connect(_choose_command)
    box.add_child(command_button)

    pass_button = Button.new()
    pass_button.text = "PASS CHAPTER"
    pass_button.pressed.connect(_do_pass)
    box.add_child(pass_button)
    return panel

func _build_hand() -> Control:
    var panel := _panel(Vector2(0, 190))
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    var m := MarginContainer.new()
    for s in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + s, 8)
    m.add_child(scroll)
    panel.add_child(m)
    hand_row = HBoxContainer.new()
    hand_row.add_theme_constant_override("separation", 8)
    scroll.add_child(hand_row)
    return panel

func _build_banner() -> void:
    var holder := PanelContainer.new()
    holder.add_theme_stylebox_override("panel", ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.92), ArcanaTheme.GOLD, 10, 2))
    holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    holder.offset_top = 232
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.modulate.a = 0.0
    var m := MarginContainer.new()
    for s2 in ["left", "right"]: m.add_theme_constant_override("margin_" + s2, 22)
    for s2 in ["top", "bottom"]: m.add_theme_constant_override("margin_" + s2, 8)
    holder.add_child(m)
    banner = Label.new()
    banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner.add_theme_font_size_override("font_size", 22)
    banner.add_theme_color_override("font_color", ArcanaTheme.GOLD)
    banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    m.add_child(banner)
    add_child(holder)
    banner.set_meta("holder", holder)

func _build_overlay() -> void:
    # Full-rect dimmer so the board behind is visibly paused and cannot be clicked.
    var dimmer := ColorRect.new()
    dimmer.color = Color(0, 0, 0, 0.55)
    dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
    dimmer.visible = false
    add_child(dimmer)

    var centre := CenterContainer.new()
    centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
    dimmer.add_child(centre)

    overlay = PanelContainer.new()
    overlay.add_theme_stylebox_override("panel", ArcanaTheme.panel_box(ArcanaTheme.PANEL, ArcanaTheme.GOLD, 12, 2))
    overlay.custom_minimum_size = Vector2(560, 0)
    centre.add_child(overlay)

    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    var m := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, 24)
    m.add_child(v)
    overlay.add_child(m)
    overlay_title = _label("", 26, ArcanaTheme.GOLD)
    overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    overlay_body = _rich(160)
    overlay_body.add_theme_font_size_override("normal_font_size", 14)
    overlay_body.add_theme_font_size_override("bold_font_size", 14)
    overlay_body.add_theme_font_size_override("italics_font_size", 13)
    overlay_button = Button.new()
    overlay_button.text = "Continue"
    overlay_button.custom_minimum_size = Vector2(0, 34)
    overlay_button.pressed.connect(_dismiss_overlay)
    v.add_child(overlay_title); v.add_child(overlay_body); v.add_child(overlay_button)
    overlay.set_meta("dimmer", dimmer)

# --- refresh ----------------------------------------------------------------

func _refresh() -> void:
    if engine.players.is_empty(): return
    var me: Dictionary = engine.players[HUMAN]
    var them: Dictionary = engine.players[RIVAL]
    var my_turn: bool = engine.current_player == HUMAN and not engine.match_over and not bool(me["passed"])

    chapter_label.text = "Chapter %d of 3   ·   Seals %d–%d" % [engine.chapter, int(me["seals"]), int(them["seals"])]
    if engine.match_over:
        turn_label.text = "MATCH OVER"
        turn_label.add_theme_color_override("font_color", ArcanaTheme.GOLD)
    elif bool(me["passed"]) and not bool(them["passed"]):
        turn_label.text = "You passed — the rival plays on"
        turn_label.add_theme_color_override("font_color", ArcanaTheme.TEXT_DIM)
    else:
        turn_label.text = "YOUR TURN" if my_turn else "RIVAL'S TURN"
        turn_label.add_theme_color_override("font_color", ArcanaTheme.YOU if my_turn else ArcanaTheme.RIVAL)

    _refresh_player_strip(0, HUMAN, "YOU")
    _refresh_player_strip(1, RIVAL, "RIVAL")
    _refresh_hand(my_turn)
    _refresh_pass_preview()

    for el_id in shape_buttons:
        var b: Button = shape_buttons[el_id]
        b.disabled = not my_turn or engine.legal_shape_tiles(HUMAN, el_id).is_empty()
        b.button_pressed = (mode == "shape" and shape_element == el_id)
    command_button.disabled = not my_turn or bool(me["commander_used"])
    command_button.button_pressed = mode == "command"
    pass_button.disabled = not my_turn
    cancel_button.disabled = mode == ""

    var lines: Array[String] = []
    var start: int = maxi(0, engine.event_log.size() - 3)
    for i in range(start, engine.event_log.size()):
        var colour := ArcanaTheme.TEXT_DIM if i < engine.event_log.size() - 1 else ArcanaTheme.TEXT
        lines.append("[color=#%s]%s[/color]" % [colour.to_html(false), engine.event_log[i]])
    log_label.text = "\n".join(lines)

    _refresh_coach()
    _refresh_highlights()
    board_view.queue_redraw()

    if engine.current_player == RIVAL and not engine.match_over and not ai_busy and not overlay_open:
        call_deferred("_run_ai")

func _refresh_player_strip(index: int, player: int, title: String) -> void:
    var p: Dictionary = engine.players[player]
    var cmd: Dictionary = db.get_commander(String(p["commander_id"]))
    var accent: Color = ArcanaTheme.owner_color(player)
    var seals := ""
    for i in range(MatchEngine.SEALS_TO_WIN):
        seals += "◆" if i < int(p["seals"]) else "◇"
    var note := "  [color=#%s](passed)[/color]" % ArcanaTheme.TEXT_FAINT.to_html(false) if bool(p["passed"]) else ""
    player_strips[index]["stats"].text = ("[b][color=#%s]%s · %s[/color][/b]   " +
        "[color=#%s]♥ %d[/color]  [color=#%s]%s[/color]  " +
        "[color=#%s]✦ %d/10[/color]  [color=#%s]◈ %d/%d[/color]  ✋ %d%s") % [
        accent.to_html(false), title, String(cmd.get("name", "Commander")),
        ArcanaTheme.HEART.to_html(false), int(p["heart"]),
        ArcanaTheme.SEAL.to_html(false), seals,
        ArcanaTheme.WONDER.to_html(false), int(p["wonder"]),
        ArcanaTheme.AETHER.to_html(false), int(p["aether"]), int(p["max_aether"]),
        p["hand"].size(), note]

func _refresh_hand(my_turn: bool) -> void:
    var hand: Array = engine.players[HUMAN]["hand"]
    # Only rebuild when the hand or its playability actually changed, so hover
    # and lift animations are not reset every state change.
    var signature := "%s|%s|%d|%s" % [str(hand), str(my_turn), int(engine.players[HUMAN]["aether"]), selected_card_id]
    if signature == _hand_signature: return
    _hand_signature = signature
    for child in hand_row.get_children(): child.queue_free()
    if hand.is_empty():
        var empty := _label("No cards in hand. Shape a tile, move a creature, or Pass to score the Chapter.",
            14, ArcanaTheme.TEXT_FAINT)
        hand_row.add_child(empty)
        return
    var counts: Dictionary = {}
    for card_id in hand:
        counts[card_id] = int(counts.get(card_id, 0)) + 1
    var shown: Array = []
    for card_id in hand:
        if shown.has(card_id): continue
        shown.append(card_id)
        var view := CardView.new()
        var reason := engine.card_block_reason(HUMAN, String(card_id)) if my_turn else "Wait for your turn."
        view.setup(db.get_card(String(card_id)), reason, art)
        view.selected = (selected_card_id == String(card_id))
        view.count = int(counts[card_id])
        view.card_clicked.connect(_select_card)
        view.card_hovered.connect(_describe_card)
        hand_row.add_child(view)

func _refresh_pass_preview() -> void:
    var preview: Dictionary = engine.pass_preview(HUMAN)
    var mine: Dictionary = preview["my_breakdown"]
    var rival_note := "" if bool(preview["rival_passed"]) else "  [color=#%s](rival still playing)[/color]" % ArcanaTheme.TEXT_FAINT.to_html(false)
    pass_body.text = ("[b]%s[/b]\nRealm [color=#%s]%d[/color] – [color=#%s]%d[/color]" +
        "  ·  %d creatures, %d land, %d landmarks\nYou keep %d cards.%s") % [
        String(preview["outcome"]),
        ArcanaTheme.YOU.to_html(false), int(preview["my_score"]),
        ArcanaTheme.RIVAL.to_html(false), int(preview["rival_score"]),
        int(mine["creatures"]), int(mine["terrain"]), int(mine["landmarks"]),
        int(preview["cards_kept"]), rival_note]

func _refresh_highlights() -> void:
    board_view.highlights.clear()
    board_view.selected_pos = selected_unit_pos
    if engine.current_player != HUMAN or engine.match_over: return
    match mode:
        "card":
            if pending_primary.x >= 0:
                board_view.selected_pos = pending_primary
                for pos in engine.legal_push_targets(pending_primary):
                    board_view.highlights[pos] = "move"
            else:
                for pos in engine.legal_targets_for_card(HUMAN, selected_card_id):
                    board_view.highlights[pos] = "target"
        "shape":
            for pos in engine.legal_shape_tiles(HUMAN, shape_element):
                board_view.highlights[pos] = "target"
        "command":
            for y in range(BoardModel.HEIGHT):
                for x in range(BoardModel.WIDTH):
                    board_view.highlights[Vector2i(x, y)] = "target"
        "unit":
            var legal: Dictionary = engine.legal_moves_for_unit(HUMAN, selected_unit_pos)
            for pos in legal["moves"]: board_view.highlights[pos] = "move"
            for pos in legal["attacks"]: board_view.highlights[pos] = "attack"
            if bool(legal["heart"]): board_view.highlights[engine.sanctuary_pos(RIVAL)] = "heart"

# --- first-match coach ------------------------------------------------------
#
# ONBOARDING_AND_ACCESSIBILITY: teach the normal game through the UI. The coach
# never changes a rule or blocks an action — it just names the next idea.

func _mark_tutorial(step_id: String) -> void:
    if tutorial_done.has(step_id): return
    tutorial_done[step_id] = true
    var steps: Array = db.tutorial.get("steps", [])
    for step in steps:
        if String(step.get("id", "")) == step_id:
            _show_banner(String(step.get("success", "")), 1.1)
            return

func _refresh_coach() -> void:
    var steps: Array = db.tutorial.get("steps", [])
    if steps.is_empty():
        coach_panel.visible = false
        return
    var done := 0
    for step in steps:
        if tutorial_done.has(String(step.get("id", ""))): done += 1
    if done >= steps.size():
        coach_title.text = "LEARNING THE GAME  ·  all done"
        coach_body.text = "[i]Every action used. The rest is strategy.[/i]"
        return
    for step in steps:
        var id := String(step.get("id", ""))
        if tutorial_done.has(id): continue
        coach_title.text = "TRY THIS  (%d of %d)  ·  %s" % [done + 1, steps.size(), String(step.get("title", ""))]
        coach_body.text = String(step.get("instruction", ""))
        return

# --- selection --------------------------------------------------------------

func _clear_selection() -> void:
    mode = ""; selected_card_id = ""; shape_element = ""
    selected_unit_pos = Vector2i(-1, -1); pending_primary = Vector2i(-1, -1)
    var cmd: Dictionary = db.get_commander(String(engine.players[HUMAN]["commander_id"]))
    detail_title.text = "Take your turn"
    detail_body.text = ("Click a card, a Shape element, or a creature.\n\n" +
        "[b]%s[/b]\n[i]%s[/i]\n%s") % [
        String(cmd.get("name", "Commander")), String(cmd.get("passive_text", "")), String(cmd.get("command_text", ""))]
    _hand_signature = ""
    _refresh()

func _select_card(card_id: String) -> void:
    var reason := engine.card_block_reason(HUMAN, card_id)
    if reason != "":
        _describe_card(card_id)
        detail_body.text += "\n\n[color=#%s]%s[/color]" % [ArcanaTheme.DANGER.to_html(false), reason]
        return
    mode = "card"; selected_card_id = card_id; shape_element = ""
    selected_unit_pos = Vector2i(-1, -1); pending_primary = Vector2i(-1, -1)
    _describe_card(card_id)
    detail_body.text += "\n\n[color=#%s]Click a glowing tile.[/color]" % ArcanaTheme.GOLD.to_html(false)
    _hand_signature = ""
    _refresh()

func _describe_card(card_id: String) -> void:
    var card: Dictionary = db.get_card(card_id)
    if card.is_empty(): return
    detail_title.text = String(card.get("name", ""))
    var els: Array[String] = []
    for el in card.get("elements", []):
        els.append("%s %s" % [ArcanaTheme.element_icon.get(el, ""), ArcanaTheme.element_name.get(el, el)])
    var body := "%s · %s · %d Aether\n%s\n\n%s" % [
        String(card.get("type", "")).capitalize(), " + ".join(els),
        int(card.get("cost", 0)), String(card.get("rules", "")),
        _attunement_note(card)]
    detail_body.text = body

func _attunement_note(card: Dictionary) -> String:
    var need: Array = card.get("attunement", [])
    if need.is_empty(): return ""
    var names: Array[String] = []
    for el in need: names.append(String(ArcanaTheme.element_name.get(el, el)))
    var missing: Array[String] = engine.missing_attunement(HUMAN, need)
    if missing.is_empty():
        return "[i]Needs %s in your realm — you have it.[/i]" % " and ".join(names)
    return "[color=#%s]Needs %s in your realm. Shape it first.[/color]" % [
        ArcanaTheme.DANGER.to_html(false), " and ".join(names)]

func _choose_shape(el: String) -> void:
    mode = "shape"; shape_element = el; selected_card_id = ""; selected_unit_pos = Vector2i(-1, -1)
    detail_title.text = "Shape %s" % ArcanaTheme.element_name.get(el, el)
    detail_body.text = "Turn a tile beside your realm into %s, giving %s Attunement.\n\n[color=#%s]Click a glowing tile.[/color] Shaping is your whole turn." % [
        ArcanaTheme.label_for_terrain(engine.terrain_for_element(el)),
        ArcanaTheme.element_name.get(el, el), ArcanaTheme.GOLD.to_html(false)]
    _hand_signature = ""
    _refresh()

func _choose_command() -> void:
    mode = "command"; selected_card_id = ""; shape_element = ""; selected_unit_pos = Vector2i(-1, -1)
    var cmd: Dictionary = db.get_commander(String(engine.players[HUMAN]["commander_id"]))
    detail_title.text = String(cmd.get("name", "Commander"))
    detail_body.text = "[i]%s[/i]\n\n%s\n\n[color=#%s]Click any tile. Once per Chapter.[/color]" % [
        String(cmd.get("passive_text", "")), String(cmd.get("command_text", "")),
        ArcanaTheme.GOLD.to_html(false)]
    _hand_signature = ""
    _refresh()

func _on_tile_hovered(pos: Vector2i) -> void:
    if mode != "" or pos.x < 0: return
    var tile: Dictionary = engine.board.get_tile(pos)
    if tile.is_empty(): return
    var unit = tile.get("creature")
    detail_title.text = ArcanaTheme.label_for_terrain(String(tile.get("terrain", "neutral")))
    var parts: Array[String] = []
    var owner := int(tile.get("owner", -1))
    parts.append("Held by: %s" % ("you" if owner == HUMAN else ("the rival" if owner == RIVAL else "nobody")))
    var states: Array = tile.get("states", [])
    if not states.is_empty():
        var named: Array[String] = []
        for s in states: named.append("%s %s" % [ArcanaTheme.icon_for_state(String(s)), ArcanaTheme.label_for_state(String(s))])
        parts.append("States: " + ", ".join(named))
        if states.size() == 1:
            parts.append("[i]Add a second, different state here to discover new terrain.[/i]")
    if unit != null:
        parts.append("%s — %d Power, %d Health" % [String(unit.get("name", "")), int(unit.get("power", 0)), int(unit.get("health", 0))])
    var lm = tile.get("landmark")
    if lm != null: parts.append("⌂ %s (%d Presence)" % [String(lm.get("name", "")), int(lm.get("presence", 1))])
    detail_body.text = "\n".join(parts)

func _on_tile_clicked(pos: Vector2i) -> void:
    if engine.match_over or overlay_open: return
    if engine.current_player != HUMAN:
        _refuse("It is the rival's turn.")
        return
    var result: Dictionary = {}
    match mode:
        "card":
            if pending_primary.x >= 0:
                result = engine.play_card(HUMAN, selected_card_id, pending_primary, pos)
            else:
                result = engine.play_card(HUMAN, selected_card_id, pos)
            if bool(result.get("needs_second_target", false)):
                pending_primary = pos
                detail_title.text = String(db.get_card(selected_card_id).get("name", ""))
                detail_body.text = "[color=#%s]%s[/color]" % [ArcanaTheme.GOLD.to_html(false), String(result.get("reason", ""))]
                _refresh()
                return
        "shape": result = engine.shape(HUMAN, shape_element, pos)
        "command": result = engine.use_commander(HUMAN, pos)
        "unit":
            if pos == engine.sanctuary_pos(RIVAL) and engine.can_attack_heart(HUMAN, selected_unit_pos):
                result = engine.attack_heart(HUMAN, selected_unit_pos)
            else:
                result = engine.move_or_attack(HUMAN, selected_unit_pos, pos)
        _:
            var unit = engine.board.get_tile(pos).get("creature")
            if unit != null and int(unit.get("owner", -1)) == HUMAN:
                mode = "unit"; selected_unit_pos = pos
                var legal: Dictionary = engine.legal_moves_for_unit(HUMAN, pos)
                detail_title.text = String(unit.get("name", "Creature"))
                # The Heart strike is the decision here, so it leads.
                var hint := ""
                if bool(legal["heart"]):
                    hint += "[color=#%s]Click the rival Sanctuary to strike for %d — the Ward hits back for %d.[/color]\n" % [
                        ArcanaTheme.HEART.to_html(false), int(unit.get("power", 0)), MatchEngine.SANCTUARY_WARD]
                hint += "Move one tile, or step into a rival creature to fight."
                detail_body.text = "%d Power · %d Health\n\n%s" % [
                    int(unit.get("power", 0)), int(unit.get("health", 0)), hint]
                _refresh()
            else:
                _on_tile_hovered(pos)
            return
    if bool(result.get("ok", false)):
        _clear_selection()
    else:
        _refuse(String(result.get("reason", "That is not a legal action.")))

func _refuse(reason: String) -> void:
    detail_title.text = "Can't do that"
    detail_body.text = "[color=#%s]%s[/color]" % [ArcanaTheme.DANGER.to_html(false), reason]

func _do_pass() -> void:
    var result: Dictionary = engine.pass_chapter(HUMAN)
    if not bool(result.get("ok", false)): _refuse(String(result.get("reason", "")))
    else: _clear_selection()

# --- rival turn -------------------------------------------------------------

func _run_ai() -> void:
    if ai_busy: return
    ai_busy = true
    while engine.current_player == RIVAL and not engine.match_over:
        await get_tree().create_timer(AI_THINK_TIME).timeout
        while overlay_open:
            await get_tree().create_timer(0.2).timeout
        if engine.match_over or engine.current_player != RIVAL: break
        engine.perform(RIVAL, engine.ai.choose_action(engine, RIVAL))
    ai_busy = false
    _refresh()

# --- events -> flourishes ---------------------------------------------------

func _on_event(event: Dictionary) -> void:
    if board_view == null: return
    var kind := String(event.get("type", ""))
    var pos: Vector2i = event.get("pos", Vector2i(-1, -1))
    if int(event.get("player", -1)) == HUMAN:
        match kind:
            "creature_summoned", "landmark_built", "spell_cast": _mark_tutorial("play_card")
            "shape": _mark_tutorial("shape")
            "unit_moved", "combat", "heart_attack": _mark_tutorial("move")
            "passed": _mark_tutorial("pass")
            "recipe": _mark_tutorial("recipe")
            "commander": _mark_tutorial("commander")
    match kind:
        "creature_summoned", "token_summoned":
            board_view.flash_tile(pos, ArcanaTheme.owner_color(int(event.get("player", -1))))
            board_view.ring(pos, ArcanaTheme.owner_color(int(event.get("player", -1))))
        "landmark_built":
            board_view.flash_tile(pos, ArcanaTheme.owner_color(int(event.get("player", -1))))
        "spell_cast":
            board_view.ring(pos, ArcanaTheme.GOLD)
        "shape":
            board_view.flash_tile(pos, ArcanaTheme.color_for_element(String(event.get("element", ""))))
        "state_added":
            var c: Color = ArcanaTheme.color_for_state(String(event.get("state", "")))
            board_view.flash_tile(pos, c)
            board_view.float_text(pos, ArcanaTheme.icon_for_state(String(event.get("state", ""))), c)
        "recipe":
            board_view.ring(pos, ArcanaTheme.GOLD, 1.0)
            board_view.flash_tile(pos, ArcanaTheme.GOLD, 0.8)
            board_view.shake(0.6)
            var rid := String(event.get("recipe_id", ""))
            if not discovered.has(rid):
                discovered[rid] = true
                _show_banner("DISCOVERY: %s" % String(event.get("name", "New terrain")))
            else:
                board_view.float_text(pos, String(event.get("name", "")), ArcanaTheme.GOLD)
        "combat":
            board_view.float_text(event.get("to", pos), "-%d" % int(event.get("enemy_damage", 0)), ArcanaTheme.DANGER)
            board_view.float_text(event.get("from", pos), "-%d" % int(event.get("my_damage", 0)), ArcanaTheme.DANGER)
            board_view.shake(0.5)
        "unit_damaged":
            board_view.float_text(pos, "-%d" % int(event.get("amount", 0)), ArcanaTheme.DANGER)
        "unit_died":
            board_view.flash_tile(pos, ArcanaTheme.DANGER, 0.6)
        "heart_attack":
            var target: Vector2i = engine.sanctuary_pos(1 - int(event.get("player", 0)))
            board_view.float_text(target, "-%d" % int(event.get("amount", 0)), ArcanaTheme.HEART)
            board_view.flash_tile(target, ArcanaTheme.HEART, 0.6)
            board_view.shake(1.0)
        "ward_retaliation":
            board_view.float_text(pos, "Ward -%d" % int(event.get("amount", 0)), ArcanaTheme.WONDER)
        "heart_healed":
            if int(event.get("amount", 0)) > 0:
                board_view.float_text(engine.sanctuary_pos(int(event.get("player", 0))), "+%d" % int(event.get("amount", 0)), ArcanaTheme.YOU)
        "heart_damaged":
            board_view.float_text(engine.sanctuary_pos(int(event.get("player", 0))), "-%d" % int(event.get("amount", 0)), ArcanaTheme.HEART)
        "wonder":
            board_view.float_text(engine.sanctuary_pos(int(event.get("player", 0))), "+%d ✦" % int(event.get("amount", 0)), ArcanaTheme.WONDER)
        "commander_passive":
            board_view.float_text(engine.sanctuary_pos(int(event.get("player", 0))), "✦", ArcanaTheme.GOLD)
        "commander":
            _show_banner(String(event.get("name", "Commander")), 0.9)

func _show_banner(text: String, hold: float = 1.5) -> void:
    var holder: Control = banner.get_meta("holder")
    banner.text = text
    holder.modulate.a = 0.0
    var tween := create_tween()
    tween.tween_property(holder, "modulate:a", 1.0, 0.18)
    tween.tween_interval(hold)
    tween.tween_property(holder, "modulate:a", 0.0, 0.4)

# --- overlays ---------------------------------------------------------------

func _on_chapter_resolved(summary: Dictionary) -> void:
    var scores: Array = summary["scores"]
    var breakdown: Array = summary["breakdown"]
    var chapter_winner := int(summary["winner"])
    overlay_title.text = "Chapter %d" % int(summary["chapter"])
    var verdict := "Nobody earns a Seal — the Chapter is tied."
    if chapter_winner == HUMAN: verdict = "You earn a Chapter Seal."
    elif chapter_winner == RIVAL: verdict = "The rival earns a Chapter Seal."
    var seals: Array = summary["seals"]
    var hands: Array = summary["hand_sizes"]
    overlay_body.text = ("[b]%s[/b]\n\nRealm Score: [color=#%s]you %d[/color] · [color=#%s]rival %d[/color]\n" +
        "You: %d creatures + %d land + %d landmarks\nRival: %d creatures + %d land + %d landmarks\n\n" +
        "Seals %d–%d.  Cards kept: you %d, rival %d.\n\n[i]Terrain and landmarks stay. Creatures go home.[/i]") % [
        verdict,
        ArcanaTheme.YOU.to_html(false), int(scores[0]), ArcanaTheme.RIVAL.to_html(false), int(scores[1]),
        int(breakdown[0]["creatures"]), int(breakdown[0]["terrain"]), int(breakdown[0]["landmarks"]),
        int(breakdown[1]["creatures"]), int(breakdown[1]["terrain"]), int(breakdown[1]["landmarks"]),
        int(seals[0]), int(seals[1]), int(hands[0]), int(hands[1])]
    overlay_button.text = "Continue"
    _open_overlay()

func _on_match_finished(match_winner: int) -> void:
    await get_tree().create_timer(0.5).timeout
    overlay_title.text = "YOU WIN" if match_winner == HUMAN else "THE RIVAL WINS"
    overlay_body.text = "[b]%s[/b]\n\nFinal Hearts: you %d, rival %d.\nSeals %d–%d.  Wonder %d and %d.\n" % [
        engine.win_reason,
        int(engine.players[0]["heart"]), int(engine.players[1]["heart"]),
        int(engine.players[0]["seals"]), int(engine.players[1]["seals"]),
        int(engine.players[0]["wonder"]), int(engine.players[1]["wonder"])]
    overlay_button.text = "Play again"
    _open_overlay()

func _open_overlay() -> void:
    overlay.get_meta("dimmer").visible = true
    overlay_open = true

func _dismiss_overlay() -> void:
    overlay.get_meta("dimmer").visible = false
    overlay_open = false
    if engine.match_over:
        discovered.clear()
        board_view.clear_flourishes()
        engine.setup(db, "starter_life", "starter_fire", randi_range(0, 1 << 30))
        _clear_selection()
    else:
        _refresh()
