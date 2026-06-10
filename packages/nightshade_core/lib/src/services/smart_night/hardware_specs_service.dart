import 'dart:math' as math;

import 'exposure_calculator.dart';

/// Per-gain camera sensor values used by the Smart Night exposure model.
class CameraGainPoint {
  final int gain;
  final double readNoiseE;
  final double fullWellE;

  const CameraGainPoint({
    required this.gain,
    required this.readNoiseE,
    required this.fullWellE,
  });

  factory CameraGainPoint.fromJson(Map<String, dynamic> json) {
    return CameraGainPoint(
      gain: _intValue(json['gain'], 'gain'),
      readNoiseE: _doubleValue(json['readNoiseE'], 'readNoiseE'),
      fullWellE: _doubleValue(json['fullWellE'], 'fullWellE'),
    );
  }

  Map<String, dynamic> toJson() => {
    'gain': gain,
    'readNoiseE': readNoiseE,
    'fullWellE': fullWellE,
  };
}

/// Bundled camera metadata. This is intentionally small and deterministic;
/// the service boundary lets us replace the catalog with JSON/remote specs
/// without changing the exposure callers.
class CameraHardwareSpec {
  final String model;
  final List<String> aliases;
  final double pixelSizeMicrons;
  final double qePeak;
  final int defaultGain;
  final List<CameraGainPoint> gainPoints;

  const CameraHardwareSpec({
    required this.model,
    this.aliases = const [],
    required this.pixelSizeMicrons,
    required this.qePeak,
    required this.defaultGain,
    required this.gainPoints,
  });

