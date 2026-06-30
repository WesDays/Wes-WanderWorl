import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wes_wanderworl/talents/talent.dart';
import 'package:wes_wanderworl/talents/talent_tree_screen.dart';

void main() {
  testWidgets('talent screen builds with the tree dropdown and tiles', (
    tester,
  ) async {
    // Landscape-ish surface so the horizontal tier rows have room.
    tester.view.physicalSize = const Size(2000, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: TalentTreeScreen(onDone: () {}),
        ),
      ),
    );

    // No layout exception was thrown building the tiers/tiles.
    expect(tester.takeException(), isNull);

    // The tree dropdown is present, and tier-1 Abilities nodes render.
    expect(find.byType(DropdownButton<TalentTree>), findsOneWidget);
    expect(find.text('Sharpened Strikes'), findsOneWidget);

    // Switching trees via the dropdown swaps the visible nodes.
    await tester.tap(find.byType(DropdownButton<TalentTree>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Defense').last);
    await tester.pumpAndSettle();
    expect(find.text('Vitality'), findsOneWidget);
  });
}
