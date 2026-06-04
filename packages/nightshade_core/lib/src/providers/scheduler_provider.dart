import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart' as ndb;
import '../models/scheduler/integration_goal.dart';
import '../models/scheduler/scheduler_decision.dart';
import '../models/scheduler/scheduler_status.dart';
import '../models/scheduler/target_constraint.dart';
import '../models/planning/project.dart';
import '../models/sequence/sequence_models.dart';
import '../services/planning/project_service.dart'
    show projectTargetsProjectIndexSql, projectTargetsSchemaSql, projectsSchemaSql;
import '../services/safe_rig_service.dart';
import '../services/scheduler/horizon_profile.dart';
import '../services/scheduler/integration_goal_service.dart';
import '../services/scheduler/scheduler_engine.dart';
import '../services/scheduler/target_constraint_service.dart';
import 'clock_provider.dart';
import 'database_provider.dart';
import 'event_provider.dart';
// Multi-night planning (component C6): the active-project selection and the
// live project list scope the scheduler's candidate set to one campaign and
// re-trigger evaluation when the operator switches projects or edits
// membership. The dependency is one-directional (planning_provider imports
// scheduler_provider, not the reverse) — only these read-only providers are
// pulled in here, so there is no cycle.
import 'planning_provider.dart' show activeProjectIdProvider, projectListProvider;
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
final schedulerTriggerStreamProvider = Provider<Stream<SchedulerTriggerEvent>>(
  (ref) {
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
  },
);

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

  _ExecutorSequenceSink(this._ref);

  @override
  Future<void> dispatchSequence(Sequence sequence) async {
    final currentNotifier = _ref.read(currentSequenceProvider.notifier);
    // The scheduler dispatches generated sequences as part of its own
    // autopilot loop; the in-editor sequence has nothing to do with what
    // the scheduler decided to run next. Discard the unsaved guard so a
    // user happening to have an unsaved sequence in the editor doesn't
    // throw inside the scheduler's run path.
    currentNotifier.loadSequence(sequence, discardUnsaved: true);
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
    final db = ref.read(databaseProvider);
    final goalService = ref.read(integrationGoalServiceProvider);

    // Make sure all three scheduler tables exist before we read them. The
    // integration-goal service already ensures its own schema; we ensure
    // the other two here using the shared DDL constants.
    await db.customStatement(targetConstraintsSchemaSql);
    await db.customStatement(targetConstraintsTargetIndexSql);
    await db.customStatement(horizonProfilesSchemaSql);

    final List<QueryRow> targetRows;
    if (projectId != null) {
      // Defensive: the planner tables are created by the v40 migration, but a
      // fresh database built without migrations (or a scheduler tick that runs
      // before the planner UI has touched ProjectService) must still find them.
      // Re-running the DDL is a no-op on an existing schema (`IF NOT EXISTS`).
      // These constants are the canonical project DDL, owned by ProjectService.
      await db.customStatement(projectsSchemaSql);
      await db.customStatement(projectTargetsSchemaSql);
      await db.customStatement(projectTargetsProjectIndexSql);

      // Restrict to the project's members. The effective priority is the
      // membership override when set, else the target's own priority — and we
      // order by that effective value so the engine sees project-scoped ranking.
      targetRows = await db.customSelect(
        'SELECT t.id, t.name, t.ra, t.dec, '
        'COALESCE(pt.priority_override, t.priority) AS priority, '
        't.object_type, t.notes '
        'FROM targets t '
        'INNER JOIN project_targets pt ON pt.target_id = t.id '
        'WHERE pt.project_id = ? '
        'ORDER BY priority DESC, t.name ASC',
        variables: [Variable.withInt(projectId)],
      ).get();
    } else {
      targetRows = await db
          .customSelect(
            'SELECT id, name, ra, dec, priority, object_type, notes FROM targets ORDER BY priority DESC, name ASC',
          )
          .get();
    }

    // Pre-fetch all constraints + horizon profiles in two queries.
    final constraintRows = await db
        .customSelect(
          'SELECT id, target_id, kind, payload_json, enabled FROM target_constraints WHERE enabled = 1',
        )
        .get();
    final horizonRows = await db
        .customSelect(
          'SELECT id, name, samples_json FROM horizon_profiles',
        )
        .get();

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

    final availableFilters = _availableFilters();

    final out = <SchedulerCandidate>[];
    for (final row in targetRows) {
      final id = row.read<int>('id');
      final goals = await goalService.listForTarget(id);
      final counts = <int>[];
      for (final g in goals) {
        counts.add(await goalService.capturedFrameCount(
          targetId: id,
          filter: g.filter,
        ));
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
                'Target $id references horizon profile ${ct.customHorizonId} which does not exist');
          }
          usedProfiles[ct.customHorizonId!] = hp;
        }
      }

      out.add(SchedulerCandidate(
        targetId: id,
        name: row.read<String>('name'),
        raHours: row.read<double>('ra'),
        decDegrees: row.read<double>('dec'),
        userPriority: row.read<int>('priority'),
        goals: goals,
        capturedCounts: counts,
        constraints: cs,
        horizonProfiles: usedProfiles,
        availableFilters: availableFilters,
        isMosaicTarget: _isMosaicTarget(row),
      ));
    }
    return out;
  }

  bool _isMosaicTarget(QueryRow row) {
    final objectType = row.readNullable<String>('object_type') ?? '';
    final notes = row.readNullable<String>('notes') ?? '';
    final haystack =
        '${row.read<String>('name')} $objectType $notes'.toLowerCase();
    return haystack.contains('mosaic');
  }

  List<String> _availableFilters() {
    // Pull from the active equipment profile via the existing provider.
    try {
      final profile = ref.read(activeEquipmentProfileProvider);
      if (profile != null) return List<String>.from(profile.filterNames);
    } catch (_) {
      // activeEquipmentProfileProvider may not yet be initialized in a
      // background tick; that's fine — fall through to an empty list and
      // the engine will treat goals as un-imageable until the operator
      // sets a profile.
    }
    return const <String>[];
  }
}

