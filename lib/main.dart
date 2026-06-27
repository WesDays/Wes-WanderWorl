import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game_screen.dart';
import 'main_menu_screen.dart';

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

/// Top-level navigation between the menu and an active run. Combat state lives
/// in the engine; this only tracks which screen is showing. Each run mounts a
/// fresh [GameScreen] (and thus a fresh game/engine), so returning to the menu
/// and starting again begins from a clean state with no reset plumbing.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

enum _Screen { menu, playing }

class _AppShellState extends State<_AppShell> {
  _Screen _screen = _Screen.menu;

  @override
  Widget build(BuildContext context) {
    return switch (_screen) {
      _Screen.menu => MainMenuScreen(
        onStart: () => setState(() => _screen = _Screen.playing),
      ),
      _Screen.playing => GameScreen(
        onExitToMenu: () => setState(() => _screen = _Screen.menu),
      ),
    };
  }
}
