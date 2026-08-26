# Claude Opus Handoff — “go build” means implement

This project is **Pocket Arcana**, not Pixel Ranch. Never touch Pixel Ranch.

## Your first prompt can literally be
> Go build. Read CLAUDE.md and follow the task queue. Do not redesign the game unless the files contradict each other. First make the project boot and play a full graybox match.

## First session
1. Read root `CLAUDE.md`, then `docs/DESIGN_DECISIONS.md`, `docs/MATCH_RULES_V1.md`, and `docs/ROADMAP_AND_TASKS.md`.
2. Run `python3 tools_validate_content.py` and `python3 tools_content_audit.py`.
3. Open Godot 4.7.2 and run `scenes/main.tscn`.
4. Fix parser/runtime errors first. Keep changes local and small.
5. Play Life vs Fire to completion. Record bugs in `docs/IMPLEMENTATION_NOTES.md`.
6. Commit the clean boot before adding MCP/editor automation.

## Token-saving rule
Do not brainstorm 240 cards. They already exist in `data/core_set.json`. Do not rewrite the design bible. Use tokens on code, scene assembly, runtime inspection and playtesting.

## Architecture direction
- `MatchEngine` owns rules and emits events.
- `BoardModel` owns tile state.
- `EffectResolver` resolves generic effects.
- `ComboResolver` transforms two-state tiles.
- UI asks engine for legal actions and renders state.
- Animation subscribes to emitted events; animation never owns rules.

## Definition of a successful first Opus session
A real Godot run can complete a Chapter, pass, score it, begin the next Chapter, and eventually finish a match without parser/runtime errors.
