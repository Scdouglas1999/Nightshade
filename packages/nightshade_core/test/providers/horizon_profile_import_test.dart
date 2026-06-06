// Tests for the horizon obstruction-profile import parsers used by Feature 3
// (backyard horizon mask). The 8-point compass profile lives in
// settings_provider.dart and is exported through the barrel under the
// `LegacyHorizonProfile` alias; we import the source directly here to reach
// the factory constructors without the alias.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';

void main() {
  group('HorizonProfile.parseHorizonText', () {
    test('parses Stellarium-style .hor whitespace pairs', () {
      const hor = '''
# A backyard skyline
0   25
90  10
180 5
270 15
''';
      final profile = HorizonProfile.parseHorizonText(hor);
      expect(profile.altitudeAt('N'), 25);
      expect(profile.altitudeAt('E'), 10);
      expect(profile.altitudeAt('S'), 5);
      expect(profile.altitudeAt('W'), 15);
      expect(profile.isFlat, isFalse);
    });

    test('parses CSV pairs and ignores comment / blank lines', () {
      const csv = '''
// azimuth,altitude
45,30

135,20
;trailing comment
''';
      final profile = HorizonProfile.parseHorizonText(csv);
      expect(profile.altitudeAt('NE'), 30);
      expect(profile.altitudeAt('SE'), 20);
      // Untouched sectors stay open sky.
      expect(profile.altitudeAt('N'), 0);
      expect(profile.altitudeAt('W'), 0);
    });

    test('bins multiple samples into a sector by taking the maximum', () {
      // Three samples land in the N sector (337.5°-22.5°); the tallest wins so
      // the obstruction is never under-reported.
      const hor = '0 8\n10 22\n350 14';
      final profile = HorizonProfile.parseHorizonText(hor);
      expect(profile.altitudeAt('N'), 22);
    });

    test('wraps azimuths past 360 and below 0 onto the right sector', () {
      const hor = '360 12\n-90 18';
      final profile = HorizonProfile.parseHorizonText(hor);
      expect(profile.altitudeAt('N'), 12); // 360 -> 0 -> N
      expect(profile.altitudeAt('W'), 18); // -90 -> 270 -> W
    });

    test('clamps altitudes into the valid 0-89 range', () {
      const hor = '0 120\n90 -5';
      final profile = HorizonProfile.parseHorizonText(hor);
      expect(profile.altitudeAt('N'), 89);
      expect(profile.altitudeAt('E'), 0);
    });

    test('round-trips through JSON', () {
      const hor = '0 25\n180 5';
      final profile = HorizonProfile.parseHorizonText(hor);
      final restored = HorizonProfile.fromJson(profile.toJson());
      expect(restored.altitudeAt('N'), 25);
      expect(restored.altitudeAt('S'), 5);
    });

    test('throws on a non-numeric field', () {
      expect(
        () => HorizonProfile.parseHorizonText('0 abc'),
        throwsFormatException,
      );
    });

    test('throws on a line with too few fields', () {
      expect(
        () => HorizonProfile.parseHorizonText('42'),
        throwsFormatException,
      );
    });

    test('throws when no usable samples are present', () {
      expect(
        () => HorizonProfile.parseHorizonText('# only comments\n\n'),
        throwsFormatException,
      );
    });
  });
}
