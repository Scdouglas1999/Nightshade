import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/daos/settings_dao.dart';
import '../database/database.dart' as ndb;
import '../models/scheduler/integration_goal.dart';
import '../models/scheduler/scheduler_decision.dart';
import '../models/scheduler/scheduler_status.dart';
import '../models/scheduler/target_constraint.dart';
import '../models/planning/project.dart';
import '../models/readiness/readiness_models.dart';
import '../models/scheduler/scheduler_readiness.dart';
import '../models/equipment/equipment_models.dart' show DeviceConnectionState;
import '../models/sequence/active_plan_owner.dart';
import '../models/sequence/sequence_models.dart';
import '../services/planning/project_service.dart'
    show
        projectTargetsProjectIndexSql,
        projectTargetsSchemaSql,
        projectsSchemaSql;
import '../services/safe_rig_service.dart';
import '../services/disk_space_guard.dart' show kSafetyMarginBytes;
import '../services/scheduler/horizon_profile.dart';
import '../services/scheduler/integration_goal_service.dart';
import '../services/scheduler/scheduler_engine.dart';
import '../services/scheduler/target_constraint_service.dart';
import '../services/smart_night_models.dart' show smartNightPlanningFilters;
import 'backend_provider.dart';
import 'clock_provider.dart';
import 'database_provider.dart';
import 'disk_space_provider.dart';
import 'event_provider.dart';
import 'readiness_provider.dart';
import 'equipment/guider_state_provider.dart';
import 'weather_safety_provider.dart';
// Multi-night planning (component C6): the active-project selection and the
// live project list scope the scheduler's candidate set to one campaign and
// re-trigger evaluation when the operator switches projects or edits
// membership. The dependency is one-directional (planning_provider imports
// scheduler_provider, not the reverse) — only these read-only providers are
// pulled in here, so there is no cycle.
import 'planning_provider.dart'
    show activeProjectIdProvider, projectListProvider;
import 'profiles_provider.dart';
import 'sequence_provider.dart';
// Hide settings_provider's legacy 8-compass-point HorizonProfile so the
// scheduler's samples-based HorizonProfile from services/scheduler/
// horizon_profile.dart resolves unambiguously below.
import 'settings_provider.dart' hide HorizonProfile;
// Pull in NightshadeEvent + EventPayload tagged-union subtypes (freezed
// generates EventPayload_Guiding / EventPayload_Equipment as part-of-library
// classes, so a plain import surfaces them here).
import 'package:nightshade_bridge/nightshade_bridge.dart';

/// Stream that pushes engine trigger events derived from the native bridge.
/// Hooks weather / guiding / mount events into the engine without
/// introducing new event types (per the W6-SCHED coordination note).
final schedulerTriggerStreamProvider = Provider<Stream<SchedulerTriggerEvent>>((
  ref,
) {
  final controller = StreamController<SchedulerTriggerEvent>.broadcast();
  final sub = ref.listen<AsyncValue<NightshadeEvent>>(
    nightshadeEventsProvider,
    (previous, next) {
      next.whenData((event) {
        final mapped = _mapEventToTrigger(event);
        if (mapped != null) controller.add(mapped);
      });
    },
  );
  ref.onDispose(() {
    sub.close();
    controller.close();
  });
  return controller.stream;
});

SchedulerTriggerEvent? _mapEventToTrigger(NightshadeEvent event) {
  switch (event.category) {
    case EventCategory.safety:
      return SchedulerTriggerEvent.weatherChange;
    case EventCategory.guiding:
      // The payload distinguishes loss vs recovery; we surface both as
      // discrete triggers so the engine can react. A finer-grained
      // mapping can be added when the payload accessor is stable.
      final payload = event.payload;
      if (payload is EventPayload_Guiding) {
        final name = payload.field0.toString().toLowerCase();
        if (name.contains('lost') || name.contains('stopped')) {
          return SchedulerTriggerEvent.guidingLost;
        }
        if (name.contains('settled') || name.contains('started')) {
          return SchedulerTriggerEvent.guidingRecovered;
        }
      }
      return null;
    case EventCategory.equipment:
      final payload = event.payload;
      if (payload is EventPayload_Equipment) {
        final name = payload.field0.toString().toLowerCase();
        if (name.contains('parked')) return SchedulerTriggerEvent.mountParked;
        if (name.contains('unparked')) {
          return SchedulerTriggerEvent.mountUnparked;
        }
      }
      return null;
    case EventCategory.sequencer:
      // A natural whole-sequence completion means the autopilot's dispatched
      // work for the current target finished. Without reacting, the rig sits
      // idle until the next periodic tick (and never re-dispatches a
      // still-eligible target held by hysteresis). Match the precise
      // SequencerEvent_Completed type only: SequencerEvent_Stopped is the
      // scheduler's OWN stop when switching targets (reacting to it would make
      // a dispatch feedback loop), and Node/Target/ExposureCompleted are
      // sub-events, not the end of the run.
      final payload = event.payload;
      if (payload is EventPayload_Sequencer &&
          payload.field0 is SequencerEvent_Completed) {
        return SchedulerTriggerEvent.sequenceCompleted;
      }
      return null;
    case EventCategory.imaging:
    case EventCategory.system:
    case EventCategory.polarAlignment:
      return null;
  }
}

/// Bridges the engine's "I picked a target" decision to the existing
/// SequenceExecutor by loading the generated Sequence and starting it.
class _ExecutorSequenceSink implements SchedulerSequenceSink {
  final Ref _ref;

  // Capture the notifier eagerly at construction (where ref.read is legal).
  // releaseSequenceOwnership() runs from SchedulerEngine.dispose(), which fires
  // inside the schedulerEngineProvider onDispose — at that point ref functions
  // are forbidden (the provider's dependency changed before it rebuilt), so we
  // must NOT call _ref.read there. currentSequenceProvider is a global (non-
  // autoDispose) StateNotifierProvider, so this notifier instance is stable for
  // the container's lifetime and safe to cache.
  final CurrentSequenceNotifier _currentSequence;

