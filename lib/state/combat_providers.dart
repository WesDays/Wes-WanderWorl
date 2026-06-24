import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../abilities.dart';
import '../game/combat_engine.dart';

/// Snapshot of a fresh engine, used as the provider's value until the running
/// game publishes its first frame.
final CombatSnapshot _initialSnapshot = CombatEngine().snapshot();

/// The HUD's read-model. The game writes a new [CombatSnapshot] every frame via
/// [CombatNotifier.set]; widgets watch slices with `select` so they only rebuild
/// when the value they care about changes.
class CombatNotifier extends Notifier<CombatSnapshot> {
  @override
  CombatSnapshot build() => _initialSnapshot;

  void set(CombatSnapshot snapshot) => state = snapshot;
}

final combatProvider = NotifierProvider<CombatNotifier, CombatSnapshot>(
  CombatNotifier.new,
);

/// A single hit the HUD should float. [seq] makes each emission distinct so the
/// floating layer spawns exactly one badge per hit even if two hits share the
/// same ability/amount.
class FloatingHit {
  const FloatingHit(this.seq, this.ability, this.amount, this.crit);

  final int seq;
  final Ability ability;
  final int amount;
  final bool crit;
}

/// Bridges engine [HitEvent]s to the (otherwise unchanged) widget-space floating
/// damage layer: the game calls [emit] per hit; the layer listens and spawns.
class FloatingHitNotifier extends Notifier<FloatingHit?> {
  int _seq = 0;

  @override
  FloatingHit? build() => null;

  void emit(Ability ability, int amount, bool crit) {
    state = FloatingHit(_seq++, ability, amount, crit);
  }
}

final floatingHitProvider = NotifierProvider<FloatingHitNotifier, FloatingHit?>(
  FloatingHitNotifier.new,
);
