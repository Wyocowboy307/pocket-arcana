# Pocket Arcana — Claude Code Instructions

This repository is Pocket Arcana. **It is completely separate from Pixel Ranch and Pixel Skies. Never read, edit, import, move, or commit anything in either other repository.**

When Thomas says “go build,” implement. Do not reopen broad product discovery.

## CURRENT PRODUCT PRIORITY — V3 ELEMENTAL LANE BATTLER

V3 is the live milestone. It is a **tabletop lane game**, not an open
battlefield: four lanes a side, each holding a Landscape, a Creature and a
Support, with the Landscape both gating what may be played there and paying for
it. Read `docs/V3_LANE_BATTLER.md` first.

- engine `scripts/v3/match_v3.gd`, content `data/v3_*.json`
  (authored by `tools/build_v3_content.py`)
- board `scripts/ui/v3/board_v3.gd`, screen `scripts/ui/v3/main_v3.gd`
- launch `PLAY POCKET ARCANA V3.command` or `scenes/v3/main_v3.tscn`
- checks: `tests_v3.tscn` (rules) and `selftest_v3.tscn` (AI-vs-AI, both seatings)

V2 stays in the repo with its own launcher until V3 proves itself, the same way
V1 was kept through V2. The V2 art pipeline — `tools/pixelart/`,
`tools/generate_hero_art.py` and the whole locked palette — carries straight
over, because V3 reuses the same card IDs.

## SUPERSEDED — V2 CLARITY PROTOTYPE

Thomas does **not** consider the current shared 7×5 movement version clear enough. Do not keep polishing the old rules merely because they already work.

The next gameplay prototype is defined by:
1. `docs/V2_CLARITY_REDESIGN.md`
2. `docs/V2_CARD_LANGUAGE.md`
3. `docs/V2_ANIMATION_CHOREOGRAPHY.md`
4. `docs/V2_TUTORIAL.md`
5. `docs/V2_PROTOTYPE_TASKS.md`

These V2 files supersede the old gameplay assumptions in `MATCH_RULES_V1.md` **for the current prototype milestone**. Keep V1 as historical/reference material until V2 proves itself; do not delete old systems blindly before the replacement is playable.

## Existing reference read order

After the V2 files, read:
- `docs/DESIGN_DECISIONS.md`
- `docs/ART_BIBLE.md`
- `docs/ART_PRODUCTION_PIPELINE.md`
- `docs/IMPLEMENTATION_NOTES.md`
- exact code/data required for the milestone

## First commands

- `python3 tools_validate_content.py`
- `python3 tools_content_audit.py`
- `./tools_verify.sh`
- boot the real Godot project and fix parser/runtime errors before feature work

## Product sentence

A 2D pixel-art magical card battler where **Land visibly builds your realm, creatures clearly belong to that land, cards physically come alive when played, and attacks are readable without needing a rulebook.**

## V2 design intent

The current prototype is too hard to understand because it mixes shared-grid movement, shaping, attunement, Chapters, Seals, Wonder, Heart attacks and card placement at the same time.

V2 deliberately tests a simpler core:
- split battlefield: your realm vs rival realm;
- four clear lanes/land plots per player;
- creatures do not wander into enemy territory;
- attacks animate across a lane and return;
- Land is a real visible card/system, not an abstract toolbar action;
- one creature + one Place per land keeps capacity readable;
- cards show type, element, cost and `PLAY ON` rule directly on the card;
- unified Aether comes from the Sanctuary + built lands;
- first prototype win condition is **reduce the rival Heart to 0**;
- Chapters/Seals/Wonder are disabled in the V2 test until the basic game is fun and obvious;
- creature fusion/combination is a first-class spectacle mechanic, not hidden trivia.

Do not add more elements before Life vs Fire is understandable. There are already eight planned elements; the current need is stronger identity, not more colors.

## Engineering rules

- Deterministic simulation.
- Generic effect vocabulary first.
- UI asks simulation for legal actions and exact failure reasons.
- Animation communicates committed state; it never decides rules.
- Data drives card role, element, land requirement, attack style and fusion tags.
- Preserve existing content where it fits, but do not force old mechanics into V2 if they harm clarity.
- Higher AI difficulty means better decisions, not hidden resources/stats.
- Commit stable milestone boundaries.

## Art / animation rule

Do not mass-generate the remaining card set while the V2 battlefield/card language is unsettled.

Life/Fire remains the only production target.

Every important action must have readable choreography: draw, select, land build, summon, Place build, spell cast, attack, hit, death, Heart strike, fusion and victory.

The goal is not “particles happened.” The player must see **cause -> travel/action -> impact -> result**.

Use AI generators aggressively for consistent production assets, but judge them in the running game at actual scale.
