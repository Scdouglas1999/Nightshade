import 'package:flutter/material.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

/// Text style for a native [LabelHintDto] (v1 sky_renderer hierarchy).
TextStyle labelTextStyleForHint(LabelHintDto hint) {
  final mag = hint.apparentMag;
  switch (hint.category) {
    case LabelCategoryDto.star:
      return TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: _labelFontSize(mag, isPlanet: false),
        fontWeight: _labelFontWeight(mag),
      );
    case LabelCategoryDto.dso:
      return TextStyle(
        color: const Color(0xFF80CBC4).withValues(alpha: mag < 10 ? 0.85 : 0.6),
        fontSize: _labelFontSize(mag, isPlanet: false),
        fontWeight: _labelFontWeight(mag),
      );
    case LabelCategoryDto.constellation:
      return TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 10,
        fontWeight: FontWeight.w500,
      );
    case LabelCategoryDto.body:
      return TextStyle(
        color: const Color(0xFFB0BEC5),
        fontSize: _labelFontSize(mag, isPlanet: true),
        fontWeight: FontWeight.w600,
      );
    case LabelCategoryDto.satellite:
      return TextStyle(
        color: const Color(0xFF81D4FA),
        fontSize: 10,
        fontWeight: FontWeight.w500,
      );
    case LabelCategoryDto.minorPlanet:
      return TextStyle(
        color: const Color(0xFFFFCC80),
        fontSize: 9,
        fontWeight: FontWeight.w400,
      );
  }
}

/// Display string for overlay (constellation/planet casing matches v1).
String labelDisplayText(LabelHintDto hint) {
  return switch (hint.category) {
    LabelCategoryDto.constellation => hint.text.toUpperCase(),
    LabelCategoryDto.body => hint.text.toUpperCase(),
    _ => hint.text,
  };
}

double _labelFontSize(double magnitude, {required bool isPlanet}) {
  if (isPlanet) return 12;
  if (magnitude < 0) return 12;
  if (magnitude < 2) return 11;
  if (magnitude < 4) return 10;
  return 9;
}

FontWeight _labelFontWeight(double magnitude) {
  if (magnitude < 1) return FontWeight.w600;
  if (magnitude < 3) return FontWeight.w500;
  return FontWeight.w400;
}
