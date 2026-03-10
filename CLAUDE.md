# SEWER SPINS - PROJECT MANIFESTO

## Core Identity
A physics-based, auto-battler roguelike set in a gritty, hand-drawn sewer. The player manages a customized "Frankenstein" Beyblade to win a 10-match "Run" against 3 Sewer Factions (Fat Rat, Wiggly Wörm, Croco Loco).

## The Roguelike Loop (The "Run")
1. **The Entry:** Player pays Scrap to get a random Chassis + 2 Limbs.
2. **The Gulag (Combat):** Player's Beyblade auto-battles AI opponents.
3. **The Goal:** Win 10 battles to claim tournament victory and keep the Beyblade as a Lobby Trophy.
4. **The Stakes:** 3 Losses (Strikes) equals a Knockout/Run Over.
5. **The Degradation:** Limbs break after 3 fights.
6. **The Loot:** After a win, the player loots 1 random limb from the defeated enemy to swap onto their Beyblade.

## Meta-Progression & Economy
* **Scrap:** Primary currency. Used to start runs, buy shop items, or mutate limbs.
* **Reputation & Factions:** Beating faction members unlocks Boss Fights for rare chassis/limbs.
* **Skill Points:** Earned post-run to upgrade global stats (Starting RPM, Thickness, Bounciness, Oilyness).
* **Bankruptcy:** If a player defaults on a Faction Loan, they lose their scrap, active chassis, and previously won Trophies.

## Visuals & Vibe
* **Palette:** Gritty, dark greens, greys, and blacks. "Sewer Sludge" aesthetic.
* **Art Style:** Hand-drawn in Paint, animated in Rive (fluid, fleshy, and mechanical).
* **UI:** Creepy, alive, ink-bleeding text.

## Godot Guidelines
* Use GDScript.
* Rely on physics-based interactions (RigidBody2D, center_of_mass offsets, angular_damp) over hardcoded animations for combat.
* Keep systems modular (e.g., RunManager, LimbManager, FactionManager).

---

## Implementation Status

### Done

**Screens & Flow**
* **GambleScreen** — loadout draft with two paper cards, brainrot names, scouting stats, power rating, faction rep HUD, float tween, jitter shader, flash/fade transitions
* **SewerArena** — physics combat, 3 factions (Fat Rats, Wiggly Worm, Croco Loco), camera shake, anti-AFK center repulsion, boss fight hook, run HUD (wins/strikes/faction)
* **PostMatchLoot** — scavenge pile screen, swap limb to left/right arm, skip with quips, spark/oil/grime particles
* **ShopScreen** — Faction Pit Stop (after wins 3, 6, 9): buy limbs, repair durability, splice a shop limb onto a Broken Nub slot
* **BankruptScreen** — shown on 3rd strike (run over)

**Managers & Systems**
* **RunManager** — win/loss counting, scrap reward, limb durability deduction, Broken Nub replacement, freshness labels/colors, pit stop scheduling
* **FactionManager** — reputation tracking per faction, boss eligibility check
* **SaveManager** — save/load/reset, trophy list
* **ShopManager** — shop inventory generation
* **Events** — full event bus: `match_ended`, `scrap_changed`, `run_completed`, `run_failed`, `open_shop`, `limb_damaged`, `part_spliced`, `part_repaired`, `reputation_changed`, `super_spark`, `set_slow_mo`, `reset_time`
* **Resource types** — ChassisData, LimbData, FactionData, PartData

**Arena Scripts**
`BowlWall`, `CirclePolygon`, `ArenaGravity`, `MutationStation`, `Abyss`, `BouncePad`, `PocketWall`, `WallSegment`, `Drain`

**Physics Scripts**
* `SpinController.gd` — spin/torque, `max_angular_velocity`, `team_color` @export
* `LimbManager.gd` — limb attachment, RPM stability bar (green→red, denominator = `max_angular_velocity`), ability lifecycle