  _ExecutorSequenceSink(this._ref)
    : _currentSequence = _ref.read(currentSequenceProvider.notifier);

  @override
  Future<void> dispatchSequence(Sequence sequence) async {
    // The scheduler dispatches generated sequences as part of its own autopilot
    // loop. Rather than silently discarding the operator's unsaved in-editor
    // work (the old discardUnsaved:true clobber), hand the editor slot to the
    // autopilot owner: takeOwnership STASHES the manual sequence on the first
    // hand-off and flips the owner to autopilot. stopSequence() restores it. A
    // re-dispatch while the autopilot already owns the slot (target switch) just
    // swaps the loaded plan without disturbing the stashed manual sequence.
    _currentSequence.takeOwnership(sequence, ActivePlanOwner.autopilot);
    final executor = _ref.read(sequenceExecutorProvider);
    await executor.start();
  }

  @override
  Future<void> pauseSequence() async {
    final executor = _ref.read(sequenceExecutorProvider);
    await executor.pause();
  }

  @override
  Future<void> resumeSequence() async {
    final executor = _ref.read(sequenceExecutorProvider);
    await executor.resume();
  }

  @override
  Future<void> stopSequence() async {
    final executor = _ref.read(sequenceExecutorProvider);
    await executor.stop();
  }

  @override
  Future<void> releaseSequenceOwnership() async {
    // Autopilot disengaged: restore manual ownership and the operator's stashed
    // unsaved sequence (a no-op if the autopilot never owned the slot). Uses the
    // cached notifier — this runs during schedulerEngineProvider disposal where
    // ref.read would throw "_didChangeDependency".
    _currentSequence.releaseOwnership();
  }

  @override
  Future<void> parkForEndOfNight() async {
    // End of night: park the mount so it stops tracking into the ground at
    // dawn, and notify the operator. We route through the shared
    // SafeRigService so this uses the same fail-closed, loudly-erroring park
    // path as the weather and low-disk watchdogs (pause sequence -> park mount,
    // with a CRITICAL notification summarizing what happened). We intentionally
    // do NOT close the dome/cover here: end-of-night is not a weather event,
    // and the operator's morning flats workflow may still need the optics open.
    //
    // SafeRigService throws a SafeRigException when a step fails (after
    // attempting every step). Errors are a feature — let it propagate to the
    // engine's evaluation lifecycle so a failed dawn-park surfaces loudly
    // rather than leaving the mount silently tracking past sunrise.
    final safeRig = _ref.read(safeRigServiceProvider);
    await safeRig.safeTheRig(
      reason: 'End of observing night — parking the mount',
      park: true,
      closeDome: false,
      closeCover: false,
    );
  }
}

/// Normalized target row fed into candidate assembly — sourced from the local
/// DB on the host, or from the host's REST catalog on a remote slave. Keeping
/// a single shape lets the local and remote loads share one assembly path.
class _LoaderTarget {
  final int id;
  final String name;
  final double raHours;
  final double decDegrees;
  final int priority;
  final String? objectType;
  final String? notes;

  const _LoaderTarget({
    required this.id,
    required this.name,
    required this.raHours,
    required this.decDegrees,
    required this.priority,
    required this.objectType,
    required this.notes,
  });

  _LoaderTarget copyWithPriority(int newPriority) => _LoaderTarget(
    id: id,
    name: name,
    raHours: raHours,
    decDegrees: decDegrees,
    priority: newPriority,
    objectType: objectType,
    notes: notes,
  );

  bool get isMosaicTarget {
    final haystack = '$name ${objectType ?? ''} ${notes ?? ''}'.toLowerCase();
    return haystack.contains('mosaic');
  }
}

/// Source of candidate targets for the engine: assembles the latest target
/// rows, their integration goals + captured counts, their constraints, and
/// the equipment filter list.
class SchedulerCandidateLoader {
  final Ref ref;

  SchedulerCandidateLoader(this.ref);

