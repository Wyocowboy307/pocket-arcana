# Implementation Notes

## 2026-08-26 scaffold rebuild
The earlier package contained mostly prose despite describing code/data that were not present. This rebuild adds actual Godot project files, JSON content and validators. Python content validation is clean; Godot parser/runtime validation is still required on a machine with Godot installed.

Known graybox limitations to address first:
- `move_unit` spell effect currently emits an event but does not choose a direction; movement UX belongs in Milestone 1.
- Explicit direct Heart attack needs a clearer action than stepping onto the Sanctuary tile.
- Commander passives are intentionally generic and simple; mastery sidegrades are content-only for now.
- AI only plays/shapes/passes; creature movement/Commander use should be added after core boot is stable.
- Board visuals are generated UI buttons, not final pixel scenes.

## 2026-08-26 first real Godot 4.7.2 pass

Gate 0 found three parser errors (single-line `if/else`, `if` after `;`) and eight
`:=` inferences off untyped Variant returns. Fixed without redesigning systems.

One runtime bug stopped every match: shaping a tile that already had that terrain
succeeded as a no-op, so both AIs re-shaped one tile forever. Shaping now has to
change the tile.

### Sanctuary Ward — a rules addition, flagged for review
`docs/PLAYTEST_MATRIX.md` asks that a player be able to win by Heart damage *and*
that Wonder require deliberate setup. With the explicit Heart-attack action from
Milestone 1, a creature parked beside the rival Sanctuary struck for free every
turn, and 150 simulated matches ran:

    Fire 86.7% / Life 13.3%, 95% of matches ended by Heart break,
    Wonder never won, and matches rarely reached Chapter 3.

Heart-rush dominated every other plan. `MatchEngine.SANCTUARY_WARD = 2` makes the
Sanctuary retaliate against whatever strikes it. That single knob moved the result to:

    Two Chapter Seals 62% of matches, Heart broken 36%, Wonder 1%.

This rule is **not** in the original design docs — it is a playtest decision, kept as
one constant so Thomas can retune or remove it in one place.

### Life and Fire were mirror decks
Both starters shipped with identical creature curves (1/2, 2/2, 1/3, 3/2, 2/4, 4/3,
5/5, 6/5, 8/8), which `CARD_DESIGN_RULES.md` bans as "same card but +1 stat" filler.
Because Realm Score is counted only when both players Pass, *survival* decides
Chapters. Life now gets the tough bodies, Fire the fragile high-Power ones:

    Life 58.7% / Fire 41.3%
    Life wins 82% of its wins on Chapter Seals (plus its Wonder wins)
    Fire wins 66% of its wins by breaking the Heart

`tools_validate_content.py` now fails if the two slice decks are ever numerical
mirrors again, and if any card in a slice deck is not `slice_ready`.

### Still open
- `move_unit` still has no directional target UX (no slice card uses it yet).
- Commander passives for Mossy Mae and Poppy Cinder are still the same sentence.
