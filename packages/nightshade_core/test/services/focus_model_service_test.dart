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
  });
}
