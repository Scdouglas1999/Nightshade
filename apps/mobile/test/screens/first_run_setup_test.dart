// Tests for the first-run setup detection.
//
// The wizard itself shells into widgets that depend on network calls
// against a live NetworkBackend; full-stack rendering is exercised by
// the dashboard widget test. Here we lock down the two pieces of
// detection logic that govern *whether* the wizard runs:
//
//   1. [FirstRunSetupNeeds.hasAnyMissing] — pure boolean.
//   2. [MobilePreferences.firstRunCompleted] — persisted latch.
//
// Coverage for both is enough to guarantee the gate flips correctly;
// the wizard UI itself is covered by a smoke render test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_mobile/screens/setup/first_run_setup_screen.dart';
import 'package:nightshade_mobile/services/mobile_preferences.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirstRunSetupNeeds.hasAnyMissing', () {
    test('returns false when nothing is missing', () {
      const needs = FirstRunSetupNeeds(
        missingImageOutputPath: false,
        missingProfiles: false,
        missingCatalogs: false,
      );
      expect(needs.hasAnyMissing, isFalse);
    });

    test('returns true when image output path is missing', () {
      const needs = FirstRunSetupNeeds(
        missingImageOutputPath: true,
        missingProfiles: false,
        missingCatalogs: false,
      );
      expect(needs.hasAnyMissing, isTrue);
    });

    test('returns true when profiles are missing', () {
      const needs = FirstRunSetupNeeds(
        missingImageOutputPath: false,
        missingProfiles: true,
        missingCatalogs: false,
      );
      expect(needs.hasAnyMissing, isTrue);
    });

    test('returns true when catalogs are missing', () {
      const needs = FirstRunSetupNeeds(
        missingImageOutputPath: false,
        missingProfiles: false,
        missingCatalogs: true,
      );
      expect(needs.hasAnyMissing, isTrue);
    });

    test('none sentinel is fully populated', () {
      expect(FirstRunSetupNeeds.none.hasAnyMissing, isFalse);
      expect(FirstRunSetupNeeds.none.missingImageOutputPath, isFalse);
      expect(FirstRunSetupNeeds.none.missingProfiles, isFalse);
      expect(FirstRunSetupNeeds.none.missingCatalogs, isFalse);
    });
  });

  group('MobilePreferences.firstRunCompleted', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults to false on a fresh install', () async {
      final prefs = MobilePreferences(await SharedPreferences.getInstance());
      expect(prefs.firstRunCompleted, isFalse);
    });

    test('setter persists the latch', () async {
      final prefs = MobilePreferences(await SharedPreferences.getInstance());
      await prefs.setFirstRunCompleted(true);

      // A fresh wrapper over the same SharedPreferences singleton must
      // observe the persisted value. We re-read SharedPreferences.getInstance
      // (which returns the same instance) and rebuild the MobilePreferences
      // wrapper to simulate a process restart.
      final reread = MobilePreferences(await SharedPreferences.getInstance());
      expect(reread.firstRunCompleted, isTrue);
    });

    test('setter can revert the latch', () async {
      final prefs = MobilePreferences(await SharedPreferences.getInstance());
      await prefs.setFirstRunCompleted(true);
      await prefs.setFirstRunCompleted(false);
      expect(prefs.firstRunCompleted, isFalse);
    });
  });

  group('FirstRunSetupScreen smoke render', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('renders the three setup steps without crashing', (
      tester,
    ) async {
      // We render the screen with a non-NetworkBackend so it never tries
      // to make HTTP calls; the wizard still has to render its Stepper
      // shell and the three step headers.
      var onCompletedFired = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(extensions: const [NightshadeColors.dark]),
            home: FirstRunSetupScreen(
              needs: const FirstRunSetupNeeds(
                missingImageOutputPath: true,
                missingProfiles: true,
                missingCatalogs: true,
              ),
              onCompleted: () => onCompletedFired = true,
            ),
          ),
        ),
      );
      await tester.pump();

      // The Stepper renders all three step titles regardless of which
      // step is active.
      expect(find.text('Image output path'), findsOneWidget);
      expect(find.text('Catalogs'), findsOneWidget);
      expect(find.text('Equipment profile'), findsOneWidget);

      // AppBar Skip button is visible. The Stepper's "Skip and continue"
      // label on the catalogs step also contains the word, but it is not
      // rendered on the active step on first build (active step is 0),
      // so an exact match against 'Skip' is unambiguous.
      expect(find.widgetWithText(TextButton, 'Skip'), findsOneWidget);
      // Wizard hasn't completed yet.
      expect(onCompletedFired, isFalse);
    });
  });
}