  /// Assemble the candidate set.
  ///
  /// When [projectId] is non-null the candidate set is restricted to the
  /// targets that belong to that planning project (component C6, multi-night
  /// planning): the catalog query is INNER-JOINed against `project_targets`,
  /// and each member's effective priority is the per-membership
  /// `priority_override` when present, falling back to the target's own global
  /// `priority`. When [projectId] is null the full catalog is loaded
  /// verbatim — the original behavior, so existing non-project users are
  /// unaffected.
  ///
  /// In both modes the goal/count/constraint/horizon assembly and the
  /// effective-filter list are identical; completed-goal rejection and
  /// remaining-need ranking still happen downstream in the engine's
  /// `scoreCandidate`, so a fully-imaged member target drops out of tonight's
  /// rotation even though it remains in the project.
  Future<List<SchedulerCandidate>> load({int? projectId}) async {
    final backendNotifier = ref.read(backendProvider.notifier);
    final backend = backendNotifier.currentBackend;
    void requireAuthority() {
      if (!backendNotifier.isCurrentBackend(backend)) {
        throw StateError(
          'Scheduler candidate load retired because the imaging backend changed',
        );
      }
    }

    // Snapshot equipment filters under the same backend authority as the
    // catalog. Reading this later, after remote awaits, could otherwise attach
    // the replacement host's filter wheel to the previous host's targets.
    final availableFilters = _availableFilters();
    final goalService = ref.read(integrationGoalServiceProvider);
    requireAuthority();

    // On a remote SLAVE the catalog/targets/constraints/horizons/project
    // membership all live in the HOST DB; the slave's local SQLite is empty.
    // Reading it would gate the autopilot preview with ZERO constraints and
    // ZERO custom horizons (silently wrong), and the project path's local
    // INNER JOIN would return no rows ("nothing eligible"). Source everything
    // from the host instead. goalService is already host-aware (above), so the
    // per-goal counts in the shared assembly loop are correct too.
    if (backend is NetworkBackend) {
      return _loadRemote(
        backend: backend,
        goalService: goalService,
        projectId: projectId,
        availableFilters: availableFilters,
        requireAuthority: requireAuthority,
      );
    }

    final db = ref.read(databaseProvider);

    // Make sure all three scheduler tables exist before we read them. The
    // integration-goal service already ensures its own schema; we ensure
    // the other two here using the shared DDL constants.
    await db.customStatement(targetConstraintsSchemaSql);
    requireAuthority();
    await db.customStatement(targetConstraintsTargetIndexSql);
    requireAuthority();
    await db.customStatement(horizonProfilesSchemaSql);
    requireAuthority();

    final List<QueryRow> targetRows;
    if (projectId != null) {
      // Defensive: the planner tables are created by the v40 migration, but a
      // fresh database built without migrations (or a scheduler tick that runs
      // before the planner UI has touched ProjectService) must still find them.
      // Re-running the DDL is a no-op on an existing schema (`IF NOT EXISTS`).
      // These constants are the canonical project DDL, owned by ProjectService.
      await db.customStatement(projectsSchemaSql);
      requireAuthority();
      await db.customStatement(projectTargetsSchemaSql);
      requireAuthority();
      await db.customStatement(projectTargetsProjectIndexSql);
      requireAuthority();

      // Restrict to the project's members. The effective priority is the
      // membership override when set, else the target's own priority — and we
      // order by that effective value so the engine sees project-scoped ranking.
      targetRows = await db
          .customSelect(
            'SELECT t.id, t.name, t.ra, t.dec, '
            'COALESCE(pt.priority_override, t.priority) AS priority, '
            't.object_type, t.notes '
            'FROM targets t '
            'INNER JOIN project_targets pt ON pt.target_id = t.id '
            'WHERE pt.project_id = ? '
            'ORDER BY priority DESC, t.name ASC',
            variables: [Variable.withInt(projectId)],
          )
          .get();
      requireAuthority();
    } else {
      targetRows = await db
          .customSelect(
            'SELECT id, name, ra, dec, priority, object_type, notes FROM targets ORDER BY priority DESC, name ASC',
          )
          .get();
      requireAuthority();
    }

    // Pre-fetch all constraints + horizon profiles in two queries.
    final constraintRows = await db
        .customSelect(
          'SELECT id, target_id, kind, payload_json, enabled FROM target_constraints WHERE enabled = 1',
        )
        .get();
    requireAuthority();
    final horizonRows = await db
        .customSelect('SELECT id, name, samples_json FROM horizon_profiles')
        .get();
    requireAuthority();

    final horizonProfiles = <int, HorizonProfile>{};
    for (final row in horizonRows) {
      final hp = HorizonProfile.fromRow(
        id: row.read<int>('id'),
        name: row.read<String>('name'),
        samplesJson: row.read<String>('samples_json'),
      );
      horizonProfiles[hp.id!] = hp;
    }

    final constraintsByTarget = <int, List<TargetConstraint>>{};
    for (final row in constraintRows) {
      final tc = TargetConstraint.fromRow(
        id: row.read<int>('id'),
        targetId: row.read<int>('target_id'),
        kindName: row.read<String>('kind'),
        payloadJson: row.read<String>('payload_json'),
        enabled: row.read<int>('enabled') == 1,
      );
      constraintsByTarget.putIfAbsent(tc.targetId, () => []).add(tc);
    }

    final targets = targetRows
        .map(
          (row) => _LoaderTarget(
            id: row.read<int>('id'),
            name: row.read<String>('name'),
            raHours: row.read<double>('ra'),
            decDegrees: row.read<double>('dec'),
            priority: row.read<int>('priority'),
            objectType: row.readNullable<String>('object_type'),
            notes: row.readNullable<String>('notes'),
          ),
        )
        .toList();

    return _assembleCandidates(
      targets: targets,
      constraintsByTarget: constraintsByTarget,
      horizonProfiles: horizonProfiles,
      goalService: goalService,
      availableFilters: availableFilters,
      requireAuthority: requireAuthority,
    );
  }

