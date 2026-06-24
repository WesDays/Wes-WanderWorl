import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Builds a throwaway [SpriteAnimation] from solid-colour frames generated at
/// runtime, so the animation state machine is real before any art exists. Each
/// colour becomes one rounded-rect frame; swap this out for `SpriteSheet`-backed
/// animations once real sheets land.
Future<SpriteAnimation> placeholderAnim(
  List<Color> colors, {
  required double stepTime,
  bool loop = true,
}) async {
  final sprites = <Sprite>[];
  for (final color in colors) {
    sprites.add(Sprite(await _solidImage(color)));
  }
  return SpriteAnimation.spriteList(sprites, stepTime: stepTime, loop: loop);
}

Future<ui.Image> _solidImage(Color color, [int size = 64]) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final side = size.toDouble();
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, side, side),
      const Radius.circular(10),
    ),
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(size, size);
}
