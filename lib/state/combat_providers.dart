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

/// A single hit the HUD should float: the rolled amount, whether it critted,
/// and the source [ability] (null for damage dealt to the player, which floats
/// without an icon). [onPlayer] floats it over the player rather than the boss;
/// [heal] renders it as a green "+amount" restore instead of damage.
class FloatingHit {
  const FloatingHit({
    this.ability,
    required this.amount,
    required this.crit,
    this.onPlayer = false,
    this.heal = false,
  });

  final Ability? ability;
  final int amount;
  final bool crit;
  final bool onPlayer;
  final bool heal;
}

/// Queue bridging engine [HitEvent]s to the widget-space floating-damage layer:
/// the game calls [emit] per hit; the layer spawns the pending hits then [clear]s
/// them. Hits accumulate into a list rather than a single slot because Riverpod
/// coalesces notifications to the latest state — so when several hits land in
/// one frame, that state must already hold every one or the earlier hits are
/// silently dropped.
class FloatingHitNotifier extends Notifier<List<FloatingHit>> {
  @override
  List<FloatingHit> build() => const [];

  void emit(FloatingHit hit) {
    state = [...state, hit];
  }

  /// Empties the queue once the layer has spawned the pending hits.
  void clear() {
    if (state.isNotEmpty) state = const [];
  }
}

final floatingHitProvider =
    NotifierProvider<FloatingHitNotifier, List<FloatingHit>>(
      FloatingHitNotifier.new,
    );
