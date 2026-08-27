# Arcana Visual Prototype — 2.5D tabletop

A separate scene built to answer one question:

> Does this give the feeling of sitting down with an amazing magical card game
> where the cards bring a miniature world to life?

It is **not** the game. V1, V2 and V3 are untouched and still launch. Nothing has
been migrated into this scene, and nothing should be until the direction is
approved.

## Run it

    ./PLAY ARCANA PROTOTYPE.command

or `Godot --path . --scene res://scenes/proto/arcana_visual_prototype.tscn`

## What is in it

| Piece | File |
| --- | --- |
| Scene assembly, camera, lighting, choreography | `scripts/proto/proto_main.gd` |
| Miniature worlds (Grove, Cinder) | `scripts/proto/proto_diorama.gd` |
| Faceted mesh builders | `scripts/proto/proto_meshlib.gd` |
| Creature actors | `scripts/proto/proto_creature.gd` |
| One-shot effects | `scripts/proto/proto_fx.gd` |
| Fanned hand | `scripts/proto/proto_hand.gd` |
| Card faces, creature cutouts, particles | `tools/build_proto_assets.py` |
| Concept generation | `tools/generate_proto_creatures.py` |

## The 60 seconds

See the tabletop → hover a card → play Sprigget onto the Grove → the card flies
in, tucks into the landscape as a plaque, and the creature rises out of a shock
ring → End Turn → Cinderbelly appears on the Cinder → click Sprigget, click
Cinderbelly → Sprigget leaps the table, hits, returns → cast a spell.

## Deliberate technique choices

- **Everything is faceted, flat-shaded, low-poly, built in code.** No modelling
  package, no imported meshes; the dioramas are deterministic from a seed, so a
  world is stable shot to shot and re-tunable by editing numbers.
- **Creatures are 2.5D billboard cutouts** of illustrated art. This is a
  prototype choice, not a production commitment — all motion goes through
  `ProtoCreature.set_visual`, so the same choreography drives a 3D model, a
  skeletal rig or a sprite if one of those wins later.
- **Card faces are rendered offline** at 512x717 with real type, then used both
  as UI textures and as 3D card meshes. The same image is the hand card, the
  flying card and the plaque.

## Three bugs worth remembering

- **Vertex colours are LINEAR in Godot unless you say otherwise.** Every sRGB hex
  in the mesh library was being over-brightened, which is why saturated greens
  kept rendering as pale mint. `vertex_color_is_srgb = true`.
- **A billboarded particle ignores its own scale** unless
  `billboard_keep_scale = true` — every mote drew at the full quad size, so
  fireflies rendered as metre-wide glowing diamonds.
- **`look_at` aims −Z at the target**, so a quad facing +Z shows its back. The
  summoned card flew in face-down until the front mesh was turned round.

## Known gaps

- The rival is a three-step script, not an AI.
- No fusion, no deckbuilding, no second lane, no other elements — all
  deliberately out of scope.
- Creature "animation" is squash, arc and tint driven by the choreography; there
  are no authored frame sets yet.
