import 'package:flutter/material.dart';
import 'nightshade_colors.dart';

/// Desaturated chart and data-viz colors aligned with the Nightshade palette.
///
/// Static series constants hold fixed chart hues. Resolver methods take
/// [NightshadeColors] to map interactive states to theme semantics.
/// Follow this pattern for new domain color helpers.
abstract final class NightshadeChartColors {
  NightshadeChartColors._();

  static const Color seriesBlue = Color(0xFF6B95B8);
  static const Color seriesViolet = Color(0xFF8A82B0);
  static const Color seriesGreen = Color(0xFF4A9A72);
  static const Color seriesAmber = Color(0xFFC4A055);
  static const Color seriesIndigo = Color(0xFF5A6690);
  static const Color seriesDeepBlue = Color(0xFF4A6E9A);

  static const Color seriesRed = Color(0xFFBF6B6B);
  static const Color seriesOrange = Color(0xFFCB8847);
  static const Color neutralDark = Color(0xFF1F2937);

  static const List<Color> series = [
    seriesBlue,
    seriesViolet,
    seriesGreen,
    seriesAmber,
    seriesIndigo,
    seriesDeepBlue,
  ];

  /// PSF heatmap: tight → average → bloated.
  static const List<Color> psfGradient = [seriesGreen, seriesAmber, seriesRed];

  /// Uniformity: flat → mild → strong gradient.
  static const List<Color> uniformityGradient = [
    seriesGreen,
    seriesAmber,
    seriesOrange,
  ];

  /// Clip-high: safe → some clip → saturated.
  static const List<Color> clipHighGradient = [
    neutralDark,
    seriesAmber,
    seriesRed,
  ];

  /// Clip-low: safe → some clip → noise floor.
  static const List<Color> clipLowGradient = [
    neutralDark,
    seriesBlue,
    seriesDeepBlue,
  ];

  /// Astronomical twilight band overlay (sequence timeline).
  static Color twilightAstro({double alpha = 0.4}) =>
      seriesIndigo.withValues(alpha: alpha);

  /// Selected frame highlight from theme semantics.
  static Color selectedFrame([NightshadeColors? colors]) =>
      (colors ?? NightshadeColors.dark).success;

  static Color unselectedFrame({double alpha = 0.65}) =>
      seriesDeepBlue.withValues(alpha: alpha);
}
