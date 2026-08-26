extends Control
## Pocket Arcana V2 match screen.
##
## Interaction is deliberately tiny: pick a card, the legal lanes light up and
## everything else goes dark; pick a creature, its lane shows where the attack
## goes. One Card Play and one Attack, then End Turn.
##
## Animations are sequenced through a small scheduler so a turn reads as a
## series of beats instead of everything firing at once.

const HUMAN := 0
const RIVAL := 1
const HAND_H := 168.0
const REST_SCALE := 0.72             # the hand sits small until you point at it
const HOVER_SCALE := 1.18

var db := ContentDatabase.new()
var engine := MatchV2.new()
var art := ArtRegistry.new()
var ai := SimpleAIV2.new()

var stage: StageV2
var hand_row: Control
var context_panel: PanelContainer
var context_title: Label
var context_body: RichTextLabel
var coach_panel: PanelContainer
var coach_label: Label
var end_turn_button: Button
var fuse_button: Button
var commander_button: Button
var banner: Label
var overlay: PanelContainer
var overlay_title: Label
var overlay_body: RichTextLabel

# Interaction state.
var mode := ""                       # "" | "card" | "attack" | "commander"
var selected_card := ""
var selected_lane := -1
var ai_busy := false
var overlay_open := false
var tutorial_step := 0
var tutorial_active := true
var _hand_signature := ""
var _cards: Array = []
var _stage_free_at := 0.0            # scheduler cursor, in seconds
var _drawing := 0                    # cards still in flight from the deck

func _ready() -> void:
    if not db.load_all():
        push_error("V2: content failed to load")
        return
    ArcanaTheme.configure(db)
    art.load_manifest()
    _build_ui()
    add_child(engine)
    engine.state_changed.connect(_refresh)
    engine.event_emitted.connect(_on_event)
    engine.match_finished.connect(_on_match_finished)
    engine.setup(db, "starter_life", "starter_fire")
    _refresh()
    _advance_tutorial()

# --- construction -----------------------------------------------------------

func _build_ui() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var bg := ColorRect.new()
    bg.color = ArcanaTheme.BG
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    stage = StageV2.new()
    stage.engine = engine
    stage.art = art
    stage.set_anchors_preset(Control.PRESET_FULL_RECT)
    stage.offset_top = 0.0
    stage.offset_bottom = -HAND_H
    stage.lane_clicked.connect(_on_lane_clicked)
    stage.lane_hovered.connect(_on_lane_hovered)
    stage.sanctuary_clicked.connect(_on_sanctuary_clicked)
    add_child(stage)

    hand_row = Control.new()
    hand_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    hand_row.offset_top = -HAND_H
    hand_row.offset_left = 150.0
    hand_row.offset_right = -260.0
    hand_row.clip_contents = false
    hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(hand_row)

    _build_controls()
    _build_context()
    _build_coach()
    _build_overlay()

func _build_controls() -> void:
    end_turn_button = Button.new()
    end_turn_button.text = "END TURN"
    end_turn_button.add_theme_font_size_override("font_size", 15)
    end_turn_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    end_turn_button.offset_left = -238.0; end_turn_button.offset_right = -18.0
    end_turn_button.offset_top = -74.0; end_turn_button.offset_bottom = -22.0
    end_turn_button.pressed.connect(_do_end_turn)
    add_child(end_turn_button)

    fuse_button = Button.new()
    fuse_button.text = "COMBINE"
    fuse_button.add_theme_font_size_override("font_size", 13)
    fuse_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    fuse_button.offset_left = -238.0; fuse_button.offset_right = -18.0
    fuse_button.offset_top = -132.0; fuse_button.offset_bottom = -84.0
    fuse_button.pressed.connect(_do_fuse)
    add_child(fuse_button)

    commander_button = Button.new()
    commander_button.text = "COMMANDER"
    commander_button.add_theme_font_size_override("font_size", 13)
    commander_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    commander_button.offset_left = -238.0; commander_button.offset_right = -18.0
    commander_button.offset_top = -190.0; commander_button.offset_bottom = -142.0
    commander_button.pressed.connect(_do_commander)
    add_child(commander_button)

    var realm := Button.new()
    realm.text = "BUILD REALM"
    realm.add_theme_font_size_override("font_size", 13)
    realm.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    realm.offset_left = 16.0; realm.offset_right = 138.0
    realm.offset_top = -190.0; realm.offset_bottom = -142.0
    realm.pressed.connect(_choose_realm)
    add_child(realm)
    realm.set_meta("role", "realm")
    set_meta("realm_button", realm)

