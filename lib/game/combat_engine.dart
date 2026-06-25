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

/// Resource Rend grants on each tick, once every [kRendResourceInterval],
/// landing together with its damage.
const int kRendResourceBonus = 2;
const Duration kRendResourceInterval = Duration(seconds: 3);

/// Resource pool the abilities draw from.
const int kMaxResource = 100;

/// Boss starting health. Combat is still a placeholder, so this is freely
/// tunable until encounter pacing is dialled in.
const int kBossMaxHealth = 500000;

/// Player starting health.
const int kPlayerMaxHealth = 10000;

/// Inclusive range a single boss swing rolls within before any crit.
const int kBossDamageMin = 600;
const int kBossDamageMax = 900;

/// How often the boss swings at the player.
const Duration kBossAttackInterval = Duration(seconds: 5);

/// Chance each boss swing crits, multiplying its damage by [kCritMultiplier].
const double kBossCritChance = 0.05;

/// Fractional swing applied to every damage roll (±10%), so identical hits
/// land on a small spread instead of a fixed number.
const double kDamageVariance = 0.10;

/// Chance every individual damage roll lands a critical hit.
const double kCritChance = 0.40;

/// Damage multiplier a critical hit applies on top of the rolled amount.
const int kCritMultiplier = 2;

/// Chance, rolled once each second, that the free-ability bonus is granted:
/// the next damaging, resource-paying ability is cast at no resource cost.
const double kFreeAbilityChance = 0.05;

/// Chance per ability point spent that the free-ability bonus is granted:
/// 20% at 1 point, scaling to a guaranteed grant at 5.
const double kFreeAbilityChancePerPoint = 0.20;

/// How much resource is regained each [kRegenInterval].
const int kRegenAmount = 20;
const Duration kRegenInterval = Duration(seconds: 2);

/// Flat resource trickled in every second, separate from the [kRegenAmount]
/// burst on the [kRegenInterval] tick. Always-on, independent of Rend.
const int kResourcePerSecond = 2;

/// Cap on ability points; generation beyond this is lost.
const int kMaxAbilityPoints = 5;

/// How often the published DPS readout is re-sampled. The running average drifts
/// every frame, so we only refresh the displayed value on this cadence to keep
/// the number readable.
const Duration kDpsSampleInterval = Duration(milliseconds: 1500);

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

/// The boss landed a swing on the player: the [amount] dealt and whether [crit].
class PlayerHitEvent extends CombatEvent {
  const PlayerHitEvent(this.amount, this.crit);

  final int amount;
  final bool crit;
}

/// The player reached 0 health this tick.
class PlayerDiedEvent extends CombatEvent {
  const PlayerDiedEvent();
}

/// An ability healed the player: the [ability] it came from and the rolled
/// [amount] (pre-clamp, so the number matches overheal). Floats over the player.
class PlayerHealedEvent extends CombatEvent {
  const PlayerHealedEvent(this.ability, this.amount);

  final Ability ability;
  final int amount;
}

/// Immutable read-model the engine publishes for the HUD. Every field the UI
/// renders is derived from engine state here; widgets watch slices of it.
class CombatSnapshot {
  const CombatSnapshot({
    required this.resource,
    required this.abilityPoints,
    required this.bossHealth,
    required this.playerHealth,
    required this.averageDps,
    required this.onCooldown,
    required this.cooldownProgress,
    required this.regenProgress,
    required this.rendSeconds,
    required this.buffSeconds,
    required this.freeAbility,
    required this.bossDead,
    required this.playerDead,
  });

  final int resource;
  final int abilityPoints;
  final int bossHealth;
  final int playerHealth;
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
  final bool playerDead;
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
  int playerHealth = kPlayerMaxHealth;
  int totalDamage = 0;

  /// Combat time accumulated from [tick]; the denominator of the average DPS.
  double elapsedSeconds = 0;

  /// Seconds left on the global cooldown; 0 means ready.
  double cooldownRemaining = 0;

  /// Continuous accumulators toward the regen cycle and the 1-second cadence
  /// that drives rend ticks, the buff countdown, and the free-ability roll.
  double _regenAccum = 0;
  double _secondAccum = 0;
  double _dpsAccum = 0;

  /// Time accumulated toward the boss's next swing at the player.
  double _bossAttackAccum = 0;

  /// The DPS value actually published to the HUD; re-sampled from the running
  /// average every [kDpsSampleInterval] instead of every frame.
  double _sampledDps = 0;

  int rendDamagePerTick = 0;
  int rendSeconds = 0;
  int rendExtends = 0;
  int rendBonusElapsed = 0;

  int buffSeconds = 0;

  bool freeAbility = false;

  bool get onCooldown => cooldownRemaining > 0;
  bool get bossDead => bossHealth <= 0;
  bool get playerDead => playerHealth <= 0;

