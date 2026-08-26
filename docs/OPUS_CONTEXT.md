# Opus Context — compact implementation brief

## What this is
Pocket Arcana is a **standalone** Godot 4.7.2 project. Never touch Pixel Ranch.

## What is already decided
- 7×5 living board.
- 8 elements: Frost, Lightning, Life, Fire, Water, Earth, Wind, Death.
- 40-card decks + one Commander.
- Commander = one passive + one once-per-Chapter Command.
- Start with 8 cards; draw 3 before Chapter 2 and 2 before Chapter 3.
- One main action each turn: card, Shape, move/fight, Command, or Pass.
- Both Pass → compare Realm Score; higher earns a Seal.
- Two Seals wins; Heart 0 or Wonder 10 wins immediately.
- Terrain and landmarks persist; creatures clear between Chapters in v1.
- Aether pays costs; shaped terrain provides Attunement.
- Two elemental states on the same tile can transform into a recipe terrain.

## Code map
- `scripts/core/content_database.gd` — loads JSON.
- `scripts/core/board_model.gd` — 7×5 tile truth.
- `scripts/core/match_engine.gd` — match/chapter/turn rules.
- `scripts/core/effect_resolver.gd` — generic card effects.
- `scripts/core/combo_resolver.gd` — state-pair terrain recipes.
- `scripts/core/simple_ai.gd` — intentionally dumb first AI.
- `scripts/core/deck_validator.gd` — constructed legality.
- `scripts/ui/main.gd` — dynamically built graybox UI.
- `scenes/self_test.tscn` — headless AI-vs-AI smoke test.

## Content map
240 cards, 24 Commanders, 8 legal starters, 28 pair recipes, 12 tokens, 24 archetype blueprints, 24 named opponents, 8 campaign regions / 40 encounter blueprints, 240 art prompts.

## First goal
**Do not make new content. Make the current graybox boot and complete a match.**

Run:
```bash
python3 tools_validate_content.py
python3 tools_content_audit.py
./run_smoke_test.sh
```

Then fix the first actual Godot failures. Once smoke test passes, play `scenes/main.tscn` manually and fix UX blockers.

## Known first improvements
1. explicit direct Heart attack UX;
2. directional push/movement spell targeting;
3. pass preview;
4. AI creature movement + Commander use;
5. event animation queue;
6. activate only the 32 `slice_ready` cards for focused playtesting.

## Do not waste tokens on
- renaming elements;
- debating match format;
- generating more cards;
- final art;
- multiplayer;
- rewriting docs unless code exposes a contradiction.
