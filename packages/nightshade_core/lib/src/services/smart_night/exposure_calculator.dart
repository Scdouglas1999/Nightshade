import 'dart:math' as math;

/// Explains which exposure ceiling selected the final sub length.
enum ExposureLimitingFactor {
  glover,
  saturation,
  mount,
  userCap,
  floor,
}

/// Camera values needed by the light-frame exposure calculator.
class CameraExposureSpec {
  final double readNoiseE;
  final double fullWellE;
  final double qePeak;

  const CameraExposureSpec({
    required this.readNoiseE,
    required this.fullWellE,
    required this.qePeak,
  });
}

/// Filter values needed by the light-frame exposure calculator.
class FilterExposureSpec {
  final String name;
  final double bandwidthNm;
  final double peakTransmission;

  const FilterExposureSpec({
    required this.name,
    required this.bandwidthNm,
    required this.peakTransmission,
  });

  const FilterExposureSpec.luminance()
      : name = 'L',
        bandwidthNm = 100,
        peakTransmission = 0.95;

  const FilterExposureSpec.narrowbandHa()
      : name = 'Ha',
        bandwidthNm = 3,
        peakTransmission = 0.9;

  factory FilterExposureSpec.fromName(String? rawName) {
    final normalized = (rawName ?? '').trim().toLowerCase();
    if (normalized == 'ha' ||
        normalized == 'h-alpha' ||
        normalized == 'halpha' ||
        normalized.contains('hydrogen')) {
      return const FilterExposureSpec.narrowbandHa();
    }
    if (normalized == 'oiii' ||
        normalized == 'o-iii' ||
        normalized == 'oxygen iii') {
      return const FilterExposureSpec(
        name: 'OIII',
        bandwidthNm: 3,
        peakTransmission: 0.9,
      );
    }
    if (normalized == 'sii' ||
        normalized == 's-ii' ||
        normalized == 'sulfur ii' ||
        normalized == 'sulphur ii') {
      return const FilterExposureSpec(
        name: 'SII',
        bandwidthNm: 3,
        peakTransmission: 0.9,
      );
    }
    if (normalized.contains('l-extreme') ||
        normalized.contains('lextreme') ||
        normalized.contains('l-ultimate') ||
        normalized.contains('lultimate') ||
        normalized.contains('l-enhance') ||
        normalized.contains('lenhance')) {
      return FilterExposureSpec(
        name:
            rawName?.trim().isNotEmpty == true ? rawName!.trim() : 'Multi-band',
        bandwidthNm: normalized.contains('ultimate') ? 3 : 7,
        peakTransmission: 0.9,
      );
    }
    if (normalized == 'r' ||
        normalized == 'red' ||
        normalized == 'g' ||
        normalized == 'green' ||
        normalized == 'b' ||
        normalized == 'blue') {
      return FilterExposureSpec(
        name: rawName?.trim().isNotEmpty == true ? rawName!.trim() : 'RGB',
        bandwidthNm: 80,
        peakTransmission: 0.9,
      );
    }
    return FilterExposureSpec(
      name: rawName?.trim().isNotEmpty == true ? rawName!.trim() : 'L',
      bandwidthNm: 100,
      peakTransmission: 0.95,
    );
  }
}

class ExposureCalculatorInput {
  final CameraExposureSpec camera;
  final FilterExposureSpec filter;
  final int bortleClass;
  final double focalLengthMm;
  final double apertureMm;
  final double pixelSizeMicrons;
  final double? guideRmsArcsec;
  final int guideSampleCount;
  final double gloverKFactor;
  final double targetSnr;
  final double saturationTargetFraction;
  final double userCapSeconds;
  final double floorSeconds;

  const ExposureCalculatorInput({
    required this.camera,
    required this.filter,
    required this.bortleClass,
    required this.focalLengthMm,
    required this.apertureMm,
    required this.pixelSizeMicrons,
    this.guideRmsArcsec,
    this.guideSampleCount = 0,
    this.gloverKFactor = 10,
    this.targetSnr = 30,
    this.saturationTargetFraction = 0.7,
    this.userCapSeconds = 300,
    this.floorSeconds = 60,
  });
}

