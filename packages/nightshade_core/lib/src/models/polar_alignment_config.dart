import 'dart:typed_data';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'polar_alignment_config.freezed.dart';
part 'polar_alignment_config.g.dart';

/// Phase of the polar alignment process
enum PolarAlignPhase {
  /// Not running - waiting to start
  idle,

  /// Capturing and solving images to measure error
  measuring,

  /// Adjustment mode - showing live error updates
  adjusting,

  /// Successfully completed
  complete,

  /// Error occurred during alignment
  error,
}

/// Extension for PolarAlignPhase display
extension PolarAlignPhaseExtension on PolarAlignPhase {
  String get displayName {
    switch (this) {
      case PolarAlignPhase.idle:
        return 'Ready';
      case PolarAlignPhase.measuring:
        return 'Measuring';
      case PolarAlignPhase.adjusting:
        return 'Adjusting';
      case PolarAlignPhase.complete:
        return 'Complete';
      case PolarAlignPhase.error:
        return 'Error';
    }
  }

  String get description {
    switch (this) {
      case PolarAlignPhase.idle:
        return 'Ready to start polar alignment';
      case PolarAlignPhase.measuring:
        return 'Capturing and plate solving images to calculate polar error';
      case PolarAlignPhase.adjusting:
        return 'Adjust your mount\'s altitude and azimuth knobs to minimize error';
      case PolarAlignPhase.complete:
        return 'Polar alignment completed successfully';
      case PolarAlignPhase.error:
        return 'An error occurred during polar alignment';
    }
  }

  bool get isActive =>
      this == PolarAlignPhase.measuring || this == PolarAlignPhase.adjusting;
}

/// Configuration for polar alignment capture settings
@freezed
class PolarAlignmentConfig with _$PolarAlignmentConfig {
  const PolarAlignmentConfig._();

  const factory PolarAlignmentConfig({
    /// Exposure time in seconds for each measurement image
    @Default(5.0) double exposureTime,

    /// Step size in degrees for mount rotation between measurements
    @Default(15.0) double stepSize,

    /// Camera binning (1, 2, 3, 4)
    @Default(2) int binning,

    /// Whether observing from northern hemisphere
    @Default(true) bool isNorth,

    /// Whether to use manual rotation (user rotates mount) vs automatic slewing
    @Default(false) bool manualRotation,

    /// Direction to rotate (true = east, false = west) for auto rotation
    @Default(true) bool rotateEast,

    /// Timeout in seconds for plate solve attempts
    @Default(30.0) double solveTimeout,

    /// Total error threshold in arcseconds to consider alignment complete
    /// When error drops below this value, auto-complete can be triggered
    @Default(30.0) double autoCompleteThreshold,

    /// Whether to start from current mount position or slew to pole first
    @Default(true) bool startFromCurrent,

    /// Camera gain (null = use camera default)
    int? gain,

    /// Camera offset (null = use camera default)
    int? offset,
  }) = _PolarAlignmentConfig;

  factory PolarAlignmentConfig.fromJson(Map<String, dynamic> json) =>
      _$PolarAlignmentConfigFromJson(json);

  /// Validate settings and return any validation errors
  List<String> validate() {
    final errors = <String>[];

    if (exposureTime < 0.1) {
      errors.add('Exposure time must be at least 0.1 seconds');
    }
    if (exposureTime > 300) {
      errors.add('Exposure time should not exceed 300 seconds');
    }

    if (stepSize < 5) {
      errors.add('Step size must be at least 5 degrees');
    }
    if (stepSize > 45) {
      errors.add('Step size should not exceed 45 degrees');
    }

    if (binning < 1 || binning > 4) {
      errors.add('Binning must be between 1 and 4');
    }

    if (solveTimeout < 5) {
      errors.add('Solve timeout must be at least 5 seconds');
    }
    if (solveTimeout > 120) {
      errors.add('Solve timeout should not exceed 120 seconds');
    }

    if (autoCompleteThreshold < 1) {
      errors.add('Auto-complete threshold must be at least 1 arcsecond');
    }
    if (autoCompleteThreshold > 300) {
      errors.add('Auto-complete threshold should not exceed 300 arcseconds');
    }

    if (gain != null && (gain! < 0 || gain! > 1000)) {
      errors.add('Gain must be between 0 and 1000');
    }

    if (offset != null && (offset! < 0 || offset! > 255)) {
      errors.add('Offset must be between 0 and 255');
    }

    return errors;
  }

