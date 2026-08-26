# Pocket Arcana Project Status — 2026-08-26

## Completed in scaffold
- [x] Standalone project boundary from Pixel Ranch
- [x] Godot 4.7.2 project file and main scene
- [x] 7×5 board model
- [x] Chapter / Pass / Seal / Heart / Wonder rules engine
- [x] Shape + elemental Attunement model
- [x] Creature summon/move/combat graybox
- [x] Landmark persistence layer
- [x] Generic effect resolver
- [x] Two-state recipe resolver
- [x] 240-card content library
- [x] 32-card vertical-slice flag set
- [x] 24 Commanders
- [x] 8 legal 40-card starter decks
- [x] 28 elemental pair recipes
- [x] 12 tokens
- [x] 24 deck archetype blueprints
- [x] 24 named AI opponent blueprints
- [x] 8 campaign regions / 40 encounter blueprints
- [x] Commander mastery / non-pay-to-win progression spec
- [x] 240 AI art prompts with common style lock
- [x] beginner glossary + tutorial steps
- [x] Python content validation and audits
- [x] headless Godot smoke-test scene/script

## Verified on a real Godot 4.7.2 run (2026-08-26)
- [x] parser/runtime cleanup in Godot 4.7.2
- [x] AI-vs-AI headless smoke test finishes
- [x] manual graybox playthrough (full match completes in the UI)
- [x] direct Heart attack UX with Sanctuary Ward
- [x] drawn board view, card views, event flourishes
- [x] Pass preview with Realm Score breakdown
- [x] Chapter transition and match-end overlays
- [x] "How to play" keyword popup
- [x] Life and Fire play as genuinely different decks

## Still open
- [ ] full push/movement spell targeting (`move_unit`)
- [ ] Mossy Mae and Poppy Cinder still share one passive
- [ ] tutorial_steps.json is not wired into the UI
- [ ] pixel art assets / audio hooks
- [ ] collection browser and deckbuilder (Milestone 4)

## Current validation
- `python3 tools_validate_content.py` — 0 errors
- `python3 tools_content_audit.py` — structural checks pass
- `./tools_check_scripts.sh` — all GDScript parses under Godot 4.7.2
- `Godot --headless --scene res://scenes/dev/tests.tscn` — 60 checks pass
- `./run_smoke_test.sh` — AI-vs-AI match completes
- `Godot --scene res://scenes/dev/balance.tscn -- --matches=150` — Life 58.7% / Fire 41.3%
