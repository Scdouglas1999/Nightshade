# Flat Wizard Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete redesign of Flat Wizard with split-view layout, rate-tracking algorithm for sky flats, history-based exposure suggestions, and real-time visual feedback.

**Architecture:** Split-view UI with controls panel (left) and preview panel (right) persistent across sub-tabs. New database table for exposure history. Improved algorithm with rate-tracking for sky flats and capped adjustment jumps.

**Tech Stack:** Flutter/Dart, Drift (SQLite), Riverpod, nightshade_ui components

---

## Phase 1: Database & Data Models

### Task 1.1: Create Flat History Table

**Files:**
- Create: `packages/nightshade_core/lib/src/database/tables/flat_history.dart`

**Step 1: Create the table definition**

```dart
import 'package:drift/drift.dart';

/// Stores historical flat frame calibration results for learned exposure suggestions
@DataClassName('FlatHistoryEntry')
@TableIndex(name: 'idx_flat_history_profile', columns: {#equipmentProfileId})
@TableIndex(name: 'idx_flat_history_filter', columns: {#filterName})
@TableIndex(name: 'idx_flat_history_timestamp', columns: {#timestamp})
class FlatHistory extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Reference to equipment profile used
  IntColumn get equipmentProfileId => integer().nullable()();

  /// Filter name (e.g., "L", "R", "Ha")
  TextColumn get filterName => text()();

  /// Optimal exposure time found (seconds)
  RealColumn get exposureTime => real()();

  /// Target histogram percentage (0-100)
  RealColumn get histogramTarget => real()();

  /// Actual ADU value achieved
  IntColumn get actualAdu => integer()();

  /// Panel brightness used (0-255, null for sky flats)
  IntColumn get panelBrightness => integer().nullable()();

  /// For sky flats: ADU change rate (ADU/second)
  RealColumn get skyAduRate => real().nullable()();

  /// Twilight phase: 'dawn', 'dusk', or null for panel
  TextColumn get twilightPhase => text().nullable()();

  /// Gain setting used
  IntColumn get gain => integer().withDefault(const Constant(0))();

  /// Binning used
  IntColumn get binning => integer().withDefault(const Constant(1))();

  /// When this calibration was performed
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}
```

---

### Task 1.2: Create Flat History DAO

**Files:**
- Create: `packages/nightshade_core/lib/src/database/daos/flat_history_dao.dart`

**Step 1: Create the DAO**

```dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/flat_history.dart';

part 'flat_history_dao.g.dart';

@DriftAccessor(tables: [FlatHistory])
class FlatHistoryDao extends DatabaseAccessor<NightshadeDatabase>
    with _$FlatHistoryDaoMixin {
  FlatHistoryDao(super.db);

  /// Get recent calibrations for a filter, optionally filtered by equipment profile
  Future<List<FlatHistoryEntry>> getRecentCalibrations({
    required String filterName,
    int? equipmentProfileId,
    int limit = 10,
  }) {
    final query = select(flatHistory)
      ..where((t) => t.filterName.equals(filterName))
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
      ..limit(limit);

    if (equipmentProfileId != null) {
      query.where((t) => t.equipmentProfileId.equals(equipmentProfileId));
    }

    return query.get();
  }

  /// Get suggested starting exposure based on historical data
  /// Returns average of last N successful calibrations for this filter
  Future<double?> getSuggestedExposure({
    required String filterName,
    int? equipmentProfileId,
    int sampleSize = 5,
  }) async {
    final entries = await getRecentCalibrations(
      filterName: filterName,
      equipmentProfileId: equipmentProfileId,
      limit: sampleSize,
    );

    if (entries.isEmpty) return null;

    final sum = entries.fold<double>(0, (sum, e) => sum + e.exposureTime);
    return sum / entries.length;
  }

  /// Record a successful calibration
  Future<int> recordCalibration({
    required String filterName,
    required double exposureTime,
    required double histogramTarget,
    required int actualAdu,
    int? equipmentProfileId,
    int? panelBrightness,
    double? skyAduRate,
    String? twilightPhase,
    int gain = 0,
    int binning = 1,
  }) {
    return into(flatHistory).insert(FlatHistoryCompanion.insert(
      filterName: filterName,
      exposureTime: exposureTime,
      histogramTarget: histogramTarget,
      actualAdu: actualAdu,
      equipmentProfileId: Value(equipmentProfileId),
      panelBrightness: Value(panelBrightness),
      skyAduRate: Value(skyAduRate),
      twilightPhase: Value(twilightPhase),
      gain: Value(gain),
      binning: Value(binning),
    ));
  }

  /// Clear old history entries (keep last N per filter)
  Future<void> pruneHistory({int keepPerFilter = 50}) async {
    // Get distinct filter names
    final filters = await (selectOnly(flatHistory, distinct: true)
          ..addColumns([flatHistory.filterName]))
        .map((row) => row.read(flatHistory.filterName)!)
        .get();

    for (final filter in filters) {
      // Get IDs to keep
      final keepIds = await (select(flatHistory)
            ..where((t) => t.filterName.equals(filter))
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
            ..limit(keepPerFilter))
          .map((e) => e.id)
          .get();

      if (keepIds.isNotEmpty) {
        // Delete entries not in keep list
        await (delete(flatHistory)
              ..where((t) =>
                  t.filterName.equals(filter) & t.id.isNotIn(keepIds)))
            .go();
      }
    }
  }
}
```

---

### Task 1.3: Register Flat History in Database

**Files:**
- Modify: `packages/nightshade_core/lib/src/database/database.dart`

**Step 1: Add import and registration**

Add to imports:
```dart
import 'tables/flat_history.dart';
import 'daos/flat_history_dao.dart';
```

