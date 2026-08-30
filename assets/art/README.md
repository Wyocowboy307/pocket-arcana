# Production art

Paths and sizes are authoritative in `data/vertical_slice_art_manifest.json`.
Generation prompts are built from that manifest plus `docs/ART_BIBLE.md` by
`tools_build_art_prompts.py`, which writes `data/art_prompts_vertical_slice.json`.

The 2026-08-30 art pass added three deterministic kits (see the ART_BIBLE
addendum for the visual language they implement):

    python3 tools/build_land_kit.py    # board/table, board/land, props, ui tokens
    python3 tools/build_card_kit.py    # ui hand frames, card backs, buttons, tray, parchment
    python3 tools/generate_hero_art.py # SpriteCook hero pieces (candidates + promote)

Never hand-edit the prompt file — change the manifest or the style rules in the
builder and regenerate, so the style lock cannot drift between assets.

    python3 tools_build_art_prompts.py    # rebuild prompts
    python3 tools_art_status.py           # what exists, what is still missing
    python3 tools_art_status.py --phase A # just the master references

Missing art is not an error. `scripts/ui/art_registry.gd` returns null for any
asset that does not exist yet and the views fall back to procedural drawing, so
assets can land one file at a time.

Textures import lossless with no mipmaps and no alpha-border fixing (see
`[importer_defaults]` in `project.godot`), and the project renders canvas
textures nearest-neighbour.
