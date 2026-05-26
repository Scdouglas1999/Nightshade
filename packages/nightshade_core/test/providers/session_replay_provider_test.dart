// Wave 7B — Tests for the session replay notifier's snapshot
// computation (scan-to-time correctness) and lifecycle.
//
// The notifier's bootstrap is wired through a stub
// `SessionReplayDataSource` so the tests exercise the real scan logic
// without any HTTP plumbing.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Fixed run window: started at t=0, ended 10 minutes later.
  final runStartedAt = DateTime.utc(2026, 5, 25, 22, 0);
  final runEndedAt = runStartedAt.add(const Duration(minutes: 10));
  const int runId = 42;

  RemoteReplayEvent eventAt(int seconds, String severity, String message) {
    final ts = runStartedAt.add(Duration(seconds: seconds));
    return RemoteReplayEvent(
      timestamp: ts,
      timestampMs: ts.millisecondsSinceEpoch,
      severity: severity,
      source: 'TestSource',
      message: message,
    );
  }

  RemoteReplayFrame frameAt(
    int id,
    int seconds, {
    String? filter,
    double? hfr,
  }) {
    final ts = runStartedAt.add(Duration(seconds: seconds));
    return RemoteReplayFrame(
      id: id,
      fileName: 'frame_$id.fits',
      filePath: '/tmp/frame_$id.fits',
      capturedAt: ts,
      capturedAtMs: ts.millisecondsSinceEpoch,
      frameType: 'light',
      exposureDuration: 60.0,
      filter: filter,
      hfr: hfr,
      binX: 1,
      binY: 1,
      isAccepted: true,
    );
  }

  group('SessionReplayNotifier', () {
    test('bootstrap transitions Loading → Ready and merges markers', () async {
      final source = _StubSource(
        run: RemoteSequenceRunDetail(
          id: runId,
          startedAt: runStartedAt,
          endedAt: runEndedAt,
          status: 'completed',
          frameCount: 3,
          sequenceName: 'Test sequence',
          targetName: 'M31',
        ),
        eventsPage: RemoteReplayEventsPage(
          items: [
            eventAt(0, 'info', 'Sequence started'),
            eventAt(120, 'info', 'Slewed to target'),
            eventAt(300, 'warning', 'HFR climbing'),
          ],
          total: 3,
          isPartial: false,
          source: 'logging_service_ring_buffer',
        ),
        frames: [
          frameAt(1, 60, filter: 'L', hfr: 2.4),
          frameAt(2, 180, filter: 'L', hfr: 2.5),
          frameAt(3, 360, filter: 'R', hfr: 2.6),
        ],
      );
      final notifier =
          SessionReplayNotifier(runId: runId, dataSource: source);
      // Bootstrap is async; wait for the state to land.
      await source.completed;

      expect(notifier.state, isA<SessionReplayReady>());
      final ready = notifier.state as SessionReplayReady;
      expect(ready.markers, hasLength(6));
      // Markers are sorted ascending by offset.
      for (var i = 1; i < ready.markers.length; i++) {
        expect(
          ready.markers[i].offsetMs,
          greaterThanOrEqualTo(ready.markers[i - 1].offsetMs),
        );
      }
      expect(ready.durationMs, const Duration(minutes: 10).inMilliseconds);
      expect(ready.playheadMs, 0);
      expect(ready.eventsPartial, isFalse);
      notifier.dispose();
    });

    test('computeSnapshotAt(t) projects only markers with offset <= t',
        () async {
      final source = _StubSource(
        run: RemoteSequenceRunDetail(
          id: runId,
          startedAt: runStartedAt,
          endedAt: runEndedAt,
          status: 'completed',
          frameCount: 3,
          sequenceName: 'Test sequence',
          targetName: 'M31',
        ),
        eventsPage: RemoteReplayEventsPage(
          items: [
            eventAt(0, 'info', 'Sequence started'),
            eventAt(60, 'info', 'Slewed to target'),
            eventAt(180, 'warning', 'HFR climbing'),
            eventAt(360, 'info', 'recovery.entered: autofocus drift'),
          ],
          total: 4,
          isPartial: false,
          source: 'logging_service_ring_buffer',
        ),
        frames: [
          frameAt(1, 30, filter: 'L', hfr: 2.4),
          frameAt(2, 90, filter: 'L', hfr: 2.5),
          frameAt(3, 240, filter: 'R', hfr: 2.6),
        ],
      );
      final notifier =
          SessionReplayNotifier(runId: runId, dataSource: source);
      await source.completed;

      // Playhead at t=120s.
      const playheadMs = 120 * 1000;
      final snap = notifier.computeSnapshotAt(playheadMs);

      // Markers BEFORE 120s: events at 0, 60; frames at 30, 90 → 4.
      // Markers AFTER 120s (180, 240, 360) must be excluded.
      expect(snap.markersUpToPlayhead, hasLength(4));
      for (final m in snap.markersUpToPlayhead) {
        expect(m.offsetMs, lessThanOrEqualTo(playheadMs));
      }
      // Frame count reflects the two frames at t<=120 only.
      expect(snap.frameCount, 2);
      // Most-recent filter at the playhead is L (frame at t=90s).
      expect(snap.currentFilter, 'L');
      // HFR follows the latest frame at or before the playhead → 2.5.
      expect(snap.lastHfr, 2.5);
      // Target falls back to the run header value because no event
      // payload sets a fresh target before t=120s.
      expect(snap.currentTarget, 'M31');
      // Recovery state has not been touched at this playhead.
      expect(snap.recoveryState, isNull);
      // Wall-clock at playhead = runStartedAt + 120s.
      expect(
        snap.playheadWallClock.difference(runStartedAt).inSeconds,
        120,
      );

      // Advance the playhead past the recovery event and verify the
      // recoveryState lights up.
      final lateSnap = notifier.computeSnapshotAt(400 * 1000);
      expect(lateSnap.recoveryState, 'entered');
      expect(lateSnap.frameCount, 3);

      notifier.dispose();
    });

    test('seekTo clamps playhead to [0, durationMs]', () async {
      final source = _StubSource(
        run: RemoteSequenceRunDetail(
          id: runId,
          startedAt: runStartedAt,
          endedAt: runEndedAt,
          status: 'completed',
          frameCount: 0,
          sequenceName: 'Empty run',
        ),
        eventsPage: const RemoteReplayEventsPage(
          items: [],
          total: 0,
          isPartial: true,
          source: 'logging_service_ring_buffer',
          partialReason: 'no_buffered_entries',
        ),
        frames: const [],
      );
      final notifier =
          SessionReplayNotifier(runId: runId, dataSource: source);
      await source.completed;

      notifier.seekTo(-1000);
      expect((notifier.state as SessionReplayReady).playheadMs, 0);

      notifier.seekTo(99999999);
      final ready = notifier.state as SessionReplayReady;
      expect(ready.playheadMs, ready.durationMs);
      // is_partial flag propagates through to the Ready state.
      expect(ready.eventsPartial, isTrue);
      expect(ready.eventsPartialReason, 'no_buffered_entries');

      notifier.dispose();
    });

    test('a data-source failure transitions to SessionReplayError', () async {
      final source = _StubSource.failing(
        error: Exception('connection refused'),
      );
      final notifier =
          SessionReplayNotifier(runId: runId, dataSource: source);
      // Drain pending microtasks so the bootstrap can run + the
      // notifier can settle into the error state.
      await Future<void>.delayed(Duration.zero);
      // Drain again — the Zone.handleUncaughtError call defers.
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<SessionReplayError>());
      final err = notifier.state as SessionReplayError;
      expect(err.runId, runId);
      expect(err.message, contains('Failed to load replay'));
      notifier.dispose();
    });

    test('snapshotStream emits a new snapshot after each seekTo', () async {
      final source = _StubSource(
        run: RemoteSequenceRunDetail(
          id: runId,
          startedAt: runStartedAt,
          endedAt: runEndedAt,
          status: 'completed',
          frameCount: 0,
          sequenceName: 'Empty run',
        ),
        eventsPage: const RemoteReplayEventsPage(
          items: [],
          total: 0,
          isPartial: false,
          source: 'logging_service_ring_buffer',
        ),
        frames: const [],
      );
      final notifier =
          SessionReplayNotifier(runId: runId, dataSource: source);
      await source.completed;

      final emitted = <int>[];
      final sub = notifier.snapshotStream.listen((s) {
        emitted.add(s.playheadMs);
      });
      notifier.seekTo(1000);
      notifier.seekTo(2500);
      // Let the broadcast controller dispatch its microtasks.
      await Future<void>.delayed(Duration.zero);
      expect(emitted, containsAllInOrder(<int>[1000, 2500]));
      await sub.cancel();
      notifier.dispose();
    });
  });
}

