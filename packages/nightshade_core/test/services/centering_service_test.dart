import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nightshade_core/nightshade_core.dart';
// Import plate_solve_service directly to get its PlateSolveResult type
import 'package:nightshade_core/src/services/plate_solve_service.dart' as plate_solve;

import 'centering_service_test.mocks.dart';

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

    setUp(() {
      mockImagingService = MockImagingService();
      mockPlateSolveService = MockPlateSolveService();
      mockDeviceService = MockDeviceService();

      container = ProviderContainer(
        overrides: [
          imagingServiceProvider.overrideWithValue(mockImagingService),
          plateSolveServiceProvider.overrideWithValue(mockPlateSolveService),
          deviceServiceProvider.overrideWithValue(mockDeviceService),
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
            notifier.updatePosition(10.0, 45.0, 30.0, 180.0); // ra, dec, alt, az
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

        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        final config = CenteringConfig(
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
        final solveResult = plate_solve.PlateSolveResult(
          success: true,
          ra: targetRa, // Same as target
          dec: targetDec, // Same as target
          rotation: 0.0,
          pixelScale: 1.0,
          fieldWidth: 2.0,
          fieldHeight: 1.5,
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

        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        final config = CenteringConfig(
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
            return plate_solve.PlateSolveResult(
              success: true,
              ra: targetRa + (120.0 / 3600.0 / 15.0), // 120 arcsec converted to hours
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
            );
          } else {
            // Second solve: within tolerance
            return plate_solve.PlateSolveResult(
              success: true,
              ra: targetRa,
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
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
        verify(mockDeviceService.slewMountToCoordinates(targetRa, targetDec)).called(1);
      });

      test('fails when max iterations reached', () async {
        // Arrange
        const targetRa = 10.0;
        const targetDec = 45.0;
        const toleranceArcsec = 30.0;
        const maxIterations = 3;

        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        final config = CenteringConfig(
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
          return plate_solve.PlateSolveResult(
            success: true,
            ra: targetRa + (300.0 / 3600.0 / 15.0), // 300 arcsec (5 arcmin) off
            dec: targetDec,
            rotation: 0.0,
            pixelScale: 1.0,
            fieldWidth: 2.0,
            fieldHeight: 1.5,
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

        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
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

        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
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
        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
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
          return plate_solve.PlateSolveResult.failed('No stars found in image');
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
        expect(result.iterations, equals(1));
        expect(result.iterationHistory.first.plateSolveSuccess, isFalse);
      });

      test('reports status updates during centering', () async {
        // Arrange
        const targetRa = 10.0;
        const targetDec = 45.0;

        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
          executablePath: '/usr/bin/astap',
        );

        final config = CenteringConfig(maxIterations: 2);

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
            return plate_solve.PlateSolveResult(
              success: true,
              ra: targetRa + (120.0 / 3600.0 / 15.0),
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
            );
          } else {
            return plate_solve.PlateSolveResult(
              success: true,
              ra: targetRa,
              dec: targetDec,
              rotation: 0.0,
              pixelScale: 1.0,
              fieldWidth: 2.0,
              fieldHeight: 1.5,
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
    });

    group('verifyCenter', () {
      test('succeeds when within tolerance', () async {
        // Arrange
        const targetRa = 10.0;
        const targetDec = 45.0;
        const toleranceArcsec = 30.0;

        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
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
          return plate_solve.PlateSolveResult(
            success: true,
            ra: targetRa,
            dec: targetDec,
            rotation: 0.0,
            pixelScale: 1.0,
            fieldWidth: 2.0,
            fieldHeight: 1.5,
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

        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
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
          return plate_solve.PlateSolveResult(
            success: true,
            ra: targetRa + (300.0 / 3600.0 / 15.0), // 5 arcmin off
            dec: targetDec,
            rotation: 0.0,
            pixelScale: 1.0,
            fieldWidth: 2.0,
            fieldHeight: 1.5,
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

        final solverConfig = plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
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
          return plate_solve.PlateSolveResult(
            success: true,
            ra: mountRa,
            dec: mountDec,
            rotation: 0.0,
            pixelScale: 1.0,
            fieldWidth: 2.0,
            fieldHeight: 1.5,
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
