# Pocket Arcana V2 — Clarity Redesign

## Why V2 exists

The current version has too many simultaneous concepts for a first-time player:
- shared 7×5 territory
- shaping
- movement
- attack legality
- elemental attunement
- Chapters / passing
- Seals
- Heart pressure
- Wonder
- creatures / landmarks / spells / land

The player should not need to understand six systems just to answer: **“Where does this card go?”**

V2 tests a much clearer board while keeping the magical-world fantasy.

## The sentence

**Build your four magical lands, summon creatures that belong there, and break the rival Heart.**

A new player should understand that sentence after one tutorial turn.

## Board

Each player owns a separate side of the battlefield.

There are **4 mirrored lanes**.

Each lane contains:
- 1 Landscape slot
- 1 Creature slot on that Landscape
- 1 Place slot on that Landscape

Behind the four lanes is the player's Commander + Heart Sanctuary.

The rival has the same structure on the opposite side.

### Critical rule

**Your creatures stay on your land. Rival creatures stay on rival land.**

There is no normal walking into the opponent's half.

Attacking is performed across the lane:
- if an opposing creature is present, attack it;
- if that lane is open, attack the rival Heart;
- special cards can target adjacent lanes or rearrange your own creatures.

This keeps lane/position strategy without requiring the player to learn grid movement.

## Landscapes / Realm cards

Land must be visually and mechanically central.

Each deck brings **4 Realm cards** in addition to the normal draw deck. They are chosen during deckbuilding and always available through a small Realm Stack, so the player cannot lose because they never drew land.

For the Life starter these are Grove lands.
For Fire these are Cinder lands.
Dual-element decks later can mix their four Realm cards.

At match start the Commander's signature home land grows automatically in one lane, giving immediate identity and enough Aether to act.

The remaining Realm cards are played as a main card play into empty lane land slots.

### Playing land should be a spectacle

Grove example:
1. Realm card lifts.
2. Empty lane glows green.
3. Card flies/slams onto the lane.
4. Card frame dissolves into roots.
5. Vines spread outward.
6. Grass/flowers/trees rise.
7. Aether leaf/pip appears.

Cinder example:
1. card ignites at edges;
2. ember ring expands;
3. ground darkens/cracks;
4. cinder stones rise;
5. sparks drift;
6. Aether flame/pip appears.

Later elements get equally unmistakable land-building animations.

## Aether

Use one resource: **Aether**.

- Sanctuary provides 1 Aether capacity.
- Every built Landscape provides +1 Aether capacity.
- Aether fully refills at the start of your turn.
- Four lands + Sanctuary = 5 maximum baseline Aether in the first prototype.

This makes the relationship obvious:
**build land -> get more magic -> play stronger cards.**

No separate Attunement meter in V2. The Landscape itself is the elemental requirement.

## Turn

At the start of turn:
1. draw 1 normal card;
2. refill Aether;
3. ready creatures.

During turn the player gets:
- **one Card Play** — Realm, Creature, Place or Spell;
- **one Attack** with one ready creature, in either order.

Then End Turn.

This is intentionally small and readable.

## Card types

### REALM / LAND
Builds one of your four landscapes and increases Aether capacity.

### CREATURE
Lives on one compatible Landscape. Has Attack and Health. Normally cannot attack on the same turn it is summoned.

### PLACE
A building/support object attached to one compatible Landscape. One Place per lane.

### SPELL
Resolves immediately against clearly highlighted legal targets.

Do not add Relic as a fifth primary type until the first four are effortless to understand.

## Element requirement

A Life creature does not check an abstract meter.

Its card says:
`PLAY ON: GROVE`

When selected:
- every valid Grove lights up;
- other lands dim;
- occupied Grove shows `Creature already here`;
- no valid Grove shows `Build a Grove first`.

Fire follows the same rule with Cinder.

## Combat

Select/drag a ready creature toward the opposing slot in the same lane.

If defender exists:
- attacker deals Attack damage;
- defender may strike back if its rules allow;
- dead creatures go to discard after the impact animation.

If defender slot is empty:
- creature attacks the Heart for its Attack.

The attacker never permanently crosses into enemy land.

## Win condition — V2 prototype

**First Heart to 0 loses.**

Start with one win condition while learning the new board.

Temporarily disable:
- Chapter Seals
- Wonder victory
- round scoring
- Pass/card-preservation system

Those systems can be reintroduced later only if they improve the now-clear core rather than obscuring it.

## Fusion / combination

A major V2 identity mechanic.

Certain pairs of friendly creatures can combine into a stronger magical creature.

Rules:
- fusion recipes are data-driven;
- valid pairs show a small linked-rune indicator;
- the UI never asks the player to blindly guess in a normal competitive match;
- activate Fusion as the Card Play for the turn;
- pay the recipe Aether cost;
- consume the two source creatures;
- summon the result into one source lane and free the other lane.

Animation should be a major moment: both creatures lift, elemental ribbons connect them, silhouettes orbit/merge, flash, then the new creature slams down.

Recipes can still be discovered in campaign/Codex, but once known they are communicated clearly.

## Life vs Fire starter identity

### Life / Grove
- healing
- growth over time
- durable creatures
- support Places
- fusion that rewards keeping creatures alive

Example presentation:
- Sproutling: `CREATURE • LIFE • 1 AETHER • PLAY ON: GROVE`
- Herbalist Hut: `PLACE • LIFE • PLAY ON: GROVE`
- Grow: `SPELL • TARGET: YOUR CREATURE`

### Fire / Cinder
- direct damage
- aggressive creatures
- temporary buffs
- burn effects
- risky high-power fusion

Example presentation:
- Cinder Pup: `CREATURE • FIRE • 1 AETHER • PLAY ON: CINDER`
- Blacksmith Nook: `PLACE • FIRE • PLAY ON: CINDER`
- Little Flame: `SPELL • TARGET: ENEMY CREATURE`

## What V2 intentionally removes

For the first playable test:
- free-form creature movement
- shared territory ownership
- free Shape toolbar action
- separate Attunement meter
- Sanctuary Ward
- Realm Score
- Chapter passing
- Seal race
- Wonder race

This is not deleting the ideas forever. It is finding a core game that can be understood before layering depth back in.
