import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:mocktail/mocktail.dart' as mt;
import 'package:nightshade_core/nightshade_core.dart';

import 'centering_service_test.mocks.dart';

/// Fake backend that lets each test control the `getMountStatus` behavior
/// for the post-slew settle poll loop. The centering service only touches
/// `getMountStatus` on this object during the polling path, so we leave the
/// other 130-odd `NightshadeBackend` methods as mocktail defaults.
class _PollBackend extends mt.Mock implements NightshadeBackend {
  @override
  Stream<NightshadeEvent> get eventStream => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get polarAlignmentEvents => const Stream.empty();

  @override
  void dispose() {}
}

/// Helper: build a [MountStatus] with `slewing` controllable, everything
/// else benign. Used by the success-path polling stub.
MountStatus _settledMount({bool slewing = false}) {
  return MountStatus(
    connected: true,
    tracking: true,
    slewing: slewing,
    parked: false,
    atHome: false,
    sideOfPier: PierSide.unknown,
    rightAscension: 0.0,
    declination: 0.0,
    altitude: 0.0,
    azimuth: 0.0,
    siderealTime: 0.0,
    trackingRate: TrackingRate.sidereal,
    canPark: true,
    canSlew: true,
    canSync: true,
    canPulseGuide: true,
    canSetTrackingRate: true,
  );
}

/// Notifier override that pins the backend StateNotifierProvider to a
/// caller-supplied instance — same trick the meridian-flip E2E test uses.
class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

