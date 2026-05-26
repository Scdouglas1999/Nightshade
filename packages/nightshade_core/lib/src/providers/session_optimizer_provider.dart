import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/guide_rms_history_dao.dart';
import '../database/daos/settings_dao.dart';
import '../models/planning/target_suggestion.dart';
import '../services/scheduler/integration_goal_service.dart';
import '../services/logging_service.dart';
import '../services/smart_night/exposure_calculator.dart';
import '../services/smart_night/hardware_specs_service.dart';
import '../services/session_optimizer_service.dart';
import '../services/smart_night_service.dart';
import 'database_provider.dart';
import 'equipment/filter_wheel_state_provider.dart';
import 'profiles_provider.dart';
import 'session_report_provider.dart';
import 'settings_provider.dart';
import 'target_suggestion_provider.dart';

/// Service provider for SessionOptimizerService.
///
/// Depends on [targetSuggestionServiceProvider] which is injected via the
/// service constructor.
final sessionOptimizerServiceProvider =
    Provider<SessionOptimizerService>((ref) {
  final suggestionService = ref.watch(targetSuggestionServiceProvider);
  return SessionOptimizerService(suggestionService: suggestionService);
});

final hardwareSpecsServiceProvider = Provider<HardwareSpecsService>(
  (_) => const HardwareSpecsService(),
);

/// Builds the Smart Night exposure context used by Plan Tonight and dashboard
/// recommendations.
///
/// Missing camera sensor/spec values are surfaced as caveats instead of being
/// silently guessed. Missing telescope focal length or aperture disables the
/// Smart Night path because the physics model cannot be made meaningful.
final smartNightExposureContextProvider =
    FutureProvider.autoDispose<SmartNightExposureContext?>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  final opticalConfig = ref.watch(opticalConfigProvider);
  final profile = ref.watch(activeEquipmentProfileProvider);
  final effectiveFilters = ref.watch(effectiveFiltersProvider);
  final guideStats = await _weightedGuideRmsForMount(
    ref.watch(guideRmsHistoryDaoProvider),
    profile?.mountId,
  );

  final focalLength = opticalConfig?.focalLength ?? profile?.focalLength;
  final aperture = opticalConfig?.aperture ?? profile?.aperture;
  if (focalLength == null ||
      focalLength <= 0 ||
      aperture == null ||
      aperture <= 0) {
    return null;
  }

  final dao = ref.watch(settingsDaoProvider);
  final caveats = <String>[];
  final hardwareOverrides = await _readCameraHardwareOverrides(dao, caveats);
  final hardwareSpecs = hardwareOverrides.isEmpty
      ? ref.watch(hardwareSpecsServiceProvider)
      : ref
          .watch(hardwareSpecsServiceProvider)
          .withCameraOverrides(hardwareOverrides);
  final hardwareMatch = hardwareSpecs.matchCamera(
    cameraName: profile?.cameraName,
    cameraId: profile?.cameraId,
    gain: profile?.defaultGain,
  );

  final readNoise = await _readDoubleSetting(
    dao,
    'science.camera.read_noise_e',
  );
  final fullWell = await _readDoubleSetting(
    dao,
    'smart_night.camera.full_well_e',
  );
  final qePeak = await _readDoubleSetting(
    dao,
    'smart_night.camera.qe_peak',
  );
  final gloverK = await _readDoubleSetting(
    dao,
    'smart_night.glover_k_factor',
  );
  var pixelSize = opticalConfig?.pixelSize;
  if (pixelSize == null || pixelSize <= 0) {
    pixelSize = hardwareMatch?.pixelSizeMicrons;
    if (pixelSize == null || pixelSize <= 0) {
      pixelSize = 3.76;
      caveats.add(
        'Camera pixel size is unavailable; using a 3.76 micron planning estimate.',
      );
    }
  }

  final hardwareCamera = hardwareMatch?.exposureSpec;
  final effectiveReadNoise = readNoise ?? hardwareCamera?.readNoiseE ?? 3.5;
  if (readNoise == null && hardwareCamera == null) {
    caveats.add(
      'Camera read noise is not configured; using a conservative 3.5e- planning estimate.',
    );
  }

  final effectiveFullWell = fullWell ?? hardwareCamera?.fullWellE ?? 18000.0;
  if (fullWell == null && hardwareCamera == null) {
    caveats.add(
      'Camera full well is not configured; using an 18,000e- planning estimate.',
    );
  }

  final effectiveQePeak = qePeak ?? hardwareCamera?.qePeak ?? 0.65;
  if (qePeak == null && hardwareCamera == null) {
    caveats.add(
      'Camera QE is not configured; using a 65% planning estimate.',
    );
  }

  return SmartNightExposureContext(
    camera: CameraExposureSpec(
      readNoiseE: effectiveReadNoise,
      fullWellE: effectiveFullWell,
      qePeak: effectiveQePeak.clamp(0.05, 1.0).toDouble(),
    ),
    bortleClass: settings.bortleClass,
    focalLengthMm: focalLength,
    apertureMm: aperture,
    pixelSizeMicrons: pixelSize,
    availableFilterNames:
        effectiveFilters.isNotEmpty ? effectiveFilters : (profile?.filterNames ?? const []),
    guideRmsArcsec: guideStats.rmsArcsec,
    guideSampleCount: guideStats.sampleCount,
    gloverKFactor: gloverK ?? 10,
    targetSnr: settings.smartNightTargetSnr,
    userCapSeconds: settings.smartNightSubExposureCeilingSecs,
    floorSeconds: settings.smartNightSubExposureFloorSecs,
    caveats: caveats,
  );
});