Add `FlatHistory` to the tables list in `@DriftDatabase`:
```dart
@DriftDatabase(
  tables: [
    EquipmentProfiles,
    ImagingSessions,
    Targets,
    Sequences,
    SequenceNodes,
    SequenceCheckpoints,
    CapturedImages,
    ImageMetadata,
    AppSettings,
    WeatherSettings,
    FlatHistory,  // Add this
  ],
  daos: [
    ImagesDao,
    EquipmentProfilesDao,
    SessionsDao,
    SequencesDao,
    SequenceCheckpointsDao,
    TargetsDao,
    SettingsDao,
    WeatherSettingsDao,
    FlatHistoryDao,  // Add this
  ],
)
```

**Step 2: Increment schema version and add migration**

Change `schemaVersion` to 7:
```dart
@override
int get schemaVersion => 7;
```

Add migration in `onUpgrade`:
```dart
// Version 7: Add flat history table
if (from < 7) {
  await m.createTable(flatHistory);
  await m.createIndex(Index('idx_flat_history_profile',
      'CREATE INDEX idx_flat_history_profile ON flat_history (equipment_profile_id)'));
  await m.createIndex(Index('idx_flat_history_filter',
      'CREATE INDEX idx_flat_history_filter ON flat_history (filter_name)'));
  await m.createIndex(Index('idx_flat_history_timestamp',
      'CREATE INDEX idx_flat_history_timestamp ON flat_history (timestamp)'));
}
```

**Step 3: Run code generation**

Run: `melos run generate`

Expected: Generated files updated including `database.g.dart` and `flat_history_dao.g.dart`

---

### Task 1.4: Create Flat Wizard Settings Model

**Files:**
- Create: `packages/nightshade_core/lib/src/models/flat_wizard/flat_wizard_settings.dart`

**Step 1: Create the settings model**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'flat_wizard_settings.freezed.dart';
part 'flat_wizard_settings.g.dart';

/// Global settings for flat wizard
@freezed
class FlatWizardGlobalSettings with _$FlatWizardGlobalSettings {
  const factory FlatWizardGlobalSettings({
    /// Target histogram percentage (0-100), default 50%
    @Default(50.0) double histogramTarget,

    /// Tolerance as percentage of target (1-25), default 10%
    @Default(10.0) double tolerancePercent,

    /// Minimum exposure in seconds
    @Default(0.001) double minExposure,

    /// Maximum exposure in seconds
    @Default(30.0) double maxExposure,

    /// Number of frames to capture per filter
    @Default(30) int frameCount,

    /// Default gain for flats
    @Default(0) int gain,

    /// Default binning for flats
    @Default(1) int binning,

    /// Save path for flat frames
    String? savePath,

    /// Create date subfolder
    @Default(true) bool createDateSubfolder,

    /// Create filter subfolders
    @Default(true) bool createFilterSubfolders,
  }) = _FlatWizardGlobalSettings;

  factory FlatWizardGlobalSettings.fromJson(Map<String, dynamic> json) =>
      _$FlatWizardGlobalSettingsFromJson(json);
}

/// Per-filter settings override
@freezed
class FlatFilterSettings with _$FlatFilterSettings {
  const factory FlatFilterSettings({
    required String filterName,

    /// Filter position in wheel (0-indexed)
    required int filterPosition,

    /// Whether this filter is enabled for capture
    @Default(true) bool enabled,

    /// Override histogram target (null = use global)
    double? histogramTargetOverride,

    /// Override tolerance (null = use global)
    double? toleranceOverride,

    /// Override min exposure (null = use global)
    double? minExposureOverride,

    /// Override max exposure (null = use global)
    double? maxExposureOverride,

    /// Override frame count (null = use global)
    int? frameCountOverride,

    /// Suggested exposure from history (informational)
    double? suggestedExposure,

    /// Current calibrated exposure (set after tuning)
    double? calibratedExposure,

    /// Frames captured so far
    @Default(0) int capturedCount,

    /// Current measured ADU
    double? currentAdu,

    /// Calibration status
    @Default(FilterCalibrationStatus.pending) FilterCalibrationStatus status,
  }) = _FlatFilterSettings;

  factory FlatFilterSettings.fromJson(Map<String, dynamic> json) =>
      _$FlatFilterSettingsFromJson(json);
}

enum FilterCalibrationStatus {
  pending,
  calibrating,
  calibrated,
  capturing,
  complete,
  failed,
  skipped,
}

/// Filter preset for quick selection
@freezed
class FlatFilterPreset with _$FlatFilterPreset {
  const factory FlatFilterPreset({
    required String name,
    required List<String> filterNames,
  }) = _$FlatFilterPreset;