func _build_context() -> void:
    context_panel = PanelContainer.new()
    context_panel.add_theme_stylebox_override("panel",
        ArcanaTheme.panel_box(Color(ArcanaTheme.PANEL, 0.95), ArcanaTheme.PANEL_EDGE, 10, 1))
    context_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    context_panel.offset_left = -282.0; context_panel.offset_right = -14.0
    context_panel.offset_top = 104.0; context_panel.offset_bottom = 104.0
    context_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    context_panel.visible = false
    var v := VBoxContainer.new()
    var m := MarginContainer.new()
    for s in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + s, 10)
    m.add_child(v)
    context_panel.add_child(m)
    context_title = Label.new()
    context_title.add_theme_font_size_override("font_size", 14)
    context_title.add_theme_color_override("font_color", ArcanaTheme.GOLD)
    context_body = RichTextLabel.new()
    context_body.bbcode_enabled = true
    context_body.fit_content = true
    context_body.scroll_active = false
    context_body.custom_minimum_size = Vector2(0, 30)
    for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
        context_body.add_theme_font_size_override(k, 12)
    context_body.add_theme_color_override("default_color", ArcanaTheme.TEXT_DIM)
    v.add_child(context_title); v.add_child(context_body)
    add_child(context_panel)

func _build_coach() -> void:
    coach_panel = PanelContainer.new()
    coach_panel.add_theme_stylebox_override("panel",
        ArcanaTheme.panel_box(Color(ArcanaTheme.BG, 0.92), ArcanaTheme.GOLD, 10, 2))
    coach_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    coach_panel.offset_top = 4.0
    coach_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var m := MarginContainer.new()
    for s in ["left", "right"]: m.add_theme_constant_override("margin_" + s, 20)
    for s in ["top", "bottom"]: m.add_theme_constant_override("margin_" + s, 6)
    coach_panel.add_child(m)
    coach_label = Label.new()
    coach_label.add_theme_font_size_override("font_size", 14)
    coach_label.add_theme_color_override("font_color", ArcanaTheme.TEXT)
    m.add_child(coach_label)
    add_child(coach_panel)

    banner = Label.new()
    banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    banner.offset_top = 248.0
    banner.add_theme_font_size_override("font_size", 26)
    banner.add_theme_color_override("font_color", ArcanaTheme.GOLD)
    banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    banner.modulate.a = 0.0
    add_child(banner)

func _build_overlay() -> void:
    var dimmer := ColorRect.new()
    dimmer.color = Color(0, 0, 0, 0.62)
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
    overlay.custom_minimum_size = Vector2(520, 0)
    centre.add_child(overlay)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    var m := MarginContainer.new()
    for s in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + s, 24)
    m.add_child(v)
    overlay.add_child(m)
    overlay_title = Label.new()
    overlay_title.add_theme_font_size_override("font_size", 26)
    overlay_title.add_theme_color_override("font_color", ArcanaTheme.GOLD)
    overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    overlay_body = RichTextLabel.new()
    overlay_body.bbcode_enabled = true
    overlay_body.fit_content = true
    overlay_body.custom_minimum_size = Vector2(0, 90)
    overlay_body.add_theme_font_size_override("normal_font_size", 14)
    var again := Button.new()
    again.text = "Play again"
    again.custom_minimum_size = Vector2(0, 34)
    again.pressed.connect(_restart)
    v.add_child(overlay_title); v.add_child(overlay_body); v.add_child(again)
    overlay.set_meta("dimmer", dimmer)

# --- refresh ----------------------------------------------------------------

