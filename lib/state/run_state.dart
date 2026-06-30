import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../talents/talent.dart';

/// The per-run progression that must survive a [GameScreen] remount: the talent
/// ranks allocated this run, banked talent points, and the player health carried
/// into the next encounter. A "run" is one unbroken Continue chain — a defeat or
/// a fresh Start from the menu [wipe]s it.
class RunState {
  const RunState({
    this.ranks = const {},
    this.bankedPoints = 0,
    this.carryoverHealth,
  });

  /// talentId -> current rank (1-based; absent = unallocated).
  final Map<String, int> ranks;

  /// Unspent talent points (1 earned per encounter win).
  final int bankedPoints;

  /// Player health the next encounter should start at, set on victory. Null on a
  /// fresh run, meaning "start at full".
  final int? carryoverHealth;

  int rankOf(String id) => ranks[id] ?? 0;

  RunState copyWith({
    Map<String, int>? ranks,
    int? bankedPoints,
    int? carryoverHealth,
    bool clearCarryover = false,
  }) {
    return RunState(
      ranks: ranks ?? this.ranks,
      bankedPoints: bankedPoints ?? this.bankedPoints,
      carryoverHealth:
          clearCarryover ? null : (carryoverHealth ?? this.carryoverHealth),
    );
  }
}

/// Talent points granted per encounter win. TEMP: bumped to 10 for testing the
/// talent trees; revert to 1 for real play.
const int kPointsPerVictory = 10;

/// TEMP (debug): banked points handed out so the talent trees can be exercised
/// without grinding encounters. Remove together with [RunNotifier.grantDebugPoints]
/// and the menu's debug Talents button.
const int kDebugStartingPoints = 50;

class RunNotifier extends Notifier<RunState> {
  @override
  RunState build() => const RunState();

  /// Total points spent in [tree] — drives tier gating.
  int pointsSpentInTree(TalentTree tree) {
    var total = 0;
    state.ranks.forEach((id, rank) {
      if (talentById(id).tree == tree) total += rank;
    });
    return total;
  }

  /// Whether [tier] (1-4) of [tree] is unlocked given points spent in it.
  bool tierUnlocked(TalentTree tree, int tier) =>
      pointsSpentInTree(tree) >= tierThreshold(tier);

  /// Whether a point can be put into [talentId] right now: a point is banked,
  /// the node isn't maxed, its tier is unlocked, and any prereq is maxed.
  bool canAllocate(String talentId) {
    if (state.bankedPoints <= 0) return false;
    final talent = talentById(talentId);
    if (state.rankOf(talentId) >= talent.maxRank) return false;
    if (!tierUnlocked(talent.tree, talent.tier)) return false;
    final prereq = talent.prereqId;
    if (prereq != null && state.rankOf(prereq) < talentById(prereq).maxRank) {
      return false;
    }
    return true;
  }

  /// Spends one banked point on [talentId]. No-op if [canAllocate] is false.
  void allocate(String talentId) {
    if (!canAllocate(talentId)) return;
    final ranks = Map<String, int>.of(state.ranks);
    ranks[talentId] = (ranks[talentId] ?? 0) + 1;
    state = state.copyWith(ranks: ranks, bankedPoints: state.bankedPoints - 1);
  }

  /// Records an encounter win: grants a talent point and stashes the health the
  /// next encounter should begin at.
  void awardVictory(int carryoverHealth) {
    state = state.copyWith(
      bankedPoints: state.bankedPoints + kPointsPerVictory,
      carryoverHealth: carryoverHealth,
    );
  }

  /// Wipes the whole run (defeat, or a fresh Start from the menu).
  void wipe() => state = const RunState();

  /// TEMP (debug): tops banked points up to [kDebugStartingPoints] so the talent
  /// trees are spendable without playing through encounters. Remove later.
  void grantDebugPoints() {
    if (state.bankedPoints < kDebugStartingPoints) {
      state = state.copyWith(bankedPoints: kDebugStartingPoints);
    }
  }
}

final runStateProvider = NotifierProvider<RunNotifier, RunState>(
  RunNotifier.new,
);
