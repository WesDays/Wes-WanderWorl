import 'package:flame_riverpod/flame_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'abilities.dart';
import 'clock_swipe.dart';
import 'game/combat_engine.dart';
import 'game/wanderworld_game.dart';
import 'state/combat_providers.dart';

/// How long a floating damage number travels across the screen before removal.
const Duration kFloatingDamageDuration = Duration(milliseconds: 1500);

/// Inset from the right edge for the rising boss-damage numbers, clearing the
/// ability-button columns that hug that edge.
const double kFloatingDamageRightInset = 150;

/// Inset from the left edge for the rising player-damage numbers, kept on the
/// opposite side from the boss-damage feed.
const double kFloatingDamageLeftInset = 24;

/// Geometry of one ability-point circle: diameter plus vertical padding on each
/// side. Used to lay out the circles and to float the effect badges above them.
const double kPointDiameter = 18;
const double kPointPadding = 4;

/// The abilities backing the two timed-effect badges.
final Ability _rendAbility = kAbilities.firstWhere((a) => a.appliesRend);
final Ability _buffAbility = kAbilities.firstWhere((a) => a.appliesBuff);

/// Hosts the Flame game and its HUD overlay. Combat state lives in the engine;
/// the HUD reads it through Riverpod, so this widget owns no combat state.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.onExitToMenu});

  /// Returns to the main menu, ending the current run.
  final VoidCallback onExitToMenu;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GlobalKey<RiverpodAwareGameWidgetState<WanderworldGame>> _gameKey =
      GlobalKey();
  late final WanderworldGame _game = WanderworldGame();

  @override
  Widget build(BuildContext context) {
    return RiverpodAwareGameWidget<WanderworldGame>(
      key: _gameKey,
      game: _game,
      overlayBuilderMap: {
        'hud': (context, game) =>
            _Hud(game: game, onExitToMenu: widget.onExitToMenu),
      },
      initialActiveOverlays: const ['hud'],
    );
  }
}

/// The whole HUD, laid out to mirror the pre-Flame design now that the app
/// renders natively in landscape (no `RotatedBox`): the resource gauge runs
/// across the top, the boss gauge across the bottom, and the ability buttons
/// stack in two columns hugging the left edge. Floating numbers drift through
/// the middle band over the Flame world.
class _Hud extends StatefulWidget {
  const _Hud({required this.game, required this.onExitToMenu});

  final WanderworldGame game;
  final VoidCallback onExitToMenu;

  @override
  State<_Hud> createState() => _HudState();
}

class _HudState extends State<_Hud> {
  bool _paused = false;

  // Pausing the Flame engine stops update(), which freezes the engine tick,
  // animations, and the published snapshot — i.e. all gameplay halts.
  void _pause() {
    widget.game.pauseEngine();
    setState(() => _paused = true);
  }

  void _resume() {
    widget.game.resumeEngine();
    setState(() => _paused = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          const Align(
            alignment: Alignment.topCenter,
            child: _BossHealthPanel(),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: _ResourcePanel(),
          ),
          const Align(
            alignment: Alignment.bottomLeft,
            child: _PlayerHealthPanel(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _AbilityBar(game: widget.game, onPause: _pause),
          ),
          const Positioned.fill(child: _FloatingDamageLayer()),
          Positioned.fill(
            child: _GameOverScreen(onExitToMenu: widget.onExitToMenu),
          ),
          if (_paused)
            Positioned.fill(
              child: _PauseMenu(
                onResume: _resume,
                onExitToMenu: widget.onExitToMenu,
              ),
            ),
        ],
      ),
    );
  }
}

/// Boss health gauge plus the running-DPS readout, running across the top.
class _BossHealthPanel extends ConsumerWidget {
  const _BossHealthPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(combatProvider.select((s) => s.bossHealth));
    final dps = ref.watch(combatProvider.select((s) => s.averageDps));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _BossHealthBar(value: health, max: kBossMaxHealth),
          const SizedBox(width: 8),
          _OutlinedNumber('${dps.round()} DPS'),
        ],
      ),
    );
  }
}

