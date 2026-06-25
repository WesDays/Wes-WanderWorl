import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'actor_component.dart';
import 'placeholder_sprites.dart';

/// Animation states the player can be in. One-shot states (attack, hit) fall
/// back to [idle] when finished; [death] holds.
enum PlayerState { idle, attack, hit, death }

/// The player avatar. Placeholder colour-frame animations stand in for real art;
/// the [ActorComponent] state machine is the part that matters.
class PlayerComponent extends ActorComponent<PlayerState> {
  PlayerComponent() : super(size: Vector2(40, 54));

  @override
  PlayerState get idleState => PlayerState.idle;

  @override
  Set<PlayerState> get holdingStates => const {PlayerState.death};

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
    wireFallbacks();
  }

  void playAttack() => play(PlayerState.attack);

  void playHit() => play(PlayerState.hit);

  void playDeath() => play(PlayerState.death);

  // Force out of the held death frame back to a fresh idle.
  void revive() => play(PlayerState.idle, force: true);
}
