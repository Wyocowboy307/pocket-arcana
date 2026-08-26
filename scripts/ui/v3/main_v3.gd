extends Control
## The V3 screen: board, hand, and the choreography between them.
##
## Rules live in MatchV3. This asks it what is legal, shows the exact refusal it
## gives, and animates only what it has already committed.

const HAND_H := 168.0
const REST_SCALE := 0.70
const HOVER_SCALE := 1.16
const HUMAN := 0
const RIVAL := 1

var db := ContentV3.new()
var engine: MatchV3
var ai: SimpleAIV3
var board: BoardV3
var art := ArtRegistry.new()
var hand_row: Control
var buttons: VBoxContainer
var banner: Label
var status: Label

var _cards: Array = []
var selected_card := ""
var mode := ""                        # "" | "card" | "attack" | "power"
var selected_lane := -1
var ai_busy := false
var _hand_signature := ""
var _queue: Array = []                # pending choreography, played in order
var _queue_time := 0.0

func _ready() -> void:
    if not db.load_all():
        push_error("V3: content failed to load")
        return
    art.load_manifest()
    engine = MatchV3.new()
    engine.event_emitted.connect(_on_event)
    ai = SimpleAIV3.new()

    board = BoardV3.new()
    board.set_anchors_preset(Control.PRESET_FULL_RECT)
    board.offset_bottom = -HAND_H
    board.engine = engine
    board.art = art
    board.slot_clicked.connect(_on_slot_clicked)
    board.slot_hovered.connect(func(_s: int, _l: int) -> void: board.queue_redraw())
    add_child(board)

    hand_row = Control.new()
    hand_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    hand_row.offset_top = -HAND_H
    hand_row.offset_left = 160.0
    hand_row.offset_right = -250.0
    hand_row.clip_contents = false
    hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(hand_row)

    _build_chrome()
    engine.setup(db, "v3_life", "v3_fire", 20250826)
    ai.setup(engine, 4242)
    _refresh()
    set_process(true)

func _build_chrome() -> void:
    banner = Label.new()
    banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
    banner.offset_top = 6.0
    banner.offset_left = -320.0
    banner.offset_right = 320.0
    banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner.add_theme_font_size_override("font_size", 14)
    add_child(banner)

    buttons = VBoxContainer.new()
    buttons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    buttons.offset_left = -238.0
    buttons.offset_top = -HAND_H + 6.0
    buttons.offset_right = -8.0
    buttons.offset_bottom = -8.0
    buttons.add_theme_constant_override("separation", 6)
    add_child(buttons)

    status = Label.new()
    status.add_theme_font_size_override("font_size", 11)
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status.custom_minimum_size = Vector2(230, 40)
    buttons.add_child(status)

func _process(delta: float) -> void:
    if not _queue.is_empty():
        _queue_time -= delta
        if _queue_time <= 0.0:
            var step: Dictionary = _queue.pop_front()
            var fn: Callable = step["run"]
            fn.call()
            _queue_time = float(step["wait"])
        return
    if engine != null and not engine.match_over and engine.current_player == RIVAL \
            and not ai_busy and not board.busy():
        ai_busy = true
        ai.take_turn(RIVAL)
        ai_busy = false
        _refresh()

func _later(wait: float, run: Callable) -> void:
    _queue.append({"wait": wait, "run": run})

# --- events -> choreography -------------------------------------------------