/// Resource gauge with the ability-point circles and timed-effect badges,
/// centred across the bottom edge. The points sit above the bar, left-aligned
/// to its start, leaving room to their right for the rend/buff badges.
class _ResourcePanel extends ConsumerWidget {
  const _ResourcePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resource = ref.watch(combatProvider.select((s) => s.resource));
    final regenProgress = ref.watch(combatProvider.select((s) => s.regenProgress));
    final free = ref.watch(combatProvider.select((s) => s.freeAbility));
    final points = ref.watch(combatProvider.select((s) => s.abilityPoints));
    final rendSeconds = ref.watch(combatProvider.select((s) => s.rendSeconds));
    final buffSeconds = ref.watch(combatProvider.select((s) => s.buffSeconds));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Points and active-effect badges share a row above the bar; the
          // badges trail to the right so they grow into the open space.
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AbilityPoints(filled: points, max: kMaxAbilityPoints),
              if (buffSeconds > 0) ...[
                const SizedBox(width: 8),
                _EffectIndicator(ability: _buffAbility, secondsLeft: buffSeconds),
              ],
              if (rendSeconds > 0) ...[
                const SizedBox(width: 8),
                _EffectIndicator(ability: _rendAbility, secondsLeft: rendSeconds),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _ResourceBar(
            value: resource,
            max: kMaxResource,
            regenProgress: regenProgress,
            free: free,
          ),
        ],
      ),
    );
  }
}

/// Player health gauge pinned to the bottom-left corner, independent of the
/// centred resource panel.
class _PlayerHealthPanel extends ConsumerWidget {
  const _PlayerHealthPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerHealth = ref.watch(combatProvider.select((s) => s.playerHealth));
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: _PlayerHealthBar(value: playerHealth, max: kPlayerMaxHealth),
    );
  }
}

/// The ability buttons: two upright columns (3 then 4) hugging the right edge,
/// dimmed while the global cooldown is in flight.
class _AbilityBar extends ConsumerWidget {
  const _AbilityBar({required this.game, required this.onPause});

  final WanderworldGame game;

  /// Opens the pause menu when the pause button is pressed.
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onCooldown = ref.watch(combatProvider.select((s) => s.onCooldown));
    final progress = ref.watch(combatProvider.select((s) => s.cooldownProgress));
    final points = ref.watch(combatProvider.select((s) => s.abilityPoints));

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Opacity(
        opacity: onCooldown ? 0.45 : 1.0,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 4-button column on the inside, 3-button column hugging the edge.
            _column(3, 7, onCooldown, progress, points),
            const SizedBox(width: 8),
            _column(0, 3, onCooldown, progress, points),
          ],
        ),
      ),
    );
  }

  Widget _column(int start, int end, bool onCooldown, double progress, int points) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = start; i < end; i++)
          if (kAbilities[i].opensPauseMenu)
            // The pause button is UI-only: it ignores the global cooldown and
            // never spends resource, so it stays live and shows no clock-swipe.
            _AbilityButton(
              ability: kAbilities[i],
              onPressed: onPause,
              onCooldown: false,
              cooldownProgress: 0,
            )
          else
            _AbilityButton(
              ability: kAbilities[i],
              onPressed: () => game.castAbility(i),
              onCooldown: onCooldown,
              cooldownProgress: progress,
              enabled: !kAbilities[i].requiresAbilityPoints || points > 0,
            ),
      ],
    );
  }
}

/// End-of-run landing page, shown once the fight ends — whether the boss dies
/// (win) or the player dies (loss). A single screen for both outcomes; its
/// button returns to the main menu. Run stats (biggest hit, total healing, …)
/// will surface here later.
class _GameOverScreen extends ConsumerWidget {
  const _GameOverScreen({required this.onExitToMenu});

  final VoidCallback onExitToMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bossDead = ref.watch(combatProvider.select((s) => s.bossDead));
    final playerDead = ref.watch(combatProvider.select((s) => s.playerDead));
    if (!bossDead && !playerDead) return const SizedBox.shrink();
    // The barrier swallows stray taps so the controls underneath (including the
    // UI-only pause button) stay inert once the run has ended.
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OutlinedNumber(
                playerDead ? 'Defeat' : 'Victory',
                fontSize: 40,
              ),
              const SizedBox(height: 24),
              // Run-summary stats will go here.
              FilledButton(
                onPressed: onExitToMenu,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Text('Main Menu', style: TextStyle(fontSize: 20)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal pause menu, shown while the engine is paused (see [_HudState]). The
/// barrier swallows stray taps so the controls underneath stay inert; Resume
/// unpauses, Main Menu ends the run.
class _PauseMenu extends StatelessWidget {
  const _PauseMenu({required this.onResume, required this.onExitToMenu});

  final VoidCallback onResume;
  final VoidCallback onExitToMenu;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _OutlinedNumber('Paused', fontSize: 40),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onResume,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Text('Resume', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onExitToMenu,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Text('Main Menu', style: TextStyle(fontSize: 20)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal resource gauge that fills from the left.
class _ResourceBar extends StatelessWidget {
  const _ResourceBar({
    required this.value,
    required this.max,
    required this.regenProgress,
    this.free = false,
  });

  final int value;
  final int max;

  /// Regen-cycle progress (0 at left, 1 at right) for the moving indicator.
  final double regenProgress;

  /// Whether the free-ability bonus is charged; highlights the bar when so.
  final bool free;

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 320,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              // Glow while the next ability is free.
              border: Border.all(
                color: free ? const Color(0xFFFFFF00) : Colors.white24,
                width: free ? 2 : 1,
              ),
              boxShadow: free
                  ? const [BoxShadow(color: Color(0xFFFFFF00), blurRadius: 10)]
                  : null,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: constraints.maxWidth * fraction,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFF00),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              },
            ),
          ),

          // Regen-timing indicator: a white bar sweeping the gauge over one
          // regen cycle, snapping back to the left when it restarts.
          Align(
            // x: -1 (left) at cycle start -> 1 (right) at cycle end.
            alignment: Alignment(-1 + 2 * regenProgress, 0),
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 1),
              ),
            ),
          ),

          _OutlinedNumber('$value'),
        ],
      ),
    );
  }
}