func _refresh() -> void:
    if engine.players.is_empty(): return
    var mine: Dictionary = engine.players[HUMAN]
    var my_turn: bool = engine.current_player == HUMAN and not engine.match_over

    _refresh_hand(my_turn)
    _refresh_highlights()

    end_turn_button.disabled = not my_turn
    var fusions: Array = engine.available_fusions(HUMAN)
    fuse_button.visible = my_turn and not fusions.is_empty()
    fuse_button.disabled = fusions.is_empty() or not bool(fusions[0]["affordable"])
    if not fusions.is_empty():
        var r: Dictionary = fusions[0]["recipe"]
        fuse_button.text = "COMBINE: %s (%d)" % [String(r.get("name", "")), int(r.get("cost", 0))]
    commander_button.visible = my_turn and engine.commander_block_reason(HUMAN) == ""
    var realm_button: Button = get_meta("realm_button")
    realm_button.visible = my_turn and int(mine["realm_stack"]) > 0 and not bool(mine["played_card"])
    realm_button.text = "BUILD REALM (%d)" % int(mine["realm_stack"])

    # Linked runes on any pair that can combine.
    var pairs: Array = []
    for option in fusions:
        pairs.append(int(option["a"])); pairs.append(int(option["b"]))
    stage.fusion_pairs = pairs

    if engine.current_player == RIVAL and not engine.match_over and not ai_busy and not overlay_open:
        call_deferred("_run_ai")

func _refresh_hand(my_turn: bool) -> void:
    var hand: Array = engine.players[HUMAN]["hand"]
    if _drawing > 0: return          # the incoming card is still flying
    var signature := "%s|%s|%d|%s|%s" % [str(hand), str(my_turn),
        int(engine.players[HUMAN]["aether"]), selected_card, str(engine.players[HUMAN]["played_card"])]
    if signature == _hand_signature: return
    _hand_signature = signature
    for c in _cards: c.queue_free()
    _cards.clear()
    var counts: Dictionary = {}
    for cid in hand: counts[cid] = int(counts.get(cid, 0)) + 1
    var shown: Array = []
    for cid_any in hand:
        var cid := String(cid_any)
        if shown.has(cid): continue
        shown.append(cid)
        var view := CardV2.new()
        var reason := engine.card_block_reason(HUMAN, cid) if my_turn else "Wait for your turn."
        view.setup(db.get_card(cid), engine.card_role(cid), engine.placement_line(cid), reason, art)
        view.count = int(counts[cid])
        view.selected = selected_card == cid
        view.size = CardV2.SIZE
        view.pivot_offset = Vector2(CardV2.SIZE.x * 0.5, CardV2.SIZE.y)
        view.scale = Vector2.ONE * REST_SCALE
        view.card_clicked.connect(_select_card)
        view.card_hovered.connect(_describe_card)
        view.mouse_entered.connect(func() -> void: _lift(view, true))
        view.mouse_exited.connect(func() -> void: _lift(view, false))
        hand_row.add_child(view)
        _cards.append(view)
    _layout_hand()

func _layout_hand() -> void:
    var n := _cards.size()
    if n == 0: return
    var card_w: float = CardV2.SIZE.x * REST_SCALE
    var spread: float = min(card_w + 10.0, max(44.0, (hand_row.size.x - card_w) / max(1, n - 1)))
    var total: float = card_w + spread * (n - 1)
    var start: float = (hand_row.size.x - total) * 0.5
    for i in range(n):
        var view: CardV2 = _cards[i]
        # Pivot is the card's bottom centre, so scaling grows it upward.
        view.position = Vector2(start + spread * i - (CardV2.SIZE.x - card_w) * 0.5,
            hand_row.size.y - CardV2.SIZE.y - 16.0)
        view.z_index = i

func _lift(view: CardV2, on: bool) -> void:
    view.hovered = on
    view.z_index = 40 if on else _cards.find(view)
    var tween := create_tween().set_parallel(true)
    tween.tween_property(view, "scale", Vector2.ONE * (HOVER_SCALE if on else REST_SCALE), 0.10)
    # A small tilt keeps the raised card feeling physical rather than scaled.
    var index := _cards.find(view)
    var lean: float = 0.0
    if on and _cards.size() > 1:
        lean = (float(index) / float(_cards.size() - 1) - 0.5) * 0.10
    tween.tween_property(view, "rotation", lean, 0.10)
    tween.tween_property(view, "position:y",
        hand_row.size.y - CardV2.SIZE.y - (34.0 if on else 16.0), 0.10)
    view.queue_redraw()

func _refresh_highlights() -> void:
    stage.highlights.clear()
    stage.dim_others = false
    stage.selected_lane = selected_lane
    if engine.current_player != HUMAN or engine.match_over: return
    match mode:
        "card":
            stage.dim_others = true
            for t in engine.legal_targets(HUMAN, selected_card):
                if int(t["lane"]) >= 0:
                    stage.highlights["%d,%d" % [int(t["side"]), int(t["lane"])]] = "legal"
            stage.ghost_card = selected_card
        "realm":
            stage.dim_others = true
            for i in range(MatchV2.LANES):
                if String(engine.lane(HUMAN, i)["land"]) == "":
                    stage.highlights["%d,%d" % [HUMAN, i]] = "legal"
        "attack":
            for i in engine.legal_attacks(HUMAN):
                stage.highlights["%d,%d" % [HUMAN, i]] = "legal"
            if selected_lane >= 0:
                stage.highlights["%d,%d" % [RIVAL, selected_lane]] = "attack"
        _:
            stage.ghost_card = ""      # nothing highlighted during normal play

