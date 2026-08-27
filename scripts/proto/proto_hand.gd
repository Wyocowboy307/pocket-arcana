class_name ProtoHand
extends Control
## The player's hand: cards fanned along the bottom, physical and precious.
##
## Cards rise, straighten and enlarge on hover, throw a soft shadow, and keep
## their gold glow while selected. The card texture itself is the information —
## no panel ever covers it.

signal card_clicked(index: int)
signal card_hovered(index: int)

const CARD_W := 176.0
const CARD_H := 246.0
const HOVER_SCALE := 1.26
const REST_PEEK := 152.0              # how much of a resting card is on screen
const FAN_ANGLE := 4.2                # degrees per card from centre
const FAN_DROP := 14.0                # arc: edge cards sit lower

var cards: Array = []                 # {id, tex, cost, playable, node}
var hover_index := -1
var selected_index := -1

func set_cards(rows: Array) -> void:
    for c in cards:
        (c["node"] as Control).queue_free()
    cards.clear()
    hover_index = -1
    selected_index = -1
    for row in rows:
        var holder := Control.new()
        holder.custom_minimum_size = Vector2(CARD_W, CARD_H)
        holder.size = Vector2(CARD_W, CARD_H)
        holder.pivot_offset = Vector2(CARD_W * 0.5, CARD_H)
        holder.mouse_filter = Control.MOUSE_FILTER_STOP

        var shadow := Panel.new()
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.09, 0.07, 0.12, 0.92)
        sb.set_corner_radius_all(10)
        sb.shadow_color = Color(0, 0, 0, 0.55)
        sb.shadow_size = 18
        sb.shadow_offset = Vector2(0, 10)
        shadow.add_theme_stylebox_override("panel", sb)
        shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
        shadow.offset_left = 4; shadow.offset_top = 4
        shadow.offset_right = -4; shadow.offset_bottom = -4
        shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
        holder.add_child(shadow)

        var glow := Panel.new()                     # selection halo
        var gb := StyleBoxFlat.new()
        gb.bg_color = Color(0, 0, 0, 0)
        gb.set_corner_radius_all(12)
        gb.border_color = Color(0.95, 0.8, 0.35, 0.95)
        gb.set_border_width_all(3)
        gb.shadow_color = Color(0.95, 0.75, 0.3, 0.5)
        gb.shadow_size = 14
        glow.add_theme_stylebox_override("panel", gb)
        glow.set_anchors_preset(Control.PRESET_FULL_RECT)
        glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
        glow.visible = false
        holder.add_child(glow)

        var face := TextureRect.new()
        face.texture = row["tex"]
        face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        face.stretch_mode = TextureRect.STRETCH_SCALE
        face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        face.set_anchors_preset(Control.PRESET_FULL_RECT)
        face.mouse_filter = Control.MOUSE_FILTER_IGNORE
        holder.add_child(face)

        var idx := cards.size()
        holder.mouse_entered.connect(func() -> void: _set_hover(idx))
        holder.mouse_exited.connect(func() -> void:
            if hover_index == idx: _set_hover(-1))
        holder.gui_input.connect(func(event: InputEvent) -> void:
            if event is InputEventMouseButton and event.pressed \
                    and event.button_index == MOUSE_BUTTON_LEFT:
                card_clicked.emit(idx))
        add_child(holder)
        cards.append({"id": row["id"], "tex": row["tex"], "cost": row["cost"],
            "playable": row.get("playable", true), "node": holder,
            "face": face, "glow": glow})
    _layout(false)

func set_playable(index: int, on: bool) -> void:
    if index < 0 or index >= cards.size(): return
    cards[index]["playable"] = on
    (cards[index]["face"] as TextureRect).modulate = \
        Color(1, 1, 1) if on else Color(0.62, 0.6, 0.68)

func set_selected(index: int) -> void:
    selected_index = index
    for i in range(cards.size()):
        (cards[i]["glow"] as Panel).visible = i == index
    _layout(true)

func remove_card(index: int) -> void:
    if index < 0 or index >= cards.size(): return
    (cards[index]["node"] as Control).queue_free()
    cards.remove_at(index)
    hover_index = -1
    selected_index = -1
    _layout(true)

## The harness uses this to stage a hover for a capture.
func simulate_hover(index: int) -> void:
    _set_hover(index)

func _set_hover(index: int) -> void:
    hover_index = index
    if index >= 0: card_hovered.emit(index)
    _layout(true)

func _layout(animate: bool) -> void:
    var n := cards.size()
    if n == 0: return
    var centre := (float(n) - 1.0) * 0.5
    var spread := minf(150.0, (size.x - CARD_W - 40.0) / maxf(1.0, float(n) - 1.0))
    for i in range(n):
        var holder: Control = cards[i]["node"]
        var off := float(i) - centre
        var hovered := i == hover_index
        var selected := i == selected_index
        # Cards peek at rest and rise fully into view on hover. At full height
        # they covered the player's own lane, which is the one thing the hand
        # must never hide.
        var target_pos := Vector2(
            size.x * 0.5 - CARD_W * 0.5 + off * spread,
            size.y - REST_PEEK + absf(off) * FAN_DROP)
        var target_rot := deg_to_rad(off * FAN_ANGLE)
        var target_scale := Vector2.ONE
        if hovered or selected:
            target_pos.y -= 116.0
            target_rot = 0.0
            target_scale = Vector2.ONE * HOVER_SCALE
        holder.z_index = 30 if (hovered or selected) else i
        if animate:
            var tw := holder.create_tween().set_parallel(true) \
                .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
            tw.tween_property(holder, "position", target_pos, 0.16)
            tw.tween_property(holder, "rotation", target_rot, 0.16)
            tw.tween_property(holder, "scale", target_scale, 0.16)
        else:
            holder.position = target_pos
            holder.rotation = target_rot
            holder.scale = target_scale
