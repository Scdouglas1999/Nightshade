import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/sequencer_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

/// Live-rig L29 (2026-08-09). After a night of headless runs the appliance
/// held:
///
/// ```
/// PS> (Get-ChildItem C:\src\rigframes -Filter *.fits -Recurse).Count
/// 30
/// GET /api/images?limit=100 -> 8 entries, every one of them from the single
///                              run started via checkpoint/resume
/// ```
///
/// Thirty frames on disk, eight in the database. The `load -> start` path the
/// appliance actually uses re-implements a subset of `SequenceExecutor.start()`
/// and had neither of the two host-side steps that make a night reviewable: it
/// never opened the `imaging_sessions` row, and it never subscribed to the
/// native event stream that turns a captured frame into a `captured_images`
/// row. The resume path had the subscription, which is why its eight frames
/// survived.
///
/// These tests pin both halves at the seam. They fail if either is removed.
class _MockSequencerBackend extends Mock implements SequencerBackend {}

class _MockDeviceBackend extends Mock implements DeviceBackend {}

SequencerStatus _status(String state) =>
    SequencerStatus(state: state, progress: 0.0);

/// A minimal serialized `SequenceDefinition`, shaped exactly as the Rust
/// executor deserializes it: `TargetHeader` -> `Loop{Count,2}` ->
/// `TakeExposure{count:5}`. Ten planned frames, which is the number the session
/// progress bar has to divide by.
String _wireSequence({
  String name = 'M42 Overnight',
  double raHours = 5.588,
  double decDegrees = -5.391,
}) => jsonEncode({
  'id': 'seq-1',
  'name': name,
  'root_node_id': 'target-1',
  'nodes': [
    {
      'id': 'target-1',
      'name': name,
      'enabled': true,
      'children': ['loop-1'],
      'node_type': {
        'type': 'TargetHeader',
        'target_name': name,
        'ra_hours': raHours,
        'dec_degrees': decDegrees,
        'priority': 0,
      },
    },
    {
      'id': 'loop-1',
      'name': 'Repeat',
      'enabled': true,
      'children': ['expose-1'],
      'node_type': {'type': 'Loop', 'iterations': 2, 'condition': 'Count'},
    },
    {
      'id': 'expose-1',
      'name': 'Lum 120s',
      'enabled': true,
      'children': <String>[],
      'node_type': {
        'type': 'TakeExposure',
        'duration_secs': 120.0,
        'count': 5,
        'filter': 'Lum',
        'binning': {'x': 1, 'y': 1},
      },
    },
  ],
});

