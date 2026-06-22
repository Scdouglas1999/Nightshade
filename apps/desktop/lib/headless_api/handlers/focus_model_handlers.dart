import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for focus model endpoints
///
/// These endpoints provide access to focus temperature compensation and filter offsets:
/// - Get/add/clear focus data points
/// - Get focus model (linear regression)
/// - Predict focus position for temperature
/// - Get/set per-filter focus offsets
///
/// Source-of-truth note (focus-model unification, 2026-06):
/// The `/predict` and `/should-refocus` endpoints are answered by the
/// DB-backed [PredictiveAfService] — the *same* per-filter model the live
/// run consults in `device_service/autofocus_controls.dart`. Previously these
/// two endpoints read the legacy JSON-backed [FocusModelService], so the HTTP
/// answer a SLAVE queried could disagree with the in-run refocus decision the
/// HOST actually made. Every other endpoint (data/model/filter-offsets/
/// export/import) still reads [FocusModelService] because it powers the
/// equipment scatter-plot UI surface; that read path is unchanged and is
/// scheduled for a later migration.
class FocusModelHandlers {
  final ProviderContainer container;
  bool _initialized = false;

  FocusModelHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'FocusModelHandlers');

  /// Ensure the focus model service is initialized
  Future<FocusModelService> _getInitializedService() async {
    final service = container.read(focusModelServiceProvider);
    if (!_initialized) {
      await service.initialize();
      _initialized = true;
    }
    return service;
  }

  /// Get the current profile ID from the active equipment profile.
  ///
  /// String form, keyed to the legacy [FocusModelService] storage (which
  /// scopes its on-disk JSON files by stringified profile id).
  String? _getActiveProfileId() {
    final activeProfile = container.read(activeEquipmentProfileProvider);
    return activeProfile?.id.toString();
  }

  /// The active profile's integer id, as keyed by [PredictiveAfService]
  /// (`equipment_profile_id` in the `focus_models` table). `null` is a valid
  /// key for the predictive model (the "no profile" bucket), so callers
  /// distinguish "no profile loaded" via [activeEquipmentProfileProvider]
  /// itself rather than a null id.
  int? _getActiveProfileIntId() {
    final activeProfile = container.read(activeEquipmentProfileProvider);
    return activeProfile?.id;
  }

  /// True when an equipment profile is loaded. The predictive-AF endpoints
  /// gate on this rather than on a null int id (id may legitimately be null).
  bool _hasActiveProfile() =>
      container.read(activeEquipmentProfileProvider) != null;

  PredictiveAfService get _predictiveAf =>
      container.read(predictiveAfServiceProvider);

  // ===========================================================================
  // Get Focus Data
  // ===========================================================================

  /// GET /api/focus-model/data
  /// Get all focus data points (temperature, position pairs)
  Future<Response> handleGetFocusData(Request request) async {
    _logInfo('[API] GET /api/focus-model/data');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }

    final profileData = service.getProfileData(profileId);
    if (profileData == null) {
      return jsonOk({"profileId": profileId, "dataPoints": [], "count": 0});
    }

    final dataPoints = profileData.dataPoints
        .map(
          (p) => {
            'timestamp': p.timestamp.toIso8601String(),
            'timestampEpoch': p.timestamp.millisecondsSinceEpoch,
            'temperature': p.temperatureCelsius,
            'position': p.focusPosition,
            'hfr': p.hfr,
            'filter': p.filterName,
          },
        )
        .toList();

    return jsonOk({
      "profileId": profileId,
      "dataPoints": dataPoints,
      "count": dataPoints.length,
      "referenceFilter": profileData.referenceFilter,
    });
  }

  // ===========================================================================
  // Add Focus Data Point
  // ===========================================================================

  /// POST /api/focus-model/add-point
  /// Add a focus data point (temperature, position, filter?)
  Future<Response> handleAddFocusPoint(Request request) async {
    _logInfo('[API] POST /api/focus-model/add-point');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }

    final payload = await readJsonObject(request);

    final temperatureCelsius = requireDouble(payload, 'temperature');
    final focusPosition = requireInt(payload, 'position');
    final hfrValue = requireDouble(payload, 'hfr');
    final filterName = optionalString(payload, 'filter');

    await service.addDataPoint(
      profileId: profileId,
      temperatureCelsius: temperatureCelsius,
      focusPosition: focusPosition,
      hfr: hfrValue,
      filterName: filterName,
    );

    // Get updated profile data
    final profileData = service.getProfileData(profileId);

    return jsonOk({
      "status": "ok",
      "profileId": profileId,
      "dataPointCount": profileData?.dataPoints.length ?? 0,
      "hasModel": profileData?.temperatureModel != null,
      "modelIsReliable": profileData?.temperatureModel?.isReliable ?? false,
    });
  }

  // ===========================================================================
  // Clear Focus Data
  // ===========================================================================

  /// DELETE /api/focus-model/clear
  /// Clear all data points
  Future<Response> handleClearFocusData(Request request) async {
    _logInfo('[API] DELETE /api/focus-model/clear');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }

    await service.clearProfileData(profileId);

    return jsonOk({
      "status": "ok",
      "profileId": profileId,
      "message": "Focus data cleared",
    });
  }

  // ===========================================================================
  // Get Focus Model
  // ===========================================================================

  /// GET /api/focus-model/model
  /// Get current focus model (slope, intercept, r-squared)
  Future<Response> handleGetFocusModel(Request request) async {
    _logInfo('[API] GET /api/focus-model/model');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }

    final profileData = service.getProfileData(profileId);
    final model = profileData?.temperatureModel;

    if (model == null) {
      return jsonOk({
        "profileId": profileId,
        "hasModel": false,
        "message":
            "Not enough data points to build model. Need at least 3 data points.",
        "dataPointCount": profileData?.dataPoints.length ?? 0,
      });
    }

    return jsonOk({
      "profileId": profileId,
      "hasModel": true,
      "model": {
        "slope": model.slope,
        "intercept": model.intercept,
        "rSquared": model.rSquared,
        "dataPointCount": model.dataPointCount,
        "lastUpdated": model.lastUpdated.toIso8601String(),
        "lastUpdatedEpoch": model.lastUpdated.millisecondsSinceEpoch,
        "isReliable": model.isReliable,
      },
      "description": _getModelDescription(model),
    });
  }

  /// Generate a human-readable description of the focus model
  String _getModelDescription(FocusModel model) {
    final slopeDir = model.slope > 0 ? 'increases' : 'decreases';
    final slopeAbs = model.slope.abs().toStringAsFixed(1);
    final reliability = model.isReliable ? 'reliable' : 'unreliable';
    final rSquaredPct = (model.rSquared * 100).toStringAsFixed(1);

    return 'Focus position $slopeDir by $slopeAbs steps per degree C. '
        'Model explains $rSquaredPct% of variance (${model.dataPointCount} data points). '
        'Model is $reliability for predictions.';
  }

  // ===========================================================================
  // Predict Focus Position
  // ===========================================================================

  /// GET /api/focus-model/predict?temperature=X&filter=Y
  /// Predict focus position for temperature.
  ///
  /// Answered by [PredictiveAfService] — the DB-backed per-filter model the
  /// live run consults — so the HTTP prediction matches the position the run
  /// would actually use. The predictive model is keyed per filter, so a
  /// `filter` query parameter is required to identify which learned model to
  /// evaluate; without it the endpoint reports `canPredict: false`. The
  /// response JSON shape is unchanged from the legacy implementation.
  Future<Response> handlePredictFocus(Request request) async {
    _logInfo('[API] GET /api/focus-model/predict');
    if (!_hasActiveProfile()) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }
    final profileId = _getActiveProfileId();
    final profileIntId = _getActiveProfileIntId();

    // Parse temperature
    final tempParam = request.url.queryParameters['temperature'];
    if (tempParam == null) {
      throw BadRequestError(
        field: 'temperature',
        expected: 'number',
        message: 'Missing required query parameter',
      );
    }

    final temperature = double.tryParse(tempParam);
    if (temperature == null) {
      throw BadRequestError(
        field: 'temperature',
        expected: 'number',
        message: 'Invalid temperature value',
      );
    }

    // The predictive model is per-filter; without a filter we cannot key it.
    final filter = request.url.queryParameters['filter'];
    if (filter == null) {
      return jsonOk({
        "profileId": profileId,
        "temperature": temperature,
        "filter": filter,
        "canPredict": false,
        "message":
            "Cannot make prediction. The predictive focus model is per-filter; "
            "supply a 'filter' query parameter.",
      });
    }

    // Consult the SAME gate the run uses (evaluateForFilter). The decision
    // tells us both the predicted position and whether the model is trusted.
    final decision = await _predictiveAf.evaluateForFilter(
      equipmentProfileId: profileIntId,
      filterName: filter,
      temperatureCelsius: temperature,
    );

    final position = decision.targetPosition;
    if (position == null) {
      // InsufficientData — no fitted model the run would trust.
      return jsonOk({
        "profileId": profileId,
        "temperature": temperature,
        "filter": filter,
        "canPredict": false,
        "message":
            "Cannot make prediction. Model not available or not reliable enough.",
      });
    }

    final confidence = decision.confidence ?? 0.0;
    return jsonOk({
      "profileId": profileId,
      "temperature": temperature,
      "filter": filter,
      "canPredict": true,
      "prediction": {
        "position": position,
        "confidence": confidence,
        "confidenceDescription": _confidenceDescription(confidence),
        "basedOnTemperature": temperature,
        // The predictive per-filter model bakes any per-filter shift into the
        // stored slope/intercept for that filter, so there is no separate
        // reference-relative offset to report here.
        "filterOffset": 0,
      },
    });
  }

  /// Human-readable confidence band. Mirrors the legacy
  /// `FocusPrediction.confidenceDescription` ladder so the JSON wording the
  /// slave renders is unchanged.
  String _confidenceDescription(double confidence) {
    if (confidence >= 0.9) return 'High';
    if (confidence >= 0.7) return 'Good';
    if (confidence >= 0.5) return 'Moderate';
    return 'Low';
  }

  // ===========================================================================
  // Get Filter Offsets
  // ===========================================================================

  /// GET /api/focus-model/filter-offsets
  /// Get per-filter focus offsets
  Future<Response> handleGetFilterOffsets(Request request) async {
    _logInfo('[API] GET /api/focus-model/filter-offsets');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }

    final profileData = service.getProfileData(profileId);
    if (profileData == null) {
      return jsonOk({
        "profileId": profileId,
        "referenceFilter": null,
        "offsets": {},
      });
    }

    final offsets = <String, dynamic>{};
    for (final entry in profileData.filterOffsets.entries) {
      final offset = entry.value;
      offsets[entry.key] = {
        'filterName': offset.filterName,
        'referenceFilter': offset.referenceFilter,
        'offsetSteps': offset.offsetSteps,
        'measurementCount': offset.measurementCount,
        'confidence': offset.confidence,
        // IMG-surface the confidence ladder so the UI can warn the
        // user when offsets are raw averages contaminated by temperature
        // drift instead of silently labelling them "high confidence".
        'confidenceBand': offset.confidenceBand.name,
        'confidenceReason': offset.confidenceReason,
        'temperatureCorrected': offset.temperatureCorrected,
      };
    }

    return jsonOk({
      "profileId": profileId,
      "referenceFilter": profileData.referenceFilter,
      "offsets": offsets,
    });
  }

  // ===========================================================================
  // Set Filter Offsets
  // ===========================================================================

  /// POST /api/focus-model/filter-offsets
  /// Set per-filter focus offsets
  Future<Response> handleSetFilterOffsets(Request request) async {
    _logInfo('[API] POST /api/focus-model/filter-offsets');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }

    final payload = await readJsonObject(request);

    // Set reference filter if provided
    final referenceFilter = optionalString(payload, 'referenceFilter');
    if (referenceFilter != null) {
      await service.setReferenceFilter(profileId, referenceFilter);
    }

    // Process filter offsets
    // Note: The FocusModelService calculates offsets automatically from data points.
    // For manual offset setting, we need to add synthetic data points.
    final offsets = optionalObject(payload, 'offsets');
    if (offsets != null) {
      // Get current profile data to determine a reasonable base position
      final profileData = service.getProfileData(profileId);
      final basePosition =
          profileData?.temperatureModel?.intercept.round() ?? 10000;
      const baseTemp = 20.0; // Standard reference temperature

      // Add synthetic data points for each filter offset
      for (final entry in offsets.entries) {
        final filterName = entry.key;
        // Why: validate per-entry value as integer through the same helper
        // used elsewhere; non-int values now produce 400 instead of a 500
        // from int.parse(toString()) on garbage.
        final offsetSteps = requireInt(offsets, filterName);

        // Add a synthetic data point for this filter
        await service.addDataPoint(
          profileId: profileId,
          temperatureCelsius: baseTemp,
          focusPosition: basePosition + offsetSteps,
          hfr: 2.0, // Use a good HFR value
          filterName: filterName,
        );
      }
    }

    // Get updated profile data
    final updatedData = service.getProfileData(profileId);

    return jsonOk({
      "status": "ok",
      "profileId": profileId,
      "referenceFilter": updatedData?.referenceFilter,
      "offsetCount": updatedData?.filterOffsets.length ?? 0,
    });
  }

  // ===========================================================================
  // Check Should Refocus
  // ===========================================================================

  /// GET /api/focus-model/should-refocus?currentTemp=X&lastFocusTemp=Y&filter=Z
  /// Check if autofocus should be triggered based on temperature drift.
  ///
  /// Answered by [PredictiveAfService] — the DB-backed per-filter model the
  /// live run consults — so the boolean a SLAVE reads here matches the gate
  /// the HOST run applies. The drift formula is identical to the legacy one
  /// (`|deltaT| * |slope| >= maxDriftSteps`), but the slope and the
  /// trust gate now come from the *run's* model. The trust gate mirrors
  /// `evaluateForFilter`: a decision the run treats as `InsufficientData`
  /// (no fitted regression / too few samples to trust) yields
  /// `shouldRefocus: false` just as the run would not act on it.
  ///
  /// The predictive model is per-filter, so an optional `filter` query
  /// parameter selects which learned model to consult. When omitted (or no
  /// model exists for that filter) the endpoint reports `hasModel: false`
  /// and `shouldRefocus: false`. The response JSON shape is unchanged.
  Future<Response> handleShouldRefocus(Request request) async {
    _logInfo('[API] GET /api/focus-model/should-refocus');
    if (!_hasActiveProfile()) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }
    final profileId = _getActiveProfileId();
    final profileIntId = _getActiveProfileIntId();

    // Parse parameters
    final currentTempParam = request.url.queryParameters['currentTemp'];
    final lastFocusTempParam = request.url.queryParameters['lastFocusTemp'];
    final maxDriftParam = request.url.queryParameters['maxDriftSteps'];

    if (currentTempParam == null) {
      throw BadRequestError(
        field: 'currentTemp',
        expected: 'number',
        message: 'Missing required query parameter',
      );
    }
    if (lastFocusTempParam == null) {
      throw BadRequestError(
        field: 'lastFocusTemp',
        expected: 'number',
        message: 'Missing required query parameter',
      );
    }

    final currentTemp = double.tryParse(currentTempParam);
    final lastFocusTemp = double.tryParse(lastFocusTempParam);
    final maxDriftSteps = double.tryParse(maxDriftParam ?? '50') ?? 50.0;

    if (currentTemp == null) {
      throw BadRequestError(
        field: 'currentTemp',
        expected: 'number',
        message: 'Invalid temperature value',
      );
    }
    if (lastFocusTemp == null) {
      throw BadRequestError(
        field: 'lastFocusTemp',
        expected: 'number',
        message: 'Invalid temperature value',
      );
    }

    final filter = request.url.queryParameters['filter'];

    final tempDelta = (currentTemp - lastFocusTemp).abs();
    final decision = await _shouldRefocusDecision(
      profileIntId: profileIntId,
      filter: filter,
      currentTemp: currentTemp,
      tempDelta: tempDelta,
      maxDriftSteps: maxDriftSteps,
    );

    return jsonOk({
      "profileId": profileId,
      "currentTemp": currentTemp,
      "lastFocusTemp": lastFocusTemp,
      "tempDelta": tempDelta,
      "maxDriftSteps": maxDriftSteps,
      "expectedDrift": decision.expectedDrift,
      "shouldRefocus": decision.shouldRefocus,
      "hasModel": decision.hasModel,
      "modelIsReliable": decision.modelIsReliable,
    });
  }

  /// Compute the refocus decision from the predictive per-filter model the
  /// run uses. Shared so a parity/contract test can assert the HTTP answer
  /// equals the run-time gate for identical inputs.
  ///
  /// `modelIsReliable` is true exactly when [PredictiveAfService.evaluateForFilter]
  /// returns a decision carrying a fitted prediction (i.e. NOT
  /// `InsufficientData`) — the same condition that lets the run trust the
  /// model. When the model is unreliable, `shouldRefocus` is forced false
  /// (the run would run a real sweep on its own schedule, not skip based on
  /// an untrusted drift estimate).
  Future<_RefocusDecision> _shouldRefocusDecision({
    required int? profileIntId,
    required String? filter,
    required double currentTemp,
    required double tempDelta,
    required double maxDriftSteps,
  }) async {
    if (filter == null) {
      return const _RefocusDecision(
        shouldRefocus: false,
        hasModel: false,
        modelIsReliable: false,
        expectedDrift: null,
      );
    }

    final model = await _predictiveAf.getModel(
      equipmentProfileId: profileIntId,
      filterName: filter,
    );
    if (model == null) {
      return const _RefocusDecision(
        shouldRefocus: false,
        hasModel: false,
        modelIsReliable: false,
        expectedDrift: null,
      );
    }

    final expectedDrift = tempDelta * model.slopeStepsPerC.abs();

    // Mirror the run's trust gate. evaluateForFilter returns InsufficientData
    // (targetPosition == null) when there is no fitted regression or too few
    // samples for the run to act on the model.
    final decision = await _predictiveAf.evaluateForFilter(
      equipmentProfileId: profileIntId,
      filterName: filter,
      temperatureCelsius: currentTemp,
    );
    final modelIsReliable = decision.targetPosition != null;

    return _RefocusDecision(
      shouldRefocus: modelIsReliable && expectedDrift >= maxDriftSteps,
      hasModel: true,
      modelIsReliable: modelIsReliable,
      expectedDrift: expectedDrift,
    );
  }

  // ===========================================================================
  // Export Focus Data
  // ===========================================================================

  /// GET /api/focus-model/export
  /// Export focus data as JSON
  Future<Response> handleExportFocusData(Request request) async {
    _logInfo('[API] GET /api/focus-model/export');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }

    final exportJson = service.exportData(profileId);

    return attachmentResponse(
      exportJson,
      fileName: 'focus_model_$profileId.json',
      contentType: jsonContentType,
    );
  }

  // ===========================================================================
  // Import Focus Data
  // ===========================================================================

  /// POST /api/focus-model/import
  /// Import focus data from JSON
  Future<Response> handleImportFocusData(Request request) async {
    _logInfo('[API] POST /api/focus-model/import');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest({
        "error": "No active equipment profile. Load a profile first.",
      });
    }

    final jsonData = await request.readAsString();

    // Validate JSON before importing
    try {
      jsonDecode(jsonData);
    } on FormatException catch (e) {
      throw BadRequestError(
        field: 'body',
        expected: 'valid_json',
        message: 'Malformed JSON: ${e.message}',
      );
    }

    await service.importData(profileId, jsonData);

    // Get updated profile data
    final profileData = service.getProfileData(profileId);

    return jsonOk({
      "status": "ok",
      "profileId": profileId,
      "dataPointCount": profileData?.dataPoints.length ?? 0,
      "hasModel": profileData?.temperatureModel != null,
      "modelIsReliable": profileData?.temperatureModel?.isReliable ?? false,
    });
  }
}

/// Outcome of the predictive-AF refocus gate, shared between the HTTP handler
/// and the parity test so both assert the exact same derivation.
class _RefocusDecision {
  final bool shouldRefocus;
  final bool hasModel;
  final bool modelIsReliable;
  final double? expectedDrift;

  const _RefocusDecision({
    required this.shouldRefocus,
    required this.hasModel,
    required this.modelIsReliable,
    required this.expectedDrift,
  });
}