  /// Remote-SLAVE candidate load: every input comes from the HOST over REST
  /// instead of the slave's empty local DB. Targets/constraints/horizons and
  /// (for the project path) the membership join are mirrored from the host so
  /// the autopilot preview gates with the SAME constraints/horizons/scope the
  /// operator configured on the master — not an un-gated, always-eligible set.
  Future<List<SchedulerCandidate>> _loadRemote({
    required NetworkBackend backend,
    required IntegrationGoalService goalService,
    int? projectId,
    required List<String> availableFilters,
    required void Function() requireAuthority,
  }) async {
    // Host catalog rows, indexed by id.
    final rawTargets = await backend.getAllTargets();
    requireAuthority();
    final byId = <int, _LoaderTarget>{};
    for (final json in rawTargets) {
      final id = json['id'] as int?;
      if (id == null) continue;
      byId[id] = _LoaderTarget(
        id: id,
        name: json['name'] as String? ?? 'Untitled target',
        raHours: (json['ra'] as num?)?.toDouble() ?? 0.0,
        decDegrees: (json['dec'] as num?)?.toDouble() ?? 0.0,
        priority: json['priority'] as int? ?? 5,
        objectType: json['objectType'] as String?,
        notes: json['notes'] as String?,
      );
    }

    final List<_LoaderTarget> targets;
    if (projectId != null) {
      // Project scope: the membership rows carry the per-project priority
      // override; fall back to the target's own priority when unset.
      final memberships = await backend.getProjectTargets(projectId);
      requireAuthority();
      final scoped = <_LoaderTarget>[];
      for (final m in memberships) {
        final base = byId[m.targetId];
        if (base == null) continue;
        scoped.add(base.copyWithPriority(m.priorityOverride ?? base.priority));
      }
      scoped.sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        return byPriority != 0 ? byPriority : a.name.compareTo(b.name);
      });
      targets = scoped;
    } else {
      targets = byId.values.toList()
        ..sort((a, b) {
          final byPriority = b.priority.compareTo(a.priority);
          return byPriority != 0 ? byPriority : a.name.compareTo(b.name);
        });
    }

    // Host constraints (enabled only, matching the local query) + horizons.
    final allConstraints = await backend.getTargetConstraints();
    requireAuthority();
    final constraintsByTarget = <int, List<TargetConstraint>>{};
    for (final tc in allConstraints) {
      if (!tc.enabled) continue;
      constraintsByTarget.putIfAbsent(tc.targetId, () => []).add(tc);
    }
    final horizonProfiles = <int, HorizonProfile>{};
    final remoteHorizons = await backend.getHorizonProfiles();
    requireAuthority();
    for (final hp in remoteHorizons) {
      if (hp.id != null) horizonProfiles[hp.id!] = hp;
    }

    return _assembleCandidates(
      targets: targets,
      constraintsByTarget: constraintsByTarget,
      horizonProfiles: horizonProfiles,
      goalService: goalService,
      availableFilters: availableFilters,
      requireAuthority: requireAuthority,
    );
  }

  /// Shared candidate assembly used by both the local and remote loads. Pure
  /// over its inputs — only the goal counts come from [goalService] (already
  /// host-aware), so this is identical on host and slave.
  Future<List<SchedulerCandidate>> _assembleCandidates({
    required List<_LoaderTarget> targets,
    required Map<int, List<TargetConstraint>> constraintsByTarget,
    required Map<int, HorizonProfile> horizonProfiles,
    required IntegrationGoalService goalService,
    required List<String> availableFilters,
    required void Function() requireAuthority,
  }) async {
    final out = <SchedulerCandidate>[];
    for (final target in targets) {
      final id = target.id;
      final goals = await goalService.listForTarget(id);
      requireAuthority();
      final counts = <int>[];
      for (final g in goals) {
        counts.add(
          await goalService.capturedFrameCount(targetId: id, filter: g.filter),
        );
        requireAuthority();
      }
      final cs = constraintsByTarget[id] ?? const <TargetConstraint>[];
      // Only attach horizon profiles a constraint actually references —
      // saves the engine from copying the whole catalogue.
      final usedProfiles = <int, HorizonProfile>{};
      for (final ct in cs) {
        if (ct.kind == TargetConstraintKind.customHorizon &&
            ct.customHorizonId != null) {
          final hp = horizonProfiles[ct.customHorizonId];
          if (hp == null) {
            throw StateError(
              'Target $id references horizon profile ${ct.customHorizonId} which does not exist',
            );
          }
          usedProfiles[ct.customHorizonId!] = hp;
        }
      }

      out.add(
        SchedulerCandidate(
          targetId: id,
          name: target.name,
          raHours: target.raHours,
          decDegrees: target.decDegrees,
          userPriority: target.priority,
          goals: goals,
          capturedCounts: counts,
          constraints: cs,
          horizonProfiles: usedProfiles,
          availableFilters: availableFilters,
          isMosaicTarget: target.isMosaicTarget,
        ),
      );
    }
    requireAuthority();
    return out;
  }

  List<String> _availableFilters() {
    // Pull from the active equipment profile via the existing provider.
    //
    // A profile with no named filters is the NORMAL state of an OSC/DSLR rig
    // with no wheel, not a misconfiguration. Handing the engine a bare empty
    // list made every filter containment check false, so an unfiltered goal
    // (filter == smartNightUnfilteredName, the empty string) scored 0 in
    // _filterCoverageFactor and its frames were dropped from the dispatched
    // sequence. smartNightPlanningFilters yields [''] for that rig — the same
    // one-unfiltered-row contract Smart Night plans against — so admission,
    // scoring and sequence building all agree.
    try {
      final profile = ref.read(activeEquipmentProfileProvider);
      if (profile != null) {
        return smartNightPlanningFilters(profile.filterNames);
      }
    } catch (_) {
      // activeEquipmentProfileProvider may not yet be initialized in a
      // background tick; that's fine — fall through to an empty list and
      // the engine will treat goals as un-imageable until the operator
      // sets a profile.
    }
    return const <String>[];
  }
}

final schedulerCandidateLoaderProvider = Provider<SchedulerCandidateLoader>((
  ref,
) {
  return SchedulerCandidateLoader(ref);
});

/// Live stream of every integration goal. Driven by
/// `IntegrationGoalService.watchAll`; used by [_schedulerAutoReevalProvider]
/// to wake the engine whenever the operator edits goals.
final integrationGoalsStreamProvider = StreamProvider<List<IntegrationGoal>>((
  ref,
) {
  return ref.watch(integrationGoalServiceProvider).watchAll();
});

/// Live stream of every constraint. Driven by
/// `TargetConstraintService.watchAll`.
final targetConstraintsStreamProvider = StreamProvider<List<TargetConstraint>>((
  ref,
) {
  return ref.watch(targetConstraintServiceProvider).watchAll();
});

/// Durable store for the operator-tuned [SchedulerConfig]. The scoring sliders
/// write through [save]; [schedulerEngineProvider] hydrates from [load] at
/// cold start so tuned weights / min-altitude / hysteresis survive a restart.
class SchedulerConfigStore {
  SchedulerConfigStore(this._dao);

  final SettingsDao _dao;
  static const String _key = 'scheduler_config';

