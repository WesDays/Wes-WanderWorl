import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws a darkened "clock swipe" cooldown indicator.
///
/// At [progress] == 0 a full dark disc is shown; as progress runs to 1 the
/// dark sector sweeps clockwise from the 12 o'clock position and empties out,
/// so the overlay visually drains away as the cooldown finishes.
class ClockSwipePainter extends CustomPainter {
  ClockSwipePainter(this.progress);

  /// 0.0 = cooldown just started, 1.0 = cooldown complete.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final double remaining = (1.0 - progress).clamp(0.0, 1.0);
    if (remaining <= 0) return;

    // Dark sector representing the time still left, sweeping clockwise from top.
    final Paint fill = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * remaining, true, fill);

    // Faint outline so the timer reads as a dial even as it empties.
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.25);
    canvas.drawCircle(center, radius, ring);
  }

  @override
  bool shouldRepaint(ClockSwipePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