**Ability System**
* `LimbAbility.gd` — base class; `passthrough_hits: bool`, `initialize()` / `on_teardown()` lifecycle
* `SlapperAbility.gd` — active: fires every 4s, freezes spin, snaps to 19.5× reach, 6500 impulse crunch, 20% limb loss chance; shapecast uses full stretched length from frame 1
* `HarpoonAbility.gd` — active: fires every 6s, launches ghost projectile (1200 px/s, max 650px), locks on within 40px, tethers for 4s with 3800 pull force per step, climax snaps both beys (2800 impulse each), 0.12s real-time delay before VFX/slow-mo fires
* `SludgeSpongeAbility.gd` — passive: drips puddle every 0.15s if angular_velocity > 15; max 30 global puddles; `on_teardown()` cleans owned puddles

**Effects**
* `SludgeTrail.gd` — Area2D puddle, 4s life (fades at 3s), 30-puddle global static cap; enemy hit: `linear_damp = 7.0` for 1.5s; owner hit: `angular_velocity += 6.0`
* `BeyDropShadow.gd` — dark oval shadow (rim + core) + 3-ring additive team-colored glow; glow pulses at 2.2Hz, intensity = `angular_velocity / max_angular_velocity` (mirrors stability bar)
* `film_grain.gdshader` — SCREEN_TEXTURE luminance-weighted multiplicative grain; UV grid-snapped for silver-halide clumping; vignette gated by `vignette_power` parameter (0 = fully off)

**Physics & Combat Polish**
* **Super Spark System** — every 5 deflections triggers violent fling, camera zoom, 1s perceived slow-mo
* **Mosquito Buff** — small/light limbs bypass 50% of target mass resistance on Critical Hits
* **Limb Loss Drama** — 1s slow-mo + red-flash on limb loss (20% chance on Super Spark or Harpoon snap)
* **Strategic Arena Geometry** — 4 C-shaped pocket corners with hazard zones
* **Fragile Walls** — destructible side walls fail after exactly 3 hits
* **Enemy Randomization** — 25% per limb slot to get a rare (Slapper/Harpoon/Sponge); post-loss clears `vs_enemy_faction_id` for full re-randomization next match
* **Bulletproof Camera Reset** — `force_camera_reset()` hard-sets zoom+offset before tweening; called at end of Super Spark, Croco Lunge, and Sewer Slap

**Sewer Den Art Layer System** (`_setup_art_layers()` in SewerArena)
All sprites world-scaled by `(vp_size / tex_size) / _base_zoom` to fill screen at camera zoom 0.5.

| Z-Index | File | Notes |
|---|---|---|
| −100 | `01_arena_bg.png` | Base background |
| −90 | `02_arena_shadows.png` | Pre-baked floor shadows |
| −80 | `03_arena_floor.png` | Main floor art |
| −75 | `02.1_arena_brighten.png` | BLEND_MODE_ADD brightening layer |
| −70 | `04_arena_floor_shadow.png` | Secondary floor depth |
| −60 | `06_corner_zones.png` | Pocket corner highlights |
| −30 | `05_arena_walls.png` | Walls above beys (z=-30) for 2.5D depth illusion |
| Layer 128 | Film grain ColorRect | Over entire composited scene |

**Shaders**
* `label_jitter.gdshader` — wobble shader on labels throughout UI
* `film_grain.gdshader` — gritty 70s security camera effect on full scene

### TODO (Immediate Roadmap)
* **Trophy Gallery Scene** — shelf/hall scene to visualize `SaveManager.trophies`
* **Boss Resources** — `.tres` files needed for: The Rat King (Heavy/Tank), Worm Mother (Segmented/Wobbly), Croco Prime (High Torque/Armored); `chassis_sewer_king.tres` and `chassis_worm_queen.tres` exist but boss flow not wired
* **Mutation Logic** — Yellow Pocket (MutationStation) needs a specific "Sewer Trash" mutation pool
* **BeyAI.gd** — implemented: Serpentine Flank (Worm), Death Lunge (Croco), Scavenger Pile (Rats); future: difficulty scaling, boss-specific overrides
* **ResultScreen** — file exists (`scripts/ui/ResultScreen.gd`), end-of-run trophy presentation not confirmed wired
* **Skill Points system** — post-run upgrades (Starting RPM, Thickness, Bounciness, Oilyness) designed but not implemented
* **Faction Loans / Bankruptcy from debt** — "default on loan → lose trophies" designed but not implemented (BankruptScreen only triggers on 3 strikes currently)
* **Rive animations** — all UI is plain Labels/Buttons; Rive is a future styling pass
* **Lobby Trophy display** — trophies saved but no lobby/display scene exists

