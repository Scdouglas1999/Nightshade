import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/settings/widgets/dark_library_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _SwappableBackendNotifier extends BackendNotifier {
  _SwappableBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }

  void switchTo(NightshadeBackend backend) => state = backend;
}

void _stubHost(_MockNetworkBackend backend) {
  when(() => backend.listDarks()).thenAnswer(
    (_) async => const <RemoteDarkLibraryEntry>[],
  );
  when(() => backend.getDarkLibrarySettings()).thenAnswer(
    (_) async => {'autoCalibrate': true, 'temperatureTolerance': 1.0},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('clear dialog cannot mutate a rig selected after it opened',
      (tester) async {
    final hostA = _MockNetworkBackend();
    final hostB = _MockNetworkBackend();
    _stubHost(hostA);
    _stubHost(hostB);
    late _SwappableBackendNotifier notifier;

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith((ref) {
            notifier = _SwappableBackendNotifier(ref, hostA);
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: DarkLibrarySettings(isMobile: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final clearLibrary = find.widgetWithText(NightshadeButton, 'Clear Library');
    await tester.ensureVisible(clearLibrary);
    await tester.pump();
    await tester.tap(clearLibrary);
    await tester.pump();
    expect(find.text('Clear Dark Library'), findsOneWidget);

    notifier.switchTo(hostB);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pump();
    await tester.pump();

    verifyNever(() => hostA.clearDarkLibrary(deleteFiles: false));
    verifyNever(() => hostB.clearDarkLibrary(deleteFiles: false));
    expect(
      find.text('Connected rig changed; dark-library action cancelled'),
      findsOneWidget,
    );
    expect(find.text('Clear Dark Library'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
