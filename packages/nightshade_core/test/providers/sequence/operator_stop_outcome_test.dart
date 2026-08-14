// WE-SEQ-N6: pressing the SAME Stop button recorded the autopilot's run as
// `Failed` (plus a Critical toast) while the hand-started run 30 minutes
// earlier was recorded `Stopped (resumable)`.
//
// The live evidence: Stop pressed while a Slew was in flight. A slew that the
// stop cancels comes back as a node FAILURE carrying "Slew: Operation
// cancelled", so the native run ends with `SequenceFailed` rather than
// `Stopped` — while a stop during an exposure ends with `Stopped`. The operator
// performed one deliberate action and got two different verdicts depending on
// which instruction happened to be running.
//
// The discriminator here is deliberately NOT the message text (a Wave E refuter
// showed what substring-matching "cancelled" costs: real faults whose text
// contains the word get swallowed). It is the executor's own state: an explicit
// stop is IN FLIGHT, so whatever terminal the native reports is the outcome of
// that stop.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart'
    as backend_events;

import '../../mocks/mock_backend.dart';

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

/// What a cancelled Slew really puts on the wire (bridge delivers
/// `InstructionFailed` as a mid-run `Error` carrying `"<node>: <message>"`, then
/// the terminal restates it).
const _slewCancelled = 'Slew: Operation cancelled';

void main() {
  late MockBackend backend;
  late StreamController<backend_events.NightshadeEvent> eventController;
  late NightshadeDatabase db;

  setUp(() {
    backend = MockBackend();
    eventController =
        StreamController<backend_events.NightshadeEvent>.broadcast();
    when(() => backend.eventStream).thenAnswer((_) => eventController.stream);
    when(
      () => backend.polarAlignmentEvents,
    ).thenAnswer((_) => const Stream.empty());
    when(() => backend.discardCheckpoint()).thenAnswer((_) async {});
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    if (!eventController.isClosed) await eventController.close();
    await db.close();
  });

  (ProviderContainer, SequenceExecutor) build() {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backendProvider.overrideWith(
          (ref) => _TestBackendNotifier(ref, backend),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(liveSequenceStatsProvider.notifier).state =
        SequenceRunStats();
    container.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.running;
    return (container, container.read(sequenceExecutorProvider));
  }

  backend_events.NightshadeEvent event(
    String type,
    Map<String, Object?> data,
  ) => backend_events.NightshadeEvent(
    timestamp: DateTime.now().millisecondsSinceEpoch,
    severity: backend_events.EventSeverity.error,
    category: backend_events.EventCategory.sequencer,
    eventType: type,
    data: data,
  );

  test(
    'a stop during a Slew is recorded as a stop, not a failed run',
    () async {
      final (container, executor) = build();
      // The native cancels the in-flight slew and reports the run as FAILED,
      // carrying the instruction-level cancellation as the reason.
      when(() => backend.sequencerStop()).thenAnswer((_) async {
        scheduleMicrotask(() {
          executor.handleSequencerEventForTest(
            event('Error', {'message': _slewCancelled}),
          );
          executor.handleSequencerEventForTest(
            event('SequenceFailed', {'error': _slewCancelled}),
          );
        });
      });

      await executor.stop(preserveCheckpoint: true);
      await executor.terminalCleanupSettledForTest;

      final result = container.read(sequenceTerminalRunResultProvider);
      expect(result, isNotNull);
      expect(
        result!.runStatus,
        'paused-stopped',
        reason:
            'the operator pressed Stop; the instruction that happened to be in '
            'flight must not change the verdict on their action',
      );
      expect(result.outcome, SequenceExecutionState.idle);
      expect(
        container.read(sequenceExecutionStateProvider),
        SequenceExecutionState.idle,
      );
    },
  );

  test('a LATE failure terminal cannot re-verdict a finished stop', () async {
    final (container, executor) = build();
    // The stop is confirmed by the native `Stopped` state change...
    when(() => backend.sequencerStop()).thenAnswer((_) async {
      scheduleMicrotask(() {
        executor.handleSequencerEventForTest(
          event('SequenceStopped', const {}),
        );
      });
    });

    await executor.stop(preserveCheckpoint: true);
    await executor.terminalCleanupSettledForTest;
    expect(
      container.read(sequenceTerminalRunResultProvider)!.runStatus,
      'paused-stopped',
    );

    // ...and the node tree's own failure lands afterwards, once the stop's
    // finalization has already been dropped.
    executor.handleSequencerEventForTest(
      event('SequenceFailed', {'error': _slewCancelled}),
    );
    await executor.terminalCleanupSettledForTest;
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(sequenceTerminalRunResultProvider)!.runStatus,
      'paused-stopped',
      reason:
          'the run is over and its verdict was the operator\'s stop — a late '
          'terminal for that same run must not re-open finalization and '
          'republish it as Failed (which is what raises the Critical toast and '
          'files the run as Failed in Execution History)',
    );
    expect(
      container.read(sequenceExecutionStateProvider),
      SequenceExecutionState.idle,
      reason: 'the dashboard must not flip to Failed after a clean stop',
    );
  });

  test('a genuine failure with no stop in flight is still a failure', () async {
    final (container, executor) = build();

    executor.handleSequencerEventForTest(
      event('SequenceFailed', {'error': 'Camera disconnected'}),
    );
    await executor.terminalCleanupSettledForTest;

    final result = container.read(sequenceTerminalRunResultProvider);
    expect(result!.runStatus, 'failed');
    expect(result.outcome, SequenceExecutionState.failed);
    expect(
      container.read(liveSequenceStatsProvider)!.errorMessages,
      contains('Camera disconnected'),
    );
  });
}