  Future<SchedulerConfig> load() async {
    final raw = await _dao.getSetting(_key);
    if (raw == null || raw.isEmpty) return SchedulerConfig.defaults;
    try {
      return SchedulerConfig.fromStorageJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (error) {
      throw FormatException(
        'Persisted scheduler configuration is invalid',
        error,
      );
    }
  }

  Future<void> save(SchedulerConfig config) {
    return _dao.setSetting(_key, jsonEncode(config.toStorageJson()));
  }
}

final schedulerConfigStoreProvider = Provider<SchedulerConfigStore>((ref) {
  return SchedulerConfigStore(ref.read(settingsDaoProvider));
});

/// One-shot cold-start load of the persisted scheduler config. Not invalidated
/// on slider edits (those update the engine in place via `updateConfig`), so
/// the engine is not torn down on every tweak.
final schedulerPersistedConfigProvider = FutureProvider<SchedulerConfig>((ref) {
  return ref.read(schedulerConfigStoreProvider).load();
});

/// Set as soon as the operator changes scheduler tuning in this process. It
/// prevents a late cold-start read from overwriting an edit made while the
/// settings row was still loading.
final schedulerConfigUserDirtyProvider = StateProvider<bool>((ref) => false);

/// The site's minimum imaging altitude in degrees — the ONE number.
///
/// The scheduler's [SchedulerConfig.minAltitudeDegrees] is the only
/// operator-editable minimum altitude in the product (Plan Tonight → Schedule →
/// Scoring weights), so it is the authority. Everything that gates on "is this
/// target high enough" reads it here instead of carrying a private constant:
/// the Smart Night sequence builder, the mosaic panel altitude waits, and the
/// threshold line the altitude charts draw. Those used to hold their own 30°
/// while the scheduler held 25°, so the app both admitted and refused the same
/// 27° target on one screen.
///
/// Per-target overrides (`targets.min_altitude`, carried on
/// `ForecastTarget.minAltitudeDeg`) are a deliberate exception: a specific
/// target may need to clear more than the site does. This provider is the
/// FLOOR, not a replacement for those.
final siteMinimumAltitudeDegProvider = Provider<double>((ref) {
  final persisted = ref.watch(schedulerPersistedConfigProvider).valueOrNull;
  // Before the durable row has loaded (or when it has never been written) the
  // engine itself runs on SchedulerConfig.defaults, so that is the honest
  // answer here too — never a second hard-coded number.
  return persisted?.minAltitudeDegrees ??
      SchedulerConfig.defaults.minAltitudeDegrees;
});

/// The single engine instance for the app.
final schedulerEngineProvider = Provider<SchedulerEngine>((ref) {
  final settingsAsync = ref.read(appSettingsProvider);
  final settings = settingsAsync.valueOrNull;
  final lat = settings?.latitude ?? 0.0;
  final lng = settings?.longitude ?? 0.0;
  // Hydrate the operator-tuned scoring config so tuned weights, minimum
  // altitude, and hysteresis survive an app restart. Loading is a one-shot
  // future; slider edits update the live engine in place rather than
  // invalidating this, so a running engine is not rebuilt mid-session.
  final persistedAsync = ref.read(schedulerPersistedConfigProvider);
  final persistedConfig =
      persistedAsync.valueOrNull ?? SchedulerConfig.defaults;
  // Why: route the scheduler's current-time reads through the user's
  // configured clock so window evaluations, scoring, and meridian-factor
  // calculations all reflect the operator's chosen timezone.
  //
  // Two separate things are needed and they used to be conflated. The engine
  // wants a real instant for ephemeris (`SchedulerEngine` does
  // `now.toUtc().add(site.localOffset)`), and it wants the *site's* offset to
  // decide whether "image between 22:00 and 04:00 local" is satisfied. Feeding
  // it `clock.now` supplied a zone rendering where an instant was expected, and
  // `DateTime.now().timeZoneOffset` supplied the laptop's offset where the
  // observatory's was meant — so a remote operator's time windows were
  // evaluated in their own zone, which is exactly what the Timezone setting
  // exists to stop.
  final clock = ref.read(clockProvider);
  final localOffset = clock.utcOffset;

  // Build a candidate loader bound to a specific active-project scope. When
  // [activeId] is null the loader runs unfiltered (the full catalog — current
  // behavior for non-project users); when it is set, the candidate set is
  // restricted to that project's members. We capture [activeId] by value so a
  // reload triggered later still queries the scope the engine was configured
  // with, rather than re-reading a moving provider value mid-tick.
  Future<List<SchedulerCandidate>> Function() loaderFor(int? activeId) =>
      () =>
          ref.read(schedulerCandidateLoaderProvider).load(projectId: activeId);

  // Read (not watch) the initial scope: watching activeProjectIdProvider here
  // would rebuild the whole engine on every project switch and lose its
  // running state. Instead we ref.listen below and swap the loader in place,
  // which preserves the engine (and its run/pause status) across switches.
  final initialActiveId = ref.read(activeProjectIdProvider);

  final engine = SchedulerEngine(
    site: SchedulerSite(
      latitudeDegrees: lat,
      longitudeDegrees: lng,
      localOffset: localOffset,
    ),
    config: persistedConfig,
    sequenceSink: _ExecutorSequenceSink(ref),
    candidateLoader: loaderFor(initialActiveId),
    triggerStream: ref.read(schedulerTriggerStreamProvider),
    clock: clock.nowUtc,
  );

  // Hydrate a late settings/config read in place. Watching either async
  // provider here used to dispose and recreate the engine on completion,
  // losing run/pause state and any target currently under scheduler control.
  ref.listen<AsyncValue<AppSettingsState>>(appSettingsProvider, (
    previous,
    next,
  ) {
    final value = next.valueOrNull;
    if (value == null) return;
    final nextSite = SchedulerSite(
      latitudeDegrees: value.latitude,
      longitudeDegrees: value.longitude,
      // The zone belongs to the clock listener below, not here. Re-reading
      // `clockProvider` at this point returns the pre-change clock — Riverpod
      // has not flushed it yet — so a Timezone edit would be compared against
      // itself, look unchanged, and leave the engine on the old offset.
      localOffset: engine.site.localOffset,
    );
    final currentSite = engine.site;
    if (nextSite.latitudeDegrees == currentSite.latitudeDegrees &&
        nextSite.longitudeDegrees == currentSite.longitudeDegrees &&
        nextSite.localOffset == currentSite.localOffset) {
      return;
    }
    engine.updateSite(nextSite);
    engine.requestReevaluation(reason: 'observer location changed');
  });
  // Settings → Location → Timezone decides what "22:00 local" means to a
  // time-window constraint. Nothing propagated it before: the site was built
  // once from the laptop's offset, so a remote operator's windows opened and
  // closed on their own evening rather than the observatory's.
  ref.listen<Clock>(clockProvider, (previous, next) {
    if (next.utcOffset == engine.site.localOffset) return;
    engine.updateSite(
      SchedulerSite(
        latitudeDegrees: engine.site.latitudeDegrees,
        longitudeDegrees: engine.site.longitudeDegrees,
        localOffset: next.utcOffset,
      ),
    );
    engine.requestReevaluation(reason: 'site timezone changed');
  });
  ref.listen<AsyncValue<SchedulerConfig>>(schedulerPersistedConfigProvider, (
    previous,
    next,
  ) {
    final value = next.valueOrNull;
    if (value == null ||
        ref.read(schedulerConfigUserDirtyProvider) ||
        value == engine.config) {
      return;
    }
    engine.updateConfig(value);
  });

  // Re-scope (and immediately re-evaluate) whenever the active project changes
  // without tearing down the engine. The auto-reeval provider also pokes the
  // engine on this same change, but re-setting the loader here is what makes
  // that re-evaluation pull from the new scope — the two are complementary.
  ref.listen<int?>(activeProjectIdProvider, (previous, next) {
    if (previous == next) return;
    engine.setCandidateLoader(loaderFor(next));
    engine.requestReevaluation(reason: 'active project changed');
  });

  ref.onDispose(() => engine.dispose());
  return engine;
});

/// One-shot authority gate for every operation that can evaluate or start the
/// unattended scheduler.
///
/// [schedulerEngineProvider] is intentionally synchronous because status
/// listeners must retain one stable engine instance. That used to mean the
/// shell constructed it immediately with `(0, 0)` and factory scoring defaults
/// while persisted settings were still loading. A fast preview/start could
/// therefore choose and dispatch the wrong target. This provider waits for
/// both authoritative inputs before exposing the engine and hydrates that same
/// stable instance in place.
///
/// Reads are deliberately one-shot. Once an engine is ready, a later transient
/// settings refresh must not hide Pause/Stop or revoke control of an already
/// running scheduler. Callers can invalidate this provider together with the
/// failed input providers to retry a cold-start failure.
final schedulerEngineReadyProvider = FutureProvider<SchedulerEngine>((
  ref,
) async {
  final settingsFuture = ref.read(appSettingsProvider.future);
  final configFuture = ref.read(schedulerPersistedConfigProvider.future);
  final settings = await settingsFuture;
  final persistedConfig = await configFuture;
  final engine = ref.watch(schedulerEngineProvider);

  engine.updateSite(
    SchedulerSite(
      latitudeDegrees: settings.latitude,
      longitudeDegrees: settings.longitude,
      // The ready gate hydrates the site AFTER construction, so taking the
      // host's offset here would silently overwrite the observatory's on every
      // cold start — the same defect as the constructor's, one call site later.
      localOffset: ref.read(clockProvider).utcOffset,
    ),
  );
  if (!ref.read(schedulerConfigUserDirtyProvider)) {
    engine.updateConfig(persistedConfig);
  }
  return engine;
});

/// Side-effect provider that subscribes to the three "candidate inputs"
/// (target catalog rows, integration goals, target constraints) and pokes
/// the engine via `requestReevaluation()` whenever any of them changes.
///
/// The engine's internal debounce coalesces bursts (a goal upsert and a
/// constraint edit that arrive in the same microtask trigger ONE eval).
/// Must be `.watch`ed from the app shell (or any always-mounted Consumer)
/// so the listeners stay live for the lifetime of the scheduler engine.
final schedulerAutoReevalProvider = Provider<void>((ref) {
  // Starting the authority future here keeps the scheduler warm for the app
  // shell without constructing a default-config/default-site engine early.
  final engine = ref.watch(schedulerEngineReadyProvider).valueOrNull;
  if (engine == null) return;

  ref.listen<AsyncValue<List<ndb.Target>>>(allDbTargetsProvider, (
    previous,
    next,
  ) {
    // Only react once we have data, and only after the very first
    // emission (initial load is the cold-start, not a "change").
    if (previous == null || !previous.hasValue) return;
    if (!next.hasValue) return;
    engine.requestReevaluation(reason: 'targets table changed');
  });

  ref.listen<AsyncValue<List<IntegrationGoal>>>(
    integrationGoalsStreamProvider,
    (previous, next) {
      if (previous == null || !previous.hasValue) return;
      if (!next.hasValue) return;
      engine.requestReevaluation(reason: 'integration goals changed');
    },
  );

  ref.listen<AsyncValue<List<TargetConstraint>>>(
    targetConstraintsStreamProvider,
    (previous, next) {
      if (previous == null || !previous.hasValue) return;
      if (!next.hasValue) return;
      engine.requestReevaluation(reason: 'target constraints changed');
    },
  );

  // Switching the active project must re-pick tonight's targets immediately so
  // the operator sees the new campaign's rotation without waiting for the next
  // scheduled tick. The loader was already re-scoped in schedulerEngineProvider
  // for this same transition; the engine's internal debounce coalesces this
  // poke with that one into a single evaluation.
  ref.listen<int?>(activeProjectIdProvider, (previous, next) {
    if (previous == next) return;
    engine.requestReevaluation(reason: 'active project changed');
  });

  // Project membership changes (adding/removing a target, editing a priority
  // override) change which targets — and at what priority — the active project
  // contributes, so re-evaluate. projectListProvider re-emits on every
  // ProjectService mutation (it bridges watchChanges → re-list), which covers
  // membership edits as well as project CRUD. As above, only react after the
  // initial emission so the cold-start load is not treated as a change.
  ref.listen<AsyncValue<List<Project>>>(projectListProvider, (previous, next) {
    if (previous == null || !previous.hasValue) return;
    if (!next.hasValue) return;
    engine.requestReevaluation(reason: 'project membership changed');
  });
});

/// StateNotifier that mirrors the engine's status stream into Riverpod so
/// widgets can `ref.watch(schedulerStatusProvider)` without subscribing to
/// the stream themselves.
final schedulerStatusProvider =
    StateNotifierProvider<SchedulerStatusNotifier, SchedulerStatus>((ref) {
      final engine = ref.watch(schedulerEngineProvider);
      return SchedulerStatusNotifier(engine);
    });

class SchedulerStatusNotifier extends StateNotifier<SchedulerStatus> {
  final SchedulerEngine _engine;
  late final StreamSubscription<SchedulerStatus> _sub;

