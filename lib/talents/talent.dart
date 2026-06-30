// Static talent catalog, transcribed from Talent_Trees_v1.txt. This is data
// only: the Talent model carries each node's tree/tier/ranks/prereqs, and
// kTalents is the full 3-tree list. Combat effects are resolved separately in
// talent_modifiers.dart; run-time allocation lives in state/run_state.dart.

/// Sentinel max rank for "no cap" endcaps — they take points indefinitely.
const int kUncapped = 9999;

enum TalentTree { abilities, defense, misc }

extension TalentTreeLabel on TalentTree {
  String get label => switch (this) {
    TalentTree.abilities => 'Abilities',
    TalentTree.defense => 'Defense',
    TalentTree.misc => 'Misc',
  };
}

/// Points that must be spent **in a tree** before [tier] (1-4) unlocks. Tier 1
/// is always open; the rest gate at 6 / 14 / 22 (see Talent_Trees_v1.txt).
int tierThreshold(int tier) => switch (tier) {
  <= 1 => 0,
  2 => 6,
  3 => 14,
  _ => 22,
};

/// One node in a talent tree. IDs match the source ideas file (A1, C2, K7, …);
/// the lone added node is `block`.
class Talent {
  const Talent({
    required this.id,
    required this.tree,
    required this.tier,
    required this.name,
    required this.description,
    required this.rankValues,
    this.prereqId,
    this.isEndcap = false,
    this.noCap = false,
    this.wired = false,
  });

  final String id;
  final TalentTree tree;

  /// Tier band 1-4; gates by points-spent-in-tree via [tierThreshold].
  final int tier;

  final String name;
  final String description;

  /// Per-rank numbers from the design doc. For [noCap] nodes this is the single
  /// per-rank increment, applied repeatedly.
  final List<num> rankValues;

  /// Another talent's [id] that must be MAXED before this unlocks (the `#-#`
  /// convention), or null.
  final String? prereqId;

  /// Endcap node (the `E` convention). Purely informational for the UI/ordering.
  final bool isEndcap;

  /// "No cap" endcap that accepts points indefinitely.
  final bool noCap;

  /// Whether this pass actually feeds combat. Batch-A nodes are true; everything
  /// else is allocatable but inert until a later batch wires it.
  final bool wired;

  int get maxRank => noCap ? kUncapped : rankValues.length;

  /// The node's value at [rank] (1-based); 0 when unallocated. Clamps to the
  /// last entry so [noCap] nodes keep returning their per-rank increment.
  num valueAt(int rank) =>
      rank <= 0 ? 0 : rankValues[(rank - 1).clamp(0, rankValues.length - 1)];
}

