import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';

void main() {
  test('release builds always normalize simulation mode to disabled', () {
    expect(effectiveSimulationMode(true, releaseMode: true), isFalse);
    expect(effectiveSimulationMode(false, releaseMode: true), isFalse);
  });

  test('development builds preserve the requested simulation state', () {
    expect(effectiveSimulationMode(true, releaseMode: false), isTrue);
    expect(effectiveSimulationMode(false, releaseMode: false), isFalse);
  });
}
