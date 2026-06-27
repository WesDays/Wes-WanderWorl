// Smoke test: the app boots to the main menu, and Start launches the game.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wes_wanderworl/game_screen.dart';
import 'package:wes_wanderworl/main.dart';
import 'package:wes_wanderworl/main_menu_screen.dart';

void main() {
  testWidgets('App boots to the menu, then Start shows the game', (tester) async {
    // The HUD reads engine state through Riverpod, so the app must run inside
    // a ProviderScope (mirrors main()).
    await tester.pumpWidget(const ProviderScope(child: MainApp()));

    expect(find.byType(MainMenuScreen), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(find.byType(GameScreen), findsOneWidget);
  });
}
