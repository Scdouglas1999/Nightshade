import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Shader types used for star point-spread rendering.
enum StarPsfShaderType {
  glow,
  outerRing,
  midRing,
  core,
  balanced,
}

/// Cache for star PSF shaders keyed by type, radius, and color.
class StarPsfShaderCache {
  final int maxEntries;
  final Map<String, ui.Shader> _cache = {};

  StarPsfShaderCache({this.maxEntries = 1024});

  ui.Shader getShader({
    required StarPsfShaderType type,
    required double radius,
    required Color color,
  }) {
    final key = '${type.index}_${color.value}_${radius.toStringAsFixed(4)}';
    final existing = _cache[key];
    if (existing != null) return existing;

    if (_cache.length >= maxEntries) {
      _cache.clear();
    }

    final shader = _createShader(type, radius, color);
    _cache[key] = shader;
    return shader;
  }

  void clear() => _cache.clear();

  int get size => _cache.length;

  ui.Shader _createShader(StarPsfShaderType type, double radius, Color color) {
    final baseColor = color.withValues(alpha: 1.0);
    final rect = Rect.fromCircle(center: Offset.zero, radius: radius);

    switch (type) {
      case StarPsfShaderType.glow:
        return RadialGradient(
          colors: [
            baseColor.withValues(alpha: 0.4),
            baseColor.withValues(alpha: 0.15),
            baseColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect);
      case StarPsfShaderType.outerRing:
        return RadialGradient(
          colors: [
            Colors.transparent,
            baseColor.withValues(alpha: 0.1),
            baseColor.withValues(alpha: 0.05),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 0.8, 1.0],
        ).createShader(rect);
      case StarPsfShaderType.midRing:
        return RadialGradient(
          colors: [
            baseColor.withValues(alpha: 0.8),
            baseColor.withValues(alpha: 0.4),
            baseColor.withValues(alpha: 0.1),
            Colors.transparent,
          ],
          stops: const [0.0, 0.3, 0.6, 1.0],
        ).createShader(rect);
      case StarPsfShaderType.core:
        return RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 1.0),
            baseColor.withValues(alpha: 1.0),
            baseColor.withValues(alpha: 0.5),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(rect);
      case StarPsfShaderType.balanced:
        return RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.9),
            baseColor.withValues(alpha: 1.0),
            baseColor.withValues(alpha: 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ).createShader(rect);
    }
  }
}
