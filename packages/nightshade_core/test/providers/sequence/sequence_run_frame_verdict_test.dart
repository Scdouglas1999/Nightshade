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

class _ConnectedCameraNotifier extends CameraStateNotifier {
  _ConnectedCameraNotifier(super.ref) {
    setConnecting(_cameraId, 'Test Camera');
    setConnected();
  }
}

const _cameraId = 'simulator:test-camera-1';

/// What the run record says about the frames a night actually produced.
///
/// Three separate claims used to be structurally impossible to make truthfully:
///
///  1. `framesRejected` was always 0. The only caller of
///     `SequenceRunStats.recordFrame` passed `accepted: true` unconditionally,
///     so a night the grader rejected frames on — writing `captured_images`
///     rows with `runtime_grade='reject'` to prove it — still reported "0
///     rejected" in the Session Report, the cockpit vitals and the morning
///     recap.
///  2. `ditherCount` was always 0. `recordDither()` had no call site at all.
///  3. Every sequenced frame triggered TWO full last-image fetches over the
///     bridge, and one of them stamped the preview with literals (2 s, gain 0,
///     bin 1) because the imaging `ExposureComplete` payload carries no
///     capture metadata — so a 300 s sub could be labelled "2 s, gain 0".
void main() {
  setUpAll(registerMocktailFallbackValues);

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
    when(() => backend.cameraGetLastImage(any())).thenAnswer((_) async => null);
    when(
      () => backend.getLastRawImageData(any()),
    ).thenAnswer((_) async => <int>[]);
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await eventController.close();
    await db.close();
  });

  (ProviderContainer, SequenceExecutor) build({Sequence? sequence}) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backendProvider.overrideWith(
          (ref) => _TestBackendNotifier(ref, backend),
        ),
        cameraStateProvider.overrideWith(_ConnectedCameraNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(liveSequenceStatsProvider.notifier).state =
        SequenceRunStats();
    if (sequence != null) {
      container
          .read(currentSequenceProvider.notifier)
          .loadSequence(sequence, discardUnsaved: true);
    }
    return (container, container.read(sequenceExecutorProvider));
  }

  backend_events.NightshadeEvent event(
    backend_events.EventCategory category,
    String type,
    Map<String, dynamic> data,
  ) => backend_events.NightshadeEvent(
    timestamp: DateTime.now().microsecondsSinceEpoch,
    severity: backend_events.EventSeverity.info,
    category: category,
    eventType: type,
    data: data,
  );

  backend_events.NightshadeEvent sequencerEvent(
    String type,
    Map<String, dynamic> data,
  ) => event(backend_events.EventCategory.sequencer, type, data);

  Sequence exposureSequence() {
    final exposure = ExposureNode(
      id: 'expo1',
      name: 'Take Exposures',
      durationSecs: 300,
      count: 4,
      gain: 120,
      offset: 30,
      binning: BinningMode.two,
      parentId: 'target1',
    );
    final target = TargetHeaderNode(
      id: 'target1',
      name: 'Target',
      targetName: 'M31',
      raHours: 0,
      decDegrees: 0,
      childIds: const ['expo1'],
    );
    return Sequence.create(
      name: 'Night',
      rootNodeId: 'target1',
      nodes: {'target1': target, 'expo1': exposure},
    );
  }

  Map<String, dynamic> frameData({
    required int frame,
    double exposureSecs = 300.0,
    int gain = 120,
    int offset = 30,
    int bin = 2,
  }) => <String, dynamic>{
    'node_id': 'expo1',
    'frame': frame,
    'total': 4,
    'exposure_secs': exposureSecs,
    'gain': gain,
    'offset': offset,
    'bin_x': bin,
    'bin_y': bin,
    'frame_type': 'Light',
  };

  group('the run record counts the frames the grader rejected', () {
    test('a rejected frame is recorded as rejected', () async {
      final (container, executor) = build(sequence: exposureSequence());

      executor.handleSequencerEventForTest(
        sequencerEvent('NodeStarted', {'node_id': 'expo1'}),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('FrameRejected', {
          ...frameData(frame: 1),
          'reason': 'HFR 6.2 above threshold 4.0',
          'reject_path': '/tmp/rejected_0001.fits',
        }),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('ExposureCompleted', {
          'frame': 1,
          'total': 4,
          'duration_secs': 300.0,
        }),
      );
      await pumpEventQueue();

      final stats = container.read(liveSequenceStatsProvider)!;
      expect(
        stats.framesRejected,
        1,
        reason: 'the grader rejected this frame; the run record must say so',
      );
      expect(
        stats.framesCaptured,
        1,
        reason: 'a rejected frame was still captured',
      );
    });

    test('the per-filter breakdown carries the rejection', () async {
      final (container, executor) = build(sequence: exposureSequence());

      executor.handleSequencerEventForTest(
        sequencerEvent('NodeStarted', {'node_id': 'expo1'}),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('InstructionProgressStructured', {
          'node_id': 'expo1',
          'detail_kind': 'Filter',
          'detail_json': '{"name":"Ha"}',
        }),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('FrameRejected', {
          ...frameData(frame: 1),
          'reason': 'too few stars',
        }),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('ExposureCompleted', {
          'frame': 1,
          'total': 4,
          'duration_secs': 300.0,
        }),
      );
      await pumpEventQueue();

      final filterStats = container
          .read(liveSequenceStatsProvider)!
          .targetBreakdown['M31']!['Ha']!;
      expect(filterStats.rejected, 1);
      expect(filterStats.captured, 1);
    });

    test('an accepted frame is not counted as rejected', () async {
      final (container, executor) = build(sequence: exposureSequence());

      executor.handleSequencerEventForTest(
        sequencerEvent('NodeStarted', {'node_id': 'expo1'}),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('FrameAccepted', {
          ...frameData(frame: 1),
          'save_path': '/tmp/light_0001.fits',
        }),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('ExposureCompleted', {
          'frame': 1,
          'total': 4,
          'duration_secs': 300.0,
        }),
      );
      await pumpEventQueue();

      final stats = container.read(liveSequenceStatsProvider)!;
      expect(stats.framesCaptured, 1);
      expect(stats.framesRejected, 0);
    });

    test('a frame no grader ruled on still counts as captured', () async {
      final (container, executor) = build(sequence: exposureSequence());

      executor.handleSequencerEventForTest(
        sequencerEvent('NodeStarted', {'node_id': 'expo1'}),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('ExposureCompleted', {
          'frame': 1,
          'total': 4,
          'duration_secs': 300.0,
        }),
      );
      await pumpEventQueue();

      final stats = container.read(liveSequenceStatsProvider)!;
      expect(
        stats.framesCaptured,
        1,
        reason:
            'a run with no save path emits no grader event at all; the frame '
            'still completed',
      );
      expect(stats.framesRejected, 0);
      expect(stats.integrationSecs, 300.0);
    });

    test('a rejection does not leak onto the next frame', () async {
      final (container, executor) = build(sequence: exposureSequence());

      executor.handleSequencerEventForTest(
        sequencerEvent('NodeStarted', {'node_id': 'expo1'}),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('FrameRejected', {
          ...frameData(frame: 1),
          'reason': 'clouds',
        }),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('ExposureCompleted', {
          'frame': 1,
          'total': 4,
          'duration_secs': 300.0,
        }),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('FrameAccepted', {
          ...frameData(frame: 2),
          'save_path': '/tmp/light_0002.fits',
        }),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('ExposureCompleted', {
          'frame': 2,
          'total': 4,
          'duration_secs': 300.0,
        }),
      );
      await pumpEventQueue();

      final stats = container.read(liveSequenceStatsProvider)!;
      expect(stats.framesCaptured, 2);
      expect(stats.framesRejected, 1);
    });
  });

  group('the run record counts dithers', () {
    test('a completed dither is counted', () async {
      final (container, executor) = build(sequence: exposureSequence());

      executor.handleSequencerEventForTest(
        event(backend_events.EventCategory.guiding, 'DitherCompleted', {}),
      );
      await pumpEventQueue();

      expect(
        container.read(liveSequenceStatsProvider)!.ditherCount,
        1,
        reason: 'the Session Report reads this figure',
      );
    });

    test('two dithers are counted twice', () async {
      final (container, executor) = build(sequence: exposureSequence());

      executor.handleSequencerEventForTest(
        event(backend_events.EventCategory.guiding, 'DitherCompleted', {}),
      );
      executor.handleSequencerEventForTest(
        event(backend_events.EventCategory.guiding, 'DitherCompleted', {}),
      );
      await pumpEventQueue();

      expect(container.read(liveSequenceStatsProvider)!.ditherCount, 2);
    });
  });

  group('one preview fetch per frame, stamped with the truth', () {
    test(
      'the imaging duplicate of ExposureCompleted fetches nothing',
      () async {
        final (_, executor) = build(sequence: exposureSequence());

        executor.handleSequencerEventForTest(
          event(backend_events.EventCategory.imaging, 'ExposureComplete', {
            'success': true,
          }),
        );
        await pumpEventQueue();

        verifyNever(() => backend.cameraGetLastImage(any()));
      },
    );

    test('a frame fetches the full image exactly once', () async {
      final (_, executor) = build(sequence: exposureSequence());

      executor.handleSequencerEventForTest(
        sequencerEvent('NodeStarted', {'node_id': 'expo1'}),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('FrameAccepted', {
          ...frameData(frame: 1),
          'save_path': '/tmp/light_0001.fits',
        }),
      );
      // Native emits BOTH for the same exposure.
      executor.handleSequencerEventForTest(
        event(backend_events.EventCategory.imaging, 'ExposureComplete', {
          'success': true,
        }),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('ExposureCompleted', {
          'frame': 1,
          'total': 4,
          'duration_secs': 300.0,
        }),
      );
      await pumpEventQueue();

      verify(() => backend.cameraGetLastImage(_cameraId)).called(1);
    });

    test('the published preview carries the frame it was taken with', () async {
      when(() => backend.cameraGetLastImage(any())).thenAnswer(
        (_) async => CapturedImageResult(
          width: 2,
          height: 2,
          displayData: List<int>.filled(2 * 2 * 4, 64),
          histogram: List<int>.filled(256, 1),
          stats: const ImageStatsResult(
            min: 0,
            max: 1,
            mean: 0.5,
            median: 0.5,
            stdDev: 0.1,
            starCount: 0,
          ),
          exposureTime: 300.0,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isColor: false,
        ),
      );
      final (container, executor) = build(sequence: exposureSequence());

      executor.handleSequencerEventForTest(
        sequencerEvent('NodeStarted', {'node_id': 'expo1'}),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('FrameAccepted', {
          ...frameData(frame: 1),
          'save_path': '/tmp/light_0001.fits',
        }),
      );
      executor.handleSequencerEventForTest(
        sequencerEvent('ExposureCompleted', {
          'frame': 1,
          'total': 4,
          'duration_secs': 300.0,
        }),
      );
      await pumpEventQueue();

      final settings = container.read(currentImageProvider)!.settings;
      expect(settings.exposureTime, 300.0);
      expect(settings.gain, 120, reason: 'gain 0 was a literal, not a reading');
      expect(settings.offset, 30);
      expect(settings.binningX, 2);
      expect(settings.binningY, 2);
    });
  });
}
