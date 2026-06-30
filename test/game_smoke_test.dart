import 'package:flutter_test/flutter_test.dart';
import 'package:wes_wanderworl/game/wanderworld_game.dart';
import 'package:wes_wanderworl/game_screen.dart';

// Compiles the full Flame + flame_riverpod import graph and checks the game
// constructs with a fresh engine. (Rendering needs a real device, so we don't
// pump the GameWidget here.)
void main() {
  test('WanderworldGame constructs with a live engine', () {
    final game = WanderworldGame();
    expect(game.engine.bossHealth, greaterThan(0));
    expect(game.engine.resource, greaterThan(0));
  });

  test('GameScreen can be instantiated', () {
    expect(
      GameScreen(onExitToMenu: () {}, onEncounterEnded: (_, _) {}),
      isA<GameScreen>(),
    );
  });
}
