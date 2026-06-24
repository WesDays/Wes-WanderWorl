import 'dart:math' as math;

import '../abilities.dart';

// --- Combat constants (moved from game_screen.dart; UI-only constants stay
// there). These are the authoritative gameplay numbers the engine runs on.

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

double _seconds(Duration d) => d.inMicroseconds / Duration.microsecondsPerSecond;

/// Something the engine produced this tick that the view layer reacts to:
/// hit numbers, attack animations, the boss dying. Drained each frame.
sealed class CombatEvent {
  const CombatEvent();
}

/// A damage instance landed on the boss: the [ability] it came from, the rolled
/// [amount] (pre-clamp, so the displayed number matches overkill), and [crit].
class HitEvent extends CombatEvent {
  const HitEvent(this.ability, this.amount, this.crit);

  final Ability ability;
  final int amount;
  final bool crit;
}

/// An ability was successfully cast — drives the player's attack animation.
class CastEvent extends CombatEvent {
  const CastEvent(this.ability);

  final Ability ability;
}

/// The boss reached 0 health this tick.
class BossDiedEvent extends CombatEvent {
  const BossDiedEvent();
}

/// Immutable read-model the engine publishes for the HUD. Every field the UI
/// renders is derived from engine state here; widgets watch slices of it.
class CombatSnapshot {
  const CombatSnapshot({
    required this.resource,
    required this.abilityPoints,
    required this.bossHealth,
    required this.averageDps,
    required this.onCooldown,
    required this.cooldownProgress,
    required this.regenProgress,
    required this.rendSeconds,
    required this.buffSeconds,
    required this.freeAbility,
    required this.bossDead,
  });

  final int resource;
  final int abilityPoints;
  final int bossHealth;
  final double averageDps;

  /// True while the global cooldown is in flight.
  final bool onCooldown;

  /// Cooldown progress 0 (just started) → 1 (complete), for the clock-swipe dial.
  final double cooldownProgress;

  /// Regen-cycle progress 0 → 1, for the climbing resource-bar indicator.
  final double regenProgress;

  final int rendSeconds;
  final int buffSeconds;
  final bool freeAbility;
  final bool bossDead;
}

