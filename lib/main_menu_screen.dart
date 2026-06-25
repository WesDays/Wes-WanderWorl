import 'package:flutter/material.dart';

/// The game's landing page, shown on launch and returned to when a run ends.
/// For now it just starts a new run; talents and stats areas will hang off here
/// later, so it's a full screen rather than a dialog.
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key, required this.onStart});

  /// Begins a new run, handing control to the combat screen.
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E16),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Wanderworld',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: onStart,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  child: Text('Start', style: TextStyle(fontSize: 22)),
                ),
              ),
              // Talents / stats areas will live here later.
            ],
          ),
        ),
      ),
    );
  }
}
