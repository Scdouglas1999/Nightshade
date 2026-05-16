import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../backend/nightshade_backend.dart';
import '../models/sequence/sequence_models.dart';
import '../models/imaging/imaging_models.dart';
import '../providers/backend_provider.dart';
import 'sky_brightness_tracker.dart';
import 'flat_exposure_calculator.dart';

/// Result of a flat frame calibration for a single filter
class FlatResult {
  final String filter;
  final double exposure;
  final double adu;
  final bool success;
  final int iterations;
  final String? errorMessage;

  const FlatResult({
    required this.filter,
    required this.exposure,
    required this.adu,
    required this.success,
    this.iterations = 0,
    this.errorMessage,
  });

  FlatResult copyWith({
    String? filter,
    double? exposure,
    double? adu,
    bool? success,
    int? iterations,
    String? errorMessage,
  }) {
    return FlatResult(
      filter: filter ?? this.filter,
      exposure: exposure ?? this.exposure,
      adu: adu ?? this.adu,
      success: success ?? this.success,
      iterations: iterations ?? this.iterations,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Service for flat frame calibration and sequence generation
class FlatWizardService {
  final NightshadeBackend backend;
  static const _imageDownloadTimeout = Duration(seconds: 60);

  FlatWizardService(this.backend);

  /// Calculate next exposure time to reach target ADU using proportional adjustment
  ///
  /// Uses a conservative approach with safety limits to avoid overshooting:
  /// - Limits adjustment ratio to prevent extreme jumps
  /// - Applies minimum/maximum exposure bounds
  /// - Uses logarithmic damping for large adjustments
  double calculateNextExposure({
    required double currentExposure,
    required double currentAdu,
    required double targetAdu,
    required double minExposure,
    required double maxExposure,
  }) {
    // Avoid division by zero
    if (currentAdu <= 0) {
      return (minExposure + maxExposure) / 2;
    }

    // Calculate raw ratio
    final ratio = targetAdu / currentAdu;

    // Apply safety limits to prevent extreme jumps
    // Allow max 3x increase or 1/3x decrease per iteration
    final clampedRatio = ratio.clamp(0.33, 3.0);

    // For large adjustments, use logarithmic damping
    final adjustedRatio = clampedRatio > 2.0 || clampedRatio < 0.5
        ? 1.0 + (clampedRatio - 1.0) * 0.7 // Reduce aggressive changes
        : clampedRatio;

    // Calculate next exposure
    final nextExposure = currentExposure * adjustedRatio;

    // Clamp to valid range
    return nextExposure.clamp(minExposure, maxExposure);
  }

  /// Capture a single test frame and return statistics
  ///
  /// Returns the mean ADU value from the captured frame.
  /// Waits for the actual ExposureComplete event rather than using a fixed delay.
  Future<double?> captureTestFrame({
    required String deviceId,
    required double exposureTime,
    String? filterName,
    int? filterPosition,
    String? filterWheelDeviceId,
    int binX = 1,
    int binY = 1,
  }) async {
    try {
      // Change filter if specified and a filter wheel device ID is available
      if (filterWheelDeviceId != null) {
        if (filterName != null) {
          await backend.filterWheelSetByName(filterWheelDeviceId, filterName);
        } else if (filterPosition != null) {
          await backend.filterWheelSetPosition(
              filterWheelDeviceId, filterPosition);
        }
      }

      // Set up listener for exposure completion BEFORE starting the exposure
      // to avoid a race condition where the event fires before we subscribe
      final exposureCompleter = Completer<bool>();
      final subscription = backend.eventStream.listen((event) {
        if (event.category == EventCategory.imaging &&
            event.eventType == 'ExposureComplete') {
          if (!exposureCompleter.isCompleted) {
            exposureCompleter.complete(true);
          }
        }
      });

      // Start exposure
      await backend.cameraStartExposure(
        deviceId: deviceId,
        exposureTime: exposureTime,
        frameType: FrameType.flat,
        gain: 0,
        offset: 0,
        binX: binX,
        binY: binY,
      );

      // Wait for exposure completion event with a generous timeout
      // Timeout: exposure time + 30s for readout/download overhead
      try {
        await exposureCompleter.future.timeout(
          Duration(milliseconds: (exposureTime * 1000).toInt() + 30000),
        );
      } on TimeoutException {
        developer.log(
            'FlatWizardService: Exposure timed out after ${exposureTime + 30}s',
            name: 'FlatWizardService',
            level: 900);
        return null;
      } finally {
        await subscription.cancel();
      }

      // Retrieve captured image
      final image = await backend.cameraGetLastImage(deviceId).timeout(
        _imageDownloadTimeout,
        onTimeout: () {
          developer.log(
            'FlatWizardService: Image retrieval timed out after '
            '${_imageDownloadTimeout.inSeconds}s',
            name: 'FlatWizardService',
            level: 900,
          );
          return null;
        },
      );
      if (image == null) {
        developer.log('FlatWizardService: Failed to retrieve test frame',
            name: 'FlatWizardService', level: 900);
        return null;
      }

      // Return mean ADU
      return image.stats.mean;
    } catch (e) {
      developer.log('FlatWizardService: Error capturing test frame: $e',
          name: 'FlatWizardService', level: 1000, error: e);
      return null;
    }
  }

  /// Run iterative calibration to find optimal exposure for target ADU
  ///
  /// Uses binary search-like algorithm with adaptive step sizing:
  /// 1. Start with initial exposure estimate
  /// 2. Capture test frame and measure ADU
  /// 3. Calculate next exposure using proportional adjustment
  /// 4. Repeat until within tolerance or max iterations reached
  ///
  /// Returns [FlatResult] with optimal exposure and final ADU
  Future<FlatResult> calibrateFilter({
    required String deviceId,
    required String filter,
    required double targetAdu,
    required double tolerance,
    required double minExposure,
    required double maxExposure,
    int maxIterations = 10,
    int binX = 1,
    int binY = 1,
    void Function(int iteration, double exposure, double adu)? onProgress,
  }) async {
    // Start with midpoint exposure
    double exposure = math.sqrt(minExposure * maxExposure);
    double? lastAdu;
    int iteration = 0;

    developer.log(
      'FlatWizardService: Starting calibration for filter "$filter"\n'
      '  Target ADU: ${targetAdu.toStringAsFixed(0)}\n'
      '  Tolerance: ±${tolerance.toStringAsFixed(1)}%\n'
      '  Exposure range: ${minExposure.toStringAsFixed(3)}s - ${maxExposure.toStringAsFixed(3)}s',
      name: 'FlatWizardService',
      level: 800,
    );

    for (iteration = 1; iteration <= maxIterations; iteration++) {
      developer.log(
        'FlatWizardService: Iteration $iteration/$maxIterations - '
        'Testing exposure: ${exposure.toStringAsFixed(3)}s',
        name: 'FlatWizardService',
        level: 800,
      );

      // Capture test frame
      final adu = await captureTestFrame(
        deviceId: deviceId,
        exposureTime: exposure,
        filterName: filter,
        binX: binX,
        binY: binY,
      );

      if (adu == null) {
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          iterations: iteration,
          errorMessage: 'Failed to capture test frame',
        );
      }

      lastAdu = adu;
      developer.log('FlatWizardService: Measured ADU: ${adu.toStringAsFixed(0)}',
          name: 'FlatWizardService', level: 800);

      // Notify progress callback
      onProgress?.call(iteration, exposure, adu);

      // Check if within tolerance
      final error = ((adu - targetAdu).abs() / targetAdu) * 100;
      if (error <= tolerance) {
        developer.log(
          'FlatWizardService: SUCCESS! Found optimal exposure: '
          '${exposure.toStringAsFixed(3)}s (ADU: ${adu.toStringAsFixed(0)}, '
          'error: ${error.toStringAsFixed(2)}%)',
          name: 'FlatWizardService',
          level: 800,
        );
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: true,
          iterations: iteration,
        );
      }

      // Calculate next exposure
      final nextExposure = calculateNextExposure(
        currentExposure: exposure,
        currentAdu: adu,
        targetAdu: targetAdu,
        minExposure: minExposure,
        maxExposure: maxExposure,
      );

      // Check for convergence (exposure not changing significantly)
      if ((nextExposure - exposure).abs() < 0.001) {
        developer.log(
          'FlatWizardService: Converged at exposure: ${exposure.toStringAsFixed(3)}s '
          '(ADU: ${adu.toStringAsFixed(0)})',
          name: 'FlatWizardService',
          level: 800,
        );
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: error <= tolerance * 2, // Accept if within 2x tolerance
          iterations: iteration,
        );
      }

      exposure = nextExposure;
    }

    // Max iterations reached
    developer.log(
      'FlatWizardService: Max iterations reached. Best result: '
      '${exposure.toStringAsFixed(3)}s (ADU: ${lastAdu?.toStringAsFixed(0) ?? "N/A"})',
      name: 'FlatWizardService',
      level: 900,
    );
    return FlatResult(
      filter: filter,
      exposure: exposure,
      adu: lastAdu ?? 0,
      success: false,
      iterations: maxIterations,
      errorMessage: 'Max iterations reached without convergence',
    );
  }

