import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The controls are laid out for a phone held upright in portrait.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const GameScreen(),
    );
  }
}
