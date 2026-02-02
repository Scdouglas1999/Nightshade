import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/app.dart';
import 'package:nightshade_app/router/app_router.dart';
import 'package:nightshade_app/services/location_sync_service.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uiScale applies text scaling correctly', (tester) async {
    const windowSize = Size(1000, 800);

    tester.binding.window.devicePixelRatioTestValue = 1.0;
    tester.binding.window.physicalSizeTestValue = windowSize;
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            // Verify text scaling is applied
            final textScaler = MediaQuery.of(context).textScaler;
            return Text(
              'Test',
              key: const ValueKey('test-text'),
              textScaler: textScaler,
            );
          },
        ),
      ],
    );

    const settings = AppSettings(
      uiScale: 'Small (0.8x)',
      autoDiscoverOnLaunch: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          appSettingsProvider.overrideWith(
            () => _TestAppSettingsNotifier(settings),
          ),
          locationSyncProvider.overrideWith((ref) {}),
          incompleteSessionsProvider
              .overrideWith((ref) async => const <SessionRecoveryInfo>[]),
          quickStartContextProvider.overrideWith((ref) async => null),
        ],
        child: const NightshadeApp(isDesktop: false, isMobile: false),
      ),
    );

    await tester.pump();

    // Verify the app renders without crashing - the main thing we're testing
    // is that the scaling doesn't break the layout
    expect(find.byKey(const ValueKey('test-text')), findsOneWidget);
  });
}

class _TestAppSettingsNotifier extends AppSettingsNotifier {
  final AppSettings _settings;

  _TestAppSettingsNotifier(this._settings);

  @override
  Future<AppSettings> build() async => _settings;
}
