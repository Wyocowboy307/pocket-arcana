# V2 Art + UI Production Pass — Audit, Triage and Direction Lock

Date: 2026-08-30. Input: 24 fresh captures of every V2 scenario at HEAD
(harness: `scenes/dev/screenshot_v2.tscn`), a four-lens visual audit
(board/pieces/UI/actions), a code map of the whole V2 view layer, and a
content/art coverage map. This document is the working spec for the pass.

## The one-line diagnosis

The creature and building art is genuinely good, but it is trapped inside a
digital dashboard: cards parked on a muddy noise field, flat charcoal panels,
and state numbers scattered to the screen edges. Nothing on screen says
"a magical board game came alive".

## Direction lock — "The Table, the Plots, the Pieces"

Approved via master mock (`docs/screenshots/direction/master_mock.png`):

1. **The table.** The unbuilt battlefield is a calm, dark arcane slate table —
   big soft value cells, zero per-pixel speckle. Each unbuilt lane slot is a
   faint carved **socket**: a recess that says "something is built here".
   The clash line is an inlaid **channel** across the table with a carved rune
   medallion per lane. No central light pool; vignette at most 15%.
2. **The plots.** A Realm card drops a chunky elevated **diorama plot** into
   its socket: calm elemental top surface (large flat patches, sparse accents),
   thick dark front face with strata, full ink outline, bright top rim.
   Grove = mossy green + blooms; Cinder = scorched black-brown + live ember
   seams. Same-element neighbours visually merge. Props stand ON plots.
   Grove top runs a step darker than creature greens so pieces win contrast.
3. **The pieces.** A played card physically becomes its creature. On the board
   there are **no card frames**: the sprite stands on the plot with a contact
   shadow and two chunky stat tokens at its feet (gold power, red health).
   Size classes matter: small 48px sprites stay small; large 96px sprites
   tower. Resting = dimmed + settled; ready = idle breathing. Name appears on
   hover only. Places are buildings standing at the back of the plot, never a
   second card. Dark-bodied Fire creatures get a warm rim-light pass so they
   never sink into their own land.
4. **The homes.** Each Sanctuary sits fully on-screen on its own element plot
   on the left rail; the Commander stands in front of it; the **Heart is a
   faceted crystal ON the sanctuary plot** with its number on a stone plaque —
   the right-rail heart diamonds are deleted. Damage cracks and dims the
   crystal in place.
5. **The components.** All chrome is physical: carved wooden hand tray, larger
   parchment hand cards (cost = aether crystal, stats = the same tokens the
   board uses), END TURN as a chunky carved button, BUILD REALM as a physical
   stack of land slabs with a count, COMBINE as a glowing talisman when live,
   aether as a row of crystal orbs (spent = dark, not absent), tooltips and
   coach as parchment scraps anchored near their subject. One visual language,
   the board's pixel density, everywhere.
6. **The reference feeling** (not the IP): Adventure Time Card Wars — the board
   is the hero, cards visibly build a little world, creatures are toys with
   personality, "strange before pretty". Zero Adventure Time content.

## Triage

### MUST FIX NOW (breaks the fantasy or the readability)
- M1 Ground: muddy camo noise everywhere → table + sockets (board lens, all captures).
- M2 Built land reads as stains → elevated chunky plots; Fire terrain almost
  invisible today ("garden vs empty dirt").
- M3 Cards parked on the field → creatures standing free + stat tokens; late
  game currently buries 70% of the world under card rectangles.
- M4 Lanes illegible → sockets + channel + medallions make them countable.
- M5 Hearts: duplicated, disconnected, faded during the win-condition beat →
  one crystal per player, in the sanctuary plot, damage animated in place.
- M6 Bottom bar + right rail are debug panels → tray + physical components.
- M7 Hand cards unreadable at rest (tiny art, red warning strip across art,
  grey names, fake progress bar) → new hand card language.
- M8 Fusion is a white blob inside a card frame → board-scale spectacle
  (sources converge, silhouette flash, shockwave, reveal) + talisman button.
- M9 Heart strike scattered across three corners → full cause→travel→impact→
  result chain onto the sanctuary crystal.
- M10 Summon shows no transformation → card slams down and the creature
  rises out of the land.
- M11 Land build has no event → growth wavefront + staggered prop pops.
- M12 View-layer bugs (code map §5): spell payload reads missing `side` key
  every frame; spell/place `element` never sent so Fire actions render
  Life-flavoured; empty-element edge case; double heart-shock; dead code in
  `motion_style`; unimplemented `ghost_card`.

