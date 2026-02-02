import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'plate_solve_service.dart';
import 'imaging_service.dart';
import 'device_service.dart';
import 'smart_notification_service.dart';
import '../providers/equipment_provider.dart';
import '../providers/current_screen_provider.dart';
import '../models/imaging/imaging_models.dart';
import '../models/equipment/equipment_models.dart';

/// Result of a centering operation
class CenteringResult {
  final bool success;
  final double? finalOffsetArcsec;
  final int iterations;
  final String? errorMessage;
  final List<CenteringIteration> iterationHistory;

  const CenteringResult({
    required this.success,
    this.finalOffsetArcsec,
    required this.iterations,
    this.errorMessage,
    required this.iterationHistory,
  });

  factory CenteringResult.success({
    required double finalOffsetArcsec,
    required int iterations,
    required List<CenteringIteration> iterationHistory,
  }) {
    return CenteringResult(
      success: true,
      finalOffsetArcsec: finalOffsetArcsec,
      iterations: iterations,
      errorMessage: null,
      iterationHistory: iterationHistory,
    );
  }

  factory CenteringResult.failure({
    required String errorMessage,
    required int iterations,
    required List<CenteringIteration> iterationHistory,
  }) {
    return CenteringResult(
      success: false,
      finalOffsetArcsec: null,
      iterations: iterations,
      errorMessage: errorMessage,
      iterationHistory: iterationHistory,
    );
  }
}

/// Single iteration of the centering process
class CenteringIteration {
  final int iterationNumber;
  final double? solvedRa;
  final double? solvedDec;
  final double? targetRa;
  final double? targetDec;
  final double? offsetArcsec;
  final double? offsetArcmin;
  final bool plateSolveSuccess;
  final String? errorMessage;
  final DateTime timestamp;

  const CenteringIteration({
    required this.iterationNumber,
    this.solvedRa,
    this.solvedDec,
    this.targetRa,
    this.targetDec,
    this.offsetArcsec,
    this.offsetArcmin,
    required this.plateSolveSuccess,
    this.errorMessage,
    required this.timestamp,
  });
}

/// Configuration for centering operation
class CenteringConfig {
  /// Maximum number of centering iterations
  final int maxIterations;

  /// Tolerance in arcseconds - centering succeeds if offset is below this
  final double toleranceArcsec;

  /// Exposure time for centering images in seconds
  final double exposureTime;

  /// Binning to use for centering images
  final int binning;

  /// Gain to use for centering images
  final int gain;

  /// Whether to sync mount after successful plate solve
  final bool syncMount;

  const CenteringConfig({
    this.maxIterations = 5,
    this.toleranceArcsec = 30.0,
    this.exposureTime = 3.0,
    this.binning = 2,
    this.gain = 100,
    this.syncMount = false,
  });
}

/// Current state of centering operation
enum CenteringState {
  idle,
  exposing,
  solving,
  slewing,
  verifying,
  completed,
  error,
}

/// Status information during centering
class CenteringStatus {
  final CenteringState state;
  final int currentIteration;
  final int maxIterations;
  final double? currentOffsetArcsec;
  final double? currentOffsetArcmin;
  final String? message;
  final List<CenteringIteration> iterationHistory;

  const CenteringStatus({
    required this.state,
    required this.currentIteration,
    required this.maxIterations,
    this.currentOffsetArcsec,
    this.currentOffsetArcmin,
    this.message,
    required this.iterationHistory,
  });

  CenteringStatus copyWith({
    CenteringState? state,
    int? currentIteration,
    int? maxIterations,
    double? currentOffsetArcsec,
    double? currentOffsetArcmin,
    String? message,
    List<CenteringIteration>? iterationHistory,
  }) {
    return CenteringStatus(
      state: state ?? this.state,
      currentIteration: currentIteration ?? this.currentIteration,
      maxIterations: maxIterations ?? this.maxIterations,
      currentOffsetArcsec: currentOffsetArcsec ?? this.currentOffsetArcsec,
      currentOffsetArcmin: currentOffsetArcmin ?? this.currentOffsetArcmin,
      message: message ?? this.message,
      iterationHistory: iterationHistory ?? this.iterationHistory,
    );
  }

