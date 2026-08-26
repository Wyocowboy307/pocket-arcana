# Pocket Arcana — Claude Code Instructions

This repository is Pocket Arcana. **It is completely separate from Pixel Ranch. Never read, edit, import, move, or commit anything in Pixel Ranch.**

When Thomas says “go build,” implement. Do not reopen product discovery.

## Read order
1. `docs/DESIGN_DECISIONS.md`
2. `docs/MATCH_RULES_V1.md`
3. `docs/ROADMAP_AND_TASKS.md`
4. `docs/IMPLEMENTATION_NOTES.md`
5. Exact code/data needed for the current milestone

## First commands
- `python3 tools_validate_content.py`
- `python3 tools_content_audit.py`
Then run `scenes/main.tscn` in Godot and fix parser/runtime errors before adding features.

## Locked product
A 2D pixel-art living-board collectible card game that a kid or non-TCG adult can learn quickly, with serious deckbuilding underneath. Board 7×5. Win 2 Chapters, break the persistent Heart, or complete 10 Wonder. Turns are one main action. Passing preserves cards for later Chapters.

Elements: Frost, Lightning, Life, Fire, Water, Earth, Wind, Death.

Every deck has one Commander: one passive + one once-per-Chapter Command. Commander progression is horizontal/cosmetic, not paid raw power.

## Data authority
- `data/core_set.json` — 240 designed cards. Do NOT bespoke-code all 240.
- `data/commanders.json` — 24 Commanders.
- `data/starter_decks.json` — 8 legal 40-card starters.
- `data/combo_recipes.json` — 28 pair recipes.
- `data/elements.json`, `data/terrain_attunement.json`, `data/tokens.json`
- `data/card_art_prompts.json` — AI-art direction prompts.

## Engineering rules
- Deterministic simulation.
- Generic effect vocabulary first.
- UI asks the simulation for legal actions and failure reasons.
- Animation communicates committed state; it never decides rules.
- Higher AI difficulty means better decisions, not hidden resources/stats.
- Commit stable milestone boundaries.
- Prefer implementing/testing over broad questions.