  SchedulerStatusNotifier(this._engine) : super(_engine.status) {
    _sub = _engine.statusStream.listen((s) {
      if (!mounted) return;
      state = s;
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// StateNotifier surfacing the engine's last decision.
final currentSchedulerDecisionProvider =
    StateNotifierProvider<CurrentSchedulerDecisionNotifier, SchedulerDecision?>(
      (ref) {
        final engine = ref.watch(schedulerEngineProvider);
        return CurrentSchedulerDecisionNotifier(engine);
      },
    );

class CurrentSchedulerDecisionNotifier
    extends StateNotifier<SchedulerDecision?> {
  final SchedulerEngine _engine;
  late final StreamSubscription<SchedulerDecision> _sub;

  CurrentSchedulerDecisionNotifier(this._engine) : super(_engine.lastDecision) {
    _sub = _engine.decisionStream.listen((d) {
      if (!mounted) return;
      state = d;
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Read-only PREVIEW of what the live autopilot would run right now.
///
/// This is the single source of truth for the Planner's "what will run
/// tonight" headline: it runs the SchedulerEngine's pure, side-effect-free
/// [SchedulerEngine.previewDecision] over the SAME candidate set the autopilot
/// scores (goals / constraints / horizon / filters / scheduled windows /
/// active-project scope), at the engine's current clock and hysteresis state.
/// By construction the target the human sees here is the target the rig will
/// slew to — no competing scorer.
///
/// It does NOT dispatch, park, or mutate engine status. It re-runs whenever
/// the engine's last decision changes (so it stays in step with live ticks and
/// trigger-driven re-evaluations) and whenever a candidate input changes; the
/// auto-reeval listeners that poke the engine cover the underlying data edits.
final schedulerPreviewDecisionProvider =
    FutureProvider.autoDispose<SchedulerDecision>((ref) async {
      // On a remote SLAVE the local scheduler engine has no candidate data — the
      // catalog/targets live in the HOST's database, never the slave's — so
      // previewDecision() would always return "nothing eligible". Mirror the
      // host's REAL preview ("what the rig would slew to next") instead. This
      // provider is invalidated by the on-connect hydrate and by scheduler
      // events (hydrateRemoteSessionState / _applySequencerEvent), so the banner
      // tracks the host live rather than computing a wrong local answer.
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return backend.getSchedulerPreview();
      }
      final engine = await ref.watch(schedulerEngineReadyProvider.future);
      final clock = ref.watch(clockProvider);
      // Re-derive the preview each time the autopilot publishes a fresh decision
      // so the read-only view tracks live evaluation. Watching the decision (not
      // just reading it once) keeps the headline current after ticks/triggers.
      ref.watch(currentSchedulerDecisionProvider);
      // The engine treats its argument as an instant to rebase (see
      // `SchedulerEngine`), so the preview has to be handed the same instant
      // the live tick gets, not a zone rendering of it — otherwise the
      // read-only preview and the autopilot disagree about what time it is.
      return engine.previewDecision(clock.nowUtc());
    });

/// Host-authoritative state consumed by the scheduler tab on a remote client.
/// Readiness is computed on the scheduler host and sent to remote clients.
/// Scheduler sequences center each target, so a usable plate solver is required.
final schedulerStartReadinessProvider = Provider<SchedulerStartReadiness>((
  ref,
) {
  final report = ref.watch(readinessReportProvider);
  final issues = <SchedulerReadinessIssue>[];
  final critical = report.itemFor(ReadinessItemId.criticalDevices);
  if (critical?.level == ReadinessLevel.blocked) {
    issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.camera,
        severity: SchedulerReadinessSeverity.blocker,
        title: 'Camera and mount',
        detail: 'The camera or mount is not connected.',
      ),
    );
  }
  final location = report.itemFor(ReadinessItemId.location);
  if (location?.level == ReadinessLevel.blocked) {
    issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.location,
        severity: SchedulerReadinessSeverity.blocker,
        title: 'Observing location',
        detail: 'Set the site location before starting unattended.',
      ),
    );
  }
  final output = report.itemFor(ReadinessItemId.outputPath);
  if (output?.level == ReadinessLevel.blocked) {
    issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.outputPath,
        severity: SchedulerReadinessSeverity.blocker,
        title: 'Capture output path',
        detail: 'Choose a writable capture directory.',
      ),
    );
  }
  final accessories = report.itemFor(ReadinessItemId.profileDevices);
  if (accessories?.level != null &&
      accessories!.level != ReadinessLevel.ready) {
    issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.guider,
        severity: SchedulerReadinessSeverity.warning,
        title: 'Assigned accessories',
        detail: 'One or more configured accessories are unavailable.',
      ),
    );
  }
  final solver = report.itemFor(ReadinessItemId.plateSolver);
  if (solver?.level != ReadinessLevel.ready) {
    issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.solver,
        severity: SchedulerReadinessSeverity.blocker,
        title: 'Plate solver',
        detail: 'Configure a working plate solver before unattended centering.',
      ),
    );
  }

  final weather = ref.watch(weatherSafetyProvider);
  if (!weather.monitoringEnabled) {
    issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.weather,
        severity: SchedulerReadinessSeverity.warning,
        title: 'Weather monitoring disabled',
        detail: 'Start requires confirmation without weather protection.',
      ),
    );
  } else if (!weather.isSafe) {
    issues.add(
      SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.weather,
        severity: SchedulerReadinessSeverity.blocker,
        title: 'Weather safety',
        detail: weather.failModeWarning ?? 'Weather is unsafe or unknown.',
      ),
    );
  }

  final guider = ref.watch(guiderStateProvider);
  if (guider.deviceId != null &&
      guider.connectionState != DeviceConnectionState.connected) {
    issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.guider,
        severity: SchedulerReadinessSeverity.warning,
        title: 'Guider',
        detail: 'The configured guider is not connected.',
      ),
    );
  }

  final disk = ref.watch(captureDirDiskSpaceProvider);
  disk.when(
    loading: () => issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.disk,
        severity: SchedulerReadinessSeverity.warning,
        title: 'Disk space',
        detail: 'Waiting for the capture volume check.',
      ),
    ),
    error: (_, __) => issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.disk,
        severity: SchedulerReadinessSeverity.blocker,
        title: 'Disk space',
        detail: 'The capture volume could not be checked.',
      ),
    ),
    data: (snapshot) {
      if (snapshot == null) {
        issues.add(
          const SchedulerReadinessIssue(
            id: SchedulerReadinessIssueId.disk,
            severity: SchedulerReadinessSeverity.blocker,
            title: 'Disk space',
            detail: 'The capture volume has no readable free-space snapshot.',
          ),
        );
      } else if (snapshot.freeBytes < kSafetyMarginBytes) {
        issues.add(
          const SchedulerReadinessIssue(
            id: SchedulerReadinessIssueId.disk,
            severity: SchedulerReadinessSeverity.blocker,
            title: 'Disk space',
            detail: 'Less than 2 GB remains on the capture volume.',
          ),
        );
      } else if (snapshot.freeBytes < 8 * 1024 * 1024 * 1024) {
        issues.add(
          const SchedulerReadinessIssue(
            id: SchedulerReadinessIssueId.disk,
            severity: SchedulerReadinessSeverity.warning,
            title: 'Disk space',
            detail: 'Less than 8 GB remains on the capture volume.',
          ),
        );
      }
    },
  );

  final settings = ref.watch(appSettingsProvider).valueOrNull;
  if (settings == null || !settings.parkBeforeDawn) {
    issues.add(
      const SchedulerReadinessIssue(
        id: SchedulerReadinessIssueId.dawn,
        severity: SchedulerReadinessSeverity.warning,
        title: 'Dawn policy',
        detail: 'Park before dawn is not confirmed enabled.',
      ),
    );
  }
  return SchedulerStartReadiness(
    issues: issues,
    available: true,
    solverRequired: true,
  );
});

