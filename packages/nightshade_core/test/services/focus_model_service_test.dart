import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/services/focus_model_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('focus-model-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FocusModelService', () {
    test('does not build a temperature model when all temperatures are identical', () async {
      final service = FocusModelService();

      await service.addDataPoint(
        profileId: 'profile-a',
        temperatureCelsius: 12.0,
        focusPosition: 10000,
        hfr: 2.1,
      );
      await service.addDataPoint(
        profileId: 'profile-a',
        temperatureCelsius: 12.0,
        focusPosition: 10010,
        hfr: 2.0,
      );
      await service.addDataPoint(
        profileId: 'profile-a',
        temperatureCelsius: 12.0,
        focusPosition: 9990,
        hfr: 1.9,
      );

      final data = service.getProfileData('profile-a');
      expect(data, isNotNull);
      expect(data!.temperatureModel, isNull);
    });

    test('rejects unrealistic slopes', () async {
      final service = FocusModelService();

      await service.addDataPoint(
        profileId: 'profile-b',
        temperatureCelsius: 10.0,
        focusPosition: 1000,
        hfr: 2.0,
      );
      await service.addDataPoint(
        profileId: 'profile-b',
        temperatureCelsius: 11.0,
        focusPosition: 2200,
        hfr: 1.9,
      );
      await service.addDataPoint(
        profileId: 'profile-b',
        temperatureCelsius: 12.0,
        focusPosition: 3400,
        hfr: 1.8,
      );

      final data = service.getProfileData('profile-b');
      expect(data, isNotNull);
      expect(data!.temperatureModel, isNull);
    });

    // AUDIT-FIX-5B (audit-handoff §4.3 item 5): the `slope.abs() > 500`
    // rejection threshold is now sourced from FocusModelConfig.
    test(
      'maxAcceptableSlopeStepsPerC override accepts what the default would reject',
      () async {
        // Slope ≈ 1200 steps/°C — rejected by the 500-step default.
        Future<void> seed(FocusModelService svc) async {
          await svc.addDataPoint(
            profileId: 'profile-c',
            temperatureCelsius: 10.0,
            focusPosition: 1000,
            hfr: 2.0,
          );
          await svc.addDataPoint(
            profileId: 'profile-c',
            temperatureCelsius: 11.0,
            focusPosition: 2200,
            hfr: 1.9,
          );
          await svc.addDataPoint(
            profileId: 'profile-c',
            temperatureCelsius: 12.0,
            focusPosition: 3400,
            hfr: 1.8,
          );
          await svc.addDataPoint(
            profileId: 'profile-c',
            temperatureCelsius: 13.0,
            focusPosition: 4600,
            hfr: 1.85,
          );
          await svc.addDataPoint(
            profileId: 'profile-c',
            temperatureCelsius: 14.0,
            focusPosition: 5800,
            hfr: 1.95,
          );
        }

        // Default config (500-step gate): regression rejected.
        final defaultSvc = FocusModelService();
        await seed(defaultSvc);
        expect(
          defaultSvc.getProfileData('profile-c')?.temperatureModel,
          isNull,
          reason: 'slope ≈ 1200 must be rejected at default 500-step gate',
        );

        // Permissive config (2000-step gate): same data yields a model.
        final permissiveSvc = FocusModelService(
          config: const FocusModelConfig(maxAcceptableSlopeStepsPerC: 2000),
        );
        await seed(permissiveSvc);
        final model =
            permissiveSvc.getProfileData('profile-c')?.temperatureModel;
        expect(
          model,
          isNotNull,
          reason: 'raising maxAcceptableSlopeStepsPerC must accept the model',
        );
        expect(model!.slope.abs(), greaterThan(500));
      },
    );

    // AUDIT-FIX-5B (§4.3 item 5): `FocusModel.isReliable` was hardcoded to
    // `rSquared >= 0.7 && dataPointCount >= 5`. The new isReliableWith() takes
    // user-configurable thresholds.
    test('isReliableWith honours the FocusModelConfig thresholds', () {
      final model = FocusModel(
        slope: 50,
        intercept: 0,
        rSquared: 0.6,
        dataPointCount: 4,
        lastUpdated: DateTime.now(),
      );

      // Default thresholds reject this model (rSquared=0.6 < 0.7, count=4 < 5).
      expect(model.isReliable, isFalse);
      expect(model.isReliableWith(const FocusModelConfig()), isFalse);

      // Lower the bars: now accepted.
      expect(
        model.isReliableWith(const FocusModelConfig(
          minRSquared: 0.5,
          minDataPointCount: 3,
        )),
        isTrue,
      );

      // Only lowering one bar still rejects.
      expect(
        model.isReliableWith(const FocusModelConfig(minRSquared: 0.5)),
        isFalse,
        reason: 'minDataPointCount default 5 still rejects 4 points',
      );
    });
  });
}
