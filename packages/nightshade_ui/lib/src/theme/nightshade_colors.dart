import 'package:flutter/material.dart';

/// Semantic color palette registered as a [ThemeExtension].
///
/// Resolve at runtime with [of]. Prefer this over static presets in widgets.
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

  /// When true, [onPrimary] uses [background] instead of white — e.g. red night
  /// vision mode where white thumbs/checkmarks would ruin dark adaptation.
  final bool useDarkOnPrimary;

  /// True only for the red-night set.
  ///
  /// Needed because red night is a WAVELENGTH constraint, not just a dark
  /// palette, and some surfaces pick colours outside this class — notably
  /// [NightshadeChartColors], whose series are `static const` and therefore
  /// theme-blind. The dashboard guiding chart drew its Dec series in
  /// `#6B95B8` (measured on device) while the rest of the UI was red, which is
  /// exactly the dark-adaptation loss the mode exists to prevent.
  /// [useDarkOnPrimary] cannot stand in for this: it is also true for light
  /// and for custom accents that want dark ink.
  final bool isRedNight;

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
    this.useDarkOnPrimary = false,
    this.isRedNight = false,
  });

  /// Foreground color for content on [primary] fills (switches, buttons).
  Color get onPrimary =>
      useDarkOnPrimary ? background : const Color(0xFFFFFFFF);

  /// Deep graphite / blue-black palette with restrained cyan-blue accents.
  static const dark = NightshadeColors(
    primary: Color(0xFF5B9EC4),
    accent: Color(0xFF7AB8D4),
    background: Color(0xFF0A0C0F),
    surface: Color(0xFF111418),
    surfaceAlt: Color(0xFF181C22),
    surfaceHover: Color(0xFF212630),
    surfaceElevated: Color(0xFF252A32),
    surfaceOverlay: Color(0xFF2A3038),
    border: Color(0xFF2E353F),
    borderHighlight: Color(0xFF3A424E),
    textPrimary: Color(0xFFE8EAED),
    textSecondary: Color(0xFF9AA3AD),
    // WCAG AA: #6B7380 measured 3.57:1 on surfaceAlt and 3.01:1 on
    // surfaceElevated — under the 4.5:1 floor, and textMuted carries the 9-12px
    // metric captions and group labels where legibility matters most. #9099A6
    // clears 4.5:1 on ALL dark surfaces (4.62 overlay → 6.80 background) and
    // stays dimmer than textSecondary so the three-level hierarchy survives.
    textMuted: Color(0xFF9099A6),
    success: Color(0xFF3DAA6D),
    warning: Color(0xFFD49A3A),
    error: Color(0xFFD85C5C),
    info: Color(0xFF5B9EC4),
    // This palette's primary/accent/error/success/warning are all LIGHT tones,
    // so white label text on a filled button scored 2.94:1 (primary), 2.18:1
    // (accent) and 3.75:1 (error — the mount STOP and every destructive
    // button). Dark ink on a light fill is the correct pairing and lifts all
    // five to 5.23-8.98:1 without touching a single accent hue.
    useDarkOnPrimary: true,
  );

  /// Cool light palette with deeper cyan-blue primary for contrast.
  static const light = NightshadeColors(
    primary: Color(0xFF2878A8),
    accent: Color(0xFF3A9BC4),
    background: Color(0xFFF4F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF1F4),
    surfaceHover: Color(0xFFE4E8EC),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceOverlay: Color(0xFFFFFFFF),
    border: Color(0xFFD8DEE4),
    borderHighlight: Color(0xFFC8D0D8),
    textPrimary: Color(0xFF141820),
    textSecondary: Color(0xFF5C6672),
    // WCAG AA: #8A939E was only 3.11:1 on the white surface (2.75:1 on
    // surfaceAlt) — the worst offender in any palette. #666E79 clears 4.5:1 on
    // white (5.16), background (4.76) and surfaceAlt (4.55).
    textMuted: Color(0xFF666E79),
    // These two are consumed as small STATUS TEXT on white (e.g. an in-progress
    // "Downloading…" caption), where #2F8F57 scored 4.05:1 and #B87A1E 3.60:1.
    // Darkened to 4.94:1 each, hue preserved. error (4.66:1 white-on-fill) and
    // info already passed, so they are unchanged.
    success: Color(0xFF2A7F4F),
    warning: Color(0xFF9A6516),
    error: Color(0xFFC94848),
    info: Color(0xFF2878A8),
  );

  /// Create a dark theme with custom accent color
  /// True when dark ink reads better than white on [fill].
  ///
  /// 0.1791 is the WCAG crossover: solve 1.05/(L+0.05) == (L+0.05)/0.05 and a
  /// fill above it contrasts better with black than with white. A user-chosen
  /// accent can be any colour, so neither ink is safe as a blanket default —
  /// white on a light accent measures as low as 1.32:1 (yellow), while dark ink
  /// on a dark accent is 1.89:1 (navy). Picking per-fill keeps every accent
  /// legible instead of leaving it to chance.
  static bool _prefersDarkInk(Color fill) => fill.computeLuminance() > 0.1791;

  static NightshadeColors darkWithAccent(Color accentColor) {
    return dark.copyWith(
      primary: accentColor,
      accent: _lightenColor(accentColor, 0.15),
      useDarkOnPrimary: _prefersDarkInk(accentColor),
    );
  }

  /// Create a light theme with custom accent color
  static NightshadeColors lightWithAccent(Color accentColor) {
    return light.copyWith(
      primary: accentColor,
      accent: _lightenColor(accentColor, 0.15),
      useDarkOnPrimary: _prefersDarkInk(accentColor),
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
    primary: Color(0xFFDC2626),
    accent: Color(0xFFB91C1C),
    background: Color(0xFF0A0000),
    surface: Color(0xFF140808),
    surfaceAlt: Color(0xFF1C0C0C),
    surfaceHover: Color(0xFF241010),
    surfaceElevated: Color(0xFF281212),
    surfaceOverlay: Color(0xFF301616),
    border: Color(0xFF2E1414),
    borderHighlight: Color(0xFF3A1A1A),
    // The red-only constraint is about WAVELENGTH, not dimness: the old ladder
    // was unreadable rather than dark-adapted — textMuted #7F1D1D measured
    // 1.67:1 and textSecondary #B71C1C 2.55:1 against these surfaces (floor
    // 4.5:1). Raised as a set so all three clear AA (5.35 / 7.46 / 9.86 worst
    // case) and stay strictly ordered, while keeping red the dominant channel
    // (red purity actually INCREASES for muted, 0.38 → 0.49).
    textPrimary: Color(0xFFFFB3B3),
    textSecondary: Color(0xFFF59191),
    textMuted: Color(0xFFE86A6A),
    success: Color(0xFFB91C1C),
    warning: Color(0xFFDC2626),
    error: Color(0xFFEF5350),
    info: Color(0xFFE57373),
    useDarkOnPrimary: true,
    isRedNight: true,
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
    bool? useDarkOnPrimary,
    bool? isRedNight,
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
      useDarkOnPrimary: useDarkOnPrimary ?? this.useDarkOnPrimary,
      isRedNight: isRedNight ?? this.isRedNight,
    );
  }

  /// Resolve the active [NightshadeColors] from [context].
  ///
  /// Falls back to [dark] or [light] when the nearest [Theme] has no
  /// extension — e.g. mobile connection [MaterialApp] shells that predate
  /// a theme rebuild, or routes pushed before the parent theme applies.
  static NightshadeColors of(BuildContext context) {
    final extension = Theme.of(context).extension<NightshadeColors>();
    if (extension != null) {
      return extension;
    }
    return Theme.of(context).brightness == Brightness.light
        ? NightshadeColors.light
        : NightshadeColors.dark;
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
      useDarkOnPrimary: t < 0.5 ? useDarkOnPrimary : other.useDarkOnPrimary,
      isRedNight: t < 0.5 ? isRedNight : other.isRedNight,
    );
  }
}

/// Shorthand for [NightshadeColors.of] on a [BuildContext].
extension NightshadeThemeContext on BuildContext {
  /// Active semantic palette from the nearest [Theme].
  NightshadeColors get nightshadeColors => NightshadeColors.of(this);
}
