// Observing-site step.
//
// After "Use my current location" fills the coordinate fields in, the banner
// directly above them must not still read "No site on record yet" and offer
// "Estimate from IP" — the screen denying what it has just done. An offer
// latched once at seed time and never re-derived does exactly that. The same
// detection must not write 39.9527237 / -75.1635262 into the fields either:
// seven decimals, about a centimetre, for a lookup the app's own consent dialog
// calls accurate to roughly 10 km.
//
// And the consent dialog must not render ~680 px tall for two short paragraphs,
// its body floating between ~230 px of empty space above and ~225 px below.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/steps/site_step.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The fix a desktop with no GPS receiver lands: the internet lookup's answer
/// to seven raw decimals, tagged with the host that supplied it.
const _philadelphia = GeolocationFix(
  latitude: 39.9527237,
  longitude: -75.1635262,
  source: GeolocationSource.internet,
  providerHost: 'ipinfo.io',
);

/// The fix a machine that does have a receiver lands: same button, the
/// device path, with the platform's metres attached.
const _deviceFix = GeolocationFix(
  latitude: 39.9527237,
  longitude: -75.1635262,
  locationName: 'GPS: 39.9527, -75.1635',
  source: GeolocationSource.device,
  accuracyMeters: 14,
);

Future<ProviderContainer> _pumpSiteStep(
  WidgetTester tester,
  NightshadeDatabase db, {
  DeviceLocationLookup? deviceLocation,
}) async {
  late ProviderContainer container;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        onboardingApproximateLocationProvider
            .overrideWithValue(() async => null),
        onboardingDeviceLocationProvider
            .overrideWithValue(deviceLocation ?? () async => null),
      ],
      child: Consumer(builder: (ctx, ref, _) {
        container = ProviderScope.containerOf(ctx);
        return MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(24),
              child: OnboardingSiteStep(),
            ),
          ),
        );
      }),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  testWidgets('the "no site on record" offer retires once a site is detected',
      (tester) async {
    final container = await _pumpSiteStep(
      tester,
      db,
      deviceLocation: () async => _philadelphia,
    );

    expect(find.textContaining('No site on record yet'), findsOneWidget);

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detect location'));
    await tester.pumpAndSettle();

    expect(container.read(appSettingsProvider).valueOrNull?.latitude, 39.9527);
    expect(find.textContaining('No site on record yet'), findsNothing);
    expect(find.text('Estimate from IP'), findsNothing);
  });

  testWidgets('a detected coordinate is not printed to seven decimals',
      (tester) async {
    await _pumpSiteStep(
      tester,
      db,
      deviceLocation: () async => _philadelphia,
    );

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detect location'));
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.first.controller?.text, '39.9527');
    expect(
      fields.elementAt(1).controller?.text,
      '-75.1635',
      reason: 'an estimate good to ~10 km must not claim centimetres',
    );
  });

  testWidgets('the consent dialog is sized to its two paragraphs',
      (tester) async {
    await _pumpSiteStep(tester, db);
    // A tall window is where the stretch showed: the dialog took 85% of it
    // whatever the body needed.
    tester.view.physicalSize = const Size(1280, 1000);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    // AlertDialog's own box is the full-screen Align that centres the surface,
    // so the panel the operator sees is the Material inside it. What the
    // finding is about is the dead space around the body, not the body's own
    // height: the prose was floated in the middle of a card stretched to 85%
    // of the viewport, leaving ~230 px empty above it and ~225 px below.
    final surface = tester.getRect(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first,
    );
    final body = tester.getRect(
      find.textContaining('Nightshade asks this device'),
    );

    expect(
      body.top - surface.top,
      lessThan(130),
      reason: 'only the title belongs between the card edge and the body',
    );
    expect(
      surface.bottom - body.bottom,
      lessThan(160),
      reason: 'only the action row belongs below the body',
    );
  });

  // The consent dialog must say what leaves the machine — the public IP to
  // the named services — because on a desktop that request is what Detect
  // actually does.
  testWidgets('the consent dialog names the IP lookup', (tester) async {
    await _pumpSiteStep(tester, db);

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    // The banner's "public IP" offer text is also on screen, so assert the
    // sentence only the dialog carries.
    expect(
      find.textContaining('sends an HTTPS request to a third-party '
          'geolocation service (ipinfo.io'),
      findsOneWidget,
    );
    expect(find.textContaining('ipwho.is'), findsOneWidget);
  });

  // A desktop with no GPS still lands a site in one click — and the
  // confirmation names the internet path, because a ~10 km estimate is not
  // the same answer a receiver gives.
  testWidgets('an internet fix is written and named as approximate',
      (tester) async {
    final container = await _pumpSiteStep(
      tester,
      db,
      deviceLocation: () async => _philadelphia,
    );

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detect location'));
    await tester.pumpAndSettle();

    expect(
      container.read(appSettingsProvider).valueOrNull?.latitude,
      39.9527,
    );
    expect(
      find.textContaining('approximate: from your internet connection'),
      findsOneWidget,
    );
    expect(find.textContaining('ipinfo.io'), findsOneWidget);
  });

  testWidgets('a device fix names the device path and its metres',
      (tester) async {
    final container = await _pumpSiteStep(
      tester,
      db,
      deviceLocation: () async => _deviceFix,
    );

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detect location'));
    await tester.pumpAndSettle();

    expect(
      container.read(appSettingsProvider).valueOrNull?.latitude,
      39.9527,
    );
    expect(find.textContaining('GPS fix, ±14 m'), findsOneWidget);
    expect(find.textContaining('approximate:'), findsNothing);
  });
}
