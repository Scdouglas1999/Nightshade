import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/planning/night_forecast.dart';
import '../models/planning/project.dart';
import '../models/planning/project_progress.dart';
import '../models/scheduler/integration_goal.dart';
import '../services/planning/forecast_planning_service.dart';
import '../services/planning/project_service.dart';
import '../services/scheduler/integration_goal_service.dart';
import '../services/weather/providers/openmeteo_cloud_provider.dart';
import '../services/weather/radar_provider.dart';
import 'database_provider.dart';
import 'scheduler_provider.dart';
import 'settings_provider.dart';

/// Riverpod plumbing for the multi-night planner (component C6).
///
/// Wires the already-built planning services ([ProjectService] /
/// [ForecastPlanningService]) and the [OpenMeteoCloudProvider] forecast feed
/// into the provider graph the planner UI consumes:
///
///   * [activeProjectIdProvider] — the operator's currently-focused project,
///     persisted across launches in `app_settings`.
///   * [projectListProvider] — the live list of projects, re-listed on every
///     [ProjectService] mutation.
///   * [projectProgressProvider] — per-project accrued-vs-remaining roll-up
///     that recomputes whenever captures, goals, or membership change.
///   * [activeProjectProgressProvider] — the roll-up for the active project.
///   * [weekForecastProvider] — the seven-night "This Week" forecast scored
///     against the active project's still-incomplete targets.
///
/// Fail-closed throughout: a missing observing location throws (matching the
/// planner screen's `_plannerOptimizationProvider`), and a forecast-feed
/// failure surfaces as [WeekForecast.unavailable] rather than a fabricated
/// clear week.

/// `app_settings` key backing [activeProjectIdProvider]. Stored as the decimal
/// project id; an absent row or an empty string means "no active project".
const String _activeProjectIdSettingKey = 'planning.active_project_id';

/// Persisted selection of the operator's currently-focused project.
///
/// Mirrors the single-value-persisted-via-`settingsDao` pattern used by the
/// onboarding draft and other selections: the notifier hydrates from
/// `app_settings` on construction and writes back on every [setActiveProject].
/// `null` means no project is active.
final activeProjectIdProvider =
    StateNotifierProvider<ActiveProjectNotifier, int?>((ref) {
  final notifier = ActiveProjectNotifier(ref);
  // Kick off the async hydrate immediately. Until it resolves the state is
  // `null` (no active project), which is the correct cold-start default.
  notifier._load();
  return notifier;
});

/// State notifier owning the active-project selection and its persistence.
class ActiveProjectNotifier extends StateNotifier<int?> {
  ActiveProjectNotifier(this._ref) : super(null);

  final Ref _ref;
  bool _isLoaded = false;
  Completer<void>? _loadCompleter;

  /// True once the persisted selection (if any) has been read into [state].
  bool get isLoaded => _isLoaded;

  /// Resolves when the initial load is done. Awaited by tests that need to be
  /// certain of the hydrated state before asserting.
  Future<void> get loaded {
    if (_isLoaded) return Future<void>.value();
    _loadCompleter ??= Completer<void>();
    return _loadCompleter!.future;
  }

  Future<void> _load() async {
    try {
      final settingsDao = _ref.read(settingsDaoProvider);
      final raw = await settingsDao.getSetting(_activeProjectIdSettingKey);
      final parsed = _parse(raw);
      if (parsed != null && mounted) {
        state = parsed;
      }
    } finally {
      _isLoaded = true;
      _loadCompleter?.complete();
      _loadCompleter = null;
    }
  }