  /// Calibrate filter with rate tracking for sky flats
  ///
  /// Uses predictive exposure calculation based on sky brightness rate
  Future<FlatResult> calibrateFilterWithRateTracking({
    required String deviceId,
    required String filter,
    required double targetAdu,
    required double tolerance,
    required double minExposure,
    required double maxExposure,
    required SkyBrightnessTracker brightnessTracker,
    double? historicalExposure,
    int maxIterations = 3, // Fewer iterations for sky flats (speed matters)
    int binX = 1,
    int binY = 1,
    void Function(int iteration, double exposure, double adu, String status)?
        onProgress,
  }) async {
    // Get starting exposure
    double exposure = FlatExposureCalculator.getStartingExposure(
      historicalExposure: historicalExposure,
      minExposure: minExposure,
      maxExposure: maxExposure,
      currentSkyAduRate: brightnessTracker.calculateRate(),
    );

    double? lastAdu;
    int iteration = 0;

    for (iteration = 1; iteration <= maxIterations; iteration++) {
      onProgress?.call(iteration, exposure, lastAdu ?? 0, 'Testing exposure');

      // Capture test frame
      final adu = await captureTestFrame(
        deviceId: deviceId,
        exposureTime: exposure,
        filterName: filter,
        binX: binX,
        binY: binY,
      );

      if (adu == null) {
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          iterations: iteration,
          errorMessage: 'Failed to capture test frame',
        );
      }

      lastAdu = adu;

      // Update brightness tracker
      brightnessTracker.addSample(
        adu: adu,
        exposureTime: exposure,
        timestamp: DateTime.now(),
      );

      // Check if within tolerance
      final toleranceAdu = targetAdu * tolerance / 100.0;
      if ((adu - targetAdu).abs() <= toleranceAdu) {
        onProgress?.call(iteration, exposure, adu, 'On target');
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: true,
          iterations: iteration,
        );
      }

