import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'placeholder_sprites.dart';

/// Boss animation states. [hit] is a one-shot flash back to [idle]; [death]
/// holds once the boss dies.
enum BossState { idle, hit, death }

/// The boss avatar. Placeholder colour-frame animations; the real
/// [SpriteAnimationGroupComponent] state machine drives hit/death reactions.
class BossComponent extends SpriteAnimationGroupComponent<BossState> {
  BossComponent()
    : super(anchor: Anchor.center, size: Vector2(176, 220));

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

    animationTickers?[BossState.hit]?.onComplete = () {
      if (current == BossState.hit) current = BossState.idle;
    };
  }

  void playHit() {
    if (current == BossState.death) return;
    animationTickers?[BossState.hit]?.reset();
    current = BossState.hit;
  }

  void playDeath() => current = BossState.death;

  void revive() => current = BossState.idle;
}
