# Pocket Arcana — Pixel Art Bible v2

## Core visual promise
Pocket Arcana should look like a tiny magical storybook world that physically grows out of cards. It is not a flat digital TCG and it is not a generic AI-fantasy card game.

The visual hierarchy is:
1. living board world
2. readable creatures/landmarks
3. clear card information
4. large, satisfying magical effects
5. decorative detail

If an asset is pretty but hurts board readability, reject it.

## Master style
- 2D pixel art only for the playable world.
- Top-down / slight storybook perspective, roughly 3/4 overhead. Never side-view battle sprites.
- Chunky silhouettes, cute proportions, clean clusters, minimal noisy single pixels.
- Soft fantasy shapes with strong readable outlines.
- One consistent light direction: upper-left.
- Creatures use 1px dark colored outlines, not pure black except in deepest shadow.
- Background/terrain uses less contrast than creatures.
- Avoid photorealism, painterly gradients, anime rendering, faux-3D, smooth vector art, or high-detail AI illustration pasted into the board.
- Cute and magical beats grim. Death is whimsical-spooky, never gore.

## Pixel scale
Design source assets around these footprints:
- small board creature: 48x48 source canvas
- normal board creature: 64x64 source canvas
- large creature / dragon: 96x96 source canvas
- landmark: 64x64 or 96x96 source canvas depending on silhouette
- terrain tile: 96x64 source canvas for the current board aspect, with safe center content inside 82x52
- Commander board avatar: 64x64
- Commander portrait: 256x256 pixel-art portrait, rendered nearest-neighbor in UI
- card illustration crop: 256x160 pixel-art scene/portrait
- element icon: 24x24 and 48x48 variants
- status icon: 16x16

No generated asset should be scaled with smoothing. Import with nearest-neighbor filtering.

## Animation budget
Do not over-animate every asset.

Small/normal creatures:
- idle: 4 frames
- move: 4 frames where useful; otherwise Godot tween + bob
- hit: Godot squash/flash, no unique sheet required
- death/vanish: Godot particles + 1-2 frame dissolve optional

Dragons / legendary creatures:
- idle: 4-6 frames
- summon: 4-8 frames if generator quality is good
- attack: 4-6 frames only for vertical-slice showcase pieces

Landmarks:
- mostly static sprite
- 2-4 frame ambient animation only when it meaningfully sells the fantasy

Spells:
- do NOT generate giant sprite sheets per spell
- use reusable Godot particles, shaders, trails, screen flash, camera punch, tile overlays and elemental VFX

## Board rule
The board itself must become the artwork.

A finished mid-match screenshot should visually show:
- terrain ownership
- terrain element/state
- actual creature silhouettes
- landmarks standing on tiles
- Sanctuaries as real magical places
- visible environmental reactions

Never fall back to a creature being only a text chip once production art exists.

## Card rule
Cards remain readable at 140x164 in the current UI.

Production card layout:
- top element ribbon + cost gem
- name
- central art window occupying roughly 45% of card height
- short rules text under art
- power/health or landmark Presence at bottom
- rarity indicator is subtle; rarity must not overpower the element identity

Card art and board sprite may depict the same subject differently:
- board sprite prioritizes silhouette/readability
- card art may show a more expressive scene

Do not use a full AI illustration as the board sprite.

## Element shape language
Color is never the only signal.

### Frost
- pale cyan / blue-white
- hexagonal crystals, snowcaps, soft icicles
- idle particles: tiny drifting snow motes
- terrain: rounded snow banks + crystal edges

### Lightning
- warm electric yellow with violet/blue shadow accents
- zigzags, coils, forks, copper shapes
- idle particles: short one-pixel arcs
- terrain: charged grass/stone with glowing cracks

### Life
- spring green with warm cream/petal accents
- leaves, sprouts, berries, flowers, antlers, mushrooms
- idle particles: floating pollen/firefly motes
- terrain: lush grove, flowers, roots and tiny grass motion

### Fire
- orange-red with hot cream/yellow cores and charcoal accents
- flames, embers, triangular aggressive silhouettes
- idle particles: upward embers and heat flicker
- terrain: cinder soil, scorched grass, glowing cracks

