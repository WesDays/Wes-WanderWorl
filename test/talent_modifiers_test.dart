import 'package:flutter_test/flutter_test.dart';
import 'package:wes_wanderworl/abilities.dart';
import 'package:wes_wanderworl/game/combat_engine.dart';
import 'package:wes_wanderworl/talents/talent_modifiers.dart';

void main() {
  group('resolveModifiers', () {
    test('empty ranks resolve to neutral defaults', () {
      final m = resolveModifiers(const {});
      expect(m.maxHpMultiplier, 1.0);
      expect(m.critMultiplier, 2.0);
      expect(m.critChanceBonus, 0.0);
      expect(m.startingAbilityPoints, 0);
      expect(m.maxResourceBonus, 0);
      expect(m.energizeSetPointBonus, 0);
    });

    test('no-cap K1 scales max HP by rank', () {
      expect(resolveModifiers({'K1': 2}).maxHpMultiplier, closeTo(1.2, 1e-9));
      expect(resolveModifiers({'K1': 5}).maxHpMultiplier, closeTo(1.5, 1e-9));
    });

    test('capped nodes read absolute totals', () {
      expect(resolveModifiers({'C1': 3}).critChanceBonus, closeTo(0.08, 1e-9));
      expect(resolveModifiers({'C2': 5}).critMultiplier, 2.5);
      expect(resolveModifiers({'E2': 2}).maxResourceBonus, 20);
      expect(resolveModifiers({'D1': 3}).energizeSetPointBonus, 6);
      expect(resolveModifiers({'B2': 4}).startingAbilityPoints, 4);
      expect(resolveModifiers({'E4': 3}).regenAmountBonus, 10);
    });
  });

  group('engine reads modifiers', () {
    test('K1 raises the player health cap', () {
      final engine = CombatEngine(modifiers: resolveModifiers({'K1': 3}));
      expect(engine.maxPlayerHealth, 13000);
      expect(engine.playerHealth, 13000);
    });

    test('E2/E4/C1/C2 feed the resolved caps and rates', () {
      final engine = CombatEngine(
        modifiers: resolveModifiers({'E2': 2, 'E4': 1, 'C1': 3, 'C2': 5}),
      );
      expect(engine.maxResource, 120);
      expect(engine.resource, 120);
      expect(engine.regenAmount, 23); // 20 base + 3
      expect(engine.critChance, closeTo(0.48, 1e-9));
      expect(engine.critMultiplier, 2.5);
    });

    test('B2 seeds starting ability points', () {
      final engine = CombatEngine(modifiers: resolveModifiers({'B2': 3}));
      expect(engine.abilityPoints, 3);
    });

    test('D1 raises the Energize set-point', () {
      final engine = CombatEngine(modifiers: resolveModifiers({'D1': 3}));
      final energizeIndex = kAbilities.indexWhere((a) => a.name == 'Energize');
      engine.resource = 5; // below the set-point so the cast raises it
      engine.castAbility(energizeIndex);
      expect(engine.resource, 66); // 60 + 6
    });

    test('startingHealth carries forward, clamped to the cap', () {
      final engine = CombatEngine(
        modifiers: resolveModifiers({'K1': 1}),
        startingHealth: 4200,
      );
      expect(engine.maxPlayerHealth, 11000);
      expect(engine.playerHealth, 4200);
    });
  });
}