  factory FlatFilterPreset.fromJson(Map<String, dynamic> json) =>
      _$FlatFilterPresetFromJson(json);
}
```

**Step 2: Run code generation**

Run: `melos run generate`

---

### Task 1.5: Create Enhanced Flat Wizard State

**Files:**
- Create: `packages/nightshade_core/lib/src/models/flat_wizard/flat_wizard_state.dart`

**Step 1: Create the state model**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'flat_wizard_settings.dart';

part 'flat_wizard_state.freezed.dart';
part 'flat_wizard_state.g.dart';

enum FlatWizardMode { quick, batch, skyFlats }
enum TwilightMode { dawn, dusk }

/// ADU measurement for tracking convergence
@freezed
class AduMeasurement with _$AduMeasurement {
  const factory AduMeasurement({
    required double exposure,
    required double adu,
    required DateTime timestamp,
  }) = _AduMeasurement;

  factory AduMeasurement.fromJson(Map<String, dynamic> json) =>
      _$AduMeasurementFromJson(json);
}

/// Sky brightness measurement for rate tracking
@freezed
class SkyBrightnessMeasurement with _$SkyBrightnessMeasurement {
  const factory SkyBrightnessMeasurement({
    required double adu,
    required double exposureUsed,
    required DateTime timestamp,
  }) = _$SkyBrightnessMeasurement;

  factory SkyBrightnessMeasurement.fromJson(Map<String, dynamic> json) =>
      _$SkyBrightnessMeasurementFromJson(json);
}

/// Complete flat wizard state
@freezed
class FlatWizardState with _$FlatWizardState {
  const factory FlatWizardState({
    /// Current operating mode
    @Default(FlatWizardMode.quick) FlatWizardMode mode,

    /// Global settings
    @Default(FlatWizardGlobalSettings()) FlatWizardGlobalSettings globalSettings,

    /// Per-filter settings
    @Default([]) List<FlatFilterSettings> filterSettings,

    /// Saved filter presets
    @Default([]) List<FlatFilterPreset> filterPresets,

    /// Current filter index being processed
    @Default(0) int currentFilterIndex,

    /// Current frame index for active filter
    @Default(0) int currentFrameIndex,

    /// Is capture/calibration in progress
    @Default(false) bool isCapturing,

    /// Is currently exposing (for countdown)
    @Default(false) bool isExposing,

    /// Current exposure start time (for countdown)
    DateTime? exposureStartTime,

    /// Current exposure duration (for countdown)
    double? currentExposureDuration,

    /// ADU measurements for convergence graph
    @Default([]) List<AduMeasurement> aduHistory,

    /// Sky brightness measurements for rate tracking
    @Default([]) List<SkyBrightnessMeasurement> skyBrightnessHistory,

    /// Calculated sky brightness change rate (ADU/s)
    double? skyAduRate,

    /// Twilight mode for sky flats
    @Default(TwilightMode.dusk) TwilightMode twilightMode,

    /// Most recent captured image path
    String? lastImagePath,

    /// Most recent captured image data (for preview)
    // Using dynamic to avoid importing image types here
    @JsonKey(includeFromJson: false, includeToJson: false)
    dynamic lastImageData,

    /// Error message if any
    String? errorMessage,

    /// Warning message (non-fatal, informational)
    String? warningMessage,

    /// Status message for progress display
    String? statusMessage,

    /// Visualization toggles
    @Default(true) bool showAduGraph,
    @Default(true) bool showExposureTimeline,
    @Default(true) bool showSkyBrightness,
    @Default(true) bool showFilterCards,
    @Default(false) bool showHistogramOverlay,
  }) = _FlatWizardState;

  factory FlatWizardState.fromJson(Map<String, dynamic> json) =>
      _$FlatWizardStateFromJson(json);
}
```

**Step 2: Run code generation**

Run: `melos run generate`

---

### Task 1.6: Export Models from nightshade_core

**Files:**
- Modify: `packages/nightshade_core/lib/nightshade_core.dart`

**Step 1: Add exports**

Add these exports to the barrel file:
```dart
export 'src/models/flat_wizard/flat_wizard_settings.dart';
export 'src/models/flat_wizard/flat_wizard_state.dart';
```

---

## Phase 2: Algorithm Improvements

### Task 2.1: Create Sky Flat Rate Tracker

**Files:**
- Create: `packages/nightshade_core/lib/src/services/sky_brightness_tracker.dart`

**Step 1: Create the rate tracker**

```dart
import 'dart:math' as math;

/// Tracks sky brightness changes during twilight for predictive exposure calculation
class SkyBrightnessTracker {
  final List<_BrightnessSample> _samples = [];

  /// Maximum age of samples to consider (5 minutes)
  static const _maxSampleAge = Duration(minutes: 5);

  /// Minimum samples needed for rate calculation
  static const _minSamples = 2;

  /// Add a brightness measurement
  void addSample({
    required double adu,
    required double exposureTime,
    required DateTime timestamp,
  }) {
    // Normalize ADU to ADU per second for comparison
    final aduPerSecond = adu / exposureTime;

    _samples.add(_BrightnessSample(
      aduPerSecond: aduPerSecond,
      timestamp: timestamp,
    ));

    // Prune old samples
    _pruneOldSamples();
  }

  void _pruneOldSamples() {
    final cutoff = DateTime.now().subtract(_maxSampleAge);
    _samples.removeWhere((s) => s.timestamp.isBefore(cutoff));
  }

  /// Calculate current rate of brightness change (ADU/s per second)
  /// Positive = brightening (dawn), Negative = darkening (dusk)
  double? calculateRate() {
    if (_samples.length < _minSamples) return null;

    // Use linear regression for rate calculation
    final n = _samples.length;
    final now = DateTime.now();

    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    for (final sample in _samples) {
      // X = seconds ago (negative so older = smaller)
      final x = sample.timestamp.difference(now).inMilliseconds / 1000.0;
      final y = sample.aduPerSecond;

      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }

    final denominator = n * sumX2 - sumX * sumX;
    if (denominator.abs() < 0.0001) return null;

    // Slope = rate of change
    final slope = (n * sumXY - sumX * sumY) / denominator;

    return slope;
  }

  /// Predict ADU at a future time given current conditions
  double? predictAdu({
    required double exposureTime,
    required Duration futureOffset,
  }) {
    if (_samples.isEmpty) return null;

    final rate = calculateRate();
    final currentAduPerSec = _samples.last.aduPerSecond;

    if (rate == null) {
      // No rate info, just use current value
      return currentAduPerSec * exposureTime;
    }

    // Predict ADU/s at future time
    final futureSeconds = futureOffset.inMilliseconds / 1000.0;
    final predictedAduPerSec = currentAduPerSec + (rate * futureSeconds);

    // Account for exposure duration (average over exposure period)
    final exposureMidpoint = futureSeconds + (exposureTime / 2);
    final midpointAduPerSec = currentAduPerSec + (rate * exposureMidpoint);

    return midpointAduPerSec * exposureTime;
  }

  /// Calculate optimal exposure to achieve target ADU
  double? calculateOptimalExposure({
    required double targetAdu,
    required double minExposure,
    required double maxExposure,
  }) {
    if (_samples.isEmpty) return null;

    final rate = calculateRate();
    final currentAduPerSec = _samples.last.aduPerSecond;

    if (currentAduPerSec <= 0) return null;

    // Simple case: no rate change
    if (rate == null || rate.abs() < 0.001) {
      final exposure = targetAdu / currentAduPerSec;
      return exposure.clamp(minExposure, maxExposure);
    }

    // With rate change, solve iteratively
    // Start with naive estimate
    double exposure = targetAdu / currentAduPerSec;

    for (int i = 0; i < 5; i++) {
      final predictedAdu = predictAdu(
        exposureTime: exposure,
        futureOffset: Duration.zero,
      );

      if (predictedAdu == null || predictedAdu <= 0) break;

      // Adjust exposure
      final ratio = targetAdu / predictedAdu;
      exposure = (exposure * ratio).clamp(minExposure, maxExposure);

      // Check convergence
      if ((ratio - 1.0).abs() < 0.02) break;
    }

    return exposure.clamp(minExposure, maxExposure);
  }

  /// Whether sky is getting brighter (dawn) or darker (dusk)
  bool? isBrightening() {
    final rate = calculateRate();
    if (rate == null) return null;
    return rate > 0;
  }

  /// Get number of samples
  int get sampleCount => _samples.length;

  /// Clear all samples
  void clear() => _samples.clear();
}

class _BrightnessSample {
  final double aduPerSecond;
  final DateTime timestamp;

  _BrightnessSample({
    required this.aduPerSecond,
    required this.timestamp,
  });
}
```

