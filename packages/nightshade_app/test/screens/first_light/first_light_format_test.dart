import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/first_light/first_light_format.dart';

void main() {
  group('describeFirstLightError', () {
    test('strips the difference-image seam envelope', () {
      expect(
        describeFirstLightError(
          Exception('boring'),
        ),
        'boring',
      );
    });

    test('strips a DifferenceImageSeamException prefix', () {
      expect(
        describeFirstLightError(
          'DifferenceImageSeamException: bridge call failed',
        ),
        'bridge call failed',
      );
    });

    test('leaves a bare message untouched', () {
      expect(describeFirstLightError('no template yet'), 'no template yet');
    });

    test('falls back to a readable label for an empty message', () {
      expect(describeFirstLightError(''), 'Unknown error.');
    });
  });
}