# --- interaction ------------------------------------------------------------

func _clear() -> void:
    mode = ""; selected_card = ""; selected_lane = -1
    stage.ghost_card = ""
    context_panel.visible = false
    _hand_signature = ""
    _refresh()

func _select_card(card_id: String) -> void:
    var reason := engine.card_block_reason(HUMAN, card_id)
    _describe_card(card_id)
    if reason != "":
        context_body.text += "\n\n[color=#%s]%s[/color]" % [ArcanaTheme.DANGER.to_html(false), reason]
        return
    mode = "card"; selected_card = card_id; selected_lane = -1
    _hand_signature = ""
    _refresh()

func _choose_realm() -> void:
    mode = "realm"; selected_card = ""; selected_lane = -1
    _show_context("Build a Realm", "Choose an empty realm slot.\nMore land means more Aether every turn.")
    _refresh()

func _describe_card(card_id: String) -> void:
    var card := db.get_card(card_id)
    if card.is_empty(): return
    var role := engine.card_role(card_id)
    var lines: Array[String] = []
    lines.append("[b]%s[/b] · %d Aether" % [role, int(card.get("cost", 0))])
    lines.append("[b]%s[/b]" % engine.placement_line(card_id))
    lines.append(String(card.get("rules", "")))
    if role == "Creature":
        lines.append("[color=#%s]%d Attack[/color] · [color=#%s]%d Health[/color]" % [
            Color("#ffd98a").to_html(false), int(card.get("power", 0)),
            Color("#ffb3c4").to_html(false), int(card.get("health", 0))])
    _show_context(String(card.get("name", "")), "\n".join(lines))

func _show_context(title: String, body: String) -> void:
    context_title.text = title
    context_body.text = body
    context_panel.visible = true

func _on_lane_hovered(side: int, index: int) -> void:
    if side < 0 or index < 0: return
    if mode == "card":
        var why := engine.lane_block_reason(HUMAN, selected_card, side, index)
        if why != "":
            _show_context("Can't play there", "[color=#%s]%s[/color]" % [ArcanaTheme.DANGER.to_html(false), why])
        else:
            _describe_card(selected_card)
    elif mode == "":
        var l: Dictionary = engine.lane(side, index)
        var parts: Array[String] = []
        parts.append("Land: %s" % (String(l["land"]).capitalize() if String(l["land"]) != "" else "empty"))
        if l["creature"] != null:
            parts.append("[b]%s[/b] — %d Attack, %d Health" % [String(l["creature"]["name"]),
                int(l["creature"]["power"]), int(l["creature"]["health"])])
        if l["place"] != null: parts.append("⌂ %s" % String(l["place"]["name"]))
        if side == HUMAN and engine.attack_block_reason(HUMAN, index) == "":
            parts.append("[color=#%s]Click to attack lane %d.[/color]" % [ArcanaTheme.GOLD.to_html(false), index + 1])
        _show_context("Lane %d" % (index + 1), "\n".join(parts))

func _on_lane_clicked(side: int, index: int) -> void:
    if engine.match_over or overlay_open: return
    if engine.current_player != HUMAN:
        _show_context("Wait", "It is the rival's turn.")
        return
    match mode:
        "realm":
            var r := engine.play_realm(HUMAN, index)
            if bool(r.get("ok", false)): _clear()
            else: _show_context("Can't build there", String(r.get("reason", "")))
        "card":
            var start := _card_screen_pos(selected_card)
            var res := engine.play_card(HUMAN, selected_card, side, index)
            if bool(res.get("ok", false)):
                _fly_card(selected_card, start, stage.lane_rect(side, index).get_center())
                _clear()
            else:
                _show_context("Can't play there", "[color=#%s]%s[/color]" % [
                    ArcanaTheme.DANGER.to_html(false), String(res.get("reason", ""))])
        "attack":
            if side == RIVAL and index == selected_lane:
                var a := engine.attack(HUMAN, index)
                if not bool(a.get("ok", false)):
                    _show_context("Can't attack", String(a.get("reason", "")))
                _clear()
            else:
                _begin_attack(index)
        _:
            if side == HUMAN: _begin_attack(index)