/// The full talent catalog across all three trees.
const List<Talent> kTalents = <Talent>[
  // ======================= TREE 1 — ABILITIES =======================
  // Tier 1
  Talent(
    id: 'A1', tree: TalentTree.abilities, tier: 1, wired: true,
    name: 'Sharpened Strikes',
    description: '+{v}% damage to Attack, Rend, and Blast.',
    rankValues: [2, 4, 6, 8, 10],
  ),
  Talent(
    id: 'C1', tree: TalentTree.abilities, tier: 1, wired: true,
    name: 'Keen Eye',
    description: '+{v}% crit chance.',
    rankValues: [2.5, 5, 8],
  ),
  Talent(
    id: 'I1', tree: TalentTree.abilities, tier: 1, wired: true,
    name: 'Empowered Buff',
    description: '+{v}% Buff damage bonus.',
    rankValues: [2, 4, 6, 8, 10],
  ),
  // Tier 2
  Talent(
    id: 'F3', tree: TalentTree.abilities, tier: 2,
    name: 'Lingering Wounds',
    description: 'Attack: {v}% chance to extend Rend by 3s instead of 2s.',
    rankValues: [20, 40, 60, 80, 100],
  ),
  Talent(
    id: 'G2', tree: TalentTree.abilities, tier: 2,
    name: 'Deep Rend',
    description: '+{v}s Rend base duration.',
    rankValues: [1, 2, 3, 4, 5],
  ),
  Talent(
    id: 'H3', tree: TalentTree.abilities, tier: 2,
    name: 'Overcharge',
    description: 'Blast: {v}% chance to deal an additional 50% damage.',
    rankValues: [1, 2, 3, 4, 5],
  ),
  Talent(
    id: 'I2', tree: TalentTree.abilities, tier: 2, wired: true,
    name: 'Lasting Buff',
    description: '+{v}s Buff duration.',
    rankValues: [1, 2, 3, 4, 5],
  ),
  Talent(
    id: 'A3', tree: TalentTree.abilities, tier: 2,
    name: 'Momentum',
    description: '+{v}% stacking damage (max 3) for casting under 1.4s apart.',
    rankValues: [1, 2, 3],
  ),
  // Tier 3
  Talent(
    id: 'C2', tree: TalentTree.abilities, tier: 3, wired: true,
    name: 'Brutal Crits',
    description: 'Crits deal {v}x damage.',
    rankValues: [2.1, 2.2, 2.3, 2.4, 2.5],
  ),
  Talent(
    id: 'C6', tree: TalentTree.abilities, tier: 3,
    name: 'Bloodlust',
    description: '+{v}% crit chance per point consumed on Rend & Blast.',
    rankValues: [3],
  ),
  Talent(
    id: 'C3', tree: TalentTree.abilities, tier: 3,
    name: 'Bloodthirst',
    description: 'Crits grant {v} resources.',
    rankValues: [1, 2, 3, 4, 5],
  ),
  Talent(
    id: 'G3', tree: TalentTree.abilities, tier: 3,
    name: 'Rending Frenzy',
    description: '+{v} Rend max ticks from Attack (11 total).',
    rankValues: [1, 2, 3, 4, 5],
  ),
  Talent(
    id: 'G4', tree: TalentTree.abilities, tier: 3,
    name: 'Bloodied Edge',
    description: 'Rend ticks: {v}% chance to add 2 resource.',
    rankValues: [20, 40, 60, 80, 100],
  ),
  Talent(
    id: 'H2', tree: TalentTree.abilities, tier: 3,
    name: 'Critical Burst',
    description: '+{v}x Blast crit multiplier.',
    rankValues: [0.2, 0.4, 0.6, 0.8, 1.0],
  ),
  Talent(
    id: 'I3', tree: TalentTree.abilities, tier: 3,
    name: 'Sustained Power',
    description: 'Rend/Blast: {v}% per point consumed to extend Buff by 2s.',
    rankValues: [4, 8, 12, 16, 20],
  ),
  Talent(
    id: 'A4', tree: TalentTree.abilities, tier: 3,
    name: 'Building Force',
    description: 'Every {v} casts, next ability +20% damage.',
    rankValues: [15, 12, 9],
  ),
  // Tier 4 — capstones
  Talent(
    id: 'F1', tree: TalentTree.abilities, tier: 4, isEndcap: true, noCap: true,
    name: 'Endless Assault',
    description: '+{v}% Attack damage (no cap).',
    rankValues: [2.5],
  ),
  Talent(
    id: 'G1', tree: TalentTree.abilities, tier: 4, isEndcap: true, noCap: true,
    name: 'Endless Bleed',
    description: '+{v}% Rend tick damage (no cap).',
    rankValues: [2.5],
  ),
  Talent(
    id: 'H1', tree: TalentTree.abilities, tier: 4, isEndcap: true, noCap: true,
    name: 'Endless Blast',
    description: '+{v}% Blast damage (no cap).',
    rankValues: [2.5],
  ),
  Talent(
    id: 'C4', tree: TalentTree.abilities, tier: 4,
    name: 'Killing Spree',
    description: '3 Attack/Blast crits in a row: next ability x2 (multiplicative).',
    rankValues: [2],
  ),
  Talent(
    id: 'C5', tree: TalentTree.abilities, tier: 4, isEndcap: true, prereqId: 'C2',
    name: 'Free Flow',
    description: 'Attack crits: {v}% chance to grant a free-cast.',
    rankValues: [0.5, 1, 1.5, 2, 2.5],
  ),

  // ======================= TREE 2 — DEFENSE =======================
  // Tier 1
  Talent(
    id: 'K1', tree: TalentTree.defense, tier: 1, isEndcap: true, noCap: true,
    wired: true,
    name: 'Vitality',
    description: '+{v}% max HP (no cap).',
    rankValues: [10],
  ),
  Talent(
    id: 'J5', tree: TalentTree.defense, tier: 1, wired: true,
    name: 'Regeneration',
    description: 'Regenerate {v} HP per second.',
    rankValues: [10, 20, 30, 40, 50],
  ),
  Talent(
    id: 'B6', tree: TalentTree.defense, tier: 1,
    name: 'Warm-Up',
    description: '-10% damage taken for the first {v}s of an encounter.',
    rankValues: [5, 10, 15, 20, 25],
  ),
  // Tier 2
  Talent(
    id: 'K2', tree: TalentTree.defense, tier: 2,
    name: 'Evasion',
    description: '+{v}% dodge chance.',
    rankValues: [2.5, 5, 8],
  ),
  Talent(
    id: 'K6', tree: TalentTree.defense, tier: 2,
    name: 'Tempered Hide',
    description: 'Reduce boss crit multiplier to {v}x.',
    rankValues: [1.9, 1.8, 1.7],
  ),
  Talent(
    id: 'J3', tree: TalentTree.defense, tier: 2,
    name: 'Desperate Mending',
    description: '+{v}% healing while below 30% HP.',
    rankValues: [20, 40, 60, 80, 100],
  ),
  Talent(
    id: 'H4', tree: TalentTree.defense, tier: 2,
    name: 'Stagger',
    description: 'Blast delays the boss\'s next attack by {v}s.',
    rankValues: [0.2, 0.4, 0.6, 0.8, 1.0],
  ),
  Talent(
    id: 'B5', tree: TalentTree.defense, tier: 2,
    name: 'First Blood Ward',
    description: '{v}% chance to avoid the first hit in the first 10s.',
    rankValues: [20, 40, 60, 80, 100],
  ),
  Talent(
    id: 'block', tree: TalentTree.defense, tier: 2,
    name: 'Block',
    description: '{v}% chance to halve an incoming hit (crits included).',
    rankValues: [2, 4, 6, 8, 10],
  ),
  // Tier 3
  Talent(
    id: 'K3', tree: TalentTree.defense, tier: 3,
    name: 'Bracing',
    description: 'Each second un-hit: next hit -{v}% (stacks 10x).',
    rankValues: [1, 2, 3],
  ),
  Talent(
    id: 'K5', tree: TalentTree.defense, tier: 3,
    name: 'Retaliation',
    description: 'Boss crit on you: +100% crit on your next Attack/Blast.',
    rankValues: [1],
  ),
  Talent(
    id: 'J1', tree: TalentTree.defense, tier: 3, isEndcap: true, noCap: true,
    name: 'Endless Mending',
    description: '+{v}% healing (no cap).',
    rankValues: [2.5],
  ),
  Talent(
    id: 'H5', tree: TalentTree.defense, tier: 3,
    name: 'Weakening Blast',
    description: 'Blast reduces boss damage {v}% for 5s.',
    rankValues: [10, 20, 30, 40, 50],
  ),
  Talent(
    id: 'F2', tree: TalentTree.defense, tier: 3,
    name: 'Lifesteal',
    description: 'Attack crit at 5 points heals {v}% of damage done.',
    rankValues: [0.5, 1, 1.5, 2, 2.5],
  ),
  // Tier 4 — capstones
  Talent(
    id: 'K7', tree: TalentTree.defense, tier: 4,
    name: 'Aegis',
    description: '-{v}% damage per point consumed, 1s after Rend/Blast.',
    rankValues: [4, 8, 12, 16, 20],
  ),
  Talent(
    id: 'J2', tree: TalentTree.defense, tier: 4, isEndcap: true, noCap: true,
    name: 'Searing Mends',
    description: '+{v}% Heal damage (no cap).',
    rankValues: [10],
  ),
  Talent(
    id: 'J4', tree: TalentTree.defense, tier: 4,
    name: 'Overflow',
    description: 'Overheal becomes a HoT for {v}% over 6s (once / 10s).',
    rankValues: [100, 150, 200],
  ),
  Talent(
    id: 'K4', tree: TalentTree.defense, tier: 4, isEndcap: true, prereqId: 'K3',
    name: 'Cheat Death',
    description: 'A killing blow leaves you at 1 HP instead (once / encounter).',
    rankValues: [1],
  ),

  // ======================= TREE 3 — MISC =======================
  // Tier 1
  Talent(
    id: 'E4', tree: TalentTree.misc, tier: 1, wired: true,
    name: 'Quick Recovery',
    description: '+{v} resource regen per tick.',
    rankValues: [3, 6, 10],
  ),
  Talent(
    id: 'B2', tree: TalentTree.misc, tier: 1, wired: true,
    name: 'Prepared',
    description: 'Start each encounter with {v} ability points.',
    rankValues: [1, 2, 3, 4, 5],
  ),
  Talent(
    id: 'A5', tree: TalentTree.misc, tier: 1,
    name: 'Fleet Footed',
    description: '+{v}% player speed.',
    rankValues: [10, 20],
  ),
  // Tier 2
  Talent(
    id: 'E1', tree: TalentTree.misc, tier: 2, wired: true,
    name: 'Efficiency',
    description: 'All finishers cost {v} less.',
    rankValues: [1, 2, 3, 4, 5],
  ),
  Talent(
    id: 'E3', tree: TalentTree.misc, tier: 2,
    name: 'Trickle',
    description: 'Passive trickle: {v}% chance to proc +2 resource.',
    rankValues: [20, 40, 60],
  ),
  Talent(
    id: 'D1', tree: TalentTree.misc, tier: 2, wired: true,
    name: 'Surge',
    description: 'Energize sets energy to {v} instead of 60.',
    rankValues: [62, 64, 66, 68, 70],
  ),
  Talent(
    id: 'B1', tree: TalentTree.misc, tier: 2,
    name: 'Opening Burst',
    description: '+{v}% damage to all abilities in the first 5s.',
    rankValues: [5, 10, 15, 20, 25],
  ),
  Talent(
    id: 'A2', tree: TalentTree.misc, tier: 2,
    name: 'Execute',
    description: '+{v}% damage to the boss below 25% HP.',
    rankValues: [20, 25, 30],
  ),
  // Tier 3
  Talent(
    id: 'E2', tree: TalentTree.misc, tier: 3, wired: true,
    name: 'Deep Reserves',
    description: 'Max resource is now {v}.',
    rankValues: [110, 120, 130],
  ),
  Talent(
    id: 'D2', tree: TalentTree.misc, tier: 3,
    name: 'Energized Mind',
    description: 'Energize: {v}% chance to add an ability point.',
    rankValues: [20, 40, 60, 80, 100],
  ),
  Talent(
    id: 'D4', tree: TalentTree.misc, tier: 3,
    name: 'Overdrive',
    description: 'Energize above 60% max: +{v}% damage for 10s.',
    rankValues: [3, 6, 10],
  ),
  Talent(
    id: 'E5', tree: TalentTree.misc, tier: 3,
    name: 'Lucky Casts',
    description: '+{v}% free-cast chance per second.',
    rankValues: [0.2, 0.4, 0.6, 0.8, 1.0],
  ),
  Talent(
    id: 'B3', tree: TalentTree.misc, tier: 3, prereqId: 'B2',
    name: 'Pre-Buffed',
    description: 'Start with {v} points worth of Buff active.',
    rankValues: [1, 2, 3, 4, 5],
  ),
  // Tier 4 — capstones
  Talent(
    id: 'D3', tree: TalentTree.misc, tier: 4,
    name: 'Spark',
    description: 'Energize: {v}% chance to proc a free-cast.',
    rankValues: [3, 6, 10],
  ),
  Talent(
    id: 'E6', tree: TalentTree.misc, tier: 4,
    name: 'Refund',
    description: 'Free-cast Rend/Blast/Buff: {v}% per point to return 10 resource.',
    rankValues: [4, 8, 12, 16, 20],
  ),
  Talent(
    id: 'B4', tree: TalentTree.misc, tier: 4, prereqId: 'B3',
    name: 'Ambush',
    description: '+{v}% crit chance on the first ability.',
    rankValues: [20, 30, 40, 50, 60],
  ),
  Talent(
    id: 'F4', tree: TalentTree.misc, tier: 4, isEndcap: true,
    name: 'Relentless',
    description: 'Attack crits reduce the Global CD by {v}s for that cast.',
    rankValues: [0.02, 0.04, 0.06, 0.08, 0.1],
  ),
];

/// Lookup by id; throws if the id is unknown (catalog is static, so a miss is a
/// programming error).
Talent talentById(String id) => kTalents.firstWhere((t) => t.id == id);