  /// Parse the stored value. Null/empty/whitespace and non-numeric values all
  /// resolve to "no active project" — a corrupt row is treated as unset rather
  /// than throwing, since the selection is a soft UI focus, not load-bearing
  /// data. A non-positive id is likewise rejected (row ids are AUTOINCREMENT,
  /// hence always >= 1).
  static int? _parse(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final value = int.tryParse(trimmed);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// Select (or clear, with `null`) the active project and persist it. Passing
  /// the id that is already active is a no-op write-through (kept idempotent so
  /// callers need not pre-check).
  Future<void> setActiveProject(int? id) async {
    if (mounted) {
      state = id;
    }
    final settingsDao = _ref.read(settingsDaoProvider);
    if (id == null) {
      await settingsDao.setSetting(_activeProjectIdSettingKey, '');
    } else {
      await settingsDao.setSetting(_activeProjectIdSettingKey, id.toString());
    }
  }
}

/// Live list of every project, most-recently-updated first.
///
/// The `projects` / `project_targets` tables are raw-SQL and invisible to
/// Drift's reactive graph, so we mirror [integrationGoalsStreamProvider]'s
/// pattern: bridge [ProjectService.watchChanges] (a `void` change-notification
/// stream) into a `List<Project>` stream by emitting the current list once up
/// front and then re-listing on each mutation.
final projectListProvider = StreamProvider<List<Project>>((ref) {
  final service = ref.watch(projectServiceProvider);

  Stream<List<Project>> listOnChange() async* {
    // Initial emit so the UI has data before the first mutation.
    yield await service.listProjects();
    await for (final _ in service.watchChanges()) {
      yield await service.listProjects();
    }
  }

  return listOnChange();
});

/// Per-project accrued-vs-remaining roll-up.
///
/// Recomputes whenever any of the three inputs to [ProjectService.buildProgress]
/// change:
///   * `captured_images` ([allDbImagesProvider]) — accrued frames are derived
///     live from history, so a new (or deleted/re-graded) frame must refresh
///     the roll-up;
///   * integration goals ([integrationGoalsStreamProvider]) — editing a goal
///     changes the remaining count;
///   * project membership ([projectListProvider], which fires on every
///     [ProjectService] mutation including add/remove target) — attaching or
///     detaching a target changes which targets roll up.
///
/// `autoDispose` so a closed project detail view stops recomputing.
final projectProgressProvider =
    FutureProvider.autoDispose.family<CampaignProgress, int>((ref, id) {
  ref.watch(allDbImagesProvider);
  ref.watch(integrationGoalsStreamProvider);
  ref.watch(projectListProvider);
  return ref.watch(projectServiceProvider).buildProgress(id);
});

/// The roll-up for the active project, or `null` when no project is active.
///
/// Delegates to [projectProgressProvider] for the active id so the
/// recomputation triggers (captures / goals / membership) are inherited.
final activeProjectProgressProvider =
    FutureProvider.autoDispose<CampaignProgress?>((ref) async {
  final activeId = ref.watch(activeProjectIdProvider);
  if (activeId == null) return null;
  return ref.watch(projectProgressProvider(activeId).future);
});

/// Factory seam that builds the [OpenMeteoCloudProvider] used by
/// [weekForecastProvider].
///
/// In production this returns a provider backed by the default
/// `http.Client`. Tests override this provider to inject a fake `http.Client`
/// (e.g. a `MockClient`) so the forecast fetch can be driven without real
/// network access — including the error path that exercises the fail-closed
/// contract.
final planningCloudProviderFactoryProvider =
    Provider<OpenMeteoCloudProvider Function()>((ref) {
  return OpenMeteoCloudProvider.new;
});

/// Immutable (latitude, longitude) key for the cloud-fetch provider family.
///
/// Equality is by value so two reads at the same site share one cached fetch
/// result (and thus one HTTP round-trip) regardless of how many times the
/// downstream combiner rebuilds.
@immutable
class ForecastSite {
  final double latitude;
  final double longitude;

