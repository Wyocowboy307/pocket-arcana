class_name HandView
extends Control
## The hand as a card-game hand: an overlapping row along the bottom that lifts
## and enlarges the card under the cursor. Cards grow upward over the world,
## so this control must never clip its children.

signal card_clicked(card_id: String)
signal card_hovered(card_id: String)
signal card_unhovered

const CARD := Vector2(132, 172)
const HOVER_SCALE := 1.42
const MAX_SPREAD := 126.0

var cards: Array[CardView] = []
var hovered := -1

func _ready() -> void:
    clip_contents = false
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func rebuild(entries: Array) -> void:
    for c in cards: c.queue_free()
    cards.clear()
    hovered = -1
    for entry in entries:
        var view := CardView.new()
        view.setup(entry["card"], String(entry["reason"]), entry["art"])
        view.count = int(entry["count"])
        view.selected = bool(entry["selected"])
        view.custom_minimum_size = CARD
        view.size = CARD
        view.pivot_offset = Vector2(CARD.x * 0.5, CARD.y)
        view.card_clicked.connect(func(cid: String) -> void: card_clicked.emit(cid))
        view.mouse_entered.connect(_on_enter.bind(view))
        view.mouse_exited.connect(_on_exit.bind(view))
        add_child(view)
        cards.append(view)
    _layout()

func _on_enter(view: CardView) -> void:
    hovered = cards.find(view)
    card_hovered.emit(view.card_id)
    _layout()

func _on_exit(view: CardView) -> void:
    if cards.find(view) == hovered:
        hovered = -1
        card_unhovered.emit()
        _layout()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED: _layout()

func _layout() -> void:
    var n := cards.size()
    if n == 0: return
    var spread: float = min(MAX_SPREAD, max(46.0, (size.x - CARD.x - 40.0) / max(1, n - 1)))
    var total: float = CARD.x + spread * (n - 1)
    var start: float = (size.x - total) * 0.5
    for i in range(n):
        var view: CardView = cards[i]
        var lifted := i == hovered
        # A hovered card rises out of the row and gets big enough to read.
        view.scale = Vector2.ONE * (HOVER_SCALE if lifted else 1.0)
        view.z_index = 20 if lifted else i
        # Bottom edge stays inside the strip; scaling grows the card upward
        # because the pivot is at its bottom centre.
        var y: float = size.y - CARD.y - (16.0 if lifted else 8.0)
        view.position = Vector2(start + spread * i, y)
        view.hovered = lifted
        # Dim the rest so the raised card is clearly the one being read.
        view.modulate = Color(1, 1, 1, 1.0) if (lifted or hovered < 0) else Color(0.72, 0.75, 0.82, 1.0)
