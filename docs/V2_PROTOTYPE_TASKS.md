# Pocket Arcana V2 — Prototype Tasks

## Objective

Build a **playable comparison prototype** of the new split-lane rules before spending more art budget or expanding elements.

Do not spend days preserving every V1 edge case. The question is whether V2 is dramatically clearer and more fun.

## Gate 0 — protect current work

- record current main commit
- keep old V1 docs/code recoverable in git history
- validator/tests still run
- add V2-specific tests instead of deleting all V1 verification immediately

## Gate 1 — board skeleton

Build four lanes per side.

Each side shows:
- Commander/Heart
- 4 Landscape slots
- 4 Creature slots
- 4 Place slots

No normal cross-half movement.

Use current art as temporary assets where possible.

## Gate 2 — Realm cards + Aether

- signature land pre-deploys with animation
- Realm Stack contains remaining lands
- play Realm into empty land slot
- Sanctuary + built lands determine Aether cap
- refill each turn
- remove free Shape action from V2 mode

## Gate 3 — card play clarity

Implement V2 card language for Life/Fire:
- type ribbon
- element crest
- Aether cost
- `PLAY ON` / `TARGET`
- legal highlight
- invalid reason
- ghost preview

Map existing starter cards into V2 roles without rewriting all 240.

## Gate 4 — lane combat

- one attack per turn
- same-lane defender first
- open lane can hit Heart
- summon sickness/readiness
- no permanent attacker crossing
- current attack styles reused/adapted

## Gate 5 — animation quality

Implement event timelines from `V2_ANIMATION_CHOREOGRAPHY.md`.

Review in real time, not frame-by-frame only.

Mandatory:
- draw
- land build
- summon
- Place build
- spell
- melee attack
- dragon/ranged attack
- hit/death
- Heart strike

## Gate 6 — Fusion prototype

Add 2 Life recipes, 2 Fire recipes and 1 Life/Fire recipe for testing.

Data-driven recipe format.

Show valid fusion indicator; no blind guessing.

Full fusion animation.

## Gate 7 — tutorial

Implement scripted first match from `V2_TUTORIAL.md`.

The player should not spawn into a full random hand with every system active.

## Gate 8 — usability test

Run an uncoached Life vs Fire match.

Ask only:
1. Can a new player tell where every card goes?
2. Does building land visibly feel important?
3. Do attacks show who attacked whom and what happened?
4. Does the Heart goal feel obvious?
5. Does Fusion feel exciting rather than confusing?

## Gate 9 — decision

Only after V2 is playable:
- compare V1 vs V2 screenshots/video and feel;
- keep the clearer core;
- then decide whether any Gwent-style round/passing system should be layered back on top.

Do not restore Chapters/Seals/Wonder merely because they were already implemented.

## Art spend freeze

Until Gate 9:
- no remaining six-element batch generation;
- no all-240-card illustration pass;
- only generate an asset if V2 cannot be judged without it.