Future<List<CameraHardwareSpec>> _readCameraHardwareOverrides(
  SettingsDao dao,
  List<String> caveats,
) async {
  final raw =
      await dao.getSetting(HardwareSpecsService.cameraOverridesSettingKey);
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    return HardwareSpecsService.cameraOverridesFromJson(jsonDecode(raw));
  } catch (_) {
    caveats.add(
      'Camera hardware overrides could not be parsed; using bundled specs or planning estimates.',
    );
    return const [];
  }
}

/// Wave 7 — Dismissed insight ids (sticky "Don't suggest this again").
///
/// Persisted under `session_insights.dismissed` as a comma-joined list of
/// insight ids. The DAO is the same `app_settings` table used elsewhere,
/// so the lifecycle matches: cleared on a database wipe, otherwise
/// survives app restarts.
class _DismissedInsightsNotifier extends AsyncNotifier<Set<String>> {
  static const _key = 'session_insights.dismissed';

  @override
  Future<Set<String>> build() async {
    final dao = ref.watch(settingsDaoProvider);
    final raw = await dao.getSetting(_key) ?? '';
    if (raw.trim().isEmpty) return <String>{};
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  Future<void> dismiss(String id) async {
    final dao = ref.read(settingsDaoProvider);
    final current = state.valueOrNull ?? <String>{};
    final updated = {...current, id};
    await dao.setSetting(_key, updated.join(','));
    state = AsyncValue.data(updated);
  }

  Future<void> undismiss(String id) async {
    final dao = ref.read(settingsDaoProvider);
    final current = state.valueOrNull ?? <String>{};
    if (!current.contains(id)) return;
    final updated = {...current}..remove(id);
    await dao.setSetting(_key, updated.join(','));
    state = AsyncValue.data(updated);
  }

  Future<void> clear() async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(_key, '');
    state = const AsyncValue.data(<String>{});
  }
}

/// Wave 7 — Operator's "Don't suggest this again" set.
final dismissedSessionInsightsProvider =
    AsyncNotifierProvider<_DismissedInsightsNotifier, Set<String>>(
  _DismissedInsightsNotifier.new,
);

/// Wave 7 — Retrospective post-session insights for the given session id.
///
/// Computes [SessionInsight]s from the persisted [SessionReport] plus any
/// altitude traces produced at runtime. Today we cannot reliably
/// reconstruct per-second altitude history from the captured frames
/// alone (the database does not record sub-minute timestamps on every
/// frame), so the trace list is empty until a future provider populates
/// it from a session-altitude log table. The optimizer's other insight
/// kinds (autofocus frequency, filter overhead, rejection rate, guiding,
/// efficiency) still produce useful output without that trace data.
final sessionInsightsProvider =
    FutureProvider.autoDispose.family<List<SessionInsight>, int>(
  (ref, sessionId) async {
    final report = await ref.watch(sessionReportProvider(sessionId).future);
    final dismissed = await ref.watch(dismissedSessionInsightsProvider.future);
    final service = ref.watch(sessionOptimizerServiceProvider);
    return service.analyze(
      report: report,
      altitudeTraces: const <SessionTargetAltitudeTrace>[],
      thresholds: SessionInsightThresholds(
        dismissedIds: dismissed,
      ),
    );
  },
);