func _on_event(event: Dictionary) -> void:
    var kind := String(event.get("type", ""))
    match kind:
        "landscape_played":
            var side := int(event["player"]); var lane := int(event["lane"])
            _later(0.55, func() -> void:
                board.play("landscape", {"side": side, "lane": lane,
                    "element": String(event["element"])}, 0.75)
                board.shake(0.25))
        "creature_played":
            var s2 := int(event["player"]); var l2 := int(event["lane"])
            _later(0.5, func() -> void:
                board.play("summon", {"side": s2, "lane": l2}, 0.6))
        "support_played":
            var s3 := int(event["player"]); var l3 := int(event["lane"])
            _later(0.4, func() -> void:
                board.play("support", {"side": s3, "lane": l3}, 0.5))
        "creature_clash", "heart_attack":
            var s4 := int(event["player"]); var l4 := int(event["lane"])
            var attacker: Dictionary = event["attacker"]
            var to_heart := kind == "heart_attack"
            var atk_card := String(attacker["card_id"])
            _later(0.85, func() -> void:
                # Carry the attacker's identity in the act. Both creatures trade,
                # so the attacker can already be dead by the time its own lunge
                # animates — the board must not need it to still be in the lane.
                board.play("attack", {"side": s4, "lane": l4,
                    "uid": int(attacker["uid"]), "card_id": atk_card,
                    "heart": to_heart}, 0.8)
                board.shake(0.6 if to_heart else 0.4))
        "creature_damaged":
            var s5 := int(event["player"]); var l5 := int(event["lane"])
            var unit: Dictionary = event["unit"]
            var amount := int(event["amount"])
            _later(0.18, func() -> void:
                board.play("hurt", {"side": s5, "lane": l5, "uid": int(unit["uid"])}, 0.35)
                board.play("float", {"at": board.creature_rect(s5, l5).get_center(),
                    "text": "-%d" % amount, "colour": ArcanaTheme.DANGER}, 0.8))
        "creature_healed":
            var s6 := int(event["player"]); var l6 := int(event["lane"])
            _later(0.14, func() -> void:
                board.play("float", {"at": board.creature_rect(s6, l6).get_center(),
                    "text": "+%d" % int(event["amount"]), "colour": Color("#b8f27a")}, 0.8))
        "heart_changed":
            var who := int(event["player"])
            var amt := int(event["amount"])
            _later(0.2, func() -> void:
                board.play("float", {"at": board.commander_rect(who).get_center(),
                    "text": ("+%d" if amt > 0 else "%d") % amt,
                    "colour": Color("#b8f27a") if amt > 0 else ArcanaTheme.HEART}, 0.9)
                if amt < 0: board.shake(0.7))
        "fusion":
            var s7 := int(event["player"])
            var sources: Array = event.get("sources", [])
            var card_a := String(sources[0]["card_id"]) if sources.size() > 0 else ""
            var card_b := String(sources[1]["card_id"]) if sources.size() > 1 else ""
            _later(1.5, func() -> void:
                board.play("fusion", {"side": s7, "lane": int(event["lane"]),
                    "freed_lane": int(event["freed_lane"]), "name": String(event.get("name", "")),
                    "card_a": card_a, "card_b": card_b,
                    "colour": ArcanaTheme.color_for_element(String(engine.players[s7]["element"]))}, 1.4)
                board.shake(1.1))
        "commander_power":
            var s8 := int(event["player"])
            _later(0.5, func() -> void:
                board.play("float", {"at": board.commander_rect(s8).get_center(),
                    "text": String(event.get("name", "")), "colour": ArcanaTheme.GOLD}, 1.0))
        "fatigue":
            var s9 := int(event["player"])
            _later(0.3, func() -> void:
                board.play("float", {"at": board.commander_rect(s9).get_center(),
                    "text": "FATIGUE", "colour": ArcanaTheme.DANGER}, 0.9))
        "match_finished":
            _later(0.4, func() -> void: _refresh())
    _refresh()

# --- interaction ------------------------------------------------------------

func _on_slot_clicked(side: int, index: int, _slot: String) -> void:
    if engine.match_over or engine.current_player != HUMAN: return
    if mode == "power":
        var res := engine.use_power(HUMAN, side, index)
        _announce(res)
        _clear(); return
    if mode == "attack":
        if side == HUMAN:
            selected_lane = index
            mode = "attack"
            _refresh(); return
        if selected_lane >= 0:
            var res2 := engine.attack(HUMAN, selected_lane)
            _announce(res2)
            _clear(); return
    if mode == "card" and selected_card != "":
        var res3 := engine.play_card(HUMAN, selected_card, side, index)
        _announce(res3)
        if bool(res3.get("ok", false)): _clear()
        return
    # Nothing selected: clicking your own ready creature starts an attack.
    if side == HUMAN and engine.attack_block_reason(HUMAN, index) == "":
        mode = "attack"; selected_lane = index
        _refresh()

func _announce(result: Dictionary) -> void:
    if not bool(result.get("ok", false)):
        status.text = String(result.get("reason", ""))
        status.add_theme_color_override("font_color", ArcanaTheme.DANGER)
    else:
        status.text = ""

func _clear() -> void:
    mode = ""; selected_card = ""; selected_lane = -1
    _refresh()

func _select_card(card_id: String) -> void:
    if engine.current_player != HUMAN: return
    var blocked := engine.card_block_reason(HUMAN, card_id)
    selected_card = card_id
    mode = "card"
    selected_lane = -1
    if blocked != "":
        status.text = blocked
        status.add_theme_color_override("font_color", ArcanaTheme.DANGER)
    else:
        status.text = engine.placement_line(card_id)
        status.add_theme_color_override("font_color", ArcanaTheme.TEXT_DIM)
    _refresh()

# --- rebuild ----------------------------------------------------------------

func _refresh() -> void:
    if engine == null: return
    _refresh_hand()
    _refresh_highlights()
    _refresh_buttons()
    board.fusion_pairs = _fusion_lanes()
    var cmd := engine.commander(engine.current_player)
    if engine.match_over:
        banner.text = "%s wins — %s" % [String(engine.commander(engine.winner).get("name", "")),
            engine.win_reason]
    elif engine.current_player == HUMAN:
        banner.text = "Turn %d — your move" % engine.turn
    else:
        banner.text = "Turn %d — %s is thinking" % [engine.turn, String(cmd.get("name", ""))]
    board.queue_redraw()

