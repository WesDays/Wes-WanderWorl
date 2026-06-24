import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_riverpod/flame_riverpod.dart';
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
    _player = PlayerComponent()..position = Vector2(-320, 40);
    _boss = BossComponent()..position = Vector2(320, 20);
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

    final snapshot = engine.snapshot();
    final events = engine.drainEvents();

    // Drive component animations now — these are Flame-side and safe inside the
    // game loop.
    for (final event in events) {
      switch (event) {
        case CastEvent():
          _player.playAttack();
        case HitEvent():
          _boss.playHit();
        case BossDiedEvent():
          _boss.playDeath();
      }
    }

    // Flame runs update() inside the GameWidget's layout callback, so the widget
    // tree is locked; modifying a provider here throws. Defer the provider
    // writes until just after the frame is built.
    Future(() {
      ref.read(combatProvider.notifier).set(snapshot);
      for (final event in events) {
        if (event case HitEvent(:final ability, :final amount, :final crit)) {
          ref.read(floatingHitProvider.notifier).emit(ability, amount, crit);
        }
      }
    });
  }
}
