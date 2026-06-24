import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'actor_component.dart';
import 'placeholder_sprites.dart';

/// Boss animation states. [hit] is a one-shot flash back to [idle]; [death]
/// holds once the boss dies.
enum BossState { idle, hit, death }

/// The boss avatar. Placeholder colour-frame animations; the [ActorComponent]
/// state machine drives hit/death reactions.
class BossComponent extends ActorComponent<BossState> {
  BossComponent() : super(size: Vector2(60, 75));

  @override
  BossState get idleState => BossState.idle;

  @override
  Set<BossState> get holdingStates => const {BossState.death};

  @override
  Future<void> onLoad() async {
    animations = {
      BossState.idle: await placeholderAnim(
        [const Color(0xFFE53935), const Color(0xFFC62828)],
        stepTime: 0.5,
      ),
      BossState.hit: await placeholderAnim(
        [const Color(0xFFFFFFFF)],
        stepTime: 0.12,
        loop: false,
      ),
      BossState.death: await placeholderAnim(
        [const Color(0xFF37474F)],
        stepTime: 0.3,
        loop: false,
      ),
    };
    current = BossState.idle;
    wireFallbacks();
  }

  void playHit() => play(BossState.hit);

  void playDeath() => play(BossState.death);

  // Force out of the held death frame back to a fresh idle.
  void revive() => play(BossState.idle, force: true);
}
