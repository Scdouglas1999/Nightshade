import 'package:test/test.dart';
import 'package:nightshade_core/src/providers/framing_provider.dart';
import 'package:nightshade_core/src/models/target/target_models.dart';

void main() {
  test('FramingTarget.raDegrees converts hours to degrees correctly', () {
    const target = FramingTarget(
      name: 'M31',
      raHours: 0.7123,
      decDegrees: 41.2689,
    );
    
    expect(target.raDegrees, closeTo(10.6845, 0.0001));
  });

  test('Verify M31 coordinates (dynamic lookup simulation)', () {
    // This test just verifies our assumptions about coordinate formats
    // M31 RA: 00h 42m 44.3s = 42.738m = 0.7123h
    // M31 Dec: +41° 16' 09" = 41 + 16/60 + 9/3600 = 41.2692°
    
    final raHours = 0 + 42/60 + 44.3/3600;
    final decDegrees = 41 + 16/60 + 9/3600;
    
    expect(raHours, closeTo(0.7123, 0.001));
    expect(decDegrees, closeTo(41.2692, 0.001));
  });
}
