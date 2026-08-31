// The Analytics session dialog's ways into the Darkroom and Session Review.
//
// The dialog is where an operator looks at a night days later, which is exactly
// when "open this in the Darkroom" is worth having. Both controls share one
// host-only gate: the recipes, the linear masters, the full-resolution subs and
// their pixels all live on the imaging computer.
//
// The gate is the client ROLE. Asked as `backend is NetworkBackend` it was a
// CONNECTION fact, which reads false for the whole life of a `--remote-host`
// launch before its first handshake — and in that window the dialog kept its
// host-capable labels and "Review & Integrate" navigated onto the Session
// Review host-only wall instead of refusing. That case is the third test here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
import 'package:nightshade_app/utils/darkroom_navigation.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _PinnedBackend extends BackendNotifier {
  _PinnedBackend(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

class _TutorialsDisabledNotifier extends TutorialNotifier {
  _TutorialsDisabledNotifier() : super(_NoopTutorialProgressDao()) {
    // ignore: invalid_use_of_protected_member
    state = const TutorialProgress(tutorialsEnabled: false);
  }
}

class _NoopTutorialProgressDao implements TutorialProgressDao {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'NoopTutorialProgressDao.${invocation.memberName} called in test',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openDialog(
    WidgetTester tester, {
    required NightshadeBackend backend,
    bool launchedAsRemoteClient = false,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final session = ImagingSession(
      id: 5,
      name: 'Night A - M31',
      startTime: DateTime(2026, 7, 30),
      totalExposures: 12,
      successfulExposures: 12,
      failedExposures: 0,
      totalIntegrationSecs: 1440,
      autofocusCount: 0,
      status: 'completed',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith((ref) => _PinnedBackend(ref, backend)),
          remoteClientLaunchProvider.overrideWithValue(launchedAsRemoteClient),
          allSessionsProvider.overrideWith(
            (ref) => Stream<List<ImagingSession>>.value([session]),
          ),
          standaloneImagesProvider.overrideWith(
            (ref) => Stream<List<DbCapturedImage>>.value(const []),
          ),
          allDbImagesProvider.overrideWith(
            (ref) => Stream<List<DbCapturedImage>>.value(const []),
          ),
          dbSessionImagesProvider(
            5,
          ).overrideWith(
              (ref) => Stream<List<DbCapturedImage>>.value(const [])),
          tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
        ],
        child: const MaterialApp(
          home:
              Scaffold(body: AnalyticsScreen(initialTab: AnalyticsTab.history)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Night A - M31'));
    // pump, not pumpAndSettle: the thumbnail futures never go idle locally.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The accessible name the icon button publishes — its own node's name, not
  /// the tooltip's.
  String semanticLabelOf(WidgetTester tester, Finder button) => tester
      .widget<Icon>(find.descendant(of: button, matching: find.byType(Icon)))
      .semanticLabel!;

  testWidgets('the host dialog offers both actions, live', (tester) async {
    await openDialog(tester, backend: DisconnectedBackend());

    for (final entry in {
      'session_detail_darkroom': 'Refine in Darkroom',
      'session_detail_review': 'Review & Integrate',
    }.entries) {
      final button = find.byKey(ValueKey(entry.key));
      expect(button, findsOneWidget);
      expect(tester.widget<IconButton>(button).tooltip, entry.value);
      expect(semanticLabelOf(tester, button), entry.value);
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    }
  });

  testWidgets('a connected remote client is refused on both controls',
      (tester) async {
    await openDialog(tester, backend: _MockNetworkBackend());

    final darkroom = find.byKey(const ValueKey('session_detail_darkroom'));
    expect(semanticLabelOf(tester, darkroom), 'Refine on imaging host');
    expect(
      tester.widget<IconButton>(darkroom).tooltip,
      kDarkroomHostOnlyRefusal,
      reason: 'the reason is on the control, readable before the press',
    );
    expect(tester.widget<IconButton>(darkroom).onPressed, isNull);

    final review = find.byKey(const ValueKey('session_detail_review'));
    expect(semanticLabelOf(tester, review), 'Review on imaging host');
    expect(tester.widget<IconButton>(review).onPressed, isNull);
  });

  testWidgets(
      'a client that has not reached its rig is refused too, and Review does '
      'not navigate', (tester) async {
    // The pre-handshake window: launched with `--remote-host`, backend still
    // Disconnected. `backend is NetworkBackend` reads FALSE here, which is
    // exactly why the question has to be the role.
    await openDialog(
      tester,
      backend: DisconnectedBackend(),
      launchedAsRemoteClient: true,
    );

    final darkroom = find.byKey(const ValueKey('session_detail_darkroom'));
    expect(semanticLabelOf(tester, darkroom), 'Refine on imaging host');
    expect(tester.widget<IconButton>(darkroom).onPressed, isNull);

    final review = find.byKey(const ValueKey('session_detail_review'));
    expect(semanticLabelOf(tester, review), 'Review on imaging host');
    expect(
      tester.widget<IconButton>(review).onPressed,
      isNull,
      reason: 'pressing it popped the dialog and landed on the Session Review '
          'host-only wall',
    );

    await tester.tap(review, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('session_detail_review')),
      findsOneWidget,
      reason: 'a disabled action leaves the dialog up rather than navigating',
    );
  });
}