---

## Sewer Armory

> Update this table whenever a limb is added or stats change. Stats confirmed from `.tres` files.

### Chassis

| Chassis | File | Mass | Torque | Friction | Drag | Passive | Notes |
|---|---|---|---|---|---|---|---|
| **Bottle Cap** | `chassis_bottle_cap` | 2.5 | 18000 | 0.18 | 0.025 | — | Featherlight speed demon; loses mass fights but outruns heavies |
| **Plastic Lid** | `chassis_plastic_lid` | 3.5 | 15000 | 0.22 | 0.03 | — | Light, fast — reliable starter option |
| **Grease Trap** | `chassis_grease_trap` | 6.0 | 19000 | 0.30 | 0.028 | — | Mid-weight all-rounder; solid torque without heavy-mass penalties |
| **Cast Iron Lid** | `chassis_cast_iron_lid` | 8.5 | 14000 | 0.50 | 0.038 | — | Sturdy mid-heavy; high friction anchor |
| **Rusty Manhole** | `chassis_rusty_manhole` | 10.0 | 12000 | 0.65 | 0.04 | **−25% ability cooldowns** | Heavy bruiser; passive rewards active-ability limbs |
| **Croco Jaw** | `chassis_croco_jaw` | 11.0 | ~~28000~~ **22000** | 0.55 | 0.03 | — | High-torque medium-heavy; v4: torque toned down |
| **Worm Queen** | `chassis_worm_queen` | 1.8 | 26000 | 0.08 | 0.01 | — | Ultra-light speed demon *(boss chassis)* |
| **Sewer King** | `chassis_sewer_king` | 18.0 | 10000 | 0.90 | 0.06 | — | Maximum mass tank *(boss chassis)* |

### Limbs

| Limb | File | Mass | Length | Wobble | Drag | Tier | Price | Special |
|---|---|---|---|---|---|---|---|---|
| **Lead Pipe** | `limb_lead_pipe` | ~~4.0~~ **3.6** | 1.2× | 1.0 | — | 1 – Common | 30 | Solid baseline heavy hitter |
| **Fleshy Tongue** | `limb_fleshy_tongue` | 1.5 | 0.8× | 2.4 | 0.55 | 1 – Common | 30 | **Passive ability**: on chassis hit → +8 av burst + limb retracts briefly |
| **Ethereal Vapor** | `limb_ethereal_vapor` | 0.8 | 1.0× | 3.5 | ~~0.75~~ **0.45** | 1 – Common | 30 | Ultra-light; mass-bypass on crits (Mosquito Buff). *v4: drag reduced* |
| **Rat Fang** | `limb_rat_fang` | ~~3.5~~ **3.15** | 1.15× | 1.8 | — | 1 – Common | 30 | `wall_recoil_penalty 1.2×` |
| **Rusty Saw** | `limb_rusty_saw` | 4.5 | 1.0× | 1.8 | — | 1 – Common | 30 | `wall_recoil_penalty` ~~2.0×~~ **1.6×** — wall contact is brutal. *v4: penalty reduced* |
| **Sewer Bone** | `limb_sewer_bone` | 2.2 | 0.9× | 0.8 | — | 1 – Common | 30 | `wall_recoil_penalty 0.5×` — shrugs off wall hits |
| **Twisted Wrench** | `limb_twisted_wrench` | 2.5 | 1.1× | 1.3 | — | 1 – Common | 30 | **Passive**: `crit_impulse_bonus +15%` — all crits hit harder |
| **Croco Tail** | `limb_croco_tail` | ~~3.8~~ **3.42** | 1.2× | 1.5 | — | 1 – Common | 30 | `wall_recoil_penalty 1.5×` |
| **Sewer Harpoon** | `limb_sewer_harpoon` | 1.2 | 1.0× | 1.5 | — | 1 – Common | 30 | **Active**: every 6s — ghost projectile (1200px/s, 650px), tethers on hit (pull force/step, 4s), climax snaps both beys (impulse each), 20% limb loss chance |
| **Sludge Sponge** | `limb_sludge_sponge` | 2.0 | 1.0× | 2.5 | — | 1 – Common | 10 | **Passive**: drips puddle every 0.15s (av>15). Puddles: slow enemies (damp 7.0/1.5s), boost owner (+6 av). 30 global cap, 4s life |
| **Sewer Slapper** | `limb_sewer_slapper` | 0.9 | 0.55× | 1.5 | — | **1 (TESTING)** | **10 (TESTING)** | **Active**: every 4s — stops spin, extends to 19.5× for 6500 crunch impulse + 1s slow-mo + camera zoom; 20% limb loss |
| **Broken Nub** | `limb_broken_nub` | 0.3 | 0.28× | 6.5 | — | — (not in shop) | — | Auto-replaces any limb when durability hits 0; near-useless stub |

