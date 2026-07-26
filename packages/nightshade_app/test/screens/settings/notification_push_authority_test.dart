import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/settings/widgets/notification_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/mock_database.dart';
import '../../harness/pump_app_screen.dart';

class _LoadedAppSettings extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async => const AppSettingsState();
}

int _pushLoadAttempts = 0;

class _FailingPushConfig extends PushNotificationConfigNotifier {
  @override
  Future<PushNotificationConfig> build() async {
    _pushLoadAttempts++;
    throw StateError('push config unavailable');
  }
}

class _MockNetworkBackend extends Mock implements NetworkBackend {}

int _unexpectedRemotePushLoads = 0;

class _CountingPushConfig extends PushNotificationConfigNotifier {
  @override
  Future<PushNotificationConfig> build() async {
    _unexpectedRemotePushLoads++;
    return const PushNotificationConfig();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('push outage isolates its controls and exposes retry',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final database = mockDatabase();
    addTearDown(database.close);
    _pushLoadAttempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appSettingsProvider.overrideWith(_LoadedAppSettings.new),
          pushNotificationConfigProvider.overrideWith(
            _FailingPushConfig.new,
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: NotificationSettings()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Could not load push configuration'), findsOneWidget);
    expect(
      find.textContaining('Bad state: push config unavailable'),
      findsOneWidget,
    );
    expect(find.text('Enable push to mobile'), findsNothing);
    expect(find.text('Enable notifications'), findsOneWidget);
    expect(find.text('Webhook URL'), findsOneWidget);
    expect(_pushLoadAttempts, 1);

    await tester.tap(find.widgetWithText(NightshadeButton, 'Retry').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_pushLoadAttempts, 2);
    expect(find.text('Enable push to mobile'), findsNothing);
  });

  testWidgets('remote controller never edits a local push/routing copy',
      (tester) async {
    final remote = _MockNetworkBackend();
    when(() => remote.eventStream).thenAnswer((_) => const Stream.empty());
    _unexpectedRemotePushLoads = 0;

    await pumpAppScreen(
      tester,
      const SingleChildScrollView(child: NotificationSettings()),
      settle: false,
      extraOverrides: [
        backendProvider.overrideWith(
          (ref) => TestBackendNotifier(ref, remote),
        ),
        appSettingsProvider.overrideWith(_LoadedAppSettings.new),
        pushNotificationConfigProvider.overrideWith(_CountingPushConfig.new),
        remoteHomeAssistantHostSettingsProvider.overrideWith(
          (ref) async => null,
        ),
      ],
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Configure push on the Nightshade host'), findsOneWidget);
    expect(
      find.text('Configure routing on the Nightshade host'),
      findsOneWidget,
    );
    expect(find.text('Enable push to mobile'), findsNothing);
    expect(find.text('Notification routing enabled'), findsNothing);
    expect(_unexpectedRemotePushLoads, 0);
  });
}
