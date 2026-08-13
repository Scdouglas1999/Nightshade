import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  group('NightshadeTheme caching', () {
    test('the three fixed themes are built once', () {
      expect(identical(NightshadeTheme.dark, NightshadeTheme.dark), isTrue);
      expect(identical(NightshadeTheme.light, NightshadeTheme.light), isTrue);
      expect(
        identical(NightshadeTheme.redNight, NightshadeTheme.redNight),
        isTrue,
      );
    });

    test('the fixed themes are still distinct from each other', () {
      expect(identical(NightshadeTheme.dark, NightshadeTheme.light), isFalse);
      expect(
        identical(NightshadeTheme.dark, NightshadeTheme.redNight),
        isFalse,
      );
      expect(NightshadeTheme.dark.brightness, Brightness.dark);
      expect(NightshadeTheme.light.brightness, Brightness.light);
      expect(NightshadeTheme.redNight.brightness, Brightness.dark);
    });

    test('repeating an accent reuses the cached theme', () {
      const accent = Color(0xFF33AA77);

      final first = NightshadeTheme.darkWithAccent(accent);
      final second = NightshadeTheme.darkWithAccent(accent);

      expect(identical(first, second), isTrue);
    });

    test('the dark and light accent caches do not collide', () {
      const accent = Color(0xFF33AA77);

      final dark = NightshadeTheme.darkWithAccent(accent);
      final light = NightshadeTheme.lightWithAccent(accent);

      expect(identical(dark, light), isFalse);
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
      // Still cached after the other brightness was asked for.
      expect(identical(NightshadeTheme.darkWithAccent(accent), dark), isTrue);
      expect(identical(NightshadeTheme.lightWithAccent(accent), light), isTrue);
    });

    test('a new accent evicts the previous one but stays correct', () {
      const first = Color(0xFF33AA77);
      const second = Color(0xFFAA3377);

      final firstTheme = NightshadeTheme.darkWithAccent(first);
      final secondTheme = NightshadeTheme.darkWithAccent(second);

      expect(identical(firstTheme, secondTheme), isFalse);
      expect(secondTheme.extension<NightshadeColors>()!.primary, second);
      // Evicted: asking again rebuilds rather than returning the stale entry.
      final firstAgain = NightshadeTheme.darkWithAccent(first);
      expect(firstAgain.extension<NightshadeColors>()!.primary, first);
    });

    test('resolveNightshadeThemeData is stable across calls', () {
      final a = resolveNightshadeThemeData(
        themeSetting: 'dark',
        accentColorHex: '#33AA77',
      );
      final b = resolveNightshadeThemeData(
        themeSetting: 'dark',
        accentColorHex: '#33AA77',
      );

      expect(identical(a, b), isTrue);
      expect(
        identical(
          resolveNightshadeThemeData(themeSetting: 'redNight'),
          resolveNightshadeThemeData(themeSetting: 'redNight'),
        ),
        isTrue,
      );
    });
  });
}
