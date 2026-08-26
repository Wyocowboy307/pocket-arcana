# Content Schema

## Card
Required: `id`, `name`, `type`, `rarity`, `cost`, `elements`, `attunement`, `rules`, `effects`, `implementation_status`. Creatures add `power` and `health`; landmarks add `presence`.

### Generic effect vocabulary in the graybox
- `add_state`
- `damage_unit`
- `damage_heart`
- `heal_heart`
- `draw`
- `gain_wonder`
- `gain_aether`
- `buff_unit`
- `transform_terrain`
- `summon_token`
- `resurrect_last`
- `move_unit` (event shell; full directional target UX is a follow-up)

## Commander
Each Commander has `passive_text`, a structured `passive`, `command_text`, and structured `command`. The runtime supports trigger names such as `on_chapter_start`, `on_first_card_played`, `on_first_state_added`, `on_unit_death`, `on_unit_move`.

## Recipe
Two required elemental states on one tile → one result terrain. Result terrain provides both corresponding Attunements.

## Implementation status
- `slice_ready`: belongs in early runtime/playtest coverage.
- `blueprint`: designed card; do not write bespoke code just to activate it. Expand generic vocabulary first.
