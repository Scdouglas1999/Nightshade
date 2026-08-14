// WF-SCI-N1: after a run completed, Analytics ▸ Session kept reviewing the
// PREVIOUS night.
//
// Live evidence: two completed runs on disk (Aug 13 20:53, Aug 14 00:20). The
// Session tab opened on the older one — "Reviewing New Sequence · Aug 13, 2026
// 20:53 · 4 frames" — with the newer run one row up in its own dropdown.
// Picking the newer night worked and then reverted after navigating away and
// back (three times). Stopping and restarting the app opened the SAME screen on
// the newer night, which is the signature of a cached answer rather than a
// wrong query: `latestScienceSessionProvider` was a plain FutureProvider,
// computed on first read and never invalidated again for the life of the
// process.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/analytics/widgets/science_analytics_tab.dart'
    show latestScienceSessionProvider;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart';

import '../../harness/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = mockDatabase();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> seedNight(DateTime at) async {
    final sessions = container.read(sessionsDaoProvider);
    final images = container.read(imagesDaoProvider);
    final id = await sessions.createSession(
      ImagingSessionsCompanion.insert(startTime: at),
    );
    await images.createImage(
      CapturedImagesCompanion.insert(
        filePath: '/subs/${at.millisecondsSinceEpoch}.fits',
        fileName: '${at.millisecondsSinceEpoch}.fits',
        sessionId: Value(id),
        exposureDuration: 60,
        frameType: const Value('light'),
        capturedAt: at,
      ),
    );
    return id;
  }

  test('a finished run becomes the session the tab opens on', () async {
    final first = await seedNight(DateTime(2026, 8, 13, 20, 53));

    expect(await container.read(latestScienceSessionProvider.future), first);

    // A second night runs while the app stays open. The run's completion is
    // what writes the session row's end time — the moment the answer changes.
    final second = await seedNight(DateTime(2026, 8, 14, 0, 20));
    await container.read(sessionsDaoProvider).endSession(second);

    // Let the session stream deliver the write.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      await container.read(latestScienceSessionProvider.future),
      second,
      reason: 'the tab followed the previous night until the app restarted',
    );
  });
}
