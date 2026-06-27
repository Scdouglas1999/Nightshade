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