  const ForecastSite(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      other is ForecastSite &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// The hourly cloud feed for a site, keyed ONLY on (lat, lng).
///
/// Deliberately decoupled from the capture/goal/active-project triggers: a
/// seven-night cloud forecast does not change frame-to-frame, so it must not be
/// refetched every time a sub lands or a goal is tweaked. During an active
/// imaging run subs arrive every few minutes; coupling the fetch to them would
/// hammer the free (rate-limited) Open-Meteo endpoint and, once throttled,
/// degrade the forecast into a fail-closed "unavailable" state for the
/// operator. [weekForecastProvider] does the capture/goal-driven candidate
/// recompute and simply re-reads this cached [RadarFetchResult].
///
/// `autoDispose` so the feed (and its HTTP client) is torn down when the
/// planner view closes. Re-fetch on demand with
/// `ref.invalidate(weekForecastCloudProvider(site))` (the strip's Retry path
/// invalidates [weekForecastProvider], which transitively re-reads this).
final weekForecastCloudProvider = FutureProvider.autoDispose
    .family<RadarFetchResult, ForecastSite>((ref, site) async {
  // The provider owns an http.Client, so dispose it once we have the result to
  // avoid leaking a connection per fetch.
  final cloudProvider = ref.watch(planningCloudProviderFactoryProvider)();
  try {
    return await cloudProvider.fetchRadarFrames(
      latitude: site.latitude,
      longitude: site.longitude,
    );
  } finally {
    cloudProvider.dispose();
  }
});

/// The seven-night "This Week" forecast, scored against the active project's
/// still-incomplete targets.
///
/// Pipeline:
///   1. Read the observing location from [appSettingsProvider]. An unset
///      location (lat == 0 && lng == 0) throws [StateError] — the same
///      fail-loud guard the planner screen's `_plannerOptimizationProvider`
///      uses, since a forecast at (0,0) is meaningless.
///   2. Read the hourly cloud feed from [weekForecastCloudProvider] (keyed only
///      on the site). That provider owns the HTTP fetch; this combiner never
///      triggers a network call directly, so the capture/goal recompute below
///      reuses the cached frames instead of refetching. On a network/API
///      failure the feed is an error [RadarFetchResult], which the forecast
///      service maps to [WeekForecast.unavailable] (fail-closed — never a
///      fabricated clear week).
///   3. Assemble the [ProjectTargetCandidate] set, recomputing when captures /
///      goals / membership / active-project change:
///        * If a project is active, use its still-incomplete targets — the
///          ones the operator actually still needs data on. A target whose
///          goals are fully met is dropped (completion removes it from future
///          nights), so the week reflects remaining work.
///        * If no project is active, fall back to every catalog target with a
///          configured-but-unmet integration goal, so the strip is still
///          useful (a "what can I shoot this week" view) rather than empty.
///          We build this fallback from the integration-goal stack rather than
///          the scheduler candidate set because the candidate set does not
///          carry per-filter accrued-vs-goal progress, which is exactly the
///          "incomplete" signal we need here.
///   4. Build the week with [ForecastPlanningService.buildWeek].
///
/// `autoDispose` so the forecast is torn down when the planner view closes.
final weekForecastProvider =
    FutureProvider.autoDispose<WeekForecast>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  final lat = settings.latitude;
  final lng = settings.longitude;
  if (lat == 0.0 && lng == 0.0) {
    throw StateError(
      'Observing location is not configured. '
      'Set your latitude and longitude in Settings before using the '
      'multi-night forecast.',
    );
  }

  // Capture/goal/active-project triggers establish the candidate set. We read
  // them BEFORE the first await so the dependency edges are registered
  // synchronously (watching after a suspension is the documented Riverpod
  // foot-gun). These intentionally do NOT gate the cloud fetch — that lives in
  // weekForecastCloudProvider, keyed only on the site, so a new frame or a goal
  // edit recomputes only the candidate set and reuses the cached feed.
  ref.watch(allDbImagesProvider);
  ref.watch(integrationGoalsStreamProvider);
  final activeProjectId = ref.watch(activeProjectIdProvider);

  // Cloud feed — cached per site; capture/goal rebuilds reuse it.
  final cloudResult =
      await ref.watch(weekForecastCloudProvider(ForecastSite(lat, lng)).future);

  final candidates = await _incompleteCandidates(ref, activeProjectId);

  final service = ForecastPlanningService(
    latitudeDegrees: lat,
    longitudeDegrees: lng,
  );
  return service.buildWeek(
    cloudResult: cloudResult,
    targets: candidates,
    nowLocal: DateTime.now(),
  );
});

/// Build the [ProjectTargetCandidate] set the forecast scores visibility for.
///
/// When [activeProjectId] is non-null we use that project's incomplete
/// targets (via [ProjectService.buildProgress]); otherwise we fall back to
/// every catalog target carrying an unmet integration goal. In both cases each
/// candidate's `minAltitude` comes from the live `targets` row so the
/// "is it up?" test honors the operator's per-target altitude floor.
Future<List<ProjectTargetCandidate>> _incompleteCandidates(
  Ref ref,
  int? activeProjectId,
) async {
  final targetsDao = ref.read(targetsDaoProvider);

  if (activeProjectId != null) {
    final projectService = ref.read(projectServiceProvider);
    final progress = await projectService.buildProgress(activeProjectId);
    final candidates = <ProjectTargetCandidate>[];
    for (final tp in progress.incompleteTargets) {
      final row = await targetsDao.getTargetById(tp.targetId);
      // A membership pointing at a deleted target is a data-integrity error,
      // but buildProgress already throws on that case before we get here, so a
      // null here would be a genuine race; surface it rather than swallow.
      if (row == null) {
        throw StateError(
          'Active project $activeProjectId references target ${tp.targetId}, '
          'which no longer exists in the catalog',
        );
      }
      candidates.add(ProjectTargetCandidate(
        targetId: tp.targetId,
        name: tp.targetName,
        raHours: tp.raHours,
        decDegrees: tp.decDegrees,
        minAltitudeDeg: row.minAltitude,
      ));
    }
    return candidates;
  }

  // No active project: every catalog target with a configured-but-unmet goal.
  // We derive the unmet set from the integration-goal stack (the single source
  // of truth for accrued-vs-goal) keyed by target.
  final goalService = ref.read(integrationGoalServiceProvider);
  final goals = await goalService.listAll();
  if (goals.isEmpty) return const [];

  // Group goals by target and decide incompleteness: a target is incomplete if
  // ANY of its goals still has frames remaining. capturedFrameCount is the same
  // accrued-from-history primitive buildProgress uses, so the two paths agree.
  final goalsByTarget = <int, List<IntegrationGoal>>{};
  for (final goal in goals) {
    (goalsByTarget[goal.targetId] ??= <IntegrationGoal>[]).add(goal);
  }

  final candidates = <ProjectTargetCandidate>[];
  for (final entry in goalsByTarget.entries) {
    final targetId = entry.key;
    var incomplete = false;
    for (final goal in entry.value) {
      final captured = await goalService.capturedFrameCount(
        targetId: targetId,
        filter: goal.filter,
      );
      if (captured < goal.frameCount) {
        incomplete = true;
        break;
      }
    }
    if (!incomplete) continue;

    final row = await targetsDao.getTargetById(targetId);
    // A goal referencing a missing target is a data-integrity error — fail
    // loud rather than silently skip.
    if (row == null) {
      throw StateError(
        'Integration goal references target $targetId, which no longer exists '
        'in the catalog',
      );
    }
    candidates.add(ProjectTargetCandidate(
      targetId: targetId,
      name: row.name,
      raHours: row.ra,
      decDegrees: row.dec,
      minAltitudeDeg: row.minAltitude,
    ));
  }
  return candidates;
}
