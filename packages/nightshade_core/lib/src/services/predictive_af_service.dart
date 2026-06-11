// Predictive autofocus that learns per-filter slope across sessions.
//
// This service is the Dart side of the persisted predictive-AF subsystem.
// It mirrors the Rust [`PersistedFocusModel`] schema/math (in
// `native/nightshade_native/sequencer/src/focus_prediction.rs`) so the model
// can be evaluated synchronously on the hot path without hopping over FRB,
// while still letting Rust drive in-process predictions inside the sequencer.
//
// Storage: a single `focus_models` row per (equipment_profile_id, filter_name).
// The `training_samples_json` blob holds the rolling N-sample regression
// window. Confidence (R²) gates whether a caller can skip a real AF sweep.
//
// File ownership: this service does not touch the existing
// [FocusModelService] (which keeps its JSON-file storage for backwards
// compat). The two coexist: [FocusModelService] is the *legacy*, profile-
// scoped, in-app working set used by the equipment screen scatter plot;
// [PredictiveAfService] is the *persisted, per-filter* model that drives
// cross-session learning, drift detection, and confidence gating.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart' as db;
import '../providers/database_provider.dart';

/// A single (temperature, focus_position) training sample. Mirrors the Rust
/// `FocusTrainingSample` JSON layout exactly so the same blob can be read
/// from either side.
class FocusTrainingSample {
  /// Unix seconds the sample was captured.
  final int timestampSecs;
  final double temperatureCelsius;
  final int focusPosition;
  final double hfr;

  const FocusTrainingSample({
    required this.timestampSecs,
    required this.temperatureCelsius,
    required this.focusPosition,
    required this.hfr,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'ts': timestampSecs,
    'temp': temperatureCelsius,
    'position': focusPosition,
    'hfr': hfr,
  };

  factory FocusTrainingSample.fromJson(Map<String, dynamic> json) =>
      FocusTrainingSample(
        timestampSecs: (json['ts'] as num).toInt(),
        temperatureCelsius: (json['temp'] as num).toDouble(),
        focusPosition: (json['position'] as num).toInt(),
        hfr: (json['hfr'] as num).toDouble(),
      );
}

/// User-tunable thresholds for the predictive-AF gates. Defaults match the
/// Rust [`PredictiveAfConfig`] and are persisted in `app_settings` so the
/// settings screen can mutate them.
class PredictiveAfConfig {
  /// Toggle for the whole feature. When `false`, the service does not
  /// gate AF runs at all — it still records samples on success so the
  /// model can warm up.
  final bool enabled;

  /// Minimum number of *unique-temperature* samples required before the
  /// model is allowed to make a "trust" decision.
  final int minSamplesForTrust;

  /// R² ≥ this → apply prediction directly.
  final double highConfidenceThreshold;

  /// R² < this → force a real autofocus sweep.
  final double lowConfidenceThreshold;

  /// Dampened-band floor for the correction factor.
  final double minCorrectionFactor;

  /// Focus-position delta (steps) that counts as a "bad" prediction for
  /// drift tracking.
  final int driftThresholdSteps;

  /// Consecutive bad predictions required before the service surfaces a
  /// re-train recommendation.
  final int driftRunsBeforeWarn;

  const PredictiveAfConfig({
    this.enabled = true,
    this.minSamplesForTrust = 8,
    this.highConfidenceThreshold = 0.8,
    this.lowConfidenceThreshold = 0.5,
    this.minCorrectionFactor = 0.4,
    this.driftThresholdSteps = 200,
    this.driftRunsBeforeWarn = 5,
  });

