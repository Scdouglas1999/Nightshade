import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// `design-tokens.json` is the source of truth for the Observatory palette and
/// this file is the reason that sentence is true rather than aspirational.
///
/// The JSON drives the HTML mockups, `check_tokens.py`'s contrast gate and the
/// generated `mockups/tokens.css`; Dart drives the app. Nothing else connects
/// them, so a value edited in one place and not the other would leave the
/// spec, the reference renders and the shipped UI quietly disagreeing — which
/// is precisely the failure the whole overhaul exists to end. Every mirrored
/// value is asserted here, in both directions: no Dart constant may drift from
/// the JSON, and no JSON key may go unmirrored.
///
/// The name map is `docs/design/overhaul/03-tokens.md` §0. The JSON uses short
/// CSS-friendly keys; the Dart names differ, and they are joined by that table,
/// never by key name.
void main() {
  /// Path is relative to the PACKAGE, which is the cwd `flutter test` uses.
  final tokensFile = File('../../docs/design/overhaul/design-tokens.json');

  late Map<String, dynamic> tokens;
  late Map<String, dynamic> palettes;

  setUpAll(() {
    expect(
      tokensFile.existsSync(),
      isTrue,
      reason:
          'design-tokens.json is missing at ${tokensFile.path}. If the design '
          'folder moved, this test moves with it — do not delete it.',
    );
    tokens = json.decode(tokensFile.readAsStringSync()) as Map<String, dynamic>;
    palettes = tokens['palettes'] as Map<String, dynamic>;
  });

  Color parseHex(String hex) {
    final clean = hex.replaceFirst('#', '');
    expect(
      clean.length,
      6,
      reason: '$hex is not a #RRGGBB literal; the mirror only handles those',
    );
    return Color(int.parse('FF$clean', radix: 16));
  }

  /// 03 §0, the colour rows: JSON key -> the field of [NightshadeColors] it
  /// mirrors. `onPrimary` is deliberately absent — it is DERIVED from
  /// `useDarkOnPrimary` rather than stored, and is asserted separately below.
  /// `accentSwatches` and `bands` are nested and are asserted separately too.
  Map<String, Color Function(NightshadeColors)> colorMap() => {
    'bg': (c) => c.background,
    'surface': (c) => c.surface,
    'well': (c) => c.well,
    'surfaceHover': (c) => c.surfaceHover,
    'surfaceElevated': (c) => c.surfaceElevated,
    'surfaceOverlay': (c) => c.surfaceOverlay,
    'border': (c) => c.border,
    'borderStrong': (c) => c.borderHighlight,
    'textPrimary': (c) => c.textPrimary,
    'textSecondary': (c) => c.textSecondary,
    'textMuted': (c) => c.textMuted,
    'primary': (c) => c.primary,
    'accent': (c) => c.accent,
    'success': (c) => c.success,
    'warning': (c) => c.warning,
    'error': (c) => c.error,
    'info': (c) => c.info,
    'startFill': (c) => c.startFill,
    'onStart': (c) => c.onStart,
  };

  Map<String, Color Function(NightshadeColors)> bandMap() => {
    'dusk': (c) => c.bandDusk,
    'twilight': (c) => c.bandTwilight,
    'dark': (c) => c.bandDark,
    'dawn': (c) => c.bandDawn,
  };

  /// JSON palette name -> the Dart constant it mirrors.
  const dartPalettes = <String, NightshadeColors>{
    'dark': NightshadeColors.dark,
    'light': NightshadeColors.light,
    'redNight': NightshadeColors.redNight,
  };

  group('design-tokens.json mirrors NightshadeColors', () {
    test('the JSON declares exactly the three palettes Dart holds', () {
      expect(palettes.keys.toSet(), dartPalettes.keys.toSet());
    });

    for (final entry in dartPalettes.entries) {
      final name = entry.key;
      final dart = entry.value;

      test('$name: every colour matches the JSON', () {
        final json = palettes[name] as Map<String, dynamic>;
        for (final field in colorMap().entries) {
          final expected = parseHex(json[field.key] as String);
          expect(
            field.value(dart).toARGB32(),
            expected.toARGB32(),
            reason:
                '$name.${field.key} is ${json[field.key]} in '
                'design-tokens.json but a different colour in '
                'NightshadeColors.$name',
          );
        }
      });

      test('$name: the night band matches the JSON', () {
        final json = palettes[name] as Map<String, dynamic>;
        final bands = json['bands'] as Map<String, dynamic>;
        expect(bands.keys.toSet(), bandMap().keys.toSet());
        for (final band in bandMap().entries) {
          expect(
            band.value(dart).toARGB32(),
            parseHex(bands[band.key] as String).toARGB32(),
            reason: '$name band ${band.key} drifted from design-tokens.json',
          );
        }
      });

      test('$name: the two flags and the derived onPrimary match', () {
        final json = palettes[name] as Map<String, dynamic>;
        expect(dart.useDarkOnPrimary, json['useDarkOnPrimary']);
        expect(dart.isRedNight, json['isRedNight']);
        // onPrimary is not a field: it is `background` or white, chosen by
        // useDarkOnPrimary. The JSON writes the resolved value, so this
        // asserts the derivation as well as the colour.
        expect(
          dart.onPrimary.toARGB32(),
          parseHex(json['onPrimary'] as String).toARGB32(),
          reason:
              '$name.onPrimary resolves to something other than the JSON says',
        );
      });

      test('$name: the accent swatches match the JSON', () {
        final json = palettes[name] as Map<String, dynamic>;
        final expected = (json['accentSwatches'] as List<dynamic>)
            .cast<String>()
            .map(parseHex)
            .map((c) => c.toARGB32())
            .toList();
        final mode = switch (name) {
          'dark' => AppThemeMode.dark,
          'light' => AppThemeMode.light,
          _ => AppThemeMode.redNight,
        };
        expect(
          AppearanceAccents.forTheme(mode).map((c) => c.toARGB32()).toList(),
          expected,
          reason:
              'the Settings > Appearance swatches for $name are not the ones '
              'check_tokens.py validated',
        );
      });
    }

    /// The mirror is only worth having if it is exhaustive. Every colour-valued
    /// key in the JSON must be claimed by the map above, so adding a token to
    /// the JSON and forgetting the Dart side fails HERE rather than in a
    /// screenshot review three waves later.
    test('no colour key in the JSON is left unmirrored', () {
      final claimed = colorMap().keys.toSet()
        ..addAll(<String>['onPrimary', 'useDarkOnPrimary', 'isRedNight'])
        ..addAll(<String>['accentSwatches', 'bands']);
      for (final entry in palettes.entries) {
        final json = entry.value as Map<String, dynamic>;
        final unmirrored = json.keys.toSet().difference(claimed);
        expect(
          unmirrored,
          isEmpty,
          reason:
              '${entry.key} carries $unmirrored in design-tokens.json with no '
              'NightshadeColors field behind it. Add the field and the row in '
              '03-tokens.md §0, or remove the key.',
        );
      }
    });
  });

  group('red night stays on the red axis', () {
    /// The wavelength rule, asserted against the SOURCE rather than the Dart
    /// copy: red dominant and green exactly equal to blue, for every colour in
    /// the palette including the night band. Anything with green ≠ blue has a
    /// hue — orange or magenta — and a hue is light the operator's rods can
    /// see, which is the one thing this mode may not spend.
    test('every red-night colour has G == B', () {
      final json = palettes['redNight'] as Map<String, dynamic>;
      final entries = <String, String>{};
      for (final e in json.entries) {
        if (e.value is String) entries[e.key] = e.value as String;
      }
      for (final b in (json['bands'] as Map<String, dynamic>).entries) {
        entries['bands.${b.key}'] = b.value as String;
      }
      expect(
        entries.length,
        greaterThan(15),
        reason: 'the sweep found almost nothing; the JSON shape has changed',
      );
      for (final e in entries.entries) {
        final c = parseHex(e.value);
        final r = (c.r * 255).round();
        final g = (c.g * 255).round();
        final b = (c.b * 255).round();
        expect(
          g,
          b,
          reason:
              'redNight.${e.key} is ${e.value}: green $g and blue $b differ, '
              'so it carries a hue off the red axis',
        );
        expect(
          r,
          greaterThanOrEqualTo(g),
          reason: 'redNight.${e.key} is ${e.value}: red is not dominant',
        );
      }
    });

    test('the Dart palette carries the same rule', () {
      const dart = NightshadeColors.redNight;
      final colors = <String, Color>{
        'background': dart.background,
        'surface': dart.surface,
        'well': dart.well,
        'surfaceHover': dart.surfaceHover,
        'surfaceElevated': dart.surfaceElevated,
        'surfaceOverlay': dart.surfaceOverlay,
        'border': dart.border,
        'borderHighlight': dart.borderHighlight,
        'textPrimary': dart.textPrimary,
        'textSecondary': dart.textSecondary,
        'textMuted': dart.textMuted,
        'primary': dart.primary,
        'accent': dart.accent,
        'success': dart.success,
        'warning': dart.warning,
        'error': dart.error,
        'info': dart.info,
        'startFill': dart.startFill,
        'onStart': dart.onStart,
        'onPrimary': dart.onPrimary,
        'bandDusk': dart.bandDusk,
        'bandTwilight': dart.bandTwilight,
        'bandDark': dart.bandDark,
        'bandDawn': dart.bandDawn,
      };
      for (final e in colors.entries) {
        expect(
          (e.value.g * 255).round(),
          (e.value.b * 255).round(),
          reason: 'redNight.${e.key} has drifted off the red axis',
        );
      }
    });
  });

  group('the non-colour tokens mirror too', () {
    test('the radius scale matches the JSON', () {
      final radius = tokens['radius'] as Map<String, dynamic>;
      expect(NightshadeTokens.radiusXs, (radius['xs'] as num).toDouble());
      expect(NightshadeTokens.radiusSm, (radius['sm'] as num).toDouble());
      expect(NightshadeTokens.radiusMd, (radius['md'] as num).toDouble());
      expect(NightshadeTokens.radiusLg, (radius['lg'] as num).toDouble());
      expect(NightshadeTokens.radiusXl, (radius['xl'] as num).toDouble());
      expect(NightshadeTokens.radiusFull, (radius['full'] as num).toDouble());
      // radiusButton is an alias of Sm, and the migration aliases fold onto
      // the scale; wave 4 deletes them, and until then they must not drift.
      expect(NightshadeTokens.radiusButton, NightshadeTokens.radiusSm);
      expect(NightshadeTokens.radiusInline2, NightshadeTokens.radiusXs);
      expect(NightshadeTokens.radiusInline4, NightshadeTokens.radiusXs);
      expect(NightshadeTokens.radiusInline8, NightshadeTokens.radiusLg);
      expect(NightshadeTokens.radiusInline9, NightshadeTokens.radiusLg);
      expect(NightshadeTokens.radiusInline11, NightshadeTokens.radiusXl);
    });

    test('the spacing scale matches the JSON', () {
      final space = tokens['space'] as Map<String, dynamic>;
      expect(NightshadeTokens.spaceXs, (space['1'] as num).toDouble());
      expect(NightshadeTokens.spaceSm, (space['2'] as num).toDouble());
      expect(NightshadeTokens.spaceMd, (space['3'] as num).toDouble());
      expect(NightshadeTokens.spaceLg, (space['4'] as num).toDouble());
      expect(NightshadeTokens.spaceXl, (space['5'] as num).toDouble());
      expect(NightshadeTokens.space2xl, (space['6'] as num).toDouble());
      expect(NightshadeTokens.space3xl, (space['8'] as num).toDouble());
      expect(NightshadeTokens.space4xl, (space['12'] as num).toDouble());
    });

    test('the motion durations match the JSON', () {
      final motion = tokens['motion'] as Map<String, dynamic>;
      expect(NightshadeTokens.durationFast.inMilliseconds, motion['hoverMs']);
      expect(NightshadeTokens.durationNormal.inMilliseconds, motion['stateMs']);
      expect(NightshadeTokens.durationSmooth.inMilliseconds, motion['panelMs']);
      // `cubic-bezier(0.215, 0.61, 0.355, 1)` IS easeOutCubic, and every named
      // curve in the app points at it: no bounce, no overshoot, no spring.
      expect(motion['easing'], 'cubic-bezier(0.215, 0.61, 0.355, 1)');
      for (final curve in <Curve>[
        NightshadeTokens.curveStandard,
        NightshadeTokens.curveDecelerate,
        NightshadeTokens.curveAccelerate,
        NightshadeTokens.curveBounce,
        NightshadeTokens.curveSharp,
        NightshadeTokens.curveSnappy,
        NightshadeTokens.curvePrecise,
        NightshadeTokens.curveSettle,
      ]) {
        expect(curve, same(Curves.easeOutCubic));
      }
    });

    test('the opacity tokens match the JSON', () {
      final opacity = tokens['opacity'] as Map<String, dynamic>;
      expect(NightshadeTokens.opacityAccentTint, opacity['accentTint']);
      expect(
        NightshadeTokens.opacityAccentTintHover,
        opacity['accentTintHover'],
      );
      expect(NightshadeTokens.opacityStatusFill, opacity['statusFill']);
      expect(NightshadeTokens.opacityDisabled, opacity['disabled']);
      expect(NightshadeTokens.opacityHairline, opacity['hairline']);
      expect(NightshadeTokens.opacityHairlineStrong, opacity['hairlineStrong']);
      expect(NightshadeTokens.opacityPanelOutline, opacity['panelOutline']);
      expect(NightshadeTokens.opacitySelectedRing, opacity['selectedRing']);
      expect(NightshadeTokens.opacityLiveHalo, opacity['liveHalo']);
    });

    test('the icon-button sizes match the JSON', () {
      final shell = tokens['shell'] as Map<String, dynamic>;
      expect(
        NightshadeTokens.iconButtonSize,
        (shell['iconButtonSize'] as num).toDouble(),
      );
      expect(
        NightshadeTokens.iconButtonSizeSm,
        (shell['iconButtonSizeSm'] as num).toDouble(),
      );
      expect(
        NightshadeTokens.iconButtonSizeStrip,
        (shell['iconButtonSizeStrip'] as num).toDouble(),
      );
    });

    /// The type scale, by the same rule as the colours. `body`, `bodySm`,
    /// `caption`, `button` and `buttonSm` predate the overhaul and carry line
    /// heights and tracking from the old scale; wave 0 does not move them,
    /// because changing a line height moves every screen. Only the styles the
    /// overhaul INTRODUCED are held to the JSON here — the rest are wave 2's,
    /// alongside the components that read them.
    test('the new type styles match the JSON exactly', () {
      final styles =
          (tokens['typography'] as Map<String, dynamic>)['styles']
              as Map<String, dynamic>;
      final mirrored = <String, TextStyle>{
        'display': NightshadeTypography.display,
        'pageTitle': NightshadeTypography.pageTitle,
        'sectionTitle': NightshadeTypography.sectionTitle,
        'eyebrow': NightshadeTypography.eyebrow,
        'bodyStrong': NightshadeTypography.bodyStrong,
        'readoutLg': NightshadeTypography.readoutLg,
        'readoutMd': NightshadeTypography.readoutMd,
        'readoutSm': NightshadeTypography.readoutSm,
        'readoutXs': NightshadeTypography.readoutXs,
        'readoutBadge': NightshadeTypography.readoutBadge,
        'readoutLabel': NightshadeTypography.readoutLabel,
        'monoCaption': NightshadeTypography.monoCaption,
        'buttonLg': NightshadeTypography.buttonLg,
      };
      for (final entry in mirrored.entries) {
        final spec = styles[entry.key] as Map<String, dynamic>;
        final style = entry.value;
        expect(
          style.fontSize,
          (spec['size'] as num).toDouble(),
          reason: '${entry.key} size',
        );
        expect(
          style.fontWeight!.value,
          spec['weight'],
          reason: '${entry.key} weight',
        );
        expect(
          style.height,
          (spec['lineHeight'] as num).toDouble(),
          reason: '${entry.key} line height',
        );
        expect(
          style.letterSpacing,
          (spec['letterSpacing'] as num).toDouble(),
          reason: '${entry.key} tracking',
        );
        expect(
          style.fontFamily,
          spec['family'] == 'mono'
              ? NightshadeTypography.fontFamilyMono
              : NightshadeTypography.fontFamily,
          reason: '${entry.key} family',
        );
        final tabular = spec['tabular'] == true;
        expect(
          style.fontFeatures?.any((f) => f.feature == 'tnum') ?? false,
          tabular,
          reason:
              '${entry.key} ${tabular ? "must" : "must not"} carry tabular '
              'figures — a readout that reflows as its digits change is the '
              'reason this feature exists',
        );
      }
    });
  });
}