  /// Create default configuration for quick start
  factory PolarAlignmentConfig.quickStart() => const PolarAlignmentConfig(
        exposureTime: 3.0,
        stepSize: 15.0,
        binning: 2,
        solveTimeout: 20.0,
      );

  /// Create configuration for high-precision alignment
  factory PolarAlignmentConfig.highPrecision() => const PolarAlignmentConfig(
        exposureTime: 10.0,
        stepSize: 30.0,
        binning: 1,
        solveTimeout: 45.0,
        autoCompleteThreshold: 10.0,
      );
}

/// A single polar alignment error measurement
@freezed
class PolarAlignmentError with _$PolarAlignmentError {
  const PolarAlignmentError._();

  const factory PolarAlignmentError({
    /// Azimuth error in arcseconds (positive = east)
    required double azimuthError,

    /// Altitude error in arcseconds (positive = above pole)
    required double altitudeError,

    /// Total error in arcseconds (pythagorean combination)
    required double totalError,

    /// Current RA position (degrees)
    required double currentRa,

    /// Current Dec position (degrees)
    required double currentDec,

    /// Target RA for perfect alignment (degrees)
    required double targetRa,

    /// Target Dec for perfect alignment (degrees)
    required double targetDec,

    /// When this measurement was taken
    required DateTime timestamp,
  }) = _PolarAlignmentError;

  factory PolarAlignmentError.fromJson(Map<String, dynamic> json) =>
      _$PolarAlignmentErrorFromJson(json);

  /// Create from backend event data
  factory PolarAlignmentError.fromEventData(Map<String, dynamic> data) {
    return PolarAlignmentError(
      azimuthError: (data['azimuth_error'] ?? 0).toDouble(),
      altitudeError: (data['altitude_error'] ?? 0).toDouble(),
      totalError: (data['total_error'] ?? 0).toDouble(),
      currentRa: (data['current_ra'] ?? 0).toDouble(),
      currentDec: (data['current_dec'] ?? 0).toDouble(),
      targetRa: (data['target_ra'] ?? 0).toDouble(),
      targetDec: (data['target_dec'] ?? 0).toDouble(),
      timestamp: DateTime.now(),
    );
  }

  /// Whether this error is within acceptable tolerance
  bool isWithinTolerance(double thresholdArcsec) =>
      totalError <= thresholdArcsec;

  /// Get direction text for azimuth adjustment
  String get azimuthDirection {
    if (azimuthError.abs() < 1) return 'centered';
    return azimuthError > 0 ? 'east' : 'west';
  }

  /// Get direction text for altitude adjustment
  String get altitudeDirection {
    if (altitudeError.abs() < 1) return 'centered';
    return altitudeError > 0 ? 'up' : 'down';
  }

  /// Format error as human-readable string
  String formatError() {
    final azDir = azimuthError > 0 ? 'E' : 'W';
    final altDir = altitudeError > 0 ? 'Up' : 'Dn';
    return 'Az: ${azimuthError.abs().toStringAsFixed(1)}" $azDir, '
        'Alt: ${altitudeError.abs().toStringAsFixed(1)}" $altDir, '
        'Total: ${totalError.toStringAsFixed(1)}"';
  }
}

/// Runtime state for polar alignment process
@freezed
class PolarAlignmentState with _$PolarAlignmentState {
  const PolarAlignmentState._();

