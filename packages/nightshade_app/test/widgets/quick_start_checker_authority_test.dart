import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/router/app_router.dart';
import 'package:nightshade_app/widgets/quick_start_checker.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _RecordingNetworkBackend extends Mock implements NetworkBackend {
  int discardCalls = 0;

  @override
  Future<void> discardCheckpoint() async {
    discardCalls++;
  }
}

class _SwappableBackendNotifier extends BackendNotifier {
  _SwappableBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }

  void switchTo(NightshadeBackend backend) => state = backend;
}

QuickStartContext _context({EquipmentSnapshot? equipmentSnapshot}) =>
    QuickStartContext(
      sessionId: 7,
      sessionName: 'Host A night',
      targetName: 'M31',
      sequenceName: 'M31 sequence',
      completedFrames: 12,
      totalFrames: 20,
      lastSessionDate: DateTime.now().subtract(const Duration(minutes: 10)),
      equipmentSnapshot: equipmentSnapshot,
      totalIntegrationHours: 1.2,
      canResumeFromCheckpoint: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('production outer-wrapper topology can show quick start',
      (tester) async {
    final backend = _RecordingNetworkBackend();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          backendProvider.overrideWith(
            (ref) => _SwappableBackendNotifier(ref, backend),
          ),
          incompleteSessionsProvider.overrideWith(
            (ref) async => const <SessionRecoveryInfo>[],
          ),
          quickStartContextProvider.overrideWith((ref) async => _context()),
        ],
        child: QuickStartChecker(
          child: MaterialApp.router(
            theme: NightshadeTheme.dark,
            routerConfig: router,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Start Fresh'), findsOneWidget);
  });

  testWidgets('quick-start dialog closes and cannot discard after host switch',
      (tester) async {
    final hostA = _RecordingNetworkBackend();
    final hostB = _RecordingNetworkBackend();
    late _SwappableBackendNotifier notifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith((ref) {
            notifier = _SwappableBackendNotifier(ref, hostA);
            return notifier;
          }),
          incompleteSessionsProvider.overrideWith(
            (ref) async => const <SessionRecoveryInfo>[],
          ),
          quickStartContextProvider.overrideWith((ref) async {
            final backend = ref.watch(backendProvider);
            return identical(backend, hostA) ? _context() : null;
          }),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const QuickStartChecker(
            child: Scaffold(body: Text('Dashboard')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Start Fresh'), findsOneWidget);

    notifier.switchTo(hostB);
    await tester.tap(find.text('Start Fresh'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Start Fresh'), findsNothing);
    expect(hostA.discardCalls, 0);
    expect(hostB.discardCalls, 0);
  });

  testWidgets('start fresh warns when saved device positions are skipped', (
    tester,
  ) async {
    final backend = _RecordingNetworkBackend();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _SwappableBackendNotifier(ref, backend),
          ),
          incompleteSessionsProvider.overrideWith(
            (ref) async => const <SessionRecoveryInfo>[],
          ),
          quickStartContextProvider.overrideWith(
            (ref) async => _context(
              equipmentSnapshot: EquipmentSnapshot(
                filterPosition: 2,
                focuserPosition: 12000,
                capturedAt: DateTime(2026),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const QuickStartChecker(
            child: Scaffold(body: Text('Dashboard')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Start Fresh'));
    await tester.tap(find.text('Start Fresh'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'could not restore: filter wheel (not connected), '
        'focuser (not connected)',
      ),
      findsOneWidget,
    );
    expect(backend.discardCalls, 1);
  });
}