func _begin_attack(index: int) -> void:
    var why := engine.attack_block_reason(HUMAN, index)
    if why != "":
        _show_context("Can't attack", "[color=#%s]%s[/color]" % [ArcanaTheme.DANGER.to_html(false), why])
        return
    mode = "attack"; selected_lane = index
    var open := engine.lane_is_open(HUMAN, index)
    _show_context("Attack lane %d" % (index + 1),
        "No creature blocking — this hits the rival Heart.\n\n[color=#%s]Click the lane opposite to strike.[/color]" % ArcanaTheme.GOLD.to_html(false)
        if open else "A rival creature is blocking this lane.\n\n[color=#%s]Click it to fight.[/color]" % ArcanaTheme.GOLD.to_html(false))
    _refresh()

func _on_sanctuary_clicked(side: int) -> void:
    if mode == "attack" and side == RIVAL and selected_lane >= 0:
        engine.attack(HUMAN, selected_lane)
        _clear()

func _do_end_turn() -> void:
    _clear()
    engine.end_turn(HUMAN)
    _advance_tutorial()

func _do_fuse() -> void:
    var options: Array = engine.available_fusions(HUMAN)
    if options.is_empty(): return
    var option: Dictionary = options[0]
    var r := engine.fuse(HUMAN, String(option["recipe"]["id"]), int(option["a"]), int(option["b"]))
    if not bool(r.get("ok", false)): _show_context("Can't combine", String(r.get("reason", "")))
    _clear()

func _do_commander() -> void:
    var r := engine.use_commander(HUMAN, RIVAL, -1)
    if not bool(r.get("ok", false)): _show_context("Can't use Commander", String(r.get("reason", "")))
    _clear()

func _card_screen_pos(card_id: String) -> Vector2:
    for view in _cards:
        if view.card_id == card_id:
            return view.global_position + view.size * 0.5 - stage.global_position
    return Vector2(stage.size.x * 0.5, stage.size.y)

# --- events become choreography ---------------------------------------------
#
# Events arrive the instant the simulation resolves. They are scheduled onto a
# cursor so a turn plays as a sequence of readable beats instead of a pile-up.

func _now() -> float:
    return float(Time.get_ticks_msec()) / 1000.0

## Reserve the next slot on the animation cursor and return when it starts.
func _schedule(duration: float, overlap := 0.72) -> float:
    var now := _now()
    # Never let the queue run more than a beat behind the player; a fast turn
    # compresses its animations instead of stacking up a backlog.
    var start: float = clampf(_stage_free_at, now, now + 1.1)
    _stage_free_at = start + duration * overlap
    return start - now

func _later(delay: float, fn: Callable) -> void:
    if delay <= 0.001:
        fn.call()
        return
    get_tree().create_timer(delay).timeout.connect(fn)