---

### Task 2.2: Create Improved Exposure Calculator

**Files:**
- Create: `packages/nightshade_core/lib/src/services/flat_exposure_calculator.dart`

**Step 1: Create the calculator**

```dart
import 'dart:math' as math;

/// Calculates optimal flat frame exposure with improved convergence
class FlatExposureCalculator {
  /// Convert histogram percentage to ADU (16-bit)
  static int histogramPercentToAdu(double percent) {
    return ((percent / 100.0) * 65535).round();
  }

  /// Convert ADU to histogram percentage
  static double aduToHistogramPercent(int adu) {
    return (adu / 65535.0) * 100.0;
  }

  /// Calculate next exposure with capped adjustments
  ///
  /// This prevents the wild jumps seen in naive proportional adjustment
  static double calculateNextExposure({
    required double currentExposure,
    required double currentAdu,
    required double targetAdu,
    required double minExposure,
    required double maxExposure,
    double maxAdjustmentFactor = 2.0,
  }) {
    if (currentAdu <= 0) {
      // No signal, try middle of range
      return math.sqrt(minExposure * maxExposure);
    }

    // Calculate raw ratio
    final ratio = targetAdu / currentAdu;

    // Cap the adjustment to prevent wild jumps
    // Max 2x increase or 0.5x decrease per iteration
    final cappedRatio = ratio.clamp(
      1.0 / maxAdjustmentFactor,
      maxAdjustmentFactor,
    );

    // Apply logarithmic damping for smoother convergence
    // This reduces oscillation around the target
    final dampedRatio = _applyDamping(cappedRatio);

    final nextExposure = currentExposure * dampedRatio;

    return nextExposure.clamp(minExposure, maxExposure);
  }

  /// Apply damping to reduce oscillation
  static double _applyDamping(double ratio) {
    // For ratios close to 1.0, use as-is
    if (ratio >= 0.8 && ratio <= 1.25) {
      return ratio;
    }

    // For larger adjustments, dampen by 30%
    final deviation = ratio - 1.0;
    return 1.0 + (deviation * 0.7);
  }

  /// Binary search with early termination
  ///
  /// More efficient than proportional adjustment for stable light sources
  static double binarySearchExposure({
    required double lowExposure,
    required double highExposure,
    required double measuredAdu,
    required double targetAdu,
    required double tolerancePercent,
  }) {
    final toleranceAdu = targetAdu * tolerancePercent / 100.0;

    // Check if within tolerance
    if ((measuredAdu - targetAdu).abs() <= toleranceAdu) {
      // Already good, return current midpoint
      return (lowExposure + highExposure) / 2.0;
    }

    // Narrow the search range
    final midpoint = (lowExposure + highExposure) / 2.0;

    if (measuredAdu < targetAdu) {
      // Need more light, search upper half
      return (midpoint + highExposure) / 2.0;
    } else {
      // Too bright, search lower half
      return (lowExposure + midpoint) / 2.0;
    }
  }

  /// Get starting exposure from history or geometric mean
  static double getStartingExposure({
    double? historicalExposure,
    required double minExposure,
    required double maxExposure,
    double? currentSkyAduRate,
    double? historicalSkyAduRate,
  }) {
    if (historicalExposure != null) {
      // Adjust historical exposure for current sky conditions if available
      if (currentSkyAduRate != null &&
          historicalSkyAduRate != null &&
          historicalSkyAduRate.abs() > 0.001) {
        final ratio = currentSkyAduRate / historicalSkyAduRate;
        // Inverse relationship: brighter sky = shorter exposure
        final adjusted = historicalExposure / ratio.clamp(0.5, 2.0);
        return adjusted.clamp(minExposure, maxExposure);
      }
      return historicalExposure.clamp(minExposure, maxExposure);
    }

    // No history, use geometric mean (good for wide ranges)
    return math.sqrt(minExposure * maxExposure);
  }

  /// Check if exposure is at limits and suggest action
  static ExposureLimitStatus checkLimits({
    required double exposure,
    required double measuredAdu,
    required double targetAdu,
    required double minExposure,
    required double maxExposure,
    required double tolerancePercent,
  }) {
    final toleranceAdu = targetAdu * tolerancePercent / 100.0;
    final isOnTarget = (measuredAdu - targetAdu).abs() <= toleranceAdu;

    if (isOnTarget) {
      return ExposureLimitStatus.onTarget;
    }

    if (exposure >= maxExposure * 0.99 && measuredAdu < targetAdu) {
      return ExposureLimitStatus.maxExposureReached;
    }

    if (exposure <= minExposure * 1.01 && measuredAdu > targetAdu) {
      return ExposureLimitStatus.minExposureReached;
    }

    return ExposureLimitStatus.adjusting;
  }
}

enum ExposureLimitStatus {
  onTarget,
  adjusting,
  maxExposureReached,
  minExposureReached,
}
```