### SHOULD FIX DURING THIS PASS
- S1 Attack readability: cap emphasis scale ~1.25x, keep defender visible,
  impact star on the victim, suppress status text during acts.
- S2 Dragon breath: aim along the lane at the real target, scorch decal.
- S3 Ready/resting: posture + dimming, kill the RESTING text and LED dots.
- S4 ∞ fusion badges and micro-indicators → engraved tokens/rune links in
  world pixel language.
- S5 Tooltip/coach/banner → parchment language, anchored near subject,
  player-facing copy (no "lane 4").
- S6 Places buried behind creatures → building at plot rear, creature in
  front, both visible; pixel signboard on hover.
- S7 Element-tint the two unbuilt halves subtly so "my side / their side"
  reads before anything is built.
- S8 Rim-light dark sprites; kill green-on-green window seams (windows gone
  with M3).
- S9 Death: decisive wilt/crumble to a clean full-opacity remnant.
- S10 Victory/defeat overlay in the component language.
- S11 Missing art: 4 spell illustrations (life_rebloom, life_wild_flourish,
  fire_scorch_mark, fire_wildfire_waltz), `dual_ashbloom_fox` creature
  (fusion result with NO art), 2 commander portraits.

### SAFE TO LEAVE FOR LATER
- L1 Names hidden at rest everywhere (needs the silhouette pass proven first —
  hover names ship now).
- L2 Audio hooks (cue signal exists).
- L3 Collection/deckbuilder visual language (screens not active in V2).
- L4 Further elements beyond Life/Fire (pipeline must scale, assets wait).
- L5 A dedicated brook/stream motif in the clash channel.

## Milestones (each committed when the game runs + captures verify)

- **A. The Table** — palette TABLE ramp; `tools/pixelart/table.py` (table
  field, socket, channel, medallions); calmer grove/cinder fields; stage
  `_draw_ground/_draw_clash_seam/_draw_atmosphere` rewrite.
- **B. The Pieces** — de-card `_draw_creature`; stat tokens; size classes;
  posture; places visible; rim light; hover nameplates.
- **C. The Homes** — sanctuary plots + embedded hearts + commander; right
  rail becomes deck + realm stack + aether crystals on a plinth.
- **D. The Components** — tray, buttons, talisman, new hand cards
  (`tools/pixelart/cards.py` + `card_v2.gd`), tooltip/coach parchment.
- **E. The Actions** — M9-M12, S1-S3, S9; harness scenario payload fix.
- **F. The Spectacle** — fusion at board scale + rune links + talisman.
- **G. Original Art** — ashbloom fox, spell illustrations, portraits,
  weird-up pass on weakest silhouettes (SpriteCook, conformed to palette).
- **H. Close** — full capture set re-shot, README/ART_BIBLE addendum, new
  tutorial/win/lose captures, triage re-check.

## Production rules for this pass

- Every asset conforms to `tools/pixelart/palette.py` (new ramps are added to
  the file deliberately, never ad-hoc colours).
- Generated art goes through `tools/generate_hero_art.py`-style candidates →
  approve → conform; the ledger `data/art_generation_log.json` records
  prompt, candidates, choice and rejection reasons.
- Judge every asset in a real capture at gameplay scale before calling it done.
- The simulation is untouched: this pass edits presentation only
  (`scripts/ui/v2/*`, `tools/pixelart/*`, assets, and the two payload bugs in
  `main_v2.gd` which are view-layer data).

## Status after the pass (2026-08-30, end of session)

Milestones A–H landed; `./tools_verify.sh` ALL CHECKS PASSED; final captures
in `docs/screenshots/v2_art_pass/`. An adversarial four-lens review of the
finished captures was run and its blockers fixed: end-overlay z-order, the
coach relocated to the clash channel (and hidden in captures), the on-card
rules strip removed, open-lane attacks now trail dots to the pulsing rival
Heart, one selection grammar in attack mode, the fusion link redrawn as
interlocking rings between body centres (it read as a stuck "-1" badge),
BUILD REALM hides with no empty socket, big creatures no longer strip their
plot's props, integer-upscale conform (fixes the tiny Poppy portrait), and
merged-slab grooves strong enough to count lanes.

Known remaining polish (deliberately deferred):
- land-build/summon spokes are still thin hairlines — wants a chunky pixel
  burst pass in the FX library
- the mid-lunge attacker keeps its idle pose — wants lean/stretch frames
- fusion collapse could silhouette its sources harder inside the core
- a numeral aether readout near the hand (dots on the shelf carry it today)
- hand-card names use the theme font — a bitmap pixel face would sit better
