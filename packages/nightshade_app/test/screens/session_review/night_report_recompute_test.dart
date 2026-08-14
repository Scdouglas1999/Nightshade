// WF-SCI-N2: the Night Doctor verdict was computed once per session and never
// again.
//
// Live evidence, on the build that had already FIXED the detector: Session
// Review for the Aug 13 session read 100 / 100, "A clean night — no problems
// detected", Excellent, 0 findings — over four subs the same app grades POOR.
// Refresh (top right) produced an identical screen, and `select * from
// night_reports` still held exactly one row, created_at Aug 13 20:54:26, i.e.
// written by the PRE-fix build. A brand-new run analysed by the new code
// scored 70 / "Rough night: every sub was graded poor", so the detector worked
// and the cache was what was stale. The same trap catches any night whose
// report is computed on first view, before grading has finished.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/session_review/session_review_controller.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart';

import '../../harness/mock_database.dart';

const _staleHeadline = 'A clean night — no problems detected (stale)';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late ProviderContainer container;
  late int sessionId;
  final capturedAt = DateTime(2026, 8, 13, 20, 53);

  setUp(() async {
    db = mockDatabase();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    sessionId = await container.read(sessionsDaoProvider).createSession(
          ImagingSessionsCompanion.insert(startTime: capturedAt),
        );
    final images = container.read(imagesDaoProvider);
    for (var i = 0; i < 4; i++) {
      await images.createImage(
        CapturedImagesCompanion.insert(
          filePath: '/subs/s$i.fits',
          fileName: 's$i.fits',
          sessionId: Value(sessionId),
          exposureDuration: 60,
          frameType: const Value('light'),
          hfr: Value(9.0 + i),
          isAccepted: const Value(true),
          capturedAt: capturedAt.add(Duration(minutes: i)),
        ),
      );
    }
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> seedStoredReport(DateTime createdAt) {
    return container.read(nightReportsDaoProvider).insertReport(
          sessionId: sessionId,
          score: 100,
          headline: _staleHeadline,
          createdAt: createdAt,
        );
  }

  SessionReviewController controller() => container.read(
        sessionReviewControllerProvider(SessionReviewScope.session(sessionId))
            .notifier,
      );

  SessionReviewState state() => container.read(
        sessionReviewControllerProvider(SessionReviewScope.session(sessionId)),
      );

  Future<void> waitUntilLoaded() async {
    for (var i = 0;
        i < 100 && (state().loading || state().loadingSmartData);
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('Refresh recomputes the verdict instead of re-reading it', () async {
    // Written after the last sub, so the staleness rule alone would keep it.
    await seedStoredReport(capturedAt.add(const Duration(hours: 1)));

    controller();
    await waitUntilLoaded();
    expect(
      state().nightReport?.headline,
      _staleHeadline,
      reason: 'a report that post-dates every sub is reused, by design',
    );

    await controller().refresh();
    await waitUntilLoaded();

    expect(
      state().nightReport?.headline,
      isNot(_staleHeadline),
      reason: 'Refresh is the operator saying "this verdict is wrong"',
    );
  });

  test('a report older than the frames it judges is recomputed on sight',
      () async {
    // The counter-input to the fix above: nobody thinks to press Refresh. A
    // report written before the run finished cannot have seen these subs.
    await seedStoredReport(capturedAt.subtract(const Duration(minutes: 1)));

    controller();
    await waitUntilLoaded();

    expect(
      state().nightReport?.headline,
      isNot(_staleHeadline),
      reason: 'it was written before three of the four subs existed',
    );
  });
}
