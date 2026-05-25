import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  group('resolveNightshadeThemeData', () {
    test('red night ignores custom accent', () {
      final theme = resolveNightshadeThemeData(
        themeSetting: 'redNight',
        accentColorHex: '#FF0000',
      );
      expect(theme.brightness, Brightness.dark);
      expect(
        theme.extension<NightshadeColors>()!.primary,
        NightshadeColors.redNight.primary,
      );
    });

    test('applies accent to dark theme', () {
      final theme = resolveNightshadeThemeData(
        themeSetting: 'dark',
        accentColorHex: '#FF0000',
      );
      final colors = theme.extension<NightshadeColors>()!;
      expect(colors.primary, const Color(0xFFFF0000));
    });
  });

  group('systemUiOverlayStyleFor', () {
    test('uses dark status icons on light theme', () {
      final style = systemUiOverlayStyleFor(NightshadeTheme.light);
      expect(style.statusBarIconBrightness, Brightness.dark);
    });

    test('uses light status icons on dark theme', () {
      final style = systemUiOverlayStyleFor(NightshadeTheme.dark);
      expect(style.statusBarIconBrightness, Brightness.light);
    });
  });
}
