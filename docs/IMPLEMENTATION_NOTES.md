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

### Commander identity and the final slice balance
Mossy Mae and Poppy Cinder both shipped with "gain 1 bonus Aether" — the same
sentence, so Commander choice changed nothing in the slice matchup. They now carry
their element's job, using only the existing effect vocabulary:

- Mossy Mae — at the start of each Chapter, heal your Heart 2.
- Poppy Cinder — at the start of each Chapter, deal 2 damage to the rival Heart.

That left Life ahead 60/40, and reversing the seating showed it was deck strength
rather than first-player advantage (Life won 63% *going second*). Life's tough
bodies survive to scoring time, and Realm Score is only counted when both players
Pass, so Fire had no way to actually race. Fire's reach was raised instead of
Life's bodies being cut: Dragon Breath 2 -> 3 Heart damage, Rax 5 -> 6.

Final, 200 matches per seating:

    Life first: Life 54.5% / Fire 45.5%
    Fire first: Fire 44.5% / Life 55.5%

    Life wins ~80% of its wins on Chapter Seals (plus both Wonder wins)
    Fire wins ~60% of its wins by breaking the Heart

Turn order is worth about a point, and each deck wins in its own way — the split
PLAYTEST_MATRIX and the "First fun proof" list ask for.

`test_slice_matchup_stays_healthy` runs 40 seeded matches in the suite so this
cannot silently regress.

### move_unit
Push/movement magic now takes a real destination. `play_card()` accepts an optional
second target; a card that needs one is refused with `needs_second_target` until it
gets a legal destination, and the UI turns that refusal into a second click.
`legal_push_targets()` never allows a creature to be pushed into a Sanctuary.
Only Tailwind uses this today, and it is outside the Life/Fire slice.

### Passing was strictly bad — the second flagged rules change
DESIGN_DECISIONS #4 says winning a Chapter by one point with cards left is often
better than winning by fifteen with an empty hand. That could not happen. By the
letter of MATCH_RULES a player who has passed is skipped, so the other player kept
taking turns until they chose to stop. Telemetry over 120 matches:

    8.22 free actions after the rival passed, 4.22 of them Shapes

Shaping costs no cards and permanently claims a tile, so those free turns were pure
Realm Score that persisted into every later Chapter. Passing first was strictly
punished, so nobody ever passed holding cards.

`MatchEngine.FINAL_TURNS_AFTER_PASS = 1` gives the remaining player one last turn
and then scores the Chapter. A/B over 120 matches each:

    free actions after a pass   8.22 -> 2.18
    cards held when a Chapter scores  2.76 -> 3.48
    Life / Fire                 65 / 35  ->  50.8 / 49.2

The free-Shape loophole was quietly favouring the slower deck, so bounding it also
closed the residual balance gap without touching a single card number. At 250 matches per
seating the matchup now sits at Life 53.6% / Fire 46.4% (54.4 / 45.6 reversed),
and matches reach Chapter 2.72 on average, so the best-of-three actually happens.

Like the Ward, this is a playtest decision rather than something the design docs
specified, and it is one constant.

Side effect worth knowing: Chapters are now much shorter (59 actions per match,
down from 88), so creatures rarely have time to walk across the board and grind a
Heart to zero. Heart strikes fell from 4.5 per match to about 1, and Fire now wins
more of its matches on Seals than by Heart break. Fire is still roughly ten times
more likely than Life to win by Heart, so the identities still read, but the split
is softer than it was. Retuning `SANCTUARY_WARD` no longer moves this much (Ward 1
vs 2 changed Fire's Heart wins by 3 matches in 150) — the Chapter length is the
binding constraint now, so that is the knob to reach for.

### Still open
- The other six starter Commanders still share the "+1 Aether" passive.
- Roughly 10% of matches are decided by the blunt "Final tiebreak" rule.
