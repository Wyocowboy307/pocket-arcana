# Pocket Arcana — Game Design Bible v1

## Elevator pitch
Pocket Arcana is a 2D pixel-art collectible card game where **the cards build a tiny living magical world**. Players Shape elemental terrain, summon creatures and landmarks onto real board positions, combine elemental states into discovered locations, conserve cards across best-of-three Chapters, and build wildly different decks around one Commander.

A kid should understand the surface game quickly: **play something cool, build your world, win two Chapters or break the Heart.** A serious card player should still find bluffing, passing, sequencing, positioning, deck construction and cross-element engines underneath.

## Non-negotiable pillars
1. **Living board, not card table.** Creatures, landmarks and terrain exist in the world after the card is played.
2. **Easy to learn, hard to master.** Complexity comes from interactions, not long paragraphs.
3. **One action, clear consequence.** Each turn is one main action, then the opponent responds.
4. **Passing matters.** Winning a Chapter by one point with cards left is often better than winning by fifteen and emptying your hand.
5. **Magic leaves evidence.** Frost Freezes. Lightning Charges. Life Overgrows. Fire Burns. Water Wets. Earth Fortifies. Wind Windsweeps. Death Haunts.
6. **Elements mix physically.** Two states on one tile can transform it into a discovered special terrain.
7. **Decks can be crazy.** Dragons, lifegain, weather, recursion, landmarks, movement, tokens, Heart burn, Wonder engines and weird hybrids all deserve room.
8. **Commander = identity, not homework.** One passive and one once-per-Chapter Command.
9. **Animation explains rules.** It never owns the rules.
10. **No pay-to-win Commander leveling.** Progression can unlock cosmetics and sidegrades, never raw purchased match stats.

## Match identity
See `MATCH_RULES_V1.md` for authoritative rules. The strategic shape is:
- 7×5 shared board;
- persistent Hearts at 25;
- best-of-three Chapters;
- earn 2 Seals to win;
- Heart at 0 wins immediately;
- 10 Wonder wins immediately;
- terrain/landmarks carry history across Chapters;
- cards left in hand carry forward, making Pass a core decision.

## The eight elements
### ❄ Frost — control and preservation
Freeze dangerous places, build crystal terrain, protect value, create slow positional locks, and eventually land huge winter finishers. Beginner idea: **freeze trouble**.

### ⚡ Lightning — setup and burst
Charge tiles, chain damage, gain temporary Aether, build storm engines and create explosive payoff turns. Beginner idea: **charge it, then pop it**.

### 🌿 Life — healing and growth
Heal the Heart, Overgrow terrain, make friendly creatures, widen boards and turn a thriving realm into Wonder. Beginner idea: **heal and grow**.

### 🔥 Fire — pressure and dragons
Burn terrain, hit Hearts, trade resources aggressively, hatch dragons and turn destruction into special terrain such as Ashbloom or Volcano. Beginner idea: **burn and hit hard**.

### 💧 Water — flow and weather
Wet terrain, draw, redirect movement, combine with other elements and win through flexible positioning. Beginner idea: **move around problems**.

### 🪨 Earth — landmarks and fortification
Fortify tiles, build landmarks, make sturdy units and accumulate Realm Score through structures that are hard to dislodge. Beginner idea: **build something strong**.

### 🌪 Wind — movement and tempo
Move units, dodge blockers, create floating terrain and make positioning itself into an engine. Beginner idea: **be where the opponent is not**.

### 💀 Death — friendly recursion
Haunt terrain, make lantern spirits, sacrifice creatures for value, return fallen friends and use the graveyard as a resource. Tone is magical-spooky, not gore. Beginner idea: **your spooky friends come back**.

## Element pair discovery
There are 28 two-element pair recipes in the core data — every possible pair among eight elements. Examples:
- Frost + Lightning → Aurora Ice
- Frost + Fire → Meltwater
- Lightning + Water → Stormglass
- Life + Fire → Ashbloom
- Life + Death → Gravegarden Bloom
- Fire + Earth → Volcano
- Fire + Water → Steamfield
- Water + Death → Ghostwater
- Earth + Wind → Floating Island

