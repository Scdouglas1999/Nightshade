import 'package:flutter/material.dart';

class NightshadeColors extends ThemeExtension<NightshadeColors> {
  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHover;
  final Color surfaceElevated;
  final Color surfaceOverlay;
  final Color border;
  final Color borderHighlight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  const NightshadeColors({
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHover,
    required this.surfaceElevated,
    required this.surfaceOverlay,
    required this.border,
    required this.borderHighlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  // Dark theme colors - inspired by night sky observation
  static const dark = NightshadeColors(
    primary: Color(0xFF6366F1), // Indigo
    accent: Color(0xFF8B5CF6), // Violet
    background: Color(0xFF0F0F14), // Deep night
    surface: Color(0xFF191922), // Base surface
    surfaceAlt: Color(0xFF242432), // Cards and panels
    surfaceHover: Color(0xFF303044), // Hover state
    surfaceElevated: Color(0xFF323246), // Raised interactive elements
    surfaceOverlay: Color(0xFF3B3B50), // Modals and floating elements
    border: Color(0xFF37374A), // Subtle border
    borderHighlight: Color(0xFF505066), // Highlight edge (catches light)
    textPrimary: Color(0xFFF4F4F5), // Primary text
    textSecondary: Color(0xFFA1A1AA), // Secondary text
    textMuted: Color(0xFF71717A), // Muted text
    success: Color(0xFF22C55E), // Green
    warning: Color(0xFFF59E0B), // Amber
    error: Color(0xFFEF4444), // Red
    info: Color(0xFF3B82F6), // Blue
  );

  // Light theme colors
  static const light = NightshadeColors(
    primary: Color(0xFF4F46E5), // Indigo
    accent: Color(0xFF7C3AED), // Violet
    background: Color(0xFFF8FAFC), // Light background
    surface: Color(0xFFFFFFFF), // White surface
    surfaceAlt: Color(0xFFF1F5F9), // Alternative surface
    surfaceHover: Color(0xFFE2E8F0), // Hover state
    surfaceElevated: Color(0xFFFFFFFF), // Raised elements (white with shadow)
    surfaceOverlay: Color(0xFFFFFFFF), // Modals (white with stronger shadow)
    border: Color(0xFFE2E8F0), // Subtle border
    borderHighlight: Color(0xFFFFFFFF), // Highlight edge (pure white on light)
    textPrimary: Color(0xFF0F172A), // Primary text
    textSecondary: Color(0xFF64748B), // Secondary text
    textMuted: Color(0xFF94A3B8), // Muted text
    success: Color(0xFF16A34A), // Green
    warning: Color(0xFFD97706), // Amber
    error: Color(0xFFDC2626), // Red
    info: Color(0xFF2563EB), // Blue
  );

  /// Create a dark theme with custom accent color
  static NightshadeColors darkWithAccent(Color accentColor) {
    return dark.copyWith(
      primary: accentColor,
      accent: _lightenColor(accentColor, 0.15),
    );
  }

  /// Create a light theme with custom accent color
  static NightshadeColors lightWithAccent(Color accentColor) {
    return light.copyWith(
      primary: accentColor,
      accent: _lightenColor(accentColor, 0.15),
    );
  }

  /// Helper to lighten a color for accent
  static Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// Red night vision theme - designed to preserve dark-adapted eyes
  /// Uses only red wavelengths which minimally affect scotopic (night) vision
  static const redNight = NightshadeColors(
    primary: Color(0xFFDC2626), // Bright red (main accent)
    accent: Color(0xFFB91C1C), // Deeper red (secondary accent)
    background: Color(0xFF0A0000), // Nearly pure black with hint of red
    surface: Color(0xFF140808), // Very dark red surface
    surfaceAlt: Color(0xFF1C0C0C), // Slightly lighter red surface
    surfaceHover: Color(0xFF241010), // Hover state
    surfaceElevated: Color(0xFF281212), // Raised interactive elements
    surfaceOverlay: Color(0xFF301616), // Modals and floating elements
    border: Color(0xFF2E1414), // Dark red border
    borderHighlight: Color(0xFF3A1A1A), // Highlight edge
    textPrimary: Color(0xFFE57373), // Light red text - easy to read
    textSecondary: Color(0xFFB71C1C), // Medium red secondary text
    textMuted: Color(0xFF7F1D1D), // Muted dark red
    success: Color(0xFFB91C1C), // Dark red for success (no green)
    warning: Color(0xFFDC2626), // Standard red for warning
    error: Color(0xFFEF5350), // Bright red for errors
    info: Color(0xFFE57373), // Light red for info
  );

  @override
  NightshadeColors copyWith({
    Color? primary,
    Color? accent,
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceHover,
    Color? surfaceElevated,
    Color? surfaceOverlay,
    Color? border,
    Color? borderHighlight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) {
    return NightshadeColors(
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      border: border ?? this.border,
      borderHighlight: borderHighlight ?? this.borderHighlight,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }

  @override
  NightshadeColors lerp(ThemeExtension<NightshadeColors>? other, double t) {
    if (other is! NightshadeColors) return this;
    return NightshadeColors(
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderHighlight: Color.lerp(borderHighlight, other.borderHighlight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