  PredictiveAfConfig copyWith({
    bool? enabled,
    int? minSamplesForTrust,
    double? highConfidenceThreshold,
    double? lowConfidenceThreshold,
    double? minCorrectionFactor,
    int? driftThresholdSteps,
    int? driftRunsBeforeWarn,
  }) {
    return PredictiveAfConfig(
      enabled: enabled ?? this.enabled,
      minSamplesForTrust: minSamplesForTrust ?? this.minSamplesForTrust,
      highConfidenceThreshold:
          highConfidenceThreshold ?? this.highConfidenceThreshold,
      lowConfidenceThreshold:
          lowConfidenceThreshold ?? this.lowConfidenceThreshold,
      minCorrectionFactor: minCorrectionFactor ?? this.minCorrectionFactor,
      driftThresholdSteps: driftThresholdSteps ?? this.driftThresholdSteps,
      driftRunsBeforeWarn: driftRunsBeforeWarn ?? this.driftRunsBeforeWarn,
    );
  }
}

/// Compact projection of a [db.FocusModelEntry] for UI consumption.
class FilterFocusModel {
  final String uuid;
  final int? equipmentProfileId;
  final String filterName;
  final int? filterIndex;
  final double slopeStepsPerC;
  final int focusOffsetRelativeToLum;
  final int interceptAtReferenceTemp;
  final double referenceTempCelsius;
  final DateTime lastTrainedAt;
  final int trainingRunCount;
  final double confidenceScore;
  final DateTime? lastUsedAt;
  final List<FocusTrainingSample> samples;
  final int maxTrainingSamples;
  final int consecutiveBadPredictions;
  final int accumulatedDriftSteps;

  const FilterFocusModel({
    required this.uuid,
    required this.equipmentProfileId,
    required this.filterName,
    required this.filterIndex,
    required this.slopeStepsPerC,
    required this.focusOffsetRelativeToLum,
    required this.interceptAtReferenceTemp,
    required this.referenceTempCelsius,
    required this.lastTrainedAt,
    required this.trainingRunCount,
    required this.confidenceScore,
    required this.lastUsedAt,
    required this.samples,
    required this.maxTrainingSamples,
    required this.consecutiveBadPredictions,
    required this.accumulatedDriftSteps,
  });

  /// Predict focus position at a given temperature using the persisted
  /// slope + intercept (relative to the stored reference temperature).
  int predictPosition(double temperatureCelsius) {
    final delta = temperatureCelsius - referenceTempCelsius;
    return (interceptAtReferenceTemp + slopeStepsPerC * delta).round();
  }

  /// Export the full model + samples as a JSON blob (used by "Save my
  /// focus model for filter Ha as JSON" UI action).
  Map<String, dynamic> toExportJson() => <String, dynamic>{
    'schema': 'nightshade.focus_model.v1',
    'uuid': uuid,
    'filter_name': filterName,
    'filter_index': filterIndex,
    'slope_steps_per_c': slopeStepsPerC,
    'focus_offset_relative_to_lum': focusOffsetRelativeToLum,
    'intercept_at_reference_temp': interceptAtReferenceTemp,
    'reference_temp_celsius': referenceTempCelsius,
    'last_trained_at': lastTrainedAt.toIso8601String(),
    'training_run_count': trainingRunCount,
    'confidence_score': confidenceScore,
    'last_used_at': lastUsedAt?.toIso8601String(),
    'samples': samples.map((s) => s.toJson()).toList(),
    'max_training_samples': maxTrainingSamples,
  };
}

/// Confidence-gated decision returned by
/// [PredictiveAfService.evaluateForFilter]. Mirrors the Rust
/// [`PredictiveAfDecision`] enum.
sealed class PredictiveAfDecision {
  const PredictiveAfDecision();

  /// The focus position the caller should send to the focuser, or `null`
  /// when the model says "you must run a real sweep from current position".
  int? get targetPosition;

