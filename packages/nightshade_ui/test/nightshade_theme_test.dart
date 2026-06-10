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

    test('dark theme uses white onPrimary', () {
      final colors = NightshadeTheme.dark.extension<NightshadeColors>()!;

      expect(colors.useDarkOnPrimary, isFalse);
      expect(colors.onPrimary, const Color(0xFFFFFFFF));
      expect(
        NightshadeTheme.dark.colorScheme.onPrimary,
        const Color(0xFFFFFFFF),
      );
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
      expect(colors.useDarkOnPrimary, isFalse);
      expect(colors.onPrimary, const Color(0xFFFFFFFF));
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
