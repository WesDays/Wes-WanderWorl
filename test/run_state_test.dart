import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wes_wanderworl/state/run_state.dart';
import 'package:wes_wanderworl/talents/talent.dart';

void main() {
  late ProviderContainer container;
  late RunNotifier run;

  setUp(() {
    container = ProviderContainer();
    run = container.read(runStateProvider.notifier);
  });
  tearDown(() => container.dispose());

  /// Grant points by winning encounters.
  void bank(int n) {
    for (var i = 0; i < n; i++) {
      run.awardVictory(100);
    }
  }

  test('a win banks points and stashes carryover health', () {
    run.awardVictory(4200);
    final state = container.read(runStateProvider);
    expect(state.bankedPoints, kPointsPerVictory);
    expect(state.carryoverHealth, 4200);
  });

  test('allocate spends a point and raises the rank', () {
    bank(1);
    run.allocate('A1');
    final state = container.read(runStateProvider);
    expect(state.rankOf('A1'), 1);
    expect(state.bankedPoints, kPointsPerVictory - 1);
  });

  test('cannot allocate with no banked points', () {
    expect(run.canAllocate('A1'), isFalse);
    run.allocate('A1');
    expect(container.read(runStateProvider).rankOf('A1'), 0);
  });

  test('tier 2 stays locked until 6 points are spent in the tree', () {
    bank(20);
    // F3 is an Abilities tier-2 node.
    expect(run.canAllocate('F3'), isFalse);
    // Spend 6 in Abilities via tier-1 nodes (A1 x5, then I1 x1).
    for (var i = 0; i < 5; i++) {
      run.allocate('A1');
    }
    run.allocate('I1');
    expect(run.pointsSpentInTree(TalentTree.abilities), 6);
    expect(run.canAllocate('F3'), isTrue);
  });

  test('a prereq node is locked until its parent is maxed', () {
    bank(30);
    // Unlock Misc tier 3 (needs 14 in tree) by maxing tier-1/2 nodes.
    for (final id in ['E4', 'B2', 'A5', 'E1', 'D1']) {
      final t = talentById(id);
      for (var i = 0; i < t.maxRank; i++) {
        run.allocate(id);
      }
    }
    expect(run.pointsSpentInTree(TalentTree.misc) >= 14, isTrue);
    // B3 requires B2 maxed — B2 was maxed above, so B3 is now allocatable.
    expect(run.canAllocate('B3'), isTrue);
  });

  test('wipe clears ranks and points', () {
    bank(3);
    run.allocate('A1');
    run.wipe();
    final state = container.read(runStateProvider);
    expect(state.bankedPoints, 0);
    expect(state.ranks, isEmpty);
    expect(state.carryoverHealth, isNull);
  });
}
