import 'package:flame/components.dart';

/// Shared animation state machine for world actors (player, boss, …). Holds the
/// [SpriteAnimationGroupComponent] wiring every actor repeats: one-shot states
/// return to [idleState] when finished, [holdingStates] stay on their final
/// frame, and [play] resets a state's ticker so one-shots replay on every call.
abstract class ActorComponent<T> extends SpriteAnimationGroupComponent<T> {
  ActorComponent({required Vector2 size})
    : super(anchor: Anchor.center, size: size);

  /// Resting state; one-shot animations fall back here on completion.
  T get idleState;

  /// States that hold their final frame instead of returning to idle (death).
  /// The actor stays in these until [play] is called with `force`.
  Set<T> get holdingStates => const {};

  /// Wires every non-holding state to return to [idleState] when it finishes.
  /// Looping states never complete, so wiring them is a harmless no-op. Call
  /// once after [animations] is populated.
  void wireFallbacks() {
    animationTickers?.forEach((state, ticker) {
      if (holdingStates.contains(state)) return;
      ticker.onComplete = () {
        if (current == state) current = idleState;
      };
    });
  }

  /// Plays [state] from its first frame, resetting its ticker so one-shot
  /// animations replay even after a previous run finished. Ignored while in a
  /// holding state (e.g. death) unless [force] is set — reviving must force the
  /// actor back out of its death frame.
  void play(T state, {bool force = false}) {
    final c = current;
    if (!force && c != null && holdingStates.contains(c)) return;
    animationTickers?[state]?.reset();
    current = state;
  }
}
