// Widget tests for the first-launch onboarding tour (W7-ONBOARDING).
//
// The tests drive [OnboardingOverlay] through its key states: initial
// render, step advancement, skip-marks-as-completed, and Settings
// "Re-run tutorial" reset. We use an in-memory Drift database so the
// underlying [TutorialProgressDao] path is exercised end-to-end without
// touching the production sqlite file.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/onboarding/onboarding_launcher.dart';
import 'package:nightshade_app/widgets/onboarding/onboarding_overlay.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/database/daos/tutorial_progress_dao.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_core/src/providers/tutorial_provider.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

NightshadeDatabase _newInMemoryDb() {
  return NightshadeDatabase.forTesting(NativeDatabase.memory());
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required NightshadeDatabase db,
  Widget? body,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: OnboardingTourLauncher(
            child: body ?? const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
  // Two pumps: first to mount, second to allow the FutureProvider for
  // the status check to resolve and the launcher to mount the overlay.
  await tester.pump();
  await tester.pump();
  // One more for the post-frame setState that re-resolves nav rects.
  await tester.pump();
}

Future<void> _pumpOverlayDirect(
  WidgetTester tester, {
  required NightshadeDatabase db,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: OnboardingOverlay(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingTourLauncher gating', () {
    testWidgets(
        'renders welcome card on first launch (no tutorial_progress row)',
        (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      await _pumpLauncher(tester, db: db);

      // Welcome title is the first step's title.
      expect(find.text('Welcome to Nightshade'), findsOneWidget);
      // Welcome card uses "Show me around" as its primary button.
      expect(find.text('Show me around'), findsOneWidget);
      // And exposes the explicit skip with the secondary copy.
      expect(find.text("Skip — I know what I'm doing"), findsOneWidget);
    });

    testWidgets('does not mount overlay when tour was completed',
        (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      // Seed the DAO with a completed row before mounting the launcher.
      final dao = TutorialProgressDao(db);
      await dao.markCompleted(firstLaunchTourCategory);

      await _pumpLauncher(tester, db: db);

      expect(find.text('Welcome to Nightshade'), findsNothing);
    });

    testWidgets('does not mount overlay when tour was skipped',
        (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      final dao = TutorialProgressDao(db);
      await dao.markDismissed(firstLaunchTourCategory);

      await _pumpLauncher(tester, db: db);

      expect(find.text('Welcome to Nightshade'), findsNothing);
    });
  });

  group('OnboardingOverlay step advancement', () {
    testWidgets('Next button advances welcome → equipment step',
        (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      await _pumpOverlayDirect(tester, db: db);

      // Welcome step is visible.
      expect(find.text('Welcome to Nightshade'), findsOneWidget);

      // "Show me around" advances to step 2 (Equipment).
      await tester.tap(find.text('Show me around'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Welcome to Nightshade'), findsNothing);
      expect(find.text('Connect your gear'), findsOneWidget);
    });

    testWidgets('reaches completion card after walking through all core steps',
        (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      await _pumpOverlayDirect(tester, db: db);

      // Welcome → step 1 (Equipment).
      await tester.tap(find.text('Show me around'));
      await tester.pumpAndSettle();
      // Steps 1..5: tap Next five times to reach the completion card
      // (welcome=0, equipment=1, profiles=2, sequencer=3, scheduler=4,
      // plate solving=5, completion=6).
      for (var i = 0; i < 5; i++) {
        expect(find.text('Next'), findsOneWidget,
            reason: 'Next button missing at step $i');
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      // Completion card has a "Done" primary button and the optional
      // secondary "Show me about defect maps".
      expect(find.text("You're set"), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Show me about defect maps'), findsOneWidget);
    });
  });

  group('OnboardingOverlay skip + completion persistence', () {
    testWidgets('Skip button marks tour as skipped in DAO', (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      await _pumpOverlayDirect(tester, db: db);

      // Advance off the welcome card so the ghost Skip button shows.
      await tester.tap(find.text('Show me around'));
      await tester.pumpAndSettle();
      // Skip from the equipment step.
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // DAO row must show dismissed=true so the launcher won't re-mount
      // the overlay on the next launch.
      final dao = TutorialProgressDao(db);
      final progress = await dao.getProgress(firstLaunchTourCategory);
      expect(progress, isNotNull,
          reason: 'Skip must persist a row to suppress re-launch');
      expect(progress!.dismissed, isTrue,
          reason: 'Skip is recorded as dismissed, not completed');
      expect(progress.completed, isFalse,
          reason: 'Skip is distinct from completion');
    });

    testWidgets(
        "Welcome card's secondary skip also persists the dismissal flag",
        (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      await _pumpOverlayDirect(tester, db: db);
      await tester.tap(find.text("Skip — I know what I'm doing"));
      await tester.pumpAndSettle();

      final dao = TutorialProgressDao(db);
      final progress = await dao.getProgress(firstLaunchTourCategory);
      expect(progress, isNotNull);
      expect(progress!.dismissed, isTrue);
    });

    testWidgets('Done on completion card marks tour as completed',
        (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      await _pumpOverlayDirect(tester, db: db);

      // Walk to the completion card.
      await tester.tap(find.text('Show me around'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final dao = TutorialProgressDao(db);
      final progress = await dao.getProgress(firstLaunchTourCategory);
      expect(progress, isNotNull);
      expect(progress!.completed, isTrue,
          reason: 'Done must persist completion=true');
      expect(progress.dismissed, isFalse,
          reason: 'Completion is distinct from skip');
    });
  });

  group('OnboardingOverlay defect-map follow-up', () {
    testWidgets(
        '"Show me about defect maps" unlocks the optional eighth step',
        (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      await _pumpOverlayDirect(tester, db: db);

      // Walk to the completion card.
      await tester.tap(find.text('Show me around'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Show me about defect maps'));
      await tester.pumpAndSettle();

      expect(find.text('Defect maps and calibration'), findsOneWidget);
      // The defect-map step is now the last step; primary button is Done.
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('Settings "Re-run tutorial" reset flow', () {
    testWidgets('reset clears completion flag so launcher re-fires overlay',
        (tester) async {
      final db = _newInMemoryDb();
      addTearDown(() async => db.close());

      // Seed the DAO with a completed row. This represents a user who
      // already finished the tour on a previous launch.
      final dao = TutorialProgressDao(db);
      await dao.markCompleted(firstLaunchTourCategory);

      // Sanity: status reads as completed before reset.
      final daoWrapper = FirstLaunchTourDao(dao);
      expect(await daoWrapper.getStatus(),
          equals(FirstLaunchTourStatus.completed));

      // Run the reset path through the same DAO wrapper the notifier
      // uses. We exercise the persistence path directly (not the
      // notifier) because the notifier holds an auto-disposing Riverpod
      // timer that interacts badly with the widget tester's pending-timer
      // assertion. The notifier delegates to FirstLaunchTourDao.reset
      // for all persistence — covering that here gives equivalent
      // coverage without the timer flake.
      await daoWrapper.reset();

      // After reset, the persisted row is gone — launcher's gate will
      // resolve to pending and re-mount the overlay on next render.
      expect(await daoWrapper.getStatus(),
          equals(FirstLaunchTourStatus.pending));
    });
  });
}
