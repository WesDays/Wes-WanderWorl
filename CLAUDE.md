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
  A **global cooldown (1.5s)** gates all abilities — pressing any one locks all of
  them briefly. (Per-ability cooldowns / costs may come later.)
- **Orientation:** designed for a phone held sideways in **landscape**. Ability
  controls hug a screen edge, rotated so their bottoms face the edge.

## Current state

Early prototype. The ability bar, the global cooldown, and its visual feedback
exist. Combat, the monster/boss, health/damage, the side-scroller world, death,
and the talent tree are **not built yet**.

What works today:
- 7 ability buttons in a vertically-centred column on the **right edge**, each
  rotated 90° (`RotatedBox(quarterTurns: 3)`) so its bottom faces the edge.
- Pressing a button shows that ability's icon + name in the screen centre for ~1s.
- Pressing any button starts a 1.5s **global cooldown** during which all presses
  are ignored; a darkened **clock-swipe** dial sweeps/empties in the centre and the
  button bar dims until the cooldown ends.

## Code map

- `lib/main.dart` — app entry; locks portrait orientation, dark theme, hosts `GameScreen`.
- `lib/game_screen.dart` — the play screen: ability bar, press popup, cooldown logic.
  - `kCooldown` (1.5s global cooldown) and `kIndicatorVisible` (1s popup) live here.
  - Cooldown is driven by a single `AnimationController`; `_onAbilityPressed`
    early-returns while it is animating.
  - **Crits:** `_dealDamage` is the single funnel for all damage (instant hits and
    Rend ticks). Each call independently rolls `kCritChance` (40%); a crit multiplies
    the rolled amount by `kCritMultiplier` (2×), after the ±10% variance. It returns
    whether it critted so callers can react — Attack grants 2 ability points on a
    crit instead of 1. Crit floating numbers render larger/amber with a trailing `!`.
- `lib/abilities.dart` — `Ability` model + `kAbilities` (the 7 abilities: presentation
  data only for now — name/icon/colour). Add gameplay stats here as combat lands.
- `lib/clock_swipe.dart` — `ClockSwipePainter`, the darkened cooldown dial.

## Stack & conventions

- Flutter, Dart SDK `^3.12.1`. Material 3, dark theme.
- Dependencies: `flutter_riverpod` (state management — not wired up yet), `uuid`.
- Lints via `flutter_lints` (see `analysis_options.yaml`). Keep `flutter analyze` clean.
- Not a git repository yet.

## Commands

- Run: `flutter run`
- Analyze: `flutter analyze`
- Test: `flutter test`

## Likely next steps (not yet implemented)

- Player & boss entities with health; damage exchange and a basic combat tick.
- Side-scrolling world / encounter flow and a win/lose (death) state.
- Talent tree for post-encounter upgrades; have abilities read real stats.
- Decide the role of Riverpod for game/combat state.