---

### Task 2.3: Update Flat Wizard Service

**Files:**
- Modify: `packages/nightshade_core/lib/src/services/flat_wizard_service.dart`

**Step 1: Add imports and dependencies**

Add at top of file:
```dart
import 'sky_brightness_tracker.dart';
import 'flat_exposure_calculator.dart';
import '../database/database.dart';
import '../database/daos/flat_history_dao.dart';
```

**Step 2: Add rate-aware calibration method**

Add this method to `FlatWizardService`:
```dart
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
  void Function(int iteration, double exposure, double adu, String status)? onProgress,
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
    iterations: iteration,
    errorMessage: 'Did not converge within $maxIterations iterations',
  );
}
```

---

## Phase 3: UI Foundation

### Task 3.1: Create Split View Layout Widget

**Files:**
- Create: `packages/nightshade_app/lib/screens/flat_wizard/widgets/flat_wizard_split_view.dart`

**Step 1: Create the split view layout**

```dart
import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Split view layout for flat wizard with controls on left, preview on right
class FlatWizardSplitView extends StatelessWidget {
  final Widget controlsPanel;
  final Widget previewPanel;
  final double controlsWidth;

  const FlatWizardSplitView({
    super.key,
    required this.controlsPanel,
    required this.previewPanel,
    this.controlsWidth = 0.4, // 40% for controls
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final controlsPixelWidth = constraints.maxWidth * controlsWidth;
        final previewPixelWidth = constraints.maxWidth * (1 - controlsWidth);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Controls panel (left)
            SizedBox(
              width: controlsPixelWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(
                    right: BorderSide(color: colors.border),
                  ),
                ),
                child: controlsPanel,
              ),
            ),

            // Preview panel (right)
            Expanded(
              child: Container(
                color: colors.background,
                child: previewPanel,
              ),
            ),
          ],
        );
      },
    );
  }
}
```

---

### Task 3.2: Create Flat Wizard Provider

**Files:**
- Create: `packages/nightshade_core/lib/src/providers/flat_wizard_provider.dart`

**Step 1: Create the provider**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/flat_wizard/flat_wizard_state.dart';
import '../models/flat_wizard/flat_wizard_settings.dart';
import '../services/flat_wizard_service.dart';
import '../services/sky_brightness_tracker.dart';
import '../services/flat_exposure_calculator.dart';
import '../database/database.dart';
import 'backend_provider.dart';
import 'equipment_provider.dart';
import 'database_provider.dart';

/// Provider for flat wizard state
final flatWizardProvider =
    StateNotifierProvider<FlatWizardNotifier, FlatWizardState>((ref) {
  return FlatWizardNotifier(ref);
});

/// Provider for sky brightness tracker (sky flats mode)
final skyBrightnessTrackerProvider = Provider<SkyBrightnessTracker>((ref) {
  return SkyBrightnessTracker();
});

class FlatWizardNotifier extends StateNotifier<FlatWizardState> {
  final Ref ref;
  bool _cancelRequested = false;

  FlatWizardNotifier(this.ref) : super(const FlatWizardState());

  // --- Mode Management ---

  void setMode(FlatWizardMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setTwilightMode(TwilightMode mode) {
    state = state.copyWith(twilightMode: mode);
  }

  // --- Global Settings ---

  void updateGlobalSettings(FlatWizardGlobalSettings settings) {
    state = state.copyWith(globalSettings: settings);
  }

  void setHistogramTarget(double percent) {
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(
        histogramTarget: percent.clamp(0, 100),
      ),
    );
  }

