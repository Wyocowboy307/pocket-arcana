# Pocket Arcana — Art Production Pipeline v1

## Goal
Turn the tested Life-vs-Fire vertical slice into a coherent pixel-art game without destabilizing the rules or wasting AI-generation budget.

## Do this in phases

### Phase A — lock the master look
Before batch generation, create only these eight reference assets:
1. Mossy Mae board avatar
2. Poppy Cinder board avatar
3. Sproutling
4. Cinder Pup
5. Garden Dragon
6. Blazewing Drake
7. Grove terrain
8. Cinder terrain

Put them in the exact paths from `data/vertical_slice_art_manifest.json`.

Run the real game and capture at least:
- empty opening board
- Life creature on Grove
- Fire creature on Cinder
- one dragon on each side

Do not proceed if they look like different games.

### Phase B — Life/Fire living board
Generate/integrate:
- all Life and Fire board creature sprites in the manifest
- Herbalist Hut and Blacksmith Nook
- neutral, Grove, Cinder and Ashbloom terrain
- two Sanctuary tiles
- Mossy Mae and Poppy Cinder portraits/avatars

At this stage creature cards may use the same approved board sprite in their card-art window. Do not generate separate fancy card illustrations yet unless the workflow is extremely cheap.

Acceptance test:
A midgame screenshot must be understandable with creature/terrain names temporarily hidden. The player should still visually distinguish Life from Fire and recognize different creatures by silhouette.

### Phase C — card presentation
Integrate:
- Life and Fire card frames/ribbons
- element icons
- Aether/Heart/Seal/Wonder icons
- spell art for the eight Life/Fire spell cards

Card readability remains more important than art size. Current card controls are 140x164; if the central art window makes rules unreadable, adjust the hand layout rather than shrinking rules below a comfortable size.

### Phase D — game juice
Build reusable Godot effects, not bespoke sprite sheets:
- Life summon
- Fire summon
- healing
- burning
- Ashbloom recipe reveal
- Heart strike
- Chapter/Seal win

Effects should listen to committed simulation events. Never move game logic into animation code.

### Phase E — screenshot review
Use the existing screenshot scenarios and add an `art_review` scenario if needed.
Capture:
- opening board
- creature selected
- Life-heavy midgame
- Fire-heavy midgame
- Ashbloom reaction
- Heart strike
- Chapter overlay
- match end

Review screenshots at 100% scale and at a small thumbnail size.

If a board is only understandable by reading labels, the art pass is not done.

## Generator workflow
Any AI pixel generator may be used, but it must obey `docs/ART_BIBLE.md`.

Recommended sequence per asset:
1. read manifest description
2. include locked style reference(s)
3. generate 3-6 candidates maximum
4. choose best silhouette, not most detailed image
5. clean transparent edges if required
6. save exact asset path
7. import nearest-neighbor
8. view in the actual game
9. reject if it fails at real board scale

Do not spend 30 generations perfecting one common creature while the rest of the slice is graybox.

## Asset loader architecture
Keep production art optional and data-driven.

Recommended helper:
`scripts/ui/art_registry.gd`

Responsibilities:
- resolve a card ID to board sprite if one exists
- resolve terrain ID to texture
- resolve Commander ID to portrait/avatar
- return null cleanly when an asset is missing

The current procedural drawing remains the fallback until the matching production asset exists. This lets art land incrementally without breaking tests.

Suggested paths:
- creature: `res://assets/art/board/creatures/<element>/<card_id>.png`
- landmark: `res://assets/art/board/landmarks/<element>/<card_id>.png`
- card spell art: `res://assets/art/cards/<element>/<card_id>.png`
- terrain: `res://assets/art/board/terrain/<terrain_id>.png`
- Commander: paths specified in the manifest

## Board integration
`BoardView` currently renders terrain as color panels and creatures as text chips. Replace visually, not logically.

Terrain:
- draw the texture inside tile rect
- tint only lightly for ownership/state feedback
- preserve current legality/selection overlays on top

Creatures:
- center sprite in tile
- maintain a small unobtrusive Power/Health plate
- damage bar remains readable
- selected/attack/move highlights remain outside or under the sprite

Landmarks:
- render behind creature sprite so the two can share a tile
- keep landmark name available on hover/detail panel rather than always occupying the board

Sanctuary:
- use Sanctuary art as tile base
- Heart number remains a UI overlay
- strike target overlay must remain obvious

## Card integration
`CardView` currently contains no art window. Add one between the card name/type and rules text.

For vertical-slice creature/landmark cards:
- use board sprite enlarged nearest-neighbor over a simple element-themed vignette

For spells:
- use the dedicated spell image from the manifest

Do not let art cover rules, cost, elements or stats.

## Animation integration
Use Tween/AnimationPlayer/GPUParticles2D or CPUParticles2D where appropriate.

A satisfying standard card-play beat:
1. chosen card lifts 8-12 px
2. legal destination pulses
3. card snaps/flies toward destination
4. elemental flash at destination
5. terrain/creature/landmark art appears
6. impact flourish / short board punch
7. state settles quickly so the next decision is readable

Target total time for a common play: ~0.45-0.8 seconds.
Legendary summon: up to ~1.5 seconds.
Never make common actions feel slow because every play has a cinematic.

## Expansion gate
Do NOT generate Frost, Lightning, Water, Earth, Wind or Death production art until all are true:
- Life/Fire screenshots look coherent
- all current UI playthrough tests still pass
- no art asset changes legality/hitboxes
- common plays remain fast
- card text remains readable
- user approves the master look

Once locked, reuse the same reference set/pixel rules for the other six elements.