Future<double?> _readDoubleSetting(SettingsDao dao, String key) async {
  final raw = await dao.getSetting(key);
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = double.tryParse(raw);
  if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
  return parsed;
}

class _GuideRmsStats {
  final double? rmsArcsec;
  final int sampleCount;

  const _GuideRmsStats({
    this.rmsArcsec,
    this.sampleCount = 0,
  });
}

Future<_GuideRmsStats> _weightedGuideRmsForMount(
  GuideRmsHistoryDao dao,
  String? mountId,
) async {
  final trimmedMountId = mountId?.trim();
  if (trimmedMountId == null || trimmedMountId.isEmpty) {
    return const _GuideRmsStats();
  }

  final samples = await dao.recentForMount(trimmedMountId, limit: 20);
  if (samples.isEmpty) {
    return const _GuideRmsStats();
  }

  final recentCutoff = DateTime.now().subtract(const Duration(days: 30));
  var weightedRms = 0.0;
  var weightTotal = 0.0;
  for (final sample in samples) {
    if (sample.totalRmsArcsec <= 0 || !sample.totalRmsArcsec.isFinite) {
      continue;
    }
    final weight = sample.recordedAt.isAfter(recentCutoff) ? 2.0 : 1.0;
    weightedRms += sample.totalRmsArcsec * weight;
    weightTotal += weight;
  }

  if (weightTotal <= 0) {
    return _GuideRmsStats(sampleCount: samples.length);
  }

  return _GuideRmsStats(
    rmsArcsec: weightedRms / weightTotal,
    sampleCount: samples.length,
  );
}

/// Per-target Smart Night integration estimate for Plan Tonight rows.
final plannerTargetIntegrationPreviewProvider = FutureProvider.autoDispose
    .family<TargetIntegrationPreview?, int>((ref, targetId) async {
  final profile = ref.watch(activeEquipmentProfileProvider);
  if (profile == null) return null;

  final exposureContext =
      await ref.watch(smartNightExposureContextProvider.future);
  if (exposureContext == null) return null;

  final suggestions = ref.watch(tonightSuggestionsProvider).valueOrNull;
  if (suggestions == null) return null;

  TargetSuggestion? suggestion;
  for (final candidate in suggestions) {
    if (candidate.targetId == targetId) {
      suggestion = candidate;
      break;
    }
  }
  if (suggestion == null) return null;

  final settings = await ref.watch(appSettingsProvider.future);
  if (settings.latitude == 0.0 && settings.longitude == 0.0) return null;

  final filters = ref.watch(effectiveFiltersProvider);
  if (filters.isEmpty) return null;

  final window = SmartNightService(
    suggestionService: ref.read(targetSuggestionServiceProvider),
    logging: ref.read(loggingServiceProvider),
  ).calculateWindow(
    latitudeDeg: settings.latitude,
    longitudeDeg: settings.longitude,
  );

  final integrationGoals =
      await ref.read(integrationGoalServiceProvider).progressForTarget(
            targetId,
          );

  final smartNightSettings = SmartNightSettings(
    targetSnr: settings.smartNightTargetSnr,
    subExposureCeilingSecs: settings.smartNightSubExposureCeilingSecs,
    subExposureFloorSecs: settings.smartNightSubExposureFloorSecs,
  );

  return SmartNightService(
    suggestionService: ref.read(targetSuggestionServiceProvider),
    logging: ref.read(loggingServiceProvider),
  ).previewTargetIntegration(
    profile: profile,
    suggestion: suggestion,
    windowStart: window.start,
    windowEnd: window.end,
    availableFilters: filters,
    exposureContext: exposureContext,
    settings: smartNightSettings,
    integrationGoalProgress: integrationGoals,
  );
});