func _on_event(event: Dictionary) -> void:
    if stage == null: return
    var kind := String(event.get("type", ""))
    # The coach only advances on things the player actually did.
    if int(event.get("player", event.get("side", -1))) == HUMAN:
        match kind:
            "land_built": _mark_taught("land")
            "creature_summoned": _mark_taught("summon")
            "place_built": _mark_taught("place")
            "spell_cast": _mark_taught("spell")
            "heart_attack": _mark_taught("heart"); _mark_taught("attack")
            "creature_clash": _mark_taught("attack")
            "fusion": _mark_taught("fusion")
    match kind:
        "card_drawn":
            if int(event.get("player", -1)) != HUMAN: return
            var delay := _schedule(0.55, 0.55)
            var card_id := String(event.get("card_id", ""))
            # Hold the hand until the card actually arrives, so it visibly
            # appears rather than blinking into existence.
            _drawing += 1
            _later(delay, func() -> void:
                stage.play("draw", {
                    "from": stage.deck_anchor(HUMAN),
                    "to": Vector2(stage.size.x * 0.5, stage.size.y - 24.0),
                    "colour": stage.card_colour(card_id),
                    "label": String(db.get_card(card_id).get("name", "")),
                    "role": engine.card_role(card_id),
                }, 0.55))
            _later(delay + 0.5, func() -> void:
                _drawing = maxi(0, _drawing - 1)
                _hand_signature = ""
                _refresh())
        "land_built":
            var side := int(event["player"])
            var lane := int(event["lane"])
            var element := String(event["element"])
            var delay2 := _schedule(0.9)
            _later(delay2, func() -> void:
                stage.play("land_build", {"side": side, "lane": lane, "element": element}, 0.9))
        "creature_summoned":
            var side2 := int(event["player"])
            var lane2 := int(event["lane"])
            var cid := String(event["card_id"])
            var els: Array = db.get_card(cid).get("elements", [])
            var delay3 := _schedule(0.8)
            _later(delay3, func() -> void:
                stage.play("summon", {"side": side2, "lane": lane2,
                    "colour": stage.card_colour(cid),
                    "element": String(els[0]) if not els.is_empty() else ""}, 0.8))
        "place_built":
            var side3 := int(event["player"])
            var lane3 := int(event["lane"])
            var cid2 := String(event["card_id"])
            var delay4 := _schedule(0.85)
            _later(delay4, func() -> void:
                stage.play("place_build", {"side": side3, "lane": lane3,
                    "colour": stage.card_colour(cid2)}, 0.85))
        "spell_cast":
            var caster := int(event["player"])
            var side4 := int(event.get("side", caster))
            var lane4 := int(event.get("lane", -1))
            var cid3 := String(event["card_id"])
            var from := stage.sanctuary_rect(caster).get_center()
            var to := stage.creature_anchor(side4, lane4) if lane4 >= 0 else stage.sanctuary_rect(engine.opponent(caster)).get_center()
            var delay5 := _schedule(0.75)
            _later(delay5, func() -> void:
                stage.play("spell", {"from": from, "to": to, "colour": stage.card_colour(cid3)}, 0.75))
        "creature_clash":
            var side5 := int(event["player"])
            var lane5 := int(event["lane"])
            var attacker: Dictionary = event["attacker"]
            var defender: Dictionary = event["defender"]
            _play_attack(side5, lane5, attacker, "attack", engine.opponent(side5),
                int(event["damage_to_defender"]), int(event["damage_to_attacker"]), defender)
        "heart_attack":
            var side6 := int(event["player"])
            var lane6 := int(event["lane"])
            var attacker2: Dictionary = event["unit"]
            _play_attack(side6, lane6, attacker2, "heart_attack", engine.opponent(side6),
                int(event["amount"]), 0, {})
        "unit_died":
            var side7 := int(event["side"])
            var lane7 := int(event["lane"])
            var unit: Dictionary = event["unit"]
            var at := stage.creature_anchor(side7, lane7)
            _later(maxf(0.0, _stage_free_at - _now()) + 0.10, func() -> void:
                stage.play("death", {"at": at, "colour": stage.card_colour(String(unit["card_id"]))}, 0.6))
        "unit_damaged":
            var s8 := int(event["side"]); var l8 := int(event["lane"])
            var amount := int(event["amount"])
            var at2 := stage.creature_anchor(s8, l8)
            _later(maxf(0.0, _stage_free_at - _now()) * 0.6, func() -> void:
                stage.play("float", {"at": at2, "text": "-%d" % amount, "colour": ArcanaTheme.DANGER}, 0.8))
        "heart_damaged", "heart_healed":
            var who := int(event["player"])
            var amt := int(event.get("amount", 0))
            if amt <= 0: return
            var heal := kind == "heart_healed"
            var at3 := stage.sanctuary_rect(who).get_center()
            _later(maxf(0.0, _stage_free_at - _now()), func() -> void:
                stage.play("float", {"at": at3, "text": ("+%d" if heal else "-%d") % amt,
                    "colour": ArcanaTheme.YOU if heal else ArcanaTheme.HEART}, 0.9)
                if not heal: stage.play("heart_shock", {"side": who}, 0.5))
        "fusion":
            var side9 := int(event["player"])
            var lane9 := int(event["lane"])
            var freed := int(event["freed_lane"])
            var unit2: Dictionary = event["unit"]
            # The stage draws the two source cards converging, so it needs to
            # know which creature was in each lane before they merged. Read the
            # units the event carries — by the time this runs the engine has
            # already put the fused creature in lane_a, so looking the lanes up
            # returns the result twice instead of the two sources.
            var sources := {}
            var source_units: Array = event.get("sources", [])
            var source_lanes := [lane9, freed]
            for i in range(mini(source_units.size(), source_lanes.size())):
                var was = source_units[i]
                if was is Dictionary and was.has("card_id"):
                    sources[str(int(source_lanes[i]))] = String(was["card_id"])
            var delay6 := _schedule(1.5, 0.95)
            _later(delay6, func() -> void:
                stage.play("fusion", {"side": side9, "lane": lane9, "freed_lane": freed,
                    "cards": sources,
                    "colour": stage.card_colour(String(unit2["card_id"])),
                    "name": String(event.get("name", "")),
                    "element": String(db.get_card(String(unit2["card_id"])).get("elements", ["life"])[0])}, 1.5))
        "commander":
            var side10 := int(event["player"])
            var delay7 := _schedule(1.0)
            _later(delay7, func() -> void:
                _show_banner(String(event.get("name", "Commander")), 0.9)
                stage.play("commander", {"side": side10,
                    "from": stage.sanctuary_rect(side10).get_center(),
                    "to": stage.sanctuary_rect(engine.opponent(side10)).get_center()}, 1.0))
        "turn_started":
            _stage_free_at = _now()

