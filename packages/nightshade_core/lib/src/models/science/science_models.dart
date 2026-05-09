import 'dart:math' as math;
import 'dart:typed_data';

enum PhotometricCatalogSource {
  auto,
  localGaia,
  localApass,
}

enum ScienceFeature {
  photometry,
  photometricCalibration,
  transparency,
  psfMap,
  astrometricResiduals,
  movingObjects,
  narrowbandRatios,
  frameQualityMaps,
  surface3d,
}

enum ScienceLayerType {
  fwhm,
  hfr,
  eccentricity,
  uniformity,
  clipLow,
  clipHigh,
  background,
  snr,
  residualMag;

  String get dbValue {
    switch (this) {
      case ScienceLayerType.fwhm:
        return 'fwhm';
      case ScienceLayerType.hfr:
        return 'hfr';
      case ScienceLayerType.eccentricity:
        return 'eccentricity';
      case ScienceLayerType.uniformity:
        return 'uniformity';
      case ScienceLayerType.clipLow:
        return 'clip_low';
      case ScienceLayerType.clipHigh:
        return 'clip_high';
      case ScienceLayerType.background:
        return 'background';
      case ScienceLayerType.snr:
        return 'snr';
      case ScienceLayerType.residualMag:
        return 'residual_mag';
    }
  }

  static ScienceLayerType fromDbValue(String value) {
    switch (value) {
      case 'fwhm':
        return ScienceLayerType.fwhm;
      case 'hfr':
        return ScienceLayerType.hfr;
      case 'eccentricity':
        return ScienceLayerType.eccentricity;
      case 'uniformity':
        return ScienceLayerType.uniformity;
      case 'clip_low':
        return ScienceLayerType.clipLow;
      case 'clip_high':
        return ScienceLayerType.clipHigh;
      case 'background':
        return ScienceLayerType.background;
      case 'snr':
        return ScienceLayerType.snr;
      case 'residual_mag':
        return ScienceLayerType.residualMag;
      default:
        return ScienceLayerType.uniformity;
    }
  }
}

class ScienceFrameQualityMetrics {
  final int? capturedImageId;
  final int? sessionId;
  final DateTime timestamp;
  final double median;
  final double mean;
  final double stdDev;
  final double mad;
  final double background;
  final double noise;
  final double snr;
  final double dynamicRangeP1P99;
  final double lowClipPercent;
  final double highClipPercent;
  final double uniformityCv;
  final double gradientX;
  final double gradientY;
  final String processingTier;
  final int processingMs;

  const ScienceFrameQualityMetrics({
    required this.capturedImageId,
    required this.sessionId,
    required this.timestamp,
    required this.median,
    required this.mean,
    required this.stdDev,
    required this.mad,
    required this.background,
    required this.noise,
    required this.snr,
    required this.dynamicRangeP1P99,
    required this.lowClipPercent,
    required this.highClipPercent,
    required this.uniformityCv,
    required this.gradientX,
    required this.gradientY,
    required this.processingTier,
    required this.processingMs,
  });

  ScienceFrameQualityMetrics copyWith({
    int? capturedImageId,
    int? sessionId,
    DateTime? timestamp,
    double? median,
    double? mean,
    double? stdDev,
    double? mad,
    double? background,
    double? noise,
    double? snr,
    double? dynamicRangeP1P99,
    double? lowClipPercent,
    double? highClipPercent,
    double? uniformityCv,
    double? gradientX,
    double? gradientY,
    String? processingTier,
    int? processingMs,
  }) {
    return ScienceFrameQualityMetrics(
      capturedImageId: capturedImageId ?? this.capturedImageId,
      sessionId: sessionId ?? this.sessionId,
      timestamp: timestamp ?? this.timestamp,
      median: median ?? this.median,
      mean: mean ?? this.mean,
      stdDev: stdDev ?? this.stdDev,
      mad: mad ?? this.mad,
      background: background ?? this.background,
      noise: noise ?? this.noise,
      snr: snr ?? this.snr,
      dynamicRangeP1P99: dynamicRangeP1P99 ?? this.dynamicRangeP1P99,
      lowClipPercent: lowClipPercent ?? this.lowClipPercent,
      highClipPercent: highClipPercent ?? this.highClipPercent,
      uniformityCv: uniformityCv ?? this.uniformityCv,
      gradientX: gradientX ?? this.gradientX,
      gradientY: gradientY ?? this.gradientY,
      processingTier: processingTier ?? this.processingTier,
      processingMs: processingMs ?? this.processingMs,
    );
  }
}