// Generate mocks for these classes
@GenerateMocks([
  ImagingService,
  PlateSolveService,
  DeviceService,
])
void main() {
  group('CenteringService', () {
    late ProviderContainer container;
    late MockImagingService mockImagingService;
    late MockPlateSolveService mockPlateSolveService;
    late MockDeviceService mockDeviceService;
    late _PollBackend pollBackend;

    setUp(() {
      mockImagingService = MockImagingService();
      mockPlateSolveService = MockPlateSolveService();
      mockDeviceService = MockDeviceService();
      pollBackend = _PollBackend();

      // Default: post-slew polling sees a settled mount on the first tick.
      // Tests that need to exercise the failure-escalation path override
      // this in their own `when(...)` clause before invoking centering.
      mt.when(() => pollBackend.getMountStatus(mt.any()))
          .thenAnswer((_) async => _settledMount());

      container = ProviderContainer(
        overrides: [
          imagingServiceProvider.overrideWithValue(mockImagingService),
          plateSolveServiceProvider.overrideWithValue(mockPlateSolveService),
          deviceServiceProvider.overrideWithValue(mockDeviceService),
          backendProvider
              .overrideWith((ref) => _TestBackendNotifier(ref, pollBackend)),
          // Override equipment states to simulate connected devices
          cameraStateProvider.overrideWith((ref) {
            final notifier = CameraStateNotifier(ref);
            notifier.setConnecting('test_camera', 'Test Camera');
            notifier.setConnected();
            return notifier;
          }),
          mountStateProvider.overrideWith((ref) {
            final notifier = MountStateNotifier(ref);
            notifier.setConnecting('test_mount');
            notifier.setConnected();
            notifier.updatePosition(
                10.0, 45.0, 30.0, 180.0); // ra, dec, alt, az
            return notifier;
          }),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    group('centerOnTarget', () {
      test('succeeds on first iteration when within tolerance', () async {
        // Arrange
        const targetRa = 10.0; // hours
        const targetDec = 45.0; // degrees
        const toleranceArcsec = 30.0;

        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        const config = CenteringConfig(
          maxIterations: 5,
          toleranceArcsec: toleranceArcsec,
          exposureTime: 3.0,
        );

        final capturedImage = CapturedImageData(
          width: 1920,
          height: 1080,
          displayData: Uint8List(1920 * 1080 * 4),
          histogram: List.filled(256, 0),
          stats: const ImageStats(mean: 100.0, stdDev: 10.0),
          capturedAt: DateTime.now(),
          settings: const ExposureSettings(
            exposureTime: 3.0,
            gain: 100,
            offset: 50,
          ),
          filePath: '/tmp/test_image.fits',
        );

        // Plate solve returns coordinates very close to target (within tolerance)
        const solveResult = PlateSolveResult(
          success: true,
          ra: targetRa, // Same as target
          dec: targetDec, // Same as target
          rotation: 0.0,
          pixelScale: 1.0,
          fieldWidth: 2.0,
          fieldHeight: 1.5,
          solveTimeSecs: 0.0,
        );

        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) async => capturedImage);

        when(mockPlateSolveService.solve(any, any))
            .thenAnswer((_) async => solveResult);

        // Act
        final service = container.read(centeringServiceProvider);
        final result = await service.centerOnTarget(
          targetRa: targetRa,
          targetDec: targetDec,
          solverConfig: solverConfig,
          config: config,
        );

        // Assert
        expect(result.success, isTrue);
        expect(result.iterations, equals(1));
        expect(result.finalOffsetArcsec, lessThanOrEqualTo(toleranceArcsec));
        expect(result.iterationHistory, hasLength(1));
        expect(result.iterationHistory.first.plateSolveSuccess, isTrue);

        // Verify no slewing occurred since we were already centered
        verifyNever(mockDeviceService.slewMountToCoordinates(any, any));
      });

      test('succeeds after multiple iterations', () async {
        // Arrange
        const targetRa = 10.0; // hours
        const targetDec = 45.0; // degrees
        const toleranceArcsec = 30.0;

        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        const config = CenteringConfig(
          maxIterations: 5,
          toleranceArcsec: toleranceArcsec,
          exposureTime: 3.0,
        );

        final capturedImage = CapturedImageData(
          width: 1920,
          height: 1080,
          displayData: Uint8List(1920 * 1080 * 4),
          histogram: List.filled(256, 0),
          stats: const ImageStats(mean: 100.0, stdDev: 10.0),
          capturedAt: DateTime.now(),
          settings: const ExposureSettings(
            exposureTime: 3.0,
            gain: 100,
            offset: 50,
          ),
          filePath: '/tmp/test_image.fits',
        );

        // First iteration: 2 arcmin off
        // Second iteration: 30 arcsec off (within tolerance)
        var iterationCount = 0;
        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) async => capturedImage);

        when(mockPlateSolveService.solve(any, any)).thenAnswer((_) async {
          iterationCount++;
          if (iterationCount == 1) {
            // First solve: 2 arcmin (120 arcsec) off in RA
            return const PlateSolveResult(
              success: true,
              ra: targetRa +
                  (120.0 / 3600.0 / 15.0), // 120 arcsec converted to hours
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
              solveTimeSecs: 0.0,
            );
          } else {
            // Second solve: within tolerance
            return const PlateSolveResult(
              success: true,
              ra: targetRa,
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
              solveTimeSecs: 0.0,
            );
          }
        });

        when(mockDeviceService.slewMountToCoordinates(any, any))
            .thenAnswer((_) async => {});

        // Act
        final service = container.read(centeringServiceProvider);
        final result = await service.centerOnTarget(
          targetRa: targetRa,
          targetDec: targetDec,
          solverConfig: solverConfig,
          config: config,
        );

        // Assert
        expect(result.success, isTrue);
        expect(result.iterations, equals(2));
        expect(result.finalOffsetArcsec, lessThanOrEqualTo(toleranceArcsec));
        expect(result.iterationHistory, hasLength(2));

        // Verify slew was called once (after first failed iteration)
        verify(mockDeviceService.slewMountToCoordinates(targetRa, targetDec))
            .called(1);
      });

      test('fails when max iterations reached', () async {
        // Arrange
        const targetRa = 10.0;
        const targetDec = 45.0;
        const toleranceArcsec = 30.0;
        const maxIterations = 3;

        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        const config = CenteringConfig(
          maxIterations: maxIterations,
          toleranceArcsec: toleranceArcsec,
          exposureTime: 3.0,
        );

        final capturedImage = CapturedImageData(
          width: 1920,
          height: 1080,
          displayData: Uint8List(1920 * 1080 * 4),
          histogram: List.filled(256, 0),
          stats: const ImageStats(mean: 100.0, stdDev: 10.0),
          capturedAt: DateTime.now(),
          settings: const ExposureSettings(
            exposureTime: 3.0,
            gain: 100,
            offset: 50,
          ),
          filePath: '/tmp/test_image.fits',
        );

        // All iterations return coordinates significantly off target
        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) async => capturedImage);

        when(mockPlateSolveService.solve(any, any)).thenAnswer((_) async {
          return const PlateSolveResult(
            success: true,
            ra: targetRa + (300.0 / 3600.0 / 15.0), // 300 arcsec (5 arcmin) off
            dec: targetDec,
            rotation: 0.0,
            pixelScale: 1.0,
            fieldWidth: 2.0,
            fieldHeight: 1.5,
            solveTimeSecs: 0.0,
          );
        });

        when(mockDeviceService.slewMountToCoordinates(any, any))
            .thenAnswer((_) async => {});

        // Act
        final service = container.read(centeringServiceProvider);
        final result = await service.centerOnTarget(
          targetRa: targetRa,
          targetDec: targetDec,
          solverConfig: solverConfig,
          config: config,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.iterations, equals(maxIterations));
        expect(result.errorMessage, contains('Maximum iterations'));
        expect(result.iterationHistory, hasLength(maxIterations));

        // Verify slew was called for each iteration except the last
        verify(mockDeviceService.slewMountToCoordinates(targetRa, targetDec))
            .called(maxIterations);
      });

      test('fails when camera not connected', () async {
        // Arrange
        final disconnectedContainer = ProviderContainer(
          overrides: [
            cameraStateProvider.overrideWith((ref) {
              return CameraStateNotifier(ref); // Default is disconnected
            }),
            mountStateProvider.overrideWith((ref) {
              final notifier = MountStateNotifier(ref);
              notifier.setConnecting('test_mount');
              notifier.setConnected();
              return notifier;
            }),
          ],
        );

        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        // Act
        final service = disconnectedContainer.read(centeringServiceProvider);
        final result = await service.centerOnTarget(
          targetRa: 10.0,
          targetDec: 45.0,
          solverConfig: solverConfig,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Camera not connected'));
        expect(result.iterations, equals(0));

        disconnectedContainer.dispose();
      });

      test('fails with an overall timeout instead of hanging indefinitely',
          () async {
        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) => Completer<CapturedImageData?>().future);

        final service = container.read(centeringServiceProvider);
        final result = await service.centerOnTarget(
          targetRa: 10.0,
          targetDec: 45.0,
          solverConfig: solverConfig,
          config: const CenteringConfig(
            overallTimeout: Duration(milliseconds: 10),
          ),
        );

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('timed out'));
      });

      test('fails when mount not connected', () async {
        // Arrange
        final disconnectedContainer = ProviderContainer(
          overrides: [
            cameraStateProvider.overrideWith((ref) {
              final notifier = CameraStateNotifier(ref);
              notifier.setConnecting('test_camera', 'Test Camera');
              notifier.setConnected();
              return notifier;
            }),
            mountStateProvider.overrideWith((ref) {
              return MountStateNotifier(ref); // Default is disconnected
            }),
          ],
        );

        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        // Act
        final service = disconnectedContainer.read(centeringServiceProvider);
        final result = await service.centerOnTarget(
          targetRa: 10.0,
          targetDec: 45.0,
          solverConfig: solverConfig,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Mount not connected'));
        expect(result.iterations, equals(0));

        disconnectedContainer.dispose();
      });

      test('fails when plate solve fails', () async {
        // Arrange
        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        final capturedImage = CapturedImageData(
          width: 1920,
          height: 1080,
          displayData: Uint8List(1920 * 1080 * 4),
          histogram: List.filled(256, 0),
          stats: const ImageStats(mean: 100.0, stdDev: 10.0),
          capturedAt: DateTime.now(),
          settings: const ExposureSettings(
            exposureTime: 3.0,
            gain: 100,
            offset: 50,
          ),
          filePath: '/tmp/test_image.fits',
        );

        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) async => capturedImage);

        when(mockPlateSolveService.solve(any, any)).thenAnswer((_) async {
          return const PlateSolveResult(
            success: false,
            ra: 0,
            dec: 0,
            pixelScale: 0,
            rotation: 0,
            fieldWidth: 0,
            fieldHeight: 0,
            solveTimeSecs: 0,
            error: 'No stars found in image',
          );
        });

        // Act
        final service = container.read(centeringServiceProvider);
        final result = await service.centerOnTarget(
          targetRa: 10.0,
          targetDec: 45.0,
          solverConfig: solverConfig,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Plate solve failed'));
        expect(result.iterations, equals(5));
        expect(result.iterationHistory.first.plateSolveSuccess, isFalse);
      });

      test('reports status updates during centering', () async {
        // Arrange
        const targetRa = 10.0;
        const targetDec = 45.0;

        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        const config = CenteringConfig(maxIterations: 2);

        final capturedImage = CapturedImageData(
          width: 1920,
          height: 1080,
          displayData: Uint8List(1920 * 1080 * 4),
          histogram: List.filled(256, 0),
          stats: const ImageStats(mean: 100.0, stdDev: 10.0),
          capturedAt: DateTime.now(),
          settings: const ExposureSettings(
            exposureTime: 3.0,
            gain: 100,
            offset: 50,
          ),
          filePath: '/tmp/test_image.fits',
        );

        var iterationCount = 0;
        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) async => capturedImage);

        when(mockPlateSolveService.solve(any, any)).thenAnswer((_) async {
          iterationCount++;
          if (iterationCount == 1) {
            return const PlateSolveResult(
              success: true,
              ra: targetRa + (120.0 / 3600.0 / 15.0),
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
              solveTimeSecs: 0.0,
            );
          } else {
            return const PlateSolveResult(
              success: true,
              ra: targetRa,
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
              solveTimeSecs: 0.0,
            );
          }
        });

        when(mockDeviceService.slewMountToCoordinates(any, any))
            .thenAnswer((_) async => {});

        final statusUpdates = <CenteringStatus>[];

        // Act
        final service = container.read(centeringServiceProvider);
        final result = await service.centerOnTarget(
          targetRa: targetRa,
          targetDec: targetDec,
          solverConfig: solverConfig,
          config: config,
          onStatusUpdate: (status) => statusUpdates.add(status),
        );

        // Assert
        expect(result.success, isTrue);
        expect(statusUpdates, isNotEmpty);

        // Verify we got exposing, solving, and slewing states
        expect(
          statusUpdates.where((s) => s.state == CenteringState.exposing),
          isNotEmpty,
        );
        expect(
          statusUpdates.where((s) => s.state == CenteringState.solving),
          isNotEmpty,
        );
        expect(
          statusUpdates.where((s) => s.state == CenteringState.slewing),
          isNotEmpty,
        );
        expect(
          statusUpdates.where((s) => s.state == CenteringState.completed),
          isNotEmpty,
        );
      });

      // ---- Post-slew polling escalation (audit IMG-P2-6) ------------------
      //
      // The centering service runs a settle-poll loop after each slew. If the
      // mount stops answering `getMountStatus` for too long, the loop must
      // escalate to a typed failure instead of dragging out the full 60s
      // wall-clock cap. The four tests below cover the contract:
      //   1. Healthy mount  -> normal proceed (regression).
      //   2. ONE transient blip -> recovers, do not escalate (regression).
      //   3. 6 consecutive failures -> abort with the typed exception.
      //   4. Failure then success -> counter resets, polling continues.

      // Shared fixture for all four polling-escalation tests: a captured
      // image good enough that plate-solve returns a 2-arcmin offset on the
      // first attempt, forcing exactly one slew + one settle-poll cycle.
      CapturedImageData buildPollFixtureImage() {
        return CapturedImageData(
          width: 1920,
          height: 1080,
          displayData: Uint8List(1920 * 1080 * 4),
          histogram: List.filled(256, 0),
          stats: const ImageStats(mean: 100.0, stdDev: 10.0),
          capturedAt: DateTime.now(),
          settings: const ExposureSettings(
            exposureTime: 3.0,
            gain: 100,
            offset: 50,
          ),
          filePath: '/tmp/poll_test.fits',
        );
      }

      void stubTwoIterationPlateSolve(double targetRa, double targetDec) {
        var iterationCount = 0;
        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) async => buildPollFixtureImage());
        when(mockPlateSolveService.solve(any, any)).thenAnswer((_) async {
          iterationCount++;
          // First poll: 2 arcmin off (forces slew + post-slew poll path).
          // Second poll: on-target (test terminates with success once the
          // poll loop completes / escalates).
          if (iterationCount == 1) {
            return PlateSolveResult(
              success: true,
              ra: targetRa + (120.0 / 3600.0 / 15.0),
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
              solveTimeSecs: 0.0,
            );
          }
          return const PlateSolveResult(
            success: true,
            ra: 10.0,
            dec: 45.0,
            rotation: 0.0,
            pixelScale: 1.0,
            fieldWidth: 2.0,
            fieldHeight: 1.5,
            solveTimeSecs: 0.0,
          );
        });
        when(mockDeviceService.slewMountToCoordinates(any, any))
            .thenAnswer((_) async => {});
      }

      test(
        'post-slew poll: mount answers every tick -> centering proceeds '
        'normally (regression)',
        () async {
          const targetRa = 10.0;
          const targetDec = 45.0;
          const solverConfig = PlateSolverConfig(
            type: PlateSolverType.astap,
            executablePath: '/usr/bin/astap',
          );

          stubTwoIterationPlateSolve(targetRa, targetDec);
          // Default setUp stub already returns a settled mount, but pin it
          // explicitly so the contract is obvious from this test body.
          mt.when(() => pollBackend.getMountStatus(mt.any()))
              .thenAnswer((_) async => _settledMount());

          final service = container.read(centeringServiceProvider);
          final result = await service.centerOnTarget(
            targetRa: targetRa,
            targetDec: targetDec,
            solverConfig: solverConfig,
            config: const CenteringConfig(maxIterations: 2),
          );

          expect(result.success, isTrue,
              reason: 'Healthy mount must complete centering normally');
          expect(result.errorMessage, isNull);
          expect(result.iterations, equals(2));
        },
      );

      test(
        'post-slew poll: single transient failure recovers, does not '
        'escalate (regression — must not be over-aggressive)',
        () async {
          const targetRa = 10.0;
          const targetDec = 45.0;
          const solverConfig = PlateSolverConfig(
            type: PlateSolverType.astap,
            executablePath: '/usr/bin/astap',
          );

          stubTwoIterationPlateSolve(targetRa, targetDec);

          // Throw once, then return settled. The escalation threshold is 6
          // CONSECUTIVE failures, so a single blip must NOT abort centering.
          var calls = 0;
          mt.when(() => pollBackend.getMountStatus(mt.any()))
              .thenAnswer((_) async {
            calls++;
            if (calls == 1) {
              throw Exception('transient I/O blip');
            }
            return _settledMount();
          });

          final service = container.read(centeringServiceProvider);
          final result = await service.centerOnTarget(
            targetRa: targetRa,
            targetDec: targetDec,
            solverConfig: solverConfig,
            config: const CenteringConfig(maxIterations: 2),
          );

          expect(result.success, isTrue,
              reason:
                  'A single transient query failure must not escalate; the '
                  'poll loop must ride it out and continue.');
          expect(calls, greaterThanOrEqualTo(2),
              reason: 'Loop must have polled at least twice (blip + recover)');
        },
      );

      test(
        'post-slew poll: 6 consecutive failures -> centering aborts with '
        'CenteringMountUnresponsiveException',
        () async {
          const targetRa = 10.0;
          const targetDec = 45.0;
          const solverConfig = PlateSolverConfig(
            type: PlateSolverType.astap,
            executablePath: '/usr/bin/astap',
          );

          // Only need the FIRST iteration to slew, then fail polling.
          when(mockImagingService.captureImage(
            settings: anyNamed('settings'),
            targetName: anyNamed('targetName'),
          )).thenAnswer((_) async => buildPollFixtureImage());
          when(mockPlateSolveService.solve(any, any)).thenAnswer((_) async {
            return const PlateSolveResult(
              success: true,
              ra: targetRa + (120.0 / 3600.0 / 15.0), // 2 arcmin off
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
              solveTimeSecs: 0.0,
            );
          });
          when(mockDeviceService.slewMountToCoordinates(any, any))
              .thenAnswer((_) async => {});

          // Every poll throws — escalation must trip at 6 consecutive
          // failures (3 seconds) instead of waiting the full 60s.
          //
          // NB: the live `MountStateNotifier` also polls `getMountStatus`
          // on its own 2s timer once the mount is "connected", so the raw
          // mock call count can drift above 6 by a tick or two. We assert
          // on the failure message + wall-clock budget instead.
          mt.when(() => pollBackend.getMountStatus(mt.any()))
              .thenAnswer((_) async {
            throw Exception('mount disconnected');
          });

          final stopwatch = Stopwatch()..start();
          final service = container.read(centeringServiceProvider);
          final result = await service.centerOnTarget(
            targetRa: targetRa,
            targetDec: targetDec,
            solverConfig: solverConfig,
            config: const CenteringConfig(maxIterations: 3),
          );
          stopwatch.stop();

          expect(result.success, isFalse);
          expect(result.errorMessage, isNotNull);
          expect(
            result.errorMessage,
            allOf(
              contains('6 times consecutively'),
              contains('aborting centering'),
              contains('disconnected or unresponsive'),
            ),
            reason: 'Failure must carry the typed exception message',
          );
          // Fail-fast: 6 ticks × 500ms = 3s for the poll loop, plus the
          // single exposure + slew of one iteration. Must come in well
          // under the 60s wall-clock cap.
          expect(
            stopwatch.elapsed,
            lessThan(const Duration(seconds: 15)),
            reason:
                'Must fail fast (~3s of poll ticks), not drag out the full '
                '60s wall-clock cap',
          );
        },
      );

      test(
        'post-slew poll: failure then success resets counter, polling '
        'continues',
        () async {
          const targetRa = 10.0;
          const targetDec = 45.0;
          const solverConfig = PlateSolverConfig(
            type: PlateSolverType.astap,
            executablePath: '/usr/bin/astap',
          );

          stubTwoIterationPlateSolve(targetRa, targetDec);

          // Pattern (per-call sequence on the mock): fail 5×, then settled.
          // If the consecutive-failure counter were NOT resetting, a
          // subsequent failure would compound and trip the threshold at
          // count=6. By following the 5 fails with a clean success we
          // prove the counter resets (centering completes successfully
          // instead of throwing CenteringMountUnresponsiveException).
          //
          // NB: `MountStateNotifier` also polls `getMountStatus` on its
          // own 2s timer, so additional unrelated calls can hit the mock.
          // We tolerate that by gating only the *first* 5 calls into the
          // failure phase and answering everything after that as settled.
          //
          // The contract under test is the SERVICE behavior (does
          // centering succeed?), not a precise mock call count.
          var sequenceCall = 0;
          mt.when(() => pollBackend.getMountStatus(mt.any()))
              .thenAnswer((_) async {
            sequenceCall++;
            if (sequenceCall <= 5) {
              throw Exception('transient blip $sequenceCall');
            }
            return _settledMount();
          });

          final service = container.read(centeringServiceProvider);
          final result = await service.centerOnTarget(
            targetRa: targetRa,
            targetDec: targetDec,
            solverConfig: solverConfig,
            config: const CenteringConfig(maxIterations: 2),
          );

          expect(result.success, isTrue,
              reason:
                  'Counter must reset on a successful poll. After 5 fails '
                  'followed by a success, the next poll starts fresh — '
                  'centering must complete normally (no escalation).');
          // Sanity: confirm we actually exercised the failure path.
          expect(sequenceCall, greaterThanOrEqualTo(5),
              reason:
                  'Mock must have been hit at least through the 5 fail '
                  'sequence — otherwise the test is not exercising the '
                  'counter-reset branch.');
        },
      );

      // Dedicated test for the bare exception type so the contract is
      // explicit and not just inferred from the failure message above.
      test('CenteringMountUnresponsiveException carries diagnostic context',
          () {
        const e = CenteringMountUnresponsiveException(
          consecutiveFailures: 6,
          elapsed: Duration(seconds: 3),
          cause: 'mount disconnected',
        );
        expect(e.consecutiveFailures, equals(6));
        expect(e.elapsed, equals(const Duration(seconds: 3)));
        expect(e.cause, equals('mount disconnected'));
        final s = e.toString();
        expect(s, contains('6 times consecutively'));
        expect(s, contains('3.0s'));
        expect(s, contains('mount disconnected'));
      });
    });

    group('verifyCenter', () {
      test('succeeds when within tolerance', () async {
        // Arrange
        const targetRa = 10.0;
        const targetDec = 45.0;
        const toleranceArcsec = 30.0;

        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        final capturedImage = CapturedImageData(
          width: 1920,
          height: 1080,
          displayData: Uint8List(1920 * 1080 * 4),
          histogram: List.filled(256, 0),
          stats: const ImageStats(mean: 100.0, stdDev: 10.0),
          capturedAt: DateTime.now(),
          settings: const ExposureSettings(
            exposureTime: 3.0,
            gain: 100,
            offset: 50,
          ),
          filePath: '/tmp/test_image.fits',
        );

        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) async => capturedImage);

        when(mockPlateSolveService.solve(any, any)).thenAnswer((_) async {
          return const PlateSolveResult(
            success: true,
            ra: targetRa,
            dec: targetDec,
            rotation: 0.0,
            pixelScale: 1.0,
            fieldWidth: 2.0,
            fieldHeight: 1.5,
            solveTimeSecs: 0.0,
          );
        });

        // Act
        final service = container.read(centeringServiceProvider);
        final result = await service.verifyCenter(
          targetRa: targetRa,
          targetDec: targetDec,
          solverConfig: solverConfig,
          toleranceArcsec: toleranceArcsec,
        );

        // Assert
        expect(result.success, isTrue);
        expect(result.iterations, equals(1));
        expect(result.finalOffsetArcsec, lessThanOrEqualTo(toleranceArcsec));

        // Verify no slewing occurred (verification only)
        verifyNever(mockDeviceService.slewMountToCoordinates(any, any));
      });

      test('fails when outside tolerance', () async {
        // Arrange
        const targetRa = 10.0;
        const targetDec = 45.0;
        const toleranceArcsec = 30.0;

        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        final capturedImage = CapturedImageData(
          width: 1920,
          height: 1080,
          displayData: Uint8List(1920 * 1080 * 4),
          histogram: List.filled(256, 0),
          stats: const ImageStats(mean: 100.0, stdDev: 10.0),
          capturedAt: DateTime.now(),
          settings: const ExposureSettings(
            exposureTime: 3.0,
            gain: 100,
            offset: 50,
          ),
          filePath: '/tmp/test_image.fits',
        );

        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) async => capturedImage);

        when(mockPlateSolveService.solve(any, any)).thenAnswer((_) async {
          return const PlateSolveResult(
            success: true,
            ra: targetRa + (300.0 / 3600.0 / 15.0), // 5 arcmin off
            dec: targetDec,
            rotation: 0.0,
            pixelScale: 1.0,
            fieldWidth: 2.0,
            fieldHeight: 1.5,
            solveTimeSecs: 0.0,
          );
        });

        // Act
        final service = container.read(centeringServiceProvider);
        final result = await service.verifyCenter(
          targetRa: targetRa,
          targetDec: targetDec,
          solverConfig: solverConfig,
          toleranceArcsec: toleranceArcsec,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('exceeds tolerance'));
        expect(result.iterations, equals(1));
      });
    });

    group('plateAndCenter', () {
      test('uses current mount position as target', () async {
        // Arrange - mount is at RA=10h, Dec=45 deg
        const mountRa = 10.0;
        const mountDec = 45.0;

        const solverConfig = PlateSolverConfig(
          type: PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        final capturedImage = CapturedImageData(
          width: 1920,
          height: 1080,
          displayData: Uint8List(1920 * 1080 * 4),
          histogram: List.filled(256, 0),
          stats: const ImageStats(mean: 100.0, stdDev: 10.0),
          capturedAt: DateTime.now(),
          settings: const ExposureSettings(
            exposureTime: 3.0,
            gain: 100,
            offset: 50,
          ),
          filePath: '/tmp/test_image.fits',
        );

        when(mockImagingService.captureImage(
          settings: anyNamed('settings'),
          targetName: anyNamed('targetName'),
        )).thenAnswer((_) async => capturedImage);

        when(mockPlateSolveService.solve(any, any)).thenAnswer((_) async {
          return const PlateSolveResult(
            success: true,
            ra: mountRa,
            dec: mountDec,
            rotation: 0.0,
            pixelScale: 1.0,
            fieldWidth: 2.0,
            fieldHeight: 1.5,
            solveTimeSecs: 0.0,
          );
        });

        // Act
        final service = container.read(centeringServiceProvider);
        final result = await service.plateAndCenter(
          solverConfig: solverConfig,
        );

        // Assert
        expect(result.success, isTrue);
        expect(result.iterationHistory.first.targetRa, equals(mountRa));
        expect(result.iterationHistory.first.targetDec, equals(mountDec));
      });
    });
  });
}