func _play_attack(side: int, lane: int, attacker: Dictionary, kind: String, target_side: int,
                  damage_out: int, damage_back: int, defender: Dictionary) -> void:
    var card_id := String(attacker["card_id"])
    var style := _style_for(card_id)
    var styles: Dictionary = db.motion.get("styles", {})
    var data: Dictionary = styles.get(style, {})
    var dur := 0.9 if kind == "attack" else 1.05
    var delay := _schedule(dur, 0.95)
    _later(delay, func() -> void:
        var atk_els: Array = db.get_card(card_id).get("elements", [])
        stage.play(kind, {
            "side": side, "lane": lane, "uid": int(attacker["uid"]), "style": style,
            "target_side": target_side, "heart": kind == "heart_attack",
            "reach": float(data.get("reach", 0.6)), "arc": float(data.get("arc", 0.0)),
            "weight": float(data.get("impact_shake", 0.6)),
            # The stage picks the creature's motion and its impact effect from
            # these, so a dragon's breath differs from a deer's charge.
            "card_id": card_id,
            "projectile": String(data.get("projectile", "")),
            "element": String(atk_els[0]) if not atk_els.is_empty() else "",
            "colour": stage.card_colour(card_id),
        }, dur))
    # The defender recoils and the number appears only after the blow lands.
    var impact := delay + dur * (0.52 if kind == "attack" else 0.58)
    if not defender.is_empty():
        _later(delay + dur * 0.24, func() -> void:
            stage.play("defend", {"uid": int(defender["uid"])}, dur * 0.5))
    _later(impact, func() -> void:
        var to: Vector2 = stage.sanctuary_rect(target_side).get_center() if kind == "heart_attack" \
            else stage.clash_centre(lane)
        if not defender.is_empty():
            stage.play("recoil", {"uid": int(defender["uid"]),
                "push": Vector2(0, -1.0 if side == 0 else 1.0)}, 0.32)
        stage.play("float", {"at": to, "text": "-%d" % damage_out,
            "colour": ArcanaTheme.HEART if kind == "heart_attack" else ArcanaTheme.DANGER}, 0.9))
    if damage_back > 0:
        _later(impact + 0.10, func() -> void:
            stage.play("recoil", {"uid": int(attacker["uid"]),
                "push": Vector2(0, 1.0 if side == 0 else -1.0)}, 0.32)
            stage.play("float", {"at": stage.creature_anchor(side, lane),
                "text": "-%d" % damage_back, "colour": ArcanaTheme.DANGER}, 0.9))

func _style_for(card_id: String) -> String:
    var table: Dictionary = db.motion.get("creatures", {})
    if table.has(card_id): return String(table[card_id])
    return "lunge"

func _fly_card(card_id: String, from: Vector2, to: Vector2) -> void:
    stage.play("card_flight", {"from": from, "to": to,
        "colour": stage.card_colour(card_id),
        "label": String(db.get_card(card_id).get("name", ""))}, 0.4)

func _show_banner(text: String, hold: float) -> void:
    banner.text = text
    banner.modulate.a = 0.0
    var tween := create_tween()
    tween.tween_property(banner, "modulate:a", 1.0, 0.16)
    tween.tween_interval(hold)
    tween.tween_property(banner, "modulate:a", 0.0, 0.4)