class ScienceTileMetric {
  final int? capturedImageId;
  final int? sessionId;
  final DateTime timestamp;
  final ScienceLayerType layerType;
  final int tileRow;
  final int tileCol;
  final int sampleCount;
  final double value;
  final double p05;
  final double p50;
  final double p95;
  final double auxValue;

  const ScienceTileMetric({
    required this.capturedImageId,
    required this.sessionId,
    required this.timestamp,
    required this.layerType,
    required this.tileRow,
    required this.tileCol,
    required this.sampleCount,
    required this.value,
    required this.p05,
    required this.p50,
    required this.p95,
    required this.auxValue,
  });
}

class ScienceVisualizationPrefs {
  final double overlayOpacity;
  final int liveGridRows;
  final int liveGridCols;
  final int analysisGridRows;
  final int analysisGridCols;

  const ScienceVisualizationPrefs({
    this.overlayOpacity = 0.35,
    this.liveGridRows = 12,
    this.liveGridCols = 16,
    this.analysisGridRows = 24,
    this.analysisGridCols = 32,
  });

  ScienceVisualizationPrefs copyWith({
    double? overlayOpacity,
    int? liveGridRows,
    int? liveGridCols,
    int? analysisGridRows,
    int? analysisGridCols,
  }) {
    return ScienceVisualizationPrefs(
      overlayOpacity: overlayOpacity ?? this.overlayOpacity,
      liveGridRows: liveGridRows ?? this.liveGridRows,
      liveGridCols: liveGridCols ?? this.liveGridCols,
      analysisGridRows: analysisGridRows ?? this.analysisGridRows,
      analysisGridCols: analysisGridCols ?? this.analysisGridCols,
    );
  }
}

class SolverCapabilities {
  final bool hasResidualVectors;
  final bool hasDistortionTerms;
  final bool supportsBatchSolve;
  final bool supportsLocalIndexOnly;

  const SolverCapabilities({
    this.hasResidualVectors = false,
    this.hasDistortionTerms = false,
    this.supportsBatchSolve = false,
    this.supportsLocalIndexOnly = true,
  });
}

class SolveOptions {
  final double? raHintHours;
  final double? decHintDegrees;
  final double? searchRadiusDegrees;

  const SolveOptions({
    this.raHintHours,
    this.decHintDegrees,
    this.searchRadiusDegrees,
  });
}

class WcsSolution {
  final double raHours;
  final double decDegrees;
  final double pixelScaleArcsecPerPixel;
  final double rotationDegrees;
  final double fieldWidthDegrees;
  final double fieldHeightDegrees;
  final String solverId;

  const WcsSolution({
    required this.raHours,
    required this.decDegrees,
    required this.pixelScaleArcsecPerPixel,
    required this.rotationDegrees,
    required this.fieldWidthDegrees,
    required this.fieldHeightDegrees,
    required this.solverId,
  });
}

class PhotometryOptions {
  final int apertureRadiusPixels;
  final int annulusInnerRadiusPixels;
  final int annulusOuterRadiusPixels;
  final double minSnr;

  const PhotometryOptions({
    this.apertureRadiusPixels = 6,
    this.annulusInnerRadiusPixels = 8,
    this.annulusOuterRadiusPixels = 12,
    this.minSnr = 4.0,
  });
}

class StarMeasurement {
  final double x;
  final double y;
  final double flux;
  final double hfr;
  final double fwhm;
  final double snr;
  final double eccentricity;
  final double sharpness;
  final double background;
  final double peak;

  const StarMeasurement({
    required this.x,
    required this.y,
    required this.flux,
    required this.hfr,
    required this.fwhm,
    required this.snr,
    required this.eccentricity,
    required this.sharpness,
    required this.background,
    required this.peak,
  });
}

class FramePhotometricCalibration {
  final int? capturedImageId;
  final int? sessionId;
  final DateTime timestamp;
  final double? airmass;
  final double exposureSeconds;
  final bool isCalibrated;
  final double? zeroPoint;
  final double? limitingMag3Sigma;
  final double? limitingMag5Sigma;
  final int matchedStarCount;
  final double calibrationRms;
  final String solverId;
  final PhotometricCatalogSource catalogSource;

