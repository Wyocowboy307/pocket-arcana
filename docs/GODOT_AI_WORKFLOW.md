# Godot + Claude / AI Workflow

## What exists in 2026
Godot itself is still a general game engine, but the official Asset Library contains community MCP add-ons that expose editor/game operations to AI clients. This is different from a first-party “Godot AI builds the game” feature.

Useful current options researched for this project:
- **Godot AI Assistant tools MCP 0.6.0** (Godot Asset Library, community, MIT): advertises scene/script editing, GDScript validation, settings/errors, 2D generation hooks, running the game, screenshotting and querying live nodes.
- **Godot MCP Toolkit** (Godot Asset Store, community, MIT): broad editor operations and playtesting; publisher marks the current release unstable.
- **Breakpoint MCP** (Godot Asset Library, community, MIT): very broad editor/runtime bridge with deterministic playtesting features and higher-trust capabilities disabled by default.

## Recommended starting posture
Use the smallest capability set that supports edit → run → inspect errors → screenshot → fix. Keep the MCP bridge scoped to the Pocket Arcana project. Take clean Git commits before enabling broad mutation capabilities.

## Token-saving loop for Claude
1. Read `DESIGN_DECISIONS.md` and the exact milestone task only.
2. Inspect current Godot errors through MCP.
3. Make one coherent change set.
4. Run the relevant scene/test directly.
5. Inspect screenshot/runtime tree/error panel.
6. Fix failures in the same context window.
7. Commit.
8. Move to next slice.

Avoid asking Claude to repeatedly summarize the whole game, regenerate the design bible, or brainstorm card sets. Those tasks are already externalized in repo files.
