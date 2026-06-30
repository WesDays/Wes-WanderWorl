import 'package:flutter/material.dart';

/// A single player ability. For now this is just presentation data —
/// behaviour (damage, cooldown-per-ability, etc.) can be layered on later.
class Ability {
  const Ability({
    required this.name,
    required this.icon,
    required this.color,
    this.iconAsset,
    this.iconAssetSize = 30,
    this.iconAssetOffset = Offset.zero,
    this.cost = 40,
    this.setsResourceTo,
    this.grantsAbilityPoint = false,
    this.consumesAbilityPoints = false,
    this.requiresAbilityPoints = false,
    this.appliesRend = false,
    this.extendsRend = false,
    this.appliesBuff = false,
    this.damage = 0,
    this.damageByPoints,
    this.heals = 0,
    this.canCrit = true,
    this.coreDamage = false,
    this.opensPauseMenu = false,
  });

  final String name;
  final IconData icon;
  final Color color;

  /// Optional image asset shown in place of [icon]. [icon] stays as a fallback.
  final String? iconAsset;

  /// Rendered size of [iconAsset] inside the ability button.
  final double iconAssetSize;

  /// Pixel nudge for [iconAsset] inside the button (negative dx = left,
  /// negative dy = up). Lets art be re-centred without editing the file.
  final Offset iconAssetOffset;

  /// Resource consumed when the ability is used.
  final int cost;

  /// If set, using this ability sets the resource pool to this value outright
  /// (instead of paying [cost]).
  final int? setsResourceTo;

  /// Whether using this ability grants one ability point (capped at the max).
  final bool grantsAbilityPoint;

  /// Whether using this ability spends all currently held ability points.
  final bool consumesAbilityPoints;

  /// Whether this ability is unusable while no ability points are held.
  final bool requiresAbilityPoints;

  /// Whether using this ability applies the timed Rend effect.
  final bool appliesRend;

  /// Whether using this ability extends an already-active Rend's duration.
  final bool extendsRend;

  /// Whether using this ability applies the timed Buff effect, whose
  /// duration scales with the ability points held at cast time.
  final bool appliesBuff;

  /// Flat damage dealt per cast. Point-scaled abilities leave this 0 and use
  /// [damageByPoints] instead.
  final int damage;

  /// Damage indexed by ability points spent at cast (index 0 = 1 point …
  /// index 4 = 5 points). Instant for Blast; the per-tick amount for Rend.
  final List<int>? damageByPoints;

  /// Health restored to the player per cast.
  final int heals;

  /// Whether this ability's damage can roll a critical hit.
  final bool canCrit;

  /// Whether this is one of the core damage abilities (Attack/Rend/Blast) that
  /// the A1 talent's damage bonus applies to.
  final bool coreDamage;

  /// Whether pressing this button opens the pause menu instead of casting. Such
  /// a button is purely UI: it touches no combat state (resource, cooldown, …).
  final bool opensPauseMenu;

  /// Whether this ability deals damage at all — flat [damage] or a
  /// point-scaled [damageByPoints] table (covers instant hits and Rend's ticks).
  bool get dealsDamage => damage > 0 || damageByPoints != null;

  /// Damage for [points] spent: the [damageByPoints] entry when point-scaled
  /// (clamped to the table, 0 when no points), otherwise the flat [damage].
  int damageFor(int points) {
    final table = damageByPoints;
    if (table == null) return damage;
    if (points <= 0) return 0;
    return table[(points - 1).clamp(0, table.length - 1)];
  }
}

/// The player's 7 abilities. Order here is the order shown down the edge.
const List<Ability> kAbilities = <Ability>[
  Ability(
    name: 'Energize',
    icon: Icons.bolt,
    color: Color(0xFFE53935),
    cost: 0,
    setsResourceTo: 60,
  ),
  // Heal deals a little damage on purpose so it counts as a damaging ability and
  // can consume the free-ability proc; canCrit is off so that chip damage stays flat.
  Ability(
    name: 'Heal',
    icon: Icons.healing,
    color: Color(0xFF29B6F6),
    cost: 40,
    grantsAbilityPoint: true,
    damage: 350,
    heals: 2000,
    canCrit: false,
  ),
  Ability(
    name: 'Pause',
    icon: Icons.pause,
    color: Color(0xFFFDD835),
    opensPauseMenu: true,
  ),
  Ability(
    name: 'Attack',
    icon: Icons.gps_fixed,
    iconAsset: 'assets/icons/attack_icon.png',
    color: Color(0xFF66BB6A),
    cost: 42,
    grantsAbilityPoint: true,
    extendsRend: true,
    damage: 3300,
    coreDamage: true,
  ),
  Ability(
    name: 'Rend',
    icon: Icons.content_cut,
    iconAsset: 'assets/icons/rend_icon.png',
    iconAssetSize: 40,
    iconAssetOffset: Offset(0, -4),
    color: Color(0xFF7E57C2),
    cost: 30,
    consumesAbilityPoints: true,
    requiresAbilityPoints: true,
    appliesRend: true,
    coreDamage: true,
    // Per-tick damage, dealt every kRendResourceInterval while active.
    damageByPoints: [420, 690, 960, 1230, 1500],
  ),
  Ability(
    name: 'Blast',
    icon: Icons.flare,
    color: Color(0xFF26C6DA),
    cost: 35,
    consumesAbilityPoints: true,
    requiresAbilityPoints: true,
    coreDamage: true,
    damageByPoints: [1160, 1900, 2600, 3400, 4150],
  ),
  Ability(
    name: 'Buff',
    icon: Icons.upgrade,
    iconAsset: 'assets/icons/buff_icon.png',
    iconAssetSize: 65,
    iconAssetOffset: Offset(-1.5, -1),
    color: Color(0xFFFF7043),
    cost: 25,
    consumesAbilityPoints: true,
    appliesBuff: true,
  ),
];
