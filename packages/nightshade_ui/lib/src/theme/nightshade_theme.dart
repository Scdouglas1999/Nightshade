import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/nightshade_switch_style.dart';
import 'nightshade_colors.dart';
import 'nightshade_tokens.dart';
import 'nightshade_typography.dart';

/// App-specific theme modes including red night for astronomy.
enum AppThemeMode {
  /// Standard dark theme
  dark,

  /// Light theme
  light,

  /// Red night vision theme - preserves dark-adapted eyes
  redNight,

  /// Follow system setting (maps to light/dark only)
  system,
}

/// Ephemeral Flutter [ThemeMode] for MaterialApp `themeMode` (light/dark only).
///
/// Used by the mobile connection screen before settings load. Does **not**
/// persist and does not support red night — use [appSettingsProvider] for that.
///
/// **Authoritative theme source:** [appSettingsProvider] in `nightshade_core`
/// (`settings.theme`: `dark` | `light` | `redNight`, plus optional accent).
/// Desktop [NightshadeApp] watches it and calls [NightshadeTheme] directly.
/// [themeSettingsProvider] is a focused DB-backed slice for theme-only writes.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

/// In-memory [AppThemeMode] including red night and system.
///
/// Transitional / test hook — production apps resolve theme from
/// [appSettingsProvider], not this provider. Prefer [getThemeForMode] when
/// bridging persisted settings to [ThemeData].
final appThemeModeProvider = StateProvider<AppThemeMode>(
  (ref) => AppThemeMode.dark,
);

/// Parse a hex accent color (`#RRGGBB` or `RRGGBB`). Returns null if invalid.
Color? parseNightshadeAccentColor(String? hexColor) {
  if (hexColor == null || hexColor.isEmpty) return null;
  try {
    final hex = hexColor.replaceFirst('#', '');
    if (hex.length != 6) return null;
    return Color(int.parse('0xFF$hex'));
  } catch (_) {
    return null;
  }
}

/// Resolve persisted settings (`dark` | `light` | `redNight`) to [ThemeData].
///
/// Shared by desktop [MaterialApp.router], mobile connection UI, and tests so
/// accent + red-night modes stay consistent across entry points.
ThemeData resolveNightshadeThemeData({
  required String themeSetting,
  String? accentColorHex,
}) {
  if (themeSetting == 'redNight') {
    return NightshadeTheme.redNight;
  }

  final accentColor = parseNightshadeAccentColor(accentColorHex);
  if (accentColor == null) {
    switch (themeSetting) {
      case 'light':
        return NightshadeTheme.light;
      case 'dark':
      default:
        return NightshadeTheme.dark;
    }
  }

  switch (themeSetting) {
    case 'light':
      return NightshadeTheme.lightWithAccent(accentColor);
    case 'dark':
    default:
      return NightshadeTheme.darkWithAccent(accentColor);
  }
}

/// Status bar / navigation bar colors aligned with [NightshadeColors.surface].
SystemUiOverlayStyle systemUiOverlayStyleFor(ThemeData theme) {
  final colors = theme.extension<NightshadeColors>();
  final isDark = theme.brightness == Brightness.dark;
  final base = isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
  final surface = colors?.surface ?? theme.colorScheme.surface;
  return base.copyWith(
    statusBarColor: surface,
    systemNavigationBarColor: surface,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
  );
}

/// Get the appropriate ThemeData for the current app theme mode
ThemeData getThemeForMode(AppThemeMode mode, Brightness systemBrightness) {
  switch (mode) {
    case AppThemeMode.dark:
      return NightshadeTheme.dark;
    case AppThemeMode.light:
      return NightshadeTheme.light;
    case AppThemeMode.redNight:
      return NightshadeTheme.redNight;
    case AppThemeMode.system:
      return systemBrightness == Brightness.dark
          ? NightshadeTheme.dark
          : NightshadeTheme.light;
  }
}

/// Assembles Flutter [ThemeData] from [NightshadeColors], [NightshadeTokens],
/// and [NightshadeTypography] for dark, light, and red-night modes.
class NightshadeTheme {
  NightshadeTheme._();

  static ThemeData get dark =>
      _buildTheme(NightshadeColors.dark, Brightness.dark);

  static ThemeData get light =>
      _buildTheme(NightshadeColors.light, Brightness.light);

  /// Red night vision theme - uses only red wavelengths for dark adaptation
  static ThemeData get redNight =>
      _buildTheme(NightshadeColors.redNight, Brightness.dark);

  /// Generate a dark theme with custom accent color
  static ThemeData darkWithAccent(Color accentColor) {
    return _buildTheme(
      NightshadeColors.darkWithAccent(accentColor),
      Brightness.dark,
    );
  }

