import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'abilities.dart';
import 'clock_swipe.dart';

/// How long every ability is locked out after any press.
const Duration kCooldown = Duration(milliseconds: 1000);

/// Duration the Rend effect is refreshed to each time the ability is used.
const Duration kRendDuration = Duration(seconds: 12);

/// Seconds an Attack adds to an active Rend.
const int kRendExtendSeconds = 2;

/// Max number of Attack extensions a single Rend can take. At 6 the total
/// duration tops out at its base plus 6×[kRendExtendSeconds] (12 + 12 = 24s).
const int kRendMaxExtends = 6;

/// Fractional damage bonus granted while the Buff effect is active (30%).
const double kBuffDamageBonus = 0.30;

/// Resource the active Rend grants every second.
const int kRendResourcePerSecond = 2;

/// Extra resource Rend grants on top once every [kRendResourceInterval].
const int kRendResourceBonus = 2;
const Duration kRendResourceInterval = Duration(seconds: 3);

/// Resource pool the abilities draw from.
const int kMaxResource = 100;

/// Boss starting health. Combat is still a placeholder, so this is freely
/// tunable until encounter pacing is dialled in.
const int kBossMaxHealth = 500000;

/// Fractional swing applied to every damage roll (±10%), so identical hits
/// land on a small spread instead of a fixed number.
const double kDamageVariance = 0.10;

/// Chance every individual damage roll lands a critical hit.
const double kCritChance = 0.40;

/// Damage multiplier a critical hit applies on top of the rolled amount.
const int kCritMultiplier = 2;

/// How long a floating damage number travels across the screen before it is
/// removed.
const Duration kFloatingDamageDuration = Duration(milliseconds: 1500);

/// Chance, rolled once each second, that the free-ability bonus is granted:
/// the next resource-paying ability is cast at no resource cost.
const double kFreeAbilityChance = 0.05;

/// Chance per ability point spent that the free-ability bonus is granted:
/// 20% at 1 point, scaling to a guaranteed grant at 5.
const double kFreeAbilityChancePerPoint = 0.20;

/// How much resource is regained each [kRegenInterval].
const int kRegenAmount = 20;
const Duration kRegenInterval = Duration(seconds: 2);

/// Cap on ability points; generation beyond this is lost.
const int kMaxAbilityPoints = 5;

/// Geometry of one ability-point circle: diameter plus vertical padding
/// on each side. Used to lay out the circles and to float the effect
/// badges directly above them.
const double kPointDiameter = 18;
const double kPointPadding = 4;

