import 'dart:convert';
import 'dart:developer' as developer;
import 'package:equatable/equatable.dart';
import 'dart:typed_data';

/// Frame type for imaging
enum FrameType {
  light,
  dark,
  flat,
  bias,
  darkFlat,
  snapshot;

  String get displayName {
    switch (this) {
      case FrameType.light:
        return 'Light';
      case FrameType.dark:
        return 'Dark';
      case FrameType.flat:
        return 'Flat';
      case FrameType.bias:
        return 'Bias';
      case FrameType.darkFlat:
        return 'Dark Flat';
      case FrameType.snapshot:
        return 'Snapshot';
    }
  }
}

/// Bayer pattern for color cameras
enum BayerPattern {
  rggb,
  bggr,
  grbg,
  gbrg;

  String get displayName => name.toUpperCase();
}

/// Debayer algorithm
enum DebayerAlgorithm {
  bilinear,
  vng,
  superPixel;

  String get displayName {
    switch (this) {
      case DebayerAlgorithm.bilinear:
        return 'Bilinear (Fast)';
      case DebayerAlgorithm.vng:
        return 'VNG (Quality)';
      case DebayerAlgorithm.superPixel:
        return 'Super Pixel (2x2)';
    }
  }
}

/// Image statistics
class ImageStats extends Equatable {
  final double? hfr;
  final double? fwhm;
  final int? starCount;
  final double? median;
  final double? mean;
  final double? stdDev;
  final double? min;
  final double? max;
  final double? mad;
  final double? snr;
  final double? background;
  final double? noise;

  const ImageStats({
    this.hfr,
    this.fwhm,
    this.starCount,
    this.median,
    this.mean,
    this.stdDev,
    this.min,
    this.max,
    this.mad,
    this.snr,
    this.background,
    this.noise,
  });