func _fusion_lanes() -> Array:
    var out: Array = []
    for option in engine.available_fusions(HUMAN):
        if not out.has(int(option["a"])): out.append(int(option["a"]))
    return out

func _refresh_highlights() -> void:
    board.highlights.clear()
    if engine.match_over: return
    if mode == "card" and selected_card != "":
        for spot in engine.legal_targets(HUMAN, selected_card):
            if engine.lane_block_reason(HUMAN, selected_card, int(spot["side"]), int(spot["lane"])) == "":
                board.highlights["%d,%d" % [int(spot["side"]), int(spot["lane"])]] = "legal"
    elif mode == "attack" and selected_lane >= 0:
        board.highlights["%d,%d" % [RIVAL, selected_lane]] = "attack"
    elif mode == "power" and String(engine.power_target_kind(HUMAN)) == "enemy_lane":
        for i in range(MatchV3.LANES):
            if engine.lane(RIVAL, i)["creature"] != null:
                board.highlights["%d,%d" % [RIVAL, i]] = "attack"

func _refresh_buttons() -> void:
    for child in buttons.get_children():
        if child != status: child.queue_free()
    if engine.match_over: return
    for option in engine.available_fusions(HUMAN):
        var recipe: Dictionary = option["recipe"]
        var b := Button.new()
        b.text = "FUSE: %s" % String(recipe.get("name", ""))
        b.pressed.connect(func() -> void:
            _announce(engine.fuse(HUMAN, String(recipe.get("id", "")),
                int(option["a"]), int(option["b"])))
            _clear())
        buttons.add_child(b)
        break
    if engine.power_block_reason(HUMAN) == "":
        var cmd := engine.commander(HUMAN)
        var pb := Button.new()
        pb.text = String(cmd.get("power_name", "POWER")).to_upper()
        pb.pressed.connect(func() -> void:
            if String(engine.power_target_kind(HUMAN)) == "enemy_lane":
                mode = "power"; status.text = "Choose a target."
                _refresh()
            else:
                _announce(engine.use_power(HUMAN))
                _clear())
        buttons.add_child(pb)
    var eb := Button.new()
    eb.text = "END TURN"
    eb.pressed.connect(func() -> void:
        _announce(engine.end_turn(HUMAN))
        _clear())
    buttons.add_child(eb)

func _refresh_hand() -> void:
    var hand: Array = engine.players[HUMAN]["hand"]
    var signature := "|".join(PackedStringArray(hand)) + "#" + selected_card
    if signature == _hand_signature: return
    _hand_signature = signature
    for view in _cards: view.queue_free()
    _cards.clear()
    for card_id in hand:
        var cid := String(card_id)
        var view := CardV2.new()
        var card := db.card(cid)
        # CardV2 reads the V1/V2 shape; V3 stores one element, not a list.
        var shaped := card.duplicate()
        shaped["elements"] = [String(card.get("element", ""))]
        # "GROVE CREATURE", coloured like the Grove lane: the single strongest
        # readability cue on the card, and the reason a player can match hand to
        # board at a glance.
        var kind := String(card.get("type", ""))
        var needs := String(card.get("play_on", ""))
        var ribbon_label := kind.capitalize()
        if needs != "":
            ribbon_label = "%s %s" % [needs.capitalize(), kind.capitalize()]
            view.ribbon_override = BoardV3.LANE_COLOUR.get(needs, Color(0.4, 0.4, 0.4))
        elif kind == "landscape":
            var terrain := String(card.get("terrain", ""))
            view.ribbon_override = BoardV3.LANE_COLOUR.get(terrain, Color(0.4, 0.4, 0.4))
        view.setup(shaped, ribbon_label,
            engine.placement_line(cid), engine.card_block_reason(HUMAN, cid), art)
        view.selected = cid == selected_card
        view.pivot_offset = Vector2(CardV2.SIZE.x * 0.5, CardV2.SIZE.y)
        view.scale = Vector2.ONE * REST_SCALE
        view.card_clicked.connect(_select_card)
        view.card_hovered.connect(func(_c: String) -> void: pass)
        hand_row.add_child(view)
        _cards.append(view)
    _layout_hand()

func _layout_hand() -> void:
    var n := _cards.size()
    if n == 0: return
    var card_w: float = CardV2.SIZE.x * REST_SCALE
    var spread: float = minf(card_w + 8.0, maxf(38.0, (hand_row.size.x - card_w) / maxf(1, n - 1)))
    var total: float = card_w + spread * (n - 1)
    var start: float = (hand_row.size.x - total) * 0.5
    for i in range(n):
        var view: CardV2 = _cards[i]
        view.position = Vector2(start + spread * i - (CardV2.SIZE.x - card_w) * 0.5,
            HAND_H - CardV2.SIZE.y - 16.0)
        view.z_index = i
