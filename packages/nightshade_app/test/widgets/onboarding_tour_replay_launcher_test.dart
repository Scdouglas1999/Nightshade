// Widget tests for [OnboardingTourReplayLauncher] (Onboarding & First-Light
// IA, C13). The first-launch tour is replay-only: Settings → Help & Tutorials
// → "Re-run onboarding tour" resets the persisted status to pending, and this
// launcher is the consumer that watches that status and re-mounts the overlay.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/onboarding/onboarding_overlay.dart';
import 'package:nightshade_app/widgets/onboarding_tour_replay_launcher.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_core/src/providers/tutorial_provider.dart';

Future<void> _pump(
  WidgetTester tester, {
  required AsyncValue<FirstLaunchTourStatus> status,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  // The OnboardingOverlay (mounted in the pending case) builds the tour
  // notifier, which reaches the tutorial-progress DAO → database. Back it with
  // an in-memory Drift DB so that path is real, not mocked.
  final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // Override the resolved status directly so the launcher's gate can be
        // exercised deterministically.
        firstLaunchTourStatusProvider.overrideWith(
          (ref) => switch (status) {
            AsyncData(:final value) => Future<FirstLaunchTourStatus>.value(value),
            AsyncError(:final error) =>
              Future<FirstLaunchTourStatus>.error(error),
            _ => Completer<FirstLaunchTourStatus>().future, // loading
          },
        ),
      ],
      child: const MaterialApp(
        home: OnboardingTourReplayLauncher(
          child: Scaffold(body: Text('APP-CONTENT')),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mounts the onboarding overlay when status is pending',
      (tester) async {
    await _pump(
      tester,
      status: const AsyncData(FirstLaunchTourStatus.pending),
    );

    expect(find.text('APP-CONTENT'), findsOneWidget);
    expect(find.byType(OnboardingOverlay), findsOneWidget);
    // The welcome step's headline confirms the tour actually rendered.
    expect(find.text('Welcome to Nightshade'), findsOneWidget);
  });

  testWidgets('does not mount the overlay when the tour is completed',
      (tester) async {
    await _pump(
      tester,
      status: const AsyncData(FirstLaunchTourStatus.completed),
    );

    expect(find.text('APP-CONTENT'), findsOneWidget);
    expect(find.byType(OnboardingOverlay), findsNothing);
  });

  testWidgets('does not mount the overlay when the tour was skipped',
      (tester) async {
    await _pump(
      tester,
      status: const AsyncData(FirstLaunchTourStatus.skipped),
    );

    expect(find.byType(OnboardingOverlay), findsNothing);
  });

  testWidgets('fails closed (no overlay) while the status is loading',
      (tester) async {
    await _pump(
      tester,
      status: const AsyncLoading(),
    );

    expect(find.text('APP-CONTENT'), findsOneWidget);
    expect(find.byType(OnboardingOverlay), findsNothing);
  });

  testWidgets('fails closed (no overlay) on a status read error',
      (tester) async {
    await _pump(
      tester,
      status: AsyncError(StateError('db read failed'), StackTrace.empty),
    );

    expect(find.text('APP-CONTENT'), findsOneWidget);
    expect(find.byType(OnboardingOverlay), findsNothing);
  });
}