/// Keeping status, decision, configuration, and admission in one response
/// prevents a remote client from making a local safety decision.
class SchedulerRemoteSnapshot {
  final SchedulerStatus status;
  final SchedulerDecision decision;
  final SchedulerConfig config;
  final SchedulerStartReadiness readiness;

  const SchedulerRemoteSnapshot({
    required this.status,
    required this.decision,
    required this.config,
    required this.readiness,
  });

  factory SchedulerRemoteSnapshot.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final decision = json['decision'];
    final config = json['config'];
    if (status is! Map || decision is! Map || config is! Map) {
      throw const FormatException(
        'Malformed scheduler state from imaging host',
      );
    }
    return SchedulerRemoteSnapshot(
      status: SchedulerStatus.fromJson(status.cast<String, dynamic>()),
      decision: SchedulerDecision.fromJson(decision.cast<String, dynamic>()),
      config: SchedulerConfig.fromStorageJson(config.cast<String, dynamic>()),
      readiness: SchedulerStartReadiness.fromStorageJson(json['readiness']),
    );
  }
}

final schedulerRemoteSnapshotProvider =
    FutureProvider.autoDispose<SchedulerRemoteSnapshot>((ref) async {
      final backend = ref.watch(backendProvider);
      if (backend is! NetworkBackend) {
        throw StateError('Remote scheduler state requires a network backend');
      }
      return SchedulerRemoteSnapshot.fromJson(
        await backend.getSchedulerState(),
      );
    });

/// Quick-access provider for the list of all integration goals (refreshes
/// when the operator edits them).
final allIntegrationGoalsProvider = FutureProvider<List<IntegrationGoal>>((
  ref,
) async {
  return ref.watch(integrationGoalServiceProvider).listAll();
});

/// Per-target progress provider used by the Scheduler screen rows.
final integrationGoalProgressProvider =
    FutureProvider.family<List<IntegrationGoalProgress>, int>((
      ref,
      targetId,
    ) async {
      return ref
          .watch(integrationGoalServiceProvider)
          .progressForTarget(targetId);
    });