  factory CameraHardwareSpec.fromJson(Map<String, dynamic> json) {
    final gainPointsJson = json['gainPoints'];
    if (gainPointsJson is! List || gainPointsJson.isEmpty) {
      throw const FormatException('Camera spec requires gainPoints');
    }
    final aliasesJson = json['aliases'];
    return CameraHardwareSpec(
      model: _stringValue(json['model'], 'model'),
      aliases: aliasesJson is List
          ? aliasesJson.map((value) => value.toString()).toList()
          : const [],
      pixelSizeMicrons: _doubleValue(
        json['pixelSizeMicrons'],
        'pixelSizeMicrons',
      ),
      qePeak: _doubleValue(json['qePeak'], 'qePeak'),
      defaultGain: _intValue(json['defaultGain'], 'defaultGain'),
      gainPoints: gainPointsJson
          .map(
            (value) => CameraGainPoint.fromJson(
              (value as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'model': model,
    'aliases': aliases,
    'pixelSizeMicrons': pixelSizeMicrons,
    'qePeak': qePeak,
    'defaultGain': defaultGain,
    'gainPoints': gainPoints.map((point) => point.toJson()).toList(),
  };
}

class CameraHardwareMatch {
  final CameraHardwareSpec spec;
  final String matchedName;
  final CameraExposureSpec exposureSpec;
  final double pixelSizeMicrons;

  const CameraHardwareMatch({
    required this.spec,
    required this.matchedName,
    required this.exposureSpec,
    required this.pixelSizeMicrons,
  });
}

class HardwareSpecsService {
  static const cameraOverridesSettingKey =
      'smart_night.hardware.camera_overrides.v1';

  final List<CameraHardwareSpec> _cameraOverrides;
  final List<CameraHardwareSpec> _cameraCatalog;

  const HardwareSpecsService({
    List<CameraHardwareSpec> cameraOverrides = const [],
    List<CameraHardwareSpec> cameraCatalog = _defaultCameraCatalog,
  }) : _cameraOverrides = cameraOverrides,
       _cameraCatalog = cameraCatalog;

  HardwareSpecsService withCameraOverrides(
    List<CameraHardwareSpec> cameraOverrides,
  ) {
    return HardwareSpecsService(
      cameraOverrides: cameraOverrides,
      cameraCatalog: _cameraCatalog,
    );
  }

  static List<CameraHardwareSpec> cameraOverridesFromJson(Object? decoded) {
    if (decoded == null) return const [];
    if (decoded is! List) {
      throw const FormatException('Camera hardware overrides must be a list');
    }
    return decoded
        .map(
          (value) => CameraHardwareSpec.fromJson(
            (value as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
  }

  CameraHardwareMatch? matchCamera({
    String? cameraName,
    String? cameraId,
    int? gain,
  }) {
    final candidates = [cameraName, cameraId]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    _CameraCatalogHit? best;
    for (final candidate in candidates) {
      final normalizedCandidate = _normalize(candidate);
      if (normalizedCandidate.isEmpty) continue;
      for (final spec in [..._cameraOverrides, ..._cameraCatalog]) {
        final names = [spec.model, ...spec.aliases];
        for (final name in names) {
          final normalizedName = _normalize(name);
          if (normalizedName.isEmpty) continue;
          final score = _matchScore(normalizedCandidate, normalizedName);
          if (score == null) continue;
          final hit = _CameraCatalogHit(
            spec: spec,
            matchedName: name,
            score: score,
          );
          if (best == null || hit.score < best.score) {
            best = hit;
          }
        }
      }
    }

    if (best == null) return null;
    final point = _gainPointFor(best.spec, gain ?? best.spec.defaultGain);
    return CameraHardwareMatch(
      spec: best.spec,
      matchedName: best.matchedName,
      pixelSizeMicrons: best.spec.pixelSizeMicrons,
      exposureSpec: CameraExposureSpec(
        readNoiseE: point.readNoiseE,
        fullWellE: point.fullWellE,
        qePeak: best.spec.qePeak,
      ),
    );
  }

  static int? _matchScore(String candidate, String catalogName) {
    if (candidate == catalogName) return 0;
    if (candidate.length >= 6 &&
        catalogName.length >= 6 &&
        (candidate.contains(catalogName) || catalogName.contains(candidate))) {
      return 1;
    }
    final distance = _levenshtein(candidate, catalogName);
    if (distance <= 3) return distance + 2;
    return null;
  }

  static CameraGainPoint _gainPointFor(CameraHardwareSpec spec, int gain) {
    final points = [...spec.gainPoints]
      ..sort((a, b) => a.gain.compareTo(b.gain));
    for (final point in points) {
      if (point.gain == gain) return point;
    }
    if (gain <= points.first.gain) return points.first;
    if (gain >= points.last.gain) return points.last;

    for (var i = 0; i < points.length - 1; i++) {
      final lower = points[i];
      final upper = points[i + 1];
      if (gain > lower.gain && gain < upper.gain) {
        final t = (gain - lower.gain) / (upper.gain - lower.gain);
        return CameraGainPoint(
          gain: gain,
          readNoiseE: _lerp(lower.readNoiseE, upper.readNoiseE, t),
          fullWellE: _lerp(lower.fullWellE, upper.fullWellE, t),
        );
      }
    }

    return points.reduce(
      (a, b) => (gain - a.gain).abs() <= (gain - b.gain).abs() ? a : b,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '')
      .replaceAll('colour', 'color');

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final substitutionCost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = math.min(
          math.min(current[j] + 1, previous[j + 1] + 1),
          previous[j] + substitutionCost,
        );
      }
      previous = current;
    }
    return previous.last;
  }
}

class _CameraCatalogHit {
  final CameraHardwareSpec spec;
  final String matchedName;
  final int score;

  const _CameraCatalogHit({
    required this.spec,
    required this.matchedName,
    required this.score,
  });
}

String _stringValue(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('Camera spec requires $field');
}

int _intValue(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.round();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Camera spec requires numeric $field');
}

double _doubleValue(Object? value, String field) {
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed.isFinite) return parsed;
  }
  throw FormatException('Camera spec requires numeric $field');
}

const _defaultCameraCatalog = [
  CameraHardwareSpec(
    model: 'ZWO ASI2600MM Pro',
    aliases: ['ASI2600MM', 'ASI2600MM Pro', 'ZWO ASI2600MM'],
    pixelSizeMicrons: 3.76,
    qePeak: 0.91,
    defaultGain: 100,
    gainPoints: [
      CameraGainPoint(gain: 0, readNoiseE: 3.5, fullWellE: 50000),
      CameraGainPoint(gain: 100, readNoiseE: 1.5, fullWellE: 18700),
    ],
  ),
  CameraHardwareSpec(
    model: 'ZWO ASI2600MC Pro',
    aliases: ['ASI2600MC', 'ASI2600MC Pro', 'ZWO ASI2600MC'],
    pixelSizeMicrons: 3.76,
    qePeak: 0.80,
    defaultGain: 100,
    gainPoints: [
      CameraGainPoint(gain: 0, readNoiseE: 3.5, fullWellE: 50000),
      CameraGainPoint(gain: 100, readNoiseE: 1.5, fullWellE: 18700),
    ],
  ),
  CameraHardwareSpec(
    model: 'ZWO ASI533MM Pro',
    aliases: ['ASI533MM', 'ASI533MM Pro', 'ZWO ASI533MM'],
    pixelSizeMicrons: 3.76,
    qePeak: 0.91,
    defaultGain: 100,
    gainPoints: [
      CameraGainPoint(gain: 0, readNoiseE: 3.5, fullWellE: 50000),
      CameraGainPoint(gain: 100, readNoiseE: 1.5, fullWellE: 18200),
    ],
  ),
  CameraHardwareSpec(
    model: 'ZWO ASI533MC Pro',
    aliases: ['ASI533MC', 'ASI533MC Pro', 'ZWO ASI533MC'],
    pixelSizeMicrons: 3.76,
    qePeak: 0.80,
    defaultGain: 100,
    gainPoints: [
      CameraGainPoint(gain: 0, readNoiseE: 3.5, fullWellE: 50000),
      CameraGainPoint(gain: 100, readNoiseE: 1.5, fullWellE: 18200),
    ],
  ),
];