  void setTolerance(double percent) {
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(
        tolerancePercent: percent.clamp(1, 25),
      ),
    );
  }

  void setFrameCount(int count) {
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(
        frameCount: count.clamp(1, 999),
      ),
    );
  }

  void setSavePath(String? path) {
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(savePath: path),
    );
  }

  // --- Filter Management ---

  /// Load filters from connected filter wheel
  Future<void> loadFiltersFromWheel() async {
    final fwState = ref.read(filterWheelStateProvider);
    if (fwState.filterNames.isEmpty) return;

    final db = ref.read(databaseProvider);
    final profileId = ref.read(activeEquipmentProfileProvider)?.id;

    final filterSettings = <FlatFilterSettings>[];
    for (int i = 0; i < fwState.filterNames.length; i++) {
      final filterName = fwState.filterNames[i];

      // Get suggested exposure from history
      final suggested = await db.flatHistoryDao.getSuggestedExposure(
        filterName: filterName,
        equipmentProfileId: profileId,
      );

      filterSettings.add(FlatFilterSettings(
        filterName: filterName,
        filterPosition: i,
        suggestedExposure: suggested,
      ));
    }

    state = state.copyWith(filterSettings: filterSettings);
  }

  /// Toggle filter enabled state
  void toggleFilter(int index, bool enabled) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = updated[index].copyWith(enabled: enabled);
    state = state.copyWith(filterSettings: updated);
  }

  /// Update per-filter settings
  void updateFilterSettings(int index, FlatFilterSettings settings) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = settings;
    state = state.copyWith(filterSettings: updated);
  }

  /// Reorder filters
  void reorderFilters(int oldIndex, int newIndex) {
    final updated = [...state.filterSettings];
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex < oldIndex ? newIndex : newIndex - 1, item);
    state = state.copyWith(filterSettings: updated);
  }

  /// Auto-order filters for twilight
  void autoOrderForTwilight() {
    if (state.filterSettings.isEmpty) return;

    // Define filter restrictiveness (higher = more restrictive = less light)
    const restrictiveness = {
      'Ha': 100, 'H-alpha': 100, 'Halpha': 100,
      'SII': 95, 'S-II': 95, 'S2': 95,
      'OIII': 90, 'O-III': 90, 'O3': 90,
      'NII': 85, 'N-II': 85,
      'R': 50, 'Red': 50,
      'G': 45, 'Green': 45,
      'B': 40, 'Blue': 40,
      'L': 10, 'Lum': 10, 'Luminance': 10, 'Clear': 10,
    };

    int getRestrictiveness(String filter) {
      for (final entry in restrictiveness.entries) {
        if (filter.toLowerCase().contains(entry.key.toLowerCase())) {
          return entry.value;
        }
      }
      return 50; // Default middle value
    }

    final sorted = [...state.filterSettings];
    sorted.sort((a, b) {
      final aVal = getRestrictiveness(a.filterName);
      final bVal = getRestrictiveness(b.filterName);

      if (state.twilightMode == TwilightMode.dusk) {
        // Dusk (darkening): most restrictive first
        return bVal.compareTo(aVal);
      } else {
        // Dawn (brightening): least restrictive first
        return aVal.compareTo(bVal);
      }
    });

    state = state.copyWith(filterSettings: sorted);
  }

  // --- Visualization Toggles ---

  void toggleAduGraph(bool show) {
    state = state.copyWith(showAduGraph: show);
  }

  void toggleExposureTimeline(bool show) {
    state = state.copyWith(showExposureTimeline: show);
  }

  void toggleSkyBrightness(bool show) {
    state = state.copyWith(showSkyBrightness: show);
  }

  void toggleFilterCards(bool show) {
    state = state.copyWith(showFilterCards: show);
  }

  void toggleHistogramOverlay(bool show) {
    state = state.copyWith(showHistogramOverlay: show);
  }

  // --- Capture Control ---

  void requestCancel() {
    _cancelRequested = true;
    state = state.copyWith(statusMessage: 'Cancelling...');
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void clearWarning() {
    state = state.copyWith(warningMessage: null);
  }

  // --- ADU History ---

  void addAduMeasurement(double exposure, double adu) {
    final measurement = AduMeasurement(
      exposure: exposure,
      adu: adu,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      aduHistory: [...state.aduHistory, measurement],
    );
  }

  void clearAduHistory() {
    state = state.copyWith(aduHistory: []);
  }
}
```

**Step 2: Export from nightshade_core**

Add to `packages/nightshade_core/lib/nightshade_core.dart`:
```dart
export 'src/providers/flat_wizard_provider.dart';
export 'src/services/sky_brightness_tracker.dart';
export 'src/services/flat_exposure_calculator.dart';
```

---

## Phase 4: Preview Panel

### Task 4.1: Create Preview Panel Widget

**Files:**
- Create: `packages/nightshade_app/lib/screens/flat_wizard/widgets/flat_preview_panel.dart`

**Step 1: Create the preview panel**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class FlatPreviewPanel extends ConsumerWidget {
  const FlatPreviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);

    return Column(
      children: [
        // Image preview area
        Expanded(
          flex: 3,
          child: _ImagePreview(
            imageData: state.lastImageData,
            showHistogram: state.showHistogramOverlay,
          ),
        ),

        // Stats bar
        _StatsBar(state: state),

        // Live countdown (when exposing)
        if (state.isExposing) _ExposureCountdown(state: state),

        // Toggleable visualizations
        Expanded(
          flex: 2,
          child: _VisualizationsSection(state: state),
        ),
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final dynamic imageData;
  final bool showHistogram;

  const _ImagePreview({
    required this.imageData,
    required this.showHistogram,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Stack(
        children: [
          // Image or placeholder
          Center(
            child: imageData != null
                ? _buildImage()
                : _buildPlaceholder(colors),
          ),

          // Histogram overlay (top right)
          if (showHistogram && imageData != null)
            Positioned(
              top: 12,
              right: 12,
              child: _buildHistogramOverlay(colors),
            ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    // TODO: Render actual image data
    return const Center(
      child: Text('Image Preview'),
    );
  }

  Widget _buildPlaceholder(NightshadeColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          LucideIcons.image,
          size: 64,
          color: colors.textMuted,
        ),
        const SizedBox(height: 16),
        Text(
          'No image captured yet',
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Start capture or test exposure to see preview',
          style: TextStyle(
            color: colors.textMuted.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildHistogramOverlay(NightshadeColors colors) {
    return Container(
      width: 150,
      height: 80,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Histogram',
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
            ),
          ),
          const Spacer(),
          // TODO: Actual histogram
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final FlatWizardState state;

  const _StatsBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Get current filter info
    final currentFilter = state.filterSettings.isNotEmpty &&
            state.currentFilterIndex < state.filterSettings.length
        ? state.filterSettings[state.currentFilterIndex]
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Filter
          _StatItem(
            label: 'Filter',
            value: currentFilter?.filterName ?? '-',
            colors: colors,
          ),
          _divider(colors),

          // Exposure
          _StatItem(
            label: 'Exposure',
            value: currentFilter?.calibratedExposure != null
                ? '${currentFilter!.calibratedExposure!.toStringAsFixed(2)}s'
                : '-',
            colors: colors,
          ),
          _divider(colors),

          // ADU
          _StatItem(
            label: 'ADU',
            value: currentFilter?.currentAdu != null
                ? currentFilter!.currentAdu!.toStringAsFixed(0)
                : '-',
            colors: colors,
          ),
          _divider(colors),

          // Frame progress
          _StatItem(
            label: 'Frame',
            value: currentFilter != null
                ? '${currentFilter.capturedCount}/${currentFilter.frameCountOverride ?? state.globalSettings.frameCount}'
                : '-/-',
            colors: colors,
          ),
          _divider(colors),

          // Status
          Expanded(
            child: _StatusIndicator(
              status: currentFilter?.status ?? FilterCalibrationStatus.pending,
              colors: colors,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(NightshadeColors colors) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: colors.border,
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _StatItem({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final FilterCalibrationStatus status;
  final NightshadeColors colors;

  const _StatusIndicator({
    required this.status,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      FilterCalibrationStatus.pending => (LucideIcons.clock, 'Pending', colors.textMuted),
      FilterCalibrationStatus.calibrating => (LucideIcons.settings, 'Calibrating', colors.warning),
      FilterCalibrationStatus.calibrated => (LucideIcons.check, 'On Target', colors.success),
      FilterCalibrationStatus.capturing => (LucideIcons.camera, 'Capturing', colors.primary),
      FilterCalibrationStatus.complete => (LucideIcons.checkCircle, 'Complete', colors.success),
      FilterCalibrationStatus.failed => (LucideIcons.alertCircle, 'Failed', colors.error),
      FilterCalibrationStatus.skipped => (LucideIcons.skipForward, 'Skipped', colors.textMuted),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ExposureCountdown extends StatelessWidget {
  final FlatWizardState state;

  const _ExposureCountdown({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    if (state.exposureStartTime == null || state.currentExposureDuration == null) {
      return const SizedBox.shrink();
    }

    final elapsed = DateTime.now().difference(state.exposureStartTime!).inMilliseconds / 1000.0;
    final remaining = (state.currentExposureDuration! - elapsed).clamp(0.0, state.currentExposureDuration!);
    final progress = elapsed / state.currentExposureDuration!;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.timer, size: 18, color: colors.primary),
          const SizedBox(width: 12),
          Text(
            'CAPTURING: ${remaining.toStringAsFixed(1)}s remaining',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: NightshadeProgressBar(
              value: progress.clamp(0.0, 1.0),
              height: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisualizationsSection extends ConsumerWidget {
  final FlatWizardState state;

  const _VisualizationsSection({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Count visible visualizations
    final visibleCount = [
      state.showAduGraph,
      state.showExposureTimeline,
      state.showSkyBrightness && state.mode == FlatWizardMode.skyFlats,
      state.showFilterCards,
    ].where((v) => v).length;

    if (visibleCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggles
          Row(
            children: [
              Text(
                'Visualizations',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              _ToggleButton(
                icon: LucideIcons.lineChart,
                isActive: state.showAduGraph,
                onTap: () => ref.read(flatWizardProvider.notifier).toggleAduGraph(!state.showAduGraph),
                tooltip: 'ADU Graph',
              ),
              _ToggleButton(
                icon: LucideIcons.barChart3,
                isActive: state.showExposureTimeline,
                onTap: () => ref.read(flatWizardProvider.notifier).toggleExposureTimeline(!state.showExposureTimeline),
                tooltip: 'Exposure Timeline',
              ),
              if (state.mode == FlatWizardMode.skyFlats)
                _ToggleButton(
                  icon: LucideIcons.sunrise,
                  isActive: state.showSkyBrightness,
                  onTap: () => ref.read(flatWizardProvider.notifier).toggleSkyBrightness(!state.showSkyBrightness),
                  tooltip: 'Sky Brightness',
                ),
              _ToggleButton(
                icon: LucideIcons.layoutGrid,
                isActive: state.showFilterCards,
                onTap: () => ref.read(flatWizardProvider.notifier).toggleFilterCards(!state.showFilterCards),
                tooltip: 'Filter Cards',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Visualization content
          Expanded(
            child: Row(
              children: [
                if (state.showAduGraph)
                  Expanded(child: _AduConvergenceGraph(history: state.aduHistory)),
                if (state.showFilterCards)
                  Expanded(child: _FilterProgressCards(state: state)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final String tooltip;

  const _ToggleButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return NightshadeTooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: isActive ? colors.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? colors.primary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _AduConvergenceGraph extends StatelessWidget {
  final List<AduMeasurement> history;

  const _AduConvergenceGraph({required this.history});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ADU Convergence',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const Spacer(),
          // TODO: Actual graph using fl_chart or custom painter
          Center(
            child: Text(
              history.isEmpty ? 'No data' : '${history.length} measurements',
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _FilterProgressCards extends StatelessWidget {
  final FlatWizardState state;

  const _FilterProgressCards({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final enabledFilters = state.filterSettings.where((f) => f.enabled).toList();

    return Container(
      margin: const EdgeInsets.only(left: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: enabledFilters.length,
        itemBuilder: (context, index) {
          final filter = enabledFilters[index];
          return _FilterCard(
            filter: filter,
            globalFrameCount: state.globalSettings.frameCount,
          );
        },
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  final FlatFilterSettings filter;
  final int globalFrameCount;

  const _FilterCard({
    required this.filter,
    required this.globalFrameCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final frameCount = filter.frameCountOverride ?? globalFrameCount;
    final progress = frameCount > 0 ? filter.capturedCount / frameCount : 0.0;

    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: filter.status == FilterCalibrationStatus.capturing
              ? colors.primary
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            filter.filterName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            filter.calibratedExposure != null
                ? '${filter.calibratedExposure!.toStringAsFixed(2)}s'
                : 'Not calibrated',
            style: TextStyle(
              fontSize: 10,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          NightshadeProgressBar(
            value: progress,
            height: 4,
          ),
          const SizedBox(height: 2),
          Text(
            '${filter.capturedCount}/$frameCount',
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Phase 5: Save Path Dialog

### Task 5.1: Create Save Path Dialog

**Files:**
- Create: `packages/nightshade_app/lib/screens/flat_wizard/widgets/save_path_dialog.dart`

**Step 1: Create the dialog**

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class SavePathDialog extends ConsumerStatefulWidget {
  final String? currentPath;
  final bool createDateSubfolder;
  final bool createFilterSubfolders;

  const SavePathDialog({
    super.key,
    this.currentPath,
    this.createDateSubfolder = true,
    this.createFilterSubfolders = true,
  });

  static Future<SavePathResult?> show(
    BuildContext context, {
    String? currentPath,
    bool createDateSubfolder = true,
    bool createFilterSubfolders = true,
  }) {
    return showDialog<SavePathResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SavePathDialog(
        currentPath: currentPath,
        createDateSubfolder: createDateSubfolder,
        createFilterSubfolders: createFilterSubfolders,
      ),
    );
  }

  @override
  ConsumerState<SavePathDialog> createState() => _SavePathDialogState();
}

class _SavePathDialogState extends ConsumerState<SavePathDialog> {
  late TextEditingController _pathController;
  late bool _createDateSubfolder;
  late bool _createFilterSubfolders;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.currentPath ?? '');
    _createDateSubfolder = widget.createDateSubfolder;
    _createFilterSubfolders = widget.createFilterSubfolders;
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _browsePath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select save location for flat frames',
      initialDirectory: _pathController.text.isNotEmpty ? _pathController.text : null,
    );

    if (result != null) {
      setState(() {
        _pathController.text = result;
      });
    }
  }

  void _confirm() {
    if (_pathController.text.isEmpty) return;

    Navigator.of(context).pop(SavePathResult(
      path: _pathController.text,
      createDateSubfolder: _createDateSubfolder,
      createFilterSubfolders: _createFilterSubfolders,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.folderOpen,
                    color: colors.warning,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Save Location Required',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose where to save your flat frames',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Path input
            Row(
              children: [
                Expanded(
                  child: NightshadeTextField(
                    controller: _pathController,
                    hintText: 'Select a folder...',
                    prefixIcon: LucideIcons.folder,
                  ),
                ),
                const SizedBox(width: 12),
                NightshadeButton(
                  onPressed: _browsePath,
                  variant: NightshadeButtonVariant.secondary,
                  child: const Text('Browse...'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Options
            _OptionCheckbox(
              value: _createDateSubfolder,
              onChanged: (v) => setState(() => _createDateSubfolder = v ?? true),
              label: 'Create date subfolder automatically',
              description: 'e.g., /2026-01-07/',
              colors: colors,
            ),
            const SizedBox(height: 12),
            _OptionCheckbox(
              value: _createFilterSubfolders,
              onChanged: (v) => setState(() => _createFilterSubfolders = v ?? true),
              label: 'Create filter subfolders',
              description: 'e.g., /L/, /R/, /G/, /B/',
              colors: colors,
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NightshadeButton(
                  onPressed: () => Navigator.of(context).pop(),
                  variant: NightshadeButtonVariant.ghost,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                NightshadeButton(
                  onPressed: _pathController.text.isNotEmpty ? _confirm : null,
                  child: const Text('Continue'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  final String description;
  final NightshadeColors colors;

  const _OptionCheckbox({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.description,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: colors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavePathResult {
  final String path;
  final bool createDateSubfolder;
  final bool createFilterSubfolders;

  SavePathResult({
    required this.path,
    required this.createDateSubfolder,
    required this.createFilterSubfolders,
  });
}
```

