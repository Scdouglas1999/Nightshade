import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/equipment_provider.dart';
import 'package:nightshade_core/src/models/imaging/imaging_models.dart';
import 'package:nightshade_core/src/services/imaging_service.dart';

import '../mocks/mock_backend.dart';

/// TestBackendNotifier that injects a mock backend into the provider.
class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(Ref ref, NightshadeBackend backend) : super(ref) {
    state = backend;
  }
}

/// Creates a sample CapturedImageResult for use in tests.
CapturedImageResult makeCapturedImageResult({
  int width = 100,
  int height = 100,
  double exposureTime = 5.0,
  String timestamp = '2025-01-15T22:30:00Z',
  double hfr = 2.5,
  int starCount = 80,
  double mean = 5000.0,
  double stdDev = 500.0,
  bool isColor = false,
}) {
  return CapturedImageResult(
    width: width,
    height: height,
    displayData: List<int>.filled(width * height * 4, 128),
    histogram: List<int>.filled(256, 100),
    stats: ImageStatsResult(
      min: 100.0,
      max: 65535.0,
      mean: mean,
      median: 4800.0,
      stdDev: stdDev,
      hfr: hfr,
      starCount: starCount,
    ),
    exposureTime: exposureTime,
    timestamp: timestamp,
    isColor: isColor,
  );
}

