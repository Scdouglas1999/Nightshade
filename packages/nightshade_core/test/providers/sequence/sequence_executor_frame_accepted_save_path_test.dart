// Wave 6 Pack P — verify the SequenceExecutor's FrameAccepted handling
// now consumes the `save_path` field that the Rust grader emits on
// accepted frames.
//
// Before Pack P, `_registerSequenceFrame` left `file_path` blank for
// accepted frames (the Rust grader did not ship the path on the
// FrameAccepted event). The thumbnail strip showed a colour-bordered
// placeholder tile.
//
// After Pack P, accepted frames carry the on-disk save path via the
// `save_path` field on `SequencerEvent::FrameAccepted` → `event.data`,
// and the inserted `captured_images` row's `file_path` column holds it.
// The thumbnail strip then renders the inline preview the same way it
// does for rejected frames via the existing `reject_path` flow.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart'
    as bridge_event;

import '../../mocks/mock_backend.dart';

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

void main() {
  setUpAll(() {
    registerMocktailFallbackValues();
  });

  late MockBackend backend;
  late StreamController<bridge_event.NightshadeEvent> eventController;
  late NightshadeDatabase db;
  late ImagesDao imagesDao;

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backendProvider.overrideWith(
          (ref) => _TestBackendNotifier(ref, backend),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    backend = MockBackend();
    eventController =
        StreamController<bridge_event.NightshadeEvent>.broadcast();
    when(() => backend.eventStream).thenAnswer((_) => eventController.stream);
    when(
      () => backend.polarAlignmentEvents,
    ).thenAnswer((_) => const Stream.empty());
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    imagesDao = ImagesDao(db);
  });

  tearDown(() async {
    await eventController.close();
    await db.close();
  });

  test(
    'FrameAccepted with save_path inserts captured_images row with file_path',
    () async {
      final container = buildContainer();
      final executor = container.read(sequenceExecutorProvider);

      const savePath = '/captures/m31/L_0001.fits';

      // Pump the event through the same handler the live native event
      // subscription uses. We don't need to spin up the Rust backend
      // because the FrameAccepted path is entirely Dart-side once the
      // event lands in `_handleSequencerEvent`.
      executor.handleSequencerEventForTest(
        bridge_event.NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: bridge_event.EventSeverity.info,
          category: bridge_event.EventCategory.sequencer,
          eventType: 'FrameAccepted',
          data: const {
            'node_id': 'exposure-node-1',
            'frame': 1,
            'total': 10,
            'hfr': 2.35,
            'eccentricity': 0.25,
            'star_count': 145,
            'accepted_total': 1,
            'rejected_total': 0,
            // The new save_path field introduced by Pack P.
            'save_path': savePath,
          },
        ),
      );

      // Let the fire-and-forget `unawaited(insertSequenceFrame(...))`
      // complete.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final rows = await imagesDao.getImagesByProducingNode(
          producingNodeId: 'exposure-node-1',
        );
        if (rows.isNotEmpty) {
          // Assert the row was tagged correctly and the path landed.
          expect(rows, hasLength(1));
          final row = rows.single;
          expect(
            row.filePath,
            equals(savePath),
            reason:
                'accepted frame must persist save_path → file_path; the thumbnail strip relies on this for the inline preview',
          );
          expect(row.fileName, equals('L_0001.fits'));
          expect(row.isAccepted, isTrue);
          expect(row.runtimeGrade, equals('pass'));
          expect(row.hfr, closeTo(2.35, 1e-9));
          expect(row.starCount, equals(145));
          expect(row.producingNodeId, equals('exposure-node-1'));
          return;
        }
      }
      fail('captured_images row for accepted frame was never written');
    },
  );

  test(
    'FrameAccepted without save_path falls back to empty file_path (legacy)',
    () async {
      final container = buildContainer();
      final executor = container.read(sequenceExecutorProvider);

      executor.handleSequencerEventForTest(
        bridge_event.NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: bridge_event.EventSeverity.info,
          category: bridge_event.EventCategory.sequencer,
          eventType: 'FrameAccepted',
          data: const {
            'node_id': 'exposure-node-legacy',
            'frame': 1,
            'total': 1,
            'accepted_total': 1,
            'rejected_total': 0,
            // No save_path: simulates a back-compat emit site.
          },
        ),
      );

      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final rows = await imagesDao.getImagesByProducingNode(
          producingNodeId: 'exposure-node-legacy',
        );
        if (rows.isNotEmpty) {
          final row = rows.single;
          expect(
            row.filePath,
            isEmpty,
            reason:
                'legacy emit without save_path must still insert the row '
                '(with an empty file_path) so the strip can show its '
                'colour-bordered placeholder tile rather than skipping',
          );
          expect(row.isAccepted, isTrue);
          return;
        }
      }
      fail('captured_images row for legacy accepted frame was never written');
    },
  );
}