/// Stub data source that hands back canned results to exercise the
/// notifier's state machine without HTTP plumbing.
class _StubSource implements SessionReplayDataSource {
  final RemoteSequenceRunDetail? run;
  final RemoteReplayEventsPage? eventsPage;
  final List<RemoteReplayFrame>? frames;
  final Object? failure;

  // We don't need futures-with-completers here; the tests just await
  // a fresh delay before asserting. But exposing a `completed` getter
  // makes the test prose read more naturally.
  Future<void> get completed async {
    // Yield twice: once for the Future.wait chain, once for the
    // notifier's state assignment microtask.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  _StubSource({
    required this.run,
    required this.eventsPage,
    required this.frames,
  }) : failure = null;

  _StubSource.failing({required Object error})
      : run = null,
        eventsPage = null,
        frames = null,
        failure = error;

  @override
  Future<RemoteSequenceRunDetail> fetchRun(int runId) async {
    if (failure != null) throw failure!;
    return run!;
  }

  @override
  Future<RemoteReplayEventsPage> fetchEvents(int runId) async {
    if (failure != null) throw failure!;
    return eventsPage!;
  }

  @override
  Future<List<RemoteReplayFrame>> fetchFrames(int runId) async {
    if (failure != null) throw failure!;
    return frames!;
  }
}