/// Authoritative combat model. Owns all combat state and rules; advanced by
/// [tick] each frame, mutated by [castAbility]. Holds no Flutter view concerns
/// (no controllers, timers, or setState) — the game ticks it and publishes
/// [snapshot] for the HUD, draining [drainEvents] for animations and floaters.
///
/// Fields are public so tests and the game can read/seed them directly; the UI
/// should read through [snapshot] rather than reaching in.
class CombatEngine {
  CombatEngine({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  final List<CombatEvent> _events = [];

  /// The abilities backing the two timed effects, resolved once for tagging
  /// Rend's damage events.
  final Ability _rendAbility = kAbilities.firstWhere((a) => a.appliesRend);

  int resource = kMaxResource;
  int abilityPoints = 0;
  int bossHealth = kBossMaxHealth;
  int totalDamage = 0;

  /// Combat time accumulated from [tick]; the denominator of the average DPS.
  double elapsedSeconds = 0;

  /// Seconds left on the global cooldown; 0 means ready.
  double cooldownRemaining = 0;

  /// Continuous accumulators toward the regen cycle and the 1-second cadence
  /// that drives rend ticks, the buff countdown, and the free-ability roll.
  double _regenAccum = 0;
  double _secondAccum = 0;

  int rendDamagePerTick = 0;
  int rendSeconds = 0;
  int rendExtends = 0;
  int rendBonusElapsed = 0;

  int buffSeconds = 0;

  bool freeAbility = false;

  bool get onCooldown => cooldownRemaining > 0;
  bool get bossDead => bossHealth <= 0;

  double get cooldownProgress =>
      onCooldown ? (1 - cooldownRemaining / _seconds(kCooldown)).clamp(0.0, 1.0) : 1;

  double get regenProgress => (_regenAccum / _seconds(kRegenInterval)).clamp(0.0, 1.0);

  double get averageDps => elapsedSeconds <= 0 ? 0 : totalDamage / elapsedSeconds;

  CombatSnapshot snapshot() => CombatSnapshot(
    resource: resource,
    abilityPoints: abilityPoints,
    bossHealth: bossHealth,
    averageDps: averageDps,
    onCooldown: onCooldown,
    cooldownProgress: cooldownProgress,
    regenProgress: regenProgress,
    rendSeconds: rendSeconds,
    buffSeconds: buffSeconds,
    freeAbility: freeAbility,
    bossDead: bossDead,
  );

  /// Returns and clears the events queued since the last drain.
  List<CombatEvent> drainEvents() {
    if (_events.isEmpty) return const [];
    final out = List<CombatEvent>.of(_events);
    _events.clear();
    return out;
  }

  /// Advances all real-time systems by [dt] seconds: cooldown, resource regen,
  /// and — on whole-second boundaries — rend ticks, the buff countdown, and the
  /// free-ability roll. Replaces the old AnimationController/Timer.periodic loops.
  void tick(double dt) {
    elapsedSeconds += dt;

    if (cooldownRemaining > 0) {
      cooldownRemaining -= dt;
      if (cooldownRemaining < 0) cooldownRemaining = 0;
    }

    final regenInterval = _seconds(kRegenInterval);
    _regenAccum += dt;
    while (_regenAccum >= regenInterval) {
      _regenAccum -= regenInterval;
      if (resource < kMaxResource) {
        resource = (resource + kRegenAmount).clamp(0, kMaxResource);
      }
    }

    _secondAccum += dt;
    while (_secondAccum >= 1.0) {
      _secondAccum -= 1.0;
      _onSecond();
    }
  }

  /// One second of elapsed combat: rolls the free-ability chance, advances an
  /// active Rend (resource, periodic bonus + damage, countdown), and ticks the
  /// buff countdown.
  void _onSecond() {
    if (_random.nextDouble() < kFreeAbilityChance) _grantFreeAbility();

    if (rendSeconds > 0) {
      resource = (resource + kRendResourcePerSecond).clamp(0, kMaxResource);
      rendBonusElapsed++;
      if (rendBonusElapsed >= kRendResourceInterval.inSeconds) {
        rendBonusElapsed = 0;
        resource = (resource + kRendResourceBonus).clamp(0, kMaxResource);
        // Rend's damage lands on the same cadence as its resource bonus.
        _dealDamage(rendDamagePerTick, _rendAbility);
      }
      rendSeconds--;
      if (rendSeconds <= 0) {
        rendSeconds = 0;
        rendBonusElapsed = 0;
        rendDamagePerTick = 0;
      }
    }

    if (buffSeconds > 0) {
      buffSeconds--;
      if (buffSeconds < 0) buffSeconds = 0;
    }
  }

  /// Validates and resolves an ability press. Mirrors the old `_onAbilityPressed`:
  /// cooldown/resource/point gating, the free-cast waiver, damage or Rend
  /// application, point grant/consume, Rend extension, and Buff refresh. Queues a
  /// [CastEvent] and starts the cooldown on success.
  void castAbility(int index) {
    if (bossDead) return;
    // Global cooldown: ignore every press while one is in flight.
    if (onCooldown) return;

    final ability = kAbilities[index];

    // The free-ability bonus only applies to abilities that actually pay a
    // resource cost, so it isn't wasted on Energize or zero-cost casts.
    final castFree =
        freeAbility && ability.setsResourceTo == null && ability.cost > 0;

    if (!castFree && resource < ability.cost) return;
    if (ability.requiresAbilityPoints && abilityPoints == 0) return;

    // Buff/Rend scale with points held now, before they are consumed.
    final pointsAtCast = abilityPoints;

    if (ability.setsResourceTo != null) {
      resource = ability.setsResourceTo!;
    } else if (castFree) {
      freeAbility = false;
    } else {
      resource -= ability.cost;
    }
    if (ability.consumesAbilityPoints) {
      abilityPoints = 0;
    }

    // Buff bonus is snapshot here from buff state at cast time, so re-casting
    // Buff later won't retro-buff an already-running Rend.
    final buffed = buffSeconds > 0;
    var critted = false;
    if (ability.appliesRend) {
      rendSeconds = kRendDuration.inSeconds;
      rendExtends = 0;
      rendBonusElapsed = 0;
      rendDamagePerTick = _buffedDamage(ability.damageFor(pointsAtCast), buffed);
    } else {
      // Every other ability deals its damage instantly; Rend's lands on its
      // ticks instead. damageFor returns 0 for non-damaging abilities.
      critted =
          _dealDamage(_buffedDamage(ability.damageFor(pointsAtCast), buffed), ability);
    }
    if (ability.grantsAbilityPoint) {
      // One point per cast, but a crit grants two. Capped: overflow is lost.
      abilityPoints =
          (abilityPoints + (critted ? 2 : 1)).clamp(0, kMaxAbilityPoints);
    }
    // Attack extends an already-active Rend, up to kRendMaxExtends times.
    if (ability.extendsRend && rendSeconds > 0 && rendExtends < kRendMaxExtends) {
      rendSeconds += kRendExtendSeconds;
      rendExtends++;
    }
    if (ability.appliesBuff) {
      buffSeconds = _buffSecondsFor(pointsAtCast);
    }

    // Spending ability points has a 20%-per-point chance to grant a free cast,
    // guaranteed at 5. Independent of the per-second roll; shares its charge.
    if (ability.consumesAbilityPoints && pointsAtCast > 0) {
      final chance = (kFreeAbilityChancePerPoint * pointsAtCast).clamp(0.0, 1.0);
      if (_random.nextDouble() < chance) _grantFreeAbility();
    }

    _events.add(CastEvent(ability));
    cooldownRemaining = _seconds(kCooldown);
  }

  /// Restores the fight to its starting state.
  void reset() {
    _events.clear();
    resource = kMaxResource;
    abilityPoints = 0;
    bossHealth = kBossMaxHealth;
    totalDamage = 0;
    elapsedSeconds = 0;
    cooldownRemaining = 0;
    _regenAccum = 0;
    _secondAccum = 0;
    rendDamagePerTick = 0;
    rendSeconds = 0;
    rendExtends = 0;
    rendBonusElapsed = 0;
    buffSeconds = 0;
    freeAbility = false;
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

  /// Grants the free-ability bonus (no-op when already held).
  void _grantFreeAbility() {
    if (freeAbility) return;
    freeAbility = true;
  }

  /// [amount] with the Buff's [kBuffDamageBonus] applied when [buffed].
  int _buffedDamage(int amount, bool buffed) =>
      buffed ? (amount * (1 + kBuffDamageBonus)).round() : amount;

  /// [amount] rolled with up to ±[kDamageVariance] swing.
  int _rollDamage(int amount) {
    if (amount <= 0) return amount;
    final factor = 1 + (_random.nextDouble() * 2 - 1) * kDamageVariance;
    return (amount * factor).round();
  }

  /// Rolls variance + a [kCritChance] crit (doubling), applies it to the boss
  /// (clamped at 0), tallies real damage, and queues a [HitEvent] (plus a
  /// [BossDiedEvent] on the killing blow). Returns whether it critted.
  bool _dealDamage(int amount, Ability source) {
    if (amount <= 0) return false;
    final crit = _random.nextDouble() < kCritChance;
    final rolled = _rollDamage(amount) * (crit ? kCritMultiplier : 1);
    final before = bossHealth;
    bossHealth = (bossHealth - rolled).clamp(0, kBossMaxHealth);
    // Count damage actually applied, so overkill doesn't inflate the average.
    totalDamage += before - bossHealth;
    _events.add(HitEvent(source, rolled, crit));
    if (bossHealth <= 0 && before > 0) _events.add(const BossDiedEvent());
    return crit;
  }
}