/// Total height of the ability-point column, so badges can be parked just
/// above it without disturbing the circles.
const double kAbilityPointsHeight =
    kMaxAbilityPoints * (kPointDiameter + 2 * kPointPadding);

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  /// Drives both the cooldown timing and the clock-swipe animation.
  late final AnimationController _cooldown;

  /// Resource pool; regenerates over time, spent by abilities.
  int _resource = kMaxResource;

  /// Secondary resource, granted by certain abilities; capped at the max.
  int _abilityPoints = 0;

  /// Boss health pool; reduced by ability damage, clamped at 0.
  int _bossHealth = kBossMaxHealth;

  /// Total damage dealt so far; divided by elapsed time for the average DPS.
  int _totalDamage = 0;

  /// When damage tracking began — the denominator of the average DPS.
  /// Reset alongside the rest of the fight when the boss dies.
  late DateTime _combatStart;

  /// True once the boss reaches 0 health; surfaces the reset button.
  bool get _bossDead => _bossHealth <= 0;

  /// Refreshes the DPS readout each second so it keeps adjusting while idle.
  Timer? _dpsTimer;

  /// Damage the active Rend deals each periodic tick, fixed from the ability
  /// points spent at cast; 0 when no Rend is active.
  int _rendDamagePerTick = 0;

  /// Seconds left on the active Rend effect; 0 means inactive.
  int _rendSeconds = 0;

  /// Attack extensions applied to the current Rend; capped at [kRendMaxExtends].
  /// Reset each time Rend is re-cast.
  int _rendExtends = 0;

  /// Ticks down [_rendSeconds] once a second while the effect is active.
  Timer? _rendTimer;

  /// Seconds elapsed since Rend last paid its periodic [kRendResourceBonus].
  /// Tracking elapsed time (rather than a fixed schedule) means extending the
  /// duration keeps the bonus ticking on the same cadence.
  int _rendBonusElapsed = 0;

  /// Seconds left on the active Buff effect; 0 means inactive.
  int _buffSeconds = 0;

  /// Ticks down [_buffSeconds] once a second while the effect is active.
  Timer? _buffTimer;

  /// The abilities backing the two timed-effect badges.
  final Ability _rendAbility = kAbilities.firstWhere((a) => a.appliesRend);
  final Ability _buffAbility = kAbilities.firstWhere((a) => a.appliesBuff);

  /// Repeats over [kRegenInterval]; doubles as the regen-progress indicator.
  /// Resource is granted each time it wraps from top back to bottom.
  late final AnimationController _regen;
  double _lastRegenValue = 0;

  /// When true, the next resource-paying ability is cast for free; the charge
  /// is then consumed. Set via [_grantFreeAbility] so any source can grant it.
  bool _freeAbility = false;

  /// Rolls the per-second chance for the free-ability bonus.
  final math.Random _random = math.Random();

  /// Drives the per-second free-ability roll.
  Timer? _freeAbilityTimer;

  /// Damage numbers currently drifting across the screen, each with its own
  /// controller driving the travel + fade. Removed as they finish.
  final List<_FloatingDamage> _floaters = [];
  int _nextFloaterId = 0;

  bool get _onCooldown => _cooldown.isAnimating;

  @override
  void initState() {
    super.initState();
    _cooldown = AnimationController(vsync: this, duration: kCooldown);
    _regen = AnimationController(vsync: this, duration: kRegenInterval)
      ..addListener(_onRegenTick)
      ..repeat();
    _freeAbilityTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_random.nextDouble() < kFreeAbilityChance) _grantFreeAbility();
    });
    _combatStart = DateTime.now();
    _dpsTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  /// Running average DPS: total damage dealt over elapsed seconds.
  double get _averageDps {
    final seconds = DateTime.now().difference(_combatStart).inMilliseconds / 1000;
    if (seconds <= 0) return 0;
    return _totalDamage / seconds;
  }

  /// Grants the free-ability bonus: the next resource-paying ability is free.
  /// Reusable entry point for any source (the per-second roll today, more
  /// later). A no-op when the charge is already held.
  void _grantFreeAbility() {
    if (_freeAbility) return;
    setState(() => _freeAbility = true);
  }

  /// [amount] with the Buff's [kBuffDamageBonus] applied when [buffed]. Snapshot
  /// at cast: instant hits read the buff live, Rend bakes it into its per-tick
  /// damage so its remaining ticks keep the bonus even after the buff drops.
  int _buffedDamage(int amount, bool buffed) =>
      buffed ? (amount * (1 + kBuffDamageBonus)).round() : amount;

  /// [amount] rolled with up to ±[kDamageVariance] swing, so repeated hits
  /// scatter around their base value.
  int _rollDamage(int amount) {
    if (amount <= 0) return amount;
    final factor = 1 + (_random.nextDouble() * 2 - 1) * kDamageVariance;
    return (amount * factor).round();
  }

  /// Rolls [amount] for variance, rolls a [kCritChance] crit that doubles it,
  /// applies it to the boss (clamped at 0), and floats the rolled number tagged
  /// with [source]'s icon. Callers run inside a setState (cast handler or Rend
  /// tick), so this only mutates state. Returns whether the hit critted, so
  /// callers can react (e.g. Attack's bonus point).
  bool _dealDamage(int amount, Ability source) {
    if (amount <= 0) return false;
    final crit = _random.nextDouble() < kCritChance;
    final rolled = _rollDamage(amount) * (crit ? kCritMultiplier : 1);
    final before = _bossHealth;
    _bossHealth = (_bossHealth - rolled).clamp(0, kBossMaxHealth);
    // Count damage actually applied, so overkill doesn't inflate the average.
    _totalDamage += before - _bossHealth;
    _spawnFloatingDamage(source, rolled, crit);
    return crit;
  }

  /// Adds a damage number that drifts right-to-left below the ability bar and
  /// removes itself once its travel finishes. [crit] tags it for distinct styling.
  void _spawnFloatingDamage(Ability source, int amount, bool crit) {
    final controller = AnimationController(
      vsync: this,
      duration: kFloatingDamageDuration,
    );
    final floater = _FloatingDamage(
      id: _nextFloaterId++,
      ability: source,
      amount: amount,
      crit: crit,
      controller: controller,
    );
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        setState(() => _floaters.remove(floater));
      }
    });
    _floaters.add(floater);
    controller.forward();
  }

  /// Restores the fight to its starting state: boss health, DPS tracking,
  /// resources, ability points, and any active timed effects.
  void _reset() {
    _rendTimer?.cancel();
    _rendTimer = null;
    _buffTimer?.cancel();
    _buffTimer = null;
    _cooldown.stop();
    for (final f in _floaters) {
      f.controller.dispose();
    }
    setState(() {
      _floaters.clear();
      _bossHealth = kBossMaxHealth;
      _totalDamage = 0;
      _combatStart = DateTime.now();
      _resource = kMaxResource;
      _abilityPoints = 0;
      _rendSeconds = 0;
      _rendExtends = 0;
      _rendBonusElapsed = 0;
      _rendDamagePerTick = 0;
      _buffSeconds = 0;
      _freeAbility = false;
    });
  }

  /// Grants resource when the regen cycle wraps (indicator reaches the top).
  void _onRegenTick() {
    if (_regen.value < _lastRegenValue && _resource < kMaxResource) {
      setState(() {
        _resource = (_resource + kRegenAmount).clamp(0, kMaxResource);
      });
    }
    _lastRegenValue = _regen.value;
  }

  @override
  void dispose() {
    _rendTimer?.cancel();
    _buffTimer?.cancel();
    _freeAbilityTimer?.cancel();
    _dpsTimer?.cancel();
    for (final f in _floaters) {
      f.controller.dispose();
    }
    _regen.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  void _onAbilityPressed(int index) {
    // Global cooldown: ignore every press while one is in flight.
    if (_onCooldown) return;

    final ability = kAbilities[index];

    // The free-ability bonus only applies to abilities that actually pay a
    // resource cost, so it isn't wasted on Energize or zero-cost casts.
    final castFree =
        _freeAbility && ability.setsResourceTo == null && ability.cost > 0;

    // Not enough resource to pay the ability's cost (waived when cast free).
    if (!castFree && _resource < ability.cost) return;

    // Requires ability points but the pool is empty.
    if (ability.requiresAbilityPoints && _abilityPoints == 0) return;

    // Buff duration scales with points held now, before they are consumed.
    final pointsAtCast = _abilityPoints;

    setState(() {
      // Either set the pool outright, cast for free, or pay the ability's cost.
      if (ability.setsResourceTo != null) {
        _resource = ability.setsResourceTo!;
      } else if (castFree) {
        // Waive the cost and spend the charge.
        _freeAbility = false;
      } else {
        _resource -= ability.cost;
      }
      if (ability.consumesAbilityPoints) {
        _abilityPoints = 0;
      }
      // Rend refreshes to full duration and overwrites its per-tick damage
      // with the amount for the points spent on this cast.
      // The Buff bonus is snapshot here from the buff state at cast time, so
      // re-casting Buff later won't retro-buff an already-running Rend.
      final buffed = _buffSeconds > 0;
      var critted = false;
      if (ability.appliesRend) {
        _rendSeconds = kRendDuration.inSeconds;
        _rendExtends = 0;
        _rendBonusElapsed = 0;
        _rendDamagePerTick = _buffedDamage(ability.damageFor(pointsAtCast), buffed);
      } else {
        // Every other ability deals its damage instantly; Rend's lands on its
        // ticks instead. damageFor returns 0 for non-damaging abilities.
        critted =
            _dealDamage(_buffedDamage(ability.damageFor(pointsAtCast), buffed), ability);
      }
      if (ability.grantsAbilityPoint) {
        // One point per cast, but a crit grants two. Capped: overflow is lost.
        _abilityPoints =
            (_abilityPoints + (critted ? 2 : 1)).clamp(0, kMaxAbilityPoints);
      }
      // Attack extends an already-active Rend, up to kRendMaxExtends times.
      // Capping the count (not the remaining seconds) stops a decaying Rend
      // from being topped back up forever.
      if (ability.extendsRend &&
          _rendSeconds > 0 &&
          _rendExtends < kRendMaxExtends) {
        _rendSeconds += kRendExtendSeconds;
        _rendExtends++;
      }
      // Buff refreshes to a duration scaled by the points held at cast.
      if (ability.appliesBuff) {
        _buffSeconds = _buffSecondsFor(pointsAtCast);
      }
    });

    if (ability.appliesRend) _ensureRendTimer();
    if (ability.appliesBuff) _ensureBuffTimer();

    // Spending ability points has a 20%-per-point chance to grant a free cast,
    // guaranteed at 5. Independent of the per-second roll; shares its charge.
    if (ability.consumesAbilityPoints && pointsAtCast > 0) {
      final chance = (kFreeAbilityChancePerPoint * pointsAtCast).clamp(0.0, 1.0);
      if (_random.nextDouble() < chance) _grantFreeAbility();
    }

    _cooldown.forward(from: 0);
  }

  /// Buff duration in seconds for the [points] held when it is cast.
  int _buffSecondsFor(int points) => switch (points) {
    >= 5 => 34,
    4 => 29,
    3 => 24,
    2 => 19,
    1 => 14,
    _ => 12,
  };

  /// Starts the per-second Rend countdown if it isn't already running.
  void _ensureRendTimer() {
    _rendTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        // A second of Rend elapsed: pay its per-second resource, then the
        // periodic bonus once enough time has built up since the last one.
        _resource = (_resource + kRendResourcePerSecond).clamp(0, kMaxResource);
        _rendBonusElapsed++;
        if (_rendBonusElapsed >= kRendResourceInterval.inSeconds) {
          _rendBonusElapsed = 0;
          _resource = (_resource + kRendResourceBonus).clamp(0, kMaxResource);
          // Rend's damage lands on the same cadence as its resource bonus.
          _dealDamage(_rendDamagePerTick, _rendAbility);
        }

        _rendSeconds--;
        if (_rendSeconds <= 0) {
          _rendSeconds = 0;
          _rendBonusElapsed = 0;
          _rendDamagePerTick = 0;
          _rendTimer?.cancel();
          _rendTimer = null;
        }
      });
    });
  }

  /// Starts the per-second Buff countdown if it isn't already running.
  void _ensureBuffTimer() {
    _buffTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _buffSeconds--;
        if (_buffSeconds <= 0) {
          _buffSeconds = 0;
          _buffTimer?.cancel();
          _buffTimer = null;
        }
      });
    });
  }

  /// Builds one row of ability buttons for the abilities in [start, end).
  Widget _abilityRow(int start, int end) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = start; i < end; i++)
          _AbilityButton(
            ability: kAbilities[i],
            onPressed: () => _onAbilityPressed(i),
            cooldown: _cooldown,
            // Greyed out and unpressable while its point requirement is unmet.
            enabled: !kAbilities[i].requiresAbilityPoints || _abilityPoints > 0,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A2233), Color(0xFF0B0E16)],
          ),
        ),
        child: Stack(
          children: [
            // --- Boss health bar: vertical gauge hugging the left edge,
            // mirroring the resource bar on the right.
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BossHealthBar(value: _bossHealth, max: kBossMaxHealth),
                    const SizedBox(width: 8),
                    _DpsLabel(dps: _averageDps),
                  ],
                ),
              ),
            ),

            // --- Ability buttons: two stacked rows near the top edge (3 on
            // top, 4 below). Each button keeps its 90° rotation.
            Align(
              alignment: Alignment.topCenter,
              child: AnimatedBuilder(
                animation: _cooldown,
                builder: (context, child) {
                  // Fade the controls slightly while locked out.
                  return Opacity(
                    opacity: _onCooldown ? 0.45 : 1.0,
                    child: child,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _abilityRow(0, 3),
                      const SizedBox(height: 8),
                      _abilityRow(3, 7),
                    ],
                  ),
                ),
              ),
            ),

            // --- Floating damage feed: each hit drifts right-to-left in a
            // band just below the ability rows, facing the same way as the
            // rest of the UI. Each badge is its own Positioned (no bounding
            // box) so the rotated number isn't squeezed by the band.
            Positioned.fill(
              child: IgnorePointer(
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
                              final opacity =
                                  t < 0.66 ? 1.0 : (1 - (t - 0.66) / 0.34);
                              return Positioned(
                                top: 152,
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
              ),
            ),

            // --- Resource bar: vertical gauge hugging the right edge, with
            // the ability-point circles sitting to its left.
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Badges float above the points via a Stack so showing
                    // one never shifts the circles.
                    Stack(
                      alignment: Alignment.bottomCenter,
                      clipBehavior: Clip.none,
                      children: [
                        _AbilityPoints(
                          filled: _abilityPoints,
                          max: kMaxAbilityPoints,
                        ),
                        if (_rendSeconds > 0 || _buffSeconds > 0)
                          Positioned(
                            bottom: kAbilityPointsHeight + 8,
                            // Nudged left of the points column.
                            child: Transform.translate(
                              offset: const Offset(-12, 0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_buffSeconds > 0)
                                    _EffectIndicator(
                                      ability: _buffAbility,
                                      secondsLeft: _buffSeconds,
                                    ),
                                  if (_buffSeconds > 0 && _rendSeconds > 0)
                                    const SizedBox(height: 8),
                                  if (_rendSeconds > 0)
                                    _EffectIndicator(
                                      ability: _rendAbility,
                                      secondsLeft: _rendSeconds,
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    _ResourceBar(
                      value: _resource,
                      max: kMaxResource,
                      regen: _regen,
                      free: _freeAbility,
                    ),
                  ],
                ),
              ),
            ),

            // --- Reset overlay: appears once the boss is dead, dimming the
            // screen behind a button that restarts the fight.
            if (_bossDead)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: ElevatedButton(
                      onPressed: _reset,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text('Reset', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
    required this.regen,
    this.free = false,
  });

  final int value;
  final int max;

  /// Regen-cycle progress (0 at bottom, 1 at top) for the moving indicator.
  final AnimationController regen;

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
          // The bar itself: bottom-pinned fill that only shrinks from the top.
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
                  ? const [
                      BoxShadow(color: Color(0xFFFFFF00), blurRadius: 10),
                    ]
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

          // Regen-timing indicator: a white bar that climbs the gauge over one
          // regen cycle, snapping back to the bottom when it restarts.
          AnimatedBuilder(
            animation: regen,
            builder: (context, _) {
              return Align(
                // y: 1 (bottom) at cycle start -> -1 (top) at cycle end.
                alignment: Alignment(0, 1 - 2 * regen.value),
                // Black outline so the bar reads against the yellow fill.
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                ),
              );
            },
          ),

          // Number centred on top of the bar, rotated to match the buttons.
          RotatedBox(quarterTurns: 3, child: _OutlinedNumber('$value')),
        ],
      ),
    );
  }
}

