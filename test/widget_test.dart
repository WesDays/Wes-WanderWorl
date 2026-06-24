// Smoke test: the app boots and mounts the game screen without throwing.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wes_wanderworl/game_screen.dart';
import 'package:wes_wanderworl/main.dart';

void main() {
  testWidgets('App boots and shows the game screen', (tester) async {
    // The HUD reads engine state through Riverpod, so the app must run inside
    // a ProviderScope (mirrors main()).
    await tester.pumpWidget(const ProviderScope(child: MainApp()));

    expect(find.byType(GameScreen), findsOneWidget);
  });
}
