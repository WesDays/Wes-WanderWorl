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

/// Geometry of one ability-point circle: diameter plus vertical padding on each
/// side. Used to lay out the circles and to float the effect badges above them.
const double kPointDiameter = 18;
const double kPointPadding = 4;

/// Total height of the ability-point column, so badges park just above it.
const double kAbilityPointsHeight =
    kMaxAbilityPoints * (kPointDiameter + 2 * kPointPadding);

/// The abilities backing the two timed-effect badges.
final Ability _rendAbility = kAbilities.firstWhere((a) => a.appliesRend);
final Ability _buffAbility = kAbilities.firstWhere((a) => a.appliesBuff);

/// Hosts the Flame game and its HUD overlay. Combat state lives in the engine;
/// the HUD reads it through Riverpod, so this widget owns no combat state.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

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
      overlayBuilderMap: {'hud': (context, game) => _Hud(game: game)},
      initialActiveOverlays: const ['hud'],
    );
  }
}

/// The whole HUD, laid out for landscape: boss gauge on the left, resource gauge
/// on the right, ability buttons along the bottom, floating numbers up top.
class _Hud extends StatelessWidget {
  const _Hud({required this.game});

  final WanderworldGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          const Align(alignment: Alignment.centerLeft, child: _BossHealthPanel()),
          const Align(alignment: Alignment.centerRight, child: _ResourcePanel()),
          Align(alignment: Alignment.bottomCenter, child: _AbilityBar(game: game)),
          const Positioned.fill(child: _FloatingDamageLayer()),
          Positioned.fill(child: _ResetOverlay(game: game)),
        ],
      ),
    );
  }
}

/// Boss health gauge plus the running-DPS readout, hugging the left edge.
class _BossHealthPanel extends ConsumerWidget {
  const _BossHealthPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(combatProvider.select((s) => s.bossHealth));
    final dps = ref.watch(combatProvider.select((s) => s.averageDps));
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
/// hugging the right edge.
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
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Badges float above the points via a Stack so showing one never
          // shifts the circles.
          Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              _AbilityPoints(filled: points, max: kMaxAbilityPoints),
              if (rendSeconds > 0 || buffSeconds > 0)
                Positioned(
                  bottom: kAbilityPointsHeight + 8,
                  child: Transform.translate(
                    offset: const Offset(-12, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (buffSeconds > 0)
                          _EffectIndicator(
                            ability: _buffAbility,
                            secondsLeft: buffSeconds,
                          ),
                        if (buffSeconds > 0 && rendSeconds > 0)
                          const SizedBox(height: 8),
                        if (rendSeconds > 0)
                          _EffectIndicator(
                            ability: _rendAbility,
                            secondsLeft: rendSeconds,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
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

/// The ability buttons: two upright rows (3 then 4) along the bottom edge,
/// dimmed while the global cooldown is in flight.
class _AbilityBar extends ConsumerWidget {
  const _AbilityBar({required this.game});

  final WanderworldGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onCooldown = ref.watch(combatProvider.select((s) => s.onCooldown));
    final progress = ref.watch(combatProvider.select((s) => s.cooldownProgress));
    final points = ref.watch(combatProvider.select((s) => s.abilityPoints));

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Opacity(
        opacity: onCooldown ? 0.45 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(0, 3, onCooldown, progress, points),
            const SizedBox(height: 8),
            _row(3, 7, onCooldown, progress, points),
          ],
        ),
      ),
    );
  }

  Widget _row(int start, int end, bool onCooldown, double progress, int points) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = start; i < end; i++)
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

/// Dim overlay with a Reset button, shown once the boss dies.
class _ResetOverlay extends ConsumerWidget {
  const _ResetOverlay({required this.game});

  final WanderworldGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dead = ref.watch(combatProvider.select((s) => s.bossDead));
    if (!dead) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: ElevatedButton(
          onPressed: game.resetCombat,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('Reset', style: TextStyle(fontSize: 20)),
          ),
        ),
      ),
    );
  }
}

/// Vertical resource gauge that fills from the bottom.
class _ResourceBar extends StatelessWidget {
  const _ResourceBar({
    required this.value,
    required this.max,
    required this.regenProgress,
    this.free = false,
  });

  final int value;
  final int max;

  /// Regen-cycle progress (0 at bottom, 1 at top) for the moving indicator.
  final double regenProgress;

  /// Whether the free-ability bonus is charged; highlights the bar when so.
  final bool free;

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 40,
      height: 300,
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
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: constraints.maxHeight * fraction,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFF00),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              },
            ),
          ),

          // Regen-timing indicator: a white bar climbing the gauge over one
          // regen cycle, snapping back to the bottom when it restarts.
          Align(
            // y: 1 (bottom) at cycle start -> -1 (top) at cycle end.
            alignment: Alignment(0, 1 - 2 * regenProgress),
            child: Container(
              height: 4,
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

/// Vertical boss health gauge that fills from the bottom, mirroring the resource
/// bar on the opposite edge.
class _BossHealthBar extends StatelessWidget {
  const _BossHealthBar({required this.value, required this.max});

  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 40,
      height: 300,
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
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: constraints.maxHeight * fraction,
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

/// Column of circles tracking ability points: [filled] solid, the rest empty.
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < max; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: kPointPadding),
            child: Container(
              width: kPointDiameter,
              height: kPointDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Bottom-up: the lowest [filled] circles are solid.
                color: i >= max - filled ? fillColor : Colors.black26,
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
    // Spawn a badge whenever the engine emits a new hit.
    ref.listen(floatingHitProvider, (prev, next) {
      if (next != null && next.seq != prev?.seq) _spawn(next);
    });

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
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
                      top: 60,
                      // Travel from off the right edge to off the left.
                      left: width - (width + 80) * t,
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
    required this.controller,
  });

  final int id;
  final Ability ability;
  final int amount;
  final bool crit;
  final AnimationController controller;
}

/// A floating hit: the ability's icon next to its rolled damage. Crits read
/// larger and amber.
class _FloatingDamageBadge extends StatelessWidget {
  const _FloatingDamageBadge({
    required this.ability,
    required this.amount,
    this.crit = false,
  });

  final Ability ability;
  final int amount;
  final bool crit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        _OutlinedNumber(
          '$amount',
          color: crit ? const Color(0xFFFFC107) : Colors.white,
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