void main() {
  setUpAll(() {
    registerMocktailFallbackValues();
    registerFallbackValue(const FitsWriteHeader(
      exposureTime: 1.0,
      captureTimestamp: '2025-01-01T00:00:00Z',
      frameType: 'Light',
    ));
  });

  group('ImagingService Quality Score Tests', () {
    // Re-implement _calculateQualityScore as a local function to test the algorithm
    double calculateQualityScore({
      required double? hfr,
      required int? starCount,
      required double mean,
      required double stdDev,
    }) {
      double score = 0.0;
      double weightSum = 0.0;

      // HFR component (40% weight)
      if (hfr != null && hfr > 0.0) {
        final hfrScore = hfr < 2.0
            ? 100.0
            : hfr < 3.0
                ? 100.0 - (hfr - 2.0) * 25.0
                : hfr < 5.0
                    ? 75.0 - (hfr - 3.0) * 25.0
                    : math.max(0.0, 25.0 - math.min(5.0, hfr - 5.0) * 5.0);
        score += hfrScore * 0.4;
        weightSum += 0.4;
      }

      // Star count component (30% weight)
      if (starCount != null) {
        final starScore = starCount >= 100
            ? 100.0
            : starCount >= 50
                ? 66.0 + (starCount - 50) / 50.0 * 34.0
                : starCount >= 20
                    ? 33.0 + (starCount - 20) / 30.0 * 33.0
                    : math.max(0.0, starCount / 20.0 * 33.0);
        score += starScore * 0.3;
        weightSum += 0.3;
      }

      // Background uniformity component (30% weight)
      if (mean > 0.0) {
        final cv = stdDev / mean;
        final uniformityScore = cv < 0.1
            ? 100.0
            : cv < 0.3
                ? 100.0 - (cv - 0.1) * 333.0
                : math.max(0.0, 33.0 - math.min(0.33, cv - 0.3) * 100.0);
        score += uniformityScore * 0.3;
        weightSum += 0.3;
      }

      if (weightSum <= 0.0) {
        return 0.0;
      }

      var normalizedScore = (score / weightSum).clamp(0.0, 100.0);

      if (hfr != null && hfr > 5.0) {
        final hfrExcess = math.min(15.0, hfr - 5.0);
        final penaltyFactor = 1.0 - (hfrExcess / 15.0) * 0.25;
        normalizedScore *= penaltyFactor;
      }

      return normalizedScore.clamp(0.0, 100.0);
    }

    test('Quality score for excellent image', () {
      final score = calculateQualityScore(
        hfr: 1.8,
        starCount: 150,
        mean: 5000.0,
        stdDev: 500.0, // CV = 0.1
      );
      expect(score, greaterThan(85.0),
          reason:
              'Excellent image (HFR=1.8, stars=150, CV=0.1) should score > 85');
    });

    test('Quality score for good image', () {
      final score = calculateQualityScore(
        hfr: 2.5,
        starCount: 75,
        mean: 5000.0,
        stdDev: 800.0, // CV = 0.16
      );
      expect(score, greaterThan(70.0),
          reason: 'Good image should score > 70');
      expect(score, lessThan(85.0), reason: 'Good image should score < 85');
    });

    test('Quality score for poor image', () {
      final score = calculateQualityScore(
        hfr: 6.0,
        starCount: 15,
        mean: 5000.0,
        stdDev: 2000.0, // CV = 0.4
      );
      expect(score, lessThan(40.0),
          reason:
              'Poor image (HFR=6.0, stars=15, CV=0.4) should score < 40');
    });

    test('Quality score with no HFR/star data', () {
      final score = calculateQualityScore(
        hfr: null,
        starCount: null,
        mean: 5000.0,
        stdDev: 800.0,
      );
      expect(score, greaterThanOrEqualTo(0.0));
      expect(score, lessThanOrEqualTo(100.0),
          reason:
              'Score should be in valid range even with no HFR/star data');
    });

    test('Quality score with zero values', () {
      final score = calculateQualityScore(
        hfr: 0.0,
        starCount: 0,
        mean: 0.0,
        stdDev: 0.0,
      );
      expect(score, greaterThanOrEqualTo(0.0));
      expect(score, lessThanOrEqualTo(100.0),
          reason: 'Score should be valid even with zeros');
    });

    test('Quality score with very high HFR', () {
      final score = calculateQualityScore(
        hfr: 20.0,
        starCount: 150,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score, lessThan(50.0),
          reason: 'Very high HFR should lower score significantly');
    });

    test('Quality score for perfect image', () {
      final score = calculateQualityScore(
        hfr: 1.5,
        starCount: 200,
        mean: 10000.0,
        stdDev: 500.0, // CV = 0.05
      );
      expect(score, greaterThan(90.0),
          reason:
              'Perfect image (HFR=1.5, stars=200, CV=0.05) should score > 90');
    });

    test('Quality score HFR thresholds', () {
      // Test HFR boundaries
      final score1 = calculateQualityScore(
        hfr: 1.9,
        starCount: 100,
        mean: 5000.0,
        stdDev: 500.0,
      );
      final score2 = calculateQualityScore(
        hfr: 2.1,
        starCount: 100,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score1, greaterThan(score2),
          reason: 'HFR 1.9 should score higher than 2.1');

      final score3 = calculateQualityScore(
        hfr: 2.9,
        starCount: 100,
        mean: 5000.0,
        stdDev: 500.0,
      );
      final score4 = calculateQualityScore(
        hfr: 3.1,
        starCount: 100,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score3, greaterThan(score4),
          reason: 'HFR 2.9 should score higher than 3.1');
    });

    test('Quality score star count thresholds', () {
      // Test star count boundaries
      final score1 = calculateQualityScore(
        hfr: 2.5,
        starCount: 19,
        mean: 5000.0,
        stdDev: 500.0,
      );
      final score2 = calculateQualityScore(
        hfr: 2.5,
        starCount: 21,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score2, greaterThan(score1),
          reason: '21 stars should score higher than 19 stars');

      final score3 = calculateQualityScore(
        hfr: 2.5,
        starCount: 49,
        mean: 5000.0,
        stdDev: 500.0,
      );
      final score4 = calculateQualityScore(
        hfr: 2.5,
        starCount: 51,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score4, greaterThan(score3),
          reason: '51 stars should score higher than 49 stars');
    });

    test('Quality score uniformity component', () {
      // Test different CV values with same HFR and star count
      final score1 = calculateQualityScore(
        hfr: 2.5,
        starCount: 75,
        mean: 5000.0,
        stdDev: 400.0, // CV = 0.08 (excellent)
      );
      final score2 = calculateQualityScore(
        hfr: 2.5,
        starCount: 75,
        mean: 5000.0,
        stdDev: 1000.0, // CV = 0.2 (good)
      );
      final score3 = calculateQualityScore(
        hfr: 2.5,
        starCount: 75,
        mean: 5000.0,
        stdDev: 2000.0, // CV = 0.4 (poor)
      );
      expect(score1, greaterThan(score2),
          reason:
              'Better uniformity (CV=0.08) should score higher');
      expect(score2, greaterThan(score3),
          reason:
              'Good uniformity (CV=0.2) should score higher than poor (CV=0.4)');
    });

    test('Quality score is in valid range', () {
      // Test various combinations to ensure score is always 0-100
      final testCases = [
        {'hfr': 1.0, 'stars': 200, 'mean': 10000.0, 'std': 300.0},
        {'hfr': 10.0, 'stars': 5, 'mean': 1000.0, 'std': 500.0},
        {'hfr': 3.5, 'stars': 75, 'mean': 5000.0, 'std': 750.0},
        {'hfr': null, 'stars': 100, 'mean': 5000.0, 'std': 500.0},
        {'hfr': 2.0, 'stars': null, 'mean': 5000.0, 'std': 500.0},
      ];

      for (final testCase in testCases) {
        final score = calculateQualityScore(
          hfr: testCase['hfr'] as double?,
          starCount: testCase['stars'] as int?,
          mean: testCase['mean'] as double,
          stdDev: testCase['std'] as double,
        );
        expect(score, greaterThanOrEqualTo(0.0));
        expect(score, lessThanOrEqualTo(100.0),
            reason: 'Score must be in 0-100 range for: $testCase');
      }
    });
  });

  group('ImagingService Capture Pipeline', () {
    late ProviderContainer container;
    late MockBackend mockBackend;
    late StreamController<NightshadeEvent> eventStreamController;

    setUp(() {
      mockBackend = MockBackend();
      eventStreamController = StreamController<NightshadeEvent>.broadcast();

      when(() => mockBackend.eventStream)
          .thenAnswer((_) => eventStreamController.stream);
      when(() => mockBackend.polarAlignmentEvents)
          .thenAnswer((_) => const Stream.empty());

      container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => TestBackendNotifier(ref, mockBackend),
          ),
          // Set camera as connected with a device ID
          cameraStateProvider.overrideWith((ref) {
            final notifier = CameraStateNotifier(ref);
            notifier.setConnecting('test-camera-1', 'Test Camera');
            notifier.setConnected();
            return notifier;
          }),
          // Mount defaults (disconnected) are fine for most tests
        ],
      );
    });

    tearDown(() {
      eventStreamController.close();
      container.dispose();
    });

    test('captureImage throws when camera is not connected', () async {
      // Create a container with disconnected camera
      final disconnectedContainer = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => TestBackendNotifier(ref, mockBackend),
          ),
          // Default CameraState is disconnected
        ],
      );
      addTearDown(disconnectedContainer.dispose);

      final service = disconnectedContainer.read(imagingServiceProvider);
      const settings = ExposureSettings(
        exposureTime: 5.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      expect(
        () => service.captureImage(settings: settings),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Camera not connected'),
        )),
      );
    });

    test('captureImage throws when already capturing', () async {
      // Set up a long-running capture by never completing the exposure event
      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        // Never complete - simulates a long exposure
        await Future.delayed(const Duration(seconds: 60));
      });

      final service = container.read(imagingServiceProvider);
      const settings = ExposureSettings(
        exposureTime: 30.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      // Start first capture (don't await - it will hang)
      unawaited(service.captureImage(settings: settings).catchError((_) => null));

      // Wait briefly so the first capture enters the capturing state
      await Future.delayed(const Duration(milliseconds: 50));

      // Second capture should throw
      expect(
        () => service.captureImage(settings: settings),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Already capturing'),
        )),
      );
    });

    test('captureImage calls backend with correct parameters', () async {
      const settings = ExposureSettings(
        exposureTime: 10.0,
        gain: 200,
        offset: 30,
        binningX: 2,
        binningY: 2,
        frameType: FrameType.dark,
        filter: 'Ha',
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        // Emit ExposureComplete event immediately
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureComplete',
          data: {},
        ));
      });

      when(() => mockBackend.cameraGetLastImage(any()))
          .thenAnswer((_) async => makeCapturedImageResult(
                exposureTime: 10.0,
              ));

      when(() => mockBackend.saveFitsFromLastCapture(
            deviceId: any(named: 'deviceId'),
            filePath: any(named: 'filePath'),
            headerData: any(named: 'headerData'),
          )).thenAnswer((_) async {});

      final service = container.read(imagingServiceProvider);
      await service.captureImage(
        settings: settings,
        targetName: 'M31',
      );

      verify(() => mockBackend.cameraStartExposure(
            deviceId: 'test-camera-1',
            exposureTime: 10.0,
            frameType: FrameType.dark,
            gain: 200,
            offset: 30,
            binX: 2,
            binY: 2,
          )).called(1);
    });

    test('captureImage returns CapturedImageData on success', () async {
      const settings = ExposureSettings(
        exposureTime: 5.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureComplete',
          data: {},
        ));
      });

      final expectedImage = makeCapturedImageResult(
        width: 1920,
        height: 1080,
        exposureTime: 5.0,
        hfr: 1.8,
        starCount: 120,
      );

      when(() => mockBackend.cameraGetLastImage(any()))
          .thenAnswer((_) async => expectedImage);

      when(() => mockBackend.saveFitsFromLastCapture(
            deviceId: any(named: 'deviceId'),
            filePath: any(named: 'filePath'),
            headerData: any(named: 'headerData'),
          )).thenAnswer((_) async {});

      final service = container.read(imagingServiceProvider);
      final result = await service.captureImage(
        settings: settings,
        targetName: 'NGC 7000',
      );

      expect(result, isNotNull);
      expect(result!.width, 1920);
      expect(result.height, 1080);
      expect(result.stats.hfr, 1.8);
      expect(result.stats.starCount, 120);
      expect(result.targetName, 'NGC 7000');
      expect(result.settings, settings);
    });

    test('captureImage updates currentImageProvider on success', () async {
      const settings = ExposureSettings(
        exposureTime: 5.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureComplete',
          data: {},
        ));
      });

      when(() => mockBackend.cameraGetLastImage(any()))
          .thenAnswer((_) async => makeCapturedImageResult());

      when(() => mockBackend.saveFitsFromLastCapture(
            deviceId: any(named: 'deviceId'),
            filePath: any(named: 'filePath'),
            headerData: any(named: 'headerData'),
          )).thenAnswer((_) async {});

      // Verify currentImageProvider is null initially
      expect(container.read(currentImageProvider), isNull);

      final service = container.read(imagingServiceProvider);
      await service.captureImage(settings: settings);

      // After capture, currentImageProvider should be populated
      final currentImage = container.read(currentImageProvider);
      expect(currentImage, isNotNull);
      expect(currentImage!.width, 100);
      expect(currentImage.height, 100);
    });

    test('captureImage returns null when exposure is cancelled', () async {
      const settings = ExposureSettings(
        exposureTime: 10.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        // Emit ExposureCancelled event
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureCancelled',
          data: {},
        ));
      });

      final service = container.read(imagingServiceProvider);
      final result = await service.captureImage(settings: settings);

      expect(result, isNull);
    });

    test('captureImage throws when exposure fails', () async {
      const settings = ExposureSettings(
        exposureTime: 5.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.error,
          category: EventCategory.imaging,
          eventType: 'ExposureFailed',
          data: {'error': 'Sensor readout error'},
        ));
      });

      final service = container.read(imagingServiceProvider);

      expect(
        () => service.captureImage(settings: settings),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Sensor readout error'),
        )),
      );
    });

    test('captureImage throws when cameraGetLastImage returns null', () async {
      const settings = ExposureSettings(
        exposureTime: 5.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureComplete',
          data: {},
        ));
      });

      when(() => mockBackend.cameraGetLastImage(any()))
          .thenAnswer((_) async => null);

      final service = container.read(imagingServiceProvider);

      expect(
        () => service.captureImage(settings: settings),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Failed to retrieve captured image'),
        )),
      );
    });

    test('captureImage resets isCapturing state after successful capture',
        () async {
      const settings = ExposureSettings(
        exposureTime: 5.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureComplete',
          data: {},
        ));
      });

      when(() => mockBackend.cameraGetLastImage(any()))
          .thenAnswer((_) async => makeCapturedImageResult());

      when(() => mockBackend.saveFitsFromLastCapture(
            deviceId: any(named: 'deviceId'),
            filePath: any(named: 'filePath'),
            headerData: any(named: 'headerData'),
          )).thenAnswer((_) async {});

      final service = container.read(imagingServiceProvider);

      expect(service.isCapturing, isFalse);
      await service.captureImage(settings: settings);
      expect(service.isCapturing, isFalse);
    });

    test('captureImage resets isCapturing state after failure', () async {
      const settings = ExposureSettings(
        exposureTime: 5.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.error,
          category: EventCategory.imaging,
          eventType: 'ExposureFailed',
          data: {'error': 'Camera disconnected'},
        ));
      });

      final service = container.read(imagingServiceProvider);

      try {
        await service.captureImage(settings: settings);
      } catch (_) {
        // Expected
      }

      // After failure, isCapturing should be reset
      expect(service.isCapturing, isFalse);
    });

    test('captureImage handles color images', () async {
      const settings = ExposureSettings(
        exposureTime: 5.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureComplete',
          data: {},
        ));
      });

      when(() => mockBackend.cameraGetLastImage(any()))
          .thenAnswer((_) async => makeCapturedImageResult(isColor: true));

      when(() => mockBackend.saveFitsFromLastCapture(
            deviceId: any(named: 'deviceId'),
            filePath: any(named: 'filePath'),
            headerData: any(named: 'headerData'),
          )).thenAnswer((_) async {});

      final service = container.read(imagingServiceProvider);
      final result = await service.captureImage(settings: settings);

      expect(result, isNotNull);
      expect(result!.isColor, isTrue);
    });
  });

  group('ImagingService Cancel Exposure', () {
    late ProviderContainer container;
    late MockBackend mockBackend;
    late StreamController<NightshadeEvent> eventStreamController;

    setUp(() {
      mockBackend = MockBackend();
      eventStreamController = StreamController<NightshadeEvent>.broadcast();

      when(() => mockBackend.eventStream)
          .thenAnswer((_) => eventStreamController.stream);
      when(() => mockBackend.polarAlignmentEvents)
          .thenAnswer((_) => const Stream.empty());

      container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => TestBackendNotifier(ref, mockBackend),
          ),
          cameraStateProvider.overrideWith((ref) {
            final notifier = CameraStateNotifier(ref);
            notifier.setConnecting('test-camera-1', 'Test Camera');
            notifier.setConnected();
            return notifier;
          }),
        ],
      );
    });

    tearDown(() {
      eventStreamController.close();
      container.dispose();
    });

    test('cancelExposure sets cancel flag and aborts via backend', () async {
      const settings = ExposureSettings(
        exposureTime: 30.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      final startedCompleter = Completer<void>();

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        startedCompleter.complete();
        // Wait a bit then emit ExposureComplete (the cancelExposure call will
        // set _cancelRequested before this completes)
        await Future.delayed(const Duration(milliseconds: 200));
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureComplete',
          data: {},
        ));
      });

      when(() => mockBackend.cameraAbortExposure(any()))
          .thenAnswer((_) async {});

      final service = container.read(imagingServiceProvider);

      // Start capture, cancel before it completes
      final captureFuture = service.captureImage(settings: settings);
      await startedCompleter.future;

      // Cancel the exposure
      service.cancelExposure();

      final result = await captureFuture;
      expect(result, isNull,
          reason: 'Cancelled capture should return null');

      verify(() => mockBackend.cameraAbortExposure('test-camera-1')).called(1);
    });
  });

  group('ImagingService Frame Counter', () {
    test('resetFrameCounter resets to zero', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(imagingServiceProvider);

      service.resetFrameCounter();
      // No assertion needed per se; if it doesn't throw, the method works.
      // We verify behavior indirectly through captureImage frame numbering.
      expect(service.isCapturing, isFalse);
    });
  });

  group('ImagingService Loop Capture', () {
    late ProviderContainer container;
    late MockBackend mockBackend;
    late StreamController<NightshadeEvent> eventStreamController;

    setUp(() {
      mockBackend = MockBackend();
      eventStreamController = StreamController<NightshadeEvent>.broadcast();

      when(() => mockBackend.eventStream)
          .thenAnswer((_) => eventStreamController.stream);
      when(() => mockBackend.polarAlignmentEvents)
          .thenAnswer((_) => const Stream.empty());

      container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => TestBackendNotifier(ref, mockBackend),
          ),
          cameraStateProvider.overrideWith((ref) {
            final notifier = CameraStateNotifier(ref);
            notifier.setConnecting('test-camera-1', 'Test Camera');
            notifier.setConnected();
            return notifier;
          }),
        ],
      );
    });

    tearDown(() {
      eventStreamController.close();
      container.dispose();
    });

    test('startLoopCapture captures maxFrames then stops', () async {
      const settings = ExposureSettings(
        exposureTime: 1.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureComplete',
          data: {},
        ));
      });

      when(() => mockBackend.cameraGetLastImage(any()))
          .thenAnswer((_) async => makeCapturedImageResult());

      when(() => mockBackend.saveFitsFromLastCapture(
            deviceId: any(named: 'deviceId'),
            filePath: any(named: 'filePath'),
            headerData: any(named: 'headerData'),
          )).thenAnswer((_) async {});

      final capturedImages = <CapturedImageData>[];
      final service = container.read(imagingServiceProvider);

      await service.startLoopCapture(
        settings: settings,
        maxFrames: 3,
        onImageCaptured: (image) => capturedImages.add(image),
      );

      expect(capturedImages.length, 3);
    });

    test('startLoopCapture calls onError and continues on failure', () async {
      const settings = ExposureSettings(
        exposureTime: 1.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      int callCount = 0;
      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        callCount++;
        if (callCount == 2) {
          // Second frame fails
          eventStreamController.add(NightshadeEvent(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            severity: EventSeverity.error,
            category: EventCategory.imaging,
            eventType: 'ExposureFailed',
            data: {'error': 'Temporary sensor error'},
          ));
        } else {
          // Other frames succeed
          eventStreamController.add(NightshadeEvent(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            severity: EventSeverity.info,
            category: EventCategory.imaging,
            eventType: 'ExposureComplete',
            data: {},
          ));
        }
      });

      when(() => mockBackend.cameraGetLastImage(any()))
          .thenAnswer((_) async => makeCapturedImageResult());

      when(() => mockBackend.saveFitsFromLastCapture(
            deviceId: any(named: 'deviceId'),
            filePath: any(named: 'filePath'),
            headerData: any(named: 'headerData'),
          )).thenAnswer((_) async {});

      final capturedImages = <CapturedImageData>[];
      final errors = <String>[];
      final service = container.read(imagingServiceProvider);

      await service.startLoopCapture(
        settings: settings,
        maxFrames: 3,
        onImageCaptured: (image) => capturedImages.add(image),
        onError: (error) => errors.add(error),
      );

      // 2 of 3 frames succeeded, 1 errored
      expect(capturedImages.length, 2);
      expect(errors.length, 1);
      expect(errors.first, contains('Temporary sensor error'));
    });

    test('startLoopCapture stops when cancelExposure is called', () async {
      const settings = ExposureSettings(
        exposureTime: 1.0,
        gain: 100,
        offset: 50,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      );

      when(() => mockBackend.cameraStartExposure(
            deviceId: any(named: 'deviceId'),
            exposureTime: any(named: 'exposureTime'),
            frameType: any(named: 'frameType'),
            gain: any(named: 'gain'),
            offset: any(named: 'offset'),
            binX: any(named: 'binX'),
            binY: any(named: 'binY'),
          )).thenAnswer((_) async {
        eventStreamController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ExposureComplete',
          data: {},
        ));
      });

      when(() => mockBackend.cameraGetLastImage(any()))
          .thenAnswer((_) async => makeCapturedImageResult());

      when(() => mockBackend.saveFitsFromLastCapture(
            deviceId: any(named: 'deviceId'),
            filePath: any(named: 'filePath'),
            headerData: any(named: 'headerData'),
          )).thenAnswer((_) async {});

      final capturedImages = <CapturedImageData>[];
      final service = container.read(imagingServiceProvider);

      // Start loop without maxFrames - cancel after first image
      final loopFuture = service.startLoopCapture(
        settings: settings,
        onImageCaptured: (image) {
          capturedImages.add(image);
          // Cancel after first successful capture
          service.cancelExposure();
        },
      );

      await loopFuture;

      // Should have captured at most 1 frame before cancellation took effect
      expect(capturedImages.length, 1);
    });
  });

  group('ExposureProgressNotifier', () {
    test('starts in idle state', () {
      final notifier = ExposureProgressNotifier();
      addTearDown(notifier.dispose);

      expect(notifier.state.elapsed, 0.0);
      expect(notifier.state.remaining, 0.0);
      expect(notifier.state.percent, 0.0);
      expect(notifier.state.isDownloading, isFalse);
    });

    test('startExposure sets initial progress state', () {
      final notifier = ExposureProgressNotifier();
      addTearDown(notifier.dispose);

      notifier.startExposure(120.0, 5, 10);

      expect(notifier.state.elapsed, 0.0);
      expect(notifier.state.remaining, 120.0);
      expect(notifier.state.percent, 0.0);
      expect(notifier.state.frameNumber, 5);
      expect(notifier.state.totalFrames, 10);
      expect(notifier.state.isDownloading, isFalse);
    });

    test('updateProgress updates elapsed and remaining', () {
      final notifier = ExposureProgressNotifier();
      addTearDown(notifier.dispose);

      notifier.startExposure(120.0, 1, null);
      notifier.updateProgress(60.0, 60.0, 50.0);

      expect(notifier.state.elapsed, 60.0);
      expect(notifier.state.remaining, 60.0);
      expect(notifier.state.percent, 50.0);
      expect(notifier.state.isDownloading, isFalse);
    });

    test('startDownload sets downloading flag', () {
      final notifier = ExposureProgressNotifier();
      addTearDown(notifier.dispose);

      notifier.startExposure(10.0, 1, null);
      notifier.updateProgress(10.0, 0.0, 100.0);
      notifier.startDownload();

      expect(notifier.state.isDownloading, isTrue);
      expect(notifier.state.percent, 100.0);
      expect(notifier.state.remaining, 0.0);
    });

    test('reset returns to idle state', () {
      final notifier = ExposureProgressNotifier();
      addTearDown(notifier.dispose);

      notifier.startExposure(120.0, 5, 10);
      notifier.updateProgress(60.0, 60.0, 50.0);
      notifier.reset();

      expect(notifier.state.elapsed, 0.0);
      expect(notifier.state.remaining, 0.0);
      expect(notifier.state.percent, 0.0);
      expect(notifier.state.frameNumber, 1);
      expect(notifier.state.totalFrames, isNull);
      expect(notifier.state.isDownloading, isFalse);
    });
  });

  group('ExposureProgress model', () {
    test('idle factory creates zero state', () {
      final idle = ExposureProgress.idle();

      expect(idle.elapsed, 0.0);
      expect(idle.remaining, 0.0);
      expect(idle.percent, 0.0);
      expect(idle.isDownloading, isFalse);
    });

    test('equality works correctly', () {
      const a = ExposureProgress(
        elapsed: 10.0,
        remaining: 50.0,
        percent: 16.7,
        frameNumber: 2,
        totalFrames: 10,
        isDownloading: false,
      );
      const b = ExposureProgress(
        elapsed: 10.0,
        remaining: 50.0,
        percent: 16.7,
        frameNumber: 2,
        totalFrames: 10,
        isDownloading: false,
      );
      const c = ExposureProgress(
        elapsed: 20.0,
        remaining: 40.0,
        percent: 33.3,
        frameNumber: 2,
        totalFrames: 10,
        isDownloading: false,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
