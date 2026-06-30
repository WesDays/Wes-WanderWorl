import 'package:flutter/material.dart';

/// The page shown when an encounter ends, owned by the app shell (not the game)
/// so it sits apart from the in-run pause overlay. Victory offers Continue /
/// Talents / Main Menu; defeat — which wipes the run — offers only Main Menu.
class EncounterEndScreen extends StatelessWidget {
  const EncounterEndScreen({
    super.key,
    required this.won,
    required this.onContinue,
    required this.onTalents,
    required this.onMainMenu,
  });

  final bool won;

  /// Starts the next encounter carrying health forward (victory only).
  final VoidCallback onContinue;

  /// Opens the talent tree to spend banked points (victory only).
  final VoidCallback onTalents;

  final VoidCallback onMainMenu;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E16),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                won ? 'Victory' : 'Defeat',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: won ? const Color(0xFF66BB6A) : const Color(0xFFE53935),
                ),
              ),
              if (!won) ...[
                const SizedBox(height: 12),
                const Text(
                  'Your talents were lost. Start a new run from the menu.',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ],
              const SizedBox(height: 32),
              if (won) ...[
                _EndButton(label: 'Continue', onPressed: onContinue),
                const SizedBox(height: 12),
                _EndButton(label: 'Talents', onPressed: onTalents),
                const SizedBox(height: 12),
              ],
              _EndButton(label: 'Main Menu', onPressed: onMainMenu),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndButton extends StatelessWidget {
  const _EndButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        child: Text(label, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
