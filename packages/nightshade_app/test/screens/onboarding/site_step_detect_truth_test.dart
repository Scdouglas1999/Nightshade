// SET-8/SET-9, observing-site step.
//
// SET-9: after "Use my current location" filled the coordinate fields in, the
// banner directly above them still read "No site on record yet" and still
// offered "Estimate from IP" — the screen denying the thing it had just done.
// The offer was latched once at seed time and never re-derived. The same
// detection also wrote 39.9527237 / -75.1635262 into the fields: seven
// decimals, about a centimetre, for a lookup the app's own consent dialog
// calls accurate to roughly 10 km.
//
// SET-8: the consent dialog rendered ~680 px tall for two short paragraphs,
// its body floating between ~230 px of empty space above and ~225 px below.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/steps/site_step.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

const _philadelphia = (39.9527237, -75.1635262, null);

Future<ProviderContainer> _pumpSiteStep(
  WidgetTester tester,
  NightshadeDatabase db, {
  ApproximateLocationLookup? deviceLocation,
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
      lessThan(130),
      reason: 'only the action row belongs below the body',
    );
  });
}