      // Calculate next exposure using rate-aware prediction
      final predictedExposure = brightnessTracker.calculateOptimalExposure(
        targetAdu: targetAdu,
        minExposure: minExposure,
        maxExposure: maxExposure,
      );

      if (predictedExposure != null) {
        exposure = predictedExposure;
      } else {
        // Fall back to capped proportional adjustment
        exposure = FlatExposureCalculator.calculateNextExposure(
          currentExposure: exposure,
          currentAdu: adu,
          targetAdu: targetAdu,
          minExposure: minExposure,
          maxExposure: maxExposure,
        );
      }

      // Check limits
      final limitStatus = FlatExposureCalculator.checkLimits(
        exposure: exposure,
        measuredAdu: adu,
        targetAdu: targetAdu,
        minExposure: minExposure,
        maxExposure: maxExposure,
        tolerancePercent: tolerance,
      );

      if (limitStatus == ExposureLimitStatus.maxExposureReached) {
        onProgress?.call(iteration, exposure, adu, 'Max exposure reached');
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: false,
          iterations: iteration,
          errorMessage: 'Max exposure reached but still under target',
        );
      }

      if (limitStatus == ExposureLimitStatus.minExposureReached) {
        onProgress?.call(iteration, exposure, adu, 'Min exposure reached');
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: false,
          iterations: iteration,
          errorMessage: 'Min exposure reached but still over target',
        );
      }
    }

    // Return best effort
    return FlatResult(
      filter: filter,
      exposure: exposure,
      adu: lastAdu ?? 0,
      success: false,
      iterations: maxIterations,
      errorMessage: 'Did not converge within $maxIterations iterations',
    );
  }

  /// Calibrate multiple filters in sequence
  ///
  /// Runs calibration for each filter and returns list of results
  Future<List<FlatResult>> calibrateMultipleFilters({
    required String deviceId,
    required List<String> filters,
    required double targetAdu,
    required double tolerance,
    required double minExposure,
    required double maxExposure,
    int maxIterations = 10,
    int binX = 1,
    int binY = 1,
    void Function(String filter, int iteration, double exposure, double adu)?
        onProgress,
    void Function(String filter, FlatResult result)? onFilterComplete,
  }) async {
    final results = <FlatResult>[];

    for (final filter in filters) {
      developer.log(
          'FlatWizardService: Starting calibration for filter: $filter',
          name: 'FlatWizardService',
          level: 800);

      final result = await calibrateFilter(
        deviceId: deviceId,
        filter: filter,
        targetAdu: targetAdu,
        tolerance: tolerance,
        minExposure: minExposure,
        maxExposure: maxExposure,
        maxIterations: maxIterations,
        binX: binX,
        binY: binY,
        onProgress: (iteration, exposure, adu) {
          onProgress?.call(filter, iteration, exposure, adu);
        },
      );

      results.add(result);
      onFilterComplete?.call(filter, result);

      if (!result.success) {
        developer.log(
          'FlatWizardService: Warning - Calibration failed for filter: $filter',
          name: 'FlatWizardService',
          level: 900,
        );
      }
    }

    return results;
  }

  /// Generate sequence nodes from flat calibration results
  ///
  /// Creates ExposureNode for each successful calibration with specified frame count
  /// Nodes are created as independent flat capture sequences
  List<SequenceNode> generateFlatSequence({
    required List<FlatResult> calibrations,
    required int framesPerFilter,
    int binX = 1,
    int binY = 1,
    int? gain,
    int? offset,
    bool onlySuccessful = true,
  }) {
    final nodes = <SequenceNode>[];
    int orderIndex = 0;

    for (final cal in calibrations) {
      // Skip failed calibrations if requested
      if (onlySuccessful && !cal.success) {
        developer.log(
          'FlatWizardService: Skipping failed calibration for filter: ${cal.filter}',
          name: 'FlatWizardService',
          level: 800,
        );
        continue;
      }

      // Create exposure node for this filter
      final node = ExposureNode(
        id: const Uuid().v4(),
        name: 'Flat ${cal.filter}',
        durationSecs: cal.exposure,
        count: framesPerFilter,
        filter: cal.filter,
        gain: gain,
        offset: offset,
        binning: _binningFromInts(binX, binY),
        frameType: FrameType.flat,
        orderIndex: orderIndex++,
        isEnabled: true,
      );

      nodes.add(node);
      developer.log(
        'FlatWizardService: Generated sequence node - '
        'Filter: ${cal.filter}, Exposure: ${cal.exposure.toStringAsFixed(3)}s, '
        'Count: $framesPerFilter',
        name: 'FlatWizardService',
        level: 800,
      );
    }

    return nodes;
  }

  /// Generate a complete flat sequence with optional sequence wrapper
  ///
  /// Creates InstructionSetNode containing all flat exposure nodes
  /// Returns a complete Sequence ready to be saved or executed
  Sequence generateCompleteSequence({
    required List<FlatResult> calibrations,
    required int framesPerFilter,
    String sequenceName = 'Flat Frame Sequence',
    String? description,
    int binX = 1,
    int binY = 1,
    int? gain,
    int? offset,
    bool onlySuccessful = true,
  }) {
    // Generate flat capture nodes
    final captureNodes = generateFlatSequence(
      calibrations: calibrations,
      framesPerFilter: framesPerFilter,
      binX: binX,
      binY: binY,
      gain: gain,
      offset: offset,
      onlySuccessful: onlySuccessful,
    );

    // Create root instruction set node
    final rootId = const Uuid().v4();
    final rootNode = InstructionSetNode(
      id: rootId,
      name: 'Flat Frames',
      childIds: captureNodes.map((n) => n.id).toList(),
      orderIndex: 0,
      isEnabled: true,
    );

    // Update child nodes with parent reference
    final updatedNodes = <String, SequenceNode>{rootId: rootNode};
    for (int i = 0; i < captureNodes.length; i++) {
      final child = captureNodes[i];
      updatedNodes[child.id] = child.copyWith(
        parentId: rootId,
        orderIndex: i,
      );
    }

    // Build description
    final desc = description ??
        'Flat frame sequence generated from wizard\n'
            'Filters: ${calibrations.where((c) => !onlySuccessful || c.success).map((c) => c.filter).join(", ")}\n'
            'Frames per filter: $framesPerFilter\n'
            'Generated: ${DateTime.now().toIso8601String()}';

    return Sequence(
      id: const Uuid().v4(),
      name: sequenceName,
      description: desc,
      nodes: updatedNodes,
      rootNodeId: rootId,
      isTemplate: false,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
  }

  /// Quick calibration with intelligent defaults
  ///
  /// Simplified calibration that uses standard settings for most scenarios
  Future<FlatResult> quickCalibrate({
    required String deviceId,
    required String filter,
    double targetAdu = 30000,
    double tolerancePercent = 10.0,
    int binX = 1,
    int binY = 1,
  }) async {
    return calibrateFilter(
      deviceId: deviceId,
      filter: filter,
      targetAdu: targetAdu,
      tolerance: tolerancePercent,
      minExposure: 0.001, // 1ms minimum
      maxExposure: 30.0, // 30s maximum
      maxIterations: 8,
      binX: binX,
      binY: binY,
    );
  }
}

/// Helper function to convert bin values to BinningMode
BinningMode _binningFromInts(int x, int y) {
  if (x == 1 && y == 1) return BinningMode.one;
  if (x == 2 && y == 2) return BinningMode.two;
  if (x == 3 && y == 3) return BinningMode.three;
  if (x == 4 && y == 4) return BinningMode.four;
  return BinningMode.one;
}

/// Provider for FlatWizardService
final flatWizardServiceProvider = Provider<FlatWizardService>((ref) {
  final backend = ref.watch(backendProvider.select((b) => b));
  return FlatWizardService(backend);
});
