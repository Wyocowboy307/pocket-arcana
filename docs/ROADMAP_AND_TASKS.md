# Roadmap & Claude Task Queue

## Gate 0 — real Godot boot
- Open with installed Godot 4.x stable.
- Fix parser errors without redesigning systems.
- Run `scenes/main.tscn`.
- Confirm a Life-vs-Fire graybox match can complete.

## Milestone 1 — rules loop
- Fix/complete mouse target selection.
- Add explicit Heart attack action when adjacent rather than relying on entering Sanctuary.
- Add move/push target direction UX.
- Add pass preview: current Realm Score and likely Chapter result.
- Add Chapter transition overlay and persistent landmark reset rules.
- Test deterministic match with fixed seed.

## Milestone 2 — 32-card vertical slice
- Only activate `slice_ready` cards first.
- Ensure at least 4 playable cards per element and 8 recipe pairs.
- Make two dramatically different decks feel real: Fire Heart-pressure vs Life/Earth realm/Wonder.
- Add card hover details and keyword help.

## Milestone 3 — presentation
- Event animation queue.
- Card lift/slam, summon, terrain morph, recipe discovery.
- Pixel tile atlas + placeholder creatures with consistent style.
- Audio event hooks.

## Milestone 4 — collection/deckbuilder
- Collection browser + filters.
- 40-card legality UI.
- Commander picker.
- Save/load custom decks.
- Starter-deck “simple label” buttons: FREEZE, STORMS, HEAL & GROW, DRAGONS, FLOW, BUILD, MOVE, SPOOKY FRIENDS.

## Milestone 5 — replay loop
- Arcana Commons hub.
- Codex discoveries.
- Commander mastery XP and cosmetic unlocks.
- Campaign map, named opponents, puzzle encounters.
- Earnable currency; no paid stat power.

## Do not do yet
Multiplayer, final economy tuning, 240 bespoke card scripts, expensive final cinematics, or huge procedural campaign generation.