  /// Confidence (R²) backing the decision. `null` for [InsufficientData].
  double? get confidence;
}

class InsufficientData extends PredictiveAfDecision {
  final String reason;
  const InsufficientData(this.reason);
  @override
  int? get targetPosition => null;
  @override
  double? get confidence => null;
}

class ForceAutofocus extends PredictiveAfDecision {
  final int suggestedPosition;
  @override
  final double confidence;
  const ForceAutofocus({
    required this.suggestedPosition,
    required this.confidence,
  });
  @override
  int? get targetPosition => suggestedPosition;
}

class ApplyDampened extends PredictiveAfDecision {
  final int predictedPosition;
  final double correctionFactor;
  @override
  final double confidence;
  const ApplyDampened({
    required this.predictedPosition,
    required this.correctionFactor,
    required this.confidence,
  });
  @override
  int? get targetPosition => predictedPosition;
}

class ApplyDirect extends PredictiveAfDecision {
  final int predictedPosition;
  @override
  final double confidence;
  const ApplyDirect({
    required this.predictedPosition,
    required this.confidence,
  });
  @override
  int? get targetPosition => predictedPosition;
}

/// Result of feeding an actual autofocus outcome back into the model. The
/// service surfaces [DriftStatus] objects via [PredictiveAfService.driftEvents]
/// so a notification listener can pick them up.
sealed class DriftStatus {
  final int? equipmentProfileId;
  final String filterName;
  const DriftStatus({
    required this.equipmentProfileId,
    required this.filterName,
  });
}

class WithinTolerance extends DriftStatus {
  final int deltaSteps;
  const WithinTolerance({
    required super.equipmentProfileId,
    required super.filterName,
    required this.deltaSteps,
  });
}

class Drifting extends DriftStatus {
  final int deltaSteps;
  final int consecutiveBadRuns;
  final int accumulatedDriftSteps;
  const Drifting({
    required super.equipmentProfileId,
    required super.filterName,
    required this.deltaSteps,
    required this.consecutiveBadRuns,
    required this.accumulatedDriftSteps,
  });
}

class ShouldWarn extends DriftStatus {
  final int consecutiveBadRuns;
  final int accumulatedDriftSteps;
  final String message;
  const ShouldWarn({
    required super.equipmentProfileId,
    required super.filterName,
    required this.consecutiveBadRuns,
    required this.accumulatedDriftSteps,
    required this.message,
  });
}

/// The service.
///
/// Public surface:
///   * [recordAutofocusOutcome] — call after every successful AF run.
///   * [evaluateForFilter] — pre-AF gate: should the sequencer apply the
///     prediction, dampen it, or force a real sweep?
///   * [recordPredictionVsActual] — post-AF: feed the actual converged
///     position back so drift tracking can surface re-train prompts.
///   * [getModel] / [listModels] / [exportModel] / [importModel] — UI.
///   * [clearSamples] — the "Re-train" button (clears samples but keeps
///     the row + lifetime counter).
class PredictiveAfService {
  final db.NightshadeDatabase _db;
  PredictiveAfConfig _config;

  final _driftController = StreamController<DriftStatus>.broadcast();

  PredictiveAfService(this._db, {PredictiveAfConfig? config})
    : _config = config ?? const PredictiveAfConfig();

  // The getter/setter pair (rather than a plain field) is intentional:
  // it gives external code a stable API surface while leaving room for
  // future side effects (e.g. emitting an event when thresholds change).
  // ignore: unnecessary_getters_setters
  PredictiveAfConfig get config => _config;

  /// Set new gate thresholds. Already-recorded samples / drift counters
  /// are unaffected — only future [evaluateForFilter] calls see the new
  /// config.
  // ignore: unnecessary_getters_setters
  set config(PredictiveAfConfig value) {
    _config = value;
  }

  /// Stream of drift detection events. Listen here to surface
  /// notifications in the UI.
  Stream<DriftStatus> get driftEvents => _driftController.stream;

  Future<void> dispose() async {
    await _driftController.close();
  }

  // ── Sample recording ──────────────────────────────────────────────────