The first discovery shows a celebration and enters the Codex. Repeats should be quick and readable.

## Card types
- **Creature:** occupies a tile, moves, fights and may pressure the rival Heart.
- **Landmark:** persists on its own layer and contributes Realm Presence; a creature can share its tile.
- **Spell:** immediate magical effect.
- **Terrain:** intentional terrain transformation.
- **Relic:** tool/equipment style effect; attachments can expand later.

## Commander system
Every deck chooses one Commander. Core set: 24, three per element.

In a match the player sees only:
- one passive sentence;
- one Command button, usable once per Chapter.

Outside matches, Commander Mastery can unlock art, frames, VFX, lore, titles and horizontal sidegrade powers. It must never become “my Commander is level 20 so it has +5 stats.”

## Deckbuilding
Constructed target: 40 cards plus one Commander.
- maximum 3 copies of a normal card;
- maximum 1 copy of a Mythic;
- mono-element starter decks are intentionally easy;
- dual-element decks gain more combinations but require shaping both Attunements;
- future tri-element decks can exist only if playtests show the board remains readable.

### Desired archetypes
- **Freeze Lock:** Frost control + preservation.
- **Storm Engine:** Lightning/Water Charged+Wet recipes and burst.
- **Heal & Grow:** Life Heart healing, tokens and Wonder.
- **Dragons:** Fire pressure into huge flying finishers.
- **Citadel:** Earth landmarks and Realm Score.
- **Sky Roads:** Wind positional/movement deck.
- **Lantern Parade:** Death ghosts, recursion and death triggers.
- **Ashbloom:** Life/Fire intentionally grows then burns its own realm.
- **Floating Kingdom:** Earth/Wind landmarks on special floating terrain.
- **Ghostwater:** Water/Death flow + recursion.
- **Winter Storm:** Frost/Lightning Aurora terrain and charged frozen payoffs.

## Why players keep playing
The collection should expand *possibilities*, not just numbers.

Long-term loop:
1. Play a duel, puzzle, campaign encounter or Expedition.
2. Earn cards, cosmetic resources and Commander Mastery.
3. Discover a recipe/interaction and add it to the Codex.
4. Unlock a named opponent, region, puzzle or Signature card.
5. Build a new deck because the discovery gave you an idea.
6. Return with a different plan.

## Campaign concept
The world is a magical atlas built around elemental regions and mixed borderlands. Each early region teaches one element in plain language; later regions deliberately combine them. Encounters can include normal duels, puzzle states, unusual terrain rules, Commander bosses and deckbuilding challenges.

The home hub, **Arcana Commons**, visibly fills with creatures, trophies, Commanders and Codex discoveries as the player progresses. The collection should feel like a place, not only a menu.

## Puzzle mode
Small authored board states teach interactions better than walls of text. Examples:
- Win the Chapter with only one card.
- Make Stormglass this turn.
- Save a creature by creating Meltwater.
- Reach the rival Sanctuary using Wind without destroying a blocker.
- Win through Wonder while your Heart is at 1.

## Presentation target
The graybox can be buttons; the final game cannot feel like a spreadsheet. A card should lift, glow, dive toward its tile and become a world object. Terrain should visibly morph. Creatures idle. Landmarks animate subtly. Recipes combine both elemental visual languages. The board at the end of a match should look like a strange little kingdom the players created together.

## Content discipline
`data/core_set.json` contains 240 designed cards, but only `slice_ready` cards should be prioritized initially. When a new card would require bespoke code, first ask whether its mechanic belongs in the generic effect/trigger vocabulary. Expand the engine before multiplying one-off scripts.

## First fun proof
Before final art or multiplayer, prove all of these:
- Pass creates a real “do I spend another card?” decision.
- Fire can pressure the Heart while Life/Earth can win through Realm/Wonder.
- At least eight recipes are satisfying and understandable.
- A creature emerging from a card feels good.
- A landmark engine visibly changes the board.
- Commander choice changes play without adding mental overload.
- A new player can finish a match without knowing TCG jargon.