  factory ImageStats.fromJson(Map<String, dynamic> json) {
    return ImageStats(
      hfr: (json['hfr'] as num?)?.toDouble(),
      fwhm: (json['fwhm'] as num?)?.toDouble(),
      starCount: json['starCount'] as int?,
      median: (json['median'] as num?)?.toDouble(),
      mean: (json['mean'] as num?)?.toDouble(),
      stdDev: (json['stdDev'] as num?)?.toDouble(),
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      mad: (json['mad'] as num?)?.toDouble(),
      snr: (json['snr'] as num?)?.toDouble(),
      background: (json['background'] as num?)?.toDouble(),
      noise: (json['noise'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hfr': hfr,
      'fwhm': fwhm,
      'starCount': starCount,
      'median': median,
      'mean': mean,
      'stdDev': stdDev,
      'min': min,
      'max': max,
      'mad': mad,
      'snr': snr,
      'background': background,
      'noise': noise,
    };
  }

  @override
  List<Object?> get props => [
        hfr,
        fwhm,
        starCount,
        median,
        mean,
        stdDev,
        min,
        max,
        mad,
        snr,
        background,
        noise
      ];
}

/// Detected star information
class DetectedStar extends Equatable {
  final double x;
  final double y;
  final double flux;
  final double hfr;
  final double fwhm;
  final double peak;
  final double background;
  final double snr;

  const DetectedStar({
    required this.x,
    required this.y,
    required this.flux,
    required this.hfr,
    required this.fwhm,
    required this.peak,
    required this.background,
    required this.snr,
  });

  @override
  List<Object?> get props => [x, y, flux, hfr, fwhm, peak, background, snr];
}

/// Star detection result
class StarDetectionResult extends Equatable {
  final List<DetectedStar> stars;
  final int starCount;
  final double medianHfr;
  final double medianFwhm;
  final double medianSnr;
  final double background;
  final double noise;

  const StarDetectionResult({
    required this.stars,
    required this.starCount,
    required this.medianHfr,
    required this.medianFwhm,
    required this.medianSnr,
    required this.background,
    required this.noise,
  });

  @override
  List<Object?> get props =>
      [stars, starCount, medianHfr, medianFwhm, medianSnr, background, noise];
}

/// Stretch parameters for image display
class StretchParams extends Equatable {
  final double shadows;
  final double highlights;
  final double midtones;

  const StretchParams({
    this.shadows = 0.0,
    this.highlights = 1.0,
    this.midtones = 0.5,
  });

  StretchParams copyWith({
    double? shadows,
    double? highlights,
    double? midtones,
  }) {
    return StretchParams(
      shadows: shadows ?? this.shadows,
      highlights: highlights ?? this.highlights,
      midtones: midtones ?? this.midtones,
    );
  }

  @override
  List<Object?> get props => [shadows, highlights, midtones];
}

/// Exposure settings
class ExposureSettings extends Equatable {
  final double exposureTime;
  final int gain;
  final int offset;
  final int binningX;
  final int binningY;
  final String? filter;
  final FrameType frameType;
  final bool fastReadout;

  const ExposureSettings({
    required this.exposureTime,
    required this.gain,
    required this.offset,
    this.binningX = 1,
    this.binningY = 1,
    this.filter,
    this.frameType = FrameType.light,
    this.fastReadout = false,
  });

  String get binning => '${binningX}x$binningY';

  ExposureSettings copyWith({
    double? exposureTime,
    int? gain,
    int? offset,
    int? binningX,
    int? binningY,
    String? filter,
    FrameType? frameType,
    bool? fastReadout,
  }) {
    return ExposureSettings(
      exposureTime: exposureTime ?? this.exposureTime,
      gain: gain ?? this.gain,
      offset: offset ?? this.offset,
      binningX: binningX ?? this.binningX,
      binningY: binningY ?? this.binningY,
      filter: filter ?? this.filter,
      frameType: frameType ?? this.frameType,
      fastReadout: fastReadout ?? this.fastReadout,
    );
  }

  @override
  List<Object?> get props => [
        exposureTime,
        gain,
        offset,
        binningX,
        binningY,
        filter,
        frameType,
        fastReadout
      ];
}

/// Cooling settings
class CoolingSettings extends Equatable {
  final double targetTemp;
  final bool enabled;
  final double warmupRate;
  final double cooldownRate;

  const CoolingSettings({
    this.targetTemp = -10.0,
    this.enabled = false,
    this.warmupRate = 2.0,
    this.cooldownRate = 5.0,
  });

  CoolingSettings copyWith({
    double? targetTemp,
    bool? enabled,
    double? warmupRate,
    double? cooldownRate,
  }) {
    return CoolingSettings(
      targetTemp: targetTemp ?? this.targetTemp,
      enabled: enabled ?? this.enabled,
      warmupRate: warmupRate ?? this.warmupRate,
      cooldownRate: cooldownRate ?? this.cooldownRate,
    );
  }

  @override
  List<Object?> get props => [targetTemp, enabled, warmupRate, cooldownRate];
}

/// Cooling status
class CoolingStatus extends Equatable {
  final double currentTemp;
  final double targetTemp;
  final double coolerPower;
  final bool isAtTarget;
  final bool isCooling;

  const CoolingStatus({
    this.currentTemp = 20.0,
    this.targetTemp = -10.0,
    this.coolerPower = 0.0,
    this.isAtTarget = false,
    this.isCooling = false,
  });

  @override
  List<Object?> get props =>
      [currentTemp, targetTemp, coolerPower, isAtTarget, isCooling];
}

/// Focus/Autofocus settings (persists across navigation)
class FocusSettings extends Equatable {
  /// Manual focus step size
  final int stepSize;

  /// Autofocus method
  final String method;

  /// Autofocus step size
  final int afStepSize;

  /// Number of steps out from center
  final int stepsOut;

  /// Exposures per focus point
  final int exposuresPerPoint;

  /// Exposure time for autofocus
  final double exposureTime;

  const FocusSettings({
    this.stepSize = 100,
    this.method = 'V-Curve',
    this.afStepSize = 100,
    this.stepsOut = 7,
    this.exposuresPerPoint = 1,
    this.exposureTime = 3.0,
  });

  FocusSettings copyWith({
    int? stepSize,
    String? method,
    int? afStepSize,
    int? stepsOut,
    int? exposuresPerPoint,
    double? exposureTime,
  }) {
    return FocusSettings(
      stepSize: stepSize ?? this.stepSize,
      method: method ?? this.method,
      afStepSize: afStepSize ?? this.afStepSize,
      stepsOut: stepsOut ?? this.stepsOut,
      exposuresPerPoint: exposuresPerPoint ?? this.exposuresPerPoint,
      exposureTime: exposureTime ?? this.exposureTime,
    );
  }

  @override
  List<Object?> get props =>
      [stepSize, method, afStepSize, stepsOut, exposuresPerPoint, exposureTime];
}

/// Dither/Settle settings for guiding (persists across navigation)
class DitherSettings extends Equatable {
  /// Dither amount in pixels
  final double ditherAmount;

  /// Settle threshold in pixels
  final double settlePixels;

  /// Settle time in seconds
  final double settleTime;

  /// Whether to settle after dither
  final bool settleAfterDither;

  const DitherSettings({
    this.ditherAmount = 5.0,
    this.settlePixels = 1.0,
    this.settleTime = 10.0,
    this.settleAfterDither = true,
  });

  DitherSettings copyWith({
    double? ditherAmount,
    double? settlePixels,
    double? settleTime,
    bool? settleAfterDither,
  }) {
    return DitherSettings(
      ditherAmount: ditherAmount ?? this.ditherAmount,
      settlePixels: settlePixels ?? this.settlePixels,
      settleTime: settleTime ?? this.settleTime,
      settleAfterDither: settleAfterDither ?? this.settleAfterDither,
    );
  }

  @override
  List<Object?> get props =>
      [ditherAmount, settlePixels, settleTime, settleAfterDither];
}

/// Slew coordinates for mount tab (persists across navigation)
class SlewCoordinates extends Equatable {
  /// Right Ascension in hours
  final String raText;

  /// Declination in degrees
  final String decText;

  const SlewCoordinates({
    this.raText = '',
    this.decText = '',
  });

  SlewCoordinates copyWith({
    String? raText,
    String? decText,
  }) {
    return SlewCoordinates(
      raText: raText ?? this.raText,
      decText: decText ?? this.decText,
    );
  }

  @override
  List<Object?> get props => [raText, decText];
}

/// Image file format
enum ImageFileFormat {
  fits,
  xisf,
  tiff,
  png,
  jpeg;

  String get extension {
    switch (this) {
      case ImageFileFormat.fits:
        return 'fits';
      case ImageFileFormat.xisf:
        return 'xisf';
      case ImageFileFormat.tiff:
        return 'tiff';
      case ImageFileFormat.png:
        return 'png';
      case ImageFileFormat.jpeg:
        return 'jpg';
    }
  }

  String get displayName {
    switch (this) {
      case ImageFileFormat.fits:
        return 'FITS';
      case ImageFileFormat.xisf:
        return 'XISF (PixInsight)';
      case ImageFileFormat.tiff:
        return 'TIFF';
      case ImageFileFormat.png:
        return 'PNG';
      case ImageFileFormat.jpeg:
        return 'JPEG';
    }
  }
}

extension ImageFileFormatSettingsX on ImageFileFormat {
  String get settingsValue {
    switch (this) {
      case ImageFileFormat.fits:
        return 'FITS';
      case ImageFileFormat.xisf:
        return 'XISF';
      case ImageFileFormat.tiff:
        return 'TIFF';
      case ImageFileFormat.png:
        return 'PNG';
      case ImageFileFormat.jpeg:
        return 'JPEG';
    }
  }

  static ImageFileFormat fromSettings(String value) {
    switch (value.toUpperCase()) {
      case 'XISF':
        return ImageFileFormat.xisf;
      case 'TIFF':
        return ImageFileFormat.tiff;
      case 'PNG':
        return ImageFileFormat.png;
      case 'JPEG':
        return ImageFileFormat.jpeg;
      case 'FITS':
      default:
        return ImageFileFormat.fits;
    }
  }
}

/// Captured image data with display buffer
class CapturedImageData extends Equatable {
  final int width;
  final int height;
  final Uint8List displayData; // Always RGBA (width*height*4), alpha=255
  final List<int> histogram;
  final ImageStats stats;
  final DateTime capturedAt;
  final ExposureSettings settings;
  final String? targetName;
  final String? filePath;
  final bool
      isColor; // true if source was color (RGB), false if grayscale — displayData is always RGBA

  const CapturedImageData({
    required this.width,
    required this.height,
    required this.displayData,
    required this.histogram,
    required this.stats,
    required this.capturedAt,
    required this.settings,
    this.targetName,
    this.filePath,
    this.isColor = false, // default to grayscale for backward compatibility
  });

  @override
  List<Object?> get props => [
        width,
        height,
        displayData,
        histogram,
        stats,
        capturedAt,
        settings,
        targetName,
        filePath,
        isColor
      ];
}

/// Captured image metadata (without pixel data)
class CapturedImage extends Equatable {
  final String id;
  final String filePath;
  final DateTime capturedAt;
  final ExposureSettings settings;
  final ImageStats? stats;
  final String? targetName;
  final ImageFileFormat format;

  const CapturedImage({
    required this.id,
    required this.filePath,
    required this.capturedAt,
    required this.settings,
    this.stats,
    this.targetName,
    this.format = ImageFileFormat.fits,
  });

  @override
  List<Object?> get props =>
      [id, filePath, capturedAt, settings, stats, targetName, format];
}

/// Exposure progress
class ExposureProgress extends Equatable {
  final double elapsed;
  final double remaining;
  final double percent;
  final int frameNumber;
  final int? totalFrames;
  final bool isDownloading;

  const ExposureProgress({
    required this.elapsed,
    required this.remaining,
    required this.percent,
    this.frameNumber = 1,
    this.totalFrames,
    this.isDownloading = false,
  });

  factory ExposureProgress.idle() {
    return const ExposureProgress(
      elapsed: 0,
      remaining: 0,
      percent: 0,
      isDownloading: false,
    );
  }

  @override
  List<Object?> get props =>
      [elapsed, remaining, percent, frameNumber, totalFrames, isDownloading];
}

/// Capture mode
enum CaptureMode {
  single,
  loop,
  count;

  String get displayName {
    switch (this) {
      case CaptureMode.single:
        return 'Single Frame';
      case CaptureMode.loop:
        return 'Loop';
      case CaptureMode.count:
        return 'Frame Count';
    }
  }
}

/// File naming pattern
class NamingPattern extends Equatable {
  final String pattern;
  final String baseDir;
  final ImageFileFormat format;
  final bool createSubdirs;

  const NamingPattern({
    this.pattern = r'$TARGET/$FRAMETYPE/$TARGET_$FILTER_$EXPTIME_$FRAMENUM',
    this.baseDir = '.',
    this.format = ImageFileFormat.fits,
    this.createSubdirs = true,
  });

  NamingPattern copyWith({
    String? pattern,
    String? baseDir,
    ImageFileFormat? format,
    bool? createSubdirs,
  }) {
    return NamingPattern(
      pattern: pattern ?? this.pattern,
      baseDir: baseDir ?? this.baseDir,
      format: format ?? this.format,
      createSubdirs: createSubdirs ?? this.createSubdirs,
    );
  }

  @override
  List<Object?> get props => [pattern, baseDir, format, createSubdirs];

  /// Available pattern variables
  static const List<String> availableVariables = [
    r'$TARGET',
    r'$FILTER',
    r'$EXPTIME',
    r'$DATE',
    r'$TIME',
    r'$DATETIME',
    r'$FRAMETYPE',
    r'$FRAMENUM',
    r'$GAIN',
    r'$OFFSET',
    r'$TEMP',
    r'$BINNING',
    r'$CAMERA',
    r'$TELESCOPE',
    r'$SEQUENCE',
    r'$SESSION',
  ];
}

/// Star detection configuration
class StarDetectionConfig extends Equatable {
  final double detectionSigma;
  final int minArea;
  final int maxArea;
  final double maxEccentricity;
  final int saturationLimit;
  final int hfrRadius;

  const StarDetectionConfig({
    this.detectionSigma = 3.0,
    this.minArea = 5,
    this.maxArea = 10000,
    this.maxEccentricity = 0.8,
    this.saturationLimit = 60000,
    this.hfrRadius = 20,
  });

  @override
  List<Object?> get props => [
        detectionSigma,
        minArea,
        maxArea,
        maxEccentricity,
        saturationLimit,
        hfrRadius
      ];
}

/// Per-filter autofocus configuration
///
/// Stores autofocus overrides for a specific filter. This allows different
/// filters to have their own AF exposure times, binning, gain/offset, and
/// focus offset values.
class FilterAutofocusConfig extends Equatable {
  /// Absolute focus offset for this filter (in focuser steps)
  final int focusOffset;

  /// Override AF exposure time for this filter (null = use default from settings)
  final double? afExposureTime;

  /// Which filter to actually use for AF when this filter is active
  /// (null = use the designated autofocus filter from settings)
  final String? afFilterName;

  /// AF binning for this filter
  final int binning;

  /// AF gain override (null = use camera default)
  final int? gain;

  /// AF offset override (null = use camera default)
  final int? offset;

  const FilterAutofocusConfig({
    this.focusOffset = 0,
    this.afExposureTime,
    this.afFilterName,
    this.binning = 1,
    this.gain,
    this.offset,
  });

  FilterAutofocusConfig copyWith({
    int? focusOffset,
    double? afExposureTime,
    bool clearAfExposureTime = false,
    String? afFilterName,
    bool clearAfFilterName = false,
    int? binning,
    int? gain,
    bool clearGain = false,
    int? offset,
    bool clearOffset = false,
  }) {
    return FilterAutofocusConfig(
      focusOffset: focusOffset ?? this.focusOffset,
      afExposureTime:
          clearAfExposureTime ? null : (afExposureTime ?? this.afExposureTime),
      afFilterName:
          clearAfFilterName ? null : (afFilterName ?? this.afFilterName),
      binning: binning ?? this.binning,
      gain: clearGain ? null : (gain ?? this.gain),
      offset: clearOffset ? null : (offset ?? this.offset),
    );
  }

  Map<String, dynamic> toJson() => {
        'focusOffset': focusOffset,
        'afExposureTime': afExposureTime,
        'afFilterName': afFilterName,
        'binning': binning,
        'gain': gain,
        'offset': offset,
      };

  factory FilterAutofocusConfig.fromJson(Map<String, dynamic> json) =>
      FilterAutofocusConfig(
        focusOffset: json['focusOffset'] as int? ?? 0,
        afExposureTime: (json['afExposureTime'] as num?)?.toDouble(),
        afFilterName: json['afFilterName'] as String?,
        binning: json['binning'] as int? ?? 1,
        gain: json['gain'] as int?,
        offset: json['offset'] as int?,
      );

  @override
  List<Object?> get props =>
      [focusOffset, afExposureTime, afFilterName, binning, gain, offset];
}

/// Comprehensive autofocus settings grouped into a single typed object.
///
/// This is derived from AppSettings autofocus fields and provides a
/// convenient, typed view for the autofocus subsystem.
class AutofocusSettings extends Equatable {
  // General AF parameters
  final String method;
  final String curveFitting;
  final int stepSize;
  final double exposureTime;
  final int initialOffsetSteps;
  final int numberOfAttempts;
  final int useBrightestNStars;
  final double outerCropRatio;
  final double innerCropRatio;
  final int binning;
  final double rSquaredThreshold;
  final bool disableGuidingDuringAf;
  final int focuserSettleTimeMs;
  final int exposuresPerPoint;

  // Backlash compensation
  final String backlashCompMethod;
  final int backlashIn;
  final int backlashOut;

  // Filter-specific
  final String autofocusFilterName;
  final Map<String, FilterAutofocusConfig> filterSettings;

  const AutofocusSettings({
    this.method = 'Star HFR',
    this.curveFitting = 'Hyperbolic',
    this.stepSize = 50,
    this.exposureTime = 4.0,
    this.initialOffsetSteps = 4,
    this.numberOfAttempts = 1,
    this.useBrightestNStars = 0,
    this.outerCropRatio = 1.0,
    this.innerCropRatio = 0.0,
    this.binning = 1,
    this.rSquaredThreshold = 0.7,
    this.disableGuidingDuringAf = false,
    this.focuserSettleTimeMs = 500,
    this.exposuresPerPoint = 1,
    this.backlashCompMethod = 'Overshoot',
    this.backlashIn = 350,
    this.backlashOut = 0,
    this.autofocusFilterName = '',
    this.filterSettings = const {},
  });

  AutofocusSettings copyWith({
    String? method,
    String? curveFitting,
    int? stepSize,
    double? exposureTime,
    int? initialOffsetSteps,
    int? numberOfAttempts,
    int? useBrightestNStars,
    double? outerCropRatio,
    double? innerCropRatio,
    int? binning,
    double? rSquaredThreshold,
    bool? disableGuidingDuringAf,
    int? focuserSettleTimeMs,
    int? exposuresPerPoint,
    String? backlashCompMethod,
    int? backlashIn,
    int? backlashOut,
    String? autofocusFilterName,
    Map<String, FilterAutofocusConfig>? filterSettings,
  }) {
    return AutofocusSettings(
      method: method ?? this.method,
      curveFitting: curveFitting ?? this.curveFitting,
      stepSize: stepSize ?? this.stepSize,
      exposureTime: exposureTime ?? this.exposureTime,
      initialOffsetSteps: initialOffsetSteps ?? this.initialOffsetSteps,
      numberOfAttempts: numberOfAttempts ?? this.numberOfAttempts,
      useBrightestNStars: useBrightestNStars ?? this.useBrightestNStars,
      outerCropRatio: outerCropRatio ?? this.outerCropRatio,
      innerCropRatio: innerCropRatio ?? this.innerCropRatio,
      binning: binning ?? this.binning,
      rSquaredThreshold: rSquaredThreshold ?? this.rSquaredThreshold,
      disableGuidingDuringAf:
          disableGuidingDuringAf ?? this.disableGuidingDuringAf,
      focuserSettleTimeMs: focuserSettleTimeMs ?? this.focuserSettleTimeMs,
      exposuresPerPoint: exposuresPerPoint ?? this.exposuresPerPoint,
      backlashCompMethod: backlashCompMethod ?? this.backlashCompMethod,
      backlashIn: backlashIn ?? this.backlashIn,
      backlashOut: backlashOut ?? this.backlashOut,
      autofocusFilterName: autofocusFilterName ?? this.autofocusFilterName,
      filterSettings: filterSettings ?? this.filterSettings,
    );
  }

  /// Parse filter settings from a JSON string stored in the database.
  ///
  /// Returns an empty map if the JSON is malformed rather than crashing,
  /// but logs a warning so the corruption is visible.
  static Map<String, FilterAutofocusConfig> parseFilterSettingsJson(
      String jsonStr) {
    if (jsonStr.isEmpty || jsonStr == '{}') return {};
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final result = <String, FilterAutofocusConfig>{};
      for (final entry in decoded.entries) {
        try {
          result[entry.key] = FilterAutofocusConfig.fromJson(
              entry.value as Map<String, dynamic>);
        } catch (e) {
          // Skip malformed individual filter entries rather than losing all data
          assert(() {
            developer.log(
              'Skipping malformed filter config for "${entry.key}": $e',
              name: 'ImagingModels',
              level: 900,
            );
            return true;
          }());
        }
      }
      return result;
    } catch (e) {
      // Corrupted JSON in DB — return empty rather than crashing the app.
      // The next save will overwrite the corrupt data with valid JSON.
      assert(() {
        developer.log(
          'Failed to parse af_filter_settings JSON: $e',
          name: 'ImagingModels',
          level: 900,
        );
        return true;
      }());
      return {};
    }
  }

  /// Serialize filter settings to a JSON string for database storage.
  static String encodeFilterSettingsJson(
      Map<String, FilterAutofocusConfig> settings) {
    if (settings.isEmpty) return '{}';
    final map = settings.map((key, value) => MapEntry(key, value.toJson()));
    return jsonEncode(map);
  }

  @override
  List<Object?> get props => [
        method,
        curveFitting,
        stepSize,
        exposureTime,
        initialOffsetSteps,
        numberOfAttempts,
        useBrightestNStars,
        outerCropRatio,
        innerCropRatio,
        binning,
        rSquaredThreshold,
        disableGuidingDuringAf,
        focuserSettleTimeMs,
        exposuresPerPoint,
        backlashCompMethod,
        backlashIn,
        backlashOut,
        autofocusFilterName,
        filterSettings,
      ];
}
