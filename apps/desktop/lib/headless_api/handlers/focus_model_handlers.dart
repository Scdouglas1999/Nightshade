import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

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
  void _logError(String message) =>
      _logger.error(message, source: 'FocusModelHandlers');

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
    try {
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
    } catch (e) {
      _logError('[API] Get focus data error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Add Focus Data Point
  // ===========================================================================

  /// POST /api/focus-model/add-point
  /// Add a focus data point (temperature, position, filter?)
  Future<Response> handleAddFocusPoint(Request request) async {
    _logInfo('[API] POST /api/focus-model/add-point');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return jsonBadRequest(
          {"error": "No active equipment profile. Load a profile first."},
        );
      }

      final payload = jsonDecode(await request.readAsString());

      // Required fields
      final temperature = payload['temperature'];
      final position = payload['position'];
      final hfr = payload['hfr'];

      if (temperature == null || position == null || hfr == null) {
        return jsonBadRequest(
          {"error": "Missing required fields: temperature, position, hfr"},
        );
      }

      final temperatureCelsius = (temperature as num).toDouble();
      final focusPosition =
          position is int ? position : int.parse(position.toString());
      final hfrValue = (hfr as num).toDouble();
      final filterName = payload['filter'] as String?;

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
    } catch (e) {
      _logError('[API] Add focus point error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Clear Focus Data
  // ===========================================================================

  /// DELETE /api/focus-model/clear
  /// Clear all data points
  Future<Response> handleClearFocusData(Request request) async {
    _logInfo('[API] DELETE /api/focus-model/clear');
    try {
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
    } catch (e) {
      _logError('[API] Clear focus data error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Focus Model
  // ===========================================================================

  /// GET /api/focus-model/model
  /// Get current focus model (slope, intercept, r-squared)
  Future<Response> handleGetFocusModel(Request request) async {
    _logInfo('[API] GET /api/focus-model/model');
    try {
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
    } catch (e) {
      _logError('[API] Get focus model error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
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
    try {
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
        return jsonBadRequest(
          {"error": "Missing required parameter: temperature"},
        );
      }

      final temperature = double.tryParse(tempParam);
      if (temperature == null) {
        return jsonBadRequest({"error": "Invalid temperature value"});
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
    } catch (e) {
      _logError('[API] Predict focus error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Filter Offsets
  // ===========================================================================

  /// GET /api/focus-model/filter-offsets
  /// Get per-filter focus offsets
  Future<Response> handleGetFilterOffsets(Request request) async {
    _logInfo('[API] GET /api/focus-model/filter-offsets');
    try {
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
    } catch (e) {
      _logError('[API] Get filter offsets error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Set Filter Offsets
  // ===========================================================================

  /// POST /api/focus-model/filter-offsets
  /// Set per-filter focus offsets
  Future<Response> handleSetFilterOffsets(Request request) async {
    _logInfo('[API] POST /api/focus-model/filter-offsets');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return jsonBadRequest(
          {"error": "No active equipment profile. Load a profile first."},
        );
      }

      final payload = jsonDecode(await request.readAsString());

      // Set reference filter if provided
      final referenceFilter = payload['referenceFilter'] as String?;
      if (referenceFilter != null) {
        await service.setReferenceFilter(profileId, referenceFilter);
      }

      // Process filter offsets
      // Note: The FocusModelService calculates offsets automatically from data points.
      // For manual offset setting, we need to add synthetic data points.
      final offsets = payload['offsets'] as Map<String, dynamic>?;
      if (offsets != null) {
        // Get current profile data to determine a reasonable base position
        final profileData = service.getProfileData(profileId);
        final basePosition =
            profileData?.temperatureModel?.intercept.round() ?? 10000;
        const baseTemp = 20.0; // Standard reference temperature

        // Add synthetic data points for each filter offset
        for (final entry in offsets.entries) {
          final filterName = entry.key;
          final offsetSteps = entry.value is int
              ? entry.value as int
              : int.parse(entry.value.toString());

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
    } catch (e) {
      _logError('[API] Set filter offsets error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Check Should Refocus
  // ===========================================================================

  /// GET /api/focus-model/should-refocus?currentTemp=X&lastFocusTemp=Y
  /// Check if autofocus should be triggered based on temperature drift
  Future<Response> handleShouldRefocus(Request request) async {
    _logInfo('[API] GET /api/focus-model/should-refocus');
    try {
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

      if (currentTempParam == null || lastFocusTempParam == null) {
        return jsonBadRequest({
          "error": "Missing required parameters: currentTemp, lastFocusTemp"
        });
      }

      final currentTemp = double.tryParse(currentTempParam);
      final lastFocusTemp = double.tryParse(lastFocusTempParam);
      final maxDriftSteps = double.tryParse(maxDriftParam ?? '50') ?? 50.0;

      if (currentTemp == null || lastFocusTemp == null) {
        return jsonBadRequest({"error": "Invalid temperature values"});
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
    } catch (e) {
      _logError('[API] Should refocus error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Export Focus Data
  // ===========================================================================

  /// GET /api/focus-model/export
  /// Export focus data as JSON
  Future<Response> handleExportFocusData(Request request) async {
    _logInfo('[API] GET /api/focus-model/export');
    try {
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
    } catch (e) {
      _logError('[API] Export focus data error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Import Focus Data
  // ===========================================================================

  /// POST /api/focus-model/import
  /// Import focus data from JSON
  Future<Response> handleImportFocusData(Request request) async {
    _logInfo('[API] POST /api/focus-model/import');
    try {
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
      } catch (_) {
        return jsonBadRequest({"error": "Invalid JSON data"});
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
    } catch (e) {
      _logError('[API] Import focus data error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }
}
