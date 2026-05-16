import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  group('OnboardingDraft', () {
    test('defaults to welcome step with empty selections', () {
      const draft = OnboardingDraft();
      expect(draft.currentStep, OnboardingStep.welcome);
      expect(draft.selectedDrivers, isEmpty);
      expect(draft.cameraId, isNull);
      expect(draft.reducerFactor, 1.0);
      expect(draft.filterNames, isEmpty);
    });

    test('imageScaleArcsecPerPixel returns null when inputs missing', () {
      const draft = OnboardingDraft();
      expect(draft.imageScaleArcsecPerPixel, isNull);

      const onlyFocal = OnboardingDraft(focalLengthMm: 1000);
      expect(onlyFocal.imageScaleArcsecPerPixel, isNull);

      const onlyPixel = OnboardingDraft(pixelSizeMicrons: 3.76);
      expect(onlyPixel.imageScaleArcsecPerPixel, isNull);
    });

    test('imageScaleArcsecPerPixel applies reducer factor', () {
      // 1000mm × 0.79 reducer, 3.76 µm pixels → 0.98 arcsec/px
      const draft = OnboardingDraft(
        focalLengthMm: 1000,
        pixelSizeMicrons: 3.76,
        reducerFactor: 0.79,
      );
      final scale = draft.imageScaleArcsecPerPixel!;
      expect(scale, closeTo(0.98, 0.02));
    });

    test('copyWith preserves unspecified fields', () {
      const original = OnboardingDraft(
        cameraId: 'cam-1',
        mountId: 'mount-1',
        focalLengthMm: 500,
      );
      final updated = original.copyWith(focalLengthMm: 1000);
      expect(updated.cameraId, 'cam-1');
      expect(updated.mountId, 'mount-1');
      expect(updated.focalLengthMm, 1000);
    });

    test('copyWith clear flags wipe individual device picks', () {
      const original = OnboardingDraft(
        focuserId: 'foc-1',
        focuserName: 'My focuser',
        filterWheelId: 'fw-1',
        guiderId: 'g-1',
      );
      final cleared = original.copyWith(
        clearFocuser: true,
        clearFilterWheel: true,
        clearGuider: true,
      );
      expect(cleared.focuserId, isNull);
      expect(cleared.focuserName, isNull);
      expect(cleared.filterWheelId, isNull);
      expect(cleared.guiderId, isNull);
    });

    test('JSON round-trip preserves all fields', () {
      final draft = OnboardingDraft(
        currentStep: OnboardingStep.opticalTrain,
        selectedDrivers: {DriverType.native, DriverType.ascom},
        cameraId: 'native:zwo:0',
        cameraName: 'ASI294MC Pro',
        mountId: 'ascom:EQMOD',
        mountName: 'EQ6-R',
        focalLengthMm: 1000,
        apertureMm: 80,
        pixelSizeMicrons: 3.76,
        reducerFactor: 0.79,
        filterNames: const ['L', 'R', 'G', 'B'],
        captureDirectory: 'C:/captures',
        profileName: 'Main rig',
      );
      final json = draft.toJsonString();
      final restored = OnboardingDraft.fromJsonStringOrEmpty(json);
      expect(restored, draft);
    });

    test('fromJsonStringOrEmpty returns default on invalid input', () {
      expect(OnboardingDraft.fromJsonStringOrEmpty(null),
          const OnboardingDraft());
      expect(OnboardingDraft.fromJsonStringOrEmpty(''),
          const OnboardingDraft());
      expect(OnboardingDraft.fromJsonStringOrEmpty('not json'),
          const OnboardingDraft());
      // Wrong shape (array instead of object)
      expect(OnboardingDraft.fromJsonStringOrEmpty('[1,2,3]'),
          const OnboardingDraft());
    });

    test('optional steps are flagged for skip-button rendering', () {
      expect(OnboardingStep.focuser.isOptional, isTrue);
      expect(OnboardingStep.filterWheel.isOptional, isTrue);
      expect(OnboardingStep.guider.isOptional, isTrue);
      expect(OnboardingStep.camera.isOptional, isFalse);
      expect(OnboardingStep.mount.isOptional, isFalse);
      expect(OnboardingStep.opticalTrain.isOptional, isFalse);
    });

    test('step order maps to display index', () {
      expect(OnboardingStep.welcome.order, 0);
      expect(OnboardingStep.summary.order,
          OnboardingStep.values.length - 1);
      expect(OnboardingStepOrder.total, OnboardingStep.values.length);
    });
  });
}
