# wes_wanderworl

A mobile (Flutter) game. The player character fights monsters in a side-scrolling
brawler; defeating a boss lets the player advance and spend upgrades in a talent tree.


## Code Comments
- Keep comments short and to the point.
- Comments explain code decisions only (the "why" behind the implementation)

## Game vision

- **Core loop:** side-scroller where the player fights a monster/boss. The boss
  fights back and damages the player. Both trade damage until one dies.
  - Player dies -> run ends (death / retry).
  - Boss dies -> player **moves on** to the next encounter.
- **Progression:** advancing earns small **upgrades** chosen from a **talent tree**.
  Upgrades are incremental ("small"), so power grows gradually across encounters.
- **Combat input:** the player has **7 abilities**, triggered by on-screen buttons.
  A **global cooldown** gates all abilities — pressing any one locks all of them
  briefly (currently `kCooldown` = 1.0s). (Per-ability cooldowns / costs may come later.)
- **Orientation:** designed for a phone held sideways in **landscape**. The app is
  locked to landscape and the HUD is drawn upright (no rotation hacks): ability
  controls along the bottom, gauges hugging the left/right edges.

## Current state

Combat runs on a **Flame** game engine that is the single source of truth; the
Flutter HUD is a read-only view driven off the engine through Riverpod. The
side-scroller world renders a **player** and a **boss** as Flame components with
animation state machines (placeholder art for now). Player health/death, the
talent tree, and side-scrolling movement between encounters are **not built yet**.

What works today:
- App locked to **landscape**; the HUD is upright (no `RotatedBox` rotations).
- A Flame world (`WanderworldGame`) renders the player + boss with
  `SpriteAnimationGroupComponent` state machines (idle/attack/hit/death), using
  runtime-generated **placeholder** sprites until real sheets land.
- 7 ability buttons along the bottom; pressing one routes input to the engine,
  which spends resource, deals damage, and triggers the player attack + boss hit
  animations. Boss health, resource, ability points, DPS, and rend/buff timers all
  update from engine state.
- Pressing any button starts the **global cooldown** during which all presses are
  ignored; a darkened **clock-swipe** dial sweeps/empties on each button and the
  bar dims until the cooldown ends.
- Floating damage numbers drift across the top (widget-space; triggered by engine
  hit events). The app boots to a **main menu**; Start launches a run, and when
  the fight ends (boss or player at 0) a single **game-over** landing page offers
  a button back to the menu (where run stats will surface later).

## Code map

- `lib/main.dart` — app entry; locks **landscape**, wraps the app in `ProviderScope`,
  dark theme. An `_AppShell` switches between the menu and an active run; each run
  mounts a fresh `GameScreen` (fresh game/engine), so no reset plumbing is needed.
- `lib/main_menu_screen.dart` — `MainMenuScreen`, the landing page shown on launch
  and returned to when a run ends; its Start button begins a new run. Future
  talents/stats areas will hang off here.
- `lib/game/combat_engine.dart` — **the source of truth.** `CombatEngine` owns all
  combat state and rules with no Flutter view concerns; advanced by `tick(dt)`,
  mutated by `castAbility(index)`. Publishes an immutable `CombatSnapshot` for the
  HUD and a queue of `CombatEvent`s (`HitEvent`/`CastEvent`/`BossDiedEvent`) drained
  each frame. **All gameplay constants live here** (`kCooldown`, `kCritChance`, …).
  - **Crits:** `_dealDamage` is the single funnel for all damage (instant hits and
    Rend ticks). Each call rolls `kCritChance` (40%); a crit multiplies the rolled
    amount by `kCritMultiplier` (2×) after ±10% variance, and returns whether it
    critted — Attack grants 2 ability points on a crit instead of 1.
  - Real-time loops (cooldown, regen, rend ticks, buff countdown, free-ability roll)
    are `tick(dt)` accumulators — no `Timer`/`AnimationController` in the engine.
- `lib/game/wanderworld_game.dart` — `WanderworldGame` (`FlameGame` +
  `RiverpodGameMixin`). Owns the engine and world; each frame ticks the engine,
  publishes the snapshot to `combatProvider`, and routes drained events to the
  player/boss animations and `floatingHitProvider`. `castAbility` is the HUD's
  input entry point; `resetCombat` restarts the fight in place (currently unused —
  runs start fresh via a new `GameScreen` — but kept for a future Retry).
- `lib/game/player_component.dart`, `lib/game/boss_component.dart` —
  `SpriteAnimationGroupComponent` state machines (idle/attack/hit/death). One-shot
  states fall back to idle on completion.
- `lib/game/placeholder_sprites.dart` — generates solid-colour `SpriteAnimation`
  frames at runtime; swap for `SpriteSheet`-backed art when real sheets exist.
- `lib/state/combat_providers.dart` — `combatProvider` (engine writes the snapshot,
  HUD reads slices via `select`) and `floatingHitProvider` (engine→floating feed).
- `lib/game_screen.dart` — hosts the game via `RiverpodAwareGameWidget` with the HUD
  as a Flame overlay. HUD pieces are `Consumer`s watching `combatProvider` slices;
  buttons call `game.castAbility`. UI-only constants (floater duration, ability-point
  geometry) live here. Crit floating numbers render larger/amber.
- `lib/abilities.dart` — `Ability` model + `kAbilities` (the 7 abilities). Already
  carries the gameplay stats the engine reads (`cost`, `damageFor`, `appliesRend`, …).
- `lib/clock_swipe.dart` — `ClockSwipePainter`, the darkened cooldown dial (fed the
  engine's `cooldownProgress`).

## Stack & conventions

- Flutter, Dart SDK `^3.12.1`. Material 3, dark theme.
- Dependencies: `flame` (game engine/loop, components, sprite animation),
  `flame_riverpod` (bridges the game and HUD into one `ProviderScope`),
  `flutter_riverpod` (HUD state), `uuid`.
- Architecture: the **engine is the source of truth**; the HUD only reads engine
  state via Riverpod and sends input back through the game. Keep combat logic in
  `CombatEngine`, not in widgets.
- Lints via `flutter_lints` (see `analysis_options.yaml`). Keep `flutter analyze` clean.
- Git repo with an `origin` on GitHub (`WesDays/Wes-WanderWorl`).

## Commands

- Run: `flutter run`
- Analyze: `flutter analyze`
- Test: `flutter test`

## Likely next steps (not yet implemented)

- Replace placeholder sprites with real `SpriteSheet`-backed art for player/boss.
- Player **health** + the boss fighting back; a win/lose (death) state.
- Side-scrolling movement / encounter flow between bosses (camera + world).
- Talent tree for post-encounter upgrades; have abilities read upgraded stats.