### Water
- blue / aqua / moonlit cyan
- droplets, waves, curls, bubbles
- idle particles: bubbles/sparkles
- terrain: shallow magical spring/ripple shapes

### Earth
- clay, ochre, mossy brown and stone grey
- blocks, arches, layered rock, chunky square silhouettes
- terrain: stonefield, pebbles, low raised ridges

### Wind
- pale mint / cloud-white / sky blue
- ribbons, spirals, feathers, kites
- terrain: skygrass bent in a common wind direction

### Death
- lavender / dusty violet / moon-grey with warm lantern gold
- lantern wisps, friendly bones, crooked gravegarden plants
- ghosts are rounded/cute, not corpses
- terrain: gravegarden with soft fog and tiny lantern lights

## Dual-element reactions
A reaction terrain must visibly read as both parents. Do not merely average colors.

Examples:
- Life + Fire / Ashbloom: blackened soil + fresh luminous flowers + ember petals
- Fire + Water / Steamfield: wet dark ground + steam vents + orange reflection
- Frost + Lightning / Aurora Ice: blue crystal ice + yellow/violet trapped arcs
- Life + Death / Gravegarden: green growth + lavender wisps + lantern flowers
- Earth + Wind / Floating Island: broken stone rim + roots + wind ribbons/cloud shadow

## Commander style
Commanders are recognizable mascots, not generic wizards.

Requirements:
- strong silhouette at 64x64
- portrait has one signature prop
- simple face readable at small size
- element identity visible without reading text
- no overly ornate armor/details that collapse at pixel scale

Vertical slice anchors:
- Mossy Mae: cheerful grove caretaker, big leaf hood/hat, wooden staff with sprout, mossy satchel
- Poppy Cinder: mischievous fire mage/tinkerer, ember-red hair or scarf, small forge tool, coal-black boots, bright flame companion

## Sanctuaries
Each side owns a Sanctuary tile. It should feel like the player's magical home/base.

Vertical slice:
- Life Sanctuary: tiny living shrine built into roots, heart-shaped leaves, warm lantern
- Fire Sanctuary: miniature forge shrine, chimney ember glow, hanging metal charm

Sanctuary art must leave room for heart UI and attack-target highlight overlays.

## AI generation rules
AI generators are production tools, not art directors.

Every generation prompt must specify:
- Pocket Arcana pixel-art style
- top-down / slight 3/4 overhead board perspective when generating world sprites
- exact canvas size
- transparent background for sprites/objects
- one upper-left light source
- chunky readable silhouette
- limited palette
- no text
- no frame/border unless generating UI
- no anti-aliasing
- no smooth vector edges
- no 3D render
- no painterly texture

Use a locked reference image/seed/style reference after the first approved Life and Fire masters are chosen.

Do not change style reference between cards because a different generation looks "cooler." Consistency beats individual prettiness.

## Rejection checklist
Reject and regenerate if any are true:
- perspective does not match the board
- outline weight changes dramatically
- subject has tiny noisy detail that disappears at game scale
- lighting comes from a different direction
- palette is muddy or outside element language
- creature becomes unreadable at 64px
- image contains fake text/glyphs
- background is baked into an object sprite
- asset looks like a different game
- generator produces smooth/non-pixel edges

## Vertical-slice rule
Do not generate the full 240-card set yet.

First production-art milestone is Life vs Fire only:
- 2 Commanders
- 16 Life/Fire creature board sprites used in the starter lists
- 2 Life/Fire landmarks
- 8 Life/Fire spell card-art scenes/effect motifs
- Life Grove terrain
- Fire Cinder terrain
- Ashbloom reaction terrain
- 2 Sanctuaries
- Life and Fire card frames/ribbons/icons
- reusable Life/Fire VFX

Once screenshots of a complete Life-vs-Fire match look coherent, the style is locked and may be expanded to the other six elements.

## Source control
Generated source/export assets belong under:
- `assets/art/board/creatures/<element>/`
- `assets/art/board/landmarks/<element>/`
- `assets/art/board/terrain/`
- `assets/art/commanders/`
- `assets/art/cards/<element>/`
- `assets/art/ui/`
- `assets/art/fx/`

Keep AI prompts associated with card IDs. Never overwrite an approved master without a commit that explicitly says the style/master changed.