  const FramePhotometricCalibration({
    required this.capturedImageId,
    required this.sessionId,
    required this.timestamp,
    this.airmass,
    this.exposureSeconds = 1.0,
    required this.isCalibrated,
    this.zeroPoint,
    this.limitingMag3Sigma,
    this.limitingMag5Sigma,
    this.matchedStarCount = 0,
    this.calibrationRms = 0.0,
    required this.solverId,
    this.catalogSource = PhotometricCatalogSource.auto,
  });
}

class TransparencyOptions {
  final int rollingWindowSize;
  final int minimumSampleCount;
  final double minAirmassSpan;

  const TransparencyOptions({
    this.rollingWindowSize = 12,
    this.minimumSampleCount = 4,
    this.minAirmassSpan = 0.25,
  });
}

class TransparencySample {
  final int? capturedImageId;
  final int? sessionId;
  final DateTime timestamp;
  final double transparencyPercent;
  final double extinctionCoefficient;
  final String qualityBucket;
  final double confidence;

  const TransparencySample({
    required this.capturedImageId,
    required this.sessionId,
    required this.timestamp,
    required this.transparencyPercent,
    required this.extinctionCoefficient,
    required this.qualityBucket,
    required this.confidence,
  });
}

class PsfMapOptions {
  final int gridRows;
  final int gridCols;

  const PsfMapOptions({
    this.gridRows = 4,
    this.gridCols = 6,
  });
}

class PsfTileMetric {
  final int row;
  final int col;
  final int starCount;
  final double medianFwhm;
  final double medianHfr;
  final double medianEccentricity;
  final double roundness;

  const PsfTileMetric({
    required this.row,
    required this.col,
    required this.starCount,
    required this.medianFwhm,
    required this.medianHfr,
    required this.medianEccentricity,
    required this.roundness,
  });
}

class PsfFieldMap {
  final int gridRows;
  final int gridCols;
  final List<PsfTileMetric> tiles;

  const PsfFieldMap({
    required this.gridRows,
    required this.gridCols,
    required this.tiles,
  });
}

class AstrometryOptions {
  final int sampleCount;

  const AstrometryOptions({
    this.sampleCount = 250,
  });
}

class ResidualVectorSample {
  final double x;
  final double y;
  final double dxArcsec;
  final double dyArcsec;
  final double magnitudeArcsec;

  const ResidualVectorSample({
    required this.x,
    required this.y,
    required this.dxArcsec,
    required this.dyArcsec,
    required this.magnitudeArcsec,
  });
}

class AstrometricResidualMap {
  final List<ResidualVectorSample> vectors;
  final double rmsArcsec;
  final String? suggestionCode;

  const AstrometricResidualMap({
    required this.vectors,
    required this.rmsArcsec,
    this.suggestionCode,
  });
}

class MovingObjectOptions {
  final double minMotionPixels;
  final double maxMotionPixels;

  const MovingObjectOptions({
    this.minMotionPixels = 1.5,
    this.maxMotionPixels = 18.0,
  });
}

class MovingObjectMatch {
  final String candidateId;
  final double raDegrees;
  final double decDegrees;
  final double motionArcsecPerMinute;
  final double positionAngleDegrees;
  final double confidence;
  final bool isKnownObject;
  final String? objectName;

  const MovingObjectMatch({
    required this.candidateId,
    required this.raDegrees,
    required this.decDegrees,
    required this.motionArcsecPerMinute,
    required this.positionAngleDegrees,
    required this.confidence,
    this.isKnownObject = false,
    this.objectName,
  });
}

class NarrowbandSet {
  final String hAlphaPath;
  final String oiiiPath;
  final String siiPath;

  const NarrowbandSet({
    required this.hAlphaPath,
    required this.oiiiPath,
    required this.siiPath,
  });
}

class LineRatioOptions {
  final double snrFloor;
  final bool continuumCorrection;
  final bool requireMatchingDimensions;

  const LineRatioOptions({
    this.snrFloor = 5.0,
    this.continuumCorrection = false,
    this.requireMatchingDimensions = true,
  });
}

class LineRatioMetric {
  final String label;
  final double value;

  const LineRatioMetric({
    required this.label,
    required this.value,
  });
}

class LineRatioProduct {
  final DateTime createdAt;
  final List<LineRatioMetric> metrics;
  final Uint8List? previewImage;

