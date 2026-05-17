import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/models/flat_wizard/flat_wizard_settings.dart';
import 'package:nightshade_core/src/services/flat_wizard_service.dart';

// AUDIT-FIX-5B (audit-handoff §4.3 item 4): regression tests proving the
// previously-hardcoded constants in flat_wizard_service.dart are now sourced
// from FlatWizardGlobalSettings.

class _FakeBackend extends Mock implements NightshadeBackend {}

void main() {
  group('FlatWizardService.fromSettings', () {
    test('default settings reproduce the prior hardcoded values', () {
      final svc = FlatWizardService.fromSettings(
        _FakeBackend(),
        const FlatWizardGlobalSettings(),
      );
      expect(svc.imageDownloadTimeout, const Duration(seconds: 60));
      expect(svc.defaultMaxIterations, 8);
      expect(svc.quickMinExposure, 0.001);
      expect(svc.quickMaxExposure, 30.0);
    });

    test('overridden settings flow into the service fields', () {
      final svc = FlatWizardService.fromSettings(
        _FakeBackend(),
        const FlatWizardGlobalSettings(
          imageDownloadTimeoutSeconds: 180,
          maxIterations: 16,
          minExposure: 0.0005,
          maxExposure: 60.0,
        ),
      );
      expect(svc.imageDownloadTimeout, const Duration(seconds: 180));
      expect(svc.defaultMaxIterations, 16);
      expect(svc.quickMinExposure, 0.0005);
      expect(svc.quickMaxExposure, 60.0);
    });
  });
}
