// Settings → Location must not claim things it did not do.
//
// Three live-observed defects are pinned here:
//   1. "Sync from Server" reported a green "Location synced from server" on a
//      standalone desktop, where the read went to this app's own settings
//      store and nothing was fetched from anywhere.
//   2. "Use Device Location / Get location from GPS" ran a third-party IP
//      lookup with no consent and wrote the new coordinates while passing the
//      OLD elevation through, producing a Pennsylvania site at 1234 m.
//   3. The Timezone picker offered 18 IANA names; `clockProvider` parses only
//      `UTC`/`UTC±HH:MM`, so 17 of them silently fell back to the system
//      clock and the picker changed nothing at all.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/widgets/location_settings.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

class _StubAppSettingsNotifier extends AppSettingsNotifier {
  _StubAppSettingsNotifier(this.initial);

  final AppSettingsState initial;

  @override
  Future<AppSettingsState> build() async => initial;
}

Future<HarnessHandle> _pumpLocation(
  WidgetTester tester, {
  required AppSettingsState settings,
  bool isRemote = false,
  DeviceLocationFetcher? fetcher,
}) async {
  final handle = await pumpAppScreen(
    tester,
    const LocationSettingsPage(),
    size: const Size(1280, 1400),
    extraOverrides: [
      appSettingsProvider
          .overrideWith(() => _StubAppSettingsNotifier(settings)),
      isRemoteModeProvider.overrideWithValue(isRemote),
      if (fetcher != null)
        deviceLocationFetcherProvider.overrideWithValue(fetcher),
    ],
  );
  await tester.pumpAndSettle();
  return handle;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sync from Server', () {
    testWidgets('is not offered on a standalone (local) session', (
      tester,
    ) async {
      await _pumpLocation(tester, settings: const AppSettingsState());
      expect(find.text('Sync from Server'), findsNothing);
    });

    testWidgets('is offered when a host is actually connected', (tester) async {
      await _pumpLocation(
        tester,
        settings: const AppSettingsState(),
        isRemote: true,
      );
      expect(find.text('Sync from Server'), findsOneWidget);
    });
  });

  group('Detect Location', () {
    const seattle = AppSettingsState(
      latitude: 47.6062,
      longitude: -122.3321,
      elevation: 1234,
    );

    testWidgets('is not labelled GPS', (tester) async {
      await _pumpLocation(tester, settings: seattle);
      expect(find.text('Get location from GPS'), findsNothing);
      expect(find.text('Detect Location'), findsOneWidget);
    });

    testWidgets('asks before anything leaves the machine', (tester) async {
      var calls = 0;
      await _pumpLocation(
        tester,
        settings: seattle,
        fetcher: () async {
          calls++;
          return (39.9817, -75.4072, 'Newtown Square, Pennsylvania');
        },
      );

      await tester.tap(find.byIcon(LucideIcons.crosshair));
      await tester.pumpAndSettle();

      expect(find.text('Detect this site’s location?'), findsOneWidget);
      expect(calls, 0, reason: 'the lookup ran before the user consented');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });

    testWidgets('a fix at another site clears the inherited elevation', (
      tester,
    ) async {
      final handle = await _pumpLocation(
        tester,
        settings: seattle,
        fetcher: () async =>
            (39.9817, -75.4072, 'Newtown Square, Pennsylvania'),
      );

      await tester.tap(find.byIcon(LucideIcons.crosshair));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detect location'));
      await tester.pumpAndSettle();

      final settings = handle.container.read(appSettingsProvider).requireValue;
      expect(settings.latitude, closeTo(39.9817, 1e-6));
      // 1234 m came from Seattle; Pennsylvania's highest point is 979 m.
      expect(settings.elevation, 0);
      expect(
        find.textContaining('Elevation cleared to 0 m'),
        findsOneWidget,
      );
    });

    testWidgets('a fix at the same site keeps the elevation', (tester) async {
      final handle = await _pumpLocation(
        tester,
        settings: seattle,
        // ~2 km from the stored position: the same observing site.
        fetcher: () async => (47.6242, -122.3321, 'Seattle, Washington'),
      );

      await tester.tap(find.byIcon(LucideIcons.crosshair));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detect location'));
      await tester.pumpAndSettle();

      expect(
        handle.container.read(appSettingsProvider).requireValue.elevation,
        1234,
      );
      expect(find.textContaining('Elevation kept at 1234 m'), findsOneWidget);
    });
  });

  group('Timezone', () {
    testWidgets('every offered value actually drives the clock', (
      tester,
    ) async {
      final handle = await _pumpLocation(
        tester,
        settings: const AppSettingsState(useSystemTime: false),
      );
      final container = handle.container;
      final notifier = container.read(appSettingsProvider.notifier);

      // Read the options off the rendered picker, not off the constant, so
      // re-populating the dropdown with labels the clock cannot parse fails
      // here rather than passing against a list nothing displays.
      final picker = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>).last,
      );
      final offered = [for (final item in picker.items!) item.value!];
      expect(offered, isNotEmpty);

      final inert = <String>[];
      for (final item in offered) {
        await notifier.setTimezone(item);
        await tester.pump();
        if (container.read(clockProvider) is! FixedOffsetClock) {
          inert.add(item);
        }
      }
      expect(
        inert,
        isEmpty,
        reason: 'these picker entries fall back to the system clock, so '
            'choosing them changes nothing: $inert',
      );
    });

    testWidgets('choosing an offset in the UI shifts the app clock', (
      tester,
    ) async {
      final handle = await _pumpLocation(
        tester,
        settings: const AppSettingsState(useSystemTime: false),
      );

      // The Timezone row owns the last dropdown on the page (Bortle owns the
      // first). Driving the real control is the point: it proves the value the
      // picker emits is one the clock can honour.
      final picker = find.byType(DropdownButton<String>).last;
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();

      final option = find.text('UTC+05:30').last;
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();

      final clock = handle.container.read(clockProvider);
      expect(clock, isA<FixedOffsetClock>());
      expect(
        (clock as FixedOffsetClock).utcOffset,
        const Duration(hours: 5, minutes: 30),
      );
      expect(
        handle.container.read(appSettingsProvider).requireValue.timezone,
        'UTC+05:30',
      );
    });

    testWidgets('a stored IANA label is migrated so the choice takes effect', (
      tester,
    ) async {
      final handle = await _pumpLocation(
        tester,
        settings: const AppSettingsState(
          timezone: 'Asia/Tokyo',
          useSystemTime: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        handle.container.read(appSettingsProvider).requireValue.timezone,
        'UTC+09:00',
      );
      final clock = handle.container.read(clockProvider);
      expect(clock, isA<FixedOffsetClock>());
      expect((clock as FixedOffsetClock).utcOffset, const Duration(hours: 9));
    });

    testWidgets('the row reports the clock the app is really running on', (
      tester,
    ) async {
      await _pumpLocation(
        tester,
        settings: const AppSettingsState(
          timezone: 'UTC+05:00',
          useSystemTime: false,
        ),
      );

      final expected = DateTime.now().toUtc().add(const Duration(hours: 5));
      final hhmm = '${expected.hour.toString().padLeft(2, '0')}:'
          '${expected.minute.toString().padLeft(2, '0')}';
      expect(
        find.textContaining('UTC+05:00 — now $hhmm'),
        findsOneWidget,
        reason: 'the Timezone row must show the time the chosen offset '
            'produces, not the host time',
      );
    });

    testWidgets('with system time on, the row says the picker is ignored', (
      tester,
    ) async {
      await _pumpLocation(tester, settings: const AppSettingsState());
      expect(
        find.textContaining('Ignored while "Use system time" is on'),
        findsOneWidget,
      );
    });
  });
}
