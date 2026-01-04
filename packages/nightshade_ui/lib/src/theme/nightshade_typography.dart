import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography system for consistent text styling across the app.
///
/// Usage:
/// ```dart
/// Text('Title', style: NightshadeTypography.h1)
/// Text('Body text', style: NightshadeTypography.body)
/// Text('12.5"', style: NightshadeTypography.mono)
/// ```
abstract final class NightshadeTypography {
  NightshadeTypography._();

  // ===========================================================================
  // Font Families
  // ===========================================================================

  /// Primary font for UI text
  static const String fontFamily = 'Inter';

  /// Monospace font for technical displays, code, and numeric values.
  /// This is loaded via GoogleFonts for consistent cross-platform rendering.
  static String get fontFamilyMono => GoogleFonts.jetBrainsMono().fontFamily!;

  // ===========================================================================
  // Heading Styles
  // ===========================================================================

  /// H1 - Page titles, hero text
  /// 32px, Semi-bold
  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.5,
  );

  /// H2 - Section titles
  /// 24px, Semi-bold
  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.33,
    letterSpacing: -0.25,
  );

  /// H3 - Card titles, subsection headers
  /// 20px, Semi-bold
  static const TextStyle h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0,
  );

  /// H4 - Small headers, widget titles
  /// 16px, Semi-bold
  static const TextStyle h4 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
    letterSpacing: 0,
  );

  /// H5 - Labels, small titles
  /// 14px, Semi-bold
  static const TextStyle h5 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.43,
    letterSpacing: 0,
  );

  /// H6 - Smallest heading
  /// 12px, Semi-bold
  static const TextStyle h6 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.5,
    letterSpacing: 0.25,
  );

  // ===========================================================================
  // Body Styles
  // ===========================================================================

  /// Body large - Primary reading text
  /// 16px, Regular
  static const TextStyle bodyLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );

  /// Body - Standard body text
  /// 14px, Regular
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );

  /// Body medium - Emphasized body text
  /// 14px, Medium
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0,
  );

  /// Body small - Secondary content
  /// 13px, Regular
  static const TextStyle bodySm = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.46,
    letterSpacing: 0,
  );

  // ===========================================================================
  // Label Styles
  // ===========================================================================

  /// Label large - Button text, navigation items
  /// 14px, Medium
  static const TextStyle labelLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.43,
    letterSpacing: 0.1,
  );

  /// Label - Form labels, list items
  /// 13px, Medium
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.38,
    letterSpacing: 0.1,
  );

  /// Label small - Helper text, badges
  /// 12px, Medium
  static const TextStyle labelSm = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.33,
    letterSpacing: 0.1,
  );

  // ===========================================================================
  // Caption & Utility Styles
  // ===========================================================================

  /// Caption - Metadata, timestamps
  /// 12px, Regular
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: 0.25,
  );

  /// Caption small - Very small text
  /// 11px, Regular
  static const TextStyle captionSm = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.27,
    letterSpacing: 0.25,
  );

  /// Overline - Section dividers, category labels
  /// 10px, Semi-bold, uppercase
  static const TextStyle overline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.6,
    letterSpacing: 1.5,
  );

  // ===========================================================================
  // Monospace Styles (Technical Displays)
  // ===========================================================================

  /// Mono large - Large numeric values, coordinates
  /// 18px, Regular
  static TextStyle get monoLg => GoogleFonts.jetBrainsMono(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: 0,
  );

  /// Mono - Standard technical text, code
  /// 14px, Regular
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: 0,
  );

  /// Mono small - Small numeric displays
  /// 12px, Regular
  static TextStyle get monoSm => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: 0,
  );

  /// Mono tiny - Very small numeric values
  /// 11px, Regular
  static TextStyle get monoXs => GoogleFonts.jetBrainsMono(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.27,
    letterSpacing: 0,
  );

  // ===========================================================================
  // Special Styles
  // ===========================================================================

  /// Stat value - Large statistic displays
  /// 36px, Bold
  static TextStyle get statValue => GoogleFonts.jetBrainsMono(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -1,
  );

  /// Stat label - Labels for stat values
  /// 12px, Medium, uppercase
  static const TextStyle statLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.33,
    letterSpacing: 0.5,
  );

  /// Button text
  /// 14px, Medium
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.43,
    letterSpacing: 0.1,
  );

  /// Button text small
  /// 13px, Medium
  static const TextStyle buttonSm = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.38,
    letterSpacing: 0.1,
  );

  /// Input text
  /// 14px, Regular
  static const TextStyle input = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: 0,
  );

  /// Input numeric (monospace)
  /// 14px, Regular
  static TextStyle get inputMono => GoogleFonts.jetBrainsMono(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: 0,
  );

  // ===========================================================================
  // Helper Methods
  // ===========================================================================

  /// Apply a color to any text style
  static TextStyle withColor(TextStyle style, Color color) {
    return style.copyWith(color: color);
  }

  /// Make any style bold
  static TextStyle bold(TextStyle style) {
    return style.copyWith(fontWeight: FontWeight.w700);
  }

  /// Make any style medium weight
  static TextStyle medium(TextStyle style) {
    return style.copyWith(fontWeight: FontWeight.w500);
  }

  /// Make any style italic
  static TextStyle italic(TextStyle style) {
    return style.copyWith(fontStyle: FontStyle.italic);
  }

  /// Add underline to any style
  static TextStyle underline(TextStyle style) {
    return style.copyWith(decoration: TextDecoration.underline);
  }

  /// Convert to uppercase
  static String uppercase(String text) => text.toUpperCase();
}

/// Extension for easy color application
extension TextStyleColorExtension on TextStyle {
  TextStyle colored(Color color) => copyWith(color: color);
}
