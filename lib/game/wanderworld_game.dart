import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_riverpod/flame_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Color;

import '../state/combat_providers.dart';
import 'boss_component.dart';
import 'combat_engine.dart';
import 'player_component.dart';

/// The Flame game. Owns the authoritative [CombatEngine], renders the world
/// (player + boss), and bridges to the Flutter HUD through Riverpod: each frame
/// it ticks the engine, publishes a [CombatSnapshot], and routes engine events
/// to component animations and the floating-damage feed.
class WanderworldGame extends FlameGame with RiverpodGameMixin {
  final CombatEngine engine = CombatEngine();

  late final PlayerComponent _player;
  late final BossComponent _boss;

  @override
  Color backgroundColor() => const Color(0xFF0B0E16);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // World origin sits at screen centre; place the duo on either side.
    camera.viewfinder.anchor = Anchor.center;
    _player = PlayerComponent()..position = Vector2(-70, 20);
    _boss = BossComponent()..position = Vector2(70, 10);
    world.addAll([_player, _boss]);
  }

  /// Input entry points for the HUD overlay.
  void castAbility(int index) => engine.castAbility(index);
  void resetCombat() {
    engine.reset();
    _boss.revive();
  }

  @override
  void update(double dt) {
    super.update(dt);
    engine.tick(dt);
    _publishAndRoute();
  }

  void _publishAndRoute() {
    // The widget's State backs Riverpod access; skip until it's mounted.
    if (widgetKey?.currentState == null) return;

    // On the init frame the game mounting forces a GameWidget rebuild, so this
    // can run while the tree is building/laying out. Mutating a provider then
    // trips Riverpod's setState guard ("modified a provider while building"), so
    // defer the publish to after the frame and bail. Steady-state ticks run in
    // the transient (ticker) phase, where writing is safe.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _publishAndRoute());
      return;
    }

    ref.read(combatProvider.notifier).set(engine.snapshot());

    for (final event in engine.drainEvents()) {
      switch (event) {
        case CastEvent():
          _player.playAttack();
        case HitEvent(:final ability, :final amount, :final crit):
          _boss.playHit();
          ref.read(floatingHitProvider.notifier).emit(ability, amount, crit);
        case BossDiedEvent():
          _boss.playDeath();
      }
    }
  }
}