/// Running-average DPS readout, rotated to face the same way as the resource
/// bar. Parked at the top of the boss bar.
class _DpsLabel extends StatelessWidget {
  const _DpsLabel({required this.dps});

  final double dps;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: 3,
      child: _OutlinedNumber('${dps.round()} DPS'),
    );
  }
}

/// Vertical boss health gauge that fills from the bottom, mirroring the
/// resource bar on the opposite edge.
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
          // Bottom-pinned fill that shrinks from the top as damage lands.
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

          // Number rotated to match the resource bar and ability buttons.
          RotatedBox(quarterTurns: 3, child: _OutlinedNumber('$value')),
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

    // Sized to its circles; the parent row bottom-aligns it with the bar.
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

/// Active-effect badge: an ability's icon with its seconds remaining stacked
/// above it, rotated to match the rest of the UI.
class _EffectIndicator extends StatelessWidget {
  const _EffectIndicator({required this.ability, required this.secondsLeft});

  final Ability ability;
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: 3,
      child: Stack(
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
          // Countdown sits on top of the icon, centred.
          _OutlinedNumber('$secondsLeft'),
        ],
      ),
    );
  }
}

/// One in-flight damage number: the ability it came from, the rolled amount,
/// and the controller driving its drift across the screen.
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

/// A floating hit: the ability's icon next to its rolled damage, rotated to
/// face the same way as the rest of the UI. Crits read larger and amber.
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
    return RotatedBox(
      quarterTurns: 3,
      child: Row(
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
          // Crits punch up: amber text, larger, and a trailing '!'.
          _OutlinedNumber(
            crit ? '$amount' : '$amount',
            color: crit ? const Color(0xFFFFC107) : Colors.white,
            fontSize: crit ? 18 : 16,
          ),
        ],
      ),
    );
  }
}

