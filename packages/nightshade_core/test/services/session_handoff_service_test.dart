import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  group('SessionHandoffService', () {
    const service = SessionHandoffService();

    test('round-trips a quick start context through serialized bundle', () {
      final bundle = service.exportBundle(
        QuickStartContext(
          sessionId: 42,
          sessionName: 'Horsehead',
          targetName: 'Horsehead Nebula',
          targetRa: 5.7,
          targetDec: -2.5,
          sequenceName: 'NB sequence',
          completedFrames: 18,
          totalFrames: 60,
          lastSessionDate: DateTime(2026, 3, 10),
          equipmentSnapshot: EquipmentSnapshot(
            cameraGain: 100,
            filterPosition: 2,
            exposureTime: 300,
            capturedAt: DateTime(2026, 3, 10),
          ),
          totalIntegrationHours: 1.5,
        ),
      );

      final decoded = SessionHandoffBundle.decode(bundle.encode());

      expect(decoded.sessionId, 42);
      expect(decoded.targetName, 'Horsehead Nebula');
      expect(decoded.equipmentSnapshot?.cameraGain, 100);
      expect(service.describe(decoded), contains('18/60'));
    });
  });
}