/// Horizontal boss health gauge that fills from the left, mirroring the
/// resource bar on the opposite edge.
class _BossHealthBar extends StatelessWidget {
  const _BossHealthBar({required this.value, required this.max});

  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 320,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: constraints.maxWidth * fraction,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              },
            ),
          ),
          _OutlinedNumber('$value'),
        ],
      ),
    );
  }
}

/// Horizontal player health gauge that fills from the left, styled like the
/// resource bar but green.
class _PlayerHealthBar extends StatelessWidget {
  const _PlayerHealthBar({required this.value, required this.max});

  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 150,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: constraints.maxWidth * fraction,
                    decoration: BoxDecoration(
                      color: const Color(0xFF43A047),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              },
            ),
          ),
          _OutlinedNumber('$value'),
        ],
      ),
    );
  }
}

/// Row of circles tracking ability points: [filled] solid, the rest empty.
class _AbilityPoints extends StatelessWidget {
  const _AbilityPoints({required this.filled, required this.max});

  final int filled;
  final int max;

  @override
  Widget build(BuildContext context) {
    // Filled circles shift colour as the pool nears full: yellow up to 3,
    // orange at 4, red at 5.
    final Color fillColor = switch (filled) {
      >= 5 => const Color(0xFFE53935),
      4 => const Color(0xFFFF7043),
      _ => const Color(0xFFFFFF00),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < max; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPointPadding),
            child: Container(
              width: kPointDiameter,
              height: kPointDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Left-to-right: the leftmost [filled] circles are solid.
                color: i < filled ? fillColor : Colors.black26,
                border: Border.all(color: Colors.white24),
              ),
            ),
          ),
      ],
    );
  }
}

/// Active-effect badge: an ability's icon with its seconds remaining on top.
class _EffectIndicator extends StatelessWidget {
  const _EffectIndicator({required this.ability, required this.secondsLeft});

  final Ability ability;
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ability.iconAsset != null
            ? Image.asset(
                ability.iconAsset!,
                width: 48,
                height: 48,
                color: ability.color,
                filterQuality: FilterQuality.medium,
              )
            : Icon(ability.icon, color: ability.color, size: 48),
        _OutlinedNumber('$secondsLeft'),
      ],
    );
  }
}

/// Widget-space floating damage feed. Visuals are unchanged from the original;
/// only the trigger moved — it listens to [floatingHitProvider] (fed by the
/// engine) and spawns one drifting badge per hit.
class _FloatingDamageLayer extends ConsumerStatefulWidget {
  const _FloatingDamageLayer();

  @override
  ConsumerState<_FloatingDamageLayer> createState() =>
      _FloatingDamageLayerState();
}