  const LineRatioProduct({
    required this.createdAt,
    required this.metrics,
    this.previewImage,
  });
}

class ScienceModeState {
  final bool advancedModeEnabled;
  final bool overlayEnabled;
  final bool scienceHudVisible;
  final bool movingObjectModeEnabled;
  final bool differentialPhotometryActive;

  const ScienceModeState({
    this.advancedModeEnabled = false,
    this.overlayEnabled = true,
    this.scienceHudVisible = false,
    this.movingObjectModeEnabled = false,
    this.differentialPhotometryActive = false,
  });

  ScienceModeState copyWith({
    bool? advancedModeEnabled,
    bool? overlayEnabled,
    bool? scienceHudVisible,
    bool? movingObjectModeEnabled,
    bool? differentialPhotometryActive,
  }) {
    return ScienceModeState(
      advancedModeEnabled: advancedModeEnabled ?? this.advancedModeEnabled,
      overlayEnabled: overlayEnabled ?? this.overlayEnabled,
      scienceHudVisible: scienceHudVisible ?? this.scienceHudVisible,
      movingObjectModeEnabled:
          movingObjectModeEnabled ?? this.movingObjectModeEnabled,
      differentialPhotometryActive:
          differentialPhotometryActive ?? this.differentialPhotometryActive,
    );
  }
}

class ScienceOverlayState {
  final bool showPsfHeatmap;
  final bool showResidualVectors;
  final bool showMovingObjectTracks;
  final bool showUniformityMap;
  final bool showClipHighMap;
  final bool showClipLowMap;
  final bool showFwhmSurface;

  const ScienceOverlayState({
    this.showPsfHeatmap = false,
    this.showResidualVectors = false,
    this.showMovingObjectTracks = false,
    this.showUniformityMap = false,
    this.showClipHighMap = false,
    this.showClipLowMap = false,
    this.showFwhmSurface = false,
  });

  ScienceOverlayState copyWith({
    bool? showPsfHeatmap,
    bool? showResidualVectors,
    bool? showMovingObjectTracks,
    bool? showUniformityMap,
    bool? showClipHighMap,
    bool? showClipLowMap,
    bool? showFwhmSurface,
  }) {
    return ScienceOverlayState(
      showPsfHeatmap: showPsfHeatmap ?? this.showPsfHeatmap,
      showResidualVectors: showResidualVectors ?? this.showResidualVectors,
      showMovingObjectTracks:
          showMovingObjectTracks ?? this.showMovingObjectTracks,
      showUniformityMap: showUniformityMap ?? this.showUniformityMap,
      showClipHighMap: showClipHighMap ?? this.showClipHighMap,
      showClipLowMap: showClipLowMap ?? this.showClipLowMap,
      showFwhmSurface: showFwhmSurface ?? this.showFwhmSurface,
    );
  }
}

class ScienceSessionConfig {
  final int? sessionId;
  final bool photometryEnabled;
  final bool calibrationEnabled;
  final bool transparencyEnabled;
  final bool psfMapEnabled;
  final bool residualsEnabled;
  final bool movingObjectsEnabled;
  final bool narrowbandEnabled;
  final int psfGridRows;
  final int psfGridCols;
  final double transparencyAlertThreshold;

  const ScienceSessionConfig({
    this.sessionId,
    this.photometryEnabled = true,
    this.calibrationEnabled = true,
    this.transparencyEnabled = true,
    this.psfMapEnabled = true,
    this.residualsEnabled = true,
    this.movingObjectsEnabled = false,
    this.narrowbandEnabled = false,
    this.psfGridRows = 4,
    this.psfGridCols = 6,
    this.transparencyAlertThreshold = 70.0,
  });