  /// Append a sample from a freshly-completed autofocus run, capping the
  /// window to `maxTrainingSamples` (default 50). Re-fits the regression
  /// and updates the stored slope/intercept/confidence.
  ///
  /// Returns the updated [FilterFocusModel]. If the regression cannot be
  /// computed yet (fewer than 3 unique-temperature samples) the slope is
  /// 0 and confidence is 0 — the row still exists so the UI can show
  /// "Building..." status.
  Future<FilterFocusModel> recordAutofocusOutcome({
    required int? equipmentProfileId,
    required String filterName,
    int? filterIndex,
    required double temperatureCelsius,
    required int focusPosition,
    required double hfr,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    final existing = await _loadByKey(equipmentProfileId, filterName);
    final samples = <FocusTrainingSample>[
      ...?existing?['samples'] as List<FocusTrainingSample>?,
      FocusTrainingSample(
        timestampSecs: now.millisecondsSinceEpoch ~/ 1000,
        temperatureCelsius: temperatureCelsius,
        focusPosition: focusPosition,
        hfr: hfr,
      ),
    ];
    final maxSamples = (existing?['max_training_samples'] as int?) ?? 50;
    if (samples.length > maxSamples) {
      final indexedSamples = <MapEntry<int, FocusTrainingSample>>[
        for (var i = 0; i < samples.length; i++) MapEntry(i, samples[i]),
      ];
      indexedSamples.sort((a, b) {
        final byTimestamp = a.value.timestampSecs.compareTo(
          b.value.timestampSecs,
        );
        return byTimestamp != 0 ? byTimestamp : a.key.compareTo(b.key);
      });
      samples
        ..clear()
        ..addAll(
          indexedSamples
              .skip(indexedSamples.length - maxSamples)
              .map((entry) => entry.value),
        );
    }

    final regression = _fitRegression(samples);
    final slope = regression?.slope ?? 0.0;
    final referenceTemp = regression?.referenceTemp ?? temperatureCelsius;
    final intercept = regression?.intercept.round() ?? focusPosition;
    final rSquared = regression?.rSquared ?? 0.0;

    if (existing == null) {
      await _db.customStatement(
        '''
        INSERT INTO focus_models (
          uuid, equipment_profile_id, filter_name, filter_index,
          temperature_compensation_slope, focus_offset_relative_to_lum,
          intercept_at_reference_temp, reference_temp_celsius,
          last_trained_at, training_run_count, confidence_score,
          last_used_at, training_samples_json, max_training_samples,
          consecutive_bad_predictions, accumulated_drift_steps,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, 1, ?, NULL, ?, ?, 0, 0, ?, ?)
        ''',
        <Object?>[
          _generateUuid(),
          equipmentProfileId,
          filterName,
          filterIndex,
          slope,
          intercept,
          referenceTemp,
          now.millisecondsSinceEpoch ~/ 1000,
          rSquared,
          jsonEncode(samples.map((s) => s.toJson()).toList()),
          maxSamples,
          now.millisecondsSinceEpoch ~/ 1000,
          now.millisecondsSinceEpoch ~/ 1000,
        ],
      );
    } else {
      await _db.customStatement(
        '''
        UPDATE focus_models SET
          filter_index = COALESCE(?, filter_index),
          temperature_compensation_slope = ?,
          intercept_at_reference_temp = ?,
          reference_temp_celsius = ?,
          last_trained_at = ?,
          training_run_count = training_run_count + 1,
          confidence_score = ?,
          training_samples_json = ?,
          updated_at = ?
        WHERE equipment_profile_id IS ? AND filter_name = ?
        ''',
        <Object?>[
          filterIndex,
          slope,
          intercept,
          referenceTemp,
          now.millisecondsSinceEpoch ~/ 1000,
          rSquared,
          jsonEncode(samples.map((s) => s.toJson()).toList()),
          now.millisecondsSinceEpoch ~/ 1000,
          equipmentProfileId,
          filterName,
        ],
      );
    }

    // Re-load to get the canonical row (so callers see exactly what's in DB).
    final fetched = await getModel(
      equipmentProfileId: equipmentProfileId,
      filterName: filterName,
    );
    return fetched!;
  }

  // ── Prediction gate ───────────────────────────────────────────────────

  /// Should the caller skip the AF sweep and trust the learned model?
  /// Updates `last_used_at` as a side effect so the UI can show staleness.
  Future<PredictiveAfDecision> evaluateForFilter({
    required int? equipmentProfileId,
    required String filterName,
    required double temperatureCelsius,
  }) async {
    final model = await getModel(
      equipmentProfileId: equipmentProfileId,
      filterName: filterName,
    );
    if (model == null) {
      return const InsufficientData('No focus model stored for this filter');
    }
    // Update last_used_at to "now". We don't await — the predict path is
    // performance-sensitive and the timestamp is purely informational.
    unawaited(_touchLastUsed(equipmentProfileId, filterName));

    if (!_config.enabled) {
      // Feature toggled off — surface a deterministic ForceAutofocus so
      // callers still get the prediction for UI display, but always run
      // a real sweep.
      return ForceAutofocus(
        suggestedPosition: model.predictPosition(temperatureCelsius),
        confidence: model.confidenceScore,
      );
    }

    final samples = model.samples;
    if (samples.length < 3 || model.confidenceScore == 0.0) {
      return InsufficientData(
        'Need at least 3 unique-temperature samples (have ${samples.length})',
      );
    }

    final predicted = model.predictPosition(temperatureCelsius);

    if (samples.length < _config.minSamplesForTrust) {
      return ForceAutofocus(
        suggestedPosition: predicted,
        confidence: model.confidenceScore,
      );
    }

    if (model.confidenceScore < _config.lowConfidenceThreshold) {
      return ForceAutofocus(
        suggestedPosition: predicted,
        confidence: model.confidenceScore,
      );
    }

    if (model.confidenceScore >= _config.highConfidenceThreshold) {
      return ApplyDirect(
        predictedPosition: predicted,
        confidence: model.confidenceScore,
      );
    }

    // Dampened band: linearly interpolate the correction factor.
    final band = math.max(
      _config.highConfidenceThreshold - _config.lowConfidenceThreshold,
      1e-6,
    );
    final t = ((model.confidenceScore - _config.lowConfidenceThreshold) / band)
        .clamp(0.0, 1.0);
    final correction =
        _config.minCorrectionFactor + t * (1.0 - _config.minCorrectionFactor);
    return ApplyDampened(
      predictedPosition: predicted,
      correctionFactor: correction,
      confidence: model.confidenceScore,
    );
  }

  // ── Drift tracking ────────────────────────────────────────────────────

  /// After a real AF run completes, call this with what the model predicted
  /// (BEFORE the AF) and the actual converged position. Updates the drift
  /// counters and, when the threshold is crossed, emits a [ShouldWarn]
  /// event on [driftEvents] AND returns it from this method.
  Future<DriftStatus> recordPredictionVsActual({
    required int? equipmentProfileId,
    required String filterName,
    required int predictedPosition,
    required int actualPosition,
  }) async {
    final model = await getModel(
      equipmentProfileId: equipmentProfileId,
      filterName: filterName,
    );
    if (model == null) {
      // No model to drift-track — pretend it's a healthy run so the caller
      // doesn't need to special-case the null path.
      final status = WithinTolerance(
        equipmentProfileId: equipmentProfileId,
        filterName: filterName,
        deltaSteps: actualPosition - predictedPosition,
      );
      _driftController.add(status);
      return status;
    }

    final delta = actualPosition - predictedPosition;
    final absDelta = delta.abs();

    if (absDelta <= _config.driftThresholdSteps) {
      // Good run — reset drift counters.
      await _db.customStatement(
        'UPDATE focus_models SET consecutive_bad_predictions = 0, '
        'accumulated_drift_steps = 0, updated_at = ? '
        'WHERE equipment_profile_id IS ? AND filter_name = ?',
        <Object?>[
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          equipmentProfileId,
          filterName,
        ],
      );
      final status = WithinTolerance(
        equipmentProfileId: equipmentProfileId,
        filterName: filterName,
        deltaSteps: delta,
      );
      _driftController.add(status);
      return status;
    }

    final newConsecutive = model.consecutiveBadPredictions + 1;
    final newAccumulated = model.accumulatedDriftSteps + absDelta;
    await _db.customStatement(
      'UPDATE focus_models SET consecutive_bad_predictions = ?, '
      'accumulated_drift_steps = ?, updated_at = ? '
      'WHERE equipment_profile_id IS ? AND filter_name = ?',
      <Object?>[
        newConsecutive,
        newAccumulated,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        equipmentProfileId,
        filterName,
      ],
    );

    if (newConsecutive >= _config.driftRunsBeforeWarn) {
      final msg =
          'Your $filterName filter focus model has drifted by '
          '$newAccumulated steps over the last $newConsecutive runs. '
          'Consider re-training (clear samples and start fresh).';
      developer.log(
        'Predictive AF drift warning for $filterName: $msg',
        name: 'PredictiveAfService',
        level: 900,
      );
      final status = ShouldWarn(
        equipmentProfileId: equipmentProfileId,
        filterName: filterName,
        consecutiveBadRuns: newConsecutive,
        accumulatedDriftSteps: newAccumulated,
        message: msg,
      );
      _driftController.add(status);
      return status;
    }

    final status = Drifting(
      equipmentProfileId: equipmentProfileId,
      filterName: filterName,
      deltaSteps: delta,
      consecutiveBadRuns: newConsecutive,
      accumulatedDriftSteps: newAccumulated,
    );
    _driftController.add(status);
    return status;
  }

  // ── Queries ───────────────────────────────────────────────────────────

  Future<FilterFocusModel?> getModel({
    required int? equipmentProfileId,
    required String filterName,
  }) async {
    final raw = await _loadByKey(equipmentProfileId, filterName);
    if (raw == null) return null;
    return _rawToModel(raw);
  }

  /// List every model for a profile, ordered by most-recently-used.
  Future<List<FilterFocusModel>> listModels({int? equipmentProfileId}) async {
    final query = equipmentProfileId == null
        ? _db.customSelect(
            'SELECT * FROM focus_models WHERE equipment_profile_id IS NULL '
            'ORDER BY COALESCE(last_used_at, last_trained_at) DESC',
          )
        : _db.customSelect(
            'SELECT * FROM focus_models WHERE equipment_profile_id = ? '
            'ORDER BY COALESCE(last_used_at, last_trained_at) DESC',
            variables: [Variable.withInt(equipmentProfileId)],
          );
    final rows = await query.get();
    return rows.map((r) => _rawToModel(_rowToMap(r))!).toList();
  }

  /// Export a single model as a portable JSON string.
  Future<String?> exportModel({
    required int? equipmentProfileId,
    required String filterName,
  }) async {
    final model = await getModel(
      equipmentProfileId: equipmentProfileId,
      filterName: filterName,
    );
    if (model == null) return null;
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(model.toExportJson());
  }

  /// Import a JSON blob previously produced by [exportModel]. Overwrites
  /// any existing model with the same `(profile_id, filter_name)` key.
  Future<FilterFocusModel> importModel({
    required int? equipmentProfileId,
    required String jsonBlob,
  }) async {
    final parsed = jsonDecode(jsonBlob) as Map<String, dynamic>;
    final schema = parsed['schema'];
    if (schema != 'nightshade.focus_model.v1') {
      throw FormatException('Unsupported focus_model export schema: $schema');
    }
    final filterName = parsed['filter_name'] as String;
    final filterIndex = parsed['filter_index'] as int?;
    final slope = (parsed['slope_steps_per_c'] as num).toDouble();
    final intercept = (parsed['intercept_at_reference_temp'] as num).toInt();
    final refTemp = (parsed['reference_temp_celsius'] as num).toDouble();
    final lastTrained = DateTime.parse(
      parsed['last_trained_at'] as String,
    ).toUtc();
    final trainingRunCount = (parsed['training_run_count'] as num).toInt();
    final confidence = (parsed['confidence_score'] as num).toDouble();
    final maxSamples = (parsed['max_training_samples'] as num?)?.toInt() ?? 50;
    final samples = (parsed['samples'] as List<dynamic>)
        .map((s) => FocusTrainingSample.fromJson(s as Map<String, dynamic>))
        .toList();

    // Delete existing, then insert.
    await _db.customStatement(
      'DELETE FROM focus_models WHERE equipment_profile_id IS ? AND filter_name = ?',
      <Object?>[equipmentProfileId, filterName],
    );
    final now = DateTime.now();
    await _db.customStatement(
      '''
      INSERT INTO focus_models (
        uuid, equipment_profile_id, filter_name, filter_index,
        temperature_compensation_slope, focus_offset_relative_to_lum,
        intercept_at_reference_temp, reference_temp_celsius,
        last_trained_at, training_run_count, confidence_score,
        last_used_at, training_samples_json, max_training_samples,
        consecutive_bad_predictions, accumulated_drift_steps,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, NULL, ?, ?, 0, 0, ?, ?)
      ''',
      <Object?>[
        parsed['uuid'] as String? ?? _generateUuid(),
        equipmentProfileId,
        filterName,
        filterIndex,
        slope,
        intercept,
        refTemp,
        lastTrained.millisecondsSinceEpoch ~/ 1000,
        trainingRunCount,
        confidence,
        jsonEncode(samples.map((s) => s.toJson()).toList()),
        maxSamples,
        now.millisecondsSinceEpoch ~/ 1000,
        now.millisecondsSinceEpoch ~/ 1000,
      ],
    );
    return (await getModel(
      equipmentProfileId: equipmentProfileId,
      filterName: filterName,
    ))!;
  }

  /// Wipe training samples for one (profile, filter) — the "Re-train"
  /// button in the model viewer. Keeps the lifetime counter intact so the
  /// UI can show "this model has been re-trained N times".
  Future<void> clearSamples({
    required int? equipmentProfileId,
    required String filterName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.customStatement(
      '''
      UPDATE focus_models SET
        training_samples_json = '[]',
        temperature_compensation_slope = 0.0,
        intercept_at_reference_temp = 0,
        confidence_score = 0.0,
        consecutive_bad_predictions = 0,
        accumulated_drift_steps = 0,
        last_trained_at = ?,
        updated_at = ?
      WHERE equipment_profile_id IS ? AND filter_name = ?
      ''',
      <Object?>[now, now, equipmentProfileId, filterName],
    );
  }

  /// Delete the row entirely (full forget). Used when a profile is being
  /// rebuilt from scratch.
  Future<void> deleteModel({
    required int? equipmentProfileId,
    required String filterName,
  }) async {
    await _db.customStatement(
      'DELETE FROM focus_models WHERE equipment_profile_id IS ? AND filter_name = ?',
      <Object?>[equipmentProfileId, filterName],
    );
  }

  /// Update the per-filter retention cap. Trimming, if needed, happens on
  /// the next `recordAutofocusOutcome` call.
  Future<void> setMaxSamples({
    required int? equipmentProfileId,
    required String filterName,
    required int maxSamples,
  }) async {
    final clamped = maxSamples.clamp(5, 200);
    await _db.customStatement(
      'UPDATE focus_models SET max_training_samples = ?, updated_at = ? '
      'WHERE equipment_profile_id IS ? AND filter_name = ?',
      <Object?>[
        clamped,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        equipmentProfileId,
        filterName,
      ],
    );
  }

  // ── Internals ─────────────────────────────────────────────────────────

  Future<void> _touchLastUsed(
    int? equipmentProfileId,
    String filterName,
  ) async {
    await _db.customStatement(
      'UPDATE focus_models SET last_used_at = ?, updated_at = ? '
      'WHERE equipment_profile_id IS ? AND filter_name = ?',
      <Object?>[
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        equipmentProfileId,
        filterName,
      ],
    );
  }

  Future<Map<String, dynamic>?> _loadByKey(
    int? equipmentProfileId,
    String filterName,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM focus_models WHERE equipment_profile_id IS ? AND filter_name = ?',
          variables: <Variable<Object>>[
            if (equipmentProfileId != null)
              Variable.withInt(equipmentProfileId)
            else
              const Variable<Object>(null),
            Variable.withString(filterName),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    return _rowToMap(rows.first);
  }

  Map<String, dynamic> _rowToMap(dynamic row) {
    // QueryRow has a `.data` Map<String, Object?>.
    final data = (row.data as Map).cast<String, Object?>();
    final samplesJson = data['training_samples_json'] as String? ?? '[]';
    final samples = (jsonDecode(samplesJson) as List<dynamic>)
        .map((s) => FocusTrainingSample.fromJson(s as Map<String, dynamic>))
        .toList();
    return <String, dynamic>{...data, 'samples': samples};
  }

  FilterFocusModel? _rawToModel(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    return FilterFocusModel(
      uuid: raw['uuid'] as String,
      equipmentProfileId: raw['equipment_profile_id'] as int?,
      filterName: raw['filter_name'] as String,
      filterIndex: raw['filter_index'] as int?,
      slopeStepsPerC: (raw['temperature_compensation_slope'] as num).toDouble(),
      focusOffsetRelativeToLum: (raw['focus_offset_relative_to_lum'] as num)
          .toInt(),
      interceptAtReferenceTemp: (raw['intercept_at_reference_temp'] as num)
          .toInt(),
      referenceTempCelsius: (raw['reference_temp_celsius'] as num).toDouble(),
      lastTrainedAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['last_trained_at'] as num).toInt() * 1000,
        isUtc: true,
      ),
      trainingRunCount: (raw['training_run_count'] as num).toInt(),
      confidenceScore: (raw['confidence_score'] as num).toDouble(),
      lastUsedAt: raw['last_used_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (raw['last_used_at'] as num).toInt() * 1000,
              isUtc: true,
            ),
      samples: raw['samples'] as List<FocusTrainingSample>,
      maxTrainingSamples: (raw['max_training_samples'] as num).toInt(),
      consecutiveBadPredictions: (raw['consecutive_bad_predictions'] as num)
          .toInt(),
      accumulatedDriftSteps: (raw['accumulated_drift_steps'] as num).toInt(),
    );
  }

  /// Linear regression on the persisted sample window. Identical math to
  /// Rust's [`PersistedFocusModel::refit`] so both sides agree.
  _RegressionFit? _fitRegression(List<FocusTrainingSample> samples) {
    if (samples.length < 3) return null;

    // Bucket by 1°C, pick lowest-HFR sample in each bucket.
    final buckets = <int, List<FocusTrainingSample>>{};
    for (final s in samples) {
      final bucket = s.temperatureCelsius.round();
      buckets.putIfAbsent(bucket, () => []).add(s);
    }
    final best = <FocusTrainingSample>[];
    for (final entry in buckets.entries) {
      entry.value.sort((a, b) => a.hfr.compareTo(b.hfr));
      best.add(entry.value.first);
    }
    if (best.length < 3) return null;

    final n = best.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (final p in best) {
      final x = p.temperatureCelsius;
      final y = p.focusPosition.toDouble();
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }
    final denom = n * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-10) return null;

    final slope = (n * sumXY - sumX * sumY) / denom;
    final refTemp = sumX / n;
    // Why we store the intercept at refTemp (= mean of x) rather than at
    // 0°C: the regression line passes through (mean_x, mean_y) by
    // construction, so intercept_at_refTemp = mean_y. Storing this triple
    // (slope, refTemp, mean_y) is numerically more stable than the
    // 0°C-centered (slope, intercept) when temperatures span -10..+30 °C
    // — predictions never accumulate intercept * slope error away from
    // the data cluster.
    final interceptAtRef = sumY / n;

    final meanY = sumY / n;
    double ssTot = 0, ssRes = 0;
    for (final p in best) {
      final predicted =
          interceptAtRef + slope * (p.temperatureCelsius - refTemp);
      ssTot += math.pow(p.focusPosition - meanY, 2).toDouble();
      ssRes += math.pow(p.focusPosition - predicted, 2).toDouble();
    }
    final rSquared = ssTot > 0 ? (1.0 - ssRes / ssTot).clamp(0.0, 1.0) : 0.0;

    return _RegressionFit(
      slope: slope,
      intercept: interceptAtRef,
      referenceTemp: refTemp,
      rSquared: rSquared,
      sampleCount: best.length,
    );
  }