class _FloatingDamageLayerState extends ConsumerState<_FloatingDamageLayer>
    with TickerProviderStateMixin {
  final List<_FloatingDamage> _floaters = [];
  int _nextId = 0;

  void _spawn(FloatingHit hit) {
    final controller = AnimationController(
      vsync: this,
      duration: kFloatingDamageDuration,
    );
    final floater = _FloatingDamage(
      id: _nextId++,
      ability: hit.ability,
      amount: hit.amount,
      crit: hit.crit,
      onPlayer: hit.onPlayer,
      heal: hit.heal,
      controller: controller,
    );
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        setState(() => _floaters.remove(floater));
      }
    });
    setState(() => _floaters.add(floater));
    controller.forward();
  }

  @override
  void dispose() {
    for (final f in _floaters) {
      f.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Spawn a badge for every queued hit, then drain the queue. Draining keeps
    // each hit spawned exactly once regardless of how Riverpod batches the
    // emissions that filled it.
    ref.listen(floatingHitProvider, (prev, next) {
      if (next.isEmpty) return;
      for (final hit in next) {
        _spawn(hit);
      }
      ref.read(floatingHitProvider.notifier).clear();
    });

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final f in _floaters)
                AnimatedBuilder(
                  animation: f.controller,
                  builder: (context, child) {
                    final t = f.controller.value;
                    // Hold full opacity, then fade over the last third.
                    final opacity = t < 0.66 ? 1.0 : (1 - (t - 0.66) / 0.34);
                    return Positioned(
                      // Boss-damage parks just left of the ability buttons on
                      // the right edge; player-damage hugs the opposite edge.
                      left: f.onPlayer ? kFloatingDamageLeftInset : null,
                      right: f.onPlayer ? null : kFloatingDamageRightInset,
                      // Rise from near the bottom toward the top as it ages.
                      bottom: 40 + (height - 120) * t,
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: _FloatingDamageBadge(
                    ability: f.ability,
                    amount: f.amount,
                    crit: f.crit,
                    heal: f.heal,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One in-flight damage number: its source ability, the rolled amount, and the
/// controller driving its drift across the screen.
class _FloatingDamage {
  _FloatingDamage({
    required this.id,
    required this.ability,
    required this.amount,
    required this.crit,
    required this.onPlayer,
    required this.heal,
    required this.controller,
  });

  final int id;
  final Ability? ability;
  final int amount;
  final bool crit;

  /// Floats over the player (left) rather than the boss (right).
  final bool onPlayer;

  /// Renders as a green "+amount" restore instead of damage.
  final bool heal;
  final AnimationController controller;
}

/// A floating hit: the ability's icon next to its rolled damage. Crits read
/// larger and amber; heals read green with a leading "+".
class _FloatingDamageBadge extends StatelessWidget {
  const _FloatingDamageBadge({
    this.ability,
    required this.amount,
    this.crit = false,
    this.heal = false,
  });

  /// Source ability for the leading icon; null (player damage) shows no icon.
  final Ability? ability;
  final int amount;
  final bool crit;
  final bool heal;

  @override
  Widget build(BuildContext context) {
    final ability = this.ability;
    // Heals use the ability's own colour for its icon; damage tints by ability.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ability != null) ...[
          ability.iconAsset != null
              ? Image.asset(
                  ability.iconAsset!,
                  width: 22,
                  height: 22,
                  color: ability.color,
                  filterQuality: FilterQuality.medium,
                )
              : Icon(ability.icon, color: ability.color, size: 22),
          const SizedBox(width: 4),
        ],
        _OutlinedNumber(
          heal ? '+$amount' : '$amount',
          color: heal
              ? const Color(0xFF66BB6A)
              : (crit ? const Color(0xFFFFC107) : Colors.white),
          fontSize: crit ? 18 : 16,
        ),
      ],
    );
  }
}

/// White text with a black outline, drawn by stacking a stroked copy behind a
/// filled copy.
class _OutlinedNumber extends StatelessWidget {
  const _OutlinedNumber(this.text, {this.color = Colors.white, this.fontSize = 16});

  final String text;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.none,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = Colors.black,
          ),
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.none,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// One ability control: a circular icon button with the cooldown clock-swipe
/// overlaid while the global cooldown is in flight.
class _AbilityButton extends StatelessWidget {
  const _AbilityButton({
    required this.ability,
    required this.onPressed,
    required this.onCooldown,
    required this.cooldownProgress,
    this.enabled = true,
  });

  final Ability ability;
  final VoidCallback onPressed;
  final bool onCooldown;
  final double cooldownProgress;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: SizedBox(
          width: 50,
          height: 50,
          child: Material(
            color: ability.color,
            shape: const CircleBorder(),
            elevation: 4,
            child: Stack(
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? onPressed : null,
                  child: Center(
                    child: ability.iconAsset != null
                        ? Transform.translate(
                            offset: ability.iconAssetOffset,
                            child: Image.asset(
                              ability.iconAsset!,
                              width: ability.iconAssetSize,
                              height: ability.iconAssetSize,
                              color: Colors.white,
                              filterQuality: FilterQuality.medium,
                            ),
                          )
                        : Icon(ability.icon, color: Colors.white, size: 26),
                  ),
                ),

                // Cooldown clock-swipe; only painted while the cooldown runs.
                if (onCooldown)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipOval(
                        child: CustomPaint(
                          painter: ClockSwipePainter(cooldownProgress),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