*Enemy rare pool (25% per slot): Sewer Harpoon, Sludge Sponge, Sewer Slapper.*

### Balance Changelog

| Version | Change | Affected |
|---|---|---|
| v2 | **Heavyweight Diet** — −10% mass on Lead Pipe (4.0→3.6), Rat Fang (3.5→3.15), Croco Tail (3.8→3.42) | Heavy-tier limbs |
| v2 | **Go-Go-Gadget Slapper** — `SLAPPER_STRETCH_MULT` 3→15 (initial buff) | Sewer Slapper |
| v2 | **Bulletproof Camera Reset** — `force_camera_reset()` called at end of Super Spark, Croco Lunge, Sewer Slap | All special events |
| v3 | **Slapper Extended** — `SLAPPER_STRETCH_MULT` 15→19.5 | Sewer Slapper |
| v3 | **Harpoon Rarity** — tier 2/60 scrap → tier 1/30 scrap for testing | Sewer Harpoon |
| v3 | **Stability Bar Fix** — denominator changed from `target_rpm` to `max_angular_velocity`; bar now reads 100% at peak spin | LimbManager RPM bar |
| v3 | **Vignette Fix** — `vign * 0.60` → `vign * vignette_power * 0.15`; power=0 now fully disables corner darkening | film_grain.gdshader |
| v3 | **Glow Boost** — `GLOW_PEAK_ALPHAS` raised to [0.45, 0.75, 1.00]; glow strength now tied to stability ratio (`av / max_angular_velocity`) | BeyDropShadow |
| v4 | **Crit Bump** — `CRIT_HIT_IMPULSE` +15%, `SUPER_SPARK_FLING_FORCE` +25% | LimbManager |
| v4 | **Wall Splat Gate** — `WALL_SPLAT_SPEED` 700→1200 | SpinController |
| v4 | **Croco Jaw Nerf** — `base_torque` 28000→22000 | Croco Jaw chassis |
| v4 | **Manhole Passive** — `cooldown_reduction 0.25` (−25% ability cooldowns) | Rusty Manhole chassis |
| v4 | **Bone Wall Shrug** — `wall_recoil_penalty 0.5` (half normal wall loss) | Sewer Bone |
| v4 | **Vapor Speed** — `drag 0.75→0.45` | Ethereal Vapor |
| v4 | **Saw Mercy** — `wall_recoil_penalty 2.0→1.6` | Rusty Saw |
| v4 | **Twisted Wrench Passive** — `crit_impulse_bonus 0.15` (+15% crit damage) | Twisted Wrench |
| v4 | **Tongue Whip Ability** — on-hit: +8 av burst + retract animation | Fleshy Tongue |
| v4 | **Grease Trap Added** — new 6kg mid-weight chassis (torque 19000, friction 0.30) | New chassis |
