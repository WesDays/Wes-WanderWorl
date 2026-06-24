import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'placeholder_sprites.dart';

/// Animation states the player can be in. One-shot states (attack, hit) fall
/// back to [idle] when finished; [death] holds.
enum PlayerState { idle, attack, hit, death }

/// The player avatar. Placeholder colour-frame animations stand in for real art;
/// the [SpriteAnimationGroupComponent] state machine is the part that matters.
class PlayerComponent extends SpriteAnimationGroupComponent<PlayerState> {
  PlayerComponent()
    : super(anchor: Anchor.center, size: Vector2(96, 128));

  @override
  Future<void> onLoad() async {
    animations = {
      PlayerState.idle: await placeholderAnim(
        [const Color(0xFF29B6F6), const Color(0xFF4FC3F7)],
        stepTime: 0.45,
      ),
      PlayerState.attack: await placeholderAnim(
        [const Color(0xFFB3E5FC), const Color(0xFFFFFFFF)],
        stepTime: 0.06,
        loop: false,
      ),
      PlayerState.hit: await placeholderAnim(
        [const Color(0xFFFF8A80)],
        stepTime: 0.18,
        loop: false,
      ),
      PlayerState.death: await placeholderAnim(
        [const Color(0xFF455A64)],
        stepTime: 0.3,
        loop: false,
      ),
    };
    current = PlayerState.idle;

    // Return to idle when a one-shot finishes.
    for (final state in [PlayerState.attack, PlayerState.hit]) {
      animationTickers?[state]?.onComplete = () {
        if (current == state) current = PlayerState.idle;
      };
    }
  }

  void playAttack() {
    if (current == PlayerState.death) return;
    animationTickers?[PlayerState.attack]?.reset();
    current = PlayerState.attack;
  }
}