  /// Generate a light theme with custom accent color
  static ThemeData lightWithAccent(Color accentColor) {
    return _buildTheme(
      NightshadeColors.lightWithAccent(accentColor),
      Brightness.light,
    );
  }

  static ThemeData _buildTheme(NightshadeColors colors, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final onPrimary = colors.onPrimary;
    final textTheme = NightshadeTypography.textTheme(colors);
    final shape = RoundedRectangleBorder(
      borderRadius: NightshadeTokens.borderRadiusMd,
    );

    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: colors.primary,
            onPrimary: onPrimary,
            secondary: colors.accent,
            onSecondary: onPrimary,
            surface: colors.surface,
            onSurface: colors.textPrimary,
            error: colors.error,
            onError: onPrimary,
            outline: colors.border,
            outlineVariant: colors.borderHighlight,
            surfaceContainerHighest: colors.surfaceElevated,
          )
        : ColorScheme.light(
            primary: colors.primary,
            onPrimary: onPrimary,
            secondary: colors.accent,
            onSecondary: onPrimary,
            surface: colors.surface,
            onSurface: colors.textPrimary,
            error: colors.error,
            onError: onPrimary,
            outline: colors.border,
            outlineVariant: colors.borderHighlight,
            surfaceContainerHighest: colors.surfaceElevated,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: NightshadeTypography.fontFamily,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      disabledColor: colors.textMuted.withValues(
        alpha: NightshadeTokens.opacityDisabled,
      ),
      unselectedWidgetColor: colors.textMuted,
      splashColor: colors.primary.withValues(alpha: 0.08),
      highlightColor: colors.primary.withValues(alpha: 0.06),
      hoverColor: colors.surfaceHover,
      focusColor: colors.primary.withValues(alpha: 0.35),
      dividerColor: colors.border,
      colorScheme: colorScheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(
        color: colors.textSecondary,
        size: NightshadeTokens.iconMd,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: systemUiOverlayStyleFor(
          ThemeData(brightness: brightness, extensions: [colors]),
        ),
        titleTextStyle: NightshadeTypography.h4.copyWith(
          color: colors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceAlt,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: shape.copyWith(
          side: BorderSide(color: colors.border.withValues(alpha: 0.7)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceElevated,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        alignment: Alignment.center,
        shape: shape.copyWith(side: BorderSide(color: colors.border)),
        titleTextStyle: NightshadeTypography.h4.copyWith(
          color: colors.textPrimary,
        ),
        contentTextStyle: NightshadeTypography.body.copyWith(
          color: colors.textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: NightshadeTokens.borderRadiusMd,
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NightshadeTokens.borderRadiusMd,
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NightshadeTokens.borderRadiusMd,
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: NightshadeTokens.borderRadiusMd,
          borderSide: BorderSide(color: colors.error),
        ),
        contentPadding: NightshadeTokens.inputPadding,
        hintStyle: NightshadeTypography.body.copyWith(color: colors.textMuted),
        labelStyle: NightshadeTypography.label.copyWith(
          color: colors.textSecondary,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.surfaceAlt;
          }
          if (states.contains(WidgetState.selected)) {
            return colors.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(onPrimary),
        side: BorderSide(color: colors.border, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: NightshadeTokens.borderRadiusXs,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.border,
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: 0.12),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      // Fallback for Material `Switch` only — prefer [NightshadeSwitch].
      switchTheme: NightshadeSwitchStyle.switchThemeData(colors, onPrimary),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: colors.surfaceAlt,
          disabledForegroundColor: colors.textMuted,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: NightshadeTokens.buttonPadding,
          textStyle: NightshadeTypography.button,
          shape: shape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: colors.surfaceAlt,
          disabledForegroundColor: colors.textMuted,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: NightshadeTokens.buttonPadding,
          textStyle: NightshadeTypography.button,
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          disabledForegroundColor: colors.textMuted,
          side: BorderSide(color: colors.border),
          padding: NightshadeTokens.buttonPadding,
          textStyle: NightshadeTypography.button,
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          disabledForegroundColor: colors.textMuted,
          padding: NightshadeTokens.buttonPadding,
          textStyle: NightshadeTypography.button,
          shape: shape,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: NightshadeTokens.borderRadiusSm,
          border: Border.all(color: colors.border),
        ),
        textStyle: NightshadeTypography.caption.copyWith(
          color: colors.textPrimary,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceElevated,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: shape.copyWith(side: BorderSide(color: colors.border)),
        textStyle: NightshadeTypography.body.copyWith(
          color: colors.textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceElevated,
        contentTextStyle: NightshadeTypography.body.copyWith(
          color: colors.textPrimary,
        ),
        shape: shape.copyWith(side: BorderSide(color: colors.border)),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NightshadeTokens.radiusLg),
          ),
          side: BorderSide(color: colors.border),
        ),
      ),
      extensions: [colors],
    );
  }
}
