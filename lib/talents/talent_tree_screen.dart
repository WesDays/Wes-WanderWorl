import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/run_state.dart';
import 'talent.dart';

/// The talent tree, reachable from the victory screen. One tree is shown at a
/// time (picked from the header dropdown); its tiers stack down the screen, and
/// each tier lays its nodes out horizontally so every choice is visible without
/// scrolling within the tier. Tapping a node's + spends a banked point.
class TalentTreeScreen extends ConsumerStatefulWidget {
  const TalentTreeScreen({super.key, required this.onDone});

  /// Returns to the victory screen.
  final VoidCallback onDone;

  @override
  ConsumerState<TalentTreeScreen> createState() => _TalentTreeScreenState();
}

class _TalentTreeScreenState extends ConsumerState<TalentTreeScreen> {
  TalentTree _tree = TalentTree.abilities;

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(runStateProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E16),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                points: run.bankedPoints,
                tree: _tree,
                onTreeChanged: (t) => setState(() => _tree = t),
                onDone: widget.onDone,
              ),
              const SizedBox(height: 8),
              Expanded(child: _TreeView(tree: _tree)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.points,
    required this.tree,
    required this.onTreeChanged,
    required this.onDone,
  });

  final int points;
  final TalentTree tree;
  final ValueChanged<TalentTree> onTreeChanged;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spent = ref.watch(runStateProvider.notifier).pointsSpentInTree(tree);
    return Row(
      children: [
        const Text(
          'Talents',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: points > 0 ? const Color(0xFF1B5E20) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$points point${points == 1 ? '' : 's'} available',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<TalentTree>(
              value: tree,
              isDense: true,
              dropdownColor: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(8),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              items: [
                for (final t in TalentTree.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) {
                if (t != null) onTreeChanged(t);
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$spent spent',
          style: const TextStyle(fontSize: 13, color: Colors.white54),
        ),
        const Spacer(),
        FilledButton(
          onPressed: onDone,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text('Back', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

/// The selected tree: its tiers stacked vertically, each a horizontal row.
class _TreeView extends ConsumerWidget {
  const _TreeView({required this.tree});

  final TalentTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spent = ref.watch(runStateProvider.notifier).pointsSpentInTree(tree);
    final tiers = <int>{for (final t in kTalents) if (t.tree == tree) t.tier};
    final sortedTiers = tiers.toList()..sort();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tier in sortedTiers)
            _TierRow(tree: tree, tier: tier, spentInTree: spent),
        ],
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tree,
    required this.tier,
    required this.spentInTree,
  });

  final TalentTree tree;
  final int tier;
  final int spentInTree;

  @override
  Widget build(BuildContext context) {
    final threshold = tierThreshold(tier);
    final unlocked = spentInTree >= threshold;
    final nodes =
        kTalents.where((t) => t.tree == tree && t.tier == tier).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4, left: 2),
          child: Text(
            unlocked ? 'Tier $tier' : 'Tier $tier — locked ($threshold in tree)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: unlocked ? Colors.white70 : Colors.white30,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // IntrinsicHeight bounds the row's height (= tallest tile) so the
          // tiles can stretch to equal heights; without it, the surrounding
          // scroll views leave height unbounded and stretch throws.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final talent in nodes)
                  _TalentTile(talent: talent, tierUnlocked: unlocked),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TalentTile extends ConsumerWidget {
  const _TalentTile({required this.talent, required this.tierUnlocked});

  final Talent talent;
  final bool tierUnlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(runStateProvider);
    final notifier = ref.watch(runStateProvider.notifier);
    final rank = run.rankOf(talent.id);
    final maxed = rank >= talent.maxRank;
    final canAllocate = notifier.canAllocate(talent.id);

    // The value shown is the next rank's (what a point buys), or the current
    // when maxed.
    final shownRank = maxed ? talent.maxRank : rank + 1;
    final desc = talent.description.replaceAll(
      '{v}',
      _fmt(talent.valueAt(shownRank)),
    );

    final rankText = talent.noCap ? 'Rank $rank' : '$rank / ${talent.maxRank}';
    final status = _status(run, notifier, rank, maxed);

    return Opacity(
      opacity: tierUnlocked ? 1.0 : 0.5,
      child: Container(
        width: 168,
        margin: const EdgeInsets.only(right: 6, bottom: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: maxed ? const Color(0xFF14301A) : Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: canAllocate ? const Color(0xFF66BB6A) : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    talent.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (talent.isEndcap) _tag('endcap', const Color(0xFF8E24AA)),
                if (!talent.wired) _tag('soon', const Color(0xFF616161)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$rankText${status.isEmpty ? '' : '  ·  $status'}',
                    style: TextStyle(
                      fontSize: 10,
                      color: status.isEmpty ? Colors.white38 : Colors.amber,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _PlusButton(
                  enabled: canAllocate,
                  onTap: () => notifier.allocate(talent.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A short reason the node can't take a point right now (empty = available or
  /// simply not yet affordable).
  String _status(RunState run, RunNotifier notifier, int rank, bool maxed) {
    if (maxed) return 'maxed';
    if (!notifier.tierUnlocked(talent.tree, talent.tier)) return 'tier locked';
    final prereq = talent.prereqId;
    if (prereq != null) {
      final prereqTalent = talentById(prereq);
      if (run.rankOf(prereq) < prereqTalent.maxRank) {
        return 'needs ${prereqTalent.name} maxed';
      }
    }
    return '';
  }

  Widget _tag(String label, Color color) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 8)),
    ),
  );
}

class _PlusButton extends StatelessWidget {
  const _PlusButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? const Color(0xFF43A047) : Colors.white12,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.add, size: 18),
        ),
      ),
    );
  }
}

/// Trims trailing-zero decimals so 2.0 -> "2" but 2.5 -> "2.5".
String _fmt(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