void main() {
  group('headless load->start opens the run\'s session row', () {
    late _MockSequencerBackend sequencer;
    late _MockDeviceBackend devices;
    late ProviderContainer container;
    late SequencerHandlers handlers;

    setUp(() {
      sequencer = _MockSequencerBackend();
      devices = _MockDeviceBackend();

      when(() => sequencer.sequencerLoadJson(any())).thenAnswer((_) async {});
      when(
        () => sequencer.sequencerSetSimulationMode(any()),
      ).thenAnswer((_) async {});
      when(
        () => sequencer.sequencerSetSafetyFailMode(any()),
      ).thenAnswer((_) async {});
      when(
        () => sequencer.sequencerSetDevices(
          cameraId: any(named: 'cameraId'),
          mountId: any(named: 'mountId'),
          focuserId: any(named: 'focuserId'),
          filterwheelId: any(named: 'filterwheelId'),
          rotatorId: any(named: 'rotatorId'),
          filterNames: any(named: 'filterNames'),
          filterFocusOffsets: any(named: 'filterFocusOffsets'),
        ),
      ).thenAnswer((_) async {});
      when(() => sequencer.sequencerStart()).thenAnswer((_) async {});
      when(() => devices.getConnectedDevices()).thenAnswer((_) async => []);

      container = createHeadlessTestContainer(
        overrides: [
          sequencerBackendProvider.overrideWithValue(sequencer),
          deviceBackendProvider.overrideWithValue(devices),
        ],
      );
      addTearDown(container.dispose);
      handlers = SequencerHandlers(container);
    });

    Future<Response> load(String json) => translateHandlerErrors(
      handlers.handleSequencerLoad(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sequencer/load'),
          body: jsonEncode({'json': json}),
        ),
      ),
    );

    Future<Response> start() => translateHandlerErrors(
      handlers.handleSequencerStart(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sequencer/start'),
          body: jsonEncode({}),
        ),
      ),
    );

    test(
      'a session row exists before the native executor is told to go',
      () async {
        expect(
          container.read(currentSequenceProvider),
          isNull,
          reason: 'this must be the bare headless branch, not the editor one',
        );
        expect(container.read(sessionStateProvider).isActive, isFalse);

        expect((await load(_wireSequence())).statusCode, 200);
        expect((await start()).statusCode, 200);

        final session = container.read(sessionStateProvider);
        expect(
          session.dbSessionId,
          isNotNull,
          reason:
              'without a session row every frame this run captures is stamped '
              'session_id NULL and the night is unreviewable',
        );
        expect(session.dbSessionId, greaterThan(0));
        expect(session.isActive, isTrue);
      },
    );

    test(
      'the row carries the sequence name and its single target\'s pointing',
      () async {
        await load(_wireSequence());
        await start();

        final session = container.read(sessionStateProvider);
        expect(session.targetName, 'M42 Overnight');
        expect(session.targetRa, closeTo(5.588, 1e-9));
        expect(session.targetDec, closeTo(-5.391, 1e-9));
      },
    );

    test('the planned frame count applies the loop multiplier', () async {
      await load(_wireSequence());
      await start();

      expect(
        container.read(sessionStateProvider).totalExposures,
        10,
        reason:
            '5 exposures inside a 2-iteration Count loop. A denominator of 5 '
            'would show the run at 100% halfway through the night',
      );
    });

    test('a multi-target sequence records no single pointing', () async {
      // Mirrors `_startSessionRow`: with more than one TargetHeader there is no
      // one direction to label the session with, and picking the first would
      // name a target the run may never reach.
      final twoTargets = jsonEncode({
        'id': 'seq-2',
        'name': 'Two Target Night',
        'root_node_id': 'root',
        'nodes': [
          {
            'id': 'root',
            'name': 'Night',
            'enabled': true,
            'children': ['t1', 't2'],
            'node_type': {
              'type': 'Loop',
              'iterations': 1,
              'condition': 'Count',
            },
          },
          for (final t in const [
            ('t1', 'M42', 5.588, -5.391),
            ('t2', 'M31', 0.712, 41.269),
          ])
            {
              'id': t.$1,
              'name': t.$2,
              'enabled': true,
              'children': <String>[],
              'node_type': {
                'type': 'TargetHeader',
                'target_name': t.$2,
                'ra_hours': t.$3,
                'dec_degrees': t.$4,
                'priority': 0,
              },
            },
        ],
      });

      await load(twoTargets);
      await start();

      final session = container.read(sessionStateProvider);
      expect(session.dbSessionId, isNotNull);
      expect(session.targetName, 'Two Target Night');
      expect(session.targetRa, isNull);
      expect(session.targetDec, isNull);
    });

    test(
      'the host is listening for the run\'s frame events before it starts',
      () async {
        // The half that actually writes `captured_images`. Thirty frames
        // reached disk on the rig with nobody subscribed; the eight that were
        // registered came from the resume path, which is the only other place
        // this subscription is installed.
        final executor = container.read(sequenceExecutorProvider);
        expect(executor.isListeningToNativeEventsForTest, isFalse);

        await load(_wireSequence());
        await start();

        expect(
          executor.isListeningToNativeEventsForTest,
          isTrue,
          reason:
              'with no subscription the night is written to disk and never '
              'reaches the database',
        );
      },
    );

    test(
      'a start with no prior load still runs, without a session row',
      () async {
        // A caller that starts whatever tree the executor already holds gets no
        // summary to label a row with. That must not cost it the run: frames on
        // disk beat a refusal.
        expect((await start()).statusCode, 200);
        verify(() => sequencer.sequencerStart()).called(1);
        expect(container.read(sessionStateProvider).dbSessionId, isNull);
      },
    );

    test('the second run of the night opens its own row', () async {
      // The appliance runs all night, one target after another.
      // `SessionService` refuses to open a second session while one is
      // active, so without closing the previous one every later target's
      // frames would be filed under the FIRST target's session — registered,
      // and registered against the wrong night.
      when(
        () => sequencer.sequencerGetStatus(),
      ).thenAnswer((_) async => _status('completed'));

      await load(_wireSequence(name: 'First Target'));
      await start();
      final first = container.read(sessionStateProvider).dbSessionId;

      await load(
        _wireSequence(name: 'Second Target', raHours: 20.0, decDegrees: 30.0),
      );
      await start();
      final second = container.read(sessionStateProvider);

      expect(second.dbSessionId, isNotNull);
      expect(second.dbSessionId, isNot(first));
      expect(second.targetName, 'Second Target');
    });

    test('a start refused as busy leaves the running session alone', () async {
      // The stale-session close must never fire against a live run. Here the
      // native executor is still running: ending its session on the way to the
      // 409 would strand the run in progress with nothing to attribute its
      // remaining frames to.
      when(
        () => sequencer.sequencerGetStatus(),
      ).thenAnswer((_) async => _status('running'));

      await load(_wireSequence(name: 'The Run In Progress'));
      await start();
      final live = container.read(sessionStateProvider);
      expect(live.dbSessionId, isNotNull);

      await load(_wireSequence(name: 'An Interloper'));
      await start();

      final after = container.read(sessionStateProvider);
      expect(after.dbSessionId, live.dbSessionId);
      expect(after.isActive, isTrue);
      expect(after.targetName, 'The Run In Progress');
    });
  });
}
