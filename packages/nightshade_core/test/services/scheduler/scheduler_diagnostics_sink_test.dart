// WF-N1 (half a) — the scheduler's own diagnostics were unreadable in the
// shipping build.
//
// Every SchedulerEngine diagnostic went to `dart:developer`, which in a release
// Flutter build has no destination anyone can reach: the rolling
// `nightshade.log.<date>` is written by the Rust tracing appender and carried 0
// SchedulerEngine lines, while Settings > Advanced > Logs (fed by
// LoggingService's in-memory ring) offered only `SequenceExecutor` in its
// source dropdown.
//
// The line that matters most is the reconcile line — the E-fix's stated
// two-implementations guard, the ONE piece of evidence that says WHICH engine
// instance re-armed the autopilot. It could not be checked by anyone.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/services/logging_service.dart';
import 'package:nightshade_core/src/services/scheduler/scheduler_engine.dart';
import 'package:nightshade_core/src/services/scheduler/scheduler_log.dart';

class _ExecutorSink implements SchedulerSequenceSink, SchedulerRunOwnership {
  final List<Sequence> dispatched = [];
  String? activeRunId;

  void dispatchedRunEnded() => activeRunId = null;

  @override
  Future<void> dispatchSequence(Sequence sequence) async {
    dispatched.add(sequence);
    activeRunId = sequence.id;
  }

  @override
  Future<void> pauseSequence() async {}

  @override
  Future<void> resumeSequence() async {}

  @override
  Future<void> stopSequence() async => activeRunId = null;

  @override
  Future<void> parkForEndOfNight() async => activeRunId = null;

  @override
  Future<void> releaseSequenceOwnership() async {}

  @override
  bool ownsRun(String sequenceId) => activeRunId == sequenceId;

  @override
  bool get hasActiveRun => activeRunId != null;
}

const _site = SchedulerSite(
  latitudeDegrees: 40.0,
  longitudeDegrees: -75.0,
  localOffset: Duration(hours: -5),
);

DateTime _night() => DateTime.utc(2026, 5, 11, 4, 0);

SchedulerCandidate _candidate() => SchedulerCandidate(
  targetId: 1,
  name: 'Bode',
  raHours: 14.0,
  decDegrees: 30.0,
  userPriority: 5,
  goals: const [],
  capturedCounts: const [],
  availableFilters: const ['L', 'R', 'G', 'B'],
  constraints: const [],
  horizonProfiles: const {},
);

/// A LoggingService with the native (Rust) appender stubbed out — the in-memory
/// ring and its `source` bookkeeping, which is exactly what the in-app Logs
/// viewer and `/api/logs/recent` read, are the real thing.
LoggingService _logger(Directory dir) => LoggingService(
  applicationSupportDirectoryProvider: () async => dir,
  environment: {'NIGHTSHADE_DATA_DIR': dir.path},
  nativeInitWithLogging: ({String? logDirectory}) {},
  nativeInit: () {},
  currentLogFileProvider: () => null,
);

void main() {
  test('the reconcile line reaches the injected diagnostics sink', () async {
    final records = <({SchedulerLogLevel level, String message})>[];
    final sink = _ExecutorSink();
    final engine = SchedulerEngine(
      site: _site,
      sequenceSink: sink,
      candidateLoader: () async => [_candidate()],
      clock: _night,
      logSink: (level, message) =>
          records.add((level: level, message: message)),
    );

    await engine.start();
    // The autopilot's own run ends by a path the engine never hears about.
    sink.dispatchedRunEnded();
    await engine.evaluateNow(reason: 'tick');

    expect(
      records.map((r) => r.message),
      contains(contains('Scheduler reconcile')),
      reason:
          'the line that proves WHICH engine re-armed the autopilot must be '
          'readable outside a debug-mode attach',
    );
    await engine.dispose();
  });

  test(
    'a scheduler diagnostic lands in the ring the Logs viewer reads, under its '
    'own source',
    () async {
      final dir = Directory.systemTemp.createTempSync('ns-sched-log');
      addTearDown(() => dir.deleteSync(recursive: true));
      final logger = _logger(dir);
      addTearDown(logger.dispose);
      final adapter = schedulerLogSinkFor(logger);

      adapter(SchedulerLogLevel.info, 'Scheduler reconcile (tick): …');

      final entries = logger
          .getRecentLogs()
          .where((e) => e.source == kSchedulerLogSource)
          .toList();
      expect(entries, hasLength(1));
      expect(entries.single.message, 'Scheduler reconcile (tick): …');
      expect(entries.single.level, LogLevel.info);
      // `Scheduler` is the string the repro greps for in the exported log.
      expect(entries.single.toString(), contains('Scheduler'));
    },
  );

  test('the adapter preserves the diagnostic level', () async {
    final dir = Directory.systemTemp.createTempSync('ns-sched-log');
    addTearDown(() => dir.deleteSync(recursive: true));
    final logger = _logger(dir);
    addTearDown(logger.dispose);
    final adapter = schedulerLogSinkFor(logger);

    adapter(SchedulerLogLevel.warning, 'Scheduler dawn park declined: …');
    adapter(SchedulerLogLevel.trace, 'Scheduler teardown: …');

    final levels = logger
        .getRecentLogs()
        .where((e) => e.source == kSchedulerLogSource)
        .map((e) => e.level)
        .toList();
    expect(levels, [LogLevel.warning, LogLevel.debug]);
  });
}