  const factory PolarAlignmentState({
    /// Current phase of alignment
    @Default(PolarAlignPhase.idle) PolarAlignPhase phase,

    /// Current measurement point (1-3 during measuring, 0 during adjusting)
    @Default(0) int currentPoint,

    /// Status message to display to user
    @Default('Ready to start polar alignment') String statusMessage,

    /// Current error measurements (null if not yet calculated)
    PolarAlignmentError? currentError,

    /// Initial error when adjustment phase started (for progress tracking)
    PolarAlignmentError? initialError,

    /// Most recent captured image (JPEG bytes for display)
    @NullableUint8ListConverter() Uint8List? imageData,

    /// Image width
    int? imageWidth,

    /// Image height
    int? imageHeight,

    /// Solved RA from last image (degrees)
    double? solvedRa,

    /// Solved Dec from last image (degrees)
    double? solvedDec,

    /// Error message if phase is error
    String? errorMessage,

    /// Configuration used for this alignment run
    PolarAlignmentConfig? config,

    /// When alignment started
    DateTime? startedAt,
  }) = _PolarAlignmentState;

  factory PolarAlignmentState.fromJson(Map<String, dynamic> json) =>
      _$PolarAlignmentStateFromJson(json);

  /// Whether alignment is currently running
  bool get isRunning => phase.isActive;

  /// Whether we have error data to display
  bool get hasError => currentError != null;

  /// Whether we have an image to display
  bool get hasImage => imageData != null && imageData!.isNotEmpty;

  /// Calculate improvement percentage from initial error
  double? get improvementPercent {
    if (initialError == null || currentError == null) return null;
    if (initialError!.totalError == 0) return 100.0;
    final improvement =
        (initialError!.totalError - currentError!.totalError) /
            initialError!.totalError *
            100;
    return improvement.clamp(0.0, 100.0);
  }

  /// Whether current error is below auto-complete threshold
  bool isWithinThreshold(double thresholdArcsec) {
    if (currentError == null) return false;
    return currentError!.totalError <= thresholdArcsec;
  }
}

/// Result of a completed polar alignment session
@freezed
class PolarAlignmentResult with _$PolarAlignmentResult {
  const PolarAlignmentResult._();

  const factory PolarAlignmentResult({
    /// Initial error at start of adjustment phase
    required PolarAlignmentError initialError,

    /// Final error when alignment completed or stopped
    required PolarAlignmentError finalError,

    /// When alignment started
    required DateTime startedAt,

    /// When alignment completed
    required DateTime completedAt,

    /// Configuration used for this alignment
    required PolarAlignmentConfig config,

    /// Whether alignment was auto-completed (reached threshold)
    @Default(false) bool autoCompleted,

    /// Equipment profile ID used (for history tracking)
    int? equipmentProfileId,
  }) = _PolarAlignmentResult;

  factory PolarAlignmentResult.fromJson(Map<String, dynamic> json) =>
      _$PolarAlignmentResultFromJson(json);

  /// Calculate total improvement in arcseconds
  double get improvementArcsec =>
      initialError.totalError - finalError.totalError;

  /// Calculate improvement percentage
  double get improvementPercent {
    if (initialError.totalError == 0) return 100.0;
    return (improvementArcsec / initialError.totalError * 100).clamp(0.0, 100.0);
  }

  /// Duration of the alignment session
  Duration get duration => completedAt.difference(startedAt);

  /// Whether this was a successful alignment (significant improvement)
  bool get wasSuccessful =>
      finalError.totalError < initialError.totalError * 0.5 ||
      finalError.totalError < 60; // Less than 1 arcminute
}

/// Custom JSON converter for nullable Uint8List
class NullableUint8ListConverter implements JsonConverter<Uint8List?, List<int>?> {
  const NullableUint8ListConverter();

  @override
  Uint8List? fromJson(List<int>? json) =>
      json != null ? Uint8List.fromList(json) : null;

  @override
  List<int>? toJson(Uint8List? object) => object?.toList();
}