  double get cooldownProgress =>
      onCooldown ? (1 - cooldownRemaining / _seconds(kCooldown)).clamp(0.0, 1.0) : 1;

  double get regenProgress => (_regenAccum / _seconds(kRegenInterval)).clamp(0.0, 1.0);

  /// The running average over the whole fight; drifts every frame, so the HUD
  /// reads the [_sampledDps] snapshot instead.
  double get _liveDps => elapsedSeconds <= 0 ? 0 : totalDamage / elapsedSeconds;

  double get averageDps => _sampledDps;

  CombatSnapshot snapshot() => CombatSnapshot(
    resource: resource,
    abilityPoints: abilityPoints,
    bossHealth: bossHealth,
    playerHealth: playerHealth,
    averageDps: averageDps,
    onCooldown: onCooldown,
    cooldownProgress: cooldownProgress,
    regenProgress: regenProgress,
    rendSeconds: rendSeconds,
    buffSeconds: buffSeconds,
    freeAbility: freeAbility,
    bossDead: bossDead,
    playerDead: playerDead,
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

    // The boss swings on its own cadence while both fighters are alive.
    if (!bossDead && !playerDead) {
      final attackInterval = _seconds(kBossAttackInterval);
      _bossAttackAccum += dt;
      while (_bossAttackAccum >= attackInterval && !playerDead) {
        _bossAttackAccum -= attackInterval;
        _bossAttack();
      }
    }

    // Freeze the DPS readout once the fight ends — boss or player dead — so it
    // holds its final value.
    if (!bossDead && !playerDead) {
      final dpsInterval = _seconds(kDpsSampleInterval);
      _dpsAccum += dt;
      while (_dpsAccum >= dpsInterval) {
        _dpsAccum -= dpsInterval;
        _sampledDps = _liveDps;
      }
    }
  }

  /// One second of elapsed combat: rolls the free-ability chance, advances an
  /// active Rend (resource, periodic bonus + damage, countdown), and ticks the
  /// buff countdown.
  void _onSecond() {
    if (_random.nextDouble() < kFreeAbilityChance) _grantFreeAbility();

    // Always-on passive trickle, on top of the burst regen tick.
    resource = (resource + kResourcePerSecond).clamp(0, kMaxResource);

    if (rendSeconds > 0) {
      rendBonusElapsed++;
      if (rendBonusElapsed >= kRendResourceInterval.inSeconds) {
        rendBonusElapsed = 0;
        // Rend's resource and damage land together on the same tick.
        resource = (resource + kRendResourceBonus).clamp(0, kMaxResource);
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
    if (bossDead || playerDead) return;
    // Global cooldown: ignore every press while one is in flight.
    if (onCooldown) return;

    final ability = kAbilities[index];

    // The free-ability bonus only applies to abilities that pay a resource cost
    // AND deal damage (Attack, Rend, Blast, Heal), so it isn't spent on Energize,
    // zero-cost casts, or pure utility casts like Buff. Heal deals damage by
    // design specifically so it qualifies and can consume the proc.
    final castFree = freeAbility &&
        ability.setsResourceTo == null &&
        ability.cost > 0 &&
        ability.dealsDamage;

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
    if (ability.heals > 0) {
      final healed = _rollDamage(ability.heals);
      playerHealth = (playerHealth + healed).clamp(0, kPlayerMaxHealth);
      _events.add(PlayerHealedEvent(ability, healed));
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
    playerHealth = kPlayerMaxHealth;
    totalDamage = 0;
    elapsedSeconds = 0;
    cooldownRemaining = 0;
    _regenAccum = 0;
    _secondAccum = 0;
    _dpsAccum = 0;
    _bossAttackAccum = 0;
    _sampledDps = 0;
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

  /// Resolves one boss swing: rolls damage in the [kBossDamageMin]–
  /// [kBossDamageMax] range, applies a [kBossCritChance] crit, drains the
  /// player's health (clamped at 0), and queues a [PlayerHitEvent].
  void _bossAttack() {
    final crit = _random.nextDouble() < kBossCritChance;
    final base =
        kBossDamageMin + _random.nextInt(kBossDamageMax - kBossDamageMin + 1);
    final dealt = crit ? base * kCritMultiplier : base;
    final before = playerHealth;
    playerHealth = (playerHealth - dealt).clamp(0, kPlayerMaxHealth);
    _events.add(PlayerHitEvent(dealt, crit));
    if (playerHealth <= 0 && before > 0) _events.add(const PlayerDiedEvent());
  }

  /// Rolls variance + a [kCritChance] crit (doubling), applies it to the boss
  /// (clamped at 0), tallies real damage, and queues a [HitEvent] (plus a
  /// [BossDiedEvent] on the killing blow). Returns whether it critted.
  bool _dealDamage(int amount, Ability source) {
    if (amount <= 0) return false;
    final crit = source.canCrit && _random.nextDouble() < kCritChance;
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
