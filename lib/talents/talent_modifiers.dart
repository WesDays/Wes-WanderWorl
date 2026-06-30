import 'talent.dart';

/// Resolved combat modifiers from a talent loadout. Immutable; built once from
/// the ranks map by [resolveModifiers] and injected into the CombatEngine at
/// construction. Every field is a delta/multiplier over the engine's base
/// constants — the engine combines them, so this type stays free of engine
/// coupling. Neutral defaults (`const TalentModifiers()`) reproduce the base game.
class TalentModifiers {
  const TalentModifiers({
    this.maxHpMultiplier = 1.0,
    this.healthRegenPerSecond = 0,
    this.coreDamageMultiplier = 1.0,
    this.critChanceBonus = 0.0,
    this.critMultiplier = 2.0,
    this.maxResourceBonus = 0,
    this.regenAmountBonus = 0,
    this.startingAbilityPoints = 0,
    this.energizeSetPointBonus = 0,
    this.finisherCostReduction = 0,
    this.buffDamageBonus = 0.0,
    this.buffDurationBonus = 0,
  });

  /// K1 — multiplier on the player's max HP (1.0 = unchanged).
  final double maxHpMultiplier;

  /// J5 — flat HP restored each second.
  final int healthRegenPerSecond;

  /// A1 — multiplier on Attack/Rend/Blast damage (1.0 = unchanged).
  final double coreDamageMultiplier;

  /// C1 — additive crit-chance bonus (0.05 = +5%).
  final double critChanceBonus;

  /// C2 — crit damage multiplier (engine default 2.0).
  final double critMultiplier;

  /// E2 — added to the base max resource (10 -> 110).
  final int maxResourceBonus;

  /// E4 — added to the per-tick regen amount.
  final int regenAmountBonus;

  /// B2 — ability points to start each encounter with.
  final int startingAbilityPoints;

  /// D1 — added to Energize's set-point (60 -> 70 at +10).
  final int energizeSetPointBonus;

  /// E1 — resource shaved off point-consuming "finisher" abilities.
  final int finisherCostReduction;

  /// I1 — added to the Buff's fractional damage bonus (0.30 base).
  final double buffDamageBonus;

  /// I2 — seconds added to the Buff's duration.
  final int buffDurationBonus;
}

/// Builds [TalentModifiers] from a talent ranks map (Batch A). Capped nodes'
/// rank values are absolute totals; "no cap" nodes (K1) are per-rank increments,
/// so those multiply by the rank held. Unwired talents simply aren't read here.
TalentModifiers resolveModifiers(Map<String, int> ranks) {
  int rank(String id) => ranks[id] ?? 0;
  num val(String id) => talentById(id).valueAt(rank(id));

  return TalentModifiers(
    // K1: +10% max HP per rank, no cap.
    maxHpMultiplier: 1 + (val('K1') * rank('K1')) / 100,
    // J5: flat HP/sec at the rank's value.
    healthRegenPerSecond: val('J5').toInt(),
    // A1: +% damage to Attack/Rend/Blast (engine applies it to the core set).
    coreDamageMultiplier: 1 + val('A1') / 100,
    // C1: additive crit chance.
    critChanceBonus: val('C1') / 100,
    // C2: absolute crit multiplier; engine default 2.0 when unallocated.
    critMultiplier: rank('C2') > 0 ? val('C2').toDouble() : 2.0,
    // E2: absolute max resource (110/120/130) over the base 100.
    maxResourceBonus: rank('E2') > 0 ? (val('E2') - 100).toInt() : 0,
    // E4: extra resource per regen tick.
    regenAmountBonus: val('E4').toInt(),
    // B2: ability points to start with.
    startingAbilityPoints: val('B2').toInt(),
    // D1: Energize set-point (62..70) over the base 60.
    energizeSetPointBonus: rank('D1') > 0 ? (val('D1') - 60).toInt() : 0,
    // E1: finisher cost reduction.
    finisherCostReduction: val('E1').toInt(),
    // I1: added to the Buff's fractional damage bonus.
    buffDamageBonus: val('I1') / 100,
    // I2: extra Buff seconds.
    buffDurationBonus: val('I2').toInt(),
  );
}
