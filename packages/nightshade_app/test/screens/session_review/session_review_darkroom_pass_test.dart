// A Darkroom pass that ended badly has to be visible on the session it ran on.
//
// The dawn pass runs while nobody is at the machine, so its ending lives only
// on its `darkroom_jobs` row: the toast that reports a pass belongs to the
// button that started one, and nothing started this one. A pass that failed at
// 05:40 therefore left Session Review showing the night's verdict, the masters
// and a clean-night score with no sign that the drafting, the night report and
// the delivery for it had not happened — the operator's first clue was a
// destination that never received the night.
//
// What these pin: a failed pass and a stopped pass are stated on the session
// they belong to, with the row's own sentence; a pass that ran to the end says
// nothing extra, because its drafts ARE the report.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/session_review/narrative_view.dart';
import 'package:nightshade_app/screens/session_review/session_review_controller.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/mock_database.dart';
import 'seeded_review_fixture.dart';

class _MockJobs extends Mock implements DarkroomJobsDao {}

DarkroomJob _job(
  DarkroomJobState state, {
  String? errorText,
  String? note,
}) =>
    DarkroomJob(
      id: 42,
      sessionId: 1,
      kind: DarkroomJobKind.dawn,
      state: state,
      progress: 0.9,
      note: note,
      errorText: errorText,
      attempts: 1,
      createdAt: DateTime.utc(2026, 8, 16),
      startedAt: DateTime.utc(2026, 8, 16),
      finishedAt: DateTime.utc(2026, 8, 16, 5, 40),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late String previewPath;
  late _MockJobs jobs;

  setUp(() async {
    db = mockDatabase();
    previewPath = await _writeSamplePng();
    jobs = _MockJobs();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpNarrative(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const scope = SessionReviewScope.session(1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          darkroomJobsDaoProvider.overrideWithValue(jobs),
          ...seededReviewOverrides(
            db: db,
            scope: scope,
            previewPath: previewPath,
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          debugShowCheckedModeBanner: false,
          home: const Scaffold(body: NarrativeView(scope: scope)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  final banner =
      find.byKey(const ValueKey('session_review_darkroom_pass_banner'));

  testWidgets('a failed dawn pass is stated on the session it ran on', (
    tester,
  ) async {
    when(() => jobs.listForSession(1)).thenAnswer(
      (_) async => [
        _job(
          DarkroomJobState.failed,
          errorText: 'The dawn job failed while delivering the night: the '
              'Darkroom output directory could not be created.',
          note: 'delivering the night',
        ),
      ],
    );

    await pumpNarrative(tester);

    expect(banner, findsOneWidget);
    final message = tester.widget<NightshadeInlineBanner>(banner).message;
    expect(message, contains('The Darkroom pass for this night failed.'));
    expect(message, contains('could not be created'));
    expect(message, contains('delivering the night'));
    expect(message, contains('Process now'));
  });

  testWidgets('a stopped pass is stated as stopped, not as a failure', (
    tester,
  ) async {
    when(() => jobs.listForSession(1)).thenAnswer(
      (_) async => [
        _job(
          DarkroomJobState.cancelled,
          errorText: 'Stopped on request during delivery; 12 files are still '
              'owed and the retry sweep resumes them.',
        ),
      ],
    );

    await pumpNarrative(tester);

    final widget = tester.widget<NightshadeInlineBanner>(banner);
    expect(widget.severity, NightshadeAlertSeverity.warning);
    expect(widget.message, contains('was stopped'));
    expect(widget.message, contains('12 files are still owed'));
  });

  testWidgets(
      'a note that is already a sentence is not wrapped in the stage '
      'frame', (tester) async {
    // The open-time recovery writes a finished sentence into the same column
    // the executor writes a stage name into. Framed as a stage this rendered
    // "It was Stopped at the retry limit; this job is not re-queued. when it
    // stopped." — a full stop mid-clause and a dangling tail.
    when(() => jobs.listForSession(1)).thenAnswer(
      (_) async => [
        _job(
          DarkroomJobState.failed,
          errorText: 'Interrupted by a process exit on attempt 3; the limit '
              'is 3 starts, so it is not retried.',
          note: 'Stopped at the retry limit; this job is not re-queued.',
        ),
      ],
    );

    await pumpNarrative(tester);

    final message = tester.widget<NightshadeInlineBanner>(banner).message;
    expect(message, isNot(contains('It was Stopped')));
    expect(message, isNot(contains('re-queued. when it stopped')));
    expect(
      message,
      contains(
        'so it is not retried. Stopped at the retry limit; this job is not '
        're-queued. The subs',
      ),
    );
  });

  testWidgets('a stage fragment still reads as one clause', (tester) async {
    when(() => jobs.listForSession(1)).thenAnswer(
      (_) async => [
        _job(
          DarkroomJobState.failed,
          errorText: 'the render engine stopped answering',
          note: 'Drafting Master · B',
        ),
      ],
    );

    await pumpNarrative(tester);

    final message = tester.widget<NightshadeInlineBanner>(banner).message;
    expect(message, contains('It was Drafting Master · B when it stopped.'));
  });

  testWidgets('a pass that ran to the end adds nothing', (tester) async {
    when(() => jobs.listForSession(1))
        .thenAnswer((_) async => [_job(DarkroomJobState.done)]);

    await pumpNarrative(tester);

    expect(banner, findsNothing);
  });

  testWidgets('a session with no pass adds nothing', (tester) async {
    when(() => jobs.listForSession(1)).thenAnswer((_) async => []);

    await pumpNarrative(tester);

    expect(banner, findsNothing);
  });

  testWidgets('the newest pass is the one reported', (tester) async {
    when(() => jobs.listForSession(1)).thenAnswer(
      // `listForSession` orders newest first, which is the order this reads.
      (_) async => [
        DarkroomJob(
          id: 43,
          sessionId: 1,
          kind: DarkroomJobKind.manual,
          state: DarkroomJobState.done,
          progress: 1.0,
          attempts: 1,
          createdAt: DateTime.utc(2026, 8, 16, 6),
        ),
        _job(DarkroomJobState.failed, errorText: 'the older attempt failed'),
      ],
    );

    await pumpNarrative(tester);

    expect(
      banner,
      findsNothing,
      reason: 'the re-run is the operator\'s answer to the failure, and it '
          'succeeded',
    );
  });
}

/// A tiny on-disk PNG for the seeded hero to load.
Future<String> _writeSamplePng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFF223344),
  );
  final image = await recorder.endRecording().toImage(8, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = await Directory.systemTemp.createTemp('ns_review_pass_');
  final file = File('${dir.path}/preview.png');
  await file.writeAsBytes(Uint8List.view(data!.buffer));
  return file.path;
}
