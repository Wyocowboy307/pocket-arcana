# Animation Bible — make simple pixels feel expensive

## Rule
Simulation commits state first. Animation reads the emitted event and explains it. Never wait on particles/tweens to decide game rules.

## Shared card-play sequence
1. Card lifts 8–12 px.
2. 120–180 ms ease-out scale to 1.06.
3. Element rim/light appears.
4. Card dives toward target tile.
5. 1–3 px board punch/shake for impactful plays.
6. World object appears with squash/stretch or materialization effect.
7. State/recipe effect happens **after** the object is readable.

## Element language
- Frost: crystalline wipe, drifting snow motes, short bright crack.
- Lightning: 1–2 frame white flash, branching pixel bolt, tiny after-sparks.
- Life: sprout arcs, leaf particles, soft upward bounce.
- Fire: ember trail, edge burn, warm burst; no realistic gore.
- Water: ripple ring, droplets, brief liquid distortion.
- Earth: chunky tile lift, pebble particles, satisfying low thump.
- Wind: curved streaks, leaf/paper motes, lateral overshoot.
- Death: friendly lantern wisps, purple/blue soul trail, soft pop; magical-spooky rather than horror.

## Recipe moment
Pause normal idle effects for ~250 ms, outline the tile, combine the two elemental motifs, morph terrain, then show `DISCOVERY: <name>` the first time. Do not interrupt every repeat with a full banner.
