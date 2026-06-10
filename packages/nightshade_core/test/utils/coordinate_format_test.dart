import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  group('CoordinateFormat.ra', () {
    test('paddedLetters + oneDecimal (default) matches legacy output', () {
      // 12h 20m 42.0s for 12.345 hours.
      expect(CoordinateFormat.ra(12.345), '12h 20m 42.0s');
    });

    test('zero-pads hours and minutes (seconds use one decimal, unpadded)', () {
      // 5.5 h -> 05h 30m 0.0s. The seconds component is rendered with
      // toStringAsFixed(1) and intentionally NOT zero-padded, matching the
      // legacy private formatters this consolidates.
      expect(CoordinateFormat.ra(5.5), '05h 30m 0.0s');
    });

    test('paddedLetters + integerRounded', () {
      expect(
        CoordinateFormat.ra(12.345, seconds: SecondsPrecision.integerRounded),
        '12h 20m 42s',
      );
    });

    test('paddedLetters + integerFloored', () {
      // 42.0s exactly floors to 42.
      expect(
        CoordinateFormat.ra(12.345, seconds: SecondsPrecision.integerFloored),
        '12h 20m 42s',
      );
    });

    test('paddedColons + integerRounded', () {
      expect(
        CoordinateFormat.ra(
          12.345,
          style: SexagesimalStyle.paddedColons,
          seconds: SecondsPrecision.integerRounded,
        ),
        '12:20:42',
      );
    });
  });

  group('CoordinateFormat.dec', () {
    test('positive value gets explicit + sign (default oneDecimal)', () {
      // Seconds use toStringAsFixed(1), unpadded, matching legacy formatters.
      expect(CoordinateFormat.dec(45.5), "+45° 30' 0.0\"");
    });

    test('negative value gets - sign; degrees/minutes zero-padded', () {
      expect(CoordinateFormat.dec(-5.25), "-05° 15' 0.0\"");
    });

    test('paddedLetters + integerRounded', () {
      expect(
        CoordinateFormat.dec(-45.5, seconds: SecondsPrecision.integerRounded),
        "-45° 30' 00\"",
      );
    });

    test('paddedColons + integerRounded', () {
      expect(
        CoordinateFormat.dec(
          45.5,
          style: SexagesimalStyle.paddedColons,
          seconds: SecondsPrecision.integerRounded,
        ),
        '+45:30:00',
      );
    });
  });
}