---

## Phase 6: Main Screen Rewrite

### Task 6.1: Create New Flat Wizard Screen

**Files:**
- Rewrite: `packages/nightshade_app/lib/screens/flat_wizard/flat_wizard_screen.dart`

This is the largest task - the full screen rewrite. Due to length, I'll provide the structure and key components.

**Step 1: Create the main screen structure**

The new screen should:
1. Use `FlatWizardSplitView` for the layout
2. Have a `TabBar` for Quick/Batch/Sky Flats modes
3. Pass the appropriate controls panel based on selected tab
4. Always show `FlatPreviewPanel` on the right
5. Check for save path before starting capture

Key structure:
```dart
class FlatWizardScreen extends ConsumerStatefulWidget {
  // ...
}

class _FlatWizardScreenState extends ConsumerState<FlatWizardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Screen header with title
        _buildHeader(),

        // Tab bar for mode selection
        _buildTabBar(),

        // Split view content
        Expanded(
          child: FlatWizardSplitView(
            controlsPanel: _buildControlsPanel(),
            previewPanel: const FlatPreviewPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildControlsPanel() {
    return TabBarView(
      controller: _tabController,
      children: [
        _QuickCaptureControls(),
        _BatchCaptureControls(),
        _SkyFlatsControls(),
      ],
    );
  }
}
```

