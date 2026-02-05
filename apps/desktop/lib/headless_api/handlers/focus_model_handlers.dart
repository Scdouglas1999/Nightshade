import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

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
    print('[API] GET /api/focus-model/data');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
        );
      }

      final profileData = service.getProfileData(profileId);
      if (profileData == null) {
        return Response.ok(
          jsonEncode({
            "profileId": profileId,
            "dataPoints": [],
            "count": 0,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final dataPoints = profileData.dataPoints.map((p) => {
        'timestamp': p.timestamp.toIso8601String(),
        'timestampEpoch': p.timestamp.millisecondsSinceEpoch,
        'temperature': p.temperatureCelsius,
        'position': p.focusPosition,
        'hfr': p.hfr,
        'filter': p.filterName,
      }).toList();

      return Response.ok(
        jsonEncode({
          "profileId": profileId,
          "dataPoints": dataPoints,
          "count": dataPoints.length,
          "referenceFilter": profileData.referenceFilter,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get focus data error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Add Focus Data Point
  // ===========================================================================

  /// POST /api/focus-model/add-point
  /// Add a focus data point (temperature, position, filter?)
  Future<Response> handleAddFocusPoint(Request request) async {
    print('[API] POST /api/focus-model/add-point');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
        );
      }

      final payload = jsonDecode(await request.readAsString());

      // Required fields
      final temperature = payload['temperature'];
      final position = payload['position'];
      final hfr = payload['hfr'];

      if (temperature == null || position == null || hfr == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Missing required fields: temperature, position, hfr"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final temperatureCelsius = (temperature as num).toDouble();
      final focusPosition = position is int ? position : int.parse(position.toString());
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

      return Response.ok(
        jsonEncode({
          "status": "ok",
          "profileId": profileId,
          "dataPointCount": profileData?.dataPoints.length ?? 0,
          "hasModel": profileData?.temperatureModel != null,
          "modelIsReliable": profileData?.temperatureModel?.isReliable ?? false,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Add focus point error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Clear Focus Data
  // ===========================================================================

  /// DELETE /api/focus-model/clear
  /// Clear all data points
  Future<Response> handleClearFocusData(Request request) async {
    print('[API] DELETE /api/focus-model/clear');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
        );
      }

      await service.clearProfileData(profileId);

      return Response.ok(
        jsonEncode({
          "status": "ok",
          "profileId": profileId,
          "message": "Focus data cleared",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Clear focus data error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Focus Model
  // ===========================================================================

  /// GET /api/focus-model/model
  /// Get current focus model (slope, intercept, r-squared)
  Future<Response> handleGetFocusModel(Request request) async {
    print('[API] GET /api/focus-model/model');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
        );
      }

      final profileData = service.getProfileData(profileId);
      final model = profileData?.temperatureModel;

      if (model == null) {
        return Response.ok(
          jsonEncode({
            "profileId": profileId,
            "hasModel": false,
            "message": "Not enough data points to build model. Need at least 3 data points.",
            "dataPointCount": profileData?.dataPoints.length ?? 0,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
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
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get focus model error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
    print('[API] GET /api/focus-model/predict');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Parse temperature
      final tempParam = request.url.queryParameters['temperature'];
      if (tempParam == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Missing required parameter: temperature"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final temperature = double.tryParse(tempParam);
      if (temperature == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid temperature value"}),
          headers: {'content-type': 'application/json'},
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
        return Response.ok(
          jsonEncode({
            "profileId": profileId,
            "temperature": temperature,
            "filter": filter,
            "canPredict": false,
            "message": "Cannot make prediction. Model not available or not reliable enough.",
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
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
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Predict focus error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Filter Offsets
  // ===========================================================================

  /// GET /api/focus-model/filter-offsets
  /// Get per-filter focus offsets
  Future<Response> handleGetFilterOffsets(Request request) async {
    print('[API] GET /api/focus-model/filter-offsets');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
        );
      }

      final profileData = service.getProfileData(profileId);
      if (profileData == null) {
        return Response.ok(
          jsonEncode({
            "profileId": profileId,
            "referenceFilter": null,
            "offsets": {},
          }),
          headers: {'content-type': 'application/json'},
        );
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

      return Response.ok(
        jsonEncode({
          "profileId": profileId,
          "referenceFilter": profileData.referenceFilter,
          "offsets": offsets,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get filter offsets error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Set Filter Offsets
  // ===========================================================================

  /// POST /api/focus-model/filter-offsets
  /// Set per-filter focus offsets
  Future<Response> handleSetFilterOffsets(Request request) async {
    print('[API] POST /api/focus-model/filter-offsets');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
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
        final basePosition = profileData?.temperatureModel?.intercept.round() ?? 10000;
        final baseTemp = 20.0; // Standard reference temperature

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

      return Response.ok(
        jsonEncode({
          "status": "ok",
          "profileId": profileId,
          "referenceFilter": updatedData?.referenceFilter,
          "offsetCount": updatedData?.filterOffsets.length ?? 0,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Set filter offsets error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Check Should Refocus
  // ===========================================================================

  /// GET /api/focus-model/should-refocus?currentTemp=X&lastFocusTemp=Y
  /// Check if autofocus should be triggered based on temperature drift
  Future<Response> handleShouldRefocus(Request request) async {
    print('[API] GET /api/focus-model/should-refocus');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Parse parameters
      final currentTempParam = request.url.queryParameters['currentTemp'];
      final lastFocusTempParam = request.url.queryParameters['lastFocusTemp'];
      final maxDriftParam = request.url.queryParameters['maxDriftSteps'];

      if (currentTempParam == null || lastFocusTempParam == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Missing required parameters: currentTemp, lastFocusTemp"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final currentTemp = double.tryParse(currentTempParam);
      final lastFocusTemp = double.tryParse(lastFocusTempParam);
      final maxDriftSteps = double.tryParse(maxDriftParam ?? '50') ?? 50.0;

      if (currentTemp == null || lastFocusTemp == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid temperature values"}),
          headers: {'content-type': 'application/json'},
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

      return Response.ok(
        jsonEncode({
          "profileId": profileId,
          "currentTemp": currentTemp,
          "lastFocusTemp": lastFocusTemp,
          "tempDelta": (currentTemp - lastFocusTemp).abs(),
          "maxDriftSteps": maxDriftSteps,
          "expectedDrift": expectedDrift,
          "shouldRefocus": shouldRefocus,
          "hasModel": model != null,
          "modelIsReliable": model?.isReliable ?? false,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Should refocus error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Export Focus Data
  // ===========================================================================

  /// GET /api/focus-model/export
  /// Export focus data as JSON
  Future<Response> handleExportFocusData(Request request) async {
    print('[API] GET /api/focus-model/export');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
        );
      }

      final exportJson = service.exportData(profileId);

      return Response.ok(
        exportJson,
        headers: {
          'content-type': 'application/json',
          'content-disposition': 'attachment; filename="focus_model_$profileId.json"',
        },
      );
    } catch (e) {
      print('[API] Export focus data error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Import Focus Data
  // ===========================================================================

  /// POST /api/focus-model/import
  /// Import focus data from JSON
  Future<Response> handleImportFocusData(Request request) async {
    print('[API] POST /api/focus-model/import');
    try {
      final service = await _getInitializedService();
      final profileId = _getActiveProfileId();

      if (profileId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No active equipment profile. Load a profile first."}),
          headers: {'content-type': 'application/json'},
        );
      }

      final jsonData = await request.readAsString();

      // Validate JSON before importing
      try {
        jsonDecode(jsonData);
      } catch (_) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid JSON data"}),
          headers: {'content-type': 'application/json'},
        );
      }

      await service.importData(profileId, jsonData);

      // Get updated profile data
      final profileData = service.getProfileData(profileId);

      return Response.ok(
        jsonEncode({
          "status": "ok",
          "profileId": profileId,
          "dataPointCount": profileData?.dataPoints.length ?? 0,
          "hasModel": profileData?.temperatureModel != null,
          "modelIsReliable": profileData?.temperatureModel?.isReliable ?? false,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Import focus data error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
