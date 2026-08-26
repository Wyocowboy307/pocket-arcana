# Pocket Arcana V2 — Animation Choreography

## Principle

Every important action must read as:

**anticipation -> action/travel -> impact -> result -> settle**

Particles by themselves are not an animation.

The player should understand what caused the number/state change even with sound off.

## Global timing language

Small action: ~0.25–0.45 s.
Standard play: ~0.45–0.8 s.
Big summon/fusion/victory: ~0.9–1.6 s.

Use brief hit-stop (~50–100 ms) on strong impacts.

Never make routine turns painfully slow; allow queued animations to speed slightly after repeated actions.

## Card play

1. selected card rises;
2. hand parts around it;
3. legal target pulses;
4. card travels toward destination in an arc;
5. destination reacts before resolution;
6. card transforms into the resulting world object/effect;
7. hand refans.

## Realm / Land play

### Life
- card lands flat;
- green rune circle races outward;
- roots/vines crawl from center;
- grass patches pop;
- flowers/leaves appear;
- small tree/landmark silhouettes rise where art supports it;
- Aether leaf ignites.

### Fire
- card descends with ember trail;
- edge flashes orange;
- char spreads outward;
- cracks pulse;
- smoke puff;
- sparks rise;
- Aether flame ignites.

The player must visibly see the board become different.

## Creature summon

1. creature card lands over compatible landscape;
2. frame collapses inward into element portal;
3. creature silhouette appears small;
4. squash/stretch/pop to final scale;
5. contact shadow settles;
6. element motes dissipate;
7. new unit shows a short `new/summoning` state if it cannot attack yet.

## Place / building

1. card hits Place slot;
2. foundation/runes mark the ground;
3. structure pieces rise/build in 2–4 beats;
4. final roof/banner/effect clicks in;
5. passive aura briefly demonstrates what the Place affects.

## Melee attack

Styles are data-driven by creature archetype.

Standard sequence:
1. attacker crouches/rears back;
2. small backwards wind-up;
3. fast lunge toward center/opposing slot;
4. 1–2 frame hit-stop;
5. defender recoils + hit flash;
6. damage number appears **after impact**;
7. death resolves if needed;
8. attacker returns and settles.

Attacker should travel enough to read but normally returns to its own landscape.

## Attack archetypes

Small beast:
- hop/headbutt

Horned animal:
- paw ground -> charge

Heavy creature:
- rear -> slam, larger screen shake

Flying creature:
- lift -> swoop arc -> return

Caster:
- raise hands/staff -> projectile -> target recoil

Dragon:
- inhale/neck pullback -> breath cone/projectile -> target burn -> wing/body settle

A dragon must not look like a Sproutling with a larger scale value.

## Heart attack

When opposing lane is empty:
1. attack lane highlights toward enemy Sanctuary;
2. creature performs its attack style toward center;
3. projectile/lunge energy continues to Heart;
4. Heart/Sanctuary physically shakes/flashes/cracks;
5. large damage number;
6. Heart bar drains after impact;
7. attacker returns.

## Damage / death

Damage:
- directional recoil
- tiny flash
- health pip drains after hit

Death:
- do not vanish before hit;
- hold final pose for a beat;
- element-specific dissolve/burst;
- card/shard travels toward discard indicator where readable.

## Spell

Spell card temporarily becomes presentation focus.

Examples:
- healing: green ribbon travels from card to target, petals rise, health increases last;
- fire damage: ember bolt travels, impact burst, target recoils, damage resolves;
- buff: rune wraps target, stats pulse upward.

No invisible immediate stat change.

## Fusion / combine

This is a signature spectacle.

1. valid pair receives linked rune;
2. activate Fusion;
3. board darkens slightly;
4. both creatures lift from landscapes;
5. ribbons in their element colors connect them;
6. creatures orbit/spiral together;
7. silhouettes compress into bright core;
8. flash / impact ring;
9. fused creature drops onto chosen source land;
10. heavy landing, particles and name reveal;
11. freed lane visibly opens.

Big fusion should feel like getting a rare summon in an animated show.

## Commander activation

Commander portrait/avatar steps forward or enlarges;
- unique signature flourish;
- target path/effect visible;
- result after impact;
- Commander returns.

## Victory

Heart reaches 0:
- final hit gets extra hit-stop;
- Sanctuary reacts visibly;
- camera/board pause;
- victor Commander celebration;
- result overlay after the action finishes, never before.

## Technical rule

Simulation commits result first and emits an event payload containing source, target, values and presentation tags.

Animation timeline consumes the event. It never decides damage, death or legality.
