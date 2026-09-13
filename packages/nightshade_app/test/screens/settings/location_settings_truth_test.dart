// Settings → Location must not claim things it did not do.
//
// Three claims are pinned here:
//   1. "Sync from server" must not report a green "Location synced from server"
//      on a standalone desktop, where the read goes to this app's own settings
//      store and nothing is fetched from anywhere.
//   2. "Detect location" must ask before a lookup that can send the machine's
//      public IP to a third party, must say which path answered (device GPS
//      vs internet) and how precise it claims to be, and must not pass the
//      OLD elevation through with new coordinates — that yields a site that
//      does not exist.
//   3. The Timezone picker must only offer values `clockProvider` can parse
//      (`UTC` / `UTC±HH:MM`); anything else silently falls back to the system
//      clock and the picker changes nothing at all.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/widgets/location_settings.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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
  PlaceSearcher? searcher,
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
      if (searcher != null) placeSearchProvider.overrideWithValue(searcher),
    ],
  );
  await tester.pumpAndSettle();
  return handle;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sync from server', () {
    testWidgets('is not offered on a standalone (local) session', (
      tester,
    ) async {
      await _pumpLocation(tester, settings: const AppSettingsState());
      expect(find.text('Sync from server'), findsNothing);
    });

    testWidgets('is offered when a host is actually connected', (tester) async {
      await _pumpLocation(
        tester,
        settings: const AppSettingsState(),
        isRemote: true,
      );
      expect(find.text('Sync from server'), findsOneWidget);
    });
  });

  group('Detect location', () {
    const seattle = AppSettingsState(
      latitude: 47.6062,
      longitude: -122.3321,
      elevation: 1234,
    );

    testWidgets('is not labelled GPS', (tester) async {
      await _pumpLocation(tester, settings: seattle);
      expect(find.text('Get location from GPS'), findsNothing);
      expect(find.text('Detect location'), findsOneWidget);
    });

    testWidgets('asks before anything leaves the machine', (tester) async {
      var calls = 0;
      await _pumpLocation(
        tester,
        settings: seattle,
        fetcher: () async {
          calls++;
          return const GeolocationFix(
            latitude: 39.9817,
            longitude: -75.4072,
            locationName: 'Newtown Square, Pennsylvania',
            source: GeolocationSource.internet,
            providerHost: 'ipinfo.io',
          );
        },
      );

      await tester.tap(find.byIcon(LucideIcons.crosshair));
      await tester.pumpAndSettle();

      expect(find.text('Detect this site’s location?'), findsOneWidget);
      // The dialog has to say what leaves the machine: the public IP to the
      // named services over HTTPS.
      expect(find.textContaining('ipinfo.io'), findsOneWidget);
      expect(find.textContaining('public IP'), findsOneWidget);
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
        fetcher: () async => const GeolocationFix(
          latitude: 39.9817,
          longitude: -75.4072,
          locationName: 'Newtown Square, Pennsylvania',
          source: GeolocationSource.internet,
          providerHost: 'ipinfo.io',
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.crosshair));
      await tester.pumpAndSettle();
      // The consent dialog's confirm button, not the row that opened it:
      // both read 'Detect location' now that the row title is sentence case.
      await tester.tap(
        find.widgetWithText(NightshadeButton, 'Detect location'),
      );
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
        fetcher: () async => const GeolocationFix(
          latitude: 47.6242,
          longitude: -122.3321,
          locationName: 'Seattle, Washington',
          source: GeolocationSource.device,
          accuracyMeters: 18,
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.crosshair));
      await tester.pumpAndSettle();
      // The consent dialog's confirm button, not the row that opened it:
      // both read 'Detect location' now that the row title is sentence case.
      await tester.tap(
        find.widgetWithText(NightshadeButton, 'Detect location'),
      );
      await tester.pumpAndSettle();

      expect(
        handle.container.read(appSettingsProvider).requireValue.elevation,
        1234,
      );
      expect(find.textContaining('Elevation kept at 1234 m'), findsOneWidget);
    });

    // On a desktop with no GPS receiver the same click lands the internet
    // fix — and has to say so, because a ~10 km guess is not a fix.
    testWidgets('an internet fix is written and named as approximate', (
      tester,
    ) async {
      final handle = await _pumpLocation(
        tester,
        settings: seattle,
        fetcher: () async => const GeolocationFix(
          latitude: 39.9817,
          longitude: -75.4072,
          locationName: 'Newtown Square, Pennsylvania',
          source: GeolocationSource.internet,
          providerHost: 'ipinfo.io',
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.crosshair));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(NightshadeButton, 'Detect location'),
      );
      await tester.pumpAndSettle();

      expect(
        handle.container.read(appSettingsProvider).requireValue.latitude,
        closeTo(39.9817, 1e-6),
      );
      expect(
        find.textContaining(
          'approximate: from your internet connection (ipinfo.io)',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Refine with Search place or the map if it is off'),
        findsOneWidget,
      );
    });

    testWidgets('a device fix is named with its metres and no refine nudge', (
      tester,
    ) async {
      await _pumpLocation(
        tester,
        settings: seattle,
        fetcher: () async => const GeolocationFix(
          latitude: 47.6242,
          longitude: -122.3321,
          locationName: 'GPS: 47.6242, -122.3321',
          source: GeolocationSource.device,
          accuracyMeters: 18,
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.crosshair));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(NightshadeButton, 'Detect location'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('GPS fix, ±18 m'), findsOneWidget);
      // The subtitle names the internet path too, so the snackbar-only
      // phrases are what distinguish the confirmation.
      expect(find.textContaining('approximate:'), findsNothing);
      expect(find.textContaining('Refine with Search place'), findsNothing);
    });

    testWidgets('the row no longer steers desktops away from Detect', (
      tester,
    ) async {
      await _pumpLocation(tester, settings: seattle);
      expect(
        find.textContaining('internet connection'),
        findsOneWidget,
        reason: 'the subtitle must say the click works without a GPS',
      );
      expect(
        find.textContaining('search for a place by name instead'),
        findsNothing,
      );
    });
  });

  group('Search place', () {
    testWidgets('choosing a hit writes the town and its elevation', (
      tester,
    ) async {
      final handle = await _pumpLocation(
        tester,
        settings: const AppSettingsState(elevation: 1234),
        searcher: (query) async {
          expect(query, 'Newtown Square');
          return const [
            PlaceSearchHit(
              latitude: 39.9868,
              longitude: -75.4010,
              elevation: 127,
              label: 'Newtown Square, Pennsylvania, United States',
            ),
          ];
        },
      );

      await tester.enterText(
        find.byType(NightshadeTextField).first,
        'Newtown Square',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(
        find.textContaining('Newtown Square, Pennsylvania, United States'),
      );
      await tester.pumpAndSettle();

      final settings = handle.container.read(appSettingsProvider).requireValue;
      expect(settings.latitude, closeTo(39.9868, 1e-6));
      expect(settings.longitude, closeTo(-75.4010, 1e-6));
      expect(settings.elevation, 127);
      expect(
        find.textContaining('Elevation 127 m'),
        findsOneWidget,
      );
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
      final picker = tester.widget<NightshadeDropdown>(
        find.byType(NightshadeDropdown).last,
      );
      final offered = picker.items;
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
      final picker = find.byType(NightshadeDropdown).last;
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

      // The row rendered a moment before this line runs; if the wall clock
      // ticked over a minute in between, the rendered time is one minute
      // behind the one computed here. Accept either — the row's claim is
      // about the offset, not sub-minute freshness.
      final after = DateTime.now().toUtc().add(const Duration(hours: 5));
      final candidates = [after, after.subtract(const Duration(minutes: 1))]
          .map(
            (t) => '${t.hour.toString().padLeft(2, '0')}:'
                '${t.minute.toString().padLeft(2, '0')}',
          )
          .toSet();
      expect(
        candidates.any(
          (hhmm) => find
              .textContaining('UTC+05:00 — now $hhmm')
              .evaluate()
              .isNotEmpty,
        ),
        isTrue,
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