  factory CenteringStatus.idle() {
    return const CenteringStatus(
      state: CenteringState.idle,
      currentIteration: 0,
      maxIterations: 0,
      iterationHistory: [],
    );
  }
}

/// Service for automated target centering using plate solving
class CenteringService {
  final Ref _ref;

  CenteringService(this._ref);

  /// Center on target coordinates with iterative plate solve and slew
  ///
  /// Returns a [CenteringResult] with success status and iteration history
  Future<CenteringResult> centerOnTarget({
    required double targetRa,
    required double targetDec,
    required PlateSolverConfig solverConfig,
    CenteringConfig config = const CenteringConfig(),
    void Function(CenteringStatus)? onStatusUpdate,
  }) async {
    final iterations = <CenteringIteration>[];
    final mountState = _ref.read(mountStateProvider);
    final cameraState = _ref.read(cameraStateProvider);

    // Validate mount and camera are connected
    if (mountState.connectionState != DeviceConnectionState.connected) {
      return CenteringResult.failure(
        errorMessage: 'Mount not connected',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    if (cameraState.connectionState != DeviceConnectionState.connected) {
      return CenteringResult.failure(
        errorMessage: 'Camera not connected',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    final imagingService = _ref.read(imagingServiceProvider);
    final plateSolveService = _ref.read(plateSolveServiceProvider);
    final deviceService = _ref.read(deviceServiceProvider);

    for (int iteration = 1; iteration <= config.maxIterations; iteration++) {
      // Update status
      onStatusUpdate?.call(CenteringStatus(
        state: CenteringState.exposing,
        currentIteration: iteration,
        maxIterations: config.maxIterations,
        message: 'Taking centering image (iteration $iteration/${config.maxIterations})...',
        iterationHistory: iterations,
      ));

      // Step 1: Take short exposure
      final exposureSettings = ExposureSettings(
        exposureTime: config.exposureTime,
        gain: config.gain,
        offset: 50,
        binningX: config.binning,
        binningY: config.binning,
        frameType: FrameType.light,
      );

      CapturedImageData? capturedImage;
      try {
        capturedImage = await imagingService.captureImage(
          settings: exposureSettings,
          targetName: 'Centering',
        );
      } catch (e) {
        final iter = CenteringIteration(
          iterationNumber: iteration,
          plateSolveSuccess: false,
          errorMessage: 'Image capture failed: $e',
          timestamp: DateTime.now(),
        );
        iterations.add(iter);

        return CenteringResult.failure(
          errorMessage: 'Failed to capture image: $e',
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      if (capturedImage == null) {
        final iter = CenteringIteration(
          iterationNumber: iteration,
          plateSolveSuccess: false,
          errorMessage: 'Image capture was cancelled',
          timestamp: DateTime.now(),
        );
        iterations.add(iter);

        return CenteringResult.failure(
          errorMessage: 'Image capture cancelled',
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      // Step 2: Plate solve the image
      onStatusUpdate?.call(CenteringStatus(
        state: CenteringState.solving,
        currentIteration: iteration,
        maxIterations: config.maxIterations,
        message: 'Plate solving image...',
        iterationHistory: iterations,
      ));

      PlateSolveResult? solveResult;
      if (capturedImage.filePath != null) {
        solveResult = await plateSolveService.solve(
          capturedImage.filePath!,
          solverConfig,
        );
      } else {
        final iter = CenteringIteration(
          iterationNumber: iteration,
          plateSolveSuccess: false,
          errorMessage: 'No image file path available',
          timestamp: DateTime.now(),
        );
        iterations.add(iter);

        return CenteringResult.failure(
          errorMessage: 'Image file not saved',
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      if (!solveResult.success || solveResult.ra == null || solveResult.dec == null) {
        final iter = CenteringIteration(
          iterationNumber: iteration,
          plateSolveSuccess: false,
          errorMessage: solveResult.errorMessage ?? 'Plate solve failed',
          timestamp: DateTime.now(),
        );
        iterations.add(iter);

        return CenteringResult.failure(
          errorMessage: 'Plate solve failed: ${solveResult.errorMessage}',
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      // Step 3: Calculate offset from target
      final solvedRa = solveResult.ra!;
      final solvedDec = solveResult.dec!;
      final offset = _calculateOffset(
        targetRa,
        targetDec,
        solvedRa,
        solvedDec,
      );

      final iter = CenteringIteration(
        iterationNumber: iteration,
        solvedRa: solvedRa,
        solvedDec: solvedDec,
        targetRa: targetRa,
        targetDec: targetDec,
        offsetArcsec: offset,
        offsetArcmin: offset / 60.0,
        plateSolveSuccess: true,
        timestamp: DateTime.now(),
      );
      iterations.add(iter);

      onStatusUpdate?.call(CenteringStatus(
        state: CenteringState.verifying,
        currentIteration: iteration,
        maxIterations: config.maxIterations,
        currentOffsetArcsec: offset,
        currentOffsetArcmin: offset / 60.0,
        message: 'Offset: ${(offset / 60.0).toStringAsFixed(2)} arcmin',
        iterationHistory: iterations,
      ));

      // Step 4: Check if within tolerance
      if (offset <= config.toleranceArcsec) {
        onStatusUpdate?.call(CenteringStatus(
          state: CenteringState.completed,
          currentIteration: iteration,
          maxIterations: config.maxIterations,
          currentOffsetArcsec: offset,
          currentOffsetArcmin: offset / 60.0,
          message: 'Target centered successfully!',
          iterationHistory: iterations,
        ));

        // Smart notification for centering completion
        final offsetArcmin = offset / 60.0;
        _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
          message: 'Target centered (offset: ${offsetArcmin.toStringAsFixed(2)} arcmin)',
          relevantScreens: [AppScreen.imaging, AppScreen.sequencer],
          title: 'Centering Complete',
        );

        return CenteringResult.success(
          finalOffsetArcsec: offset,
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      // Step 5: Slew to correct position
      onStatusUpdate?.call(CenteringStatus(
        state: CenteringState.slewing,
        currentIteration: iteration,
        maxIterations: config.maxIterations,
        currentOffsetArcsec: offset,
        currentOffsetArcmin: offset / 60.0,
        message: 'Slewing to target...',
        iterationHistory: iterations,
      ));

      try {
        if (config.syncMount) {
          // Sync mount to solved coordinates, then slew to target
          await deviceService.syncMountToCoordinates(solvedRa, solvedDec);
          await deviceService.slewMountToCoordinates(targetRa, targetDec);
        } else {
          // Just slew to target coordinates
          await deviceService.slewMountToCoordinates(targetRa, targetDec);
        }
      } catch (e) {
        return CenteringResult.failure(
          errorMessage: 'Mount slew failed: $e',
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      // Add a small delay before next iteration
      await Future.delayed(const Duration(seconds: 2));
    }

    // Max iterations reached without achieving tolerance
    final lastOffset = iterations.isNotEmpty ? iterations.last.offsetArcsec : null;
    return CenteringResult.failure(
      errorMessage: 'Maximum iterations (${config.maxIterations}) reached. Final offset: ${lastOffset != null ? (lastOffset / 60.0).toStringAsFixed(2) : 'unknown'} arcmin',
      iterations: config.maxIterations,
      iterationHistory: iterations,
    );
  }

  /// Quick center using current mount position
  /// Takes an image, plate solves it, and slews to center the solved position
  Future<CenteringResult> plateAndCenter({
    required PlateSolverConfig solverConfig,
    CenteringConfig config = const CenteringConfig(),
    void Function(CenteringStatus)? onStatusUpdate,
  }) async {
    final mountState = _ref.read(mountStateProvider);

    // Get current mount position as target
    if (mountState.ra == null || mountState.dec == null) {
      return CenteringResult.failure(
        errorMessage: 'Mount position not available',
        iterations: 0,
        iterationHistory: [],
      );
    }

    return centerOnTarget(
      targetRa: mountState.ra!,
      targetDec: mountState.dec!,
      solverConfig: solverConfig,
      config: config,
      onStatusUpdate: onStatusUpdate,
    );
  }

  /// Verify that the current position is centered on target
  /// Takes an image, plate solves it, and returns the offset
  Future<CenteringResult> verifyCenter({
    required double targetRa,
    required double targetDec,
    required PlateSolverConfig solverConfig,
    double toleranceArcsec = 30.0,
    double exposureTime = 3.0,
    int binning = 2,
  }) async {
    final iterations = <CenteringIteration>[];
    final cameraState = _ref.read(cameraStateProvider);

    if (cameraState.connectionState != DeviceConnectionState.connected) {
      return CenteringResult.failure(
        errorMessage: 'Camera not connected',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    final imagingService = _ref.read(imagingServiceProvider);
    final plateSolveService = _ref.read(plateSolveServiceProvider);

    // Take an image
    final exposureSettings = ExposureSettings(
      exposureTime: exposureTime,
      gain: 100,
      offset: 50,
      binningX: binning,
      binningY: binning,
      frameType: FrameType.light,
    );

    CapturedImageData? capturedImage;
    try {
      capturedImage = await imagingService.captureImage(
        settings: exposureSettings,
        targetName: 'Verification',
      );
    } catch (e) {
      return CenteringResult.failure(
        errorMessage: 'Failed to capture image: $e',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    if (capturedImage == null || capturedImage.filePath == null) {
      return CenteringResult.failure(
        errorMessage: 'Image capture failed or cancelled',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    // Plate solve
    final solveResult = await plateSolveService.solve(
      capturedImage.filePath!,
      solverConfig,
    );

    if (!solveResult.success || solveResult.ra == null || solveResult.dec == null) {
      final iter = CenteringIteration(
        iterationNumber: 1,
        plateSolveSuccess: false,
        errorMessage: solveResult.errorMessage ?? 'Plate solve failed',
        timestamp: DateTime.now(),
      );
      iterations.add(iter);

      return CenteringResult.failure(
        errorMessage: 'Plate solve failed: ${solveResult.errorMessage}',
        iterations: 1,
        iterationHistory: iterations,
      );
    }

    // Calculate offset
    final offset = _calculateOffset(
      targetRa,
      targetDec,
      solveResult.ra!,
      solveResult.dec!,
    );

    final iter = CenteringIteration(
      iterationNumber: 1,
      solvedRa: solveResult.ra,
      solvedDec: solveResult.dec,
      targetRa: targetRa,
      targetDec: targetDec,
      offsetArcsec: offset,
      offsetArcmin: offset / 60.0,
      plateSolveSuccess: true,
      timestamp: DateTime.now(),
    );
    iterations.add(iter);

    if (offset <= toleranceArcsec) {
      return CenteringResult.success(
        finalOffsetArcsec: offset,
        iterations: 1,
        iterationHistory: iterations,
      );
    } else {
      return CenteringResult.failure(
        errorMessage: 'Offset ${(offset / 60.0).toStringAsFixed(2)} arcmin exceeds tolerance ${(toleranceArcsec / 60.0).toStringAsFixed(2)} arcmin',
        iterations: 1,
        iterationHistory: iterations,
      );
    }
  }

  /// Calculate angular separation between two celestial coordinates in arcseconds
  /// Uses the haversine formula for great circle distance
  double _calculateOffset(
    double targetRa,
    double targetDec,
    double solvedRa,
    double solvedDec,
  ) {
    // Convert RA from hours to radians (RA is in hours)
    final ra1 = targetRa * 15.0 * math.pi / 180.0; // hours to degrees to radians
    final ra2 = solvedRa * 15.0 * math.pi / 180.0;

    // Convert Dec from degrees to radians
    final dec1 = targetDec * math.pi / 180.0;
    final dec2 = solvedDec * math.pi / 180.0;

    // Haversine formula for great circle distance
    final deltaRa = ra2 - ra1;
    final deltaDec = dec2 - dec1;

    final a = math.pow(math.sin(deltaDec / 2), 2) +
        math.cos(dec1) * math.cos(dec2) * math.pow(math.sin(deltaRa / 2), 2);
    final c = 2 * math.asin(math.sqrt(a));

    // Convert radians to arcseconds
    final offsetRadians = c;
    final offsetDegrees = offsetRadians * 180.0 / math.pi;
    final offsetArcsec = offsetDegrees * 3600.0;

    return offsetArcsec;
  }
}

/// Provider for the centering service
final centeringServiceProvider = Provider<CenteringService>((ref) {
  return CenteringService(ref);
});

/// Provider for centering status
final centeringStatusProvider = StateProvider<CenteringStatus>((ref) {
  return CenteringStatus.idle();
});

/// Provider for last centering result
final lastCenteringResultProvider = StateProvider<CenteringResult?>((ref) => null);