/// White text with a black outline, drawn by stacking a stroked copy
/// behind a filled copy.
class _OutlinedNumber extends StatelessWidget {
  const _OutlinedNumber(
    this.text, {
    this.color = Colors.white,
    this.fontSize = 16,
  });

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

/// One ability control, rotated so its bottom faces the screen edge.
class _AbilityButton extends StatelessWidget {
  const _AbilityButton({
    required this.ability,
    required this.onPressed,
    required this.cooldown,
    this.enabled = true,
  });

  final Ability ability;
  final VoidCallback onPressed;

  /// Drives the per-button clock-swipe; shared global cooldown controller.
  final AnimationController cooldown;

  /// When false the button is greyed out and ignores taps.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: RotatedBox(
        // 3 quarter-turns => the button's bottom points to the right edge.
        quarterTurns: 3,
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
                              // Button is rotated 90° (quarterTurns: 3), so map
                              // the screen-space nudge onto the icon's local axes.
                              offset: Offset(
                                -ability.iconAssetOffset.dy,
                                ability.iconAssetOffset.dx,
                              ),
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

                  // Cooldown clock-swipe overlaid on the button itself; only
                  // painted while the global cooldown is in flight.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipOval(
                        child: AnimatedBuilder(
                          animation: cooldown,
                          builder: (context, _) {
                            if (!cooldown.isAnimating) {
                              return const SizedBox.shrink();
                            }
                            return CustomPaint(
                              painter: ClockSwipePainter(cooldown.value),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
