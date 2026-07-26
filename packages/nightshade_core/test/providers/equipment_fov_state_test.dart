import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  test('EquipmentFovState can clear stale nullable dimensions', () {
    const configured = EquipmentFovState(
      widthDegrees: 2.4,
      heightDegrees: 1.6,
      rotationDegrees: 37,
    );

    final cleared = configured.copyWith(
      widthDegrees: null,
      heightDegrees: null,
    );

    expect(cleared.widthDegrees, isNull);
    expect(cleared.heightDegrees, isNull);
    expect(cleared.hasFov, isFalse);
    expect(cleared.rotationDegrees, 37);
  });

  test('EquipmentFovState preserves dimensions when they are omitted', () {
    const configured = EquipmentFovState(widthDegrees: 2.4, heightDegrees: 1.6);

    final rotated = configured.copyWith(rotationDegrees: 90);

    expect(rotated.widthDegrees, 2.4);
    expect(rotated.heightDegrees, 1.6);
    expect(rotated.rotationDegrees, 90);
  });
}