class ExposureRecommendation {
  final double seconds;
  final ExposureLimitingFactor limitingFactor;
  final Map<ExposureLimitingFactor, double> allCeilings;
  final String rationale;
  final List<String> caveats;

  const ExposureRecommendation({
    required this.seconds,
    required this.limitingFactor,
    required this.allCeilings,
    required this.rationale,
    required this.caveats,
  });
}

/// Physics-based light-frame sub-exposure calculator for Plan Tonight.
///
/// This implements the Smart Night design's four-ceiling model:
/// sky-limited Glover length, star saturation, mount tracking, and user caps.
class SmartNightExposureCalculator {
  const SmartNightExposureCalculator();

  static const Map<int, double> _bortleMagPerArcsec2 = {
    1: 22.0,
    2: 21.7,
    3: 21.3,
    4: 20.8,
    5: 20.3,
    6: 19.5,
    7: 18.8,
    8: 18.2,
    9: 17.8,
  };

  // Integrated 0-mag photon flux over the reference broadband passband. This
  // keeps the Bortle 5 / 3 nm Ha fixture in the 300-450 s Glover range from
  // the approved design while preserving monotonic sky-brightness behavior.
  static const double _zeroMagPhotonFluxPerCm2PerSec = 2500000;
  static const double _referenceBandwidthNm = 100;
  static const double _brightestPixelFluxFraction = 0.01;
  static const double _referenceSaturationStarMagnitude = 10;
  static const int _minGuideSamplesForMountLimit = 3;

  ExposureRecommendation recommend(ExposureCalculatorInput input) {
    _validate(input);

    final pixelScale = 206.265 * input.pixelSizeMicrons / input.focalLengthMm;
    final skyRate = _skyElectronsPerSecondPerPixel(input, pixelScale);
    final snrScale = math.pow(input.targetSnr / 30.0, 2).toDouble();
    final glover = input.gloverKFactor *
        snrScale *
        input.camera.readNoiseE *
        input.camera.readNoiseE /
        skyRate;
    final saturation = _saturationCeiling(input);

    final ceilings = <ExposureLimitingFactor, double>{
      ExposureLimitingFactor.glover: glover,
      ExposureLimitingFactor.saturation: saturation,
      ExposureLimitingFactor.userCap: input.userCapSeconds,
    };

    final caveats = <String>[];
    if (input.guideRmsArcsec != null && input.guideRmsArcsec! > 0) {
      if (input.guideSampleCount >= _minGuideSamplesForMountLimit) {
        final maxTrailArcsec = 1.5 * pixelScale;
        ceilings[ExposureLimitingFactor.mount] =
            maxTrailArcsec / (2 * input.guideRmsArcsec!) * 60;
      } else {
        caveats.add(
          'Mount limit not applied: need 3 guided sessions for this mount.',
        );
      }
    }

    var limitingFactor = ExposureLimitingFactor.glover;
    var selected = ceilings[limitingFactor]!;
    for (final entry in ceilings.entries) {
      if (entry.value < selected) {
        limitingFactor = entry.key;
        selected = entry.value;
      }
    }

    var seconds = selected;
    if (seconds < input.floorSeconds) {
      limitingFactor = ExposureLimitingFactor.floor;
      seconds = input.floorSeconds;
    }

    final rounded = _roundExposure(seconds);
    return ExposureRecommendation(
      seconds: rounded,
      limitingFactor: limitingFactor,
      allCeilings: Map.unmodifiable(ceilings),
      rationale: _rationale(
        limitingFactor,
        rounded,
        input,
        ceilings,
      ),
      caveats: List.unmodifiable(caveats),
    );
  }

