import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart' as ndb;
import '../models/scheduler/integration_goal.dart';
import '../models/scheduler/scheduler_decision.dart';
import '../models/scheduler/scheduler_status.dart';
import '../models/scheduler/target_constraint.dart';
import '../models/sequence/sequence_models.dart';
import '../services/scheduler/horizon_profile.dart';
import '../services/scheduler/integration_goal_service.dart';
import '../services/scheduler/scheduler_engine.dart';
import '../services/scheduler/target_constraint_service.dart';
import 'database_provider.dart';
import 'event_provider.dart';
import 'profiles_provider.dart';
import 'sequence_provider.dart';
// Hide settings_provider's legacy 8-compass-point HorizonProfile so the
// scheduler's samples-based HorizonProfile from services/scheduler/
// horizon_profile.dart resolves unambiguously below.
import 'settings_provider.dart' hide HorizonProfile;
// Pull in NightshadeEvent + EventPayload tagged-union subtypes (freezed
// generates EventPayload_Guiding / EventPayload_Equipment as part-of-library
// classes, so a plain import surfaces them here).
import 'package:nightshade_bridge/src/event.dart';

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
    case EventCategory.imaging:
    case EventCategory.sequencer:
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
    final currentNotifier =
        _ref.read(currentSequenceProvider.notifier);
    currentNotifier.loadSequence(sequence);
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
}

/// Source of candidate targets for the engine: assembles the latest target
/// rows, their integration goals + captured counts, their constraints, and
/// the equipment filter list.
class SchedulerCandidateLoader {
  final Ref ref;

  SchedulerCandidateLoader(this.ref);

  Future<List<SchedulerCandidate>> load() async {
    final db = ref.read(databaseProvider);
    final goalService = ref.read(integrationGoalServiceProvider);

    // Make sure all three scheduler tables exist before we read them. The
    // integration-goal service already ensures its own schema; we ensure
    // the other two here using the shared DDL constants.
    await db.customStatement(targetConstraintsSchemaSql);
    await db.customStatement(targetConstraintsTargetIndexSql);
    await db.customStatement(horizonProfilesSchemaSql);

    final targetRows = await db.customSelect(
      'SELECT id, name, ra, dec, priority FROM targets ORDER BY priority DESC, name ASC',
    ).get();

    // Pre-fetch all constraints + horizon profiles in two queries.
    final constraintRows = await db.customSelect(
      'SELECT id, target_id, kind, payload_json, enabled FROM target_constraints WHERE enabled = 1',
    ).get();
    final horizonRows = await db.customSelect(
      'SELECT id, name, samples_json FROM horizon_profiles',
    ).get();

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
      ));
    }
    return out;
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
  final localOffset = DateTime.now().timeZoneOffset;

  final engine = SchedulerEngine(
    site: SchedulerSite(
      latitudeDegrees: lat,
      longitudeDegrees: lng,
      localOffset: localOffset,
    ),
    sequenceSink: _ExecutorSequenceSink(ref),
    candidateLoader: () => ref.read(schedulerCandidateLoaderProvider).load(),
    triggerStream: ref.watch(schedulerTriggerStreamProvider),
  );
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

  CurrentSchedulerDecisionNotifier(this._engine)
      : super(_engine.lastDecision) {
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

// `Variable` import needed elsewhere; suppress unused-import via reference
// in a no-op to keep the public surface clean.
// ignore: unused_element
void _ensureVariableImported() {
  Variable.withInt(0);
}
