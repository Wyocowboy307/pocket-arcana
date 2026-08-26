# Pocket Arcana V2 — Card Language

## Goal

A player should identify **what a card is, where it goes and what it needs in under one second**.

Do not rely on rules paragraphs.

## Every card must communicate five things

1. **TYPE** — Realm / Creature / Place / Spell
2. **ELEMENT** — large crest + frame language
3. **COST** — Aether number/gems
4. **DESTINATION** — `PLAY ON` or `TARGET`
5. **PAYOFF** — one short effect sentence

## Layout hierarchy

Top left:
- large Aether cost

Top center:
- card name

Top/right crest:
- element icon

Under name:
- unmistakable type ribbon: `CREATURE`, `PLACE`, `SPELL`, `REALM`

Main middle:
- large art window

Directly below art:
- **PLAY ON: GROVE**
- or **TARGET: ENEMY CREATURE**
- or **BUILD: EMPTY REALM SLOT**

Bottom:
- maximum 1–2 short rules lines

Creature bottom corners:
- Attack gem
- Health gem

## Type silhouette

Type must read even in grayscale:
- Realm: wide organic frame / landscape notch
- Creature: rounded living frame
- Place: square architectural frame
- Spell: sharp/radiant frame

Element color is secondary reinforcement, not the only cue.

## Element language

Life:
- leaf crest
- vine corners
- green/gold glow
- growth particles

Fire:
- flame crest
- charred/forged corners
- ember orange/red
- spark particles

Future elements keep unique shape motifs, not just recolors.

## Selection behavior

Hover:
- card lifts 12–18 px
- scale ~1.15–1.3 depending hand density
- subtle tilt toward pointer
- frame glow
- nearby cards yield space

Click/drag:
- selected card lifts clearly above hand
- legal destinations become bright
- illegal destinations desaturate/dim
- destination ghost appears on hover
- release on legal destination commits
- release elsewhere returns card smoothly to hand

## Failure reasons

One sentence, closest to the target.

Examples:
- `Needs a Grove`
- `Build land here first`
- `Creature slot occupied`
- `Place slot occupied`
- `Need 2 more Aether`
- `Target an enemy creature`

Never show engine terminology to the player.

## Card draw presentation

Drawing must be visible.

Sequence:
1. deck pulses;
2. top card rises;
3. card back arcs toward hand;
4. flips during travel or just before landing;
5. new card briefly enlarges;
6. hand refans.

First tutorial draws pause long enough to explain the card.

## Art rule

No production card should show a plain white/empty rectangle as the dominant visual.

If illustration is missing, use a deliberate element sigil/texture fallback that looks intentional.

Commander/Sanctuary art also needs the same finished visual language; no debug plates.

## Keyword budget

A beginner card should have at most:
- one main ability;
- one keyword.

Complex cards can exist later, but the Life/Fire tutorial decks must teach one concept at a time.

## Tooltips

Tooltips explain keywords, not basic placement.

Basic placement is always printed directly on the card.
