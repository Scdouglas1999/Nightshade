import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/daos/narrator_events_dao.dart';
import 'package:nightshade_core/src/services/science/narrator/narrator_service.dart';

/// The sessionless (hand-driven) narrator path.
///
/// An adversarial verifier found the ticker had been pointed at the sessionless
/// feed while nothing wrote to it: `_bindStreams` returns as soon as
/// `_sessionId == null`, and `_onImagesChanged` — the only producer of
/// `_imageStats` — hangs off `sessionImagesStreamProvider`, which is only bound
/// below that return. An operator shooting by hand for an hour saw an empty
/// strip, which was the original complaint, one layer down.
///
/// These tests pin the producer, not the widget: if `_ingestSessionlessStats`
/// stops being called, or goes back to only stashing `_pendingFwhm`, the
/// context loses its samples and the first three go red.
/// The service takes a `Ref`, so it has to be built inside the container.
final _sessionlessServiceProvider = Provider<NarratorService>(
  (ref) => NarratorService(ref, sessionId: null),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  }

  Future<NarratorService> startSessionless(ProviderContainer container) async {
    final service = container.read(_sessionlessServiceProvider);
    await service.start();
    await Future<void>.delayed(Duration.zero);
    return service;
  }

  test('a hand-driven frame reaches the narrator context', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final service = await startSessionless(container);
    addTearDown(service.dispose);

    container.read(lastImageStatsProvider.notifier).state = const ImageStats(
      hfr: 3.4,
      fwhm: 4.1,
      starCount: 812,
    );
    await Future<void>.delayed(Duration.zero);

    final stats = service.buildContextForTest().imageStats;
    expect(stats, hasLength(1));
    expect(stats.single.hfr, 3.4);
    expect(stats.single.fwhm, 4.1);
    expect(stats.single.starCount, 812);
    // No captured_images row exists on this path, and inventing an id would let
    // a detector believe it can look the frame up.
    expect(stats.single.capturedImageId, isNull);
  });

  test('successive frames accumulate', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final service = await startSessionless(container);
    addTearDown(service.dispose);

    final notifier = container.read(lastImageStatsProvider.notifier);
    for (var i = 0; i < 4; i++) {
      notifier.state = ImageStats(hfr: 3.0 + i * 0.1, starCount: 700 + i);
      await Future<void>.delayed(Duration.zero);
    }

    final stats = service.buildContextForTest().imageStats;
    expect(stats, hasLength(4));
    expect(stats.last.starCount, 703);
  });

  test('re-emitting the same object does not double-count the frame', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final service = await startSessionless(container);
    addTearDown(service.dispose);

    const frame = ImageStats(hfr: 3.4, starCount: 812);
    final notifier = container.read(lastImageStatsProvider.notifier);
    notifier.state = frame;
    await Future<void>.delayed(Duration.zero);
    // A different object carrying identical numbers is a genuinely new frame —
    // two consecutive subs of the same target can measure the same. Only
    // identity means "this is the emission I already ingested".
    notifier.state = frame;
    await Future<void>.delayed(Duration.zero);

    expect(service.buildContextForTest().imageStats, hasLength(1));
  });

  test('a frame that measured nothing is not pushed', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final service = await startSessionless(container);
    addTearDown(service.dispose);

    // Star detection found nothing usable: an all-null sample would pad the
    // queue and let a detector average over holes.
    container.read(lastImageStatsProvider.notifier).state = const ImageStats(
      median: 1200,
      mean: 1210,
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.buildContextForTest().imageStats, isEmpty);
  });

  group('sessionless dedupe is bounded by a window', () {
    Future<void> insertEvent(DateTime when, String key) async {
      await db
          .into(db.narratorEvents)
          .insert(
            NarratorEventsCompanion.insert(
              timestamp: Value(when),
              eventType: 'conditions.excellent',
              category: 'conditions',
              severity: 'info',
              headline: 'Conditions are excellent',
              dedupeKey: key,
            ),
          );
    }

    test('last night no longer silences tonight', () async {
      final dao = NarratorEventsDao(db);
      await insertEvent(
        DateTime.now().subtract(const Duration(days: 3)),
        'conditions.excellent',
      );

      // Without the window this is `sessionId IS NULL` with no time bound, so a
      // static-key detector fires once per install and is mute for ever after.
      expect(await dao.hasDedupeKey(null, 'conditions.excellent'), isFalse);
      expect(await dao.dedupeKeysForSession(null), isEmpty);
    });

    test('but the same night still does', () async {
      final dao = NarratorEventsDao(db);
      await insertEvent(
        DateTime.now().subtract(const Duration(hours: 2)),
        'conditions.excellent',
      );

      expect(await dao.hasDedupeKey(null, 'conditions.excellent'), isTrue);
      expect(
        await dao.dedupeKeysForSession(null),
        contains('conditions.excellent'),
      );
    });
  });
}
