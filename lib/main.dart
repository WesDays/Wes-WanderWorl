import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game/combat_engine.dart' show kPlayerMaxHealth;
import 'game_screen.dart';
import 'main_menu_screen.dart';
import 'screens/encounter_end_screen.dart';
import 'state/run_state.dart';
import 'talents/talent_modifiers.dart';
import 'talents/talent_tree_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The game is a side-scroller designed for a phone held in landscape.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const _AppShell(),
    );
  }
}

/// Top-level navigation across the menu, an active encounter, the victory/defeat
/// landing, and the talent tree. Combat state lives in the engine; the per-run
/// progression (talents, banked points, carry-over HP) lives in [runStateProvider]
/// so it survives [GameScreen] remounts. Each encounter mounts a fresh GameScreen
/// (keyed by [_encounterId]) and thus a fresh engine seeded with the run's talents.
class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

enum _Screen { menu, playing, victory, defeat, talents }

class _AppShellState extends ConsumerState<_AppShell> {
  _Screen _screen = _Screen.menu;

  /// Bumped each time an encounter starts, so the GameScreen (and its engine)
  /// is always rebuilt fresh rather than reused.
  int _encounterId = 0;

  /// Config for the encounter currently being mounted.
  TalentModifiers _modifiers = const TalentModifiers();
  int? _startingHealth;

  RunNotifier get _run => ref.read(runStateProvider.notifier);

  /// Start a brand-new run from the menu: wipe the loadout, full HP.
  void _startFreshRun() {
    _run.wipe();
    setState(() {
      _modifiers = resolveModifiers(const {});
      _startingHealth = null;
      _encounterId++;
      _screen = _Screen.playing;
    });
  }

  void _onEncounterEnded(bool won, int remainingHealth) {
    if (won) {
      _run.awardVictory(remainingHealth);
      setState(() => _screen = _Screen.victory);
    } else {
      setState(() => _screen = _Screen.defeat);
    }
  }

  /// Next encounter after a victory: carry HP forward plus half the missing HP.
  void _continue() {
    final run = ref.read(runStateProvider);
    final mods = resolveModifiers(run.ranks);
    final maxHp = (kPlayerMaxHealth * mods.maxHpMultiplier).round();
    final current = run.carryoverHealth ?? maxHp;
    final startHealth = (current + (maxHp - current) * 0.5).round();
    setState(() {
      _modifiers = mods;
      _startingHealth = startHealth;
      _encounterId++;
      _screen = _Screen.playing;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_screen) {
      _Screen.menu => MainMenuScreen(onStart: _startFreshRun),
      _Screen.playing => GameScreen(
        key: ValueKey(_encounterId),
        modifiers: _modifiers,
        startingHealth: _startingHealth,
        // Pause -> Main Menu abandons the run in place; the next Start wipes it.
        onExitToMenu: () => setState(() => _screen = _Screen.menu),
        onEncounterEnded: _onEncounterEnded,
      ),
      _Screen.victory => EncounterEndScreen(
        won: true,
        onContinue: _continue,
        onTalents: () => setState(() => _screen = _Screen.talents),
        onMainMenu: () => setState(() => _screen = _Screen.menu),
      ),
      _Screen.defeat => EncounterEndScreen(
        won: false,
        onContinue: () {},
        onTalents: () {},
        // Defeat ends the run: wipe the loadout on the way out.
        onMainMenu: () {
          _run.wipe();
          setState(() => _screen = _Screen.menu);
        },
      ),
      _Screen.talents => TalentTreeScreen(
        onDone: () => setState(() => _screen = _Screen.victory),
      ),
    };
  }
}
