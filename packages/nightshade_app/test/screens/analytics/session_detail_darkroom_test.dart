// The Analytics session dialog's way into the Darkroom.
//
// The dialog is where an operator looks at a night days later, which is exactly
// when "open this in the Darkroom" is worth having. The control sits beside the
// Session Review one and shares its host-only gate: the recipes, the linear
// masters and their pixels all live on the imaging computer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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

  testWidgets('the host dialog offers "Refine in Darkroom"', (tester) async {
    await openDialog(tester, backend: DisconnectedBackend());

    final button = find.byKey(const ValueKey('session_detail_darkroom'));
    expect(button, findsOneWidget);
    expect(
      tester.widget<IconButton>(button).tooltip,
      'Refine in Darkroom',
    );
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
  });

  testWidgets('a remote client is pointed at the imaging host', (tester) async {
    await openDialog(tester, backend: _MockNetworkBackend());

    final button = find.byKey(const ValueKey('session_detail_darkroom'));
    expect(button, findsOneWidget);
    expect(
      tester.widget<IconButton>(button).tooltip,
      'Refine on imaging host',
      reason: 'the control stays pressable so the tap can explain itself',
    );
  });
}
