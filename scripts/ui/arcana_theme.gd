class_name ArcanaTheme
extends RefCounted
## Shared palette and element language for the Pocket Arcana UI.
##
## Accessibility rule (ONBOARDING_AND_ACCESSIBILITY): an element is never
## communicated by colour alone — always colour + icon + word.

const BG := Color("#141821")
const PANEL := Color("#1e2430")
const PANEL_EDGE := Color("#333c4e")
const TILE_EMPTY := Color("#262d3a")
const TEXT := Color("#e9edf5")
const TEXT_DIM := Color("#95a1b8")
const TEXT_FAINT := Color("#6b768c")
const GOLD := Color("#f2c86b")
const HEART := Color("#e46a86")
const WONDER := Color("#7fc6ff")
const AETHER := Color("#a68ce0")
const SEAL := Color("#f2c86b")
const YOU := Color("#5fd39b")
const RIVAL := Color("#e8795f")
const LEGAL := Color("#f2c86b")
const MOVE := Color("#5fd39b")
const ATTACK := Color("#e8795f")
const DANGER := Color("#ff8a6b")

static var element_color: Dictionary = {}
static var element_icon: Dictionary = {}
static var element_name: Dictionary = {}
static var element_state: Dictionary = {}
static var state_element: Dictionary = {}
static var terrain_elements: Dictionary = {}

## Build the element language from data/ so the UI never hardcodes content.
static func configure(db: ContentDatabase) -> void:
    element_color.clear(); element_icon.clear(); element_name.clear()
    element_state.clear(); state_element.clear()
    for el_id in db.elements:
        var el: Dictionary = db.elements[el_id]
        element_color[el_id] = Color(String(el.get("color", "#ffffff")))
        element_icon[el_id] = String(el.get("emoji", "*"))
        element_name[el_id] = String(el.get("name", el_id))
        element_state[el_id] = String(el.get("state", ""))
        state_element[String(el.get("state", ""))] = el_id
    terrain_elements = db.terrain_attunement.duplicate(true)

static func color_for_element(el: String) -> Color:
    return element_color.get(el, TEXT_DIM)

static func color_for_state(state: String) -> Color:
    return color_for_element(String(state_element.get(state, "")))

## Terrain takes the colour of its element, or a blend for discovered recipe terrain.
static func color_for_terrain(terrain: String) -> Color:
    if terrain == "" or terrain == "neutral": return TILE_EMPTY
    var els: Array = terrain_elements.get(terrain, [])
    if els.is_empty(): return TILE_EMPTY
    var c: Color = color_for_element(String(els[0]))
    for i in range(1, els.size()):
        c = c.lerp(color_for_element(String(els[i])), 0.5)
    return c

static func label_for_terrain(terrain: String) -> String:
    if terrain == "" or terrain == "neutral": return "Open ground"
    return terrain.replace("_", " ").capitalize()

static func label_for_state(state: String) -> String:
    return state.capitalize()

static func icon_for_state(state: String) -> String:
    return String(element_icon.get(String(state_element.get(state, "")), "*"))

static func owner_color(owner: int) -> Color:
    if owner == 0: return YOU
    if owner == 1: return RIVAL
    return PANEL_EDGE

static func panel_box(fill: Color = PANEL, edge: Color = PANEL_EDGE, radius: int = 8, width: int = 1) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = fill
    sb.border_color = edge
    sb.set_border_width_all(width)
    sb.set_corner_radius_all(radius)
    return sb

static func font() -> Font:
    return ThemeDB.fallback_font

## Trim a string to fit a pixel width so nothing ever overflows its tile.
static func fit(text: String, size: int, max_width: float) -> String:
    var f := font()
    if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_width:
        return text
    var out := text
    while out.length() > 1 and f.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
        out = out.substr(0, out.length() - 1)
    return out + "…"
