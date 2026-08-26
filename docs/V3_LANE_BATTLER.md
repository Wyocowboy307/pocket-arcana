# Pocket Arcana V3 — Elemental Lane Battler

V3 replaces the V2 open battlefield with a **tabletop lane game**. The reference
for readability and feel is Adventure Time Card Wars; the twist that makes it
Pocket Arcana is **elemental landscapes that are also your resource system**.

V2 stays in the repo and keeps its launcher until V3 proves itself, the same way
V1 was kept through V2.

## The one-sentence pitch

Lay down landscapes, and the land you build both **decides what you may play in
that lane** and **pays for it**.

## Board

Rival on top, player on the bottom. Each player owns:

- one **Commander**, who holds that player's **Heart** (25)
- four **lanes**, each with three slots:
  - **Landscape** — the land that defines the lane
  - **Creature** — one creature at a time
  - **Support** — one attached Place at a time

Lanes face each other straight across. Lane 0 fights lane 0.

## Turn

1. **Refresh.** Your resource pool is recalculated from the landscapes you
   control (see below). Draw 1.
2. **Actions**, in any order, as many as you can pay for:
   - play **one Landscape** (free, one per turn) into an empty Landscape slot
   - play a **Creature** into a lane whose Landscape matches its element
   - play a **Support**, attached to a lane whose Landscape matches
   - cast a **Spell**
   - **Fuse** two of your creatures
   - use your **Commander's power** (once per match)
3. **Combat.** Each of your ready creatures may attack once.
4. **End turn.**

A creature played this turn is **resting** and cannot attack until your next
turn. Landscapes and Supports are ready immediately.

## Resources — the signature system

> Your pool of an element **equals the number of Landscapes of that element you
> control**, minus what you have spent this turn.

Control 2 Grove and 1 Cinder, and you have **2 Life and 1 Fire** to spend. The
pool refreshes completely at the start of your turn and does not carry over.

Three consequences worth stating, because they are the whole design:

- **Landscapes are free and limited to one per turn.** That is what bootstraps
  the economy and paces the game. Your curve is your land.
- **A Landscape played this turn is usable this turn.** It enters awake, so
  playing land always does something now, not next turn.
- **Costs are element-specific.** A 2-cost Life creature needs 2 Life; Fire
  cannot pay for it. Splashing a second element costs you lanes, and lanes are
  also where your creatures stand. That tension is the deckbuilding.

Because you hold at most four Landscapes, **no card costs more than 4.**

## Playing on

Every Creature and Support prints its land requirement:

> **Sproutling** · Creature · Life · **Play on: Grove**

If the lane's Landscape does not match, the card cannot go there. Selecting a
card lights every lane it can legally enter.

## Combat

- A ready creature attacks **straight across its own lane**.
- If the opposing lane holds a creature, the attacker deals its **Power** to that
  creature's **Health**. The defender does **not** strike back — it attacks on
  its own turn. One-way damage keeps a trade readable without a rulebook.
- If the opposing lane is **empty**, the damage hits the rival **Heart**.
- A creature reduced to 0 Health is discarded; the lane keeps its Landscape.

Reduce the rival Heart to 0 to win.

## Supports

A Support attaches to a lane and enhances what is there.

> **Herbalist Hut** · Support · Life · **Attach to: Grove**
> Creatures here heal 1 at end of turn.

Supports leave when their Landscape does.

## Fusion

Fusion is Pocket Arcana's signature spectacle. Two compatible creatures anywhere
in your lanes combine into a stronger one.

- Both sources must be yours and on the board.
- The result lands in the **first** source's lane; the other lane's creature
  leaves. Its Landscape and Support stay.
- The destination Landscape must match the result's element.
- Costs the recipe's cost in that element.
- The fused creature enters **ready**, because you have already paid two bodies
  for it.

## Commanders

Each Commander has one always-on **passive** and one **once-per-match** power.

**Mossy Mae — Life**
- *Verdant Care* (passive): at the end of your turn, each of your creatures
  standing on Grove heals 1.
- *Wild Spring* (once per match): draw 2 cards.

**Poppy Cinder — Fire**
- *Forge Heat* (passive): your creatures standing on Cinder have +1 Power.
- *Ember Rush* (once per match): deal 3 damage to one enemy creature, or to the
  rival Heart.

## Card types

| Type | Costs | Goes | Notes |
| --- | --- | --- | --- |
| Landscape | free, 1/turn | Landscape slot | generates 1 of its element |
| Creature | element | Creature slot | needs a matching Landscape |
| Support | element | Support slot | needs a matching Landscape |
| Spell | element | — | resolves and is discarded |

## Scope

Life/Grove and Fire/Cinder only. Water/Tidepool, Death/Gravebloom and the rest
wait until this reads well.

## Presentation

A tabletop, not a map. Lanes are visually distinct and themed by the landscape
laid in them. Cards are the pieces and stay the pieces: a creature may **animate
out of its card** to attack — the card anticipates, the creature climbs out,
travels, hits, and drops back in — but it never becomes a free-roaming sprite.
