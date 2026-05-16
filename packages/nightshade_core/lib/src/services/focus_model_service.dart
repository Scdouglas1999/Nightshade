// ignore_for_file: unused_local_variable

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Provider for the focus model service
final focusModelServiceProvider = Provider<FocusModelService>((ref) {
  final service = FocusModelService();
  unawaited(service.initialize());
  return service;
});

/// A single temperature-compensation history sample collected after each
/// successful autofocus run. Persisted across sessions to feed the linear
/// regression model that predicts focus position from temperature.
///
/// Distinct from `FocusDataPoint` (in `models/backend/autofocus_result.dart`),
/// which represents a single sample on an in-progress autofocus V-curve.
class FocusHistoryPoint {
  final DateTime timestamp;
  final double temperatureCelsius;
  final int focusPosition;
  final double hfr;
  final String? filterName;

  FocusHistoryPoint({
    required this.timestamp,
    required this.temperatureCelsius,
    required this.focusPosition,
    required this.hfr,
    this.filterName,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'temperature': temperatureCelsius,
        'position': focusPosition,
        'hfr': hfr,
        'filter': filterName,
      };

  factory FocusHistoryPoint.fromJson(Map<String, dynamic> json) =>
      FocusHistoryPoint(
        timestamp: DateTime.parse(json['timestamp'] as String),
        temperatureCelsius: (json['temperature'] as num).toDouble(),
        focusPosition: json['position'] as int,
        hfr: (json['hfr'] as num).toDouble(),
        filterName: json['filter'] as String?,
      );
}

/// Linear regression result for temperature-focus correlation
class FocusModel {
  final double slope; // Steps per degree C
  final double intercept; // Base focus position at 0°C
  final double rSquared; // Correlation coefficient
  final int dataPointCount; // Number of points used
  final DateTime lastUpdated;

  FocusModel({
    required this.slope,
    required this.intercept,
    required this.rSquared,
    required this.dataPointCount,
    required this.lastUpdated,
  });

  /// Predict focus position for a given temperature
  int predictPosition(double temperatureCelsius) {
    return (intercept + slope * temperatureCelsius).round();
  }

  /// Check if model is reliable enough to use
  bool get isReliable => rSquared >= 0.7 && dataPointCount >= 5;

  Map<String, dynamic> toJson() => {
        'slope': slope,
        'intercept': intercept,
        'rSquared': rSquared,
        'dataPointCount': dataPointCount,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory FocusModel.fromJson(Map<String, dynamic> json) => FocusModel(
        slope: (json['slope'] as num).toDouble(),
        intercept: (json['intercept'] as num).toDouble(),
        rSquared: (json['rSquared'] as num).toDouble(),
        dataPointCount: json['dataPointCount'] as int,
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      );
}

/// Filter focus offset relative to a reference filter
class FilterOffset {
  final String filterName;
  final String referenceFilter;
  final int offsetSteps;
  final int measurementCount;
  final double confidence; // 0.0 to 1.0

  FilterOffset({
    required this.filterName,
    required this.referenceFilter,
    required this.offsetSteps,
    required this.measurementCount,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'filterName': filterName,
        'referenceFilter': referenceFilter,
        'offsetSteps': offsetSteps,
        'measurementCount': measurementCount,
        'confidence': confidence,
      };

  factory FilterOffset.fromJson(Map<String, dynamic> json) => FilterOffset(
        filterName: json['filterName'] as String,
        referenceFilter: json['referenceFilter'] as String,
        offsetSteps: json['offsetSteps'] as int,
        measurementCount: json['measurementCount'] as int,
        confidence: (json['confidence'] as num).toDouble(),
      );
}

/// Complete focus data for an equipment profile
class ProfileFocusData {
  final String profileId;
  final List<FocusHistoryPoint> dataPoints;
  final FocusModel? temperatureModel;
  final Map<String, FilterOffset> filterOffsets;
  final String? referenceFilter;

  ProfileFocusData({
    required this.profileId,
    this.dataPoints = const [],
    this.temperatureModel,
    this.filterOffsets = const {},
    this.referenceFilter,
  });