  String _generateUuid() {
    // Tiny RFC4122-ish v4: 16 random bytes hex-encoded with the standard
    // version + variant nibbles. We don't pull in `package:uuid` to keep
    // the service self-contained.
    final rnd = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final s = bytes.map(hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}

class _RegressionFit {
  final double slope;
  final double intercept;
  final double referenceTemp;
  final double rSquared;
  final int sampleCount;

  const _RegressionFit({
    required this.slope,
    required this.intercept,
    required this.referenceTemp,
    required this.rSquared,
    required this.sampleCount,
  });
}

/// Riverpod provider for the predictive AF service. Lives at the DB layer
/// so it can be reached from anywhere in the app.
final predictiveAfServiceProvider = Provider<PredictiveAfService>((ref) {
  final database = ref.watch(databaseProvider);
  final service = PredictiveAfService(database);
  ref.onDispose(() async {
    await service.dispose();
  });
  return service;
});

/// Last predictive-AF consultation, surfaced for the UI (focus model card).
///
/// The model previously trained and predicted entirely silently — the
/// operator had no way to see whether the model trusts itself for a filter,
/// what it predicted, or how the real sweep compared. Written by the
/// device-service AF path before (decision) and after (actual outcome) each
/// sweep.
class PredictiveAfStatus {
  final DateTime at;
  final String filterName;
  final PredictiveAfDecision decision;

  /// Best-focus position the real sweep converged to. Null until the sweep
  /// completes; stays null when the sweep failed.
  final int? actualPosition;

  const PredictiveAfStatus({
    required this.at,
    required this.filterName,
    required this.decision,
    this.actualPosition,
  });

  PredictiveAfStatus withActual(int actualPosition) => PredictiveAfStatus(
    at: at,
    filterName: filterName,
    decision: decision,
    actualPosition: actualPosition,
  );

  /// Short human label for the decision band.
  String get decisionLabel => switch (decision) {
    InsufficientData() => 'training',
    ForceAutofocus() => 'low confidence',
    ApplyDampened() => 'medium confidence',
    ApplyDirect() => 'high confidence',
  };

  /// Prediction error in steps once the sweep completed, when the model
  /// made a prediction at all.
  int? get predictionErrorSteps {
    final predicted = decision.targetPosition;
    final actual = actualPosition;
    if (predicted == null || actual == null) return null;
    return actual - predicted;
  }
}

/// See [PredictiveAfStatus].
final lastPredictiveAfStatusProvider = StateProvider<PredictiveAfStatus?>(
  (ref) => null,
);
