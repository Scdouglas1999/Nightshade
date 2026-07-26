import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  group('NightshadeTheme', () {
    final themes = <String, ThemeData>{
      'dark': NightshadeTheme.dark,
      'light': NightshadeTheme.light,
      'redNight': NightshadeTheme.redNight,
    };

    for (final entry in themes.entries) {
      test('${entry.key} theme registers NightshadeColors extension', () {
        final colors = entry.value.extension<NightshadeColors>();

        expect(colors, isNotNull);
        expect(colors!.primary, isA<Color>());
      });
    }

    test('ColorScheme primary matches NightshadeColors.primary', () {
      for (final theme in themes.values) {
        final colors = theme.extension<NightshadeColors>()!;
        expect(theme.colorScheme.primary, colors.primary);
      }
    });

    test('dark theme uses dark ink on its light-toned primary', () {
      // Was pinned to white, which measured only 2.94:1 against the dark
      // palette's primary #5B9EC4 (and 2.18:1 on accent, 3.75:1 on error) —
      // below the WCAG AA 4.5:1 floor for button labels. Dark ink on a light
      // fill is the correct pairing; the accent hues are unchanged.
      final colors = NightshadeTheme.dark.extension<NightshadeColors>()!;

      expect(colors.useDarkOnPrimary, isTrue);
      expect(colors.onPrimary, colors.background);
      expect(NightshadeTheme.dark.colorScheme.onPrimary, colors.background);
    });

    test('light theme uses white onPrimary', () {
      final colors = NightshadeTheme.light.extension<NightshadeColors>()!;

      expect(colors.useDarkOnPrimary, isFalse);
      expect(colors.onPrimary, const Color(0xFFFFFFFF));
      expect(
        NightshadeTheme.light.colorScheme.onPrimary,
        const Color(0xFFFFFFFF),
      );
    });

    test('redNight theme uses dark onPrimary for night vision contrast', () {
      final colors = NightshadeTheme.redNight.extension<NightshadeColors>()!;

      expect(colors.useDarkOnPrimary, isTrue);
      expect(colors.onPrimary, colors.background);
      expect(colors.onPrimary, isNot(const Color(0xFFFFFFFF)));
      expect(NightshadeTheme.redNight.colorScheme.onPrimary, colors.background);
    });

    test('accent theme registers NightshadeColors and matches ColorScheme', () {
      const accent = Color(0xFF10B981);
      final theme = NightshadeTheme.darkWithAccent(accent);
      final colors = theme.extension<NightshadeColors>()!;

      expect(colors.primary, accent);
      expect(theme.colorScheme.primary, accent);
    });

    test('accent ink is chosen by accent luminance, not hardcoded', () {
      // A user accent can be any colour, so neither ink is safe as a blanket
      // default: white on this light emerald is 2.54:1 while dark ink is
      // 7.72:1, and on a dark navy the ratios invert (10.36:1 vs 1.89:1).
      const lightAccent = Color(0xFF10B981); // luminance 0.364 -> dark ink
      const darkAccent = Color(0xFF1E3A8A); // luminance 0.051 -> white

      final lightAccentColors = NightshadeTheme.darkWithAccent(
        lightAccent,
      ).extension<NightshadeColors>()!;
      expect(lightAccentColors.useDarkOnPrimary, isTrue);
      expect(lightAccentColors.onPrimary, lightAccentColors.background);

      final darkAccentColors = NightshadeTheme.darkWithAccent(
        darkAccent,
      ).extension<NightshadeColors>()!;
      expect(darkAccentColors.useDarkOnPrimary, isFalse);
      expect(darkAccentColors.onPrimary, const Color(0xFFFFFFFF));
    });

    test('copyWith preserves useDarkOnPrimary unless overridden', () {
      final copied = NightshadeColors.redNight.copyWith(primary: Colors.red);

      expect(copied.useDarkOnPrimary, isTrue);
      expect(copied.onPrimary, NightshadeColors.redNight.background);
    });
  });

  group('NightshadeThemeContext', () {
    testWidgets('nightshadeColors resolves from ThemeData', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NightshadeTheme.dark,
          home: Builder(
            builder: (context) {
              expect(
                context.nightshadeColors.primary,
                NightshadeColors.dark.primary,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('NightshadeSwitchStyle.switchThemeData parity', () {
    test('uses colors.onPrimary for selected thumb in dark theme', () {
      const colors = NightshadeColors.dark;
      final theme = NightshadeSwitchStyle.switchThemeData(
        colors,
        colors.onPrimary,
      );

      expect(
        theme.thumbColor!.resolve({WidgetState.selected}),
        colors.onPrimary,
      );
    });

    test('uses colors.onPrimary for selected thumb in redNight theme', () {
      const colors = NightshadeColors.redNight;
      final theme = NightshadeSwitchStyle.switchThemeData(
        colors,
        colors.onPrimary,
      );

      expect(
        theme.thumbColor!.resolve({WidgetState.selected}),
        colors.background,
      );
    });
  });
}