---

## Remaining Tasks (Summary)

Due to the extensive nature of this redesign, here are the remaining tasks in summary form:

### Task 6.2-6.4: Controls Panels
- Create `_QuickCaptureControls` widget with histogram target slider, tolerance, exposure limits, test/auto-tune/start buttons
- Create `_BatchCaptureControls` widget with filter checklist, presets, global settings, per-filter overrides, filter ordering
- Create `_SkyFlatsControls` widget extending batch with twilight mode, sky brightness indicator, timing display

### Task 7.1-7.3: Capture Logic Integration
- Wire up start capture to check save path first (show dialog if not set)
- Implement capture loop with progress updates to state
- Implement rate-tracking for sky flats mode
- Record successful calibrations to history database

### Task 8.1-8.2: Visualizations
- Implement ADU convergence graph using `fl_chart` or custom `CustomPainter`
- Implement sky brightness trend graph for sky flats

### Task 9.1: Testing
- Test database migration
- Test algorithm convergence
- Test UI state management

---

## Execution Notes

This plan is large. Recommended approach:
1. Complete Phase 1 (Database) first - this is foundational
2. Complete Phase 2 (Algorithm) - independent of UI
3. Complete Phases 3-5 (UI Foundation) in order
4. Phase 6 (Main Screen Rewrite) is the integration phase

Each phase can be tested independently before moving to the next.
