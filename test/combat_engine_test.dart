import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wes_wanderworl/abilities.dart';
import 'package:wes_wanderworl/game/combat_engine.dart';

/// Deterministic Random: every roll returns [value]. Lets tests force or avoid
/// crits and free-ability grants (both compare nextDouble() against a chance).
class _FixedRandom implements math.Random {
  _FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

// Ability indices in kAbilities.
const _energize = 0;
const _attack = 3;
const _rend = 4;
const _buff = 6;

void main() {
  // 0.99 dodges every chance roll (no crit, no free grant); 0.0 forces them.
  CombatEngine noLuck() => CombatEngine(random: _FixedRandom(0.99));
  CombatEngine allLuck() => CombatEngine(random: _FixedRandom(0.0));

  group('cooldown', () {
    test('a cast starts the cooldown and blocks further casts until it elapses', () {
      final e = noLuck();
      e.castAbility(_energize); // cost 0, sets resource to 60
      expect(e.onCooldown, isTrue);
      expect(e.resource, 60);

      // Second press is ignored while on cooldown.
      e.resource = 10;
      e.castAbility(_energize);
      expect(e.resource, 10);

      e.tick(_secondsOf(kCooldown));
      expect(e.onCooldown, isFalse);
      e.castAbility(_energize);
      expect(e.resource, 60);
    });
  });

  group('resource', () {
    test('regenerates kRegenAmount each kRegenInterval', () {
      final e = noLuck();
      e.resource = 0;
      e.tick(_secondsOf(kRegenInterval));
      // Ticking a full kRegenInterval also crosses two 1-second boundaries, so
      // the per-second trickle stacks on top of the burst. Both are independent.
      final secondsElapsed = kRegenInterval.inSeconds;
      expect(e.resource, kRegenAmount + secondsElapsed * kResourcePerSecond);
    });

    test('a paying ability spends its cost', () {
      final e = noLuck();
      e.resource = 100;
      e.castAbility(_attack); // cost 42
      expect(e.resource, 100 - 42);
    });
  });

  group('damage', () {
    test('a cast reduces boss health and tallies damage', () {
      final e = noLuck();
      final before = e.bossHealth;
      e.castAbility(_attack);
      expect(e.bossHealth, lessThan(before));
      expect(e.totalDamage, before - e.bossHealth);
    });

    test('a crit on Attack grants two ability points', () {
      final e = allLuck();
      e.castAbility(_attack);
      expect(e.abilityPoints, 2);
    });

    test('boss death queues BossDiedEvent and reset restores the fight', () {
      final e = allLuck();
      e.bossHealth = 1;
      e.castAbility(_attack);
      expect(e.bossDead, isTrue);
      expect(e.drainEvents().whereType<BossDiedEvent>(), isNotEmpty);

      e.reset();
      expect(e.bossHealth, kBossMaxHealth);
      expect(e.bossDead, isFalse);
    });
  });

  group('rend', () {
    test('applies for its full duration and deals damage on its bonus cadence', () {
      final e = noLuck();
      e.abilityPoints = 5;
      e.castAbility(_rend);
      expect(e.rendSeconds, kRendDuration.inSeconds);
      expect(e.abilityPoints, 0); // consumed
      expect(e.rendDamagePerTick, greaterThan(0));

      final before = e.bossHealth;
      e.tick(kRendResourceInterval.inSeconds.toDouble()); // 3 one-second ticks
      expect(e.bossHealth, lessThan(before)); // a rend damage tick landed
    });

    test('Attack extends an active Rend up to kRendMaxExtends times', () {
      final e = noLuck();
      e.rendSeconds = kRendDuration.inSeconds;
      for (var i = 0; i < kRendMaxExtends + 3; i++) {
        e.resource = 100; // keep Attack affordable
        e.cooldownRemaining = 0; // skip waiting out the cooldown
        e.castAbility(_attack);
      }
      expect(e.rendExtends, kRendMaxExtends);
    });

    test('an active Buff is baked into Rend per-tick damage at cast', () {
      final e = noLuck();
      e.buffSeconds = 10;
      e.abilityPoints = 5;
      final base = kAbilities[_rend].damageFor(5);
      e.castAbility(_rend);
      expect(e.rendDamagePerTick, (base * (1 + kBuffDamageBonus)).round());
    });
  });

  group('free ability', () {
    test('spending points can grant a free cast (guaranteed at 5 points)', () {
      final e = allLuck();
      e.abilityPoints = 5;
      e.castAbility(_buff); // consumes points; chance = 0.20*5 = guaranteed
      expect(e.freeAbility, isTrue);
    });
  });
}

/// Duration → seconds, mirroring the engine's internal helper for tick math.
double _secondsOf(Duration d) => d.inMicroseconds / Duration.microsecondsPerSecond;
