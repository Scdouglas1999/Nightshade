import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../planning/target_scoring.dart';
import 'planetarium_providers.dart';

/// Provider for the target scoring service
final targetScoringServiceProvider = Provider<TargetScoringService>((ref) {
  final location = ref.watch(observerLocationProvider);
  final time = ref.watch(observationTimeProvider);
  final moonPos = ref.watch(moonPositionProvider);
  final moonInfo = ref.watch(moonInfoProvider);
  final twilight = ref.watch(twilightTimesProvider);

  return TargetScoringService(
    latitude: location.latitude,
    longitude: location.longitude,
    observationTime: time.time,
    moonPosition: (moonPos.$1, moonPos.$2),
    moonIllumination: moonInfo.illumination,
    twilight: twilight,
  );
});

/// Provider for scoring a single selected target
final selectedTargetScoreProvider = Provider<TargetScore?>((ref) {
  final selectedObject = ref.watch(selectedObjectProvider);
  if (selectedObject.object == null) return null;

  final scoringService = ref.watch(targetScoringServiceProvider);
  return scoringService.scoreTarget(selectedObject.object!);
});

/// Provider for the best targets for tonight
final tonightsBestTargetsProvider =
    FutureProvider<List<TargetScore>>((ref) async {
  final dsos = await ref.watch(loadedDsosProvider.future);
  final scoringService = ref.watch(targetScoringServiceProvider);

  // Score all DSOs
  final scores = scoringService.scoreTargets(dsos);

  // Return top 20 targets with score > 40
  return scores.where((s) => s.totalScore > 40).take(20).toList();
});

/// Alert state for target warnings
class TargetAlertState {
  final List<TargetWarning> activeWarnings;
  final bool hasAltitudeAlert;
  final bool hasMoonAlert;
  final bool hasSettingAlert;

  const TargetAlertState({
    this.activeWarnings = const [],
    this.hasAltitudeAlert = false,
    this.hasMoonAlert = false,
    this.hasSettingAlert = false,
  });

  bool get hasAnyAlert =>
      hasAltitudeAlert || hasMoonAlert || hasSettingAlert;

  int get alertCount =>
      (hasAltitudeAlert ? 1 : 0) +
      (hasMoonAlert ? 1 : 0) +
      (hasSettingAlert ? 1 : 0);
}

/// Provider for real-time alerts on the currently selected/active target
final targetAlertProvider = Provider<TargetAlertState>((ref) {
  final score = ref.watch(selectedTargetScoreProvider);
  if (score == null) return const TargetAlertState();

  final warnings = score.warnings;

  return TargetAlertState(
    activeWarnings: warnings,
    hasAltitudeAlert: warnings.any((w) =>
        w.type == WarningType.lowAltitude ||
        w.type == WarningType.belowHorizon),
    hasMoonAlert: warnings.any((w) => w.type == WarningType.moonProximity),
    hasSettingAlert: warnings.any((w) => w.type == WarningType.settingSoon),
  );
});

/// Moon proximity info for the selected target
class MoonProximityInfo {
  final double distance;
  final double moonIllumination;
  final bool isTooClose;
  final String recommendation;

  const MoonProximityInfo({
    required this.distance,
    required this.moonIllumination,
    required this.isTooClose,
    required this.recommendation,
  });
}

/// Provider for moon proximity information for the selected target
final moonProximityProvider = Provider<MoonProximityInfo?>((ref) {
  final selectedObject = ref.watch(selectedObjectProvider);
  if (selectedObject.object == null) return null;

  final scoringService = ref.watch(targetScoringServiceProvider);
  final moonInfo = ref.watch(moonInfoProvider);

  final distance = scoringService.getMoonDistance(selectedObject.object!);
  final isTooClose = scoringService.isMoonTooClose(selectedObject.object!);

  String recommendation;
  if (moonInfo.illumination < 20) {
    recommendation = 'New moon - excellent for broadband imaging';
  } else if (isTooClose) {
    if (distance < 15) {
      recommendation = 'Too close to moon - consider a different target';
    } else {
      recommendation = 'Moon glow may affect image - use narrowband filters';
    }
  } else if (moonInfo.illumination > 70 && distance < 60) {
    recommendation = 'Bright moon nearby - narrowband recommended';
  } else if (moonInfo.illumination > 50) {
    recommendation = 'Moon is bright - check for sky glow';
  } else {
    recommendation = 'Moon conditions acceptable';
  }

  return MoonProximityInfo(
    distance: distance,
    moonIllumination: moonInfo.illumination,
    isTooClose: isTooClose,
    recommendation: recommendation,
  );
});

/// Altitude trend info
enum AltitudeTrend { rising, setting, transiting, belowHorizon }

class AltitudeInfo {
  final double currentAltitude;
  final double? transitAltitude;
  final AltitudeTrend trend;
  final Duration? timeToTransit;
  final Duration? timeToSet;
  final double airmass;

  const AltitudeInfo({
    required this.currentAltitude,
    this.transitAltitude,
    required this.trend,
    this.timeToTransit,
    this.timeToSet,
    required this.airmass,
  });

  bool get isGoodForImaging =>
      currentAltitude >= 30 && airmass <= 2.0;

  bool get isAcceptable =>
      currentAltitude >= 15 && airmass <= 3.0;
}

/// Provider for altitude information for the selected target
final altitudeInfoProvider = Provider<AltitudeInfo?>((ref) {
  final score = ref.watch(selectedTargetScoreProvider);
  if (score == null) return null;

  final vis = score.visibility;
  final time = ref.watch(observationTimeProvider).time;

  AltitudeTrend trend;
  Duration? timeToTransit;
  Duration? timeToSet;

  if (vis.currentAltitude < 0) {
    trend = AltitudeTrend.belowHorizon;
  } else if (vis.transitTime != null) {
    final transitDiff = vis.transitTime!.difference(time);
    if (transitDiff.inMinutes.abs() < 30) {
      trend = AltitudeTrend.transiting;
    } else if (transitDiff.isNegative) {
      trend = AltitudeTrend.setting;
    } else {
      trend = AltitudeTrend.rising;
    }
    timeToTransit = transitDiff.isNegative ? null : transitDiff;
  } else {
    // No transit info - use azimuth to guess
    trend = vis.currentAzimuth < 180
        ? AltitudeTrend.rising
        : AltitudeTrend.setting;
  }

  if (vis.setTime != null && vis.currentAltitude > 0) {
    final setDiff = vis.setTime!.difference(time);
    if (!setDiff.isNegative) {
      timeToSet = setDiff;
    }
  }

  return AltitudeInfo(
    currentAltitude: vis.currentAltitude,
    transitAltitude: vis.transitAltitude,
    trend: trend,
    timeToTransit: timeToTransit,
    timeToSet: timeToSet,
    airmass: vis.airmass,
  );
});