  ScienceSessionConfig copyWith({
    int? sessionId,
    bool? photometryEnabled,
    bool? calibrationEnabled,
    bool? transparencyEnabled,
    bool? psfMapEnabled,
    bool? residualsEnabled,
    bool? movingObjectsEnabled,
    bool? narrowbandEnabled,
    int? psfGridRows,
    int? psfGridCols,
    double? transparencyAlertThreshold,
  }) {
    return ScienceSessionConfig(
      sessionId: sessionId ?? this.sessionId,
      photometryEnabled: photometryEnabled ?? this.photometryEnabled,
      calibrationEnabled: calibrationEnabled ?? this.calibrationEnabled,
      transparencyEnabled: transparencyEnabled ?? this.transparencyEnabled,
      psfMapEnabled: psfMapEnabled ?? this.psfMapEnabled,
      residualsEnabled: residualsEnabled ?? this.residualsEnabled,
      movingObjectsEnabled: movingObjectsEnabled ?? this.movingObjectsEnabled,
      narrowbandEnabled: narrowbandEnabled ?? this.narrowbandEnabled,
      psfGridRows: psfGridRows ?? this.psfGridRows,
      psfGridCols: psfGridCols ?? this.psfGridCols,
      transparencyAlertThreshold:
          transparencyAlertThreshold ?? this.transparencyAlertThreshold,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'photometryEnabled': photometryEnabled,
      'calibrationEnabled': calibrationEnabled,
      'transparencyEnabled': transparencyEnabled,
      'psfMapEnabled': psfMapEnabled,
      'residualsEnabled': residualsEnabled,
      'movingObjectsEnabled': movingObjectsEnabled,
      'narrowbandEnabled': narrowbandEnabled,
      'psfGridRows': psfGridRows,
      'psfGridCols': psfGridCols,
      'transparencyAlertThreshold': transparencyAlertThreshold,
    };
  }

  factory ScienceSessionConfig.fromJson(Map<String, dynamic> json) {
    return ScienceSessionConfig(
      sessionId: (json['sessionId'] as num?)?.toInt(),
      photometryEnabled: json['photometryEnabled'] as bool? ?? true,
      calibrationEnabled: json['calibrationEnabled'] as bool? ?? true,
      transparencyEnabled: json['transparencyEnabled'] as bool? ?? true,
      psfMapEnabled: json['psfMapEnabled'] as bool? ?? true,
      residualsEnabled: json['residualsEnabled'] as bool? ?? true,
      movingObjectsEnabled: json['movingObjectsEnabled'] as bool? ?? false,
      narrowbandEnabled: json['narrowbandEnabled'] as bool? ?? false,
      psfGridRows: (json['psfGridRows'] as num?)?.toInt() ?? 4,
      psfGridCols: (json['psfGridCols'] as num?)?.toInt() ?? 6,
      transparencyAlertThreshold:
          (json['transparencyAlertThreshold'] as num?)?.toDouble() ?? 70.0,
    );
  }
}

class ScienceDiagnostics {
  final String solverId;
  final SolverCapabilities capabilities;
  final String? lastWarning;
  final DateTime? lastUpdated;

  const ScienceDiagnostics({
    required this.solverId,
    required this.capabilities,
    this.lastWarning,
    this.lastUpdated,
  });
}

class ScienceFrameContext {
  final int? capturedImageId;
  final int? sessionId;
  final DateTime capturedAt;
  final double exposureSeconds;
  final String? filterName;
  final double? airmass;
  final int imageWidth;
  final int imageHeight;

  const ScienceFrameContext({
    required this.capturedImageId,
    required this.sessionId,
    required this.capturedAt,
    required this.exposureSeconds,
    required this.filterName,
    required this.airmass,
    required this.imageWidth,
    required this.imageHeight,
  });
}

class PhotometryAnchor {
  final String objectId;
  final String label;
  final double raDegrees;
  final double decDegrees;

  const PhotometryAnchor({
    required this.objectId,
    required this.label,
    required this.raDegrees,
    required this.decDegrees,
  });

  PhotometryAnchor copyWith({
    String? objectId,
    String? label,
    double? raDegrees,
    double? decDegrees,
  }) {
    return PhotometryAnchor(
      objectId: objectId ?? this.objectId,
      label: label ?? this.label,
      raDegrees: raDegrees ?? this.raDegrees,
      decDegrees: decDegrees ?? this.decDegrees,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'objectId': objectId,
      'label': label,
      'raDegrees': raDegrees,
      'decDegrees': decDegrees,
    };
  }

