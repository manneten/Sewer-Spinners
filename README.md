# SEWER SPINS

> *A physics-based auto-battler roguelike set in the grimy depths of the sewer.*

You build a Frankenstein Beyblade from scavenged parts, throw it into a filthy arena, and watch it tear through three criminal factions — one brutal match at a time. Win 10 fights. Don't get knocked out. Keep your trophy.

---

## Gameplay Loop

```
Pay Scrap → Draft Chassis + 2 Limbs → Fight → Loot → Repeat
```

1. **Enter** — Pay 50 Scrap to enter a Run. You're dealt two random loadout cards. Pick one.
2. **Fight** — Your Beyblade auto-battles an enemy from one of three Sewer Factions.
3. **Loot** — Win a match, scavenge one of the enemy's limbs and swap it onto your blade.
4. **Pit Stop** — Every 3 wins, hit the Faction Shop: buy limbs, repair durability, splice a new part onto a broken slot.
5. **Survive** — 3 losses (Strikes) and the Run is over. Win 10 and your Beyblade becomes a permanent Lobby Trophy.

---

## The Three Sewer Factions

| Faction | Style | Threat |
|---|---|---|
| **Fat Rats** | Heavy bruiser, high mass | Slow but hits like a pipe |
| **Wiggly Wörm** | Featherlight speedster | Slippery, hard to pin down |
| **Croco Loco** | Mid-weight torque machine | Charges the arena center every 1.8s |

Beat enough faction members to unlock **Boss Fights** — rare chassis and limbs are on the line.

---

## Combat System

Combat is fully **physics-driven** — no scripted animations, no fake hits. Two RigidBody2D blades spin, collide, and fling each other around a bowl arena using real mass, torque, friction, and angular velocity.

### Hit System
- **Deflects** — standard contact, momentum exchange based on mass difference
- **Critical Hits** — high-speed impacts trigger bonus impulse; lightweight limbs bypass 50% of mass resistance (Mosquito Buff)
- **Super Spark** — every 5 deflections triggers a violent mutual fling, camera zoom, and 1 second of slow-motion
- **Limb Loss** — 20% chance on Super Sparks and special abilities; 1s slow-mo + red flash

### Ability Limbs

**Sewer Slapper** — Active, 4s cooldown
Freezes spin, extends the limb to 19.5× its resting length and delivers a 6500-force crunch. Triggers slow-mo and camera zoom on hit. 20% chance of ripping off an enemy limb.

**Sewer Harpoon** — Active, 6s cooldown
Fires a ghost projectile at 1200px/s. On contact it tethers both blades with a 3800-force pull for 4 seconds, then snaps them together for a 2800-impulse climax hit. Comes with its own slow-mo, super spark, and 20% limb loss roll.

**Sludge Sponge** — Passive
Drips oil puddles while spinning. Puddles slow enemies (high linear damp for 1.5s) and give the owner a +6 angular velocity burst on contact. Maximum 30 puddles globally.

**Fleshy Tongue** — Passive
On every chassis hit received, fires a +8 angular velocity burst and briefly retracts. Makes lightweight builds surprisingly resilient.

**Twisted Wrench** — Passive
All critical hits deal +15% bonus impulse.

---

## The Armory

### Chassis
From the featherlight **Bottle Cap** (2.5kg) to the immovable **Sewer King** (18kg). Each chassis has unique mass, torque, friction, and drag. The **Rusty Manhole** grants −25% ability cooldowns. The **Croco Jaw** packs a top-tier 22,000 base torque.

### Limbs
12 limbs across Common and rare tiers, each with individual mass, length multiplier, wobble intensity, and wall recoil penalties. Limbs have **3 durability** — after 3 wins they degrade into a **Broken Nub** (near-useless stub). Repair them at the Pit Stop or splice in a replacement.

---

## Arena & Visual Effects

### Arena Design
- Circular bowl physics arena with **4 C-shaped pocket corners** and hazard zones
- **Destructible side walls** — fail after exactly 3 hits; if no KO in 45 seconds all walls shatter simultaneously
- **Anti-AFK center repulsion** — blades don't stall in the middle
- **Abyss drain** at center — fall in and you're out

### Visual Effects
- **Film grain shader** — luminance-weighted, UV grid-snapped silver-halide grain with vignette. Full 70s security camera aesthetic.
- **Drop shadow & glow system** — each blade has a dark oval shadow plus 3-ring additive team-colored glow. Glow intensity pulses at 2.2Hz tied directly to current spin speed.
- **Sludge trails** — oil puddles with 4s fade lifetime
- **Camera shake** on hard hits; zoom + slow-mo on special events
- **Label jitter shader** — all UI text wobbles like it's hand-drawn and alive
- **Layered arena art** — 12-layer composited scene (background → floor shadows → floor art → geysers → pipes → wall shadows → corners → film grain overlay) for a 2.5D depth illusion
- **Rat crowd** — procedural spectator rats on the left and right arena rim; they jump on Super Sparks, flinch on limb damage, celebrate wins, droop on losses, and explode in a shower of blood if a blade flies out and hits them

### UI Screens
| Screen | Purpose |
|---|---|
| **GambleScreen** | Loadout draft — two paper cards, brainrot names, power ratings, faction rep |
| **PostMatchLoot** | Scavenge pile — pick one enemy limb to swap onto your blade |
| **ShopScreen** | Faction Pit Stop — buy, repair, or splice limbs |
| **BankruptScreen** | Run over — shown on 3rd Strike |

---

## Economy & Meta

- **Scrap** — primary currency. Earned from wins, spent on run entry and shop items.
- **Reputation** — earned per faction. High rep unlocks Boss Fights.
- **Trophies** — winning blades are preserved as Lobby Trophies.
- **Skill Points** *(in development)* — post-run upgrades to global stats: Starting RPM, Thickness, Bounciness, Oiliness.
- **Faction Loans / Bankruptcy** *(in development)* — default on a loan and lose your scrap, chassis, and trophies.

---

## Built With

- **Godot 4** — GDScript, RigidBody2D physics
- **Rive** *(planned)* — fluid UI animations
- **Hand-drawn art** — painted in MS Paint, sewer aesthetic throughout

---

*Three factions. Ten fights. One trophy. Don't lose the blade.*
