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

  /// Get the current profile ID from the active equipment profile
  String? _getActiveProfileId() {
    final activeProfile = container.read(activeEquipmentProfileProvider);
    return activeProfile?.id.toString();
  }

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
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
    }

    final profileData = service.getProfileData(profileId);
    if (profileData == null) {
      return jsonOk({
        "profileId": profileId,
        "dataPoints": [],
        "count": 0,
      });
    }

    final dataPoints = profileData.dataPoints
        .map((p) => {
              'timestamp': p.timestamp.toIso8601String(),
              'timestampEpoch': p.timestamp.millisecondsSinceEpoch,
              'temperature': p.temperatureCelsius,
              'position': p.focusPosition,
              'hfr': p.hfr,
              'filter': p.filterName,
            })
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
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
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
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
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
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
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

  /// GET /api/focus-model/predict?temperature=X
  /// Predict focus position for temperature
  Future<Response> handlePredictFocus(Request request) async {
    _logInfo('[API] GET /api/focus-model/predict');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
    }

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

    // Optional filter
    final filter = request.url.queryParameters['filter'];

    final prediction = service.predictFocusPosition(
      profileId: profileId,
      currentTemperature: temperature,
      currentFilter: filter,
    );

    if (prediction == null) {
      return jsonOk({
        "profileId": profileId,
        "temperature": temperature,
        "filter": filter,
        "canPredict": false,
        "message":
            "Cannot make prediction. Model not available or not reliable enough.",
      });
    }

    return jsonOk({
      "profileId": profileId,
      "temperature": temperature,
      "filter": filter,
      "canPredict": true,
      "prediction": {
        "position": prediction.position,
        "confidence": prediction.confidence,
        "confidenceDescription": prediction.confidenceDescription,
        "basedOnTemperature": prediction.basedOnTemperature,
        "filterOffset": prediction.filterOffset,
      },
    });
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
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
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
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
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

  /// GET /api/focus-model/should-refocus?currentTemp=X&lastFocusTemp=Y
  /// Check if autofocus should be triggered based on temperature drift
  Future<Response> handleShouldRefocus(Request request) async {
    _logInfo('[API] GET /api/focus-model/should-refocus');
    final service = await _getInitializedService();
    final profileId = _getActiveProfileId();

    if (profileId == null) {
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
    }

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

    final shouldRefocus = service.shouldRefocus(
      profileId: profileId,
      currentTemperature: currentTemp,
      lastFocusTemperature: lastFocusTemp,
      maxDriftSteps: maxDriftSteps,
    );

    // Calculate expected drift for information
    final profileData = service.getProfileData(profileId);
    final model = profileData?.temperatureModel;
    double? expectedDrift;
    if (model != null) {
      expectedDrift = (currentTemp - lastFocusTemp).abs() * model.slope.abs();
    }

    return jsonOk({
      "profileId": profileId,
      "currentTemp": currentTemp,
      "lastFocusTemp": lastFocusTemp,
      "tempDelta": (currentTemp - lastFocusTemp).abs(),
      "maxDriftSteps": maxDriftSteps,
      "expectedDrift": expectedDrift,
      "shouldRefocus": shouldRefocus,
      "hasModel": model != null,
      "modelIsReliable": model?.isReliable ?? false,
    });
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
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
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
      return jsonBadRequest(
        {"error": "No active equipment profile. Load a profile first."},
      );
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