  static void _validate(ExposureCalculatorInput input) {
    if (input.camera.readNoiseE <= 0 ||
        input.camera.fullWellE <= 0 ||
        input.camera.qePeak <= 0 ||
        input.focalLengthMm <= 0 ||
        input.apertureMm <= 0 ||
        input.pixelSizeMicrons <= 0 ||
        input.filter.bandwidthNm <= 0 ||
        input.filter.peakTransmission <= 0 ||
        input.gloverKFactor <= 0 ||
        input.targetSnr <= 0 ||
        input.saturationTargetFraction <= 0 ||
        input.userCapSeconds <= 0 ||
        input.floorSeconds <= 0 ||
        input.floorSeconds > input.userCapSeconds) {
      throw ArgumentError.value(
        input,
        'input',
        'Exposure calculator inputs must be positive and floor <= cap.',
      );
    }
  }

  static double _skyElectronsPerSecondPerPixel(
    ExposureCalculatorInput input,
    double pixelScaleArcsec,
  ) {
    final mag = _bortleMagPerArcsec2[input.bortleClass.clamp(1, 9)]!;
    final photonFlux =
        _zeroMagPhotonFluxPerCm2PerSec * math.pow(10, -0.4 * mag).toDouble();
    final pixelAreaArcsec2 = pixelScaleArcsec * pixelScaleArcsec;
    final apertureAreaCm2 =
        math.pi * (input.apertureMm / 20) * (input.apertureMm / 20);
    final bandpassScale = input.filter.bandwidthNm / _referenceBandwidthNm;

    return (photonFlux *
            pixelAreaArcsec2 *
            apertureAreaCm2 *
            input.camera.qePeak *
            input.filter.peakTransmission *
            bandpassScale)
        .clamp(1e-9, double.infinity)
        .toDouble();
  }

  static double _saturationCeiling(ExposureCalculatorInput input) {
    final starFlux = _zeroMagPhotonFluxPerCm2PerSec *
        math.pow(10, -0.4 * _referenceSaturationStarMagnitude).toDouble();
    final apertureAreaCm2 =
        math.pi * (input.apertureMm / 20) * (input.apertureMm / 20);
    final bandpassScale = input.filter.bandwidthNm / _referenceBandwidthNm;
    final peakPixelElectronsPerSec = starFlux *
        apertureAreaCm2 *
        input.camera.qePeak *
        input.filter.peakTransmission *
        bandpassScale *
        _brightestPixelFluxFraction;

    return (input.saturationTargetFraction * input.camera.fullWellE) /
        peakPixelElectronsPerSec.clamp(1e-9, double.infinity);
  }

  static double _roundExposure(double seconds) {
    if (seconds <= 120) {
      return (seconds / 5).round() * 5.0;
    }
    return (seconds / 30).round() * 30.0;
  }

  static String _rationale(
    ExposureLimitingFactor factor,
    double seconds,
    ExposureCalculatorInput input,
    Map<ExposureLimitingFactor, double> ceilings,
  ) {
    final filter = input.filter.name;
    switch (factor) {
      case ExposureLimitingFactor.glover:
        return '$filter sub length set to ${seconds.toStringAsFixed(0)}s by sky-limited Glover SNR ${input.targetSnr.toStringAsFixed(0)} math.';
      case ExposureLimitingFactor.saturation:
        return '$filter sub length set to ${seconds.toStringAsFixed(0)}s to protect bright star cores.';
      case ExposureLimitingFactor.mount:
        return '$filter sub length set to ${seconds.toStringAsFixed(0)}s by recent mount guiding RMS.';
      case ExposureLimitingFactor.userCap:
        final glover = ceilings[ExposureLimitingFactor.glover];
        final suffix = glover == null
            ? ''
            : ' Glover would allow about ${glover.toStringAsFixed(0)}s.';
        return '$filter sub length limited by user cap at ${seconds.toStringAsFixed(0)}s.$suffix';
      case ExposureLimitingFactor.floor:
        return '$filter sub length raised to ${seconds.toStringAsFixed(0)}s floor to avoid excessive overhead.';
    }
  }
}