  ProfileFocusData copyWith({
    String? profileId,
    List<FocusHistoryPoint>? dataPoints,
    FocusModel? temperatureModel,
    Map<String, FilterOffset>? filterOffsets,
    String? referenceFilter,
  }) {
    return ProfileFocusData(
      profileId: profileId ?? this.profileId,
      dataPoints: dataPoints ?? this.dataPoints,
      temperatureModel: temperatureModel ?? this.temperatureModel,
      filterOffsets: filterOffsets ?? this.filterOffsets,
      referenceFilter: referenceFilter ?? this.referenceFilter,
    );
  }

  Map<String, dynamic> toJson() => {
        'profileId': profileId,
        'dataPoints': dataPoints.map((p) => p.toJson()).toList(),
        'temperatureModel': temperatureModel?.toJson(),
        'filterOffsets': filterOffsets.map((k, v) => MapEntry(k, v.toJson())),
        'referenceFilter': referenceFilter,
      };

  factory ProfileFocusData.fromJson(Map<String, dynamic> json) =>
      ProfileFocusData(
        profileId: json['profileId'] as String,
        dataPoints: (json['dataPoints'] as List<dynamic>?)
                ?.map((p) => FocusHistoryPoint.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        temperatureModel: json['temperatureModel'] != null
            ? FocusModel.fromJson(
                json['temperatureModel'] as Map<String, dynamic>)
            : null,
        filterOffsets: (json['filterOffsets'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(
                    k, FilterOffset.fromJson(v as Map<String, dynamic>))) ??
            {},
        referenceFilter: json['referenceFilter'] as String?,
      );
}

/// Service for managing focus models and predictions
class FocusModelService {
  final Map<String, ProfileFocusData> _profileData = {};
  String? _storageDir;
  Future<void>? _initializeFuture;
  bool _isInitialized = false;

  /// Initialize storage directory
  Future<void> initialize() async {
    if (_isInitialized) return;
    _initializeFuture ??= _initializeInternal();
    await _initializeFuture;
  }

  Future<void> _initializeInternal() async {
    final appDir = await getApplicationDocumentsDirectory();
    _storageDir = '${appDir.path}/Nightshade/focus_models';
    await Directory(_storageDir!).create(recursive: true);
    await _loadAllProfiles();
    _isInitialized = true;
  }

  /// Get focus data for a profile
  ProfileFocusData? getProfileData(String profileId) {
    return _profileData[profileId];
  }

  /// Add a focus data point from an autofocus run
  Future<void> addDataPoint({
    required String profileId,
    required double temperatureCelsius,
    required int focusPosition,
    required double hfr,
    String? filterName,
  }) async {
    await initialize();
    final point = FocusHistoryPoint(
      timestamp: DateTime.now(),
      temperatureCelsius: temperatureCelsius,
      focusPosition: focusPosition,
      hfr: hfr,
      filterName: filterName,
    );

    var data =
        _profileData[profileId] ?? ProfileFocusData(profileId: profileId);
    final newPoints = [...data.dataPoints, point];

    // Keep only last 100 points to avoid unbounded growth
    if (newPoints.length > 100) {
      newPoints.removeRange(0, newPoints.length - 100);
    }

    data = data.copyWith(dataPoints: newPoints);

    // Recalculate temperature model
    final model = _calculateTemperatureModel(newPoints);
    if (model != null) {
      data = data.copyWith(temperatureModel: model);
    } else {
      data = data.copyWith(temperatureModel: null);
    }

    // Update filter offsets if we have a reference filter
    if (filterName != null && data.referenceFilter != null) {
      final offsets = _updateFilterOffsets(newPoints, data.referenceFilter!);
      data = data.copyWith(filterOffsets: offsets);
    }

    _profileData[profileId] = data;
    await _saveProfile(profileId);
  }

  /// Calculate linear regression model for temperature vs focus position
  FocusModel? _calculateTemperatureModel(List<FocusHistoryPoint> points) {
    if (points.length < 3) return null;

    // Use only the best HFR point per temperature range
    // Group by temperature buckets (1°C)
    final buckets = <int, List<FocusHistoryPoint>>{};
    for (final point in points) {
      final bucket = point.temperatureCelsius.round();
      buckets.putIfAbsent(bucket, () => []).add(point);
    }

    // Take best (lowest HFR) from each bucket
    final bestPoints = <FocusHistoryPoint>[];
    for (final bucket in buckets.values) {
      bucket.sort((a, b) => a.hfr.compareTo(b.hfr));
      bestPoints.add(bucket.first);
    }

    if (bestPoints.length < 3) return null;

    // Linear regression: y = mx + b
    // where y = focus position, x = temperature
    final n = bestPoints.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;

    for (final point in bestPoints) {
      final x = point.temperatureCelsius;
      final y = point.focusPosition.toDouble();
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
      sumY2 += y * y;
    }

    final denominator = n * sumX2 - sumX * sumX;
    if (denominator.abs() < 1e-9) {
      return null;
    }

    final slope = (n * sumXY - sumX * sumY) / denominator;
    if (slope.abs() > 500) {
      developer.log(
          'Rejecting focus model with unrealistic slope ${slope.toStringAsFixed(2)} steps/°C',
          name: 'FocusModelService',
          level: 900);
      return null;
    }
    final intercept = (sumY - slope * sumX) / n;

    // Calculate R-squared
    final meanY = sumY / n;
    double ssTot = 0, ssRes = 0;
    for (final point in bestPoints) {
      final predicted = intercept + slope * point.temperatureCelsius;
      ssTot += math.pow(point.focusPosition - meanY, 2);
      ssRes += math.pow(point.focusPosition - predicted, 2);
    }

    final rSquared = ssTot > 0 ? 1.0 - (ssRes / ssTot) : 0.0;

    return FocusModel(
      slope: slope,
      intercept: intercept,
      rSquared: rSquared,
      dataPointCount: bestPoints.length,
      lastUpdated: DateTime.now(),
    );
  }

  /// Update filter offsets based on collected data
  Map<String, FilterOffset> _updateFilterOffsets(
    List<FocusHistoryPoint> points,
    String referenceFilter,
  ) {
    final offsets = <String, FilterOffset>{};

    // Group by filter
    final byFilter = <String, List<FocusHistoryPoint>>{};
    for (final point in points) {
      if (point.filterName != null) {
        byFilter.putIfAbsent(point.filterName!, () => []).add(point);
      }
    }

    // Get reference filter data
    final refPoints = byFilter[referenceFilter];
    if (refPoints == null || refPoints.isEmpty) return offsets;

    // Calculate average position for reference at various temperatures
    final refAvg =
        refPoints.map((p) => p.focusPosition).reduce((a, b) => a + b) /
            refPoints.length;

    // Calculate offsets for each filter
    for (final entry in byFilter.entries) {
      if (entry.key == referenceFilter) continue;

      final filterPoints = entry.value;
      if (filterPoints.isEmpty) continue;

      // Calculate average position for this filter
      final filterAvg =
          filterPoints.map((p) => p.focusPosition).reduce((a, b) => a + b) /
              filterPoints.length;

      final offsetSteps = (filterAvg - refAvg).round();

      // Confidence based on measurement count and consistency
      final variance = filterPoints
              .map((p) => math.pow(p.focusPosition - filterAvg, 2))
              .reduce((a, b) => a + b) /
          filterPoints.length;
      final stdDev = math.sqrt(variance);
      final consistency = stdDev < 50 ? 1.0 : 50 / stdDev;
      final countFactor = math.min(filterPoints.length / 5.0, 1.0);
      final confidence = (consistency * countFactor).clamp(0.0, 1.0);

      offsets[entry.key] = FilterOffset(
        filterName: entry.key,
        referenceFilter: referenceFilter,
        offsetSteps: offsetSteps,
        measurementCount: filterPoints.length,
        confidence: confidence,
      );
    }

    return offsets;
  }

  /// Predict optimal focus position based on current conditions
  FocusPrediction? predictFocusPosition({
    required String profileId,
    required double currentTemperature,
    String? currentFilter,
  }) {
    final data = _profileData[profileId];
    if (data == null || data.temperatureModel == null) return null;

    final model = data.temperatureModel!;
    if (!model.isReliable) return null;

    int predictedPosition = model.predictPosition(currentTemperature);
    double confidence = model.rSquared;

    // Apply filter offset if applicable
    int filterOffset = 0;
    if (currentFilter != null &&
        data.filterOffsets.containsKey(currentFilter)) {
      final offset = data.filterOffsets[currentFilter]!;
      if (offset.confidence >= 0.5) {
        filterOffset = offset.offsetSteps;
        predictedPosition += filterOffset;
        confidence *= offset.confidence;
      }
    }

    return FocusPrediction(
      position: predictedPosition,
      confidence: confidence,
      basedOnTemperature: currentTemperature,
      filterOffset: filterOffset,
      model: model,
    );
  }

  /// Check if autofocus should be triggered based on temperature drift
  bool shouldRefocus({
    required String profileId,
    required double currentTemperature,
    required double lastFocusTemperature,
    double maxDriftSteps = 50.0,
  }) {
    final data = _profileData[profileId];
    if (data == null || data.temperatureModel == null) return false;

    final model = data.temperatureModel!;
    if (!model.isReliable) return false;

    // Calculate expected focus drift
    final tempDelta = (currentTemperature - lastFocusTemperature).abs();
    final expectedDrift = tempDelta * model.slope.abs();

    return expectedDrift >= maxDriftSteps;
  }

  /// Set the reference filter for offset calculations
  Future<void> setReferenceFilter(String profileId, String filterName) async {
    await initialize();
    var data = _profileData[profileId];
    if (data == null) return;

    data = data.copyWith(referenceFilter: filterName);

    // Recalculate offsets with new reference
    final offsets = _updateFilterOffsets(data.dataPoints, filterName);
    data = data.copyWith(filterOffsets: offsets);

    _profileData[profileId] = data;
    await _saveProfile(profileId);
  }

  /// Directly update filter offsets for a profile and persist to disk.
  ///
  /// This is used by the FilterOffsetNotifier when the user manually
  /// adjusts filter offsets in the UI.
  Future<void> updateFilterOffsets(
    String profileId,
    Map<String, FilterOffset> offsets, {
    String? referenceFilter,
  }) async {
    await initialize();
    var data =
        _profileData[profileId] ?? ProfileFocusData(profileId: profileId);

    data = data.copyWith(
      filterOffsets: offsets,
      referenceFilter: referenceFilter ?? data.referenceFilter,
    );

    _profileData[profileId] = data;
    await _saveProfile(profileId);
  }

  /// Clear focus data for a profile
  Future<void> clearProfileData(String profileId) async {
    await initialize();
    _profileData.remove(profileId);
    if (_storageDir != null) {
      final file = File('$_storageDir/$profileId.json');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Export focus data
  String exportData(String profileId) {
    final data = _profileData[profileId];
    if (data == null) return '{}';
    return jsonEncode(data.toJson());
  }

  /// Import focus data
  Future<void> importData(String profileId, String jsonData) async {
    await initialize();
    final json = jsonDecode(jsonData) as Map<String, dynamic>;
    final data = ProfileFocusData.fromJson(json);
    _profileData[profileId] = data;
    await _saveProfile(profileId);
  }

  Future<void> _saveProfile(String profileId) async {
    if (_storageDir == null) return;

    final data = _profileData[profileId];
    if (data == null) return;

    final file = File('$_storageDir/$profileId.json');
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  Future<void> _loadAllProfiles() async {
    if (_storageDir == null) return;

    final dir = Directory(_storageDir!);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final data = ProfileFocusData.fromJson(json);
          _profileData[data.profileId] = data;
        } catch (e) {
          // Log corrupted files but continue loading others
          developer.log(
              'FocusModelService: Skipping corrupted focus data file ${entity.path}: $e',
              name: 'FocusModelService',
              level: 900,
              error: e);
        }
      }
    }
  }
}

/// Result of focus position prediction
class FocusPrediction {
  final int position;
  final double confidence;
  final double basedOnTemperature;
  final int filterOffset;
  final FocusModel model;

  FocusPrediction({
    required this.position,
    required this.confidence,
    required this.basedOnTemperature,
    required this.filterOffset,
    required this.model,
  });

  /// Get a human-readable confidence description
  String get confidenceDescription {
    if (confidence >= 0.9) return 'High';
    if (confidence >= 0.7) return 'Good';
    if (confidence >= 0.5) return 'Moderate';
    return 'Low';
  }
}