final schedulerCandidateLoaderProvider =
    Provider<SchedulerCandidateLoader>((ref) {
  return SchedulerCandidateLoader(ref);
});

/// Live stream of every integration goal. Driven by
/// `IntegrationGoalService.watchAll`; used by [_schedulerAutoReevalProvider]
/// to wake the engine whenever the operator edits goals.
final integrationGoalsStreamProvider =
    StreamProvider<List<IntegrationGoal>>((ref) {
  return ref.watch(integrationGoalServiceProvider).watchAll();
});

/// Live stream of every constraint. Driven by
/// `TargetConstraintService.watchAll`.
final targetConstraintsStreamProvider =
    StreamProvider<List<TargetConstraint>>((ref) {
  return ref.watch(targetConstraintServiceProvider).watchAll();
});

/// The single engine instance for the app.
final schedulerEngineProvider = Provider<SchedulerEngine>((ref) {
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  final lat = settings?.latitude ?? 0.0;
  final lng = settings?.longitude ?? 0.0;
  // Why: route the scheduler's current-time reads through the user's
  // configured clock so window evaluations, scoring, and meridian-factor
  // calculations all reflect the operator's chosen timezone
  // (audit-handoff §2.1 WIRE-UP #9). The local offset still comes from
  // the system clock — the scheduler internally rebases to UTC for
  // ephemeris math.
  final clock = ref.watch(clockProvider);
  final localOffset = DateTime.now().timeZoneOffset;

  // Build a candidate loader bound to a specific active-project scope. When
  // [activeId] is null the loader runs unfiltered (the full catalog — current
  // behavior for non-project users); when it is set, the candidate set is
  // restricted to that project's members. We capture [activeId] by value so a
  // reload triggered later still queries the scope the engine was configured
  // with, rather than re-reading a moving provider value mid-tick.
  Future<List<SchedulerCandidate>> Function() loaderFor(int? activeId) =>
      () => ref.read(schedulerCandidateLoaderProvider).load(projectId: activeId);

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
    sequenceSink: _ExecutorSequenceSink(ref),
    candidateLoader: loaderFor(initialActiveId),
    triggerStream: ref.watch(schedulerTriggerStreamProvider),
    clock: clock.now,
  );

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

/// Side-effect provider that subscribes to the three "candidate inputs"
/// (target catalog rows, integration goals, target constraints) and pokes
/// the engine via `requestReevaluation()` whenever any of them changes.
///
/// The engine's internal debounce coalesces bursts (a goal upsert and a
/// constraint edit that arrive in the same microtask trigger ONE eval).
/// Must be `.watch`ed from the app shell (or any always-mounted Consumer)
/// so the listeners stay live for the lifetime of the scheduler engine.
final schedulerAutoReevalProvider = Provider<void>((ref) {
  final engine = ref.watch(schedulerEngineProvider);

  ref.listen<AsyncValue<List<ndb.Target>>>(
    allDbTargetsProvider,
    (previous, next) {
      // Only react once we have data, and only after the very first
      // emission (initial load is the cold-start, not a "change").
      if (previous == null || !previous.hasValue) return;
      if (!next.hasValue) return;
      engine.requestReevaluation(reason: 'targets table changed');
    },
  );

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
  ref.listen<int?>(
    activeProjectIdProvider,
    (previous, next) {
      if (previous == next) return;
      engine.requestReevaluation(reason: 'active project changed');
    },
  );

  // Project membership changes (adding/removing a target, editing a priority
  // override) change which targets — and at what priority — the active project
  // contributes, so re-evaluate. projectListProvider re-emits on every
  // ProjectService mutation (it bridges watchChanges → re-list), which covers
  // membership edits as well as project CRUD. As above, only react after the
  // initial emission so the cold-start load is not treated as a change.
  ref.listen<AsyncValue<List<Project>>>(
    projectListProvider,
    (previous, next) {
      if (previous == null || !previous.hasValue) return;
      if (!next.hasValue) return;
      engine.requestReevaluation(reason: 'project membership changed');
    },
  );
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
});

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

/// Quick-access provider for the list of all integration goals (refreshes
/// when the operator edits them).
final allIntegrationGoalsProvider =
    FutureProvider<List<IntegrationGoal>>((ref) async {
  return ref.watch(integrationGoalServiceProvider).listAll();
});

/// Per-target progress provider used by the Scheduler screen rows.
final integrationGoalProgressProvider =
    FutureProvider.family<List<IntegrationGoalProgress>, int>(
  (ref, targetId) async {
    return ref
        .watch(integrationGoalServiceProvider)
        .progressForTarget(targetId);
  },
);