  factory PhotometryAnchor.fromJson(Map<String, dynamic> json) {
    return PhotometryAnchor(
      objectId: json['objectId']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      raDegrees: (json['raDegrees'] as num?)?.toDouble() ?? 0.0,
      decDegrees: (json['decDegrees'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SciencePhotometrySelection {
  final bool differentialEnabled;
  final PhotometryAnchor? target;
  final List<PhotometryAnchor> comparisons;

  const SciencePhotometrySelection({
    this.differentialEnabled = false,
    this.target,
    this.comparisons = const [],
  });

  SciencePhotometrySelection copyWith({
    bool? differentialEnabled,
    PhotometryAnchor? target,
    bool clearTarget = false,
    List<PhotometryAnchor>? comparisons,
  }) {
    return SciencePhotometrySelection(
      differentialEnabled: differentialEnabled ?? this.differentialEnabled,
      target: clearTarget ? null : (target ?? this.target),
      comparisons: comparisons ?? this.comparisons,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'differentialEnabled': differentialEnabled,
      'target': target?.toJson(),
      'comparisons': comparisons.map((entry) => entry.toJson()).toList(),
    };
  }

  factory SciencePhotometrySelection.fromJson(Map<String, dynamic> json) {
    final rawComparisons = json['comparisons'];
    final parsedComparisons = <PhotometryAnchor>[];
    if (rawComparisons is List) {
      for (final raw in rawComparisons) {
        if (raw is Map<String, dynamic>) {
          parsedComparisons.add(PhotometryAnchor.fromJson(raw));
        } else if (raw is Map) {
          parsedComparisons.add(
            PhotometryAnchor.fromJson(raw.cast<String, dynamic>()),
          );
        }
      }
    }

    final rawTarget = json['target'];
    PhotometryAnchor? parsedTarget;
    if (rawTarget is Map<String, dynamic>) {
      parsedTarget = PhotometryAnchor.fromJson(rawTarget);
    } else if (rawTarget is Map) {
      parsedTarget =
          PhotometryAnchor.fromJson(rawTarget.cast<String, dynamic>());
    }

    return SciencePhotometrySelection(
      differentialEnabled: json['differentialEnabled'] == true,
      target: parsedTarget,
      comparisons: parsedComparisons,
    );
  }
}

/// A single star match used for computing photometric transform coefficients.
class TransformStarMatch {
  final double catalogMag;
  final double instrumentalMag;
  final double colorIndex;
  final double airmass;
  final double residual;

  const TransformStarMatch({
    required this.catalogMag,
    required this.instrumentalMag,
    required this.colorIndex,
    required this.airmass,
    required this.residual,
  });

  Map<String, dynamic> toJson() {
    return {
      'catalogMag': catalogMag,
      'instrumentalMag': instrumentalMag,
      'colorIndex': colorIndex,
      'airmass': airmass,
      'residual': residual,
    };
  }

  factory TransformStarMatch.fromJson(Map<String, dynamic> json) {
    return TransformStarMatch(
      catalogMag: (json['catalogMag'] as num?)?.toDouble() ?? 0.0,
      instrumentalMag: (json['instrumentalMag'] as num?)?.toDouble() ?? 0.0,
      colorIndex: (json['colorIndex'] as num?)?.toDouble() ?? 0.0,
      airmass: (json['airmass'] as num?)?.toDouble() ?? 1.0,
      residual: (json['residual'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Photometric transformation coefficients for converting instrumental
/// magnitudes to standard magnitudes using the equation:
///   M_std = m_inst - k*X + T*(B-V) + zp
/// where:
///   m_inst = instrumental magnitude (-2.5 * log10(flux))
///   k = extinction coefficient (mags per airmass)
///   X = airmass
///   T = color term (transform coefficient)
///   (B-V) = color index of the star
///   zp = zero point
class PhotometricTransformCoefficients {
  final int? id;
  final int? equipmentProfileId;
  final String filterName;
  final double colorTerm;
  final double extinctionCoefficient;
  final double zeroPoint;
  final double rmsResidual;
  final int matchedStarCount;
  final String catalogSource;
  final List<TransformStarMatch> fitData;
  final DateTime dateComputed;

  const PhotometricTransformCoefficients({
    this.id,
    this.equipmentProfileId,
    required this.filterName,
    required this.colorTerm,
    required this.extinctionCoefficient,
    required this.zeroPoint,
    required this.rmsResidual,
    required this.matchedStarCount,
    this.catalogSource = 'auto',
    this.fitData = const [],
    required this.dateComputed,
  });

  /// Apply this transform to convert instrumental magnitude to standard.
  double applyTransform({
    required double instrumentalMag,
    required double airmass,
    required double colorIndex,
  }) {
    return instrumentalMag - extinctionCoefficient * airmass +
        colorTerm * colorIndex + zeroPoint;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'equipmentProfileId': equipmentProfileId,
      'filterName': filterName,
      'colorTerm': colorTerm,
      'extinctionCoefficient': extinctionCoefficient,
      'zeroPoint': zeroPoint,
      'rmsResidual': rmsResidual,
      'matchedStarCount': matchedStarCount,
      'catalogSource': catalogSource,
      'fitData': fitData.map((match) => match.toJson()).toList(),
      'dateComputed': dateComputed.toIso8601String(),
    };
  }

  factory PhotometricTransformCoefficients.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawFitData = json['fitData'] as List? ?? const [];
    return PhotometricTransformCoefficients(
      id: (json['id'] as num?)?.toInt(),
      equipmentProfileId: (json['equipmentProfileId'] as num?)?.toInt(),
      filterName: json['filterName']?.toString() ?? '',
      colorTerm: (json['colorTerm'] as num?)?.toDouble() ?? 0.0,
      extinctionCoefficient:
          (json['extinctionCoefficient'] as num?)?.toDouble() ?? 0.0,
      zeroPoint: (json['zeroPoint'] as num?)?.toDouble() ?? 0.0,
      rmsResidual: (json['rmsResidual'] as num?)?.toDouble() ?? 0.0,
      matchedStarCount: (json['matchedStarCount'] as num?)?.toInt() ?? 0,
      catalogSource: json['catalogSource']?.toString() ?? 'auto',
      fitData: rawFitData
          .whereType<Map>()
          .map((entry) => TransformStarMatch.fromJson(
                entry.cast<String, dynamic>(),
              ))
          .toList(growable: false),
      dateComputed: DateTime.tryParse(json['dateComputed']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Input data for the calibration wizard — catalog star with known magnitudes
/// matched to a detected source in the image.
class CatalogStarMatch {
  final double x;
  final double y;
  final double raDegrees;
  final double decDegrees;
  final double catalogMagV;
  final double catalogMagB;
  final double instrumentalFlux;
  final double snr;
  final double airmass;

  const CatalogStarMatch({
    required this.x,
    required this.y,
    required this.raDegrees,
    required this.decDegrees,
    required this.catalogMagV,
    required this.catalogMagB,
    required this.instrumentalFlux,
    required this.snr,
    required this.airmass,
  });

  double get colorIndex => catalogMagB - catalogMagV;

  double get instrumentalMag {
    if (instrumentalFlux <= 0) {
      return 99.0;
    }
    return -2.5 * math.log(instrumentalFlux.clamp(1e-30, double.infinity)) / math.ln10;
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'raDegrees': raDegrees,
      'decDegrees': decDegrees,
      'catalogMagV': catalogMagV,
      'catalogMagB': catalogMagB,
      'instrumentalFlux': instrumentalFlux,
      'snr': snr,
      'airmass': airmass,
    };
  }

  factory CatalogStarMatch.fromJson(Map<String, dynamic> json) {
    return CatalogStarMatch(
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      raDegrees: (json['raDegrees'] as num?)?.toDouble() ?? 0.0,
      decDegrees: (json['decDegrees'] as num?)?.toDouble() ?? 0.0,
      catalogMagV: (json['catalogMagV'] as num?)?.toDouble() ?? 0.0,
      catalogMagB: (json['catalogMagB'] as num?)?.toDouble() ?? 0.0,
      instrumentalFlux:
          (json['instrumentalFlux'] as num?)?.toDouble() ?? 0.0,
      snr: (json['snr'] as num?)?.toDouble() ?? 0.0,
      airmass: (json['airmass'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class LightCurvePoint {
  final DateTime timestamp;
  final double flux;
  final double differentialMagnitude;
  final double snr;
  final double uncertainty;

  const LightCurvePoint({
    required this.timestamp,
    required this.flux,
    required this.differentialMagnitude,
    required this.snr,
    required this.uncertainty,
  });
}

class TransparencyTrendPoint {
  final DateTime timestamp;
  final double transparencyPercent;
  final double extinctionCoefficient;

  const TransparencyTrendPoint({
    required this.timestamp,
    required this.transparencyPercent,
    required this.extinctionCoefficient,
  });
}

class MovingObjectCandidate {
  final DateTime timestamp;
  final String candidateId;
  final double confidence;
  final double motionArcsecPerMinute;
  final String? objectName;

  const MovingObjectCandidate({
    required this.timestamp,
    required this.candidateId,
    required this.confidence,
    required this.motionArcsecPerMinute,
    this.objectName,
  });
}