# --- rival turn -------------------------------------------------------------

func _run_ai() -> void:
    if ai_busy: return
    ai_busy = true
    while engine.current_player == RIVAL and not engine.match_over:
        await get_tree().create_timer(0.5).timeout
        while stage.busy():
            await get_tree().create_timer(0.15).timeout
        if engine.match_over or engine.current_player != RIVAL: break
        ai.take_turn(engine, RIVAL)
        await get_tree().create_timer(maxf(0.3, _stage_free_at - _now())).timeout
    ai_busy = false
    _refresh()
    _advance_tutorial()

# --- scripted tutorial ------------------------------------------------------
#
# docs/V2_TUTORIAL.md: teach one obvious action, then immediately show why it
# mattered. The coach never blocks input; it only names the next idea.

## One concept at a time, in the order docs/V2_TUTORIAL.md sets out. Each step
## names the next idea and says how it is satisfied; the coach advances only when
## the player has actually done that thing, so nothing is taught out of order.
const TUTORIAL := [
    {"id": "sanctuary", "text": "This is your Sanctuary. Its Heart is what the rival is trying to break."},
    {"id": "land", "text": "Land gives you Aether and a home for creatures. Press BUILD REALM."},
    {"id": "summon", "text": "Pick a creature. Only the land it says PLAY ON will light up."},
    {"id": "attack", "text": "Creatures fight across their own lane. Click yours, then the lane opposite."},
    {"id": "place", "text": "A PLACE is a building. It supports the creature standing on its land."},
    {"id": "spell", "text": "A SPELL resolves at once on whatever it says TARGET."},
    {"id": "heart", "text": "No creature blocking a lane? That attack goes straight to the Heart."},
    {"id": "fusion", "text": "Two matching creatures can COMBINE into something stronger."},
    {"id": "done", "text": "That is the whole game: build land, summon, attack, break the Heart."},
]

## Which steps the player has already demonstrated.
var _taught: Dictionary = {}

func _mark_taught(id: String) -> void:
    if _taught.has(id): return
    _taught[id] = true
    _advance_tutorial()

func _advance_tutorial() -> void:
    if not tutorial_active:
        coach_panel.visible = false
        return
    var mine: Dictionary = engine.players[HUMAN]
    # Derive what has been demonstrated, so the coach never claims a step the
    # player has not actually performed.
    if engine.built_lands(HUMAN) >= 2: _taught["land"] = true
    for i in range(MatchV2.LANES):
        if engine.lane(HUMAN, i)["creature"] != null: _taught["summon"] = true
        if engine.lane(HUMAN, i)["place"] != null: _taught["place"] = true
    if int(engine.players[RIVAL]["heart"]) < MatchV2.HEART_START: _taught["heart"] = true
    if engine.turn >= 2: _taught["sanctuary"] = true

    for step in TUTORIAL:
        var id := String(step["id"])
        if id == "fusion" and engine.available_fusions(HUMAN).is_empty(): continue
        if id == "done": continue
        if _taught.has(id): continue
        coach_label.text = String(step["text"])
        coach_panel.visible = true
        tutorial_step = TUTORIAL.find(step)
        return
    # Everything demonstrated: say so once, then get out of the way.
    if not _taught.has("done"):
        _taught["done"] = true
        coach_label.text = String(TUTORIAL[TUTORIAL.size() - 1]["text"])
        coach_panel.visible = true
        get_tree().create_timer(6.0).timeout.connect(func() -> void:
            if coach_panel != null: coach_panel.visible = false)
    else:
        coach_panel.visible = false

func _on_match_finished(winner: int) -> void:
    await get_tree().create_timer(maxf(0.6, _stage_free_at - _now())).timeout
    stage.hitstop(0.2)
    stage.shake(1.4)
    overlay_title.text = "YOU WIN" if winner == HUMAN else "THE RIVAL WINS"
    overlay_body.text = "[b]%s[/b]\n\nHearts: you %d, rival %d.\nTurn %d." % [
        engine.win_reason, int(engine.players[0]["heart"]), int(engine.players[1]["heart"]), engine.turn]
    overlay.get_meta("dimmer").visible = true
    overlay_open = true

func _restart() -> void:
    overlay.get_meta("dimmer").visible = false
    overlay_open = false
    _stage_free_at = _now()
    engine.setup(db, "starter_life", "starter_fire", randi_range(0, 1 << 30))
    _clear()
    _advance_tutorial()
